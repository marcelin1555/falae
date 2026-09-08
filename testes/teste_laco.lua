--[[ teste_laco - o telefone continua buscando recado

  Este arquivo existe por causa de um bug que passou por todos os outros
  testes e so apareceu no jogo: a mensagem simplesmente nao chegava no
  destinatario.

  O laco do aplicativo criava um timer por volta e so agia se o evento fosse o
  timer DAQUELA volta. Mas os.pullEvent devolve todo tipo de evento, e o
  aparelho recebe modem_message toda vez que a central responde qualquer coisa.
  Ao cair num evento que o laco nao tratava, a volta seguinte criava outro
  timer sem cancelar o anterior - e dai em diante o timer que chegava era
  sempre o da volta passada, nunca igual ao da volta atual. A condicao nunca
  mais dava certo.

  O resultado no jogo: o telefone abria, desenhava, respondia ao teclado, e
  nunca mais perguntava nada a central. Sem erro na tela, sem nada no log.

  Nenhum dos outros testes podia pegar isso, porque todos chamavam as funcoes
  por dentro em vez de rodar o laco. Aqui o laco roda de verdade, com a fila de
  eventos na mao.
]]

local PROJETO = ...

local mock = dofile(PROJETO .. "/testes/cc_mock.lua")
mock.instalar()

local imprimir = print
local total, falhas = 0, 0

local function ok(condicao, titulo, detalhe)
  total = total + 1
  if condicao then
    imprimir("  ok   " .. titulo)
  else
    falhas = falhas + 1
    imprimir("  FALHA " .. titulo .. (detalhe and ("  -> " .. tostring(detalhe)) or ""))
  end
end

local function igual(a, b, titulo)
  ok(a == b, titulo, ("esperava [%s], veio [%s]"):format(tostring(b), tostring(a)))
end

-- ---------------------------------------------------------------- montagem

local ID_CENTRAL = 8

mock.disco("central")
mock.id = ID_CENTRAL
mock.montarCentral(PROJETO, false)
mock.instalarDofile()

local lib     = dofile("/core/lib.lua")
local central = lib("central")
central.prepararDados()

for _, nome in ipairs({ "pocketA", "pocketB" }) do
  mock.disco(nome)
  mock.montarTelefone(PROJETO)
end

mock.redeDireta(central, ID_CENTRAL, "central")

local carregar = dofile("/carregar.lua")
local fnet   = carregar("fnet")
local agenda = carregar("agenda")
local app    = carregar("app")

local function usar(aparelho, id)
  mock.disco(aparelho)
  mock.id = id
  fnet.central = nil
  agenda.carregar()
end

-- duas linhas
usar("pocketA", 101)
local _, linhaA = fnet.criarLinha("Ana", "1111")
local ANA = linhaA.numero

usar("pocketB", 102)
local _, linhaB = fnet.criarLinha("Bruno", "2222")
local BRUNO = linhaB.numero

-- ------------------------------------------------------- o laco de verdade

--- Roda o laco do telefone ate a fila de eventos acabar.
--
-- O app termina levantando FILA_VAZIA de dentro do pullEvent falso - e o jeito
-- de sair de um "while true" sem inventar uma condicao que so existe no teste.
local function rodarLaco(destino)
  local ok2, erro = pcall(app.rodar, destino)
  if not ok2 and not tostring(erro):find("FILA_VAZIA") then
    error(erro, 0)
  end
  return ok2
end

imprimir("\n-- o laco busca recado no timer --")

-- Ana manda para Bruno
usar("pocketA", 101)
local okE, rE = fnet.enviar(BRUNO, "chegou?")
ok(okE, "Ana mandou o recado", rE)

-- Bruno liga o telefone. Fila: so o timer.
usar("pocketB", 102)
mock.instalarEventos()
local tela = mock.monitor(26, 20)

mock.dispararTimer()   -- ainda nao ha timer: nao faz nada, e tudo bem
mock.enfileirar("timer", 1)

rodarLaco(tela)

ok(#agenda.conversa(BRUNO, ANA) > 0,
   "o recado chegou depois de um ciclo do laco")

-- ------------------------------------- o caso que quebrava: evento estranho

imprimir("\n-- com eventos que o laco nao trata no meio --")

