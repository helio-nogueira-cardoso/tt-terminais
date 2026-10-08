#!/usr/bin/env bash
# Subtarefas e descrição em visão própria: a mãe só conclui com todas as subtarefas feitas (por
# ⏎, duplo clique, botão ✓, menu e --tarefa-ok), concluir a última não conclui a mãe, reabrir ou
# criar subtarefa reabre a mãe, recorrente reabre o checklist, "limpar feitas" preserva o checklist
# de mãe aberta; a descrição não polui a lista (≡) e abre num cartão (prévia). Isola HOME/XDG.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[[ -x "$TT" ]]; bash -n "$TT"

mkdir -p "$T/home/.config/tt" "$T/bin" "$T/rt"
printf 'nome=A\ntarefas_sync=off\n' >"$T/home/.config/tt/config"
printf '#!/usr/bin/env bash\ncase ${1:-} in list-sessions) exit 1;; display-message) echo cx;; *) exit 0;; esac\n' >"$T/bin/tmux"
chmod +x "$T/bin/tmux"
C="$T/home/.config/tt/tarefas"
UI="$T/rt/tt-tarefas-ui-$(id -u)"
run(){ env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/state" \
  TT_RT="$T/rt" TT_MACHINE=A LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH="$T/bin:$PATH" "$TT" "$@"; }
acao(){ FZF_QUERY= run --tarefa-acao "$@"; }
sem_cor(){ sed 's/\x1b\[[0-9;]*m//g'; }
id_de(){ awk -F'\t' -v t="$1" '$5==t{print $1; exit}' "$C"; }
est(){ awk -F'\t' -v t="$1" '$5==t{print $2; exit}' "$C"; }
meta(){ awk -F'\t' -v t="$1" '$5==t{print $6; exit}' "$C"; }
fail(){ echo "FALHOU: $1" >&2; exit 1; }
printf 'filtro=todas\nmodo=lista\n' >"$UI"

run --tarefa-add "Viagem" >/dev/null; m=$(id_de Viagem)
run --tarefa-sub-prompt "$m" <<<"passagens" >/dev/null 2>&1
run --tarefa-sub-prompt "$m" <<<"hotel" >/dev/null 2>&1
s1=$(id_de passagens); s2=$(id_de hotel)
printf 'filtro=todas\nmodo=lista\n' >"$UI"

# 1) --tarefa-ok recusa a mãe com subtarefas abertas e diz quais faltam
if out=$(run --tarefa-ok "$m" 2>&1); then fail "--tarefa-ok concluiu mãe com subtarefas abertas"; fi
grep -q 'passagens' <<<"$out" && grep -q 'hotel' <<<"$out" || fail "--tarefa-ok deveria listar o que falta: $out"
[[ $(est Viagem) == aberta ]] || fail "mãe não pode ficar feita"
echo "ok: --tarefa-ok recusa a mãe e lista as subtarefas que faltam"

# 2) ⏎, botão ✓ e item do menu recusam, avisam no cabeçalho (uma vez) e abrem a mãe
for via in "enter $m" "feita $m" "clique act:feita:$m"; do
  printf 'filtro=todas\nmodo=lista\n' >"$UI"
  r=$(acao $via); grep -q reload <<<"$r" || fail "ação ($via) deveria recarregar: $r"
  [[ $(est Viagem) == aberta ]] || fail "ação ($via) concluiu a mãe com subtarefas abertas"
  cab=$(FZF_COLUMNS=72 run --tarefas-cabecalho | sem_cor)
  grep -q '⚠ Para concluir, faltam 2 subtarefas: passagens, hotel' <<<"$cab" || fail "aviso ausente ($via): $cab"
  grep -q '⚠' <<<"$(FZF_COLUMNS=72 run --tarefas-cabecalho)" && fail "aviso deveria aparecer uma vez só"
  grep -qx "exp=$m" "$UI" || fail "ação ($via) deveria abrir a mãe para mostrar o que falta"
done
grep -q "act:feita:$m	.*faltam 2 subtarefas" <<<"$(printf 'modo=menu:%s\n' "$m" >"$UI"; run --tarefas-lista | sem_cor)" ||
  fail "menu deveria dizer que faltam 2 subtarefas"
printf 'filtro=todas\nmodo=lista\n' >"$UI"
echo "ok: ⏎, ✓ e menu recusam, avisam o que falta e abrem a mãe"

# 3) duplo clique (2 cliques rápidos) também recusa, e a mãe fica aberta mostrando as subtarefas
acao clique "$m" >/dev/null; acao clique "$m" >/dev/null
[[ $(est Viagem) == aberta ]] || fail "duplo clique concluiu a mãe com subtarefas abertas"
grep -qx "exp=$m" "$UI" || fail "depois da recusa no duplo clique a mãe deveria estar aberta"
echo "ok: duplo clique recusa e deixa a mãe aberta"

# 4) concluir a última subtarefa NÃO conclui a mãe; com tudo feito, a mãe conclui
run --tarefa-ok "$s1"; run --tarefa-ok "$s2"
[[ $(est hotel) == feita ]] || fail "subtarefa não concluiu"
[[ $(est Viagem) == aberta ]] || fail "concluir a última subtarefa não pode concluir a mãe"
acao enter "$m" >/dev/null
[[ $(est Viagem) == feita ]] || fail "com todas as subtarefas feitas a mãe deveria concluir"
echo "ok: a última subtarefa não conclui a mãe; com tudo feito, ela conclui"

# 5) reabrir uma subtarefa (ou criar outra) reabre a mãe
acao clique "$s2" >/dev/null
[[ $(est hotel) == aberta && $(est Viagem) == aberta ]] || fail "reabrir subtarefa deveria reabrir a mãe"
run --tarefa-ok "$s2"; run --tarefa-ok "$m"; [[ $(est Viagem) == feita ]] || fail "mãe deveria concluir de novo"
run --tarefa-sub-prompt "$m" <<<"seguro" >/dev/null 2>&1
[[ $(est Viagem) == aberta ]] || fail "subtarefa nova numa mãe feita deveria reabrir a mãe"
echo "ok: reabrir ou criar subtarefa reabre a mãe"

# 6) "limpar feitas" não apaga o checklist de mãe aberta; apaga a mãe feita com as dela
run --tarefa-add "Antiga" >/dev/null; a=$(id_de Antiga)
run --tarefa-sub-prompt "$a" <<<"etapa" >/dev/null 2>&1; run --tarefa-ok "$(id_de etapa)"; run --tarefa-ok "$a"
run --tarefa-limpar
[[ $(est passagens) == feita ]] || fail "limpar feitas apagou subtarefa feita de mãe aberta"
[[ $(est Antiga) == removida && $(est etapa) == removida ]] || fail "limpar feitas deveria remover a mãe feita e as subtarefas dela"
echo "ok: limpar feitas preserva o checklist de mãe aberta"

# 7) mãe recorrente: concluir avança o prazo (mantendo a hora) e reabre as subtarefas
run --tarefa-add-natural "Faxina @amanha 9h *semanal" >/dev/null; f=$(id_de Faxina)
run --tarefa-sub-prompt "$f" <<<"cozinha" >/dev/null 2>&1; run --tarefa-ok "$(id_de cozinha)"
p0=$(sed -n 's/.*prazo=\([0-9]*\).*/\1/p' <<<"$(meta Faxina)")
acao feita "$f" >/dev/null
p1=$(sed -n 's/.*prazo=\([0-9]*\).*/\1/p' <<<"$(meta Faxina)")
((p1 - p0 >= 6 * 86400)) || fail "recorrente semanal deveria avançar ~7 dias ($p0 -> $p1)"
[[ $(meta Faxina) == *hora=1* ]] || fail "recorrente perdeu o horário ao avançar: $(meta Faxina)"
[[ $(est Faxina) == aberta && $(est cozinha) == aberta ]] || fail "recorrente deveria seguir aberta e reabrir as subtarefas"
echo "ok: mãe recorrente avança o prazo com a hora e reabre o checklist"

# 8) descrição em visão própria: fora da lista (≡), aberta mostra uma linha que abre o cartão
run --tarefa-add "Relatório" >/dev/null; r=$(id_de Relatório)
printf '#!/bin/sh\nprintf "primeira linha\\\\nsegunda linha\\\\n" > "$1"\n' >"$T/bin/ed"; chmod +x "$T/bin/ed"
EDITOR="$T/bin/ed" run --tarefa-desc-prompt "$r" >/dev/null 2>&1
printf 'filtro=todas\nmodo=lista\n' >"$UI"
l=$(run --tarefas-lista | sem_cor)
grep -q 'Relatório  ≡$' <<<"$l" || fail "tarefa com descrição deveria mostrar só ≡ na linha: $(grep Relatório <<<"$l")"
grep -q 'primeira linha' <<<"$l" && fail "a descrição não pode aparecer na lista"
acao clique "$r" >/dev/null
l=$(run --tarefas-lista | sem_cor)
grep -q "^desc:$r	.*≡ descrição · 2 linhas" <<<"$l" || fail "tarefa aberta sem a linha '≡ descrição · 2 linhas': $l"
grep -q 'primeira linha' <<<"$l" && fail "nem aberta a descrição entra na lista (vai para a visão própria)"
[[ $(acao clique "desc:$r") == toggle-preview ]] || fail "clique em ≡ descrição deveria abrir a visão (prévia)"
grep -q 'execute(.*--tarefa-desc-prompt' <<<"$(acao clique "desc:$m")" || fail "sem descrição, o clique deveria abrir o editor"
card=$(run --tarefa-preview "desc:$r" | sem_cor)
[[ $(sed -n 1p <<<"$card") == Relatório ]] || fail "cartão deveria começar pelo título: $card"
grep -q 'primeira linha' <<<"$card" && grep -q 'segunda linha' <<<"$card" || fail "cartão sem a descrição inteira: $card"
grep -q 'Subtarefas 2/3' <<<"$(run --tarefa-preview "$m" | sem_cor)" || fail "cartão da mãe deveria resumir as subtarefas"
grep -q 'Sem descrição' <<<"$(run --tarefa-preview "$m" | sem_cor)" || fail "cartão sem descrição deveria dizer como escrever"
echo "ok: descrição fora da lista (≡), linha '≡ descrição' abre o cartão com tudo"
