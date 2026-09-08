--[[ app - o telefone

  Junta as pecas: monta o arranjo das janelas, decide quem tem o teclado,
  pergunta a central no ritmo certo e redesenha so o que mudou.

  O ARRANJO e a unica parte do aplicativo que sabe o tamanho da tela:

    largura < LARGO    uma janela ocupando tudo, uma tela por vez
    largura >= LARGO   lista a esquerda, conversa a direita, as duas juntas

  As telas nao sabem em qual dos dois estao. Elas recebem uma janela, desenham
  de 1 ate a largura dela, e pronto. Por isso nao existe uma versao de pocket e
  outra de computador de nada: existe uma implementacao e dois arranjos.

  O LACO nao dorme parado. Ele espera evento com um timer, e o timer vale o
  que o ritmo mandar - de 2s numa conversa viva a 30s num aparelho esquecido no
  bolso. Um so timer por volta, sempre recriado: acumular timer e como se enche
  a fila de eventos de um computador do CC sem perceber.
]]

local carregar = dofile("/carregar.lua")
local janela   = carregar("janela")
local campo    = carregar("campo")
local numero   = carregar("numero")
local ritmo    = carregar("ritmo")
local fnet     = carregar("fnet")
local agenda   = carregar("agenda")

local app = {}

-- A partir desta largura cabem as duas colunas com folga. Um pocket tem 26.
app.LARGO = 40
-- Quanto da largura fica com a lista no arranjo de duas colunas.
app.COLUNA = 21

local C = {
  fundo   = colors.black,
  texto   = colors.white,
  fraco   = colors.gray,
  marca   = colors.yellow,
  marcaFraca = colors.brown,
  selecao = colors.gray,
  entrada = colors.gray,
  meu     = colors.lightGray,
  bom     = colors.lime,
  ruim    = colors.red,
  aviso   = colors.orange,
}
app.CORES = C

--- Sem cor, a marca amarela sobre preto vira dois brancos iguais. Num pocket
-- comum (nao Advanced) o telefone precisa continuar legivel, e legivel aqui
-- quer dizer: contraste de verdade, nem que seja so preto e branco.
local function semCor()
  C.marca = colors.white
  C.marcaFraca = colors.white
  C.selecao = colors.white
  C.entrada = colors.black
  C.meu = colors.white
  C.fraco = colors.white
  C.bom, C.ruim, C.aviso = colors.white, colors.white, colors.white
end

local telas = {
  conversas = carregar("conversas"),
  conversa  = carregar("conversa"),
  contatos  = carregar("contatos"),
  perfil    = carregar("perfil"),
}

-- ------------------------------------------------------------------ estado

local e

local function novoEstado(sessao)
  return {
    eu = { numero = sessao.numero, nome = sessao.nome },
    tela = "conversas",       -- conversas | contatos | perfil
    foco = "lista",           -- lista | conversa   (so vale no arranjo largo)
    aberta = nil,
    conversas = {},
    nomeDe = {},              -- [canonico] = nome publico, o que a central contou
    escolhido = 1,
    topo = 1,
    escolhidoContato = 1,
    topoContatos = 1,
    escolhidoPerfil = 1,
    rascunho = campo.novo({ max = 160 }),
    naoLidos = 0,
    agora = os.epoch("utc"),
    sinal = "?",
    aviso = nil,
    sujo = true,
    rodando = true,
  }
end

-- ----------------------------------------------------------------- arranjo

--- Quais telas aparecem agora, e em que retangulo cada uma desenha.
-- @return lista de { nome=, j=, focada= }
local function arranjo(destino)
  local w, h = destino.getSize()
  local tudo = janela.nova(destino, 1, 1, w, h)

  -- contatos e perfil ocupam a tela inteira nos dois formatos: sao telas de
  -- ida e volta, nao fazem par com nada
  if e.tela == "contatos" or e.tela == "perfil" then
    return { { nome = e.tela, j = tudo, focada = true } }
  end

  if w < app.LARGO then
    -- pocket: uma de cada vez
    if e.aberta then
      return { { nome = "conversa", j = tudo, focada = true } }
    end
    return { { nome = "conversas", j = tudo, focada = true } }
  end

  -- computador: as duas juntas
  local largura = math.min(app.COLUNA, math.floor(w / 2))
  return {
    { nome = "conversas", j = janela.nova(destino, 1, 1, largura, h),
      focada = e.foco == "lista" },
    { nome = "conversa",  j = janela.nova(destino, largura + 2, 1, w - largura - 1, h),
      focada = e.foco == "conversa" },
  }
end

local function largo(destino)
  local w = destino.getSize()
  return w >= app.LARGO
end

-- ----------------------------------------------------------------- desenho

