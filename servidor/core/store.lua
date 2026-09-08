--[[ store - tabelas guardadas em disco

  Grava num arquivo temporario e so entao renomeia. Se o servidor for
  desligado no meio da gravacao - ou o chunk descarregar, que no CC acontece -
  o arquivo antigo continua inteiro em vez de virar meio arquivo corrompido.
  Como o registro de dispositivos mora aqui, meio arquivo significaria a
  empresa inteira perdendo o cracha de uma vez.
]]

local store = {}

--- Le uma tabela do disco. Nunca levanta erro: arquivo faltando, vazio ou
-- corrompido devolvem o padrao.
function store.carregar(caminho, padrao)
  padrao = padrao or {}
  if not fs.exists(caminho) then return padrao end
  local f = fs.open(caminho, "r")
  if not f then return padrao end
  local txt = f.readAll()
  f.close()
  if not txt or txt == "" then return padrao end
  local t = textutils.unserialize(txt)
  if type(t) ~= "table" then return padrao end
  return t
end

function store.salvar(caminho, tabela)
  local dir = fs.getDir(caminho)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end

  local tmp = caminho .. ".tmp"
  local f = fs.open(tmp, "w")
  if not f then return false end
  local ok = pcall(function() f.write(textutils.serialize(tabela)) end)
  f.close()
  if not ok then
    if fs.exists(tmp) then fs.delete(tmp) end
    return false
  end

  if fs.exists(caminho) then fs.delete(caminho) end
  fs.move(tmp, caminho)
  return true
end

--- Le um arquivo de texto puro. nil se nao existir.
function store.texto(caminho)
  if not fs.exists(caminho) or fs.isDir(caminho) then return nil end
  local f = fs.open(caminho, "r")
  if not f then return nil end
  local txt = f.readAll()
  f.close()
  return txt or ""
end

function store.escreverTexto(caminho, texto)
  local dir = fs.getDir(caminho)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(caminho, "w")
  if not f then return false end
  f.write(texto)
  f.close()
  return true
end

--- Lista recursiva de arquivos dentro de uma pasta, com caminho relativo a ela.
-- Ignora .tmp e arquivos que comecam com ponto.
function store.arquivos(raiz, prefixo, saida)
  prefixo = prefixo or ""
  saida = saida or {}
  local alvo = prefixo == "" and raiz or fs.combine(raiz, prefixo)
  if not fs.exists(alvo) then return saida end

  for _, nome in ipairs(fs.list(alvo)) do
    if nome:sub(1, 1) ~= "." and nome:sub(-4) ~= ".tmp" then
      local rel = prefixo == "" and nome or (prefixo .. "/" .. nome)
      if fs.isDir(fs.combine(raiz, rel)) then
        store.arquivos(raiz, rel, saida)
      else
        saida[#saida + 1] = rel
      end
    end
  end
  return saida
end

--- Acrescenta UMA linha ao fim de um arquivo, sem reler nem reescrever o resto.
--
-- E o que mantem o custo de mandar um recado constante. store.salvar()
-- reserializa a tabela toda: com mil recados guardados, cada mensagem enviada
-- pagaria o historico inteiro. Aqui a conta nao depende de quantos recados ja
-- existem.
--
-- Nao usa arquivo temporario de proposito - o append e a operacao que o fs do
-- CC ja faz de uma vez, e um .tmp por mensagem seria justamente a copia do
-- arquivo inteiro que estamos evitando. O preco: uma queda no meio da escrita
-- pode deixar meia linha no fim do arquivo. Quem le trata isso descartando
-- linha que nao decodifica, em vez de perder o arquivo.
function store.anexar(caminho, linha)
  local dir = fs.getDir(caminho)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(caminho, "a")
  if not f then return false end
  f.write(tostring(linha) .. "\n")
  f.close()
  return true
end

--- Le um arquivo de linhas, devolvendo uma lista de strings sem as vazias.
function store.linhas(caminho)
  local txt = store.texto(caminho)
  if not txt or txt == "" then return {} end
  local saida = {}
  for linha in txt:gmatch("[^\r\n]+") do
    if linha ~= "" then saida[#saida + 1] = linha end
  end
  return saida
end

--- Reescreve o arquivo de linhas inteiro, pelo temporario.
--
-- So acontece quando o historico e aparado - fora do caminho de um pedido,
-- nunca por mensagem. Vai pelo .tmp e nao por escreverTexto() porque este e o
-- unico momento em que o arquivo de recados fica vulneravel: uma queda no meio
-- da reescrita perderia de uma vez o historico que o append protegeu recado a
-- recado.
function store.escreverLinhas(caminho, lista)
  local texto = #lista > 0 and (table.concat(lista, "\n") .. "\n") or ""

  local dir = fs.getDir(caminho)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end

  local tmp = caminho .. ".tmp"
  local f = fs.open(tmp, "w")
  if not f then return false end
  local ok = pcall(function() f.write(texto) end)
  f.close()
  if not ok then
    if fs.exists(tmp) then fs.delete(tmp) end
    return false
  end

  if fs.exists(caminho) then fs.delete(caminho) end
  fs.move(tmp, caminho)
  return true
end

return store
