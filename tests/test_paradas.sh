#!/usr/bin/env bash
# Sessões paradas: fecha só a que ninguém usa e não roda nada; nunca anexada, fixada, com programa
# em primeiro ou segundo plano, nem ponte; 0 desliga. O tempo vale para a config de todas.
# Shells aninhados ociosos (um "bash -l" aberto para recarregar o PATH) e o invólucro do proot não
# contam como programa; um shell aninhado com algo rodando, ou "sh -c", conta.
source "$(dirname "$0")/lib.sh"; isolar
T_() { tmux -f /dev/null "$@"; }
T_ new -d -s parada 'bash --norc'
T_ new -d -s fundo 'bash --norc'; tmux send -t =fundo: 'sleep 900 &' Enter
T_ new -d -s rodando 'bash --norc'; tmux send -t =rodando: 'sleep 900' Enter
T_ new -d -s fixada 'bash --norc'; printf 'teste\tfixada\t\n' >"$XDG_CONFIG_HOME/tt/fixadas"
T_ new -d -s ponte 'bash --norc'; tmux set -t =ponte: @ponte x
T_ new -d -s olhada 'bash --norc'; anexar v 80 20 olhada
T_ new -d -s aninhada 'bash --norc'; tmux send -t =aninhada: 'bash --norc' Enter
T_ new -d -s aninhada-rodando 'bash --norc'; tmux send -t =aninhada-rodando: 'bash --norc' Enter
mkdir -p "$T/bin"; ln -s "$(command -v bash)" "$T/bin/proot"
T_ new -d -s proot-ociosa 'bash --norc'; tmux send -t =proot-ociosa: "$T/bin/proot --norc" Enter
T_ new -d -s script 'bash --norc'; tmux send -t =script: "sh -c 'read x'" Enter
sleep 1; tmux send -t =aninhada-rodando: 'sleep 900' Enter
sleep 4
TT_PARADAS_SEGUNDOS=0 "$TT" --fechar-paradas
[[ $(tmux ls -F '#S' | wc -l) == 10 ]] || falhou 'limite 0 (desativado) fechou sessões'
TT_PARADAS_SEGUNDOS=2 "$TT" --fechar-paradas
r=$(tmux ls -F '#S' | sort | tr '\n' ' ')
[[ $r == "aninhada-rodando fixada fundo olhada ponte rodando script " ]] || falhou "sobraram: $r"
passou 'paradas: só a sessão realmente parada fecha (inclusive com shell aninhado ou proot ocioso)'
"$TT" --definir-paradas 45 --local; grep -qx 'fechar_paradas=45' "$XDG_CONFIG_HOME/tt/config" || falhou 'tempo não gravado'
"$TT" --definir-paradas abc --local 2>/dev/null && falhou 'aceitou tempo inválido'
passou 'tempo configurável e validado'
