--[[ agenda - os contatos, no disco do proprio aparelho

  A central nunca ve a agenda. Ela e sua: os apelidos que voce da para as
  pessoas, no seu aparelho.

  Isso e escolha de projeto, nao economia. Mandar a agenda para a central
  transformaria a FALAE num lugar onde esta escrito quem conhece quem - a
  informacao mais delicada que um sistema de mensagem pode juntar, e que nao e
  necessaria para nada do que ele faz. Aqui a central sabe que dois numeros
  trocaram recado; ela nao sabe que voce chama um deles de "chefe".

  O preco e honesto e vale dizer: trocar de aparelho perde a agenda. A linha
  vai junto, as conversas vao junto (moram na central), os apelidos ficam.

  A caixa de recados tambem mora aqui, e pelo mesmo motivo de sempre: com o
  historico em disco, o telefone abre a conversa na hora, sem pedir nada, e
  so pergunta a central o que chegou depois.
]]

local carregar = dofile("/carregar.lua")
local numero  = carregar("numero")
local orelhao = carregar("orelhao")

local agenda = {}

agenda.CONTATOS = "/.falae_contatos"
agenda.CAIXA    = "/.falae_caixa"
agenda.NOME_MAX = 16

-- Quanto o aparelho guarda. Um pocket tem pouco disco, e historico infinito
-- num aparelho de bolso e so um jeito lento de enche-lo.
agenda.MAX = 300

local contatos = {}    -- [canonico] = apelido
local caixa    = { desde = 0, recados = {} }

-- --------------------------------------------------------------- contatos

local function lerTabela(caminho, padrao)
  if not fs.exists(caminho) then return padrao end
  local f = fs.open(caminho, "r")
  if not f then return padrao end
  local t = textutils.unserialize(f.readAll() or "")
  f.close()
  if type(t) ~= "table" then return padrao end
  return t
end

local function gravarTabela(caminho, t)
  local f = fs.open(caminho, "w")
  if not f then return false end
  f.write(textutils.serialize(t))
  f.close()
  return true
end

function agenda.carregar()
  contatos = lerTabela(agenda.CONTATOS, {})
  caixa = lerTabela(agenda.CAIXA, { desde = 0, recados = {} })
  if type(caixa.recados) ~= "table" then caixa.recados = {} end
  if type(caixa.desde) ~= "number" then caixa.desde = 0 end
  return contatos
end

function agenda.salvarContatos()
  return gravarTabela(agenda.CONTATOS, contatos)
end

--- Como este numero deve aparecer na tela.
--
-- Ordem: o apelido que voce deu, depois o nome publico que a pessoa escolheu,
-- e so entao o numero. O seu apelido ganha do nome dela de proposito: se voce
-- salvou alguem como "chefe", e "chefe" que voce quer ler, mesmo que ela mude
-- o nome dela para outra coisa amanha.
--
-- Um orelhao nunca passa por nenhuma dessas contas - nao tem apelido (nao da
-- para salvar contato de quem e anonimo de proposito) nem nome publico
-- (nao e uma linha). Aparece sempre do mesmo jeito, pelo proprio codigo.
function agenda.como(canonico, nomePublico)
  if orelhao.valido(canonico) then return orelhao.nome(canonico) end
  return contatos[canonico] or nomePublico or numero.formatar(canonico)
end

function agenda.apelido(canonico)
  return contatos[canonico]
end

