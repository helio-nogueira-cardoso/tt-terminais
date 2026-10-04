#!/usr/bin/env bash
# Sessões paradas: fecha só a que ninguém usa e não roda nada; nunca anexada, fixada, com programa
# em primeiro ou segundo plano, nem ponte; 0 desliga. O tempo vale para a config de todas.
source "$(dirname "$0")/lib.sh"; isolar
T_() { tmux -f /dev/null "$@"; }
T_ new -d -s parada 'bash --norc'
T_ new -d -s fundo 'bash --norc'; tmux send -t =fundo: 'sleep 900 &' Enter
T_ new -d -s rodando 'bash --norc'; tmux send -t =rodando: 'sleep 900' Enter
T_ new -d -s fixada 'bash --norc'; printf 'teste\tfixada\t\n' >"$XDG_CONFIG_HOME/tt/fixadas"
T_ new -d -s ponte 'bash --norc'; tmux set -t =ponte: @ponte x
T_ new -d -s olhada 'bash --norc'; anexar v 80 20 olhada
sleep 4
TT_PARADAS_SEGUNDOS=0 "$TT" --fechar-paradas
[[ $(tmux ls -F '#S' | wc -l) == 6 ]] || falhou 'limite 0 (desativado) fechou sessões'
TT_PARADAS_SEGUNDOS=2 "$TT" --fechar-paradas
r=$(tmux ls -F '#S' | sort | tr '\n' ' ')
[[ $r == "fixada fundo olhada ponte rodando " ]] || falhou "sobraram: $r"
passou 'paradas: só a sessão realmente parada fecha'
"$TT" --definir-paradas 45 --local; grep -qx 'fechar_paradas=45' "$XDG_CONFIG_HOME/tt/config" || falhou 'tempo não gravado'
"$TT" --definir-paradas abc --local 2>/dev/null && falhou 'aceitou tempo inválido'
passou 'tempo configurável e validado'
