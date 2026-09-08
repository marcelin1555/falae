--[[ startup - sobe a central da FALAE quando o chunk carrega

  Fino de proposito: so acha o codigo e chama. Toda a logica mora em
  /core/central.lua, que e o que os testes carregam direto - sem passar por
  aqui, porque aqui precisa de tela e teclado de verdade.
]]

if not fs.exists("/core/central.lua") then
  print("FALAE: instalacao incompleta - falta /core/central.lua")
  print("rode o deploy de novo.")
  return
end

local lib = dofile("/core/lib.lua")
local central = lib("central")

local ok, erro = pcall(central.rodar)
if not ok then
  term.setBackgroundColour(colors.black)
  term.setTextColour(colors.red)
  print("a central caiu: " .. tostring(erro))
  term.setTextColour(colors.white)
  print("")
  print("reinicie com Ctrl+R.")
end
