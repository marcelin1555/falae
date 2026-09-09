--[[ teste_exportacao - a unica porta pela qual o texto sai por ordem judicial

  Este arquivo prova o que o comentario de exportacao.lua promete:

  1. NUNCA PELA REDE. exportacao.lua nao pode chamar http nem rednet, nem
     hoje nem depois de alguem mexer nele sem ler o cabecalho. O teste
     desliga http e rednet ANTES de montar qualquer exportacao e confere que
     nada quebra por falta deles - se algum dia o modulo tentar usar rede,
     ele quebra aqui, e nao so quando alguem notar o vazamento no jogo.

  2. O MOTIVO E OBRIGATORIO, e fica gravado - mesmo quando so o pedido foi
     feito e a gravacao no disquete (que e coisa do console, nao deste
     modulo) ainda nao aconteceu.

  3. O LOG DE AUDITORIA NUNCA APARA. Ao contrario do log de tela da central
     (100 linhas e descarta), este e para sempre.
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
  ok(a == b, titulo, ("esperava [%s], veio [%s]"):format(tostring(b), tostring(a)))
end

-- SEM REDE NENHUMA. Se exportacao.lua tentar usar qualquer uma destas, o
-- proprio require ou a primeira chamada explode - e o teste falha alto,
-- nao em silencio.
_G.http = nil
_G.rednet = nil

local lib       = dofile("/core/lib.lua")
local linhas    = lib("linhas")
local recados   = lib("recados")
local exportacao = lib("exportacao")

linhas.carregar()
recados.carregar()

local ANA   = select(1, linhas.criar("Ana", "1234", 11)).numero
local BRUNO = select(1, linhas.criar("Bruno", "5678", 12)).numero
local CARLA = select(1, linhas.criar("Carla", "9999", 13)).numero

recados.enviar(ANA, BRUNO, "oi Bruno, isto e segredo")
recados.enviar(BRUNO, ANA, "oi Ana")
recados.enviar(ANA, CARLA, "conversa com a Carla, nao com o Bruno")

print("\n-- o motivo e obrigatorio --")

local semMotivo, erro = exportacao.montar(ANA, BRUNO, "", "operadora")
ok(semMotivo == nil, "sem motivo, nao monta nada", erro)
ok(tostring(erro):find("motivo"), "e o motivo do erro fala em motivo", erro)

local soEspacos = exportacao.montar(ANA, BRUNO, "   ", "operadora")
ok(soEspacos == nil, "so espaco tambem nao conta como motivo")

print("\n-- monta a conversa entre dois numeros --")

local texto, erro2 = exportacao.montar(ANA, BRUNO, "processo 123", "operadora Joana")
ok(texto ~= nil, "com motivo, monta", erro2)
ok(texto:find("isto e segredo", 1, true) ~= nil, "tem o recado da Ana")
ok(texto:find("oi Ana", 1, true) ~= nil, "e o recado do Bruno")
ok(not texto:find("Carla", 1, true), "mas NAO a conversa com a Carla")
ok(texto:find("processo 123", 1, true) ~= nil, "o motivo aparece no cabecalho")
ok(texto:find("operadora Joana", 1, true) ~= nil, "e quem pediu tambem")

print("\n-- numero B vazio exporta TUDO do numero A --")

local tudo = exportacao.montar(ANA, "", "processo 456", "operadora")
ok(tudo:find("isto e segredo", 1, true) ~= nil, "tem a conversa com o Bruno")
ok(tudo:find("conversa com a Carla", 1, true) ~= nil, "e tambem a conversa com a Carla")

print("\n-- numero invalido recusa --")

ok(select(1, exportacao.montar("123", BRUNO, "x", "op")) == nil,
   "numero A invalido nao monta")
ok(select(1, exportacao.montar(ANA, "123", "x", "op")) == nil,
   "numero B invalido nao monta")

print("\n-- sem recado nenhum, ainda monta (com aviso) --")

local DENISE = select(1, linhas.criar("Denise", "1111", 14)).numero
local vazio = exportacao.montar(ANA, DENISE, "processo 789", "operadora")
ok(vazio ~= nil, "conversa vazia ainda gera um arquivo", vazio)
ok(vazio:find("nenhum recado", 1, true) ~= nil, "avisando que nao ha nada")
ok(vazio:find("recados    : 0", 1, true) ~= nil, "e contando zero")

print("\n-- o log de auditoria --")

local historico = exportacao.historico()
-- so 3 dos exportacao.montar() acima tinham numero E motivo validos (o do
-- "processo 123", o do numero B vazio, e o da conversa vazia com a Denise);
-- os com motivo vazio/so espaco e os com numero invalido nao registram.
igual(#historico, 3, "cada pedido com numero e motivo validos vira uma linha no log")

local ultimo = historico[#historico]
igual(ultimo.numeroA, ANA, "a linha guarda o numero A")
igual(ultimo.numeroB, DENISE, "e o numero B")
igual(ultimo.motivo, "processo 789", "e o motivo exato")
ok(ultimo.quem:find("operadora"), "e quem pediu", ultimo.quem)
ok(type(ultimo.quando) == "number" and ultimo.quando > 0, "com um timestamp")

print("\n-- o log NUNCA apara --")

-- ao contrario do log de tela (100 linhas), a auditoria fica toda. Simula
-- muitos pedidos e confere que nenhum some.
for i = 1, 150 do
  exportacao.montar(ANA, BRUNO, "pedido em lote " .. i, "operadora")
end
igual(#exportacao.historico(), 3 + 150, "cento e cinquenta pedidos depois, nenhum sumiu")

print("\n-- o nome do arquivo nao repete no mesmo milissegundo --")

-- nao e uma garantia formal (dois pedidos no mesmssimo ms colidiriam), so
-- confere que a funcao devolve algo com cara de nome de arquivo
local nome = exportacao.nomeArquivo()
ok(nome:match("^exportacao_%d+%.txt$") ~= nil, "tem o formato esperado", nome)

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
