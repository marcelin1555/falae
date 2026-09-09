--[[ startup - sobe o computador da loja quando o chunk carrega

  Fino de proposito, igual ao startup da central e do telefone: so acha o
  codigo e chama. SEM CHAVE NENHUMA aqui - a loja precisa vender linha mesmo
  quando o dono nao esta por perto. So a administracao (tecla A, dentro do
  app) pede disquete e PIN.
]]

if not fs.exists("/app.lua") then
  print("FALAE (loja): instalacao incompleta - falta /app.lua")
  print("rode o instalador de novo.")
  return
end

local carregar = dofile("/carregar.lua")
local app = carregar("app")

local ok, erro = pcall(app.rodar)
if not ok then
  term.setBackgroundColour(colors.black)
  term.setTextColour(colors.red)
  print("a loja caiu: " .. tostring(erro))
  term.setTextColour(colors.white)
  print("")
  print("reinicie com Ctrl+R.")
end
