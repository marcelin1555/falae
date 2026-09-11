--[[ teste_instalador - o caminho pelo qual a FALAE entra num computador

  Num servidor de outra pessoa nao ha pasta de save para copiar arquivo: o
  computador precisa buscar tudo sozinho pela rede. Entao o instalador nao e um
  extra - ele e A instalacao. Se ele estiver errado, nada mais do projeto chega
  a rodar, e o sintoma no jogo e um computador pela metade dizendo "modulo
  faltando" sem dizer qual.

  Aqui o http e falso e serve os arquivos do disco real, entao da para conferir
  o que o instalador FAZ (quais arquivos pede, onde grava, o que responde
  quando a rede falha) sem abrir o jogo e sem depender do GitHub estar no ar.

  O teste que mais importa e o do manifesto contra o disco: e ele que pega o
  arquivo novo que alguem escreveu e esqueceu de listar - o erro mais provavel
  deste projeto daqui para frente.
]]

local PROJETO = ...

local mock = dofile(PROJETO .. "/testes/cc_mock.lua")
mock.instalar()

local total, falhas = 0, 0

-- O print de verdade, guardado ANTES de qualquer coisa. Testar o instalador
-- exige trocar o print global por um que escreve na tela falsa - e sem esta
-- copia o relatorio do proprio teste iria para dentro do buffer da tela em vez
-- da saida, e a suite terminaria muda parecendo que travou. Foi o que
-- aconteceu na primeira vez.
local imprimir = print

local function ok(condicao, titulo, detalhe)
  total = total + 1
  if condicao then
    imprimir("  ok   " .. titulo)
  else
    falhas = falhas + 1
    imprimir("  FALHA " .. titulo .. (detalhe and ("  -> " .. tostring(detalhe)) or ""))
  end
end

local function igual(a, b, titulo)
  ok(a == b, titulo, ("esperava [%s], veio [%s]"):format(tostring(b), tostring(a)))
end

local BASE = "https://raw.githubusercontent.com/marcelin1555/falae/main/"

--- Le o manifesto do disco real, do mesmo jeito que o instalador le da rede.
local function lerManifesto()
  local f = io.open(PROJETO .. "/manifesto.txt", "rb")
  local texto = f:read("*a")
  f:close()

  local porPapel = {}
  for l in texto:gmatch("[^\r\n]+") do
    if l:sub(1, 1) ~= "#" and l:find("|", 1, true) then
      local papel, destino, origem = l:match("^%s*([^|]-)%s*|%s*([^|]-)%s*|%s*(.-)%s*$")
      porPapel[papel] = porPapel[papel] or {}
      table.insert(porPapel[papel], { destino = destino, origem = origem })
    end
  end
  return porPapel, texto
end

local manifesto, textoManifesto = lerManifesto()

-- --------------------------------------------- 1. o manifesto bate com o disco

imprimir("\n-- o manifesto e o disco --")

local papeis = { "central", "central-visual", "telefone", "telefone-visual" }
for _, papel in ipairs(papeis) do
  ok(manifesto[papel] ~= nil and #manifesto[papel] > 0,
     "o papel " .. papel .. " tem arquivos")
end

