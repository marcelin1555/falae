--[[ admin - a parte da loja que so o dono mexe

  Preco, quantas linhas ja foram vendidas, e as chaves que abrem esta loja.
  Atras da mesma chave por disquete que protege a central - os tres modulos
  (chave/chaveiro/tranca) sao os mesmos arquivos, e cada maquina guarda o
  proprio chaveiro (o da loja nao sabe nada do chaveiro da central, e
  vice-versa).

  A LOJA EM SI NAO PEDE CHAVE PARA LIGAR NEM PARA VENDER - so para mexer aqui
  dentro. Um cliente nunca precisa de disquete nenhum; so o dono, quando quer
  trocar o preco ou emitir uma segunda chave para outro atendente.

  ASSUME QUE O TERMINAL E O PROPRIO COMPUTADOR, nunca um monitor. tranca.lerPin
  e tranca.abrir desenham direto no `term` fisico (a mesma escolha do console
  da central, que tambem nunca roda numa tela de parede) - se um dia a loja
  ganhar uma versao em monitor de toque, esta tela precisa ser repensada, nao
  so chamada de outro lugar.
]]

local carregar = dofile("/carregar.lua")
local janela  = carregar("janela")
local campo   = carregar("campo")
local store   = carregar("store")
local chave    = carregar("chave")
local chaveiro = carregar("chaveiro")
local tranca   = carregar("tranca")

tranca.usar(chave, chaveiro)
chaveiro.carregar()

local admin = {}

admin.LOG = "/dados/loja.log"

--- Nunca apara, como o log de auditoria da exportacao judicial: acoes de
-- administracao (preco, chaves) sao raras e merecem rastro permanente.
local function registrar(texto)
  store.anexar(admin.LOG, os.epoch("utc") .. "|" .. texto)
end

-- As cores de app.lua, guardadas na entrada de admin.tela(). Modulo carrega
-- uma vez so (ver /carregar.lua), entao isto e estado de UM computador,
-- exatamente como a sessao do balcao da central mora em console.lua.
local C = nil

-- -------------------------------------------------------------------- tela

local function ler(j, y, rotulo, opcoes)
  local c = campo.novo(opcoes)
  while true do
    j:texto(2, y, rotulo, C.fraco, C.fundo)
    j:linha(y + 1, " " .. janela.encher(campo.visivel(c), j.w - 2), C.texto, C.entrada)
    j.destino.setCursorPos(j.x + 1 + campo.cursorVisivel(c), j.y + y)
    j.destino.setCursorBlink(true)

    local ev, p1 = os.pullEvent()
    if ev == "char" then
      campo.tecla(c, nil, p1)
    elseif ev == "key" then
      if p1 == keys.enter then
        j.destino.setCursorBlink(false)
        return campo.valor(c)
      elseif p1 == keys.tab then
        j.destino.setCursorBlink(false)
        return nil
      else
        campo.tecla(c, p1)
      end
    end
  end
end

local function avisar(j, texto, cor)
  j:linha(j.h, " " .. tostring(texto) .. "  (tecla)", cor or C.ruim, C.fundo)
  os.pullEvent("key")
end

--- Drena o "char" que sobra de uma tecla de letra premida de verdade.
--
-- O CC dispara DOIS eventos por uma tecla imprimivel: "key" e, logo depois,
-- "char". Os menus daqui esperam so por "key" (os.pullEvent("key")), mas isso
-- so filtra o QUE ELES VEEM primeiro - o "char" que sobra da mesma tecla
-- continua na fila. Um atalho de letra unica (N para novo preco/nova chave, B
-- para revogar) que chama ler() logo em seguida - e ler() faz um
-- os.pullEvent() SEM filtro como primeira coisa - recebe esse "char" e
-- prefixa a letra do atalho no que for digitado a seguir. Mesma causa do bug
-- de denuncia no telefone (ver telefone/app.lua), replicada aqui.
--
-- So descarta o "char" se ele for EXATAMENTE o esperado: qualquer outra coisa
-- volta pra fila via os.queueEvent, para nao se perder.
local function descartarCharPendente(charEsperado)
  local temporizador = os.startTimer(0)
  local ev, p1, p2, p3 = os.pullEvent()
  os.cancelTimer(temporizador)
  if ev == "char" and p1 == charEsperado then return end
  if not (ev == "timer" and p1 == temporizador) then
    os.queueEvent(ev, p1, p2, p3)
  end
