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
local function decodificar(linha)
  local n, de, para, quando, texto = linha:match("^(%d+)|(%d+)|(%d+)|(%-?%d+)|(.*)$")
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
  for _, m in ipairs(lista) do
    if m.n > desde and (m.de == canonico or m.para == canonico) then
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

--- Com quem esta linha ja falou, e o ultimo recado de cada conversa.
-- E o que a tela de conversas mostra.
function recados.conversas(canonico)
  local porOutro = {}
  for _, m in ipairs(lista) do
    local outro
    if m.de == canonico then outro = m.para
    elseif m.para == canonico then outro = m.de end
    if outro then porOutro[outro] = m end
  end

  local saida = {}
  for outro, m in pairs(porOutro) do
    saida[#saida + 1] = { numero = outro, ultimo = m }
  end
  table.sort(saida, function(a, b) return a.ultimo.n > b.ultimo.n end)
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

return recados
