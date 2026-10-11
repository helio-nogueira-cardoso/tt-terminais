#!/usr/bin/env bash
# Apelido e código visíveis na lista do painel: o apelido (o mesmo de `tt --tarefa-codigo`) vem antes do
# título em toda tarefa, a subtarefa mostra .N (kito47.2), o código completo aparece no fim da linha em painel
# largo (>= 60 colunas: o painel real tem 64) e a busca acha pelo apelido ou pelo código. A subtarefa também mostra o próprio apelido
# (.N apelido texto), o código no fim em painel largo e, no preview, '⌗ apelido · código' de cada uma.
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
sub1=$(tt --tarefa-codigo "$ap.1" | cut -f2); sub1ap=$(tt --tarefa-codigo "$ap.1" | cut -f1)
[[ $sub1 =~ ^[0-9a-f]{12}$ && $sub1ap =~ ^[a-z]{4}[0-9]{2}$ ]] || fail "subtarefa sem apelido/código: '$sub1ap' '$sub1'"
[[ $(grep -cE '    ☐ \.[0-9]+ [a-z]{4}[0-9]{2} slide' <<<"$l") == 2 ]] && grep -qE "☐ \.1 $sub1ap slide um" <<<"$l" && grep -qE '☐ \.2 [a-z]{4}[0-9]{2} slide dois' <<<"$l" || fail "subtarefas sem .N e apelido: $l"
grep -qE "☐ \.1 $sub1ap slide um .*$sub1" <<<"$l" || fail "painel largo: o código da subtarefa deveria fechar a linha: $l"
passou "painel largo mostra apelido, código e .N das subtarefas, com apelido e código nelas também"

l=$(FZF_COLUMNS=50 tt --tarefas-lista | sem_cor | cut -f2-)
grep -qE "☐ $ap Preparar apresentação" <<<"$l" || fail "painel estreito perdeu o apelido: $l"
grep -q "$id" <<<"$l" && fail "painel estreito não deveria mostrar o código inteiro: $l"
grep -qE "☐ \.1 $sub1ap slide um" <<<"$l" || fail "painel estreito perdeu o apelido da subtarefa: $l"
grep -q "$sub1" <<<"$l" && fail "painel estreito não deveria mostrar o código da subtarefa: $l"
passou "painel estreito (50 colunas) mostra o apelido (da tarefa e das subtarefas), sem o código"

# o painel real do celular: 64 colunas (72 com terminal >= 120) já mostra o código, na tarefa e na subtarefa
l=$(FZF_COLUMNS=64 tt --tarefas-lista | sem_cor | cut -f2-)
grep -qE "☐ $ap Preparar apresentação .*$id" <<<"$l" || fail "painel de 64 colunas deveria mostrar o código da tarefa: $l"
grep -qE "☐ \.1 $sub1ap slide um .*$sub1" <<<"$l" || fail "painel de 64 colunas deveria mostrar o código da subtarefa: $l"
passou "o painel real (64 colunas) mostra apelido e código"

pv=$(tt --tarefa-preview "$id" | sem_cor)
grep -qF "⌗ $sub1ap · $sub1" <<<"$pv" || fail "preview sem '⌗ apelido · código' da subtarefa: $pv"
grep -qF "⌗ $ap · $id" <<<"$pv" || fail "preview perdeu o '⌗ apelido · código' da tarefa: $pv"
passou "o preview mostra apelido e código da tarefa e de cada subtarefa"

for q in "$ap" "${id:0:6}"; do
  r=$(FZF_COLUMNS=100 tt --tarefas-lista "$q" | sem_cor | cut -f2-)
  grep -q 'Preparar apresentação' <<<"$r" && ! grep -q 'Comprar café' <<<"$r" || fail "busca por '$q' deveria achar só a tarefa: $r"
done
passou "a busca acha pelo apelido e pelo código"
echo "TODOS OS TESTES PASSARAM"
