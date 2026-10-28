#!/usr/bin/env bash
# tt-teste: sozinho (envia teclas pelo PTY; não deve disputar a máquina)
# Painel da conversa do mesh: o nome inteiro da persona (com acento), a caixa de mensagem aceita acento, move o cursor para
# qualquer posição (setas, Home/End, Ctrl+setas, Delete, Ctrl+W/U/K, clique), quebra linha, aceita colagem em bloco, as
# mensagens novas aparecem sozinhas e Alt+setas trocam o dia. Pseudo-terminal de verdade; o mesh é falso.
source "$(dirname "$0")/lib.sh"; isolar

# 1) Persona com mais de uma palavra e acento: o nome vai até o travessão.
M="$T/mesh"; mkdir -p "$M/channel"; git -C "$M" init -q
printf '## Personas\n- **dell** · Vito — coordenador.\n- **mac** · Pedro Estêvão — prático e direto.\n- **empresa** · Zaca - crítico.\n' >"$M/mission.md"
hora=$(date -u +%Y%m%dT%H%M%SZ)
printf -- '---\nfrom: mac\nto: all\ntopic: nome\n---\nque isso, meu fi?\n' >"$M/channel/${hora}-mac-a1.md"
printf -- '---\nfrom: empresa\nto: all\ntopic: nome\n---\nhum.\n' >"$M/channel/${hora}-empresa-a2.md"
out=$(TT_MESH="$M" TT_MAQUINA=dell TT_CORES=0 python3 -I "$RAIZ/conversa-mesh.py" "$(date +%F)")
grep -q 'Pedro Estêvão  mac' <<<"$out" || falhou "o nome da persona deveria sair inteiro, com acento: $(grep -m1 mac <<<"$out")"
grep -q 'Zaca  empresa' <<<"$out" || falhou 'persona com hífen como separador deveria sair só com o nome'
passou 'persona: o nome vai até o travessão, com mais de uma palavra e acento'

# 2) Edição no terminal de verdade.
M2="$T/mesh2"; mkdir -p "$M2/channel"; git -C "$M2" init -q
cp "$M/mission.md" "$M2/mission.md"
TT_MESH="$M2" TT_BIN=/bin/true LINES=24 COLUMNS=44 timeout 120 python3 -I - "$RAIZ/conversa-mesh.py" "$M2" <<'PY' || falhou 'a caixa de mensagem do painel não se comportou como esperado'
import glob, os, pty, select, sys, time
script, mesh = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("python3", ["python3", "-I", script, "--painel"])
def ler(t=0.5):
    out = b""; fim = time.time() + t
    while time.time() < fim:
        if select.select([fd], [], [], 0.05)[0]:
            try: out += os.read(fd, 65536)
            except OSError: break
    return out
vistos = set()
def enviado(_n=None):
    """Corpo do próximo recado do dono que aparecer no canal (espera até 3 s). Os nomes dos arquivos não seguem a ordem de
    envio dentro do mesmo segundo, então o que vale é o arquivo novo."""
    fim = time.time() + 3
    while time.time() < fim:
        novos = sorted(set(glob.glob(os.path.join(mesh, "channel", "*-dono-*.md"))) - vistos)
        if novos:
            vistos.add(novos[0])
            return open(novos[0], encoding="utf-8").read().split("\n---\n", 1)[1].rstrip("\n")
        time.sleep(0.1)
    raise AssertionError("o recado não foi gravado")
def digitar(texto):
    os.write(fd, texto.encode()); ler(0.25)
def tecla(b): os.write(fd, b); ler(0.2)
ESQ, DIR, HOME, END = b"\x1b[D", b"\x1b[C", b"\x1b[H", b"\x1b[F"
CTRL_ESQ, DEL = b"\x1b[1;5D", b"\x1b[3~"
ler(1.0)

# a) Acento digitado no meio: "Pedro Estevo" + ← + "ã" → "Pedro Estevão"
digitar("Pedro Estevo"); tecla(ESQ); digitar("ã"); tecla(b"\r")
r = enviado(); assert r == "Pedro Estevão", f"acento no meio do texto: {r!r}"