-- Todo arquivo listado existe? Um caminho errado no manifesto vira 404 no
-- meio da instalacao, num servidor de outra pessoa, com a pessoa olhando.
local sumidos = {}
for papel, lista in pairs(manifesto) do
  for _, a in ipairs(lista) do
    local f = io.open(PROJETO .. "/" .. a.origem, "rb")
    if f then f:close() else sumidos[#sumidos + 1] = papel .. " -> " .. a.origem end
  end
end
ok(#sumidos == 0, "todo arquivo do manifesto existe no disco",
   table.concat(sumidos, "; "))

-- E o contrario, que e o erro mais provavel: alguem escreve um modulo novo e
-- esquece de lista-lo. No jogo isso aparece como "modulo faltando".
local listados = {}
for _, lista in pairs(manifesto) do
  for _, a in ipairs(lista) do listados[a.origem] = true end
end

local esperados = {
  "comum/protocolo.lua", "comum/numero.lua", "comum/janela.lua",
  "comum/campo.lua", "comum/ritmo.lua", "comum/carregar.lua",
  "comum/pixel.lua", "comum/palette.lua",
  "servidor/startup.lua",
  "servidor/core/lib.lua", "servidor/core/store.lua", "servidor/core/linhas.lua",
  "servidor/core/recados.lua", "servidor/core/bloqueio.lua",
  "servidor/core/central.lua", "servidor/core/console.lua",
  "servidor/tela/marca.lua", "servidor/tela/painel.lua",
  "telefone/startup.lua", "telefone/fnet.lua", "telefone/agenda.lua",
  "telefone/app.lua",
  "telefone/telas/conversas.lua", "telefone/telas/conversa.lua",
  "telefone/telas/contatos.lua", "telefone/telas/perfil.lua",
  "telefone/telas/bloqueados.lua", "telefone/telas/entrar.lua",
}

local naoListados = {}
for _, caminho in ipairs(esperados) do
  if not listados[caminho] then naoListados[#naoListados + 1] = caminho end
end
ok(#naoListados == 0,
   "todo modulo do projeto esta em algum papel do manifesto",
   table.concat(naoListados, "; "))

-- ------------------------------------------------- 2. o telefone fica inteiro

imprimir("\n-- o que o telefone precisa para ligar --")

-- O startup do aparelho confere estes na primeira linha. Se o manifesto nao
-- entregar algum, o telefone instala e recusa ligar.
local telefoneTem = {}
for _, a in ipairs(manifesto.telefone) do telefoneTem[a.destino] = true end

for _, nome in ipairs({ "carregar.lua", "protocolo.lua", "numero.lua",
                        "janela.lua", "campo.lua", "ritmo.lua",
                        "fnet.lua", "agenda.lua", "app.lua", "startup.lua" }) do
  ok(telefoneTem[nome], "o telefone recebe " .. nome)
end

for _, nome in ipairs({ "conversas", "conversa", "contatos", "perfil", "bloqueados", "entrar" }) do
  ok(telefoneTem["telas/" .. nome .. ".lua"], "e a tela " .. nome)
end

-- A parte visual e opcional: ela NAO pode estar no papel obrigatorio, senao
-- deixa de ser opcional e o -SemMarca nao serve para nada.
ok(not telefoneTem["pixel.lua"], "pixel fica so no papel visual, como o previsto")
ok(not telefoneTem["marca.lua"], "e a marca tambem")

local centralTem = {}
for _, a in ipairs(manifesto.central) do centralTem[a.destino] = true end
for _, nome in ipairs({ "core/lib.lua", "core/store.lua", "core/central.lua",
                        "core/linhas.lua", "core/recados.lua",
                        "core/bloqueio.lua", "core/console.lua",
                        "protocolo.lua", "numero.lua", "startup.lua" }) do
  ok(centralTem[nome], "a central recebe " .. nome)
end
ok(not centralTem["tela/painel.lua"], "o painel fica no papel visual da central")

-- ------------------------------------------------ 3. o instalador de verdade

imprimir("\n-- rodando o instalador --")

mock.disco("computadorNovo")
mock.instalarHttp(PROJETO, BASE)
mock.instalarTerm(51, 19)
_G.pocket = nil                       -- um computador comum
_G.os.reboot = function() error("REBOOT", 0) end

-- respostas: tipo, visual, reiniciar
mock.responder({ "telefone", "s", "n" })

local instalador = io.open(PROJETO .. "/instalar.lua", "rb")
local codigo = instalador:read("*a")
instalador:close()

local fn = load(codigo, "@instalar.lua")
ok(fn ~= nil, "instalar.lua compila")

local rodou = pcall(fn)
ok(rodou, "e roda sem quebrar")

imprimir("\n-- o que ele deixou no disco --")
for _, a in ipairs(manifesto.telefone) do
  ok(fs.exists("/" .. a.destino), "gravou " .. a.destino)
end
for _, a in ipairs(manifesto["telefone-visual"]) do
  ok(fs.exists("/" .. a.destino), "gravou " .. a.destino .. " (visual)")
end

-- e nada da central foi parar num aparelho
ok(not fs.exists("/core/central.lua"), "nao instalou a central no aparelho")

-- o conteudo tem que chegar igual, nao truncado
local baixado = mock.ler("fnet.lua")
local original = io.open(PROJETO .. "/telefone/fnet.lua", "rb")
local esperado = original:read("*a")
original:close()
igual(#baixado, #esperado, "o arquivo chegou inteiro")

-- e o instalador nao pediu nada fora do repositorio
local forasteiro = nil
for _, url in ipairs(mock.http.pedidos) do
  if url:sub(1, #BASE) ~= BASE then forasteiro = url end
end
ok(forasteiro == nil, "so pediu coisa do proprio repositorio", forasteiro)

-- ------------------------------------------------------ 4. a central tambem

imprimir("\n-- instalando a central --")

mock.disco("centralNova")
mock.instalarTerm(51, 19)
mock.responder({ "central", "s", "n" })

local ok2 = pcall(load(codigo, "@instalar.lua"))
ok(ok2, "instala a central sem quebrar")
for _, a in ipairs(manifesto.central) do
  ok(fs.exists("/" .. a.destino), "gravou " .. a.destino)
end
ok(fs.exists("/tela/painel.lua"), "e o painel do monitor")
ok(not fs.exists("/app.lua"), "sem o aplicativo do telefone junto")

-- ------------------------------------------------------- 5. sem visual

imprimir("\n-- instalando sem a parte visual --")

mock.disco("magrinho")
mock.instalarTerm(51, 19)
mock.responder({ "telefone", "n", "n" })
pcall(load(codigo, "@instalar.lua"))

ok(fs.exists("/app.lua"), "o telefone veio")
ok(not fs.exists("/pixel.lua"), "e a parte visual ficou de fora, como pedido")
ok(not fs.exists("/marca.lua"), "sem a marca")

-- ------------------------------------------------------- 6. quando falha

imprimir("\n-- quando a rede falha --")

mock.disco("semRede")
mock.instalarTerm(51, 19)
mock.instalarHttp(PROJETO, BASE)
mock.http.falhar[BASE .. "manifesto.txt"] = "timeout"
mock.responder({ "telefone", "s", "n" })

pcall(load(codigo, "@instalar.lua"))
ok(not fs.exists("/app.lua"),
   "manifesto que nao chega para a instalacao antes de gravar qualquer coisa")
ok(mock.textoDaSaida():find("nao consegui") ~= nil,
   "e diz que nao conseguiu, em vez de terminar em silencio")

imprimir("\n-- quando um arquivo do meio falha --")
mock.disco("meioCaminho")
mock.instalarTerm(51, 19)
mock.instalarHttp(PROJETO, BASE)
mock.http.falhar[BASE .. "telefone/app.lua"] = "500"
mock.responder({ "telefone", "s", "n" })

pcall(load(codigo, "@instalar.lua"))
ok(fs.exists("/fnet.lua"), "o que deu certo continua gravado")
ok(not fs.exists("/app.lua"), "e o que falhou nao ficou pela metade")
ok(mock.textoDaSaida():find("falharam") ~= nil, "o resumo no fim conta a falha")
ok(mock.textoDaSaida():find("de novo") ~= nil, "e manda rodar de novo")

imprimir("\n-- sem a API http --")
mock.disco("semHttp")
mock.instalarTerm(51, 19)
_G.http = nil
mock.responder({ "telefone", "s", "n" })
pcall(load(codigo, "@instalar.lua"))
ok(mock.textoDaSaida():find("http") ~= nil,
   "explica que a API http esta desligada, que e coisa do dono do servidor")

imprimir("\n-- num pocket, nao pergunta o tipo --")
mock.disco("pocketNovo")
mock.instalarTerm(26, 20)
mock.instalarHttp(PROJETO, BASE)
_G.pocket = { equipBack = function() end }
-- so duas respostas: visual e reiniciar. Se ele perguntasse o tipo, a
-- primeira resposta seria comida e o resto sairia trocado.
local quantas = mock.responder({ "s", "n" })
pcall(load(codigo, "@instalar.lua"))
ok(fs.exists("/app.lua"), "instalou o telefone sozinho")
ok(not fs.exists("/core/central.lua"), "e nunca a central - pocket nao serve de central")
igual(quantas(), 2, "gastou exatamente as duas perguntas")

_G.pocket = nil

imprimir(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