local function desenhar(destino)
  local partes = arranjo(destino)

  for _, p in ipairs(partes) do
    telas[p.nome].desenhar(p.j, e, C, p.focada)
  end

  -- a regua que separa as colunas, so no arranjo largo
  if #partes == 2 then
    local w, h = destino.getSize()
    local x = partes[1].j.w + 1
    for y = 1, h do
      destino.setCursorPos(x, y)
      destino.setBackgroundColour(C.fundo)
      destino.setTextColour(C.fraco)
      destino.write("|")
    end
  end

  -- o aviso passa por cima de tudo: e o unico jeito de dizer "sem sinal" sem
  -- roubar uma linha permanente de uma tela de 20 linhas
  if e.aviso then
    local w, h = destino.getSize()
    destino.setCursorPos(1, h)
    destino.setBackgroundColour(C.aviso)
    destino.setTextColour(colors.black)
    destino.write(janela.encher(" " .. e.aviso, w))
  end

  -- o cursor fica onde se digita, e so quando ha onde digitar
  local escrevendo = nil
  for _, p in ipairs(partes) do
    if p.nome == "conversa" and p.focada and e.aberta then escrevendo = p end
  end
  if escrevendo and not e.aviso then
    local cx, cy = telas.conversa.cursor(escrevendo.j, e)
    destino.setCursorPos(escrevendo.j.x + cx - 1, escrevendo.j.y + cy - 1)
    destino.setTextColour(C.texto)
    destino.setCursorBlink(true)
  else
    destino.setCursorBlink(false)
  end

  e.sujo = false
end

-- -------------------------------------------------------------------- rede

--- Recolhe o que a central tem para este aparelho.
--
-- Repete enquanto a central disser que sobrou mais: quem passou dias com o
-- pocket desligado tem mais recado do que cabe numa resposta so, e parar na
-- primeira deixaria o resto para o proximo ciclo - que pode ser daqui a trinta
-- segundos.
local function buscar()
  local novos = 0
  for _ = 1, 10 do
    local ok, r = fnet.novidades(agenda.desde(), 50)
    if not ok then
      e.sinal = "sem sinal"
      return novos, false
    end

    e.sinal = "ok"
    if r.nada then
      if r.ultimo then agenda.receber({}, r.ultimo) end
      break
    end

    novos = novos + agenda.receber(r.recados, r.ultimo)
    if not r.mais then break end
  end
  return novos, true
end

--- Refaz a lista de conversas a partir do que esta no disco do aparelho.
local function recarregar()
  e.conversas = agenda.conversas(e.eu.numero)
  e.naoLidos = agenda.naoLidos(e.eu.numero)
  for _, c in ipairs(e.conversas) do
    c.nome = e.nomeDe[c.numero]
  end
  if e.escolhido > #e.conversas then e.escolhido = math.max(1, #e.conversas) end
  e.sujo = true
end

--- Pergunta a central o nome publico de um numero, uma vez so por numero.
local function nomeDe(canonico)
  if e.nomeDe[canonico] ~= nil then return e.nomeDe[canonico] end
  local ok, r = fnet.buscar(canonico)
  if ok and r.existe then
    e.nomeDe[canonico] = r.linha.nome
  else
    e.nomeDe[canonico] = false
  end
  return e.nomeDe[canonico]
end

local function abrir(canonico)
  e.aberta = canonico
  e.foco = "conversa"
  campo.limpar(e.rascunho)
  nomeDe(canonico)
  agenda.marcarLido(e.eu.numero, canonico)
  recarregar()
end

local function enviar()
  local texto = campo.valor(e.rascunho)
  if texto == "" or not e.aberta then return end

  local ok, r = fnet.enviar(e.aberta, texto)
  if not ok then
    e.aviso = janela.cortar(tostring(r), 40)
    e.sujo = true
    return
  end

  campo.limpar(e.rascunho)
  -- mostra na hora, sem esperar o proximo ciclo: quem digitou precisa ver a
  -- propria frase entrar na conversa
  if r.recado and r.recado.n and r.recado.n > 0 then
    agenda.meu(r.recado)
  end
  recarregar()
end

-- ------------------------------------------------------------ acoes de tela

