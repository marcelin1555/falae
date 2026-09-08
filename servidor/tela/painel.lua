--[[ painel - a FALAE nos monitores da central

  SALA DE OPERACAO, nao vitrine. Estas telas existem para a operadora saber o
  que esta acontecendo, e o espaco vale mais como dado do que como enfeite -
  por isso a marca ficou numa faixa de cabecalho em vez de ocupar meia tela.

  Com DOIS monitores:

    principal  linhas, aparelhos, recados, o grafico de trafego e a faixa de
               atencao
    tecnico    pedidos, custo por rota, disco, e o log ao vivo

  Com UM, o principal cabe nele sozinho. Com NENHUM, a central roda igual - um
  sistema que exige monitor quebra no dia em que alguem tira o bloco.

  A FAIXA DE ATENCAO SO APARECE QUANDO HA ALGO. Um painel que exibe "nenhum
  problema" em letras grandes treina a pessoa a nao olhar para ele, e ai o dia
  em que houver problema tambem passa batido.

  O TEXTO DE DENUNCIA NUNCA ENTRA AQUI. O painel fica numa sala por onde
  qualquer um passa; ele mostra quantas esperam, e ler e coisa do console.

  DESENHA O FUNDO UMA VEZ E DEPOIS SO REESCREVE O QUE MUDOU. Monitor de CC e
  sincronizado com todo cliente por perto: quadro redesenhado a toa vira
  trafego no servidor Minecraft inteiro, inclusive para quem so passou andando
  pela sala. Com a FALAE parada, um ciclo de painel nao gera uma escrita.
]]

local lib       = dofile("/core/lib.lua")
local store     = lib("store")
local pixel     = lib("pixel")
local palette   = lib("palette")
local marca     = lib("marca")
local grafico   = lib("grafico")
local numero    = lib("numero")
local linhas    = lib("linhas")
local recados   = lib("recados")
local denuncias = lib("denuncias")

local painel = {}

painel.CAMINHO = "/dados/telas"

-- Alvo de largura ao escolher a escala do texto.
--
-- Sao dois porque os dois monitores mostram coisas diferentes. O TECNICO e
-- texto: quanto maior a letra, melhor se le da porta da sala. O PRINCIPAL tem
-- o grafico e a marca, e ali cada celula a mais vale 2x3 pontos de desenho -
-- num 8x4 blocos, escala 1.5 da 51 pontos de altura e escala 1.0 da 78.
painel.ALVO           = 56
painel.ALVO_PRINCIPAL = 82
painel.MINIMO         = 30

painel.HORAS = 12    -- quanto o grafico de trafego olha para tras

local C = {
  fundo = colors.black, texto = colors.white, fraco = colors.gray,
  marca = colors.yellow, apagada = colors.brown,
  bom = colors.lime, ruim = colors.red, aviso = colors.orange,
  grafico = colors.cyan, agora = colors.yellow,
}
painel.CORES = C

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
-- Escala fixa nao serve: um 8x4 blocos da 164x52 caracteres em escala 0.5 e
-- 41x13 em escala 2. Os dois "cabem" - mas 164 colunas num painel que se le do
-- outro lado da sala e letra de bula.
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

local function alvoDe(papel)
  if papel == "principal" then return painel.ALVO_PRINCIPAL end
  return painel.ALVO
end

-- ------------------------------------------------------------------ ligar

local function papeis(quantos)
  if quantos >= 2 then
    if invertido then return { "tecnico", "principal" } end
    return { "principal", "tecnico" }
  end
  return { "principal" }
end

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
    -- escala deixaria o principal sem resolucao para o grafico e para a marca
    painel.escala(t.mon, alvoDe(t.papel))
    t.montado = false
    t.ultimo = {}
  end
  return invertido
end

function painel.quantas() return #telas end

--- O que esta ligado agora. Responde dentro do jogo a pergunta "os dois estao
-- funcionando?", que de fora nao da para responder.
function painel.diagnostico()
  local saida = {}
  for _, t in ipairs(telas) do
    local ok, c, l = pcall(t.mon.getSize)
    local esc = select(2, pcall(t.mon.getTextScale))
    saida[#saida + 1] = {
      nome = t.nome, papel = t.papel,
      colunas = ok and c or 0, linhas = ok and l or 0,
      escala = type(esc) == "number" and esc or nil,
      nomeDesenhado = t.nomeDesenhado,
      erro = t.erro,
    }
  end
  return saida
end

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

local function regua(t, y, largura)
  escrever(t, 1, y, string.rep("-", largura), C.fraco)
end

-- ------------------------------------------------------------------ marca

