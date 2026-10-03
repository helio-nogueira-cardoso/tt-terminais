#!/usr/bin/env bash
# Paleta Catppuccin Mocha para o terminal que abriu o shell.
# OSC 4/10/11 é entendido por Windows Terminal, VTE/GNOME Terminal e Termux.
# Em emuladores que não o suportam, as sequências são simplesmente ignoradas.

[[ -t 1 && ${TERM:-} != dumb && -z ${TMUX:-} ]] || exit 0

osc() { printf '\033]%s\007' "$1"; }

# ANSI normal (0–7) e brilhante (8–15). O cinza destacado evita o branco
# ofuscante dos realces de agentes e preserva contraste em telas escuras.
cores=(
  '#45475a' '#f38ba8' '#a6e3a1' '#f9e2af'
  '#89b4fa' '#f5c2e7' '#94e2d5' '#bac2de'
  '#585b70' '#eba0ac' '#a6e3a1' '#f9e2af'
  '#89b4fa' '#f5c2e7' '#94e2d5' '#cdd6f4'
)
for i in "${!cores[@]}"; do osc "4;$i;${cores[$i]}"; done

osc '10;#cdd6f4'
osc '11;#1e1e2e'
osc '12;#89b4fa'
