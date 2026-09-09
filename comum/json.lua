--[[ json - so para CODIFICAR, escrito a mao

  A central manda numeros para o painel externo (ver
  servidor/core/telemetria.lua), e o outro lado (uma pagina na Vercel) fala
  JSON, nao o formato de tabela do textutils.serialize. Este arquivo existe
  so para essa travessia.

  SO CODIFICA. A central nunca precisa LER JSON de volta - o pedido e sempre
  um POST de numeros, e a resposta que importa e so "deu certo ou nao", que da
  para saber pelo codigo HTTP. Um decodificador que ninguem chama e superficie
  sem uso.

  ESCRITO A MAO, sem depender de textutils.serializeJSON. O CC:Tweaked tem
  essa funcao, mas o projeto inteiro evita depender de API que ninguem
  verificou byte a byte primeiro (o mesmo motivo do XOR feito a mao em
  comum/chave.lua) - e um codificador de JSON e pequeno o bastante para nao
  valer o risco de uma diferenca de escape passar batido.

  ARRAY OU OBJETO? Uma tabela Lua nao sabe dizer sozinha. A regra aqui e a
  mesma que textutils.serializeJSON usa: se a tabela e uma SEQUENCIA (chaves
  1, 2, 3... sem buraco, e nenhuma chave de outro tipo), vira array; senao,
  vira objeto. Uma tabela vazia vira array vazio "[]", que e o formato mais
  comum para "nada aqui" do lado de quem le em JavaScript.
]]

local json = {}

--- E uma sequencia (array), ou tem chave de outro tipo (objeto)?
local function ehSequencia(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true, n
end

-- Escapes na ordem da especificacao JSON: barra invertida primeiro, senao ela
-- escaparia os escapes que acabaram de ser inseridos.
local ESCAPES = {
  ["\\"] = "\\\\", ["\""] = "\\\"",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
  ["\b"] = "\\b", ["\f"] = "\\f",
}

local function textoJSON(s)
  local partes = { "\"" }
  for i = 1, #s do
    local c = s:sub(i, i)
    local esc = ESCAPES[c]
    if esc then
      partes[#partes + 1] = esc
    elseif c:byte() < 32 then
      partes[#partes + 1] = ("\\u%04x"):format(c:byte())
    else
      partes[#partes + 1] = c
    end
  end
  partes[#partes + 1] = "\""
  return table.concat(partes)
end

local function numeroJSON(n)
  if n ~= n then return "0" end                    -- NaN nao existe em JSON
  if n == math.huge then return "1e308" end         -- nem infinito
  if n == -math.huge then return "-1e308" end
  if n == math.floor(n) and math.abs(n) < 1e15 then
    -- inteiro dentro de uma faixa segura: sem ponto decimal, sem notacao
    -- cientifica - e o formato que um numero de contagem deve ter
    return ("%.0f"):format(n)
  end
  return tostring(n)
end

local codificarValor  -- forward declaration, para a recursao com tabelas

local function codificarTabela(t)
  local seq, n = ehSequencia(t)
  local partes = {}

  if seq then
    for i = 1, n do partes[#partes + 1] = codificarValor(t[i]) end
    return "[" .. table.concat(partes, ",") .. "]"
  end

  for k, v in pairs(t) do
    partes[#partes + 1] = textoJSON(tostring(k)) .. ":" .. codificarValor(v)
  end
  return "{" .. table.concat(partes, ",") .. "}"
end

codificarValor = function(v)
  local tipo = type(v)
  if v == nil then return "null" end
  if tipo == "boolean" then return v and "true" or "false" end
  if tipo == "number" then return numeroJSON(v) end
  if tipo == "string" then return textoJSON(v) end
  if tipo == "table" then return codificarTabela(v) end
  error("json: nao sei codificar um " .. tipo, 0)
end

--- Codifica um valor Lua (numero, string, booleano, tabela, ou nil) em JSON.
function json.codificar(valor)
  return codificarValor(valor)
end

return json
