--[[ protocolo - a lingua da rede da FALAE

  Todo trafego passa por UM protocolo rednet ("falae-net") e um envelope unico.
  O roteamento acontece DENTRO do envelope, pelo campo "servico" - nao por
  protocolos rednet diferentes. Assim a central tem um unico ponto de escuta e,
  principalmente, um unico lugar onde a sessao e conferida: nao da para
  esquecer de proteger uma rota nova.

  Pedido:
    { v=1, id=7, servico="msg", acao="enviar", token="a3f...", dados={} }

  Resposta:
    { v=1, id=7, ok=true,  dados={...} }
    { v=1, id=7, ok=false, erro="sessao expirada" }

  O "id" e um numero por pedido e volta igual na resposta. Sem ele, uma
  resposta atrasada de um pedido anterior seria lida como resposta do pedido
  atual - o que acontece de verdade em rede wireless de longa distancia.

  A diferenca para a rede da Expresso Labs, e o motivo de este arquivo existir
  separado: la o token identifica um COMPUTADOR e mora no disco dele para
  sempre. Aqui o token e uma SESSAO de uma linha, e a mesma linha pode estar em
  outro aparelho amanha. Sao dois desenhos de identidade diferentes, e mistura-
  los num protocolo so seria um convite a confundir aparelho com pessoa.
]]

local protocolo = {}

protocolo.REDE   = "falae-net"
protocolo.HOST   = "falae-central"
protocolo.VERSAO = 1

-- Rotas que respondem sem sessao. E por elas que alguem que ainda nao tem
-- linha nenhuma consegue chegar na FALAE. Qualquer outra exige token.
--
-- A FALAE e aberta a qualquer jogador de proposito: nao existe senha de
-- instalacao da empresa aqui, porque a linha e o produto. Quem chega compra
-- uma; quem ja tem, entra.
protocolo.SEM_SESSAO = {
  ["central.ping"] = true,
  ["linha.criar"]  = true,
  ["linha.entrar"] = true,
}

-- Mensagem rednet grande demais e perdida sem aviso. Nada na FALAE chega
-- perto disso (um recado tem 160 caracteres), mas a constante fica aqui para
-- o dia em que alguem mandar uma lista longa.
protocolo.PEDACO = 8000

local proximo = 0

function protocolo.novoId()
  proximo = proximo + 1
  return proximo
end

function protocolo.pedido(servico, acao, dados, token)
  return {
    v       = protocolo.VERSAO,
    id      = protocolo.novoId(),
    servico = servico,
    acao    = acao,
    token   = token,
    dados   = dados or {},
  }
end

function protocolo.ok(id, dados)
  return { v = protocolo.VERSAO, id = id, ok = true, dados = dados or {} }
end

function protocolo.erro(id, msg)
  return { v = protocolo.VERSAO, id = id, ok = false, erro = tostring(msg) }
end

--- "servico.acao" - a chave usada na tabela de rotas e no medidor de custo.
function protocolo.rota(m)
  return tostring(m.servico or "?") .. "." .. tostring(m.acao or "?")
end

--- Isto tem cara de pedido? Vale para qualquer lixo que chegue pelo modem: a
-- central nao pode confiar em nada que veio da rede.
function protocolo.valido(m)
  if type(m) ~= "table" then return false end
  if m.v ~= protocolo.VERSAO then return false end
  if type(m.id) ~= "number" then return false end
  if type(m.servico) ~= "string" or type(m.acao) ~= "string" then return false end
  if m.dados ~= nil and type(m.dados) ~= "table" then return false end
  if m.token ~= nil and type(m.token) ~= "string" then return false end
  return true
end

--- Abre TODOS os modems do computador, com fio e sem fio.
--
-- O rednet transmite por todo modem aberto, entao abrir os dois tipos deixa a
-- maquina alcancavel pelos dois caminhos ao mesmo tempo. Nao ha custo em abrir
-- os dois - o modem so escuta.
--
-- No pocket isto quase sempre acha um so, o Ender Modem das costas. E o
-- suficiente: alcance ilimitado e atravessa dimensao, que e o que faz a FALAE
-- funcionar do outro lado do mapa.
--
-- @return lista { {nome=, semFio=}, ... }, ou nil + motivo
function protocolo.abrirModems()
  local abertos = {}
  for _, nome in ipairs(peripheral.getNames()) do
    if peripheral.getType(nome) == "modem" then
      local m = peripheral.wrap(nome)
      local ok, semFio = pcall(function() return m.isWireless() end)
      if ok then
        if not rednet.isOpen(nome) then pcall(rednet.open, nome) end
        if rednet.isOpen(nome) then
          abertos[#abertos + 1] = { nome = nome, semFio = semFio and true or false }
        end
      end
    end
  end

  if #abertos == 0 then
    return nil, "sem modem - o aparelho precisa de um Ender Modem nas costas"
  end

  -- sem fio primeiro: e o caminho que alcanca o mapa inteiro
  table.sort(abertos, function(a, b)
    if a.semFio ~= b.semFio then return a.semFio end
    return a.nome < b.nome
  end)
  return abertos
end

function protocolo.resumoModems(lista)
  if not lista or #lista == 0 then return "sem modem" end
  local nomes = {}
  for _, m in ipairs(lista) do
    nomes[#nomes + 1] = m.nome .. (m.semFio and "" or " (cabo)")
  end
  return table.concat(nomes, " + ")
end

--- Atalho de quem so quer saber se deu certo.
function protocolo.abrirModem()
  local lista, erro = protocolo.abrirModems()
  if not lista then return nil, erro end
  return protocolo.resumoModems(lista), nil, lista
end

--- Soma de verificacao de um texto (djb2).
function protocolo.soma(texto)
  local h = 5381
  for i = 1, #texto do
    h = (h * 33 + texto:byte(i)) % 4294967296
  end
  return h
end

return protocolo
