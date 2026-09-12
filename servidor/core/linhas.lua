--[[ linhas - as contas da FALAE

  Uma LINHA e uma pessoa: numero, nome e PIN. Ela mora aqui, na central, e nao
  no aparelho - e essa a diferenca entre a FALAE e a rede da Expresso Labs, em
  que o cracha mora no disco de um computador especifico. Aqui voce entra com
  numero e PIN no pocket do amigo e e voce, nao ele.

  Uma SESSAO e um aparelho que provou ser dono de uma linha. Ela existe para o
  PIN viajar UMA vez: depois do login, todo pedido leva o token da sessao. Numa
  rede que qualquer um escuta, quanto menos vezes o PIN passar, melhor.

  ATE ONDE ISSO PROTEGE. Rednet nao e criptografado: quem estiver no alcance
  escutando o canal pega o PIN no instante do login e pega os tokens que
  passam. O CC nao oferece criptografia de verdade para consertar isso.

  E o resumo do PIN nao e criptografia - e ofuscacao. Um PIN de quatro digitos
  tem dez mil possibilidades; nenhuma funcao de resumo torna isso seguro. O sal
  e as voltas so encarecem a vida de quem quebrar a central e ler o disco.
  Quem protege de verdade e o FREIO logo abaixo: errar de novo custa espera, e
  a espera cresce. E por isso que o freio, e nao o resumo, e o que tem teste.
]]

local lib    = dofile("/core/lib.lua")
local store  = lib("store")
local numero = lib("numero")

local linhas = {}

linhas.CAMINHO  = "/dados/linhas"
linhas.SESSOES  = "/dados/sessoes"

linhas.PIN_MIN  = 4
linhas.PIN_MAX  = 8
linhas.NOME_MAX = 16
linhas.VOLTAS   = 600      -- voltas do resumo do PIN

-- Espera depois de cada erro seguido, em segundos. O primeiro erro nao custa
-- nada: quem digitou torto merece tentar de novo na hora. A partir do
-- terceiro, a espera cresce ate um minuto - o suficiente para varrer dez mil
-- PINs levar mais de uma semana, e pouco para quem so errou o dedo.
linhas.FREIO = { 0, 0, 3, 10, 30, 60 }

-- Quanto tempo vale o codigo que o balcao entrega quando zera um PIN. Um dia
-- e folgado para quem foi atendido e voltou para casa, e curto o bastante para
-- um codigo esquecido nao ficar valendo para sempre.
linhas.RESGATE_VALIDADE = 24 * 60 * 60 * 1000

-- Sessao parada por mais que isto cai sozinha. Nao e seguranca contra ataque
-- (o token continua valendo enquanto e usado); e faxina, para o arquivo nao
-- crescer para sempre com aparelho que foi para o bau e nao volta.
linhas.VALIDADE = 30 * 24 * 60 * 60 * 1000   -- 30 dias, em ms

local registro = {}    -- [canonico] = { numero, nome, sal, resumo, criada, visto, erros, travadaAte }
local sessoes  = {}    -- [token]    = { numero, aparelho, desde, visto }

math.randomseed((os.epoch("utc") % 2147483647) + os.getComputerID())

-- ------------------------------------------------------------------ segredos

local function aleatorio(n)
  local d = {}
  for i = 1, n do d[i] = string.format("%x", math.random(0, 15)) end
  return table.concat(d)
end

--- Resumo do PIN. djb2 dado em VOLTAS voltas, realimentando o texto a cada
-- passagem para que o custo nao possa ser cortado pela metade.
function linhas.resumir(sal, pin)
  local texto = tostring(sal) .. ":" .. tostring(pin)
  local h = 5381
  for _ = 1, linhas.VOLTAS do
    for i = 1, #texto do
      h = (h * 33 + texto:byte(i)) % 4294967296
    end
    texto = string.format("%08x", h) .. sal
  end
  return string.format("%08x", h)
end

