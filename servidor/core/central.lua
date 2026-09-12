--[[ central - o coracao da FALAE

  Um laco recebe, confere a sessao e despacha. Todas as rotas passam por aqui,
  entao a autenticacao acontece em UM lugar so: rota nova nasce protegida sem
  ninguem precisar lembrar disso.

  Tres tarefas em paralelo:
    rede      atende pedidos
    tela      redesenha o painel do monitor, se houver
    teclado   o balcao de atendimento

  Sao corrotinas, nao threads: elas so trocam de vez nos pontos de espera
  (receive, sleep, pullEvent). Nenhuma consegue interromper a outra no meio de
  uma gravacao - e por isso que nada aqui precisa de trava.

  REGRA DE DESEMPENHO: nenhuma rota pode varrer todas as linhas nem todos os
  recados no caminho comum. Consulta e por chave; o que precisa de varredura
  (faxina de sessao, aparo do historico) roda fora do pedido. Vale como regra
  de revisao: se uma rota nova tiver um "for" sobre tudo, ela esta errada.
]]

local lib       = dofile("/core/lib.lua")
local protocolo = lib("protocolo")
local numero    = lib("numero")
local linhas    = lib("linhas")
local recados   = lib("recados")
local bloqueio  = lib("bloqueio")
local denuncias = lib("denuncias")
local telemetria = lib("telemetria")
local orelhao   = lib("orelhao")

local central = {}

local C = {
  fundo = colors.black, texto = colors.white, fraco = colors.gray,
  marca = colors.orange, bom = colors.lime, ruim = colors.red,
  aviso = colors.yellow,
}
central.CORES = C

local estado = {
  modem = nil,
  desde = os.epoch("utc"),
  pedidos = 0,
  recusas = 0,
  rapidas = 0,          -- respostas "nada mudou" - o caso comum
  log = {},
  custo = {},           -- [rota] = { n =, tempo = }  em segundos de CPU
  rodando = true,
  tela = "principal",
}
central.estado = estado

local LOG_MAX = 100

local function agora()
  return textutils.formatTime(os.time(), true)
end

function central.log(texto, cor)
  table.insert(estado.log, { hora = agora(), texto = tostring(texto), cor = cor or C.texto })
  while #estado.log > LOG_MAX do table.remove(estado.log, 1) end
end

-- -------------------------------------------------------------------- rotas

--- Cada rota recebe (dados, linha, sessao, de) e devolve tabela de resposta,
-- ou nil + motivo. A linha e nil so nas rotas SEM_SESSAO.
local rotas = {}

rotas["central.ping"] = function()
  return {
    central = os.getComputerID(),
    label   = os.getComputerLabel() or "FALAE",
    hora    = os.epoch("utc"),
    linhas  = linhas.quantas(),
  }
end

rotas["linha.criar"] = function(d, _, _, de)
  local pub, token = linhas.criar(d.nome, d.pin, de)
  if not pub then return nil, token end
  central.log(("linha nova %s (%s)"):format(numero.formatar(pub.numero), pub.nome), C.bom)
  return { linha = pub, token = token }
end

rotas["linha.entrar"] = function(d, _, _, de)
  -- Quem passou pelo balcao volta por aqui com definir=true e o codigo de
  -- resgate que o atendimento entregou. E rota sem sessao porque tem que ser -
  -- a pessoa ainda nao consegue entrar para pedir nada - e por isso mesmo o
  -- codigo existe: sem ele, quem digitasse um numero recem-zerado ficava com a
  -- linha, e a propria mensagem de erro dizia quais numeros estavam assim.
  if d.definir then
    local token, pub = linhas.definirPin(d.numero, d.pin, d.codigo, de)
    if not token then return nil, pub end
    central.log(("PIN novo em %s"):format(numero.formatar(pub.numero)), C.bom)
    return { linha = pub, token = token }
  end

  local token, pub = linhas.entrar(d.numero, d.pin, de)
  if not token then return nil, pub end
  return { linha = pub, token = token }
end

rotas["linha.sair"] = function(_, _, _, _, token)
  return { saiu = linhas.sair(token) }
end

rotas["linha.eu"] = function(_, l)
  return {
    numero = l.numero, nome = l.nome, criada = l.criada,
    aparelhos = linhas.sessoesDe(l.numero),
    aceitaAnonimo = linhas.aceitaAnonimo(l.numero),
  }
end