end

-- --------------------------------------------------------------- reivindicar

--- A loja ainda nao tem chave: a primeira a ser emitida vira a dona.
--
-- Mesmo instante de qualquer instalacao nova - quem chega primeiro no
-- computador recem-posto e o dono - e a tela diz isso com todas as letras,
-- como servidor/startup.lua ja faz para a central.
local function reivindicar(j)
  while true do
    j:limpar(C.fundo)
    j:barra(1, " FALAE - loja", "", colors.black, C.marca)
    j:texto(2, 3, "administracao sem dona", C.fraco, C.fundo)
    j:texto(2, 5, "Esta loja ainda nao tem chave.", C.texto, C.fundo)
    j:texto(2, 6, "A primeira emitida agora manda aqui.", C.fraco, C.fundo)

    local id, motivo = tranca.disco()
    if not id then
      j:texto(2, 8, tostring(motivo), C.ruim, C.fundo)
      j:linha(j.h, " ponha um disquete VAZIO   qualquer tecla tenta de novo", C.fraco, C.fundo)
      os.pullEvent("key")
    else
      j:texto(2, 8, "disquete #" .. tostring(id), C.marca, C.fundo)
      local nome = ler(j, 10, "nome da chave:")
      if nome == nil then return false end
      if nome == "" then nome = "loja" end

      local pin = tranca.lerPin("PIN novo (8 a 12 digitos):")
      if not pin then return false end
      local outra = tranca.lerPin("de novo:")
      if outra ~= pin then
        avisar(j, "os dois PINs nao batem", C.ruim)
      else
        local k, erro = tranca.emitir(nome, "loja", pin)
        if not k then
          avisar(j, tostring(erro), C.ruim)
        else
          registrar(("chave %s emitida no disquete #%s (primeira - reivindicou a loja)")
                    :format(nome, tostring(id)))
          avisar(j, "chave gravada - guarde o disquete", C.bom)
          return true
        end
      end
    end
  end
end

-- ------------------------------------------------------------------- menu

local function telaPreco(j, dados)
  while true do
    j:limpar(C.fundo)
    j:barra(1, " administracao", "", colors.black, C.marca)
    j:texto(2, 3, ("preco atual: %s"):format(dados.preco()), C.marca, C.fundo)
    j:linha(j.h, " N novo preco   Q volta", C.fraco, C.fundo)

    local _, k = os.pullEvent("key")
    if k == keys.q or k == keys.backspace then return end
    if k == keys.n then
      descartarCharPendente("n")
      local novo = ler(j, 6, "novo preco:")
      if novo and novo ~= "" then
        local ok, erro = dados.definirPreco(novo)
        if ok then
          registrar("preco alterado para " .. novo)
          avisar(j, "preco alterado", C.bom)
        else
          avisar(j, tostring(erro), C.ruim)
        end
      end
    end
  end
end

local function telaVendas(j, dados)
  j:limpar(C.fundo)
  j:barra(1, " administracao", "", colors.black, C.marca)
  j:texto(2, 3, ("linhas vendidas aqui: %d"):format(dados.vendas()), C.marca, C.fundo)
  j:linha(j.h, " qualquer tecla volta", C.fraco, C.fundo)
  os.pullEvent("key")
end

