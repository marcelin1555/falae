--[[ bloqueados - quem voce nao quer ouvir, e como parar

  Antes disto, liberar alguem pedia para DIGITAR O NUMERO DE VOLTA - trabalho
  que a FALAE ja tinha feito uma vez, no dia do bloqueio. Uma lista tocavel,
  com o nome de cada um, e o gesto certo: voce ve quem esta bloqueado e toca
  para liberar, sem lembrar treze digitos de cor.

  A lista vem PRONTA de app.lua (e.bloqueadosLista), buscada uma vez quando a
  pessoa entra aqui pelo menu do perfil - esta tela so desenha e diz qual foi
  tocado. Rede e tela continuam separadas, como em todo o resto do aplicativo.
]]

local carregar = dofile("/carregar.lua")
local janela = carregar("janela")
local numero = carregar("numero")

local tela = {}

function tela.desenhar(j, e, C)
  local lista = e.bloqueadosLista or {}
  j:limpar(C.fundo)
  j:barra(1, " Bloqueados", tostring(#lista) .. " ", colors.black, C.marca)

  if #lista == 0 then
    j:texto(2, 3, "Ninguem bloqueado.", C.fraco, C.fundo)
    local textoVazio, regioesVazio = janela.rodape({
      { rotulo = "Q volta", acao = "perfil" },
    }, j.w)
    e.rodapeBloqueados = regioesVazio
    j:linha(j.h, textoVazio, C.fraco, C.fundo)
    return
  end

  local cabem = math.floor((j.h - 2) / 2)
  e.topoBloqueados = janela.rolar(e.escolhidoBloqueados, #lista, cabem, e.topoBloqueados)

  for i = 0, cabem - 1 do
    local b = lista[e.topoBloqueados + i]
    local y = 2 + i * 2
    if not b then
      j:linha(y, "", C.texto, C.fundo)
      j:linha(y + 1, "", C.texto, C.fundo)
    else
      local sel = (e.topoBloqueados + i) == e.escolhidoBloqueados
      local fundo = sel and C.selecao or C.fundo
      local nome = b.nome or numero.formatar(b.numero)
      local quando = b.quando and janela.quando(b.quando, e.agora) or "-"

      -- o badge de desbloquear fica colado na direita, tres celulas - o
      -- mesmo raciocinio do "<" na conversa: a AREA tocavel e a linha
      -- inteira (ver tela.clique), o badge so mostra onde olhar
      local largura = j.w - 4
      j:linha(y, " " .. janela.encher(nome, largura) .. "   ", C.texto, fundo)
      j:texto(j.w - 2, y, " X ", colors.black, C.aviso)

      j:linha(y + 1, "   bloqueado " .. quando, C.fraco, fundo)
    end
  end

  local texto, regioes = janela.rodape({
    { rotulo = "Q volta", acao = "perfil" },
    { rotulo = "X libera", acao = "desbloquear" },
  }, j.w)
  e.rodapeBloqueados = regioes
  j:linha(j.h, texto, C.fraco, C.fundo)
end

--- @return acao, ou nil
function tela.clique(e, lx, ly, j)
  local lista = e.bloqueadosLista or {}

  if ly == j.h then
    return janela.acaoNoRodape(e.rodapeBloqueados, lx)
  end
  if #lista == 0 then return nil end

  if ly >= 2 then
    local indice = (e.topoBloqueados or 1) + math.floor((ly - 2) / 2)
    if lista[indice] then
      e.escolhidoBloqueados = indice
      return "desbloquear"
    end
  end
  return nil
end

function tela.tecla(e, k)
  local lista = e.bloqueadosLista or {}

  if #lista > 0 then
    if k == keys.down and e.escolhidoBloqueados < #lista then
      e.escolhidoBloqueados = e.escolhidoBloqueados + 1
      return "redesenhar"
    end
    if k == keys.up and e.escolhidoBloqueados > 1 then
      e.escolhidoBloqueados = e.escolhidoBloqueados - 1
      return "redesenhar"
    end
    if k == keys.x then return "desbloquear" end
  end
  if k == keys.q or k == keys.backspace then return "perfil" end
  return nil
end

return tela
