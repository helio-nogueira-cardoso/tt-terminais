#!/usr/bin/env bash
# tt --notificar-daqui: não avisa quando um cliente com foco mostra a janela do agente ("vendo");
# avisa quando o foco está em outra sessão, em outra janela ou em lugar nenhum; --sempre avisa
# assim mesmo; o aviso leva a ação sessao:<sessão>|<painel> e o clique troca o cliente para lá.
# tmux simulado; isola HOME/XDG.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
source "$(dirname "$0")/tmux-isolado.sh"
mkdir -p "$T/home/.config/tt" "$T/bin" "$T/rt" "$T/state"
printf 'nome=A\ntarefas_sync=off\nfaixa_notif=1\n' >"$T/home/.config/tt/config"
cat >"$T/bin/tmux" <<'E'
#!/usr/bin/env bash
echo "$*" >>"$TMUX_LOG"
case "$1" in
  display-message)
    case "$*" in
      *'#{session_name}'*) [[ "$*" == *' -t %4 '* ]] && exit 1; echo agente ;;  # %4: painel que já não existe
      *'#{window_id}'*) echo @7 ;;
      *'#{client_pid}'*) echo 1 ;;
    esac ;;
  list-clients) [[ -s $TMUX_CLIENTES ]] && cat "$TMUX_CLIENTES" ;;
  has-session) [[ "$*" == *'=agente'* ]] ;;
  list-sessions|list-panes|show-options) exit 0 ;;
  *) exit 0 ;;
