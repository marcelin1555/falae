--[[ teste_telefone - dois aparelhos e uma central, no mesmo processo

  Aqui a FALAE inteira roda: dois pockets com disco proprio, uma central com o
  disco dela, e uma rede que entrega os pedidos de um lado para o outro. E o
  mais perto do jogo que se chega sem abrir o jogo.

  O que so aparece neste nivel, e por isso vale o trabalho de montar tudo:

    - a sessao que fica no disco do aparelho e o token que vai em cada pedido
      sao a mesma coisa? (se nao forem, cada tela funciona sozinha e o telefone
      nao funciona)
    - o recado sai de um pocket e chega no outro?
    - a caixa do aparelho e a da central concordam sobre o que ja foi visto?
    - emprestar o telefone, entrar com outra linha e sair devolve o aparelho
      limpo?
]]

local PROJETO = ...

local mock = dofile(PROJETO .. "/testes/cc_mock.lua")
mock.instalar()

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

-- ---------------------------------------------------------------- montagem

local ID_CENTRAL = 8

-- a central, no disco dela
mock.disco("central")
mock.id = ID_CENTRAL
mock.montarCentral(PROJETO, false)
mock.instalarDofile()

local lib     = dofile("/core/lib.lua")
local central = lib("central")
central.prepararDados()

-- dois aparelhos, cada um com o proprio disco
for _, nome in ipairs({ "pocketA", "pocketB" }) do
  mock.disco(nome)
  mock.montarTelefone(PROJETO)
end

mock.redeDireta(central, ID_CENTRAL, "central")

-- O carregador guarda os modulos em _G, entao trocar de disco nao troca o que
-- ja esta na memoria. Um aparelho de verdade so tem a si mesmo; aqui os dois
-- dividem o processo, e e o teste que precisa fazer o papel do "ligar o outro
-- pocket": reler o que e do disco.
local carregar = dofile("/carregar.lua")
local fnet   = carregar("fnet")
local agenda = carregar("agenda")
local numero = carregar("numero")

local function usar(aparelho, id)
  mock.disco(aparelho)
  mock.id = id
  fnet.central = nil        -- cada aparelho descobre a central por conta
  agenda.carregar()
end

-- ------------------------------------------------------------------ criar

print("\n-- tirar linha nos dois aparelhos --")

