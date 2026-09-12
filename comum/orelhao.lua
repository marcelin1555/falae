--[[ orelhao - o codigo de um orelhao, e como ele aparece na tela

  Um orelhao nao tem PIN nem dono: ninguem "entra" nele, so digita um numero e
  liga. Ele e identificado so pelo proprio codigo, escolhido por quem o
  instala ("#240" pra rua dos blocos, por exemplo).

  O formato ("#" + digitos) e deliberadamente diferente do formato de uma
  linha (13 digitos, sem "#") para os dois nunca colidirem no mesmo espaco de
  nomes que recados.de/recados.para usa - e e essa diferenca de formato que
  deixa central.lua saber, sem tabela nenhuma, se esta lidando com uma linha
  de verdade ou com um orelhao.
]]

local orelhao = {}

--- O codigo e valido? "#" seguido de pelo menos um digito.
function orelhao.valido(codigo)
  return type(codigo) == "string" and codigo:match("^#%d+$") ~= nil
end

--- Como aparece na tela, no lugar de um nome de contato - nunca salvo na
-- agenda, nunca trocado por apelido: quem liga e anonimo de proposito.
function orelhao.nome(codigo)
  return "Orelhao " .. codigo
end

return orelhao
