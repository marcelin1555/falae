--[[ painel - a FALAE nos monitores da central

  Com DOIS monitores, o conteudo se divide:

    o da marca      o balao grande, se esta no ar, e quantas linhas existem
    o do movimento  recados, pedidos, a fatia de "nada mudou", e o custo por
                    rota

  Com UM, tudo cabe nele: a marca a esquerda e os numeros a direita. Com
  nenhum, a central roda igual - o console no teclado continua contando tudo,
  e um sistema que exige monitor para funcionar quebra no dia em que alguem
  tira o bloco.

  QUAL E QUAL: a ordem e a dos nomes do periferico (monitor_0 antes de
  monitor_1), que e a ordem em que voce colocou os blocos. O primeiro fica com
  a marca. Para trocar sem mexer no codigo, a tecla T no console inverte e
  guarda a escolha em /dados/telas.

  DESENHA O FUNDO UMA VEZ E DEPOIS SO REESCREVE NUMERO. Monitor de CC e
  sincronizado com todo cliente por perto: quadro redesenhado a toa vira
  trafego a toa no servidor Minecraft inteiro, inclusive para quem so passou
  andando pela sala. Por isso o atualizar() so escreve o que MUDOU - com a
  FALAE parada, um minuto inteiro de painel nao gera uma escrita sequer.

  A marca some para cinza quando a central perde o modem. E leitura de longe:
  da porta da sala nao da para ler texto, mas da para ver que o amarelo apagou.
]]

local lib     = dofile("/core/lib.lua")
local store   = lib("store")
local pixel   = lib("pixel")
local palette = lib("palette")
local marca   = lib("marca")
local linhas  = lib("linhas")
local recados = lib("recados")

local painel = {}

painel.CAMINHO = "/dados/telas"

-- Alvo de largura ao escolher a escala do texto. Ver painel.escala.
--
-- Sao dois, e a razao e que os dois monitores mostram coisas diferentes.
--
-- O do MOVIMENTO e texto: quanto maior a letra, melhor se le da porta da sala,
-- entao o alvo e baixo (poucas colunas = escala grande).
--
-- O da MARCA e desenho. Ali a letra do terminal quase nao aparece - sao tres
-- linhas curtas - e o que manda e a resolucao: cada celula vale 2x3 pontos de
-- subpixel, entao dobrar as colunas dobra o tamanho do balao em pontos. Num
-- 8x4 blocos, escala 1.5 da 51 pontos de altura e o nome nao cabe desenhado;
-- escala 1.0 da 78 e o nome aparece inteiro, com o circunflexo.
painel.ALVO       = 56
painel.ALVO_MARCA = 82
painel.MINIMO     = 30

local C = {
  fundo = colors.black, texto = colors.white, fraco = colors.gray,
  marca = colors.yellow, apagada = colors.brown,
  bom = colors.lime, ruim = colors.red, aviso = colors.orange,
}
painel.CORES = C

-- cada tela: { mon =, nome =, papel = "marca"|"movimento"|"tudo",
--              ultimo = {}, montado = false, antes = <paleta> }
local telas = {}
local corMarca = colors.yellow
local invertido = false

-- ------------------------------------------------------------------ achar

