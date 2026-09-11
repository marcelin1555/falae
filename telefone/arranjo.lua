--[[ arranjo - quais telas aparecem, e em que retangulo cada uma desenha

  A UNICA parte do telefone que sabe o tamanho da tela:

    largura < LARGO    uma janela ocupando tudo, uma tela por vez
    largura >= LARGO   lista a esquerda, conversa a direita, as duas juntas

  As telas nao sabem em qual dos dois estao. Elas recebem uma janela, desenham
  de 1 ate a largura dela, e pronto. Por isso nao existe uma versao de pocket e
  outra de computador de nada: existe uma implementacao e dois arranjos.

  Matematica pura (destino + os 3 campos de estado que decidem layout, nunca o
  estado inteiro) - dá para testar sem montar um app.rodar() completo.
]]

local carregar = dofile("/carregar.lua")
local janela = carregar("janela")

local arranjo = {}

-- A partir desta largura cabem as duas colunas com folga. Um pocket tem 26.
arranjo.LARGO = 40
-- Quanto da largura fica com a lista no arranjo de duas colunas.
arranjo.COLUNA = 21

function arranjo.largo(destino)
  local w = destino.getSize()
  return w >= arranjo.LARGO
end

--- Quais telas aparecem agora, e em que retangulo cada uma desenha.
-- @param estado { tela=, aberta=, foco= } - so os 3 campos que decidem o
--        layout, nao o estado inteiro do app
-- @return lista de { nome=, j=, focada= }
function arranjo.montar(destino, estado)
  local w, h = destino.getSize()
  local tudo = janela.nova(destino, 1, 1, w, h)

  -- contatos, perfil e bloqueados ocupam a tela inteira nos dois formatos:
  -- sao telas de ida e volta, nao fazem par com nada
  if estado.tela == "contatos" or estado.tela == "perfil" or estado.tela == "bloqueados" then
    return { { nome = estado.tela, j = tudo, focada = true } }
  end

  if w < arranjo.LARGO then
    -- pocket: uma de cada vez
    if estado.aberta then
      return { { nome = "conversa", j = tudo, focada = true } }
    end
    return { { nome = "conversas", j = tudo, focada = true } }
  end

  -- computador: as duas juntas
  local largura = math.min(arranjo.COLUNA, math.floor(w / 2))
  return {
    { nome = "conversas", j = janela.nova(destino, 1, 1, largura, h),
      focada = estado.foco == "lista" },
    { nome = "conversa",  j = janela.nova(destino, largura + 2, 1, w - largura - 1, h),
      focada = estado.foco == "conversa" },
  }
end

return arranjo