# b) Home, texto na frente, End, texto atrás; Delete apaga a letra sob o cursor
digitar("Estevão"); tecla(HOME); digitar("Pedro "); tecla(END); digitar("!"); tecla(HOME); tecla(DEL); tecla(DEL); tecla(b"\r")
r = enviado(); assert r == "dro Estevão!", f"Home/End/Delete: {r!r}"

# c) Ctrl+← pula palavra; Ctrl+W apaga a palavra de trás; Ctrl+U apaga até o começo; Ctrl+K até o fim
digitar("um dois três"); tecla(CTRL_ESQ); digitar("X"); tecla(b"\r")
r = enviado(); assert r == "um dois Xtrês", f"Ctrl+←: {r!r}"
digitar("ação rápida e certa"); tecla(b"\x17"); tecla(b"\r")
r = enviado(); assert r == "ação rápida e", f"Ctrl+W: {r!r}"
digitar("antes|depois"); tecla(ESQ * 6); tecla(b"\x0b"); tecla(b"\r")
r = enviado(); assert r == "antes|", f"Ctrl+K: {r!r}"
digitar("lixo fim"); tecla(ESQ * 3); tecla(b"\x15"); tecla(b"\r")
r = enviado(); assert r == "fim", f"Ctrl+U: {r!r}"

# d) Ctrl+J quebra a linha (Enter envia); Alt+Enter também
digitar("linha 1"); tecla(b"\n"); digitar("linha 2"); tecla(b"\x1b\r"); digitar("linha 3"); tecla(b"\r")
r = enviado(); assert r == "linha 1\nlinha 2\nlinha 3", f"linhas: {r!r}"

# e) Colagem em bloco (bracketed paste): com acento e quebra de linha, sem enviar no meio
os.write(fd, "\x1b[200~Pedro Estêvão\nsegunda linha\x1b[201~".encode()); ler(0.4)
tecla(b"\r")
r = enviado(); assert r == "Pedro Estêvão\nsegunda linha", f"colagem: {r!r}"

# f) Texto longo quebra na caixa (várias linhas); Ctrl+Home, ↑/↓ e Home/End andam por ela; nada é perdido
longo = "esta é uma mensagem bem comprida para conferir que a caixa quebra as linhas e não perde nada"
digitar(longo); tecla(b"\x1b[1;5H"); digitar(">> "); tecla(b"\r")   # Ctrl+Home: começo da mensagem toda
r = enviado(); assert r == ">> " + longo, f"texto longo: {r!r}"
digitar(longo); tecla(b"\x1b[A" * 6); tecla(HOME); digitar("["); tecla(b"\x1b[B" * 6); tecla(END); digitar("]"); tecla(b"\r")
r = enviado(); assert r == "[" + longo + "]", f"↑/↓ e Home/End entre as linhas da caixa: {r!r}"

# g) Clique do mouse na caixa move o cursor: caixa na linha 22 (24 linhas: 22 úteis - 1 de caixa + ...); coluna do texto = 14 + c
digitar("abcdef")
os.write(fd, b"\x1b[<0;17;22M\x1b[<0;17;22m"); ler(0.4)   # x=17 → 4ª coluna do texto: antes do "d" (índice 3)
digitar("_"); tecla(b"\r")
r = enviado(); assert r == "abc_def", f"clique na caixa: {r!r}"

# h) Recado enviado aparece na conversa, e mensagem nova de outra máquina aparece sozinha (sem tecla)
digitar("oi, Pedro Estevão"); saida = ler(0.2); os.write(fd, b"\r"); saida = ler(1.2)
assert "oi, Pedro Estevão".encode() in saida, "o recado enviado deveria aparecer na conversa"
hora = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
with open(os.path.join(mesh, "channel", f"{hora}-mac-z9.md"), "w", encoding="utf-8") as f:
    f.write("---\nfrom: mac\nto: all\ntopic: ao vivo\n---\nchegou sem eu apertar nada\n")
