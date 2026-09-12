--[[ perfil - a sua linha neste aparelho

  O seu numero grande na tela, porque e o que a pessoa vem aqui ver: ela quer
  ditar o proprio numero para alguem.

  E o lugar de sair da linha. Sair apaga a agenda e a caixa de recados do
  aparelho junto - se nao apagasse, o proximo dono do pocket abriria o telefone
  e leria a conversa de quem usou antes. Um aparelho de bolso muda de mao, e
  esse e o momento em que ele muda.
]]

local carregar = dofile("/carregar.lua")
local janela = carregar("janela")
local numero = carregar("numero")

local tela = {}

-- Cada item tem duas linhas (rotulo em cima, o que mostrar embaixo) e um
-- BADGE - um bloco de cor com uma letra dentro, no lugar do icone que o
-- terminal do CC nao desenha. A cor conta a categoria da acao antes mesmo de
-- ler o texto: azul edita um campo, rosa leva para outra tela, vermelho sai.
local ITENS = {
  { chave = "nome", rotulo = "SEU NOME",
    valor = function(e) return e.eu.nome end,
    badge = "E", corBadge = "lightBlue" },
  { chave = "pin", rotulo = "SEU PIN",
    valor = function() return nil end,   -- nunca mostra: nem a FALAE sabe o PIN
    badge = "E", corBadge = "lightBlue" },
  { chave = "bloq", rotulo = "BLOQUEADOS",
    valor = function() return "quem voce nao ouve" end,
    badge = ">", corBadge = "pink" },
  -- SEM dialogo: um toque so alterna, feito um interruptor - por isso o
  -- badge mostra o ESTADO atual ("SIM"/"NAO"), nao uma acao fixa como os
  -- outros ("E" de editar, ">" de abrir outra tela).
  { chave = "anonimo", rotulo = "LIGACOES ANONIMAS",
    valor = function() return "de orelhao, sem identificacao" end,
    badgeDinamico = function(e)
      if e.aceitaAnonimo then return "SIM", "lime" end
      return "NAO", "red"
    end },
  { chave = "sair", rotulo = "SAIR DESTA LINHA",
    valor = function() return nil end,
    badge = "X", corBadge = "red" },
}

tela.ITENS = ITENS

--- Onde cada linha comeca. Duas celulas por item, a primeira comecando logo
-- depois do numero (linha 5).
local function yDoItem(i) return 5 + (i - 1) * 2 end

function tela.desenhar(j, e, C)
  j:limpar(C.fundo)
  j:barra(1, " Minha linha", "", colors.black, C.marca)

  j:texto(2, 3, numero.formatar(e.eu.numero), C.marca, C.fundo)

  for i, item in ipairs(ITENS) do
    local y = yDoItem(i)
    local sel = i == e.escolhidoPerfil
    local fundo = sel and C.selecao or C.fundo

    j:linha(y, "", C.texto, fundo)
    j:texto(2, y, item.rotulo, C.fraco, fundo)

    local valor = item.valor(e)
    j:linha(y + 1, "", C.texto, fundo)
    j:texto(2, y + 1, valor or "", C.texto, fundo)

    -- o badge: tres celulas coladas na borda direita, cor propria e nao
    -- afetada pela selecao - ele diz o que a linha FAZ, nao se esta focada.
    -- badgeDinamico existe para o unico item que nao FAZ uma coisa so - ele
    -- MOSTRA um estado (SIM/NAO) que muda a cada toque, entao o texto e a
    -- cor vem de uma funcao em vez de ficar fixo na tabela.
    local texto, cor
    if item.badgeDinamico then
      local rotuloBadge, corNome = item.badgeDinamico(e)
      texto, cor = rotuloBadge, colors[corNome] or C.marca
    else
      texto, cor = " " .. item.badge .. " ", colors[item.corBadge] or C.marca
    end
    j:texto(j.w - #texto + 1, y, texto, colors.black, cor)
  end

  -- a linha de diagnostico: por que o telefone "demorou"
  j:texto(2, j.h - 2, ("sinal: %s"):format(e.sinal or "?"),
          e.sinal == "ok" and C.bom or C.aviso, C.fundo)
  j:texto(2, j.h - 1, ("pergunta a cada %ds"):format(e.intervalo or 0),
          C.fraco, C.fundo)

  local texto, regioes = janela.rodape({
    { rotulo = "Q volta", acao = "voltar" },
  }, j.w)
  e.rodapePerfil = regioes
  j:linha(j.h, texto, C.fraco, C.fundo)
end

function tela.clique(e, lx, ly, j)
  if ly == j.h then
    return janela.acaoNoRodape(e.rodapePerfil, lx)
  end
  -- as DUAS linhas do item respondem ao toque - mirar so na de cima seria
  -- pedir demais do dedo, a mesma razao pela qual a barra da conversa inteira
  -- e tocavel e nao so o "<"
  for i in ipairs(ITENS) do
    local y = yDoItem(i)
    if ly == y or ly == y + 1 then
      e.escolhidoPerfil = i
      return "perfil:" .. ITENS[i].chave
    end
  end
  return nil
end

function tela.tecla(e, k)
  if k == keys.down and e.escolhidoPerfil < #ITENS then
    e.escolhidoPerfil = e.escolhidoPerfil + 1
    return "redesenhar"
  end
  if k == keys.up and e.escolhidoPerfil > 1 then
    e.escolhidoPerfil = e.escolhidoPerfil - 1
    return "redesenhar"
  end
  if k == keys.enter then
    return "perfil:" .. ITENS[e.escolhidoPerfil].chave
  end
  if k == keys.q or k == keys.backspace then return "voltar" end
  return nil
end

return tela
