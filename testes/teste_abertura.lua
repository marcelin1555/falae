--[[ teste_abertura - o roteiro dos quatro atos

  Animacao se testa quadro a quadro, contra um relogio falso. Um teste que
  espera quinze segundos ninguem roda duas vezes - e o que se quer conferir nao
  e "ficou bonito" (isso e olhando), e sim que cada instante do roteiro entrega
  o que promete.

  O que da para quebrar sem ninguem ver:

    - um ato que nunca acontece porque o marco esta errado, e a animacao pula
      do balao para o diagnostico sem o nome
    - a PALETA NAO SER DEVOLVIDA. A paleta do CC e global e sobrevive ao
      programa: uma abertura que mexe nas cores e nao as restaura deixa o
      shell, o edit e todo o resto errados ate o computador reiniciar. O
      palette.lua avisa isso no topo justamente porque ja aconteceu.
    - pular nao pular
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

local lib      = dofile("/core/lib.lua")
local pixel    = lib("pixel")
local marca    = lib("marca")
local palette  = lib("palette")
local abertura = lib("abertura")

local R = abertura.R

local DIAG = {
  abertura.linhaDiag("modem", "ok"),
  abertura.linhaDiag("linhas", 12),
  abertura.linhaDiag("recados", 847),
  abertura.linhaDiag("rede", "no ar"),
}

--- Desenha o quadro do instante t e devolve o estado mais o que foi pintado.
local function quadro(t, colunas, linhas)
  local tela = mock.monitor(colunas or 82, linhas or 40)
  local fb = pixel.novo(tela)
  local estado = abertura.quadro(fb, marca, t, R, DIAG)

  local pintados = 0
  for y = 1, fb.h do
    for x = 1, fb.w do
      if fb.buf[y][x] ~= colors.black then pintados = pintados + 1 end
    end
  end
  estado.pintados = pintados
  estado.fb = fb
  return estado
end

-- ------------------------------------------------------------- os marcos

print("\n-- o roteiro nao pula ato --")

ok(R.cresce < R.digita and R.digita < R.cauda and R.cauda < R.fim,
   "os quatro marcos estao em ordem",
   ("%.1f %.1f %.1f %.1f"):format(R.cresce, R.digita, R.cauda, R.fim))

ok(R.digita - R.cresce >= 3,
   "o ato de digitar tem tempo para as cinco letras",
   ("%.1fs para %d letras"):format(R.digita - R.cresce, marca.quantasLetras()))

-- ---------------------------------------------------------- ato 1: cresce

print("\n-- ato 1: o balao cresce --")

local inicio = quadro(0.1)
igual(inicio.ato, 1, "comeca no ato 1")
ok(inicio.balao < 0.3, "e o balao comeca pequeno", inicio.balao)
igual(inicio.letras, 0, "sem letra nenhuma ainda")
igual(inicio.cauda, 0, "e sem cauda")

local meio = quadro(R.cresce / 2)
ok(meio.balao > inicio.balao, "no meio do ato ele ja cresceu")
ok(meio.pintados > inicio.pintados, "e ha mais coisa pintada na tela",
   ("%d -> %d"):format(inicio.pintados, meio.pintados))

local fimCresce = quadro(R.cresce - 0.05)
ok(fimCresce.balao > 0.9, "no fim do ato 1 ele esta quase inteiro", fimCresce.balao)
igual(fimCresce.cauda, 0, "e a cauda continua sem aparecer")

-- ---------------------------------------------------------- ato 2: digita

print("\n-- ato 2: o nome e digitado --")

local vistas = {}
for k = 0, 10 do
  local t = R.cresce + (R.digita - R.cresce) * (k / 10)
  local q = quadro(t + 0.01)
  vistas[#vistas + 1] = q.letras
end

igual(vistas[1], 0, "comeca sem letra")
ok(vistas[#vistas] >= marca.quantasLetras() - 1,
   "e termina com o nome quase todo ou inteiro", vistas[#vistas])

-- as letras so podem CRESCER: uma letra que some e some no meio da palavra
local sempreCresce = true
for i = 2, #vistas do
  if vistas[i] < vistas[i - 1] then sempreCresce = false end
end
ok(sempreCresce, "e as letras so aparecem, nunca somem",
   table.concat(vistas, ","))

local digitando = quadro(R.cresce + 0.5)
igual(digitando.ato, 2, "no meio da digitacao, ato 2")
igual(digitando.cauda, 0, "a cauda ainda nao caiu")

-- o cursor pisca: em dois instantes proximos dentro do mesmo segundo de
-- digitacao, ele nao pode estar sempre igual
local piscou = false
local base = quadro(R.cresce + 0.2).cursor
for k = 1, 8 do
  if quadro(R.cresce + 0.2 + k * 0.25).cursor ~= base then piscou = true end
end
ok(piscou, "o cursor pisca durante a digitacao")

local depois = quadro(R.digita + 0.5)
igual(depois.letras, marca.quantasLetras(), "depois do ato 2, o nome esta inteiro")
ok(not depois.cursor, "e o cursor sumiu")

-- ----------------------------------------------------------- ato 3: cauda

print("\n-- ato 3: a cauda cai --")

local comecoCauda = quadro(R.digita + 0.05)
igual(comecoCauda.ato, 3, "entra no ato 3")
ok(comecoCauda.cauda > 0 and comecoCauda.cauda < 0.3,
   "e a cauda esta comecando a descer", comecoCauda.cauda)

local meioCauda = quadro((R.digita + R.cauda) / 2)
ok(meioCauda.cauda > comecoCauda.cauda, "ela desce ao longo do ato",
   ("%.2f -> %.2f"):format(comecoCauda.cauda, meioCauda.cauda))

local fimCauda = quadro(R.cauda - 0.05)
ok(fimCauda.cauda > 0.9, "e chega inteira no fim do ato", fimCauda.cauda)

-- o pulso: o balao incha um tico no instante do envio. E o gesto que amarra a
-- animacao - sem ele, a cauda so aparece, e nao "e enviada"
local pulso = quadro(R.digita + 0.25)
ok(pulso.balao > 1.0, "o balao pulsa no momento do envio", pulso.balao)
local jaPassou = quadro(R.digita + 0.9)
ok(math.abs(jaPassou.balao - 1) < 0.01,
   "e volta ao normal logo depois - pulso longo viraria respiracao",
   jaPassou.balao)

-- ------------------------------------------------------ ato 4: diagnostico

print("\n-- ato 4: o diagnostico --")

igual(quadro(R.cauda - 0.1).linhas, 0, "antes do ato 4, nenhuma linha")

local entrando = quadro((R.cauda + R.fim) / 2)
igual(entrando.ato, 4, "entra no ato 4")
ok(entrando.linhas > 0 and entrando.linhas < #DIAG,
   "e as linhas entram uma a uma, nao todas de vez", entrando.linhas)

local quaseFim = quadro(R.fim - 0.05)
igual(quaseFim.linhas, #DIAG, "no fim, todas as linhas apareceram")

-- e nunca mais que as que existem
for k = 0, 20 do
  local q = quadro(R.cauda + (R.fim - R.cauda) * (k / 20))
  if q.linhas > #DIAG then
    ok(false, "nunca passa do numero de linhas que existem", q.linhas)
    break
  end
  if k == 20 then ok(true, "nunca passa do numero de linhas que existem") end
end

print("\n-- a linha do diagnostico --")
local l = abertura.linhaDiag("modem", "ok", 22)
ok(l:find("modem", 1, true) == 1, "comeca com o rotulo")
ok(l:find("ok", 1, true), "e termina com o valor")
ok(l:find("%.%.%."), "com pontinhos alinhando no meio", l)
igual(#abertura.linhaDiag("a", "b", 20), 20, "e ocupa a largura pedida")
igual(#abertura.linhaDiag("um rotulo bem comprido", "valor", 20) > 0, true,
      "rotulo maior que a largura nao explode")

-- --------------------------------------------------- nos dois tamanhos

print("\n-- o pocket usa o roteiro curto --")

local C = abertura.CURTO
ok(C.fim < R.fim / 2, "o roteiro curto e menos da metade do longo",
   ("%.1fs contra %.1fs"):format(C.fim, R.fim))
ok(C.cresce < C.digita and C.digita < C.cauda and C.cauda < C.fim,
   "e os marcos dele tambem estao em ordem")

-- num pocket a letra nao cabe desenhada e a marca cai para caracteres; o
-- roteiro tem que rodar do mesmo jeito, sem erro
local telaP = mock.monitor(26, 20)
local fbP = pixel.novo(telaP)
local okP = pcall(function()
  for k = 0, 12 do
    abertura.quadro(fbP, marca, C.fim * (k / 12), C, DIAG)
  end
end)
ok(okP, "o roteiro inteiro roda num pocket 26x20 sem quebrar")

print("\n-- a digitacao funciona nas telas sem resolucao --")

-- No pocket a letra nao cabe desenhada e a marca cai para a fonte do terminal.
-- A digitacao tem que acontecer DOS DOIS JEITOS - se so o desenhado digitasse,
-- o ato 2 (que e o coracao da animacao) simplesmente nao apareceria no
-- aparelho, e nada indicaria isso.
local telaPocket = mock.monitor(26, 20)
local jan = window.create(telaPocket, 1, 1, 26, 14, true)
local fbPocket = pixel.novo(jan)

-- um instante com letra ja digitada: antes da primeira, nao ha nome nenhum
-- para escrever e o aviso nao faria sentido
local tComLetra = C.cresce + (C.digita - C.cresce) * 0.5
local qP = abertura.quadro(fbPocket, marca, tComLetra, C, DIAG)
ok(qP.letras > 0, "no meio do ato 2 ja ha letra", qP.letras)
ok(qP.precisaEscrever == true,
   "e num pocket o quadro avisa que o nome precisa ser escrito")

-- e o texto parcial sai mesmo
marca.escrever(jan, qP.r, qP.cx, qP.cy, colors.black, colors.yellow, 2, true)
local escrito = telaPocket.tudo()
ok(escrito:find("FA", 1, true) ~= nil, "e as duas primeiras letras aparecem")
ok(escrito:find("FALAE", 1, true) == nil,
   "sem as que ainda nao foram digitadas")

-- O texto tem sempre a largura do nome inteiro: escrever so "FA" deixaria as
-- letras seguintes do quadro anterior na tela, e o nome apareceria e sumiria
-- em pedacos.
marca.escrever(jan, qP.r, qP.cx, qP.cy, colors.black, colors.yellow, 5, false)
marca.escrever(jan, qP.r, qP.cx, qP.cy, colors.black, colors.yellow, 1, false)
local depoisDeVoltar = telaPocket.tudo()
ok(depoisDeVoltar:find("ALAE", 1, true) == nil,
   "escrever menos letras apaga as que sobravam", depoisDeVoltar:sub(1, 60))

-- e numa tela grande, o desenhado continua sendo o caminho
local telaGrande = mock.monitor(82, 40)
local fbGrande = pixel.novo(telaGrande)
local qG = abertura.quadro(fbGrande, marca,
                           R.cresce + (R.digita - R.cresce) * 0.5, R, DIAG)
ok(not qG.precisaEscrever, "numa tela grande, o nome sai desenhado")

print("\n-- o diagnostico nao escreve por cima do balao --")

-- Foi o que aconteceu na primeira versao: no pocket o texto saia sobre o
-- amarelo e nao se lia nem uma coisa nem outra.
ok(not abertura.diagAoLado(26, 20, DIAG, marca),
   "num pocket o diagnostico vai embaixo")
ok(abertura.diagAoLado(82, 26, DIAG, marca),
   "e numa tela larga, ao lado")

-- O terminal de um computador: 51 colunas parecem largas, mas o balao vai ate
-- a coluna 41 e sobram dez - menos que a linha mais curta do diagnostico. A
-- regra antiga era so "colunas >= 40" e mandava o texto para cima do amarelo,
-- cortado na borda. Foi visto rodando de verdade no CraftOS-PC, nao aqui.
ok(not abertura.diagAoLado(51, 19, DIAG, marca),
   "num terminal de 51 colunas o balao ocupa o lado, e o texto desce")

-- E o que decide e a SOBRA, nao a largura: as mesmas 51 colunas com linhas
-- curtas tem lugar ao lado.
local curtas = { "ok", "12" }
ok(abertura.diagAoLado(51, 19, curtas, marca),
   "com linhas curtas, essas mesmas 51 colunas ja acomodam ao lado")

-- Nenhuma linha pode passar da borda direita.
for _, caso in ipairs({ { 82, 26, DIAG }, { 51, 19, curtas } }) do
  local col = abertura.colunaDoDiag(caso[1], caso[2], caso[3], marca)
  ok(col and col + abertura.larguraDiag(caso[3]) - 1 <= caso[1],
     ("o diagnostico cabe inteiro em %dx%d"):format(caso[1], caso[2]),
     ("coluna %s, largura %d, tela %d")
       :format(tostring(col), abertura.larguraDiag(caso[3]), caso[1]))
end

local _, _, _, alturaBalao = abertura.areaDoBalao(mock.monitor(26, 20), DIAG, marca)
ok(alturaBalao <= 20 - 4, "o balao cede as linhas do diagnostico",
   ("altura %d de 20, com 4 linhas de texto"):format(alturaBalao))

local _, _, _, alturaLarga = abertura.areaDoBalao(mock.monitor(82, 26), DIAG, marca)
igual(alturaLarga, 26, "numa tela larga ele usa a altura toda")

local _, _, _, semDiag = abertura.areaDoBalao(mock.monitor(26, 20), {}, marca)
igual(semDiag, 20, "e sem diagnostico tambem")

print("\n-- telas minusculas --")
for _, tam in ipairs({ { 10, 5 }, { 6, 3 }, { 4, 2 } }) do
  local t2 = mock.monitor(tam[1], tam[2])
  local fb2 = pixel.novo(t2)
  local ok2 = pcall(function()
    for k = 0, 6 do abertura.quadro(fb2, marca, R.fim * (k / 6), R, DIAG) end
  end)
  ok(ok2, ("%dx%d nao quebra"):format(tam[1], tam[2]))
end

-- ---------------------------------------------------------- a paleta

print("\n-- a paleta e devolvida --")

-- E o teste que mais importa. A paleta do CC e global e sobrevive ao programa:
-- sem restaurar, o shell fica com as cores da FALAE ate o computador
-- reiniciar. Aqui a abertura roda de verdade, com eventos, e as cores tem que
-- voltar exatamente como estavam.
local tela = mock.monitor(51, 19)
local antes = {}
for _, cor in ipairs(palette.MEXIDAS) do
  local r, g, b = tela.getPaletteColour(cor)
  antes[cor] = { r, g, b }
end

mock.instalarEventos()
-- uma tecla logo no comeco: e o caminho de "pular", o mais facil de esquecer
mock.enfileirar("key", mock.KEYS.q)
local foiAteOFim = abertura.rodar(tela,
  { pixel = pixel, marca = marca, palette = palette }, DIAG)

ok(foiAteOFim == false, "pular devolve false")

local mudou = {}
for _, cor in ipairs(palette.MEXIDAS) do
  local r, g, b = tela.getPaletteColour(cor)
  local a = antes[cor]
  if math.abs(r - a[1]) > 0.001 or math.abs(g - a[2]) > 0.001
     or math.abs(b - a[3]) > 0.001 then
    mudou[#mudou + 1] = cor
  end
end
igual(#mudou, 0, "e a paleta volta exatamente como estava, mesmo pulando",
      ("%d cor(es) ficaram trocadas"):format(#mudou))

print("\n-- e devolve mesmo se algo quebrar no meio --")

local telaRuim = mock.monitor(51, 19)
local antesRuim = {}
for _, cor in ipairs(palette.MEXIDAS) do
  local r, g, b = telaRuim.getPaletteColour(cor)
  antesRuim[cor] = { r, g, b }
end

-- uma marca que levanta erro no meio do desenho
local marcaRuim = setmetatable({
  desenharCorpo = function() error("monitor sumiu", 0) end,
}, { __index = marca })

mock.instalarEventos()
mock.enfileirar("timer", 1)
local semQuebrar = pcall(abertura.rodar, telaRuim,
  { pixel = pixel, marca = marcaRuim, palette = palette }, DIAG)
ok(semQuebrar, "a abertura nao propaga o erro para quem a chamou")

local mudouRuim = 0
for _, cor in ipairs(palette.MEXIDAS) do
  local r, g, b = telaRuim.getPaletteColour(cor)
  local a = antesRuim[cor]
  if math.abs(r - a[1]) > 0.001 or math.abs(g - a[2]) > 0.001
     or math.abs(b - a[3]) > 0.001 then
    mudouRuim = mudouRuim + 1
  end
end
igual(mudouRuim, 0, "e a paleta volta mesmo assim")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
