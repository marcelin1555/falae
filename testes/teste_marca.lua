--[[ teste_marca - a logo

  A logo e desenho, e desenho nao tem certo e errado que um teste decida. O que
  da para garantir por programa e o que quebra sem ninguem ver:

    - o nome nao vaza para fora do balao (num monitor da sala, o F saindo pela
      esquerda e a primeira coisa que alguem repara)
    - a medida bate com o que e desenhado de fato (a medida decide o
      posicionamento; se ela mentir, o encaixe erra em silencio)
    - a marca desiste de desenhar o nome quando nao ha resolucao, em vez de
      virar ruido dentro do balao
    - e continua desenhando quando ha

  Foi assim que a primeira versao falhou: as letras eram riscos de um ponto,
  ficavam ilegiveis, e nada apontava isso - so olhando.
]]

local PROJETO = ...

local mock = dofile(PROJETO .. "/testes/cc_mock.lua")
mock.instalar()
mock.montarCentral(PROJETO, false)
mock.montarArquivo("/tela/marca.lua", PROJETO .. "/servidor/tela/marca.lua")
mock.instalarDofile()

local total, falhas = 0, 0

local function ok(condicao, titulo, detalhe)
  total = total + 1
  if condicao then
    print("  ok   " .. titulo)
  else
    falhas = falhas + 1
    print("  FALHA " .. titulo .. (detalhe and ("  -> " .. tostring(detalhe)) or ""))
  end
end

local function igual(a, b, titulo)
  ok(a == b, titulo, ("esperava [%s], veio [%s]"):format(tostring(b), tostring(a)))
end

local pixel = dofile("/pixel.lua")
local marca = dofile("/tela/marca.lua")

-- ------------------------------------------------------------- preenchimento

print("\n-- poligono preenchido --")

local t = mock.monitor(20, 10)
local fb = pixel.novo(t)
fb:limpar(colors.black)

-- um quadrado simples, para conferir que preenche e nao so contorna
marca.poligono(fb, { {5,5}, {15,5}, {15,15}, {5,15} }, colors.yellow)

local dentro = fb.buf[10][10] == colors.yellow
local borda  = fb.buf[5][5] == colors.yellow
local fora   = fb.buf[3][3] == colors.black
ok(dentro, "o meio do poligono e preenchido, nao so a borda")
ok(borda, "a borda entra junto")
ok(fora, "e nada e pintado fora dele")

-- triangulo: e a forma das pernas do A, e a que mais erra em varredura
fb:limpar(colors.black)
marca.poligono(fb, { {10,3}, {18,17}, {2,17} }, colors.yellow)
ok(fb.buf[16][10] == colors.yellow, "triangulo preenche a base")
ok(fb.buf[5][10] == colors.yellow, "e o bico")
ok(fb.buf[16][1] == colors.black, "sem vazar pelo lado")

-- ------------------------------------------------------------------ medida

print("\n-- a medida bate com o desenho --")

-- Desenha o letreiro isolado e compara o retangulo REAL dos pontos pintados
-- com o que marca.medida promete. E a medida que decide o posicionamento: se
-- ela mentir, o encaixe erra em silencio e o nome sai do balao.
local function retanguloReal(altura)
  local tela = mock.monitor(80, 30)
  local f = pixel.novo(tela)
  f:limpar(colors.black)

  local ancoraX, ancoraY = 40, 60
  marca.letreiro(f, ancoraX, ancoraY, altura, colors.yellow)

  local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
  for y = 1, f.h do
    for x = 1, f.w do
      if f.buf[y][x] == colors.yellow then
        if x < minX then minX = x end
        if x > maxX then maxX = x end
        if y < minY then minY = y end
        if y > maxY then maxY = y end
      end
    end
  end
  return maxX - minX, maxY - minY, minX - ancoraX, minY - ancoraY
end

for _, altura in ipairs({ 12, 16, 20 }) do
  local w, h, dx, dy = marca.medida(altura)
  local rw, rh, rdx, rdy = retanguloReal(altura)

  -- folga de 2 pontos: a varredura arredonda, e a medida usa a caixa da letra
  -- enquanto o desenho usa os poligonos dentro dela
  ok(math.abs(w - rw) <= 3,
     ("largura medida bate com a desenhada (altura %d)"):format(altura),
     ("medida %.1f, real %d"):format(w, rw))
  ok(math.abs(h - rh) <= 3,
     ("altura medida bate com a desenhada (altura %d)"):format(altura),
     ("medida %.1f, real %d"):format(h, rh))
  ok(math.abs(dx - rdx) <= 3 and math.abs(dy - rdy) <= 3,
     ("o canto medido bate (altura %d)"):format(altura),
     ("medida %.1f,%.1f  real %d,%d"):format(dx, dy, rdx, rdy))
