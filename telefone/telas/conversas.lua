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
        -- SO no item em foco: dois botoes por extenso, um por linha - EDITAR
        -- no lugar do "ha quanto tempo", BLOQUEAR no lugar do fim do recado.
        -- Pedido explicito: a letra sozinha ("E"/"X") nao dizia o que fazia
        -- sem explicar antes: o botao por extenso se explica sozinho.
        local BOTAO = 10   -- cabe "BLOQUEAR" (8) com 1 de respiro dos 2 lados
        local largura = j.w - BOTAO
        j:linha(y, marca .. janela.encher(nome, largura - 2),
                c.naoLidos > 0 and C.marca or C.texto, fundo)
        j:texto(j.w - BOTAO + 1, y, janela.centralizar("EDITAR", BOTAO),
                colors.black, colors.lightBlue)

        local prefixo = (c.ultimo.de == e.eu.numero) and "  voce: " or "  "
        j:linha(y + 1, janela.encher(prefixo .. c.ultimo.texto, largura), C.fraco, fundo)
        j:texto(j.w - BOTAO + 1, y + 1, janela.centralizar("BLOQUEAR", BOTAO),
                colors.black, colors.pink)

        e.badgesLista = {
          numero = c.numero,
          yEditar = y, colIni = j.w - BOTAO + 1, colFim = j.w,
          yBloquear = y + 1,
        }
      else
        local quando = janela.quando(c.ultimo.quando, e.agora)
        local largura = j.w - #quando - 2
        j:linha(y, marca .. janela.encher(nome, largura - 2) .. quando,
                c.naoLidos > 0 and C.marca or C.texto, fundo)

        local prefixo = (c.ultimo.de == e.eu.numero) and "  voce: " or "  "
        j:linha(y + 1, prefixo .. c.ultimo.texto, C.fraco, fundo)
      end
    end
  end

  -- cabem*2 quase nunca preenche a altura inteira do corpo (8 itens cabem em
  -- 16 linhas, mas o corpo tem 17: da linha 2 ate a de cima do rodape) -
  -- sem limpar o que sobra, um resto de OUTRA tela (o fim de uma conversa
  -- aberta, por exemplo) continua visivel ali por baixo depois de voltar
  -- para a lista, porque o redesenho e so das linhas que cada tela escreve.
  for y = 2 + cabem * 2, j.h - 1 do
    j:linha(y, "", C.texto, C.fundo)
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

  -- os botoes do item em foco, ANTES do toque generico da linha - senao
  -- tocar em EDITAR/BLOQUEAR tambem abriria a conversa, porque cai na mesma
  -- linha
  local b = e.badgesLista
  if b and lx >= b.colIni and lx <= b.colFim then
    if ly == b.yEditar then return "renomear:" .. b.numero end
    if ly == b.yBloquear then return "bloquear:" .. b.numero end
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
