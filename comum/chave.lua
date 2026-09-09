--[[ chave - o segredo que mora num disquete

  Uma CHAVE da FALAE e um disquete. Quem tem o disquete na mao e sabe o PIN
  liga a central e opera o balcao; quem nao tem, nao.

  TRES COISAS FAZEM ELA VALER ALGUMA COISA, e nenhuma e criptografia - o CC nao
  tem criptografia de verdade e fingir que tem seria pior que nao ter:

  1. O SELO E AMARRADO AO ID DO DISQUETE. Cada disquete do Minecraft tem um
     numero proprio, e ele NAO acompanha uma copia dos arquivos: copiar
     chave.falae para outro disquete leva o arquivo e deixa o numero para tras.
     O id que a conta usa vem do DRIVE, nunca do que esta escrito no arquivo -
     entao a copia deriva outro segredo e nao abre nada. E o id tambem nao da
     para escolher: o mundo entrega numero novo a cada disquete e nunca repete
     um que ja saiu, entao ninguem fabrica um disquete com o numero da sua
     chave.

  2. O SEGREDO VAI CIFRADO PELO PIN, e o disquete NAO SABE conferir o PIN.
     Nao ha resumo do PIN gravado nele, nada com que comparar. Um PIN errado
     produz um segredo errado, silenciosamente. Quem achar o disquete no chao
     so descobre se acertou perguntando a maquina - que freia a cada erro e
     escreve no log. Isso importa porque em Minecraft voce morre e derruba o
     inventario: o disquete perdido nao pode ser a chave inteira.

  3. A MAQUINA GUARDA SO A IMPRESSAO. Ler o disco da central da a impressao do
     segredo, e nao o segredo: ninguem fabrica uma chave a partir do que a
     central guarda.

  ATE ONDE ISSO VAI. Quem levar o disquete E o disco da central junto pode
  tentar adivinhar o PIN offline, sem freio nenhum, comparando com a impressao.
  E por isso que o resumo daqui e lento de proposito e que o PIN do operador e
  maior que o do cliente. Nao existe conserto melhor dentro do CC; existe
  encarecer, e e o que este arquivo faz.
]]

local chave = {}

chave.VERSAO  = 1
chave.ARQUIVO = "chave.falae"     -- dentro do disquete

-- Voltas do resumo. Cada tentativa de PIN paga isto, inclusive a de quem
-- estiver adivinhando offline.
--
-- Medido no CraftOS-PC: com 900 voltas, varrer um PIN de seis digitos offline
-- levava cinco horas - rapido demais para uma coisa que abre a empresa. Com
-- 3000, um destrancar continua na casa do quarto de segundo e a varredura sobe
-- junto. O numero e uma troca, e esta aqui em cima para poder ser mexido:
-- subir encarece o ataque E a espera de quem esta na frente da maquina.
chave.VOLTAS = 3000

-- O PIN do operador e MAIOR que o do cliente, e a conta e esta: o do cliente e
-- protegido pelo freio da central, que nunca deixa passar de umas poucas
-- tentativas por minuto. Este aqui pode ser atacado offline por quem levar o
-- disquete E o disco da maquina, e ai o unico freio e o tamanho.
--
--   6 digitos, 3000 voltas  ->  umas 17 horas
--   8 digitos               ->  uns 70 dias
--  10 digitos               ->  uns 19 anos
--
-- Oito e o piso porque abaixo dele o numero deixa de assustar.
chave.PIN_MIN = 8
chave.PIN_MAX = 12

chave.SEGREDO_DIGITOS = 32        -- 128 bits de segredo
chave.SAL_DIGITOS     = 16

chave.PAPEIS = { central = true, loja = true }

-- Semear uma vez so por computador. Duas semeaduras com a mesma conta, no
-- mesmo milissegundo, reiniciariam a sequencia - e os "aleatorios" seguintes
-- repetiriam os que ja sairam.
if not _G.__falaeSemeado then
  math.randomseed((os.epoch("utc") % 2147483647) + os.getComputerID() * 7919)
  _G.__falaeSemeado = true
end

-- --------------------------------------------------------------- resumo

-- Quatro djb2 com sementes diferentes, concatenados: 128 bits. Um djb2 sozinho
-- da 32, e 32 bits colidem por acaso mais cedo do que a gente gostaria numa
-- coisa que abre porta.
local SEMENTES = { 5381, 33427, 63689, 1000003 }