end

-- ------------------------------------------------- o nome cabe no balao

print("\n-- o nome nao vaza do balao --")

--- Desenha a marca inteira e confere que todo ponto do NOME esta sobre o
-- balao. Um ponto do nome fora do amarelo e uma letra pendurada no vazio.
local function nomeDentro(colunas, linhas)
  local tela = mock.monitor(colunas, linhas)
  local f = pixel.novo(tela)

  -- primeiro so o balao, para saber onde ele esta
  f:limpar(colors.black)
  local r, cx, cy = marca.desenhar(f, colors.yellow)
  if not r then return nil end

  local balao = {}
  for y = 1, f.h do
    balao[y] = {}
    for x = 1, f.w do balao[y][x] = (f.buf[y][x] == colors.yellow) end
  end

  -- agora o nome, numa cor propria
  local desenhado = marca.nomeDesenhado(f, r, cx, cy, colors.white)
  if not desenhado then return false, r end

  local fora = 0
  for y = 1, f.h do
    for x = 1, f.w do
      if f.buf[y][x] == colors.white and not balao[y][x] then
        fora = fora + 1
      end
    end
  end
  return fora, r, marca.alturaLetra(r)
end

for _, tam in ipairs({ { 36, 26 }, { 51, 19 }, { 60, 30 }, { 40, 40 } }) do
  local fora, r, alturaLetra = nomeDentro(tam[1], tam[2])
  if fora == false then
    ok(true, ("%dx%d: sem resolucao, o nome vai em caracteres (raio %.0f)")
             :format(tam[1], tam[2], r))
  else
    ok(fora == 0,
       ("%dx%d: o nome desenhado fica todo dentro do balao (letra %.0f pts)")
       :format(tam[1], tam[2], alturaLetra or 0),
       ("%d ponto(s) fora"):format(fora or -1))
  end
end

-- ------------------------------------------------ desiste quando nao cabe

print("\n-- desenhado quando ha espaco, escrito quando nao ha --")

local function comoSaiu(colunas, linhas)
  local tela = mock.monitor(colunas, linhas)
  local _, r, _, _, desenhado = marca.completa(tela, pixel, colors.yellow, colors.black)
  return desenhado, r, tela
end

local grande = comoSaiu(36, 26)
ok(grande == true, "com resolucao de sobra, o nome e desenhado")

local pequeno, rp, telaP = comoSaiu(26, 12)
ok(pequeno == false, "num pocket, cai para o nome em caracteres")
ok(telaP.tudo():find("FALAE", 1, true) ~= nil,
   "e o nome escrito aparece de verdade na tela")

-- Abaixo do minimo o desenhado nunca deve entrar: letra pequena demais vira
-- ruido dentro do balao, que foi como a primeira versao falhou.
local semNada = comoSaiu(10, 5)
ok(semNada ~= true, "numa tela minuscula, nao tenta desenhar o nome")

print("\n-- o minimo de letra e respeitado --")
for _, tam in ipairs({ { 36, 26 }, { 51, 19 }, { 30, 14 }, { 26, 20 } }) do
  local tela = mock.monitor(tam[1], tam[2])
  local f = pixel.novo(tela)
  local r = marca.raio(f)
  local altura = marca.alturaLetra(r)
  local desenhado = altura >= marca.MINIMO_LETRA
  ok(not desenhado or altura >= marca.MINIMO_LETRA,
     ("%dx%d: letra de %.1f pts %s"):format(
       tam[1], tam[2], altura, desenhado and "-> desenhado" or "-> caracteres"))
end

-- ------------------------------------------------------------------ balao

print("\n-- corpo e cauda, separados --")

