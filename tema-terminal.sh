#!/usr/bin/env bash
# Paleta Catppuccin Mocha para o terminal que abriu o shell.
# OSC 4/10/11 é entendido por Windows Terminal, VTE/GNOME Terminal e Termux.
# Em emuladores que não o suportam, as sequências são simplesmente ignoradas.
#
# Este arquivo é carregado com `source` pelo ~/.bashrc: NUNCA usar `exit` fora de uma função
# (encerraria o shell que o carregou — no Termux, a sessão tmux fechava em menos de 1 s). Tudo fica
# numa função que some no fim, para não deixar variáveis nem funções no shell do usuário.

_tt_tema_terminal() {
  [[ -t 1 && ${TERM:-} != dumb && -z ${TMUX:-} ]] || return 0

  # ANSI normal (0–7) e brilhante (8–15). O cinza destacado evita o branco
  # ofuscante dos realces de agentes e preserva contraste em telas escuras.
  local -a cores=(
    '#45475a' '#f38ba8' '#a6e3a1' '#f9e2af'
    '#89b4fa' '#f5c2e7' '#94e2d5' '#bac2de'
    '#585b70' '#eba0ac' '#a6e3a1' '#f9e2af'
    '#89b4fa' '#f5c2e7' '#94e2d5' '#cdd6f4'
  )
  local i
  for i in "${!cores[@]}"; do printf '\033]4;%s;%s\007' "$i" "${cores[$i]}"; done
  printf '\033]10;#cdd6f4\007\033]11;#1e1e2e\007\033]12;#89b4fa\007'
}

_tt_tema_terminal
unset -f _tt_tema_terminal
