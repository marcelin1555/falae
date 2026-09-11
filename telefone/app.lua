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
local modal    = carregar("modal")

local app = {}

-- A partir desta largura cabem as duas colunas com folga. Um pocket tem 26.
app.LARGO = 40
-- Quanto da largura fica com a lista no arranjo de duas colunas.
app.COLUNA = 21

local C = {
  fundo   = colors.black,
  texto   = colors.white,
  fraco   = colors.gray,
  marca   = colors.orange,
  marcaFraca = colors.brown,
  selecao = colors.gray,
  entrada = colors.gray,
  meu     = colors.lightGray,
  bom     = colors.lime,
  ruim    = colors.red,
  aviso   = colors.yellow,
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
  conversas  = carregar("conversas"),
  conversa   = carregar("conversa"),
  contatos   = carregar("contatos"),
  perfil     = carregar("perfil"),
  bloqueados = carregar("bloqueados"),
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
    bloqueadosLista = {},
    escolhidoBloqueados = 1,
    topoBloqueados = 1,
    rascunho = campo.novo({ max = 160 }),
    rolagem = 0,              -- quantas linhas a conversa esta rolada para tras
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

  -- contatos, perfil e bloqueados ocupam a tela inteira nos dois formatos:
  -- sao telas de ida e volta, nao fazem par com nada
  if e.tela == "contatos" or e.tela == "perfil" or e.tela == "bloqueados" then
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
  -- guardado para o toque: o clique precisa saber em que retangulo cada tela
  -- foi desenhada, e recalcular o arranjo na hora do clique arriscaria usar um
  -- diferente do que esta na tela
  e.partes = partes

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
  e.rolagem = 0
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
  -- Mostra na hora, sem esperar o proximo ciclo: quem digitou precisa ver a
  -- propria frase entrar na conversa. Inclusive quando a central devolveu o
  -- recibo de n = 0, que e o recado que ela NAO guardou por causa de um
  -- bloqueio: a frase some da tela dela, nao da sua (ver agenda.soAqui).
  if r.recado then agenda.meu(r.recado) end
  e.rolagem = 0
  recarregar()
end

-- ------------------------------------------------------------ acoes de tela

--- Perguntas curtas que interrompem o aplicativo. Usadas pelo menu do perfil e
-- pelo salvar contato - coisas raras, em que parar tudo por dois segundos nao
-- custa nada.
--
-- TELA INTEIRA, com um campo, um botao CONFIRMAR e um "cancelar" - os tres
-- tocaveis. Antes disto so dava para confirmar com Enter e cancelar com Tab,
-- e Tab-para-cancelar e invisivel: quem esta usando o dedo nao tem como
-- adivinhar. E a mesma licao do "<" na barra da conversa - uma saida que nao
-- se anuncia e uma saida que nao existe.
--
-- @param opcoes { max=, mascara=, marcador= }  marcador e o texto fantasma
--        que aparece com o campo vazio, tipo "digite aqui seu nome..."
local function perguntar(destino, rotulo, opcoes)
  opcoes = opcoes or { max = 32 }
  local r = modal.abrir(destino, C, { { rotulo = rotulo, opcoes = opcoes } })
  return r and r[1]
end

--- Como perguntar(), mas para trocar o PIN: dois campos numa tela so, porque
-- trocar PIN e uma decisao unica, nao duas perguntas separadas em sequencia.
--
-- @return antigo, novo   ou nil se cancelou
local function perguntarPin(destino)
  local r = modal.abrir(destino, C, {
    titulo = "Trocar PIN",
    { rotulo = "PIN atual", opcoes = { max = 8, mascara = "pin" } },
    { rotulo = "PIN novo",  opcoes = { max = 8, mascara = "pin" } },
  })
  if not r then return nil end
  return r[1], r[2]
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

--- @param numero opcional - o da conversa aberta, se nao vier (o badge de
--        renomear na LISTA passa o numero da linha tocada, sem abrir nada)
local function salvarContato(destino, numero)
  numero = numero or e.aberta
  if not numero then return end
  local atual = agenda.apelido(numero) or e.nomeDe[numero] or ""
  local nome = perguntar(destino, "salvar como (vazio apaga):", { max = 16 })
  if nome == nil then return end
  agenda.salvar(numero, nome)
  recarregar()
end

local function acaoPerfil(destino, qual)
  if qual == "nome" then
    local novo = perguntar(destino, "novo nome",
      { max = 16, marcador = "digite aqui seu nome..." })
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
    local antigo, novo = perguntarPin(destino)
    if not antigo then return end
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
    -- So busca e troca de tela: quem desenha e telas.bloqueados, e quem
    -- desbloqueia e desbloquearBloqueado() logo abaixo - a mesma separacao
    -- que o resto do app usa entre "buscar da rede" e "tela".
    local ok, r = fnet.bloqueados()
    if not ok then
      e.aviso = janela.cortar(tostring(r), 40)
      return
    end
    e.bloqueadosLista = r.bloqueados
    e.escolhidoBloqueados = 1
    e.tela = "bloqueados"

  elseif qual == "sair" then
    local certeza = perguntar(destino, "sair apaga a agenda daqui. s/N:", { max = 3 })
    if certeza and certeza:lower() == "s" then
      fnet.sair()
      agenda.limpar()
      e.rodando = false
    end
  end
end

--- Denuncia a conversa aberta.
--
-- Pede confirmacao: uma tecla sem confirmacao vira denuncia por engano, e do
-- outro lado alguem entra numa fila de julgamento sem ter feito nada.
--
-- Manda so o numero. O texto quem escolhe e a central, do historico dela - o
-- aparelho nao pode dizer o que o outro escreveu.
local function denunciarAtual(destino)
  if not e.aberta then return end
  local certeza = perguntar(destino, "denunciar essa conversa? s/N:", { max = 3 })
  if not certeza or certeza:lower() ~= "s" then return end

  local ok, r = fnet.denunciar(e.aberta)
  if ok then
    e.aviso = "denunciado - a FALAE vai olhar"
  else
    e.aviso = janela.cortar(tostring(r), 40)
  end
end

--- @param numero opcional - o badge de bloquear na LISTA passa o numero da
--        linha tocada, sem abrir a conversa primeiro
local function bloquearAtual(numero)
  numero = numero or e.aberta
  if not numero then return end
  local ok = fnet.bloquear(numero)
  e.aviso = ok and "bloqueado" or "nao consegui bloquear"
end

--- Libera quem esta escolhido na tela de bloqueados.
--
-- Tira da lista NA HORA, sem esperar reabrir a tela: reabrir buscaria a lista
-- de novo da central so para mostrar uma a menos, e o toque ja disse qual foi.
local function desbloquearEscolhido()
  local b = e.bloqueadosLista[e.escolhidoBloqueados]
  if not b then return end

  local ok, r = fnet.desbloquear(b.numero)
  if not ok then
    e.aviso = janela.cortar(tostring(r), 40)
    return
  end

  table.remove(e.bloqueadosLista, e.escolhidoBloqueados)
  if e.escolhidoBloqueados > #e.bloqueadosLista then
    e.escolhidoBloqueados = math.max(1, #e.bloqueadosLista)
  end
  e.aviso = ("%s liberado"):format(b.nome or numero.formatar(b.numero))
end

-- --------------------------------------------------------------------- laco

--- Drena o "char" que sobra de uma tecla de letra premida de verdade.
--
-- O CC dispara DOIS eventos por uma tecla imprimivel: "key" e, logo depois,
-- "char". Um atalho de letra unica (D para denunciar, S para salvar
-- contato, N para nova conversa) que abre um dialogo de dentro do MESMO
-- despacho sincrono - e o dialogo faz um os.pullEvent() sem filtro como
-- primeira coisa - recebe esse "char" que sobrou da propria tecla que
-- acabou de abri-lo, prefixando a letra do atalho no que a pessoa digitar a
-- seguir. "D" + "s" + Enter virava o campo "ds", a comparacao com "s" nunca
-- batia, e a denuncia nunca saia - sem erro, sem travar, so nao funcionava.
--
-- So descarta o "char" se ele for EXATAMENTE o esperado: qualquer outra
-- coisa (um toque, um recado que chegou, outra tecla digitada rapido demais)
-- volta pra fila via os.queueEvent, para nao se perder. Chamar isto quando a
-- acao veio de TOQUE (sem tecla nenhuma por tras) tambem e seguro: sem
-- "char" pendente, o timer(0) vence a corrida e a funcao nao faz nada, ao
-- preco de uma volta de evento a mais.
local function descartarCharPendente(charEsperado)
  local temporizador = os.startTimer(0)
  local ev, p1, p2, p3 = os.pullEvent()
  os.cancelTimer(temporizador)
  if ev == "char" and p1 == charEsperado then return end
  if not (ev == "timer" and p1 == temporizador) then
    os.queueEvent(ev, p1, p2, p3)
  end
end

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
  elseif acao == "focar" then
    if largo(destino) then e.foco = "conversa" end
    e.sujo = true
  elseif acao == "apagar" then
    agir(destino, telas.contatos.apagar(e))
  elseif acao == "nova" then
    -- a tecla N tambem abre um dialogo (perguntar, mascarado de numero) - o
    -- mascaramento ja rejeitava a letra "n" sozinho (nao e digito), entao
    -- isto nunca teve sintoma visivel, mas drenar do mesmo jeito fecha a
    -- mesma classe de furo em vez de depender de um acaso da mascara
    descartarCharPendente("n")
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
  elseif acao == "desbloquear" then
    desbloquearEscolhido()
    e.sujo = true
  elseif acao:sub(1, 9) == "renomear:" then
    -- o badge "E" da lista de conversas: renomeia sem abrir a conversa
    salvarContato(destino, acao:sub(10))
    e.sujo = true
  elseif acao:sub(1, 9) == "bloquear:" then
    -- o badge "X" da lista de conversas: mesma logica
    bloquearAtual(acao:sub(10))
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

    -- p2 e p3 sao a coluna e a linha do clique, quando o evento e de mouse
    local ev, p1, p2, p3 = os.pullEvent()

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
        -- salvarContato abre um dialogo (perguntar) - drena o "char" que
        -- sobra desta mesma tecla antes de abrir, ou ele vira o primeiro
        -- caractere do nome digitado
        descartarCharPendente("s")
        salvarContato(destino)
        e.sujo = true
      elseif p1 == keys.b and focada(destino) == "conversa" and e.aberta
             and campo.vazio(e.rascunho) then
        -- bloquearAtual nao abre dialogo nenhum - nao ha "char" para drenar
        bloquearAtual()
        e.sujo = true
      elseif p1 == keys.d and focada(destino) == "conversa" and e.aberta
             and campo.vazio(e.rascunho) then
        -- mesmo motivo do "s": denunciarAtual abre um dialogo
        descartarCharPendente("d")
        denunciarAtual(destino)
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
        -- recado novo desce a conversa de volta para o fim: quem estava
        -- olhando o passado quer ver o que acabou de chegar
        e.rolagem = 0
        recarregar()
      end
      e.sujo = true

    elseif ev == "mouse_click" then
      -- Confirmado no jar: o pocket recebe mouse_click como qualquer
      -- computador. p2 e p3 sao coluna e linha, em celulas do terminal.
      -- Cancela o temporizador, como o teclado faz. Sem isto o ritmo.sinal
      -- abaixo nao valia de nada: o timer pendente continuava com o intervalo
      -- antigo, e um aparelho que estava no degrau "dormindo" so ia perguntar
      -- a central trinta segundos depois do toque. Num pocket navegado pelo
      -- dedo, que e o caso, o telefone nunca acordava.
      if temporizador then os.cancelTimer(temporizador); temporizador = nil end
      ritmo.sinal(r, os.epoch("utc"))
      if e.aviso then
        e.aviso = nil
        e.sujo = true
      else
        local _, cx, cy = ev, p2, p3
        for _, parte in ipairs(e.partes or {}) do
          local lx, ly = parte.j:ondeCaiu(cx, cy)
          if lx then
            -- tocar do outro lado tambem troca o foco: e o que a pessoa espera
            -- ao encostar na coluna que nao estava ativa
            if largo(destino) and e.tela == "conversas" then
              e.foco = (parte.nome == "conversa") and "conversa" or "lista"
            end
            agir(destino, telas[parte.nome].clique(e, lx, ly, parte.j))
            e.sujo = true
            break
          end
        end
      end

    elseif ev == "mouse_scroll" then
      -- p1 e a direcao (1 para baixo), p2/p3 a posicao
      if temporizador then os.cancelTimer(temporizador); temporizador = nil end
      ritmo.sinal(r, os.epoch("utc"))
      local alvo = telas[focada(destino)]
      if alvo.rolar then
        agir(destino, alvo.rolar(e, p1))
      end

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
