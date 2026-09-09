<#
.SYNOPSIS
  Instala a FALAE num computador do save, copiando direto.

.DESCRIPTION
  ESTE E O CAMINHO SECUNDARIO. Ele so funciona se voce for dono do mundo,
  porque mexe na pasta do save. Em servidor de outra pessoa use o instalador
  que roda dentro do jogo:

    wget run https://raw.githubusercontent.com/marcelin1555/falae/main/instalar.lua

  A lista de arquivos NAO mora aqui: ela vem de manifesto.txt, o mesmo arquivo
  que o instalador le pela rede. Duas listas separadas divergiriam no dia em
  que um modulo novo entrasse so numa delas, e o sintoma seria um computador
  instalado pela metade dizendo "modulo faltando".

  Funciona com o jogo aberto: basta Ctrl+R no computador depois.

.EXAMPLE
  .\deploy.ps1 -Id 9                        # central no computador 9
  .\deploy.ps1 -Id 13 -Tipo telefone        # telefone no pocket 13
  .\deploy.ps1 -Id 13 -Tipo telefone -SemVisual
  .\deploy.ps1 -Perfil ALLUM -Save "Novo mundo" -Id 5
#>
param(
  [int]$Id = 9,
  [ValidateSet("central", "telefone", "loja")][string]$Tipo = "central",
  [string]$Save = "New World",
  # Outro perfil do Modrinth. Caminho completo, ou so o nome da pasta.
  [string]$Perfil = "",
  # Pula a marca e o painel: um telefone sem a animacao continua sendo um
  # telefone, e num disco apertado essa e a primeira coisa a cortar.
  [switch]$SemVisual
)

$ErrorActionPreference = "Stop"
$raiz = $PSScriptRoot

# CUIDADO: nome de variavel no PowerShell nao diferencia maiuscula. Chamar
# esta de $perfil apagaria o parametro $Perfil, e o deploy iria sempre para o
# perfil onde o script mora.
$destino = Split-Path $raiz -Parent

if ($Perfil -ne "") {
  if (Test-Path $Perfil) {
    $destino = (Resolve-Path $Perfil).Path
  } else {
    $destino = Join-Path (Split-Path $destino -Parent) $Perfil
  }
  if (-not (Test-Path $destino)) {
    Write-Host "perfil nao encontrado: $destino" -ForegroundColor Red
    exit 1
  }
}

$alvo = Join-Path $destino "saves\$Save\computercraft\computer\$Id"

if (-not (Test-Path $alvo)) {
  Write-Host "A pasta do computador $Id nao existe:" -ForegroundColor Red
  Write-Host "  $alvo"
  Write-Host "Coloque o computador no mundo e rode qualquer programa nele uma vez."
  Write-Host "Num pocket: segure e aperte com o botao direito."
  exit 1
}

# ------------------------------------------------------------- o manifesto

$manifesto = Join-Path $raiz "manifesto.txt"
if (-not (Test-Path $manifesto)) {
  Write-Host "falta o manifesto.txt - ele e a lista de arquivos do projeto" -ForegroundColor Red
  exit 1
}

$papeis = @($Tipo)
if (-not $SemVisual) { $papeis += "$Tipo-visual" }

$arquivos = @()
foreach ($linha in Get-Content $manifesto) {
  $l = $linha.Trim()
  if ($l -eq "" -or $l.StartsWith("#")) { continue }
  $partes = $l -split '\|'
  if ($partes.Count -ne 3) { continue }
  $papel = $partes[0].Trim()
  if ($papeis -contains $papel) {
    $arquivos += [pscustomobject]@{
      Destino = $partes[1].Trim()
      Origem  = $partes[2].Trim()
    }
  }
}

if ($arquivos.Count -eq 0) {
  Write-Host "o manifesto nao tem nada para o papel '$Tipo'" -ForegroundColor Red
  exit 1
}

# ---------------------------------------------------------------- copiando

Write-Host "FALAE -> computador $Id ($Tipo)" -ForegroundColor Yellow

$faltando = @()
foreach ($a in $arquivos) {
  $de = Join-Path $raiz $a.Origem
  if (-not (Test-Path $de)) {
    $faltando += $a.Origem
    continue
  }

  $para = Join-Path $alvo ($a.Destino -replace '/', '\')
  $pasta = Split-Path $para -Parent
  if (-not (Test-Path $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
  Copy-Item -Path $de -Destination $para -Force
  Write-Host "  $($a.Destino)" -ForegroundColor DarkGray
}

if ($faltando.Count -gt 0) {
  Write-Host ""
  Write-Host "o manifesto lista arquivo que nao existe:" -ForegroundColor Red
  foreach ($f in $faltando) { Write-Host "  $f" -ForegroundColor Red }
  exit 1
}

Write-Host ""
Write-Host "$($arquivos.Count) arquivo(s). Ctrl+R no computador." -ForegroundColor Green

if ($Tipo -eq "central") {
  Write-Host "A central precisa de um Ender Modem encostado." -ForegroundColor DarkYellow
  if (-not $SemVisual) {
    Write-Host "Monitor, se houver, tambem encostado." -ForegroundColor DarkYellow
  }
} else {
  Write-Host "O aparelho precisa de um Ender Modem nas costas." -ForegroundColor DarkYellow
  Write-Host "O slot de upgrade e um so, entao nao da para ter speaker junto." -ForegroundColor DarkGray
}
