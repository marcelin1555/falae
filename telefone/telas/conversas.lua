--[[ conversas - a lista de quem falou com voce

  Desenha dentro da janela que recebe, sem saber se ela e a tela inteira de um
  pocket ou a coluna da esquerda de um computador. E dai que vem a economia:
  esta funcao e a MESMA nos dois formatos.

  A lista vem do disco do proprio aparelho, nao da central. Abrir o telefone
  nao espera rede: o que ja chegou aparece na hora, e a central so e consultada
  para saber o que veio depois.
]]

local carregar = dofile("/carregar.lua")
local janela = carregar("janela")
local agenda = carregar("agenda")
local numero = carregar("numero")

local tela = {}

function tela.desenhar(j, e, C, focada)
  local lista = e.conversas

  j:barra(1, " FALAE", (e.naoLidos > 0 and (tostring(e.naoLidos) .. " ") or ""),
          colors.black, C.marca)

  if #lista == 0 then
    j:limpar(C.fundo)
    j:barra(1, " FALAE", "", colors.black, C.marca)
    j:texto(2, 3, "Nenhuma conversa ainda.", C.fraco, C.fundo)
    j:texto(2, 5, "Aperte N e digite o", C.texto, C.fundo)
    j:texto(2, 6, "numero de alguem.", C.texto, C.fundo)
    j:texto(2, 8, "O seu numero:", C.fraco, C.fundo)
    j:texto(2, 9, numero.formatar(e.eu.numero), C.marca, C.fundo)
    return
  end

  -- duas linhas por conversa: quem, e o comeco do que foi dito
  local cabem = math.floor((j.h - 2) / 2)
  e.topo = janela.rolar(e.escolhido, #lista, cabem, e.topo)

  for i = 0, cabem - 1 do
    local c = lista[e.topo + i]
    local y = 2 + i * 2
    if not c then
      j:linha(y, "", C.texto, C.fundo)
      j:linha(y + 1, "", C.texto, C.fundo)
    else
      local escolhida = (e.topo + i) == e.escolhido
      local fundo = (escolhida and focada) and C.selecao or C.fundo
      local nome = agenda.como(c.numero, c.nome)
      local quando = janela.quando(c.ultimo.quando, e.agora)

      -- o "quando" fica colado na direita; o nome usa o que sobrar
      local largura = j.w - #quando - 2
      local marca = c.naoLidos > 0 and "* " or "  "
      j:linha(y, marca .. janela.encher(nome, largura - 2) .. quando,
              c.naoLidos > 0 and C.marca or C.texto, fundo)

      local prefixo = (c.ultimo.de == e.eu.numero) and "  voce: " or "  "
      j:linha(y + 1, prefixo .. c.ultimo.texto, C.fraco, fundo)
    end
  end
end

--- @return acao, ou nil se a tecla nao era para esta tela
function tela.tecla(e, k)
  local lista = e.conversas

  if k == keys.down then
    if e.escolhido < #lista then e.escolhido = e.escolhido + 1 end
    return "redesenhar"
  end
  if k == keys.up then
    if e.escolhido > 1 then e.escolhido = e.escolhido - 1 end
    return "redesenhar"
  end
  if k == keys.enter or k == keys.right then
    local c = lista[e.escolhido]
    if c then
      e.aberta = c.numero
      return "abrir"
    end
    return "redesenhar"
  end
  if k == keys.n then return "nova" end
  if k == keys.a then return "contatos" end
  if k == keys.p then return "perfil" end
  return nil
end

return tela
