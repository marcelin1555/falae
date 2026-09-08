--[[ grafico - barras em subpixel

  Recebe uma serie de numeros e um retangulo, e desenha barras com escala
  automatica. Nao sabe o que os numeros significam - por isso serve para o
  trafego de recados hoje e para qualquer outra serie amanha.

  MORA SEPARADO DO PAINEL por dois motivos. E a unica peca do painel que nao
  fala de telefonia, e escala automatica e onde erro de arredondamento se
  esconde: uma barra que estoura o retangulo por um ponto so aparece com a
  serie certa, num dia qualquer, e escreve por cima do que estiver em volta.
  Separado, ele tem teste proprio com as series que costumam quebrar - vazia,
  toda zero, um valor so, valor gigante no meio de pequenos.

  A ESCALA COMECA NO ZERO, sempre. Grafico de barras com base cortada mente
  sobre a proporcao entre as barras, e este aqui existe justamente para
  responder "hoje foi mais movimentado que ontem?".
]]

local grafico = {}

--- Desenha as barras.
--
-- @param fb framebuffer de pixel.lua
-- @param x,y canto superior esquerdo, em pontos de subpixel
-- @param w,h tamanho, em pontos
-- @param serie lista de numeros, do mais antigo para o mais recente
-- @param cor cor das barras
-- @param opcoes { pico = teto fixo, corUltima = cor da barra do fim }
-- @return o pico usado na escala
function grafico.barras(fb, x, y, w, h, serie, cor, opcoes)
  opcoes = opcoes or {}
  local n = #serie
  if n == 0 or w < 1 or h < 1 then return 0 end

  local pico = opcoes.pico
  if not pico then
    pico = 0
    for _, v in ipairs(serie) do if v > pico then pico = v end end
  end

  -- Serie toda zero: desenha a linha de base e sai. Sem isto a divisao por
  -- pico estoura, e "nao houve nada" e um resultado legitimo - a central passa
  -- a madrugada inteira assim.
  if pico <= 0 then
    for px = x, x + w - 1 do fb:ponto(px, y + h - 1, cor) end
    return 0
  end

  -- Quando nao cabe uma barra por valor, mostra as ULTIMAS - e um grafico de
  -- tempo, e a hora que esta correndo importa mais que a de doze horas atras.
  -- Sem este corte, cada barra ocuparia o minimo de um ponto e o conjunto
  -- passaria da largura, escrevendo por cima do que estiver ao lado.
  local primeira = 1
  if n > w then
    primeira = n - w + 1
    n = w
  end

  -- Largura da barra pela divisao inteira, com o resto virando espaco entre
  -- elas. Distribuir o resto dentro das barras deixaria umas mais gordas que
  -- as outras, e em barra fina isso se ve.
  local largura = math.max(1, math.floor(w / n))
  local usado = largura * n
  local folga = math.floor((w - usado) / 2)

  for pos = 1, n do
    local v = serie[primeira + pos - 1]
    if v > 0 then
      local altura = math.floor((v / pico) * h + 0.5)
      if altura < 1 then altura = 1 end        -- houve algo: tem que aparecer
      if altura > h then altura = h end        -- e nunca passar do retangulo

      local bx = x + folga + (pos - 1) * largura
      local by = y + h - altura
      local corBarra = (pos == n and opcoes.corUltima) or cor

      -- deixa um ponto de respiro entre barras quando elas sao largas
      local grossura = largura > 2 and (largura - 1) or largura
      fb:retangulo(bx, by, grossura, altura, corBarra, true)
    end
  end

  return pico
end

--- Quantos pontos de altura a barra de <valor> teria. Serve ao teste e a quem
-- precise alinhar um rotulo com o topo de uma barra.
function grafico.altura(valor, pico, h)
  if pico <= 0 or valor <= 0 then return 0 end
  local altura = math.floor((valor / pico) * h + 0.5)
  if altura < 1 then altura = 1 end
  if altura > h then altura = h end
  return altura
end

--- Um numero curto para o eixo: 1200 vira "1.2k".
--
-- Existe porque o eixo tem tres ou quatro colunas de largura, e "1200" nao
-- cabe do lado de um grafico de 12 colunas.
function grafico.curto(v)
  v = math.floor(tonumber(v) or 0)
  if v < 1000 then return tostring(v) end
  if v < 10000 then return ("%.1fk"):format(v / 1000):gsub("%.0k", "k") end
  return math.floor(v / 1000) .. "k"
end

return grafico