--- Todos os monitores encostados, em ordem de nome.
--
-- Ordem de nome e a ordem em que os blocos foram colocados, entao ela e
-- previsivel para quem montou a sala - diferente da ordem de
-- peripheral.getNames(), que nao promete nada.
function painel.achar()
  local achados = {}
  for _, nome in ipairs(peripheral.getNames()) do
    if peripheral.getType(nome) == "monitor" then
      achados[#achados + 1] = { nome = nome, mon = peripheral.wrap(nome) }
    end
  end
  table.sort(achados, function(a, b) return a.nome < b.nome end)
  return achados
end

--- Escolhe a escala do texto pelo tamanho fisico do monitor.
--
-- Escala fixa nao serve: um monitor 8x4 blocos da 164x52 caracteres em escala
-- 0.5 e 41x13 em escala 2. Os dois "cabem" - mas 164 colunas num painel que se
-- le do outro lado da sala e letra de bula, e o painel existe para ser lido de
-- longe. O alvo e a MAIOR escala (letra maior) que ainda deixa espaco.
function painel.escala(monitor, alvo)
  alvo = alvo or painel.ALVO
  local melhor, melhorErro = 1, math.huge

  for passo = 10, 1, -1 do
    local e = passo * 0.5
    if pcall(monitor.setTextScale, e) then
      local colunas = monitor.getSize()
      if colunas >= painel.MINIMO then
        local erro = math.abs(colunas - alvo)
        if erro < melhorErro then melhor, melhorErro = e, erro end
      end
    end
  end

  pcall(monitor.setTextScale, melhor)
  return melhor
end

--- O alvo de largura do papel que este monitor vai mostrar.
local function alvoDe(papel)
  if papel == "marca" then return painel.ALVO_MARCA end
  return painel.ALVO
end

-- ------------------------------------------------------------------ ligar

local function papeis(quantos)
  if quantos >= 2 then
    if invertido then return { "movimento", "marca" } end
    return { "marca", "movimento" }
  end
  return { "tudo" }
end

--- Prepara os monitores encontrados. Devolve quantos entraram.
function painel.ligar(achados)
  achados = achados or painel.achar()
  telas = {}
  if #achados == 0 then return 0 end

  local guardado = store.carregar(painel.CAMINHO, {})
  invertido = guardado.invertido == true

  local quais = papeis(#achados)

  for i = 1, math.min(#achados, 2) do
    local a = achados[i]
    local t = {
      mon = a.mon, nome = a.nome, papel = quais[i],
      ultimo = {}, montado = false,
    }
    t.antes = palette.guardar(a.mon)
    painel.escala(a.mon, alvoDe(t.papel))
    palette.aplicar(a.mon, palette.PALETAS.falae)
    telas[#telas + 1] = t
  end

  return #telas
end

function painel.inverter()
  invertido = not invertido
  store.salvar(painel.CAMINHO, { invertido = invertido })
  local quais = papeis(#telas)
  for i, t in ipairs(telas) do
    t.papel = quais[i] or t.papel
    -- a escala vai junto: cada papel quer uma, e trocar o papel sem trocar a
    -- escala deixaria a marca sem resolucao para o nome desenhado
    painel.escala(t.mon, alvoDe(t.papel))
    t.montado = false
    t.ultimo = {}
  end
  return invertido
end

function painel.quantas() return #telas end

function painel.desligar()
  for _, t in ipairs(telas) do
    pcall(palette.restaurar, t.mon, t.antes)
    pcall(function()
      t.mon.setBackgroundColour(colors.black)
      t.mon.setTextColour(colors.white)
      t.mon.clear()
    end)
  end
  telas = {}
end

-- ---------------------------------------------------------------- desenho

local function escrever(t, x, y, texto, cor, fundo)
  t.mon.setCursorPos(x, y)
  t.mon.setTextColour(cor or C.texto)
  t.mon.setBackgroundColour(fundo or C.fundo)
  t.mon.write(texto)
end

--- Escreve so se mudou. E a peca que faz o painel nao custar nada parado.
local function campo(t, rotulo, x, y, texto, cor, largura)
  texto = tostring(texto)
  local assinatura = texto .. "/" .. tostring(cor)
  if t.ultimo[rotulo] == assinatura then return false end
  t.ultimo[rotulo] = assinatura
  largura = largura or #texto
  escrever(t, x, y, texto .. string.rep(" ", math.max(0, largura - #texto)), cor)
  return true
end

--- Desenha a marca dentro de um retangulo do monitor.
--
-- O nome vai DESENHADO quando o retangulo da resolucao para isso, e escrito em
-- caracteres quando nao da. Quem decide e a propria marca (marca.completa):
-- aqui so se entrega o espaco disponivel.
local function pintarMarca(t, x, y, w, h)
  if w < 10 or h < 6 then
    -- retangulo pequeno demais ate para o balao; sobra o nome, e so
    escrever(t, x, y + 1, "FALAE", corMarca)
    t.janelaMarca = nil
    return
  end

  local jan = window.create(t.mon, x, y, w, h, true)
  t.janelaMarca = { jan = jan, x = x, y = y, w = w, h = h }

  local _, _, _, _, desenhado =
    marca.completa(jan, pixel, corMarca, colors.black)
  t.nomeDesenhado = desenhado
end

local function repintarMarca(t)
  if not t.janelaMarca then return end
  local _, _, _, _, desenhado =
    marca.completa(t.janelaMarca.jan, pixel, corMarca, colors.black)
  t.nomeDesenhado = desenhado
end

-- --------------------------------------------------------------- montagem

--- O monitor da marca: o balao a esquerda, o estado a direita.
--
-- Nao e o balao ocupando tudo, e a razao e a forma do monitor. Um 8x4 blocos
-- da 55x17 caracteres, que em pontos de subpixel e 110x51 - mais que duas
-- vezes mais largo que alto. A marca e quadrada, entao esticada nessa tela ela
-- encolhe presa pela ALTURA e sobra metade da tela vazia dos dois lados.
--
-- Com a marca na esquerda e o estado na direita, o balao fica maior (a coluna
-- dele e quase quadrada) E a largura vira texto legivel de longe, que e para o
-- que este monitor existe.
local function montarMarca(t)
  local w, h = t.mon.getSize()
  t.mon.setBackgroundColour(C.fundo)
  t.mon.clear()

  -- a coluna da marca: o mais perto de quadrada que der, sem passar da metade
  local colunaMarca = math.min(math.floor(h * 3 / 2), math.floor(w * 0.45))
  colunaMarca = math.max(colunaMarca, 8)

  pintarMarca(t, 1, 1, colunaMarca, h)

  t.x = colunaMarca + 3
  t.largura = math.max(1, w - t.x)

  -- as tres linhas do estado, espalhadas na altura em vez de amontoadas: e
  -- painel de parede, nao lista.
  local meio = math.floor(h / 2)
  t.linhaEstado = math.max(2, meio - 2)
  t.linhaLinhas = meio + 1
  t.linhaRecados = meio + 3

  escrever(t, t.x, 1, "central telefonica", C.fraco)

  t.montado = true
  t.ultimo = {}
end

--- O monitor do movimento: rotulos a esquerda, numeros a direita.
local function montarMovimento(t)
  local w, h = t.mon.getSize()
  t.mon.setBackgroundColour(C.fundo)
  t.mon.clear()

  escrever(t, 2, 1, "FALAE - movimento", C.marca)

  local rotulos = {
    { "recados guardados", "recados" },
    { "pedidos atendidos", "pedidos" },
    { "sem novidade",      "rapidas" },
    { "recusas",           "recusas" },
    { "no ar ha",          "noar" },
  }

  t.campos = {}
  local y = 3
  for _, r in ipairs(rotulos) do
    escrever(t, 2, y, r[1], C.fraco)
    t.campos[r[2]] = y
    y = y + 2
  end

  t.yCusto = y + 1
  if t.yCusto + 1 <= h then
    escrever(t, 2, t.yCusto, "custo por rota", C.fraco)
  end

  t.largura = w
  t.montado = true
  t.ultimo = {}
end

--- Um monitor so: marca a esquerda, numeros a direita.
local function montarTudo(t)
  local w, h = t.mon.getSize()
  t.mon.setBackgroundColour(C.fundo)
  t.mon.clear()

  local corte = math.min(math.floor(w * 0.42), 26)
  pintarMarca(t, 1, 1, corte, h)

  local x = corte + 2
  t.x = x
  t.largura = w - x

  escrever(t, x, 2, "central telefonica", C.fraco)
  t.campos = {}
  local pares = {
    { "estado",  3 }, { "linhas",  5 }, { "recados", 7 },
    { "pedidos", 9 }, { "rapidas", 11 }, { "noar",   13 },
  }
  local rotulos = { linhas = 4, recados = 6, pedidos = 8, rapidas = 10, noar = 12 }
  local nomes = { linhas = "linhas", recados = "recados", pedidos = "pedidos",
                  rapidas = "sem novidade", noar = "no ar" }
  for chave, y in pairs(rotulos) do
    if y <= h then escrever(t, x, y, nomes[chave], C.fraco) end
  end
  for _, p in ipairs(pares) do t.campos[p[1]] = p[2] end

  t.montado = true
  t.ultimo = {}
end

-- -------------------------------------------------------------- atualizar

local function tempoNoAr(estado)
  local minutos = math.floor((os.epoch("utc") - estado.desde) / 60000)
  if minutos < 60 then return minutos .. " min" end
  return ("%dh %dmin"):format(math.floor(minutos / 60), minutos % 60)
end

local function fatiaRapidas(estado)
  local soma = estado.pedidos + estado.recusas
  if soma == 0 then return "-" end
  return ("%d%%  (%d)"):format(math.floor(estado.rapidas / soma * 100), estado.rapidas)
end

local function atualizarMarca(t, estado)
  if not t.montado then montarMarca(t) end
  local x, w = t.x, t.largura

  -- O estado em caixa alta e com folga: e a linha que se le do outro lado da
  -- sala, junto com a cor da marca.
  campo(t, "estado", x, t.linhaEstado,
        estado.modem and "NO AR" or "SEM MODEM",
        estado.modem and C.bom or C.aviso, w)

  campo(t, "linhas", x, t.linhaLinhas,
        ("%d linha(s)"):format(linhas.quantas()), C.marca, w)

  campo(t, "recados", x, t.linhaRecados,
        ("%d recado(s)"):format(recados.quantos()), C.fraco, w)
end

local function atualizarMovimento(t, estado, custos)
  if not t.montado then montarMovimento(t) end
  local w = t.largura
  local x = 22
  if x > w - 8 then x = math.max(2, w - 10) end

  campo(t, "recados", x, t.campos.recados, tostring(recados.quantos()), C.texto, w - x)
  campo(t, "pedidos", x, t.campos.pedidos, tostring(estado.pedidos), C.texto, w - x)
  campo(t, "rapidas", x, t.campos.rapidas, fatiaRapidas(estado), C.fraco, w - x)
  campo(t, "recusas", x, t.campos.recusas, tostring(estado.recusas),
        estado.recusas > 0 and C.aviso or C.fraco, w - x)
  campo(t, "noar", x, t.campos.noar, tempoNoAr(estado), C.fraco, w - x)

  -- as rotas mais caras, se sobrou tela
  local _, h = t.mon.getSize()
  for i = 1, 4 do
    local y = t.yCusto + i
    if y <= h then
      local c = custos[i]
      local texto = c and ("%-16s %5d  %6.3fs"):format(c.rota:sub(1, 16), c.n, c.tempo) or ""
      campo(t, "custo" .. i, 2, y, texto, C.fraco, w - 2)
    end
  end
end

local function atualizarTudo(t, estado)
  if not t.montado then montarTudo(t) end
  local x, w = t.x, t.largura
  campo(t, "estado", x, t.campos.estado,
        estado.modem and "no ar" or "SEM MODEM",
        estado.modem and C.bom or C.aviso, w)
  campo(t, "linhas", x, t.campos.linhas, tostring(linhas.quantas()), C.marca, w)
  campo(t, "recados", x, t.campos.recados, tostring(recados.quantos()), C.texto, w)
  campo(t, "pedidos", x, t.campos.pedidos, tostring(estado.pedidos), C.texto, w)
  campo(t, "rapidas", x, t.campos.rapidas, fatiaRapidas(estado), C.fraco, w)
  campo(t, "noar", x, t.campos.noar, tempoNoAr(estado), C.fraco, w)
end

--- Atualiza todos os monitores. Chamado no maximo a cada poucos segundos.
function painel.atualizar(estado, custos)
  if #telas == 0 then return false end
  custos = custos or {}

  -- a marca acompanha o modem: amarela no ar, cinza fora. Leitura de longe.
  local queria = estado.modem and colors.yellow or colors.brown
  if queria ~= corMarca then
    corMarca = queria
    for _, t in ipairs(telas) do repintarMarca(t) end
  end

  for _, t in ipairs(telas) do
    local ok, erro = pcall(function()
      if t.papel == "marca" then atualizarMarca(t, estado)
      elseif t.papel == "movimento" then atualizarMovimento(t, estado, custos)
      else atualizarTudo(t, estado) end
    end)

    -- Um monitor quebrado (alguem tirou o bloco no meio) nao pode derrubar a
    -- central. Mas engolir o erro em silencio e pior: o monitor fica preto e
    -- ninguem descobre por que. O erro fica guardado e vai para o log da
    -- central uma vez - repetir a cada 3 segundos encheria o log sozinho.
    if not ok then
      t.montado = false
      if t.erro ~= tostring(erro) then
        t.erro = tostring(erro)
        t.erroNovo = true
      end
    elseif t.erro then
      t.erro, t.erroNovo = nil, nil
    end
  end
  return true
end

--- Erros que apareceram desde a ultima chamada, para a central logar.
function painel.errosNovos()
  local saida = {}
  for _, t in ipairs(telas) do
    if t.erroNovo then
      saida[#saida + 1] = t.nome .. ": " .. t.erro
      t.erroNovo = false
    end
  end
  return saida
end

--- A abertura, uma vez, quando a central sobe. Nos dois monitores ao mesmo
-- tempo, porque a sala inteira acende junto.
function painel.abrir(achados)
  achados = achados or painel.achar()
  if #achados == 0 then return false end

  local quais = papeis(#achados)
  for i = 1, math.min(#achados, 2) do
    local m = achados[i].mon
    painel.escala(m, alvoDe(quais[i]))
    palette.aplicar(m, palette.PALETAS.falae)
  end

  -- anima no primeiro e desenha o resultado nos outros: animar os dois em
  -- paralelo dobraria as escritas de monitor sem dobrar o efeito
  marca.abertura(achados[1].mon, pixel, 10)
  for i = 2, math.min(#achados, 2) do
    marca.completa(achados[i].mon, pixel, colors.yellow, colors.black)
  end

  sleep(0.6)
  return true
end

return painel
