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

  Doze telas caberiam num arquivo so, mas nao devem: cada console_*.lua abaixo
  e um grupo que realmente compartilha algo (o que mexe na chave, o que mexe
  em linha, os dois que tocam texto de recado, os que nao pedem chave
  nenhuma). Este arquivo fica com o que toda tela-filha precisa de volta - os
  helpers de desenho, a tranca, a tela principal e o laco - e QUEM MONTA a
  tabela `console` que elas preenchem.
]]

local lib      = dofile("/core/lib.lua")
local linhas   = lib("linhas")
local recados  = lib("recados")
local denuncias = lib("denuncias")
local chave     = lib("chave")
local chaveiro  = lib("chaveiro")
local tranca    = lib("tranca")

local console = {}

--- O que cada console_*.lua recebe para desenhar igual e chamar de volta no
-- resto do balcao: as cores e o objeto `central` mudam de valor so uma vez,
-- no console.ligar() abaixo - por isso vivem NUM CAMPO desta tabela (lida de
-- novo a cada chamada), e nao num parametro capturado no momento em que cada
-- modulo-filho e carregado, que aconteceria ANTES do ligar().
local ajuda = {}

-- A sessao do balcao. nil = trancado.
local sessao = nil

function console.ligar(c)
  ajuda.central = c
  ajuda.C = c.CORES
  tranca.usar(chave, chaveiro)
  chaveiro.carregar()
end

-- ------------------------------------------------------------------ desenho

local function limpar()
  local C = ajuda.C
  term.setBackgroundColour(C.fundo)
  term.setTextColour(C.texto)
  term.clear()
  term.setCursorPos(1, 1)
end

local function linha(y, texto, cor)
  term.setCursorPos(1, y)
  term.setTextColour(cor or ajuda.C.texto)
  term.clearLine()
  term.write(texto)
end
ajuda.linha = linha

local function cabecalho(titulo)
  limpar()
  local C = ajuda.C
  local w = term.getSize()
  term.setBackgroundColour(C.marca)
  term.setTextColour(colors.black)
  term.setCursorPos(1, 1)
  term.write((" FALAE  " .. titulo):sub(1, w) .. string.rep(" ", math.max(0, w - #titulo - 8)))
  term.setBackgroundColour(C.fundo)
end
ajuda.cabecalho = cabecalho

local function rodape(texto)
  local w, h = term.getSize()
  term.setCursorPos(1, h)
  term.setTextColour(ajuda.C.fraco)
  term.clearLine()
  term.write(texto:sub(1, w))
end
ajuda.rodape = rodape

--- Le uma linha de texto no rodape. Bloqueia o console, e tudo bem: a tarefa
-- de rede continua atendendo em paralelo enquanto a operadora digita.
local function perguntar(rotulo)
  local C = ajuda.C
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
ajuda.perguntar = perguntar

local function avisar(texto, cor)
  local C = ajuda.C
  local _, h = term.getSize()
  term.setCursorPos(1, h)
  term.setTextColour(cor or C.texto)
  term.clearLine()
  term.write(texto)
  term.setTextColour(C.fraco)
  term.write("  (tecla)")
  os.pullEvent("key")
end
ajuda.avisar = avisar

local function quando(ms)
  if not ms then return "-" end
  local seg = math.floor((os.epoch("utc") - ms) / 1000)
  if seg < 60 then return seg .. "s" end
  if seg < 3600 then return math.floor(seg / 60) .. "min" end
  if seg < 86400 then return math.floor(seg / 3600) .. "h" end
  return math.floor(seg / 86400) .. "d"
end
ajuda.quando = quando

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
  local central = ajuda.central
  local C = ajuda.C
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
ajuda.exigir = console.exigir

--- Fecha o balcao na hora, sem esperar o prazo.
function console.trancar()
  sessao = nil
end
ajuda.trancar = console.trancar

--- A sessao atual, so para as telas-filha mostrarem quem esta atendendo (ex.:
-- o "*" ao lado da chave em uso, em console_chaves.lua). Nunca o PIN.
function console.sessao()
  return sessao
end
ajuda.sessao = console.sessao

-- ------------------------------------------------------------------- telas

function console.principal()
  local central = ajuda.central
  local C = ajuda.C
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

-- --------------------------------------------------------- telas-filha

-- Cada uma recebe a tabela `console` (para preencher) e `ajuda` (para
-- desenhar igual e chamar console.exigir/trancar/sessao de volta) - o mesmo
-- padrao de tranca.usar(chave, chaveiro): quem monta decide quem cada um usa.
lib("console_chaves")(console, ajuda)
lib("console_linhas")(console, ajuda)
lib("console_denuncias")(console, ajuda)
lib("console_export")(console, ajuda)
lib("console_diagnostico")(console, ajuda)
lib("console_telemetria")(console, ajuda)

-- --------------------------------------------------------------------- laco

function console.laco()
  local central = ajuda.central
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
