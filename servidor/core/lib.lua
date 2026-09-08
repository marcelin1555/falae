--[[ lib - carregador de modulos da central

  dofile() executa o arquivo de novo a cada chamada: dois modulos que fizessem
  dofile("linhas.lua") ficariam com DOIS registros de linha na memoria, e o que
  um deles salvasse apagaria o do outro. Aqui cada modulo e carregado uma vez
  so e fica guardado.

  O cache mora em _G porque este proprio arquivo e carregado por dofile: sem
  isso, cada dofile("lib.lua") criaria um cache novo e o problema voltaria.

    local lib    = dofile("/core/lib.lua")
    local linhas = lib("linhas")
]]

if _G.__falaeLib then return _G.__falaeLib end

local cache = {}

-- Onde procurar, na ordem: logica primeiro, desenho depois.
local PASTAS = { "/core/", "/tela/" }

local function lib(nome)
  if cache[nome] then return cache[nome] end
  for _, pasta in ipairs(PASTAS) do
    local caminho = pasta .. nome .. ".lua"
    if fs.exists(caminho) then
      local m = dofile(caminho)
      cache[nome] = m
      return m
    end
  end
  error("modulo faltando: " .. nome, 0)
end

--- Estes moram na raiz: protocolo e numero porque sao compartilhados com o
-- telefone, pixel e palette porque sao bibliotecas de uso geral.
cache.protocolo = dofile("/protocolo.lua")
cache.numero    = dofile("/numero.lua")
if fs.exists("/pixel.lua")   then cache.pixel   = dofile("/pixel.lua")   end
if fs.exists("/palette.lua") then cache.palette = dofile("/palette.lua") end

_G.__falaeLib = lib
return lib
