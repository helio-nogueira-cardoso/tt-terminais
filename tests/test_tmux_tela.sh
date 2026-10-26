#!/usr/bin/env bash
# Servidor da tela (jube42): o helper tmux_tela escolhe o tmux do Termux quando o tt roda no proot; conf_em_dia recarrega
# só quando @tt_conf_versao diverge do VERSAO e grava a versão nova. tmux é falso (registra as chamadas).
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/px/bin" "$T/bin" "$T/dados"
: >"$T/px/bin/sshd"; chmod +x "$T/px/bin/sshd"
cat >"$T/fake-tela" <<'SH'
#!/bin/sh
echo "TMPDIR=$TMUX_TMPDIR ARGS=$*" >>"$FAKE_LOG"
case "$*" in
  "show -gqv @tt_conf_versao") cat "$FAKE_VERSAO" 2>/dev/null ;;
  "list-sessions") echo "janela-1" ;;
esac
exit 0
SH
chmod +x "$T/fake-tela"
printf '516 2cc4281 2026-10-24 2.11.21\n' >"$T/dados/VERSAO"
export FAKE_LOG="$T/log" FAKE_VERSAO="$T/versao-tela"
export TT_TMUX_TELA_PREFIX="$T/px" TT_TMUX_TELA_BIN="$T/fake-tela" PREFIX=/usr/local
run() { TT_SO_CARREGAR=1 bash -c 'source "$1"; redesenhar_todos(){ :; }; DIR_TT=$2; conf_em_dia' _ "$TT" "$T/dados"; }

# 1) versão antiga na tela: recarrega e grava a nova
printf '515 aaaaaaa\n' >"$FAKE_VERSAO"; : >"$FAKE_LOG"
run
grep -q 'ARGS=source-file' "$FAKE_LOG" || falhou 'com versão antiga a tela deveria recarregar (source-file)'
grep -q 'ARGS=set -gq @tt_conf_versao 516 2cc4281' "$FAKE_LOG" || falhou 'a versão nova deveria ser gravada na tela'
grep -q 'TMPDIR='"$T"'/px/var/run' "$FAKE_LOG" || falhou 'a tela deveria usar o TMUX_TMPDIR do Termux'
passou 'versão antiga na tela: recarrega, grava a nova e usa o servidor do Termux'

# 2) mesma versão: nada de source-file (a recarga repetida faz a tela inteira redesenhar)
printf '516 2cc4281\n' >"$FAKE_VERSAO"; : >"$FAKE_LOG"
run
grep -q 'ARGS=source-file' "$FAKE_LOG" && falhou 'com a mesma versão não pode haver source-file'
passou 'mesma versão: nenhuma recarga'
