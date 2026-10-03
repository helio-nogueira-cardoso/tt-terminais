#!/usr/bin/env bash
# Paleta Dracula para o terminal que abriu o shell.
# OSC 4/10/11 é entendido por Windows Terminal, VTE/GNOME Terminal e Termux.
# Em emuladores que não o suportam, as sequências são simplesmente ignoradas.

[[ -t 1 && ${TERM:-} != dumb && -z ${TMUX:-} ]] || exit 0

osc() { printf '\033]%s\007' "$1"; }

# ANSI normal (0–7) e brilhante (8–15). Fundo escuro e branco brilhante têm
# contraste suficiente para highlights e texto em negrito.
cores=(
  '#21222c' '#ff5555' '#50fa7b' '#f1fa8c'
  '#bd93f9' '#ff79c6' '#8be9fd' '#f8f8f2'
  '#6272a4' '#ff6e6e' '#69ff94' '#ffffa5'
  '#d6acff' '#ff92df' '#a4ffff' '#ffffff'
)
for i in "${!cores[@]}"; do osc "4;$i;${cores[$i]}"; done

osc '10;#f8f8f2'
osc '11;#282a36'
osc '12;#f8f8f2'