--- O codigo que o balcao entrega. Seis digitos, para a pessoa conseguir
-- guardar na cabeca do balcao ate o aparelho - quem protege nao e o tamanho
-- dele, e o freio que conta as tentativas erradas.
local function codigoResgate()
  local d = {}
  for i = 1, 6 do d[i] = tostring(math.random(0, 9)) end
  return table.concat(d)
end

-- -------------------------------------------------------------------- disco

function linhas.carregar()
  registro = store.carregar(linhas.CAMINHO, {})
  sessoes  = store.carregar(linhas.SESSOES, {})
  linhas.faxinar()
  return registro
end

function linhas.salvar()
  return store.salvar(linhas.CAMINHO, registro)
end

function linhas.salvarSessoes()
  return store.salvar(linhas.SESSOES, sessoes)
end

--- Joga fora sessao vencida. Chamado no boot e de vez em quando pela central,
-- nunca dentro de um pedido: e uma varredura, e varredura no caminho de um
-- pedido e exatamente o que a secao de desempenho proibe.
function linhas.faxinar()
  local agora = os.epoch("utc")
  local foram = 0
  for token, s in pairs(sessoes) do
    if type(s) ~= "table" or not s.visto or (agora - s.visto) > linhas.VALIDADE then
      sessoes[token] = nil
      foram = foram + 1
    end
  end
  if foram > 0 then linhas.salvarSessoes() end
  return foram
end

-- ------------------------------------------------------------------ consulta

function linhas.todas() return registro end

function linhas.existe(canonico)
  return registro[canonico] ~= nil
end

function linhas.quantas()
  local n = 0
  for _ in pairs(registro) do n = n + 1 end
  return n
end

--- O que um estranho pode saber sobre uma linha: que ela existe e como ela se
-- chama. Nunca o sal, o resumo, nem quando foi vista.
function linhas.publico(canonico)
  local l = registro[canonico]
  if not l then return nil end
  return { numero = l.numero, nome = l.nome }
end

function linhas.lista()
  local out = {}
  for _, l in pairs(registro) do
    out[#out + 1] = {
      numero = l.numero, nome = l.nome, criada = l.criada,
      visto = l.visto, travadaAte = l.travadaAte, semPin = l.resumo == nil,
    }
  end
  table.sort(out, function(a, b) return a.numero < b.numero end)
  return out
end

-- -------------------------------------------------------------------- regras

