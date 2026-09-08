--[[ conversa - a conversa aberta, e o que voce esta escrevendo

  As mensagens sao quebradas em linhas na largura da janela que chegar. E o
  ponto em que o layout duplo se paga: no pocket a conversa tem 26 colunas, no
  computador tem 25 da coluna da direita, e a quebra e a mesma conta.

  Desenha de baixo para cima, comecando pela mensagem mais nova. Numa conversa,
  o fim e o que importa - e desenhar de cima para baixo faria a mensagem que
  acabou de chegar aparecer fora da tela, que e o oposto do que se quer.
]]

local carregar = dofile("/carregar.lua")
local janela = carregar("janela")
local agenda = carregar("agenda")
local campo  = carregar("campo")
local numero = carregar("numero")

local tela = {}

--- Quebra um texto em linhas de no maximo <largura>, sem partir palavra.
local function quebrar(texto, largura)
  local linhas = {}
  if largura < 4 then return { texto } end

  local resto = texto
  while #resto > largura do
    -- procura o ultimo espaco que ainda cabe
    local corte = nil
    for i = largura + 1, 2, -1 do
      if resto:sub(i, i) == " " then corte = i; break end
    end
    -- palavra unica maior que a linha: corta seco, nao ha alternativa
    if not corte or corte < 2 then corte = largura + 1 end
    linhas[#linhas + 1] = resto:sub(1, corte - 1)
    resto = resto:sub(corte):gsub("^%s+", "")
  end
  if resto ~= "" or #linhas == 0 then linhas[#linhas + 1] = resto end
  return linhas
end

tela.quebrar = quebrar

function tela.desenhar(j, e, C, focada)
  local outro = e.aberta
  if not outro then
    j:limpar(C.fundo)
    j:texto(2, 2, "Escolha uma conversa", C.fraco, C.fundo)
    return
  end

  local nome = agenda.como(outro, e.nomeDe and e.nomeDe[outro])
  j:barra(1, " " .. janela.cortar(nome, j.w - 2), "", colors.black,
          focada and C.marca or C.marcaFraca)

  -- rodape: o que esta sendo escrito
  local yEntrada = j.h
  local recados = agenda.conversa(e.eu.numero, outro)

  -- monta as linhas de tras para frente ate encher o espaco disponivel
  local espaco = j.h - 2
  local pilha = {}
  for i = #recados, 1, -1 do
    local m = recados[i]
    local meu = m.de == e.eu.numero
    local prefixo = meu and "> " or "  "
    local linhas = quebrar(prefixo .. m.texto, j.w)
    for k = #linhas, 1, -1 do
      table.insert(pilha, 1, { texto = linhas[k], meu = meu })
      if #pilha >= espaco then break end
    end
    if #pilha >= espaco then break end
  end

  -- limpa o miolo e escreve a pilha alinhada com o fim
  for y = 2, yEntrada - 1 do
    j:linha(y, "", C.texto, C.fundo)
  end
  local inicio = yEntrada - 1 - #pilha + 1
  for i, l in ipairs(pilha) do
    j:linha(inicio + i - 1, l.texto, l.meu and C.meu or C.texto, C.fundo)
  end

  if #recados == 0 then
    j:texto(2, 3, "Nada ainda. Escreva algo.", C.fraco, C.fundo)
    j:texto(2, 5, numero.formatar(outro), C.fraco, C.fundo)
  end

  -- a linha de escrita
  local prompt = focada and "> " or "  "
  local visivel = campo.visivel(e.rascunho)
  local sobra = j.w - #prompt
  -- rola o texto para o fim quando ele passa da largura: quem digita precisa
  -- ver o que esta digitando agora, nao o comeco da frase
  if #visivel > sobra then visivel = visivel:sub(#visivel - sobra + 1) end
  j:linha(yEntrada, prompt .. visivel, focada and C.texto or C.fraco, C.entrada)
end

--- Onde o cursor do terminal deve piscar, em coordenadas da janela.
function tela.cursor(j, e)
  local visivel = campo.visivel(e.rascunho)
  local sobra = j.w - 2
  local col = 2 + math.min(#visivel, sobra) + 1
  return math.min(col, j.w), j.h
end

--- @return acao
function tela.tecla(e, k, ch)
  if ch then
    campo.tecla(e.rascunho, nil, ch)
    return "digitou"
  end

  if k == keys.enter then
    if campo.vazio(e.rascunho) then return "redesenhar" end
    return "enviar"
  end

  -- Backspace com o campo vazio volta para a lista. E o gesto natural de quem
  -- quer sair, e no pocket nao ha espaco para um botao de voltar.
  if k == keys.backspace and campo.vazio(e.rascunho) then
    return "fechar"
  end

  if campo.tecla(e.rascunho, k) then return "digitou" end

  if k == keys.up or k == keys.down then return "lista" end
  return nil
end

--- Toque na conversa.
--
-- A barra de titulo volta para a lista (e o gesto de "voltar" que todo mundo
-- ja tem no dedo), e a linha de escrita so poe o foco aqui - digitar continua
-- no teclado.
function tela.clique(e, lx, ly, j)
  if ly == 1 then return "fechar" end
  if ly == j.h then return "focar" end
  return nil
end

return tela
