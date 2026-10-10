#!/usr/bin/env bash
# Apelido e código visíveis na lista do painel: o apelido (o mesmo de `tt --tarefa-codigo`) vem antes do
# título em toda tarefa, a subtarefa mostra .N (kito47.2), o código completo aparece no fim da linha em painel
# largo (>= 80 colunas) e a busca acha pelo apelido ou pelo código.
source "$(dirname "$0")/lib.sh"; isolar
tt() { "$TT" "$@"; }
passou() { echo "ok: $1"; }
fail() { echo "FALHOU: $1" >&2; exit 1; }
sem_cor() { sed 's/\x1b\[[0-9;]*m//g'; }
tt --tarefa-add "Preparar apresentação" >/dev/null; tt --tarefa-add "Comprar café" >/dev/null
id=$(tt --tarefa-codigo | awk -F'\t' '$3=="Preparar apresentação"{print $2}'); ap=$(tt --tarefa-codigo | awk -F'\t' '$3=="Preparar apresentação"{print $1}')
[[ $id =~ ^[0-9a-f]{12}$ && $ap =~ ^[a-z]{4}[0-9]{2}$ ]] || fail "código/apelido inesperados: '$id' '$ap'"
tt --tarefa-sub-add "$ap" "slide um" >/dev/null; tt --tarefa-sub-add "$ap" "slide dois" >/dev/null

tt --tarefa-clique "$id" >/dev/null 2>&1   # abre a mãe
l=$(FZF_COLUMNS=100 tt --tarefas-lista | sem_cor | cut -f2-)
grep -qE "☐ $ap Preparar apresentação .*$id" <<<"$l" || fail "painel largo: apelido antes do título e código no fim: $l"
grep -qE '☐ [a-z]{4}[0-9]{2} Comprar café' <<<"$l" || fail "toda tarefa mostra o apelido: $l"
[[ $(grep -cE '    ☐ \.[0-9]+ slide' <<<"$l") == 2 ]] && grep -qE '☐ \.1 slide' <<<"$l" && grep -qE '☐ \.2 slide' <<<"$l" || fail "subtarefas sem .N: $l"
passou "painel largo mostra apelido, código e .N das subtarefas"

l=$(FZF_COLUMNS=60 tt --tarefas-lista | sem_cor | cut -f2-)
grep -qE "☐ $ap Preparar apresentação" <<<"$l" || fail "painel estreito perdeu o apelido: $l"
grep -q "$id" <<<"$l" && fail "painel estreito não deveria mostrar o código inteiro: $l"
passou "painel estreito mostra só o apelido"

for q in "$ap" "${id:0:6}"; do
  r=$(FZF_COLUMNS=100 tt --tarefas-lista "$q" | sem_cor | cut -f2-)
  grep -q 'Preparar apresentação' <<<"$r" && ! grep -q 'Comprar café' <<<"$r" || fail "busca por '$q' deveria achar só a tarefa: $r"
done
passou "a busca acha pelo apelido e pelo código"
echo "TODOS OS TESTES PASSARAM"
