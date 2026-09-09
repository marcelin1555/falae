--[[ marca - a logo da FALAE

  O balao amarelo com a cauda, e FALAE em branco subindo na diagonal.

  POR QUE POLIGONO E NAO RISCO. A primeira versao desenhava as letras com
  linhas de um ponto de espessura e viravam ruido dentro do balao: a marca e
  pesada, de traco grosso, e um risco fino nao e uma letra magra - e um
  rabisco. Aqui cada letra e um conjunto de POLIGONOS PREENCHIDOS, entao a
  espessura acompanha o tamanho e a letra continua sendo letra em qualquer
  escala.

  A DIAGONAL. Na marca o nome sobe da esquerda para a direita, acompanhando a
  barriga do balao. Cada letra e girada e assentada um pouco mais alta que a
  anterior. Sem isso o nome fica reto no meio de uma forma redonda, e some
  dentro dela.

  QUANDO NAO CABE. Abaixo de um tamanho, letra desenhada perde para letra de
  fonte: o terminal tem uma fonte feita por gente, nitida porque nao esta sendo
  escalada. Entao a marca tem duas versoes e escolhe sozinha - a desenhada
  quando ha espaco, o nome em caracteres quando nao ha. Ver marca.completa.

  O charset do CC vem do CP437, que tem "e" minusculo acentuado mas nao o "E"
  maiusculo: na versao em caracteres o nome so pode sair FALAE. Na desenhada o
  circunflexo existe, porque ali nada depende de fonte.
]]

local marca = {}

marca.NOME = "FALAE"

-- Abaixo disto o letreiro desenhado fica pior que o escrito. Medido olhando os
-- tres tamanhos lado a lado: com 12 e 10 pontos o nome se le; com 9 o travessao
-- do A ja come o vao e as duas letras viram a mesma mancha.
marca.MINIMO_LETRA = 10

-- Inclinacao do nome. Mais que isto e a subida come a altura util dentro do
-- balao e a letra tem que encolher para caber.
marca.GRAUS = -11

-- ------------------------------------------------------------- preenchimento

