#!/usr/bin/env bash
# tt --notificar-daqui: não avisa quando um cliente com foco mostra a janela do agente ("vendo");
# avisa quando o foco está em outra sessão, em outra janela ou em lugar nenhum; --sempre avisa
# assim mesmo; o aviso leva a ação sessao:<sessão>|<painel> e o clique troca o cliente para lá.
# tmux simulado; isola HOME/XDG.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/.config/tt" "$T/bin" "$T/rt" "$T/state"
printf 'nome=A\ntarefas_sync=off\nfaixa_notif=1\n' >"$T/home/.config/tt/config"
cat >"$T/bin/tmux" <<'E'
#!/usr/bin/env bash
echo "$*" >>"$TMUX_LOG"
case "$1" in
  display-message)
    case "$*" in
      *'#{session_name}'*) echo agente ;;
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
