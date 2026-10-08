#!/usr/bin/env bash
# Captura rápida com sintaxe natural: a frase carrega prazo (@), prioridade (!) e recorrência (*),
# extraídos para a meta; o resto vira o texto. Isola HOME/XDG; nenhum arquivo real tocado.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[[ -x "$TT" ]] || { echo "FALHOU: tt não executável"; exit 1; }
bash -n "$TT" || { echo "FALHOU: sintaxe"; exit 1; }

for fn in tarefa_add_natural tarefas_token_prazo; do
  grep -q "^$fn()" "$TT" || { echo "FALHOU: função $fn ausente"; exit 1; }
done

mkdir -p "$T/home/.config/tt" "$T/bin" "$T/rt"
printf 'nome=A\n' >"$T/home/.config/tt/config"
printf '#!/usr/bin/env bash\ncase ${1:-} in list-sessions) exit 1;; display-message) echo cx;; *) exit 0;; esac\n' >"$T/bin/tmux"
chmod +x "$T/bin/tmux"
C="$T/home/.config/tt/tarefas"
run(){ env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" \
  TT_RT="$T/rt" TT_MACHINE=A PATH="$T/bin:$PATH" "$TT" "$@"; }
linha(){ awk -F'\t' -v t="$1" '$5==t{print; exit}' "$C"; }
fail(){ echo "FALHOU: $1" >&2; exit 1; }

# 1) frase completa: texto limpo + prazo + prioridade + recorrência na meta
run --tarefa-add-natural "Pagar aluguel @hoje !alta *m" >/dev/null
l=$(linha "Pagar aluguel")
[[ -n $l ]] || fail "texto não ficou 'Pagar aluguel' (tokens não removidos): $(cat "$C")"
grep -q 'prio=1' <<<"$l" || fail "!alta não virou prio=1: $l"
grep -q 'rep=m' <<<"$l" || fail "*m não virou rep=m: $l"
grep -q 'prazo=' <<<"$l" || fail "@hoje não virou prazo: $l"
echo "ok: frase natural separa texto, prazo, prioridade e recorrência"

# 2) data explícita @DD/MM vira prazo com o dia/mês certos
run --tarefa-add-natural "Dentista @25/12" >/dev/null
l=$(linha "Dentista"); ep=$(sed 's/.*prazo=\([0-9]*\).*/\1/' <<<"$l")
[[ -n $ep ]] || fail "@25/12 não virou prazo: $l"
d=$(date -d "@$ep" +%m/%d 2>/dev/null || date -r "$ep" +%m/%d 2>/dev/null)
[[ $d == 12/25 ]] || fail "@25/12 resolveu para data errada ($d)"
echo "ok: @DD/MM resolve o prazo (dia/mês)"

# 2b) data com ano @DD/MM/AAAA (regressão: "rest: unbound variable" deixava o token no texto, sem prazo)
run --tarefa-add-natural "Renovar passaporte @05/01/2031" >/dev/null
l=$(linha "Renovar passaporte")
[[ -n $l ]] || fail "@DD/MM/AAAA ficou no texto (token não consumido): $(cat "$C")"
ep=$(sed 's/.*prazo=\([0-9]*\).*/\1/' <<<"$l"); [[ -n $ep && $ep != "$l" ]] || fail "@05/01/2031 não virou prazo: $l"
d=$(date -d "@$ep" +%Y-%m-%d 2>/dev/null || date -r "$ep" +%Y-%m-%d 2>/dev/null)
[[ $d == 2031-01-05 ]] || fail "@05/01/2031 resolveu para data errada ($d)"
echo "ok: @DD/MM/AAAA resolve o prazo com o ano"

# 3) !media => prio=2; sem tokens => texto puro, sem meta
run --tarefa-add-natural "Revisar !media" >/dev/null
grep -q 'prio=2' <<<"$(linha "Revisar")" || fail "!media não virou prio=2"
run --tarefa-add-natural "Tarefa simples" >/dev/null
l=$(linha "Tarefa simples")
m6=$(awk -F'\t' '{print $6}' <<<"$l")
[[ -z $m6 ]] || fail "tarefa sem tokens não deveria ter meta: $l"
echo "ok: !media vira prio=2 e frase sem tokens não cria meta"

# 4) token não reconhecido (@qualquercoisa) permanece no texto
run --tarefa-add-natural "Ligar @joao sobre contrato" >/dev/null
grep -q '@joao' <<<"$(linha "Ligar @joao sobre contrato")" || fail "token @ não reconhecido deveria ficar no texto"
echo "ok: @token desconhecido fica no texto (não vira prazo)"
