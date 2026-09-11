--[[ console_denuncias - a fila de denuncias. O UNICO lugar onde um recado
  alheio aparece.

  Aqui, e nao no painel, porque aqui e o teclado da central: quem esta
  olhando e a operadora. O painel de parede fica numa sala por onde qualquer
  um passa e so mostra quantas esperam.
]]

local lib = dofile("/core/lib.lua")
local numero    = lib("numero")
local linhas    = lib("linhas")
local recados   = lib("recados")
local bloqueio  = lib("bloqueio")
local denuncias = lib("denuncias")

--- @param console a tabela compartilhada do balcao, para preencher
-- @param ajuda { C=, central=, cabecalho=, linha=, rodape=, perguntar=,
--        avisar=, quando=, exigir= }
return function(console, ajuda)
  local cabecalho, linha, rodape = ajuda.cabecalho, ajuda.linha, ajuda.rodape
  local perguntar, avisar, quando = ajuda.perguntar, ajuda.avisar, ajuda.quando

  --- Mostra quantas vezes aquele numero ja foi denunciado e por quantas
  -- pessoas DIFERENTES - e o que separa briga de dois de um problema de
  -- verdade.
  function console.denuncias()
    -- E aqui que mora o unico texto de recado que a central guarda. Se
    -- alguma tela deste console precisa de chave, e esta.
    if not ajuda.exigir() then return end
    local C = ajuda.C

    local escolhida = 1

    while true do
      local lista = denuncias.pendentes()
      if escolhida > #lista then escolhida = math.max(1, #lista) end

      cabecalho(("denuncias (%d)"):format(#lista))

      if #lista == 0 then
        linha(3, "nenhuma denuncia esperando.", C.fraco)
        linha(5, "Quem recebe algo ruim denuncia", C.fraco)
        linha(6, "pelo proprio telefone, na tecla D.", C.fraco)
        rodape("Q volta")
      else
        local d = lista[escolhida]
        local vezes, pessoas = denuncias.historicoDe(d.sobre)

        linha(3, ("%d de %d"):format(escolhida, #lista), C.fraco)

        linha(5, "sobre    " .. numero.formatar(d.sobre), C.marca)
        local pub = linhas.publico(d.sobre)
        linha(6, "         " .. (pub and pub.nome or "(linha ja apagada)"), C.fraco)

        linha(8, "de       " .. numero.formatar(d.de), C.texto)
        linha(9, "quando   " .. quando(d.quando) .. " atras", C.fraco)

        if vezes > 1 then
          linha(11, ("ja denunciado %d vezes, por %d pessoa(s)"):format(vezes, pessoas),
                pessoas > 1 and C.ruim or C.aviso)
        else
          linha(11, "primeira denuncia sobre esse numero", C.fraco)
        end

        -- o recado, que e o motivo de esta tela existir
        local w = term.getSize()
        linha(13, "o recado:", C.fraco)
        linha(14, "  " .. tostring(d.texto or ""):sub(1, w - 3), C.texto)

        rodape("setas  A arquiva  X cassa a linha  Q volta")
      end

      local _, tecla = os.pullEvent("key")
      if tecla == keys.q or tecla == keys.backspace then return end

      if #lista > 0 then
        local d = lista[escolhida]

        if tecla == keys.down and escolhida < #lista then
          escolhida = escolhida + 1
        elseif tecla == keys.up and escolhida > 1 then
          escolhida = escolhida - 1

        elseif tecla == keys.a then
          denuncias.resolver(d.n, "arquivada")
          ajuda.central.log(("denuncia %d arquivada"):format(d.n), C.fraco)

        elseif tecla == keys.x then
          local certeza = perguntar(("cassar %s e apagar a conversa dela? s/N:")
                                    :format(numero.formatar(d.sobre)))
          if certeza:lower() == "s" then
            local apagados = recados.esquecer(d.sobre)
            bloqueio.esquecer(d.sobre)
            -- resolve ANTES de esquecer: esquecer apaga a denuncia junto com
            -- a linha, e resolver depois nao acharia mais nada para marcar
            denuncias.resolver(d.n, "linha cassada")
            denuncias.esquecer(d.sobre)
            linhas.remover(d.sobre)
            ajuda.central.log(("linha %s cassada por denuncia"):format(
                        numero.formatar(d.sobre)), C.aviso)
            avisar(("linha apagada, com %d recado(s)"):format(apagados), C.bom)
          end
        end
      end
    end
  end
end
