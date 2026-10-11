#!/usr/bin/env bash
# Termux: o ssh não interativo não lê o profile.d, então o comando remoto precisa achar sozinho o
# TMUX_TMPDIR ($PREFIX/var/run) onde mora o servidor tmux; fora do Termux nada muda.
source "$(dirname "$0")/lib.sh"; isolar
eval "$(sed -n '/^PATH_REMOTO=/p; /^TT_REMOTO=/p' "$TT")"
mkdir -p "$HOME/pfx/var/run" "$HOME/.local/bin"
printf '#!/bin/sh\necho "TMUX_TMPDIR=[$TMUX_TMPDIR]"\n' >"$HOME/.local/bin/tmux"
cp "$HOME/.local/bin/tmux" "$HOME/.local/bin/tt"; chmod +x "$HOME/.local/bin/tmux" "$HOME/.local/bin/tt"
ssh_sem() { env -i HOME="$HOME" PATH=/usr/bin:/bin "$@" sh -c "$CMD"; }

CMD="$PATH_REMOTO tmux"; r=$(env -i HOME="$HOME" PATH=/usr/bin:/bin PREFIX="$HOME/pfx" sh -c "$CMD")
[[ $r == "TMUX_TMPDIR=[$HOME/pfx/var/run]" ]] || falhou "PATH_REMOTO no Termux: $r"
CMD="$TT_REMOTO"; r=$(env -i HOME="$HOME" PATH=/usr/bin:/bin PREFIX="$HOME/pfx" sh -c "$CMD")
[[ $r == "TMUX_TMPDIR=[$HOME/pfx/var/run]" ]] || falhou "TT_REMOTO no Termux: $r"
passou 'Termux: comando remoto aponta o tmux para $PREFIX/var/run'

CMD="$PATH_REMOTO tmux"; r=$(env -i HOME="$HOME" PATH=/usr/bin:/bin sh -c "$CMD")
[[ $r == "TMUX_TMPDIR=[]" ]] || falhou "fora do Termux: $r"
r=$(env -i HOME="$HOME" PATH=/usr/bin:/bin PREFIX="$HOME/pfx" TMUX_TMPDIR=/x sh -c "$PATH_REMOTO tmux")
[[ $r == "TMUX_TMPDIR=[/x]" ]] || falhou "TMUX_TMPDIR já definido foi trocado: $r"
passou 'fora do Termux (ou com TMUX_TMPDIR definido) nada muda'
