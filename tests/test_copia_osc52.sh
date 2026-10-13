#!/usr/bin/env bash
# Cópia para fora do terminal: o tmux manda cada cópia ao terminal de quem olha por OSC 52. De fábrica
# ele a manda com a seleção vazia ("52;;…"), e o mosh 1.4 só repassa "52;c;…": no Termux via mosh a
# cópia sumia no caminho. O tmux.conf do tt fixa a seleção "c" nos terminais xterm*. Aqui um terminal de
# verdade (script, do util-linux) fica anexado ao tmux isolado com o tmux.conf do pacote e guarda os
# bytes que recebe.
source "$(dirname "$0")/lib.sh"; isolar
command -v script >/dev/null || { passou 'cópia por OSC 52: sem o script (util-linux) nesta máquina, pulado'; exit 0; }
cru=$T/terminal.cru
tmux -f "$RAIZ/tmux.conf" new-session -d -s s -x 100 -y 30 'sleep 60'
TERM=xterm-256color timeout 8 script -q -c "stty rows 30 cols 100; tmux attach -t s" /dev/null >"$cru" 2>&1 </dev/null &
anexado=$!
for _ in $(seq 1 30); do [[ -n $(tmux list-clients 2>/dev/null) ]] && break; sleep 0.1; done
[[ -n $(tmux list-clients 2>/dev/null) ]] || falhou 'o terminal de teste não anexou ao tmux'
tmux set-buffer -w -- 'copia-para-fora'
sleep 1
# recarregar a config (Ctrl+B r, sincronizar) não acumula o ajuste
tmux source-file "$RAIZ/tmux.conf" 2>/dev/null || true
n=$(tmux show -s terminal-overrides | grep -c 'Ms=')
tmux kill-server 2>/dev/null; wait "$anexado" 2>/dev/null || true
osc=$(python3 -I -c '
import base64, re, sys
d = open(sys.argv[1], "rb").read()
for m in re.finditer(rb"\x1b\]52;([^;\x07\x1b]*);([^\x07\x1b]*)(?:\x07|\x1b\\)", d):
    print(m.group(1).decode(), base64.b64decode(m.group(2)).decode())' "$cru")
[[ $osc == 'c copia-para-fora' ]] || falhou "a cópia deveria sair como OSC 52 com a seleção c (o mosh descarta a vazia); veio [$osc]"
((n == 1)) || falhou "recarregar a config acumulou o ajuste do OSC 52 ($n linhas com Ms=)"
passou 'cópia sai por OSC 52 com a seleção c (chega ao Termux via mosh); recarregar a config não acumula'
