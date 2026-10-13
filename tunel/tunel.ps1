# tunel - expoe portas locais em subdominios HTTPS usando o Pangolin (Windows).
# Rode "tunel --help" para ver como usar. Credenciais em tunel.config.json (mesma pasta).
#
# Como funciona: uma unica conexao do Pangolin (processo em segundo plano, gerenciado por um
# "supervisor") atende todos os tuneis deste PC. Cada terminal com "tunel" aberto adiciona seus
# tuneis ao blueprint; o Pangolin recarrega o arquivo sozinho. Ao sair (Ctrl+C ou fechando a
# janela) os tuneis daquele terminal sao desativados (enabled: false). Sem tuneis ativos, o
# supervisor encerra o Pangolin depois de ~30s.

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$StateDir    = Join-Path $env:LOCALAPPDATA "tunel"
$StateFile   = Join-Path $StateDir "tunnels.json"
$Blueprint   = Join-Path $StateDir "blueprint.yaml"
$SupPidFile  = Join-Path $StateDir "supervisor.pid"
$PanPidFile  = Join-Path $StateDir "pangolin.pid"
$HealthFile  = Join-Path $StateDir "healthy"
$LogFile     = Join-Path $StateDir "pangolin.log"
$ErrLogFile  = Join-Path $StateDir "pangolin.err.log"
New-Item -ItemType Directory -Force $StateDir | Out-Null

# ---------------------------------------------------------------- ajuda

function Show-Example {
  Write-Host ""
  Write-Host "  Uso: tunel <porta> [nome]" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  Exemplo:"
  Write-Host "    tunel 8001 meuapp      ->  https://meuapp.$((Get-Config).domain)  ->  localhost:8001" -ForegroundColor Green
  Write-Host ""
  Write-Host "  Mais opcoes: tunel --help"
  Write-Host ""
}

function Show-Help {
  $dom = (Get-Config).domain
  Write-Host @"

  tunel - expoe portas locais em https://<nome>.$dom

  USO
    tunel <porta> [nome]             Abre um tunel. Sem nome, usa p<porta>.
    tunel <porta:nome> [...]         Varios tuneis no mesmo comando.
    tunel list                       Mostra a conexao e os tuneis ativos.
    tunel stop                       Encerra TODOS os tuneis e a conexao.
    tunel --help                     Esta ajuda.

  OPCOES
    -DryRun                          So mostra o blueprint, nao abre nada.

  EXEMPLOS
    tunel 8001 meuapp                https://meuapp.$dom  -> localhost:8001
    tunel 8001                       https://p8001.$dom   -> localhost:8001
    tunel 8001:api 5173:front        dois tuneis no mesmo terminal

  VARIOS TUNEIS
    Pode abrir "tunel" em quantos terminais quiser: todos usam a mesma conexao
    do Pangolin. A primeira chamada conecta; as seguintes so adicionam o tunel.
    Ctrl+C (ou fechar o terminal) desativa os tuneis daquele terminal.

  VERIFICACOES
    - Porta ou nome ja em uso por outro tunel ativo: recusa.
    - Nada escutando na porta local: avisa (o link dara 502 ate o app subir).
    - Pangolin rodando fora do "tunel" (manual ou servico): recusa, com instrucoes.

  ARQUIVOS
    Config:  $(Join-Path $PSScriptRoot "tunel.config.json")
    Estado:  $StateDir

"@
}

# ---------------------------------------------------------------- utilitarios

function Get-Config {
  $p = Join-Path $PSScriptRoot "tunel.config.json"
  if (-not (Test-Path $p)) { throw "Nao achei $p" }
  return Get-Content $p -Raw | ConvertFrom-Json
}

function Test-Alive([int]$procId) {
  if ($procId -le 0) { return $false }
  return [bool](Get-Process -Id $procId -ErrorAction SilentlyContinue)
}

function Read-PidFile([string]$path) {
  if (-not (Test-Path $path)) { return 0 }
  $v = (Get-Content $path -Raw -ErrorAction SilentlyContinue)
  if ($v -match '^\s*(\d+)\s*$') { return [int]$Matches[1] }
  return 0
}

