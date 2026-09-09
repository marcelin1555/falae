--[[ tranca - a fechadura, do lado de fora

  Junta o disquete, o PIN e o chaveiro numa coisa so, com tela. E o que a
  central chama no boot e no balcao, e e o que a loja vai chamar numa linha
  quando existir:

    local tranca = lib("tranca")
    tranca.usar(lib("chave"), lib("chaveiro"))
    if not tranca.abrir("loja") then return end

  O DRIVE ENCOSTADO GANHA DO DRIVE DA REDE. peripheral.find acha os dois, e um
  drive ligado por modem com fio pode estar em qualquer lugar do mapa - inclusive
  na casa de outra pessoa. A chave e uma coisa fisica; ela tem que estar
  fisicamente ali. Procurar pelos lados primeiro e o que garante isso.
]]

local tranca = {}

tranca.LADOS = { "top", "bottom", "left", "right", "front", "back" }

-- Quanto tempo o balcao fica destrancado depois de um PIN certo. Curto: o
-- risco nao e alguem arrombar, e alguem ir almocar com o console aberto.
tranca.SESSAO = 10 * 60 * 1000

local chave, chaveiro

--- Diz quais modulos usar. Cada maquina carrega os seus do jeito dela.
function tranca.usar(m1, m2)
  chave, chaveiro = m1, m2
end

-- ------------------------------------------------------------------ drive

--- Acha um drive, preferindo os encostados na maquina.
-- @return o periferico, o nome   ou nil
function tranca.drive()
  for _, lado in ipairs(tranca.LADOS) do
    if peripheral.getType(lado) == "drive" then
      return peripheral.wrap(lado), lado
    end
  end
  -- nenhum encostado: aceita um da rede, mas so porque nao ter drive nenhum e
  -- pior que ter um longe - e o id do disquete continua sendo o que manda
  local nome = nil
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "drive" then nome = n; break end
  end
  if nome then return peripheral.wrap(nome), nome end
  return nil
end

--- O id do disquete que esta no drive agora, ou nil.
--
-- SEMPRE daqui, nunca do arquivo. O arquivo pode ter sido copiado; o id, nao.
function tranca.disco()
  local d = tranca.drive()
  if not d then return nil, "sem drive - encoste um Disk Drive na maquina" end
  local ok, presente = pcall(d.isDiskPresent)
  if not ok or not presente then return nil, "sem disquete no drive" end
  local ok2, id = pcall(d.getDiskID)
  if not ok2 or not id then return nil, "esse disquete nao tem dados" end
  return id, nil, d
end

local function caminhoDoSelo(d)
  local ok, mp = pcall(d.getMountPath)
  if not ok or not mp then return nil end
  return fs.combine(mp, chave.ARQUIVO)
end

function tranca.lerSelo(d)
  local caminho = caminhoDoSelo(d)
  if not caminho or not fs.exists(caminho) then return nil end
  local f = fs.open(caminho, "r")
  if not f then return nil end
  local t = textutils.unserialize(f.readAll() or "")
  f.close()
  return type(t) == "table" and t or nil
end

function tranca.gravarSelo(d, selo)
  local caminho = caminhoDoSelo(d)
  if not caminho then return false end
  local f = fs.open(caminho, "w")
  if not f then return false end
  f.write(textutils.serialize(selo))
  f.close()
  return true
end

-- -------------------------------------------------------------------- tela

local C = {
  fundo = colors.black, texto = colors.white, fraco = colors.gray,
  marca = colors.yellow, ruim = colors.red, bom = colors.lime,
}

local function cor(c)
  if term.isColour and term.isColour() then term.setTextColour(c) end
end

local function moldura(titulo)
  term.setBackgroundColour(C.fundo)
  term.clear()
  term.setCursorPos(1, 1)
  cor(C.marca)
  print("FALAE")
  cor(C.fraco)
  print(titulo or "")
  cor(C.texto)
  print("")
end

