#!/usr/bin/env bash
# Arquivo (histórico) de tarefas: arquivar as feitas (^l: arquivar/apagar/cancelar), uma tarefa
# pelo menu, a mãe leva as subtarefas, subtarefa não vai sozinha e a feita de mãe aberta fica;
# fora da lista, das contas e da agenda; aba Arquivo com busca; restaurar devolve como estava;
# apagar de vez some sem histórico; sync por merge (arquivar/restaurar vencem a cópia velha);
# CLI; e a lista ativa continua rápida com milhares de arquivadas. Isola HOME/XDG.
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
acao(){ FZF_QUERY=${Q:-} run --tarefa-acao "$@"; }
sem_cor(){ sed 's/\x1b\[[0-9;]*m//g'; }
id_de(){ awk -F'\t' -v t="$1" '$5==t{print $1; exit}' "$C"; }
est(){ awk -F'\t' -v t="$1" '$5==t{print $2; exit}' "$C"; }
meta(){ awk -F'\t' -v t="$1" '$5==t{print $6; exit}' "$C"; }
fail(){ echo "FALHOU: $1" >&2; exit 1; }
filtro(){ printf 'filtro=%s\nmodo=lista\n' "$1" >"$UI"; }
filtro todas

run --tarefa-add "Projeto" >/dev/null; p=$(id_de Projeto)
run --tarefa-sub-prompt "$p" <<<"etapa 1" >/dev/null 2>&1; run --tarefa-ok "$(id_de 'etapa 1')"; run --tarefa-ok "$p"
run --tarefa-add "Aberta" >/dev/null; a=$(id_de Aberta)
run --tarefa-sub-prompt "$a" <<<"sub pronta" >/dev/null 2>&1; run --tarefa-ok "$(id_de 'sub pronta')"
run --tarefa-add-natural "Comprar pão @hoje" >/dev/null; run --tarefa-ok "$(id_de 'Comprar pão')"
run --tarefa-add "Ideia" >/dev/null
filtro todas

# 1) ^l: ⏎ (padrão) arquiva as feitas de topo com as subtarefas; sub feita de mãe aberta fica
run --tarefa-limpar-prompt <<<"" >/dev/null 2>&1
[[ $(est Projeto) == arquivada && $(est 'etapa 1') == arquivada ]] || fail "^l/⏎ deveria arquivar a mãe feita com a subtarefa"
[[ $(est 'Comprar pão') == arquivada ]] || fail "^l/⏎ deveria arquivar as feitas"
[[ $(est 'sub pronta') == feita && $(est Aberta) == aberta ]] || fail "subtarefa feita de mãe aberta não pode ir para o arquivo"
[[ $(meta Projeto) == *arq=*:f* && $(meta 'Comprar pão') == *prazo=* ]] || fail "arquivar deveria guardar arq=EPOCH:f e manter a meta: $(meta Projeto)"
echo "ok: ^l arquiva as feitas (mãe com subtarefas); checklist de mãe aberta fica"

# 2) fora da lista ativa, das contas, da agenda e do lembrete; aba Arquivo mostra e busca
l=$(run --tarefas-lista | sem_cor)
grep -q 'Projeto\|Comprar pão' <<<"$l" && fail "arquivada não pode aparecer em Todas: $l"
c=$(FZF_COLUMNS=90 run --tarefas-cabecalho | sem_cor | sed -n 1p)
grep -q 'Arquivo 2' <<<"$c" || fail "aba Arquivo deveria contar 2: $c"
grep -q 'Agenda' <<<"$c" && grep -q 'Agenda [0-9]' <<<"$c" && fail "tarefa arquivada não pode contar na Agenda: $c"
filtro arquivo
l=$(run --tarefas-lista | sem_cor)
grep -q '☑ Projeto  ▤ arquivada hoje' <<<"$l" || fail "aba Arquivo sem a tarefa arquivada (com a data): $l"
grep -q 'Ideia\|Aberta' <<<"$l" && fail "aba Arquivo só mostra arquivadas: $l"
grep -q 'Comprar pão' <<<"$(run --tarefas-lista pão | sem_cor)" || fail "busca no Arquivo não achou"
grep -q 'criar tarefa' <<<"$(run --tarefas-lista xyz | sem_cor)" && fail "no Arquivo a busca não oferece criar tarefa"
echo "ok: arquivadas saem da lista/contas/agenda e ficam na aba Arquivo (com busca)"

# 3) aberta no Arquivo: subtarefas, ↩ restaurar e ✕ apagar de vez; nada mais mexe nela
acao clique "$p" >/dev/null
l=$(run --tarefas-lista | sem_cor)
grep -q "^rest:$p	.*↩ restaurar para a lista" <<<"$l" || fail "Arquivo aberto sem ↩ restaurar: $l"
grep -q "^apag:$p	.*✕ apagar de vez .*sem histórico" <<<"$l" || fail "Arquivo aberto sem ✕ apagar de vez (sem histórico)"
grep -q '☑ etapa 1' <<<"$l" || fail "Arquivo aberto deveria mostrar a subtarefa"
acao feita "$p" >/dev/null; [[ $(est Projeto) == arquivada ]] || fail "✓ Feita não pode mexer em tarefa arquivada"
grep -q '⚠ Tarefa arquivada' <<<"$(FZF_COLUMNS=90 run --tarefas-cabecalho | sem_cor)" || fail "deveria avisar que está arquivada"
grep -q "^act:restaurar:$p" <<<"$(printf 'modo=menu:%s\n' "$p" >"$UI"; run --tarefas-lista)" || fail "menu da arquivada sem Restaurar"
filtro arquivo
echo "ok: no Arquivo, ↩ restaurar e ✕ apagar de vez; o resto não mexe na arquivada"