-- Conta quantas vezes a central foi perguntada, e nao se o recado chegou: o
-- app faz UM buscar() no boot, antes do laco, entao o recado chega mesmo com o
-- laco quebrado. Foi exatamente isso no jogo - reiniciar o telefone mostrava a
-- mensagem, e com ele aberto nunca chegava nada. Medir o recado escondia o
-- defeito; medir as perguntas mostra.
local function perguntas()
  local c = central.estado.custo["msg.novidades"]
  return c and c.n or 0
end

usar("pocketA", 101)
fnet.enviar(BRUNO, "segunda mensagem")

usar("pocketB", 102)
mock.instalarEventos()
tela = mock.monitor(26, 20)

-- E ESTE o cenario do jogo. modem_message chega toda vez que a central
-- responde; peripheral e mouse_click acontecem sozinhos. Antes do conserto,
-- bastava UM destes para o telefone nunca mais buscar nada.
mock.enfileirar("modem_message", "back", 1, 2, "lixo")
mock.enfileirar("peripheral", "monitor_0")
mock.enfileirar("modem_message", "back", 1, 2, "mais lixo")
mock.enfileirar("mouse_click", 1, 3, 4)
mock.enfileirar("timer", 1)

local antesPerguntas = perguntas()
local antes = #agenda.conversa(BRUNO, ANA)
rodarLaco(tela)

ok(#agenda.conversa(BRUNO, ANA) > antes, "o recado chega")

-- O boot pergunta uma vez; o timer que vem depois dos eventos estranhos tem
-- que perguntar de novo. Com o laco quebrado, essa segunda pergunta nunca sai.
ok(perguntas() >= antesPerguntas + 2,
   "e o laco perguntou de novo DEPOIS do boot, apesar dos eventos estranhos",
   ("perguntas: %d -> %d"):format(antesPerguntas, perguntas()))
imprimir("\n-- e o timer nao acumula --")

usar("pocketB", 102)
mock.instalarEventos()
tela = mock.monitor(26, 20)

-- vinte eventos que o laco ignora, e nenhum timer
for i = 1, 20 do
  mock.enfileirar("modem_message", "back", 1, 2, "lixo " .. i)
end
rodarLaco(tela)

-- Antes do conserto isto criava 21 timers. Um laco que vaza timer enche a
-- fila de eventos do computador e come o tempo do pool de threads que todos
-- os computadores do mundo dividem.
ok(mock.timersVivos() <= 1,
   "20 eventos ignorados deixam no maximo UM timer vivo",
   ("vivos: %d, criados: %d"):format(mock.timersVivos(), mock.timersCriados))
ok(mock.timersCriados <= 2,
   "e o laco nao ficou criando timer a cada volta",
   ("criados: %d"):format(mock.timersCriados))

imprimir("\n-- tecla cancela o timer, nao vaza --")

usar("pocketB", 102)
mock.instalarEventos()
tela = mock.monitor(26, 20)

for i = 1, 10 do
  mock.enfileirar("key", mock.KEYS.down)
end
rodarLaco(tela)
ok(mock.timersVivos() <= 1, "dez teclas seguidas nao deixam timer para tras",
   ("vivos: %d"):format(mock.timersVivos()))
ok(mock.timersCancelados >= 9, "cada tecla cancelou o timer da vez",
   ("cancelados: %d"):format(mock.timersCancelados))

imprimir("\n-- varios ciclos seguidos continuam buscando --")

usar("pocketB", 102)
mock.instalarEventos()
tela = mock.monitor(26, 20)

-- alterna evento ignorado e timer, cinco vezes. Se o desalinhamento voltar,
-- so o primeiro ciclo busca e o teste falha no numero de recados.
mock.enfileirar("timer", 1)
for volta = 1, 5 do
  mock.enfileirar("modem_message", "back", 1, 2, "ruido")
  mock.dispararTimer()
end

local marcaAntes = #agenda.conversa(BRUNO, ANA)
usar("pocketA", 101)
for i = 1, 3 do fnet.enviar(BRUNO, "seguida " .. i) end
usar("pocketB", 102)

-- refaz a fila agora que ha recado novo para buscar
mock.instalarEventos()
mock.enfileirar("modem_message", "back", 1, 2, "ruido")
mock.enfileirar("timer", 1)
mock.enfileirar("modem_message", "back", 1, 2, "ruido")
rodarLaco(tela)

ok(#agenda.conversa(BRUNO, ANA) >= marcaAntes + 3,
   "os tres recados novos chegaram",
   ("tinha %d, agora %d"):format(marcaAntes, #agenda.conversa(BRUNO, ANA)))

imprimir(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
