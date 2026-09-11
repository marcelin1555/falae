--[[ console_telemetria - liga, desliga e mostra o status do painel externo
  (numeros, nunca texto - ver servidor/core/telemetria.lua).

  Atras da chave pelo mesmo motivo do resto: o token que vai aqui autoriza
  mandar dados desta central para fora do jogo, e quem configura isso precisa
  provar que e a operadora.
]]

local lib = dofile("/core/lib.lua")
local telemetria = lib("telemetria")

--- @param console a tabela compartilhada do balcao, para preencher
-- @param ajuda { C=, central=, cabecalho=, linha=, rodape=, perguntar=,
--        avisar=, exigir= }
return function(console, ajuda)
  local cabecalho, linha, rodape = ajuda.cabecalho, ajuda.linha, ajuda.rodape
  local perguntar, avisar = ajuda.perguntar, ajuda.avisar

  function console.telemetria()
    if not ajuda.exigir() then return end
    local central = ajuda.central

    while true do
      cabecalho("painel externo")
      local C = ajuda.C
      local cfg = telemetria.lerConfig()

      if not cfg then
        linha(3, "nenhum painel configurado.", C.fraco)
        linha(5, "A central manda so NUMEROS -", C.fraco)
        linha(6, "linhas, recados, saude de rede.", C.fraco)
        linha(7, "Nunca texto de conversa.", C.fraco)
        rodape("N configurar   Q volta")
      else
        linha(3, "endereco:", C.fraco)
        linha(4, "  " .. cfg.url:sub(1, 45), C.texto)
        linha(6, ("manda a cada %ds"):format(telemetria.INTERVALO), C.fraco)

        if telemetria.ultimoEnvio then
          local ha = math.floor((os.epoch("utc") - telemetria.ultimoEnvio) / 1000)
          linha(7, ("ultimo envio: ha %ds"):format(ha), C.bom)
        else
          linha(7, "ainda nao mandou nada nesta sessao", C.fraco)
        end

        rodape("N trocar   B desligar   T testar agora   Q volta")
      end

      local _, tecla = os.pullEvent("key")
      if tecla == keys.q or tecla == keys.backspace then return end

      if tecla == keys.n then
        console.configurarTelemetria()
      elseif tecla == keys.b and cfg then
        telemetria.apagarConfig()
        central.log("painel externo desligado", C.fraco)
        avisar("desligado", C.bom)
      elseif tecla == keys.t and cfg then
        avisar("mandando...", C.fraco)
        local ok, motivo = telemetria.enviar(central.estado, central.custos())
        if ok then
          avisar("deu certo", C.bom)
        else
          avisar(tostring(motivo), C.ruim)
        end
      end
    end
  end

  function console.configurarTelemetria()
    cabecalho("painel externo")
    local C = ajuda.C
    linha(3, "cole o endereco que a Vercel deu,", C.fraco)
    linha(4, "e o token de push (nao a chave da", C.fraco)
    linha(5, "IA - esse token e so desta central).", C.fraco)

    local url = perguntar("endereco (https://...):")
    if url == "" then return end
    local token = perguntar("token:")
    if token == "" then return end

    local ok, erro = telemetria.gravarConfig(url, token)
    if not ok then return avisar(tostring(erro), C.ruim) end

    ajuda.central.log("painel externo configurado", C.bom)
    avisar("gravado - o proximo boot ja manda numeros", C.bom)
  end
end