# 4) restaurar devolve mãe + subtarefas como estavam (feita/aberta) e tira a marca arq
acao clique "rest:$p" >/dev/null
[[ $(est Projeto) == feita && $(est 'etapa 1') == feita ]] || fail "restaurar deveria devolver mãe e sub como estavam"
[[ $(meta Projeto) != *arq=* ]] || fail "restaurar deveria tirar arq= da meta"
grep -q '↩ Restaurada' <<<"$(FZF_COLUMNS=90 run --tarefas-cabecalho | sem_cor)" || fail "deveria avisar que restaurou"
echo "ok: ↩ restaurar devolve a tarefa (e as subtarefas) como estavam"

# 5) menu ⋯: arquivar uma tarefa aberta; subtarefa não vai sozinha; restaurar volta aberta
filtro todas
acao clique "act:arquivar:$(id_de Ideia)" >/dev/null
[[ $(est Ideia) == arquivada && $(meta Ideia) == *arq=*:a* ]] || fail "menu ⋯ ▤ Arquivar não arquivou a tarefa aberta"
acao arquivar "$(id_de 'sub pronta')" >/dev/null
[[ $(est 'sub pronta') == feita ]] || fail "subtarefa não pode ser arquivada sozinha"
grep -q 'não se arquiva sozinha' <<<"$(FZF_COLUMNS=90 run --tarefas-cabecalho | sem_cor)" || fail "deveria explicar por que a subtarefa não arquiva"
grep -q "^act:arquivar:$a" <<<"$(printf 'modo=menu:%s\n' "$a" >"$UI"; run --tarefas-lista)" || fail "menu ⋯ de tarefa de topo sem ▤ Arquivar"
filtro todas
run --tarefa-restaurar "$(id_de Ideia)"; [[ $(est Ideia) == aberta ]] || fail "restaurar deveria voltar aberta"
echo "ok: menu ⋯ arquiva uma tarefa (aberta também); subtarefa não vai sozinha"

# 6) ^l com x apaga de vez (sem histórico); esc cancela; CLI
run --tarefa-ok "$(id_de Ideia)"
run --tarefa-limpar-prompt <<<"n" >/dev/null 2>&1; [[ $(est Ideia) == feita ]] || fail "cancelar no ^l mudou algo"
run --tarefa-limpar-prompt <<<"x" >/dev/null 2>&1
[[ $(est Ideia) == removida && $(est Projeto) == removida ]] || fail "^l x deveria apagar de vez as feitas"
[[ -z $(run --tarefas-arquivadas | grep Ideia) ]] || fail "apagada de vez não pode ir para o arquivo"
run --tarefas-arquivadas | grep -q 'Comprar pão' || fail "--tarefas-arquivadas deveria listar o histórico"
run --tarefa-arquivar "$(id_de 'sub pronta')" 2>/dev/null && fail "--tarefa-arquivar de subtarefa deveria falhar"
run --tarefa-restaurar "$a" 2>/dev/null && fail "--tarefa-restaurar de tarefa fora do arquivo deveria falhar"
[[ $(run --tarefas-arquivar-feitas) == '0 arquivadas' ]] || fail "sem feitas de topo, arquivar-feitas deveria dizer 0"
echo "ok: ^l x apaga sem histórico, esc cancela; verbos de linha de comando"

# 7) sync: arquivar/restaurar vencem a cópia velha de outra máquina (merge por id/mudada)
velha="$T/velha"; cp "$C" "$velha"
cp_id=$(id_de 'Comprar pão')
awk -F'\t' -v OFS='\t' -v id="$cp_id" '$1==id{$2="feita"; $4=$4-100; sub(/\|?arq=[^|]*/, "", $6)} {print}' "$velha" >"$velha.n" && mv "$velha.n" "$velha"
run --receber-tarefas <"$velha" >/dev/null 2>&1 || true
[[ $(est 'Comprar pão') == arquivada ]] || fail "cópia velha (feita) de outra máquina não pode tirar a tarefa do arquivo"
nova="$T/nova"
awk -F'\t' -v OFS='\t' -v id="$a" '$1==id{$2="arquivada"; $4=$4+100; $6=($6==""?"":$6"|") "arq=" $4 ":a"} $1==id || $6 ~ ("pai=" id) {print}' "$C" >"$nova"
run --receber-tarefas <"$nova" >/dev/null 2>&1
[[ $(est Aberta) == arquivada ]] || fail "tarefa arquivada noutra máquina (mais nova) deveria chegar arquivada aqui"
echo "ok: sync — arquivar vale entre máquinas e cópia velha não desfaz"

# 8) desempenho: 5000 arquivadas não pesam na lista ativa
h=$(date +%s)
for ((i = 1; i <= 5000; i++)); do printf 'c%011d\tarquivada\t%s\t%s\tVelha %s\tarq=%s:f\n' "$i" "$h" "$h" "$i" "$h"; done >>"$C"
filtro todas
t0=$(date +%s%N); run --tarefas-lista >/dev/null; t1=$(date +%s%N); ms_ativa=$(( (t1 - t0) / 1000000 ))
filtro arquivo
t0=$(date +%s%N); n=$(run --tarefas-lista | grep -c 'Velha'); t1=$(date +%s%N); ms_arq=$(( (t1 - t0) / 1000000 ))
((n == 5000)) || fail "aba Arquivo deveria listar as 5000, listou $n"
((ms_ativa < 1500)) || fail "lista ativa com 5000 arquivadas levou $ms_ativa ms"
echo "ok: com 5000 arquivadas, lista ativa em $ms_ativa ms e aba Arquivo (5000 linhas) em $ms_arq ms"
