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

  -- duas linhas por conversa: quem, e o comeco do que foi dito. Uma linha do
  -- fim fica com o rodape tocavel.
  local cabem = math.floor((j.h - 3) / 2)
  e.topo = janela.rolar(e.escolhido, #lista, cabem, e.topo)

  -- e.badgesLista guarda ONDE os dois badges do item selecionado cairam, para
  -- o toque e o desenho nunca discordarem - o mesmo raciocinio de
  -- janela.rodape().
  e.badgesLista = nil

  for i = 0, cabem - 1 do
    local c = lista[e.topo + i]
    local y = 2 + i * 2
    if not c then
      j:linha(y, "", C.texto, C.fundo)
      j:linha(y + 1, "", C.texto, C.fundo)
    else
      local escolhida = (e.topo + i) == e.escolhido
      local emFoco = escolhida and focada
      local fundo = emFoco and C.selecao or C.fundo
      local nome = agenda.como(c.numero, c.nome)
      local marca = c.naoLidos > 0 and "* " or "  "

      if emFoco then
        -- SO no item em foco: renomear e bloquear, no lugar do "ha quanto
        -- tempo". Nao cabem em todo item de uma vez num pocket de 26 colunas
        -- - a referencia mostra os tres icones em toda linha, mas ali a tela
        -- e mais larga. Aqui eles aparecem onde o dedo (ou o cursor) ja esta,
        -- que e tambem onde a pessoa provavelmente os quer.
        local largura = j.w - 5   -- 3 celulas de badge + 2 de respiro
        j:linha(y, marca .. janela.encher(nome, largura - 2),
                c.naoLidos > 0 and C.marca or C.texto, fundo)
        j:texto(j.w - 2, y, "E", colors.black, colors.lightBlue)
        j:texto(j.w, y, "X", colors.black, colors.pink)
        e.badgesLista = { y = y, numero = c.numero, colE = j.w - 2, colX = j.w }
      else
        local quando = janela.quando(c.ultimo.quando, e.agora)
        local largura = j.w - #quando - 2
        j:linha(y, marca .. janela.encher(nome, largura - 2) .. quando,
                c.naoLidos > 0 and C.marca or C.texto, fundo)
      end

      local prefixo = (c.ultimo.de == e.eu.numero) and "  voce: " or "  "
      j:linha(y + 1, prefixo .. c.ultimo.texto, C.fraco, fundo)
    end
  end

  tela.desenharRodape(j, e, C)
end

--- O rodape de atalhos, que tambem e a fileira de botoes do toque.
--
-- O texto e as regioes tocaveis saem da MESMA chamada, entao nao existe a
-- possibilidade de o botao ficar num lugar e o toque em outro.
function tela.desenharRodape(j, e, C)
  local texto, regioes = janela.rodape({
    { rotulo = "N novo",   acao = "nova" },
    { rotulo = "A agenda", acao = "contatos" },
    { rotulo = "P linha",  acao = "perfil" },
  }, j.w)
  e.rodapeConversas = regioes
  j:linha(j.h, texto, C.fraco, C.fundo)
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

  -- SEM atalho de teclado para renomear/bloquear aqui - so os badges (E/X)
  -- na linha em foco. Nao perde alcance: quem abrir a conversa (Enter) chega
  -- nos mesmos dois, por S e B, em telas/conversa.lua - o mesmo caminho que
  -- um pocket no lectern ja usava antes destes badges existirem.
  return nil
end

--- Toque dentro desta janela, em coordenadas dela.
--
-- Devolve as MESMAS acoes que tela.tecla: o dedo e o teclado chegam no mesmo
-- lugar, e o aplicativo nao precisa saber por onde a pessoa pediu.
function tela.clique(e, lx, ly, j)
  -- o rodape
  if ly == j.h then
    return janela.acaoNoRodape(e.rodapeConversas, lx)
  end

  -- os badges do item em foco, ANTES do toque generico da linha - senao
  -- tocar no "E" tambem abriria a conversa, porque cai na mesma linha
  local b = e.badgesLista
  if b and ly == b.y then
    if lx == b.colE then return "renomear:" .. b.numero end
    if lx == b.colX then return "bloquear:" .. b.numero end
  end

  -- uma conversa: duas linhas por item, comecando na linha 2
  if ly >= 2 then
    local indice = (e.topo or 1) + math.floor((ly - 2) / 2)
    local c = e.conversas[indice]
    if c then
      e.escolhido = indice
      e.aberta = c.numero
      return "abrir"
    end
  end
  return nil
end

--- Rolagem da roda do mouse. dir e 1 para baixo, -1 para cima.
function tela.rolar(e, dir)
  local novo = e.escolhido + dir
  if novo >= 1 and novo <= #e.conversas then
    e.escolhido = novo
    return "redesenhar"
  end
  return nil
end

return tela
