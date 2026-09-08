--[[ denuncias - a unica porta pela qual um recado sai do aparelho

  A FALAE nao le mensagem de ninguem. E a promessa que sustenta o produto, e o
  teste_privacidade existe para garanti-la.

  A denuncia e a UNICA excecao, e ela so e aceitavel porque tem consentimento:
  quem RECEBEU decide entregar aquele recado. Ninguem e vigiado por padrao,
  nada e lido por varredura, e nenhuma palavra e filtrada.

  Tres regras vem disso, e as tres estao no codigo, nao so no comentario:

  1. SO O ULTIMO RECADO RECEBIDO daquele numero. Nao a conversa, nao o
     historico. Uma denuncia carrega uma frase, o suficiente para a operadora
     julgar.

  2. O TEXTO VEM DAQUI, do historico da central - nunca do que o aparelho
     mandou. Se viesse do aparelho, qualquer um poderia inventar uma frase e
     dizer que foi outra pessoa quem escreveu, e a denuncia viraria uma arma.
     Quem chama denuncias.criar passa os dois numeros; o texto e buscado.

  3. O TEXTO NUNCA VAI PARA O PAINEL. O painel fica numa sala por onde qualquer
     um passa; ele mostra quantas denuncias esperam, e mais nada. Ler e coisa
     do console, no teclado, onde so a operadora esta.

  O denunciado nao e avisado. Avisar transformaria a denuncia num aviso, e a
  pessoa simplesmente tiraria outra linha - que custa nada.
]]

local lib   = dofile("/core/lib.lua")
local store = lib("store")

local denuncias = {}

denuncias.CAMINHO = "/dados/denuncias"
denuncias.MAX     = 200     -- quantas ficam guardadas, resolvidas incluidas

-- fila[i] = { n, de, sobre, texto, quando, resolvida, comoAcabou }
local fila = { proximo = 1, itens = {} }

function denuncias.carregar()
  fila = store.carregar(denuncias.CAMINHO, { proximo = 1, itens = {} })
  if type(fila.itens) ~= "table" then fila.itens = {} end
  if type(fila.proximo) ~= "number" then fila.proximo = 1 end
  return fila
end

function denuncias.salvar()
  return store.salvar(denuncias.CAMINHO, fila)
end

-- ------------------------------------------------------------------- criar

--- Registra uma denuncia.
--
-- @param de quem denunciou (canonico)
-- @param sobre quem foi denunciado (canonico)
-- @param buscarTexto funcao(quem, de) -> recado, para pegar o ultimo recado
--        recebido. Passada de fora para este modulo nao depender de recados -
--        e para o teste poder provar que o texto NAO vem do aparelho.
-- @return a denuncia, ou nil + motivo
function denuncias.criar(de, sobre, buscarTexto)
  if de == sobre then return nil, "nao da para denunciar a propria linha" end

  -- Uma denuncia por par, enquanto a primeira nao for resolvida. Sem isto,
  -- apertar a tecla tres vezes vira tres denuncias iguais na fila da operadora.
  for _, d in ipairs(fila.itens) do
    if not d.resolvida and d.de == de and d.sobre == sobre then
      return nil, "voce ja denunciou esse numero"
    end
  end

  local recado = buscarTexto and buscarTexto(de, sobre) or nil
  if not recado then
    return nil, "nao ha recado dessa pessoa para denunciar"
  end

  local d = {
    n = fila.proximo,
    de = de,
    sobre = sobre,
    texto = recado.texto,
    quandoRecado = recado.quando,
    quando = os.epoch("utc"),
    resolvida = false,
  }
  fila.proximo = fila.proximo + 1
  fila.itens[#fila.itens + 1] = d

  -- aparo em lote, como no historico de recados: cortar de um em um pela
  -- posicao 1 desloca a tabela inteira a cada corte
  if #fila.itens > denuncias.MAX + 50 then
    local nova = {}
    for i = #fila.itens - denuncias.MAX + 1, #fila.itens do
      nova[#nova + 1] = fila.itens[i]
    end
    fila.itens = nova
  end

  denuncias.salvar()
  return d
end

-- ---------------------------------------------------------------- consulta

--- As que ainda esperam, mais recentes primeiro.
function denuncias.pendentes()
  local saida = {}
  for _, d in ipairs(fila.itens) do
    if not d.resolvida then saida[#saida + 1] = d end
  end
  table.sort(saida, function(a, b) return a.n > b.n end)
  return saida
end

--- Quantas esperam. E o unico numero que o painel pode mostrar.
function denuncias.quantasPendentes()
  local n = 0
  for _, d in ipairs(fila.itens) do
    if not d.resolvida then n = n + 1 end
  end
  return n
end

--- Quantas vezes este numero ja foi denunciado, resolvidas incluidas.
--
-- E o dado que muda a decisao da operadora: uma denuncia pode ser briga de
-- dois; cinco denuncias de cinco pessoas diferentes sao outra coisa. Por isso
-- devolve tambem quantas pessoas DIFERENTES denunciaram.
function denuncias.historicoDe(canonico)
  local total, resolvidas = 0, 0
  local quem = {}
  for _, d in ipairs(fila.itens) do
    if d.sobre == canonico then
      total = total + 1
      if d.resolvida then resolvidas = resolvidas + 1 end
      quem[d.de] = true
    end
  end
  local pessoas = 0
  for _ in pairs(quem) do pessoas = pessoas + 1 end
  return total, pessoas, resolvidas
end

function denuncias.quantas()
  return #fila.itens
end

-- --------------------------------------------------------------- resolver

--- Marca como resolvida. <como> vai para o registro, para a operadora lembrar
-- o que ela decidiu quando o mesmo numero aparecer de novo.
function denuncias.resolver(n, como)
  for _, d in ipairs(fila.itens) do
    if d.n == n and not d.resolvida then
      d.resolvida = true
      d.comoAcabou = como or "arquivada"
      d.quandoResolvida = os.epoch("utc")
      denuncias.salvar()
      return d
    end
  end
  return nil, "denuncia nao encontrada"
end

--- Some com tudo que envolve uma linha cassada, dos DOIS lados.
--
-- Do lado do denunciado e obvio. Do lado de quem denunciou tambem: se a linha
-- de quem denunciou for cassada, as denuncias dela carregam recados de uma
-- conversa que a FALAE disse ter apagado.
function denuncias.esquecer(canonico)
  local nova, foram = {}, 0
  for _, d in ipairs(fila.itens) do
    if d.de == canonico or d.sobre == canonico then
      foram = foram + 1
    else
      nova[#nova + 1] = d
    end
  end
  if foram == 0 then return 0 end
  fila.itens = nova
  denuncias.salvar()
  return foram
end

return denuncias
