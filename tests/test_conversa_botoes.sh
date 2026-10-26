#!/usr/bin/env bash
# Botões do rodapé do painel: clicar em "fechar" fecha; clicar em "atualizar" não fecha. Pseudo-terminal de verdade.
source "$(dirname "$0")/lib.sh"; isolar
M="$T/mesh"; mkdir -p "$M/channel"; git -C "$M" init -q
TT_MESH="$M" LINES=20 timeout 90 python3 -I - "$RAIZ/conversa-mesh.py" <<'PY' || falhou 'os botões do painel não responderam a clique'
import os, pty, sys, time, select
def abrir():
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("python3", ["python3", "-I", sys.argv[1], "--painel"])
    return pid, fd
def ler(fd, t=0.6):
    out=b""; fim=time.time()+t
    while time.time()<fim:
        r,_,_=select.select([fd],[],[],0.1)
        if r:
            try: out+=os.read(fd,65536)
            except OSError: break
    return out
altura = 15            # LINES=20 - 5
linha_botoes = altura + 2
x_atualizar, x_fechar = 4, 30  # dentro de cada chip (ver BOTOES)
# clique em atualizar: o painel continua aberto
pid, fd = abrir(); ler(fd, 1.0)
os.write(fd, f"\x1b[<0;{x_atualizar};{linha_botoes}M".encode()); ler(fd, 0.8)
os.write(fd, f"\x1b[<0;{x_atualizar};{linha_botoes}m".encode()); ler(fd, 0.5)
assert os.waitpid(pid, os.WNOHANG)[0] == 0, "clicar em atualizar não pode fechar o painel"
# clique em fechar: fecha
os.write(fd, f"\x1b[<0;{x_fechar};{linha_botoes}M".encode()); ler(fd, 1.0)
done,_ = os.waitpid(pid, os.WNOHANG)
if done == 0:
    os.kill(pid, 9); raise SystemExit("clicar em fechar deveria fechar o painel")
PY
passou 'botões do rodapé: atualizar não fecha, fechar fecha'