esac
E
chmod +x "$T/bin/tmux"
run(){ env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/state" TT_RT="$T/rt" \
  TT_MACHINE=A LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH="$T/bin:$PATH" TMUX_LOG="$T/log" \
  TMUX_CLIENTES="$T/clientes" TMUX_PANE=%3 TMUX="$T/sock,1,0" "$TT" "$@"; }
fail(){ echo "FALHOU: $1" >&2; exit 1; }
notifs(){ cat "$T"/state/tt/notifs/* 2>/dev/null || true; }
clientes(){ printf '%s\n' "$@" | cut -d'|' -f2- | tr '|' '\t' >"$T/clientes"; }  # sem o nome do cliente: mesmo formato que o tt pede

# 1) cliente com foco na mesma sessão e janela: não avisa
clientes '/dev/pts/1|agente|attached,focused,UTF-8|@7'
[[ $(run --notificar-daqui "acabou") == vendo ]] || fail "deveria dizer vendo"
[[ -z $(notifs) ]] || fail "não deveria gravar aviso quando o usuário está vendo"
echo "ok: usuário olhando para a janela, nada é enviado"

# 2) foco em outra sessão, mesma sessão em outra janela, ou sem foco: avisa
for c in '/dev/pts/1|outra|attached,focused,UTF-8|@9' '/dev/pts/1|agente|attached,focused,UTF-8|@8' '/dev/pts/1|agente|attached,UTF-8|@7'; do
  rm -rf "$T/state/tt/notifs"; clientes "$c"
  [[ $(run --notificar-daqui "acabou") == notificado ]] || fail "deveria notificar com cliente $c"
  notifs | grep -q $'🤖 agente · acabou\tsessao:agente|%3' || fail "aviso com texto e ação: $(notifs)"
done
echo "ok: foco em outro lugar gera aviso com a ação de voltar à sessão"

# 3) --sempre avisa mesmo com o usuário olhando; sem texto é erro
rm -rf "$T/state/tt/notifs"; clientes '/dev/pts/1|agente|attached,focused,UTF-8|@7'
[[ $(run --notificar-daqui "aprovar push" --sempre) == notificado ]] || fail "--sempre"
if run --notificar-daqui 2>/dev/null; then fail "sem texto deveria falhar"; fi
echo "ok: --sempre força o aviso; sem texto é erro"

# 4) o clique leva o cliente à sessão e ao painel de origem
: >"$T/log"
run --notif-abrir 'sessao:agente|%3' /dev/pts/1 || true
grep -q 'select-pane -t %3' "$T/log" || fail "deveria focar o painel: $(cat "$T/log")"
grep -q 'switch-client -c /dev/pts/1 -t =agente' "$T/log" || fail "deveria trocar o cliente: $(cat "$T/log")"
: >"$T/log"
run --notif-abrir 'sessao:sumiu|%4' /dev/pts/1 || true
! grep -q 'switch-client' "$T/log" || fail "sessão inexistente não troca"
grep -q 'não existe mais' "$T/log" || fail "sessão inexistente avisa"
echo "ok: clique vai à sessão e ao painel; sessão fechada só avisa"

# 5) aviso de agente vai pelo 🔔, não pelo slot da faixa: grava o canal sino; o miolo da faixa (letreiro-tt.py)
#    não o mostra, mas mostra um aviso comum; o contador do 🔔 o conta
quadro(){ env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/state" python3 -I "$ROOT/letreiro-tt.py" quadro 140; }
rm -rf "$T/state/tt/notifs"; : >"$T/log"; clientes '/dev/pts/1|outra|attached,focused,UTF-8|@9'
run --notificar "aviso comum" 120 >/dev/null
run --notificar-daqui "precisa de você" >/dev/null
f=$(grep -l 'precisa de você' "$T"/state/tt/notifs/*)
[[ $(cut -f4 "$f") == sino ]] || fail "aviso de agente deveria sair com o canal sino: $(cat "$f")"
[[ $(cut -f3 "$f") == 'sessao:agente|%3' ]] || fail "a ação de voltar à sessão deveria continuar no 3º campo: $(cat "$f")"
q=$(quadro)
grep -q 'aviso comum' <<<"$q" || fail "aviso comum deveria aparecer no slot (controle do teste): $q"
[[ $q != *'precisa de você'* ]] || fail "aviso de agente não deve piscar no slot da faixa: $q"
grep -q 'set -g @barra_notifs_n #\[fg=#f9e2af,bold\]2#\[nobold\]' "$T/log" || fail "contador do 🔔 deveria somar o comum e o do agente (2): $(grep barra_notifs_n "$T/log" | tail -2)"
echo "ok: aviso de agente só no 🔔 (nada no slot); aviso comum segue piscando"

# 6) o contador do 🔔 guarda o aviso do agente (de qualquer idade) até ele ser aberto; expirado não conta
rm -rf "$T/state/tt/notifs"; mkdir -p "$T/state/tt/notifs"
agora=$(date +%s)
printf '%s\t%s\t%s\t%s\n' "$((agora + 600))" "🤖 velho · ainda não lido" 'sessao:agente|%3' sino >"$T/state/tt/notifs/$((agora - 3600))000000000"
printf '%s\t%s\t%s\t%s\n' "$((agora - 5))" "🤖 expirado · não conta" 'sessao:agente|%3' sino >"$T/state/tt/notifs/$((agora - 7200))000000000"
env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/state" TT_RT="$T/rt" TT_MACHINE=A LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH="$T/bin:$PATH" TMUX_LOG="$T/log" TMUX_CLIENTES="$T/clientes" "$TT" --notificar-daqui "🤖 sem destino" >/dev/null  # fora do tmux (sem TMUX_PANE): aviso do 🔔 sem destino
mv "$(ls -1d "$T"/state/tt/notifs/* | tail -1)" "$T/state/tt/notifs/$((agora - 1800))000000000"
[[ $(cut -f3 "$T/state/tt/notifs/$((agora - 1800))000000000") == - && $(cut -f4 "$T/state/tt/notifs/$((agora - 1800))000000000") == sino ]] || fail "aviso sem destino deveria levar - na ação e sino no canal: $(cat "$T/state/tt/notifs/$((agora - 1800))000000000")"
: >"$T/log"; run --barras >/dev/null 2>&1 || true
grep -q 'set -g @barra_notifs_n #\[fg=#f9e2af,bold\]2#\[nobold\]' "$T/log" || fail "contador deveria guardar os 2 avisos de agente não lidos e vigentes: $(grep barra_notifs_n "$T/log" | tail -2)"
[[ $(quadro) != *'ainda não lido'* ]] || fail "aviso velho de agente não deve voltar ao slot"
# a central lista com o destino (↗) e sem vazar o canal para a ação
lista=$(run --notifs-ui | sed 's/\x1b\[[0-9;]*m//g')
grep -q 'ainda não lido  ↗' <<<"$lista" || fail "central deveria marcar o destino (↗): $lista"
! grep -q 'sino' <<<"$lista" || fail "o canal não pode vazar para o texto da central: $lista"
grep -q 'sem destino$' <<<"$lista" || fail "aviso sem destino não deve ter ↗ nem o marcador - : $lista"
# abrir o aviso (marca .lida) tira do contador; ^l marca todos
: >"$T/state/tt/notifs/$((agora - 3600))000000000.lida"
: >"$T/log"; run --barras >/dev/null 2>&1 || true
grep -q 'set -g @barra_notifs_n #\[fg=#f9e2af,bold\]1#\[nobold\]' "$T/log" || fail "aviso aberto deveria sair do contador (sobra 1): $(grep barra_notifs_n "$T/log" | tail -2)"
run --notifs-lidas
: >"$T/log"; run --barras >/dev/null 2>&1 || true
! grep -q 'set -g @barra_notifs_n #\[fg=' "$T/log" || fail "--notifs-lidas deveria zerar o contador: $(grep barra_notifs_n "$T/log")"
echo "ok: o 🔔 guarda o aviso do agente até abrir (ou ^l); expirado não conta; a central mostra o destino"

# 7) o clique no slot não abre aviso de agente (ele não está lá): sem aviso comum vigente, abre a central
rm -rf "$T/state/tt/notifs"; : >"$T/log"
run --notificar-daqui "só no sino" >/dev/null
: >"$T/log"; run --clique notifx /dev/pts/1 %3 "$T" 0 >/dev/null 2>&1 || true
! grep -q 'switch-client' "$T/log" || fail "clicar no slot não pode saltar para a sessão de um aviso que nem aparece nele: $(cat "$T/log")"
grep -q 'display-popup.*notificações' "$T/log" || fail "sem aviso comum vigente o clique no slot deveria abrir a central: $(cat "$T/log")"
echo "ok: clique no slot ignora avisos só do 🔔 e abre a central"

# 8) sem a faixa (faixa_notif=0) não há 🔔: o aviso do agente segue o caminho antigo (sem canal) e vai à tela dos clientes
printf 'faixa_notif=0\n' >>"$T/home/.config/tt/config"
rm -rf "$T/state/tt/notifs"; : >"$T/log"; clientes '/dev/pts/1|outra|attached,focused,UTF-8|@9'
printf '/dev/pts/1\n' >"$T/clientes"
run --notificar-daqui "sem faixa" >/dev/null
f=$(ls "$T"/state/tt/notifs/* | head -1)
[[ -z $(cut -sf4 "$f") ]] || fail "sem a faixa não deve haver canal sino: $(cat "$f")"
echo "ok: faixa desligada mantém o caminho antigo"

# 9) regra do Hélio (12/10/2026): o notify-send dos agentes NUNCA é suprimido. Com o 🔔 ligado, o aviso do agente vai
#    ao 🔔 (canal sino) E às notificações do sistema; sem a faixa, também. (O stub fica em $T/bin, na frente do PATH.)
printf '#!/bin/sh\nprintf "%%s|%%s\\n" "$3" "$4" >>"%s/notify.log"\n' "$T" >"$T/bin/notify-send"; chmod +x "$T/bin/notify-send"
sed -i '/^faixa_notif=/d' "$T/home/.config/tt/config"; printf 'faixa_notif=1\n' >>"$T/home/.config/tt/config"
rm -rf "$T/state/tt/notifs"; : >"$T/notify.log"; clientes '/dev/pts/1|outra|attached,focused,UTF-8|@9'
run --notificar-daqui "revisar o PR" >/dev/null
grep -qx '🤖 agente|revisar o PR' "$T/notify.log" || fail "com o 🔔 ligado o agente também tem de ir ao notify-send: $(cat "$T/notify.log")"
[[ $(cut -f4 "$(grep -l 'revisar o PR' "$T"/state/tt/notifs/*)") == sino ]] || fail 'e também ao 🔔 (canal sino)'
sed -i '/^faixa_notif=/d' "$T/home/.config/tt/config"; printf 'faixa_notif=0\n' >>"$T/home/.config/tt/config"
: >"$T/notify.log"; run --notificar-daqui "sem faixa também" >/dev/null
grep -qx '🤖 agente|sem faixa também' "$T/notify.log" || fail "sem a faixa o agente vai ao notify-send: $(cat "$T/notify.log")"
echo "ok: aviso de agente vai ao 🔔 e ao notify-send (nunca suprimido), com ou sem a faixa"
