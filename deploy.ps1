<#
.SYNOPSIS
  Instala a FALAE num computador do save.

.DESCRIPTION
  Copia direto para a pasta do computador dentro do save. Funciona com o jogo
  aberto: o CC le o arquivo do disco quando o programa roda, entao basta um
  reboot (Ctrl+R) no computador do jogo para pegar a versao nova.

  -Tipo central    a central telefonica: rotas, linhas, recados, console e o
                   painel do monitor.
  -Tipo telefone   o aparelho: as telas, a agenda e a linha direta com a
                   central. E o que vai no Advanced Pocket Computer.

  -SemMarca        pula pixel, palette e marca. O aparelho fica sem a abertura
                   e a central sem o painel, mas os dois funcionam igual. Serve
                   para pocket com disco apertado.

.EXAMPLE
  .\deploy.ps1 -Id 9                       # central no computador 9
  .\deploy.ps1 -Id 13 -Tipo telefone       # telefone no pocket 13
  .\deploy.ps1 -Id 13 -Tipo telefone -SemMarca
#>
param(
  [int]$Id = 9,
  [ValidateSet("central", "telefone")][string]$Tipo = "central",
  [string]$Save = "New World",
  # Outro perfil do Modrinth. Caminho completo, ou so o nome da pasta.
  [string]$Perfil = "",
  [switch]$SemMarca
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
  Write-Host "Num pocket: aperte com ele na mao e feche."
  exit 1
}

function Copiar($de, $para) {
  $pasta = Split-Path $para -Parent
  if (-not (Test-Path $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
  Copy-Item -Path $de -Destination $para -Force
  Write-Host "  $(Split-Path $para -Leaf)" -ForegroundColor DarkGray
}

# A parte visual. Sai junto por padrao e fica de fora com -SemMarca: e a
# primeira coisa a cortar quando o disco aperta, porque um telefone sem a
# animacao continua sendo um telefone.
$visual = @("pixel", "palette")

Write-Host "FALAE -> computador $Id ($Tipo)" -ForegroundColor Yellow

if ($Tipo -eq "central") {
  foreach ($n in @("protocolo", "numero")) {
    Copiar (Join-Path $raiz "comum\$n.lua") (Join-Path $alvo "$n.lua")
  }
  if (-not $SemMarca) {
    foreach ($n in $visual) {
      Copiar (Join-Path $raiz "comum\$n.lua") (Join-Path $alvo "$n.lua")
    }
  }

  Copiar (Join-Path $raiz "servidor\startup.lua") (Join-Path $alvo "startup.lua")

  Get-ChildItem (Join-Path $raiz "servidor\core") -Filter *.lua | ForEach-Object {
    Copiar $_.FullName (Join-Path $alvo "core\$($_.Name)")
  }

  if (-not $SemMarca) {
    Get-ChildItem (Join-Path $raiz "servidor\tela") -Filter *.lua | ForEach-Object {
      Copiar $_.FullName (Join-Path $alvo "tela\$($_.Name)")
    }
  } else {
    Write-Host "  (sem tela: a central roda sem monitor)" -ForegroundColor DarkYellow
  }

  Write-Host "pronto - Ctrl+R no computador. A central precisa de um Ender Modem." -ForegroundColor Green
}
else {
  # o aparelho: bibliotecas na raiz, telas em /telas
  foreach ($n in @("carregar", "protocolo", "numero", "janela", "campo", "ritmo")) {
    Copiar (Join-Path $raiz "comum\$n.lua") (Join-Path $alvo "$n.lua")
  }
  if (-not $SemMarca) {
    foreach ($n in $visual) {
      Copiar (Join-Path $raiz "comum\$n.lua") (Join-Path $alvo "$n.lua")
    }
    # a marca mora em servidor\tela porque a central tambem a usa; no aparelho
    # ela vai para a raiz, que e onde o carregador procura
    Copiar (Join-Path $raiz "servidor\tela\marca.lua") (Join-Path $alvo "marca.lua")
  }

  foreach ($n in @("fnet", "agenda", "app", "startup")) {
    Copiar (Join-Path $raiz "telefone\$n.lua") (Join-Path $alvo "$n.lua")
  }

  Get-ChildItem (Join-Path $raiz "telefone\telas") -Filter *.lua | ForEach-Object {
    Copiar $_.FullName (Join-Path $alvo "telas\$($_.Name)")
  }

  Write-Host "pronto - Ctrl+R no aparelho." -ForegroundColor Green
  Write-Host "Precisa de um Ender Modem nas costas (o slot e um so)." -ForegroundColor DarkYellow
}
