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
]]

local lib      = dofile("/core/lib.lua")
local numero   = lib("numero")
local linhas   = lib("linhas")
local recados  = lib("recados")
local bloqueio = lib("bloqueio")

local console = {}

local C   -- cores, vem da central
local central

function console.ligar(c)
  central = c
  C = c.CORES
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

  local _, h = term.getSize()
  for i = 1, math.min(4, #e.log) do
    local reg = e.log[#e.log - i + 1]
    linha(h - 1 - i, (" %s %s"):format(reg.hora, reg.texto), reg.cor)
  end

  rodape("L linhas  R zerar PIN  X cassar  C custo  G log  Q sai")
end

function console.linhas()
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

  local ok = linhas.zerarPin(canonico)
  if not ok then
    return avisar("nao consegui zerar", C.ruim)
  end

  central.log(("PIN zerado em %s no balcao"):format(numero.formatar(canonico)), C.aviso)
  avisar(("PIN de %s (%s) zerado - a pessoa define um novo ao entrar"):format(
         numero.formatar(canonico), pub.nome), C.bom)
end

function console.cassar()
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
  linhas.remover(canonico)

  central.log(("linha %s cassada no balcao"):format(numero.formatar(canonico)), C.aviso)
  avisar(("linha apagada, com %d recado(s)"):format(apagados), C.bom)
end

--- O que cada rota esta custando. Sem isto, "a FALAE esta lenta" e uma
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
      elseif p1 == keys.c then
        console.custos()
      elseif p1 == keys.g then
        console.verLog()
      end
      if e.rodando then console.principal() end
    elseif evento == "timer" and p1 == temporizador then
      console.principal()
    end
  end
end

return console
