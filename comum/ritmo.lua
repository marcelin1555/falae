--[[ ritmo - de quanto em quanto tempo o telefone pergunta

  O telefone nao recebe aviso da central: ele pergunta. Perguntar de dois em
  dois segundos para sempre e o desenho obvio e o errado - vinte aparelhos
  esquecidos no bolso fariam dez pedidos por segundo a vida inteira para a
  central responder dez vezes por segundo que nao aconteceu nada.

  Entao o intervalo acompanha o que esta acontecendo. Conversa viva pergunta
  rapido; telefone parado vai afrouxando sozinho. Qualquer sinal de vida - uma
  tecla, um recado que chegou - derruba tudo de volta para o degrau de baixo.

  Mora num arquivo proprio, sem tela e sem rede, porque assim a politica de
  cadencia pode ser testada como o que ela e: uma funcao do tempo de silencio.
  Enfiada dentro do laco do aplicativo, ela so poderia ser conferida abrindo o
  jogo e esperando cinco minutos olhando para um pocket.
]]

local ritmo = {}

-- Quanto tempo de silencio ainda conta como "conversa viva".
ritmo.VIVO = 60          -- segundos
-- A partir daqui o aparelho e considerado esquecido.
ritmo.ESQUECIDO = 300    -- segundos

ritmo.RAPIDO   = 2       -- conversa acontecendo agora
ritmo.CONVERSA = 5       -- conversa aberta, mas parada
ritmo.LISTA    = 10      -- na lista de conversas, parado
ritmo.LENTO    = 30      -- ninguem mexe no aparelho ha muito tempo

--- Cria o ritmo de um aparelho.
-- @param agora epoch em ms (os.epoch("utc"))
function ritmo.novo(agora)
  return {
    ultimoSinal = agora or 0,
  }
end

--- Houve vida: tecla apertada, recado que chegou, conversa aberta.
-- Derruba o intervalo para o degrau mais rapido na proxima conta.
function ritmo.sinal(r, agora)
  r.ultimoSinal = agora
end

--- Ha quantos segundos nada acontece.
function ritmo.silencio(r, agora)
  return math.max(0, (agora - r.ultimoSinal) / 1000)
end

--- Quantos segundos ate a proxima pergunta.
--
-- @param conversaAberta a pessoa esta dentro de uma conversa? Quem esta com
--        uma conversa na tela espera resposta; quem esta na lista, nao.
function ritmo.intervalo(r, agora, conversaAberta)
  local parado = ritmo.silencio(r, agora)

  if parado < ritmo.VIVO then return ritmo.RAPIDO end
  if parado >= ritmo.ESQUECIDO then return ritmo.LENTO end
  return conversaAberta and ritmo.CONVERSA or ritmo.LISTA
end

--- Nome do degrau, para a linha de diagnostico do aparelho. Serve para a
-- pessoa (e para quem for depurar) entender por que o telefone "demorou":
-- ele nao travou, ele estava dormindo.
function ritmo.degrau(r, agora, conversaAberta)
  local i = ritmo.intervalo(r, agora, conversaAberta)
  if i == ritmo.RAPIDO then return "vivo" end
  if i == ritmo.LENTO  then return "dormindo" end
  return "parado"
end

return ritmo
