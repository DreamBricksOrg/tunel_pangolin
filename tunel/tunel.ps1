# tunel - expoe portas locais em subdominios HTTPS usando o Pangolin (Windows).
# Rode "tunel --help" para ver como usar. Credenciais em tunel.config.json (mesma pasta);
# outros servidores: tunel.config.<perfil>.json e a opcao -p <perfil>.
#
# Como funciona: uma unica conexao do Pangolin (processo em segundo plano, gerenciado por um
# "supervisor") atende todos os tuneis deste PC. Cada terminal com "tunel" aberto adiciona seus
# tuneis ao blueprint; o Pangolin recarrega o arquivo sozinho. Ao sair (Ctrl+C ou fechando a
# janela) os tuneis daquele terminal sao desativados (enabled: false). Sem tuneis ativos, o
# supervisor encerra o Pangolin depois de ~30s.

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BaseDir = Join-Path $env:LOCALAPPDATA "tunel"

# Perfil = um servidor Pangolin. "default" usa tunel.config.json; os demais usam
# tunel.config.<perfil>.json, com estado proprio em $BaseDir\profiles\<perfil>.
function Set-Profile([string]$name) {
  $script:ProfileName = $name
  if ($name -eq "default") {
    $script:ConfigPath  = Join-Path $PSScriptRoot "tunel.config.json"
    $script:StateDir    = $BaseDir
    $script:MutexSuffix = ""
  } else {
    $script:ConfigPath  = Join-Path $PSScriptRoot "tunel.config.$name.json"
    $script:StateDir    = Join-Path $BaseDir "profiles\$name"
    $script:MutexSuffix = "-$name"
  }
  $script:StateFile  = Join-Path $StateDir "tunnels.json"
  $script:Blueprint  = Join-Path $StateDir "blueprint.yaml"
  $script:SupPidFile = Join-Path $StateDir "supervisor.pid"
  $script:PanPidFile = Join-Path $StateDir "pangolin.pid"
  $script:HealthFile = Join-Path $StateDir "healthy"
  $script:LogFile    = Join-Path $StateDir "pangolin.log"
  $script:ErrLogFile = Join-Path $StateDir "pangolin.err.log"
  New-Item -ItemType Directory -Force $StateDir | Out-Null
}

# Perfis que tem arquivo de configuracao.
function Get-Profiles {
  $p = @()
  if (Test-Path (Join-Path $PSScriptRoot "tunel.config.json")) { $p += "default" }
  Get-ChildItem $PSScriptRoot -Filter "tunel.config.*.json" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^tunel\.config\.([a-z0-9][a-z0-9-]*)\.json$' -and $Matches[1] -ne "example" } |
    ForEach-Object { $p += ([regex]::Match($_.Name, '^tunel\.config\.(.+)\.json$')).Groups[1].Value }
  return $p
}

# ---------------------------------------------------------------- ajuda

function Show-Example {
  Write-Host ""
  Write-Host "  Uso: tunel <porta> [nome]" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  Exemplo:"
  Write-Host "    tunel 8001 meuapp      ->  https://meuapp.$((Get-Config).domain)  ->  localhost:8001" -ForegroundColor Green
  $others = @(Get-Profiles | Where-Object { $_ -ne $ProfileName })
  if ($others) { Write-Host "    tunel -p $($others[0]) 8001 meuapp   (outro servidor)" -ForegroundColor Green }
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
    tunel list                       Mostra a conexao e os tuneis ativos (todos os perfis).
    tunel stop                       Encerra TODOS os tuneis e conexoes (todos os perfis).
    tunel --help                     Esta ajuda.

  OPCOES
    -p, --profile <perfil>           Usa outro servidor (perfil). Padrao: tunel.config.json.
                                     Tambem vale a variavel TUNEL_PROFILE.
    -DryRun                          So mostra o blueprint, nao abre nada.

  PERFIS (varios servidores / dominios no mesmo PC)
    Cada perfil e um arquivo tunel.config.<perfil>.json (copie tunel.config.example.json).
    tunel -p dbpe 8001 meuapp        https://meuapp.<dominio do perfil dbpe>
    tunel -p dbpe list               so o perfil dbpe
    tunel -p dbpe stop               encerra so o perfil dbpe
    Perfis disponiveis: $((Get-Profiles) -join ', ')

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

  TERMINAL FECHADO A FORCA
    Os tuneis daquele terminal ficam desativados (o link da 404). A conexao em segundo plano
    morre junto com o supervisor e, se sobrar algum processo antigo, ele e encerrado na proxima
    vez que voce rodar "tunel". Basta rodar o comando de novo. Se o supervisor cair com o
    terminal aberto, o terminal religa tudo sozinho.

  ARQUIVOS
    Config:  $ConfigPath
    Estado:  $StateDir

"@
}