--- Perguntas curtas que interrompem o aplicativo. Usadas pelo menu do perfil e
-- pelo salvar contato - coisas raras, em que parar tudo por dois segundos nao
-- custa nada.
local function perguntar(destino, rotulo, opcoes)
  local w, h = destino.getSize()
  local j = janela.nova(destino, 1, 1, w, h)
  local c = campo.novo(opcoes or { max = 32 })

  while true do
    j:linha(h - 1, " " .. rotulo, C.marca, C.fundo)
    j:linha(h, " " .. janela.encher(campo.visivel(c), w - 2), C.texto, C.entrada)
    destino.setCursorPos(2 + campo.cursorVisivel(c), h)
    destino.setCursorBlink(true)

    local ev, p1 = os.pullEvent()
    if ev == "char" then
      campo.tecla(c, nil, p1)
    elseif ev == "key" then
      if p1 == keys.enter then
        destino.setCursorBlink(false)
        return campo.valor(c)
      elseif p1 == keys.tab then
        destino.setCursorBlink(false)
        return nil
      else
        campo.tecla(c, p1)
      end
    end
  end
end

local function novaConversa(destino)
  local texto = perguntar(destino, "numero (13 digitos):", { max = 13, mascara = "numero" })
  if not texto then return end

  local canonico = numero.canonico(texto)
  if not canonico then
    e.aviso = "numero incompleto"
    return
  end
  if canonico == e.eu.numero then
    e.aviso = "esse numero e o seu"
    return
  end

  local ok, r = fnet.buscar(canonico)
  if not ok then
    e.aviso = janela.cortar(tostring(r), 40)
    return
  end
  if not r.existe then
    e.aviso = "esse numero nao existe"
    return
  end

  e.nomeDe[canonico] = r.linha.nome
  abrir(canonico)
end

local function salvarContato(destino)
  if not e.aberta then return end
  local atual = agenda.apelido(e.aberta) or e.nomeDe[e.aberta] or ""
  local nome = perguntar(destino, "salvar como (vazio apaga):", { max = 16 })
  if nome == nil then return end
  agenda.salvar(e.aberta, nome)
  recarregar()
end

