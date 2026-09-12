--[[ recados - as mensagens da FALAE

  Uma lista unica, em ordem, com um numero "n" crescente por recado. O telefone
  pergunta "o que houve depois do n que eu tenho" e recebe so isso. Um aparelho
  que ficou uma semana no bau nao baixa o mundo, e um que esta acompanhando
  gasta quase nada.

  Este arquivo carrega as duas decisoes de desempenho que sustentam o projeto,
  e as duas so sao baratas porque foram tomadas antes de existir codigo:

  1. O CATALOGO (ultimoN). Para cada linha, o maior n que a envolve. Com ele,
     "nada mudou" e respondido sem varrer nada - e "nada mudou" e a resposta da
     esmagadora maioria dos pedidos que a central vai receber na vida. Sem esta
     tabela, vinte telefones parados fariam vinte varreduras de mil recados por
     ciclo para a central dizer vinte vezes que nao aconteceu nada.

  2. O LOG QUE SO CRESCE PELO FIM. Cada recado e uma linha acrescentada ao
     arquivo. O mural da Expresso Labs reserializa a tabela inteira a cada
     mensagem, o que com duzentas mensagens custa pouco e com mil custa o
     historico completo por mensagem enviada. Aqui o custo de mandar um recado
     nao depende de quantos ja existem.

  O formato de linha e "n|de|para|quando|texto", e nao textutils.serialize,
  por tres motivos: cabe numa linha so (que e o que torna o append possivel),
  e varias vezes menor, e o texto vem por ultimo - entao ele pode conter o
  separador sem quebrar nada, bastando dividir nos quatro primeiros.
]]

local lib   = dofile("/core/lib.lua")
local store = lib("store")

local recados = {}

recados.LOG     = "/dados/recados.log"
recados.MAX     = 1000    -- quanto fica guardado
recados.FOLGA   = 200     -- quanto passa disso antes de valer a pena aparar
recados.TAMANHO = 160     -- caracteres por recado

local lista   = {}    -- em ordem de n
local proximo = 1
local ultimoN = {}    -- [canonico] = maior n que envolve essa linha

-- ------------------------------------------------------------------ formato

local function codificar(m)
  return table.concat({ m.n, m.de, m.para, m.quando, m.texto }, "|")
end

--- Le uma linha do log. Devolve nil para lixo, e lixo acontece: uma queda no
-- meio de um append deixa meia linha no fim do arquivo. Descartar a linha e
-- perder um recado; levantar erro seria perder o historico inteiro.
--
-- de/para aceitam qualquer coisa sem "|" no meio, e nao so digito: um orelhao
-- se identifica por "#240", nao por um numero de linha (ver comum/orelhao.lua)
-- - o unico dos cinco campos que PRECISA ser so digito e "n", porque e nele
-- que a busca binaria de primeiroDepois() confia.
local function decodificar(linha)
  local n, de, para, quando, texto = linha:match("^(%d+)|([^|]+)|([^|]+)|(%-?%d+)|(.*)$")
  if not n then return nil end
  return {
    n = tonumber(n), de = de, para = para,
    quando = tonumber(quando), texto = texto,
  }
end

-- -------------------------------------------------------------------- indice

local function catalogar(m)
  if not ultimoN[m.de] or m.n > ultimoN[m.de] then ultimoN[m.de] = m.n end
  if not ultimoN[m.para] or m.n > ultimoN[m.para] then ultimoN[m.para] = m.n end
end

local function recatalogar()
  ultimoN = {}
  for _, m in ipairs(lista) do catalogar(m) end
end

--- O maior n que esta linha ja viu. O telefone que estiver neste numero esta
-- em dia, e e so isso que a central precisa comparar para responder "nada".
function recados.ultimo(canonico)
  return ultimoN[canonico] or 0
end

-- -------------------------------------------------------------------- disco

