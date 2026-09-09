--[[ console - o balcao de atendimento da FALAE

  O teclado da central. E aqui que a operadora faz o que nenhuma rota da rede
  pode fazer: zerar o PIN de quem esqueceu, cassar uma linha, e olhar quanto
  cada rota esta custando.

  Zerar PIN nao existe pela rede DE PROPOSITO. Se existisse, seria a rota mais
  valiosa da FALAE para quem quisesse roubar uma linha - e ela viajaria por um
  rednet que qualquer um escuta. Atendimento e coisa de teclado, com a pessoa
  na frente. E a mesma escolha que a Expresso Labs fez com a troca de senha.

  A central nao sabe PIN de ninguem: zerar apaga o resumo, e a pessoa define um
  novo no proximo login do aparelho dela. A operadora nunca ve, nunca digita e
  nunca pode contar o PIN de um cliente.

  ISTO AQUI E TRANCADO, e nao era. Ate a chave por disquete existir, qualquer
  um que chegasse no teclado da central cassava linha, zerava PIN e lia
  denuncia - e era um buraco maior que o do boot, porque ligar a central nao
  faz mal a ninguem e cassar a linha de uma pessoa faz.

  Destrancar quer o disquete E o PIN. A sessao vale dez minutos e morre no
  instante em que o disquete sai do drive: acabou o atendimento, leva a chave.
]]

local lib      = dofile("/core/lib.lua")
local numero   = lib("numero")
local linhas   = lib("linhas")
local recados  = lib("recados")
local bloqueio = lib("bloqueio")
local denuncias = lib("denuncias")
local chave     = lib("chave")
local chaveiro  = lib("chaveiro")
local tranca    = lib("tranca")
local exportacao = lib("exportacao")
local telemetria = lib("telemetria")

local console = {}

local C   -- cores, vem da central
local central

-- A sessao do balcao. nil = trancado.
local sessao = nil

function console.ligar(c)
  central = c
  C = c.CORES
  tranca.usar(chave, chaveiro)
  chaveiro.carregar()
end

-- ------------------------------------------------------------------ desenho

local function limpar()
  term.setBackgroundColour(C.fundo)
  term.setTextColour(C.texto)
  term.clear()
  term.setCursorPos(1, 1)
end

local function linha(y, texto, cor)
  term.setCursorPos(1, y)
  term.setTextColour(cor or C.texto)
  term.clearLine()
  term.write(texto)
end

