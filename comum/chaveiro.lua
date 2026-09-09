--[[ chaveiro - as chaves que ESTA maquina aceita

  Cada maquina tem o seu. A central tem o dela, a loja tera o dela, e nenhuma
  das duas pergunta nada pela rede para conferir uma chave.

  ISSO E DE PROPOSITO. Conferir chave por rednet significaria a prova viajando
  por um canal que qualquer um escuta e repete depois. Daria para resolver com
  desafio e resposta, mas ai a maquina que confere precisa guardar o SEGREDO em
  vez da impressao - e o disco dela vira o cofre de todas as chaves. Local, sem
  rede, cada maquina guardando so impressao: menos peca, menos superficie, e
  nada que dependa de um canal em texto puro.

  O FREIO E O MESMO DA LINHA. Errar o PIN da chave custa espera, e a espera
  cresce. Sem ele, um PIN de seis digitos e um milhao de tentativas, e um
  milhao de tentativas e questao de minutos para um computador.

  A PRIMEIRA CHAVE NAO TEM COMO SER CONFERIDA POR OUTRA. Chaveiro vazio quer
  dizer maquina sem dono: a primeira chave emitida a reivindica. E o mesmo
  momento de qualquer instalacao nova - quem chega primeiro no computador
  recem-posto e o dono - e por isso a tela diz isso com todas as letras em vez
  de deixar parecer que ja havia tranca.
]]

local chaveiro = {}

chaveiro.CAMINHO = "/dados/chaves"

-- Espera depois de cada erro seguido, em segundos. Igual ao da linha: os dois
-- primeiros nao custam nada, porque dedo torto acontece.
chaveiro.FREIO = { 0, 0, 5, 15, 45, 90 }

-- [disco] = { nome, papel, sal, impressao, emitida, ultimoUso, erros, travadaAte }
local registro = {}

-- ------------------------------------------------------------------ disco

local function ler()
  if not fs.exists(chaveiro.CAMINHO) then return {} end
  local f = fs.open(chaveiro.CAMINHO, "r")
  if not f then return {} end
  local t = textutils.unserialize(f.readAll() or "")
  f.close()
  return type(t) == "table" and t or {}
end

local function gravar()
  local dir = fs.getDir(chaveiro.CAMINHO)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end

  -- pelo temporario e com copia, como o store: este e o arquivo que decide
  -- quem entra, e perde-lo tranca a operadora para fora da propria central
  local tmp = chaveiro.CAMINHO .. ".tmp"
  local f = fs.open(tmp, "w")
  if not f then return false end
  f.write(textutils.serialize(registro))
  f.close()

  local bak = chaveiro.CAMINHO .. ".bak"
  if fs.exists(bak) then fs.delete(bak) end
  if fs.exists(chaveiro.CAMINHO) then fs.move(chaveiro.CAMINHO, bak) end
  fs.move(tmp, chaveiro.CAMINHO)
  if fs.exists(bak) then fs.delete(bak) end
  return true
end

function chaveiro.carregar()
  registro = ler()
  -- as chaves ficam por id de disquete, e o textutils devolve chave de tabela
  -- como texto quando o arquivo foi escrito com numero: normaliza uma vez
  local normal = {}
  for k, v in pairs(registro) do
    if type(v) == "table" then normal[tostring(k)] = v end
  end
  registro = normal
  return registro
end

function chaveiro.salvar() return gravar() end

-- ---------------------------------------------------------------- consulta

function chaveiro.vazio()
  return next(registro) == nil
end

function chaveiro.quantas()
  local n = 0
  for _ in pairs(registro) do n = n + 1 end
  return n
end

function chaveiro.de(disco)
  return registro[tostring(disco)]
end

--- Este disquete e uma chave inscrita para este papel?
--
-- SEM PIN. E o que o boot usa: conferir o id do disquete nao prova que quem
-- esta ali sabe o PIN, mas prova que o disquete e aquele - e id de disquete
-- nao se fabrica, porque o mundo nunca repete um numero que ja saiu. Basta
-- para ligar a maquina, e nao basta para operar: quem opera passa por
-- chaveiro.conferir, que quer o segredo.
function chaveiro.inscrita(disco, papel)
  local k = registro[tostring(disco)]
  if not k then return false end
  if papel and k.papel ~= papel and k.papel ~= "central" then return false end
  return true
