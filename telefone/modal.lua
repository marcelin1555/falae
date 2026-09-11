--[[ modal - um dialogo de um ou mais campos, com toque e teclado

  perguntar() (numero de telefone, nome de contato, "s/N" de confirmacao) e
  perguntarPin() (PIN atual + PIN novo) eram duas copias quase identicas do
  mesmo desenho - barra "FALAE", campo(s) com marcador/valor, barra CONFIRMAR
  verde, link cancelar - e da mesma maquina de estado (Tab troca foco, Enter
  avanca/confirma, toque nas mesmas tres areas). modal.abrir e o primitivo de
  onde as duas nascem: um so campo e o caso simples, dois ou mais e so mais
  uma volta no mesmo laco.
]]

local carregar = dofile("/carregar.lua")
local janela = carregar("janela")
local campo  = carregar("campo")

local modal = {}

--- @param destino a tela onde desenhar (term real, ou window de teste)
-- @param C as cores de app.lua
-- @param especificacao lista de campos, na ordem em que aparecem:
--        { { rotulo =, opcoes = }, ... }
--        opcoes e o mesmo de campo.novo(); um marcador nela vira o texto
--        cinza que aparece com o campo vazio (so faz sentido com 1 campo so -
--        com varios, o vazio fica em branco, como perguntarPin ja fazia).
--        Um titulo opcional (especificacao.titulo) desenha uma segunda linha
--        abaixo da barra, para quando o dialogo precisa de um nome (ex.:
--        "Trocar PIN").
-- @return lista com o valor de cada campo, na mesma ordem, ou nil se cancelou
function modal.abrir(destino, C, especificacao)
  local n = #especificacao
  local w, h = destino.getSize()
  local j = janela.nova(destino, 1, 1, w, h)

  local campos = {}
  for i, spec in ipairs(especificacao) do
    campos[i] = campo.novo(spec.opcoes)
  end

  -- A mesma conta de espacamento nos dois formatos antigos: um campo so
  -- comeca na linha 5 (ou mais alto, se a tela for baixa); cada campo a mais
  -- empurra 4 linhas, o espaco que um rotulo + campo ocupam.
  local yBase = math.min(5, h - 5 - 4 * (n - 1))
  local function yDoCampo(i) return yBase + 4 * (i - 1) end
  local yConfirmar = yDoCampo(n) + 3
  local yCancelar = yDoCampo(n) + 5

  local foco = 1
  local function ativo() return campos[foco] end

  while true do
    j:limpar(C.fundo)
    j:barra(1, " FALAE", "", colors.black, C.marca)
    if especificacao.titulo then
      j:texto(2, 2, especificacao.titulo, C.fraco, C.fundo)
    end

    for i, spec in ipairs(especificacao) do
      local y = yDoCampo(i)
      j:texto(2, y - 1, spec.rotulo, C.fraco, C.fundo)

      local visivel = campo.visivel(campos[i])
      local marcador = spec.opcoes and spec.opcoes.marcador
      local mostrar, cor
      if visivel == "" and marcador then
        mostrar, cor = marcador, C.fraco
      else
        mostrar, cor = visivel, C.texto
      end
      local fundoCampo = (foco == i) and C.entrada or C.selecao
      j:linha(y, " " .. janela.encher(mostrar, w - 2), cor, fundoCampo)
    end

    j:linha(yConfirmar, janela.centralizar("CONFIRMAR", w), colors.black, C.bom)
    j:linha(yCancelar, janela.centralizar("cancelar", w), C.fraco, C.fundo)

    destino.setCursorPos(2 + campo.cursorVisivel(ativo()), yDoCampo(foco))
    destino.setCursorBlink(true)

    local function confirmar()
      destino.setCursorBlink(false)
      local resultado = {}
      for i, c in ipairs(campos) do resultado[i] = campo.valor(c) end
      return resultado
    end

    local function cancelar()
      destino.setCursorBlink(false)
      return nil
    end

    local ev, p1, p2, p3 = os.pullEvent()
    if ev == "char" then
      campo.tecla(ativo(), nil, p1)
    elseif ev == "key" then
      if p1 == keys.tab then
        -- com um campo so nao ha para onde trocar o foco: Tab e o gesto de
        -- cancelar, exatamente como no perguntar() original
        if n > 1 then foco = (foco % n) + 1 else return cancelar() end
      elseif p1 == keys.down then
        if n > 1 then foco = (foco % n) + 1 else campo.tecla(ativo(), p1) end
      elseif p1 == keys.up then
        if n > 1 then foco = ((foco - 2) % n) + 1 else campo.tecla(ativo(), p1) end
      elseif p1 == keys.enter then
        if foco < n then
          foco = foco + 1
        else
          return confirmar()
        end
      elseif p1 == keys.backspace and n > 1 and campo.vazio(ativo()) then
        return cancelar()
      else
        campo.tecla(ativo(), p1)
      end
    elseif ev == "mouse_click" then
      local caiu = false
      for i = 1, n do
        if p3 == yDoCampo(i) then foco = i; caiu = true; break end
      end
      if not caiu then
        if p3 == yConfirmar then return confirmar()
        elseif p3 == yCancelar then return cancelar() end
      end
    end
  end
end

return modal