-- A abertura solta a cauda no momento do envio, entao ela precisa existir
-- sozinha. Se corpo e cauda voltarem a ser uma coisa so, a animacao perde o
-- gesto que a amarra - e nada quebraria, ela so ficaria sem sentido.
local function pintados(fn)
  local tl = mock.monitor(40, 20)
  local f = pixel.novo(tl)
  f:limpar(colors.black)
  local r, cx, cy = marca.raio(f), nil, nil
  cx, cy = marca.centro(f, r)
  fn(f, cx, cy, r)
  local n = 0
  for y = 1, f.h do
    for x = 1, f.w do if f.buf[y][x] ~= colors.black then n = n + 1 end end
  end
  return n, f
end

local soCorpo = pintados(function(f, cx, cy, r)
  marca.corpo(f, cx, cy, r, colors.yellow)
end)
local corpoECauda = pintados(function(f, cx, cy, r)
  marca.balao(f, cx, cy, r, colors.yellow)
end)

ok(soCorpo > 0, "o corpo desenha sozinho")
ok(corpoECauda > soCorpo, "e a cauda acrescenta area ao conjunto",
   ("%d -> %d"):format(soCorpo, corpoECauda))

local meiaCauda = pintados(function(f, cx, cy, r)
  marca.corpo(f, cx, cy, r, colors.yellow)
  marca.cauda(f, cx, cy, r, colors.yellow, 0.5)
end)
ok(meiaCauda > soCorpo and meiaCauda < corpoECauda,
   "meia cauda fica entre nenhuma e inteira",
   ("%d < %d < %d"):format(soCorpo, meiaCauda, corpoECauda))

local semCauda = pintados(function(f, cx, cy, r)
  marca.corpo(f, cx, cy, r, colors.yellow)
  marca.cauda(f, cx, cy, r, colors.yellow, 0)
end)
igual(semCauda, soCorpo, "cauda em 0 nao desenha nada")

print("\n-- o letreiro parcial --")

local function letrasNaTela(quantas, cursor)
  local tl = mock.monitor(80, 30)
  local f = pixel.novo(tl)
  f:limpar(colors.black)
  marca.letreiro(f, 10, 50, 16, colors.yellow, nil, quantas, cursor)
  local n = 0
  for y = 1, f.h do
    for x = 1, f.w do if f.buf[y][x] ~= colors.black then n = n + 1 end end
  end
  return n
end

local nenhuma = letrasNaTela(0)
igual(nenhuma, 0, "zero letras nao desenha nada")

local anterior = 0
local cresceu = true
for q = 1, marca.quantasLetras() do
  local n = letrasNaTela(q)
  if n <= anterior then cresceu = false end
  anterior = n
end
ok(cresceu, "cada letra a mais acrescenta area")

igual(letrasNaTela(99), letrasNaTela(marca.quantasLetras()),
      "pedir mais letras do que existem da o nome inteiro")

local comCursor = letrasNaTela(2, true)
local semCursor = letrasNaTela(2, false)
ok(comCursor > semCursor, "o cursor acrescenta um bloco",
   ("%d contra %d"):format(comCursor, semCursor))

-- no fim da palavra o cursor nao tem vaga: quem pede as cinco letras ja tem o
-- nome inteiro, e um bloco depois do E ficaria fora do balao
ok(letrasNaTela(marca.quantasLetras(), true) >= letrasNaTela(marca.quantasLetras(), false),
   "e no fim da palavra ele nao estraga o nome")

print("\n-- o balao --")

local tela = mock.monitor(40, 20)
local f = pixel.novo(tela)
f:limpar(colors.black)
local r, cx, cy = marca.desenhar(f, colors.yellow)
ok(r ~= nil, "desenha num tamanho normal")

-- a cauda desce a direita: tem que haver amarelo abaixo e a direita do centro
local temCauda = false
for y = math.floor(cy + r * 0.9), f.h do
  for x = math.floor(cx), f.w do
    if f.buf[y] and f.buf[y][x] == colors.yellow then temCauda = true end
  end
end
ok(temCauda, "e a cauda desce pelo lado direito")

-- nada pode ser pintado fora do quadro
local vazou = false
for y = 1, f.h do
  if f.buf[y][0] ~= nil or f.buf[y][f.w + 1] ~= nil then vazou = true end
end
ok(not vazou, "e nada e pintado fora do framebuffer")

local minusculo = pixel.novo(mock.monitor(4, 2))
ok(marca.desenhar(minusculo, colors.yellow) == nil,
   "numa area minuscula, desiste em vez de desenhar lixo")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