rotas["linha.nome"] = function(d, l)
  local pub, erro = linhas.trocarNome(l.numero, d.nome)
  if not pub then return nil, erro end
  return { linha = pub }
end

--- Liga ou desliga o recebimento de ligacoes de orelhao (ver
-- comum/orelhao.lua e linhas.aceitaAnonimo).
rotas["linha.anonimo"] = function(d, l)
  local ok, erro = linhas.trocarAceitaAnonimo(l.numero, d.valor)
  if not ok then return nil, erro end
  return { aceitaAnonimo = linhas.aceitaAnonimo(l.numero) }
end

rotas["linha.pin"] = function(d, l)
  local ok, erro = linhas.trocarPin(l.numero, d.antigo, d.novo)
  if not ok then return nil, erro end
  return { trocado = true }
end

--- Esse numero existe, e como se chama? E o que a tela de nova conversa
-- precisa para mostrar um nome em vez de treze digitos.
--
-- So responde a quem tem sessao: sem isso, qualquer um com um modem varreria
-- os numeros da FALAE de fora para montar uma lista de quem existe.
rotas["linha.buscar"] = function(d)
  local canonico, erro = numero.canonico(d.numero)
  if not canonico then return nil, erro end
  local pub = linhas.publico(canonico)
  if not pub then return { existe = false } end
  return { existe = true, linha = pub }
end

-- ------------------------------------------------------------------ recados

rotas["msg.enviar"] = function(d, l)
  -- Responder a uma ligacao de orelhao passa direto: um orelhao nao e uma
  -- linha (nao tem PIN, nao esta em linhas.existe), entao os testes abaixo -
  -- pensados para linha de verdade - nao se aplicam. Nao ha o que bloquear
  -- (o orelhao nao tem numero para o bloqueio comparar) nem denunciar
  -- (denuncia.criar exige linhas.existe, que um orelhao nunca passa).
  if orelhao.valido(d.para) then
    local m, motivo = recados.enviar(l.numero, d.para, d.texto)
    if not m then return nil, motivo end
    return { recado = m }
  end

  local para, erro = numero.canonico(d.para)
  if not para then return nil, erro end
  if para == l.numero then return nil, "esse numero e o seu" end
  if not linhas.existe(para) then return nil, "esse numero nao existe" end

  -- Bloqueado recebe a MESMA resposta de quem foi entregue. Ver bloqueio.lua:
  -- avisar quem foi bloqueado transformaria o bloqueio num aviso.
  if bloqueio.bloqueado(para, l.numero) then
    return { recado = { n = 0, de = l.numero, para = para,
                        texto = tostring(d.texto or ""), quando = os.epoch("utc") } }
  end

  local m, motivo = recados.enviar(l.numero, para, d.texto)
  if not m then return nil, motivo end
  return { recado = m }
end

--- A rota mais chamada da FALAE, e a mais barata de proposito.
--
-- Todo telefone ligado bate aqui em laco, para sempre. Quando nada mudou - que
-- e quase sempre - a resposta sai de uma comparacao de dois numeros, sem
-- varrer a lista de recados e sem serializar mensagem nenhuma.
rotas["msg.novidades"] = function(d, l)
  local lista, ate, mais = recados.desde(l.numero, d.desde, d.limite)
  if not lista then
    estado.rapidas = estado.rapidas + 1
    return { nada = true, ultimo = ate }
  end
  -- "ultimo" e o do ultimo recado ENTREGUE: e ele que o telefone guarda como
  -- proximo "desde". Ver recados.desde.
  return { recados = lista, ultimo = ate, mais = mais or nil }
end

--- O que ja passou numa conversa. So no primeiro login de um aparelho novo:
-- depois disso o telefone tem os recados em disco e monta a tela sozinho.
rotas["msg.conversa"] = function(d, l)
  local outro, erro = numero.canonico(d.com)
  if not outro then return nil, erro end
  return { recados = recados.conversa(l.numero, outro, d.limite) }
end

-- ---------------------------------------------------------------- denuncia

