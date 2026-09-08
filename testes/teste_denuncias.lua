--[[ teste_denuncias - a unica porta pela qual um recado sai do aparelho

  A FALAE nao le mensagem de ninguem, e o teste_privacidade existe para
  garantir isso. A denuncia e a excecao, e ela so e aceitavel enquanto as tres
  regras dela valerem. Este arquivo e o que impede que uma delas caia sem
  ninguem perceber:

  1. O texto vem do HISTORICO DA CENTRAL, nunca do que o aparelho mandou. Se
     viesse do aparelho, qualquer um poderia inventar uma frase e atribui-la a
     outra pessoa - a denuncia viraria uma arma em vez de uma defesa. E o
     teste mais importante daqui.

  2. So o ULTIMO recado recebido. Nao a conversa.

  3. A resposta ao aparelho nao carrega texto de volta.

  A quarta regra - o painel nunca mostra o texto - e testada no teste_painel,
  porque e la que ela pode ser quebrada.
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

local lib       = dofile("/core/lib.lua")
local protocolo = lib("protocolo")
local central   = lib("central")
local denuncias = lib("denuncias")
local recados   = lib("recados")
local linhas    = lib("linhas")

central.prepararDados()

local function pedir(de, servico, acao, dados, token)
  return central.atender(de, {
    v = protocolo.VERSAO, id = math.random(1, 100000),
    servico = servico, acao = acao, token = token, dados = dados or {},
  })
end

-- tres pessoas: o Chato manda algo ruim para a Ana, e a Carla e a terceira
local rAna   = pedir(10, "linha", "criar", { nome = "Ana",   pin = "1111" })
local rChato = pedir(20, "linha", "criar", { nome = "Chato", pin = "2222" })
local rCarla = pedir(30, "linha", "criar", { nome = "Carla", pin = "3333" })

local ANA,   tAna   = rAna.dados.linha.numero,   rAna.dados.token
local CHATO, tChato = rChato.dados.linha.numero, rChato.dados.token
local CARLA, tCarla = rCarla.dados.linha.numero, rCarla.dados.token

-- ------------------------------------------------------------ o modulo

print("\n-- o texto vem do historico, nao do aparelho --")

-- Chamado direto, sem passar pela central, para deixar visivel que quem
-- decide o texto e a funcao de busca - e nao um argumento de fora.
local chamadas = {}
local d1 = denuncias.criar(ANA, CHATO, function(quem, deQuem)
  chamadas[#chamadas + 1] = { quem = quem, de = deQuem }
  return { texto = "o que ele escreveu de verdade", quando = mock.relogio }
end)

ok(d1 ~= nil, "a denuncia foi criada")
igual(d1.texto, "o que ele escreveu de verdade", "e o texto veio da busca")
igual(#chamadas, 1, "a busca foi chamada uma vez")
igual(chamadas[1].quem, ANA, "perguntando o que a Ana recebeu")
igual(chamadas[1].de, CHATO, "vindo do Chato")

-- sem recado daquela pessoa, nao ha o que denunciar
local nada, motivo = denuncias.criar(CARLA, CHATO, function() return nil end)
ok(nada == nil, "sem recado daquele numero, a denuncia e recusada", motivo)

ok(select(1, denuncias.criar(ANA, ANA, function() return { texto = "x" } end)) == nil,
   "nao da para denunciar a propria linha")

print("\n-- uma denuncia por par, enquanto a primeira espera --")
local repetida = denuncias.criar(ANA, CHATO, function()
  return { texto = "de novo", quando = mock.relogio }
end)
ok(repetida == nil, "apertar a tecla duas vezes nao vira duas denuncias")
igual(denuncias.quantasPendentes(), 1, "e a fila continua com uma")

print("\n-- o historico de um numero --")
denuncias.criar(CARLA, CHATO, function()
  return { texto = "comigo tambem", quando = mock.relogio }
end)

local vezes, pessoas = denuncias.historicoDe(CHATO)
igual(vezes, 2, "o Chato foi denunciado duas vezes")
igual(pessoas, 2, "por duas pessoas diferentes")

-- E a diferenca que muda a decisao da operadora: uma denuncia pode ser briga
-- de dois; duas pessoas diferentes sao outra coisa.
local _, sozinha = denuncias.historicoDe(CARLA)
igual(sozinha, 0, "e a Carla nunca foi denunciada")

print("\n-- resolver --")
igual(denuncias.quantasPendentes(), 2, "duas esperando")
ok(denuncias.resolver(d1.n, "arquivada") ~= nil, "arquiva a primeira")
igual(denuncias.quantasPendentes(), 1, "sobra uma")
ok(select(1, denuncias.resolver(d1.n)) == nil, "resolver de novo nao acha nada")

-- resolvida continua no historico: e o que a operadora consulta quando o mesmo
-- numero aparecer de novo
local aindaVezes = denuncias.historicoDe(CHATO)
igual(aindaVezes, 2, "a resolvida continua contando no historico do numero")

-- ---------------------------------------------------- pela central, de verdade

print("\n-- pela rota, como o telefone faz --")

-- o Chato manda algo para a Ana
pedir(20, "msg", "enviar", { para = ANA, texto = "mensagem ruim de verdade" }, tChato)
pedir(20, "msg", "enviar", { para = ANA, texto = "e mais uma pior ainda" }, tChato)

local antes = denuncias.quantasPendentes()
local r = pedir(10, "denuncia", "criar", { numero = CHATO }, tAna)
ok(r.ok, "a Ana denuncia o Chato", r.erro)
igual(denuncias.quantasPendentes(), antes + 1, "entrou na fila")

-- a resposta NAO devolve o texto: quem denunciou ja tem o recado no proprio
-- aparelho, e devolve-lo criaria mais um lugar por onde ele passa
local serializada = textutils.serialize(r.dados)
ok(not serializada:find("mensagem ruim", 1, true)
   and not serializada:find("pior ainda", 1, true),
   "e a resposta nao devolve o texto de volta")

print("\n-- so o ULTIMO recado recebido --")
local pendentes = denuncias.pendentes()
local nova = pendentes[1]
igual(nova.texto, "e mais uma pior ainda", "guardou o ultimo, e nao o primeiro")
ok(not tostring(nova.texto):find("mensagem ruim", 1, true),
   "o recado anterior nao foi junto")

print("\n-- o aparelho nao escolhe o texto --")

-- Uma quarta pessoa, porque a Carla ja denunciou o Chato la em cima e a regra
-- de uma denuncia por par recusaria a segunda - o teste estaria medindo a
-- regra errada.
local rDiego = pedir(40, "linha", "criar", { nome = "Diego", pin = "4444" })
local DIEGO, tDiego = rDiego.dados.linha.numero, rDiego.dados.token

-- O pedido leva um campo "texto" cheio de mentira. A central tem que ignorar:
-- se ela usasse, qualquer um poderia inventar uma frase e dizer que foi outro
-- quem escreveu.
pedir(20, "msg", "enviar", { para = DIEGO, texto = "oi diego" }, tChato)
local forjado = pedir(40, "denuncia", "criar",
                      { numero = CHATO,
                        texto = "FRASE INVENTADA PELO APARELHO" }, tDiego)
ok(forjado.ok, "o pedido com texto a mais e aceito", forjado.erro)

local doDiego
for _, d in ipairs(denuncias.pendentes()) do
  if d.de == DIEGO and d.sobre == CHATO then doDiego = d end
end
ok(doDiego ~= nil, "a denuncia do Diego existe")
igual(doDiego and doDiego.texto, "oi diego",
      "e o texto e o que o Chato escreveu de verdade")
ok(not (doDiego and tostring(doDiego.texto):find("INVENTADA", 1, true)),
   "o texto que o aparelho mandou foi ignorado")

-- e a regra do par continua valendo, que foi o que atrapalhou este teste
ok(not pedir(40, "denuncia", "criar", { numero = CHATO }, tDiego).ok,
   "denunciar o mesmo numero de novo e recusado enquanto a primeira espera")

print("\n-- denuncia nao vira porta de leitura --")

-- Carla denuncia um numero com quem nunca falou. Nao ha recado dela para
-- aquele numero, entao nao ha nada a entregar - e a recusa nao pode dizer
-- nada sobre a conversa dos outros.
local rIsolada = pedir(30, "denuncia", "criar", { numero = ANA }, tCarla)
ok(not rIsolada.ok, "denunciar quem nunca te escreveu e recusado")
ok(not tostring(rIsolada.erro):find("mensagem ruim", 1, true),
   "e a recusa nao vaza conversa alheia", rIsolada.erro)

ok(not pedir(30, "denuncia", "criar", { numero = CHATO }).ok,
   "sem sessao, nao se denuncia")
ok(not pedir(30, "denuncia", "criar", { numero = "5599999999999" }, tCarla).ok,
   "numero que nao existe e recusado")

-- ------------------------------------------------------------- esquecer

print("\n-- cassar uma linha leva as denuncias junto --")

local quantasAntes = denuncias.quantas()
local foram = denuncias.esquecer(CHATO)
ok(foram > 0, "some com as denuncias sobre ele", foram)
igual(denuncias.quantas(), quantasAntes - foram, "e a conta bate")
igual(select(1, denuncias.historicoDe(CHATO)), 0, "o historico dele zera")

-- dos DOIS lados: uma denuncia carrega um recado, e deixar a de quem denunciou
-- guardaria conversa de uma linha que a FALAE disse ter apagado
local d2 = denuncias.criar(ANA, CARLA, function()
  return { texto = "algo", quando = mock.relogio }
end)
ok(d2 ~= nil, "nova denuncia, agora da Ana sobre a Carla")
denuncias.esquecer(ANA)
igual(denuncias.historicoDe(CARLA), 0,
      "cassar quem DENUNCIOU tambem apaga a denuncia dela")

-- --------------------------------------------------------------- disco

print("\n-- sobrevive ao reinicio --")
denuncias.criar(CARLA, ANA, function()
  return { texto = "guardada", quando = mock.relogio }
end)
denuncias.salvar()

local outro = dofile("/core/denuncias.lua")
outro.carregar()
ok(outro.quantasPendentes() > 0, "as denuncias voltam do disco")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
