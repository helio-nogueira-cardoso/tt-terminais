#!/usr/bin/env bash
# Regressão das sessões fixadas com um tmux de verdade (servidor isolado): o mock de tmux do
# test_fixadas.sh devolve TAB real e não pega formatos que o tmux imprime literalmente ("\t").
#  - reconciliar não pode desafixar uma sessão que existe;
#  - rename feito por fora do tt é acompanhado pelo identificador;
#  - fixar durante uma reconciliação lenta não pode ser desfeito por ela.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
D=$(mktemp -d)
export HOME=$D/home XDG_CONFIG_HOME=$D/home/.config TMUX_TMPDIR=$D/tmux TT_RT=$D/rt TT_DIR=$ROOT
unset TMUX TMUX_PANE
mkdir -p "$XDG_CONFIG_HOME/tt" "$TMUX_TMPDIR" "$TT_RT"
trap 'tmux kill-server 2>/dev/null || true; rm -rf "$D"' EXIT
printf 'nome=teste\n' >"$XDG_CONFIG_HOME/tt/config"
: >"$XDG_CONFIG_HOME/tt/maquinas"
tt() { "$ROOT/tt" "$@"; }
lista() { cut -f1,2 "$XDG_CONFIG_HOME/tt/fixadas" | tr '\t' ':' | sort | tr '\n' ' '; }
falha() { echo "FALHOU — $1 (fixadas: $(lista))" >&2; exit 1; }

tmux -f /dev/null new -d -s alfa 'sleep 600'
tmux new -d -s beta 'sleep 600'

tt --fixar alfa >/dev/null
[[ $(lista) == "teste:alfa " ]] || falha 'fixar alfa'
[[ -n $(cut -f3 "$XDG_CONFIG_HOME/tt/fixadas") ]] || falha 'fixada sem identificador'

tt --reconciliar-fixadas
[[ $(lista) == "teste:alfa " ]] || falha 'reconciliar desafixou uma sessão que existe'

tmux rename-session -t =alfa alfa-renomeada
tt --reconciliar-fixadas
[[ $(lista) == "teste:alfa-renomeada " ]] || falha 'rename por fora do tt não foi acompanhado'

# Reconciliação lenta (uma máquina que não responde) que também tem algo a mudar (uma sessão que
# fechou): fixar no meio dela não pode ser desfeito quando ela terminar.
printf '192.0.2.1 ninguem lenta\n' >"$XDG_CONFIG_HOME/tt/maquinas"
tmux new -d -s gama 'sleep 600'
tt --fixar gama >/dev/null
printf 'lenta\tsessao-x\tid-x\n' >>"$XDG_CONFIG_HOME/tt/fixadas"
tmux kill-session -t =gama
tt --reconciliar-fixadas &
sleep 1
tt --fixar beta >/dev/null
wait
lista | grep -q 'teste:beta' || falha 'fixar durante a reconciliação foi desfeito'
lista | grep -q 'teste:alfa-renomeada' || falha 'reconciliação concorrente perdeu alfa'
lista | grep -q 'lenta:sessao-x' || falha 'máquina sem resposta perdeu a fixada'

tt --reconciliar-fixadas
lista | grep -q 'teste:gama' && falha 'sessão fechada continuou fixada'
lista | grep -q 'teste:beta' || falha 'beta sumiu na reconciliação seguinte'

echo 'ok: fixadas com tmux real (reconciliar, rename, concorrência)'
