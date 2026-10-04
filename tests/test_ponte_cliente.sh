#!/usr/bin/env bash
# Troca de sessão pedida pela barra de outra máquina (tt --ir-ponte): quando dois aparelhos estão na
# mesma ponte, só o que agiu por último troca de sessão — o outro fica onde estava.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
D=$(mktemp -d)
export HOME=$D/home XDG_CONFIG_HOME=$D/home/.config TMUX_TMPDIR=$D/tmux TT_RT=$D/rt TT_DIR=$ROOT
unset TMUX TMUX_PANE
mkdir -p "$XDG_CONFIG_HOME/tt" "$TMUX_TMPDIR" "$TT_RT"
printf 'nome=teste\n' >"$XDG_CONFIG_HOME/tt/config"
: >"$XDG_CONFIG_HOME/tt/maquinas"
fora="tt-ponte-teste-$$"
O() { tmux -L "$fora" -f /dev/null "$@"; }
trap 'O kill-server 2>/dev/null || true; tmux kill-server 2>/dev/null || true; rm -rf "$D"' EXIT

tmux -f /dev/null new -d -s ponte-x 'sleep 600'
tmux new -d -s destino 'sleep 600'
O new -d -s pc -x 100 -y 20 "env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t ponte-x"; sleep 0.5
O new -d -s cel -x 60 -y 20 "env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t ponte-x"; sleep 1
O send -t cel x; sleep 1.1 # o celular é quem mexeu por último (atividade em segundos)

"$ROOT/tt" --ir-ponte ponte-x teste destino
sleep 0.3
estado=$(tmux list-clients -F '#{client_width} #{session_name}' | sort -n | tr '\n' ' ')
[[ $estado == "60 destino 100 ponte-x " ]] || { echo "FALHOU — ir-ponte trocou o aparelho errado: $estado" >&2; exit 1; }
echo 'ok: ir-ponte troca só o aparelho que agiu'
