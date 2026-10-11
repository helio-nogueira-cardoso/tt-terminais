#!/usr/bin/env bash
# Regressão (projeto tt): emoji viravam "_" (um por célula, 📋 → "__") nas telas que abrem um cliente tmux DENTRO de
# outra janela (e-mail em popup/painel flutuante, pontes). Esse cliente decide se o terminal é UTF-8 pelo ambiente
# dele (LC_ALL/LC_CTYPE/LANG); sem locale UTF-8 o tmux desenha "_". O tt agora lança todos com `tmux -u`.
source "$(dirname "$0")/tmux-isolado.sh"
TT="$(cd "$(dirname "$0")/.." && pwd)/tt"
passou() { echo "ok: $1"; }
falhou() { echo "FALHOU — $1" >&2; exit 1; }

# 1) estática: todo `attach -t` que o tt monta para rodar dentro de outra janela leva -u
sem=$(grep -nE '(env -u TMUX [^"]*|PATH_REMOTO[^"]*tmux )attach -t' "$TT" | grep -vE -- '-u attach' || true)
[[ -z $sem ]] || falhou "cliente aninhado sem -u: $sem"
n=$(grep -cE -- '-u attach -t' "$TT"); ((n >= 5)) || falhou "esperava >= 5 attach com -u no tt, vi $n"
passou "todo cliente tmux aninhado (e-mail em popup/flutuante, ponte local e remota) usa -u"

# 2) dinâmica: o cliente aninhado, SEM locale, desenha o emoji com -u e "_" sem ele
command -v script >/dev/null || { echo "pulado: sem 'script' para dar um terminal ao cliente"; exit 0; }
export LANG=C.UTF-8
fora() { tmux "$@"; }
fora new-session -d -s a -x 100 -y 30 "sleep 300"
( sleep 80 | script -qec "tmux attach -t a" /dev/null ) >/dev/null 2>&1 &
for _ in $(seq 1 20); do [[ $(tmux list-clients -F '#{client_utf8}' 2>/dev/null | head -1) == 1 ]] && break; sleep 0.5; done
[[ $(tmux list-clients -F '#{client_utf8}' 2>/dev/null | head -1) == 1 ]] || { echo "pulado: não consegui anexar um cliente de verdade"; exit 0; }
P=$(tmux list-panes -t a: -F '#{pane_id}' | head -1)
roda() { # modo ("" ou -u)
  tmux -L aninhado kill-server 2>/dev/null
  cat >"$TMUX_TMPDIR/an.sh" <<SH
unset TMUX
env -u LANG -u LC_ALL -u LC_CTYPE tmux -L aninhado new-session -d -s i -x 40 -y 6 "printf 'ANINHADO: \xf0\x9f\x93\x8b \xe2\x9c\x93 fim\n'; sleep 30"
exec env -u LANG -u LC_ALL -u LC_CTYPE tmux $1 -L aninhado attach -t i
SH
  local alvo
  alvo=$(tmux split-window -d -P -F '#{pane_id}' -t "$P" -- bash "$TMUX_TMPDIR/an.sh")
  sleep 4; tmux capture-pane -p -t "$alvo" | grep ANINHADO | head -1
  tmux kill-pane -t "$alvo" 2>/dev/null; tmux -L aninhado kill-server 2>/dev/null
}
sem=$(roda ""); com=$(roda "-u")
[[ $sem == *"__ _"* ]] || echo "(aviso: sem -u não reproduziu o '_' neste tmux: $sem)"
[[ $com == *"📋 ✓"* ]] || falhou "com -u o emoji deveria aparecer: '$com'"
passou "sem locale: com -u o emoji aparece ($com)"
