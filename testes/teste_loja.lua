--[[ teste_loja - o terminal de balcao

  Tres coisas para provar, e as tres sao especificas da loja - o resto
  (a crueza do chave/chaveiro/tranca) ja tem teste_chave.lua inteiro so para
  isso:

  1. NAO GUARDA SESSAO. E um terminal PUBLICO, usado por gente diferente o dia
     inteiro. app.lua chama fnet.pedir() direto (nao fnet.criarLinha, que
     grava token em disco) - o teste confere que fnet.ARQUIVO nunca existe no
     disco da loja, nem depois de uma venda.

  2. A COBRANCA ACONTECE ANTES DO PEDIDO. Recusar o pagamento nao manda nada
     para a central nem soma na contagem de vendas.

  3. A ADMINISTRACAO E DA LOJA, NAO DA CENTRAL. O chaveiro da loja e um
     arquivo proprio, sem nenhuma relacao com o chaveiro da central - uma
     chave que abre a central nao abre a loja, e vice-versa (isto ja e
     testado a fundo por chaveiro.conferir() no papel; aqui so confere que
     admin.lua liga os dois modulos certos).
]]

local PROJETO = ...

local mock = dofile(PROJETO .. "/testes/cc_mock.lua")
mock.instalar()

-- mock.instalarTerm() (mais abaixo) redefine o print global para escrever no
-- terminal falso da loja, em vez do console real - guarda a referencia
-- original ANTES disso, como teste_laco.lua ja faz pelo mesmo motivo.
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
local ID_LOJA    = 20

mock.disco("central")
mock.id = ID_CENTRAL
mock.montarCentral(PROJETO, false)
mock.instalarDofile()

local lib     = dofile("/core/lib.lua")
local central = lib("central")
central.prepararDados()

mock.disco("loja")
mock.id = ID_LOJA
mock.montarLoja(PROJETO)

-- rede: a loja fala com a central de verdade (via o disco "central"), como
-- teste_laco.lua e teste_telefone.lua ja fazem para o telefone
mock.redeDireta(central, ID_CENTRAL, "central")

-- redeDireta troca os perifericos por so um modem - o drive precisa entrar
-- DEPOIS, sem apagar o modem que acabou de ser instalado
local drive = mock.drive("left")
mock.perifericos({ mock.modem("ender_modem_0", true), drive })

local carregar = dofile("/carregar.lua")
local app   = carregar("app")
local admin = carregar("admin")
local janela = carregar("janela")
local numero = carregar("numero")
local fnet   = carregar("fnet")
local chaveiro = carregar("chaveiro")

-- app.lua e admin.lua guardam o modulo `carregar("admin")`/`carregar("app")`
-- em cima do mesmo cache que /carregar.lua ja usa - nada a fazer aqui, so
-- confirmar que os dois carregaram sem se travar num require circular
ok(app ~= nil and admin ~= nil, "app.lua e admin.lua carregam sem se travar um no outro")

local tela = mock.instalarTerm(51, 19)  -- tambem vira _G.term, para bater com
                                        -- tranca.lerPin/tranca.abrir (raw term)

--- Roda uma funcao (app.rodar, admin.tela...) ate a fila de eventos acabar -
-- o mesmo truque de teste_laco.lua para sair de um "while true" sem inventar
-- condicao de teste.
local function rodar(fn, ...)
  local args = { ... }
  local ok2, erro = pcall(fn, table.unpack(args))
  if not ok2 and not tostring(erro):find("FILA_VAZIA") then
    error(erro, 0)
  end
  return ok2
end

--- Enfileira um "char" por letra/digito de um texto.
local function digitar(texto)
  for i = 1, #texto do mock.enfileirar("char", texto:sub(i, i)) end
end

-- ------------------------------------------------------------------- preco

imprimir("\n-- preco e vendas, guardados em disco --")

igual(app.preco(), app.PRECO_PADRAO, "sem configurar, usa o padrao")
ok(app.definirPreco(5), "define um preco novo")
igual(app.preco(), 5, "e ele fica valendo")
ok(not app.definirPreco(-1), "preco negativo recusa")
igual(app.preco(), 5, "sem mudar o que ja estava")

igual(app.vendas(), 0, "comeca sem vendas")

-- ------------------------------------------------------ comprar de verdade

imprimir("\n-- um cliente compra uma linha --")

mock.instalarEventos()
mock.enfileirar("key", keys.enter)   -- toque para comecar
digitar("Ana"); mock.enfileirar("key", keys.enter)     -- nome
digitar("1234"); mock.enfileirar("key", keys.enter)    -- PIN
digitar("1234"); mock.enfileirar("key", keys.enter)    -- PIN de novo
mock.enfileirar("key", keys.s)        -- confirma a cobranca
mock.enfileirar("key", keys.enter)    -- sai da tela de resultado