--- A unica rota pela qual um recado sai do aparelho de alguem.
--
-- O aparelho manda SO o numero denunciado. O texto e buscado no historico da
-- central (recados.ultimoDe): se viesse no pedido, qualquer um poderia
-- inventar uma frase e dizer que foi outra pessoa quem escreveu, e a denuncia
-- viraria uma arma em vez de uma defesa.
rotas["denuncia.criar"] = function(d, l)
  local sobre, erro = numero.canonico(d.numero)
  if not sobre then return nil, erro end
  if not linhas.existe(sobre) then return nil, "esse numero nao existe" end

  local nova, motivo = denuncias.criar(l.numero, sobre, function(quem, deQuem)
    return recados.ultimoDe(quem, deQuem)
  end)
  if not nova then return nil, motivo end

  central.log(("denuncia sobre %s"):format(numero.formatar(sobre)), C.aviso)

  -- A resposta NAO devolve o texto. Quem denunciou ja tem o recado no proprio
  -- aparelho; devolve-lo aqui so criaria mais um lugar por onde ele passa.
  return { criada = true, n = nova.n }
end

-- ----------------------------------------------------------------- bloqueio

rotas["bloq.listar"] = function(_, l)
  local saida = {}
  for _, item in ipairs(bloqueio.listar(l.numero)) do
    local pub = linhas.publico(item.numero)
    saida[#saida + 1] = { numero = item.numero, nome = pub and pub.nome or nil,
                          quando = item.quando }
  end
  return { bloqueados = saida }
end

rotas["bloq.por"] = function(d, l)
  local alvo, erro = numero.canonico(d.numero)
  if not alvo then return nil, erro end
  local ok, motivo = bloqueio.por(l.numero, alvo)
  if not ok then return nil, motivo end
  return { bloqueado = true }
end

rotas["bloq.tirar"] = function(d, l)
  local alvo, erro = numero.canonico(d.numero)
  if not alvo then return nil, erro end
  return { tirado = bloqueio.tirar(l.numero, alvo) }
end

-- ------------------------------------------------------------------ orelhao

--- Liga de um orelhao para uma linha de verdade.
--
-- SEM SESSAO de proposito: um orelhao nao tem PIN nem dono, so um codigo
-- ("#240") que ele mesmo diz que e. Isso e o ponto - a ligacao e anonima -
-- entao nao ha "de" para bloquear nem "de" para denunciar. Quem recebe so
-- pode aceitar ou recusar TODA ligacao anonima, na propria configuracao (ver
-- linhas.aceitaAnonimo) - nunca uma pessoa especifica, porque nao ha pessoa
-- nenhuma do outro lado para identificar.
rotas["orelhao.ligar"] = function(d)
  if not orelhao.valido(d.codigo) then return nil, "orelhao sem codigo" end

  local para, erro = numero.canonico(d.para)
  if not para then return nil, erro end
  if not linhas.existe(para) then return nil, "esse numero nao existe" end
  if not linhas.aceitaAnonimo(para) then
    return nil, "essa pessoa nao aceita ligacao anonima"
  end

  local m, motivo = recados.enviar(d.codigo, para, d.texto)
  if not m then return nil, motivo end
  return { recado = m }
end

--- Mesma ideia de msg.novidades, so que pelo codigo do orelhao em vez do
-- token de uma sessao - e por isso uma rota propria, e nao a mesma: msg.*
-- sempre resolve "l" a partir do token, e um orelhao nao tem um.
rotas["orelhao.novidades"] = function(d)
  if not orelhao.valido(d.codigo) then return nil, "orelhao sem codigo" end
  local lista, ate, mais = recados.desde(d.codigo, d.desde, d.limite)
  if not lista then return { nada = true, ultimo = ate } end
  return { recados = lista, ultimo = ate, mais = mais or nil }
end

rotas["orelhao.conversa"] = function(d)
  if not orelhao.valido(d.codigo) then return nil, "orelhao sem codigo" end
  local outro, erro = numero.canonico(d.com)
  if not outro then return nil, erro end
  return { recados = recados.conversa(d.codigo, outro, d.limite) }
end

--- Desliga: apaga da central TUDO que passou por este orelhao, dos dois
-- lados. E o pedido explicito - nada de rastro depois que a ligacao acaba,
-- nem pra quem chegar no MESMO orelhao em seguida. Quem recebeu a ligacao
-- guarda a propria copia no proprio aparelho, como qualquer conversa; isto
-- aqui so apaga o que a CENTRAL ainda tinha.
rotas["orelhao.encerrar"] = function(d)
  if not orelhao.valido(d.codigo) then return nil, "orelhao sem codigo" end
  return { apagados = recados.esquecer(d.codigo) }
end

central.rotas = rotas

-- --------------------------------------------------------------------- rede

