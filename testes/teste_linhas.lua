--[[ teste_linhas - contas, PIN, sessao e o freio

  O freio e o assunto principal deste arquivo. Um PIN de quatro digitos tem dez
  mil possibilidades: nenhuma funcao de resumo torna isso seguro, e o que
  segura de verdade e a espera que cresce a cada erro. Se o freio parar de
  funcionar, a FALAE fica aberta e ninguem percebe - nao ha sintoma visivel.
  Por isso ele e testado aqui, e nao o resumo.

  O outro assunto: a sessao tem que sobreviver ao chunk descarregar. Em
  Minecraft isso acontece o tempo todo, e sessao so em memoria deslogaria a
  cidade inteira toda vez que ninguem passasse perto da central.
]]

local PROJETO = ...

local mock = dofile(PROJETO .. "/testes/cc_mock.lua")
mock.instalar()
mock.montarCentral(PROJETO, false)
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
  ok(a == b, titulo, ("esperava %s, veio %s"):format(tostring(b), tostring(a)))
end

local lib    = dofile("/core/lib.lua")
local numero = lib("numero")
local linhas = lib("linhas")

linhas.carregar()

--- Faz o relogio do mock andar. E como se testa espera sem esperar.
local function avancar(segundos)
  mock.relogio = mock.relogio + segundos * 1000
end

-- ------------------------------------------------------------------- criar

