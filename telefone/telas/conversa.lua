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

  -- O "<" e o sinal universal de voltar. Ele existe porque as DUAS saidas que
  -- havia - backspace com o campo vazio, e tocar na barra - eram invisiveis:
  -- quem pega o telefone nao tem como adivinhar nenhuma das duas. Uma saida que
  -- nao se anuncia e uma saida que nao existe.
  --
  -- A barra INTEIRA continua tocavel, e nao so o caractere: mirar numa coluna
  -- so num pocket e pedir demais do dedo. O "<" diz onde tocar; a area
  -- generosa e o que faz funcionar.
  local nome = agenda.como(outro, e.nomeDe and e.nomeDe[outro])
  j:barra(1, " < " .. janela.cortar(nome, j.w - 5), "", colors.black,
          focada and C.marca or C.marcaFraca)

  -- rodape: o que esta sendo escrito
  local yEntrada = j.h
  local recados = agenda.conversa(e.eu.numero, outro)

  -- Monta as linhas de tras para frente ate encher o espaco disponivel, MAIS
  -- o quanto a pessoa rolou para tras. Como a pilha e montada do mais novo
  -- para o mais velho e inserida na frente, o comeco dela e o trecho antigo -
  -- entao rolar e so colher um pouco mais e ficar com as primeiras.
  local espaco = j.h - 2
  local desloc = math.max(0, e.rolagem or 0)
  local pilha = {}
  local acabou = true
  for i = #recados, 1, -1 do
    local m = recados[i]
    local meu = m.de == e.eu.numero
    local prefixo = meu and "> " or "  "
    local linhas = quebrar(prefixo .. m.texto, j.w)
    for k = #linhas, 1, -1 do
      table.insert(pilha, 1, { texto = linhas[k], meu = meu })
      if #pilha >= espaco + desloc then acabou = false; break end
    end
    if #pilha >= espaco + desloc then break end
  end

  -- Rolou alem do comeco da conversa: encosta no topo em vez de mostrar tela
  -- vazia. Guardado de volta no estado para a proxima rolagem partir do que
  -- esta na tela, e nao de um numero que nunca existiu.
  if acabou and #pilha < espaco + desloc then
    desloc = math.max(0, #pilha - espaco)
    e.rolagem = desloc
  end
  if desloc > 0 then
    local janelinha = {}
    for i = 1, math.min(espaco, #pilha) do janelinha[i] = pilha[i] end
    pilha = janelinha
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

  -- As setas rolam a conversa. Antes elas iam para a lista, e o historico
  -- ficava inalcancavel: nao havia tecla, toque nem roda que subisse a
  -- conversa - so dava para ver a ultima tela de mensagens. Para a lista se
  -- volta pelo "<", pelo backspace ou pelo tab, que sao tres caminhos.
  if k == keys.up then return tela.rolar(e, -1) end
  if k == keys.down then return tela.rolar(e, 1) end
  if k == keys.pageUp then return tela.rolar(e, -5) end
  if k == keys.pageDown then return tela.rolar(e, 5) end
  return nil
end

--- Rola a conversa. dir negativo sobe (para o passado), positivo desce.
--
-- O limite de cima e conferido no desenho, que e quem sabe quantas linhas a
-- conversa tem depois de quebrada na largura desta janela.
function tela.rolar(e, dir)
  local antes = e.rolagem or 0
  e.rolagem = math.max(0, antes - (dir or 0))
  if e.rolagem == antes then return nil end
  return "redesenhar"
end

--- Toque na conversa.
--
-- A barra de titulo volta para a lista (e o gesto de "voltar" que todo mundo
-- ja tem no dedo), e a linha de escrita so poe o foco aqui - digitar continua
-- no teclado.
function tela.clique(e, lx, ly, j)
  -- a barra de titulo inteira volta, nao so o "<"
  if ly == 1 then return "fechar" end
  if ly == j.h then return "focar" end
  return nil
end

return tela
