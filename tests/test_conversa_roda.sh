#!/usr/bin/env bash
# Roda do mouse no painel da conversa: para cima rola (3 linhas por giro), para baixo volta, clique não mexe; o mouse é ligado e desligado.
# Usa um pseudo-terminal de verdade (Python pty) e um mesh falso com mensagens de sobra.
source "$(dirname "$0")/lib.sh"; isolar
M="$T/mesh"; mkdir -p "$M/channel"; git -C "$M" init -q
for i in $(seq 1 25); do printf -- "---\nfrom: dell\nto: all\ntopic: t$i\n---\nmensagem numero $i\n" >"$M/channel/$(date -u -d "-$i minutes" +%Y%m%dT%H%M%SZ)-dell-$i.md"; done
TT_MESH="$M" LINES=20 TT_MAQUINA=mac timeout 90 python3 -I - "$RAIZ/conversa-mesh.py" <<'PY' || falhou 'a roda do mouse no painel não se comportou como esperado'
import os, pty, sys, time, select
pid, fd = pty.fork()
if pid == 0:
    os.execvp("python3", ["python3", "-I", sys.argv[1], "--painel"])
def ler(t=0.6):
    out=b""; fim=time.time()+t
    while time.time()<fim:
        r,_,_=select.select([fd],[],[],0.1)
        if r:
            try: out+=os.read(fd,65536)
            except OSError: break
    return out
ler(1.0)
os.write(fd,b"\x1b[<64;10;5M"); assert b"3 linha(s) abaixo" in ler(0.8), "roda para cima deveria rolar (3 linhas por giro)"
os.write(fd,b"\x1b[<64;10;5M"); assert b"6 linha(s) abaixo" in ler(0.8), "a roda continua rolando"
os.write(fd,b"\x1b[<0;10;5M\x1b[<0;10;5m"); ler(0.6)   # clique na conversa não mexe na posição…
os.write(fd,b"\x1b[<65;10;5M"); assert b"3 linha(s) abaixo" in ler(0.8), "clique não deveria voltar ao fim (6 - 3 = 3 linhas abaixo)"
os.write(fd,b"\x1b[<65;10;5M"); assert b"linha(s) abaixo" not in ler(0.8), "roda para baixo deveria voltar ao fim"
apagou = 0
for tecla in (b"a", b"b", b"\x1b[A", b"\x1b[B"):
    os.write(fd, tecla); apagou += ler(0.4).count(b"\x1b[2J")
assert apagou == 0, "o redesenho não pode apagar a tela a cada tecla (pisca)"
os.write(fd,b"\x1b"); fim=ler(0.8)
assert b"\x1b[?1000l" in fim, "o mouse deveria ser desligado ao sair"
done,_=os.waitpid(pid, os.WNOHANG)
if done == 0:
    os.kill(pid, 9); raise SystemExit("o painel não fechou com Esc")
PY
passou 'roda do mouse no painel: rola para cima, clique não mexe, para baixo volta ao fim, mouse desligado ao sair'