# ---------------------------------------------------------------- utilitarios

function Get-Config {
  if (-not (Test-Path $ConfigPath)) {
    if ($ProfileName -eq "default") { throw "Nao achei $ConfigPath" }
    throw "Perfil '$ProfileName' nao existe. Crie $ConfigPath (copie tunel.config.example.json e preencha)."
  }
  return Get-Content $ConfigPath -Raw | ConvertFrom-Json
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
  $m = New-Object Threading.Mutex($false, "Local\tunel-state$MutexSuffix")
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

# O tunel inicia o Pangolin com --blueprint-file apontando para uma pasta dentro de $BaseDir.
function Test-TunelCmdLine([string]$cmd) {
  return [bool]($cmd -and $cmd.IndexOf($BaseDir, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                $cmd.IndexOf("blueprint.yaml", [StringComparison]::OrdinalIgnoreCase) -ge 0)
}

# Processos do Pangolin que NAO foram iniciados pelo tunel (de nenhum perfil) e que usam o
# site deste perfil. Sem linha de comando legivel (ex.: servico), considera conflito.
function Get-ExternalPangolin {
  $id = (Get-Config).id
  $procs = @(Get-CimInstance Win32_Process -Filter "Name='pangolin.exe'" -ErrorAction SilentlyContinue)
  return @($procs | Where-Object {
    -not (Test-TunelCmdLine $_.CommandLine) -and
    ((-not $_.CommandLine) -or ($_.CommandLine -notmatch '--id') -or ($_.CommandLine -match ('--id[ =]' + [regex]::Escape($id))))
  } | ForEach-Object { [pscustomobject]@{ Id = [int]$_.ProcessId } })
}

# Pangolin deste perfil que ficou orfao (o supervisor morreu a forca e deixou o processo vivo).
# Dois Pangolin com o mesmo site brigam entre si, entao sao encerrados antes de religar.
function Stop-ProfileOrphans {
  $procs = @(Get-CimInstance Win32_Process -Filter "Name='pangolin.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($Blueprint, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
  foreach ($p in $procs) { Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue }
  if ($procs.Count -gt 0) { Start-Sleep -Milliseconds 500 }
  Remove-Item $PanPidFile, $HealthFile -ErrorAction SilentlyContinue
  return $procs.Count
}

# Job do Windows com KILL_ON_JOB_CLOSE: o Pangolin morre junto com o supervisor, mesmo que ele
# seja encerrado a forca (nao sobra processo orfao).
function Add-ToKillJob($proc) {
  try {
    if (-not ("TunelJob" -as [type])) {
      Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TunelJob {
  [StructLayout(LayoutKind.Sequential)] struct IO_COUNTERS { public ulong a, b, c, d, e, f; }
  [StructLayout(LayoutKind.Sequential)] struct BASIC {
    public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags;
    public UIntPtr MinWs, MaxWs; public uint ActiveLimit; public UIntPtr Affinity; public uint Priority, SchedClass; }
  [StructLayout(LayoutKind.Sequential)] struct EXT {
    public BASIC Basic; public IO_COUNTERS Io; public UIntPtr ProcMem, JobMem, PeakProc, PeakJob; }
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr a, string name);
  [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int cls, IntPtr info, uint len);
  [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr proc);
  static IntPtr job = IntPtr.Zero;
  public static bool Attach(IntPtr proc) {
    if (job == IntPtr.Zero) {
      job = CreateJobObject(IntPtr.Zero, null);
      EXT e = new EXT(); e.Basic.LimitFlags = 0x2000;
      int len = Marshal.SizeOf(typeof(EXT)); IntPtr p = Marshal.AllocHGlobal(len);
      Marshal.StructureToPtr(e, p, false);
      bool ok = SetInformationJobObject(job, 9, p, (uint)len);
      Marshal.FreeHGlobal(p);
      if (!ok) return false;
    }
    return AssignProcessToJobObject(job, proc);
  }
}
'@
    }
    [void][TunelJob]::Attach($proc.Handle)
  } catch { }
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
      # o corpo as vezes vem vazio; o 404 do Traefik tem sempre 19 bytes em text/plain
      if ($resp.ContentLength -eq 19 -and $resp.ContentType -like "text/plain*") { return -404 }
    }
    return $code
  }
}

