#!/usr/bin/env bash
# A barra das fixadas não marca como morta (✗) uma sessão que só foi renomeada: entre o rename e a reconciliação o nome
# guardado some do tmux, mas o código estável (@tt_session_id) segue vivo. Sessão que realmente fechou continua ✗.
# (tarefa bero42, 28/10/2026: "fixada indica sessão morta durante renomeação apesar de UUID vivo")
source "$(dirname "$0")/lib.sh"; isolar
tt() { "$TT" "$@"; }
barra() { tt --barra-fixadas 2>/dev/null | sed 's/#\[[^]]*\]//g'; }

tmux -f /dev/null new -d -s alfa 'sleep 600'
tmux new -d -s beta 'sleep 600'
tt --fixar alfa >/dev/null
tt --fixar beta >/dev/null
[[ $(cut -f2 "$XDG_CONFIG_HOME/tt/fixadas" | tr '\n' ' ') == "alfa beta " ]] || falhou 'preparo: fixadas alfa e beta'

b=$(barra)
[[ $b == *'✗'* ]] && falhou "sessões vivas apareceram como mortas: $b"

# 1) rename por fora do tt, sem reconciliar: o nome guardado (alfa) já não existe, o código sim.
tmux rename-session -t =alfa alfa-renomeada
b=$(barra)
[[ $b == *'✗'* ]] && falhou "sessão renomeada (código vivo) apareceu como morta: $b"

# 2) sessão que fechou de verdade (nome e código sumiram) continua marcada como morta.
tmux kill-session -t =beta
b=$(barra)
[[ $b == *'✗'* ]] || falhou "sessão encerrada deixou de aparecer como morta: $b"

# 3) o nome guardado foi reaproveitado por OUTRA sessão (outro código): a fixada acha pelo nome, como sempre.
tmux new -d -s beta 'sleep 600'
b=$(barra)
[[ $b == *'✗'* ]] && falhou "nome reaproveitado não devia aparecer como morto: $b"
passou
