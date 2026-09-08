--[[ teste_carga - o orcamento, medido

  O alvo do projeto: 20 telefones ligados custam menos de 5 pedidos por segundo
  a central, e um pedido "nada mudou" custa tempo constante.

  Este arquivo existe porque as otimizacoes de desempenho sao invisiveis quando
  funcionam. Trocar a resposta rapida por uma varredura, ou o append por uma
  reescrita, nao quebra teste nenhum e nao muda tela nenhuma - so fica lento,
  e so muito depois, no mundo de verdade, com o historico ja crescido. Sem uma
  medicao aqui, essas decisoes seriam desfeitas por engano um dia e ninguem
  saberia dizer quando.

  QUASE TUDO AQUI E CONTAGEM, NAO CRONOMETRO. E de proposito, e a razao esta no
  proprio banco de testes: o fs falso guarda arquivo como string na memoria, e
  o modo "a" dele refaz a string inteira a cada escrita (cc_mock, fs.open). Ou
  seja, no mock o append CUSTA proporcional ao tamanho do arquivo, enquanto no
  CC de verdade ele nao custa. Cronometrar gravacao aqui mediria o banco de
  testes em vez do codigo, e mediria errado justamente na direcao que
  interessa.

  Contar chamadas nao tem esse problema: quantas vezes o codigo mandou
  reescrever o arquivo inteiro e uma propriedade dele, nao da maquina nem do
  mock. O cronometro fica so onde ele mede algo que o mock nao distorce - o
  caminho rapido, que nao toca em disco.
]]

local PROJETO = ...

local mock = dofile(PROJETO .. "/testes/cc_mock.lua")
mock.instalar()
mock.montarCentral(PROJETO, false)
mock.instalarDofile()

local total, falhas = 0, 0

local function ok(condicao, titulo, detalhe)
  total = total + 1
  if condicao then
    print("  ok   " .. titulo)
  else
    falhas = falhas + 1
    print("  FALHA " .. titulo .. (detalhe and ("  -> " .. tostring(detalhe)) or ""))
  end
end

local function igual(a, b, titulo)
  ok(a == b, titulo, ("esperava %s, veio %s"):format(tostring(b), tostring(a)))
end

local lib       = dofile("/core/lib.lua")
local protocolo = lib("protocolo")
local central   = lib("central")
local recados   = lib("recados")
local store     = lib("store")

central.prepararDados()

local function pedir(de, servico, acao, dados, token)
  return central.atender(de, {
    v = protocolo.VERSAO, id = math.random(1, 100000),
    servico = servico, acao = acao, token = token, dados = dados or {},
  })
end

local function cronometrar(fn)
  local t = os.clock()
  fn()
  return os.clock() - t
end

-- ------------------------------------------------------------- o espiao

-- Conta quantas vezes cada gravacao foi pedida. Funciona porque todo modulo
-- pega o store pelo lib(), que devolve sempre a MESMA tabela: trocar um campo
-- dela aqui troca para quem ja carregou tambem.
local contagem = {}
local function espionar(nome)
  contagem[nome] = 0
  local original = store[nome]
  store[nome] = function(...)
    contagem[nome] = contagem[nome] + 1
    return original(...)
  end
end
espionar("anexar")          -- uma linha no fim do arquivo: barato
espionar("salvar")          -- reserializa a tabela inteira: caro
espionar("escreverLinhas")  -- reescreve o arquivo inteiro: caro

local function zerar()
  for k in pairs(contagem) do contagem[k] = 0 end
end

-- ------------------------------------------------------- vinte telefones

local TELEFONES = 20

print("\n-- montando " .. TELEFONES .. " linhas --")
local frota = {}
for i = 1, TELEFONES do
  local r = pedir(100 + i, "linha", "criar", { nome = "tel" .. i, pin = "1234" })
  frota[i] = { numero = r.dados.linha.numero, token = r.dados.token, id = 100 + i, desde = 0 }
