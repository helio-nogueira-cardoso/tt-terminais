#!/usr/bin/env bash
# Cópias da mesma conversa do Claude: fica a da aba anexada; as outras ociosas são encerradas
# (Ctrl+C duplo); uma cópia trabalhando nunca é tocada; conversas diferentes não são afetadas.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin" "$HOME/.claude/sessions"
cat >"$T/bin/claude" <<'C'
#!/bin/bash
n=0; trap 'n=$((n+1)); [ $n -ge 2 ] && exit 0' INT
while :; do sleep 0.2; done
C
chmod +x "$T/bin/claude"
sessao() { # nome conversa estado
  tmux new -d -s "$1" "$T/bin/claude"; sleep 0.5
  local pid; pid=$(pgrep -f "$T/bin/claude" -n)
  printf '{"pid":%s,"sessionId":"%s","status":"%s","name":"x"}\n' "$pid" "$2" "$3" >"$HOME/.claude/sessions/$pid.json"
  echo "$pid"
}
tmux -f /dev/null new -d -s base 'sleep 600'
a=$(sessao anexada conv-1 idle); b=$(sessao ociosa conv-1 idle); c=$(sessao trabalhando conv-1 busy); d=$(sessao outra conv-2 idle)
anexar v 80 20 anexada; sleep 1.5
"$TT" --encerrar-duplicados; sleep 1.5
vivo() { [[ -d /proc/$1 ]] && echo vivo || echo morto; }
r="$(vivo "$a") $(vivo "$b") $(vivo "$c") $(vivo "$d")"
[[ $r == "vivo morto vivo vivo" ]] || falhou "esperava anexada viva, ociosa encerrada, trabalhando e outra conversa vivas: $r"
grep -q 'claude duplicado encerrado: conversa conv-1, aba ociosa' "$HOME/.cache/tt-vigia.log" || falhou 'encerramento não registrado no log'
passou 'cópia ociosa da mesma conversa encerrada; anexada, trabalhando e outra conversa intactas'
