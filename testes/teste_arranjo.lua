--[[ teste_arranjo - a matematica do layout, sem montar o app

  arranjo.montar decide quantas telas aparecem e em que retangulo cada uma
  desenha, so a partir do tamanho da tela e dos 3 campos de estado que
  importam (tela, aberta, foco). Puro o bastante para testar direto, sem
  precisar de um app.rodar() inteiro.
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
local arranjo = carregar("arranjo")

-- ---------------------------------------------------------------- largo()

print("\n-- largo() --")

local pocket = mock.monitor(26, 20)
local computador = mock.monitor(51, 19)

ok(not arranjo.largo(pocket), "um pocket de 26 colunas nao e largo")
ok(arranjo.largo(computador), "um computador de 51 colunas e largo")

-- ------------------------------------------------------------- uma so tela

print("\n-- pocket: uma tela por vez --")

local partes = arranjo.montar(pocket, { tela = "conversas", aberta = nil, foco = "lista" })
igual(#partes, 1, "so uma parte")
igual(partes[1].nome, "conversas", "e e a lista, sem conversa aberta")

partes = arranjo.montar(pocket, { tela = "conversas", aberta = "5511999999999", foco = "lista" })
igual(#partes, 1, "ainda so uma parte")
igual(partes[1].nome, "conversa", "com uma conversa aberta, a conversa toma a tela inteira")

for _, nomeTela in ipairs({ "contatos", "perfil", "bloqueados" }) do
  partes = arranjo.montar(pocket, { tela = nomeTela, aberta = nil, foco = "lista" })
  igual(#partes, 1, "so uma parte para " .. nomeTela)
  igual(partes[1].nome, nomeTela, nomeTela .. " toma a tela inteira, mesmo no computador largo")
end

-- essas 3 telas sao de ida-e-volta nos DOIS formatos - nem o computador largo
-- as divide em duas colunas
partes = arranjo.montar(computador, { tela = "perfil", aberta = "555", foco = "lista" })
igual(#partes, 1, "perfil continua sozinho mesmo no arranjo largo")

-- --------------------------------------------------------- duas colunas

print("\n-- computador: lista e conversa juntas --")

partes = arranjo.montar(computador, { tela = "conversas", aberta = "555", foco = "lista" })
igual(#partes, 2, "duas partes no arranjo largo")
igual(partes[1].nome, "conversas", "a primeira e a lista")
igual(partes[2].nome, "conversa", "a segunda e a conversa")
ok(partes[1].focada, "com foco 'lista', a lista esta em foco")
ok(not partes[2].focada, "e a conversa nao")

partes = arranjo.montar(computador, { tela = "conversas", aberta = "555", foco = "conversa" })
ok(not partes[1].focada, "com foco 'conversa', a lista perde o foco")
ok(partes[2].focada, "e a conversa ganha")

-- a coluna da lista nunca passa de arranjo.COLUNA, mas tambem nunca passa da
-- metade da tela - a mesma conta que app.lua usava antes da extracao
local w = select(1, computador.getSize())
local esperado = math.min(arranjo.COLUNA, math.floor(w / 2))
igual(partes[1].j.w, esperado, "a largura da coluna da lista bate com a conta")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
