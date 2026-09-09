--[[ telemetria - a central manda numeros para um painel de fora, nunca texto

  O painel externo (uma pagina na Vercel) mostra saude da FALAE para quem nao
  esta no jogo: quantas linhas, quantos recados, quanto custa cada rota. NADA
  disto e texto de conversa, e NADA disto e "quem falou com quem" - so
  agregados. O texto de um recado tem um caminho proprio e deliberadamente
  manual, fisico e registrado (ver servidor/core/exportacao.lua); este arquivo
  nao e, e nao pode ser, esse caminho.

  OPCIONAL DE PROPOSITO. Uma central sem /dados/painel.cfg configurado
  continua atendendo exatamente como sempre atendeu - nenhuma rota, nenhum
  laco de rede, nada muda. Enfeite nao pode ameacar quem esta atendendo; e a
  mesma regra que ja vale para o painel de monitor.

  NUNCA DERRUBA A CENTRAL. Toda chamada de rede aqui esta dentro de um pcall.
  Se a Vercel estiver fora do ar, ou o token estiver errado, ou a internet do
  servidor cair - a FALAE continua atendendo pedido por rednet like sempre.
]]

local lib       = dofile("/core/lib.lua")
local json      = lib("json")
local linhas    = lib("linhas")
local recados   = lib("recados")
local denuncias = lib("denuncias")

local telemetria = {}

telemetria.CONFIG = "/dados/painel.cfg"

-- De quanto em quanto tempo manda um snapshot novo. Nao precisa ser rapido -
-- e um painel de saude, nao uma tela de conversa - e um numero baixo demais
-- so gastaria banda do servidor Minecraft e a cota de requisicoes da Vercel.
telemetria.INTERVALO = 30

-- ------------------------------------------------------------------- config

--- Ha um painel configurado nesta central?
function telemetria.configurado()
  return fs.exists(telemetria.CONFIG)
end

--- Le { url=, token= }, ou nil se nao configurado ou corrompido.
function telemetria.lerConfig()
  if not fs.exists(telemetria.CONFIG) then return nil end
  local f = fs.open(telemetria.CONFIG, "r")
  if not f then return nil end
  local t = textutils.unserialize(f.readAll() or "")
  f.close()
  if type(t) ~= "table" or type(t.url) ~= "string" or type(t.token) ~= "string" then
    return nil
  end
  if t.url == "" or t.token == "" then return nil end
  return t
end

--- Grava a configuracao. O token e um segredo de push-so: ele so autoriza
-- mandar numero, nunca ler nada de volta - por isso nao precisa do mesmo
-- cuidado que o PIN de uma linha ou de uma chave.
function telemetria.gravarConfig(url, token)
  url = tostring(url or ""):gsub("^%s+", ""):gsub("%s+$", "")
  token = tostring(token or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if url == "" then return false, "endereco vazio" end
  if token == "" then return false, "token vazio" end

  local dir = fs.getDir(telemetria.CONFIG)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(telemetria.CONFIG, "w")
  if not f then return false, "nao consegui gravar" end
  f.write(textutils.serialize({ url = url, token = token }))
  f.close()
  return true
end

function telemetria.apagarConfig()
  if fs.exists(telemetria.CONFIG) then fs.delete(telemetria.CONFIG) end
end

-- ------------------------------------------------------------------ coletar

--- Monta o snapshot a mandar. Funcao PURA, sem rede - o teste confere a forma
-- exata do que sai sem precisar de http nenhum.
--
-- @param estado central.estado (passado por quem chama - telemetria.lua nao
--        importa central.lua, porque central.lua e quem importa telemetria:
--        um lib("central") daqui criaria um require circular. O mesmo motivo
--        pelo qual painel.lua tambem nunca importa central.)
-- @param custos o que central.custos() devolveu
--
-- SO NUMERO. Nenhum numero de LINHA (nem o seu, nem o de ninguem), nenhum
-- texto de recado, nenhum par "quem falou com quem".
function telemetria.coletar(estado, custos)
  local abertas, vivas, maquinas = linhas.sessoesAbertas()
  local baldes, pico = recados.porHora(12)

  local agora = os.epoch("utc")
  local HORA = 60 * 60 * 1000
  local DIA  = 24 * HORA

  local top = {}
  for i = 1, math.min(6, #(custos or {})) do
    local c = custos[i]
    top[#top + 1] = { rota = c.rota, n = c.n, tempo = c.tempo, media = c.media }
  end

  return {
    v = 1,
    quando = agora,
    linhas = {
      total = linhas.quantas(),
      ativas1h = linhas.ativasDesde(agora - HORA),
      ativas24h = linhas.ativasDesde(agora - DIA),
    },
    sessoes = { abertas = abertas, vivas = vivas, aparelhos = maquinas },
    recados = {
      total = recados.quantos(),
      ultimos5min = recados.quantosDesde(agora - 5 * 60 * 1000),
      ultimaHora = recados.quantosDesde(agora - HORA),
      porHora = baldes,
      pico = pico,
    },
    denuncias = { pendentes = denuncias.quantasPendentes() },
    central = {
      tempoNoAr = estado.desde and math.floor((agora - estado.desde) / 1000) or 0,
      pedidos = estado.pedidos or 0,
      recusas = estado.recusas or 0,
      rapidas = estado.rapidas or 0,
      modem = estado.modem ~= nil,
      custos = top,
    },
  }
end

-- ------------------------------------------------------------------- enviar

--- Manda o snapshot. NUNCA levanta erro - problema de rede aqui e normal, e
-- vira "nao mandei desta vez", nunca uma central que caiu.
--
-- @return true, ou false + motivo
function telemetria.enviar(estado, custos)
  local cfg = telemetria.lerConfig()
  if not cfg then return false, "painel nao configurado" end
  if not http then return false, "a API http esta desligada neste servidor" end

  local corpo = json.codificar(telemetria.coletar(estado, custos))

  local ok, resposta, erro = pcall(http.post, cfg.url, corpo, {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer " .. cfg.token,
  })

  if not ok then return false, tostring(resposta) end
  if not resposta then return false, tostring(erro or "sem resposta") end

  resposta.close()
  telemetria.ultimoEnvio = os.epoch("utc")
  return true
end

return telemetria
