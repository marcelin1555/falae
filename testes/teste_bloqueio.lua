--[[ teste_bloqueio - quem voce nao quer ouvir

  Duas coisas para provar, e a segunda e a que se esquece:

  1. O recado de quem foi bloqueado nao chega.
  2. Quem foi bloqueado NAO DESCOBRE que foi.

  A segunda importa porque a FALAE e aberta e uma linha custa nada. Se a
  central respondesse "voce foi bloqueado", a pessoa chata simplesmente tiraria
  outra linha e voltaria. Ela precisa achar que a mensagem foi entregue e que
  o outro lado nao quis responder.
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
local recados   = lib("recados")

central.prepararDados()

local function pedir(de, servico, acao, dados, token)
  return central.atender(de, {
    v = protocolo.VERSAO, id = math.random(1, 100000),
    servico = servico, acao = acao, token = token, dados = dados or {},
  })
end

local rAna  = pedir(10, "linha", "criar", { nome = "Ana",  pin = "1111" })
local rChato = pedir(20, "linha", "criar", { nome = "Chato", pin = "2222" })
local ANA,   tAna   = rAna.dados.linha.numero,   rAna.dados.token
local CHATO, tChato = rChato.dados.linha.numero, rChato.dados.token

-- ------------------------------------------------------------------- antes

print("\n-- antes de bloquear --")
pedir(20, "msg", "enviar", { para = ANA, texto = "oi oi oi oi" }, tChato)
local caixa = pedir(10, "msg", "novidades", { desde = 0 }, tAna)
igual(#caixa.dados.recados, 1, "o recado dele chega normalmente")

-- ---------------------------------------------------------------- bloquear

print("\n-- bloquear --")
local bloq = pedir(10, "bloq", "por", { numero = CHATO }, tAna)
ok(bloq.ok and bloq.dados.bloqueado, "Ana bloqueia o Chato")

local lista = pedir(10, "bloq", "listar", {}, tAna)
igual(#lista.dados.bloqueados, 1, "ele aparece na lista dela")
igual(lista.dados.bloqueados[1].numero, CHATO, "com o numero certo")
igual(lista.dados.bloqueados[1].nome, "Chato", "e com o nome, para ela saber quem e")
ok(type(lista.dados.bloqueados[1].quando) == "number",
   "e quando: a tela de bloqueados mostra ha quanto tempo")

ok(not pedir(10, "bloq", "por", { numero = ANA }, tAna).ok,
   "nao da para bloquear a propria linha")

-- ------------------------------------------------------------------ depois

print("\n-- depois de bloquear --")
local antesDoN = recados.ultimo(ANA)
local tentativa = pedir(20, "msg", "enviar",
                        { para = ANA, texto = "oi de novo, responde ai" }, tChato)

-- A resposta tem que ser indistinguivel de um envio que deu certo. Se ela
-- viesse com ok=false, bloquear viraria um aviso.
ok(tentativa.ok, "a central responde ao Chato como se tivesse entregue")
ok(tentativa.dados.recado ~= nil, "e devolve um recado, do mesmo formato de sempre")
ok(not (tentativa.erro or ""):find("bloque"), "nada na resposta fala em bloqueio")

igual(recados.ultimo(ANA), antesDoN, "mas nada foi guardado para a Ana")

local caixa2 = pedir(10, "msg", "novidades", { desde = caixa.dados.ultimo }, tAna)
ok(caixa2.dados.nada == true or #(caixa2.dados.recados or {}) == 0,
   "e nada novo aparece na caixa dela")

-- o Chato tambem nao pode descobrir olhando a propria caixa
local caixaChato = pedir(20, "msg", "novidades", { desde = 0 }, tChato)
local aparece = false
for _, m in ipairs(caixaChato.dados.recados or {}) do
  if m.texto:find("responde ai") then aparece = true end
end
ok(not aparece, "o recado recusado tambem nao entra na caixa de quem mandou")

print("\n-- o bloqueio e de mao unica --")
-- Ana bloqueou o Chato; ela continua podendo falar com ele se quiser
local dela = pedir(10, "msg", "enviar", { para = CHATO, texto = "para de me mandar msg" }, tAna)
ok(dela.ok and dela.dados.recado.n > 0, "Ana ainda consegue mandar para ele")
local doChato = pedir(20, "msg", "novidades", { desde = 0 }, tChato)
local recebeu = false
for _, m in ipairs(doChato.dados.recados or {}) do
  if m.texto:find("para de me mandar") then recebeu = true end
end
ok(recebeu, "e ele recebe")

-- ---------------------------------------------------------------- desfazer

print("\n-- desbloquear --")
ok(pedir(10, "bloq", "tirar", { numero = CHATO }, tAna).dados.tirado, "Ana desbloqueia")
igual(#pedir(10, "bloq", "listar", {}, tAna).dados.bloqueados, 0, "a lista esvazia")

pedir(20, "msg", "enviar", { para = ANA, texto = "desculpa" }, tChato)
local caixa3 = pedir(10, "msg", "novidades", { desde = caixa.dados.ultimo }, tAna)
local voltou = false
for _, m in ipairs(caixa3.dados.recados or {}) do
  if m.texto == "desculpa" then voltou = true end
end
ok(voltou, "o recado dele volta a chegar")

ok(not pedir(10, "bloq", "tirar", { numero = CHATO }, tAna).dados.tirado,
   "desbloquear duas vezes nao explode")

-- ------------------------------------------------------------------ limite

print("\n-- limites e limpeza --")
local bloqueio = lib("bloqueio")
local vitima = "5511100009999"
for i = 1, bloqueio.MAX do
  bloqueio.por(vitima, ("55111000%05d"):format(i))
end
igual(bloqueio.quantos(vitima), bloqueio.MAX, "a lista enche ate o limite")
ok(select(1, bloqueio.por(vitima, "5511100008888")) == nil, "e recusa passar do limite")

-- numero sorteado volta a circular um dia; se a lista nao esquecesse a linha
-- cassada, o proximo dono do numero nasceria bloqueado sem entender por que
bloqueio.por(ANA, CHATO)
bloqueio.esquecer(CHATO)
ok(not bloqueio.bloqueado(ANA, CHATO), "cassar uma linha tira ela das listas dos outros")
igual(bloqueio.quantos(CHATO), 0, "e apaga a lista dela")

-- ------------------------------------------------------------- save antigo

print("\n-- um bloqueio de antes do 'quando' --")

-- registro[dono][alvo] era `true`, sem data. Um save assim nao pode quebrar
-- so porque a tela de bloqueados aprendeu a mostrar ha quanto tempo.
local ANTIGA = "5511100007777"
bloqueio.por(ANA, ANTIGA)
-- mexe direto no arquivo, simulando o que um save de antes desta versao tinha
local store = lib("store")
local registro = store.carregar(bloqueio.CAMINHO, {})
registro[ANA][ANTIGA] = true
store.salvar(bloqueio.CAMINHO, registro)
bloqueio.carregar()

ok(bloqueio.bloqueado(ANA, ANTIGA), "continua contando como bloqueado")
local achouAntiga = false
for _, item in ipairs(bloqueio.listar(ANA)) do
  if item.numero == ANTIGA then
    achouAntiga = true
    igual(item.quando, nil, "sem data - a tela mostra '-' em vez de quebrar")
  end
end
ok(achouAntiga, "e ele aparece na lista mesmo assim")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
