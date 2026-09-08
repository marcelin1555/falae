--[[ campo - uma linha de texto sendo digitada

  Feito com eventos char/key, e nunca com read().

  read() bloqueia ate a pessoa apertar enter. Enquanto ela pensa no que
  escrever, o telefone estaria parado dentro do read: nao perguntaria a
  central, nao mostraria o recado que chegou, nao redesenharia nada. Voce
  digitaria uma frase e so descobriria que o outro respondeu depois de mandar a
  sua. A Expresso Labs chegou na mesma conclusao no mural dela.

  Guarda o texto e onde esta o cursor. Nao desenha - quem desenha e a tela,
  que sabe onde o campo mora.

  A mascara de numero e o motivo de este arquivo existir separado do resto:
  treze digitos seguidos sem nenhuma referencia visual e o tipo de coisa em que
  se erra um no meio e so se descobre quando a mensagem nao chega.
]]

local carregar = dofile("/carregar.lua")
local numero = carregar("numero")

local campo = {}

--- @param opcoes { max =, mascara = "numero"|"pin"|nil }
function campo.novo(opcoes)
  opcoes = opcoes or {}
  return {
    texto   = "",
    cursor  = 0,
    max     = opcoes.max or 160,
    mascara = opcoes.mascara,
  }
end

function campo.limpar(c)
  c.texto = ""
  c.cursor = 0
end

function campo.definir(c, texto)
  c.texto = tostring(texto or ""):sub(1, c.max)
  c.cursor = #c.texto
end

--- O valor de verdade: o que o programa usa.
function campo.valor(c)
  return c.texto
end

function campo.vazio(c)
  return c.texto == ""
end

--- O que aparece na tela. Para numero, formatado enquanto se digita; para
-- PIN, escondido - alguem olhando por cima do ombro em Minecraft e tao
-- possivel quanto na vida.
function campo.visivel(c)
  if c.mascara == "numero" then return numero.parcial(c.texto) end
  if c.mascara == "pin" then return string.rep("*", #c.texto) end
  return c.texto
end

--- Onde o cursor cai na versao visivel. Sem esta conta, o cursor de um campo
-- de numero fica atras do texto, porque os espacos e o traco da mascara nao
-- existem no valor.
function campo.cursorVisivel(c)
  if c.mascara == "numero" then return #numero.parcial(c.texto:sub(1, c.cursor)) end
  return c.cursor
end

local function cabe(c, ch)
  if #c.texto >= c.max then return false end
  if c.mascara == "numero" or c.mascara == "pin" then
    return ch:match("%d") ~= nil
  end
  return true
end

--- Trata uma tecla ou caractere.
-- @return true se o conteudo mudou (e a tela precisa ser redesenhada)
function campo.tecla(c, tecla, ch)
  if ch then
    if not cabe(c, ch) then return false end
    c.texto = c.texto:sub(1, c.cursor) .. ch .. c.texto:sub(c.cursor + 1)
    c.cursor = c.cursor + 1
    return true
  end

  if tecla == keys.backspace then
    if c.cursor == 0 then return false end
    c.texto = c.texto:sub(1, c.cursor - 1) .. c.texto:sub(c.cursor + 1)
    c.cursor = c.cursor - 1
    return true
  end

  if tecla == keys.delete then
    if c.cursor >= #c.texto then return false end
    c.texto = c.texto:sub(1, c.cursor) .. c.texto:sub(c.cursor + 2)
    return true
  end

  if tecla == keys.left then
    if c.cursor == 0 then return false end
    c.cursor = c.cursor - 1
    return true
  end

  if tecla == keys.right then
    if c.cursor >= #c.texto then return false end
    c.cursor = c.cursor + 1
    return true
  end

  if tecla == keys.home then
    if c.cursor == 0 then return false end
    c.cursor = 0
    return true
  end

  if tecla == keys["end"] then
    if c.cursor >= #c.texto then return false end
    c.cursor = #c.texto
    return true
  end

  return false
end

return campo
