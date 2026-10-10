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
_tmux_isolado_fim() { tmux kill-server 2>/dev/null || true; rm -rf "$TMUX_TMPDIR"; }
eval "_tmux_isolado_ant=$(trap -p EXIT | sed 's/^trap -- //; s/ EXIT$//')"
trap "set +e; ${_tmux_isolado_ant:+$_tmux_isolado_ant;} _tmux_isolado_fim" EXIT
