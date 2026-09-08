--[[ perfil - a sua linha neste aparelho

  O seu numero grande na tela, porque e o que a pessoa vem aqui ver: ela quer
  ditar o proprio numero para alguem.

  E o lugar de sair da linha. Sair apaga a agenda e a caixa de recados do
  aparelho junto - se nao apagasse, o proximo dono do pocket abriria o telefone
  e leria a conversa de quem usou antes. Um aparelho de bolso muda de mao, e
  esse e o momento em que ele muda.
]]

local carregar = dofile("/carregar.lua")
local janela = carregar("janela")
local numero = carregar("numero")
local agenda = carregar("agenda")

local tela = {}

local ITENS = {
  { chave = "nome",   texto = "Trocar meu nome" },
  { chave = "pin",    texto = "Trocar meu PIN" },
  { chave = "bloq",   texto = "Bloqueados" },
  { chave = "sair",   texto = "Sair desta linha" },
}

tela.ITENS = ITENS

function tela.desenhar(j, e, C)
  j:limpar(C.fundo)
  j:barra(1, " Minha linha", "", colors.black, C.marca)

  j:texto(2, 3, e.eu.nome, C.texto, C.fundo)
  j:texto(2, 4, numero.formatar(e.eu.numero), C.marca, C.fundo)

  j:regua(6, C.fraco, C.fundo)

  for i, item in ipairs(ITENS) do
    local sel = i == e.escolhidoPerfil
    j:linha(6 + i, (sel and " > " or "   ") .. item.texto,
            sel and colors.black or C.texto,
            sel and C.marca or C.fundo)
  end

  -- a linha de diagnostico: por que o telefone "demorou"
  j:texto(2, j.h - 2, ("sinal: %s"):format(e.sinal or "?"),
          e.sinal == "ok" and C.bom or C.aviso, C.fundo)
  j:texto(2, j.h - 1, ("ritmo: %s (%ds)"):format(e.degrau or "-", e.intervalo or 0),
          C.fraco, C.fundo)

  j:linha(j.h, " enter escolhe   Q volta", C.fraco, C.fundo)
end

function tela.tecla(e, k)
  if k == keys.down and e.escolhidoPerfil < #ITENS then
    e.escolhidoPerfil = e.escolhidoPerfil + 1
    return "redesenhar"
  end
  if k == keys.up and e.escolhidoPerfil > 1 then
    e.escolhidoPerfil = e.escolhidoPerfil - 1
    return "redesenhar"
  end
  if k == keys.enter then
    return "perfil:" .. ITENS[e.escolhidoPerfil].chave
  end
  if k == keys.q or k == keys.backspace then return "voltar" end
  return nil
end

return tela
