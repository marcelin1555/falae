--[[ startup - sobe o computador do orelhao quando o chunk carrega

  Fino de proposito, igual ao startup da loja e da central: so acha o codigo
  e chama. SEM CHAVE NENHUMA - um orelhao nao tem administracao propria, so
  liga.
]]

if not fs.exists("/app.lua") then
  print("FALAE (orelhao): instalacao incompleta - falta /app.lua")
  print("rode o instalador de novo.")
  return
end

local carregar = dofile("/carregar.lua")
local app = carregar("app")

local ok, erro = pcall(app.rodar)
if not ok then
  term.setBackgroundColour(colors.black)
  term.setTextColour(colors.red)
  print("o orelhao caiu: " .. tostring(erro))
  term.setTextColour(colors.white)
  print("")
  print("reinicie com Ctrl+R.")
end
