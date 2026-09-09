--[[ fnet - a linha direta do telefone com a central da FALAE

  Todo pedido do aparelho passa por aqui. Nenhuma tela mexe em rednet na mao:
  as tres coisas chatas de rede estao resolvidas neste arquivo e so aqui.

    descoberta   o id da central vem de rednet.lookup, nunca fixo no codigo.
                 A central pode ser reconstruida, mudar de lugar, ganhar id
                 novo - os aparelhos acham do mesmo jeito.

    perda        wireless a longa distancia perde pacote. Todo pedido tem
                 prazo e e repetido algumas vezes antes de desistir.

    resposta trocada  cada pedido leva um numero; resposta com numero
                 diferente e de um pedido antigo que chegou atrasado e vai
                 para o lixo. Sem isso, o telefone mostraria a resposta de
                 outra pergunta e ninguem entenderia por que.

  O QUE ELE GUARDA EM DISCO e so a sessao: numero, nome e token. O PIN nunca e
  gravado - se fosse, quem pegasse o pocket de alguem no chao teria a linha da
  pessoa junto, e o PIN existiria para nada.
]]

-- Uma instancia por aparelho: quem guarda "onde esta a central" e este
-- modulo, e duas copias dele significariam dois rednet.lookup no boot - que
-- bloqueiam cerca de dois segundos cada. Quem garante a copia unica e o
-- /carregar.lua; nenhum arquivo do telefone deve chamar dofile direto.
local carregar = dofile("/carregar.lua")
local protocolo = carregar("protocolo")

local fnet = {}

fnet.ARQUIVO    = "/.falae"
fnet.TENTATIVAS = 3
fnet.PRAZO      = 2       -- segundos por tentativa

fnet.central = nil        -- id descoberto, em memoria
fnet.modem   = nil

-- ------------------------------------------------------------------ sessao

--- Le a sessao do disco: { numero=, nome=, token= }
function fnet.sessao()
  if not fs.exists(fnet.ARQUIVO) then return nil end
  local f = fs.open(fnet.ARQUIVO, "r")
  if not f then return nil end
  local t = textutils.unserialize(f.readAll() or "")
  f.close()
  if type(t) ~= "table" or type(t.token) ~= "string" then return nil end
  return t
end

function fnet.guardarSessao(t)
  local f = fs.open(fnet.ARQUIVO, "w")
  if not f then return false end
  f.write(textutils.serialize(t))
  f.close()
  return true
end

function fnet.esquecerSessao()
  if fs.exists(fnet.ARQUIVO) then fs.delete(fnet.ARQUIVO) end
end

function fnet.entrou()
  return fnet.sessao() ~= nil
end

-- -------------------------------------------------------------------- rede

--- Abre o modem e acha a central. Chame uma vez no comeco.
-- @return id da central, ou nil + motivo
function fnet.conectar(silencioso)
  local nome, erro = protocolo.abrirModem()
  if not nome then return nil, erro end
  fnet.modem = nome

  if fnet.central then return fnet.central end

  if not silencioso then io.write("procurando a FALAE... ") end
  local id = rednet.lookup(protocolo.REDE, protocolo.HOST)
  if not silencioso then print(id and ("achei: #" .. id) or "nao achei") end
  if not id then return nil, "a FALAE nao respondeu - sem sinal aqui" end

  fnet.central = id
  return id
end

--- Espera a resposta do pedido numero <id>, descartando o que nao for dele.
local function esperar(id, prazo)
  local fim = os.clock() + prazo
  while true do
    local resto = fim - os.clock()
    if resto <= 0 then return nil end
    local de, m = rednet.receive(protocolo.REDE, resto)
    if de == nil then return nil end
    if de == fnet.central and type(m) == "table" and m.id == id and m.ok ~= nil then
      return m
    end
  end
end

