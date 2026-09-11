--[[ console_linhas - as telas do balcao que mexem em linha: listar, zerar
  PIN, cassar. Todas atras da chave, todas tocando linhas/recados/bloqueio.
]]

local lib = dofile("/core/lib.lua")
local numero   = lib("numero")
local linhas   = lib("linhas")
local recados  = lib("recados")
local bloqueio = lib("bloqueio")
local denuncias = lib("denuncias")

--- @param console a tabela compartilhada do balcao, para preencher
-- @param ajuda { C=, central=, cabecalho=, linha=, rodape=, perguntar=,
--        avisar=, quando=, exigir= }
return function(console, ajuda)
  local cabecalho, linha, rodape = ajuda.cabecalho, ajuda.linha, ajuda.rodape
  local perguntar, avisar, quando = ajuda.perguntar, ajuda.avisar, ajuda.quando

  --- A lista de linhas nao e publica: sao os numeros e os nomes de todo mundo
  -- que tem linha, num so lugar. Ver isso ja e operar.
  function console.linhas()
    if not ajuda.exigir() then return end
    local C = ajuda.C

    local lista = linhas.lista()
    local topo = 1
    local _, h = term.getSize()
    local cabem = h - 4

    while true do
      cabecalho(("linhas (%d)"):format(#lista))
      if #lista == 0 then
        linha(3, "nenhuma linha ainda.", C.fraco)
      end
      for i = 0, cabem - 1 do
        local l = lista[topo + i]
        if not l then break end
        local marca = l.semPin and " [sem PIN]" or ""
        linha(3 + i, ("%s  %-16s %s%s"):format(
              numero.formatar(l.numero), l.nome, quando(l.visto), marca),
              l.semPin and C.aviso or C.texto)
      end
      rodape("setas rolam   Q volta")

      local _, tecla = os.pullEvent("key")
      if tecla == keys.q or tecla == keys.backspace then return end
      if tecla == keys.down and topo + cabem <= #lista then topo = topo + 1 end
      if tecla == keys.up and topo > 1 then topo = topo - 1 end
    end
  end

  function console.zerarPin()
    if not ajuda.exigir() then return end
    local C = ajuda.C

    local texto = perguntar("numero da linha:")
    if texto == "" then return end

    local canonico = numero.canonico(texto)
    if not canonico then
      return avisar("numero invalido", C.ruim)
    end

    local pub = linhas.publico(canonico)
    if not pub then
      return avisar("essa linha nao existe", C.ruim)
    end

    local codigo = linhas.zerarPin(canonico)
    if not codigo then
      return avisar("nao consegui zerar", C.ruim)
    end

    -- O codigo NAO vai para o log. O log rola na tela da central e fica; o
    -- codigo e para ser dito uma vez, para a pessoa que esta na frente.
    ajuda.central.log(("PIN zerado em %s no balcao"):format(numero.formatar(canonico)), C.aviso)
    avisar(("%s (%s): diga o codigo %s - vale 24h"):format(
           numero.formatar(canonico), pub.nome, codigo), C.bom)
  end

  function console.cassar()
    if not ajuda.exigir() then return end
    local C = ajuda.C

    local texto = perguntar("cassar qual numero:")
    if texto == "" then return end

    local canonico = numero.canonico(texto)
    if not canonico or not linhas.publico(canonico) then
      return avisar("essa linha nao existe", C.ruim)
    end

    local pub = linhas.publico(canonico)
    local certeza = perguntar(("apagar %s (%s) e a conversa dela? s/N:"):format(
                              numero.formatar(canonico), pub.nome))
    if certeza:lower() ~= "s" then return end

    local apagados = recados.esquecer(canonico)
    bloqueio.esquecer(canonico)
    -- as denuncias vao junto, dos dois lados: uma denuncia carrega um
    -- recado, e deixa-la para tras guardaria conversa de uma linha que a
    -- FALAE disse ter apagado
    denuncias.esquecer(canonico)
    linhas.remover(canonico)

    ajuda.central.log(("linha %s cassada no balcao"):format(numero.formatar(canonico)), C.aviso)
    avisar(("linha apagada, com %d recado(s)"):format(apagados), C.bom)
  end
end