function Test-Supervisor { return Test-Alive (Read-PidFile $SupPidFile) }

function Invoke-Locked([scriptblock]$Body) {
  $m = New-Object Threading.Mutex($false, "Local\tunel-state")
  $got = $false
  try {
    try { $got = $m.WaitOne(15000) } catch [Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) { throw "Timeout esperando o lock do estado do tunel." }
    & $Body
  } finally {
    if ($got) { $m.ReleaseMutex() }
    $m.Dispose()
  }
}

function Read-State {
  if (-not (Test-Path $StateFile)) { return @() }
  $raw = Get-Content $StateFile -Raw
  if (-not $raw.Trim()) { return @() }
  return @((ConvertFrom-Json $raw).tunnels | Where-Object { $_ })
}

# Grava via arquivo temporario; tenta de novo se outro processo estiver lendo o destino.
function Write-FileAtomic([string]$path, [string]$content) {
  $tmp = "$path.tmp"
  [IO.File]::WriteAllText($tmp, $content)
  for ($i = 0; $i -lt 20; $i++) {
    try { Move-Item -Force $tmp $path; return } catch { Start-Sleep -Milliseconds 100 }
  }
  throw "Nao consegui gravar $path"
}

function Save-State($tunnels) {
  Write-FileAtomic $StateFile (ConvertTo-Json -InputObject @{ tunnels = @($tunnels) } -Depth 5)
}

# Marca como inativos os tuneis cujo terminal dono nao existe mais.
function Update-Prune($tunnels) {
  foreach ($t in $tunnels) { if ($t.active -and -not (Test-Alive $t.owner)) { $t.active = $false } }
  return $tunnels
}

function New-BlueprintYaml($tunnels, [string]$domain) {
  $yaml = "public-resources:`n"
  foreach ($t in $tunnels) {
    $en = if ($t.active) { "true" } else { "false" }
    $yaml += @"
  tunel-$($t.sub):
    name: tunel $($t.sub)
    mode: http
    full-domain: $($t.sub).$domain
    enabled: $en
    auth:
      sso-enabled: false
    targets:
      - hostname: $($t.host)
        port: $($t.port)
        method: http

"@
  }
  return $yaml
}

function Write-Blueprint($tunnels) {
  $yaml = New-BlueprintYaml $tunnels (Get-Config).domain
  $old = if (Test-Path $Blueprint) { [IO.File]::ReadAllText($Blueprint) } else { "" }
  if ($old -eq $yaml) { return }
  Write-FileAtomic $Blueprint $yaml
}

# Processos do Pangolin que NAO foram iniciados pelo tunel.
function Get-ExternalPangolin {
  $ours = Read-PidFile $PanPidFile
  return @(Get-Process -Name pangolin -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $ours })
}

# Descobre quem escuta na porta e qual endereco usar como destino.
function Get-Listener([int]$port) {
  $l = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
  if (-not $l) { return $null }
  $addrs = @($l | ForEach-Object { $_.LocalAddress } | Select-Object -Unique)
  $name = (Get-Process -Id $l[0].OwningProcess -ErrorAction SilentlyContinue).ProcessName
  # localhost e resolvido primeiro como ::1; apps so em IPv4 precisam de 127.0.0.1
  $h = "localhost"
  if ($addrs -contains "0.0.0.0" -or $addrs -contains "127.0.0.1") { $h = "127.0.0.1" }
  elseif (-not ($addrs -contains "::" -or $addrs -contains "::1")) { $h = $addrs[0] }
  return [pscustomobject]@{ Host = $h; Process = $name; Addrs = ($addrs -join ", ") }
}

function Get-UrlStatus([string]$url) {
  try {
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
    return [int]$r.StatusCode
  } catch {
    $resp = $_.Exception.Response
    if (-not $resp) { return 0 }
    $code = [int]$resp.StatusCode
    if ($code -eq 404) {
      # 404 do Traefik = recurso ainda nao existe/ativo; 404 do app = tunel ok
      try {
        $body = (New-Object IO.StreamReader($resp.GetResponseStream())).ReadToEnd()
        if ($body.Trim() -eq "404 page not found") { return -404 }
      } catch {}
    }
    return $code
  }
}

