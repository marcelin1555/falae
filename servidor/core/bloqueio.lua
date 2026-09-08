--[[ bloqueio - quem voce nao quer ouvir

  A FALAE e aberta a qualquer jogador do servidor. Isso e o produto, e tambem
  significa que mais cedo ou mais tarde alguem vai encher o saco de alguem.

  Mora em arquivo proprio, e nao como um campo dentro da linha, por causa da
  escrita: bloquear alguem reescreveria o registro de TODAS as linhas se
  morasse la, e o registro de linhas e o arquivo que guarda os resumos de PIN.
  Arquivo separado, escrita separada, risco separado.

  A REGRA QUE NAO PODE SER QUEBRADA: quem foi bloqueado nao pode descobrir que
  foi. O recado dele e recusado com a mesma resposta de sucesso que qualquer
  outro receberia. Se a FALAE respondesse "voce foi bloqueado", bloquear
  viraria um aviso - e a pessoa chata simplesmente tiraria outra linha, que
  custa nada. Melhor que ela ache que esta falando sozinha.
]]

local lib   = dofile("/core/lib.lua")
local store = lib("store")

local bloqueio = {}

bloqueio.CAMINHO = "/dados/bloqueios"
bloqueio.MAX     = 50    -- por linha

-- [dono] = { [alvo] = true }
local registro = {}

function bloqueio.carregar()
  registro = store.carregar(bloqueio.CAMINHO, {})
  return registro
end

function bloqueio.salvar()
  return store.salvar(bloqueio.CAMINHO, registro)
end

--- O dono nao quer ouvir o alvo? Consulta O(1) em duas tabelas por chave;
-- roda em todo recado enviado, entao nao pode ser varredura.
function bloqueio.bloqueado(dono, alvo)
  local meus = registro[dono]
  return meus ~= nil and meus[alvo] == true
end

function bloqueio.quantos(dono)
  local meus = registro[dono]
  if not meus then return 0 end
  local n = 0
  for _ in pairs(meus) do n = n + 1 end
  return n
end

function bloqueio.por(dono, alvo)
  if dono == alvo then return nil, "nao da para bloquear a propria linha" end
  if bloqueio.quantos(dono) >= bloqueio.MAX then
    return nil, "sua lista de bloqueio esta cheia"
  end
  registro[dono] = registro[dono] or {}
  registro[dono][alvo] = true
  bloqueio.salvar()
  return true
end

function bloqueio.tirar(dono, alvo)
  local meus = registro[dono]
  if not meus or not meus[alvo] then return false end
  meus[alvo] = nil
  if next(meus) == nil then registro[dono] = nil end
  bloqueio.salvar()
  return true
end

function bloqueio.listar(dono)
  local saida = {}
  for alvo in pairs(registro[dono] or {}) do saida[#saida + 1] = alvo end
  table.sort(saida)
  return saida
end

--- Some com uma linha cassada: a lista dela, e o nome dela na lista dos
-- outros. Sem isto, cassar uma linha deixaria o numero morto bloqueado para
-- sempre em toda lista onde ele aparecia - e um numero sorteado volta a
-- circular um dia.
function bloqueio.esquecer(canonico)
  local mexeu = registro[canonico] ~= nil
  registro[canonico] = nil
  for _, meus in pairs(registro) do
    if meus[canonico] then meus[canonico] = nil; mexeu = true end
  end
  if mexeu then bloqueio.salvar() end
  return mexeu
end

return bloqueio
