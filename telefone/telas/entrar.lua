--[[ entrar - a primeira tela de quem acabou de ligar o aparelho

  Tres portas: tirar uma linha nova, entrar numa que ja existe, e definir um
  PIN novo com o codigo que o balcao entregou a quem esqueceu o antigo.

  A terceira e uma porta ANUNCIADA, e nao um desvio que a central sugere. Ela
  sugeria: quando o numero existia e estava sem PIN, a resposta de erro dizia
  isso - o que so acontecia para numero de verdade, e apontava as linhas
  abertas para quem chegasse primeiro. Hoje a central recusa tudo igual, e quem
  vem por aqui vem porque esteve no balcao.

  Tem laco proprio, diferente do resto do aplicativo, porque aqui nao ha nada
  para atualizar em segundo plano: ninguem tem recado antes de ter linha. E o
  unico lugar do telefone que pode ficar parado esperando uma tecla.

  O PIN nunca aparece na tela e nunca vai para o disco. O que fica guardado no
  aparelho e o token da sessao - se alguem achar o pocket no chao, tem a
  conversa de quem perdeu, mas nao tem o PIN para entrar em outro aparelho nem
  para trocar nada.
]]

local carregar = dofile("/carregar.lua")
local janela = carregar("janela")
local campo  = carregar("campo")
local numero = carregar("numero")
local fnet   = carregar("fnet")

local entrar = {}

local function moldura(j, C, titulo)
  j:limpar(C.fundo)
  j:barra(1, " FALAE", "", colors.black, C.marca)
  if titulo then j:texto(2, 3, titulo, C.texto, C.fundo) end
end

--- Le uma linha de texto na janela, com eventos. Devolve o valor, ou nil se a
-- pessoa desistiu com Esc.
local function ler(j, C, y, rotulo, opcoes)
  local c = campo.novo(opcoes)
  while true do
    j:texto(2, y, rotulo, C.fraco, C.fundo)
    local visivel = campo.visivel(c)
    j:linha(y + 1, " " .. janela.encher(visivel, j.w - 2), C.texto, C.entrada)

    j.destino.setCursorPos(j.x + 1 + campo.cursorVisivel(c), j.y + y)
    j.destino.setCursorBlink(true)

    local ev, p1 = os.pullEvent()
    if ev == "char" then
      campo.tecla(c, nil, p1)
    elseif ev == "key" then
      if p1 == keys.enter then
        j.destino.setCursorBlink(false)
        return campo.valor(c)
      elseif p1 == keys.tab then
        j.destino.setCursorBlink(false)
        return nil
      else
        campo.tecla(c, p1)
      end
    end
  end
end

local function avisar(j, C, y, texto, cor)
  j:linha(y, " " .. janela.cortar(texto, j.w - 2), cor or C.ruim, C.fundo)
end

local function esperarTecla()
  os.pullEvent("key")
end

-- ------------------------------------------------------------------- criar

local function criarLinha(j, C)
  while true do
    moldura(j, C, "Sua linha nova")
    j:texto(2, 4, "Como voce quer aparecer", C.fraco, C.fundo)
    j:texto(2, 5, "para os outros?", C.fraco, C.fundo)

    local nome = ler(j, C, 7, "nome:", { max = 16 })
    if nome == nil then return false end
    if nome ~= "" then
      moldura(j, C, "Sua linha nova")
      j:texto(2, 4, "Escolha um PIN de 4 a 8", C.fraco, C.fundo)
      j:texto(2, 5, "numeros. Anote: nem a", C.fraco, C.fundo)
      j:texto(2, 6, "FALAE sabe qual e o seu.", C.fraco, C.fundo)

      local pin = ler(j, C, 8, "PIN:", { max = 8, mascara = "pin" })
      if pin == nil then return false end

      local repetido = ler(j, C, 11, "de novo:", { max = 8, mascara = "pin" })
      if repetido == nil then return false end

      if pin ~= repetido then
        avisar(j, C, j.h, "os dois PINs nao batem  (tecla)")
        esperarTecla()
      else
        moldura(j, C, "Tirando sua linha...")
        local ok, r = fnet.criarLinha(nome, pin)
        if ok then
          moldura(j, C, "Pronto!")
          j:texto(2, 5, "Seu numero e:", C.fraco, C.fundo)
          j:texto(2, 7, numero.formatar(r.numero), C.marca, C.fundo)
          j:texto(2, 9, "Anote. E por ele que as", C.fraco, C.fundo)
          j:texto(2, 10, "pessoas te acham.", C.fraco, C.fundo)
          j:linha(j.h, " qualquer tecla para comecar", C.fraco, C.fundo)
          esperarTecla()
          return true
        end
        avisar(j, C, j.h, janela.cortar(tostring(r), j.w - 2) .. " (tecla)")
        esperarTecla()
      end
    end
  end
end

-- ------------------------------------------------------------------ entrar

