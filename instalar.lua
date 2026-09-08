--[[ instalar - a FALAE entra num computador pela rede

  Rode uma vez, dentro do jogo:

    wget run https://raw.githubusercontent.com/marcelin1555/falae/main/instalar.lua

  Existe porque num servidor de outra pessoa nao ha como chegar na pasta do
  save: o computador tem que buscar os arquivos sozinho. Este e o unico caminho
  de instalacao que funciona sem ser dono do mundo - e por isso e o principal,
  nao um extra.

  Baixa a lista do manifesto e depois cada arquivo dela. Um arquivo de cada
  vez, com o nome na tela: se a rede cair no meio, da para ver onde parou em
  vez de descobrir depois que faltou um modulo.

  ATUALIZAR e rodar de novo. Os arquivos sao substituidos; a linha, a agenda e
  as conversas do aparelho ficam onde estao (moram em arquivos que comecam com
  ponto, e o instalador nao encosta neles).
]]

local REPO  = "marcelin1555/falae"
local RAMO  = "main"
local BASE  = "https://raw.githubusercontent.com/" .. REPO .. "/" .. RAMO .. "/"

local C = {
  marca = colors.yellow, texto = colors.white, fraco = colors.lightGray,
  bom = colors.lime, ruim = colors.red, aviso = colors.orange,
}

-- ------------------------------------------------------------------- tela

local function cor(c)
  if term.isColour() then term.setTextColour(c) end
end

local function linha(texto, c)
  cor(c or C.texto)
  print(texto)
  cor(C.texto)
end

local function cabecalho()
  term.setBackgroundColour(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  cor(C.marca)
  print("FALAE")
  cor(C.fraco)
  print("instalador")
  cor(C.texto)
  print("")
end

-- ------------------------------------------------------------------- rede

--- Baixa um texto. Devolve nil + motivo, nunca levanta erro: erro de rede e
-- normal e precisa virar mensagem legivel, nao pilha de chamada.
local function baixar(caminho)
  if not http then
    return nil, "o servidor esta com a API http desligada"
  end

  local url = BASE .. caminho
  local resposta, erro = http.get(url)
  if not resposta then
    return nil, tostring(erro or "sem resposta")
  end

  local corpo = resposta.readAll()
  resposta.close()
  if not corpo or corpo == "" then
    return nil, "veio vazio"
  end
  return corpo
end

--- Le o manifesto e devolve so as linhas do papel pedido.
local function lerManifesto(texto, papeis)
  local quero = {}
  for _, p in ipairs(papeis) do quero[p] = true end

  local lista = {}
  for l in texto:gmatch("[^\r\n]+") do
    if l:sub(1, 1) ~= "#" and l:find("|", 1, true) then
      local papel, destino, origem = l:match("^%s*([^|]-)%s*|%s*([^|]-)%s*|%s*(.-)%s*$")
      if papel and quero[papel] then
        lista[#lista + 1] = { destino = destino, origem = origem }
      end
    end
  end
  return lista
end

-- ------------------------------------------------------------------ disco

local function gravar(caminho, conteudo)
  local dir = fs.getDir(caminho)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(caminho, "w")
  if not f then return false end
  f.write(conteudo)
  f.close()
  return true
end

-- ---------------------------------------------------------------- perguntas

local function perguntar(texto, opcoes)
  while true do
    cor(C.marca)
    write(texto .. " ")
    cor(C.texto)
    local r = read():lower()
    for _, o in ipairs(opcoes) do
      if r == o or r == o:sub(1, 1) then return o end
    end
    linha("responda com: " .. table.concat(opcoes, ", "), C.aviso)
  end
end

local function simNao(texto, padraoSim)
  cor(C.marca)
  write(texto .. (padraoSim and " [S/n] " or " [s/N] "))
  cor(C.texto)
  local r = read():lower()
  if r == "" then return padraoSim end
  return r:sub(1, 1) == "s"
end

-- -------------------------------------------------------------------- main

local function principal()
  cabecalho()

  -- Um pocket computer nao tem como ser central: ele desliga quando sai do
  -- inventario de alguem, e uma central que some quando o dono desloga nao e
  -- uma central. Dizer isso agora poupa a descoberta depois.
  local ehPocket = pocket ~= nil

  local tipo
  if ehPocket then
    linha("Este e um pocket computer:", C.fraco)
    linha("instalando o telefone.", C.fraco)
    print("")
    tipo = "telefone"
  else
    linha("O que este computador vai ser?")
    print("")
    linha("  central   a central telefonica da FALAE", C.fraco)
    linha("  telefone  um aparelho", C.fraco)
    print("")
    tipo = perguntar("central ou telefone?", { "central", "telefone" })
    print("")
  end

  local comVisual = simNao("Instalar a parte visual (marca e painel)?", true)
  print("")

  linha("buscando a lista de arquivos...", C.fraco)
  local texto, erro = baixar("manifesto.txt")
  if not texto then
    print("")
    linha("nao consegui: " .. erro, C.ruim)
    print("")
    if not http then
      linha("A API http do CC esta desligada neste servidor.", C.aviso)
      linha("So o dono do servidor pode ligar, em", C.fraco)
      linha("config/computercraft-server.toml", C.fraco)
    else
      linha("Confira se o computador alcanca a internet.", C.fraco)
    end
    return false
  end

  local papeis = { tipo }
  if comVisual then papeis[#papeis + 1] = tipo .. "-visual" end

  local lista = lerManifesto(texto, papeis)
  if #lista == 0 then
    linha("a lista veio vazia - manifesto errado?", C.ruim)
    return false
  end

  print("")
  linha(("%d arquivo(s) a baixar."):format(#lista), C.texto)
  print("")

  local falhou = {}
  for i, a in ipairs(lista) do
    cor(C.fraco)
    write(("[%d/%d] "):format(i, #lista))
    cor(C.texto)
    write(a.destino)

    local conteudo, motivo = baixar(a.origem)
    if not conteudo then
      cor(C.ruim)
      print("  x")
      falhou[#falhou + 1] = a.destino .. ": " .. tostring(motivo)
    elseif not gravar(a.destino, conteudo) then
      cor(C.ruim)
      print("  x")
      falhou[#falhou + 1] = a.destino .. ": nao consegui gravar"
    else
      cor(C.bom)
      print("  ok")
    end
    cor(C.texto)
  end

  print("")
  if #falhou > 0 then
    linha(("%d arquivo(s) falharam:"):format(#falhou), C.ruim)
    for _, f in ipairs(falhou) do linha("  " .. f, C.fraco) end
    print("")
    linha("Rode o instalador de novo.", C.aviso)
    return false
  end

  linha("Instalado.", C.bom)
  print("")

  if tipo == "central" then
    linha("A central precisa de um Ender Modem", C.fraco)
    linha("encostado no computador.", C.fraco)
    linha("Monitor, se houver, tambem encostado.", C.fraco)
  else
    linha("O aparelho precisa de um Ender Modem", C.fraco)
    linha("nas costas (o slot de upgrade e um so,", C.fraco)
    linha("entao nao da para ter speaker junto).", C.fraco)
  end

  print("")
  if simNao("Reiniciar agora?", true) then
    os.reboot()
  end
  return true
end

local ok, erro = pcall(principal)
if not ok then
  cor(C.ruim)
  print("")
  print("o instalador quebrou: " .. tostring(erro))
  cor(C.texto)
end
