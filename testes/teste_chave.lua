--[[ teste_chave - a chave por disquete

  A pergunta que este arquivo responde e uma so: DA PARA ABRIR A FALAE SEM O
  DISQUETE DE VERDADE?

  As tentativas que uma pessoa faria, e que o teste faz:

    - copiar chave.falae para outro disquete
    - editar o campo "disco" do arquivo para o id do disquete novo
    - chutar o PIN
    - ler o disco da central e montar uma chave a partir do que esta la
    - descobrir, so olhando o disquete, se o PIN chutado esta certo

  A ultima e a mais importante e a menos obvia. Se o disquete soubesse conferir
  o PIN, quem o achasse no chao adivinharia em casa, sem freio e sem rastro. E
  por isso que chave.abrir devolve lixo em vez de erro quando o PIN esta errado
  - e por isso que ha um teste so para provar que ele nao denuncia nada.
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

local lib      = dofile("/core/lib.lua")
local chave    = lib("chave")
local chaveiro = lib("chaveiro")
local tranca   = lib("tranca")

tranca.usar(chave, chaveiro)

local drive = mock.drive("drive_0")
mock.perifericos({ drive })

local PIN = "91827364"

-- ------------------------------------------------------------------ resumo

print("\n-- o resumo --")

igual(#chave.resumir("abc", 1), 32, "o resumo tem 128 bits (32 digitos hex)")
ok(chave.resumir("abc", 1) ~= chave.resumir("abd", 1),
   "textos diferentes dao resumos diferentes")
igual(chave.resumir("abc", 1), chave.resumir("abc", 1), "e o mesmo texto da o mesmo")

-- Um djb2 sozinho da 32 bits, e 32 bits colidem cedo demais para uma coisa que
-- abre porta. As quatro sementes tem que produzir quatro pedacos diferentes.
local r = chave.resumir("falae", 1)
local pedacos = {}
for i = 1, 4 do pedacos[i] = r:sub(i * 8 - 7, i * 8) end
local todosIguais = pedacos[1] == pedacos[2] and pedacos[2] == pedacos[3]
ok(not todosIguais, "as quatro sementes nao produzem o mesmo pedaco quatro vezes", r)

print("\n-- o XOR --")
local a, b = "abcdef01", "1234abcd"
igual(chave.xorHex(chave.xorHex(a, b), b), a, "xor duas vezes volta ao original")

-- ------------------------------------------------------------------ selar

print("\n-- selar e abrir --")

local segredo = chave.novoSegredo()
igual(#segredo, chave.SEGREDO_DIGITOS, "o segredo tem o tamanho combinado")

local selo = chave.selar(7, segredo, PIN)
igual(selo.disco, 7, "o selo anota de que disquete ele e")
ok(selo.cifrado ~= segredo, "e o segredo nao fica em claro dentro dele")
ok(not tostring(textutils.serialize(selo)):find(segredo, 1, true),
   "o segredo nao aparece em lugar nenhum do arquivo")

igual(chave.abrir(selo, 7, PIN), segredo, "com o disquete e o PIN certos, abre")

-- ---------------------------------------------------- o que uma pessoa tenta

print("\n-- copiar o arquivo para outro disquete --")

-- ESTE E O TESTE QUE SUSTENTA O PROJETO INTEIRO. O arquivo copia; o id do
-- disquete, nao. Como a conta usa o id lido do DRIVE, a copia deriva outro
-- fluxo e sai outro segredo.
ok(chave.abrir(selo, 8, PIN) ~= segredo,
   "o mesmo arquivo em outro disquete NAO devolve o segredo")

-- e nao adianta editar o arquivo para dizer que e o disquete 8: o campo
-- "disco" do selo nao entra na conta, quem entra e o drive
local editado = {}
for k, v in pairs(selo) do editado[k] = v end
editado.disco = 8
ok(chave.abrir(editado, 8, PIN) ~= segredo,
   "nem editando o campo 'disco' do arquivo para o id novo")

print("\n-- chutar o PIN --")
ok(chave.abrir(selo, 7, "000000") ~= segredo, "PIN errado nao devolve o segredo")

-- E A PARTE QUE MAIS IMPORTA: o disquete nao sabe dizer que o PIN esta errado.
-- Se soubesse, quem o achasse no chao adivinharia em casa, sem freio nenhum.
local comErrado, motivo = chave.abrir(selo, 7, "000000")
ok(comErrado ~= nil and motivo == nil,
   "e o disquete NAO denuncia o erro - devolve lixo, calado", tostring(motivo))
igual(#comErrado, #segredo, "lixo do mesmo tamanho, para nem o tamanho contar")

-- ---------------------------------------------------------------- chaveiro

print("\n-- o chaveiro da maquina --")

chaveiro.carregar()
ok(chaveiro.vazio(), "central nova nasce sem dono")

local k = chaveiro.inscrever(7, "mestra", "central", segredo, chave)
ok(k ~= nil, "inscreve a primeira chave")
ok(not chaveiro.vazio(), "e ai ela tem dono")
igual(chaveiro.quantas(), 1, "uma chave")

-- LER O DISCO DA CENTRAL NAO DA UMA CHAVE. O que esta gravado e a impressao.
local noDisco = textutils.serialize(chaveiro.de(7))
ok(not noDisco:find(segredo, 1, true),
   "o segredo NAO esta no disco da central - so a impressao dele")

ok(chaveiro.conferir(7, segredo, "central", chave) ~= nil,
   "o segredo certo confere")
ok(select(1, chaveiro.conferir(7, "0000000000000000000000000000000f", "central", chave)) == nil,
   "um segredo errado nao confere")
ok(select(1, chaveiro.conferir(9, segredo, "central", chave)) == nil,
   "e um disquete que nao esta inscrito nao confere")

-- a recusa tem que ser a mesma, para nao contar a quem achou um disquete no
-- chao se ele e uma chave de verdade
local _, semChave = chaveiro.conferir(9, segredo, "central", chave)
chaveiro.de(7).erros = 0
local _, pinErrado = chaveiro.conferir(7, "00000000000000000000000000000000", "central", chave)
igual(semChave, pinErrado, "disquete desconhecido e segredo errado recusam igual")

print("\n-- o freio --")
local kk = chaveiro.de(7)
kk.erros, kk.travadaAte = 0, nil
local travou = false
for _ = 1, 6 do
  local _, m = chaveiro.conferir(7, "00000000000000000000000000000000", "central", chave)
  if tostring(m):find("espere") then travou = true end
end
ok(travou, "errar seguido trava a chave")
ok(chaveiro.travada(7) > 0, "e a trava tem prazo", chaveiro.travada(7) .. "s")

-- travada, nem o segredo certo entra
ok(select(1, chaveiro.conferir(7, segredo, "central", chave)) == nil,
   "travada, nem o segredo certo abre")

kk.erros, kk.travadaAte = 0, nil
ok(chaveiro.conferir(7, segredo, "central", chave) ~= nil, "destravada, abre de novo")

print("\n-- papeis --")
local segredoLoja = chave.novoSegredo()
chaveiro.inscrever(21, "vitrine", "loja", segredoLoja, chave)
ok(chaveiro.conferir(21, segredoLoja, "loja", chave) ~= nil, "a chave da loja abre a loja")
ok(select(1, chaveiro.conferir(21, segredoLoja, "central", chave)) == nil,
   "e NAO abre a central")
ok(chaveiro.conferir(7, segredo, "loja", chave) ~= nil,
   "a chave da central abre a loja tambem - quem manda, manda")

print("\n-- revogar --")
ok(chaveiro.remover(21), "revoga a chave da loja")
ok(select(1, chaveiro.conferir(21, segredoLoja, "loja", chave)) == nil,
   "e ela para de abrir na hora")
ok(select(1, chaveiro.remover(7)) == nil,
   "mas nao da para revogar a ultima - a central ficaria sem dono")

-- ------------------------------------------------------------------ tranca

print("\n-- a tranca, com drive de verdade --")

drive.tirar()
ok(select(1, tranca.disco()) == nil, "sem disquete, nao ha id")
ok(not tranca.presente("central"), "e a maquina fica trancada")

drive.por(7)
igual(tranca.disco(), 7, "com o disquete, o id vem do DRIVE")
ok(tranca.presente("central"), "o disquete inscrito destranca o boot")

drive.por(8)
ok(not tranca.presente("central"), "outro disquete nao destranca")

-- emitir grava no disquete e inscreve
drive.por(30)
local nova, erro = tranca.emitir("segunda", "central", PIN)
ok(nova ~= nil, "emite uma chave nova no disquete que estiver no drive", erro)
ok(tranca.presente("central"), "e ela ja destranca")

-- o arquivo foi mesmo para o disquete, e so para ele
ok(fs.exists("disco30/" .. chave.ARQUIVO), "o arquivo esta no disquete 30")
ok(not fs.exists("disco8/" .. chave.ARQUIVO), "e nao no 8")

print("\n-- a copia do arquivo, ponta a ponta --")

-- Alguem le o disquete 30, copia chave.falae para o disquete 8, e tenta.
local orig = fs.open("disco30/" .. chave.ARQUIVO, "r")
local conteudo = orig.readAll()
orig.close()
fs.makeDir("disco8")
local copia = fs.open("disco8/" .. chave.ARQUIVO, "w")
copia.write(conteudo)
copia.close()

drive.por(8)
ok(tranca.lerSelo(drive.dev) ~= nil, "a copia esta la e e legivel")
ok(not tranca.presente("central"),
   "mas o disquete 8 continua sem abrir nada - o id nao copiou")

-- E LEVAR A COPIA PARA A CENTRAL DE VERDADE tambem nao adianta: o chaveiro
-- procura pelo id do disquete, e o 8 nao esta la. E nem se estivesse: o
-- segredo que sai do selo no disquete 8 nao e o mesmo que a central inscreveu
-- para o 30, porque o id entra na conta.
local seloCopiado = tranca.lerSelo(drive.dev)
ok(select(1, chaveiro.conferir(8, chave.abrir(seloCopiado, 8, PIN), "central", chave)) == nil,
   "levar a copia para a central nao abre nada")

local segredoNoOito = chave.abrir(seloCopiado, 8, PIN)
local segredoNoTrinta = chave.abrir(seloCopiado, 30, PIN)
ok(segredoNoOito ~= segredoNoTrinta,
   "o mesmo arquivo em disquetes diferentes deriva segredos diferentes")

-- o que a central inscreveu para o 30 e o que sai do selo NO 30
ok(chaveiro.conferir(30, segredoNoTrinta, "central", chave) ~= nil,
   "e so o do disquete 30 confere com o que a central guardou")

-- ------------------------------------------------------------------ sessao

print("\n-- a sessao do balcao --")

drive.por(30)
local kNova = chaveiro.de(30)
local sessao = tranca.novaSessao(kNova, 30)
ok(tranca.sessaoValida(sessao), "sessao vale com o disquete no drive")

drive.tirar()
ok(not tranca.sessaoValida(sessao),
   "tirar o disquete tranca na hora, sem esperar o prazo")

drive.por(30)
ok(tranca.sessaoValida(sessao), "e volta a valer quando ele volta")

drive.por(8)
ok(not tranca.sessaoValida(sessao), "outro disquete no drive nao serve")

drive.por(30)
sessao.ate = os.epoch("utc") - 1
ok(not tranca.sessaoValida(sessao), "e a sessao vencida tambem nao vale")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
