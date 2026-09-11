--[[ teste_janela - as mesmas telas nos dois formatos

  Voce escolheu dois layouts de verdade, e o risco dessa escolha e conhecido:
  duas interfaces para manter em sincronia para sempre, com todo conserto
  precisando ser feito duas vezes e a segunda sendo esquecida.

  A saida foi fazer as telas nao saberem onde estao - cada uma desenha dentro
  de uma janela que recebe pronta. Este arquivo prova que a saida funciona:
  chama AS MESMAS funcoes de desenho em 26x20 e em 51x19 e confere que nenhuma
  escreve fora do proprio retangulo.

  O vazamento e o defeito que mais importa aqui, porque no arranjo de duas
  colunas uma linha comprida demais nao "fica feia": ela escreve por cima da
  coluna do lado, e o texto de uma conversa aparece dentro de outra.
]]

local PROJETO = ...

local mock = dofile(PROJETO .. "/testes/cc_mock.lua")
mock.instalar()
mock.montarCentral(PROJETO, false)
mock.montarTelefone(PROJETO)
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

-- pelo carregador, e nao por dofile: e assim que o telefone carrega de
-- verdade, e foi justamente a diferenca entre os dois que escondeu um bug
local carregar = dofile("/carregar.lua")
local janela = carregar("janela")
local campo  = carregar("campo")
local ritmo  = carregar("ritmo")
local agenda = carregar("agenda")

-- --------------------------------------------------------------- cortar

