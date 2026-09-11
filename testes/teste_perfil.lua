--[[ teste_perfil - trocar nome, trocar PIN e liberar bloqueado, pelo dedo

  As telas de nome/PIN so tinham teclado: confirmar era Enter, cancelar era
  Tab - invisivel para quem usa o pocket com o dedo, a mesma falha que a barra
  da conversa tinha antes do "<". Este arquivo prova que agora os dois
  caminhos - tecla e toque - chegam no mesmo lugar, rodando app.rodar() de
  verdade, contra uma central de verdade (via mock.redeDireta).
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

mock.disco("central")
mock.id = ID_CENTRAL
mock.montarCentral(PROJETO, false)
mock.instalarDofile()

local lib     = dofile("/core/lib.lua")
local central = lib("central")
local linhasSrv = lib("linhas")
local bloqueioSrv = lib("bloqueio")
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

usar("pocketA", 101)
local _, linhaA = fnet.criarLinha("Ana", "1111")
local ANA = linhaA.numero

usar("pocketB", 102)
local _, linhaB = fnet.criarLinha("Bruno", "2222")
local BRUNO = linhaB.numero

usar("pocketA", 101)

--- Roda app.rodar() ate a fila de eventos acabar - o mesmo truque de
-- teste_laco.lua para sair de um "while true" sem inventar condicao de teste.
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

-- ------------------------------------------------------------ trocar o nome

print("\n-- trocar o nome, confirmando com o dedo --")

mock.instalarEventos()
local tela = mock.monitor(26, 20)

-- A geometria de perguntar() e simples e fixa (ver telefone/app.lua): o botao
-- CONFIRMAR e uma barra full-width, tocavel em QUALQUER coluna da linha dela
-- - por isso o teste so precisa acertar a LINHA, calculada com a mesma conta
-- que o codigo usa.
local w20, h20 = tela.getSize()
local yCampoNome = math.min(5, h20 - 5)
local yConfirmarNome = yCampoNome + 3
local yCancelarNome = yCampoNome + 5

mock.enfileirar("key", keys.p)          -- conversas -> perfil
mock.enfileirar("key", keys.enter)      -- item 1 (nome) -> "perfil:nome"
digitar("Aninha")
mock.enfileirar("mouse_click", 1, 5, yConfirmarNome)

rodar(tela)

igual(linhasSrv.publico(ANA).nome, "Aninha", "o nome mudou na central")

local sessao = fnet.sessao()
igual(sessao.nome, "Aninha", "e a sessao do aparelho tambem")

-- ---------------------------------------------------------------- cancelar

print("\n-- cancelar com o dedo nao muda nada --")

mock.instalarEventos()
mock.enfileirar("key", keys.p)
mock.enfileirar("key", keys.enter)
digitar("Nome Que Nao Vale")
mock.enfileirar("mouse_click", 1, 5, yCancelarNome)
rodar(tela)

igual(linhasSrv.publico(ANA).nome, "Aninha",
      "o nome continua o de antes - cancelar tocando funciona")

-- ------------------------------------------------------------- trocar o PIN

print("\n-- trocar o PIN, os dois campos e o toque --")

mock.instalarEventos()
mock.enfileirar("key", keys.p)
mock.enfileirar("key", keys.down)   -- item 2: PIN
mock.enfileirar("key", keys.enter)  -- "perfil:pin"

digitar("1111")                      -- PIN atual, campo ja focado
mock.enfileirar("key", keys.enter)   -- avanca para o campo novo
digitar("9999")                      -- PIN novo

local yAtualPin = math.min(5, h20 - 9)
local yConfirmarPin = yAtualPin + 4 + 3
mock.enfileirar("mouse_click", 1, 3, yConfirmarPin)

-- trocar o PIN derruba a sessao e poe e.rodando=false: app.rodar() TERMINA
-- sozinho (retorna true), sem precisar do FILA_VAZIA.
local terminou = app.rodar(tela)
ok(terminou, "app.rodar() volta normalmente depois de trocar o PIN")
ok(fnet.sessao() == nil, "a sessao caiu - precisa entrar nesta linha de novo")

usar("pocketA", 101)
local okNovo = fnet.entrar(ANA, "9999")
ok(okNovo, "o PIN novo funciona")
ok(not fnet.entrar(ANA, "1111"), "e o antigo nao funciona mais")

-- ------------------------------------------------------------ bloqueados

print("\n-- ver e liberar um bloqueado, pelo dedo --")

usar("pocketA", 101)
fnet.entrar(ANA, "9999")
ok(fnet.bloquear(BRUNO), "Ana bloqueia o Bruno")
ok(bloqueioSrv.bloqueado(ANA, BRUNO), "e a central registra")

mock.instalarEventos()
mock.enfileirar("key", keys.p)      -- perfil
mock.enfileirar("key", keys.down)
mock.enfileirar("key", keys.down)
mock.enfileirar("key", keys.enter)  -- item 3: "perfil:bloq" -> busca e troca de tela

-- a lista tem 1 bloqueado (Bruno); a linha dele comeca 2 celulas abaixo do
-- topo, como bloqueados.lua desenha
mock.enfileirar("mouse_click", 1, 5, 2)   -- toca na linha do Bruno

rodar(tela)

ok(not bloqueioSrv.bloqueado(ANA, BRUNO), "o toque liberou o Bruno de verdade")

-- --------------------------------------------------- renomear pela lista

print("\n-- renomear direto na lista de conversas, pelo dedo --")

-- precisa de uma conversa para aparecer na lista; sem isso nao ha item nem
-- badge para tocar
local okEnv = fnet.enviar(BRUNO, "oi de novo")
ok(okEnv, "Ana manda um recado para o Bruno")

mock.instalarEventos()
tela = mock.monitor(26, 20)

-- o app.rodar() busca ao ligar; a conversa com o Bruno ja aparece como item
-- 1, selecionado por padrao - e e nele que o badge "E" sai, na coluna w-2
mock.enfileirar("mouse_click", 1, 26 - 2, 2)   -- toca no badge E do item 1
digitar("Amigo")
mock.enfileirar("key", keys.enter)

rodar(tela)

local agendaMod = carregar("agenda")
igual(agendaMod.apelido(BRUNO), "Amigo",
      "o toque no badge da lista salvou o apelido, sem abrir a conversa")

-- ------------------------------------------------- atalho D com char de verdade

print("\n-- denunciar pela tecla D, com o par key+char de uma tecla de verdade --")

-- O CC dispara "key" e "char" para toda letra premida de verdade -
-- mock.enfileirarTecla simula os dois, na ordem certa. Sem o
-- descartarCharPendente em telefone/app.lua, o "char" de "D" sobraria e viraria
-- o primeiro caractere digitado no dialogo (a resposta "ds" nunca bateria com
-- "s", e a denuncia nunca sairia - o bug relatado).
--
-- denunciar exige um recado DO denunciado - Ana so tinha mandado para o
-- Bruno ate aqui; o Bruno manda um de volta para a denuncia ter o que citar.
usar("pocketB", 102)
fnet.entrar(BRUNO, "2222")
fnet.enviar(ANA, "responde ai")

usar("pocketA", 101)
fnet.entrar(ANA, "9999")

local denunciasSrv = lib("denuncias")
local antes = denunciasSrv.quantasPendentes()

mock.instalarEventos()
tela = mock.monitor(26, 20)

mock.enfileirar("key", keys.enter)      -- abre a conversa com o Bruno (item 1)
mock.enfileirarTecla("d")               -- atalho D: key + char juntos, de verdade
digitar("s")
mock.enfileirar("key", keys.enter)      -- confirma "s"

rodar(tela)

igual(denunciasSrv.quantasPendentes(), antes + 1,
      "a denuncia saiu - o 'd' nao vazou para dentro da resposta")

-- ------------------------------------------------- atalho S com char de verdade

print("\n-- salvar contato pela tecla S, com o par key+char de uma tecla de verdade --")

mock.instalarEventos()
tela = mock.monitor(26, 20)

mock.enfileirar("key", keys.enter)      -- abre a conversa com o Bruno (item 1)
mock.enfileirarTecla("s")               -- atalho S: key + char juntos, de verdade
digitar("Bru")
mock.enfileirar("key", keys.enter)

rodar(tela)

igual(agendaMod.apelido(BRUNO), "Bru",
      "o apelido virou 'Bru', nao 'sBru' - o 's' do atalho nao vazou")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
