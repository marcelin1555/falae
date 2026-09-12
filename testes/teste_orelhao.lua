--[[ teste_orelhao - ligacoes anonimas, sem PIN nem dono

  O orelhao nao e uma linha: nao tem sessao, nao pode ser bloqueado (nao ha
  "de" para comparar) e nao pode ser denunciado (denuncia.criar exige
  linhas.existe, que um orelhao nunca passa). O unico controle que quem
  recebe tem e um interruptor geral - aceitar ou nao QUALQUER ligacao
  anonima - porque nao ha como identificar quem ligou para bloquear so ele.
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

mock.disco("central")
mock.id = 8
mock.montarCentral(PROJETO, false)
mock.instalarDofile()

local lib     = dofile("/core/lib.lua")
local central = lib("central")
local linhas  = lib("linhas")
local recados = lib("recados")
central.prepararDados()

local CODIGO = "#240"

-- cria a linha direto por linhas.criar - mais curto que montar um telefone so
-- para tirar um numero, ja que este arquivo testa a rota, nao o app
local linhaA = linhas.criar("Ana", "1111")
local ANA = linhaA.numero

-- --------------------------------------------------------- codigo invalido

print("\n-- codigo de orelhao mal formado --")

for _, ruim in ipairs({ nil, "", "240", "orelhao", "#", "#24a" }) do
  local ok2, motivo = central.rotas["orelhao.ligar"]({ codigo = ruim, para = ANA, texto = "oi" })
  ok(not ok2, ("ligar recusa codigo [%s]"):format(tostring(ruim)), motivo)
end

-- ------------------------------------------------------------------ ligar

print("\n-- o orelhao liga para uma linha de verdade --")

local res, motivo = central.rotas["orelhao.ligar"]({
  codigo = CODIGO, para = ANA, texto = "quem fala?",
})
ok(res ~= nil, "a ligacao saiu", motivo)
igual(res and res.recado and res.recado.de, CODIGO,
      "o recado ficou com o codigo do orelhao como remetente")

-- Ana ve a mensagem pela MESMA rota que ja usa - msg.novidades nao muda nada
local resp = central.rotas["msg.novidades"]({ desde = 0, limite = 50 }, { numero = ANA })
ok(resp.recados and #resp.recados == 1, "Ana recebeu a ligacao pela rota normal")
igual(resp.recados[1].de, CODIGO, "com o codigo do orelhao, nao um numero de linha")

-- ----------------------------------------------------- recusa por preferencia

print("\n-- quem desligou ligacao anonima nao recebe --")

linhas.trocarAceitaAnonimo(ANA, false)
local recusado, motivoRecusa = central.rotas["orelhao.ligar"]({
  codigo = CODIGO, para = ANA, texto = "de novo",
})
ok(not recusado, "a central recusa a ligacao", motivoRecusa)

linhas.trocarAceitaAnonimo(ANA, true)
local aceito = central.rotas["orelhao.ligar"]({ codigo = CODIGO, para = ANA, texto = "de novo" })
ok(aceito ~= nil, "e volta a aceitar depois de ligar de novo")

-- --------------------------------------------------------------- responder

print("\n-- Ana responde, pela mesma msg.enviar de sempre --")

local respondeu, motivoResp = central.rotas["msg.enviar"](
  { para = CODIGO, texto = "quem e voce?" }, { numero = ANA })
ok(respondeu ~= nil, "msg.enviar aceita responder a um orelhao", motivoResp)
igual(respondeu and respondeu.recado and respondeu.recado.de, ANA,
      "o recado de resposta e da Ana")
igual(respondeu and respondeu.recado and respondeu.recado.para, CODIGO,
      "enderecado ao codigo do orelhao")

-- ---------------------------------------------------- o orelhao le a volta

print("\n-- o orelhao le a conversa e as novidades pelo proprio codigo --")

local conversa = central.rotas["orelhao.conversa"]({ codigo = CODIGO, com = ANA })
ok(conversa.recados and #conversa.recados >= 3, "a conversa inteira aparece",
   ("veio %d"):format(conversa.recados and #conversa.recados or -1))

local novidades = central.rotas["orelhao.novidades"]({ codigo = CODIGO, desde = 0 })
ok(novidades.recados and #novidades.recados >= 3, "e as novidades tambem")

-- --------------------------------------------------------------- denuncia

print("\n-- o orelhao nao pode ser denunciado --")

local denuncia, motivoDenuncia = central.rotas["denuncia.criar"](
  { numero = CODIGO }, { numero = ANA })
ok(not denuncia, "denuncia.criar recusa - o codigo do orelhao nao e uma linha", motivoDenuncia)

-- ----------------------------------------------------------------- encerrar

print("\n-- encerrar apaga tudo daquele orelhao, dos dois lados --")

local encerrou = central.rotas["orelhao.encerrar"]({ codigo = CODIGO })
ok(encerrou and encerrou.apagados > 0, "apagou os recados", encerrou and encerrou.apagados)

local depoisDeEncerrar = central.rotas["orelhao.conversa"]({ codigo = CODIGO, com = ANA })
igual(#depoisDeEncerrar.recados, 0, "nao sobrou nada na conversa deste orelhao")

-- a linha de Ana e as demais mensagens dela continuam intactas - encerrar so
-- apaga o que passou POR ESTE orelhao, nao a conta dela inteira
ok(linhas.existe(ANA), "a linha da Ana nao foi mexida")

-- --------------------------------------------------------- persiste no disco

print("\n-- de/para nao-numerico sobrevive a um recarregar do disco --")

central.rotas["orelhao.ligar"]({ codigo = CODIGO, para = ANA, texto = "de volta" })
recados.carregar()   -- simula um reinicio da central: le tudo de novo do log

local aposReiniciar = central.rotas["orelhao.conversa"]({ codigo = CODIGO, com = ANA })
igual(#aposReiniciar.recados, 1, "o recado do orelhao nao virou lixo no recarregar")
igual(aposReiniciar.recados[1].de, CODIGO, "com o codigo intacto")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
