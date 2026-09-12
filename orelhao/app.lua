--[[ app - o computador do orelhao

  Um terminal publico para ligar para uma linha SEM ter uma - sem PIN, sem
  numero, sem sessao. So o codigo deste orelhao ("#240"), escolhido uma vez
  na instalacao, que identifica a MAQUINA, nunca quem esta usando ela.

  NADA fica gravado depois que a ligacao acaba. Ao desligar, este aparelho
  apaga a propria memoria da chamada E pede para a central apagar o que ela
  guardou daquele codigo (ver orelhao.encerrar em servidor/core/central.lua) -
  o proximo que chegar aqui nao ve rastro nenhum de quem usou antes. E o
  ponto do orelhao: anonimo de verdade, nao so "sem nome na tela".

  Por isso este arquivo nao reusa telefone/telas/conversa.lua nem
  telefone/agenda.lua: os dois presumem uma linha de verdade, com apelido,
  bloqueio, denuncia - nada disso faz sentido aqui. E de proposito uma
  interface propria, mais simples.
]]

local carregar = dofile("/carregar.lua")
local janela  = carregar("janela")
local campo   = carregar("campo")
local numero  = carregar("numero")
local fnet    = carregar("fnet")
local store   = carregar("store")
local orelhao = carregar("orelhao")

local app = {}

app.CFG = "/dados/orelhao.cfg"

local C = {
  fundo = colors.black, texto = colors.white, fraco = colors.gray,
  marca = colors.orange, entrada = colors.gray, meu = colors.lightGray,
  bom = colors.lime, ruim = colors.red,
}

-- Poll da chamada em andamento. Fixo, sem afrouxar nem apertar sozinho - a
-- mesma escolha que telefone/app.lua fez (ver historico do bug do ritmo
-- adaptativo): simples e previsivel venceu economizar pedido.
app.INTERVALO = 3

-- ------------------------------------------------------------------ codigo

--- O codigo deste orelhao, escolhido na instalacao. nil se ainda nao foi.
function app.codigo()
  local cfg = store.carregar(app.CFG, {})
  return orelhao.valido(cfg.codigo) and cfg.codigo or nil
end

function app.definirCodigo(digitos)
  local d = tostring(digitos or ""):gsub("%D", "")
  if d == "" then return false, "precisa de pelo menos um digito" end
  local codigo = "#" .. d
  store.salvar(app.CFG, { codigo = codigo })
  return true, codigo
end

-- -------------------------------------------------------------------- tela

local function moldura(j, titulo, codigo)
  j:limpar(C.fundo)
  j:barra(1, (" Orelhao %s"):format(codigo or ""), "", colors.black, C.marca)
  if titulo then j:texto(2, 3, titulo, C.texto, C.fundo) end
end

--- Campo de texto com eventos, para o aplicativo nao ficar preso num read()
-- bloqueante - a mesma ideia de loja/admin.lua e telefone/telas/entrar.lua.
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

-- --------------------------------------------------------------- instalacao

--- So roda uma vez, na primeira ligacao desta maquina. O codigo e escolhido
-- por quem instala (a rua dos blocos pode ser "#240", por exemplo) - nao
-- sorteado, porque faz parte de identificar o LUGAR, nao so a maquina.
local function configurarCodigo(j)
  while true do
    moldura(j, "Instalacao", nil)
    j:texto(2, 4, "Este orelhao ainda nao tem", C.fraco, C.fundo)
    j:texto(2, 5, "codigo. Escolha um numero", C.fraco, C.fundo)
    j:texto(2, 6, "que identifique este lugar.", C.fraco, C.fundo)

    local digitos = ler(j, 8, "codigo (so numero):")
    if digitos then
      local ok, codigoOuErro = app.definirCodigo(digitos)
      if ok then return codigoOuErro end
      avisar(j, j.h, codigoOuErro, C.ruim)
    end
  end
end

-- ------------------------------------------------------------------- discar