end
igual(#frota, TELEFONES, "as linhas foram criadas")

-- historico realista: mil recados, todos entre os dois primeiros telefones.
-- Os outros 18 nunca falaram, que e o caso do telefone parado no bolso.
print("\n-- enchendo o historico com 1000 recados --")
local a, b = frota[1], frota[2]
for i = 1, 1000 do
  local de, para = (i % 2 == 0) and a or b, (i % 2 == 0) and b or a
  recados.enviar(de.numero, para.numero, "recado numero " .. i)
end
ok(recados.quantos() >= 1000, "mil recados guardados", recados.quantos())

-- deixa os dois primeiros em dia, para que TODOS estejam sem novidade
for _, t in ipairs({ a, b }) do
  local r = pedir(t.id, "msg", "novidades", { desde = 0 }, t.token)
  t.desde = r.dados.ultimo
end

-- --------------------------------------------- 1. o caminho rapido existe

print("\n-- a resposta rapida --")

local function umCiclo()
  for _, t in ipairs(frota) do
    local r = pedir(t.id, "msg", "novidades", { desde = t.desde }, t.token)
    if r.dados.ultimo then t.desde = r.dados.ultimo end
  end
end

local antes = central.estado.rapidas
umCiclo()
local rapidas = central.estado.rapidas - antes

-- Este e o teste que protege a otimizacao numero 1. Se um dia alguem trocar a
-- comparacao de dois numeros por uma varredura da lista, ele falha aqui - e
-- nao seis meses depois, no jogo, como "a FALAE ficou lenta".
igual(rapidas, TELEFONES,
      "os " .. TELEFONES .. " pedidos sem novidade sairam pelo caminho rapido")

local r = pedir(a.id, "msg", "novidades", { desde = a.desde }, a.token)
ok(r.dados.nada == true, "a resposta rapida diz nada=true")
ok(r.dados.recados == nil, "e nao traz lista de recado alguma")

-- ----------------------------------------- 2. o poll nao encosta no disco

print("\n-- um ciclo de poll nao grava nada --")
-- Vinte telefones perguntando para sempre nao podem gerar escrita nenhuma. Se
-- gerassem, a FALAE castigaria o disco parada, sem ninguem conversando.
zerar()
umCiclo()
igual(contagem.anexar, 0, "nenhum append num ciclo sem novidade")
igual(contagem.salvar, 0, "nenhuma reserializacao num ciclo sem novidade")
igual(contagem.escreverLinhas, 0, "nenhuma reescrita de arquivo num ciclo sem novidade")

-- ---------------------------------------- 3. o custo do poll e constante

print("\n-- o custo do poll nao cresce com o historico --")
local VOLTAS = 40
local gasto = cronometrar(function()
  for _ = 1, VOLTAS do umCiclo() end
end)
local ciclos = VOLTAS * TELEFONES
local porPedido = gasto / ciclos
print(("     %d pedidos completos com 1000 recados guardados: %.4fs (%.6fs cada)")
      :format(ciclos, gasto, porPedido))

-- Cronometro aqui e honesto: este caminho nao toca em disco, entao o mock nao
-- distorce. E a afirmacao e sobre ordem de grandeza, nao sobre porcentagem -
-- uma varredura de mil itens nao cabe em cinco centesimos de milissegundo.
ok(porPedido < 0.0002,
   "cada pedido sem novidade custa menos de 0.2ms mesmo com 1000 recados",
   ("%.6fs"):format(porPedido))

-- ------------------------------------ 4. enviar so acrescenta uma linha

print("\n-- enviar grava UMA linha, nunca o arquivo inteiro --")

local env = dofile("/core/recados.lua")
env.LOG = "/dados/envio.log"
env.MAX = 100000     -- sem aparo, para medir so o custo de gravar
env.carregar()
local ANA, BRU = frota[3].numero, frota[4].numero

zerar()
for i = 1, 200 do env.enviar(ANA, BRU, "primeiras " .. i) end
igual(contagem.anexar, 200, "200 recados, 200 appends")
igual(contagem.salvar, 0, "e nenhuma reserializacao da tabela")
igual(contagem.escreverLinhas, 0, "e nenhuma reescrita do arquivo")

-- o mesmo com o arquivo ja grande: a conta nao pode mudar
for i = 1, 1500 do env.enviar(ANA, BRU, "enchendo " .. i) end
zerar()
for i = 1, 200 do env.enviar(ANA, BRU, "ultimas " .. i) end
igual(contagem.anexar, 200, "com 1700 guardados, ainda 200 appends")
igual(contagem.escreverLinhas, 0, "e ainda nenhuma reescrita")

-- E o teste que pega a regressao de verdade: se alguem trocar store.anexar
-- por store.salvar em recados.enviar, tudo continua funcionando e este numero
-- vira 200.
ok(contagem.salvar == 0,
   "trocar o append por salvar() seria pego aqui", contagem.salvar)

-- --------------------------------------------- 5. o aparo acontece em lote

print("\n-- o aparo em lote --")

local ap = dofile("/core/recados.lua")
ap.LOG = "/dados/aparoCarga.log"
ap.MAX = 500
ap.FOLGA = 100
ap.carregar()

for i = 1, ap.MAX + ap.FOLGA do ap.enviar(ANA, BRU, "enche " .. i) end

zerar()
local ENVIOS = 600
for i = 1, ENVIOS do ap.enviar(ANA, BRU, "passa " .. i) end

print(("     %d envios sobre historico cheio: %d reescrita(s) do arquivo")
      :format(ENVIOS, contagem.escreverLinhas))

-- Aparar assim que passa de MAX faria uma reescrita por recado - seriam 600.
-- Com a folga, e uma a cada FOLGA recados.
ok(contagem.escreverLinhas > 0, "o aparo acontece")
ok(contagem.escreverLinhas <= ENVIOS / ap.FOLGA + 2,
   "e em lote, nao a cada recado",
   ("%d reescritas em %d envios"):format(contagem.escreverLinhas, ENVIOS))

-- O aparo deixa o historico entre MAX e MAX+FOLGA, nao em MAX exato: a folga
-- e o intervalo em que ele deliberadamente nao faz nada.
ok(ap.quantos() >= ap.MAX and ap.quantos() <= ap.MAX + ap.FOLGA,
   "o historico fica entre MAX e MAX+FOLGA",
   ("%d, para MAX=%d FOLGA=%d"):format(ap.quantos(), ap.MAX, ap.FOLGA))

-- e o catalogo tem que continuar valendo depois de aparar, senao a resposta
-- rapida passa a mentir sobre o que a pessoa ja viu
local maisNovo = ap.conversa(ANA, BRU, 1)[1]
igual(ap.ultimo(ANA), maisNovo.n, "o catalogo acompanha o aparo")

-- ---------------------------------------- 5b. a resposta truncada nao pula

print("\n-- quem ficou muito tempo fora nao perde recado --")

-- Este bloco existe por causa de um bug encontrado ao escrever este arquivo.
-- A resposta e limitada; se o "ultimo" devolvido fosse o maior numero da
-- linha em vez do ultimo ENTREGUE, o telefone guardaria esse numero como
-- proximo "desde" e pularia tudo que nao coube. Some mensagem exatamente para
-- quem passou dias com o aparelho desligado - e some em silencio.
local vol = dofile("/core/recados.lua")
vol.LOG = "/dados/volta.log"
vol.carregar()

local TOTAL_FORA = 120
for i = 1, TOTAL_FORA do vol.enviar(BRU, ANA, "enquanto voce nao estava " .. i) end

-- o aparelho volta e busca de 25 em 25, como faria de verdade
local recolhidos, desde, voltas = {}, 0, 0
repeat
  local pacote, ate, mais = vol.desde(ANA, desde, 25)
  voltas = voltas + 1
  for _, m in ipairs(pacote or {}) do recolhidos[#recolhidos + 1] = m end
  desde = ate
until not mais or voltas > 20

igual(#recolhidos, TOTAL_FORA, "recebeu TODOS os recados que chegaram enquanto esteve fora")

-- e na ordem, sem buraco
local seguido = true
for i = 2, #recolhidos do
  if recolhidos[i].n <= recolhidos[i - 1].n then seguido = false end
end
ok(seguido, "e em ordem, sem repetir nem pular")

local pacote, _, mais = vol.desde(ANA, 0, 25)
igual(#pacote, 25, "a resposta respeita o limite pedido")
ok(mais == true, "e avisa que sobrou mais para buscar")

local _, _, temMais = vol.desde(ANA, 0, 500)
ok(temMais == false, "quando cabe tudo, nao ha mais a buscar")

-- ------------------------------------------------------- 6. o medidor

print("\n-- o medidor de custo --")
local custos = central.custos()
ok(#custos > 0, "a central mede o custo por rota")

local achouNovidades = false
for _, c in ipairs(custos) do
  if c.rota == "msg.novidades" then
    achouNovidades = true
    print(("     msg.novidades: %d pedidos, %.4fs no total, %.6fs de media")
          :format(c.n, c.tempo, c.media))
  end
end
ok(achouNovidades, "e a rota mais chamada aparece no medidor")

local e = central.estado
local somaPedidos = e.pedidos + e.recusas
ok(e.rapidas / somaPedidos > 0.5,
   "a maioria dos pedidos desta simulacao foi 'nada mudou', como no mundo real",
   ("%d de %d"):format(e.rapidas, somaPedidos))

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
