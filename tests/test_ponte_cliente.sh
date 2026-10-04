#!/usr/bin/env bash
# Troca de sessão pedida pela barra de outra máquina (tt --ir-ponte): quando dois aparelhos estão na
# mesma ponte, só o que agiu por último troca de sessão — o outro fica onde estava.
source "$(dirname "$0")/lib.sh"; isolar
O() { fora "$@"; }

tmux -f /dev/null new -d -s ponte-x 'sleep 600'
tmux new -d -s destino 'sleep 600'
O new -d -s pc -x 100 -y 20 "env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t ponte-x"; sleep 0.5
O new -d -s cel -x 60 -y 20 "env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t ponte-x"; sleep 1
O send -t cel x; sleep 1.1 # o celular é quem mexeu por último (atividade em segundos)

"$TT" --ir-ponte ponte-x teste destino
sleep 0.3
estado=$(tmux list-clients -F '#{client_width} #{session_name}' | sort -n | tr '\n' ' ')
[[ $estado == "60 destino 100 ponte-x " ]] || { echo "FALHOU — ir-ponte trocou o aparelho errado: $estado" >&2; exit 1; }
echo 'ok: ir-ponte troca só o aparelho que agiu'

# Pontes por aparelho: os dois vão para a mesma sessão de outra máquina (inacessível de propósito:
# a ponte só tenta conectar). Cada um precisa ganhar a sua ponte; nenhum pode arrastar o outro.
printf '192.0.2.1 ninguem remota\n' >"$XDG_CONFIG_HOME/tt/maquinas"
c_pc=$(tmux list-clients -F '#{client_width} #{client_name}' | awk '$1 == 100 { print $2 }')
c_cel=$(tmux list-clients -F '#{client_width} #{client_name}' | awk '$1 == 60 { print $2 }')
O send -t pc x; sleep 1.1
"$TT" --ir-ponte ponte-x remota alvo                  # o pc vai a remota:alvo
tmux switch-client -c "$c_cel" -t =ponte-x; sleep 0.3
O send -t cel x; sleep 1.1
"$TT" --ir-ponte ponte-x remota alvo                  # agora o cel também
sleep 0.3
pc=$(tmux list-clients -F '#{client_width} #{session_name}' | awk '$1 == 100 { print $2 }')
cel=$(tmux list-clients -F '#{client_width} #{session_name}' | awk '$1 == 60 { print $2 }')
[[ -n $pc && -n $cel && $pc != "$cel" && $pc != ponte-x && $cel != ponte-x ]] ||
  { echo "FALHOU — aparelhos dividem a ponte: pc=$pc cel=$cel" >&2; exit 1; }
[[ $(tmux show-options -qv -t "=$pc:" @ponte_alvo) == "$(tmux show-options -qv -t "=$cel:" @ponte_alvo)" ]] ||
  { echo "FALHOU — pontes com alvos diferentes" >&2; exit 1; }
echo "ok: cada aparelho tem a sua ponte para a mesma sessão remota ($pc, $cel)"

# Ponte sem ninguém há mais que o limite é fechada; ponte em uso fica.
tmux new -d -s velha 'sleep 600'; tmux set-option -t =velha: @ponte x
TT_T_PONTE=0 bash -c "source <(sed -n '/^fechar_pontes_ociosas()/,/^}/p' '$TT'); fechar_pontes_ociosas \$(( \$(date +%s) + 5 ))"
tmux has-session -t =velha 2>/dev/null && { echo "FALHOU — ponte ociosa não fechou" >&2; exit 1; }
tmux has-session -t "=$pc" 2>/dev/null || { echo "FALHOU — ponte em uso foi fechada" >&2; exit 1; }
echo 'ok: pontes ociosas fecham, as em uso ficam'
