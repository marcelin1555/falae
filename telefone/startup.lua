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
-- Opcional de proposito: pixel, palette e marca sao a parte pesada da
-- instalacao e a primeira a ficar de fora quando o disco aperta. Um telefone
-- sem a animacao continua sendo um telefone; um telefone que se recusa a ligar
-- porque falta o desenho da logo, nao.
local function abertura()
  if not (fs.exists("/marca.lua") and fs.exists("/pixel.lua")) then return end
  local ok = pcall(function()
    local pixel = carregar("pixel")
    local marca = carregar("marca")
    if fs.exists("/palette.lua") then
      local palette = carregar("palette")
      palette.aplicar(term.current(), palette.PALETAS.falae)
    end
    marca.abertura(term.current(), pixel, 8)
    sleep(0.4)
  end)
  return ok
end

abertura()

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