--- Quebra um texto em linhas de no maximo <largura>, sem partir palavra -
-- copia pequena da mesma ideia de telefone/telas/conversa.lua: um orelhao nao
-- guarda historico entre chamadas, entao nao vale a pena compartilhar o
-- modulo so por causa desta funcao.
local function quebrar(texto, largura)
  local linhas = {}
  if largura < 4 then return { texto } end
  local resto = texto
  while #resto > largura do
    local corte = nil
    for i = largura + 1, 2, -1 do
      if resto:sub(i, i) == " " then corte = i; break end
    end
    if not corte or corte < 2 then corte = largura + 1 end
    linhas[#linhas + 1] = resto:sub(1, corte - 1)
    resto = resto:sub(corte):gsub("^%s+", "")
  end
  if resto ~= "" or #linhas == 0 then linhas[#linhas + 1] = resto end
  return linhas
end

--- A chamada em andamento: transcricao, campo de escrever, DESLIGAR.
--
-- Tudo em MEMORIA, nunca em disco - e a garantia de "nada de rastro" comeca
-- aqui, antes mesmo de encerrar() apagar o lado da central.
local function chamada(j, codigo, alvo, nomeAlvo)
  local mensagens = {}
  local desde = 0

  local ok, r = fnet.orelhaoConversa(codigo, alvo)
  if ok and r.recados then
    mensagens = r.recados
    for _, m in ipairs(mensagens) do
      if m.n and m.n > desde then desde = m.n end
    end
  end

  local rascunho = campo.novo({ max = 160 })
  local sujo = true
  local temporizador = nil

  -- botao DESLIGAR no canto da barra de titulo - a mesma ideia dos badges de
  -- telefone/telas/conversa.lua: toque e desenho saem da mesma conta, para
  -- nunca discordar de onde o botao realmente esta.
  local BOTAO = 10
  local colBotao = j.w - BOTAO + 1

  local function desenhar()
    j:limpar(C.fundo)
    local titulo = nomeAlvo or numero.formatar(alvo)
    j:barra(1, " " .. janela.cortar(titulo, j.w - BOTAO), "", colors.black, C.marca)
    j:texto(colBotao, 1, janela.centralizar("DESLIGAR", BOTAO), colors.black, colors.red)

    local yEntrada = j.h
    local espaco = yEntrada - 2
    local pilha = {}
    for i = #mensagens, 1, -1 do
      local m = mensagens[i]
      local meu = m.de == codigo
      local prefixo = meu and "> " or "  "
      local linhas = quebrar(prefixo .. m.texto, j.w)
      for k = #linhas, 1, -1 do
        table.insert(pilha, 1, linhas[k])
        if #pilha >= espaco then break end
      end
      if #pilha >= espaco then break end
    end

    local inicio = yEntrada - 1 - #pilha + 1
    for i, l in ipairs(pilha) do
      j:linha(inicio + i - 1, l, C.texto, C.fundo)
    end
    if #mensagens == 0 then
      j:texto(2, 3, "Ligando...", C.fraco, C.fundo)
    end

    local visivel = campo.visivel(rascunho)
    local sobra = j.w - 2
    if #visivel > sobra then visivel = visivel:sub(#visivel - sobra + 1) end
    j:linha(yEntrada, "> " .. visivel, C.texto, C.entrada)
  end

  local function posicionarCursor()
    -- a entrada e "> " (2 celulas) + o texto - a mesma conta de
    -- telefone/telas/conversa.lua:tela.cursor()
    local visivel = campo.visivel(rascunho)
    local sobra = j.w - 2
    local col = math.min(2 + math.min(#visivel, sobra) + 1, j.w)
    j.destino.setCursorPos(j.x + col - 1, j.y + j.h - 1)
    j.destino.setCursorBlink(true)
  end

  local function desligar()
    if temporizador then os.cancelTimer(temporizador) end
    fnet.orelhaoEncerrar(codigo)
    j.destino.setCursorBlink(false)
  end

  while true do
    if sujo then
      desenhar()
      posicionarCursor()
      sujo = false
    end

    if not temporizador then temporizador = os.startTimer(app.INTERVALO) end
    local ev, p1, p2, p3 = os.pullEvent()

    if ev == "char" then
      if campo.tecla(rascunho, nil, p1) then sujo = true end

    elseif ev == "key" then
      if p1 == keys.q then
        desligar()
        return
      elseif p1 == keys.enter and not campo.vazio(rascunho) then
        local texto = campo.valor(rascunho)
        local okEnv, rEnv = fnet.orelhaoLigar(codigo, alvo, texto)
        if okEnv then
          mensagens[#mensagens + 1] = rEnv.recado
          desde = math.max(desde, rEnv.recado.n)
          campo.limpar(rascunho)
        end
        sujo = true
      elseif campo.tecla(rascunho, p1) then
        sujo = true
      end

    elseif ev == "mouse_click" then
      if p3 == 1 and p2 >= colBotao and p2 <= j.w then
        desligar()
        return
      end

    elseif ev == "timer" and p1 == temporizador then
      temporizador = nil
      local okNov, rNov = fnet.orelhaoNovidades(codigo, desde)
      if okNov and rNov.recados and #rNov.recados > 0 then
        for _, m in ipairs(rNov.recados) do
          mensagens[#mensagens + 1] = m
          if m.n > desde then desde = m.n end
        end
        sujo = true
      end
    end
  end
end

--- A tela ociosa. So desenha - quem espera o toque ou a tecla de comecar e
-- app.rodar(), a mesma separacao que loja/app.lua ja usa.
local function ociosa(j, codigo)
  moldura(j, nil, codigo)
  j:texto(2, 4, "Ligue para qualquer numero", C.texto, C.fundo)
  j:texto(2, 5, "da FALAE, sem se identificar.", C.texto, C.fundo)
  j:linha(j.h, " toque ou tecla para comecar", C.fraco, C.fundo)
end

--- O fluxo de discar: numero, mensagem, ligar. So chamada depois que
-- app.rodar() ja confirmou que o sinal de comecar foi key/mouse_click de
-- verdade, e nao um modem_message ou timer perdido chegando na tela ociosa.
local function discar(j, codigo)
  moldura(j, "Para qual numero?", codigo)
  local alvoTexto = ler(j, 5, "numero (13 digitos):", { max = 13, mascara = "numero" })
  if not alvoTexto then return end

  local alvo, erro = numero.canonico(alvoTexto)
  if not alvo then return avisar(j, j.h, erro, C.ruim) end

  moldura(j, "O que vai dizer?", codigo)
  local texto = ler(j, 5, "mensagem:", { max = 160 })
  if not texto or texto == "" then return end

  moldura(j, "Ligando...", codigo)
  local ok, r = fnet.orelhaoLigar(codigo, alvo, texto)
  if not ok then return avisar(j, j.h, janela.cortar(tostring(r), j.w - 2), C.ruim) end

  -- linha.buscar exige sessao de proposito (ver central.lua: sem isso,
  -- qualquer um varreria numeros para montar uma lista de quem existe) - um
  -- orelhao nunca tem sessao, entao nunca mostra o nome de quem atendeu, so
  -- o numero. E o preco certo: anonimato tambem quer dizer nao virar uma
  -- ferramenta de descobrir quem esta por tras de um numero.
  chamada(j, codigo, alvo, nil)
end

--- Espera a central aparecer - sem rede, o orelhao nao liga para ninguem.
local function esperarCentral(j, codigo)
  while true do
    moldura(j, "Procurando a FALAE...", codigo)
    if fnet.conectar(true) then return end
    moldura(j, "Sem sinal", codigo)
    j:texto(2, 5, "Nao encontrei a central", C.texto, C.fundo)
    j:texto(2, 6, "da FALAE daqui.", C.texto, C.fundo)
    j:linha(j.h, " qualquer tecla tenta de novo", C.fraco, C.fundo)
    os.pullEvent("key")
  end
end

function app.rodar(destino)
  destino = destino or term.current()
  local j = janela.tela(destino)

  local codigo = app.codigo()
  if not codigo then codigo = configurarCodigo(j) end

  esperarCentral(j, codigo)
  while true do
    ociosa(j, codigo)
    local ev = os.pullEvent()
    if ev == "key" or ev == "mouse_click" then
      if fnet.conectar(true) then
        discar(j, codigo)
      else
        esperarCentral(j, codigo)
      end
    end
  end
end

return app