local function telaChaves(j)
  while true do
    j:limpar(C.fundo)
    j:barra(1, " administracao - chaves", "", colors.black, C.marca)

    local lista = chaveiro.listar()
    if #lista == 0 then
      j:texto(2, 3, "nenhuma chave (nao devia acontecer)", C.ruim, C.fundo)
    else
      j:texto(2, 3, "disquete  papel  chave", C.fraco, C.fundo)
      for i, k in ipairs(lista) do
        j:texto(2, 3 + i, ("#%-8s %-6s %s"):format(tostring(k.disco), k.papel, k.nome),
                C.texto, C.fundo)
      end
    end
    j:linha(j.h, " N nova chave   B revogar   Q volta", C.fraco, C.fundo)

    local _, k = os.pullEvent("key")
    if k == keys.q or k == keys.backspace then return end

    if k == keys.n then
      -- drena aqui, nao so no ramo que abre ler(): se ficar so la, um disco
      -- ausente ou ja-cadastrado deixa o "char" sobrando para a PROXIMA vez
      -- que este menu chamar ler() (num "N" bem-sucedido depois), a mesma
      -- classe de bug so que adiada
      descartarCharPendente("n")
      local id, motivo = tranca.disco()
      if not id then
        avisar(j, tostring(motivo), C.ruim)
      elseif chaveiro.de(id) then
        avisar(j, "esse disquete ja e uma chave desta loja", C.ruim)
      else
        local nome = ler(j, 8, "nome da chave nova:")
        if nome and nome ~= "" then
          local pin = tranca.lerPin("PIN da chave nova:")
          local outra = pin and tranca.lerPin("de novo:")
          if pin and outra == pin then
            local novo, erro = tranca.emitir(nome, "loja", pin)
            if novo then
              registrar(("chave %s emitida no disquete #%s"):format(nome, tostring(id)))
              avisar(j, "chave gravada", C.bom)
            else
              avisar(j, tostring(erro), C.ruim)
            end
          elseif pin then
            avisar(j, "os dois PINs nao batem", C.ruim)
          end
        end
      end
    elseif k == keys.b then
      descartarCharPendente("b")
      local texto = ler(j, 8, "revogar qual disquete:")
      if texto and texto ~= "" then
        local ok, motivo = chaveiro.remover(texto)
        if ok then
          registrar("chave do disquete #" .. texto .. " revogada")
          avisar(j, "revogada", C.bom)
        else
          avisar(j, tostring(motivo or "nao achei essa chave"), C.ruim)
        end
      end
    end
  end
end

--- A tela de administracao inteira. Chamada de app.lua quando alguem aperta A
-- na tela ociosa.
--
-- @param j a janela (sempre o terminal fisico da loja - ver o aviso no topo)
-- @param cores a mesma tabela C de app.lua
-- @param dados { preco=, definirPreco=, vendas= } - as funcoes de app.lua que
--        esta tela precisa. Passadas por fora, e nao lendo app.lua direto, so
--        para nao criar um require circular (app.lua ja carrega admin.lua).
function admin.tela(j, cores, dados)
  C = cores

  if chaveiro.vazio() then
    if not reivindicar(j) then return end
  end

  local sessaoAberta = nil
  while true do
    j:limpar(C.fundo)
    j:barra(1, " administracao da loja", "", colors.black, C.marca)

    local opcoes = { "Preco", "Vendas", "Chaves" }
    for i, texto in ipairs(opcoes) do
      j:texto(2, 3 + i, ("%d. %s"):format(i, texto), C.texto, C.fundo)
    end
    j:linha(j.h, " numero escolhe   Q sai", C.fraco, C.fundo)

    local _, k = os.pullEvent("key")
    if k == keys.q or k == keys.backspace then return end

    local qual = nil
    if k == keys.one then qual = telaPreco
    elseif k == keys.two then qual = telaVendas
    elseif k == keys.three then qual = telaChaves end

    if qual then
      -- toda acao aqui dentro exige a chave, uma vez por entrada nesta tela -
      -- nao a cada sub-tela, para nao pedir o PIN de novo entre "preco" e
      -- "vendas" na mesma visita
      if not sessaoAberta then
        local kAberta, motivo = tranca.abrir("loja", "administracao")
        if not kAberta then
          if motivo ~= "cancelado" then avisar(j, tostring(motivo), C.ruim) end
        else
          sessaoAberta = kAberta
        end
      end
      if sessaoAberta then qual(j, dados) end
    end
  end
end

return admin
