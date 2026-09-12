# FALAÊ

Operadora de telefonia em CC:Tweaked. Uma **central** e um número qualquer de
**aparelhos** — a pessoa tira um número, cria um PIN, e conversa com quem
quiser.

Empresa própria, não subsidiária de ninguém. Fala com a rede da Expresso Labs
como duas empresas fazem negócio: pelo protocolo uma da outra, sem uma mandar
na outra.

## Instalar

Dentro do jogo, no computador:

```
wget run https://raw.githubusercontent.com/marcelin1555/falae/main/instalar.lua
```

Ele pergunta se aquele computador é a central ou um aparelho, e baixa só o que
aquele papel precisa. Rodar de novo atualiza — a linha, a agenda e as conversas
ficam onde estão.

Esse é o caminho principal, e não um extra: **em servidor de outra pessoa não há
como chegar na pasta do save**, então o computador precisa buscar os arquivos
sozinho. Se você é dono do mundo e prefere copiar direto, o `deploy.ps1` também
funciona.

### Hardware

| | precisa |
|---|---|
| central | um computador + **Ender Modem** + **Disk Drive** encostados. Monitor é opcional |
| aparelho | **Advanced Pocket Computer** + **Ender Modem** nas costas |

O pocket tem **um slot de upgrade só** (confirmado no jar: `PocketAPI` expõe
apenas `equipBack`/`unequipBack`, e os tipos registrados são `SPEAKER` e
`WIRELESS_MODEM`). O modem é obrigatório, então **não há toque de notificação** —
todo aviso do telefone é visual.

Um pocket colocado num **lectern** roda e é usável: dá para montar orelhão
público sem escrever nada a mais.

