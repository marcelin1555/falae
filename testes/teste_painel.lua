--[[ teste_painel - os monitores da central

  O painel e a parte do sistema que parece nao ter consequencia se estiver
  errada - e tem duas.

  A primeira e desempenho: monitor de CC e sincronizado com todo cliente por
  perto, entao redesenhar a toa vira trafego no servidor Minecraft inteiro,
  inclusive para quem so passou andando pela sala. O painel promete nao
  escrever nada quando nada mudou, e essa promessa e invisivel quando cumprida.

  A segunda e a central cair junto. Alguem quebra o bloco do monitor com a
  central rodando, e o programa que estava desenhando nele levanta erro. Um
  painel que derruba a operadora inteira por causa de um bloco quebrado e pior
  do que nao ter painel.

  E ha o caso que so aparece no mundo: monitor de 8x4 blocos muda de tamanho
  conforme a escala do texto. Escolher errado nao quebra nada - so deixa o
  painel com letra de bula, e ninguem descobre por codigo.
]]

local PROJETO = ...

local mock = dofile(PROJETO .. "/testes/cc_mock.lua")
mock.instalar()
mock.montarCentral(PROJETO, true)
mock.instalarDofile()

local total, falhas = 0, 0

local function ok(condicao, titulo, detalhe)
  total = total + 1
  if condicao then
    print("  ok   " .. titulo)
  else
    falhas = falhas + 1
    print("  FALHA " .. titulo .. (detalhe and ("  -> " .. tostring(detalhe)) or ""))
  end
end

local function igual(a, b, titulo)
  ok(a == b, titulo, ("esperava [%s], veio [%s]"):format(tostring(b), tostring(a)))
end

local lib     = dofile("/core/lib.lua")
local central = lib("central")
local painel  = lib("painel")
local linhas  = lib("linhas")
local recados = lib("recados")

central.prepararDados()

