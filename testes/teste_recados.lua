--[[ teste_recados - mensagens, historico e as duas decisoes de custo

  Alem de guardar e devolver recado na ordem certa, este arquivo protege duas
  coisas que sao invisiveis quando funcionam:

  1. O log que so cresce pelo fim. Se alguem trocar o append por uma reescrita
     do arquivo inteiro, tudo continua passando - so fica lento, e so muito
     depois, quando o historico crescer no mundo de verdade.

  2. O aparo em lote. Cortar de um em um com table.remove(lista, 1) tambem
     funciona; e trabalho ao quadrado, e tambem so aparece tarde.

  Nenhum dos dois tem sintoma no jogo antes de ser tarde. Por isso o custo
  deles e medido aqui - e a medicao propriamente dita esta no teste_carga.
]]

local PROJETO = ...

local mock = dofile(PROJETO .. "/testes/cc_mock.lua")
mock.instalar()
mock.montarCentral(PROJETO, false)
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
  ok(a == b, titulo, ("esperava %s, veio %s"):format(tostring(b), tostring(a)))
end

local lib     = dofile("/core/lib.lua")
local recados = lib("recados")

local ANA   = "5511100000001"
local BRUNO = "5511100000002"
local CARLA = "5511100000003"

recados.carregar()

-- ------------------------------------------------------------------ enviar

print("\n-- enviar --")
local m1 = recados.enviar(ANA, BRUNO, "e ai, ta na base?")
ok(m1 ~= nil, "recado enviado")
igual(m1.n, 1, "o primeiro recado e o numero 1")
igual(m1.de, ANA, "guarda quem mandou")
igual(m1.para, BRUNO, "guarda para quem")

local m2 = recados.enviar(BRUNO, ANA, "to indo agora")
igual(m2.n, 2, "o proximo recado e o 2")

ok(select(1, recados.enviar(ANA, BRUNO, "")) == nil, "recado vazio e recusado")
ok(select(1, recados.enviar(ANA, BRUNO, "   ")) == nil, "so espaco e recusado")
ok(select(1, recados.enviar(ANA, BRUNO, nil)) == nil, "nil e recusado")

