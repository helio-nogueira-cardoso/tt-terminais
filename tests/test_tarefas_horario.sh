#!/usr/bin/env bash
# Prazo com horário (opcional), descrição visível e a agenda: frase natural com hora e multi-linha,
# rótulos "◷ amanhã 14:00" e "venceu" pela hora, aba Agenda agrupada por dia, calendário (modo
# prazo) com hora digitada/dia todo/hora inválida, recorrência que mantém a hora, lembrete na hora
# e a conta de datas do calendário. Isola HOME/XDG e usa stub de tmux; nada real é tocado.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[[ -x "$TT" ]]; bash -n "$TT"

mkdir -p "$T/home/.config/tt" "$T/bin" "$T/rt" "$T/state"
printf 'nome=A\ntarefas_sync=off\n' >"$T/home/.config/tt/config"
printf '#!/usr/bin/env bash\ncase ${1:-} in list-sessions) exit 1;; display-message) echo cx;; *) exit 0;; esac\n' >"$T/bin/tmux"
printf '#!/usr/bin/env bash\necho "NOTIF: $*" >> "%s/notifs.log"\n' "$T" >"$T/bin/notify-send"
chmod +x "$T/bin/tmux" "$T/bin/notify-send"
C="$T/home/.config/tt/tarefas"
UI="$T/rt/tt-tarefas-ui-$(id -u)"
run(){ env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/state" \
  TT_RT="$T/rt" TT_MACHINE=A LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH="$T/bin:$PATH" "$TT" "$@"; }
sem_cor(){ sed 's/\x1b\[[0-9;]*m//g'; }
meta(){ awk -F'\t' -v t="$1" '$5==t{print $6; exit}' "$C"; }
id_de(){ awk -F'\t' -v t="$1" '$5==t{print $1; exit}' "$C"; }
prazo_de(){ sed -n 's/.*prazo=\([0-9]*\).*/\1/p' <<<"$(meta "$1")"; }
fail(){ echo "FALHOU: $1" >&2; exit 1; }
amanha=$(date -d tomorrow +%Y-%m-%d)

# 1) frase natural: dia + hora (com e sem "às"), só hora; linhas além da 1ª viram descrição
run --tarefa-add-natural "$(printf 'Reunião @amanha 14h !alta\nlevar o relatório\ne o crachá')"
run --tarefa-add-natural "Dentista @amanha às 9h30"
run --tarefa-add-natural "Ler https://ex.com/a//b"
run --tarefa-add-natural "Almoço @25/12"
[[ $(prazo_de Reunião) == "$(date -d "$amanha 14:00" +%s)" ]] || fail "@amanha 14h deveria dar amanhã 14:00: $(meta Reunião)"
[[ $(meta Reunião) == *hora=1* ]] || fail "prazo com horário sem hora=1: $(meta Reunião)"
[[ $(prazo_de Dentista) == "$(date -d "$amanha 09:30" +%s)" ]] || fail "'@amanha às 9h30' errado: $(meta Dentista)"
[[ -n $(id_de 'Ler https://ex.com/a//b') ]] || fail "URL com // não pode virar descrição"
[[ $(meta Almoço) != *hora=* ]] || fail "prazo sem horário não pode ter hora=1 (horário é opcional)"
d=$(run --tarefa-preview "$(id_de Reunião)")
grep -q 'levar o relatório' <<<"$d" && grep -q 'e o crachá' <<<"$d" || fail "// não virou descrição em linhas: $d"
grep -q 'às 14:00' <<<"$d" || fail "prévia não mostra o horário: $d"
run --tarefa-add-natural "Ligar @23:59"
[[ $(prazo_de Ligar) == "$(date -d "$(date +%Y-%m-%d) 23:59" +%s)" ]] || fail "@23:59 deveria ser hoje 23:59"
echo "ok: @dia + hora, 'às', @hora; linhas além da 1ª viram descrição; horário é opcional"

# 2) lista: rótulo com a hora, ≡ de quem tem descrição (sem poluir a lista), "venceu" pela hora
printf 'filtro=todas\nmodo=lista\n' >"$UI"
l=$(FZF_COLUMNS=72 run --tarefas-lista | sem_cor)
grep -q 'Reunião  ◷ amanhã 14:00' <<<"$l" || fail "rótulo sem a hora: $l"
grep -q 'Reunião  ◷ amanhã 14:00.*≡$' <<<"$l" || fail "tarefa com descrição deveria terminar em ≡: $l"
grep -q 'levar o relatório' <<<"$l" && fail "a descrição não pode aparecer na lista (polui): $l"
grep -q 'Almoço  ◷ .*25/12$' <<<"$l" || fail "prazo sem hora deveria mostrar só o dia: $(grep Almoço <<<"$l")"
run --tarefa-add "Passou" >/dev/null
ip=$(id_de Passou); h0=$(date -d "$(date +%Y-%m-%d) 00:01" +%s)
awk -F'\t' -v OFS='\t' -v id="$ip" -v m="prazo=$h0|hora=1" '$1==id{$6=m} {print}' "$C" >"$C.n" && mv "$C.n" "$C"
grep -q 'Passou  ◷ venceu hoje 00:01' <<<"$(run --tarefas-lista | sem_cor)" || fail "com horário vencido hoje deveria mostrar 'venceu hoje 00:01'"
echo "ok: lista mostra a hora, a descrição e vence pela hora"

# 3) aba Agenda: só abertas com prazo, agrupadas por dia (títulos clicáveis), ordem pela hora
printf 'filtro=prazo\nmodo=lista\n' >"$UI"
ag=$(run --tarefas-lista | sem_cor)
grep -q '^dia:[0-9]*	 Amanhã · ' <<<"$ag" || fail "agenda sem o título do dia de amanhã: $ag"
pd=$(grep -n 'Dentista' <<<"$ag" | cut -d: -f1); pr=$(grep -n 'Reunião' <<<"$ag" | head -1 | cut -d: -f1)
((pd < pr)) || fail "agenda deveria ordenar pela hora (09:30 antes de 14:00)"
grep -q '09:30 Dentista' <<<"$ag" || fail "na agenda a hora vem antes do texto: $ag"
grep -q 'Atrasadas' <<<"$ag" || fail "agenda sem o grupo de atrasadas"
grep -q 'Ler https' <<<"$ag" && fail "tarefa sem prazo não entra na agenda"
cab=$(FZF_COLUMNS=72 run --tarefas-cabecalho | sem_cor)
grep -q 'Agenda 5' <<<"$cab" || fail "aba Agenda deveria contar 5 (abertas com prazo): $(sed -n 1p <<<"$cab")"
grep -q '▦ Calendário' <<<"$cab" || fail "cabeçalho sem o botão ▦ Calendário"
r=$(FZF_QUERY= run --tarefa-acao clique "$(grep -m1 -o '^dia:[0-9]*' <<<"$ag")")
grep -q 'calendario-agenda' <<<"$r" || fail "clique no título do dia não abre a agenda: $r"
echo "ok: aba Agenda agrupa por dia, ordena pela hora e o título do dia abre o calendário"

# 4) calendário (modo prazo, sem tela): ⏎ = dia todo; dígitos = horário; d volta ao dia todo;
#    hora inválida não confirma; x = sem prazo
cal(){ TT_CAL_TECLAS="$1" run --calendario ""; }
[[ $(cal $'\n') == "$(date -d 'today 12:00' +%s)" ]] || fail "calendário: ⏎ deveria dar hoje (dia todo)"
[[ $(cal $'1430\n') == "$(date -d "$(date +%Y-%m-%d) 14:30" +%s) 1" ]] || fail "calendário: 1430 deveria dar hoje 14:30 com horário"
[[ $(cal $'l9h\n') == "$(date -d "$amanha 09:00" +%s) 1" ]] || fail "calendário: l + 9h deveria dar amanhã 09:00"
[[ $(cal $'1430d\n') == "$(date -d 'today 12:00' +%s)" ]] || fail "calendário: d deveria voltar ao dia todo"
[[ -z $(cal $'99\n') ]] || fail "calendário: hora inválida não pode confirmar"
[[ $(cal x) == limpar ]] || fail "calendário: x deveria tirar o prazo"
ia=$(id_de Almoço)
TT_CAL_TECLAS=$'1800\n' run --tarefa-prazo-prompt "$ia" >/dev/null 2>&1
[[ $(meta Almoço) == *hora=1* ]] || fail "prompt de prazo não gravou o horário: $(meta Almoço)"
TT_CAL_TECLAS=$'d\n' run --tarefa-prazo-prompt "$ia" >/dev/null 2>&1
[[ $(meta Almoço) != *hora=* ]] || fail "dia todo no calendário deveria tirar o horário: $(meta Almoço)"
echo "ok: calendário escolhe dia, horário opcional (digitado), dia todo e sem prazo"

# 5) datas do calendário (aritmética própria) batem com o date, inclusive a semana ISO
src=$(sed -n '/^_cal_dias() {/,/^}/p; /^_cal_civil() {/,/^}/p' "$TT")
for dt in 1970-01-01 2024-02-29 2026-10-08 2027-01-01 2030-12-31; do
  n=$(( $(date -u -d "$dt" +%s) / 86400 ))
  got=$(bash -c "$src"'; _cal_dias '"${dt:0:4} $((10#${dt:5:2})) $((10#${dt:8:2}))"'; echo $R; _cal_civil '"$n"'; printf "%04d-%02d-%02d" $CY $CM $CD')
  [[ $got == "$n"$'\n'"$dt" ]] || fail "conta de datas errada para $dt: $got"
done
echo "ok: conta de datas do calendário confere com o date"

# 6) recorrência com horário mantém a hora ao avançar
id=$(id_de Reunião); run --tarefa-rep-ciclar "$id" >/dev/null   # diária
run --tarefa-toggle "$id" >/dev/null
[[ $(date -d "@$(prazo_de Reunião)" +%H:%M) == 14:00 ]] || fail "recorrência perdeu o horário: $(meta Reunião)"
[[ $(date -d "@$(prazo_de Reunião)" +%Y-%m-%d) == "$(date -d '2 days' +%Y-%m-%d)" ]] || fail "recorrência diária não avançou um dia"
echo "ok: concluir uma recorrente com horário avança o dia e mantém a hora"

# 7) lembrete: com horário avisa quando faltam 10 min (uma vez); mais longe, ainda não
: >"$C"
agora=$(date +%s)
run --tarefa-add "Logo" >/dev/null; run --tarefa-add "Depois" >/dev/null
awk -F'\t' -v OFS='\t' -v a="prazo=$((agora + 300))|hora=1" -v b="prazo=$((agora + 3600))|hora=1" \
  '$5=="Logo"{$6=a} $5=="Depois"{$6=b} {print}' "$C" >"$C.n" && mv "$C.n" "$C"
run --tarefas-lembrete; run --tarefas-lembrete
grep -c 'Logo' "$T/notifs.log" | grep -qx 1 || fail "lembrete com horário deveria avisar 1 vez: $(cat "$T/notifs.log" 2>/dev/null)"
grep -q 'Às ' "$T/notifs.log" || fail "aviso deveria dizer a hora ('Às HH:MM')"
grep -q 'Depois' "$T/notifs.log" && fail "tarefa daqui a 1 h não deveria avisar ainda"
echo "ok: lembrete avisa 10 min antes do horário, uma vez só"

# 8) descrição pelo editor do tt (EDITOR manda) e removida apagando tudo
run --tarefa-add "Com desc" >/dev/null; idd=$(id_de "Com desc")
printf '#!/bin/sh\nprintf "linha um\\nlinha dois\\n" > "$1"\n' >"$T/bin/ed-escreve"
printf '#!/bin/sh\n: > "$1"\n' >"$T/bin/ed-apaga"; chmod +x "$T/bin/ed-escreve" "$T/bin/ed-apaga"
EDITOR="$T/bin/ed-escreve" run --tarefa-desc-prompt "$idd" >/dev/null 2>&1
[[ $(run --tarefa-preview "$idd" | tail -2) == $'linha um\nlinha dois' ]] || fail "descrição pelo editor não gravou as duas linhas"
grep -q 'Com desc.*≡' <<<"$(printf 'filtro=todas\nmodo=lista\n' >"$UI"; run --tarefas-lista | sem_cor)" || fail "tarefa com descrição sem o ≡"
EDITOR="$T/bin/ed-apaga" run --tarefa-desc-prompt "$idd" >/dev/null 2>&1
[[ $(meta "Com desc") != *desc=* ]] || fail "apagar tudo deveria tirar a descrição"
echo "ok: descrição pelo editor do tt (≡ na lista); vazio remove"
