--[[ app - o computador da loja

  Um terminal de balcao, para quem nao tem pocket. Reusa exatamente o mesmo
  fluxo de "tirar linha nova" que telefone/telas/entrar.lua ja tem, com duas
  diferencas:

    COBRA antes de mandar o pedido. Sem integracao de economia automatica no
    CC - a confirmacao e social, como um caixa de verdade apertando "recebido"
    depois de contar o dinheiro na mao. Nao ha como isto ser a prova de
    fraude; a FALAE ja e aberta a qualquer jogador de proposito, e quem
    quisesse trapacear a loja tambem poderia so tirar a linha de graca pelo
    proprio telefone - a cobranca aqui e sobre o NEGOCIO, nao sobre travar
    quem ja pode entrar de qualquer jeito.

    NAO GUARDA SESSAO NENHUMA. E uma maquina publica, usada por gente
    diferente o dia inteiro - guardar a ultima sessao criada aqui deixaria o
    numero e o PIN de um cliente acessiveis ao proximo que chegasse. Por isso
    o app chama fnet.pedir() direto, e nao fnet.criarLinha() (que persiste em
    disco): o numero aparece na tela para a PESSOA anotar, e o aparelho
    esquece assim que volta para a tela ociosa.

  A tela de administracao (preco, vendas, chaves) mora em admin.lua, atras da
  chave por disquete - ela sim precisa saber quem esta mexendo. A loja em si
  nao: ela abre para qualquer cliente, o dia inteiro, sem pedir nada de
  ninguem.
]]

local carregar = dofile("/carregar.lua")
local janela = carregar("janela")
local campo  = carregar("campo")
local numero = carregar("numero")
local fnet   = carregar("fnet")
local store  = carregar("store")
local admin  = carregar("admin")

-- admin.lua nao importa este arquivo de volta - as funcoes de preco/vendas
-- que ele precisa vao por PARAMETRO em admin.tela(), nao por
-- carregar("app"). Um require circular entre os dois (cada um esperando o
-- outro terminar de carregar) e exatamente o defeito que /carregar.lua existe
-- para não esconder: ele devolveria uma copia vazia do primeiro modulo a
-- pedir o outro, do mesmo jeito que aconteceu com a agenda do telefone antes
-- de carregar.lua existir.

local app = {}

app.PRECO_CFG   = "/dados/preco.cfg"
app.VENDAS_CFG  = "/dados/vendas.cfg"
app.PRECO_PADRAO = 1

-- Quanto tempo o numero fica na tela depois de uma venda, antes de a maquina
-- voltar sozinha para a tela ociosa. Tempo o bastante para anotar treze
-- digitos, curto o bastante para o proximo cliente nao esperar disso.
app.RESULTADO_SEGUNDOS = 25

local C = {
  fundo = colors.black, texto = colors.white, fraco = colors.gray,
  marca = colors.yellow, entrada = colors.gray,
  bom = colors.lime, ruim = colors.red,
}

-- ------------------------------------------------------------------- preco

function app.preco()
  local cfg = store.carregar(app.PRECO_CFG, { valor = app.PRECO_PADRAO })
  return tonumber(cfg.valor) or app.PRECO_PADRAO
end

function app.definirPreco(novo)
  novo = tonumber(novo)
  if not novo or novo < 0 then return false, "preco invalido" end
  store.salvar(app.PRECO_CFG, { valor = novo })
  return true
end

-- ------------------------------------------------------------------ vendas

local function vendasCruas()
  local v = store.carregar(app.VENDAS_CFG, { total = 0 })
  if type(v.total) ~= "number" then v.total = 0 end
  return v
end

function app.vendas()
  return vendasCruas().total
end

local function registrarVenda()
  local v = vendasCruas()
  v.total = v.total + 1
  store.salvar(app.VENDAS_CFG, v)
end

-- -------------------------------------------------------------------- tela

local function moldura(j, titulo)
  j:limpar(C.fundo)
  j:barra(1, " FALAE - loja", "", colors.black, C.marca)
  if titulo then j:texto(2, 3, titulo, C.texto, C.fundo) end
end

--- Igual ao ler() de telefone/telas/entrar.lua: campo de texto com eventos,
-- para o aplicativo nao ficar preso num read() bloqueante.
local function ler(j, y, rotulo, opcoes)
  local c = campo.novo(opcoes)
  while true do
    j:texto(2, y, rotulo, C.fraco, C.fundo)
    local visivel = campo.visivel(c)
    j:linha(y + 1, " " .. janela.encher(visivel, j.w - 2), C.texto, C.entrada)

    j.destino.setCursorPos(j.x + 1 + campo.cursorVisivel(c), j.y + y)
    j.destino.setCursorBlink(true)

    local ev, p1 = os.pullEvent()
    if ev == "char" then
      campo.tecla(c, nil, p1)
    elseif ev == "key" then
      if p1 == keys.enter then
        j.destino.setCursorBlink(false)
        return campo.valor(c)
      elseif p1 == keys.tab then
        j.destino.setCursorBlink(false)
        return nil
      else
        campo.tecla(c, p1)
      end
    end
  end
end

local function avisar(j, y, texto, cor)
  j:linha(y, " " .. janela.cortar(texto, j.w - 2) .. "  (tecla)", cor or C.ruim, C.fundo)
  os.pullEvent("key")
end

--- Espera uma tecla OU um toque em qualquer lugar da tela - a tela ociosa e
-- publica, e "toque em qualquer canto para comecar" e o convite mais generoso
-- que da para fazer para quem nunca usou a maquina.
local function esperarComeco()
  while true do
    local ev = os.pullEvent()
    if ev == "key" or ev == "mouse_click" then return end
  end
end

-- ------------------------------------------------------------------ compra

