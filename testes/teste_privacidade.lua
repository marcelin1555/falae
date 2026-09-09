--[[ teste_privacidade - o teste mais importante do projeto

  A FALAE e aberta: qualquer jogador tira uma linha, e portanto qualquer
  jogador tem um token valido e pode chamar qualquer rota. Toda a privacidade
  do sistema mora numa unica ideia - a central responde sempre sobre a linha DA
  SESSAO, nunca sobre a linha que o pedido pediu.

  Se isso vazar, ninguem percebe. Nao ha tela errada, nao ha lentidao, nao ha
  erro no log: o sistema continua parecendo funcionar enquanto entrega conversa
  alheia. E o tipo de falha que so aparece quando alguem descobre - e ai ja
  aconteceu.

  Por isso aqui os pedidos passam pela central de verdade (central.atender),
  como se tivessem chegado pelo modem, e nao pelos modulos por dentro.
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

local lib       = dofile("/core/lib.lua")
local protocolo = lib("protocolo")
local central   = lib("central")

central.prepararDados()

--- Manda um pedido como se tivesse chegado do computador <de>, pelo modem.
local function pedir(de, servico, acao, dados, token)
  return central.atender(de, {
    v = protocolo.VERSAO, id = math.random(1, 100000),
    servico = servico, acao = acao, token = token, dados = dados or {},
  })
end

-- ------------------------------------------------------------------ cenario

-- tres pessoas: Ana e Bruno conversam, Carla e a intrusa
local rAna   = pedir(10, "linha", "criar", { nome = "Ana",   pin = "1111" })
local rBruno = pedir(20, "linha", "criar", { nome = "Bruno", pin = "2222" })
local rCarla = pedir(30, "linha", "criar", { nome = "Carla", pin = "3333" })

local ANA,   tAna   = rAna.dados.linha.numero,   rAna.dados.token
local BRUNO, tBruno = rBruno.dados.linha.numero, rBruno.dados.token
local CARLA, tCarla = rCarla.dados.linha.numero, rCarla.dados.token

pedir(10, "msg", "enviar", { para = BRUNO, texto = "segredo da Ana para o Bruno" }, tAna)
pedir(20, "msg", "enviar", { para = ANA,   texto = "resposta do Bruno para a Ana" }, tBruno)

-- --------------------------------------------------------------- sem sessao

print("\n-- sem sessao nao se faz nada --")
for _, rota in ipairs({ "eu", "nome", "buscar" }) do
  local r = pedir(30, "linha", rota, { numero = ANA, nome = "x" })
  ok(not r.ok, "linha." .. rota .. " exige sessao")
end
for _, rota in ipairs({ "enviar", "novidades", "conversa", "conversas" }) do
  local r = pedir(30, "msg", rota, { para = ANA, com = ANA, texto = "oi" })
  ok(not r.ok, "msg." .. rota .. " exige sessao")
end
for _, rota in ipairs({ "listar", "por", "tirar" }) do
  local r = pedir(30, "bloq", rota, { numero = ANA })
  ok(not r.ok, "bloq." .. rota .. " exige sessao")
end

local inventado = pedir(30, "msg", "novidades", { desde = 0 }, "tokeninventado123")
ok(not inventado.ok, "token inventado nao abre nada")

-- O ping e a criacao de linha PRECISAM responder sem sessao: e por elas que
-- alguem que ainda nao tem linha nenhuma chega na FALAE.
ok(pedir(99, "central", "ping", {}).ok, "central.ping responde sem sessao, de proposito")

-- ------------------------------------------------- a conversa dos outros

print("\n-- Carla nao le a conversa de Ana com Bruno --")

local nov = pedir(30, "msg", "novidades", { desde = 0 }, tCarla)
ok(nov.ok, "Carla consegue perguntar por novidades dela")
ok(nov.dados.nada == true or #(nov.dados.recados or {}) == 0,
   "e nao vem recado nenhum - ela nao falou com ninguem")

-- a rota so aceita "desde"; nao existe um campo para pedir a caixa de outro,
-- e este teste garante que ninguem acrescente um por engano
local comNumero = pedir(30, "msg", "novidades",
                        { desde = 0, numero = ANA, linha = ANA, de = ANA }, tCarla)
ok(comNumero.ok, "pedido com campos a mais e aceito")
ok(comNumero.dados.nada == true or #(comNumero.dados.recados or {}) == 0,
   "mas os campos a mais sao ignorados - continua vindo vazio")

local conv = pedir(30, "msg", "conversa", { com = ANA }, tCarla)
ok(conv.ok, "Carla pode pedir a conversa dela com a Ana")
igual(#conv.dados.recados, 0, "e ela esta vazia - elas nunca falaram")

-- este e o cenario que mais assusta: Carla pedindo a conversa entre outros
-- dois. A rota interpreta "com = BRUNO" como "minha conversa com o Bruno",
-- entao ela recebe a dela, vazia - e nao a de Ana com Bruno.
local espiar = pedir(30, "msg", "conversa", { com = BRUNO }, tCarla)
igual(#espiar.dados.recados, 0, "pedir a conversa entre Ana e Bruno traz vazio")

-- A rota que devolvia a lista de conversas saiu: o aparelho monta a lista do
-- que ja tem em disco, e a central nao precisa varrer o historico para
-- responder o que o telefone ja sabe. Uma rota a menos e uma superficie a
-- menos - e esta era a unica que devolvia recado de VARIAS conversas de uma
-- vez, que e a forma mais util de vazamento que poderia existir aqui.
local semRota = pedir(30, "msg", "conversas", {}, tCarla)
ok(not semRota.ok, "a rota de listar conversas nao existe mais")

-- e nenhum texto da conversa alheia pode aparecer em lugar nenhum do que
-- Carla recebe: a busca abaixo e sobre a resposta inteira, serializada
local tudoQueCarlaViu = textutils.serialize({
  nov.dados, conv.dados, espiar.dados, semRota, comNumero.dados,
})
ok(not tudoQueCarlaViu:find("segredo da Ana", 1, true),
   "o texto da conversa alheia nao aparece em NADA que Carla recebeu")

-- ------------------------------------------------ nao dar para se passar

print("\n-- ninguem manda recado no nome de outro --")

-- Carla manda com o token dela mas escrevendo o numero da Ana no envelope
local forjado = pedir(30, "msg", "enviar",
                      { para = BRUNO, de = ANA, numero = ANA,
                        texto = "isto deveria parecer da Ana" }, tCarla)
ok(forjado.ok, "o envio em si e aceito")
igual(forjado.dados.recado.de, CARLA,
      "mas o remetente vem da SESSAO, nao do envelope")

-- e o Bruno tem que ver a Carla como remetente
local doBruno = pedir(20, "msg", "novidades", { desde = 0 }, tBruno)
local achouForjado = false
for _, m in ipairs(doBruno.dados.recados or {}) do
  if m.texto == "isto deveria parecer da Ana" then
    achouForjado = (m.de == CARLA)
  end
end
ok(achouForjado, "o Bruno recebe o recado marcado como da Carla")

-- --------------------------------------------------- o que a busca conta

print("\n-- a busca de numero conta o minimo --")
local achou = pedir(30, "linha", "buscar", { numero = ANA }, tCarla)
ok(achou.ok and achou.dados.existe, "acha uma linha que existe")
igual(achou.dados.linha.nome, "Ana", "e conta o nome, que e publico")
ok(achou.dados.linha.sal == nil and achou.dados.linha.resumo == nil,
   "mas nunca o sal nem o resumo do PIN")
ok(achou.dados.linha.visto == nil, "nem quando a pessoa foi vista")

local naoExiste = pedir(30, "linha", "buscar", { numero = "5599999999999" }, tCarla)
ok(naoExiste.ok and naoExiste.dados.existe == false, "diz que nao existe sem explodir")

print("\n-- linha.eu so fala de quem perguntou --")
local eu = pedir(30, "linha", "eu", {}, tCarla)
igual(eu.dados.numero, CARLA, "Carla recebe a linha da Carla")
ok(eu.dados.resumo == nil and eu.dados.sal == nil, "sem segredo na resposta")

-- e trocar o nome vale so para a propria linha
pedir(30, "linha", "nome", { nome = "Invasora", numero = ANA }, tCarla)
local anaAgora = pedir(10, "linha", "eu", {}, tAna)
igual(anaAgora.dados.nome, "Ana", "trocar nome com o numero da Ana no pedido nao mexe nela")
local carlaAgora = pedir(30, "linha", "eu", {}, tCarla)
igual(carlaAgora.dados.nome, "Invasora", "mexeu na propria, que era o esperado")

-- ------------------------------------------------------------------ lixo

print("\n-- lixo que chega pelo modem --")
ok(not pedir(30, "naoexiste", "nadinha", {}, tCarla).ok, "rota desconhecida e recusada")
ok(not protocolo.valido(nil), "envelope nulo nao passa")
ok(not protocolo.valido({ v = 99, id = 1, servico = "a", acao = "b" }),
   "envelope de outra versao nao passa")
ok(not protocolo.valido({ v = 1, id = 1, servico = "msg", acao = "enviar", token = 5 }),
   "token que nem e texto nao passa")

print("\n-- sair --")
-- sair vale para a sessao do token apresentado, e so para ela. Nao ha como
-- derrubar a sessao de outro: para mandar o pedido no nome dela, seria preciso
-- ja ter o token dela - e quem tem o token dela ja e ela.
local tBruno2 = pedir(21, "linha", "entrar",
                      { numero = BRUNO, pin = "2222" }).dados.token
ok(pedir(20, "linha", "sair", {}, tBruno).dados.saiu, "sair fecha a sessao do token usado")
ok(not pedir(20, "linha", "eu", {}, tBruno).ok, "o token usado para sair morre")
ok(pedir(21, "linha", "eu", {}, tBruno2).ok,
   "e a OUTRA sessao da mesma linha continua viva")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
