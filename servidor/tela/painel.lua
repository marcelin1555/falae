--[[ painel - a FALAE no monitor da central

  O que a operadora ve de longe: se a FALAE esta no ar, quantas linhas existem,
  quanto trafego passa e qual fatia dos pedidos foi "nada mudou".

  DESENHA O FUNDO UMA VEZ E DEPOIS SO REESCREVE NUMERO. E a mesma disciplina do
  painel da Expresso Labs, e aqui ela vale ainda mais: monitor de CC e
  sincronizado com todo cliente por perto, entao quadro redesenhado a toa vira
  trafego a toa no servidor Minecraft inteiro - inclusive para quem so passou
  andando pela sala.

  Por isso tambem o atualizar() so escreve o que MUDOU desde a ultima vez: com
  a FALAE parada, um minuto inteiro de painel nao gera uma escrita sequer.

  A marca some para cinza quando a central perde o modem. E leitura de longe:
  da porta da sala nao da para ler texto, mas da para ver que o amarelo apagou.
]]

local lib     = dofile("/core/lib.lua")
local pixel   = lib("pixel")
local palette = lib("palette")
local marca   = lib("marca")
local numero  = lib("numero")
local linhas  = lib("linhas")
local recados = lib("recados")

local painel = {}

local tela          -- o monitor
local ultimo = {}   -- o que ja esta escrito, por rotulo
local montado = false
local corMarca = colors.yellow

local C = {
  fundo = colors.black, texto = colors.white, fraco = colors.gray,
  marca = colors.yellow, bom = colors.lime, ruim = colors.red,
  aviso = colors.orange,
}

--- Acha um monitor encostado na central. Sem monitor, o painel simplesmente
-- nao existe e a central roda igual - a tecla do console continua contando
-- tudo. Um sistema que exige monitor para funcionar quebra no dia em que
-- alguem tira o bloco.
function painel.achar()
  for _, nome in ipairs(peripheral.getNames()) do
    if peripheral.getType(nome) == "monitor" then
      return peripheral.wrap(nome), nome
    end
  end
  return nil
end

--- Escolhe a escala do texto pelo tamanho fisico do monitor.
--
-- Escala fixa nao serve: um monitor 8x4 blocos da 164x52 caracteres em escala
-- 0.5 e 41x13 em escala 2. Os dois "cabem" - mas 164 colunas num painel que se
-- le do outro lado da sala e letra de bula, e o painel existe justamente para
-- ser lido de longe.
--
-- O alvo e ficar perto de ALVO colunas: a maior escala (letra maior) que ainda
-- deixa espaco para a marca e a coluna de numeros lado a lado.
painel.ALVO   = 56
painel.MINIMO = 30    -- abaixo disto nao cabem as duas colunas

function painel.escala(monitor)
  local melhor, melhorErro = 1, math.huge

  -- de 5 para 0.5: comeca pela letra maior e so desce se nao couber
  for passo = 10, 1, -1 do
    local e = passo * 0.5
    if pcall(monitor.setTextScale, e) then
      local colunas = monitor.getSize()
      if colunas >= painel.MINIMO then
        local erro = math.abs(colunas - painel.ALVO)
        if erro < melhorErro then melhor, melhorErro = e, erro end
      end
    end
  end

  pcall(monitor.setTextScale, melhor)
  return melhor
end

function painel.ligar(monitor)
  tela = monitor
  if not tela then return false end

  painel.escalaUsada = painel.escala(tela)
  palette.aplicar(tela, palette.PALETAS.falae)
  montado = false
  ultimo = {}
  return true
end

function painel.desligar()
  if not tela then return end
  palette.restaurar(tela, painel.paletaAntes)
  tela.setBackgroundColour(colors.black)
  tela.setTextColour(colors.white)
  tela.clear()
end

-- ------------------------------------------------------------------ desenho

local function escrever(x, y, texto, cor, fundo)
  tela.setCursorPos(x, y)
  tela.setTextColour(cor or C.texto)
  tela.setBackgroundColour(fundo or C.fundo)
  tela.write(texto)
end