# ---------------------------------------------------------------- supervisor

function Start-Supervisor {
  $args2 = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$PSCommandPath`"", "__supervisor")
  Start-Process -FilePath "powershell.exe" -ArgumentList $args2 -WindowStyle Hidden | Out-Null
}

function Start-Pangolin($cfg) {
  $exe = (Get-Command $cfg.pangolin -ErrorAction SilentlyContinue).Source
  if (-not $exe) { throw "Nao achei o executavel do Pangolin: '$($cfg.pangolin)'" }
  Remove-Item $HealthFile -ErrorAction SilentlyContinue
  $a = @("up", "site", "--id", $cfg.id, "--secret", $cfg.secret, "--endpoint", $cfg.endpoint,
         "--blueprint-file", "`"$Blueprint`"", "--health-file", "`"$HealthFile`"")
  $p = Start-Process -FilePath $exe -ArgumentList $a -WindowStyle Hidden -PassThru `
         -RedirectStandardOutput $LogFile -RedirectStandardError $ErrLogFile
  [IO.File]::WriteAllText($PanPidFile, "$($p.Id)")
  return $p
}

function Invoke-Supervisor {
  # Garante um unico supervisor (o mutex fica preso enquanto este processo viver)
  $single = New-Object Threading.Mutex($false, "Local\tunel-supervisor")
  try { if (-not $single.WaitOne(0)) { return } } catch [Threading.AbandonedMutexException] {}
  [IO.File]::WriteAllText($SupPidFile, "$PID")
  $cfg = Get-Config
  $pan = $null
  $idleSince = $null
  try {
    while ($true) {
      $active = Invoke-Locked {
        $t = Update-Prune (Read-State)
        Save-State $t
        Write-Blueprint $t
        @($t | Where-Object { $_.active }).Count
      }
      if ($active -eq 0) {
        if (-not $idleSince) { $idleSince = Get-Date }
        # espera o Pangolin aplicar o "enabled: false" antes de desligar
        elseif (((Get-Date) - $idleSince).TotalSeconds -gt 30) { break }
      } else {
        $idleSince = $null
        if (-not $pan -or $pan.HasExited) {
          if ($pan) { Start-Sleep 5 }  # caiu: espera um pouco antes de religar
          $pan = Start-Pangolin $cfg
        }
      }
      Start-Sleep 2
    }
  } finally {
    if ($pan -and -not $pan.HasExited) { Stop-Process -Id $pan.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item $PanPidFile, $SupPidFile, $HealthFile -ErrorAction SilentlyContinue
  }
}

# ---------------------------------------------------------------- comandos

function Invoke-List {
  $sup = Read-PidFile $SupPidFile
  $pan = Read-PidFile $PanPidFile
  $t = @(Invoke-Locked { Update-Prune (Read-State) } | Where-Object { $_.active })
  Write-Host ""
  if (Test-Alive $sup) {
    $st = if (Test-Path $HealthFile) { "online" } else { "conectando..." }
    Write-Host "  Pangolin: $st (PID $pan)" -ForegroundColor Green
  } else {
    Write-Host "  Pangolin: parado" -ForegroundColor DarkGray
  }
  $ext = Get-ExternalPangolin
  if ($ext) { Write-Host "  Atencao: Pangolin rodando fora do tunel (PID $($ext.Id -join ', '))" -ForegroundColor Yellow }
  Write-Host ""
  if (-not $t) { Write-Host "  Nenhum tunel ativo.`n"; return }
  $dom = (Get-Config).domain
  foreach ($x in $t) {
    Write-Host ("  {0,-45} -> {1}:{2}   (terminal PID {3})" -f "https://$($x.sub).$dom", $x.host, $x.port, $x.owner)
  }
  Write-Host ""
}