local antesVendas = app.vendas()
local antesLinhas = (function()
  mock.disco("central")
  local n = lib("linhas").quantas()
  mock.disco("loja")
  return n
end)()

rodar(app.rodar, tela)

igual(app.vendas(), antesVendas + 1, "a venda foi contada")
ok(not fs.exists(fnet.ARQUIVO),
   "e NENHUMA sessao ficou gravada no disco da loja - e um terminal publico")

local depoisLinhas = (function()
  mock.disco("central")
  local n = lib("linhas").quantas()
  mock.disco("loja")
  return n
end)()
igual(depoisLinhas, antesLinhas + 1, "e a linha existe de verdade, do lado da central")

-- --------------------------------------------------------- cancelar a compra

imprimir("\n-- recusar o pagamento nao manda nada --")

mock.instalarEventos()
mock.enfileirar("key", keys.enter)
digitar("Bru"); mock.enfileirar("key", keys.enter)
digitar("5678"); mock.enfileirar("key", keys.enter)
digitar("5678"); mock.enfileirar("key", keys.enter)
mock.enfileirar("key", keys.n)   -- CANCELA a cobranca

local antesVendas2 = app.vendas()
rodar(app.rodar, tela)
igual(app.vendas(), antesVendas2, "nenhuma venda nova - o cliente desistiu de pagar")

-- ------------------------------------------------------------- administracao

imprimir("\n-- a loja ainda nao tem chave --")

chaveiro.carregar()
ok(chaveiro.vazio(), "chaveiro da loja comeca vazio")

local C = { fundo = colors.black, texto = colors.white, fraco = colors.gray,
            marca = colors.yellow, entrada = colors.gray, bom = colors.lime, ruim = colors.red }
local dados = { preco = app.preco, definirPreco = app.definirPreco, vendas = app.vendas }
local jAdmin = janela.tela(tela)

local PIN = "88889999"

imprimir("\n-- reivindicar a administracao --")

drive.por(77)
mock.instalarEventos()
digitar("dono"); mock.enfileirar("key", keys.enter)   -- nome da chave
digitar(PIN); mock.enfileirar("key", keys.enter)      -- PIN novo
digitar(PIN); mock.enfileirar("key", keys.enter)      -- PIN de novo
mock.enfileirar("key", keys.enter)                    -- "(tecla)" apos "chave gravada"
mock.enfileirar("key", keys.q)                        -- sai do menu de administracao
rodar(admin.tela, jAdmin, C, dados)

ok(not chaveiro.vazio(), "a loja tem dona agora")
igual(chaveiro.listar()[1].papel, "loja", "e a chave e do papel 'loja'")

imprimir("\n-- entrar de novo na administracao pede a chave --")

drive.por(77)
mock.instalarEventos()
mock.enfileirar("key", keys.two)   -- escolhe "vendas"
digitar(PIN); mock.enfileirar("key", keys.enter)   -- PIN certo
mock.enfileirar("key", keys.enter)                 -- sai da tela de vendas
mock.enfileirar("key", keys.q)
rodar(admin.tela, jAdmin, C, dados)

igual(chaveiro.quantas(), 1, "so ver vendas nao cria nem duplica chave nenhuma")

imprimir("\n-- PIN errado nao abre --")

drive.por(77)
mock.instalarEventos()
mock.enfileirar("key", keys.one)   -- escolhe "preco"
digitar("00000000"); mock.enfileirar("key", keys.enter)   -- PIN errado
mock.enfileirar("key", keys.enter)   -- "(tecla)" do aviso de recusa
mock.enfileirar("key", keys.q)
rodar(admin.tela, jAdmin, C, dados)
igual(app.preco(), 5, "o preco continua o mesmo - o PIN errado nao mudou nada")

imprimir("\n-- com a chave certa, muda o preco --")

drive.por(77)
mock.instalarEventos()
mock.enfileirar("key", keys.one)   -- escolhe "preco"
digitar(PIN); mock.enfileirar("key", keys.enter)   -- PIN certo
mock.enfileirar("key", keys.n)                     -- "novo preco"
digitar("9"); mock.enfileirar("key", keys.enter)
mock.enfileirar("key", keys.enter)   -- "(tecla)" apos "preco alterado"
mock.enfileirar("key", keys.q)   -- sai da tela de preco
mock.enfileirar("key", keys.q)   -- sai do menu de administracao
rodar(admin.tela, jAdmin, C, dados)
igual(app.preco(), 9, "o preco mudou, com a chave certa")

imprimir("\n-- sem disquete no drive, a administracao nem pergunta PIN --")

drive.tirar()
mock.instalarEventos()
mock.enfileirar("key", keys.one)
mock.enfileirar("key", keys.enter)   -- "(tecla)" do aviso ("sem disquete no drive")
mock.enfileirar("key", keys.q)
rodar(admin.tela, jAdmin, C, dados)
igual(app.preco(), 9, "e nada muda sem a chave")

imprimir(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