--- A marca em faixa: balao pequeno a esquerda, nome ao lado.
--
-- Naquela altura o nome desenhado nao caberia; marca.completa percebe isso
-- sozinha e cai para a fonte do terminal.
local function pintarMarca(t, x, y, w, h)
  if w < 6 or h < 3 then
    escrever(t, x, y, "FALAE", corMarca)
    t.janelaMarca = nil
    return
  end
  local jan = window.create(t.mon, x, y, w, h, true)
  t.janelaMarca = jan
  local _, _, _, _, desenhado = marca.completa(jan, pixel, corMarca, colors.black)
  t.nomeDesenhado = desenhado
end

local function repintarMarca(t)
  if not t.janelaMarca then return end
  local _, _, _, _, desenhado =
    marca.completa(t.janelaMarca, pixel, corMarca, colors.black)
  t.nomeDesenhado = desenhado
end

-- --------------------------------------------------------------- formatos

local function relogio()
  return textutils.formatTime(os.time(), true)
end

local function tempoNoAr(estado)
  local minutos = math.floor((os.epoch("utc") - estado.desde) / 60000)
  if minutos < 60 then return minutos .. " min" end
  return ("%dh %dmin"):format(math.floor(minutos / 60), minutos % 60)
end

local function ha(ms)
  if not ms then return "-" end
  local seg = math.floor((os.epoch("utc") - ms) / 1000)
  if seg < 60 then return seg .. "s" end
  if seg < 3600 then return math.floor(seg / 60) .. "min" end
  if seg < 86400 then return math.floor(seg / 3600) .. "h" end
  return math.floor(seg / 86400) .. "d"
end

local function disco()
  local ok, livre = pcall(fs.getFreeSpace, "/")
  if not ok or type(livre) ~= "number" then return "?" end
  if livre > 1024 * 1024 then return ("%.1f MB"):format(livre / 1048576) end
  return ("%d KB"):format(math.floor(livre / 1024))
end

-- ------------------------------------------------------- painel principal

local HORA = 60 * 60 * 1000
local DIA  = 24 * HORA

--- Os numeros de um bloco. O TITULO NAO ENTRA AQUI: ele e fundo, escrito uma
-- vez no montar. Escrito a cada ciclo, ele sozinho garantiria tres escritas de
-- monitor por atualizacao mesmo com a FALAE completamente parada - e a
-- promessa do arquivo e que parado nao custa nada.
local function bloco(t, x, y, itens, larguraCol)
  for i, item in ipairs(itens) do
    campo(t, item.chave, x, y + i,
          ("%5s  %s"):format(item.valor, item.rotulo),
          item.cor or C.texto, larguraCol)
  end
end

local function montarPrincipal(t)
  local w, h = t.mon.getSize()
  t.mon.setBackgroundColour(C.fundo)
  t.mon.clear()

  -- cabecalho: marca em faixa, e o resto e estado
  t.alturaMarca = math.min(5, math.max(3, math.floor(h * 0.20)))
  pintarMarca(t, 1, 1, math.min(14, math.floor(w * 0.18)), t.alturaMarca)

  t.xCabecalho = math.min(16, math.floor(w * 0.20)) + 1
  escrever(t, t.xCabecalho, 2, "central telefonica", C.fraco)

  regua(t, t.alturaMarca + 1, w)

  -- tres colunas de numeros
  t.yBlocos = t.alturaMarca + 2
  t.colunas = { 2, math.floor(w * 0.35), math.floor(w * 0.66) }
  t.larguraCol = math.floor(w * 0.30)

  escrever(t, t.colunas[1], t.yBlocos, "LINHAS", C.fraco)
  escrever(t, t.colunas[2], t.yBlocos, "APARELHOS", C.fraco)
  escrever(t, t.colunas[3], t.yBlocos, "RECADOS", C.fraco)

  -- o grafico embaixo dos blocos, com uma linha de respiro: colado no bloco de
  -- cima, o rotulo TRAFEGO parece a quarta linha da coluna RECADOS
  t.yGrafico = t.yBlocos + 6
  t.alturaGrafico = math.max(4, math.min(7, h - t.yGrafico - 4))

  -- a atencao no rodape, se houver
  t.yAtencao = t.yGrafico + t.alturaGrafico + 2

  t.largura = w
  t.altura = h
  t.montado = true
  t.ultimo = {}
end

