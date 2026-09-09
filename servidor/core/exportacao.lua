--[[ exportacao - a UNICA porta pela qual o texto de um recado sai por
     ordem judicial

  A FALAE nao manda texto de conversa para lugar nenhum pela rede - nem para
  outro aparelho, nem para o painel externo. O painel (ver
  servidor/core/telemetria.lua) so manda numero. Quando um juiz pede uma
  conversa, o caminho e este arquivo: fisico, manual, e registrado para
  sempre.

  TRES REGRAS, no codigo e nao so no comentario:

  1. NUNCA PELA REDE. Este modulo nao importa protocolo nem chama rednet ou
     http em lugar nenhum. O resultado vai para um DISQUETE, o mesmo objeto
     fisico que ja e a chave da central - quem exporta carrega o resultado na
     mao, para fora do computador.

  2. O MOTIVO E OBRIGATORIO E FICA GRAVADO. Uma exportacao sem motivo
     declarado nao acontece. O motivo, quem pediu e quando vao para dentro do
     proprio arquivo exportado E para um log em separado que nunca e apagado
     nem aparado - ver exportacao.LOG.

  3. SO ATRAS DA CHAVE. A tela do console que chama isto (console.lua,
     console.exportarJudicial) exige console.exigir() antes - a mesma chave
     por disquete que ja tranca denuncia e cassacao. Isto aqui so monta o
     texto; quem manda a pessoa provar quem e e o console.
]]

local lib     = dofile("/core/lib.lua")
local numero  = lib("numero")
local recados = lib("recados")
local store   = lib("store")

local exportacao = {}

-- Append-only, e ISTO NUNCA APARA. O log principal da central (estado.log)
-- guarda so as ultimas 100 linhas porque e um mural de operacao; este aqui e
-- uma prova de auditoria - perder uma linha dele e perder a prova de que uma
-- exportacao aconteceu.
exportacao.LOG = "/dados/exportacoes.log"

local function linhaDoLog(registro)
  -- formato de linha, como recados.log: cabe numa linha, nao quebra com o
  -- separador porque so o motivo (por ultimo) pode conter qualquer coisa
  return table.concat({
    registro.quando, registro.quem, registro.numeroA,
    registro.numeroB or "", registro.motivo,
  }, "|")
end

--- Registra uma exportacao no log de auditoria. Nunca falha em silencio: se
-- nao conseguir gravar, quem chamou precisa saber - uma exportacao sem rastro
-- e exatamente o que este arquivo existe para impedir.
local function registrar(quem, numeroA, numeroB, motivo)
  local registro = {
    quando = os.epoch("utc"), quem = tostring(quem or "?"),
    numeroA = numeroA, numeroB = numeroB, motivo = motivo,
  }
  return store.anexar(exportacao.LOG, linhaDoLog(registro))
end

--- As linhas do log de auditoria, mais recente por ultimo (como foram
-- escritas). Para a tela do console poder mostrar as ultimas exportacoes.
function exportacao.historico()
  local saida = {}
  for _, l in ipairs(store.linhas(exportacao.LOG)) do
    local quando, quem, numeroA, numeroB, motivo =
      l:match("^(%-?%d+)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if quando then
      saida[#saida + 1] = {
        quando = tonumber(quando), quem = quem, numeroA = numeroA,
        numeroB = numeroB ~= "" and numeroB or nil, motivo = motivo,
      }
    end
  end
  return saida
end

-- ------------------------------------------------------------------- montar

--- Formata um recado para o arquivo exportado.
--
-- Data e hora de verdade, com os.date - NAO textutils.formatTime. formatTime
-- espera "hora do dia" (0 a 24, o relogio do Minecraft) e trata um epoch em
-- segundos como se fosse isso: o resultado sai tipo "1788992099:40", um
-- numero sem sentido nenhum. Conferido no CraftOS-PC.
local function linhaRecado(m)
  local quando = os.date("!%Y-%m-%d %H:%M:%S", math.floor(m.quando / 1000))
  return ("[%s UTC] %s -> %s: %s"):format(
    quando, numero.formatar(m.de), numero.formatar(m.para), m.texto)
end

--- Monta o texto de uma exportacao judicial, e registra no log de auditoria.
--
-- @param numeroA canonico, obrigatorio
-- @param numeroB canonico, ou nil - vazio exporta TUDO que numeroA envolveu,
--        nao so a conversa com uma pessoa
-- @param motivo texto livre, obrigatorio - vai para o cabecalho e para o log
-- @param quem nome de quem esta pedindo (a chave que abriu o balcao)
-- @return o texto pronto para gravar, ou nil + motivo
function exportacao.montar(numeroA, numeroB, motivo, quem)
  local a, erro = numero.canonico(numeroA)
  if not a then return nil, erro end

  local b = nil
  if numeroB and numeroB ~= "" then
    b, erro = numero.canonico(numeroB)
    if not b then return nil, erro end
  end

  motivo = tostring(motivo or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if motivo == "" then return nil, "o motivo e obrigatorio" end

  local msgs = b and recados.conversa(a, b, math.huge) or recados.tudoDe(a)

  local linhas = {
    "FALAE - exportacao judicial",
    "",
    "pedida por : " .. tostring(quem or "?"),
    "quando     : " .. os.date("!%Y-%m-%d %H:%M:%S", math.floor(os.epoch("utc") / 1000)) .. " UTC",
    "numero A   : " .. numero.formatar(a),
    "numero B   : " .. (b and numero.formatar(b) or "(toda a linha de A)"),
    "motivo     : " .. motivo,
    "recados    : " .. #msgs,
    "",
    "----------------------------------------------------------------",
    "",
  }

  if #msgs == 0 then
    linhas[#linhas + 1] = "(nenhum recado encontrado)"
  else
    for _, m in ipairs(msgs) do
      linhas[#linhas + 1] = linhaRecado(m)
    end
  end

  -- registra ANTES de devolver: se a gravacao no disquete falhar depois, o
  -- pedido ja ficou provado - o rastro e do PEDIDO, nao do sucesso da copia
  registrar(quem, a, b, motivo)

  return table.concat(linhas, "\n") .. "\n"
end

--- O nome de arquivo de uma exportacao nova, unico o bastante para nao
-- sobrescrever a de outro caso no mesmo disquete.
--
-- NAO USA "%d" COM os.epoch(). Confirmado no CraftOS-PC: um epoch em
-- milissegundos e grande demais para o inteiro que "%d" espera, e
-- string.format levanta "bad argument (not a number in proper range)". O
-- resto do projeto (recados.lua, entre outros) sempre grava epoch por
-- concatenacao - e por isso, nao por acaso.
function exportacao.nomeArquivo()
  return "exportacao_" .. os.epoch("utc") .. ".txt"
end

return exportacao