--- Resumo largo e lento de um texto.
-- @param voltas quantas passagens (mais voltas = mais caro para quem adivinha)
function chave.resumir(texto, voltas)
  texto = tostring(texto)
  voltas = voltas or 1

  local partes = {}
  for k = 1, #SEMENTES do
    local h = SEMENTES[k]
    local t = texto .. ":" .. k
    for _ = 1, voltas do
      for i = 1, #t do
        h = (h * 33 + t:byte(i)) % 4294967296
      end
      -- realimenta o texto a cada volta para o custo nao poder ser cortado
      t = string.format("%08x", h) .. texto
    end
    partes[k] = string.format("%08x", h)
  end
  return table.concat(partes)
end

-- ------------------------------------------------------------------ bits

--- XOR de dois textos hexadecimais, digito a digito.
--
-- Na mao, sem bit32 nem os operadores de bit: o Lua do CC e o do banco de
-- testes nao sao a mesma versao, e uma conta que existe num e nao no outro e
-- uma conta que quebra so dentro do jogo.
local function xorHex(a, b)
  local saida = {}
  for i = 1, #a do
    local x = tonumber(a:sub(i, i), 16) or 0
    local y = tonumber(b:sub(i, i), 16) or 0
    local r, peso = 0, 1
    for _ = 1, 4 do
      if (x % 2) ~= (y % 2) then r = r + peso end
      x, y, peso = math.floor(x / 2), math.floor(y / 2), peso * 2
    end
    saida[i] = string.format("%x", r)
  end
  return table.concat(saida)
end

chave.xorHex = xorHex

local function aleatorio(n)
  local d = {}
  for i = 1, n do d[i] = string.format("%x", math.random(0, 15)) end
  return table.concat(d)
end

function chave.novoSegredo() return aleatorio(chave.SEGREDO_DIGITOS) end

-- ------------------------------------------------------------------ regras

function chave.pinValido(pin)
  pin = tostring(pin or "")
  if not pin:match("^%d+$") then return nil, "o PIN e so de numeros" end
  if #pin < chave.PIN_MIN or #pin > chave.PIN_MAX then
    return nil, ("o PIN da chave tem de %d a %d digitos"):format(
                chave.PIN_MIN, chave.PIN_MAX)
  end
  return pin
end

-- ------------------------------------------------------------------- selo

--- O fluxo que cifra o segredo. Depende do PIN, do sal e DO ID DO DISQUETE.
--
-- O id entra aqui para a copia do arquivo em outro disquete derivar outro
-- fluxo. Nao e enfeite: e a unica coisa que impede copiar a chave.
function chave.fluxo(pin, sal, disco, quantos)
  local saida = {}
  local bloco = 0
  while #saida < quantos do
    bloco = bloco + 1
    local h = chave.resumir(
      table.concat({ tostring(pin), tostring(sal), tostring(disco), bloco }, "|"),
      chave.VOLTAS)
    for i = 1, #h do
      saida[#saida + 1] = h:sub(i, i)
      if #saida >= quantos then break end
    end
  end
  return table.concat(saida)
end

--- Fecha um segredo num selo, para gravar no disquete.
-- @return { v, disco, sal, cifrado }
function chave.selar(disco, segredo, pin)
  local sal = aleatorio(chave.SAL_DIGITOS)
  return {
    v       = chave.VERSAO,
    disco   = disco,
    sal     = sal,
    cifrado = xorHex(segredo, chave.fluxo(pin, sal, disco, #segredo)),
  }
end

--- Abre um selo. SEMPRE devolve alguma coisa quando o selo tem forma valida -
-- inclusive com o PIN errado, e ai o que sai e lixo.
--
-- E de proposito, e e a parte que mais importa: um "abrir" que dissesse "PIN
-- errado" transformaria o disquete num oraculo offline, e quem o achasse no
-- chao poderia adivinhar o PIN em casa, sem freio e sem deixar rastro. Assim,
-- descobrir se acertou exige perguntar a maquina - que conta as tentativas.
--
-- @param discoReal o id lido do DRIVE, nunca o que esta escrito no selo
function chave.abrir(selo, discoReal, pin)
  if type(selo) ~= "table" then return nil, "selo ilegivel" end
  if selo.v ~= chave.VERSAO then return nil, "selo de outra versao" end
  if type(selo.sal) ~= "string" or type(selo.cifrado) ~= "string" then
    return nil, "selo incompleto"
  end
  return xorHex(selo.cifrado,
                chave.fluxo(pin, selo.sal, discoReal, #selo.cifrado))
end

--- A impressao que a maquina guarda no lugar do segredo.
function chave.impressao(disco, segredo, sal)
  return chave.resumir(
    table.concat({ tostring(sal), tostring(disco), tostring(segredo) }, "|"),
    chave.VOLTAS)
end

function chave.novoSal() return aleatorio(chave.SAL_DIGITOS) end

return chave