local function acaoPerfil(destino, qual)
  if qual == "nome" then
    local novo = perguntar(destino, "novo nome:", { max = 16 })
    if not novo or novo == "" then return end
    local ok, r = fnet.trocarNome(novo)
    if ok then
      e.eu.nome = r.linha.nome
      local s = fnet.sessao()
      if s then s.nome = e.eu.nome; fnet.guardarSessao(s) end
      e.aviso = "nome trocado"
    else
      e.aviso = janela.cortar(tostring(r), 40)
    end

  elseif qual == "pin" then
    local antigo = perguntar(destino, "PIN atual:", { max = 8, mascara = "pin" })
    if not antigo then return end
    local novo = perguntar(destino, "PIN novo:", { max = 8, mascara = "pin" })
    if not novo then return end
    local ok, r = fnet.trocarPin(antigo, novo)
    if ok then
      -- trocar o PIN derruba TODAS as sessoes, inclusive esta: e o que faz a
      -- troca valer alguma coisa. Este aparelho tem que entrar de novo.
      fnet.esquecerSessao()
      e.aviso = "PIN trocado - entre de novo"
      e.rodando = false
    else
      e.aviso = janela.cortar(tostring(r), 40)
    end

  elseif qual == "bloq" then
    local ok, r = fnet.bloqueados()
    if not ok then
      e.aviso = janela.cortar(tostring(r), 40)
      return
    end
    if #r.bloqueados == 0 then
      e.aviso = "ninguem bloqueado"
      return
    end
    local alvo = perguntar(destino,
      ("%d bloqueado(s). numero p/ liberar:"):format(#r.bloqueados),
      { max = 13, mascara = "numero" })
    if not alvo then return end
    local canonico = numero.canonico(alvo)
    if canonico then
      fnet.desbloquear(canonico)
      e.aviso = "liberado"
    end

  elseif qual == "sair" then
    local certeza = perguntar(destino, "sair apaga a agenda daqui. s/N:", { max = 3 })
    if certeza and certeza:lower() == "s" then
      fnet.sair()
      agenda.limpar()
      e.rodando = false
    end
  end
end

local function bloquearAtual()
  if not e.aberta then return end
  local ok = fnet.bloquear(e.aberta)
  e.aviso = ok and "bloqueado" or "nao consegui bloquear"
end

-- --------------------------------------------------------------------- laco

--- Trata o que a tela devolveu.
local function agir(destino, acao)
  if acao == nil then return end

  if acao == "redesenhar" or acao == "digitou" then
    e.sujo = true
  elseif acao == "abrir" then
    abrir(e.aberta)
  elseif acao == "enviar" then
    enviar()
    e.sujo = true
  elseif acao == "fechar" then
    if largo(destino) then
      e.foco = "lista"
    else
      e.aberta = nil
    end
    e.sujo = true
  elseif acao == "lista" then
    if largo(destino) then e.foco = "lista" end
    e.sujo = true
  elseif acao == "nova" then
    novaConversa(destino)
    e.sujo = true
  elseif acao == "contatos" then
    e.tela = "contatos"
    e.sujo = true
  elseif acao == "perfil" then
    e.tela = "perfil"
    e.sujo = true
  elseif acao == "voltar" then
    e.tela = "conversas"
    e.sujo = true
  elseif acao:sub(1, 7) == "perfil:" then
    acaoPerfil(destino, acao:sub(8))
    e.sujo = true
  end
end

--- Quem recebe a tecla agora.
local function focada(destino)
  if e.tela ~= "conversas" then return e.tela end
  if largo(destino) then
    return (e.foco == "conversa" and e.aberta) and "conversa" or "conversas"
  end
  return e.aberta and "conversa" or "conversas"
end

function app.rodar(destino)
  destino = destino or term.current()

  local sessao = fnet.sessao()
  if not sessao then return false, "sem sessao" end

  if destino.isColour and not destino.isColour() then semCor() end

  agenda.carregar()
  e = novoEstado(sessao)
  app.estado = e

  local r = ritmo.novo(os.epoch("utc"))

  -- primeira carga: o que ja esta no disco aparece antes de qualquer rede
  recarregar()
  desenhar(destino)

  buscar()
  recarregar()

  local temporizador = nil

  while e.rodando do
    e.agora = os.epoch("utc")
    local conversaAberta = e.aberta ~= nil and e.tela == "conversas"
    local intervalo = ritmo.intervalo(r, e.agora, conversaAberta)
    e.intervalo = intervalo
    e.degrau = ritmo.degrau(r, e.agora, conversaAberta)

    if e.sujo then desenhar(destino) end

    -- UM timer, vivo entre as voltas.
    --
    -- Criar um timer novo a cada volta parece inofensivo e nao e: os.pullEvent
    -- devolve TODO evento, e o aparelho recebe modem_message toda vez que a
    -- central responde qualquer coisa. Ao cair num evento que o laco nao trata,
    -- a volta seguinte criava outro timer sem cancelar o anterior - e dai em
    -- diante o timer que chegava era sempre o da volta passada, nunca igual ao
    -- da volta atual. A condicao nunca mais dava certo e o telefone parava de
    -- buscar recado para sempre, sem erro nenhum na tela.
    if not temporizador then temporizador = os.startTimer(intervalo) end

    local ev, p1 = os.pullEvent()

    if ev == "key" then
      if temporizador then os.cancelTimer(temporizador); temporizador = nil end
      -- Qualquer tecla e sinal de vida: o telefone volta ao degrau rapido.
      -- Quem esta digitando espera resposta em segundos, nao em meio minuto.
      ritmo.sinal(r, os.epoch("utc"))

      if e.aviso then
        e.aviso = nil
        e.sujo = true
      elseif p1 == keys.tab and largo(destino) and e.tela == "conversas" then
        e.foco = (e.foco == "lista") and "conversa" or "lista"
        e.sujo = true
      elseif p1 == keys.s and focada(destino) == "conversa" and e.aberta
             and campo.vazio(e.rascunho) then
        salvarContato(destino)
        e.sujo = true
      elseif p1 == keys.b and focada(destino) == "conversa" and e.aberta
             and campo.vazio(e.rascunho) then
        bloquearAtual()
        e.sujo = true
      else
        agir(destino, telas[focada(destino)].tecla(e, p1, nil))
      end

    elseif ev == "char" then
      if temporizador then os.cancelTimer(temporizador); temporizador = nil end
      ritmo.sinal(r, os.epoch("utc"))
      if e.aviso then
        e.aviso = nil
        e.sujo = true
      else
        agir(destino, telas[focada(destino)].tecla(e, nil, p1))
      end

    elseif ev == "timer" and p1 == temporizador then
      temporizador = nil
      local novos = buscar()
      if novos > 0 then
        -- recado que chegou tambem e sinal de vida: a conversa acabou de
        -- ficar viva, e a proxima pergunta deve ser rapida
        ritmo.sinal(r, os.epoch("utc"))
        if e.aberta then agenda.marcarLido(e.eu.numero, e.aberta) end
        recarregar()
      end
      e.sujo = true

    elseif ev == "term_resize" then
      -- o pocket entrando ou saindo de um lectern muda o tamanho da tela
      if temporizador then os.cancelTimer(temporizador); temporizador = nil end
      e.sujo = true
    end
    -- Qualquer outro evento (modem_message, mouse, peripheral) cai aqui e nao
    -- encosta no temporizador: ele continua valendo para a proxima volta.
  end

  destino.setCursorBlink(false)
  destino.setBackgroundColour(colors.black)
  destino.setTextColour(colors.white)
  destino.clear()
  destino.setCursorPos(1, 1)
  return true
end

return app