vivo = ler(4.5)
assert b"chegou sem eu apertar nada" in vivo, "mensagem nova deveria aparecer sozinha em poucos segundos"
assert "Pedro Estêvão".encode() in vivo, "o cabeçalho da mensagem nova deveria ter o nome inteiro"
assert b"\x1b[2J" not in vivo, "atualizar sozinho não pode apagar a tela (pisca)"

# i) Alt+← (caixa vazia) mostra o dia anterior; Alt+→ volta; a barra do alto diz "ontem"/"hoje"
os.write(fd, b"\x1b[1;3D"); tela = ler(0.8)
assert b"ontem" in tela, "Alt+← deveria mostrar o dia anterior"
os.write(fd, b"\x1b[1;3C"); tela = ler(0.8)
assert b"hoje" in tela, "Alt+→ deveria voltar a hoje"
os.write(fd, b"\x1b[<0;3;1M\x1b[<0;3;1m"); tela = ler(0.8)      # clique na seta ◀ da barra do alto
assert b"ontem" in tela, "clicar na seta ◀ deveria mostrar o dia anterior"

os.write(fd, b"\x1b"); ler(0.6)
fim = time.time() + 5
while time.time() < fim:
    if os.waitpid(pid, os.WNOHANG)[0]: break
    time.sleep(0.1)
else:
    os.kill(pid, 9); raise SystemExit("o painel não fechou com Esc")
PY
passou 'conversa do mesh: acento, cursor em qualquer posição (setas, Home/End, Ctrl, clique), colagem, linhas, ao vivo e troca de dia'

# 3) Funções puras: quebra da caixa, cursor sobre acento combinante e posição por clique.
python3 -I - "$RAIZ/conversa-mesh.py" <<'PY' || falhou 'cálculo da caixa de mensagem errado'
import importlib.util, sys
sp = importlib.util.spec_from_file_location("cm", sys.argv[1]); cm = importlib.util.module_from_spec(sp); sp.loader.exec_module(cm)
t = "uma frase que precisa quebrar em duas linhas"
ls = cm.linhas_entrada(t, 20)
assert all(cm.largura_visual(t[a:b]) <= 20 for a, b in ls), ls
assert "".join(t[a:b] for a, b in ls) == t, ls                      # quebra suave não perde nem duplica nada
assert cm.linhas_entrada("", 10) == [(0, 0)]
assert cm.linhas_entrada("a\n", 10) == [(0, 1), (2, 2)]             # \n no fim: o cursor tem uma linha vazia embaixo
assert cm.linhas_entrada("a" * 25, 10) == [(0, 10), (10, 20), (20, 25)]   # palavra maior que a linha parte no meio
e = "aéi"                                                      # "é" combinante conta como uma letra para o cursor
assert cm.cursor_prox(e, 1) == 3 and cm.cursor_ant(e, 3) == 1
assert cm.cursor_prox("🇧🇷x", 0) == 2 or cm.cursor_prox("🇧🇷x", 0) == 1   # não trava nem passa do fim
assert cm.cursor_prox("x", 1) == 1 and cm.cursor_ant("x", 0) == 0
assert cm.indice_na_coluna("漢字ab", 0, 4, 2) == 1                  # 2ª coluna cai no começo do 2º ideograma (largura 2)
assert cm.palavra_ant("um dois três", 12) == 8 and cm.palavra_prox("um dois", 0) == 2
# linha_do_cursor: no fim de uma linha quebrada à força o cursor fica no começo da seguinte
ls = [(0, 10), (10, 20), (20, 25)]
assert cm.linha_do_cursor(ls, 10) == 1 and cm.linha_do_cursor(ls, 25) == 2 and cm.linha_do_cursor(ls, 0) == 0
PY
passou 'caixa de mensagem: quebra de linha, cursor sobre acentos combinantes e posição pelo clique'
