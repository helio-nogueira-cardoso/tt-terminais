#!/usr/bin/env bash
# Agenda viva: barra fica vermelha (⚠ N) quando há tarefa aberta vencida/hoje; recorrência (rep)
# faz a tarefa renascer com o próximo prazo ao ser concluída, em vez de fechar. Isola HOME/XDG.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[[ -x "$TT" ]] || { echo "FALHOU: tt não executável"; exit 1; }
bash -n "$TT" || { echo "FALHOU: sintaxe"; exit 1; }

for fn in tarefas_hoje_n tarefa_get_rep tarefa_set_rep tarefa_rep_ciclar tarefas_proximo_prazo; do
  grep -q "^$fn()" "$TT" || { echo "FALHOU: função $fn ausente"; exit 1; }
done

mkdir -p "$T/home/.config/tt" "$T/bin" "$T/rt"
printf 'nome=A\n' >"$T/home/.config/tt/config"
printf '#!/usr/bin/env bash\ncase ${1:-} in list-sessions) exit 1;; display-message) echo cx;; *) exit 0;; esac\n' >"$T/bin/tmux"
chmod +x "$T/bin/tmux"
C="$T/home/.config/tt/tarefas"
run(){ env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" \
  TT_RT="$T/rt" TT_MACHINE=A PATH="$T/bin:$PATH" "$TT" "$@"; }
meta(){ awk -F'\t' -v id="$1" '$1==id{print $6}' "$C"; }
prazo_de(){ awk -F'\t' -v id="$1" '$1==id{print $6}' "$C" | sed 's/.*prazo=\([0-9]*\).*/\1/'; }
estado_de(){ awk -F'\t' -v id="$1" '$1==id{print $2}' "$C"; }
fail(){ echo "FALHOU: $1" >&2; exit 1; }
hoje=$(date +%s); ontem=$((hoje - 86400))

# 1) barra normal (amarela 📋) sem prazos
run --tarefa-add "sem prazo" >/dev/null
run --tarefas-barra | grep -Fq '📋 1' || fail "barra deveria mostrar 📋 1 sem urgências"
echo "ok: barra mostra 📋 N quando não há urgência"

# 2) barra vira vermelha (⚠ 1) com uma tarefa vencida
run --tarefa-add "pagar" >/dev/null
idp=$(awk -F'\t' '$5=="pagar"{print $1}' "$C")
awk -F'\t' -v OFS='\t' -v id="$idp" -v m="prazo=$ontem" 'NF>=5{if($1==id){$6=m} print}' "$C" >"$C.n" && mv "$C.n" "$C"
run --tarefas-barra | grep -Fq '⚠ 1' || fail "barra deveria mostrar ⚠ 1 com tarefa vencida: $(run --tarefas-barra)"
echo "ok: barra fica vermelha com ⚠ N quando há tarefa vencida/hoje"

# 3) ciclar recorrência: sem -> d -> w -> m -> sem
run --tarefa-rep-ciclar "$idp" >/dev/null; [[ $(meta "$idp") == *rep=d* ]] || fail "1º ciclo rep deveria ser diária (d)"
run --tarefa-rep-ciclar "$idp" >/dev/null; [[ $(meta "$idp") == *rep=w* ]] || fail "2º ciclo rep deveria ser semanal (w)"
run --tarefa-rep-ciclar "$idp" >/dev/null; [[ $(meta "$idp") == *rep=m* ]] || fail "3º ciclo rep deveria ser mensal (m)"
run --tarefa-rep-ciclar "$idp" >/dev/null; [[ $(meta "$idp") != *rep=* ]] || fail "4º ciclo rep deveria limpar"
echo "ok: recorrência cicla sem -> d -> w -> m -> sem"

# 4) concluir tarefa recorrente (diária) avança o prazo e mantém ABERTA (renasce)
run --tarefa-rep-ciclar "$idp" >/dev/null   # volta para diária
pa=$(prazo_de "$idp")
run --tarefa-toggle "$idp" >/dev/null
[[ $(estado_de "$idp") == aberta ]] || fail "tarefa recorrente concluída deveria permanecer aberta (renascer), veio '$(estado_de "$idp")'"
pd=$(prazo_de "$idp")
[[ -n $pd && $pd -gt $pa ]] || fail "prazo deveria avançar ($pa -> $pd)"
echo "ok: concluir tarefa recorrente avança o prazo e a mantém aberta"

# 5) tarefa recorrente SEM prazo: concluir fecha normalmente (rep sem âncora não age)
run --tarefa-add "habito sem prazo" >/dev/null
idh=$(awk -F'\t' '$5=="habito sem prazo"{print $1}' "$C")
run --tarefa-rep-ciclar "$idh" >/dev/null  # d, mas sem prazo
run --tarefa-toggle "$idh" >/dev/null
[[ $(estado_de "$idh") == feita ]] || fail "rep sem prazo deveria concluir normalmente"
echo "ok: recorrência sem prazo não impede a conclusão normal"
