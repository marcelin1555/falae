--[[ teste_telemetria - a central manda numeros para fora, nunca texto

  O QUE MAIS IMPORTA AQUI: conferir de verdade, byte a byte no JSON que sairia
  pela rede, que nenhum texto de recado e nenhum numero de linha (nem o meu,
  nem o de ninguem) vai junto. O painel externo mostra saude, nao conversa.

  telemetria.coletar() e pura - sem rede - de proposito, para este teste poder
  provar a FORMA do snapshot sem precisar de http nenhum. telemetria.enviar()
  e testado com o http.post falso do cc_mock, que grava tudo que foi mandado
  para o teste inspecionar.
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

local lib         = dofile("/core/lib.lua")
local json        = lib("json")
local linhas      = lib("linhas")
local recados     = lib("recados")
local telemetria  = lib("telemetria")

linhas.carregar()
recados.carregar()

local ANA   = select(1, linhas.criar("Ana", "1234", 11)).numero
local BRUNO = select(1, linhas.criar("Bruno", "5678", 12)).numero
recados.enviar(ANA, BRUNO, "isto e um segredo que nao pode vazar")
recados.enviar(BRUNO, ANA, "outro segredo")

local estadoFalso = {
  desde = os.epoch("utc") - 60000, pedidos = 42, recusas = 3, rapidas = 900,
  modem = "ender_modem_0",
}
local custosFalsos = {
  { rota = "msg.novidades", n = 900, tempo = 0.5, media = 0.00055 },
  { rota = "linha.entrar", n = 4, tempo = 0.01, media = 0.0025 },
}

-- ------------------------------------------------------------------ coletar

print("\n-- coletar e uma funcao pura, sem rede --")

_G.http = nil  -- coletar NAO pode precisar disto
local snap = telemetria.coletar(estadoFalso, custosFalsos)
ok(snap ~= nil, "coleta sem http nenhum instalado")

igual(snap.linhas.total, 2, "conta as duas linhas")
igual(snap.recados.total, 2, "conta os dois recados")
igual(snap.denuncias.pendentes, 0, "sem denuncia pendente")
igual(snap.central.pedidos, 42, "os numeros do estado passam direto")
igual(snap.central.modem, true, "modem vira booleano, nao o nome do periferico")
igual(#snap.central.custos, 2, "as duas rotas de custo")
igual(snap.central.custos[1].rota, "msg.novidades", "na ordem que veio")

print("\n-- NADA que identifique uma pessoa ou uma conversa --")

local out = json.codificar(snap)

ok(not out:find("segredo", 1, true), "nenhum texto de recado no JSON")
ok(not out:find(ANA, 1, true), "nao tem o numero da Ana")
ok(not out:find(BRUNO, 1, true), "nem o do Bruno")
ok(not out:find("Ana", 1, true) and not out:find("Bruno", 1, true),
   "nem os nomes")

-- e para garantir que isto continua verdade se alguem mexer no snapshot
-- amanha: nenhum campo de nivel 1 ou 2 pode se chamar coisa que cheire a
-- identidade individual
local function nenhumCampoSuspeito(t, caminho)
  for k, v in pairs(t) do
    local nome = tostring(k):lower()
    ok(not nome:find("numero") and not nome:find("nome") and not nome:find("texto"),
       ("o campo '%s%s' nao existe no snapshot"):format(caminho, k))
    if type(v) == "table" and caminho:len() < 20 then
      nenhumCampoSuspeito(v, caminho .. tostring(k) .. ".")
    end
  end
end
nenhumCampoSuspeito(snap, "")

-- ------------------------------------------------------------------- config

print("\n-- configuracao --")

ok(not telemetria.configurado(), "sem arquivo, nao configurado")
ok(telemetria.lerConfig() == nil, "e le nil")

local okCfg, erroCfg = telemetria.gravarConfig("", "abc")
ok(not okCfg, "endereco vazio recusa", erroCfg)

local okCfg2, erroCfg2 = telemetria.gravarConfig("https://x.vercel.app/api/ingest", "")
ok(not okCfg2, "token vazio recusa", erroCfg2)

ok(telemetria.gravarConfig("https://x.vercel.app/api/ingest", "tok-123"),
   "com os dois, grava")
ok(telemetria.configurado(), "e ai fica configurado")

local cfg = telemetria.lerConfig()
igual(cfg.url, "https://x.vercel.app/api/ingest", "guarda o endereco")
igual(cfg.token, "tok-123", "e o token")

telemetria.apagarConfig()
ok(not telemetria.configurado(), "apagar volta ao estado sem painel")

-- --------------------------------------------------------------------- enviar

print("\n-- enviar sem configurar --")

local okEnv, motivoEnv = telemetria.enviar(estadoFalso, custosFalsos)
ok(not okEnv, "sem config, nao manda", motivoEnv)
ok(tostring(motivoEnv):find("configurado"), "e o motivo fala nisso")

print("\n-- enviar de verdade (com o http falso) --")

telemetria.gravarConfig("https://falae-painel.vercel.app/api/ingest", "tok-secreto")
mock.instalarHttpPost()

local okEnv2, erroEnv2 = telemetria.enviar(estadoFalso, custosFalsos)
ok(okEnv2, "manda com sucesso", erroEnv2)
igual(#mock.posts, 1, "um post foi feito")

local p = mock.posts[1]
igual(p.url, "https://falae-painel.vercel.app/api/ingest", "para o endereco configurado")
ok(p.cabecalhos["Authorization"] == "Bearer tok-secreto",
   "com o token no cabecalho Authorization", p.cabecalhos["Authorization"])
igual(p.cabecalhos["Content-Type"], "application/json", "como JSON")

-- o corpo do post e o mesmo snapshot, sem nada de recado
ok(not p.corpo:find("segredo", 1, true), "o corpo do post nao tem texto de recado")
local corpoDecodificado = textutils.unserialiseJSON and textutils.unserialiseJSON(p.corpo)
if corpoDecodificado then
  igual(corpoDecodificado.linhas.total, 2, "e o JSON decodifica de volta certinho")
end

ok(telemetria.ultimoEnvio ~= nil, "guarda quando foi o ultimo envio bem-sucedido")

print("\n-- quando a Vercel esta fora do ar --")

mock.httpPostFalhar("Connection refused")
local okEnv3, erroEnv3 = telemetria.enviar(estadoFalso, custosFalsos)
ok(not okEnv3, "nao manda", erroEnv3)
ok(tostring(erroEnv3):find("refused"), "e o motivo e o erro de rede, nao mascarado")

print("\n-- e ISSO NUNCA LEVANTA ERRO, so devolve false --")

local semExplodir = pcall(telemetria.enviar, estadoFalso, custosFalsos)
ok(semExplodir, "enviar() nunca da erro, mesmo com a rede fora - a central nao pode cair por causa disto")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
