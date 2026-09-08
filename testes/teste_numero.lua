--[[ teste_numero - a linha por dentro e por fora

  O numero e a chave de tudo: e chave de tabela na central, e o que a pessoa
  digita para achar alguem, e o que aparece na tela. Um numero que entra de
  dois jeitos diferentes e sai como duas chaves diferentes quebraria a FALAE
  de um jeito que so apareceria depois, como "as vezes a mensagem nao chega".
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
  ok(a == b, titulo, ("esperava %s, veio %s"):format(tostring(b), tostring(a)))
end

local numero = dofile("/numero.lua")

print("\n-- limpar --")
igual(numero.limpar("+55 119 8472-3310"), "5511984723310", "tira espaco, mais e traco")
igual(numero.limpar("abc"), "", "texto sem digito vira vazio")
igual(numero.limpar(nil), "", "nil nao explode")

print("\n-- canonico --")
igual(numero.canonico("5511984723310"), "5511984723310", "digitado inteiro")
igual(numero.canonico("+55 119 8472-3310"), "5511984723310", "colado da agenda")
igual(numero.canonico("11984723310"), "5511984723310", "sem o pais, o +55 entra sozinho")

-- as tres formas acima sao o mesmo numero; se nao fossem a mesma chave, a
-- mesma pessoa teria tres caixas de recado diferentes
ok(numero.canonico("5511984723310") == numero.canonico("+55 119 8472-3310")
   and numero.canonico("11984723310") == numero.canonico("5511984723310"),
   "as tres formas dao a MESMA chave")

ok(numero.canonico("123") == nil, "numero curto e recusado")
ok(numero.canonico("99119847233101234") == nil, "numero longo e recusado")
ok(numero.canonico("1111984723310") == nil, "outro codigo de pais e recusado")
ok(numero.canonico("") == nil, "vazio e recusado")
ok(numero.canonico(nil) == nil, "nil e recusado")

print("\n-- formatar --")
igual(numero.formatar("5511984723310"), "+55 119 8472-3310", "sai como a pessoa le")
igual(numero.formatar("123"), "123", "numero torto sai como veio, sem explodir")

-- ida e volta: o que a tela mostra tem que voltar a ser a mesma chave
igual(numero.canonico(numero.formatar("5511984723310")), "5511984723310",
      "formatar e voltar da a mesma chave")

print("\n-- mascara enquanto digita --")
igual(numero.parcial(""), "", "nada digitado, nada na tela")
igual(numero.parcial("5"), "+5", "primeiro digito")
igual(numero.parcial("55"), "+55", "codigo do pais fechado")
igual(numero.parcial("55119"), "+55 119", "abre o segundo grupo")
igual(numero.parcial("551198472"), "+55 119 8472", "abre o terceiro")
igual(numero.parcial("5511984723310"), "+55 119 8472-3310", "completo")
igual(numero.parcial("55119847233109999"), "+55 119 8472-3310", "digito a mais e ignorado")
igual(numero.faltam("55119"), 8, "conta quantos faltam")
igual(numero.faltam("5511984723310"), 0, "completo nao falta nada")

print("\n-- sorteio --")
local n1 = numero.sortear()
ok(numero.canonico(n1) == n1, "sorteado ja vem canonico")
igual(#n1, 13, "sorteado tem 13 digitos")
igual(n1:sub(1, 2), "55", "sorteado comeca com o pais")

local vistos, repetido = {}, false
for _ = 1, 200 do
  local n = numero.sortear()
  if vistos[n] then repetido = true end
  vistos[n] = true
end
ok(not repetido, "200 sorteios sem repetir")

-- o sorteio tem que respeitar quem ja existe, senao dois clientes recebem a
-- mesma linha e passam a ver a conversa um do outro
local ocupados = {}
for _ = 1, 30 do ocupados[numero.sortear()] = true end
local novo = numero.sortear(function(c) return ocupados[c] end)
ok(novo ~= nil and not ocupados[novo], "sorteio pula os numeros ja ocupados")

-- e quando NAO ha vaga, precisa desistir em vez de devolver um numero ocupado
local semVaga = numero.sortear(function() return true end)
ok(semVaga == nil, "sem numero livre, devolve nil em vez de um ocupado")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
