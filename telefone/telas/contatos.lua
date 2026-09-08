--[[ contatos - a agenda deste aparelho

  Os apelidos ficam so aqui, no disco do pocket. A central nunca ve. Ver
  agenda.lua para o porque - em resumo: a lista de quem conhece quem e a
  informacao mais delicada que um sistema de mensagem pode juntar, e a FALAE
  nao precisa dela para funcionar.
]]

local carregar = dofile("/carregar.lua")
local janela = carregar("janela")
local agenda = carregar("agenda")
local numero = carregar("numero")

local tela = {}

function tela.desenhar(j, e, C)
  local lista = agenda.lista()
  j:limpar(C.fundo)
  j:barra(1, " Contatos", tostring(#lista) .. " ", colors.black, C.marca)

  if #lista == 0 then
    j:texto(2, 3, "Nenhum contato salvo.", C.fraco, C.fundo)
    j:texto(2, 5, "Abra uma conversa e", C.texto, C.fundo)
    j:texto(2, 6, "aperte S para dar um", C.texto, C.fundo)
    j:texto(2, 7, "nome ao numero.", C.texto, C.fundo)
    j:linha(j.h, " Q volta", C.fraco, C.fundo)
    return
  end

  local cabem = math.floor((j.h - 2) / 2)
  e.topoContatos = janela.rolar(e.escolhidoContato, #lista, cabem, e.topoContatos)

  for i = 0, cabem - 1 do
    local c = lista[e.topoContatos + i]
    local y = 2 + i * 2
    if c then
      local sel = (e.topoContatos + i) == e.escolhidoContato
      local fundo = sel and C.selecao or C.fundo
      j:linha(y, " " .. c.apelido, C.texto, fundo)
      j:linha(y + 1, " " .. numero.formatar(c.numero), C.fraco, fundo)
    else
      j:linha(y, "", C.texto, C.fundo)
      j:linha(y + 1, "", C.texto, C.fundo)
    end
  end

  j:linha(j.h, " enter abre  X apaga  Q volta", C.fraco, C.fundo)
end

function tela.tecla(e, k)
  local lista = agenda.lista()

  if k == keys.down and e.escolhidoContato < #lista then
    e.escolhidoContato = e.escolhidoContato + 1
    return "redesenhar"
  end
  if k == keys.up and e.escolhidoContato > 1 then
    e.escolhidoContato = e.escolhidoContato - 1
    return "redesenhar"
  end
  if k == keys.enter then
    local c = lista[e.escolhidoContato]
    if c then
      e.aberta = c.numero
      return "abrir"
    end
    return "redesenhar"
  end
  if k == keys.x then
    local c = lista[e.escolhidoContato]
    if c then
      agenda.esquecer(c.numero)
      if e.escolhidoContato > 1 then e.escolhidoContato = e.escolhidoContato - 1 end
      return "redesenhar"
    end
  end
  if k == keys.q or k == keys.backspace then return "voltar" end
  return nil
end

return tela