--- Preenche um poligono por varredura de linhas.
--
-- E o que permite letra com peso: cada traco e uma area, nao um risco. Em
-- resolucao de subpixel a diferenca entre os dois e a diferenca entre ler e
-- nao ler.
function marca.poligono(fb, pontos, cor)
  local minY, maxY = math.huge, -math.huge
  for _, p in ipairs(pontos) do
    if p[2] < minY then minY = p[2] end
    if p[2] > maxY then maxY = p[2] end
  end

  for y = math.floor(minY + 0.5), math.floor(maxY + 0.5) do
    local cortes = {}
    local n = #pontos
    for i = 1, n do
      local a = pontos[i]
      local b = pontos[i % n + 1]
      local ya, yb = a[2], b[2]
      -- aresta que cruza esta linha: a comparacao assimetrica evita contar o
      -- vertice duas vezes, que deixaria buraco no preenchimento
      if (ya <= y and yb > y) or (yb <= y and ya > y) then
        local t = (y - ya) / (yb - ya)
        cortes[#cortes + 1] = a[1] + t * (b[1] - a[1])
      end
    end
    table.sort(cortes)
    for i = 1, #cortes - 1, 2 do
      for x = math.floor(cortes[i] + 0.5), math.floor(cortes[i + 1] + 0.5) do
        fb:ponto(x, y, cor)
      end
    end
  end
end

-- ------------------------------------------------------------------- balao

--- So o corpo do balao, sem a cauda.
--
-- Montado com circulos sobrepostos em vez de uma formula fechada: a forma da
-- marca e organica - larga em cima, puxada para a esquerda embaixo, com o
-- ombro direito mais cheio. Circulos de raios diferentes chegam mais perto
-- disso do que qualquer elipse, e sao muito mais faceis de ajustar.
--
--
-- Separado da cauda porque na abertura ela CAI depois, no momento em que a
-- mensagem e enviada - e o gesto que amarra a animacao inteira. Quem so quer a
-- marca pronta chama marca.balao, que junta os dois.
function marca.corpo(fb, cx, cy, r, cor)
  fb:circulo(cx, cy - r * 0.10, r, cor, true)                    -- o corpo
  fb:circulo(cx - r * 0.20, cy + r * 0.26, r * 0.88, cor, true)  -- a barriga
  fb:circulo(cx + r * 0.32, cy - r * 0.28, r * 0.74, cor, true)  -- o ombro
  fb:circulo(cx - r * 0.30, cy - r * 0.34, r * 0.66, cor, true)  -- o alto
end

--- A cauda, que desce do lado direito e afina ate a ponta.
--
-- Circulos que diminuem, e nao um triangulo: em subpixel a ponta de um
-- triangulo fica serrilhada, e a da marca e arredondada.
--
-- @param quanto 0 a 1 - quanto da cauda ja desceu. Em 0 nao ha cauda, em 1 ela
--        esta inteira. E o que permite a abertura solta-la no momento do envio.
function marca.cauda(fb, cx, cy, r, cor, quanto)
  quanto = (quanto == nil) and 1 or quanto
  if quanto <= 0 then return end
  if quanto > 1 then quanto = 1 end

  local passos = math.max(6, math.floor(r))
  local ate = math.floor(passos * quanto)

  for i = 0, ate do
    local t = i / passos
    -- a cauda curva um pouco para fora antes de descer, como na marca
    local curva = math.sin(t * 3.14159) * 0.10
    fb:circulo(cx + r * (0.46 + 0.40 * t + curva),
               cy + r * (0.38 + 0.82 * t),
               r * (0.48 * (1 - t) + 0.05), cor, true)
  end
end

--- O balao inteiro: corpo e cauda.
function marca.balao(fb, cx, cy, r, cor)
  marca.corpo(fb, cx, cy, r, cor)
  marca.cauda(fb, cx, cy, r, cor, 1)
end

-- ------------------------------------------------------------------ letras

-- Cada letra e uma lista de poligonos num quadrado 0..1, com y=0 no topo.
-- Proporcoes de letra pesada: haste larga, contraforma pequena.
local LETRAS = {
  F = {
    { {0,0}, {0.32,0}, {0.32,1}, {0,1} },                    -- haste
    { {0,0}, {0.92,0}, {0.92,0.23}, {0,0.23} },              -- braco de cima
    { {0,0.40}, {0.72,0.40}, {0.72,0.61}, {0,0.61} },        -- braco do meio
  },
  A = {
    { {0,1}, {0.25,1}, {0.57,0}, {0.43,0} },                 -- perna esquerda
    { {0.75,1}, {1,1}, {0.57,0}, {0.43,0} },                 -- perna direita
    { {0.19,0.60}, {0.81,0.60}, {0.81,0.79}, {0.19,0.79} },  -- travessao
  },
  L = {
    { {0,0}, {0.32,0}, {0.32,1}, {0,1} },
    { {0,0.77}, {0.88,0.77}, {0.88,1}, {0,1} },
  },
  E = {
    { {0,0}, {0.32,0}, {0.32,1}, {0,1} },
    { {0,0}, {0.92,0}, {0.92,0.23}, {0,0.23} },
    { {0,0.39}, {0.76,0.39}, {0.76,0.59}, {0,0.59} },
    { {0,0.77}, {0.92,0.77}, {0.92,1}, {0,1} },
  },
}
marca.LETRAS = LETRAS

-- O circunflexo, acima da letra (y negativo). E o que faz a marca ser FALAE
-- com acento em vez de FALAE sem - e o unico lugar do sistema onde ele cabe,
-- porque aqui nada depende da fonte do terminal.
local CIRCUNFLEXO = {
  { {0.06,-0.24}, {0.46,-0.60}, {0.86,-0.24}, {0.66,-0.24}, {0.46,-0.42}, {0.26,-0.24} },
}

--- Gira um ponto em torno de (ox, oy).
local function girar(x, y, cos, sen, ox, oy)
  local dx, dy = x - ox, y - oy
  return ox + dx * cos - dy * sen, oy + dx * sen + dy * cos
end

--- Desenha uma forma (lista de poligonos em 0..1) posicionada e girada.
local function forma(fb, polis, x, y, w, h, cos, sen, cor)
  for _, poli in ipairs(polis) do
    local pontos = {}
    for i, p in ipairs(poli) do
      local px = x + p[1] * w
      local py = y + p[2] * h
      -- gira em torno do pe da letra: e o que faz a linha de base subir junto
      local gx, gy = girar(px, py, cos, sen, x, y + h)
      pontos[i] = { gx, gy }
    end
    marca.poligono(fb, pontos, cor)
  end
end

--- FALAE subindo na diagonal.
--
-- @param x,y canto de baixo a esquerda da primeira letra
-- @param altura altura de uma letra, em pontos
-- @param graus inclinacao do conjunto
-- @param quantas quantas letras desenhar, do comeco. nil desenha as cinco - e
--        o que permite a abertura escrever o nome uma letra por vez.
-- @param cursor true poe um bloco na vaga da PROXIMA letra, que e onde ele
--        estaria se alguem estivesse mesmo digitando
function marca.letreiro(fb, x, y, altura, cor, graus, quantas, cursor)
  graus = graus or marca.GRAUS
  local rad = graus * 3.14159265 / 180
  local cos, sen = math.cos(rad), math.sin(rad)

  local largura = altura * 0.66
  -- kerning apertado, como na marca: as letras quase se encostam. Espaco
  -- folgado obrigaria a diminuir a letra para o conjunto caber, e em subpixel
  -- quem decide se da para ler e o tamanho da letra, nao o ar entre elas.
  local passo = largura * 1.18

  local nomes = { "F", "A", "L", "A", "E" }
  quantas = math.max(0, math.min(quantas or #nomes, #nomes))

  if cursor then
    local avanco = quantas * passo
    forma(fb, { { {0.06, 0.02}, {0.44, 0.02}, {0.44, 1}, {0.06, 1} } },
          x + avanco * cos, y + avanco * sen - altura,
          largura, altura, cos, sen, cor)
  end

  for i, letra in ipairs(nomes) do
    if i > quantas then break end
    -- a diagonal sai da propria rotacao: cada letra avanca ao longo do eixo
    -- girado, entao a linha de base do conjunto e uma reta inclinada
    local avanco = (i - 1) * passo
    local lx = x + avanco * cos
    local ly = y + avanco * sen

    forma(fb, LETRAS[letra], lx, ly - altura, largura, altura, cos, sen, cor)

    if i == 5 then
      forma(fb, CIRCUNFLEXO, lx, ly - altura, largura, altura, cos, sen, cor)
    end
  end

  return #nomes * passo
end

--- O retangulo que o letreiro realmente ocupa.
--
-- Calculado varrendo os cantos de cada letra ja girada, e nao por formula
-- aproximada. Com o nome inclinado, a conta "largura vezes cosseno" erra: o
-- topo de cada letra desloca para um lado e a base para o outro, e o
-- circunflexo sobe acima de tudo. Errar aqui poe o F para fora do balao, que
-- foi exatamente o que aconteceu na primeira tentativa.
--
-- @return largura, altura, dx, dy
--         dx,dy = do ponto de ancoragem ate o canto superior esquerdo
function marca.medida(altura, graus)
  graus = graus or marca.GRAUS
  local rad = graus * 3.14159265 / 180
  local cos, sen = math.cos(rad), math.sin(rad)

  local largura = altura * 0.66
  local passo = largura * 1.18

  local minX, maxX = math.huge, -math.huge
  local minY, maxY = math.huge, -math.huge

  for i = 1, 5 do
    local avanco = (i - 1) * passo
    local lx, ly = avanco * cos, avanco * sen
    -- o topo da caixa da letra; o E leva o circunflexo, que sobe mais
    local topo = (i == 5) and -1.60 * altura or -altura
    for _, canto in ipairs({ {0, 0}, {largura, 0}, {0, topo}, {largura, topo} }) do
      local dx, dy = canto[1], canto[2]
      local gx = lx + dx * cos - dy * sen
      local gy = ly + dx * sen + dy * cos
      if gx < minX then minX = gx end
      if gx > maxX then maxX = gx end
      if gy < minY then minY = gy end
      if gy > maxY then maxY = gy end
    end
  end

  return maxX - minX, maxY - minY, minX, minY
end

-- ---------------------------------------------------------------- composicao

--- O raio que faz a marca caber inteira numa area.
--
-- O conjunto ocupa cerca de 2.5 raios na vertical (o alto sobe, a cauda desce)
-- e 2.3 na horizontal.
function marca.raio(fb, proporcao)
  return math.min(fb.h / 2.4, fb.w / 2.25) * (proporcao or 1)
end

--- O raio que a marca teria numa tela de tantas colunas e linhas.
--
-- Existe para quem precisa saber onde o balao termina ANTES de desenhar: a
-- abertura decide por aqui se o diagnostico cabe ao lado. Refazer a formula la
-- seria a mesma conta em dois lugares, e um dia as duas discordariam.
function marca.raioDeTela(colunas, linhas)
  return marca.raio({ w = colunas * 2, h = linhas * 3 })
end

function marca.centro(fb, r)
  return fb.w / 2, fb.h / 2 - r * 0.08
end

--- Desenha SO O CORPO centrado, sem a cauda e sem o nome.
--
-- E o que a abertura usa nos primeiros atos: la a cauda so aparece no momento
-- do envio, e o corpo precisa poder crescer sozinho.
-- @return r, cx, cy   ou nil se a area e pequena demais
function marca.desenharCorpo(fb, cor, proporcao)
  local r = marca.raio(fb, proporcao)
  if r < 3 then return nil end
  local cx, cy = marca.centro(fb, r)
  marca.corpo(fb, cx, cy, r, cor)
  return r, cx, cy
end

--- Desenha o balao centrado, sem o nome.
-- @return r, cx, cy   ou nil se a area e pequena demais
function marca.desenhar(fb, cor, proporcao)
  local r = marca.raio(fb, proporcao)
  if r < 3 then return nil end
  local cx, cy = marca.centro(fb, r)
  marca.balao(fb, cx, cy, r, cor)
  return r, cx, cy
end

--- A maior altura de letra que cabe dentro de um balao de raio r.
--
-- Procura por tentativa em vez de inverter a formula: a medida do letreiro
-- depende do angulo e do circunflexo de um jeito que nao inverte bonito, e
-- errar para mais poe letra fora do balao.
--
-- A area util nao e o diametro: o letreiro fica na barriga, onde o balao ja
-- esta estreitando, e precisa de margem para nao encostar na borda.
function marca.alturaLetra(r)
  local larguraUtil = r * 1.62
  local alturaUtil  = r * 1.05

  local melhor = 0
  for altura = 6, 40, 0.5 do
    local w, h = marca.medida(altura)
    if w <= larguraUtil and h <= alturaUtil then melhor = altura else break end
  end
  return melhor
end

--- Desenha o nome dentro do balao, na diagonal.
-- @param quantas quantas letras, do comeco (nil = todas)
-- @param cursor poe o bloco de cursor na vaga seguinte
-- @return true se coube desenhado
function marca.nomeDesenhado(fb, r, cx, cy, cor, quantas, cursor)
  local altura = marca.alturaLetra(r)
  if altura < marca.MINIMO_LETRA then return false end

  local w, h, dx, dy = marca.medida(altura)

  -- Centro do letreiro onde ele fica na marca: um pouco abaixo e a esquerda do
  -- centro do balao, que e onde a barriga e mais larga.
  local alvoX = cx - r * 0.02
  local alvoY = cy + r * 0.04

  -- dx,dy vao do ponto de ancoragem ao canto do retangulo, entao a ancora sai
  -- do centro desejado menos meio retangulo, menos o deslocamento
  local x = alvoX - w / 2 - dx
  local y = alvoY - h / 2 - dy

  marca.letreiro(fb, x, y, altura, cor, nil, quantas, cursor)
  return true
end

--- Quantas letras o nome tem. A abertura precisa saber para cronometrar a
-- digitacao sem repetir a lista de letras em outro arquivo.
function marca.quantasLetras()
  return #marca.NOME
end

--- O nome em caracteres, para quando o desenhado nao cabe.
--
-- Chame DEPOIS de fb:enviar(): o framebuffer reescreve a celula inteira, entao
-- um texto posto antes seria apagado pelo proximo envio.
-- @param quantas quantas letras do nome escrever (nil = todas). Existe para a
--        abertura poder "digitar" tambem nas telas em que o nome nao cabe
--        desenhado - o gesto e o mesmo, muda so quem desenha a letra.
-- @param cursor acrescenta um bloco depois da ultima letra
function marca.escrever(tela, r, cx, cy, corTexto, corBalao, quantas, cursor)
  if not r then return false end
  local colunas, linhas = tela.getSize()

  -- de ponto de subpixel para celula do terminal: 2 de largura, 3 de altura
  local col = math.floor(cx / 2) - math.floor(#marca.NOME / 2)
  local lin = math.floor((cy + r * 0.08) / 3) + 1
  if lin < 1 or lin > linhas then return false end
  col = math.max(1, math.min(col, colunas - #marca.NOME + 1))

  -- O texto fica sempre com a largura do nome inteiro, preenchido com espaco.
  -- Escrever so "FA" deixaria as letras seguintes do quadro anterior na tela,
  -- e o nome apareceria e desapareceria em pedacos.
  local texto = marca.NOME:sub(1, quantas or #marca.NOME)
  if cursor and #texto < #marca.NOME then texto = texto .. "_" end
  texto = texto .. string.rep(" ", #marca.NOME - #texto)

  tela.setCursorPos(col, lin)
  tela.setBackgroundColour(corBalao)
  tela.setTextColour(corTexto)
  tela.write(texto)
  return true
end

--- A marca inteira. Escolhe sozinha entre o nome desenhado e o escrito.
function marca.completa(tela, pixel, corBalao, corTexto, proporcao)
  local fb = pixel.novo(tela)
  fb:limpar(colors.black)

  local r, cx, cy = marca.desenhar(fb, corBalao, proporcao)
  if not r then
    fb:enviar()
    return fb, nil
  end

  local desenhado = marca.nomeDesenhado(fb, r, cx, cy, corTexto)
  fb:enviar()

  if not desenhado then
    marca.escrever(tela, r, cx, cy, corTexto, corBalao)
  end
  return fb, r, cx, cy, desenhado
end

--- A abertura: o balao cresce e o nome assenta.
--
-- Roda UMA vez, no boot, e nunca em laco. Animacao em laco num computador do
-- CC gasta o tempo do pool de threads que TODOS os computadores do mundo
-- dividem - e a central tem coisa melhor a fazer com ele.
--
-- @param quadros passos da animacao; 0 desenha direto, sem animar
function marca.abertura(tela, pixel, quadros)
  quadros = quadros or 10
  if quadros <= 0 then
    return marca.completa(tela, pixel, colors.yellow, colors.black)
  end

  local fb = pixel.novo(tela)
  for i = 1, quadros do
    local t = i / quadros
    -- desacelera no fim: cresce rapido e assenta devagar
    local suave = 1 - (1 - t) * (1 - t)
    fb:limpar(colors.black)
    local r, cx, cy = marca.desenhar(fb, colors.yellow, suave)

    -- o nome so no ultimo quadro: escrito durante o crescimento, ele apareceria
    -- do tamanho final dentro de um balao ainda pequeno
    local desenhado = false
    if i == quadros and r then
      desenhado = marca.nomeDesenhado(fb, r, cx, cy, colors.black)
    end
    fb:enviar()
    if i == quadros and r and not desenhado then
      marca.escrever(tela, r, cx, cy, colors.black, colors.yellow)
    end
    sleep(0.04)
  end
  return fb
end

return marca
