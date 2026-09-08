--[[ marca - a logo da FALAE

  O balao amarelo com a cauda embaixo a direita, e o nome dentro.

  DUAS TECNICAS, UMA IMAGEM. O balao e desenhado em subpixel; o nome e escrito
  com caracteres de terminal por cima. Essa divisao nao e preguica - foi a
  conclusao de tentar o contrario.

  Desenhar as letras em subpixel tambem parecia obvio: resolucao dobrada, tudo
  no mesmo buffer. Mas o balao cabe em cerca de 46 pontos de largura numa tela
  de 50 colunas, e cinco letras nesse espaco dao uns 12 pontos de altura cada.
  Doze pontos bastam para uma curva parecer curva - nao para um F parecer um F.
  Testado e visto: virava ruido dentro do balao.

  O terminal ja tem uma fonte desenhada por gente, e ela e nitida porque nao
  esta sendo escalada. Entao o nome vai nela.

  O PRECO: o charset do CC vem do CP437, que tem "e" minusculo acentuado mas
  nao o "E" maiusculo. Em caixa alta o nome so pode sair FALAE. E por isso que
  a marca escrita e sempre em caixa alta no sistema inteiro - melhor um nome
  consistente sem acento do que o acento aparecer em metade das telas.
]]

local marca = {}

marca.NOME = "FALAE"

--- Desenha o balao, em pontos de subpixel.
--
-- Montado com circulos sobrepostos em vez de uma formula fechada: a forma da
-- marca e organica, mais larga em cima e puxada para a esquerda embaixo, e
-- tres circulos de raios diferentes chegam mais perto disso do que qualquer
-- elipse - alem de serem muito mais faceis de ajustar.
--
-- @param fb framebuffer de pixel.lua
-- @param cx,cy centro, em pontos
-- @param r raio de referencia
function marca.balao(fb, cx, cy, r, cor)
  fb:circulo(cx, cy - r * 0.08, r, cor, true)                    -- o corpo
  fb:circulo(cx - r * 0.18, cy + r * 0.28, r * 0.86, cor, true)  -- a barriga
  fb:circulo(cx + r * 0.30, cy - r * 0.30, r * 0.72, cor, true)  -- o ombro

  -- a cauda: desce do lado direito afinando. Feita de circulos que diminuem,
  -- porque uma linha reta afinando fica serrilhada nesta resolucao.
  local passos = math.max(4, math.floor(r * 0.7))
  for i = 0, passos do
    local t = i / passos
    fb:circulo(cx + r * (0.45 + 0.42 * t),
               cy + r * (0.40 + 0.78 * t),
               r * (0.46 * (1 - t) + 0.04), cor, true)
  end
end

--- O raio que faz a marca caber inteira numa tela.
--
-- O conjunto ocupa cerca de 2.5 raios na vertical (o ombro sobe, a cauda
-- desce) e 2.3 na horizontal. Monitor de CC costuma ser mais largo que alto,
-- entao quem manda quase sempre e a altura.
function marca.raio(fb, proporcao)
  return math.min(fb.h / 2.5, fb.w / 2.3) * (proporcao or 1)
end

function marca.centro(fb, r)
  return fb.w / 2, fb.h / 2 - r * 0.08
end

--- Desenha o balao centrado. O nome NAO entra aqui - ele e escrito depois de
-- fb:enviar(), com marca.escrever().
-- @return r, cx, cy  (ou nil se a tela e pequena demais para a marca)
function marca.desenhar(fb, cor, proporcao)
  local r = marca.raio(fb, proporcao)
  if r < 3 then return nil end
  local cx, cy = marca.centro(fb, r)
  marca.balao(fb, cx, cy, r, cor)
  return r, cx, cy
end

--- Escreve o nome dentro do balao, em caracteres.
--
-- Chame DEPOIS de fb:enviar(): o framebuffer reescreve a celula inteira, entao
-- um texto posto antes seria apagado pelo proximo envio.
--
-- @param r,cx,cy o que marca.desenhar devolveu
function marca.escrever(tela, r, cx, cy, corTexto, corBalao)
  if not r then return false end

  local colunas, linhas = tela.getSize()

  -- de ponto de subpixel para celula do terminal: 2 de largura, 3 de altura
  local col = math.floor(cx / 2) - math.floor(#marca.NOME / 2)
  local lin = math.floor((cy + r * 0.08) / 3) + 1

  if lin < 1 or lin > linhas then return false end
  col = math.max(1, math.min(col, colunas - #marca.NOME + 1))

  tela.setCursorPos(col, lin)
  tela.setBackgroundColour(corBalao)
  tela.setTextColour(corTexto)
  tela.write(marca.NOME)
  return true
end

--- A marca inteira: balao e nome.
function marca.completa(tela, pixel, corBalao, corTexto, proporcao)
  local fb = pixel.novo(tela)
  fb:limpar(colors.black)
  local r, cx, cy = marca.desenhar(fb, corBalao, proporcao)
  fb:enviar()
  marca.escrever(tela, r, cx, cy, corTexto, corBalao)
  return fb, r, cx, cy
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
    fb:enviar()
    -- o nome so no ultimo quadro: escrito durante o crescimento, ele ficaria
    -- do tamanho final dentro de um balao ainda pequeno
    if i == quadros then
      marca.escrever(tela, r, cx, cy, colors.black, colors.yellow)
    end
    sleep(0.04)
  end
  return fb
end

return marca
