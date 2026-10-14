#!/usr/bin/env bash
# Desfazer a conclusão de uma tarefa recorrente: concluir guarda o prazo anterior (até 3 ciclos),
# conta os ciclos feitos e marca quando foi; `tt --tarefa-desfazer` (e ^z / menu no painel) volta
# um ciclo de cada vez, com as subtarefas como estavam. Sem o que desfazer, uma tarefa feita reabre.
# A linha mostra "✓ ciclo feito" por 24 h e o painel avisa no cabeçalho. Isola HOME/XDG.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
source "$(dirname "$0")/tmux-isolado.sh"
[[ -x "$TT" ]] || { echo "FALHOU: tt não executável"; exit 1; }
bash -n "$TT" || { echo "FALHOU: sintaxe"; exit 1; }

mkdir -p "$T/home/.config/tt" "$T/bin" "$T/rt"
printf 'nome=A\ntarefas_sync=off\n' >"$T/home/.config/tt/config"
printf '#!/usr/bin/env bash\ncase ${1:-} in list-sessions) exit 1;; display-message) echo cx;; *) exit 0;; esac\n' >"$T/bin/tmux"
chmod +x "$T/bin/tmux"
C="$T/home/.config/tt/tarefas"
UI="$T/rt/tt-tarefas-ui-$(id -u)"
run(){ env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" \
  TT_RT="$T/rt" TT_MACHINE=A LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH="$T/bin:$PATH" "$TT" "$@"; }
sem_cor(){ sed 's/\x1b\[[0-9;]*m//g'; }
# Como o fzf: o cabeçalho que a ação devolve pronto (transform-header(cat ARQ)) é o que o painel mostra.
cab_da_acao(){ local o a; o=$(FZF_COLUMNS=90 run --tarefa-acao "$@"); a=$(sed -n "s/.*transform-header(cat '\([^']*\)'.*/\1/p" <<<"$o" | head -1)
  [[ -n $a && -f $a ]] && sem_cor <"$a"; }
id_de(){ awk -F'\t' -v t="$1" '$5==t{print $1; exit}' "$C"; }
meta(){ awk -F'\t' -v id="$1" '$1==id{print $6}' "$C"; }
mk(){ tr '|' '\n' <<<"$(meta "$1")" | sed -n "s/^$2=//p"; }
est(){ awk -F'\t' -v id="$1" '$1==id{print $2}' "$C"; }
set_meta(){ awk -F'\t' -v OFS='\t' -v id="$1" -v m="$2" 'NF>=5{if($1==id){$6=m} print}' "$C" >"$C.n" && mv "$C.n" "$C"; }
fail(){ echo "FALHOU: $1" >&2; exit 1; }

p0=$(date -d "$(date -d '+3 days' +%F) 14:00" +%s)
p1=$(date -d "$(date -d "@$p0" '+%F %H:%M') 1 month" +%s)
p2=$(date -d "$(date -d "@$p1" '+%F %H:%M') 1 month" +%s)

# 1) concluir uma recorrente guarda o prazo anterior, conta o ciclo e marca quando foi
run --tarefa-add "NFe" >/dev/null
nf=$(id_de NFe)
set_meta "$nf" "prazo=$p0|hora=1|rep=m"
run --tarefa-ok "$nf" || fail "concluir a recorrente falhou"
[[ $(mk "$nf" prazo) == "$p1" ]] || fail "1º ciclo deveria avançar um mês: $(meta "$nf")"
[[ $(mk "$nf" ant) == "$p0" ]] || fail "deveria guardar o prazo anterior em ant: $(meta "$nf")"
[[ $(mk "$nf" ciclos) == 1 ]] || fail "deveria contar 1 ciclo: $(meta "$nf")"
[[ -n $(mk "$nf" feito) ]] || fail "deveria marcar quando o ciclo foi feito: $(meta "$nf")"
run --tarefa-ok "$nf" || fail "2º concluir falhou"
[[ $(mk "$nf" prazo) == "$p2" && $(mk "$nf" ant) == "$p0,$p1" && $(mk "$nf" ciclos) == 2 ]] || fail "2º ciclo: $(meta "$nf")"
echo "ok: concluir a recorrente guarda o prazo anterior, conta e data o ciclo"

# 2) desfazer volta um ciclo de cada vez, mantendo a hora; sem nada a desfazer, avisa e falha
run --tarefa-desfazer "$nf" >/dev/null || fail "1º desfazer falhou"
[[ $(mk "$nf" prazo) == "$p1" && $(mk "$nf" ant) == "$p0" && $(mk "$nf" ciclos) == 1 ]] || fail "1º desfazer: $(meta "$nf")"
[[ $(mk "$nf" hora) == 1 ]] || fail "desfazer perdeu o horário: $(meta "$nf")"
[[ -z $(mk "$nf" feito) ]] || fail "desfazer deveria tirar a marca de ciclo feito agora: $(meta "$nf")"
saida=$(run --tarefa-desfazer "$nf") || fail "2º desfazer falhou"
grep -q 'prazo volta' <<<"$saida" || fail "desfazer deveria dizer para onde o prazo voltou: $saida"
[[ $(mk "$nf" prazo) == "$p0" && -z $(mk "$nf" ant) && -z $(mk "$nf" ciclos) ]] || fail "2º desfazer: $(meta "$nf")"
[[ $(est "$nf") == aberta ]] || fail "recorrente desfeita deveria seguir aberta"
run --tarefa-desfazer "$nf" >/dev/null 2>"$T/err" && fail "sem nada a desfazer deveria falhar"
grep -qi 'nada a desfazer' "$T/err" || fail "deveria explicar que não há o que desfazer: $(cat "$T/err")"
echo "ok: desfazer volta um ciclo por vez e para quando não há mais"

# 3) guarda só os 3 últimos ciclos
for _ in 1 2 3 4 5; do run --tarefa-ok "$nf" || fail "concluir em série falhou"; done
[[ $(mk "$nf" ant | tr ',' '\n' | grep -c .) == 3 ]] || fail "deveria guardar só 3 prazos: $(meta "$nf")"
[[ $(mk "$nf" ciclos) == 5 ]] || fail "o contador não tem limite: $(meta "$nf")"
for _ in 1 2 3; do run --tarefa-desfazer "$nf" >/dev/null || fail "desfazer em série falhou"; done
run --tarefa-desfazer "$nf" >/dev/null 2>&1 && fail "o 4º desfazer não tem o que voltar"
[[ $(mk "$nf" ciclos) == 2 ]] || fail "contador após 3 desfazer: $(meta "$nf")"
echo "ok: guarda até 3 ciclos para desfazer; o contador segue"

# 4) mãe recorrente: desfazer devolve as subtarefas reabertas ao estado feito; a nova fica aberta
run --tarefa-add "Faxina" >/dev/null
fx=$(id_de Faxina)
set_meta "$fx" "prazo=$p0|rep=w"
run --tarefa-sub-add "$fx" "cozinha" >/dev/null; run --tarefa-sub-add "$fx" "sala" >/dev/null
coz=$(id_de cozinha); sala=$(id_de sala)
run --tarefa-ok "$coz"; run --tarefa-ok "$sala"
run --tarefa-ok "$fx" || fail "concluir a mãe falhou"
[[ $(est "$coz") == aberta && $(est "$sala") == aberta ]] || fail "concluir deveria reabrir o checklist"
run --tarefa-sub-add "$fx" "quintal" >/dev/null; qt=$(id_de quintal)
run --tarefa-desfazer "$fx" >/dev/null || fail "desfazer da mãe falhou"
[[ $(est "$coz") == feita && $(est "$sala") == feita ]] || fail "desfazer deveria devolver as subtarefas a feitas"
[[ $(est "$qt") == aberta ]] || fail "subtarefa criada depois não é do ciclo desfeito: deveria seguir aberta"
[[ $(mk "$fx" prazo) == "$p0" && -z $(mk "$fx" antsub) ]] || fail "mãe desfeita: $(meta "$fx")"
echo "ok: desfazer devolve o checklist do ciclo, sem tocar no que nasceu depois"

# 5) não recorrente: desfazer reabre uma tarefa feita; aberta sem histórico não tem o que desfazer
run --tarefa-add "simples" >/dev/null; sp=$(id_de simples)
run --tarefa-desfazer "$sp" >/dev/null 2>&1 && fail "aberta sem histórico não tem o que desfazer"
run --tarefa-ok "$sp"; [[ $(est "$sp") == feita ]] || fail "deveria concluir"
run --tarefa-desfazer "$sp" >/dev/null || fail "desfazer de feita deveria reabrir"
[[ $(est "$sp") == aberta ]] || fail "desfazer deveria reabrir a tarefa feita"
echo "ok: sem ciclo, desfazer reabre a tarefa feita"

# 6) painel: a linha mostra ✓ ciclo feito por 24 h; o menu oferece ↶ Desfazer; ^z desfaz e avisa
printf 'filtro=todas\nmodo=lista\n' >"$UI"
run --tarefa-ok "$nf" || fail "concluir para o painel falhou"
grep "NFe" <<<"$(run --tarefas-lista | sem_cor)" | grep -q '✓ ciclo feito' || fail "a linha deveria mostrar ✓ ciclo feito: $(run --tarefas-lista | sem_cor | grep NFe)"
m=$(meta "$nf"); set_meta "$nf" "$(sed "s/feito=[0-9]*/feito=$(( $(date +%s) - 90000 ))/" <<<"$m")"
grep "NFe" <<<"$(run --tarefas-lista | sem_cor)" | grep -q '✓ ciclo feito' && fail "depois de 24 h a marca some"
menu=$(printf 'filtro=todas\nmodo=menu:%s\n' "$nf" >"$UI"; run --tarefas-lista | sem_cor)
grep -q "^act:desfazer:$nf	.*↶ Desfazer a última conclusão.*prazo volta" <<<"$menu" || fail "o menu deveria oferecer ↶ Desfazer com a dica do prazo: $menu"
menu=$(printf 'filtro=todas\nmodo=menu:%s\n' "$fx" >"$UI"; run --tarefas-lista | sem_cor)
grep -q "act:desfazer:" <<<"$menu" && fail "sem o que desfazer, o menu não oferece ↶ Desfazer"
printf 'filtro=todas\nmodo=lista\n' >"$UI"
antes=$(mk "$nf" ant); antes=${antes##*,}
cab=$(cab_da_acao desfazer "$nf")
[[ $(mk "$nf" prazo) == "$antes" ]] || fail "^z deveria desfazer o último ciclo: $(meta "$nf")"
grep -q '↶ Ciclo desfeito: o prazo volta para' <<<"$cab" || fail "^z deveria avisar no cabeçalho: $cab"
grep -qF 'ctrl-z:transform' "$TT" || fail "o painel deveria ligar o ^z"
echo "ok: painel mostra o ciclo feito, oferece desfazer no menu e no ^z"

# 7) concluir uma recorrente pelo painel avisa no cabeçalho, com o próximo prazo e o ^z
printf 'filtro=todas\nmodo=lista\n' >"$UI"
cab=$(cab_da_acao feita "$nf")
grep -q '✓ Ciclo feito · próximo: .* · ^z desfaz' <<<"$cab" || fail "concluir a recorrente deveria avisar o ciclo e o ^z: $cab"
echo "ok: concluir a recorrente no painel avisa o próximo prazo e como desfazer"
