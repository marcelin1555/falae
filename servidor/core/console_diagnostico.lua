--[[ console_diagnostico - as tres telas do balcao que NAO pedem chave: sao
  leitura, sobre a propria maquina, nunca sobre uma pessoa.
]]

--- @param console a tabela compartilhada do balcao, para preencher
-- @param ajuda { C=, central=, cabecalho=, linha=, rodape= }
return function(console, ajuda)
  local cabecalho, linha, rodape = ajuda.cabecalho, ajuda.linha, ajuda.rodape

  --- Os monitores: o que a central achou, e a troca entre eles.
  --
  -- A lista existe para responder dentro do jogo a pergunta que de fora nao
  -- da para responder: os dois monitores estao mesmo funcionando? Se
  -- aparecer um so, quase sempre e uma destas duas coisas - os dois blocos
  -- encostados e alinhados viraram UM monitor (o CC funde monitores
  -- adjacentes), ou o segundo nao alcanca a central e precisa de um Wired
  -- Modem com cabo.
  function console.telas()
    while true do
      cabecalho("monitores")
      local C = ajuda.C

      if not console.painel then
        linha(3, "os modulos de tela nao foram", C.aviso)
        linha(4, "instalados nesta central.", C.aviso)
        linha(6, "rode o instalador de novo e", C.fraco)
        linha(7, "aceite a parte visual.", C.fraco)
        rodape("Q volta")
      else
        local lista = console.painel.diagnostico()

        if #lista == 0 then
          linha(3, "nenhum monitor encontrado.", C.aviso)
          linha(5, "O monitor precisa encostar na", C.fraco)
          linha(6, "central, ou chegar nela por um", C.fraco)
          linha(7, "Wired Modem com cabo.", C.fraco)
        else
          linha(3, ("%d monitor(es) ligado(s):"):format(#lista), C.marca)
          local y = 5
          for _, m in ipairs(lista) do
            linha(y, ("  %s"):format(m.nome), C.texto)
            linha(y + 1, ("    mostra: %s"):format(m.papel), C.fraco)
            linha(y + 2, ("    %dx%d, escala %s"):format(
                  m.colunas, m.linhas, tostring(m.escala or "?")), C.fraco)
            if m.papel == "marca" then
              linha(y + 3, ("    nome: %s"):format(
                    m.nomeDesenhado and "desenhado" or "em caracteres"), C.fraco)
              y = y + 1
            end
            if m.erro then
              linha(y + 3, "    ERRO: " .. m.erro:sub(1, 28), C.ruim)
              y = y + 1
            end
            y = y + 4
          end

          if #lista == 1 then
            local _, h = term.getSize()
            linha(h - 3, "so um? os dois blocos encostados", C.aviso)
            linha(h - 2, "viram UM monitor. Separe-os.", C.aviso)
          end
        end

        rodape(#lista >= 2 and "T troca os dois   Q volta" or "Q volta")
      end

      local _, tecla = os.pullEvent("key")
      if tecla == keys.q or tecla == keys.backspace then return end
      if tecla == keys.t and console.painel and console.painel.quantas() >= 2 then
        console.painel.inverter()
      end
    end
  end

  --- O que cada rota esta custando. Sem isto, "a FALAE esta lenta" e uma
  -- sensacao; com isto e uma linha dizendo qual rota e quanto.
  function console.custos()
    cabecalho("custo por rota")
    local C = ajuda.C
    local central = ajuda.central
    local lista = central.custos()

    if #lista == 0 then
      linha(3, "nenhum pedido ainda.", C.fraco)
    else
      linha(3, ("%-16s %7s %9s %9s"):format("rota", "vezes", "total", "media"), C.fraco)
      local _, h = term.getSize()
      for i = 1, math.min(#lista, h - 6) do
        local c = lista[i]
        linha(4 + i - 1, ("%-16s %7d %8.3fs %8.4fs"):format(
              c.rota:sub(1, 16), c.n, c.tempo, c.media))
      end
    end

    local e = central.estado
    local total = e.pedidos + e.recusas
    local _, h = term.getSize()
    if total > 0 then
      linha(h - 2, ("%d%% dos pedidos foram 'nada mudou'"):format(
            math.floor(e.rapidas / total * 100)), C.marca)
    end

    rodape("Q volta")
    repeat
      local _, tecla = os.pullEvent("key")
    until tecla == keys.q or tecla == keys.backspace
  end

  function console.verLog()
    cabecalho("log")
    local C = ajuda.C
    local e = ajuda.central.estado
    local _, h = term.getSize()
    local cabem = h - 4
    local inicio = math.max(1, #e.log - cabem + 1)
    for i = inicio, #e.log do
      local reg = e.log[i]
      linha(3 + i - inicio, (" %s %s"):format(reg.hora, reg.texto), reg.cor)
    end
    if #e.log == 0 then linha(3, "nada aconteceu ainda.", C.fraco) end
    rodape("Q volta")
    repeat
      local _, tecla = os.pullEvent("key")
    until tecla == keys.q or tecla == keys.backspace
  end
end
