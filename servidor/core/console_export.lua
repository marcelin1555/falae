--[[ console_export - exportar uma conversa para o disquete, por ordem
  judicial.

  E A UNICA TELA QUE TIRA TEXTO DE RECADO DA CENTRAL PARA FORA - e ela tira
  para um DISQUETE, nunca para a rede. Nao existe um botao "mandar pelo
  rednet" aqui, nem vai existir: o texto sai fisicamente com quem tem a
  chave, e so depois de dizer por que.
]]

local lib = dofile("/core/lib.lua")
local tranca     = lib("tranca")
local exportacao = lib("exportacao")

--- @param console a tabela compartilhada do balcao, para preencher
-- @param ajuda { C=, central=, cabecalho=, linha=, rodape=, perguntar=,
--        avisar=, exigir=, sessao= }
return function(console, ajuda)
  local cabecalho, linha, rodape = ajuda.cabecalho, ajuda.linha, ajuda.rodape
  local perguntar, avisar = ajuda.perguntar, ajuda.avisar

  --- Atras da mesma chave que tranca denuncia e cassacao. O motivo e
  -- obrigatorio e fica gravado para sempre em exportacao.LOG, mesmo se a
  -- gravacao no disquete falhar depois - o rastro e do PEDIDO, nao do
  -- sucesso da copia.
  function console.exportarJudicial()
    if not ajuda.exigir() then return end
    local C = ajuda.C

    cabecalho("exportacao judicial")
    linha(3, "O texto sai so para um disquete.", C.fraco)
    linha(4, "Nunca pela rede. O pedido fica no", C.fraco)
    linha(5, "log de auditoria para sempre.", C.fraco)

    local numeroA = perguntar("numero (obrigatorio):")
    if numeroA == "" then return end

    local numeroB = perguntar("com este numero (vazio = tudo dele):")

    local motivo = perguntar("motivo (obrigatorio, ex: processo 123):")
    if motivo == "" then return avisar("sem motivo, nao exporta", C.ruim) end

    local id, motivoDrive, d = tranca.disco()
    if not id then return avisar(motivoDrive, C.ruim) end

    local sessao = ajuda.sessao()
    local texto, erro = exportacao.montar(numeroA, numeroB, motivo,
                                          sessao and sessao.nome or "?")
    if not texto then return avisar(tostring(erro), C.ruim) end

    local mp = d.getMountPath()
    local arquivo = fs.combine(mp, exportacao.nomeArquivo())
    local f = fs.open(arquivo, "w")
    if not f then
      return avisar("registrei o pedido, mas nao gravei no disquete", C.aviso)
    end
    f.write(texto)
    f.close()

    ajuda.central.log(("exportacao judicial: %s (motivo: %s)"):format(
                numeroA, motivo:sub(1, 40)), C.aviso)
    avisar("gravado no disquete #" .. tostring(id), C.bom)
  end
end