--- Le um PIN sem mostrar o que foi digitado.
-- @return o texto, ou nil se desistiu com Esc
local function lerPin(rotulo)
  local _, y = term.getCursorPos()
  local digitado = ""
  while true do
    term.setCursorPos(1, y)
    term.clearLine()
    cor(C.marca)
    term.write(rotulo .. " ")
    cor(C.texto)
    term.write(("*"):rep(#digitado))
    term.setCursorBlink(true)

    local ev, p1 = os.pullEvent()
    if ev == "char" and p1:match("%d") then
      digitado = digitado .. p1
    elseif ev == "key" then
      if p1 == keys.enter then
        term.setCursorBlink(false)
        print("")
        return digitado
      elseif p1 == keys.backspace then
        digitado = digitado:sub(1, -2)
      elseif p1 == keys.tab then
        term.setCursorBlink(false)
        print("")
        return nil
      end
    end
  end
end

tranca.lerPin = lerPin

local function dizer(texto, c)
  cor(c or C.texto)
  print(texto)
  cor(C.texto)
end

-- ------------------------------------------------------------------- boot

--- Ha uma chave inscrita no drive, sem pedir PIN?
--
-- E o que liga a maquina. Conferir so o id nao prova que quem esta ali sabe o
-- PIN - prova que o disquete e aquele, e id de disquete nao se fabrica. Basta
-- para a maquina subir, e nao basta para operar: operar passa por
-- tranca.abrir, que quer o segredo.
--
-- Ligar sem PIN e o que faz a central voltar sozinha depois de um reinicio de
-- chunk, com o disquete deixado no drive. Uma central telefonica que so volta
-- quando alguem aparece com um disquete na mao nao e uma central telefonica.
function tranca.presente(papel)
  local id = tranca.disco()
  if not id then return false end
  return chaveiro.inscrita(id, papel)
end

--- Espera ate aparecer uma chave valida no drive. Volta true quando aparecer.
--
-- Nao morre e nao pede reinicio: encaixar o disquete sobe a maquina na hora,
-- do mesmo jeito que encaixar um modem poe a FALAE no ar.
function tranca.esperar(papel, titulo)
  if tranca.presente(papel) then return true end

  while true do
    moldura(titulo or "trancada")
    local id, motivo = tranca.disco()
    if id and not chaveiro.inscrita(id, papel) then
      motivo = "esse disquete nao e uma chave desta maquina"
    end
    dizer(motivo or "", C.ruim)
    print("")
    dizer("Ponha a chave da FALAE no drive.", C.fraco)
    dizer("Ela sobe sozinha assim que entrar.", C.fraco)

    -- disk e disk_eject sao os do CC; peripheral e peripheral_detach cobrem o
    -- drive sendo posto ou tirado, e o timer cobre o resto
    local temporizador = os.startTimer(3)
    local ev = os.pullEvent()
    if ev == "terminate" then return false end
    if ev ~= "timer" then os.cancelTimer(temporizador) end

    if tranca.presente(papel) then return true end
  end
end

-- ----------------------------------------------------------------- destranca

--- Destranca de verdade: disquete + PIN.
--
-- @return a chave, ou nil + motivo
function tranca.abrir(papel, titulo)
  local id, motivo, d = tranca.disco()
  if not id then return nil, motivo end

  local selo = tranca.lerSelo(d)
  if not selo then return nil, "esse disquete nao tem chave gravada" end

  moldura(titulo or "balcao trancado")
  dizer("Chave no drive: disquete #" .. tostring(id), C.fraco)
  print("")

  local pin = lerPin("PIN da chave:")
  if pin == nil then return nil, "cancelado" end

  print("")
  dizer("conferindo...", C.fraco)

  -- O id vem do DRIVE. Se o selo foi copiado para outro disquete, o fluxo
  -- deriva diferente e o segredo sai errado - que e o ponto.
  local segredo, erro = chave.abrir(selo, id, pin)
  if not segredo then return nil, erro end

  return chaveiro.conferir(id, segredo, papel, chave)
end

--- A sessao do balcao: destrancado enquanto o disquete estiver no drive e
-- dentro do prazo.
--
-- Tirar o disquete tranca na hora. E o gesto que a pessoa ja tem: acabou,
-- leva a chave.
function tranca.sessaoValida(sessao)
  if type(sessao) ~= "table" then return false end
  if os.epoch("utc") > (sessao.ate or 0) then return false end
  local id = tranca.disco()
  return id ~= nil and tostring(id) == tostring(sessao.disco)
end

function tranca.novaSessao(k, disco)
  return { disco = tostring(disco), nome = k.nome, papel = k.papel,
           ate = os.epoch("utc") + tranca.SESSAO }
end

-- ------------------------------------------------------------------ emitir

--- Grava uma chave nova no disquete que estiver no drive, e inscreve.
--
-- NAO DESENHA NADA. Quem chama ja tem uma tela na mao e sabe onde esta; e uma
-- funcao que grava disquete e mexe no chaveiro precisa poder ser testada sem
-- terminal nenhum, que e onde os erros dela apareceriam.
--
-- @return a chave inscrita, ou nil + motivo
function tranca.emitir(nome, papel, pin)
  local id, motivo, d = tranca.disco()
  if not id then return nil, motivo end

  if chaveiro.de(id) then
    return nil, "esse disquete ja e uma chave desta maquina"
  end

  local p, erro = chave.pinValido(pin)
  if not p then return nil, erro end

  local segredo = chave.novoSegredo()
  local selo = chave.selar(id, segredo, p)

  if not tranca.gravarSelo(d, selo) then
    return nil, "nao consegui gravar no disquete"
  end

  local k, motivo2 = chaveiro.inscrever(id, nome, papel, segredo, chave)
  if not k then return nil, motivo2 end

  pcall(function() disk.setLabel(peripheral.getName(d), "FALAE " .. papel) end)
  return k
end

return tranca