--- Soma o custo de uma rota. os.clock() mede o tempo de CPU deste computador,
-- entao "a FALAE esta lenta" vira uma linha dizendo qual rota e quanto - em
-- vez de achismo.
local function medir(rota, gasto)
  local c = estado.custo[rota]
  if not c then c = { n = 0, tempo = 0 }; estado.custo[rota] = c end
  c.n = c.n + 1
  c.tempo = c.tempo + gasto
end

local function atender(de, m)
  local rota = protocolo.rota(m)
  local fn = rotas[rota]
  if not fn then
    estado.recusas = estado.recusas + 1
    return protocolo.erro(m.id, "rota desconhecida: " .. rota)
  end

  -- linhas.sessao devolve (linha, sessao) quando reconhece o token e
  -- (nil, motivo) quando nao. Os dois casos sao lidos em nomes separados de
  -- proposito: reaproveitar a mesma variavel para "sessao" e para "motivo"
  -- funciona e engana o proximo que ler.
  local l, s
  if not protocolo.SEM_SESSAO[rota] then
    local achou, extra = linhas.sessao(m.token)
    if not achou then
      estado.recusas = estado.recusas + 1
      return protocolo.erro(m.id, extra)
    end
    l, s = achou, extra
  end

  local comeco = os.clock()
  local ok, res, erro = pcall(fn, m.dados or {}, l, s, de, m.token)
  medir(rota, os.clock() - comeco)

  if not ok then
    central.log(("erro interno em %s: %s"):format(rota, tostring(res)), C.ruim)
    return protocolo.erro(m.id, "erro interno na central")
  end
  if not res then
    estado.recusas = estado.recusas + 1
    return protocolo.erro(m.id, erro or "pedido recusado")
  end

  estado.pedidos = estado.pedidos + 1
  return protocolo.ok(m.id, res)
end

-- exposto para o banco de testes fora do jogo poder mandar pedidos sem
-- precisar de modem, tela nem teclado
central.atender = atender

--- Carrega tudo do disco. Separado do laco para os testes poderem subir a
-- central sem rede.
function central.prepararDados()
  linhas.carregar()
  bloqueio.carregar()
  recados.carregar()
  denuncias.carregar()
end

--- Pedidos por minuto desde que a central subiu.
--
-- Media do periodo inteiro, e nao dos ultimos segundos: numa central que
-- passou a noite parada, a media do periodo conta a historia, e a instantanea
-- so conta o momento em que alguem olhou.
function central.porMinuto()
  local minutos = central.tempoNoAr() / 60
  if minutos < 0.1 then return 0 end
  return (estado.pedidos + estado.recusas) / minutos
end

function central.tempoNoAr()
  return math.floor((os.epoch("utc") - estado.desde) / 1000)
end

--- Resumo do custo, do mais caro para o mais barato.
function central.custos()
  local saida = {}
  for rota, c in pairs(estado.custo) do
    saida[#saida + 1] = {
      rota = rota, n = c.n, tempo = c.tempo,
      media = c.n > 0 and (c.tempo / c.n) or 0,
    }
  end
  table.sort(saida, function(a, b) return a.tempo > b.tempo end)
  return saida
end

-- --------------------------------------------------------------------- lacos

local function lacoRede()
  while estado.rodando do
    if not estado.modem then
      -- Sem modem a central nao morre: fica procurando. Encaixar um Ender
      -- Modem poe a FALAE no ar sem ninguem reiniciar nada, e o console diz o
      -- que esta faltando enquanto isso.
      local nome = protocolo.abrirModem()
      if nome then
        estado.modem = nome
        rednet.host(protocolo.REDE, protocolo.HOST)
        central.log("modem em " .. nome .. " - FALAE no ar", C.bom)
      else
        sleep(3)
      end
    else
      local de, m = rednet.receive(protocolo.REDE, 5)
      if de then
        if protocolo.valido(m) then
          -- rednet.send nao levanta erro sem modem: devolve false, calado.
          -- Conferido no CraftOS-PC. Sem olhar esse retorno, quebrar o Ender
          -- Modem deixava a FALAE muda com o painel dizendo "modem ok" - a
          -- pior forma de estar fora do ar, a que ninguem ve.
          if not rednet.send(de, atender(de, m), protocolo.REDE) then
            estado.modem = nil
            central.log("o envio falhou - perdi o modem?", C.ruim)
          end
        else
          -- lixo, versao velha de telefone, ou alguem brincando com o modem
          estado.recusas = estado.recusas + 1
        end
      end
    end
  end
end