function agenda.salvar(canonico, apelido)
  apelido = tostring(apelido or ""):gsub("[\r\n]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if apelido == "" then return agenda.esquecer(canonico) end
  if #apelido > agenda.NOME_MAX then apelido = apelido:sub(1, agenda.NOME_MAX) end
  contatos[canonico] = apelido
  agenda.salvarContatos()
  return apelido
end

function agenda.esquecer(canonico)
  if not contatos[canonico] then return false end
  contatos[canonico] = nil
  agenda.salvarContatos()
  return true
end

function agenda.lista()
  local saida = {}
  for canonico, apelido in pairs(contatos) do
    saida[#saida + 1] = { numero = canonico, apelido = apelido }
  end
  table.sort(saida, function(a, b) return a.apelido:lower() < b.apelido:lower() end)
  return saida
end

function agenda.quantos()
  local n = 0
  for _ in pairs(contatos) do n = n + 1 end
  return n
end

-- ------------------------------------------------------------------ caixa

function agenda.desde()
  return caixa.desde
end

function agenda.salvarCaixa()
  return gravarTabela(agenda.CAIXA, caixa)
end

--- Guarda o que chegou da central.
--
-- Descarta repetido pelo numero do recado: um pedido repetido por perda de
-- pacote pode trazer de novo o que ja esta aqui, e a conversa apareceria com
-- a mesma frase duas vezes.
--
-- @return quantos eram novos
function agenda.receber(recados, ate)
  local novos = 0

  -- A tabela de vistos so e montada quando ha o que comparar. A resposta comum
  -- da central e "nada mudou", com lista vazia: montar um indice de trezentos
  -- recados para conferir coisa nenhuma e trabalho puro, em laco, para sempre.
  if recados and #recados > 0 then
    local vistos = {}
    for _, m in ipairs(caixa.recados) do vistos[m.n] = true end

    for _, m in ipairs(recados) do
      if type(m) == "table" and m.n and not vistos[m.n] then
        caixa.recados[#caixa.recados + 1] = m
        vistos[m.n] = true
        novos = novos + 1
      end
    end

    if novos > 0 then
      table.sort(caixa.recados, function(a, b) return a.n < b.n end)
      agenda.aparar()
    end
  end

  -- SO GRAVA QUANDO ALGUMA COISA MUDOU DE VERDADE.
  --
  -- O "ate" vem em toda resposta, inclusive na de "nada mudou" - e em Lua o
  -- zero e verdadeiro, entao gravar por causa dele gravava sempre. Um pocket
  -- esquecido no bolso reserializava a caixa inteira, ate trezentos recados,
  -- de trinta em trinta segundos, para sempre. A central faz ginastica para a
  -- resposta comum nao custar nada; nao e o aparelho que vai cobrar por ela.
  local avancou = ate ~= nil and ate > caixa.desde
  if avancou then caixa.desde = ate end
  if novos > 0 or avancou then agenda.salvarCaixa() end
  return novos
end

--- Corta o comeco da caixa quando ela passa do tamanho.
--
-- Em lote, pelo mesmo motivo da central: cortar de um em um pela posicao 1
-- desloca a tabela inteira a cada corte.
function agenda.aparar()
  if #caixa.recados <= agenda.MAX then return 0 end
  local corte = #caixa.recados - agenda.MAX
  local nova = {}
  for i = corte + 1, #caixa.recados do nova[#nova + 1] = caixa.recados[i] end
  caixa.recados = nova
  return corte
end

--- O maior numero de recado que este aparelho conhece.
local function maiorN()
  local maior = 0
  for _, m in ipairs(caixa.recados) do
    if m.n and m.n > maior then maior = m.n end
  end
  return maior
end

--- Um recado que so existe NESTE aparelho.
--
-- E o que voce mandou para quem te bloqueou. A central nao guarda e nao diz
-- que nao guardou - avisar transformaria o bloqueio num aviso (ver
-- bloqueio.lua). Mas se a frase tambem sumisse da sua tela, enquanto todas as
-- outras aparecem na hora, o bloqueio se anunciaria pelo comportamento, que da
-- na mesma. Entao ela fica aqui, so aqui.
--
-- O "n" e o maior conhecido mais um milesimo: ordena depois de tudo que ja
-- chegou e antes do proximo inteiro que a central vier a usar, entao nunca
-- colide com recado de verdade nem atrapalha o "desde".
function agenda.soAqui(m)
  if type(m) ~= "table" then return 0 end

  local maior = maiorN()
  local base = math.floor(maior)
  local fracao = math.min(0.999, (maior - base) + 0.001)

  local copia = {}
  for k, v in pairs(m) do copia[k] = v end
  copia.n = base + fracao
  copia.soAqui = true

  caixa.recados[#caixa.recados + 1] = copia
  agenda.aparar()
  agenda.salvarCaixa()
  return 1
end

--- Acrescenta um recado que este aparelho acabou de mandar, para ele aparecer
-- na conversa antes de a central confirmar. Sem isto, quem digita ve a
-- propria frase sumir e reaparecer um segundo depois.
function agenda.meu(m)
  if type(m) ~= "table" then return end
  -- n = 0 e o recibo de um recado que a central nao guardou: bloqueio.
  if m.n and m.n > 0 then return agenda.receber({ m }) end
  return agenda.soAqui(m)
end

--- Toda a conversa com um numero, em ordem.
function agenda.conversa(eu, outro)
  local saida = {}
  for _, m in ipairs(caixa.recados) do
    if (m.de == eu and m.para == outro) or (m.de == outro and m.para == eu) then
      saida[#saida + 1] = m
    end
  end
  return saida
end

--- Com quem este aparelho ja falou, mais recente primeiro.
--
-- Montada aqui, do que ja esta em disco, e nao pedida a central: abrir o
-- telefone nao precisa de rede, e a lista aparece antes de qualquer resposta
-- chegar. Se a central estiver fora do ar, o aparelho ainda mostra tudo que
-- ja tinha - que e o comportamento que a Expresso Labs tambem escolheu para
-- os postos dela.
function agenda.conversas(eu)
  local ultimo, naoLidos = {}, {}
  for _, m in ipairs(caixa.recados) do
    local outro
    if m.de == eu then outro = m.para
    elseif m.para == eu then outro = m.de end

    if outro then
      if not ultimo[outro] or m.n > ultimo[outro].n then ultimo[outro] = m end
      if m.para == eu and not m.lido then
        naoLidos[outro] = (naoLidos[outro] or 0) + 1
      end
    end
  end

  local saida = {}
  for outro, m in pairs(ultimo) do
    saida[#saida + 1] = { numero = outro, ultimo = m, naoLidos = naoLidos[outro] or 0 }
  end
  table.sort(saida, function(a, b) return a.ultimo.n > b.ultimo.n end)
  return saida
end

--- Marca como lida a conversa que a pessoa acabou de abrir.
function agenda.marcarLido(eu, outro)
  local mexeu = false
  for _, m in ipairs(caixa.recados) do
    if m.para == eu and m.de == outro and not m.lido then
      m.lido = true
      mexeu = true
    end
  end
  if mexeu then agenda.salvarCaixa() end
  return mexeu
end

function agenda.naoLidos(eu)
  local n = 0
  for _, m in ipairs(caixa.recados) do
    if m.para == eu and not m.lido then n = n + 1 end
  end
  return n
end

--- Esquece tudo deste aparelho. Chamado ao sair da linha: o proximo dono do
-- pocket nao pode abrir o telefone e ler a conversa de quem usou antes.
function agenda.limpar()
  contatos = {}
  caixa = { desde = 0, recados = {} }
  if fs.exists(agenda.CONTATOS) then fs.delete(agenda.CONTATOS) end
  if fs.exists(agenda.CAIXA) then fs.delete(agenda.CAIXA) end
end

return agenda
