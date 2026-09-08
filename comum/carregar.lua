--[[ carregar - o require do telefone

  dofile() executa o arquivo DE NOVO a cada chamada. Sem cache, cada arquivo
  que pedisse a agenda ficaria com uma copia propria dela: o aplicativo
  carregaria os recados do disco na copia dele, e a tela de conversas leria uma
  copia vazia. O telefone abriria bonito e nao mostraria mensagem nenhuma.

  Nao e hipotese - foi o que aconteceu, e o teste das telas pegou.

  O servidor ja tinha o mesmo problema resolvido em /core/lib.lua. Este arquivo
  e a mesma ideia do lado do aparelho, onde os modulos moram na raiz e as telas
  numa pasta.

  O cache mora em _G porque este proprio arquivo e carregado por dofile: sem
  isso, cada dofile("/carregar.lua") criaria um cache novo e o problema
  voltaria por baixo.

    local carregar = dofile("/carregar.lua")
    local agenda   = carregar("agenda")
]]

if _G.__falaeCarregar then return _G.__falaeCarregar end

local cache = {}

-- Onde procurar, na ordem: as bibliotecas na raiz, as telas na pasta delas.
local PASTAS = { "/", "/telas/" }

local function carregar(nome)
  if cache[nome] ~= nil then return cache[nome] end
  for _, pasta in ipairs(PASTAS) do
    local caminho = pasta .. nome .. ".lua"
    if fs.exists(caminho) then
      local m = dofile(caminho)
      cache[nome] = m
      return m
    end
  end
  error("modulo faltando no telefone: " .. tostring(nome), 0)
end

_G.__falaeCarregar = carregar
return carregar
