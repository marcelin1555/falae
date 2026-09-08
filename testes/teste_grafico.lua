--[[ teste_grafico - as barras do painel

  Escala automatica e onde erro de arredondamento se esconde: uma barra que
  estoura o retangulo por um ponto so aparece com a serie certa, num dia
  qualquer, e escreve por cima do que estiver em volta. Como o grafico fica no
  meio do painel, isso apagaria os numeros do lado.

  As series testadas sao as que costumam quebrar desenho com escala: vazia,
  toda zero, um valor so, um valor gigante no meio de pequenos, e valores
  pequenos que arredondariam para zero e sumiriam da tela.
]]

local PROJETO = ...

local mock = dofile(PROJETO .. "/testes/cc_mock.lua")
mock.instalar()
mock.montarCentral(PROJETO, true)
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

local pixel   = dofile("/pixel.lua")
local grafico = dofile("/tela/grafico.lua")

--- Desenha num retangulo com margem e devolve o que foi pintado.
local function desenhar(serie, w, h, opcoes)
  local tela = mock.monitor(math.ceil((w + 8) / 2), math.ceil((h + 8) / 3))
  local fb = pixel.novo(tela)
  fb:limpar(colors.black)

  -- o retangulo comeca em (4,4): sobra margem de todo lado, entao qualquer
  -- ponto pintado fora dela e vazamento visivel
  local pico = grafico.barras(fb, 4, 4, w, h, serie, colors.cyan, opcoes)

  local fora, dentro = 0, 0
  local alturas = {}
  for y = 1, fb.h do
    for x = 1, fb.w do
      if fb.buf[y][x] ~= colors.black then
        if x < 4 or x > 4 + w - 1 or y < 4 or y > 4 + h - 1 then
          fora = fora + 1
        else
          dentro = dentro + 1
          alturas[x] = (alturas[x] or 0) + 1
        end
      end
    end
  end
  return { pico = pico, fora = fora, dentro = dentro, alturas = alturas, fb = fb }
end

-- ------------------------------------------------------------ o basico

print("\n-- uma serie normal --")
local r = desenhar({ 3, 5, 2, 8, 14, 22, 31, 18, 9, 4, 11, 6 }, 60, 20)
igual(r.pico, 31, "o pico e o maior valor da serie")
igual(r.fora, 0, "nada e pintado fora do retangulo")
ok(r.dentro > 0, "e alguma coisa foi desenhada")

-- a barra mais alta tem que ter exatamente a altura do retangulo
local maisAlta = 0
for _, a in pairs(r.alturas) do if a > maisAlta then maisAlta = a end end
igual(maisAlta, 20, "a barra do pico ocupa a altura inteira")

print("\n-- proporcao --")
-- metade do pico tem que dar metade da altura, ou o grafico mente
igual(grafico.altura(31, 31, 20), 20, "o pico enche")
igual(grafico.altura(0, 31, 20), 0, "zero nao desenha")
ok(math.abs(grafico.altura(15, 30, 20) - 10) <= 1,
   "metade do pico da metade da altura", grafico.altura(15, 30, 20))

-- A escala COMECA NO ZERO sempre. Um grafico de barras com base cortada mente
-- sobre a proporcao entre elas, e este existe para responder "hoje foi mais
-- movimentado que ontem?".
local baixo = desenhar({ 100, 101, 102 }, 30, 12)
local alturas = {}
for _, a in pairs(baixo.alturas) do alturas[#alturas + 1] = a end
table.sort(alturas)
ok(alturas[1] >= alturas[#alturas] - 2,
   "valores proximos dao barras proximas - a base nao e cortada",
   table.concat(alturas, ","))

-- ------------------------------------------------- as series que quebram

print("\n-- series de canto --")

local vazia = desenhar({}, 40, 12)
igual(vazia.pico, 0, "serie vazia devolve pico zero")
igual(vazia.dentro, 0, "e nao desenha nada")
igual(vazia.fora, 0, "sem vazar")

local zeros = desenhar({ 0, 0, 0, 0 }, 40, 12)
igual(zeros.pico, 0, "serie toda zero devolve pico zero")
ok(zeros.dentro > 0, "mas desenha a linha de base - 'nao houve nada' e um resultado")
igual(zeros.fora, 0, "sem vazar")

local umSo = desenhar({ 7 }, 40, 12)
igual(umSo.pico, 7, "um valor so vira o proprio pico")
igual(umSo.fora, 0, "sem vazar")

local gigante = desenhar({ 1, 0, 0, 500 }, 40, 12)
igual(gigante.pico, 500, "o gigante manda na escala")
igual(gigante.fora, 0, "e nao estoura o retangulo")

-- O 1 ao lado do 500 arredondaria para zero e sumiria. Sumir e pior que
-- desproporcional: quem olha conclui que nao houve nada naquela hora.
local temPequena = false
for _, a in pairs(gigante.alturas) do
  if a >= 1 and a <= 3 then temPequena = true end
end
ok(temPequena, "e o valor pequeno ainda aparece, com pelo menos um ponto")

print("\n-- retangulos apertados --")
for _, tam in ipairs({ { 10, 4 }, { 5, 2 }, { 3, 1 }, { 1, 1 } }) do
  local ap = desenhar({ 1, 2, 3, 4, 5 }, tam[1], tam[2])
  igual(ap.fora, 0, ("%dx%d nao vaza"):format(tam[1], tam[2]))
end

local nada = desenhar({ 1, 2 }, 0, 0)
igual(nada.dentro + nada.fora, 0, "retangulo de tamanho zero nao desenha nada")

print("\n-- pico forcado --")
local forcado = desenhar({ 5, 10 }, 40, 12, { pico = 100 })
igual(forcado.pico, 100, "o pico dado de fora e respeitado")
local maior = 0
for _, a in pairs(forcado.alturas) do if a > maior then maior = a end end
ok(maior < 12, "e as barras ficam baixas, como manda a escala", maior)

print("\n-- a ultima barra pode ter cor propria --")
local comCor = desenhar({ 5, 5, 5 }, 30, 12, { corUltima = colors.yellow })
local temAmarelo = false
for y = 1, comCor.fb.h do
  for x = 1, comCor.fb.w do
    if comCor.fb.buf[y][x] == colors.yellow then temAmarelo = true end
  end
end
ok(temAmarelo, "a barra do 'agora' sai na cor de destaque")

print("\n-- numeros curtos para o eixo --")
igual(grafico.curto(0), "0", "zero")
igual(grafico.curto(999), "999", "abaixo de mil sai inteiro")
igual(grafico.curto(1500), "1.5k", "mil e quinhentos")
igual(grafico.curto(12000), "12k", "doze mil")
ok(#grafico.curto(999999) <= 4, "e nada passa de quatro caracteres",
   grafico.curto(999999))

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
