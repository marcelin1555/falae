--[[ numero - a linha da FALAE, por dentro e por fora

  Por dentro e uma string de 13 digitos: "5511984723310". So digito, sempre o
  mesmo tamanho, e por isso serve de chave de tabela sem susto - comparar dois
  numeros e comparar duas strings iguais, nao adivinhar se um deles veio com
  espaco a mais.

  Por fora e "+55 119 8472-3310", que e o que a pessoa le, dita para o amigo e
  digita de volta.

  Os dois mundos se encontram so aqui. Nenhum outro arquivo do projeto deve
  saber onde ficam os espacos e o traco: no dia em que a FALAE mudar de
  formato, muda este arquivo e nada mais.
]]

local numero = {}

numero.PAIS    = "55"    -- fixo: toda linha e da FALAE
numero.DIGITOS = 13      -- 55 + 11 sorteados

--- So os digitos de um texto qualquer.
function numero.limpar(texto)
  return (tostring(texto or ""):gsub("%D", ""))
end

--- A forma guardada, a partir do que a pessoa digitou.
--
-- Aceita os tres jeitos de escrever a mesma linha, porque os tres vao
-- acontecer: colado da agenda ("+55 119 8472-3310"), digitado inteiro
-- ("5511984723310") e digitado sem o pais ("11984723310"), que e como a
-- pessoa fala o proprio numero em voz alta.
--
-- @return 13 digitos, ou nil + motivo
function numero.canonico(texto)
  local d = numero.limpar(texto)

  if #d == numero.DIGITOS - #numero.PAIS then
    d = numero.PAIS .. d
  end

  if #d ~= numero.DIGITOS then
    return nil, "o numero tem " .. numero.DIGITOS .. " digitos"
  end
  if d:sub(1, #numero.PAIS) ~= numero.PAIS then
    return nil, "toda linha da FALAE comeca com +" .. numero.PAIS
  end
  return d
end

function numero.valido(texto)
  return numero.canonico(texto) ~= nil
end

--- "5511984723310" -> "+55 119 8472-3310"
function numero.formatar(canonico)
  local d = numero.limpar(canonico)
  if #d ~= numero.DIGITOS then return tostring(canonico or "") end
  return ("+%s %s %s-%s"):format(d:sub(1, 2), d:sub(3, 5), d:sub(6, 9), d:sub(10, 13))
end

--- Como fica na tela enquanto a pessoa ainda esta digitando.
--
-- Serve para a mascara do campo de texto: a cada tecla, o telefone mostra o
-- que ja da para mostrar. Sem isto a pessoa digita treze digitos seguidos sem
-- nenhuma referencia visual e erra um no meio sem perceber.
function numero.parcial(digitos)
  local d = numero.limpar(digitos):sub(1, numero.DIGITOS)
  if d == "" then return "" end
  local partes = { "+" .. d:sub(1, 2) }
  if #d > 2 then partes[#partes + 1] = " " .. d:sub(3, 5) end
  if #d > 5 then partes[#partes + 1] = " " .. d:sub(6, 9) end
  if #d > 9 then partes[#partes + 1] = "-" .. d:sub(10, 13) end
  return table.concat(partes)
end

--- Quantos digitos ainda faltam para a linha ficar completa.
function numero.faltam(digitos)
  return numero.DIGITOS - #numero.limpar(digitos)
end

--- Sorteia uma linha livre.
--
-- Sao 10^11 combinacoes depois do +55, entao colidir e praticamente
-- impossivel - o que nao e motivo para nao conferir. "Praticamente impossivel"
-- que acontece uma vez entrega a linha de alguem para outra pessoa, e o
-- sintoma seria duas pessoas recebendo a mesma conversa.
--
-- @param ocupado funcao(canonico) -> true se ja existe
-- @return canonico, ou nil se nao achou vaga
function numero.sortear(ocupado)
  for _ = 1, 50 do
    local d = { numero.PAIS }
    for _ = 1, numero.DIGITOS - #numero.PAIS do
      d[#d + 1] = tostring(math.random(0, 9))
    end
    local cand = table.concat(d)
    if not ocupado or not ocupado(cand) then return cand end
  end
  return nil, "nao achei numero livre"
end

return numero