usar("pocketA", 101)
local okA, linhaA = fnet.criarLinha("Ana", "1111")
ok(okA, "o pocket A tirou uma linha", linhaA)
ok(linhaA and #linhaA.numero == 13, "com numero de 13 digitos")
local ANA = linhaA.numero

local sessaoA = fnet.sessao()
ok(sessaoA ~= nil, "e a sessao ficou gravada no disco do aparelho")
igual(sessaoA.numero, ANA, "com o numero certo")
ok(sessaoA.token ~= nil, "e com token")
ok(sessaoA.pin == nil, "o PIN NAO fica gravado no aparelho")

usar("pocketB", 102)
ok(fnet.sessao() == nil, "o pocket B ainda nao tem linha - discos separados")
local okB, linhaB = fnet.criarLinha("Bruno", "2222")
ok(okB, "o pocket B tirou a dele", linhaB)
local BRUNO = linhaB.numero
ok(ANA ~= BRUNO, "os dois numeros sao diferentes")

-- ------------------------------------------------------------------ falar

print("\n-- um manda, o outro recebe --")

usar("pocketA", 101)
local okE, rE = fnet.enviar(BRUNO, "e ai, ta na base?")
ok(okE, "Ana manda um recado para o Bruno", rE)
agenda.meu(rE.recado)

usar("pocketB", 102)
local okN, rN = fnet.novidades(agenda.desde())
ok(okN, "Bruno pergunta se tem novidade", rN)
ok(not rN.nada, "e tem")
igual(#rN.recados, 1, "um recado")
igual(rN.recados[1].texto, "e ai, ta na base?", "com o texto certo")
igual(rN.recados[1].de, ANA, "e vindo da Ana")

agenda.receber(rN.recados, rN.ultimo)
local conversas = agenda.conversas(BRUNO)
igual(#conversas, 1, "a conversa aparece na lista do aparelho")
igual(conversas[1].numero, ANA, "com a Ana")
igual(conversas[1].naoLidos, 1, "marcada como nao lida")

print("\n-- o segundo pedido nao traz nada de novo --")
local _, rVazio = fnet.novidades(agenda.desde())
ok(rVazio.nada == true, "a central responde pelo caminho rapido")
igual(agenda.receber({}, rVazio.ultimo), 0, "e nada e somado a caixa")

print("\n-- responder --")
local okR, rR = fnet.enviar(ANA, "to indo agora")
ok(okR, "Bruno responde")
agenda.meu(rR.recado)
agenda.marcarLido(BRUNO, ANA)
igual(agenda.naoLidos(BRUNO), 0, "abrir a conversa zera os nao lidos")

usar("pocketA", 101)
local _, rA = fnet.novidades(agenda.desde())
agenda.receber(rA.recados, rA.ultimo)
local conversaAna = agenda.conversa(ANA, BRUNO)
igual(#conversaAna, 2, "a Ana ve as duas falas na conversa")
igual(conversaAna[1].texto, "e ai, ta na base?", "na ordem certa: a dela primeiro")
igual(conversaAna[2].texto, "to indo agora", "e a resposta depois")

-- ---------------------------------------------------------------- agenda

print("\n-- a agenda e do aparelho --")
agenda.salvar(BRUNO, "Bruno da obra")
igual(agenda.como(BRUNO, "Bruno"), "Bruno da obra",
      "o apelido que voce deu ganha do nome publico")

usar("pocketB", 102)
igual(agenda.como(ANA, "Ana"), "Ana",
      "e o outro aparelho nao tem o apelido - a agenda nao viaja")
ok(agenda.apelido(ANA) == nil, "nem por acidente")

-- ------------------------------------------------------------- repeticao

print("\n-- recado repetido nao duplica --")
usar("pocketA", 101)
local antes = #agenda.conversa(ANA, BRUNO)
-- e o que acontece quando um pacote se perde e o pedido e repetido
local _, rRep = fnet.novidades(0)
agenda.receber(rRep.recados, rRep.ultimo)
igual(#agenda.conversa(ANA, BRUNO), antes,
      "pedir tudo de novo nao repete o que ja estava na caixa")

-- ---------------------------------------------------------- outro aparelho

print("\n-- a linha anda entre aparelhos --")
-- e a diferenca entre a FALAE e a rede da Expresso Labs: la o cracha e do
-- computador, aqui a linha e da pessoa
mock.disco("pocketC")
mock.montarTelefone(PROJETO)
usar("pocketC", 103)

ok(fnet.sessao() == nil, "o pocket C esta zerado")
local okC, linhaC = fnet.entrar(ANA, "1111")
ok(okC, "a Ana entra na linha dela num aparelho emprestado", linhaC)
igual(linhaC.numero, ANA, "e e a mesma linha")

local _, rC = fnet.novidades(0)
agenda.receber(rC.recados, rC.ultimo)
igual(#agenda.conversa(ANA, BRUNO), 2,
      "as conversas dela estao la - elas moram na central")
ok(agenda.apelido(BRUNO) == nil,
   "mas a agenda do outro aparelho nao veio junto, como avisado")

print("\n-- PIN errado --")
mock.disco("pocketD")
mock.montarTelefone(PROJETO)
usar("pocketD", 104)
local okX, motivo = fnet.entrar(ANA, "9999")
ok(not okX, "PIN errado nao entra")
ok(fnet.sessao() == nil, "e nao deixa sessao nenhuma no aparelho", motivo)

-- ------------------------------------------------------------------- sair

print("\n-- devolver o aparelho emprestado --")
usar("pocketC", 103)
ok(fnet.sessao() ~= nil, "o pocket C esta com a linha da Ana")
ok(#agenda.conversa(ANA, BRUNO) > 0, "e com a conversa dela em disco")

fnet.sair()
agenda.limpar()

ok(fnet.sessao() == nil, "sair apaga a sessao do aparelho")
igual(#agenda.conversa(ANA, BRUNO), 0,
      "e apaga a conversa - o proximo dono do pocket nao le a de quem usou antes")
igual(agenda.quantos(), 0, "e a agenda tambem")

-- e a linha continua viva no aparelho dela
usar("pocketA", 101)
ok(fnet.sessao() ~= nil, "o aparelho original da Ana continua logado")
local okEu, eu = fnet.eu()
ok(okEu and eu.numero == ANA, "e a central ainda reconhece a linha dela")

-- ---------------------------------------------------------------- bloqueio

print("\n-- bloquear pelo aparelho --")
usar("pocketB", 102)
ok(fnet.bloquear(ANA), "Bruno bloqueia a Ana")

usar("pocketA", 101)
local okB2, rB2 = fnet.enviar(BRUNO, "oi?")
ok(okB2, "a Ana continua achando que mandou")
ok(not (tostring(rB2 and rB2.erro or ""):find("bloque")),
   "e nada na resposta conta que ela foi bloqueada")

usar("pocketB", 102)
local antesB = #agenda.conversa(BRUNO, ANA)
local _, rB3 = fnet.novidades(agenda.desde())
agenda.receber(rB3.recados, rB3.ultimo)
igual(#agenda.conversa(BRUNO, ANA), antesB, "mas o recado nao chegou nele")

-- --------------------------------------------------------------- sem sinal

print("\n-- a central some --")
usar("pocketA", 101)
local antesSem = #agenda.conversa(ANA, BRUNO)

-- desliga a rede: e o que acontece quando o chunk da central descarrega, ou
-- quando o pocket entra no Nether longe de um Ender Modem
local redeMorta = {
  enviar = function() end,
  receber = function() return nil end,
  procurar = function() return nil end,
}
mock.instalarRede(redeMorta)
fnet.central = nil

local okSem, motivoSem = fnet.novidades(0)
ok(not okSem, "pedir sem central falha", motivoSem)
ok(tostring(motivoSem):find("sinal") or tostring(motivoSem):find("respondeu"),
   "e o motivo fala em sinal, nao num erro de programa", motivoSem)

-- E o que mais importa: o aparelho continua util. O que ja estava em disco
-- continua la, e a pessoa continua lendo as conversas dela.
igual(#agenda.conversa(ANA, BRUNO), antesSem,
      "e a conversa continua legivel no aparelho, sem rede nenhuma")
ok(#agenda.conversas(ANA) > 0, "e a lista de conversas tambem")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