print("\n-- cortar e encher --")
igual(janela.cortar("abc", 10), "abc", "texto curto passa inteiro")
igual(janela.cortar("abcdefghij", 5), "ab...", "texto longo ganha reticencias")
igual(#janela.cortar("abcdefghij", 5), 5, "e cabe exatamente na largura")
igual(janela.cortar("abcdefghij", 2), "ab", "largura minuscula corta seco")
igual(janela.cortar(nil, 5), "", "nil nao explode")
igual(#janela.encher("ab", 6), 6, "encher completa ate a largura")
igual(#janela.encher("abcdefgh", 4), 4, "encher tambem corta o que passa")

print("\n-- centralizar --")
-- E o que faz um rotulo parecer BOTAO: colado na esquerda parece rodape de
-- atalho, no meio parece coisa que se aperta.
igual(#janela.centralizar("OK", 10), 10, "sempre preenche a largura pedida")
igual(janela.centralizar("OK", 10), "    OK    ", "com o texto no meio")
igual(janela.centralizar("ABCD", 5), "ABCD ", "largura impar sobra pro lado direito")
igual(janela.centralizar("abcdefghij", 5), janela.cortar("abcdefghij", 5),
      "texto maior que a largura corta como janela.cortar")

-- --------------------------------------------------------------- rolagem

print("\n-- rolagem --")
igual(janela.rolar(1, 3, 10, 1), 1, "lista que cabe nao rola")
igual(janela.rolar(1, 20, 5, 1), 1, "escolhido no topo")
igual(janela.rolar(7, 20, 5, 1), 3, "escolhido abaixo desce a janela")
igual(janela.rolar(2, 20, 5, 6), 2, "escolhido acima sobe a janela")
igual(janela.rolar(20, 20, 5, 1), 16, "no fim da lista, encosta no fim")

-- ---------------------------------------------------------------- quando

print("\n-- ha quanto tempo --")
local agora = 1700000000000
igual(janela.quando(agora - 5000, agora), "agora", "poucos segundos")
igual(janela.quando(agora - 120000, agora), "2m", "minutos")
igual(janela.quando(agora - 7200000, agora), "2h", "horas")
igual(janela.quando(agora - 90000000, agora), "ontem", "ontem")
igual(janela.quando(nil, agora), "", "sem data nao explode")

-- ------------------------------------------------------------------ campo

print("\n-- campo de texto --")
local c = campo.novo({ max = 10 })
campo.tecla(c, nil, "o")
campo.tecla(c, nil, "i")
igual(campo.valor(c), "oi", "digita")
campo.tecla(c, mock.KEYS.backspace)
igual(campo.valor(c), "o", "apaga")
campo.tecla(c, mock.KEYS.left)
campo.tecla(c, nil, "a")
igual(campo.valor(c), "ao", "escreve no meio, onde o cursor esta")

for _ = 1, 30 do campo.tecla(c, nil, "x") end
igual(#campo.valor(c), 10, "respeita o maximo")

local pin = campo.novo({ max = 8, mascara = "pin" })
campo.tecla(pin, nil, "1")
campo.tecla(pin, nil, "a")   -- letra em campo de PIN
igual(campo.valor(pin), "1", "campo de PIN recusa letra")
igual(campo.visivel(pin), "*", "e o PIN nao aparece na tela")

local num = campo.novo({ max = 13, mascara = "numero" })
for d in ("5511984723310"):gmatch(".") do campo.tecla(num, nil, d) end
igual(campo.valor(num), "5511984723310", "campo de numero guarda so digitos")
igual(campo.visivel(num), "+55 119 8472-3310", "e mostra formatado")
ok(campo.cursorVisivel(num) == #campo.visivel(num),
   "o cursor acompanha a mascara, nao o valor cru")

-- ------------------------------------------------------------------ ritmo

print("\n-- o ritmo do poll --")
local t0 = 1700000000000
local r = ritmo.novo(t0)

igual(ritmo.intervalo(r, t0, true), ritmo.RAPIDO, "acabou de acontecer algo: rapido")
igual(ritmo.intervalo(r, t0 + 30000, true), ritmo.RAPIDO, "30s depois ainda rapido")

igual(ritmo.intervalo(r, t0 + 90000, true), ritmo.CONVERSA,
      "conversa aberta e parada afrouxa um degrau")
igual(ritmo.intervalo(r, t0 + 90000, false), ritmo.LISTA,
      "na lista, afrouxa mais - ninguem esta esperando resposta ali")

igual(ritmo.intervalo(r, t0 + 400000, true), ritmo.LENTO,
      "esquecido no bolso: o degrau mais lento")
igual(ritmo.intervalo(r, t0 + 400000, false), ritmo.LENTO,
      "e o degrau mais lento vale nos dois casos")

-- E a parte que faz a diferenca para quem usa: qualquer sinal de vida derruba
-- tudo de volta. Sem isto, responder a uma mensagem depois de meia hora
-- parado levaria trinta segundos para a resposta aparecer.
ritmo.sinal(r, t0 + 400000)
igual(ritmo.intervalo(r, t0 + 400000, true), ritmo.RAPIDO,
      "uma tecla derruba o intervalo de volta para o mais rapido")
igual(ritmo.degrau(r, t0 + 400000, true), "vivo", "e o degrau se chama vivo")
igual(ritmo.degrau(r, t0 + 900000, false), "dormindo", "muito tempo depois, dormindo")

ok(ritmo.LENTO > ritmo.LISTA and ritmo.LISTA > ritmo.CONVERSA
   and ritmo.CONVERSA > ritmo.RAPIDO, "os degraus estao em ordem crescente")

-- ------------------------------------------------- desenho nos dois formatos

print("\n-- as MESMAS telas em 26x20 e 51x19 --")

local telas = {
  conversas = carregar("conversas"),
  conversa  = carregar("conversa"),
  contatos  = carregar("contatos"),
  perfil    = carregar("perfil"),
}

local C = {
  fundo = colors.black, texto = colors.white, fraco = colors.gray,
  marca = colors.yellow, marcaFraca = colors.brown, selecao = colors.gray,
  entrada = colors.gray, meu = colors.lightGray,
  bom = colors.lime, ruim = colors.red, aviso = colors.orange,
}

local EU    = "5511100000001"
local OUTRO = "5511100000002"

agenda.carregar()
agenda.salvar(OUTRO, "Bruno o Comprido")
local recados = {}
for i = 1, 30 do
  recados[i] = {
    n = i,
    de = (i % 2 == 0) and EU or OUTRO,
    para = (i % 2 == 0) and OUTRO or EU,
    quando = agora - i * 60000,
    texto = (i % 3 == 0)
      and "uma frase bem comprida que passa da largura de qualquer uma das duas telas e precisa quebrar direito"
      or ("recado " .. i),
  }
end
agenda.receber(recados, 30)

local function estadoDeTeste()
  local e = {
    eu = { numero = EU, nome = "Ana" },
    tela = "conversas", foco = "lista", aberta = OUTRO,
    conversas = agenda.conversas(EU),
    nomeDe = { [OUTRO] = "Bruno" },
    escolhido = 1, topo = 1,
    escolhidoContato = 1, topoContatos = 1, escolhidoPerfil = 1,
    rascunho = campo.novo({ max = 160 }),
    naoLidos = agenda.naoLidos(EU),
    agora = agora,
    sinal = "ok", degrau = "vivo", intervalo = 2,
  }
  return e
end

--- Desenha uma tela numa janela dentro de um terminal maior e confere que
-- nada foi escrito fora do retangulo dela.
local function semVazar(nomeTela, telaW, telaH, jx, jy, jw, jh, titulo)
  local t = mock.monitor(telaW, telaH)

  -- pinta a tela toda de "#" para que qualquer celula que continue "#" dentro
  -- da janela signifique "nao desenhou" e qualquer celula alterada fora dela
  -- signifique "vazou"
  t.setBackgroundColour(colors.black)
  t.setTextColour(colors.white)
  for y = 1, telaH do
    t.setCursorPos(1, y)
    t.write(string.rep("#", telaW))
  end

  local j = janela.nova(t, jx, jy, jw, jh)
  local e = estadoDeTeste()
  telas[nomeTela].desenhar(j, e, C, true)

  local vazou = nil
  for y = 1, telaH do
    for x = 1, telaW do
      local dentro = x >= jx and x <= jx + jw - 1 and y >= jy and y <= jy + jh - 1
      if not dentro and t.celulas[y][x].ch ~= "#" then
        vazou = ("linha %d, coluna %d"):format(y, x)
      end
    end
  end
  ok(vazou == nil, titulo, vazou)
  return t, j
end

-- pocket: a tela inteira e uma janela so
for _, nome in ipairs({ "conversas", "conversa", "contatos", "perfil" }) do
  semVazar(nome, 26, 20, 1, 1, 26, 20,
           nome .. " cabe no pocket 26x20")
end

-- computador: duas colunas. A janela da direita e a que mais arrisca vazar,
-- porque e a que tem texto comprido - e vazar ali escreve na conversa do lado.
semVazar("conversas", 51, 19, 1, 1, 21, 19, "conversas na coluna esquerda (51x19)")
semVazar("conversa", 51, 19, 23, 1, 29, 19, "conversa na coluna direita (51x19)")

-- e uma janela apertada, para o caso de alguem usar um monitor pequeno
semVazar("conversas", 30, 12, 2, 2, 12, 8, "conversas numa janela apertada 12x8")
semVazar("conversa", 30, 12, 2, 2, 12, 8, "conversa numa janela apertada 12x8")

print("\n-- o conteudo aparece de verdade --")
-- nao basta nao vazar: tem que ter desenhado alguma coisa
local t = semVazar("conversas", 26, 20, 1, 1, 26, 20, "(desenho no pocket)")
ok(t.tudo():find("FALAE", 1, true) ~= nil, "a marca aparece no cabecalho")
ok(t.tudo():find("Bruno", 1, true) ~= nil, "e o apelido salvo, nao o numero cru")

local t2 = semVazar("perfil", 26, 20, 1, 1, 26, 20, "(desenho do perfil)")
ok(t2.tudo():find("+55 119 8472", 1, true) or t2.tudo():find("+55", 1, true),
   "o perfil mostra o numero formatado")

print("\n-- quebra de linha da conversa --")
local quebrar = telas.conversa.quebrar
local linhas = quebrar("uma frase bem comprida que precisa quebrar", 12)
local passou = false
for _, l in ipairs(linhas) do if #l > 12 then passou = true end end
ok(not passou, "nenhuma linha quebrada passa da largura")
ok(#linhas > 1, "e a frase foi mesmo quebrada em varias")

local palavrao = quebrar(string.rep("x", 40), 10)
local cabeTudo = true
for _, l in ipairs(palavrao) do if #l > 10 then cabeTudo = false end end
ok(cabeTudo, "palavra unica maior que a linha e cortada seco, sem estourar")

igual(table.concat(quebrar("abc def", 20)), "abc def", "texto que cabe fica inteiro")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
