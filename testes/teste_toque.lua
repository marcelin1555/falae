--[[ teste_toque - o telefone no dedo

  Confirmado no jar antes de escrever uma linha: pocket computer recebe
  mouse_click como qualquer computador (TerminalWidget.mouseClicked chama
  UserComputerInput.mouseClick, e o pocket usa a mesma tela generica).

  O que da para quebrar sem sintoma:

    - o clique cair na janela errada no arranjo de duas colunas, e a pessoa
      tocar numa conversa e abrir outra
    - o rodape responder onde o rotulo NAO esta, porque a area tocavel ficou
      numa posicao fixa enquanto o texto mudou de lugar
    - o toque levar a uma acao diferente da tecla equivalente, e o aplicativo
      passar a ter dois comportamentos para a mesma coisa

  O ultimo e o mais insidioso: tudo funciona nos dois caminhos, so que
  diferente, e a divergencia so aparece muito depois.
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

local carregar = dofile("/carregar.lua")
local janela = carregar("janela")
local campo  = carregar("campo")
local agenda = carregar("agenda")
local numero = carregar("numero")

-- ------------------------------------------------------- onde o dedo caiu

print("\n-- a janela sabe se o ponto e dela --")

local tela = mock.monitor(51, 19)
local esquerda = janela.nova(tela, 1, 1, 21, 19)
local direita  = janela.nova(tela, 23, 1, 29, 19)

ok(esquerda:contem(1, 1), "o canto de cima a esquerda e da esquerda")
ok(esquerda:contem(21, 19), "e o canto de baixo a direita tambem")
ok(not esquerda:contem(22, 5), "a coluna do meio nao e dela")
ok(direita:contem(23, 5), "e e da direita")
ok(not direita:contem(22, 5), "a regua entre as colunas nao e de ninguem")
ok(not esquerda:contem(0, 5) and not esquerda:contem(5, 0),
   "fora da tela nao e de ninguem")

print("\n-- e converte para coordenadas dela --")
local lx, ly = esquerda:ondeCaiu(1, 1)
ok(lx == 1 and ly == 1, "o canto vira 1,1")
lx, ly = direita:ondeCaiu(23, 1)
ok(lx == 1 and ly == 1, "na direita tambem - a tela nao sabe onde esta")
lx, ly = direita:ondeCaiu(30, 7)
ok(lx == 8 and ly == 7, "e o meio converte certo", ("%s,%s"):format(lx, ly))
ok(direita:ondeCaiu(5, 5) == nil,
   "fora da janela devolve nil, para o chamador nao precisar conferir duas vezes")

-- ------------------------------------------------------------- o rodape

print("\n-- o rodape: as areas saem de onde o texto ficou --")

local texto, regioes = janela.rodape({
  { rotulo = "N novo",   acao = "nova" },
  { rotulo = "A agenda", acao = "contatos" },
  { rotulo = "P linha",  acao = "perfil" },
}, 26)

igual(#texto, 26, "o rodape ocupa a largura inteira")
igual(#regioes, 3, "com tres areas")

-- E a garantia que importa: a area de cada acao cobre exatamente as colunas
-- onde o rotulo dela foi escrito. Se um dia o rotulo mudar de tamanho, a area
-- muda junto - e nao ha como o dedo acertar o botao errado.
for _, r in ipairs(regioes) do
  local pedaco = texto:sub(r.de, r.ate)
  ok(pedaco:match("%S"), ("a area de '%s' cai sobre texto, nao sobre espaco"):format(r.acao),
     ("[%s]"):format(pedaco))
end

igual(janela.acaoNoRodape(regioes, regioes[1].de), "nova", "tocar no primeiro")
igual(janela.acaoNoRodape(regioes, regioes[2].de + 1), "contatos", "tocar no segundo")
igual(janela.acaoNoRodape(regioes, regioes[3].ate), "perfil", "tocar no fim do terceiro")
igual(janela.acaoNoRodape(regioes, regioes[1].ate + 1), nil,
      "tocar no espaco entre dois nao faz nada")
-- Com 26 colunas os tres rotulos vao ate a borda e nao sobra vazio, entao o
-- vazio de verdade se testa numa largura folgada.
local _, folgado = janela.rodape({
  { rotulo = "N novo", acao = "nova" },
}, 40)
igual(janela.acaoNoRodape(folgado, 40), nil, "tocar no vazio do fim nao faz nada")
igual(janela.acaoNoRodape(folgado, 1), nil, "nem na margem antes do primeiro")
igual(janela.acaoNoRodape(nil, 3), nil, "sem regioes, nao explode")

print("\n-- rotulo comprido muda a area junto --")
local _, r2 = janela.rodape({
  { rotulo = "N nova conversa", acao = "nova" },
  { rotulo = "A agenda", acao = "contatos" },
}, 40)
ok(r2[2].de > regioes[2].de,
   "o segundo botao andou para a direita porque o primeiro cresceu")
igual(janela.acaoNoRodape(r2, r2[2].de), "contatos",
      "e o toque acompanha - nao ficou apontando para o lugar antigo")

local _, r3 = janela.rodape({
  { rotulo = "N novo", acao = "nova" },
  { rotulo = "A agenda muito comprida demais", acao = "contatos" },
}, 12)
igual(#r3, 1, "o que nao cabe na largura nao vira botao invisivel")

-- ---------------------------------------------------- as telas respondem

print("\n-- tocar numa conversa abre ela --")

local telas = {
  conversas  = carregar("conversas"),
  conversa   = carregar("conversa"),
  contatos   = carregar("contatos"),
  perfil     = carregar("perfil"),
  bloqueados = carregar("bloqueados"),
}

local EU, A, B = "5511100000001", "5511100000002", "5511100000003"
agenda.carregar()
agenda.receber({
  { n = 1, de = A, para = EU, quando = 1700000000000, texto = "oi da A" },
  { n = 2, de = B, para = EU, quando = 1700000001000, texto = "oi da B" },
}, 2)

local function estadoNovo()
  return {
    eu = { numero = EU, nome = "Eu" },
    tela = "conversas", foco = "lista", aberta = nil,
    conversas = agenda.conversas(EU),
    nomeDe = {}, escolhido = 1, topo = 1,
    escolhidoContato = 1, topoContatos = 1, escolhidoPerfil = 1,
    rascunho = campo.novo({ max = 160 }),
    naoLidos = agenda.naoLidos(EU),
    agora = 1700000002000,
    sinal = "ok", degrau = "vivo", intervalo = 2,
  }
end

local e = estadoNovo()
local j = janela.nova(mock.monitor(26, 20), 1, 1, 26, 20)
local C = {
  fundo = colors.black, texto = colors.white, fraco = colors.gray,
  marca = colors.yellow, marcaFraca = colors.brown, selecao = colors.gray,
  entrada = colors.gray, meu = colors.lightGray,
  bom = colors.lime, ruim = colors.red, aviso = colors.orange,
}

telas.conversas.desenhar(j, e, C, true)

-- a primeira conversa comeca na linha 2; cada uma ocupa duas linhas
igual(telas.conversas.clique(e, 3, 2, j), "abrir", "tocar na primeira linha abre")
igual(e.aberta, e.conversas[1].numero, "e abre a conversa certa")

e = estadoNovo()
telas.conversas.desenhar(j, e, C, true)
igual(telas.conversas.clique(e, 3, 3, j), "abrir",
      "tocar na SEGUNDA linha do mesmo item abre o mesmo item")
igual(e.aberta, e.conversas[1].numero, "ainda a primeira conversa")

e = estadoNovo()
telas.conversas.desenhar(j, e, C, true)
igual(telas.conversas.clique(e, 3, 4, j), "abrir", "tocar no segundo item")
igual(e.aberta, e.conversas[2].numero, "abre a segunda conversa")

e = estadoNovo()
telas.conversas.desenhar(j, e, C, true)
igual(telas.conversas.clique(e, 3, 18, j), nil,
      "tocar no vazio abaixo da lista nao faz nada")

print("\n-- toque e tecla levam ao mesmo lugar --")

-- E o que impede o aplicativo de ter dois comportamentos para a mesma coisa.
local porTecla = estadoNovo()
telas.conversas.desenhar(j, porTecla, C, true)
local acaoTecla = telas.conversas.tecla(porTecla, mock.KEYS.enter)

local porToque = estadoNovo()
telas.conversas.desenhar(j, porToque, C, true)
local acaoToque = telas.conversas.clique(porToque, 3, 2, j)

igual(acaoToque, acaoTecla, "abrir pela tecla e pelo dedo da a mesma acao")
igual(porToque.aberta, porTecla.aberta, "e a mesma conversa")

print("\n-- o rodape da lista --")
e = estadoNovo()
telas.conversas.desenhar(j, e, C, true)
ok(e.rodapeConversas ~= nil, "a tela guardou onde os botoes ficaram")
local acaoRodape = telas.conversas.clique(e, e.rodapeConversas[1].de, j.h, j)
igual(acaoRodape, "nova", "tocar no primeiro botao pede conversa nova")
igual(telas.conversas.clique(e, e.rodapeConversas[3].de, j.h, j), "perfil",
      "e no terceiro, o perfil")

print("\n-- na conversa aberta --")
e = estadoNovo()
e.aberta = A
telas.conversa.desenhar(j, e, C, true)
igual(telas.conversa.clique(e, 5, 1, j), "fechar",
      "tocar na barra de titulo volta para a lista")

-- O "<" existe porque as duas saidas eram invisiveis: quem pega o telefone nao
-- tinha como adivinhar nem o backspace nem o toque na barra. Uma saida que nao
-- se anuncia e uma saida que nao existe.
local telaConv = mock.monitor(26, 20)
local jConv = janela.nova(telaConv, 1, 1, 26, 20)
local eConv = estadoNovo()
eConv.aberta = A
telas.conversa.desenhar(jConv, eConv, C, true)
ok(telaConv.texto(1):find("<", 1, true) ~= nil,
   "e o sinal de voltar aparece na barra", telaConv.texto(1))

-- a barra INTEIRA continua tocavel: mirar num caractere so num pocket e pedir
-- demais do dedo
igual(telas.conversa.clique(eConv, 1, 1, jConv), "fechar", "tocar na coluna 1 volta")
igual(telas.conversa.clique(eConv, 24, 1, jConv), "fechar", "e no fim da barra tambem")
igual(telas.conversa.clique(e, 5, j.h, j), "focar",
      "tocar na linha de escrita poe o foco ali")
igual(telas.conversa.clique(e, 5, 8, j), nil,
      "tocar no meio da conversa nao faz nada - nao ha o que abrir")

-- ------------------------------------------------- rolar a propria conversa

print("\n-- a conversa rola --")

-- Nao rolava por meio nenhum: as setas iam para a lista, o toque no miolo nao
-- fazia nada e a tela nao tinha rolar(). Dava para ver a ultima tela de
-- mensagens e mais nada - o historico ficava em disco, inalcancavel.
local telaR = mock.monitor(26, 20)
local jR = janela.nova(telaR, 1, 1, 26, 20)
local eR = estadoNovo()
eR.aberta = A

-- conversa comprida o bastante para nao caber na tela
local muitos = {}
for i = 1, 40 do
  muitos[i] = { n = 100 + i, de = A, para = EU,
                quando = 1700000000000 + i, texto = "recado numero " .. i }
end
agenda.receber(muitos, 140)
eR.conversas = agenda.conversas(EU)

telas.conversa.desenhar(jR, eR, C, true)
local fimVisivel = telaR.texto(jR.h - 1)
ok(fimVisivel:find("40", 1, true) ~= nil,
   "sem rolar, a conversa mostra o fim", fimVisivel)

igual(telas.conversa.rolar(eR, -1), "redesenhar", "a roda para cima rola")
igual(eR.rolagem, 1, "e a rolagem sobe uma linha")

telas.conversa.rolar(eR, -5)
telas.conversa.desenhar(jR, eR, C, true)
local depois = telaR.texto(jR.h - 1)
ok(depois ~= fimVisivel, "e a tela mostra outra parte da conversa",
   fimVisivel .. "  ->  " .. depois)

-- as setas rolam em vez de sair para a lista
eR.rolagem = 0
igual(telas.conversa.tecla(eR, keys.up), "redesenhar", "a seta para cima rola")
igual(eR.rolagem, 1, "uma linha por seta")
igual(telas.conversa.tecla(eR, keys.down), "redesenhar", "e a de baixo desce")
igual(eR.rolagem, 0, "de volta ao fim")

-- no fim da conversa nao ha para onde descer, e isso nao e um redesenho
igual(telas.conversa.tecla(eR, keys.down), nil, "no fim, descer nao faz nada")

-- E NAO DA PARA ROLAR PARA ALEM DO COMECO. Um numero grande demais deixaria a
-- tela vazia, que e pior do que nao rolar.
eR.rolagem = 9999
telas.conversa.desenhar(jR, eR, C, true)
ok(eR.rolagem < 9999, "rolar demais encosta no comeco", tostring(eR.rolagem))
ok(telaR.texto(jR.h - 1):find("recado", 1, true) ~= nil,
   "e a tela continua com conversa, nao vazia", telaR.texto(jR.h - 1))

print("\n-- rolagem --")
e = estadoNovo()
igual(e.escolhido, 1, "comeca no primeiro")
telas.conversas.rolar(e, 1)
igual(e.escolhido, 2, "rolar para baixo desce")
telas.conversas.rolar(e, 1)
igual(e.escolhido, 2, "e para no fim da lista")
telas.conversas.rolar(e, -1)
igual(e.escolhido, 1, "rolar para cima sobe")
telas.conversas.rolar(e, -1)
igual(e.escolhido, 1, "e para no comeco")

print("\n-- o arranjo de duas colunas --")

-- No computador as duas telas aparecem juntas, e o toque tem que cair na que
-- esta debaixo do dedo. Errar aqui abre a conversa errada.
local jEsq = janela.nova(mock.monitor(51, 19), 1, 1, 21, 19)
local jDir = janela.nova(mock.monitor(51, 19), 23, 1, 29, 19)

local partes = {
  { nome = "conversas", j = jEsq },
  { nome = "conversa",  j = jDir },
}

local function ondeCai(x, y)
  for _, parte in ipairs(partes) do
    local a, b = parte.j:ondeCaiu(x, y)
    if a then return parte.nome, a, b end
  end
  return nil
end

igual(select(1, ondeCai(5, 5)), "conversas", "a esquerda e a lista")
igual(select(1, ondeCai(30, 5)), "conversa", "a direita e a conversa")
igual(select(1, ondeCai(22, 5)), nil, "a regua do meio nao e de nenhuma")
local nome, cx = ondeCai(23, 5)
igual(cx, 1, "e a primeira coluna da direita e a 1 dela, nao a 23")

-- ------------------------------------------------------------- minha linha

print("\n-- perfil: rotulo, valor e badge --")

local telaPerfil = mock.monitor(26, 20)
local jPerfil = janela.nova(telaPerfil, 1, 1, 26, 20)
local ePerfil = estadoNovo()
ePerfil.eu = { numero = EU, nome = "Marcelin" }

telas.perfil.desenhar(jPerfil, ePerfil, C)

ok(telaPerfil.texto(5):find("SEU NOME", 1, true) ~= nil,
   "o rotulo do primeiro item aparece", telaPerfil.texto(5))
ok(telaPerfil.texto(6):find("Marcelin", 1, true) ~= nil,
   "e o nome de verdade embaixo dele", telaPerfil.texto(6))
ok(telaPerfil.texto(7):find("SEU PIN", 1, true) ~= nil, "o segundo item e o PIN")
ok(not telaPerfil.texto(8):find("%d%d%d%d"),
   "e NUNCA mostra o PIN - nem a FALAE sabe qual e")

-- os quatro badges: um caractere por item, na borda direita
for i, item in ipairs(telas.perfil.ITENS) do
  local y = 5 + (i - 1) * 2
  ok(telaPerfil.texto(y):find(item.badge, 1, true) ~= nil,
     ("o badge de '%s' aparece"):format(item.chave), telaPerfil.texto(y))
end

print("\n-- perfil: as duas linhas do item respondem ao toque --")

-- mirar so na linha de cima seria pedir demais do dedo - a mesma regra da
-- barra da conversa. yDoItem(i) = 5 + (i-1)*2, a mesma conta de perfil.lua.
for i, item in ipairs(telas.perfil.ITENS) do
  local y = 5 + (i - 1) * 2
  igual(telas.perfil.clique(estadoNovo(), 5, y, jPerfil), "perfil:" .. item.chave,
        ("tocar na linha de cima do item %d"):format(i))
  igual(telas.perfil.clique(estadoNovo(), 5, y + 1, jPerfil), "perfil:" .. item.chave,
        ("e na linha de baixo do item %d tambem"):format(i))
end

igual(telas.perfil.clique(ePerfil, 5, jPerfil.h, jPerfil), "voltar",
      "o rodape ainda volta")

-- teclado continua funcionando do mesmo jeito
local eTeclado = estadoNovo()
eTeclado.escolhidoPerfil = 2
igual(telas.perfil.tecla(eTeclado, keys.enter), "perfil:pin",
      "enter usa o item selecionado")
telas.perfil.tecla(eTeclado, keys.down)
igual(eTeclado.escolhidoPerfil, 3, "seta desce")

-- ------------------------------------------------------------ bloqueados

print("\n-- bloqueados: vazio --")

local telaBloq = mock.monitor(26, 20)
local jBloq = janela.nova(telaBloq, 1, 1, 26, 20)
local eVazio = estadoNovo()
eVazio.bloqueadosLista = {}

telas.bloqueados.desenhar(jBloq, eVazio, C)
ok(telaBloq.texto(3):find("Ninguem bloqueado", 1, true) ~= nil,
   "avisa que a lista esta vazia")
igual(telas.bloqueados.clique(eVazio, 5, 5, jBloq), nil,
      "tocar no miolo vazio nao faz nada")
igual(telas.bloqueados.tecla(eVazio, keys.q), "perfil",
      "Q volta para o perfil, nao para a lista de conversas")
igual(telas.bloqueados.tecla(eVazio, keys.backspace), "perfil", "backspace tambem")

print("\n-- bloqueados: com gente na lista --")

local eBloq = estadoNovo()
eBloq.escolhidoBloqueados = 1
eBloq.bloqueadosLista = {
  { numero = A, nome = "Chato", quando = eBloq.agora - 3600000 },
  { numero = B, nome = nil,     quando = nil },   -- save de antes do "quando"
}

telas.bloqueados.desenhar(jBloq, eBloq, C)
ok(telaBloq.texto(2):find("Chato", 1, true) ~= nil, "o nome aparece")
ok(telaBloq.texto(3):find("1h", 1, true) ~= nil, "e ha quanto tempo, formatado")
ok(telaBloq.texto(4):find(numero.formatar(B), 1, true) ~= nil,
   "sem nome salvo, mostra o numero formatado")
ok(telaBloq.texto(5):find("%-"), "e sem 'quando' (save antigo), mostra '-' em vez de quebrar")

igual(telas.bloqueados.clique(eBloq, 5, 2, jBloq), "desbloquear",
      "tocar na linha do primeiro pede para desbloquear")
igual(eBloq.escolhidoBloqueados, 1, "e escolhe ele")

igual(telas.bloqueados.clique(eBloq, 5, 4, jBloq), "desbloquear",
      "tocar no segundo item tambem")
igual(eBloq.escolhidoBloqueados, 2, "e escolhe o segundo")

igual(telas.bloqueados.tecla(eBloq, keys.x), "desbloquear",
      "a tecla X faz o mesmo que tocar no badge")

eBloq.escolhidoBloqueados = 1
telas.bloqueados.tecla(eBloq, keys.down)
igual(eBloq.escolhidoBloqueados, 2, "seta desce entre os bloqueados")

print(("\n%d de %d passaram"):format(total - falhas, total))
return falhas