--- Faz um pedido a central.
-- @return true, dados   ou   false, motivo
function fnet.pedir(servico, acao, dados, semSessao)
  local token
  if not semSessao then
    local s = fnet.sessao()
    token = s and s.token or nil
  end

  for tentativa = 1, fnet.TENTATIVAS do
    if not fnet.central then
      local id = fnet.conectar(true)
      if not id then
        if tentativa == fnet.TENTATIVAS then return false, "sem sinal" end
        sleep(1)
      end
    end

    if fnet.central then
      local m = protocolo.pedido(servico, acao, dados, token)
      rednet.send(fnet.central, m, protocolo.REDE)
      local r = esperar(m.id, fnet.PRAZO)
      if r then
        if r.ok then return true, r.dados end
        return false, r.erro or "pedido recusado"
      end
      -- silencio: pode ser pacote perdido, mas tambem central que sumiu.
      -- esquece o id e procura de novo na proxima volta.
      fnet.central = nil
    end
  end

  return false, "a FALAE nao respondeu"
end

-- ----------------------------------------------------------------- atalhos

function fnet.ping()
  return fnet.pedir("central", "ping", {}, true)
end

--- Tira uma linha nova. O numero e sorteado pela central.
function fnet.criarLinha(nome, pin)
  local ok, r = fnet.pedir("linha", "criar", { nome = nome, pin = pin }, true)
  if not ok then return false, r end
  fnet.guardarSessao({ numero = r.linha.numero, nome = r.linha.nome, token = r.token })
  return true, r.linha
end

--- Entra numa linha que ja existe.
function fnet.entrar(numeroTexto, pin)
  local ok, r = fnet.pedir("linha", "entrar",
                           { numero = numeroTexto, pin = pin }, true)
  if not ok then return false, r end
  fnet.guardarSessao({ numero = r.linha.numero, nome = r.linha.nome, token = r.token })
  return true, r.linha
end

--- Define um PIN novo numa linha que passou pelo balcao.
--
-- O codigo vem do atendimento, dito de viva voz. Ele existe para esta rota nao
-- entregar a linha para o primeiro que digitar o numero: ela e sem sessao, e
-- sem sessao quer dizer qualquer um com um modem.
function fnet.definirPin(numeroTexto, codigo, pin)
  local ok, r = fnet.pedir("linha", "entrar",
                           { numero = numeroTexto, pin = pin,
                             codigo = codigo, definir = true }, true)
  if not ok then return false, r end
  fnet.guardarSessao({ numero = r.linha.numero, nome = r.linha.nome, token = r.token })
  return true, r.linha
end

--- Sai da linha neste aparelho.
--
-- Apaga a sessao do disco mesmo se a central nao responder. Sem isso, sair sem
-- sinal deixaria a linha da pessoa aberta no aparelho que ela acabou de
-- emprestar - e "sair" que as vezes nao sai e pior que nao ter o botao.
function fnet.sair()
  fnet.pedir("linha", "sair", {})
  fnet.esquecerSessao()
  return true
end

function fnet.eu()
  return fnet.pedir("linha", "eu", {})
end

function fnet.trocarNome(nome)
  return fnet.pedir("linha", "nome", { nome = nome })
end

function fnet.trocarPin(antigo, novo)
  return fnet.pedir("linha", "pin", { antigo = antigo, novo = novo })
end

function fnet.buscar(numeroTexto)
  return fnet.pedir("linha", "buscar", { numero = numeroTexto })
end

function fnet.enviar(para, texto)
  return fnet.pedir("msg", "enviar", { para = para, texto = texto })
end

--- O que houve desde o recado <desde>. A resposta pode vir com nada=true, que
-- e o caso comum e NAO e erro.
function fnet.novidades(desde, limite)
  return fnet.pedir("msg", "novidades", { desde = desde or 0, limite = limite })
end

function fnet.conversa(com, limite)
  return fnet.pedir("msg", "conversa", { com = com, limite = limite })
end

--- Denuncia uma conversa.
--
-- Manda so o numero. O texto quem escolhe e a central, do historico dela - o
-- aparelho nao tem como dizer o que o outro escreveu.
function fnet.denunciar(numeroTexto)
  return fnet.pedir("denuncia", "criar", { numero = numeroTexto })
end

function fnet.bloqueados()
  return fnet.pedir("bloq", "listar", {})
end

function fnet.bloquear(numeroTexto)
  return fnet.pedir("bloq", "por", { numero = numeroTexto })
end

function fnet.desbloquear(numeroTexto)
  return fnet.pedir("bloq", "tirar", { numero = numeroTexto })
end

return fnet