local function nomeLimpo(nome)
  nome = tostring(nome or ""):gsub("[\r\n]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if nome == "" then return nil, "escolha um nome" end
  if #nome > linhas.NOME_MAX then nome = nome:sub(1, linhas.NOME_MAX) end
  return nome
end

local function pinValido(pin)
  pin = tostring(pin or "")
  if not pin:match("^%d+$") then return nil, "o PIN e so de numeros" end
  if #pin < linhas.PIN_MIN or #pin > linhas.PIN_MAX then
    return nil, ("o PIN tem de %d a %d digitos"):format(linhas.PIN_MIN, linhas.PIN_MAX)
  end
  return pin
end

-- --------------------------------------------------------------------- criar

--- Tira uma linha nova. O numero e sorteado.
-- @return { numero=, nome= }, token   ou   nil + motivo
function linhas.criar(nome, pin, aparelho)
  local n, erro = nomeLimpo(nome)
  if not n then return nil, erro end

  local p, erro2 = pinValido(pin)
  if not p then return nil, erro2 end

  local canonico, erro3 = numero.sortear(function(c) return registro[c] ~= nil end)
  if not canonico then return nil, erro3 end

  local sal = aleatorio(8)
  registro[canonico] = {
    numero = canonico,
    nome   = n,
    sal    = sal,
    resumo = linhas.resumir(sal, p),
    criada = os.epoch("utc"),
    visto  = os.epoch("utc"),
    erros  = 0,
  }
  linhas.salvar()

  local token = linhas.abrirSessao(canonico, aparelho)
  return linhas.publico(canonico), token
end

-- -------------------------------------------------------------------- entrar

--- Quanto tempo falta na trava desta linha, em segundos. 0 se esta livre.
function linhas.travada(canonico)
  local l = registro[canonico]
  if not l or not l.travadaAte then return 0 end
  local resta = l.travadaAte - os.epoch("utc")
  if resta <= 0 then return 0 end
  return math.ceil(resta / 1000)
end

--- Entra numa linha com numero e PIN.
-- @return token, linha publica   ou   nil + motivo
function linhas.entrar(texto, pin, aparelho)
  local canonico = numero.canonico(texto)
  if not canonico then return nil, "numero invalido" end

  local l = registro[canonico]

  -- Mesma resposta para linha inexistente e para PIN errado, de proposito.
  -- Respostas diferentes transformariam a tela de login num consultor de quais
  -- numeros existem, e a lista de linhas da FALAE nao e publica.
  local RECUSA = "numero ou PIN errado"
  if not l then return nil, RECUSA end

  -- Linha sem PIN recebe a MESMA recusa, e nao "esta linha esta sem PIN".
  -- Dizer isso era um oraculo: a resposta so aparecia para numero que EXISTE,
  -- e ainda apontava exatamente os que estavam abertos para quem chegasse
  -- primeiro com definir=true. Quem passou pelo balcao sabe que precisa do
  -- caminho do codigo; nao precisa ser lembrado por uma tela de login.
  if l.resumo == nil then return nil, RECUSA end

  local espera = linhas.travada(canonico)
  if espera > 0 then
    return nil, ("muita tentativa - espere %ds"):format(espera)
  end

  if linhas.resumir(l.sal, tostring(pin or "")) ~= l.resumo then
    l.erros = (l.erros or 0) + 1
    local segundos = linhas.FREIO[math.min(l.erros, #linhas.FREIO)] or 0
    if segundos > 0 then
      l.travadaAte = os.epoch("utc") + segundos * 1000
    end
    linhas.salvar()
    if segundos > 0 then
      return nil, ("numero ou PIN errado - espere %ds"):format(segundos)
    end
    return nil, RECUSA
  end

  l.erros = 0
  l.travadaAte = nil
  l.visto = os.epoch("utc")
  linhas.salvar()

  return linhas.abrirSessao(canonico, aparelho), linhas.publico(canonico)
end

-- -------------------------------------------------------------------- sessao

function linhas.abrirSessao(canonico, aparelho)
  local token = aleatorio(24)
  sessoes[token] = {
    numero   = canonico,
    aparelho = tonumber(aparelho) or 0,
    desde    = os.epoch("utc"),
    visto    = os.epoch("utc"),
  }
  linhas.salvarSessoes()
  return token
end

--- Quem esta falando? Chamado em TODO pedido com sessao, entao e O(1) por
-- construcao: tabela por chave, nenhuma varredura.
-- @return linha (a tabela interna), sessao   ou   nil + motivo
function linhas.sessao(token)
  if type(token) ~= "string" then return nil, "sem sessao - entre na sua linha" end
  local s = sessoes[token]
  if not s then return nil, "sessao expirada - entre de novo" end

  local l = registro[s.numero]
  if not l then
    -- a linha foi cassada no balcao enquanto o aparelho estava logado
    sessoes[token] = nil
    linhas.salvarSessoes()
    return nil, "esta linha nao existe mais"
  end

  -- O "visto" nao vai para o disco a cada pedido de proposito: seria uma
  -- gravacao por poll, de todo aparelho, para sempre. Ele pega carona na
  -- proxima gravacao que acontecer por outro motivo.
  s.visto = os.epoch("utc")
  l.visto = s.visto
  return l, s
end

function linhas.sair(token)
  if not sessoes[token] then return false end
  sessoes[token] = nil
  linhas.salvarSessoes()
  return true
end

--- Fecha toda sessao de uma linha. Usado quando o PIN e trocado ou zerado: um
-- PIN novo que deixasse os aparelhos antigos logados nao teria trocado nada.
function linhas.fecharTodas(canonico)
  local n = 0
  for token, s in pairs(sessoes) do
    if s.numero == canonico then sessoes[token] = nil; n = n + 1 end
  end
  if n > 0 then linhas.salvarSessoes() end
  return n
end

function linhas.sessoesDe(canonico)
  local n = 0
  for _, s in pairs(sessoes) do
    if s.numero == canonico then n = n + 1 end
  end
  return n
end

-- -------------------------------------------------------------------- perfil

function linhas.trocarNome(canonico, nome)
  local l = registro[canonico]
  if not l then return nil, "linha nao encontrada" end
  local n, erro = nomeLimpo(nome)
  if not n then return nil, erro end
  l.nome = n
  linhas.salvar()
  return linhas.publico(canonico)
end

--- Troca o PIN sabendo o antigo. Derruba as outras sessoes.
function linhas.trocarPin(canonico, antigo, novo)
  local l = registro[canonico]
  if not l then return nil, "linha nao encontrada" end
  if l.resumo ~= nil and linhas.resumir(l.sal, tostring(antigo or "")) ~= l.resumo then
    return nil, "PIN atual errado"
  end
  local p, erro = pinValido(novo)
  if not p then return nil, erro end

  l.sal = aleatorio(8)
  l.resumo = linhas.resumir(l.sal, p)
  linhas.salvar()
  linhas.fecharTodas(canonico)
  return true
end

-- -------------------------------------------------------------------- balcao

--- Zera o PIN de uma linha. So o console da central chama isto - e o
-- atendimento da FALAE, com a pessoa na frente.
--
-- Nao devolve PIN nenhum porque a central nao sabe PIN de ninguem: ela apaga o
-- resumo e a linha entra no modo "defina um PIN novo" no proximo login.
--- @return o codigo de resgate a dizer para a pessoa, ou nil + motivo
function linhas.zerarPin(texto)
  local canonico = numero.canonico(texto)
  if not canonico or not registro[canonico] then return nil, "linha nao encontrada" end
  local l = registro[canonico]
  l.sal = nil
  l.resumo = nil
  l.erros = 0
  l.travadaAte = nil
  l.resgate = {
    codigo = codigoResgate(),
    ate    = os.epoch("utc") + linhas.RESGATE_VALIDADE,
  }
  linhas.salvar()
  linhas.fecharTodas(canonico)
  return l.resgate.codigo
end

function linhas.semPin(texto)
  local canonico = numero.canonico(texto)
  if not canonico then return false end
  local l = registro[canonico]
  return l ~= nil and l.resumo == nil
end

--- Define o PIN de uma linha que esta sem nenhum, com o codigo do balcao.
--
-- O CODIGO E O QUE FAZ ISTO SER SEGURO. Sem ele, esta rota entregava a linha
-- para quem digitasse o numero primeiro - e como ela e (e precisa ser) uma
-- rota sem sessao, "quem digitasse primeiro" quer dizer qualquer um com um
-- modem. A janela era o tempo entre o balcao zerar e a pessoa voltar para
-- casa, que sao justamente as horas em que ninguem esta olhando.
--
-- Toda recusa devolve a mesma frase, e o freio das tentativas e o mesmo do
-- login: seis digitos sem freio sao um milhao de tentativas, e um milhao de
-- tentativas e coisa de minutos para um computador.
--
-- @return token, linha publica  ou  nil + motivo
function linhas.definirPin(texto, pin, codigo, aparelho)
  local RECUSA = "numero ou codigo errado"

  local canonico = numero.canonico(texto)
  if not canonico then return nil, RECUSA end
  local l = registro[canonico]
  if not l or l.resumo ~= nil then return nil, RECUSA end

  local espera = linhas.travada(canonico)
  if espera > 0 then
    return nil, ("muita tentativa - espere %ds"):format(espera)
  end

  local r = l.resgate
  local vencido = type(r) ~= "table" or not r.codigo
                  or (r.ate ~= nil and os.epoch("utc") > r.ate)
  if vencido or tostring(codigo or "") ~= r.codigo then
    l.erros = (l.erros or 0) + 1
    local segundos = linhas.FREIO[math.min(l.erros, #linhas.FREIO)] or 0
    if segundos > 0 then l.travadaAte = os.epoch("utc") + segundos * 1000 end
    linhas.salvar()
    return nil, RECUSA
  end

  local p, erro = pinValido(pin)
  if not p then return nil, erro end

  l.sal = aleatorio(8)
  l.resumo = linhas.resumir(l.sal, p)
  l.resgate = nil
  l.erros = 0
  l.travadaAte = nil
  l.visto = os.epoch("utc")
  linhas.salvar()
  return linhas.abrirSessao(canonico, aparelho), linhas.publico(canonico)
end

--- Cassa uma linha. O historico de recados nao e apagado aqui: quem cuida
-- disso e o modulo de recados, que sabe o que fazer com conversa de dois.
function linhas.remover(texto)
  local canonico = numero.canonico(texto)
  if not canonico or not registro[canonico] then return false end
  registro[canonico] = nil
  linhas.salvar()
  linhas.fecharTodas(canonico)
  return true
end

-- ------------------------------------------------------- para o painel

-- Quanto tempo sem ser vista antes de a linha deixar de contar como "no ar".
-- O telefone pergunta a central a cada 5 segundos (ver telefone/app.lua),
-- entao dois minutos de silencio ja querem dizer aparelho desligado.
linhas.NO_AR = 2 * 60 * 1000

--- Quantas sessoes estao abertas agora, e em quantos aparelhos diferentes.
--
-- Uma linha pode estar aberta em dois aparelhos (o pocket e um computador), e
-- os dois numeros contam coisas diferentes: sessoes e quantas portas estao
-- destrancadas, aparelhos e quantas maquinas ligadas existem.
function linhas.sessoesAbertas()
  local agora = os.epoch("utc")
  local abertas, vivas = 0, 0
  local aparelhos = {}
  for _, s in pairs(sessoes) do
    if type(s) == "table" then
      abertas = abertas + 1
      if s.visto and (agora - s.visto) <= linhas.NO_AR then
        vivas = vivas + 1
        if s.aparelho then aparelhos[s.aparelho] = true end
      end
    end
  end
  local maquinas = 0
  for _ in pairs(aparelhos) do maquinas = maquinas + 1 end
  return abertas, vivas, maquinas
end

--- Quantas linhas foram vistas depois de <ms>.
function linhas.ativasDesde(ms)
  local n = 0
  for _, l in pairs(registro) do
    if l.visto and l.visto >= ms then n = n + 1 end
  end
  return n
end

--- O que precisa da operadora agora.
--
-- Duas coisas, e as duas sao acionaveis - que e o criterio para entrar aqui.
-- Numero que so informa nao e atencao, e uma faixa de atencao que vive cheia
-- de informacao treina a pessoa a nao olhar para ela.
--
--   semPin    passou pelo balcao e ainda nao definiu PIN novo. Alguem esta
--             esperando para voltar a usar a linha.
--   travada   errou o PIN vezes demais. Pode ser a pessoa com o dedo torto,
--             pode ser alguem tentando entrar na linha dos outros.
--
-- @return lista de { numero=, motivo=, desde= }, mais recente primeiro
function linhas.atencao()
  local agora = os.epoch("utc")
  local saida = {}

  for canonico, l in pairs(registro) do
    if l.resumo == nil then
      saida[#saida + 1] = {
        numero = canonico, motivo = "sem PIN", desde = l.visto or l.criada,
      }
    elseif l.travadaAte and l.travadaAte > agora then
      saida[#saida + 1] = {
        numero = canonico, motivo = "travada", desde = l.visto or l.criada,
        ate = l.travadaAte,
      }
    end
  end

  table.sort(saida, function(a, b) return (a.desde or 0) > (b.desde or 0) end)
  return saida
end

return linhas
