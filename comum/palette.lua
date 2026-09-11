--[[ palette - paletas nomeadas e transicao suave entre elas

  As 16 cores do CC sao redefiniveis com term.setPaletteColour, e a mudanca
  vale para a TELA INTEIRA. E o que permite fazer o amanhecer sem redesenhar
  nada: o sol e desenhado uma vez e so as cores mudam.

  CUIDADO: a paleta e global e persiste depois que o programa termina. Se
  ninguem restaurar, o shell, o edit e todo o resto ficam com as cores erradas
  ate o computador reiniciar. Por isso:

    local antes = palette.guardar(tela)
    ... mexe a vontade ...
    palette.restaurar(tela, antes)      -- em pcall, em TODO caminho de saida

  Use palette.com(tela, funcao) quando puder: ele faz isso sozinho.
]]

local palette = {}

--- Cores que as paletas deste sistema mexem. As outras ficam como estao,
-- para nao estragar a aparencia de outros programas que rodem depois.
--
-- orange e a cor da marca da FALAE (ate a v2 era yellow; trocou de lado, mas
-- os dois continuam na lista porque yellow virou a cor de "aviso" no resto do
-- projeto - conferir o proprio tom dele ainda importa). brown fica na lista
-- porque guarda a versao apagada da marca (a coluna sem foco); se ficasse de
-- fora, restaurar() nao o devolveria ao normal e o shell ficaria com um
-- marrom errado ate reiniciar.
local MEXIDAS = {
  colors.white, colors.orange, colors.yellow, colors.red,
  colors.gray, colors.lightGray, colors.cyan, colors.blue,
  colors.lime, colors.black, colors.brown,
}

palette.MEXIDAS = MEXIDAS

--- As cores da FALAE.
--
-- Os valores vieram da logo: o laranja do balao e o branco do letreiro. brown
-- e a versao sem foco do laranja - a mesma relacao que a coluna desfocada de
-- um arranjo de dois monitores ja usava.
--
-- "apagada" e a mesma paleta com a marca dessaturada. Serve para a transicao
-- de abertura e para o momento em que a central perde o modem: a FALAE fica
-- cinza quando esta fora do ar, o que se le de longe, do outro lado da sala.
palette.PALETAS = {
  falae = {
    [colors.orange]    = { 0.95, 0.60, 0.15 },   -- o laranja do balao
    [colors.yellow]    = { 0.99, 0.79, 0.23 },   -- so "aviso" agora - continua vivo
    [colors.brown]     = { 0.55, 0.44, 0.14 },   -- a marca sem foco
    [colors.white]     = { 0.97, 0.97, 0.96 },
    [colors.lightGray] = { 0.62, 0.62, 0.60 },
    [colors.gray]      = { 0.28, 0.28, 0.29 },
    [colors.black]     = { 0.06, 0.06, 0.07 },
    [colors.lime]      = { 0.45, 0.80, 0.35 },
    [colors.red]       = { 0.85, 0.32, 0.28 },
    [colors.cyan]      = { 0.35, 0.62, 0.70 },
    [colors.blue]      = { 0.20, 0.35, 0.80 },
  },
  apagada = {
    [colors.yellow]    = { 0.42, 0.40, 0.34 },
    [colors.orange]    = { 0.38, 0.33, 0.26 },
    [colors.brown]     = { 0.26, 0.24, 0.20 },
    [colors.white]     = { 0.62, 0.62, 0.62 },
    [colors.lightGray] = { 0.40, 0.40, 0.40 },
    [colors.gray]      = { 0.20, 0.20, 0.21 },
    [colors.black]     = { 0.05, 0.05, 0.06 },
    [colors.lime]      = { 0.35, 0.45, 0.33 },
    [colors.red]       = { 0.45, 0.30, 0.28 },
    [colors.cyan]      = { 0.30, 0.38, 0.42 },
    [colors.blue]      = { 0.22, 0.26, 0.40 },
  },
}

--- A tela aceita mexer na paleta?
local function podeMexer(tela)
  if not tela then return false end
  if type(tela.setPaletteColour) ~= "function" then return false end
  if tela.isColour and not tela.isColour() then return false end
  return true
end
palette.podeMexer = podeMexer

--- Le as cores atuais da tela para poder devolver do jeito que estavam.
-- Devolve nil se a tela nao mexe em paleta - e nil e aceito por restaurar().
function palette.guardar(tela)
  if not podeMexer(tela) then return nil end
  local estado = {}
  for _, cor in ipairs(MEXIDAS) do
    local ok, r, g, b = pcall(tela.getPaletteColour, cor)
    if ok and type(r) == "number" then estado[cor] = { r, g, b } end
  end
  return estado
end

--- Devolve as cores exatamente como estavam quando guardar() rodou.
-- Nao assume o padrao do CC: outro programa pode ter mexido antes de nos.
function palette.restaurar(tela, estado)
  if not estado or not podeMexer(tela) then return end
  for cor, rgb in pairs(estado) do
    pcall(tela.setPaletteColour, cor, rgb[1], rgb[2], rgb[3])
  end
end

function palette.aplicar(tela, paleta)
  if not paleta or not podeMexer(tela) then return end
  for cor, rgb in pairs(paleta) do
    pcall(tela.setPaletteColour, cor, rgb[1], rgb[2], rgb[3])
  end
end

--- Interpola duas paletas. t de 0 (de) a 1 (para).
function palette.tween(tela, de, para, t)
  if not podeMexer(tela) then return end
  t = math.max(0, math.min(1, t or 0))
  for cor, a in pairs(de) do
    local b = para[cor]
    if b then
      pcall(tela.setPaletteColour, cor,
            a[1] + (b[1] - a[1]) * t,
            a[2] + (b[2] - a[2]) * t,
            a[3] + (b[3] - a[3]) * t)
    end
  end
end

--- Roda uma funcao com a paleta livre e devolve as cores no fim, aconteca o
-- que acontecer - inclusive erro ou Ctrl+T. Este e o jeito recomendado.
-- Devolve os mesmos valores de pcall: ok, resultado-ou-erro.
function palette.com(tela, fn)
  local antes = palette.guardar(tela)
  local ok, r = pcall(fn)
  palette.restaurar(tela, antes)
  return ok, r
end

return palette