--- Tudo que precisa varrer alguma coisa mora aqui, longe do caminho de um
-- pedido. E o outro lado da regra de desempenho: a varredura nao deixa de
-- existir, ela so nao acontece enquanto alguem espera resposta.
local function lacoManutencao()
  while estado.rodando do
    sleep(60)

    local foram = linhas.faxinar()
    if foram > 0 then
      central.log(("%d sessao(oes) vencida(s) na faxina"):format(foram), C.fraco)
    end
    linhas.salvarSessoes()

    -- Modem encaixado depois que a central subiu entra sozinho na proxima
    -- volta, sem reiniciar nada.
    if estado.modem then
      local resumo = protocolo.abrirModem()
      if not resumo then
        -- Modem arrancado. Zerar o estado devolve a central para o ramo que
        -- procura modem no lacoRede, e la ela volta a hospedar o nome da rede
        -- sozinha quando alguem encaixar outro.
        estado.modem = nil
        central.log("fiquei sem modem - procurando", C.ruim)
      elseif resumo ~= estado.modem then
        estado.modem = resumo
        central.log("modems agora: " .. resumo, C.marca)
      end
    end
  end
end

--- O monitor da sede, se houver um encostado.
--
-- No maximo a cada 3s, e mesmo assim so escreve o que mudou (ver painel.lua).
-- Monitor de CC e sincronizado com todo cliente por perto: redesenhar a toa
-- vira trafego no servidor Minecraft inteiro, nao so aqui.
local function lacoTela(painel)
  while estado.rodando do
    estado.porMinuto = central.porMinuto()
    pcall(painel.atualizar, estado, central.custos())

    -- monitor que deu erro aparece no log uma vez, em vez de ficar preto sem
    -- explicacao nenhuma
    local ok, erros = pcall(painel.errosNovos)
    if ok and erros then
      for _, e in ipairs(erros) do central.log("monitor: " .. e, C.aviso) end
    end

    sleep(3)
  end
end

--- Manda um snapshot de numeros para o painel externo, no ritmo de
-- telemetria.INTERVALO. So entra na lista de tarefas se
-- telemetria.configurado() - uma central sem painel nao ganha um laco a mais
-- rodando a toa.
local function lacoTelemetria()
  while estado.rodando do
    sleep(telemetria.INTERVALO)
    local ok, motivo = telemetria.enviar(estado, central.custos())
    if not ok then
      -- so uma vez, no fraco: falha de painel externo e esperada (a Vercel
      -- pode estar fora do ar) e nao merece o mesmo peso de um erro interno
      central.log("painel: " .. tostring(motivo), C.fraco)
    end
  end
end

--- Sobe a FALAE. Volta quando o console pede para sair.
function central.rodar()
  central.prepararDados()
  central.log(("%d linha(s), %d recado(s)"):format(linhas.quantas(), recados.quantos()), C.marca)

  local console = lib("console")
  console.ligar(central)

  -- A parte visual e OPCIONAL. Sem monitor, ou com os modulos de desenho fora
  -- do disquete (eles sao a primeira coisa a ficar de fora quando aperta), a
  -- central atende igual. Uma operadora precisa atender, nao desenhar um
  -- balao.
  local painel, monitores
  local okTela = pcall(function()
    painel = lib("painel")
    monitores = painel.achar()
  end)

  local tarefas = { lacoRede, lacoManutencao, console.laco }

  if telemetria.configurado() then
    tarefas[#tarefas + 1] = lacoTelemetria
    central.log("painel externo configurado", C.fraco)
  end

  if okTela and painel and monitores and #monitores > 0 then
    pcall(painel.abrir, monitores, estado)
    -- ligar devolve QUANTOS monitores entraram. Comparar com zero e nao usar o
    -- numero como condicao: em Lua, 0 e verdadeiro.
    if painel.ligar(monitores) > 0 then
      tarefas[#tarefas + 1] = function() lacoTela(painel) end
      console.painel = painel
      central.log(("%d monitor(es) ligado(s)"):format(painel.quantas()), C.fraco)
    end
  elseif not okTela then
    central.log("sem os modulos de tela - rodando sem monitor", C.fraco)
  end

  parallel.waitForAny(table.unpack(tarefas))

  estado.rodando = false
  linhas.salvarSessoes()
  if painel then pcall(painel.desligar) end

  term.setBackgroundColour(colors.black)
  term.setTextColour(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  print("FALAE fora do ar.")
end

return central
