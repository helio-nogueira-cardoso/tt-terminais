#!/usr/bin/env bash
# Fora do tmux (jube42), o tt escolhe o binário do próprio tt (tmux 3.8), não o do PATH (3.6b). Isola HOME; tmux é falso.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$HOME/.local/share/tt-tmux/bin" "$T/pathbin"
printf '#!/bin/sh\necho 3.8\n' >"$HOME/.local/share/tt-tmux/bin/tmux"; chmod +x "$HOME/.local/share/tt-tmux/bin/tmux"
printf '#!/bin/sh\necho 3.6b\n' >"$T/pathbin/tmux"; chmod +x "$T/pathbin/tmux"
export PATH="$T/pathbin:$PATH"
escolhido=$(env -u TMUX TT_SO_CARREGAR=1 bash -c 'source "$1"; echo "$TT_TMUX_BIN"' _ "$TT")
[[ $escolhido == "$HOME/.local/share/tt-tmux/bin/tmux" ]] || falhou "fora do tmux deveria usar o binário do tt, veio: $escolhido"
passou 'fora do tmux: o binário do tt vence o do PATH'