-- um pouco de movimento, para os numeros nao serem todos zero
local numeros = {}
for i = 1, 7 do
  local l = linhas.criar("cliente" .. i, "1234", 100 + i)
  numeros[#numeros + 1] = l.numero
end
for i = 1, 40 do recados.enviar(numeros[1], numeros[2], "recado " .. i) end

local estado = central.estado
estado.modem = "ender_modem_0"
estado.pedidos = 4821
estado.recusas = 3
estado.rapidas = 4402
estado.desde = mock.relogio - 95 * 60 * 1000

local custos = {
  { rota = "msg.novidades", n = 4402, tempo = 0.812, media = 0.0002 },
  { rota = "msg.enviar",    n = 40,   tempo = 0.334, media = 0.008 },
  { rota = "linha.entrar",  n = 14,   tempo = 0.201, media = 0.014 },
}

-- ---------------------------------------------------------------- a escala

print("\n-- a escala do texto sai do tamanho do monitor --")

local m8x4 = mock.monitorBlocos(8, 4)
local escolhida = painel.escala(m8x4)
local c, l = m8x4.getSize()
print(("     8x4 blocos -> escala %s, %dx%d caracteres"):format(tostring(escolhida), c, l))

ok(c >= painel.MINIMO, "o 8x4 fica com largura util", c)
ok(c <= 90, "e nao com letra de bula (164 colunas em escala 0.5)", c)
igual(l >= 12, true, "e com altura suficiente para a marca e o estado")

-- um monitor pequeno tem que continuar funcionando, so que apertado
local m2x2 = mock.monitorBlocos(2, 2)
painel.escala(m2x2)
local c2 = m2x2.getSize()
ok(c2 >= 1, "monitor pequeno tambem recebe uma escala", c2)

-- ------------------------------------------------------- dois monitores

print("\n-- dois monitores dividem o conteudo --")

local mA = mock.monitorBlocos(8, 4)
local mB = mock.monitorBlocos(8, 4)
local achados = {
  { nome = "monitor_0", mon = mA },
  { nome = "monitor_1", mon = mB },
}

igual(painel.ligar(achados), 2, "os dois entram")
painel.atualizar(estado, custos)
igual(#painel.errosNovos(), 0, "e nenhum deu erro")

local textoA, textoB = mA.tudo(), mB.tudo()

-- O nome nao e procurado como texto: quando ha resolucao, ele e DESENHADO em
-- subpixel e nao existe como caractere na tela. O que se confere e o balao -
-- celulas pintadas de amarelo, que e a cor da marca.
local function temAmarelo(m)
  local w, h = m.getSize()
  local n = 0
  for y = 1, h do
    for x = 1, w do
      local c = m.celulas[y][x]
      if c.fg == "4" or c.bg == "4" then n = n + 1 end
    end
  end
  return n
end

ok(temAmarelo(mA) > 50, "o balao da marca aparece no primeiro",
   ("celulas amarelas: %d"):format(temAmarelo(mA)))
ok(textoA:find("NO AR", 1, true) ~= nil, "com o estado")
ok(textoA:find("7 linha", 1, true) ~= nil, "e quantas linhas existem")

ok(textoB:find("movimento", 1, true) ~= nil, "o segundo mostra o movimento")
ok(textoB:find("4821", 1, true) ~= nil, "com os pedidos atendidos")
ok(textoB:find("msg.novidades", 1, true) ~= nil, "e o custo por rota")

-- o conteudo nao pode aparecer nos dois: seria desperdicio de duas telas
ok(textoB:find("msg.novidades", 1, true) and not textoA:find("msg.novidades", 1, true),
   "o custo por rota fica so no monitor do movimento")

-- ------------------------------------------------ o redesenho que nao custa

print("\n-- parado, o painel nao escreve nada --")

mA.zerarContador()
mB.zerarContador()
painel.atualizar(estado, custos)
local escritasA = mA.contador()
local escritasB = mB.contador()

-- Esta e a promessa do arquivo: com a FALAE parada, um minuto inteiro de
-- painel nao gera uma escrita sequer. Se alguem trocar o campo() por um
-- escrever() direto, tudo continua parecendo certo na tela e o custo volta.
igual(escritasA, 0, "nada mudou, nada foi escrito no monitor da marca")
igual(escritasB, 0, "nem no do movimento")

-- e quando muda, escreve
recados.enviar(numeros[1], numeros[3], "novidade")
estado.pedidos = estado.pedidos + 1
mA.zerarContador()
mB.zerarContador()
painel.atualizar(estado, custos)
ok(mB.contador() > 0, "quando o numero muda, ele e reescrito")

-- ------------------------------------------------------------ sem modem

print("\n-- a marca apaga quando a central perde o modem --")

estado.modem = nil
painel.atualizar(estado, custos)
ok(mA.tudo():find("SEM MODEM", 1, true) ~= nil,
   "o monitor da marca avisa que esta fora do ar")

estado.modem = "ender_modem_0"
painel.atualizar(estado, custos)
ok(mA.tudo():find("NO AR", 1, true) ~= nil, "e volta quando o modem volta")

-- --------------------------------------------------------------- inverter

print("\n-- trocar o que cada monitor mostra --")

painel.inverter()
painel.atualizar(estado, custos)
ok(mA.tudo():find("movimento", 1, true) ~= nil,
   "depois de inverter, o primeiro mostra o movimento")
ok(mB.tudo():find("NO AR", 1, true) ~= nil, "e o segundo, a marca")

-- a escolha tem que sobreviver a um reinicio da central: quem virou a sala
-- nao pode ter que virar de novo toda vez que o chunk descarrega
painel.desligar()
local painel2 = dofile("/tela/painel.lua")
painel2.ligar(achados)
painel2.atualizar(estado, custos)
ok(mA.tudo():find("movimento", 1, true) ~= nil,
   "e continua invertido depois de recarregar do disco")

painel2.inverter()   -- devolve ao normal para os testes seguintes
painel2.desligar()

-- ----------------------------------------------------------- um monitor so

print("\n-- com um monitor so, tudo cabe nele --")

local unico = mock.monitorBlocos(8, 4)
igual(painel.ligar({ { nome = "monitor_0", mon = unico } }), 1, "um monitor entra")
painel.atualizar(estado, custos)

local texto = unico.tudo()
ok(texto:find("FALAE", 1, true) ~= nil, "a marca esta la")
ok(texto:find("linhas", 1, true) ~= nil, "e os numeros tambem")
igual(#painel.errosNovos(), 0, "sem erro")

-- ------------------------------------------------------------ sem monitor

print("\n-- sem monitor nenhum --")

igual(painel.ligar({}), 0, "ligar sem monitor devolve zero")
igual(painel.quantas(), 0, "e nenhuma tela fica registrada")
ok(painel.atualizar(estado, custos) == false,
   "atualizar sem monitor nao explode - a central roda sem painel")

-- ------------------------------------------------------------ diagnostico

print("\n-- o diagnostico responde 'os dois estao funcionando?' --")

painel.ligar(achados)
painel.atualizar(estado, custos)
local diag = painel.diagnostico()

igual(#diag, 2, "lista os dois monitores")
igual(diag[1].nome, "monitor_0", "com o nome de cada um")
ok(diag[1].papel == "marca" or diag[1].papel == "movimento",
   "e o que cada um mostra", diag[1].papel)
ok(diag[1].colunas > 0 and diag[1].linhas > 0, "e o tamanho em caracteres",
   ("%dx%d"):format(diag[1].colunas, diag[1].linhas))
ok(diag[1].escala ~= nil, "e a escala escolhida", tostring(diag[1].escala))

-- o monitor da marca tem que dizer se o nome coube desenhado: e a diferenca
-- entre a logo bonita e o nome na fonte do terminal
local daMarca
for _, m in ipairs(diag) do if m.papel == "marca" then daMarca = m end end
ok(daMarca ~= nil, "um deles e o da marca")
ok(daMarca.nomeDesenhado ~= nil, "e ele conta se o nome saiu desenhado",
   tostring(daMarca and daMarca.nomeDesenhado))

painel.ligar({ { nome = "monitor_0", mon = unico } })
igual(#painel.diagnostico(), 1, "com um monitor so, lista um")

painel.ligar({})
igual(#painel.diagnostico(), 0, "sem monitor, lista vazia")

-- ------------------------------------------------- monitor que da problema

print("\n-- alguem quebra o bloco do monitor --")

local quebrado = mock.monitorBlocos(8, 4)
painel.ligar({ { nome = "monitor_0", mon = quebrado } })
painel.atualizar(estado, custos)
painel.errosNovos()

-- e o que o CC faz quando o periferico some: as chamadas passam a levantar
quebrado.write = function() error("Terminal is not attached", 0) end
quebrado.clear = function() error("Terminal is not attached", 0) end

-- Precisa mudar algum numero, senao o painel nao tenta escrever e nem fica
-- sabendo que o monitor sumiu. Isso e o desenho funcionando, nao um defeito:
-- ele so descobre o problema no momento em que teria algo a dizer - e ate la
-- nao havia nada a mostrar mesmo.
estado.pedidos = estado.pedidos + 7

local sobreviveu = pcall(painel.atualizar, estado, custos)
ok(sobreviveu, "o painel nao derruba a central quando o monitor some")

local erros = painel.errosNovos()
ok(#erros > 0, "e o problema aparece, em vez de a tela ficar preta em silencio")
ok(tostring(erros[1]):find("monitor_0", 1, true) ~= nil,
   "dizendo qual monitor", erros[1])

-- so uma vez: repetir a cada 3 segundos encheria o log da central sozinho
painel.atualizar(estado, custos)
igual(#painel.errosNovos(), 0, "e o mesmo erro nao repete no log a cada ciclo")

painel.desligar()

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
