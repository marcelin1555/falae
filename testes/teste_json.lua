--[[ teste_json - o codificador JSON escrito a mao

  So testa CODIFICAR - e so isso que o modulo faz, de proposito (ver o
  cabecalho de comum/json.lua). A ordem das chaves de um objeto Lua nao e
  garantida por `pairs`, entao os testes com mais de uma chave conferem que
  cada pedaco esperado esta presente e que a pontuacao (chaves, colchetes,
  virgulas) bate, em vez de comparar a string inteira.
]]

local PROJETO = ...
local json = dofile(PROJETO .. "/comum/json.lua")

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

--- Conta quantas vezes um caractere aparece.
local function conta(texto, c)
  local n = 0
  for i = 1, #texto do if texto:sub(i, i) == c then n = n + 1 end end
  return n
end

print("\n-- valores simples --")

igual(json.codificar(nil), "null", "nil vira null")
igual(json.codificar(true), "true", "true")
igual(json.codificar(false), "false", "false")
igual(json.codificar(42), "42", "inteiro sem ponto decimal")
igual(json.codificar(0), "0", "zero")
igual(json.codificar(-7), "-7", "negativo")
igual(json.codificar("oi"), "\"oi\"", "string simples")
igual(json.codificar(""), "\"\"", "string vazia")

print("\n-- escapes --")

igual(json.codificar("a\"b"), "\"a\\\"b\"", "aspas escapam")
igual(json.codificar("a\\b"), "\"a\\\\b\"", "barra invertida escapa")
igual(json.codificar("a\nb"), "\"a\\nb\"", "quebra de linha escapa")
igual(json.codificar("a\tb"), "\"a\\tb\"", "tab escapa")

-- a barra invertida tem que ser a PRIMEIRA a escapar, senao o escape de outra
-- coisa vira barra invertida dupla e quebra o JSON de quem le
local perigoso = json.codificar("\\\"")
ok(perigoso == "\"\\\\\\\"\"", "barra e aspas juntas nao se confundem", perigoso)

print("\n-- numeros grandes --")

-- os numeros que a telemetria manda sao epoch em milissegundos e contagens -
-- nenhum dos dois pode sair em notacao cientifica, que grande parte de
-- parsers JSON aceita mas nem todo consumidor espera
local epoch = 1788992697781
local saida = json.codificar(epoch)
ok(not saida:find("e", 1, true) and not saida:find("E", 1, true),
   "epoch grande nao vira notacao cientifica", saida)
igual(saida, "1788992697781", "e sai com todos os digitos")

print("\n-- casos que nao sao numero valido em JSON --")

igual(json.codificar(0/0), "0", "NaN vira 0 em vez de quebrar o JSON")
igual(json.codificar(1/0), "1e308", "infinito vira um numero finito grande")
igual(json.codificar(-1/0), "-1e308", "e infinito negativo tambem")

print("\n-- listas --")

igual(json.codificar({}), "[]", "tabela vazia vira array vazio")
igual(json.codificar({ 1, 2, 3 }), "[1,2,3]", "lista de numeros")
igual(json.codificar({ "a", "b" }), "[\"a\",\"b\"]", "lista de strings")

print("\n-- objetos --")

local objSimples = json.codificar({ nome = "Ana" })
igual(objSimples, "{\"nome\":\"Ana\"}", "objeto de uma chave so")

local objDuplo = json.codificar({ a = 1, b = 2 })
ok(objDuplo:find("\"a\":1", 1, true) ~= nil, "objeto com duas chaves tem a primeira")
ok(objDuplo:find("\"b\":2", 1, true) ~= nil, "e a segunda")
igual(conta(objDuplo, ","), 1, "com uma virgula separando as duas")
ok(objDuplo:sub(1, 1) == "{" and objDuplo:sub(-1) == "}", "entre chaves")

print("\n-- aninhado, como a telemetria vai mandar --")

local snapshot = {
  linhas = 12,
  recados = { total = 847, ultimaHora = 30 },
  custos = { { rota = "msg.novidades", n = 900 }, { rota = "linha.entrar", n = 4 } },
  modem = true,
}
local out = json.codificar(snapshot)

ok(out:find("\"linhas\":12", 1, true) ~= nil, "o numero de linhas esta la")
ok(out:find("\"modem\":true", 1, true) ~= nil, "o booleano esta la")
ok(out:find("\"total\":847", 1, true) ~= nil, "o objeto aninhado tem o total")
ok(out:find("\"ultimaHora\":30", 1, true) ~= nil, "e a hora")
ok(out:find("\"msg.novidades\"", 1, true) ~= nil, "a lista de tabelas tem a primeira rota")
ok(out:find("\"linha.entrar\"", 1, true) ~= nil, "e a segunda")
igual(conta(out, "{"), conta(out, "}"), "chaves abertas e fechadas em par")
igual(conta(out, "["), conta(out, "]"), "colchetes abertos e fechados em par")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
