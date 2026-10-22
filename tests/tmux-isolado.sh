#!/usr/bin/env bash
# Para os testes que não usam o isolar() do lib.sh: o tmux sem -L/-S do teste (e o do tt que ele
# chama) nunca fala com o tmux de quem roda a suíte. Sem isto, o tt de um teste herdava o TMUX e o
# socket padrão e mandava display-message aos clientes de verdade (em 10/10/2026, o "✓ 2 itens de
# A → A:/tmp/…" do test_transferencias.sh cobriu a faixa de notificações do book). Uso: logo depois
# do trap EXIT do teste (ou no começo, se ele não tem um):
#   source "$(dirname "$0")/tmux-isolado.sh"
# A limpeza daqui se soma ao trap que já existe (não o troca): primeiro a do teste (que pode usar o
# tmux -L dele, cujo socket mora nesta pasta), depois esta; sem set -e, para que uma limpeza que
# falhe não troque o código de saída do teste.
unset TMUX TMUX_PANE TT_CLIENTE TT_PANE
TMUX_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/tt-teste-tmux.XXXXXX"); export TMUX_TMPDIR
# O runtime do tt (caches, estado dos painéis, travas) também é do teste: sem isto o tt de um teste caía
# no /run/user/UID de verdade, o de quem roda a suíte, e dois testes em paralelo disputavam os arquivos.
export TT_SEM_VIGIA_AUTO=1 # o tt de um teste não religa o vigia sozinho (test_vigia_garantir.sh esvazia)
export TT_PRECARREGAR=0
[[ -n ${TT_RT:-} ]] || { TT_RT=$TMUX_TMPDIR/rt; mkdir -p "$TT_RT"; export TT_RT; }
# Nem a tela gráfica (área de transferência) de quem roda a suíte: ver sem_tela_real no lib.sh.
mkdir -p "$TMUX_TMPDIR/run" && chmod 700 "$TMUX_TMPDIR/run" && export XDG_RUNTIME_DIR=$TMUX_TMPDIR/run
[[ -n ${WAYLAND_DISPLAY:-} ]] && export WAYLAND_DISPLAY=wayland-tt-teste
[[ -n ${DISPLAY:-} ]] && export DISPLAY=:99999
source "$(dirname "${BASH_SOURCE[0]}")/sem-clipboard-real.sh"; sem_clipboard_real "$TMUX_TMPDIR"
_tmux_isolado_fim() { tmux kill-server 2>/dev/null || true; rm -rf "$TMUX_TMPDIR"; }
eval "_tmux_isolado_ant=$(trap -p EXIT | sed 's/^trap -- //; s/ EXIT$//')"
# O código de saída passa adiante: com "set +e" na frente, o $? que a limpeza anterior lia era o do set (0), e
# o limpar_isolado do lib.sh, que sai com ele, fazia um teste que falhou sair 0 (test_mac_atalhos, 20/10/2026).
trap "_tmux_isolado_st=\$?; set +e; ${_tmux_isolado_ant:+(exit \$_tmux_isolado_st); $_tmux_isolado_ant;} _tmux_isolado_fim; exit \$_tmux_isolado_st" EXIT
# nem notificações do sistema de verdade (notify-send/termux-notification): veja sem-notificacao-real.sh
source "$(dirname "${BASH_SOURCE[0]}")/sem-notificacao-real.sh"; sem_notificacao_real "$TMUX_TMPDIR"