# ---------------------------------------------------------------- supervisor

function Start-Supervisor {
  $args2 = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$PSCommandPath`"", "-p", $ProfileName, "__supervisor")
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
  Add-ToKillJob $p
  return $p
}

function Invoke-Supervisor {
  # Garante um unico supervisor (o mutex fica preso enquanto este processo viver)
  $single = New-Object Threading.Mutex($false, "Local\tunel-supervisor$MutexSuffix")
  try { if (-not $single.WaitOne(0)) { return } } catch [Threading.AbandonedMutexException] {}
  [IO.File]::WriteAllText($SupPidFile, "$PID")
  [void](Stop-ProfileOrphans)   # sobras de um supervisor morto a forca
  $cfg = Get-Config
  $cfgStamp = (Get-Item $ConfigPath).LastWriteTimeUtc
  $pan = $null
  $idleSince = $null
  try {
    while ($true) {
      # config editada (ex.: novo ID/secret): rele e reconecta
      $stamp = (Get-Item $ConfigPath -ErrorAction SilentlyContinue).LastWriteTimeUtc
      if ($stamp -and $stamp -ne $cfgStamp) {
        $cfgStamp = $stamp
        try { $cfg = Get-Config } catch {}
        if ($pan -and -not $pan.HasExited) { Stop-Process -Id $pan.Id -Force -ErrorAction SilentlyContinue; $pan = $null }
      }
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

function Show-ProfileList {
  $sup = Read-PidFile $SupPidFile
  $pan = Read-PidFile $PanPidFile
  $t = @(Invoke-Locked { Update-Prune (Read-State) } | Where-Object { $_.active })
  $dom = (Get-Config).domain
  Write-Host ""
  Write-Host "  [$ProfileName] $dom" -ForegroundColor Cyan
  if (Test-Alive $sup) {
    $st = if (Test-Path $HealthFile) { "online" } else { "conectando..." }
    Write-Host "  Pangolin: $st (PID $pan)" -ForegroundColor Green
  } else {
    Write-Host "  Pangolin: parado" -ForegroundColor DarkGray
  }
  $ext = Get-ExternalPangolin
  if ($ext) { Write-Host "  Atencao: Pangolin rodando fora do tunel (PID $($ext.Id -join ', '))" -ForegroundColor Yellow }
  if (-not $t) { Write-Host "  Nenhum tunel ativo."; return }
  Write-Host ""
  foreach ($x in $t) {
    Write-Host ("  {0,-45} -> {1}:{2}   (terminal PID {3})" -f "https://$($x.sub).$dom", $x.host, $x.port, $x.owner)
  }
}

function Invoke-List([string[]]$names) {
  if (-not $names) { Write-Host "`n  Nenhum perfil configurado (tunel.config.json)." -ForegroundColor Yellow }
  foreach ($n in $names) { Set-Profile $n; Show-ProfileList }
  Write-Host ""
}

