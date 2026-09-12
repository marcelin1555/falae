--[[ teste_orelhao_app - o terminal do orelhao, ponta a ponta

  teste_orelhao.lua ja prova as rotas da central. Este arquivo prova o
  aplicativo em si: configurar o codigo na primeira ligacao, discar, mandar a
  primeira mensagem, receber uma resposta enquanto a chamada esta aberta, e
  desligar - conferindo que desligar apaga tudo da central (o pedido
  explicito de nao deixar rastro nenhum).
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
central.prepararDados()

-- a linha que vai receber a ligacao - criada direto, sem montar um telefone:
-- este arquivo testa o ORELHAO, o numero so precisa existir do outro lado
local linhaAna = linhas.criar("Ana", "1111")
local ANA = linhaAna.numero

mock.disco("orelhao1")
mock.montarOrelhao(PROJETO)
mock.redeDireta(central, 8, "central")

local carregar = dofile("/carregar.lua")
local app = carregar("app")

local function rodar(destino)
  local ok2, erro = pcall(app.rodar, destino)
  if not ok2 and not tostring(erro):find("FILA_VAZIA") then
    error(erro, 0)
  end
  return ok2
end

local function digitar(texto)
  for i = 1, #texto do mock.enfileirar("char", texto:sub(i, i)) end
end

--- Procura um texto em qualquer linha da tela - mais robusto que acertar a
-- linha exata, que depende da ordem em que os recados vieram da central.
local function telaTem(tela, altura, texto)
  for y = 1, altura do
    if tela.texto(y):find(texto, 1, true) then return true end
  end
  return false
end

-- ------------------------------------------------------------- primeiro uso

print("\n-- primeira ligacao: pede o codigo, disca, manda a primeira mensagem --")

mock.instalarEventos()
local tela = mock.monitor(51, 19)

digitar("240")                       -- codigo deste orelhao (primeira vez)
mock.enfileirar("key", keys.enter)
mock.enfileirar("key", keys.enter)   -- qualquer tecla comeca a discar
digitar(ANA)                         -- numero de quem vai receber
mock.enfileirar("key", keys.enter)
digitar("quem fala?")                -- a primeira mensagem, que "liga"
mock.enfileirar("key", keys.enter)

-- Ana responde, direto na central - como se o telefone dela tivesse
-- respondido de verdade. Isto roda AGORA, antes de mock.enfileirar("timer"),
-- entao quando o poll disparar dentro da MESMA chamada de app.rodar() a
-- resposta ja vai estar la para ele achar.
central.rotas["msg.enviar"]({ para = "#240", texto = "quem e voce?" }, { numero = ANA })

mock.enfileirar("timer", 1)   -- o poll da chamada busca essa resposta
-- SEM "Q" ainda de proposito: a fila acaba aqui, dentro do proprio laco da
-- chamada (o pullEvent logo depois de tratar o timer) - assim a tela para
-- exatamente com a transcricao na tela, antes de qualquer coisa apagar ela.
-- app.rodar() voltar para a tela ociosa depois de desligar (mais abaixo)
-- reescreve a tela inteira, entao so da para checar o conteudo ANTES disso.

rodar(tela)

igual(app.codigo(), "#240", "o codigo ficou gravado para a proxima vez")
ok(telaTem(tela, 19, "quem fala?"), "a primeira mensagem apareceu na tela")
ok(telaTem(tela, 19, "quem e voce?"), "e a resposta de Ana tambem, ainda com a chamada aberta")

-- ---------------------------------------------------------- desligar apaga

print("\n-- desligar apaga tudo daquele codigo na central --")

-- a chave por disquete (chave.usar) nao existe para o orelhao, entao nao ha
-- sessao de app.rodar() para "retomar" - mas isso nao importa aqui: o que
-- este bloco prova e a tecla Q em si, chamando fnet.orelhaoEncerrar. Como a
-- primeira mensagem ainda esta na central (o teste acima nao mexeu nisso),
-- uma chamada nova ao MESMO numero, seguida de Q, prova que desligar apaga
-- tudo daquele codigo - inclusive o que ficou de uma chamada anterior.
mock.instalarEventos()
tela = mock.monitor(51, 19)

mock.enfileirar("key", keys.enter)   -- comeca a discar direto - sem instalacao de novo
digitar(ANA)
mock.enfileirar("key", keys.enter)
digitar("de novo")
mock.enfileirar("key", keys.enter)
mock.enfileirar("key", keys.q)       -- desliga

rodar(tela)

local depois = central.rotas["orelhao.conversa"]({ codigo = "#240", com = ANA })
igual(#depois.recados, 0, "nada sobrou na central depois de Q desligar - nem o que ja estava")

local aRecebeu = central.rotas["msg.novidades"]({ desde = 0, limite = 50 }, { numero = ANA })
igual(aRecebeu.recados and #aRecebeu.recados or 0, 0,
      "e o proximo poll do telefone da Ana tambem nao acha mais nada")

igual(app.codigo(), "#240", "o codigo continua o mesmo, sem perguntar de novo")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
