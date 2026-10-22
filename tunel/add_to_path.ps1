# add_to_path - coloca a pasta do tunel no PATH do usuario (Windows), para rodar "tunel"
# de qualquer pasta. Nao precisa de administrador.
#
# Uso:
#   add_to_path.cmd              adiciona esta pasta ao PATH
#   add_to_path.cmd -Remove      remove esta pasta do PATH

$ErrorActionPreference = "Stop"
$remove = ($args -contains "-Remove" -or $args -contains "--remove")
$dir = $PSScriptRoot.TrimEnd('\')

function Write-Info([string]$msg, [string]$color = "Gray") { Write-Host "  $msg" -ForegroundColor $color }

Write-Host ""
if (-not (Test-Path (Join-Path $dir "tunel.cmd"))) {
  Write-Info "Nao achei tunel.cmd em $dir. Rode este script de dentro da pasta tunel." Red
  Write-Host ""
  exit 1
}

$atual = [Environment]::GetEnvironmentVariable("Path", "User")
$itens = @($atual -split ';' | Where-Object { $_ -and $_.Trim() })
$ja = @($itens | Where-Object { $_.TrimEnd('\') -ieq $dir }).Count -gt 0

if ($remove) {
  if (-not $ja) { Write-Info "A pasta nao esta no PATH: $dir" Yellow; Write-Host ""; exit 0 }
  $novo = ($itens | Where-Object { $_.TrimEnd('\') -ine $dir }) -join ';'
  [Environment]::SetEnvironmentVariable("Path", $novo, "User")
  Write-Info "Removido do PATH: $dir" Green
  Write-Info "Abra um terminal novo para valer." DarkGray
  Write-Host ""
  exit 0
}

if ($ja) {
  Write-Info "Ja esta no PATH: $dir" Green
} else {
  $novo = (($itens + $dir) -join ';')
  [Environment]::SetEnvironmentVariable("Path", $novo, "User")
  Write-Info "Adicionado ao PATH: $dir" Green
}

# Verificacoes uteis para um PC novo
if (-not (Test-Path (Join-Path $dir "tunel.config.json"))) {
  Write-Info "Falta o tunel.config.json nesta pasta (copie tunel.config.example.json e preencha ID e Secret)." Yellow
}
if (-not (Get-Command pangolin -ErrorAction SilentlyContinue)) {
  Write-Info "O comando 'pangolin' nao foi encontrado. Instale o Pangolin CLI (passo 5 do guia)." Yellow
}

Write-Host ""
Write-Info "Pronto. Feche e abra o terminal e teste com:  tunel --help" Cyan
Write-Host ""
