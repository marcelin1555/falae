--[[ janela - um retangulo da tela, e tudo que uma tela pode saber

  A ideia que sustenta a interface inteira da FALAE: AS TELAS NAO SABEM ONDE
  ESTAO. Cada uma desenha dentro de uma janela que recebe pronta, em
  coordenadas de 1 ate a largura dela, e nunca fala com o terminal direto.

  Com isso, o mesmo codigo serve os dois formatos:

    pocket 26x20      uma janela ocupando a tela toda, uma tela por vez
    computador 51x19  duas janelas lado a lado, as duas ao mesmo tempo

  Sem esta camada seriam duas interfaces para manter em sincronia para sempre,
  e todo conserto de desenho teria que ser feito duas vezes - a segunda sendo
  esquecida com frequencia.

  O CORTE E OBRIGATORIO, e o motivo e o layout de duas colunas: uma linha de
  texto comprida demais que vazasse para fora da janela escreveria por cima da
  coluna do lado. Nada aqui deixa o texto passar da largura.
]]

local janela = {}

local J = {}
J.__index = J

--- @param destino term.current(), um monitor, ou outra coisa com a API de
--        terminal. A janela nao guarda cor de fundo global: quem desenha diz.
function janela.nova(destino, x, y, w, h)
  return setmetatable({
    destino = destino,
    x = x, y = y, w = w, h = h,
  }, J)
end

--- A tela inteira como uma janela so. E o arranjo do pocket.
function janela.tela(destino)
  local w, h = destino.getSize()
  return janela.nova(destino, 1, 1, w, h)
end

--- Uma sub-janela desta, em coordenadas relativas. Usada para separar o
-- cabecalho e o rodape do miolo, sem cada tela ter que somar deslocamento.
function J:parte(lx, ly, w, h)
  return janela.nova(self.destino,
                     self.x + lx - 1, self.y + ly - 1,
                     math.min(w, self.w - lx + 1),
                     math.min(h, self.h - ly + 1))
end

-- ------------------------------------------------------------------- texto

--- Corta um texto na largura pedida, com reticencias quando sobra.
--
-- Cortar seco no meio de uma palavra confunde quem le - "Ana: vou passar ai"
-- virando "Ana: vou passar a" parece frase inteira. As reticencias avisam.
function janela.cortar(texto, largura)
  texto = tostring(texto or "")
  if largura <= 0 then return "" end
  if #texto <= largura then return texto end
  if largura <= 3 then return texto:sub(1, largura) end
  return texto:sub(1, largura - 3) .. "..."
end

--- Preenche a direita para o texto ocupar a largura inteira. Necessario para
-- apagar o que estava escrito antes sem limpar a janela toda - que e o que
-- mantem o redesenho barato.
function janela.encher(texto, largura)
  texto = janela.cortar(texto, largura)
  return texto .. string.rep(" ", largura - #texto)
end

--- Escreve dentro da janela. Fora dela, nada acontece.
function J:texto(lx, ly, s, fg, bg)
  if ly < 1 or ly > self.h then return end
  if lx > self.w then return end
  lx = math.max(1, lx)

  s = janela.cortar(s, self.w - lx + 1)
  if s == "" then return end

  self.destino.setCursorPos(self.x + lx - 1, self.y + ly - 1)
  if fg then self.destino.setTextColour(fg) end
  if bg then self.destino.setBackgroundColour(bg) end
  self.destino.write(s)
end

--- Uma linha inteira da janela, preenchida ate a borda.
function J:linha(ly, s, fg, bg)
  self:texto(1, ly, janela.encher(s, self.w), fg, bg)
end

function J:limpar(bg, fg)
  local vazio = string.rep(" ", self.w)
  for ly = 1, self.h do
    self:texto(1, ly, vazio, fg, bg)
  end
end

--- Regua horizontal, para separar cabecalho do miolo.
function J:regua(ly, cor, bg, caractere)
  self:texto(1, ly, string.rep(caractere or "-", self.w), cor, bg)
end

--- Uma barra de titulo: fundo cheio, texto a esquerda e um canto a direita.
function J:barra(ly, esquerda, direita, fg, bg)
  local sobra = self.w - #tostring(direita or "")
  local s = janela.encher(esquerda, math.max(0, sobra)) .. tostring(direita or "")
  self:texto(1, ly, janela.cortar(s, self.w), fg, bg)
end

-- ------------------------------------------------------------------ rolagem

--- Qual deve ser a primeira linha visivel para que <escolhido> apareca.
--
-- Chamado a cada desenho em vez de guardado: guardar a posicao da rolagem em
-- dois lugares (a tela e a janela) e o caminho mais curto para os dois
-- discordarem depois de a lista mudar de tamanho.
function janela.rolar(escolhido, quantos, cabem, topoAtual)
  local topo = topoAtual or 1
  if cabem >= quantos then return 1 end
  if escolhido < topo then topo = escolhido end
  if escolhido > topo + cabem - 1 then topo = escolhido - cabem + 1 end
  if topo < 1 then topo = 1 end
  if topo > quantos - cabem + 1 then topo = quantos - cabem + 1 end
  return topo
end

-- ------------------------------------------------------------------- tempo

--- "2m", "1h", "ontem" - o quanto faz, do jeito que se fala.
--
-- Cabe em quatro caracteres de proposito: e o que sobra na direita da lista de
-- conversas de um pocket de 26 colunas depois do nome.
function janela.quando(ms, agora)
  if not ms then return "" end
  local seg = math.floor(((agora or os.epoch("utc")) - ms) / 1000)
  if seg < 60 then return "agora" end
  if seg < 3600 then return math.floor(seg / 60) .. "m" end
  if seg < 86400 then return math.floor(seg / 3600) .. "h" end
  if seg < 172800 then return "ontem" end
  return math.floor(seg / 86400) .. "d"
end

return janela