local function entrarNaLinha(j, C)
  while true do
    moldura(j, C, "Entrar na sua linha")

    local num = ler(j, C, 5, "numero:", { max = 13, mascara = "numero" })
    if num == nil then return false end

    local canonico = numero.canonico(num)
    if not canonico then
      avisar(j, C, j.h, "numero incompleto  (tecla)")
      esperarTecla()
    else
      j:texto(2, 7, numero.formatar(canonico), C.marca, C.fundo)
      local pin = ler(j, C, 9, "PIN:", { max = 8, mascara = "pin" })
      if pin == nil then return false end

      moldura(j, C, "Entrando...")
      local ok, r = fnet.entrar(canonico, pin)
      if ok then return true end

      avisar(j, C, j.h, janela.cortar(tostring(r), j.w - 2) .. " (tecla)")
      esperarTecla()
    end
  end
end

-- ----------------------------------------------------------------- resgate

--- Definir um PIN novo depois de passar no balcao da FALAE.
--
-- E uma PORTA PROPRIA no menu, e nao um desvio que aparece sozinho quando a
-- central responde "esta linha esta sem PIN". Aquela resposta era um oraculo:
-- ela so saia para numero que existe, e apontava justamente as linhas abertas
-- para quem chegasse primeiro. Agora a central recusa tudo com a mesma frase,
-- e quem sabe que passou pelo balcao entra por aqui - porque sabe, nao porque
-- foi avisado.
local function resgatarLinha(j, C)
  while true do
    moldura(j, C, "PIN novo")
    j:texto(2, 4, "Para quem passou no", C.fraco, C.fundo)
    j:texto(2, 5, "balcao da FALAE e tem", C.fraco, C.fundo)
    j:texto(2, 6, "o codigo de 6 digitos.", C.fraco, C.fundo)

    local num = ler(j, C, 8, "numero:", { max = 13, mascara = "numero" })
    if num == nil then return false end

    local canonico = numero.canonico(num)
    if not canonico then
      avisar(j, C, j.h, "numero incompleto  (tecla)")
      esperarTecla()
    else
      local codigo = ler(j, C, 11, "codigo:", { max = 6, mascara = "pin" })
      if codigo == nil then return false end

      moldura(j, C, "PIN novo")
      j:texto(2, 3, numero.formatar(canonico), C.marca, C.fundo)
      local novo = ler(j, C, 5, "PIN novo:", { max = 8, mascara = "pin" })
      if novo == nil then return false end
      local repetido = ler(j, C, 8, "de novo:", { max = 8, mascara = "pin" })
      if repetido == nil then return false end

      if novo ~= repetido then
        avisar(j, C, j.h, "os dois PINs nao batem  (tecla)")
        esperarTecla()
      else
        moldura(j, C, "Conferindo...")
        local ok, r = fnet.definirPin(canonico, codigo, novo)
        if ok then return true end
        avisar(j, C, j.h, janela.cortar(tostring(r), j.w - 2) .. " (tecla)")
        esperarTecla()
      end
    end
  end
end

-- ------------------------------------------------------------------ menu

--- Roda o fluxo de entrada. Volta true quando o aparelho ficou com sessao.
function entrar.rodar(j, C)
  -- Sem central alcancavel nao ha o que fazer aqui: nem criar linha nem
  -- entrar acontecem sem rede. Dizer isso na cara e melhor do que deixar a
  -- pessoa digitar um PIN inteiro para so entao falhar.
  while true do
    moldura(j, C, nil)
    j:texto(2, 3, "Procurando a FALAE...", C.fraco, C.fundo)
    local achou = fnet.conectar(true)
    if achou then break end

    moldura(j, C, "Sem sinal")
    j:texto(2, 5, "Nao achei a central da", C.texto, C.fundo)
    j:texto(2, 6, "FALAE daqui.", C.texto, C.fundo)
    j:texto(2, 8, "Confira o Ender Modem", C.fraco, C.fundo)
    j:texto(2, 9, "nas costas do aparelho.", C.fraco, C.fundo)
    j:linha(j.h, " R tentar de novo   Q sair", C.fraco, C.fundo)

    local _, k = os.pullEvent("key")
    if k == keys.q then return false end
  end

  local escolha = 1
  while true do
    moldura(j, C, nil)
    j:texto(2, 3, "Bem-vindo a FALAE.", C.texto, C.fundo)
    j:texto(2, 5, "O que voce quer fazer?", C.fraco, C.fundo)

    local opcoes = { "Tirar uma linha nova", "Entrar na minha linha",
                     "Esqueci meu PIN" }
    for i, texto in ipairs(opcoes) do
      local sel = i == escolha
      j:linha(7 + i, (sel and " > " or "   ") .. texto,
              sel and colors.black or C.texto,
              sel and C.marca or C.fundo)
    end
    j:linha(j.h, " setas escolhem   enter confirma", C.fraco, C.fundo)

    local _, k = os.pullEvent("key")
    if k == keys.up and escolha > 1 then escolha = escolha - 1 end
    if k == keys.down and escolha < #opcoes then escolha = escolha + 1 end
    if k == keys.enter then
      local pronto
      if escolha == 1 then pronto = criarLinha(j, C)
      elseif escolha == 2 then pronto = entrarNaLinha(j, C)
      else pronto = resgatarLinha(j, C) end
      if pronto then return true end
    end
    if k == keys.q then return false end
  end
end

return entrar
