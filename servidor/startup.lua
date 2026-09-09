--[[ startup - sobe a central da FALAE quando o chunk carrega

  Fino de proposito: acha o codigo, confere a chave, e chama. Toda a logica
  mora em /core/central.lua, que e o que os testes carregam direto - sem passar
  por aqui, porque aqui precisa de tela, teclado e drive de verdade.

  A CHAVE SO PRECISA ESTAR NO DRIVE. Nao pede PIN aqui, e isso e escolha, nao
  esquecimento: se pedisse, a central nao voltaria sozinha depois de um
  reinicio de chunk, e uma operadora telefonica que fica fora do ar ate alguem
  aparecer com um disquete na mao nao e uma operadora telefonica. Ligar nao e o
  ato perigoso. Cassar linha, zerar PIN e ler denuncia sao - e esses ficam
  atras do PIN, no console.
]]

if not fs.exists("/core/central.lua") then
  print("FALAE: instalacao incompleta - falta /core/central.lua")
  print("rode o deploy de novo.")
  return
end

local lib      = dofile("/core/lib.lua")
local chave    = lib("chave")
local chaveiro = lib("chaveiro")
local tranca   = lib("tranca")

tranca.usar(chave, chaveiro)
chaveiro.carregar()

-- ------------------------------------------------------------ a primeira

local function cor(c)
  if term.isColour and term.isColour() then term.setTextColour(c) end
end

local function ler(rotulo)
  cor(colors.yellow)
  write(rotulo .. " ")
  cor(colors.white)
  return read()
end

--- Reivindica uma central que ainda nao tem dono.
--
-- Chaveiro vazio quer dizer maquina sem chave nenhuma, e nao ha como conferir
-- a primeira contra coisa alguma. E o mesmo instante de qualquer instalacao
-- nova - quem chega primeiro no computador recem-posto e o dono - e a tela diz
-- isso com todas as letras, em vez de deixar parecer que ja havia tranca.
local function reivindicar()
  while true do
    term.setBackgroundColour(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    cor(colors.yellow)
    print("FALAE")
    cor(colors.gray)
    print("central sem dono")
    cor(colors.white)
    print("")
    print("Esta central ainda nao tem chave.")
    cor(colors.gray)
    print("A primeira chave e a dona: quem")
    print("emitir agora manda aqui.")
    print("")
    print("Ponha um disquete VAZIO no drive.")
    cor(colors.white)
    print("")

    local id, motivo = tranca.disco()
    if not id then
      cor(colors.red)
      print(motivo)
      cor(colors.gray)
      print("qualquer tecla para tentar de novo")
      cor(colors.white)
      os.pullEvent("key")
    else
      print("disquete #" .. tostring(id))
      print("")
      local nome = ler("nome da chave (ex: mestra):")
      if nome == "" then nome = "mestra" end

      local pin = tranca.lerPin("PIN novo (" .. chave.PIN_MIN .. " a " ..
                                chave.PIN_MAX .. " digitos):")
      if pin then
        local outra = tranca.lerPin("de novo:")
        if outra ~= pin then
          cor(colors.red)
          print("os dois PINs nao batem")
          cor(colors.gray)
          print("qualquer tecla")
          cor(colors.white)
          os.pullEvent("key")
        else
          local k, erro = tranca.emitir(nome, "central", pin)
          if k then
            cor(colors.lime)
            print("")
            print("Chave emitida.")
            cor(colors.gray)
            print("Guarde o disquete. Sem ele a central")
            print("nao sobe, e sem o PIN o balcao nao abre.")
            print("Nem a FALAE sabe o seu PIN.")
            cor(colors.white)
            print("")
            print("qualquer tecla para subir")
            os.pullEvent("key")
            return true
          end
          cor(colors.red)
          print(tostring(erro))
          cor(colors.gray)
          print("qualquer tecla")
          cor(colors.white)
          os.pullEvent("key")
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ sobe

if chaveiro.vazio() then
  if not reivindicar() then return end
elseif not tranca.esperar("central", "central trancada") then
  return
end

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