--- O grafico de trafego, desenhado por cima do retangulo reservado.
--
-- Redesenhado so quando a serie muda: a assinatura e a serie inteira virada em
-- texto. Sem isso, o grafico seria reenviado ao monitor a cada tres segundos
-- para mostrar exatamente as mesmas barras.
local function desenharGrafico(t, serie, pico)
  local assinatura = table.concat(serie, ",")
  if t.ultimo.grafico == assinatura then return false end
  t.ultimo.grafico = assinatura

  local x, y = 2, t.yGrafico
  local w = t.largura - 10
  local h = t.alturaGrafico

  escrever(t, x, y - 1,
           ("TRAFEGO   recados por hora, ultimas %dh"):format(#serie), C.fraco)

  -- limpa a area antes: barra que encolheu deixaria rastro da altura antiga
  for ly = y, y + h - 1 do
    escrever(t, 1, ly, string.rep(" ", t.largura))
  end

  local jan = window.create(t.mon, x + 5, y, w, h, true)
  local fb = pixel.novo(jan)
  fb:limpar(colors.black)
  grafico.barras(fb, 1, 1, fb.w, fb.h, serie, C.grafico,
                 { corUltima = C.agora })
  fb:enviar()

  -- eixo: so o topo e a base, que e o que cabe e o que basta para ler a escala
  escrever(t, x, y, ("%4s"):format(grafico.curto(pico)), C.fraco)
  escrever(t, x, y + h - 1, "   0", C.fraco)
  escrever(t, x + 5, y + h, ("ha %dh"):format(#serie), C.fraco)
  local rotuloFim = "agora"
  escrever(t, x + 5 + w - #rotuloFim, y + h, rotuloFim, C.agora)
  return true
end

--- A faixa de atencao. So existe quando ha algo a fazer.
local function desenharAtencao(t, itens)
  local assinatura = ""
  for _, i in ipairs(itens) do assinatura = assinatura .. i.texto .. "|" end
  if t.ultimo.atencao == assinatura then return false end
  t.ultimo.atencao = assinatura

  local y = t.yAtencao
  for ly = y, t.altura do
    escrever(t, 1, ly, string.rep(" ", t.largura))
  end

  if #itens == 0 then return true end

  escrever(t, 2, y, "ATENCAO", C.ruim)
  for i, item in ipairs(itens) do
    if y + i <= t.altura then
      escrever(t, 3, y + i, item.texto:sub(1, t.largura - 4), item.cor or C.aviso)
    end
  end
  return true
end

local function atualizarPrincipal(t, estado)
  if not t.montado then montarPrincipal(t) end

  local agora = os.epoch("utc")
  local x = t.xCabecalho
  local lc = t.larguraCol

  -- estado, no cabecalho
  campo(t, "estado", x, 3, estado.modem and "NO AR" or "SEM MODEM",
        estado.modem and C.bom or C.aviso, 12)
  campo(t, "relogio", t.largura - 6, 2, relogio(), C.fraco, 6)
  -- 16 colunas: "no ar 12h 45min" e o caso mais comprido, e cortar justamente
  -- o numero seria o pior lugar para cortar
  campo(t, "noar", t.largura - 16, 3, ("no ar %s"):format(tempoNoAr(estado)),
        C.fraco, 16)

  -- os tres blocos
  local abertas, vivas = linhas.sessoesAbertas()
  local atencao = linhas.atencao()
  local semPin = 0
  for _, a in ipairs(atencao) do
    if a.motivo == "sem PIN" then semPin = semPin + 1 end
  end

  local y = t.yBlocos
  bloco(t, t.colunas[1], y, {
    { chave = "l1", valor = linhas.quantas(), rotulo = "no total", cor = C.marca },
    { chave = "l2", valor = linhas.ativasDesde(agora - DIA), rotulo = "ativas hoje" },
    { chave = "l3", valor = semPin, rotulo = "SEM PIN",
      cor = semPin > 0 and C.ruim or C.fraco },
  }, lc)

  bloco(t, t.colunas[2], y, {
    { chave = "a1", valor = vivas, rotulo = "no ar agora", cor = C.bom },
    { chave = "a2", valor = abertas, rotulo = "sessoes abertas" },
    { chave = "a3", valor = linhas.ativasDesde(agora - HORA), rotulo = "linhas na hora" },
  }, lc)

  bloco(t, t.colunas[3], y, {
    { chave = "r1", valor = recados.quantos(), rotulo = "guardados" },
    { chave = "r2", valor = recados.quantosDesde(agora - HORA), rotulo = "na ultima hora" },
    { chave = "r3", valor = recados.quantosDesde(agora - 5 * 60 * 1000),
      rotulo = "nos ultimos 5min", cor = C.marca },
  }, lc)

  -- o grafico
  local serie, pico = recados.porHora(painel.HORAS)
  desenharGrafico(t, serie, pico)

  -- a atencao
  local itens = {}
  for _, a in ipairs(atencao) do
    if #itens < 3 then
      itens[#itens + 1] = {
        texto = ("%s   %s ha %s"):format(
                numero.formatar(a.numero), a.motivo, ha(a.desde)),
        cor = a.motivo == "sem PIN" and C.aviso or C.ruim,
      }
    end
  end

  -- so o contador: o texto da denuncia nunca entra num painel de parede
  local esperando = denuncias.quantasPendentes()
  if esperando > 0 then
    itens[#itens + 1] = {
      texto = ("%d denuncia(s) esperando   (tecla D no console)"):format(esperando),
      cor = C.ruim,
    }
  end

  desenharAtencao(t, itens)
end

-- --------------------------------------------------------- painel tecnico

local function montarTecnico(t)
  local w, h = t.mon.getSize()
  t.mon.setBackgroundColour(C.fundo)
  t.mon.clear()

  escrever(t, 2, 1, "FALAE - operacao", C.marca)
  regua(t, 2, w)

  escrever(t, 2, 3, "pedidos", C.fraco)
  escrever(t, 2, 4, "recusas", C.fraco)

  escrever(t, 2, 6, "CUSTO POR ROTA", C.fraco)
  escrever(t, 2, 7, ("%-16s %6s %8s"):format("rota", "vezes", "total"), C.fraco)
  t.yCusto = 8
  t.linhasCusto = math.max(1, math.min(4, h - 14))

  t.yDisco = t.yCusto + t.linhasCusto + 1
  t.yLog = t.yDisco + 2
  regua(t, t.yDisco + 1, w)
  t.largura = w
  t.altura = h
  t.montado = true
  t.ultimo = {}
end

local function atualizarTecnico(t, estado, custos)
  if not t.montado then montarTecnico(t) end
  local w = t.largura
  local x = 12

  campo(t, "noar", w - 18, 1, ("no ar %s"):format(tempoNoAr(estado)), C.fraco, 18)

  campo(t, "pedidos", x, 3,
        ("%-8d %.1f/min"):format(estado.pedidos, estado.porMinuto or 0),
        C.texto, w - x)
  campo(t, "recusas", x, 4,
        ("%-8d sem novidade %d%%"):format(estado.recusas, estado.fatiaRapidas or 0),
        estado.recusas > 0 and C.aviso or C.fraco, w - x)

  for i = 1, t.linhasCusto do
    local c = custos[i]
    local texto = c and ("%-16s %6d %7.3fs"):format(c.rota:sub(1, 16), c.n, c.tempo) or ""
    campo(t, "custo" .. i, 2, t.yCusto + i - 1, texto, C.fraco, w - 2)
  end

  local abertas = linhas.sessoesAbertas()
  campo(t, "disco", 2, t.yDisco,
        ("disco %s livres      sessoes %d"):format(disco(), abertas), C.fraco, w - 2)

  -- o log ao vivo: e o que a tela da parede nao contava, e o que responde
  -- "o que acabou de acontecer" sem ninguem ir ate o teclado
  local quantas = t.altura - t.yLog + 1
  for i = 1, quantas do
    local reg = estado.log[#estado.log - i + 1]
    local texto = reg and (" %s %s"):format(reg.hora, reg.texto) or ""
    campo(t, "log" .. i, 1, t.yLog + i - 1, texto:sub(1, w), reg and reg.cor or C.fraco, w)
  end
end

-- -------------------------------------------------------------- atualizar

--- Atualiza todos os monitores. Chamado no maximo a cada poucos segundos.
function painel.atualizar(estado, custos)
  if #telas == 0 then return false end
  custos = custos or {}

  -- numeros derivados, calculados uma vez e nao por tela
  local soma = estado.pedidos + estado.recusas
  estado.fatiaRapidas = soma > 0 and math.floor(estado.rapidas / soma * 100) or 0

  -- A marca acompanha o modem: amarela no ar, cinza fora. Leitura de longe.
  --
  -- So MARCA que precisa repintar; a repintura acontece dentro do pcall de
  -- cada tela, logo abaixo. Repintar aqui derrubaria a central inteira no
  -- instante em que ela perdesse o modem com um monitor quebrado na parede -
  -- ou seja, no pior momento possivel, e justamente por causa do enfeite.
  local queria = estado.modem and colors.yellow or colors.brown
  if queria ~= corMarca then
    corMarca = queria
    for _, t in ipairs(telas) do t.precisaRepintar = true end
  end

  for _, t in ipairs(telas) do
    local ok, erro = pcall(function()
      if t.precisaRepintar then
        t.precisaRepintar = false
        repintarMarca(t)
      end
      if t.papel == "tecnico" then atualizarTecnico(t, estado, custos)
      else atualizarPrincipal(t, estado) end
    end)

    -- Um monitor quebrado nao pode derrubar a central. Mas engolir o erro em
    -- silencio e pior: a tela fica preta e ninguem descobre por que. O erro vai
    -- para o log uma vez - repetir a cada 3 segundos encheria o log sozinho.
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

--- A abertura, uma vez, quando a central sobe. Nos dois monitores.
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
