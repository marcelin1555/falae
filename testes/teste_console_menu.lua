--[[ teste_console_menu - o rodape do menu principal do balcao, pelo dedo

  console.lua NUNCA teve teste proprio antes desta sessao - so os modulos que
  ele chama (denuncias.lua, exportacao.lua...) eram testados. A divisao em
  console_*.lua (ver console.lua) e o botao de toque no menu principal
  (janela.rodape/janela.acaoNoRodape, o mesmo mecanismo que
  telefone/telas/conversas.lua ja usa) sao coisa nova o bastante para merecer
  um teste de verdade: clicar no rodape tem que chamar a MESMA tela que a
  tecla chamaria, e nao travar o laco.
]]

local PROJETO = ...

-- mock.instalarTerm() (mais abaixo) redefine o print global para escrever no
-- terminal falso, em vez do console real - guarda a referencia ANTES disso,
-- como teste_loja.lua ja faz pelo mesmo motivo.
local imprimir = print

local mock = dofile(PROJETO .. "/testes/cc_mock.lua")
mock.instalar()

mock.disco("central")
mock.id = 8
mock.montarCentral(PROJETO, false)
mock.instalarDofile()

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

local lib = dofile("/core/lib.lua")
local central = lib("central")
local console = lib("console")
central.prepararDados()
console.ligar(central)

-- Uma tela LARGA de proposito: com os 51 do Computer padrao, os ultimos itens
-- do rodape ("K chaves" em diante) nem cabem no texto - o mesmo corte que a
-- string fixa original ja sofria (texto:sub(1, w)). Testar num terminal largo
-- separa "o mecanismo de toque funciona" de "cabe nesta largura", que sao
-- duas perguntas diferentes.
mock.instalarTerm(120, 19)

local function rodar()
  local ok2, erro = pcall(console.laco)
  if not ok2 and not tostring(erro):find("FILA_VAZIA") then
    error(erro, 0)
  end
end

-- --------------------------------------------------------- toque em "T telas"

imprimir("\n-- toque em 'T telas' abre a mesma tela que a tecla T --")

-- "L linhas"(2-9) "R PIN"(12-16) "X cassar"(19-26) "D denuncias"(29-39)
-- "J judicial"(42-51) "K chaves"(54-61) "P painel"(64-71) "C custo"(74-80)
-- "G log"(83-87) "T telas"(90-96) "Q sai"(99-103)
local COL_T = 92   -- dentro de "T telas" (90-96)
local COL_Q = 100  -- dentro de "Q sai" (99-103)

mock.instalarEventos()
mock.enfileirar("mouse_click", 1, COL_T, 19)   -- toca em "T telas", linha do rodape
mock.enfileirar("key", keys.q)                 -- sai da tela de monitores
mock.enfileirar("mouse_click", 1, COL_Q, 19)   -- toca em "Q sai", encerra o laco

rodar()

ok(not central.estado.rodando, "o toque em Q sai encerrou o laco (via T no meio)")

-- ------------------------------------------------ toque fora do rodape

imprimir("\n-- toque fora da linha do rodape nao ativa nada --")

central.estado.rodando = true
mock.instalarEventos()
mock.enfileirar("mouse_click", 1, COL_Q, 5)   -- mesma coluna de "Q sai", linha ERRADA
mock.enfileirar("key", keys.q)                -- so a tecla mesmo encerra

rodar()

ok(not central.estado.rodando, "precisou da tecla Q - o clique fora do rodape nao contou")

imprimir(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