O **Disk Drive** da central não é opcional: sem a chave (ver
[A chave](#a-chave)) ela não sobe. Deixe o disquete no drive e a central volta
sozinha depois de qualquer reinício de chunk.

## A ideia

Estrela: **nenhum aparelho fala com outro aparelho**. Tudo passa pela central.
Isso dá autenticação num lugar só, uma ordem só das mensagens, e nenhuma escrita
concorrente — as tarefas são corrotinas, e trocam de vez só nos pontos de espera.

### Linha ≠ aparelho

É a diferença que define o projeto. Na rede da Expresso Labs o crachá é do
**computador** e mora no disco dele. Aqui a **linha** é da pessoa e mora na
central: você entra com número e PIN no pocket do amigo e é você, não ele.

```
aparelho  →  guarda só um token de sessão em /.falae
linha     →  mora na central: número, nome, PIN (sal + resumo), bloqueados
```

O PIN viaja **uma vez**, no login. Depois disso todo pedido leva o token.

### O número

`+55 119 8472-3310` — o `+55` é fixo (toda linha é da FALAÊ) e os outros onze
dígitos são sorteados. Por dentro é uma string de treze dígitos, que é o que
serve de chave sem susto.

## Serviços

| Rota | O que faz | Sessão |
|---|---|---|
| `central.ping` | descobre a central | não |
| `linha.criar` | sorteia número, define PIN e nome | não |
| `linha.entrar` | número + PIN → token | não |
| `linha.eu` / `nome` / `pin` / `sair` | a sua linha | sim |
| `linha.buscar` | esse número existe? qual o nome? | sim |
| `msg.enviar` | manda para um número | sim |
| `msg.novidades` | o que houve desde N | sim |
| `msg.conversa` / `conversas` | histórico, no primeiro login | sim |
| `bloq.listar` / `por` / `tirar` | lista de bloqueio | sim |

As três sem sessão são a porta de entrada: quem ainda não tem linha nenhuma
precisa chegar por algum lugar.

## O telefone

Dois layouts de verdade — e **uma implementação só**.

```
pocket 26x20      uma janela ocupando tudo, uma tela por vez
computador 51x19  lista à esquerda, conversa à direita, as duas juntas
```

O truque: as telas **não sabem onde estão**. Cada uma desenha dentro de uma
janela que recebe pronta, de 1 até a largura dela, e nunca fala com o terminal
direto. `conversas.desenhar(janela, estado)` é a mesma função nos dois arranjos
— muda só o retângulo e quem tem o foco do teclado.

| tecla | onde | o quê |
|---|---|---|
| setas / enter | lista | escolher e abrir |
| `N` | lista | conversa nova (digita o número) |
| `A` | lista | agenda |
| `P` | lista | minha linha |
| `S` | conversa | salvar o número na agenda |
| `B` | conversa | bloquear |
| `D` | conversa | denunciar (pede confirmação) |
| **toque** | qualquer | abrir, rodapé, menus — tudo menos digitar |
| **roda** | listas | rolar |
| backspace | conversa vazia | voltar |
| tab | computador | trocar de coluna |

### Toque

O pocket recebe `mouse_click` como qualquer computador — confirmado no jar:
`TerminalWidget.mouseClicked` chama `UserComputerInput.mouseClick`, e o pocket
usa a mesma tela genérica. Dá para usar o telefone só com o dedo: tocar numa
conversa abre, o rodapé é uma fileira de botões, e a roda rola as listas.
Digitar continua no teclado, que é onde teclado ganha de qualquer toque.

As áreas tocáveis do rodapé saem de **onde o texto foi escrito**, não de
posições fixas. Com posição fixa, mudar um rótulo moveria o texto e deixaria o
botão para trás — e o dedo passaria a acertar a ação errada, que é o pior tipo
de defeito de toque: parece que o programa entendeu outra coisa.

Toque é adição, não troca: toda tecla continua funcionando, porque um pocket no
lectern se usa com teclado.

**As telas de trocar nome/PIN e a de bloqueados são tela inteira, com botão.**
Antes, confirmar era só Enter e cancelar era só Tab — invisível para quem usa
o dedo, a mesma falha que a barra da conversa tinha antes do `<`. Agora um
campo com o texto (ou um marcador tipo "digite aqui seu nome...") fica sobre
uma barra `CONFIRMAR` e um link `cancelar`, os dois tocáveis em qualquer coluna
da linha deles — igual à barra de título da conversa, mirar num pixel só é
pedir demais do dedo. Trocar PIN mostra os dois campos (atual e novo) na
mesma tela, com Tab ou o toque trocando o foco entre eles.

**"Minha linha" e "Bloqueados" usam BADGES no lugar de ícone.** O terminal do
CC não desenha ícone nenhum fora da logo (célula por caractere, sem fonte
customizada) — então cada ação vira um bloco de cor com uma letra dentro:
azul para editar, rosa para abrir outra tela, vermelho para sair, laranja
para liberar um bloqueio. A cor conta a categoria antes mesmo de ler o texto.
Bloqueados agora é uma lista de verdade — nome e há quanto tempo — em vez de
pedir para redigitar o número que a FALAÊ já tinha guardado.

A **agenda é do aparelho** e nunca vai para a central. Mandá-la para lá
transformaria a FALAÊ num lugar onde está escrito quem conhece quem — a
informação mais delicada que um sistema de mensagem pode juntar, e que não é
necessária para nada do que ele faz. O preço, honesto: trocar de aparelho perde
os apelidos. A linha e as conversas vão junto.

## Denúncias

A FALAÊ não lê mensagem de ninguém. A denúncia é a **única** exceção, e ela só
existe porque tem consentimento: quem *recebeu* decide entregar aquele recado.
Ninguém é vigiado por padrão, nada é lido por varredura, nenhuma palavra é
filtrada.

Quatro regras, e as quatro estão no código:

- Só o **último recado recebido** daquele número sai do aparelho. Não a
  conversa, não o histórico.
- O texto vem do **histórico da central**, nunca do que o aparelho mandou. Se
  viesse do aparelho, qualquer um poderia inventar uma frase e atribuí-la a
  outra pessoa — a denúncia viraria arma em vez de defesa.
- O texto **nunca aparece no painel de parede**. Ele fica numa sala por onde
  qualquer um passa; ali vai só o contador. Ler é coisa do console.
- O denunciado **não é avisado**. Avisar transformaria a denúncia num aviso, e a
  pessoa tiraria outra linha — que custa nada.

No console, `D` abre a fila: quem denunciou, sobre quem, o recado, e quantas
vezes aquele número já foi denunciado **por quantas pessoas diferentes** — que é
o que separa briga de dois de um problema de verdade. Duas saídas: arquivar, ou
cassar a linha.

## Os monitores

São **sala de operação**, não vitrine: existem para a operadora saber o que está
acontecendo, e o espaço vale mais como dado do que como enfeite. Por isso a
marca é uma faixa de cabeçalho em vez de meia tela.

Com **dois**, o conteúdo se divide:

- **principal** — linhas, aparelhos e recados em três blocos; o gráfico de
  tráfego por hora; e a faixa de atenção
- **técnico** — pedidos por minuto, custo por rota, disco, e o log ao vivo

Com **um**, o principal cabe nele. Com **nenhum**, a central roda igual — um
sistema que exige monitor quebra no dia em que alguém tira o bloco.

A **faixa de atenção só aparece quando há algo**: linha zerada no balcão
esperando PIN novo, linha travada por tentativa errada, denúncias na fila. Um
painel que exibe "nenhum problema" em letras grandes treina a pessoa a não olhar
para ele — e aí o dia em que houver problema também passa batido.

Qual é qual sai da ordem dos nomes do periférico (`monitor_0` antes de
`monitor_1`), que é a ordem em que os blocos foram colocados. A tecla `T` no
console abre a lista do que a central achou — nome, tamanho, escala e o que cada
um mostra — e inverte os dois, guardando a escolha.

**Se aparecer só um monitor**, quase sempre é uma destas duas coisas:

- **Os dois blocos viraram um.** O CC funde monitores adjacentes e alinhados
  (classe `Expander`): dois 8×4 encostados no mesmo plano são um monitor 16×4, e
  o painel enxerga um periférico só — e está certo. Separe-os.
- **O segundo não alcança a central.** Dois monitores 8×4 dificilmente encostam
  ambos no computador; o caminho normal é **Wired Modem + cabo** em cada um.

A escala do texto **não é fixa**: um monitor de 8×4 blocos dá 164×52 caracteres
em escala 0.5 e 41×13 em escala 2. Os dois cabem, mas 164 colunas num painel que
se lê do outro lado da sala é letra de bula. O painel escolhe a maior escala que
ainda deixa espaço.

**O layout também não tem posições fixas.** Um 8×4 dá 26 linhas e um 8×6 dá 40;
com o desenho calculado para 26, o monitor alto ficava com quatorze linhas
pretas no fim. A altura que sobra vai quase toda para o gráfico, que é o que
melhora com espaço — num 8×6 ele fica com 20 linhas em vez de 7. Num monitor
baixo demais para o gráfico, ele sai inteiro e a faixa de atenção sobe: mostrar
menos é correto, sumir em silêncio não.

| monitor | principal | técnico |
|---|---|---|
| 8×4 blocos | 82×26 | 55×17 |
| 8×6 blocos | 82×40 | 55×27 |

E o painel **não escreve nada quando nada muda**. Monitor de CC é sincronizado
com todo cliente por perto, então quadro redesenhado à toa vira tráfego no
servidor Minecraft inteiro, inclusive para quem só passou andando pela sala.

## A abertura

A FALAÊ é uma operadora de mensagem, então ela se apresenta **escrevendo uma
mensagem**: o balão nasce do escuro com a cor esquentando de cinza até o amarelo
da marca, o nome é digitado letra por letra com um cursor piscando, **a cauda cai
no momento do envio** — com um pulso curto do balão — e só então o diagnóstico
entra linha a linha.

```
ATO 1   0 - 4s     o balao cresce, e a cor esquenta junto
ATO 2   4 - 9s     o nome e digitado, com cursor
ATO 3   9 - 11s    a cauda cai: a mensagem foi enviada
ATO 4  11 - 15s    modem ......... ok
                   linhas ........ 12
                   recados ....... 847
                   rede .......... no ar
```

~15s na central, ~6s no pocket, e **qualquer tecla pula**. A digitação funciona
dos dois jeitos: onde o letreiro desenhado cabe, ele é desenhado; onde não cabe
(o pocket), o nome é escrito na fonte do terminal, letra por letra do mesmo
jeito. Num pocket o diagnóstico vai para as últimas linhas e o balão cede o
espaço — senão o texto sairia escrito por cima do amarelo.

A abertura roda dentro de `pcall` e **devolve a paleta sempre**, inclusive ao
pular ou ao falhar. A paleta do CC é global e sobrevive ao programa: sem
restaurar, o shell fica com as cores da FALAÊ até o computador reiniciar.

## A logo

O balão é desenhado em subpixel (2×3 pontos por célula) e o nome vai **dentro
dele, na diagonal**, com o circunflexo — cada letra é um conjunto de polígonos
preenchidos, não riscos de um ponto. A primeira versão usava linhas finas e
virava ruído: a marca é de traço grosso, e um risco fino não é uma letra magra,
é um rabisco.

Abaixo de **10 pontos de altura por letra** a marca desiste e escreve `FALAE` na
fonte do terminal. Isso não é desistência à toa — foi medido olhando os três
tamanhos lado a lado: com 12 e 10 o nome se lê; com 9 o travessão do A já come o
vão e as duas letras viram a mesma mancha. A fonte do terminal é nítida porque
não está sendo escalada, então abaixo desse ponto ela ganha do desenho.

Por isso o monitor da marca usa uma escala **diferente** do monitor do
movimento: ali quase não há texto, e cada célula a mais vale 2×3 pontos de
desenho. Num 8×4, escala 1.5 dá 51 pontos de altura e o nome não cabe desenhado;
escala 1.0 dá 78 e ele aparece inteiro.

O `Ê` só existe desenhado. O charset do CC vem do CP437, que tem `ê` minúsculo
mas não o maiúsculo — em caracteres o nome só pode sair `FALAE`.

## Balcão de atendimento

O teclado da central. Zerar PIN **não existe pela rede**, de propósito: seria a
rota mais valiosa da FALAÊ para quem quisesse roubar uma linha, e viajaria por
um rednet que qualquer um escuta.

```
L  lista de linhas       J  exportação judicial
X  cassar uma linha      K  as chaves
D  fila de denúncias     P  painel externo
R  zerar o PIN           C  custo por rota
T  os monitores          G  log
F  fechar o balcão       Q  sair
```

A central não sabe PIN de ninguém: zerar apaga o resumo, e a pessoa define um
novo no próximo login — com o **código de seis dígitos** que o balcão entrega na
hora, sem o qual a linha zerada ficaria aberta para quem chegasse primeiro.

**L, R, X, D, J, K e P pedem a chave.** Ver logo abaixo.

## A chave

Uma chave da FALAÊ é um **disquete**. O disquete liga; disquete **+ PIN** opera.

Ligar não é o ato perigoso — cassar a linha de alguém é. Se o boot pedisse PIN,
a central não voltaria sozinha depois de um reinício de chunk, e uma operadora
telefônica que fica fora do ar até alguém aparecer com um disquete na mão não é
uma operadora telefônica.

| | precisa |
|---|---|
| a central subir | o disquete no drive |
| o balcão abrir | o disquete **e** o PIN, e a sessão morre quando o disquete sai |

**A primeira chave é a dona.** Central sem chave nenhuma é central sem dono: ela
pede um disquete vazio no primeiro boot e a chave emitida ali manda. Depois
disso, só quem já tem chave emite outra (tecla `K`).

Três coisas fazem ela valer alguma coisa, e **nenhuma é criptografia** — o CC
não tem, e fingir que tem seria pior que não ter:

1. **O selo é amarrado ao id do disquete.** Cada disquete do Minecraft tem
   número próprio, e ele não acompanha uma cópia dos arquivos. O id que a conta
   usa vem do **drive**, nunca do que está escrito no arquivo — então copiar
   `chave.falae` para outro disquete leva o arquivo e deixa o número para trás,
   e a cópia deriva outro segredo. O id também não dá para escolher: o mundo
   nunca repete um número que já saiu.
2. **O segredo vai cifrado pelo PIN, e o disquete não sabe conferir o PIN.** Não
   há resumo do PIN gravado nele. PIN errado devolve lixo, calado. Descobrir se
   acertou exige perguntar à máquina — que freia a cada erro e escreve no log.
   Isso importa porque em Minecraft você morre e derruba o inventário.
3. **A máquina guarda só a impressão.** Ler o disco da central dá a impressão do
   segredo, não o segredo.

Cada máquina tem o seu chaveiro, e **nada disso passa pela rede**: conferir
chave por rednet seria a prova viajando por um canal em texto puro, repetível
por quem escutasse.

O PIN da chave tem de 8 a 12 dígitos — maior que o do cliente porque o do
cliente é protegido pelo freio da central, e este pode ser atacado offline por
quem levar o disquete **e** o disco da máquina juntos. Medido no CraftOS-PC, com
3000 voltas: 8 dígitos ≈ 70 dias de varredura, 10 dígitos ≈ 19 anos.

## A loja

Um terceiro tipo de máquina, `loja` no instalador — um terminal de balcão para
quem não tem pocket. Diferente do telefone de dois jeitos:

- **Cobra antes de mandar o pedido.** Sem integração de economia automática no
  CC — a tela mostra o preço e espera o atendente, que está fisicamente ali,
  confirmar o pagamento (tecla `S`), como um caixa de verdade. Recusar (`N`)
  não manda nada para a central e não conta como venda.
- **Não guarda sessão nenhuma.** É pública, usada por gente diferente o dia
  inteiro: guardar a última sessão criada deixaria o número e o PIN de um
  cliente acessíveis ao próximo. Por isso o terminal manda o pedido direto
  (`fnet.pedir`), e não pelo caminho que o telefone usa para logar
  (`fnet.criarLinha`, que grava um token em disco) — o número aparece na tela
  para a pessoa anotar, e a máquina esquece assim que volta ao início.

A administração (preço, quantas linhas já foram vendidas, emitir ou revogar
chave de outro atendente) fica atrás da tecla `A`, e atrás da **mesma chave por
disquete** da central — só que com o **chaveiro da própria loja**: uma chave
que abre a central não abre a loja, e vice-versa. A loja **não** pede chave
para ligar nem para vender; só para mexer no que é do dono.

## Exportação judicial

A FALAÊ não lê recado de ninguém, e isso vale até para ordem judicial: não há
uma rota, um endpoint ou um botão que mande texto de conversa para fora do
computador pela rede. Existe **uma única porta**, deliberadamente manual —
tecla `J` no console, atrás da chave:

1. Pede os dois números (o segundo pode ficar em branco, para exportar tudo o
   que um número mandou ou recebeu, não só uma conversa) e um **motivo**, que é
   obrigatório.
2. Monta um arquivo com cabeçalho — quem pediu, quando, os números, o motivo —
   e grava **no disquete que estiver no drive**. Nunca em `/dados` da central,
   nunca pela rede: o texto sai fisicamente com quem tem a chave.
3. Registra o pedido em `/dados/exportacoes.log`, que **nunca é aparado** —
   diferente do log de tela, que guarda só as últimas 100 linhas. O registro
   acontece mesmo que a gravação no disquete falhe depois: o rastro é do
   pedido, não do sucesso da cópia.

## O painel externo

A central pode mandar **números** — nunca texto, nunca "quem falou com
quem" — para uma página fora do jogo (tecla `P` no console configura o
endereço e um token de push). O que sai: quantas linhas, sessões abertas,
recados por hora, denúncias pendentes, custo por rota, saúde do modem. É
testado byte a byte no JSON que sairia pela rede, com uma varredura que rejeita
qualquer campo cujo nome contenha "numero", "nome" ou "texto" — para a promessa
não depender de alguém lembrar de não adicionar um campo errado um dia.

Opcional de propósito: sem token configurado, a central roda idêntica a
sempre — nenhuma rota nova, nenhum laço a mais. Toda tentativa de rede fica
num `pcall`; a página fora do ar vira uma linha fraca no log, nunca uma central
que caiu.

## Segurança — até onde vai

- **Rednet não é criptografado.** Quem estiver no alcance escutando o canal pega
  o PIN no instante do login e pega os tokens que passam. O CC não oferece
  criptografia de verdade para consertar isso.
- **PIN de quatro dígitos não é protegível por resumo.** São dez mil
  possibilidades. O sal e as voltas só encarecem a vida de quem quebrar a
  central e ler o disco. Quem protege de verdade é o **freio**: erro repetido
  faz a espera crescer até um minuto — o suficiente para varrer dez mil PINs
  levar mais de uma semana. É o freio que tem teste, não o resumo.
- PIN de cliente aceito de 4 a 8 dígitos, para quem quiser mais margem ter como
  pedir. O da **chave** é de 8 a 12, por outro motivo — ver [A chave](#a-chave).
- **Quem alcançar o computador da central alcança tudo.** A chave por disquete
  tranca o teclado, não o bloco: quem quebrar a central lê o disco dela. Em
  Minecraft isso se resolve com a porta da sala, não com código.

## Desempenho

Um app de mensagem é N aparelhos perguntando à mesma central para sempre. O
orçamento: **20 telefones ligados custam menos de 5 pedidos por segundo, e um
pedido "nada mudou" custa tempo constante.**

O que faz isso valer:

- **O catálogo.** A central guarda o maior `n` de cada linha. "Nada mudou" — que
  é quase toda resposta que ela dará na vida — sai de comparar dois números, sem
  varrer os mil recados nem serializar nada.
- **Cadência fixa e previsível.** Todo telefone pergunta a cada 5s, sempre -
  sem afrouxar sozinho nem depender de sinal de vida para acordar.
- **Log que só cresce pelo fim.** Cada recado é uma linha acrescentada ao
  arquivo, e não uma reserialização do histórico inteiro. Mandar recado custa o
  mesmo com zero ou com mil guardados.
- **Aparo em lote.** `table.remove(lista, 1)` num laço é trabalho ao quadrado.
  Aqui a lista é recriada de uma vez, e só quando passa da folga.

`C` no console mostra o custo medido de cada rota. "A FALAÊ está lenta" vira uma
linha dizendo qual rota e quanto.

## Testes

```bash
python testes/rodar.py            # tudo, fora do jogo
python testes/rodar.py --sintaxe  # só compila
python testes/rodar.py --carga    # só a aferição de custo
```

Roda os mesmos arquivos que vão para o jogo contra uma API falsa do CC
(`testes/cc_mock.lua`), com disco virtual por computador — nenhum teste encosta
num save. Precisa de `pip install lupa`.

| Suíte | Cobre |
|---|---|
| `numero` | canônico ↔ exibição, sorteio, entrada torta |
| `linhas` | criação, PIN, **o freio**, balcão, sessão que sobrevive ao reinício |
| `recados` | histórico incremental, aparo, log corrompido |
| `privacidade` | **A não lê a conversa de B com C** — o mais importante daqui |
| `bloqueio` | não chega, o bloqueado não descobre, e o `quando` não quebra save antigo |
| `perfil` | trocar nome/PIN e liberar bloqueado **pelo dedo**, `app.rodar()` de ponta a ponta |
| `janela` | as mesmas telas em 26x20 e 51x19, sem vazar |
| `telefone` | dois aparelhos e uma central, ponta a ponta |
| `laco` | o telefone continua buscando com evento estranho no meio |
| `marca` | o nome não vaza do balão, e a medida bate com o desenho |
| `painel` | escala, dois monitores, e o redesenho que não custa nada |
| `instalador` | manifesto, os quatro papéis, e o que fazer quando a rede cai |
| `denuncias` | **o texto vem da central, não do aparelho**; uma por par; cassar leva junto |
| `toque` | o clique cai na janela certa; o rodapé responde onde o rótulo está |
| `grafico` | escala, série vazia, valor gigante, e barra que não estoura o retângulo |
| `carga` | o orçamento, medido — e o gráfico não varre a toa |
| `chave` | **a cópia do disquete não abre nada** — o id vem do drive, nunca do arquivo |
| `loja` | não guarda sessão; a cobrança acontece antes do pedido; administração é da loja |
| `exportacao` | **nunca chama http nem rednet**; motivo obrigatório; o log nunca apara |
| `json` | escapes, números grandes sem notação científica, NaN/infinito não quebram |
| `telemetria` | **nenhum campo do snapshot cheira a número de linha ou texto de recado** |

O de carga conta chamadas em vez de cronometrar quase tudo: o `fs` falso refaz a
string inteira a cada append, então cronometrar gravação ali mediria o banco de
testes — e mediria errado na direção que interessa.

## Mapa dos arquivos

```
comum/protocolo.lua   envelope falae-net, SEM_SESSAO, abertura dos modems
comum/numero.lua      +55 119 8472-3310 ↔ 5511984723310, sorteio, máscara
comum/janela.lua      o retângulo em que toda tela desenha
comum/campo.lua       uma linha de texto sendo digitada, com máscara
comum/carregar.lua    o require do telefone (dofile reexecuta; isso morde)
comum/pixel.lua       framebuffer subpixel 2x3      (veio do HELIOS)
comum/palette.lua     as cores da marca             (veio do HELIOS)
comum/chave.lua       o segredo do disquete, amarrado ao id do drive
comum/chaveiro.lua    as chaves que UMA máquina aceita, com o freio
comum/tranca.lua      a fechadura, com tela — central e loja usam a mesma
comum/json.lua        codificador JSON escrito à mão, só para telemetria.lua

servidor/core/central.lua   laço de rede, rotas, medidor de custo
servidor/core/linhas.lua    contas, PIN, sessões, o freio
servidor/core/recados.lua   mensagens, catálogo, log append-only
servidor/core/bloqueio.lua  quem você não quer ouvir
servidor/core/console.lua   o balcão de atendimento
servidor/core/denuncias.lua a fila, e as quatro regras dela
servidor/core/exportacao.lua a única porta de texto por ordem judicial
servidor/core/telemetria.lua coleta e manda números para o painel externo
servidor/tela/marca.lua     a logo: balão em subpixel, nome em caracteres
servidor/tela/painel.lua    os dois monitores da central
servidor/tela/grafico.lua   barras em subpixel, com escala automática

telefone/fnet.lua      a linha direta com a central
telefone/agenda.lua    contatos e caixa de recados, no disco do aparelho
telefone/app.lua       o arranjo das janelas e o laço
telefone/telas/        entrar, conversas, conversa, contatos, perfil, bloqueados

loja/app.lua           o terminal de balcão: nome, PIN, cobrança, resultado
loja/admin.lua         preço, vendas e chaves da loja, atrás da tranca

manifesto.txt          a única lista de arquivos — instalador e deploy leem ela
instalar.lua           o instalador que roda dentro do jogo
```

## O que fica de fora, de propósito

Grupos, cobrança, e chamada de voz — esta última é impossível: o slot de upgrade
do pocket é um só, e ele está com o modem.
