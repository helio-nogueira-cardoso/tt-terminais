#!/usr/bin/env bash
# Prioridade e ordenação manual das tarefas-mãe. Ciclar prioridade (nenhuma -> alta -> média ->
# nenhuma), ícone 🔴/🟡 no render, ordenação por prioridade (alta primeiro) e movimentação manual
# de tarefas de topo com ^k/^j (grava ord e reordena). Isola HOME/XDG; nenhum arquivo real tocado.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[[ -x "$TT" ]] || { echo "FALHOU: tt não executável"; exit 1; }
bash -n "$TT" || { echo "FALHOU: sintaxe"; exit 1; }

for fn in tarefa_get_prio tarefa_set_prio tarefa_prio_ciclar tarefas_prio_icone tarefas_topo_ordenadas tarefa_mover; do
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
meta(){ awk -F'\t' -v id="$1" '$1==id{print $6}' "$C"; }
pos(){ run --tarefas-lista | grep -n "$1" | head -1 | cut -d: -f1; }

run --tarefa-add "alfa" >/dev/null
run --tarefa-add "beta" >/dev/null
run --tarefa-add "gama" >/dev/null
ida=$(awk -F'\t' '$5=="alfa"{print $1}' "$C")
idb=$(awk -F'\t' '$5=="beta"{print $1}' "$C")
idg=$(awk -F'\t' '$5=="gama"{print $1}' "$C")

# 1) ciclar prioridade: nenhuma -> alta -> média -> nenhuma
run --tarefa-prio-ciclar "$idb" >/dev/null
[[ $(meta "$idb") == *prio=1* ]] || fail "1º ciclo deveria dar prioridade alta (prio=1)"
run --tarefa-prio-ciclar "$idb" >/dev/null
[[ $(meta "$idb") == *prio=2* ]] || fail "2º ciclo deveria dar prioridade média (prio=2)"
run --tarefa-prio-ciclar "$idb" >/dev/null
[[ $(meta "$idb") != *prio=* ]] || fail "3º ciclo deveria limpar a prioridade"
echo "ok: prioridade cicla nenhuma -> alta -> média -> nenhuma"

# 2) ícone 🔴 aparece no render quando prioridade alta
run --tarefa-prio-ciclar "$idg" >/dev/null   # gama vira alta
grep -q '🔴' <<<"$(run --tarefas-lista)" || fail "render não mostra 🔴 para prioridade alta"
echo "ok: render mostra 🔴 na tarefa de prioridade alta"

# 3) ordenação: a de prioridade alta (gama) vem antes das sem prioridade (alfa, beta)
pa=$(pos alfa); pg=$(pos gama)
[[ -n $pg && -n $pa && $pg -lt $pa ]] || fail "prioridade alta (gama, linha $pg) deveria vir antes de alfa (linha $pa)"
echo "ok: tarefa de prioridade alta é listada antes das sem prioridade"

# 4) mover tarefa de topo com ^k/^j (sem prioridade, ordena por recência: gama>beta>alfa).
run --tarefa-prio-ciclar "$idg" >/dev/null  # alta->média
run --tarefa-prio-ciclar "$idg" >/dev/null  # média->nenhuma
primeira=$(run --tarefas-lista | grep -m1 -E 'alfa|beta|gama')
grep -q 'gama' <<<"$primeira" || fail "sem prioridade, a mais recente (gama) deveria estar no topo (1ª: $primeira)"
run --tarefa-mover "$ida" cima >/dev/null
pa=$(pos alfa); pb=$(pos beta)
[[ -n $pa && -n $pb && $pa -lt $pb ]] || fail "mover alfa para cima não a colocou antes de beta (alfa $pa, beta $pb)"
echo "ok: ^k move tarefa de topo para cima (ordem manual via ord)"