print("\n-- criar linha --")
local ana, tokenAna = linhas.criar("Ana", "1234", 42)
ok(ana ~= nil, "linha criada", tokenAna)
ok(ana and #ana.numero == 13, "numero sorteado com 13 digitos")
igual(ana and ana.nome, "Ana", "guarda o nome")
ok(type(tokenAna) == "string" and #tokenAna == 24, "sai com sessao aberta")

ok(select(1, linhas.criar("", "1234", 1)) == nil, "nome vazio e recusado")
ok(select(1, linhas.criar("Bruno", "12", 1)) == nil, "PIN curto e recusado")
ok(select(1, linhas.criar("Bruno", "123456789", 1)) == nil, "PIN longo e recusado")
ok(select(1, linhas.criar("Bruno", "12ab", 1)) == nil, "PIN com letra e recusado")
ok(select(1, linhas.criar("Bruno", "12345678", 1)) ~= nil, "PIN de 8 digitos e aceito")

-- o nome nao pode virar um jeito de escrever varias linhas na tela dos outros
local torto = linhas.criar("Ana\ndois", "1234", 1)
ok(torto and not torto.nome:find("\n"), "quebra de linha some do nome")
local longo = linhas.criar(string.rep("x", 40), "1234", 1)
ok(longo and #longo.nome <= linhas.NOME_MAX, "nome comprido e cortado")

print("\n-- o que a central conta sobre uma linha --")
local pub = linhas.publico(ana.numero)
ok(pub.nome == "Ana" and pub.numero == ana.numero, "publico traz numero e nome")
ok(pub.sal == nil and pub.resumo == nil, "publico NAO traz sal nem resumo do PIN")

-- ------------------------------------------------------------------ entrar

print("\n-- entrar --")
local t1 = linhas.entrar(ana.numero, "1234", 7)
ok(type(t1) == "string", "entra com o PIN certo")
ok(t1 ~= tokenAna, "cada login abre uma sessao nova")

ok(select(1, linhas.entrar(numero.formatar(ana.numero), "1234", 7)) ~= nil,
   "entra digitando o numero formatado")

local nada, motivo = linhas.entrar("5599999999999", "1234", 7)
ok(nada == nil, "numero que nao existe e recusado")
igual(motivo, "numero ou PIN errado", "e recusado com a MESMA frase de PIN errado")

-- Se a resposta fosse diferente, a tela de login viraria um consultor de
-- quais numeros existem na FALAE, e a lista de clientes nao e publica.
local _, motivo2 = linhas.entrar(ana.numero, "9999", 7)
igual(motivo2, "numero ou PIN errado", "PIN errado da a mesma frase")

-- -------------------------------------------------------------------- freio

print("\n-- o freio de tentativas --")
local bruno = linhas.criar("Bruno", "4321", 9)

-- os dois primeiros erros nao custam espera: quem errou o dedo tenta de novo
linhas.entrar(bruno.numero, "0000", 9)
igual(linhas.travada(bruno.numero), 0, "1o erro nao trava")
linhas.entrar(bruno.numero, "0000", 9)
igual(linhas.travada(bruno.numero), 0, "2o erro nao trava")

linhas.entrar(bruno.numero, "0000", 9)
ok(linhas.travada(bruno.numero) > 0, "3o erro trava")

-- e a trava vale mesmo para quem acertar o PIN: sem isso, o freio nao freia
local durante, porque = linhas.entrar(bruno.numero, "4321", 9)
ok(durante == nil, "travada, nem o PIN certo entra")
ok(porque and porque:find("espere"), "e a recusa diz quanto falta", porque)

avancar(2)
ok(linhas.travada(bruno.numero) > 0, "2s depois ainda esta travada")
avancar(5)
igual(linhas.travada(bruno.numero), 0, "passou o tempo, destravou")
ok(linhas.entrar(bruno.numero, "4321", 9) ~= nil, "destravada, o PIN certo entra")

-- acertar zera o contador: senao, quem errou tres vezes na segunda-feira
-- pegaria um minuto de espera na sexta
linhas.entrar(bruno.numero, "0000", 9)
igual(linhas.travada(bruno.numero), 0, "depois de acertar, o contador zerou")

print("\n-- a espera cresce --")
local carla = linhas.criar("Carla", "1111", 3)
local esperas = {}
for i = 1, 6 do
  linhas.entrar(carla.numero, "0000", 3)
  esperas[i] = linhas.travada(carla.numero)
  avancar(120)   -- passa a trava para poder errar de novo
end
ok(esperas[3] > 0 and esperas[4] > esperas[3] and esperas[5] > esperas[4],
   "cada erro seguido custa mais que o anterior",
   table.concat(esperas, ","))
ok(esperas[6] >= 60, "chega em um minuto de espera", esperas[6])

-- ------------------------------------------------------------------ sessao

print("\n-- sessao --")
local dono = linhas.sessao(t1)
ok(dono ~= nil and dono.numero == ana.numero, "o token diz de quem e a linha")
ok(select(1, linhas.sessao("naoexiste")) == nil, "token inventado nao vale")
ok(select(1, linhas.sessao(nil)) == nil, "sem token nao vale")
ok(select(1, linhas.sessao(42)) == nil, "token que nem e texto nao vale")

ok(linhas.sair(t1), "sair fecha a sessao")
ok(select(1, linhas.sessao(t1)) == nil, "depois de sair, o token nao vale mais")

print("\n-- a sessao sobrevive ao chunk descarregar --")
-- e o que acontece toda vez que ninguem passa perto da central; sessao so em
-- memoria deslogaria todo mundo nesse momento
local tokenVivo = select(2, linhas.criar("Dani", "5555", 11))
linhas.salvar()
linhas.salvarSessoes()

-- sobe um modulo novo, do zero, lendo so o que ficou no disco
local linhas2 = dofile("/core/linhas.lua")
linhas2.carregar()
local sobreviveu = linhas2.sessao(tokenVivo)
ok(sobreviveu ~= nil, "o token continua valendo depois de recarregar do disco")

print("\n-- trocar PIN --")
local elias = linhas.criar("Elias", "1234", 21)
local tokenElias = select(2, linhas.criar("Fabio", "1234", 22))
ok(select(1, linhas.trocarPin(elias.numero, "9999", "5678")) == nil,
   "trocar PIN sem saber o atual e recusado")
ok(linhas.trocarPin(elias.numero, "1234", "5678"), "trocar PIN sabendo o atual")
ok(select(1, linhas.entrar(elias.numero, "1234", 21)) == nil, "o PIN velho nao entra mais")
ok(linhas.entrar(elias.numero, "5678", 21) ~= nil, "o PIN novo entra")

-- trocar o PIN tem que derrubar os outros aparelhos, senao nao trocou nada
local gil = linhas.criar("Gil", "1234", 31)
local tokenAntigo = select(1, linhas.entrar(gil.numero, "1234", 32))
linhas.trocarPin(gil.numero, "1234", "8888")
ok(select(1, linhas.sessao(tokenAntigo)) == nil,
   "trocar o PIN derruba as sessoes antigas")

-- --------------------------------------------------------------- o balcao

print("\n-- balcao: zerar PIN --")
local helo = linhas.criar("Helo", "1234", 51)
local tokenHelo = select(1, linhas.entrar(helo.numero, "1234", 51))

ok(linhas.zerarPin(helo.numero), "o balcao zera o PIN")
ok(linhas.semPin(helo.numero), "a linha fica marcada como sem PIN")
ok(select(1, linhas.sessao(tokenHelo)) == nil, "zerar derruba quem estava logado")

local _, recusa = linhas.entrar(helo.numero, "1234", 51)
ok(recusa and recusa:find("sem PIN"), "entrar avisa que precisa definir um novo", recusa)

local tokenNovo = linhas.definirPin(helo.numero, "7777", 51)
ok(type(tokenNovo) == "string", "define o PIN novo e ja entra")
ok(not linhas.semPin(helo.numero), "a marca de sem PIN sai")
ok(linhas.entrar(helo.numero, "7777", 51) ~= nil, "o PIN novo funciona")
ok(select(1, linhas.definirPin(helo.numero, "0000", 51)) == nil,
   "nao da para definir PIN por cima de uma linha que ja tem")

print("\n-- balcao: cassar linha --")
local ivo = linhas.criar("Ivo", "1234", 61)
local tokenIvo = select(1, linhas.entrar(ivo.numero, "1234", 61))
ok(linhas.remover(ivo.numero), "cassa a linha")
ok(not linhas.existe(ivo.numero), "a linha some do registro")
ok(select(1, linhas.sessao(tokenIvo)) == nil, "quem estava logado nela cai")
ok(not linhas.remover(ivo.numero), "cassar de novo nao explode")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
