--[[ teste_modal - o dialogo de um ou mais campos, direto, sem montar o app

  perguntar() e perguntarPin() (telefone/app.lua) sao hoje so um-liners em
  cima de modal.abrir(). Este arquivo testa o primitivo em si - tecla, toque,
  cancelar, foco entre campos - sem precisar montar central+telefone so para
  chegar num dialogo.
]]

local PROJETO = ...

local mock = dofile(PROJETO .. "/testes/cc_mock.lua")
mock.instalar()
mock.montarTelefone(PROJETO)
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

local carregar = dofile("/carregar.lua")
local modal = carregar("modal")

local C = { fundo = colors.black, texto = colors.white, fraco = colors.gray,
            marca = colors.yellow, entrada = colors.gray, selecao = colors.gray,
            bom = colors.lime, ruim = colors.red }

local function digitar(texto)
  for i = 1, #texto do mock.enfileirar("char", texto:sub(i, i)) end
end

-- --------------------------------------------------------- um campo so

print("\n-- um campo so, confirmando com Enter --")

mock.instalarEventos()
local tela = mock.monitor(26, 20)

digitar("Aninha")
mock.enfileirar("key", keys.enter)

local r = modal.abrir(tela, C, { { rotulo = "novo nome", opcoes = { max = 16 } } })
igual(r and r[1], "Aninha", "Enter no unico campo confirma")

print("\n-- um campo so, Tab cancela --")

mock.instalarEventos()
tela = mock.monitor(26, 20)

digitar("nao vale")
mock.enfileirar("key", keys.tab)

r = modal.abrir(tela, C, { { rotulo = "x", opcoes = { max = 16 } } })
igual(r, nil, "Tab cancela quando so ha um campo")

print("\n-- um campo so, toque no CONFIRMAR --")

mock.instalarEventos()
tela = mock.monitor(26, 20)

local w, h = tela.getSize()
local yCampo = math.min(5, h - 5)
local yConfirmar = yCampo + 3
local yCancelar = yCampo + 5

digitar("Bruno")
mock.enfileirar("mouse_click", 1, 3, yConfirmar)

r = modal.abrir(tela, C, { { rotulo = "x", opcoes = { max = 16 } } })
igual(r and r[1], "Bruno", "toque no CONFIRMAR confirma o valor digitado")

print("\n-- um campo so, toque em cancelar --")

mock.instalarEventos()
tela = mock.monitor(26, 20)

digitar("nao vale")
mock.enfileirar("mouse_click", 1, 3, yCancelar)

r = modal.abrir(tela, C, { { rotulo = "x", opcoes = { max = 16 } } })
igual(r, nil, "toque em cancelar cancela")

-- ---------------------------------------------------------- backspace vazio

print("\n-- um campo so, backspace com o campo vazio NAO cancela --")

-- perguntar() original nunca teve esse gesto - so o de dois campos (a troca
-- de PIN) tinha. modal.abrir precisa preservar essa diferenca: com um campo
-- so, backspace no vazio e so um backspace sem efeito, o dialogo continua
-- aberto esperando Enter ou Tab.
mock.instalarEventos()
tela = mock.monitor(26, 20)

mock.enfileirar("key", keys.backspace)
digitar("ok")
mock.enfileirar("key", keys.enter)

r = modal.abrir(tela, C, { { rotulo = "x", opcoes = { max = 16 } } })
igual(r and r[1], "ok", "backspace no campo vazio nao cancelou - so nao fez nada")

-- ------------------------------------------------------------- dois campos

print("\n-- dois campos, Tab troca de foco e Enter avanca/confirma --")

mock.instalarEventos()
tela = mock.monitor(26, 20)

digitar("1111")
mock.enfileirar("key", keys.enter)   -- avanca do campo 1 para o 2
digitar("2222")
mock.enfileirar("key", keys.enter)   -- confirma (ja esta no ultimo campo)

r = modal.abrir(tela, C, {
  titulo = "Trocar PIN",
  { rotulo = "PIN atual", opcoes = { max = 8, mascara = "pin" } },
  { rotulo = "PIN novo",  opcoes = { max = 8, mascara = "pin" } },
})
igual(r and r[1], "1111", "primeiro campo veio certo")
igual(r and r[2], "2222", "e o segundo tambem - Enter avancou, nao confirmou cedo demais")

print("\n-- dois campos, backspace no campo focado vazio cancela --")

mock.instalarEventos()
tela = mock.monitor(26, 20)

mock.enfileirar("key", keys.backspace)   -- campo 1 comeca vazio: cancela na hora

r = modal.abrir(tela, C, {
  { rotulo = "PIN atual", opcoes = { max = 8, mascara = "pin" } },
  { rotulo = "PIN novo",  opcoes = { max = 8, mascara = "pin" } },
})
igual(r, nil, "backspace no campo vazio cancelou, com dois campos")

print("\n-- dois campos, Tab troca o foco em vez de cancelar --")

mock.instalarEventos()
tela = mock.monitor(26, 20)

digitar("1111")
mock.enfileirar("key", keys.tab)      -- troca para o campo 2, sem cancelar
digitar("2222")
mock.enfileirar("key", keys.enter)    -- confirma

r = modal.abrir(tela, C, {
  { rotulo = "PIN atual", opcoes = { max = 8, mascara = "pin" } },
  { rotulo = "PIN novo",  opcoes = { max = 8, mascara = "pin" } },
})
igual(r and r[1], "1111", "campo 1 ficou com o que foi digitado antes do Tab")
igual(r and r[2], "2222", "e o Tab levou para o campo 2, nao cancelou o dialogo")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
