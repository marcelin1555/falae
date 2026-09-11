--[[ abertura - a FALAE se apresentando

  Uma operadora de mensagem se apresenta ESCREVENDO UMA MENSAGEM. O balao nasce
  do escuro, o nome e digitado dentro dele com um cursor piscando, a cauda cai
  no momento do envio, e so entao o diagnostico entra. E o gesto da propria
  empresa, e nao uma copia do frasco fervendo da Expresso Labs - as duas sao
  empresas diferentes, as aberturas tambem devem ser.

    ATO 1   o balao cresce, e a cor esquenta de cinza ate o laranja da marca
    ATO 2   o nome e digitado, uma letra por vez
    ATO 3   a cauda cai, e o balao da um pulso - a mensagem foi enviada
    ATO 4   o diagnostico entra linha a linha, ao lado

  MORA SEPARADO DA MARCA pelo mesmo motivo que o bootmon mora separado do
  frasco, na Expresso Labs: a marca sabe DESENHAR, a abertura sabe CONTAR. E
  roteiro cronometrado se testa quadro a quadro, contra um relogio falso - um
  teste que espera quinze segundos ninguem roda duas vezes.

  A PALETA E DEVOLVIDA NO FIM, sempre, inclusive quando alguem pula ou quando
  algo quebra no meio. A paleta do CC e global e sobrevive ao programa: uma
  abertura que mexe nas cores e nao as devolve deixa o shell, o edit e todo o
  resto errados ate o computador reiniciar.
]]

local abertura = {}

abertura.FPS = 12

--- Marcos do roteiro, em segundos. Ler daqui e mais facil que contar somas
-- espalhadas pelo codigo, e mudar o ritmo vira mudar quatro numeros.
abertura.R = {
  cresce = 4.0,    -- ato 1 acaba aqui
  digita = 9.0,    -- ato 2
  cauda  = 11.0,   -- ato 3
  fim    = 15.0,   -- ato 4
}

--- Versao curta, para o pocket. Quem tira o telefone do bolso quer usar o
-- telefone, nao assistir a uma apresentacao.
abertura.CURTO = {
  cresce = 1.6,
  digita = 4.2,
  cauda  = 5.0,
  fim    = 6.0,
}

--- A linha mais comprida do diagnostico.
function abertura.larguraDiag(linhasDiag)
  local maior = 0
  for _, l in ipairs(linhasDiag or {}) do
    if #l > maior then maior = #l end
  end
  return maior
end

--- Em que coluna o diagnostico comeca, se couber AO LADO do balao. nil quando
-- nao cabe, e ai ele vai embaixo.
--
-- A conta e a sobra de verdade: onde o balao termina, quantas colunas restam
-- ate a borda, e se a linha mais comprida cabe nelas. Decidir so pela largura
-- da tela ("40 colunas ja da") erra no caso mais comum de todos - um terminal
-- de 51 colunas, onde o balao vai ate a coluna 41 e sobram dez. O texto saia
-- escrito por cima do laranja e cortado na borda; foi assim que apareceu.
--
-- Quem sabe o tamanho do balao e a marca, e por isso ela vem por parametro:
-- refazer a formula do raio aqui seria a mesma decisao em dois lugares, e um
-- dia os dois discordariam.
function abertura.colunaDoDiag(colunas, linhas, linhasDiag, marca)
  local largura = abertura.larguraDiag(linhasDiag)
  if largura == 0 then return nil end
  if not (marca and marca.raioDeTela) then
    return colunas >= 40 and (colunas - largura + 1) or nil
  end

  local r = marca.raioDeTela(colunas, linhas)
  -- de ponto de subpixel para celula: 2 de largura. O centro do balao e o meio
  -- da tela, e 1.15 r e a barriga dele, a parte mais larga.
  local col = math.floor((colunas + r * 1.15) / 2) + 2
  if col + largura - 1 > colunas then return nil end
  return col
end

--- O diagnostico cabe ao LADO do balao, ou tem que ir embaixo?
--
-- Numa tela larga ele fica na direita, e o balao usa a altura toda. Num pocket
-- de 26 colunas nao ha lado nenhum: ele vai para as ultimas linhas, e ai o
-- balao PRECISA ceder o espaco. Sem isso o texto sai escrito por cima do
-- laranja e nao se le nem uma coisa nem outra - foi o que aconteceu na
-- primeira versao.
function abertura.diagAoLado(colunas, linhas, linhasDiag, marca)
  return abertura.colunaDoDiag(colunas, linhas, linhasDiag, marca) ~= nil
end

--- A area em que o balao pode desenhar: a tela inteira, ou o que sobra acima
-- do diagnostico.
function abertura.areaDoBalao(tela, linhasDiag, marca)
  local colunas, linhas = tela.getSize()
  local quantas = #(linhasDiag or {})
  if quantas == 0 or abertura.diagAoLado(colunas, linhas, linhasDiag, marca) then
    return 1, 1, colunas, linhas
  end
  -- uma linha de respiro entre o balao e o texto
  return 1, 1, colunas, math.max(3, linhas - quantas - 1)
