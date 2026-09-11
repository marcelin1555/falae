--[[ cc_mock - finge ser o CC:Tweaked para os testes rodarem fora do jogo

  Veio pronto da Expresso Labs, onde ja tinha sido usado contra um servidor de
  verdade. Aqui muda so o que se monta no disco virtual.

  Implementa em memoria o pedaco da API que a central usa: fs, textutils,
  os, colors. Nada de rede, tela ou periferico - o que precisa disso e
  testado por fora, chamando central.atender direto.

  O disco e virtual: montar() copia os arquivos reais do projeto para dentro
  dele, e tudo que o servidor gravar fica so na memoria do teste. Nenhum teste
  encosta no save do Minecraft.
]]

local mock = {}

local arquivos = {}          -- caminho -> conteudo
local pastas   = { [""] = true }

-- Varios computadores, cada um com seu disco. As funcoes de fs fecham sobre as
-- variaveis acima, nao sobre o valor delas: trocar de disco e so reapontar as
-- duas, e todo mundo passa a enxergar o disco novo. E o que permite testar
-- cliente e servidor conversando de verdade dentro do mesmo processo.
local discos = { padrao = { arquivos = arquivos, pastas = pastas } }
local emUso = "padrao"

function mock.disco(nome)
  if not discos[nome] then
    discos[nome] = { arquivos = {}, pastas = { [""] = true } }
  end
  arquivos = discos[nome].arquivos
  pastas   = discos[nome].pastas
  emUso = nome
  return nome
end

function mock.discoEmUso() return emUso end

-- ------------------------------------------------------------------ caminhos

