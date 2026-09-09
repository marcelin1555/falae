--[[ startup - o telefone liga

  Se ainda nao ha linha neste aparelho, abre a tela de entrada. Depois, o
  aplicativo. Sair do aplicativo (trocar de PIN, sair da linha) volta para a
  tela de entrada em vez de cair no shell - um telefone que vira linha de
  comando quando voce sai da conta nao parece um telefone.
]]

local function achar(caminho)
  return fs.exists(caminho)
end

for _, arquivo in ipairs({ "/carregar.lua", "/protocolo.lua", "/numero.lua", "/janela.lua",
                          "/campo.lua", "/ritmo.lua", "/fnet.lua",
                          "/agenda.lua", "/app.lua" }) do
  if not achar(arquivo) then
    print("FALAE: instalacao incompleta - falta " .. arquivo)
    return
  end
end

local carregar = dofile("/carregar.lua")
local fnet   = carregar("fnet")
local app    = carregar("app")
local entrar = carregar("entrar")
local janela = carregar("janela")

--- A abertura, uma vez, ao ligar o aparelho.
--
-- Versao CURTA: uns seis segundos em vez dos quinze da central. Quem tira o
-- pocket do bolso quer usar o pocket, e a central so se apresenta uma vez por
-- reinicio - o telefone, toda vez que alguem o pega.
--
-- Opcional de proposito: pixel, palette, marca e abertura sao a parte pesada da
-- instalacao e a primeira a ficar de fora quando o disco aperta. Um telefone
-- sem a animacao continua sendo um telefone; um que se recusa a ligar porque
-- falta o desenho da logo, nao.
local function mostrarAbertura()
  if not (fs.exists("/marca.lua") and fs.exists("/pixel.lua")
          and fs.exists("/palette.lua") and fs.exists("/abertura.lua")) then
    return false
  end

  local ok = pcall(function()
    local pixel   = carregar("pixel")
    local marca   = carregar("marca")
    local abert   = carregar("abertura")
    local palette = carregar("palette")
    local numero  = carregar("numero")

    -- O diagnostico do aparelho: se ele achou a central, e qual e a sua linha.
    -- Buscar a central AQUI aproveita a espera da animacao para uma coisa util
    -- - o rednet.lookup bloqueia uns dois segundos de qualquer jeito, e o
    -- aplicativo ja acha o caminho pronto quando abrir.
    local achou = fnet.conectar(true)
    local sessao = fnet.sessao()

    local diag = {
      abert.linhaDiag("modem", fnet.modem and "ok" or "faltando", 18),
      abert.linhaDiag("central", achou and ("#" .. achou) or "sem sinal", 18),
    }
    if sessao then
      diag[#diag + 1] = abert.linhaDiag("linha", numero.formatar(sessao.numero), 18)
    end

    abert.rodar(term.current(),
                { pixel = pixel, marca = marca, palette = palette },
                diag, true)
  end)
  return ok
end

mostrarAbertura()

while true do
  if not fnet.entrou() then
    local tela = janela.tela(term.current())
    local ok, entrou = pcall(entrar.rodar, tela, app.CORES)
    if not ok then
      term.setBackgroundColour(colors.black)
      term.setTextColour(colors.red)
      term.clear()
      term.setCursorPos(1, 1)
      print("FALAE: " .. tostring(entrou))
      return
    end
    if not entrou then
      term.setBackgroundColour(colors.black)
      term.setTextColour(colors.white)
      term.clear()
      term.setCursorPos(1, 1)
      return
    end
  end

  local ok, erro = pcall(app.rodar, term.current())
  if not ok then
    term.setCursorBlink(false)
    term.setBackgroundColour(colors.black)
    term.setTextColour(colors.red)
    term.clear()
    term.setCursorPos(1, 1)
    print("o telefone caiu:")
    print(tostring(erro))
    term.setTextColour(colors.white)
    print("")
    print("qualquer tecla para tentar de novo")
    os.pullEvent("key")
  end
end