function Invoke-Stop {
  Invoke-Locked {
    $t = Read-State
    foreach ($x in $t) { $x.active = $false }
    Save-State $t
    Write-Blueprint $t
  }
  foreach ($f in @($SupPidFile, $PanPidFile)) {
    $p = Read-PidFile $f
    if (Test-Alive $p) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item $PanPidFile, $SupPidFile, $HealthFile -ErrorAction SilentlyContinue
  Write-Host "`n  Todos os tuneis e a conexao foram encerrados.`n" -ForegroundColor Yellow
}

function Get-Specs([string[]]$a) {
  # "8001 nome" vira "8001:nome"
  if ($a.Count -eq 2 -and $a[0] -match '^\d+$' -and $a[1] -notmatch ':' -and $a[1] -notmatch '^\d+$') {
    $a = @("$($a[0]):$($a[1])")
  }
  $seen = @{}
  foreach ($s in $a) {
    $parts = $s.Split(':')
    $port = $parts[0]
    if ($port -notmatch '^\d+$' -or [int]$port -lt 1 -or [int]$port -gt 65535) {
      throw "Porta invalida: '$s'. Use <porta> ou <porta:nome> (1-65535)."
    }
    $sub = if ($parts.Count -gt 1 -and $parts[1]) { $parts[1].ToLower() } else { "p$port" }
    if ($sub -notmatch '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$') { throw "Nome invalido: '$sub' (letras, numeros e hifen)." }
    if ($seen.ContainsKey("p$port")) { throw "Porta $port repetida no comando." }
    if ($seen.ContainsKey("s$sub"))  { throw "Nome '$sub' repetido no comando." }
    $seen["p$port"] = 1; $seen["s$sub"] = 1
    [pscustomobject]@{ port = [int]$port; sub = $sub }
  }
}

function Invoke-Open([string[]]$specArgs, [bool]$dryRun) {
  $cfg = Get-Config
  $specs = @(Get-Specs $specArgs)

  # Porta local: tem algo escutando? Define o destino (127.0.0.1 / localhost).
  $mine = @()
  foreach ($s in $specs) {
    $l = Get-Listener $s.port
    $h = "localhost"
    if ($l) { $h = $l.Host }
    else { Write-Host "  Aviso: nada escutando em localhost:$($s.port). O link dara 502 ate o app subir." -ForegroundColor Yellow }
    $mine += [pscustomobject]@{ sub = $s.sub; port = $s.port; host = $h; owner = $PID; active = $true; proc = $(if ($l) { $l.Process } else { "" }) }
  }

  if ($dryRun) { New-BlueprintYaml $mine $cfg.domain; return }

  # Pangolin iniciado fora do tunel usa as mesmas credenciais e entraria em conflito.
  $ext = Get-ExternalPangolin
  if ($ext) {
    Write-Host "`n  Ja existe um Pangolin rodando fora do 'tunel' (PID $($ext.Id -join ', '))." -ForegroundColor Red
    Write-Host "  Ele usa o mesmo site e entraria em conflito. Encerre-o e rode de novo:"
    Write-Host "    Stop-Process -Id $($ext.Id -join ',')`n"
    Write-Host "  Se for um servico do Windows: pangolin service uninstall site`n"
    exit 1
  }

  # Registra os tuneis (com verificacao de conflito) sob lock.
  $conflict = Invoke-Locked {
    $t = @(Update-Prune (Read-State))
    foreach ($m in $mine) {
      $busy = $t | Where-Object { $_.active -and ($_.port -eq $m.port -or $_.sub -eq $m.sub) } | Select-Object -First 1
      if ($busy) {
        if ($busy.port -eq $m.port) { return "A porta $($m.port) ja esta no tunel 'https://$($busy.sub).$($cfg.domain)' (terminal PID $($busy.owner))." }
        return "O nome '$($m.sub)' ja esta em uso pelo tunel da porta $($busy.port) (terminal PID $($busy.owner))."
      }
    }
    foreach ($m in $mine) {
      $t = @($t | Where-Object { $_.sub -ne $m.sub })
      $t += [pscustomobject]@{ sub = $m.sub; port = $m.port; host = $m.host; owner = $m.owner; active = $true }
    }
    Save-State $t
    Write-Blueprint $t
    return $null
  }
  if ($conflict) { Write-Host "`n  $conflict`n  Veja os ativos com: tunel list`n" -ForegroundColor Red; exit 1 }

  try {
    $reuse = Test-Supervisor
    if ($reuse) {
      Write-Host "`n  Pangolin ja esta online - adicionando a conexao existente." -ForegroundColor DarkGray
    } else {
      Write-Host "`n  Conectando ao Pangolin..." -ForegroundColor DarkGray
      Start-Supervisor
      $deadline = (Get-Date).AddSeconds(30)
      while (-not (Test-Path $HealthFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
      if (-not (Test-Path $HealthFile)) {
        Write-Host "  Nao conectou em 30s. Ultimas linhas do log:" -ForegroundColor Red
        Get-Content $LogFile, $ErrLogFile -Tail 8 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" }
        Write-Host "  (continuo tentando em segundo plano)" -ForegroundColor DarkGray
      }
    }

    Write-Host ""
    foreach ($m in $mine) {
      $app = if ($m.proc) { "  [$($m.proc)]" } else { "" }
      Write-Host ("  {0,-45} -> http://{1}:{2}{3}" -f "https://$($m.sub).$($cfg.domain)", $m.host, $m.port, $app) -ForegroundColor Green
    }

    # Espera o recurso ficar ativo (o Pangolin recarrega o blueprint em alguns segundos).
    Write-Host ""
    foreach ($m in $mine) {
      $url = "https://$($m.sub).$($cfg.domain)/"
      $deadline = (Get-Date).AddSeconds(60)
      $code = 0
      do { $code = Get-UrlStatus $url; if ($code -le 0) { Start-Sleep 2 } } while ($code -le 0 -and (Get-Date) -lt $deadline)
      if ($code -le 0) { Write-Host "  $($m.sub): ainda nao respondeu - pode levar mais alguns segundos." -ForegroundColor Yellow }
      elseif ($code -eq 502 -or $code -eq 503) { Write-Host "  $($m.sub): tunel ativo, mas o app nao respondeu ($code)." -ForegroundColor Yellow }
      else { Write-Host "  $($m.sub): pronto ($code)" -ForegroundColor Green }
    }
    Write-Host "`n  Ctrl+C para encerrar. Outros tuneis: abra outro terminal e rode 'tunel'.`n" -ForegroundColor DarkGray

    # Mantem o terminal "dono" dos tuneis; religa o supervisor se ele cair.
    $subs = @($mine | ForEach-Object { $_.sub })
    while ($true) {
      Start-Sleep 2
      try {
        $still = Invoke-Locked { @(Read-State | Where-Object { $_.active -and $_.owner -eq $PID -and $subs -contains $_.sub }).Count }
      } catch { continue }
      if ($still -eq 0) { Write-Host "  Tuneis encerrados por 'tunel stop'." -ForegroundColor Yellow; break }
      if (-not (Test-Supervisor)) { Start-Supervisor; Start-Sleep 3 }
    }
  } finally {
    Invoke-Locked {
      $t = @(Read-State)
      foreach ($x in $t) { if ($x.owner -eq $PID) { $x.active = $false } }
      Save-State $t
      Write-Blueprint $t
    }
    Write-Host "  Tunel encerrado." -ForegroundColor DarkGray
  }
}

# ---------------------------------------------------------------- main

$argv = @($args | ForEach-Object { "$_" })
$dry = $false
if ($argv -contains "-DryRun" -or $argv -contains "--dry-run") {
  $dry = $true
  $argv = @($argv | Where-Object { $_ -ne "-DryRun" -and $_ -ne "--dry-run" })
}

try {
  if ($argv.Count -eq 0) { Show-Example; exit 0 }
  switch -Regex ($argv[0]) {
    '^(--help|-h|-\?|/\?|help|ajuda)$' { Show-Help; exit 0 }
    '^__supervisor$'                   { Invoke-Supervisor; exit 0 }
    '^(list|status|ls)$'               { Invoke-List; exit 0 }
    '^stop$'                           { Invoke-Stop; exit 0 }
    default                            { Invoke-Open $argv $dry }
  }
} catch {
  Write-Host "`n  Erro: $($_.Exception.Message)`n" -ForegroundColor Red
  exit 1
}
