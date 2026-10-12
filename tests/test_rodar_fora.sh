#!/usr/bin/env bash
# Só o seletor já aberto precisa adiar Carbonyl; um link direto da sessão de e-mail deve abrir
# uma janela filha que fecha e devolve exatamente o foco ao leitor.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$(dirname "$0")/lib.sh"; isolar
source <(grep '^em_popup()' "$ROOT/tt")
source <(sed -n '/^rodar_fora()/,/^}/p' "$ROOT/tt")
TD=$T/rodar; mkdir -p "$TD"
TMUX=sock; TT_LINK_CLIENTE=cliente; export TMUX TT_LINK_CLIENTE
q() { printf '%q' "$1"; }
cliente_externo() { echo cliente; }
tam_popup() { echo '-w 80 -h 20'; }
popup_fixo() { printf 'popup %s\n' "$*" >>"$TD/log"; }
tmux() { printf 'tmux %s\n' "$*" >>"$TD/log"; }
: >"$TD/log"
unset TT_LINK_POPUP
rodar_fora 1 'carbonyl https://example.com'
grep -q '^popup ' "$TD/log" || { echo 'FALHOU: Carbonyl direto não abriu sobre o e-mail' >&2; exit 1; }
! grep -q 'run-shell' "$TD/log" || { echo 'FALHOU: link direto foi confundido com seletor temporário' >&2; exit 1; }
: >"$TD/log"; TT_LINK_POPUP=1
rodar_fora 1 'carbonyl https://example.com'
grep -q 'run-shell -b' "$TD/log" && grep -q 'sleep 0.3; tmux display-popup' "$TD/log" || {
  echo 'FALHOU: Carbonyl do seletor não foi adiado até fechar o seletor' >&2; exit 1;
}
echo 'ok: Carbonyl direto abre como janela filha do e-mail; só o seletor adia a abertura'