local function cabecalho(titulo)
  limpar()
  local w = term.getSize()
  term.setBackgroundColour(C.marca)
  term.setTextColour(colors.black)
  term.setCursorPos(1, 1)
  term.write((" FALAE  " .. titulo):sub(1, w) .. string.rep(" ", math.max(0, w - #titulo - 8)))
  term.setBackgroundColour(C.fundo)
end

local function rodape(texto)
  local w, h = term.getSize()
  term.setCursorPos(1, h)
  term.setTextColour(C.fraco)
  term.clearLine()
  term.write(texto:sub(1, w))
end

--- Le uma linha de texto no rodape. Bloqueia o console, e tudo bem: a tarefa
-- de rede continua atendendo em paralelo enquanto a operadora digita.
local function perguntar(rotulo)
  local w, h = term.getSize()
  term.setCursorPos(1, h)
  term.setBackgroundColour(C.fundo)
  term.setTextColour(C.marca)
  term.clearLine()
  term.write(rotulo:sub(1, w - 1) .. " ")
  term.setTextColour(C.texto)
  local resposta = read()
  return resposta
end

local function avisar(texto, cor)
  local _, h = term.getSize()
  term.setCursorPos(1, h)
  term.setTextColour(cor or C.texto)
  term.clearLine()
  term.write(texto)
  term.setTextColour(C.fraco)
  term.write("  (tecla)")
  os.pullEvent("key")
end

-- ----------------------------------------------------------------- a tranca

--- Esta destrancado agora?
--
-- Confere a sessao E o disquete: tirar o disquete tranca na hora, sem esperar
-- o prazo acabar. E o gesto que a pessoa ja tem na mao - acabou, leva a chave.
function console.destrancado()
  if not tranca.sessaoValida(sessao) then sessao = nil end
  return sessao ~= nil
end

--- Exige a chave antes de uma acao perigosa. Volta true se pode seguir.
function console.exigir()
  if console.destrancado() then
    -- usar renova o prazo: quem esta atendendo nao pode ser interrompido no
    -- meio de um atendimento para digitar o PIN de novo
    sessao.ate = os.epoch("utc") + tranca.SESSAO
    return true
  end

  local k, motivo = tranca.abrir("central", "balcao trancado")
  if not k then
    -- Vai para o log da central, que fica na tela e no painel do monitor: uma
    -- chave recusada e a coisa que a operadora mais precisa ver quando voltar.
    if motivo ~= "cancelado" then
      central.log("balcao recusou uma chave: " .. tostring(motivo), C.aviso)
    end
    console.principal()
    if motivo ~= "cancelado" then avisar(tostring(motivo), C.ruim) end
    return false
  end

  sessao = tranca.novaSessao(k, tranca.disco())
  central.log(("balcao aberto com a chave %s"):format(k.nome), C.marca)
  return true
end

--- Fecha o balcao na hora, sem esperar o prazo.
function console.trancar()
  sessao = nil
end

-- ------------------------------------------------------------------- telas

local function quando(ms)
  if not ms then return "-" end
  local seg = math.floor((os.epoch("utc") - ms) / 1000)
  if seg < 60 then return seg .. "s" end
  if seg < 3600 then return math.floor(seg / 60) .. "min" end
  if seg < 86400 then return math.floor(seg / 3600) .. "h" end
  return math.floor(seg / 86400) .. "d"
end

function console.principal()
  local e = central.estado
  cabecalho("central")

  local noAr = central.tempoNoAr()
  linha(3, "modem     " .. (e.modem or "procurando..."), e.modem and C.bom or C.aviso)
  linha(4, ("no ar     %dmin"):format(math.floor(noAr / 60)))
  linha(6, ("linhas    %d"):format(linhas.quantas()), C.marca)
  linha(7, ("recados   %d guardados"):format(recados.quantos()))
  linha(9, ("pedidos   %d"):format(e.pedidos))
  linha(10, ("  vazios  %d  (nada mudou)"):format(e.rapidas), C.fraco)
  linha(11, ("recusas   %d"):format(e.recusas), e.recusas > 0 and C.aviso or C.fraco)

  local esperando = denuncias.quantasPendentes()
  if esperando > 0 then
    linha(13, ("%d denuncia(s) esperando   (D)"):format(esperando), C.ruim)
  end

  local _, h = term.getSize()
  for i = 1, math.min(4, #e.log) do
    local reg = e.log[#e.log - i + 1]
    linha(h - 1 - i, (" %s %s"):format(reg.hora, reg.texto), reg.cor)
  end

  local _, hh = term.getSize()
  if console.destrancado() then
    term.setCursorPos(1, hh - 1)
    term.setTextColour(C.bom)
    term.clearLine()
    term.write((" balcao aberto: %s   (F fecha)"):format(sessao.nome or "chave"))
  end

  rodape("L linhas  R PIN  X cassar  D denuncias  J judicial  K chaves  P painel  C custo  G log  T telas  Q sai")
end

-- ----------------------------------------------------------------- chaves

--- As chaves que esta central aceita.
--
-- Nao mostra segredo nenhum porque nao tem: o chaveiro guarda impressao. O que
-- da para ver e o que serve para decidir - qual disquete, que papel, quando
-- foi usada pela ultima vez.
function console.chaves()
  -- Gatilhada como a lista de linhas: ver quais disquetes abrem esta central
  -- nao deixa ninguem entrar (id de disquete nao se fabrica), mas e a planta da
  -- fechadura, e planta de fechadura fica com quem tem a chave.
  if not console.exigir() then return end

  while true do
    cabecalho("chaves")
    local lista = chaveiro.listar()

    if #lista == 0 then
      linha(3, "nenhuma chave - central sem dono", C.ruim)
    else
      linha(3, ("disquete  papel     ultima vez  chave"), C.fraco)
      for i, k in ipairs(lista) do
        local marca = (sessao and tostring(sessao.disco) == tostring(k.disco))
                      and " *" or "  "
        linha(3 + i, ("#%-8s %-9s %-11s %s%s"):format(
              tostring(k.disco), k.papel, quando(k.ultimoUso), k.nome, marca),
              k.travadaAte and k.travadaAte > os.epoch("utc") and C.ruim or C.texto)
      end
    end

    rodape("N nova chave   B revogar   qualquer outra volta")
    local _, tecla = os.pullEvent("key")

    if tecla == keys.n then
      console.emitirChave()
    elseif tecla == keys.b then
      console.revogarChave()
    else
      return
    end
  end
end

--- Emite uma chave nova no disquete que estiver no drive.
function console.emitirChave()
  if not console.exigir() then return end

  local id, motivo = tranca.disco()
  if not id then return avisar(motivo, C.ruim) end

  cabecalho("chave nova")
  linha(3, "disquete #" .. tostring(id), C.marca)
  linha(5, "papel:", C.fraco)
  linha(6, "  central  abre a central e o balcao", C.fraco)
  linha(7, "  loja     abre so o computador da loja", C.fraco)

  local papel = perguntar("papel (central/loja):")
  if not chave.PAPEIS[papel] then return avisar("papel desconhecido", C.ruim) end

  local nome = perguntar("nome da chave:")
  if nome == "" then nome = papel end

  local pin = tranca.lerPin("PIN da chave nova:")
  if not pin then return end
  local outra = tranca.lerPin("de novo:")
  if outra ~= pin then return avisar("os dois PINs nao batem", C.ruim) end

  local k, erro = tranca.emitir(nome, papel, pin)
  if not k then return avisar(tostring(erro), C.ruim) end

  central.log(("chave %s emitida no disquete #%s"):format(nome, tostring(id)), C.bom)
  avisar("chave gravada no disquete #" .. tostring(id), C.bom)
end

--- Tira uma chave da lista. O disquete continua existindo; ele so deixa de
-- abrir esta central - que e o que se quer quando um sumiu.
function console.revogarChave()
  if not console.exigir() then return end

  local texto = perguntar("revogar qual disquete (numero):")
  if texto == "" then return end

  local ok, motivo = chaveiro.remover(texto)
  if not ok then return avisar(tostring(motivo or "nao achei essa chave"), C.ruim) end

  -- Revogar a propria chave que abriu o balcao fecha o balcao: continuar
  -- destrancado por uma chave que acabou de deixar de valer seria mentira.
  if sessao and tostring(sessao.disco) == tostring(texto) then
    console.trancar()
  end

  central.log(("chave do disquete #%s revogada"):format(texto), C.aviso)
  avisar("revogada", C.bom)
end

function console.linhas()
  -- A lista de linhas nao e publica: sao os numeros e os nomes de todo mundo
  -- que tem linha, num so lugar. Ver isso ja e operar.
  if not console.exigir() then return end

  local lista = linhas.lista()
  local topo = 1
  local _, h = term.getSize()
  local cabem = h - 4

  while true do
    cabecalho(("linhas (%d)"):format(#lista))
    if #lista == 0 then
      linha(3, "nenhuma linha ainda.", C.fraco)
    end
    for i = 0, cabem - 1 do
      local l = lista[topo + i]
      if not l then break end
      local marca = l.semPin and " [sem PIN]" or ""
      linha(3 + i, ("%s  %-16s %s%s"):format(
            numero.formatar(l.numero), l.nome, quando(l.visto), marca),
            l.semPin and C.aviso or C.texto)
    end
    rodape("setas rolam   Q volta")

    local _, tecla = os.pullEvent("key")
    if tecla == keys.q or tecla == keys.backspace then return end
    if tecla == keys.down and topo + cabem <= #lista then topo = topo + 1 end
    if tecla == keys.up and topo > 1 then topo = topo - 1 end
  end
end

function console.zerarPin()
  if not console.exigir() then return end

  local texto = perguntar("numero da linha:")
  if texto == "" then return end

  local canonico = numero.canonico(texto)
  if not canonico then
    return avisar("numero invalido", C.ruim)
  end

  local pub = linhas.publico(canonico)
  if not pub then
    return avisar("essa linha nao existe", C.ruim)
  end

  local codigo = linhas.zerarPin(canonico)
  if not codigo then
    return avisar("nao consegui zerar", C.ruim)
  end

  -- O codigo NAO vai para o log. O log rola na tela da central e fica; o
  -- codigo e para ser dito uma vez, para a pessoa que esta na frente.
  central.log(("PIN zerado em %s no balcao"):format(numero.formatar(canonico)), C.aviso)
  avisar(("%s (%s): diga o codigo %s - vale 24h"):format(
         numero.formatar(canonico), pub.nome, codigo), C.bom)
end

function console.cassar()
  if not console.exigir() then return end

  local texto = perguntar("cassar qual numero:")
  if texto == "" then return end

  local canonico = numero.canonico(texto)
  if not canonico or not linhas.publico(canonico) then
    return avisar("essa linha nao existe", C.ruim)
  end

  local pub = linhas.publico(canonico)
  local certeza = perguntar(("apagar %s (%s) e a conversa dela? s/N:"):format(
                            numero.formatar(canonico), pub.nome))
  if certeza:lower() ~= "s" then return end

  local apagados = recados.esquecer(canonico)
  bloqueio.esquecer(canonico)
  -- as denuncias vao junto, dos dois lados: uma denuncia carrega um recado, e
  -- deixa-la para tras guardaria conversa de uma linha que a FALAE disse ter
  -- apagado
  denuncias.esquecer(canonico)
  linhas.remover(canonico)

  central.log(("linha %s cassada no balcao"):format(numero.formatar(canonico)), C.aviso)
  avisar(("linha apagada, com %d recado(s)"):format(apagados), C.bom)
end

--- A fila de denuncias. O UNICO lugar onde um recado alheio aparece.
--
-- Aqui, e nao no painel, porque aqui e o teclado da central: quem esta olhando
-- e a operadora. O painel de parede fica numa sala por onde qualquer um passa e
-- so mostra quantas esperam.
--
-- Mostra quantas vezes aquele numero ja foi denunciado e por quantas pessoas
-- DIFERENTES - e o que separa briga de dois de um problema de verdade.
function console.denuncias()
  -- E aqui que mora o unico texto de recado que a central guarda. Se alguma
  -- tela deste console precisa de chave, e esta.
  if not console.exigir() then return end

  local escolhida = 1

  while true do
    local lista = denuncias.pendentes()
    if escolhida > #lista then escolhida = math.max(1, #lista) end

    cabecalho(("denuncias (%d)"):format(#lista))

    if #lista == 0 then
      linha(3, "nenhuma denuncia esperando.", C.fraco)
      linha(5, "Quem recebe algo ruim denuncia", C.fraco)
      linha(6, "pelo proprio telefone, na tecla D.", C.fraco)
      rodape("Q volta")
    else
      local d = lista[escolhida]
      local vezes, pessoas = denuncias.historicoDe(d.sobre)

      linha(3, ("%d de %d"):format(escolhida, #lista), C.fraco)

      linha(5, "sobre    " .. numero.formatar(d.sobre), C.marca)
      local pub = linhas.publico(d.sobre)
      linha(6, "         " .. (pub and pub.nome or "(linha ja apagada)"), C.fraco)

      linha(8, "de       " .. numero.formatar(d.de), C.texto)
      linha(9, "quando   " .. quando(d.quando) .. " atras", C.fraco)

      if vezes > 1 then
        linha(11, ("ja denunciado %d vezes, por %d pessoa(s)"):format(vezes, pessoas),
              pessoas > 1 and C.ruim or C.aviso)
      else
        linha(11, "primeira denuncia sobre esse numero", C.fraco)
      end

      -- o recado, que e o motivo de esta tela existir
      local w = term.getSize()
      linha(13, "o recado:", C.fraco)
      linha(14, "  " .. tostring(d.texto or ""):sub(1, w - 3), C.texto)

      rodape("setas  A arquiva  X cassa a linha  Q volta")
    end

    local _, tecla = os.pullEvent("key")
    if tecla == keys.q or tecla == keys.backspace then return end

    if #lista > 0 then
      local d = lista[escolhida]

      if tecla == keys.down and escolhida < #lista then
        escolhida = escolhida + 1
      elseif tecla == keys.up and escolhida > 1 then
        escolhida = escolhida - 1

      elseif tecla == keys.a then
        denuncias.resolver(d.n, "arquivada")
        central.log(("denuncia %d arquivada"):format(d.n), C.fraco)

      elseif tecla == keys.x then
        local certeza = perguntar(("cassar %s e apagar a conversa dela? s/N:")
                                  :format(numero.formatar(d.sobre)))
        if certeza:lower() == "s" then
          local apagados = recados.esquecer(d.sobre)
          bloqueio.esquecer(d.sobre)
          -- resolve ANTES de esquecer: esquecer apaga a denuncia junto com a
          -- linha, e resolver depois nao acharia mais nada para marcar
          denuncias.resolver(d.n, "linha cassada")
          denuncias.esquecer(d.sobre)
          linhas.remover(d.sobre)
          central.log(("linha %s cassada por denuncia"):format(
                      numero.formatar(d.sobre)), C.aviso)
          avisar(("linha apagada, com %d recado(s)"):format(apagados), C.bom)
        end
      end
    end
  end
end

-- --------------------------------------------------------------- o painel

--- Liga, desliga e mostra o status do painel externo (numeros, nunca texto -
-- ver servidor/core/telemetria.lua).
--
-- Atras da chave pelo mesmo motivo do resto: o token que vai aqui autoriza
-- mandar dados desta central para fora do jogo, e quem configura isso precisa
-- provar que e a operadora.
function console.telemetria()
  if not console.exigir() then return end

  while true do
    cabecalho("painel externo")
    local cfg = telemetria.lerConfig()

    if not cfg then
      linha(3, "nenhum painel configurado.", C.fraco)
      linha(5, "A central manda so NUMEROS -", C.fraco)
      linha(6, "linhas, recados, saude de rede.", C.fraco)
      linha(7, "Nunca texto de conversa.", C.fraco)
      rodape("N configurar   Q volta")
    else
      linha(3, "endereco:", C.fraco)
      linha(4, "  " .. cfg.url:sub(1, 45), C.texto)
      linha(6, ("manda a cada %ds"):format(telemetria.INTERVALO), C.fraco)

      if telemetria.ultimoEnvio then
        local ha = math.floor((os.epoch("utc") - telemetria.ultimoEnvio) / 1000)
        linha(7, ("ultimo envio: ha %ds"):format(ha), C.bom)
      else
        linha(7, "ainda nao mandou nada nesta sessao", C.fraco)
      end

      rodape("N trocar   B desligar   T testar agora   Q volta")
    end

    local _, tecla = os.pullEvent("key")
    if tecla == keys.q or tecla == keys.backspace then return end

    if tecla == keys.n then
      console.configurarTelemetria()
    elseif tecla == keys.b and cfg then
      telemetria.apagarConfig()
      central.log("painel externo desligado", C.fraco)
      avisar("desligado", C.bom)
    elseif tecla == keys.t and cfg then
      avisar("mandando...", C.fraco)
      local ok, motivo = telemetria.enviar(central.estado, central.custos())
      if ok then
        avisar("deu certo", C.bom)
      else
        avisar(tostring(motivo), C.ruim)
      end
    end
  end
end

function console.configurarTelemetria()
  cabecalho("painel externo")
  linha(3, "cole o endereco que a Vercel deu,", C.fraco)
  linha(4, "e o token de push (nao a chave da", C.fraco)
  linha(5, "IA - esse token e so desta central).", C.fraco)

  local url = perguntar("endereco (https://...):")
  if url == "" then return end
  local token = perguntar("token:")
  if token == "" then return end

  local ok, erro = telemetria.gravarConfig(url, token)
  if not ok then return avisar(tostring(erro), C.ruim) end

  central.log("painel externo configurado", C.bom)
  avisar("gravado - o proximo boot ja manda numeros", C.bom)
end

-- ------------------------------------------------------------ ordem judicial

--- Exporta uma conversa para o disquete, por ordem judicial.
--
-- E A UNICA TELA QUE TIRA TEXTO DE RECADO DA CENTRAL PARA FORA - e ela tira
-- para um DISQUETE, nunca para a rede. Nao existe um botao "mandar pelo
-- rednet" aqui, nem vai existir: o texto sai fisicamente com quem tem a
-- chave, e so depois de dizer por que.
--
-- Atras da mesma chave que tranca denuncia e cassacao. O motivo e obrigatorio
-- e fica gravado para sempre em exportacao.LOG, mesmo se a gravacao no
-- disquete falhar depois - o rastro e do PEDIDO, nao do sucesso da copia.
function console.exportarJudicial()
  if not console.exigir() then return end

  cabecalho("exportacao judicial")
  linha(3, "O texto sai so para um disquete.", C.fraco)
  linha(4, "Nunca pela rede. O pedido fica no", C.fraco)
  linha(5, "log de auditoria para sempre.", C.fraco)

  local numeroA = perguntar("numero (obrigatorio):")
  if numeroA == "" then return end

  local numeroB = perguntar("com este numero (vazio = tudo dele):")

  local motivo = perguntar("motivo (obrigatorio, ex: processo 123):")
  if motivo == "" then return avisar("sem motivo, nao exporta", C.ruim) end

  local id, motivoDrive, d = tranca.disco()
  if not id then return avisar(motivoDrive, C.ruim) end

  local texto, erro = exportacao.montar(numeroA, numeroB, motivo,
                                        sessao and sessao.nome or "?")
  if not texto then return avisar(tostring(erro), C.ruim) end

  local mp = d.getMountPath()
  local arquivo = fs.combine(mp, exportacao.nomeArquivo())
  local f = fs.open(arquivo, "w")
  if not f then
    return avisar("registrei o pedido, mas nao gravei no disquete", C.aviso)
  end
  f.write(texto)
  f.close()

  central.log(("exportacao judicial: %s (motivo: %s)"):format(
              numeroA, motivo:sub(1, 40)), C.aviso)
  avisar("gravado no disquete #" .. tostring(id), C.bom)
end

--- Os monitores: o que a central achou, e a troca entre eles.
--
-- A lista existe para responder dentro do jogo a pergunta que de fora nao da
-- para responder: os dois monitores estao mesmo funcionando? Se aparecer um
-- so, quase sempre e uma destas duas coisas - os dois blocos encostados e
-- alinhados viraram UM monitor (o CC funde monitores adjacentes), ou o segundo
-- nao alcanca a central e precisa de um Wired Modem com cabo.
function console.telas()
  while true do
    cabecalho("monitores")

    if not console.painel then
      linha(3, "os modulos de tela nao foram", C.aviso)
      linha(4, "instalados nesta central.", C.aviso)
      linha(6, "rode o instalador de novo e", C.fraco)
      linha(7, "aceite a parte visual.", C.fraco)
      rodape("Q volta")
    else
      local lista = console.painel.diagnostico()

      if #lista == 0 then
        linha(3, "nenhum monitor encontrado.", C.aviso)
        linha(5, "O monitor precisa encostar na", C.fraco)
        linha(6, "central, ou chegar nela por um", C.fraco)
        linha(7, "Wired Modem com cabo.", C.fraco)
      else
        linha(3, ("%d monitor(es) ligado(s):"):format(#lista), C.marca)
        local y = 5
        for _, m in ipairs(lista) do
          linha(y, ("  %s"):format(m.nome), C.texto)
          linha(y + 1, ("    mostra: %s"):format(m.papel), C.fraco)
          linha(y + 2, ("    %dx%d, escala %s"):format(
                m.colunas, m.linhas, tostring(m.escala or "?")), C.fraco)
          if m.papel == "marca" then
            linha(y + 3, ("    nome: %s"):format(
                  m.nomeDesenhado and "desenhado" or "em caracteres"), C.fraco)
            y = y + 1
          end
          if m.erro then
            linha(y + 3, "    ERRO: " .. m.erro:sub(1, 28), C.ruim)
            y = y + 1
          end
          y = y + 4
        end

        if #lista == 1 then
          local _, h = term.getSize()
          linha(h - 3, "so um? os dois blocos encostados", C.aviso)
          linha(h - 2, "viram UM monitor. Separe-os.", C.aviso)
        end
      end

      rodape(#lista >= 2 and "T troca os dois   Q volta" or "Q volta")
    end

    local _, tecla = os.pullEvent("key")
    if tecla == keys.q or tecla == keys.backspace then return end
    if tecla == keys.t and console.painel and console.painel.quantas() >= 2 then
      console.painel.inverter()
    end
  end
end

--- O que cada rota esta custando.--- O que cada rota esta custando. Sem isto, "a FALAE esta lenta" e uma
-- sensacao; com isto e uma linha dizendo qual rota e quanto.
function console.custos()
  cabecalho("custo por rota")
  local lista = central.custos()

  if #lista == 0 then
    linha(3, "nenhum pedido ainda.", C.fraco)
  else
    linha(3, ("%-16s %7s %9s %9s"):format("rota", "vezes", "total", "media"), C.fraco)
    local _, h = term.getSize()
    for i = 1, math.min(#lista, h - 6) do
      local c = lista[i]
      linha(4 + i - 1, ("%-16s %7d %8.3fs %8.4fs"):format(
            c.rota:sub(1, 16), c.n, c.tempo, c.media))
    end
  end

  local e = central.estado
  local total = e.pedidos + e.recusas
  local _, h = term.getSize()
  if total > 0 then
    linha(h - 2, ("%d%% dos pedidos foram 'nada mudou'"):format(
          math.floor(e.rapidas / total * 100)), C.marca)
  end

  rodape("Q volta")
  repeat
    local _, tecla = os.pullEvent("key")
  until tecla == keys.q or tecla == keys.backspace
end

function console.verLog()
  cabecalho("log")
  local e = central.estado
  local _, h = term.getSize()
  local cabem = h - 4
  local inicio = math.max(1, #e.log - cabem + 1)
  for i = inicio, #e.log do
    local reg = e.log[i]
    linha(3 + i - inicio, (" %s %s"):format(reg.hora, reg.texto), reg.cor)
  end
  if #e.log == 0 then linha(3, "nada aconteceu ainda.", C.fraco) end
  rodape("Q volta")
  repeat
    local _, tecla = os.pullEvent("key")
  until tecla == keys.q or tecla == keys.backspace
end

-- --------------------------------------------------------------------- laco

function console.laco()
  local e = central.estado
  console.principal()

  while e.rodando do
    -- timer curto para o painel do console acompanhar os contadores sem
    -- precisar de tecla; ele so redesenha texto, nao a tela toda
    local temporizador = os.startTimer(2)
    local evento, p1 = os.pullEvent()

    if evento == "key" then
      os.cancelTimer(temporizador)
      if p1 == keys.q then
        e.rodando = false
      elseif p1 == keys.l then
        console.linhas()
      elseif p1 == keys.r then
        console.zerarPin()
      elseif p1 == keys.x then
        console.cassar()
      elseif p1 == keys.k then
        console.chaves()
      elseif p1 == keys.f then
        -- fechar o balcao na saida e o habito que faz a tranca valer: quem
        -- vai embora leva a chave, mas quem so vira as costas aperta F
        console.trancar()
      elseif p1 == keys.c then
        console.custos()
      elseif p1 == keys.g then
        console.verLog()
      elseif p1 == keys.t then
        console.telas()
      elseif p1 == keys.d then
        console.denuncias()
      elseif p1 == keys.j then
        console.exportarJudicial()
      elseif p1 == keys.p then
        console.telemetria()
      end
      if e.rodando then console.principal() end
    elseif evento == "timer" and p1 == temporizador then
      console.principal()
    end
  end
end

return console
