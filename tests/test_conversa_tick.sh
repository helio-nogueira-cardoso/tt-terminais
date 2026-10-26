#!/usr/bin/env bash
# Ctrl+T no painel abre o menu do tick (tt --mesh-tick-menu) e volta ao painel; Esc continua fechando.
source "$(dirname "$0")/lib.sh"; isolar
M="$T/mesh"; mkdir -p "$M/channel"
printf '#!/bin/sh\necho "$@" >>"%s/chamou"\n' "$T" >"$T/tt-falso"; chmod +x "$T/tt-falso"
TT_MESH="$M" TT_BIN="$T/tt-falso" LINES=20 timeout 60 python3 -I - "$RAIZ/conversa-mesh.py" "$T" <<'PY' || falhou 'o Ctrl+T do painel deveria abrir o menu do tick e o Esc deveria fechar'
import os, pty, sys, time, select
pid, fd = pty.fork()
if pid == 0:
    os.execvp("python3", ["python3", "-I", sys.argv[1], "--painel"])
def ler(t=0.5):
    out=b""; fim=time.time()+t
    while time.time()<fim:
        r,_,_=select.select([fd],[],[],0.1)
        if r:
            try: out+=os.read(fd,65536)
            except OSError: break
    return out
ler(1.0); os.write(fd, b"\x14"); ler(1.0)
os.write(fd, b"\x1b"); ler(0.8)
done,_=os.waitpid(pid, os.WNOHANG)
if done == 0:
    os.kill(pid, 9); raise SystemExit(1)
chamou = open(os.path.join(sys.argv[2], "chamou")).read() if os.path.exists(os.path.join(sys.argv[2], "chamou")) else ""
assert "--mesh-tick-menu" in chamou, "Ctrl+T deveria chamar tt --mesh-tick-menu"
PY
passou 'Ctrl+T no painel abre o menu do tick; Esc fecha'