--- Confirma a cobranca. O atendente que esta fisicamente ali confirma, como
-- um caixa apertando "recebido" - nao existe integracao de economia
-- automatica dentro do CC para conferir isto sozinho.
local function confirmarCobranca(j)
  local preco = app.preco()
  moldura(j, "Pagamento")
  j:texto(2, 5, ("Preco: %s"):format(preco), C.marca, C.fundo)
  j:texto(2, 7, "Pague ao atendente.", C.texto, C.fundo)
  j:linha(j.h, " S confirma recebido   N cancela", C.fraco, C.fundo)

  while true do
    local ev, p1, p2, p3 = os.pullEvent()
    if ev == "key" then
      if p1 == keys.s then return true end
      if p1 == keys.n or p1 == keys.q then return false end
    elseif ev == "mouse_click" then
      -- toque na metade de cima confirma, na de baixo cancela - generoso o
      -- bastante para nao exigir mirar num botao miudo
      local _, cy = j:ondeCaiu(p2, p3)
      if cy then return cy <= math.floor(j.h / 2) end
    end
  end
end

--- O fluxo inteiro: nome, PIN, cobranca, pedido, resultado.
local function comprar(j)
  moldura(j, "Sua linha nova")
  j:texto(2, 4, "Como voce quer aparecer", C.fraco, C.fundo)
  j:texto(2, 5, "para os outros?", C.fraco, C.fundo)
  local nome = ler(j, 7, "nome:", { max = 16 })
  if nome == nil or nome == "" then return end

  moldura(j, "Sua linha nova")
  j:texto(2, 4, "Escolha um PIN de 4 a 8", C.fraco, C.fundo)
  j:texto(2, 5, "numeros. Anote: nem a", C.fraco, C.fundo)
  j:texto(2, 6, "FALAE sabe qual e o seu.", C.fraco, C.fundo)
  local pin = ler(j, 8, "PIN:", { max = 8, mascara = "pin" })
  if pin == nil then return end
  local repetido = ler(j, 11, "de novo:", { max = 8, mascara = "pin" })
  if repetido == nil then return end
  if pin ~= repetido then
    return avisar(j, j.h, "os dois PINs nao batem")
  end

  if not confirmarCobranca(j) then return end

  moldura(j, "Tirando sua linha...")

  -- fnet.pedir(), NAO fnet.criarLinha(): a segunda gravaria a sessao em
  -- disco, e este e um terminal publico. O token que a central devolve e
  -- descartado aqui mesmo - ninguem nesta maquina precisa dele.
  local ok, r = fnet.pedir("linha", "criar", { nome = nome, pin = pin }, true)
  if not ok then
    return avisar(j, j.h, janela.cortar(tostring(r), j.w - 2))
  end

  registrarVenda()

  moldura(j, "Pronto!")
  j:texto(2, 5, "Seu numero e:", C.fraco, C.fundo)
  j:texto(2, 7, numero.formatar(r.linha.numero), C.marca, C.fundo)
  j:texto(2, 9, "Anote agora. E por ele que", C.fraco, C.fundo)
  j:texto(2, 10, "as pessoas te acham.", C.fraco, C.fundo)
  j:linha(j.h, " qualquer tecla volta antes", C.fraco, C.fundo)

  -- Some sozinho depois de um tempo - a tela nao pode ficar mostrando o
  -- numero e o nome do ultimo cliente para sempre, esperando alguem apertar
  -- uma tecla que talvez ninguem aperte.
  local temporizador = os.startTimer(app.RESULTADO_SEGUNDOS)
  while true do
    local ev, p1 = os.pullEvent()
    if ev == "key" or ev == "mouse_click" then
      os.cancelTimer(temporizador)
      return
    elseif ev == "timer" and p1 == temporizador then
      return
    end
  end
end

-- -------------------------------------------------------------------- ida

local function ociosa(j)
  moldura(j, nil)
  j:texto(2, 4, "Tire sua linha aqui.", C.texto, C.fundo)
  j:texto(2, 6, ("Preco: %s"):format(app.preco()), C.marca, C.fundo)
  j:texto(2, 8, "Nome e PIN sao so seus -", C.fraco, C.fundo)
  j:texto(2, 9, "nem a FALAE guarda o PIN.", C.fraco, C.fundo)
  j:linha(j.h, " toque para comecar   A administrar", C.fraco, C.fundo)
end

--- Espera a central aparecer, como entrar.rodar() no telefone. Sem rede, a
-- loja nao pode vender nada - melhor dizer isso na cara do que deixar a
-- pessoa digitar nome e PIN so para descobrir no fim.
local function esperarCentral(j)
  while true do
    moldura(j, nil)
    j:texto(2, 4, "Procurando a FALAE...", C.fraco, C.fundo)
    if fnet.conectar(true) then return true end

    moldura(j, "Sem sinal")
    j:texto(2, 5, "Nao encontrei a central", C.texto, C.fundo)
    j:texto(2, 6, "da FALAE daqui.", C.texto, C.fundo)
    j:texto(2, 8, "Confira o Ender Modem", C.fraco, C.fundo)
    j:texto(2, 9, "encostado neste computador.", C.fraco, C.fundo)
    j:linha(j.h, " qualquer tecla tenta de novo", C.fraco, C.fundo)
    os.pullEvent("key")
  end
end

function app.rodar(destino)
  destino = destino or term.current()
  local j = janela.tela(destino)

  while true do
    ociosa(j)
    local ev, p1 = os.pullEvent()

    if ev == "key" and p1 == keys.a then
      admin.tela(j, C, {
        preco = app.preco, definirPreco = app.definirPreco, vendas = app.vendas,
      })
    elseif ev == "key" or ev == "mouse_click" then
      if esperarCentral(j) then comprar(j) end
    end
  end
end

return app