--- Normaliza para a forma que o CC usa internamente: sem barra inicial,
-- sem barra final, com "." e ".." resolvidos.
local function norm(p)
  p = tostring(p or ""):gsub("\\", "/")
  local partes = {}
  for parte in p:gmatch("[^/]+") do
    if parte == ".." then
      if #partes > 0 then table.remove(partes) end
    elseif parte ~= "." then
      partes[#partes + 1] = parte
    end
  end
  return table.concat(partes, "/")
end

local function paiDe(p)
  p = norm(p)
  local corte = p:match("^(.*)/[^/]*$")
  return corte or ""
end

local function criarPastasAte(p)
  local acumulado = ""
  for parte in norm(p):gmatch("[^/]+") do
    acumulado = acumulado == "" and parte or (acumulado .. "/" .. parte)
    pastas[acumulado] = true
  end
end

-- ------------------------------------------------------------------------ fs

local fs = {}

function fs.combine(a, b)
  return norm(norm(a) .. "/" .. tostring(b or ""))
end

function fs.getDir(p) return paiDe(p) end
function fs.getName(p) return (norm(p):match("[^/]+$")) or "" end

function fs.exists(p)
  p = norm(p)
  return arquivos[p] ~= nil or pastas[p] == true
end

function fs.isDir(p)
  return pastas[norm(p)] == true
end

function fs.getSize(p)
  local c = arquivos[norm(p)]
  return c and #c or 0
end

function fs.attributes(p)
  p = norm(p)
  if arquivos[p] then
    return { size = #arquivos[p], isDir = false, modified = mock.relogio, created = 0 }
  end
  if pastas[p] then return { size = 0, isDir = true, modified = 0, created = 0 } end
  error("nao existe: " .. p)
end

function fs.makeDir(p)
  criarPastasAte(p)
  return true
end

--- Espaco livre sob um caminho. Modela o limite do disquete: o que ja foi
-- gravado ali conta contra o total.
function fs.getFreeSpace(p)
  p = norm(p)
  local usado = 0
  for k, v in pairs(arquivos) do
    if k == p or k:sub(1, #p + 1) == p .. "/" then usado = usado + #v end
  end
  local livre = mock.espacoLivre - usado
  return livre > 0 and livre or 0
end

function fs.delete(p)
  p = norm(p)
  arquivos[p] = nil
  pastas[p] = nil
  -- apaga o que estava dentro, como o CC faz
  for k in pairs(arquivos) do
    if k:sub(1, #p + 1) == p .. "/" then arquivos[k] = nil end
  end
  for k in pairs(pastas) do
    if k:sub(1, #p + 1) == p .. "/" then pastas[k] = nil end
  end
  return true
end

function fs.move(de, para)
  de, para = norm(de), norm(para)
  if arquivos[de] == nil then error("nao existe: " .. de) end
  criarPastasAte(paiDe(para))
  arquivos[para] = arquivos[de]
  arquivos[de] = nil
  return true
end

function fs.list(p)
  p = norm(p)
  local vistos, saida = {}, {}
  local prefixo = p == "" and "" or (p .. "/")
  local function considerar(caminho)
    if caminho:sub(1, #prefixo) ~= prefixo then return end
    local resto = caminho:sub(#prefixo + 1)
    if resto == "" then return end
    local nome = resto:match("^([^/]+)")
    if nome and not vistos[nome] then
      vistos[nome] = true
      saida[#saida + 1] = nome
    end
  end
  for k in pairs(arquivos) do considerar(k) end
  for k in pairs(pastas) do considerar(k) end
  table.sort(saida)
  return saida
end

function fs.open(p, modo)
  p = norm(p)
  if modo == "r" then
    local c = arquivos[p]
    if not c then return nil end
    local pos = 1
    local h = {}
    function h.readAll()
      local r = c:sub(pos)
      pos = #c + 1
      return r
    end
    function h.readLine()
      if pos > #c then return nil end
      local i = c:find("\n", pos, true)
      local linha
      if i then linha = c:sub(pos, i - 1); pos = i + 1
      else linha = c:sub(pos); pos = #c + 1 end
      return linha
    end
    function h.close() end
    return h
  elseif modo == "w" or modo == "a" then
    criarPastasAte(paiDe(p))
    local partes = (modo == "a" and arquivos[p]) and { arquivos[p] } or {}
    local h = {}
    function h.write(s) partes[#partes + 1] = tostring(s) end
    function h.writeLine(s) partes[#partes + 1] = tostring(s) .. "\n" end
    function h.close() arquivos[p] = table.concat(partes) end
    return h
  end
  return nil
end

-- ---------------------------------------------------------------- textutils

local textutils = {}

local function serializar(v, indent, visto)
  local t = type(v)
  if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
  if t == "string" then return string.format("%q", v) end
  if t ~= "table" then error("nao da para serializar " .. t) end
  if visto[v] then error("tabela ciclica") end
  visto[v] = true

  local pedacos = { "{" }
  for k, val in pairs(v) do
    local chave
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then
      chave = k .. " = "
    else
      chave = "[" .. serializar(k, indent, visto) .. "] = "
    end
    pedacos[#pedacos + 1] = indent .. "  " .. chave ..
                            serializar(val, indent .. "  ", visto) .. ","
  end
  pedacos[#pedacos + 1] = indent .. "}"
  visto[v] = nil
  return table.concat(pedacos, "\n")
end

function textutils.serialize(t) return serializar(t, "", {}) end
textutils.serialise = textutils.serialize

function textutils.unserialize(s)
  if type(s) ~= "string" or s == "" then return nil end
  local f = load("return " .. s, "unserialize", "t", {})
  if not f then return nil end
  local ok, v = pcall(f)
  if not ok then return nil end
  return v
end
textutils.unserialise = textutils.unserialize

function textutils.formatTime(t, vinteQuatro)
  local h = math.floor(t or 0) % 24
  local m = math.floor(((t or 0) % 1) * 60)
  return string.format("%02d:%02d", h, m)
end

-- ------------------------------------------------------------------------ os

local osCC = {}
for k, v in pairs(os) do osCC[k] = v end

mock.relogio = 1700000000000    -- ms; os testes avancam isto na mao
mock.id = 8
mock.label = nil

function osCC.epoch(qual)
  if qual == "utc" or qual == nil then return mock.relogio end
  return mock.relogio
end
function osCC.time() return 12.5 end
function osCC.day() return 1 end
function osCC.getComputerID() return mock.id end
function osCC.getComputerLabel() return mock.label end
function osCC.setComputerLabel(l) mock.label = l end
function osCC.reboot() error("reboot pedido", 0) end
function osCC.sleep() end

-- -------------------------------------------------------------------- cores

local colors = {
  white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16,
  lime = 32, pink = 64, gray = 128, lightGray = 256, cyan = 512,
  purple = 1024, blue = 2048, brown = 4096, green = 8192, red = 16384,
  black = 32768,
}

-- ------------------------------------------------------------------ montagem

-- Teclas com valores DISTINTOS.
--
-- Antes isto era uma tabela que devolvia 0 para tudo, o que fazia
-- keys.up == keys.down == keys.q. Qualquer teste de teclado passava sem
-- testar nada: toda comparacao de tecla dava verdadeiro na primeira.
mock.KEYS = {}
do
  local nomes = {
    "one","two","three","four","five","six","seven","eight","nine","zero",
    "q","w","e","r","t","y","u","i","o","p",
    "a","s","d","f","g","h","j","k","l",
    "z","x","c","v","b","n","m",
    "enter","backspace","tab","space","delete","home","up","down","left","right",
    "leftShift","leftCtrl",
  }
  for i, nome in ipairs(nomes) do mock.KEYS[nome] = i end
  mock.KEYS["end"] = #nomes + 1
end

--- Instala as APIs falsas como globais.
function mock.instalar()
  _G.fs = fs
  _G.textutils = textutils
  _G.os = osCC
  _G.colors = colors
  _G.colours = colors
  _G.sleep = function() end
  _G.keys = mock.KEYS
  mock.instalarWindow()
end

--- Monitor falso. Guarda o conteudo de cada celula, entao da para conferir
-- por programa onde o texto caiu - que e a versao automatica do "olhar a tela
-- e ver se sobrepos".
function mock.monitor(colunas, linhas)
  local m = { colunas = colunas, linhas = linhas, blits = 0, escritas = 0, escala = 1 }
  m.celulas = {}
  for y = 1, linhas do
    m.celulas[y] = {}
    for x = 1, colunas do m.celulas[y][x] = { ch = " ", fg = "0", bg = "f" } end
  end

  local cx, cy, fg, bg = 1, 1, colors.white, colors.black
  local paleta = {}

  local function digito(cor)
    local n, v = 0, cor or 1
    while v > 1 do v = v / 2; n = n + 1 end
    return ("0123456789abcdef"):sub(n + 1, n + 1)
  end

  function m.getSize() return colunas, linhas end
  function m.isColour() return true end
  m.isColor = m.isColour
  function m.setTextScale(e) m.escala = e end
  function m.setCursorPos(x, y) cx, cy = x, y end
  function m.getCursorPos() return cx, cy end
  function m.setTextColor(c) fg = c end
  m.setTextColour = m.setTextColor
  function m.setBackgroundColor(c) bg = c end
  m.setBackgroundColour = m.setBackgroundColor
  function m.setPaletteColour(c, r, g, b) paleta[c] = { r, g, b } end
  m.setPaletteColor = m.setPaletteColour
  function m.getPaletteColour(c)
    local p = paleta[c] or { 0.5, 0.5, 0.5 }
    return p[1], p[2], p[3]
  end
  m.getPaletteColor = m.getPaletteColour

  function m.clear()
    for y = 1, linhas do for x = 1, colunas do
      m.celulas[y][x] = { ch = " ", fg = digito(fg), bg = digito(bg) }
    end end
  end

  function m.write(s)
    m.escritas = m.escritas + 1
    s = tostring(s)
    for i = 1, #s do
      local x = cx + i - 1
      if x >= 1 and x <= colunas and cy >= 1 and cy <= linhas then
        m.celulas[cy][x] = { ch = s:sub(i, i), fg = digito(fg), bg = digito(bg), texto = true }
      end
    end
    cx = cx + #s
  end

  function m.clearLine()
    for x = 1, colunas do
      if cy >= 1 and cy <= linhas then
        m.celulas[cy][x] = { ch = " ", fg = digito(fg), bg = digito(bg) }
      end
    end
  end

  m.piscando = false
  function m.setCursorBlink(b) m.piscando = b and true or false end
  function m.getTextColour() return fg end
  m.getTextColor = m.getTextColour
  function m.getBackgroundColour() return bg end
  m.getBackgroundColor = m.getBackgroundColour

  --- O que esta escrito numa linha da tela. E como se confere layout por
  -- programa em vez de abrir o jogo e olhar.
  function m.texto(y)
    local out = {}
    for x = 1, colunas do out[x] = m.celulas[y][x].ch end
    return table.concat(out)
  end

  --- A tela inteira como uma string, para procurar coisa dentro.
  function m.tudo()
    local out = {}
    for y = 1, linhas do out[y] = m.texto(y) end
    return table.concat(out, "|")
  end

  function m.blit(texto, cfg, cbg)
    m.blits = m.blits + 1
    for i = 1, #texto do
      local x = cx + i - 1
      if x >= 1 and x <= colunas and cy >= 1 and cy <= linhas then
        m.celulas[cy][x] = { ch = texto:sub(i, i), fg = cfg:sub(i, i), bg = cbg:sub(i, i) }
      end
    end
    cx = cx + #texto
  end

  return m
end

-- ------------------------------------------------------------- perifericos

mock.espacoLivre = 125000     -- limite do disquete neste servidor

--- Instala uma lista de perifericos. Cada item: { nome=, tipo=, dev= }
function mock.perifericos(lista)
  mock.lista = lista or {}
  local function achar(nome)
    for _, p in ipairs(mock.lista) do if p.nome == nome then return p end end
  end
  _G.peripheral = {
    getNames = function()
      local n = {}
      for _, p in ipairs(mock.lista) do n[#n + 1] = p.nome end
      return n
    end,
    getType = function(nome) local p = achar(nome); return p and p.tipo end,
    hasType = function(nome, t) local p = achar(nome); return p ~= nil and p.tipo == t end,
    wrap    = function(nome) local p = achar(nome); return p and p.dev end,
    getName = function(dev)
      for _, p in ipairs(mock.lista) do if p.dev == dev then return p.nome end end
    end,
    find = function(tipo)
      for _, p in ipairs(mock.lista) do if p.tipo == tipo then return p.dev end end
    end,
  }
end

function mock.modem(nome, semFio)
  return { nome = nome, tipo = "modem",
           dev = { isWireless = function() return semFio and true or false end } }
end

--- Unidade de disquete montada em <montagem> dentro do disco virtual.
function mock.unidade(nome, montagem, temDisco)
  local rotulo
  return { nome = nome, tipo = "drive", dev = {
    isDiskPresent = function() return temDisco and true or false end,
    getMountPath  = function() return temDisco and montagem or nil end,
    setDiskLabel  = function(l) rotulo = l end,
    getDiskLabel  = function() return rotulo end,
  } }
end

--- Um drive de disquete em que da para trocar o disquete.
--
-- Cada disquete tem id proprio e uma pasta propria dentro do disco virtual: e
-- assim no jogo, e e o que faz o teste conseguir provar a coisa que mais
-- importa da chave - copiar o arquivo para outro disquete nao copia o id, e a
-- copia nao abre nada.
function mock.drive(nome)
  local dentro, rotulo = nil, nil
  local p
  p = {
    nome = nome, tipo = "drive",
    dev = {
      isDiskPresent = function() return dentro ~= nil end,
      getDiskID     = function() return dentro end,
      getMountPath  = function() return dentro and ("disco" .. dentro) or nil end,
      setDiskLabel  = function(l) rotulo = l end,
      getDiskLabel  = function() return rotulo end,
      ejectDisk     = function() dentro = nil end,
    },
    --- Poe um disquete de id <id>. Sem argumento, tira o que estiver la.
    por = function(id) dentro = id; rotulo = nil end,
    tirar = function() dentro = nil end,
  }
  return p
end

--- Modem e rednet falsos. O teste passa as funcoes que ligam um computador
-- no outro; aqui so montamos a fachada que o codigo de producao espera.
function mock.instalarRede(rede)
  mock.perifericos({ mock.modem("ender_modem_0", true) })
  _G.rednet = {
    open    = function() end,
    close   = function() end,
    isOpen  = function() return true end,
    host    = function() end,
    unhost  = function() end,
    send    = rede.enviar,
    receive = rede.receber,
    lookup  = rede.procurar,
  }
end

--- Copia um arquivo real do projeto para o disco virtual.
function mock.montarArquivo(destino, origemReal)
  local f = io.open(origemReal, "rb")
  if not f then error("nao achei no disco real: " .. origemReal) end
  local c = f:read("*a")
  f:close()
  criarPastasAte(paiDe(destino))
  arquivos[norm(destino)] = c
end

-- Todo modulo da central, num lugar so. Cada teste que montava a propria
-- lista quebrava toda vez que a central ganhava uma dependencia nova - e
-- quebrava com "modulo faltando", que parece bug do codigo e nao do teste.
mock.CORE = { "lib", "store", "linhas", "recados", "bloqueio", "denuncias",
              "exportacao", "telemetria", "central", "console" }
-- Moram em comum/ no repositorio e em /core/ na central, porque e la que o
-- lib.lua procura. O chaveiro e de cada maquina; a tranca e a mesma para todas.
mock.CORE_COMUM = { "chave", "chaveiro", "tranca", "json" }
mock.TELA = { "marca", "grafico", "abertura", "painel" }

--- Monta a central inteira no disco virtual atual.
-- @param comTela inclui os modulos de desenho (so o teste de tela precisa)
function mock.montarCentral(projeto, comTela)
  mock.montarArquivo("/protocolo.lua", projeto .. "/comum/protocolo.lua")
  mock.montarArquivo("/numero.lua",    projeto .. "/comum/numero.lua")
  mock.montarArquivo("/pixel.lua",     projeto .. "/comum/pixel.lua")
  mock.montarArquivo("/palette.lua",   projeto .. "/comum/palette.lua")
  mock.montarArquivo("/startup.lua",   projeto .. "/servidor/startup.lua")
  for _, nome in ipairs(mock.CORE) do
    mock.montarArquivo("/core/" .. nome .. ".lua",
                       projeto .. "/servidor/core/" .. nome .. ".lua")
  end
  for _, nome in ipairs(mock.CORE_COMUM) do
    mock.montarArquivo("/core/" .. nome .. ".lua",
                       projeto .. "/comum/" .. nome .. ".lua")
  end
  if comTela ~= false then
    for _, nome in ipairs(mock.TELA) do
      mock.montarArquivo("/tela/" .. nome .. ".lua",
                         projeto .. "/servidor/tela/" .. nome .. ".lua")
    end
  end
end

--- Monta um telefone no disco virtual atual. Use com mock.disco() para ter
-- varios aparelhos conversando com a mesma central dentro de um processo so.
function mock.montarTelefone(projeto)
  for _, nome in ipairs({ "carregar", "protocolo", "numero", "janela", "campo", "ritmo" }) do
    mock.montarArquivo("/" .. nome .. ".lua", projeto .. "/comum/" .. nome .. ".lua")
  end
  for _, nome in ipairs({ "fnet", "agenda", "app", "startup" }) do
    mock.montarArquivo("/" .. nome .. ".lua", projeto .. "/telefone/" .. nome .. ".lua")
  end
  for _, nome in ipairs({ "conversas", "conversa", "contatos", "perfil", "bloqueados", "entrar" }) do
    mock.montarArquivo("/telas/" .. nome .. ".lua",
                       projeto .. "/telefone/telas/" .. nome .. ".lua")
  end
end

--- Monta o computador da loja inteiro no disco virtual atual.
--
-- fnet.lua vem de telefone/ - a origem do arquivo, no repositorio, continua
-- la; so o destino em cada maquina que muda (ver a nota no manifesto.txt).
function mock.montarLoja(projeto)
  for _, nome in ipairs({ "carregar", "protocolo", "numero", "janela", "campo",
                         "chave", "chaveiro", "tranca" }) do
    mock.montarArquivo("/" .. nome .. ".lua", projeto .. "/comum/" .. nome .. ".lua")
  end
  mock.montarArquivo("/store.lua", projeto .. "/servidor/core/store.lua")
  mock.montarArquivo("/fnet.lua", projeto .. "/telefone/fnet.lua")
  for _, nome in ipairs({ "admin", "app", "startup" }) do
    mock.montarArquivo("/" .. nome .. ".lua", projeto .. "/loja/" .. nome .. ".lua")
  end
end

--- Escreve um arquivo direto no disco virtual (para montar pacotes de teste).
function mock.escrever(destino, conteudo)
  criarPastasAte(paiDe(destino))
  arquivos[norm(destino)] = conteudo
end

function mock.ler(caminho)
  return arquivos[norm(caminho)]
end

function mock.limparDados()
  for k in pairs(arquivos) do
    if k:sub(1, 6) == "dados/" then arquivos[k] = nil end
  end
end

--- Monitor medido em BLOCOS, que muda de tamanho conforme a escala do texto,
-- como o de verdade.
--
-- mock.monitor() tem tamanho fixo, entao com ele setTextScale nao faz nada e o
-- codigo que ESCOLHE a escala nunca e testado de verdade. A conta abaixo e a do
-- CC:Tweaked, lida do bytecode de ServerMonitor.rebuildTerminal:
--
--   colunas = round((blocosLargura - 0.3125) / (escala * 6 * 0.015625))
--   linhas  = round((blocosAltura  - 0.3125) / (escala * 9 * 0.015625))
--
-- Um monitor de 8x4 blocos da 164x52 em escala 0.5 e 41x13 em escala 2 - e por
-- isso que escolher escala importa.
function mock.tamanhoDeMonitor(blocosW, blocosH, escala)
  local colunas = math.max(math.floor((blocosW - 0.3125) / (escala * 6 * 0.015625) + 0.5), 1)
  local linhas  = math.max(math.floor((blocosH - 0.3125) / (escala * 9 * 0.015625) + 0.5), 1)
  return colunas, linhas
end

function mock.monitorBlocos(blocosW, blocosH, escalaInicial)
  local m = { blocos = { w = blocosW, h = blocosH } }
  local atual
  local escala = escalaInicial or 1

  -- Trocar a escala cria um monitor NOVO do tamanho novo e reaponta tudo para
  -- ele. Redimensionar "por dentro" nao funciona: as funcoes de mock.monitor
  -- fecham sobre o tamanho com que foram criadas, entao mexer so nas celulas
  -- deixa a escrita validando contra o tamanho velho - e o desenho some sem
  -- erro nenhum, que foi exatamente o que aconteceu na primeira tentativa.
  local function refazer()
    local colunas, linhas = mock.tamanhoDeMonitor(blocosW, blocosH, escala)
    atual = mock.monitor(colunas, linhas)
    m.celulas = atual.celulas
    m.colunas, m.linhas = colunas, linhas
    m.escala = escala

    for _, nome in ipairs({
      "getSize", "isColour", "isColor", "setCursorPos", "getCursorPos",
      "setTextColor", "setTextColour", "setBackgroundColor", "setBackgroundColour",
      "setPaletteColour", "setPaletteColor", "getPaletteColour", "getPaletteColor",
      "clear", "clearLine", "write", "blit", "setCursorBlink",
      "getTextColour", "getTextColor", "getBackgroundColour", "getBackgroundColor",
      "texto", "tudo",
    }) do
      m[nome] = atual[nome]
    end
  end

  function m.setTextScale(e)
    escala = e
    refazer()
  end
  function m.getTextScale() return escala end

  --- Quantas escritas e blits o monitor recebeu. E como se mede, por
  -- programa, se o painel esta redesenhando a toa - monitor de CC e
  -- sincronizado com todo cliente por perto, entao escrita a toa custa no
  -- servidor inteiro.
  function m.contador() return atual.escritas, atual.blits end
  function m.zerarContador() atual.escritas, atual.blits = 0, 0 end

  refazer()
  return m
end

--- Timers e fila de eventos, para testar laco de aplicativo.
--
-- Existe por causa de um bug que so aparecia no jogo: o laco do telefone criava
-- um timer por volta e so agia no timer daquela volta, entao qualquer evento
-- que ele nao tratasse (modem_message, por exemplo) desalinhava tudo e o
-- aparelho parava de buscar recado para sempre. Sem poder injetar evento no
-- laco, nao ha como um teste pegar isso.
--
-- Os timers NAO disparam sozinhos: quem entrega evento e a fila. Assim o teste
-- decide exatamente o que chega e em que ordem.
function mock.instalarEventos()
  mock.fila = {}
  mock.timers = {}          -- [id] = true enquanto vivo
  mock.timersCriados = 0
  mock.timersCancelados = 0
  local proximoId = 0

  _G.os.startTimer = function()
    proximoId = proximoId + 1
    mock.timers[proximoId] = true
    mock.timersCriados = mock.timersCriados + 1
    return proximoId
  end

  _G.os.cancelTimer = function(id)
    if mock.timers[id] then
      mock.timers[id] = nil
      mock.timersCancelados = mock.timersCancelados + 1
    end
  end

  --- Quantos timers foram criados e nunca cancelados nem disparados.
  -- Se este numero cresce a cada volta do laco, ha vazamento.
  mock.timersVivos = function()
    local n = 0
    for _ in pairs(mock.timers) do n = n + 1 end
    return n
  end

  --- Poe um evento na fila. Sem argumentos vira um evento generico que o
  -- aplicativo nao trata - que e justamente o caso que quebrava.
  mock.enfileirar = function(...)
    mock.fila[#mock.fila + 1] = { ... }
  end

  --- Poe na fila o PAR key+char que uma tecla imprimivel de verdade gera, na
  -- mesma ordem do jogo. Sem isto, todo teste de atalho de letra testava um
  -- mundo onde key e char nunca colidem - que nao existe no jogo, e foi
  -- assim que o furo do "D"+"s" virar "ds" (ver descartarCharPendente em
  -- telefone/app.lua) passou batido por 1003 asserções.
  mock.enfileirarTecla = function(letra)
    mock.enfileirar("key", mock.KEYS[letra])
    mock.enfileirar("char", letra)
  end

  --- Poe um evento de VOLTA na FRENTE da fila - o que descartarCharPendente
  -- (telefone/app.lua e loja/admin.lua) usa para devolver um evento que
  -- espiou e nao era o que procurava. No CC de verdade os.queueEvent poe no
  -- FIM da fila, mas o efeito pratico para este uso e o mesmo: nao existe
  -- nenhum outro evento no meio entre o "espiar" e o proximo pullEvent, entao
  -- fim e frente da fila vazia dao no mesmo lugar - e frente e mais simples
  -- de simular aqui.
  _G.os.queueEvent = function(...)
    table.insert(mock.fila, 1, { ... })
  end

  --- Dispara o timer mais antigo ainda vivo, como o CC faria.
  mock.dispararTimer = function()
    local menor
    for id in pairs(mock.timers) do
      if not menor or id < menor then menor = id end
    end
    if not menor then return nil end
    mock.timers[menor] = nil
    mock.enfileirar("timer", menor)
    return menor
  end

  _G.os.pullEvent = function(filtro)
    while true do
      local ev = table.remove(mock.fila, 1)
      if not ev then
        -- fila vazia: o teste acabou. Sair por erro e o jeito de parar um
        -- laco "while true" de dentro sem inventar uma condicao so para teste.
        error("FILA_VAZIA", 0)
      end
      if not filtro or ev[1] == filtro then
        return table.unpack(ev)
      end
    end
  end
  _G.os.pullEventRaw = _G.os.pullEvent
end

--- http.get falso, servindo os arquivos do repositorio no disco real.
--
-- E o que permite testar o instalador sem rede e sem jogo. Ele so sabe pedir
-- uma URL; de onde o texto vem nao e problema dele.
--
-- @param projeto a pasta do projeto no disco real
-- @param base a URL que o instalador usa como raiz
function mock.instalarHttp(projeto, base)
  mock.http = { pedidos = {}, falhar = {} }

  _G.http = {
    get = function(url)
      mock.http.pedidos[#mock.http.pedidos + 1] = url

      if mock.http.falhar[url] then
        return nil, mock.http.falhar[url]
      end

      if url:sub(1, #base) ~= base then
        return nil, "fora do repositorio: " .. url
      end
      local rel = url:sub(#base + 1)

      local f = io.open(projeto .. "/" .. rel, "rb")
      if not f then return nil, "404" end
      local corpo = f:read("*a")
      f:close()

      local h = {}
      function h.readAll() return corpo end
      function h.close() end
      return h
    end,
  }
end

---- http.post falso e controlavel - para testar quem MANDA dado para fora
-- (telemetria.lua) sem precisar de rede de verdade.
--
-- mock.posts guarda cada post feito, na ordem: { url=, corpo=, cabecalhos= }.
-- O teste le mock.posts para conferir exatamente o que saiu - inclusive que
-- NAO tem texto de recado nenhum dentro.
function mock.instalarHttpPost()
  mock.posts = {}
  local resposta = { ok = true }

  _G.http = _G.http or {}
  _G.http.post = function(url, corpo, cabecalhos)
    mock.posts[#mock.posts + 1] = { url = url, corpo = corpo, cabecalhos = cabecalhos }
    if not resposta.ok then return nil, resposta.erro or "falhou" end
    local h = {}
    function h.readAll() return resposta.texto or "" end
    function h.close() end
    return h
  end

  --- A partir de agora, todo post falha com este motivo.
  function mock.httpPostFalhar(motivo)
    resposta.ok = false
    resposta.erro = motivo or "falhou"
  end

  --- Volta a funcionar normalmente.
  function mock.httpPostFuncionar()
    resposta.ok = true
  end
end

-- Respostas prontas para o read() do instalador, na ordem.
function mock.responder(respostas)
  local i = 0
  _G.read = function()
    i = i + 1
    return respostas[i] or ""
  end
  return function() return i end
end

--- Um terminal falso simples, para programas que so escrevem texto corrido.
function mock.instalarTerm(colunas, linhas)
  mock.saida = {}
  local t = mock.monitor(colunas or 51, linhas or 19)
  _G.term = t
  _G.write = function(s) t.write(tostring(s)); mock.saida[#mock.saida + 1] = tostring(s) end
  _G.print = function(...)
    local partes = {}
    for i = 1, select("#", ...) do partes[i] = tostring((select(i, ...))) end
    local l = table.concat(partes, " ")
    mock.saida[#mock.saida + 1] = l .. "\n"
  end
  return t
end

function mock.textoDaSaida()
  return table.concat(mock.saida or {})
end

--- window.create falso: uma sub-janela que escreve no terminal de tras.
--
-- O painel usa window.create para dar a marca um retangulo proprio, e sem isto
-- aqui o teste de tela nao roda - o painel quebraria no jogo e o banco de
-- testes nao teria como saber.
function mock.instalarWindow()
  _G.window = {
    create = function(pai, x, y, w, h)
      local j = {}
      local cx, cy = 1, 1
      local fg, bg = colors.white, colors.black

      function j.getSize() return w, h end
      function j.setCursorPos(a, b) cx, cy = a, b end
      function j.getCursorPos() return cx, cy end
      function j.setTextColour(c) fg = c end
      j.setTextColor = j.setTextColour
      function j.setBackgroundColour(c) bg = c end
      j.setBackgroundColor = j.setBackgroundColour
      function j.isColour() return pai.isColour and pai.isColour() or true end
      j.isColor = j.isColour
      function j.setCursorBlink() end
      function j.getPaletteColour(c)
        if pai.getPaletteColour then return pai.getPaletteColour(c) end
        return 0.5, 0.5, 0.5
      end
      j.getPaletteColor = j.getPaletteColour
      function j.setPaletteColour(...) if pai.setPaletteColour then pai.setPaletteColour(...) end end
      j.setPaletteColor = j.setPaletteColour

      --- Recorta na borda da janela: e o comportamento que importa testar,
      -- porque escrever fora dela e escrever na tela de outro.
      local function dentro(lx, ly)
        return lx >= 1 and lx <= w and ly >= 1 and ly <= h
      end

      function j.write(texto)
        texto = tostring(texto)
        for i = 1, #texto do
          local lx = cx + i - 1
          if dentro(lx, cy) then
            pai.setCursorPos(x + lx - 1, y + cy - 1)
            pai.setTextColour(fg)
            pai.setBackgroundColour(bg)
            pai.write(texto:sub(i, i))
          end
        end
        cx = cx + #texto
      end

      function j.blit(texto, cfg, cbg)
        for i = 1, #texto do
          local lx = cx + i - 1
          if dentro(lx, cy) then
            pai.setCursorPos(x + lx - 1, y + cy - 1)
            pai.blit(texto:sub(i, i), cfg:sub(i, i), cbg:sub(i, i))
          end
        end
        cx = cx + #texto
      end

      function j.clear()
        for ly = 1, h do
          pai.setCursorPos(x, y + ly - 1)
          pai.setTextColour(fg)
          pai.setBackgroundColour(bg)
          pai.write(string.rep(" ", w))
        end
      end

      function j.clearLine()
        if not dentro(1, cy) then return end
        pai.setCursorPos(x, y + cy - 1)
        pai.setBackgroundColour(bg)
        pai.write(string.rep(" ", w))
      end

      return j
    end,
  }
end

--- Uma rede em que o telefone fala com a central dentro do mesmo processo.
--
-- rednet.send entrega o pedido a central na hora e guarda a resposta; o
-- rednet.receive seguinte devolve ela. Nao ha perda, atraso nem ordem trocada
-- - o que se testa aqui e o fluxo do aplicativo, nao o radio.
--
-- @param central o modulo central ja carregado (o dono de atender)
-- @param idCentral o id que o lookup devolve
function mock.redeDireta(central, idCentral, discoCentral)
  idCentral = idCentral or 8
  local caixa = {}
  local rede = {}

  function rede.enviar(para, mensagem)
    if para ~= idCentral then return end

    -- A central grava em /dados no disco DELA. Sem esta troca, ela gravaria no
    -- disco do aparelho que mandou o pedido - que e o disco ativo no momento
    -- do send - e o teste passaria a medir uma central que nao existe.
    local voltarPara = mock.discoEmUso()
    if discoCentral then mock.disco(discoCentral) end
    local quem = mock.id
    local ok, resposta = pcall(central.atender, quem, mensagem)
    if discoCentral then mock.disco(voltarPara) end
    if not ok then error(resposta, 0) end

    caixa[#caixa + 1] = { de = idCentral, m = resposta }
  end

  function rede.receber()
    local pacote = table.remove(caixa, 1)
    if not pacote then return nil end
    return pacote.de, pacote.m
  end

  function rede.procurar()
    return idCentral
  end

  mock.instalarRede(rede)
  return rede
end

--- dofile do CC resolve caminho absoluto a partir da raiz do computador;
-- o dofile do Lua de verdade iria procurar no disco real. Trocamos.
function mock.instalarDofile()
  _G.dofile = function(caminho)
    local c = arquivos[norm(caminho)]
    if not c then error("dofile: nao existe " .. tostring(caminho), 0) end
    local f, erro = load(c, "@" .. caminho)
    if not f then error("dofile: " .. tostring(erro), 0) end
    return f()
  end
end

return mock
