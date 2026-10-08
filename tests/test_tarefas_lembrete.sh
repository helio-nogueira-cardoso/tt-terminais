#!/usr/bin/env bash
# Lembrete de prazo pelo vigia: uma notificação por tarefa aberta vencida/hoje, uma vez por dia
# (dedupe por id|AAAAMMDD). Usa um stub de notify-send no PATH para capturar as notificações.
# Isola HOME/XDG; nenhum arquivo real tocado.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[[ -x "$TT" ]] || { echo "FALHOU: tt não executável"; exit 1; }
bash -n "$TT" || { echo "FALHOU: sintaxe"; exit 1; }

for fn in tarefas_lembrete tarefas_notificar tarefas_lembrete_arq; do
  grep -q "^$fn()" "$TT" || { echo "FALHOU: função $fn ausente"; exit 1; }
done
grep -q -- '--tarefas-lembrete) tarefas_lembrete' "$TT" || { echo "FALHOU: verbo --tarefas-lembrete ausente"; exit 1; }
grep -q -- '--tarefas-lembrete >/dev/null' "$TT" || { echo "FALHOU: vigia não dispara o lembrete"; exit 1; }

mkdir -p "$T/home/.config/tt" "$T/bin" "$T/rt" "$T/state"
printf 'nome=A\n' >"$T/home/.config/tt/config"
printf '#!/usr/bin/env bash\ncase ${1:-} in list-sessions) exit 1;; display-message) echo cx;; *) exit 0;; esac\n' >"$T/bin/tmux"
chmod +x "$T/bin/tmux"
printf '#!/usr/bin/env bash\necho "NOTIF: $*" >> "%s/notifs.log"\n' "$T" >"$T/bin/notify-send"
chmod +x "$T/bin/notify-send"
C="$T/home/.config/tt/tarefas"
AVISADOS="$T/state/tt/tt-tarefas-avisadas"
run(){ env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/state" \
  TT_RT="$T/rt" TT_MACHINE=A PATH="$T/bin:$PATH" "$TT" "$@"; }
fail(){ echo "FALHOU: $1" >&2; exit 1; }
notifs(){ wc -l < "$T/notifs.log" 2>/dev/null | tr -d ' '; }
hoje=$(date +%s); ontem=$((hoje - 86400)); amanha=$((hoje + 86400))

cria(){ run --tarefa-add "$1" >/dev/null; local id; id=$(awk -F'\t' -v t="$1" '$5==t{print $1}' "$C")
  awk -F'\t' -v OFS='\t' -v id="$id" -v m="prazo=$2" 'NF>=5{if($1==id){$6=m} print}' "$C" >"$C.n" && mv "$C.n" "$C"; }
cria "Vencida" "$ontem"
cria "De hoje" "$hoje"
cria "Futura"  "$amanha"
run --tarefa-add "Sem prazo" >/dev/null

# 1) primeira varredura: notifica a vencida e a de hoje (2), não a futura nem a sem prazo
run --tarefas-lembrete
[[ $(notifs) == 2 ]] || fail "deveria notificar 2 (vencida + hoje), notificou $(notifs): $(cat "$T/notifs.log" 2>/dev/null)"
grep -q 'Vencida' "$T/notifs.log" || fail "não notificou a tarefa vencida"
grep -q 'De hoje' "$T/notifs.log" || fail "não notificou a tarefa de hoje"
grep -q 'Futura' "$T/notifs.log" && fail "não deveria notificar tarefa futura"
echo "ok: notifica só as abertas vencidas ou de hoje"

# 2) segunda varredura no mesmo dia: não repete (dedupe)
run --tarefas-lembrete
[[ $(notifs) == 2 ]] || fail "dedupe falhou: repetiu a notificação ($(notifs) no total)"
echo "ok: não repete a notificação no mesmo dia (dedupe por id|dia)"

# 3) TT_TAREFAS_LEMBRETE=0 desliga
: > "$T/notifs.log"; rm -f "$AVISADOS"
env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/state" \
  TT_RT="$T/rt" TT_MACHINE=A PATH="$T/bin:$PATH" TT_TAREFAS_LEMBRETE=0 "$TT" --tarefas-lembrete
[[ -z $(notifs) || $(notifs) == 0 ]] || fail "TT_TAREFAS_LEMBRETE=0 não desligou (notificou $(notifs))"
echo "ok: TT_TAREFAS_LEMBRETE=0 desliga o lembrete"

# 4) concluir a tarefa some do lembrete (não notifica mais)
: > "$T/notifs.log"; rm -f "$AVISADOS"
idv=$(awk -F'\t' '$5=="Vencida"{print $1}' "$C"); run --tarefa-ok "$idv"
run --tarefas-lembrete
grep -q 'Vencida' "$T/notifs.log" && fail "tarefa concluída não deveria notificar"
echo "ok: tarefa concluída sai do lembrete"
