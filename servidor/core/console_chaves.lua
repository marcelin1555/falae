--[[ console_chaves - as telas do balcao que sao literalmente o sistema
  chave/chaveiro/tranca visto de dentro da central: listar, emitir, revogar.
]]

local lib = dofile("/core/lib.lua")
local chave    = lib("chave")
local chaveiro = lib("chaveiro")
local tranca   = lib("tranca")

--- @param console a tabela compartilhada do balcao, para preencher
-- @param ajuda { C=, central=, cabecalho=, linha=, rodape=, perguntar=,
--        avisar=, quando=, exigir=, trancar=, sessao= }
return function(console, ajuda)
  local cabecalho, linha, rodape = ajuda.cabecalho, ajuda.linha, ajuda.rodape
  local perguntar, avisar, quando = ajuda.perguntar, ajuda.avisar, ajuda.quando

  --- As chaves que esta central aceita.
  --
  -- Nao mostra segredo nenhum porque nao tem: o chaveiro guarda impressao. O
  -- que da para ver e o que serve para decidir - qual disquete, que papel,
  -- quando foi usada pela ultima vez.
  function console.chaves()
    -- Gatilhada como a lista de linhas: ver quais disquetes abrem esta
    -- central nao deixa ninguem entrar (id de disquete nao se fabrica), mas e
    -- a planta da fechadura, e planta de fechadura fica com quem tem a chave.
    if not ajuda.exigir() then return end

    while true do
      cabecalho("chaves")
      local C = ajuda.C
      local lista = chaveiro.listar()
      local sessao = ajuda.sessao()

      if #lista == 0 then
        linha(3, "nenhuma chave - central sem dono", C.ruim)
      else
        linha(3, ("disquete  papel     ultima vez  chave"), C.fraco)
        for i, k in ipairs(lista) do
          local marca = (sessao and tostring(sessao.disco) == tostring(k.disco))
                        and " *" or "  "
          linha(3 + i, ("#%-8s %-9s %-11s %s%s"):format(
                tostring(k.disco), k.papel, quando(k.ultimoUso), k.nome, marca),
                k.travadaAte and k.travadaAte > os.epoch("utc") and C.ruim or C.texto)
        end
      end

      rodape("N nova chave   B revogar   qualquer outra volta")
      local _, tecla = os.pullEvent("key")

      if tecla == keys.n then
        console.emitirChave()
      elseif tecla == keys.b then
        console.revogarChave()
      else
        return
      end
    end
  end

  --- Emite uma chave nova no disquete que estiver no drive.
  function console.emitirChave()
    if not ajuda.exigir() then return end
    local C = ajuda.C

    local id, motivo = tranca.disco()
    if not id then return avisar(motivo, C.ruim) end

    cabecalho("chave nova")
    linha(3, "disquete #" .. tostring(id), C.marca)
    linha(5, "papel:", C.fraco)
    linha(6, "  central  abre a central e o balcao", C.fraco)
    linha(7, "  loja     abre so o computador da loja", C.fraco)

    local papel = perguntar("papel (central/loja):")
    if not chave.PAPEIS[papel] then return avisar("papel desconhecido", C.ruim) end

    local nome = perguntar("nome da chave:")
    if nome == "" then nome = papel end

    local pin = tranca.lerPin("PIN da chave nova:")
    if not pin then return end
    local outra = tranca.lerPin("de novo:")
    if outra ~= pin then return avisar("os dois PINs nao batem", C.ruim) end

    local k, erro = tranca.emitir(nome, papel, pin)
    if not k then return avisar(tostring(erro), C.ruim) end

    ajuda.central.log(("chave %s emitida no disquete #%s"):format(nome, tostring(id)), C.bom)
    avisar("chave gravada no disquete #" .. tostring(id), C.bom)
  end

  --- Tira uma chave da lista. O disquete continua existindo; ele so deixa de
  -- abrir esta central - que e o que se quer quando um sumiu.
  function console.revogarChave()
    if not ajuda.exigir() then return end
    local C = ajuda.C

    local texto = perguntar("revogar qual disquete (numero):")
    if texto == "" then return end

    local ok, motivo = chaveiro.remover(texto)
    if not ok then return avisar(tostring(motivo or "nao achei essa chave"), C.ruim) end

    -- Revogar a propria chave que abriu o balcao fecha o balcao: continuar
    -- destrancado por uma chave que acabou de deixar de valer seria mentira.
    local sessao = ajuda.sessao()
    if sessao and tostring(sessao.disco) == tostring(texto) then
      ajuda.trancar()
    end

    ajuda.central.log(("chave do disquete #%s revogada"):format(texto), C.aviso)
    avisar("revogada", C.bom)
  end
end