function recados.carregar()
  lista, ultimoN, proximo = {}, {}, 1
  for _, linha in ipairs(store.linhas(recados.LOG)) do
    local m = decodificar(linha)
    if m then
      lista[#lista + 1] = m
      catalogar(m)
      if m.n >= proximo then proximo = m.n + 1 end
    end
  end
  return #lista
end

function recados.quantos() return #lista end

--- A lista crua, em ordem de n. Existe para o teste poder comparar a busca
-- binaria com a varredura ingenua; a central nao tem por que percorrer isto.
function recados.todos() return lista end
function recados.proximoN() return proximo end

--- Corta o comeco do historico.
--
-- Em LOTE, e nunca com table.remove(lista, 1) num laco: remover a posicao 1
-- desloca a tabela inteira, entao apagar um por um e trabalho ao quadrado.
-- Aqui a lista e recriada de uma vez, copiando so a cauda que fica - uma
-- passagem, nenhum deslocamento.
--
-- So roda quando passa de MAX + FOLGA. Aparar assim que passa de MAX faria
-- uma reescrita do arquivo a cada recado novo, que e justamente o custo que o
-- append existe para evitar.
function recados.aparar(forcar)
  if not forcar and #lista <= recados.MAX + recados.FOLGA then return 0 end

  local corte = #lista - recados.MAX
  if corte <= 0 then return 0 end

  local nova = {}
  for i = corte + 1, #lista do nova[#nova + 1] = lista[i] end
  lista = nova
  recatalogar()

  local linhasTexto = {}
  for i = 1, #lista do linhasTexto[i] = codificar(lista[i]) end
  store.escreverLinhas(recados.LOG, linhasTexto)
  return corte
end

-- ------------------------------------------------------------------- enviar

--- Guarda um recado.
-- Nao decide se pode: quem confere bloqueio e a rota, antes de chamar.
-- @return o recado gravado, ou nil + motivo
function recados.enviar(de, para, texto)
  if type(texto) ~= "string" then return nil, "recado invalido" end
  texto = texto:gsub("[\r\n|]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if texto == "" then return nil, "recado vazio" end
  if #texto > recados.TAMANHO then texto = texto:sub(1, recados.TAMANHO) end

  local m = {
    n = proximo, de = de, para = para,
    quando = os.epoch("utc"), texto = texto,
  }
  proximo = proximo + 1
  lista[#lista + 1] = m
  catalogar(m)

  -- Uma linha no fim do arquivo. Custo constante, e o recado ja esta em disco
  -- antes de a central responder: uma queda depois disto nao perde a mensagem.
  store.anexar(recados.LOG, codificar(m))

  recados.aparar()
  return m
end

-- --------------------------------------------------------------------- ler

--- O indice do primeiro recado com n maior que <desde>.
--
-- Busca binaria porque a lista esta em ordem de n, sempre: os recados entram
-- pelo fim e o aparo so tira do comeco. Percorrer desde a posicao 1 para achar
-- o que esta no fim era a unica varredura que sobrava no caminho de um pedido,
-- e ela contrariava a regra que o resto do arquivo defende.
--
-- Devolve #lista + 1 quando nao ha nenhum, e ai o laco de quem chama nao roda.
local function primeiroDepois(desde)
  local baixo, alto = 1, #lista
  local achado = #lista + 1
  while baixo <= alto do
    local meio = math.floor((baixo + alto) / 2)
    if lista[meio].n > desde then
      achado = meio
      alto = meio - 1
    else
      baixo = meio + 1
    end
  end
  return achado
end

recados.primeiroDepois = primeiroDepois

--- O que aconteceu com esta linha depois do recado numero <desde>.
--
-- @return lista, ate, mais   ou   nil, ate, false  quando nada mudou
--
-- O nil e a resposta rapida, e ele existe para a rota poder devolver uma
-- resposta minuscula sem varrer nem serializar. Chamador nenhum deve tratar
-- isso como erro - "nada novo" e o caso comum, nao a excecao.
--
-- O "ate" e sempre o numero do ULTIMO RECADO ENTREGUE, e nao o maior numero
-- que esta linha ja viu. A diferenca so aparece quando a resposta bate no
-- limite, e ai ela e tudo: o telefone guarda o "ate" como o proximo "desde",
-- entao devolver o maior numero da linha faria ele pular exatamente os
-- recados que nao couberam. O sintoma seria mensagem sumindo justamente para
-- quem passou muito tempo com o aparelho desligado - o caso em que a pessoa
-- mais espera encontrar recado esperando.
--
-- O "mais" avisa que sobrou coisa: o telefone pergunta de novo na hora, em
-- vez de esperar o proximo ciclo.
function recados.desde(canonico, desde, limite)
  desde = tonumber(desde) or 0
  local ultimo = ultimoN[canonico] or 0

  if desde >= ultimo then return nil, ultimo, false end

  limite = math.min(tonumber(limite) or recados.MAX, recados.MAX)
  local saida = {}
  local cortou = false
  for i = primeiroDepois(desde), #lista do
    local m = lista[i]
    if m.de == canonico or m.para == canonico then
      if #saida >= limite then cortou = true; break end
      saida[#saida + 1] = m
    end
  end

  local ate = (#saida > 0) and saida[#saida].n or ultimo
  return saida, ate, cortou
end

--- Toda a conversa entre duas linhas, da mais nova para tras.
-- Usado quando o telefone abre uma conversa e precisa do que ja passou.
function recados.conversa(eu, outro, limite)
  limite = math.min(tonumber(limite) or 50, recados.MAX)
  local saida = {}
  for i = #lista, 1, -1 do
    local m = lista[i]
    if (m.de == eu and m.para == outro) or (m.de == outro and m.para == eu) then
      table.insert(saida, 1, m)
      if #saida >= limite then break end
    end
  end
  return saida
end

--- Apaga tudo que envolve uma linha cassada no balcao.
--
-- Apaga dos DOIS lados de proposito: um recado tem dono duplo, e deixar a
-- metade do outro seria manter no disco a conversa de uma linha que a FALAE
-- disse ter apagado.
function recados.esquecer(canonico)
  local nova, foram = {}, 0
  for _, m in ipairs(lista) do
    if m.de == canonico or m.para == canonico then
      foram = foram + 1
    else
      nova[#nova + 1] = m
    end
  end
  if foram == 0 then return 0 end

  lista = nova
  recatalogar()
  local linhasTexto = {}
  for i = 1, #lista do linhasTexto[i] = codificar(lista[i]) end
  store.escreverLinhas(recados.LOG, linhasTexto)
  return foram
end

-- ------------------------------------------------------- para o painel

--- Quantos recados depois de <ms>.
function recados.quantosDesde(ms)
  local n = 0
  -- de tras para frente: o que interessa esta no fim, entao sair no primeiro
  -- recado velho evita varrer o historico inteiro para contar os ultimos cinco
  for i = #lista, 1, -1 do
    if lista[i].quando < ms then break end
    n = n + 1
  end
  return n
end

-- O histograma fica guardado. O painel pede a cada 3 segundos e a conta varre
-- os mil recados: refazer isso vinte vezes por minuto para desenhar o mesmo
-- grafico e o tipo de desperdicio que o projeto inteiro evita.
--
-- O cache vence quando chega recado novo (o "proximo" mudou) ou quando vira a
-- janela de tempo - o que acontecer primeiro. Sem o segundo, um grafico de
-- "ultimas 12 horas" ficaria parado no tempo numa central sem movimento.
local cache = { proximo = -1, feito = 0, horas = 0, dados = nil }
recados.CACHE_VALIDADE = 60 * 1000
recados.varreduras = 0     -- so para o teste conferir que o cache funciona

--- Recados por hora, nas ultimas <horas> horas.
--
-- @return lista de <horas> numeros, do mais antigo para o mais recente, e o
--         maior deles
function recados.porHora(horas)
  horas = tonumber(horas) or 12
  local agora = os.epoch("utc")

  if cache.dados and cache.horas == horas
     and cache.proximo == proximo
     and (agora - cache.feito) < recados.CACHE_VALIDADE then
    return cache.dados, cache.pico
  end

  recados.varreduras = recados.varreduras + 1

  local HORA = 60 * 60 * 1000
  local baldes = {}
  for i = 1, horas do baldes[i] = 0 end

  local inicio = agora - horas * HORA
  for i = #lista, 1, -1 do
    local m = lista[i]
    if m.quando < inicio then break end
    -- balde 1 e a hora mais antiga; o ultimo balde e a hora que esta correndo
    local balde = horas - math.floor((agora - m.quando) / HORA)
    if balde >= 1 and balde <= horas then baldes[balde] = baldes[balde] + 1 end
  end

  local pico = 0
  for _, v in ipairs(baldes) do if v > pico then pico = v end end

  cache.dados, cache.pico = baldes, pico
  cache.proximo, cache.feito, cache.horas = proximo, agora, horas
  return baldes, pico
end

--- O ultimo recado que <quem> recebeu de <de>.
--
-- E o que a denuncia guarda. Vem daqui, do historico da central, e nao do que
-- o aparelho mandar: o telefone poderia inventar um texto e dizer que foi o
-- outro quem escreveu.
function recados.ultimoDe(quem, de)
  for i = #lista, 1, -1 do
    local m = lista[i]
    if m.para == quem and m.de == de then return m end
  end
  return nil
end

--- Quando foi o ultimo recado de todos, para o painel dizer ha quanto tempo a
-- FALAE esta calada.
function recados.ultimoQuando()
  local m = lista[#lista]
  return m and m.quando or nil
end

--- TUDO que uma linha mandou ou recebeu, em ordem cronologica.
--
-- Existe para UMA coisa so: a exportacao judicial (ver
-- servidor/core/exportacao.lua). Nao e rota de rede, nao tem limite, e ninguem
-- mais chama isto - um numero so pode ver a propria conversa de dentro do
-- proprio aparelho, uma conversa de cada vez. Isto aqui e o historico inteiro
-- de uma pessoa, de uma vez, e por isso mora atras da chave por disquete e
-- nunca atras de rednet.
function recados.tudoDe(canonico)
  local saida = {}
  for _, m in ipairs(lista) do
    if m.de == canonico or m.para == canonico then
      saida[#saida + 1] = m
    end
  end
  return saida
end

return recados
