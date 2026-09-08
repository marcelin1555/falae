"""Roda os testes da FALAE fora do Minecraft.

O CC:Tweaked nao da para automatizar de fora, entao o Lua real (lupa) roda os
mesmos arquivos que vao para o computador do jogo, contra uma API falsa do CC
(testes/cc_mock.lua). O que passa aqui ainda pode falhar no jogo por causa de
periferico ou timing - mas privacidade entre linhas, freio de tentativas e o
custo de cada rota sao pegos aqui, onde o ciclo e de segundos em vez de
minutos.

    python testes/rodar.py            todos os testes
    python testes/rodar.py --sintaxe  so confere se todo .lua compila
    python testes/rodar.py --carga    so a afericao de custo
"""

import sys
from pathlib import Path

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit("falta a lupa: pip install lupa")

PROJETO = Path(__file__).resolve().parent.parent

# Nome do arquivo -> titulo mostrado na saida. A ordem importa: quem quebra a
# fundacao deve aparecer antes de quem quebra o que esta em cima dela.
SUITES = [
    ("teste_numero.lua", "numero da linha"),
    ("teste_linhas.lua", "linhas, PIN e sessao"),
    ("teste_recados.lua", "recados e historico"),
    ("teste_privacidade.lua", "privacidade entre linhas"),
    ("teste_bloqueio.lua", "bloqueio"),
    ("teste_denuncias.lua", "denuncias"),
    ("teste_janela.lua", "telas nos dois formatos"),
    ("teste_telefone.lua", "o telefone ponta a ponta"),
    ("teste_laco.lua", "o laco do telefone"),
    ("teste_toque.lua", "o toque no pocket"),
    ("teste_marca.lua", "a logo"),
    ("teste_grafico.lua", "o grafico"),
    ("teste_painel.lua", "os monitores da central"),
    ("teste_instalador.lua", "instalador"),
    ("teste_carga.lua", "custo e orcamento"),
]


def checar_sintaxe() -> int:
    """Compila todo .lua do projeto sem executar nada."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    carregar = lua.eval(
        "function(codigo, nome)"
        "  local fn, erro = load(codigo, nome)"
        "  return (fn ~= nil), tostring(erro or '')"
        " end"
    )
    problemas = 0
    for caminho in sorted(PROJETO.rglob("*.lua")):
        rel = caminho.relative_to(PROJETO).as_posix()
        codigo = caminho.read_text(encoding="utf-8")
        compilou, erro = carregar(codigo, "@" + rel)
        if not compilou:
            problemas += 1
            print(f"  ERRO  {rel}: {erro}")
        else:
            print(f"  ok    {rel}", flush=True)
    print(f"\n{problemas} arquivo(s) com erro de sintaxe")
    return problemas


def rodar_um(nome: str) -> int:
    """Cada arquivo de teste ganha um Lua novo: o mock instala globais e
    guarda cache em _G, entao dois testes no mesmo estado se contaminariam."""
    # o print do Lua escreve direto no stdout do processo; sem esvaziar o
    # buffer do Python antes, a saida dos dois sai fora de ordem
    sys.stdout.flush()
    lua = LuaRuntime(unpack_returned_tuples=True)
    teste = PROJETO / "testes" / nome
    if not teste.exists():
        print(f"  (pulado: {nome} ainda nao existe)")
        return 0
    fn = lua.eval(f"loadfile([[{teste}]])")
    if fn is None:
        sys.exit(f"nao consegui carregar {teste}")
    return int(fn(PROJETO.as_posix()) or 0)


def rodar_testes(so=None) -> int:
    falhas = 0
    for nome, titulo in SUITES:
        if so and so not in nome:
            continue
        print(f"\n== {titulo} ==", flush=True)
        falhas += rodar_um(nome)
    return falhas


if __name__ == "__main__":
    if "--sintaxe" in sys.argv:
        sys.exit(1 if checar_sintaxe() else 0)

    so = "carga" if "--carga" in sys.argv else None
    if not so:
        print("== sintaxe ==")
        if checar_sintaxe():
            sys.exit(1)
    sys.exit(1 if rodar_testes(so) else 0)
