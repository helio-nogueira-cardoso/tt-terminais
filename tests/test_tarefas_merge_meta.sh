#!/usr/bin/env bash
# Empate total no merge de tarefas (mesmo id, mesmo "mudada", mesmo estado) funde o meta: uma máquina
# com pai/ord e outra com desc acabam iguais, em qualquer ordem — antes cada uma guardava a sua.
source "$(dirname "$0")/lib.sh"; isolar
eval "$(sed -n '/^tarefas_merge() {/,/^}/p' "$TT")"
T=$'\t'; A="$HOME/a.tsv"; B="$HOME/b.tsv"
printf 'aaaaaaaaaaaa\taberta\t1\t100\tfilha\tdesc=XYZ\nbbbbbbbbbbbb\tfeita\t1\t100\tigual\n' >"$A"
printf 'aaaaaaaaaaaa\taberta\t1\t100\tfilha\tpai=mmmmmmmmmmmm|ord=2\nbbbbbbbbbbbb\tfeita\t1\t100\tigual\n' >"$B"
ab=$(tarefas_merge "$A" "$B"); ba=$(tarefas_merge "$B" "$A")
[[ $ab == "$ba" ]] || falhou "merge depende da ordem: $ab // $ba"
l=$(grep '^aaaa' <<<"$ab")
for k in 'desc=XYZ' 'pai=mmmmmmmmmmmm' 'ord=2'; do [[ $l == *"$k"* ]] || falhou "faltou $k: $l"; done
[[ $(grep -c . <<<"$ab") == 2 ]] || falhou "linhas a mais: $ab"
passou 'empate no merge: pai/ord de uma e desc da outra se juntam, igual em qualquer ordem'
printf '%s\n' "$ab" >"$A"; [[ $(tarefas_merge "$A" "$B") == "$ab" ]] || falhou 'merge não é idempotente'
printf 'aaaaaaaaaaaa\tfeita\t1\t100\tfilha\tpai=zzzzzzzzzzzz\n' >"$B"
[[ $(tarefas_merge "$A" "$B" | cut -f2) == *feita* ]] || falhou 'estado de maior rank deveria vencer'
passou 'merge idempotente; estado de maior rank continua vencendo'