function Stop-Profile {
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
}

function Invoke-Stop([string[]]$names, [bool]$all) {
  foreach ($n in $names) { Set-Profile $n; Stop-Profile }
  if ($all) { Write-Host "`n  Todos os tuneis e conexoes foram encerrados.`n" -ForegroundColor Yellow }
  else { Write-Host "`n  Tuneis e conexao do perfil '$($names -join ', ')' encerrados.`n" -ForegroundColor Yellow }
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
    if ($reuse -and (Test-Path $HealthFile)) {
      Write-Host "`n  Pangolin ja esta online [$($ProfileName)] - adicionando a conexao existente." -ForegroundColor DarkGray
    } else {
      Write-Host "`n  Conectando ao Pangolin [$($ProfileName): $($cfg.domain)]..." -ForegroundColor DarkGray
      if (-not $reuse) {
        $n = Stop-ProfileOrphans
        if ($n -gt 0) { Write-Host "  Encerrei $n conexao antiga que ficou em segundo plano (terminal fechado a forca)." -ForegroundColor Yellow }
        Start-Supervisor
      }
      $deadline = (Get-Date).AddSeconds(30)
      while (-not (Test-Path $HealthFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
      if (-not (Test-Path $HealthFile)) {
        Write-Host "  NAO conectou em 30s - os links vao dar 404 ate conectar. Ultimas linhas do log:" -ForegroundColor Red
        Get-Content $LogFile, $ErrLogFile -Tail 4 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" }
        if ((Get-Content $LogFile -Tail 20 -ErrorAction SilentlyContinue) -match 'No newt found') {
          Write-Host "  O ID '$($cfg.id)' nao existe em $($cfg.endpoint). Crie o site NESSE painel e atualize $ConfigPath." -ForegroundColor Yellow
        }
        Write-Host "  (continuo tentando em segundo plano; editar o config reconecta sozinho)" -ForegroundColor DarkGray
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

$raw = @($args | ForEach-Object { "$_" })
$dry = $false
$explicitProfile = $null
$argv = @()
for ($i = 0; $i -lt $raw.Count; $i++) {
  $a = $raw[$i]
  if ($a -eq "-DryRun" -or $a -eq "--dry-run") { $dry = $true; continue }
  if ($a -match '^(-p|--profile|-Profile|--perfil)$') {
    if ($i + 1 -ge $raw.Count) { Write-Host "`n  Erro: $a precisa do nome do perfil.`n" -ForegroundColor Red; exit 1 }
    $explicitProfile = $raw[++$i].ToLower()
    continue
  }
  $argv += $a
}
if (-not $explicitProfile -and $env:TUNEL_PROFILE) { $explicitProfile = $env:TUNEL_PROFILE.ToLower() }

try {
  if ($explicitProfile -and $explicitProfile -notmatch '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$') {
    throw "Nome de perfil invalido: '$explicitProfile' (letras minusculas, numeros e hifen)."
  }
  Set-Profile $(if ($explicitProfile) { $explicitProfile } else { "default" })

  if ($argv.Count -eq 0) { Show-Example; exit 0 }
  switch -Regex ($argv[0]) {
    '^(--help|-h|-\?|/\?|help|ajuda)$' { Show-Help; exit 0 }
    '^__supervisor$'                   { Invoke-Supervisor; exit 0 }
    '^(list|status|ls)$'               {
      $names = if ($explicitProfile) { @($explicitProfile) } else { @(Get-Profiles) }
      Invoke-List $names; exit 0
    }
    '^stop$'                           {
      $names = if ($explicitProfile) { @($explicitProfile) } else { @(Get-Profiles) }
      Invoke-Stop $names (-not $explicitProfile); exit 0
    }
    default                            { Invoke-Open $argv $dry }
  }
} catch {
  Write-Host "`n  Erro: $($_.Exception.Message)`n" -ForegroundColor Red
  exit 1
}
