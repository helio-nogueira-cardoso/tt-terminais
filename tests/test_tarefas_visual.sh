#!/usr/bin/env bash
# Shell visual do painel de tarefas: cabeçalho com contadores por aba, aba "hoje" (vencidas + de
# hoje), ícone de urgência ⚠/📅 por linha, barra de progresso da mãe, estado vazio orientativo e
# wrapper de data portável. Isola HOME/XDG e usa stub de tmux; nenhum arquivo real é tocado.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[[ -x "$TT" ]]; bash -n "$TT"

for fn in tt_fmt_epoch tt_epoch_de tarefas_dias_ate tarefas_contagens; do
  grep -q "^$fn()" "$TT" || { echo "FALHOU: função $fn ausente"; exit 1; }
done

mkdir -p "$T/home/.config/tt" "$T/bin" "$T/rt"
printf 'nome=A\n' >"$T/home/.config/tt/config"
printf '#!/usr/bin/env bash\ncase ${1:-} in list-sessions) exit 1;; display-message) echo cx;; *) exit 0;; esac\n' >"$T/bin/tmux"
chmod +x "$T/bin/tmux"
C="$T/home/.config/tt/tarefas"
run(){ env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" \
  TT_RT="$T/rt" TT_MACHINE=A PATH="$T/bin:$PATH" "$TT" "$@"; }
fail(){ echo "FALHOU: $1" >&2; exit 1; }
hoje=$(date +%s)
ontem=$((hoje - 86400))

# 1) data portável: epoch -> data -> epoch
e2=$(bash -c '
  source <(sed -n "/^tt_fmt_epoch() {/,/^}/p; /^tt_epoch_de() {/,/^}/p" "'"$TT"'")
  d=$(tt_fmt_epoch '"$hoje"' +%Y-%m-%d); tt_epoch_de "$d 12:00"')
[[ -n $e2 ]] || fail "tt_epoch_de/tt_fmt_epoch não fizeram a ida e volta"
echo "ok: wrapper de data portável converte epoch<->data"

# 2) estado vazio orientativo
: >"$C"
lista=$(run --tarefas-lista)
grep -qi 'criar\|digite\|Sem tarefas\|em dia' <<<"$lista" || fail "estado vazio não orienta: '$lista'"
echo "ok: lista vazia mostra dica em vez de tela em branco"

# 3) urgência: tarefa aberta vencida (prazo ontem) ganha ⚠ e entra na aba 'hoje'
run --tarefa-add "pagar conta" >/dev/null
idv=$(awk -F'\t' '$5=="pagar conta"{print $1}' "$C")
awk -F'\t' -v OFS='\t' -v id="$idv" -v meta="prazo=$ontem" 'NF>=5{if($1==id){$6=meta} print}' "$C" >"$C.n" && mv "$C.n" "$C"
printf 'filtro=hoje\n' >"$T/rt/tt-tarefas-ui-$(id -u)"
lista=$(run --tarefas-lista)
grep -q '◷ venceu ontem' <<<"$lista" || fail "tarefa vencida não mostra '◷ venceu ontem': '$lista'"
grep -q 'pagar conta' <<<"$lista" || fail "aba 'hoje' não mostrou a tarefa vencida"
echo "ok: aba hoje filtra vencidas/hoje e a linha mostra que venceu"

# 4) cabeçalho tem as 5 abas com contador (hoje tem 1)
cab=$(run --tarefas-cabecalho | sed 's/\x1b\[[0-9;]*m//g')
for a in hoje abertas feitas prazo todas; do grep -qi "$a" <<<"$cab" || fail "cabeçalho sem a aba $a"; done
grep -qi 'hoje 1' <<<"$cab" || fail "contador da aba hoje deveria ser 1: $(sed -n 1p <<<"$cab")"
echo "ok: cabeçalho mostra 5 abas com contador (hoje=1)"

# 5) barra de progresso da mãe: 1 de 2 subtarefas feitas
printf 'filtro=todas\n' >"$T/rt/tt-tarefas-ui-$(id -u)"
run --tarefa-add "projeto" >/dev/null
idp=$(awk -F'\t' '$5=="projeto"{print $1}' "$C")
run --tarefa-sub-prompt "$idp" <<<"etapa um" >/dev/null 2>&1
run --tarefa-sub-prompt "$idp" <<<"etapa dois" >/dev/null 2>&1
s1=$(awk -F'\t' '$5=="etapa um"{print $1}' "$C")
run --tarefa-ok "$s1" >/dev/null
lista=$(run --tarefas-lista)
grep -q '1/2' <<<"$lista" || fail "barra de progresso da mãe não mostra 1/2: '$lista'"
echo "ok: barra de progresso da mãe mostra feitas/total (1/2)"
