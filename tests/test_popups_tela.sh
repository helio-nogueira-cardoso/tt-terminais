#!/usr/bin/env bash
# Popups de tamanho fixo cabem na tela do cliente (dim_popup). O tmux recusa popup maior que a tela
# ("width too large") e, no celular com 63 colunas, tocar no +N das fixadas, no 🔔 e em vários itens de
# menu não fazia nada. Parte 1, tmux falso: o tamanho pedido encolhe até a tela e não passa do original
# numa tela grande, inclusive nos itens de menu montados de antemão. Parte 2, tmux isolado de verdade
# com um cliente de 63 colunas: o +N (fixadas) e o 🔔 (notificações) abrem o popup.
source "$(dirname "$0")/lib.sh"; isolar

# --- parte 1: tmux falso, registra o display-popup -------------------------
mkdir -p "$T/falso"
cat >"$T/falso/tmux" <<'TMUX'
#!/usr/bin/env bash
case ${1:-} in
  # só o tamanho responde; o resto (ex.: #{window_modal_pane}, "já há uma janela aberta") vem vazio
  list-clients) [[ $* == *client_width* ]] && printf 'cel\t%s\n' "${TT_TESTE_TELA:-63 30}" || printf 'cel\t\n' ;;
  display-popup) printf '%s\n' "$*" >>"$TT_TMUX_LOG" ;;
  display-message) [[ $* == *client_name* ]] && echo cel ;;
  *) exit 0 ;;
esac
TMUX
chmod +x "$T/falso/tmux"
falso() { local tela=$1; shift; : >"$T/popup.log"; rm -f "$TT_RT"/tt-menu-itens.*
  env PATH="$T/falso:$PATH" TT_TESTE_TELA="$tela" TT_TMUX_LOG="$T/popup.log" "$TT" "$@" >/dev/null 2>&1 || true; }
pediu() { grep -q -- "$1" "$T/popup.log" || falhou "$2: pediu '$(cat "$T/popup.log")'"; }

falso "63 30" --fixadas-popup cel; pediu '-w 63 -h 18' "+N das fixadas em 63 colunas deveria pedir 63x18"
falso "200 50" --fixadas-popup cel; pediu '-w 64 -h 18' "+N das fixadas em tela grande deveria manter 64x18"
falso "63 30" --notifs cel; pediu '-w 63 -h 26' "🔔 em 63 colunas deveria pedir 63x26"
falso "63 12" --notifs cel; pediu '-w 63 -h 12' "🔔 em tela baixa deveria encolher a altura"
falso "200 50" --notifs cel; pediu '-w 92 -h 26' "🔔 em tela grande deveria manter 92x26"
# A conversa do mesh ocupa a altura inteira, mas sua largura nominal de 46 colunas precisa caber.
falso "40 20" --conversa-mesh-alternar cel; pediu '-w 40 -h 100%' "conversa do mesh em 40 colunas deveria encolher a largura"
falso "200 50" --conversa-mesh-alternar cel; pediu '-w 46 -h 100%' "conversa do mesh deveria manter 46 colunas em tela larga"
# Itens de menu montados de antemão (botão direito no 📋 e em "sessão ▾"): o popup do item já cabe.
falso "63 30" --clique-direito tarefas cel %1 0
grep -h 'nova tarefa' "$TT_RT"/tt-menu-itens.* 2>/dev/null | grep -q -- '-w 63 -h 14' || falhou "item + Nova tarefa do 📋 não cabe em 63 colunas"
falso "63 30" --clique-direito sessao cel %1 0
grep -h 'renomear' "$TT_RT"/tt-menu-itens.* 2>/dev/null | grep -q -- '-w 63 -h 7' || falhou "item Renomear da sessão não cabe em 63 colunas"
# Nenhum popup do tt com tamanho fixo literal (todos passam por dim_popup, tam_popup ou conta própria).
fixos=$(grep -n 'display-popup' "$TT" | grep -E -- '-[wh] "?[0-9]+"?( |$)' || true)
[[ -z $fixos ]] || falhou "popup com tamanho fixo (use dim_popup): $fixos"
passou "tamanho fixo encolhe até a tela (63 colunas) e não muda em tela grande, inclusive nos menus"

# --- parte 2: tmux isolado de verdade, cliente de 63 colunas ----------------
instalar_isolado
tmux -f "$HOME/.tmux.conf" new -d -s s -x 63 -y 30 'sleep 600'
anexar cel 63 30 s
c=""; for _ in $(seq 40); do c=$(tmux list-clients -F '#{client_name}' 2>/dev/null | head -1); [[ -n $c ]] && break; sleep 0.25; done
[[ -n $c ]] || falhou "o cliente de teste não anexou"
[[ $(tmux display -p -c "$c" '#{client_width}') == 63 ]] || falhou "o cliente de teste deveria ter 63 colunas"
sleep 2   # o cliente recém-anexado ainda não aceita popup (como nos outros testes com anexar)
"$TT" --fixar s >/dev/null 2>&1 || true   # com uma fixada, o popup fica aberto esperando a escolha
aberto() { local i; for ((i = 0; i < 24; i++)); do pgrep -f -- "$T/.*$1" >/dev/null && return 0; sleep 0.25; done; return 1; }

"$TT" --fixadas-popup "$c" &   # display-popup só volta quando o popup fecha
aberto '--fixadas-ui' || falhou "o +N das fixadas não abriu o popup num cliente de 63 colunas"
tmux display-popup -C -c "$c" 2>/dev/null || true; pkill -f -- "$T/.*--fixadas-ui" 2>/dev/null || true; sleep 0.3
"$TT" --notificar "aviso de teste" 600 >/dev/null
"$TT" --notifs "$c" &
aberto '--notifs-ui' || falhou "o 🔔 não abriu o histórico num cliente de 63 colunas"
tmux display-popup -C -c "$c" 2>/dev/null || true; pkill -f -- "$T/.*--notifs-ui" 2>/dev/null || true; wait
passou "cliente de 63 colunas: +N das fixadas e 🔔 abrem o popup"

echo "TODOS OS TESTES PASSARAM"