end

function chaveiro.listar()
  local saida = {}
  for disco, k in pairs(registro) do
    saida[#saida + 1] = {
      disco = disco, nome = k.nome, papel = k.papel,
      emitida = k.emitida, ultimoUso = k.ultimoUso,
      travadaAte = k.travadaAte,
    }
  end
  table.sort(saida, function(a, b) return (a.emitida or 0) < (b.emitida or 0) end)
  return saida
end

-- ------------------------------------------------------------------ freio

--- Quantos segundos faltam na trava desta chave. 0 se esta livre.
function chaveiro.travada(disco)
  local k = registro[tostring(disco)]
  if not k or not k.travadaAte then return 0 end
  local resta = k.travadaAte - os.epoch("utc")
  if resta <= 0 then return 0 end
  return math.ceil(resta / 1000)
end

local function errou(k)
  k.erros = (k.erros or 0) + 1
  local segundos = chaveiro.FREIO[math.min(k.erros, #chaveiro.FREIO)] or 0
  if segundos > 0 then k.travadaAte = os.epoch("utc") + segundos * 1000 end
  gravar()
  return segundos
end

-- ---------------------------------------------------------------- inscrever

--- Guarda uma chave nova neste chaveiro.
--
-- Recebe o SEGREDO e guarda so a impressao dele. Nada aqui devolve segredo
-- nenhum depois: quem quiser usar a chave tem que trazer o disquete.
function chaveiro.inscrever(disco, nome, papel, segredo, chave)
  disco = tostring(disco)
  if registro[disco] then return nil, "esse disquete ja e uma chave" end
  if not chave.PAPEIS[papel] then return nil, "papel desconhecido: " .. tostring(papel) end

  local sal = chave.novoSal()
  registro[disco] = {
    nome      = tostring(nome or "chave"),
    papel     = papel,
    sal       = sal,
    impressao = chave.impressao(disco, segredo, sal),
    emitida   = os.epoch("utc"),
    erros     = 0,
  }
  gravar()
  return registro[disco]
end

function chaveiro.remover(disco)
  disco = tostring(disco)
  if not registro[disco] then return false end
  -- Tirar a ultima chave destrancaria a maquina inteira, e quem fizesse isso
  -- por engano so descobriria no proximo reinicio, com a FALAE fora do ar.
  if chaveiro.quantas() <= 1 then
    return nil, "e a ultima chave - a central ficaria sem dono"
  end
  registro[disco] = nil
  gravar()
  return true
end

-- ----------------------------------------------------------------- conferir

--- O segredo que veio do disquete confere?
--
-- @param disco id lido do DRIVE
-- @param segredo o que saiu de chave.abrir (com o PIN que a pessoa digitou)
-- @return a chave, ou nil + motivo
function chaveiro.conferir(disco, segredo, papel, chave)
  disco = tostring(disco)
  local k = registro[disco]

  -- Mesma recusa para disquete desconhecido e para PIN errado. Respostas
  -- diferentes contariam para quem achou um disquete no chao se ele e uma
  -- chave de verdade - o que ja e meia informacao a mais do que precisa sair.
  local RECUSA = "chave nao reconhecida"
  if not k then return nil, RECUSA end

  local espera = chaveiro.travada(disco)
  if espera > 0 then
    return nil, ("chave travada - espere %ds"):format(espera)
  end

  if papel and k.papel ~= papel and k.papel ~= "central" then
    return nil, "essa chave nao abre isto aqui"
  end

  if chave.impressao(disco, segredo, k.sal) ~= k.impressao then
    local segundos = errou(k)
    if segundos > 0 then
      return nil, ("chave nao reconhecida - espere %ds"):format(segundos)
    end
    return nil, RECUSA
  end

  k.erros = 0
  k.travadaAte = nil
  k.ultimoUso = os.epoch("utc")
  gravar()
  return k
end

return chaveiro