local comprido = recados.enviar(ANA, BRUNO, string.rep("x", 400))
ok(#comprido.texto <= recados.TAMANHO, "recado comprido e cortado")

-- A barra vertical separa os campos no arquivo. Se ela passasse no texto, o
-- proximo boot leria o recado partido - e o texto de alguem viraria o numero
-- de outro alguem.
local comBarra = recados.enviar(ANA, BRUNO, "a|b|c")
ok(not comBarra.texto:find("|", 1, true), "a barra some do texto")

local comQuebra = recados.enviar(ANA, BRUNO, "linha1\nlinha2")
ok(not comQuebra.texto:find("\n", 1, true), "a quebra de linha some do texto")

-- --------------------------------------------------------------- catalogo

print("\n-- o catalogo (ultimoN) --")
-- e o que permite responder "nada mudou" sem varrer a lista
ok(recados.ultimo(ANA) > 0, "a linha que falou tem ultimo n")
igual(recados.ultimo(ANA), recados.ultimo(BRUNO), "os dois lados veem o mesmo ultimo")
igual(recados.ultimo(CARLA), 0, "quem nunca falou tem ultimo 0")
igual(recados.ultimo("5599999999999"), 0, "numero desconhecido tem ultimo 0")

-- ---------------------------------------------------------------- desde

print("\n-- desde --")
local lista, ultimo = recados.desde(ANA, 0)
ok(lista ~= nil, "desde 0 traz o historico")
igual(#lista, recados.quantos(), "e traz tudo que existe (so ha essa conversa)")

local nada, ult2 = recados.desde(ANA, ultimo)
ok(nada == nil, "quem esta em dia recebe nil, nao lista vazia")
igual(ult2, ultimo, "e recebe o ultimo n mesmo assim")

-- O nil e a resposta rapida. Se um dia virar lista vazia, a central passa a
-- varrer e serializar para dizer que nao houve nada - que e exatamente o
-- custo que o desenho existe para evitar.
local naoTem = recados.desde(CARLA, 0)
ok(naoTem == nil, "quem nunca falou tambem cai na resposta rapida")

local parcial = recados.desde(ANA, 1)
ok(parcial ~= nil and parcial[1].n == 2, "desde N traz so o que veio depois")

local limitado = recados.desde(ANA, 0, 2)
igual(#limitado, 2, "o limite e respeitado")

-- --------------------------------------------------------------- conversa

print("\n-- conversa e lista de conversas --")
recados.enviar(CARLA, ANA, "oi Ana, aqui e a Carla")

local comBruno = recados.conversa(ANA, BRUNO)
local soDosDois = true
for _, m in ipairs(comBruno) do
  if not ((m.de == ANA and m.para == BRUNO) or (m.de == BRUNO and m.para == ANA)) then
    soDosDois = false
  end
end
ok(soDosDois, "a conversa com Bruno so tem recado dos dois")

-- A lista de conversas e montada NO APARELHO, do que ele ja tem em disco (ver
-- agenda.conversas). A central tinha uma rota igual que varria todos os
-- recados para responder a mesma coisa; ninguem chamava, e ela contrariava a
-- regra do proprio arquivo. Saiu.
ok(recados.conversas == nil,
   "a central nao monta lista de conversa - isso e do aparelho")

-- ------------------------------------------------------------------ disco

print("\n-- o log --")
local antes = recados.quantos()
local recados2 = dofile("/core/recados.lua")
recados2.carregar()
igual(recados2.quantos(), antes, "recarregar do disco traz os mesmos recados")
igual(recados2.ultimo(ANA), recados.ultimo(ANA), "e reconstroi o catalogo")
ok(recados2.enviar(ANA, BRUNO, "depois de recarregar").n > antes,
   "o proximo n continua de onde parou")

print("\n-- a busca comeca perto do fim, nao no comeco --")

-- A lista esta sempre em ordem de n: os recados entram pelo fim e o aparo so
-- tira do comeco. Percorrer da posicao 1 para achar o que esta no fim era a
-- unica varredura que sobrava no caminho de um pedido - o mesmo defeito que o
-- catalogo ultimoN existe justamente para nao ter.
local quantos = recados.quantos()
igual(recados.primeiroDepois(0), 1, "desde zero, comeca do primeiro")
igual(recados.primeiroDepois(999999), quantos + 1,
      "depois do fim, o laco de quem chama nem roda")

-- A prova que importa: para TODO valor de "desde", a busca binaria tem que
-- devolver exatamente o que a varredura ingenua devolveria. Uma busca binaria
-- com o indice torto por um erra num valor so, e esse valor e o que alguem vai
-- pedir no jogo.
local function ingenuo(canonico, desde)
  local saida = {}
  for _, m in ipairs(recados.todos()) do
    if m.n > desde and (m.de == canonico or m.para == canonico) then
      saida[#saida + 1] = m.n
    end
  end
  return saida
end

local batem = true
local ondeErrou = nil
for desde = 0, quantos + 2 do
  local esperado = ingenuo(ANA, desde)
  local veio = recados.desde(ANA, desde, 1000) or {}
  if #veio ~= #esperado then
    batem = false
    ondeErrou = ondeErrou or ("desde=" .. desde ..
                ": " .. #veio .. " em vez de " .. #esperado)
  else
    for i = 1, #veio do
      if veio[i].n ~= esperado[i] then
        batem = false
        ondeErrou = ondeErrou or ("desde=" .. desde .. ", posicao " .. i)
      end
    end
  end
end
ok(batem, "a busca binaria devolve o mesmo que a varredura, para todo 'desde'",
   ondeErrou)

print("\n-- linha corrompida no fim do arquivo --")
-- uma queda no meio de um append deixa meia linha; descartar a linha perde um
-- recado, levantar erro perderia o historico inteiro
local store = lib("store")
store.anexar(recados.LOG, "isto nao e um recado")
local recados3 = dofile("/core/recados.lua")
local quantos = recados3.carregar()
ok(quantos > 0, "o historico continua legivel com lixo no fim", quantos)

-- ------------------------------------------------------------------ aparo

print("\n-- aparo do historico --")
local rec = dofile("/core/recados.lua")
rec.LOG = "/dados/aparo.log"
rec.MAX = 20
rec.FOLGA = 5
rec.carregar()

for i = 1, rec.MAX + rec.FOLGA do
  rec.enviar(ANA, BRUNO, "recado " .. i)
end
igual(rec.quantos(), rec.MAX + rec.FOLGA, "ate MAX+FOLGA nada e aparado")

-- aparar so ao passar da folga: aparar assim que passa de MAX faria uma
-- reescrita do arquivo a cada recado novo
rec.enviar(ANA, BRUNO, "o que estoura")
igual(rec.quantos(), rec.MAX, "passou da folga, apara para MAX")

local sobrou = rec.desde(ANA, 0)
ok(sobrou[1].texto ~= "recado 1", "o aparo corta o comeco, nao o fim")
ok(sobrou[#sobrou].texto == "o que estoura", "e o mais novo continua la")

-- depois de aparar, o catalogo tem que continuar valendo, senao a resposta
-- rapida passa a mentir
ok(rec.ultimo(ANA) == sobrou[#sobrou].n, "o catalogo acompanha o aparo")

local rec2 = dofile("/core/recados.lua")
rec2.LOG = "/dados/aparo.log"
rec2.carregar()
igual(rec2.quantos(), rec.MAX, "o arquivo em disco tambem foi aparado")

-- ---------------------------------------------------------------- esquecer

print("\n-- esquecer uma linha cassada --")
local esq = dofile("/core/recados.lua")
esq.LOG = "/dados/esquecer.log"
esq.carregar()
esq.enviar(ANA, BRUNO, "um")
esq.enviar(BRUNO, ANA, "dois")
esq.enviar(ANA, CARLA, "tres")
esq.enviar(CARLA, BRUNO, "quatro")

local foram = esq.esquecer(ANA)
igual(foram, 3, "some com todo recado que envolve a linha")
igual(esq.quantos(), 1, "o que nao envolvia ela fica")
igual(esq.ultimo(ANA), 0, "o catalogo esquece a linha")

-- apagar so o lado dela deixaria a conversa no disco pela metade, do lado do
-- outro - e a FALAE teria dito que apagou
local restante = esq.desde(BRUNO, 0)
local sobrouAlgumDaAna = false
for _, m in ipairs(restante or {}) do
  if m.de == ANA or m.para == ANA then sobrouAlgumDaAna = true end
end
ok(not sobrouAlgumDaAna, "nao sobra a metade da conversa do outro lado")

print("\n-- a troca de arquivo nao deixa buraco --")

local store = lib("store")
local ALVO = "/dados/teste_troca"

-- O caminho ingenuo - apagar o atual e mover o novo por cima - deixa um
-- instante em que NENHUM dos dois existe. E curto, e o CC descarrega chunk no
-- meio de qualquer coisa; e o arquivo que some assim e o das contas de todo
-- mundo.
store.salvar(ALVO, { quem = "antes" })
store.salvar(ALVO, { quem = "depois" })
igual(store.carregar(ALVO, {}).quem, "depois", "gravar por cima troca o conteudo")
ok(not fs.exists(ALVO .. ".tmp"), "e nao deixa temporario para tras")
ok(not fs.exists(ALVO .. ".bak"), "nem copia de seguranca")

-- A QUEDA NO PIOR INSTANTE: o original ja virou .bak e o novo ainda nao
-- chegou. E o unico momento em que o arquivo principal nao existe, e quem le
-- tem que achar a copia em vez de devolver o padrao vazio.
local f = fs.open(ALVO .. ".bak", "w")
f.write(textutils.serialize({ quem = "sobrevivi" }))
f.close()
fs.delete(ALVO)

igual(store.carregar(ALVO, { quem = "padrao" }).quem, "sobrevivi",
      "some o principal no meio da troca, e a copia salva o dia")

-- e um .bak que tambem esta ilegivel nao pode derrubar nada
fs.delete(ALVO .. ".bak")
local g = fs.open(ALVO .. ".bak", "w")
g.write("isto nao e uma tabela {{{")
g.close()
igual(store.carregar(ALVO, { quem = "padrao" }).quem, "padrao",
      "e com os dois ilegiveis, volta o padrao em vez de levantar erro")
fs.delete(ALVO .. ".bak")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
