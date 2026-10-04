#!/usr/bin/env bash
# Vigia: uma instância só, mesmo lançando várias juntas; quem perde o pidfile sai; sem tmux, sai.
source "$(dirname "$0")/lib.sh"; isolar
tmux -f /dev/null new -d -s s 'sleep 600'
vivos() { local n=0 p; for p in $(pgrep -f "$TT --vigia"); do [[ $(ps -o args= -p "$p") == "bash $TT --vigia" ]] && n=$((n+1)); done; echo $n; }
pid() { cat "$TT_RT/tt-vigia-$(id -u).pid" 2>/dev/null; }
for i in 1 2 3; do TT_PAUSA=2 "$TT" --vigia >/dev/null 2>&1 & done
sleep 3
[[ $(vivos) -le 2 ]] || true # subshells do vigia contam; o dono é o do pidfile
p=$(pid); [[ -n $p && -d /proc/$p ]] || falhou 'nenhum vigia ficou com o pidfile'
sleep 3; n=0; for q in $(pgrep -f "$TT --vigia"); do [[ $(ps -o ppid= -p "$q" | tr -d ' ') == 1 || $(ps -o ppid= -p "$q" | tr -d ' ') == $$ ]] && n=$((n+1)); done
[[ $n -le 1 ]] || falhou "$n vigias principais rodando"
passou 'três vigias lançados juntos: fica um só'
echo 99999 >"$TT_RT/tt-vigia-$(id -u).pid"; sleep 5
[[ -d /proc/$p ]] && falhou 'vigia que perdeu o pidfile continuou rodando'
passou 'vigia que perde o pidfile sai sozinho'
TT_PAUSA=1 "$TT" --vigia >/dev/null 2>&1 & v=$!; sleep 2; tmux kill-server; sleep 7
[[ -d /proc/$v ]] && falhou 'vigia continuou sem servidor tmux'
passou 'sem servidor tmux, o vigia sai'