end

local function limitar(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

--- 0 a 1 dentro de um trecho do roteiro.
local function fracao(t, de, ate)
  if ate <= de then return 1 end
  return limitar((t - de) / (ate - de), 0, 1)
end

-- ------------------------------------------------------------------ quadro

--- Desenha UM quadro no instante t.
--
-- Separada de rodar() para o teste poder medir cada instante do roteiro sem
-- monitor, sem sleep e sem esperar o relogio - que e a unica forma de testar
-- animacao que presta.
--
-- @param t segundos desde o comeco
-- @param R os marcos (abertura.R ou abertura.CURTO)
-- @return o que este quadro contem, para o teste conferir:
--         { ato =, balao =, letras =, cursor =, cauda =, linhas = }
function abertura.quadro(fb, marca, t, R, linhasDiag)
  local estado = { ato = 1, balao = 0, letras = 0, cursor = false, cauda = 0, linhas = 0 }

  fb:limpar(colors.black)

  -- ---------------------------------------------------------- ato 1: cresce
  if t < R.cresce then
    estado.ato = 1
    -- desacelera no fim: cresce rapido e assenta devagar
    local k = fracao(t, 0, R.cresce)
    estado.balao = 1 - (1 - k) * (1 - k)
  else
    estado.balao = 1
  end

  local r, cx, cy = marca.desenharCorpo(fb, colors.orange, estado.balao)
  if not r then return estado end

  -- ---------------------------------------------------------- ato 2: digita
  if t >= R.cresce then
    if t < R.digita then
      estado.ato = 2
      local k = fracao(t, R.cresce, R.digita)
      estado.letras = math.floor(k * marca.quantasLetras() + 0.001)
      -- o cursor pisca a 2 Hz, e some quando a ultima letra entra
      estado.cursor = estado.letras < marca.quantasLetras()
                      and (math.floor(t * 2) % 2 == 0)
    else
      estado.letras = marca.quantasLetras()
    end
  end

  -- ---------------------------------------------------------- ato 3: a cauda
  if t >= R.digita then
    estado.ato = 3
    estado.cauda = fracao(t, R.digita, R.cauda)

    -- O pulso: o balao incha um tico no instante em que a cauda comeca, como
    -- quem solta a mensagem. Dura pouco de proposito - um pulso longo vira
    -- respiracao, e o balao ficaria parecendo vivo em vez de ter enviado algo.
    local pulso = fracao(t, R.digita, R.digita + 0.5)
    if pulso < 1 then
      estado.balao = 1 + math.sin(pulso * 3.14159) * 0.06
      fb:limpar(colors.black)
      r, cx, cy = marca.desenharCorpo(fb, colors.orange, estado.balao)
    end
  end

  if estado.cauda > 0 then
    marca.cauda(fb, cx, cy, r, colors.orange, estado.cauda)
  end

  -- o nome vai por ultimo: ele fica POR CIMA do balao, e o balao acabou de ser
  -- redesenhado no pulso
  -- O nome vai por cima do balao. Quando a tela nao tem resolucao para o
  -- letreiro desenhado (o caso do pocket), quem escreve e o chamador, com a
  -- fonte do terminal - e por isso o estado avisa. A digitacao acontece dos
  -- dois jeitos; muda so quem desenha a letra.
  if estado.letras > 0 or estado.cursor then
    estado.desenhado = marca.nomeDesenhado(fb, r, cx, cy, colors.black,
                                           estado.letras, estado.cursor)
    estado.precisaEscrever = not estado.desenhado
  end

  -- ----------------------------------------------------- ato 4: diagnostico
  if t >= R.cauda then
    estado.ato = 4
    local k = fracao(t, R.cauda, R.fim)
    estado.linhas = math.min(#linhasDiag, math.floor(k * (#linhasDiag + 1)))
  end

  estado.r, estado.cx, estado.cy = r, cx, cy
  return estado
end

-- ------------------------------------------------------------------ rodar

--- "modem ......... ok", com os pontinhos alinhando os valores.
function abertura.linhaDiag(rotulo, valor, largura)
  largura = largura or 22
  local pontos = math.max(1, largura - #rotulo - #tostring(valor) - 2)
  return ("%s %s %s"):format(rotulo, string.rep(".", pontos), valor)
end

--- Roda a abertura inteira.
--
-- @param tela term.current() ou um monitor
-- @param libs { pixel =, marca =, palette = }
-- @param linhasDiag lista de textos ja prontos, do ato 4
-- @param curto true usa o roteiro do pocket
-- @return true se foi ate o fim, false se pularam
function abertura.rodar(tela, libs, linhasDiag, curto)
  local pixel, marca, palette = libs.pixel, libs.marca, libs.palette
  linhasDiag = linhasDiag or {}
  local R = curto and abertura.CURTO or abertura.R

  local antes = palette.guardar(tela)

  -- Devolve a paleta aconteca o que acontecer - pular, erro, Ctrl+T. A paleta
  -- e global e sobrevive ao programa; sem isto o shell fica com as cores da
  -- FALAE ate o computador reiniciar.
  local ok, foiAteOFim = pcall(function()
    palette.aplicar(tela, palette.PALETAS.apagada)

    -- o balao desenha na AREA dele, que num pocket exclui as linhas do
    -- diagnostico. window.create devolve algo com a API de terminal, e o
    -- pixel.lua nao precisa saber a diferenca.
    local ax, ay, aw, ah = abertura.areaDoBalao(tela, linhasDiag, marca)
    local alvo = tela
    if ah < select(2, tela.getSize()) then
      alvo = window.create(tela, ax, ay, aw, ah, true)
    end

    local fb = pixel.novo(alvo)
    local inicio = os.clock()
    local intervalo = 1 / abertura.FPS
    local temporizador = nil
    local ultimoDiag = 0

    while true do
      local t = os.clock() - inicio
      if t >= R.fim then break end

      local estado = abertura.quadro(fb, marca, t, R, linhasDiag)
      fb:enviar()

      -- o nome em caracteres, quando nao coube desenhado. Depois do enviar():
      -- o framebuffer reescreve a celula inteira e apagaria o que viesse antes.
      if estado.precisaEscrever then
        marca.escrever(alvo, estado.r, estado.cx, estado.cy,
                       colors.black, colors.orange, estado.letras, estado.cursor)
      end

      -- a cor esquenta junto com o balao: nasce cinza e vira o laranja da
      -- marca. Nao redesenha nada - troca as cores da tela de uma vez.
      if t < R.cresce then
        palette.tween(tela, palette.PALETAS.apagada, palette.PALETAS.falae,
                      fracao(t, 0, R.cresce))
      elseif ultimoDiag == 0 then
        palette.aplicar(tela, palette.PALETAS.falae)
        ultimoDiag = -1
      end

      -- o diagnostico e TEXTO do terminal, escrito depois do enviar(): o
      -- framebuffer reescreve a celula inteira e apagaria o que viesse antes
      if estado.linhas > 0 then
        abertura.escreverDiag(tela, estado, linhasDiag, marca)
      end

      -- UM timer, vivo entre as voltas. Criar um por volta e o erro que fez o
      -- telefone parar de buscar recado: os.pullEvent devolve todo evento, e
      -- ao cair num que o laco nao trata, o timer da volta seguinte nunca e o
      -- que chega. Aqui daria numa animacao que engasga e nunca termina.
      if not temporizador then temporizador = os.startTimer(intervalo) end
      local ev, p1 = os.pullEvent()

      if ev == "key" or ev == "mouse_click" then
        if temporizador then os.cancelTimer(temporizador) end
        return false                          -- pularam
      elseif ev == "timer" and p1 == temporizador then
        temporizador = nil
      end
    end

    -- o quadro final, inteiro e parado
    fb:limpar(colors.black)
    local r, cx, cy = marca.desenharCorpo(fb, colors.orange, 1)
    if r then
      marca.cauda(fb, cx, cy, r, colors.orange, 1)
      local desenhado = marca.nomeDesenhado(fb, r, cx, cy, colors.black)
      fb:enviar()
      if not desenhado then
        marca.escrever(alvo, r, cx, cy, colors.black, colors.orange)
      end
      abertura.escreverDiag(tela, { r = r, cx = cx, cy = cy, linhas = #linhasDiag },
                            linhasDiag, marca)
    else
      fb:enviar()
    end
    return true
  end)

  palette.restaurar(tela, antes)
  if not ok then return false end
  return foiAteOFim ~= false
end

--- As linhas do diagnostico: a direita do balao, ou embaixo dele.
--
-- Quem decide e abertura.diagAoLado, a mesma funcao que abertura.areaDoBalao
-- consulta. Duas contas separadas para a mesma decisao acabariam discordando -
-- e o sintoma seria exatamente o texto por cima do balao.
function abertura.escreverDiag(tela, estado, linhasDiag, marca)
  local colunas, linhas = tela.getSize()
  if not estado.r then return end

  local col = abertura.colunaDoDiag(colunas, linhas, linhasDiag, marca)
  local primeira

  if col then
    -- de ponto de subpixel para celula: 3 de altura
    primeira = math.floor(estado.cy / 3) - math.floor(#linhasDiag / 2) + 1
  else
    col = 2
    primeira = linhas - #linhasDiag + 1
  end

  for i = 1, estado.linhas do
    local y = primeira + i - 1
    if y >= 1 and y <= linhas then
      tela.setCursorPos(col, y)
      tela.setBackgroundColour(colors.black)
      tela.setTextColour(colors.white)
      tela.write(linhasDiag[i]:sub(1, colunas - col + 1))
    end
  end
end

return abertura