--- Escreve so se mudou. E a peca que faz o painel nao custar nada parado.
local function campo(rotulo, x, y, texto, cor, largura)
  texto = tostring(texto)
  if ultimo[rotulo] == texto .. "/" .. tostring(cor) then return false end
  ultimo[rotulo] = texto .. "/" .. tostring(cor)
  largura = largura or #texto
  escrever(x, y, texto .. string.rep(" ", math.max(0, largura - #texto)), cor)
  return true
end

--- O fundo: a marca a esquerda e os rotulos a direita. Uma vez so.
local function montar()
  local w, h = tela.getSize()

  tela.setBackgroundColour(C.fundo)
  tela.clear()

  -- a marca ocupa a esquerda; o resto da tela e a coluna de numeros
  local corte = math.min(math.floor(w * 0.42), 26)

  if corte >= 10 and h >= 8 then
    local janelaMarca = window.create(tela, 1, 1, corte, h, true)
    painel.janelaMarca = janelaMarca
    local fb = pixel.novo(janelaMarca)
    fb:limpar(colors.black)
    local r, cx, cy = marca.desenhar(fb, corMarca)
    fb:enviar()
    marca.escrever(janelaMarca, r, cx, cy, colors.black, corMarca)
  else
    painel.janelaMarca = nil
    escrever(2, 2, "FALAE", C.marca)
  end

  painel.x = corte + 2
  local x = painel.x

  escrever(x, 2, "central telefonica", C.fraco)
  escrever(x, 4, "linhas", C.fraco)
  escrever(x, 6, "recados", C.fraco)
  escrever(x, 8, "pedidos", C.fraco)
  escrever(x, 10, "sem novidade", C.fraco)
  escrever(x, 12, "no ar", C.fraco)

  montado = true
  ultimo = {}
end

--- Redesenha so a marca, quando ela troca de cor (a FALAE saiu ou voltou).
local function repintarMarca()
  if not painel.janelaMarca then return end
  local fb = pixel.novo(painel.janelaMarca)
  fb:limpar(colors.black)
  local r, cx, cy = marca.desenhar(fb, corMarca)
  fb:enviar()
  marca.escrever(painel.janelaMarca, r, cx, cy, colors.black, corMarca)
end

--- Atualiza os numeros. Chamado no maximo a cada poucos segundos.
-- @param estado o estado da central
function painel.atualizar(estado)
  if not tela then return false end
  if not montado then montar() end

  local x = painel.x
  local w = select(1, tela.getSize())
  local largura = w - x

  -- a marca acompanha o estado do modem: amarela no ar, cinza fora
  local queria = estado.modem and colors.yellow or colors.brown
  if queria ~= corMarca then
    corMarca = queria
    repintarMarca()
  end

  campo("modem", x, 3, estado.modem and "no ar" or "sem modem",
        estado.modem and C.bom or C.aviso, largura)

  campo("linhas", x, 5, tostring(linhas.quantas()), C.marca, largura)
  campo("recados", x, 7, tostring(recados.quantos()), C.texto, largura)
  campo("pedidos", x, 9, tostring(estado.pedidos), C.texto, largura)

  local soma = estado.pedidos + estado.recusas
  local fatia = soma > 0 and math.floor(estado.rapidas / soma * 100) or 0
  campo("rapidas", x, 11, ("%d%%  (%d)"):format(fatia, estado.rapidas),
        C.fraco, largura)

  local minutos = math.floor((os.epoch("utc") - estado.desde) / 60000)
  campo("noar", x, 13, minutos < 60
        and (minutos .. " min")
        or (math.floor(minutos / 60) .. "h " .. (minutos % 60) .. "min"),
        C.fraco, largura)

  return true
end

--- A abertura, uma vez, quando a central sobe.
function painel.abrir(monitor)
  if not monitor then return false end
  painel.paletaAntes = palette.guardar(monitor)
  painel.escala(monitor)
  palette.aplicar(monitor, palette.PALETAS.falae)
  marca.abertura(monitor, pixel, 10)
  sleep(0.6)
  return true
end

return painel
