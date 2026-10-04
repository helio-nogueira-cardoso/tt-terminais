#!/usr/bin/env bash
# Ambiente isolado para os testes: HOME, config, tmux e estado do tt numa pasta temporária, e o
# pacote COPIADO para lá (TT_DIR nunca aponta para o repositório: a instalação troca a pasta
# inteira de TT_DIR). Uso: source "$(dirname "$0")/lib.sh"; isolar
set -euo pipefail
RAIZ=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

isolar() {
  T=$(mktemp -d)
  mkdir -p "$T/pkg" "$T/home/.config/tt" "$T/tmux" "$T/rt"
  local f
  for f in tt tmux.conf tema-tmux.conf tema-terminal.sh tema-agentes.sh memoria-agentes.sh \
           atalhos-padrao atalhos-padrao-mobile README.md AI-DLC.md; do
    [[ -e $RAIZ/$f ]] && cp "$RAIZ/$f" "$T/pkg/"
  done
  echo "999 teste 2099-01-01" >"$T/pkg/VERSAO"
  export HOME=$T/home XDG_CONFIG_HOME=$T/home/.config TMUX_TMPDIR=$T/tmux TT_RT=$T/rt TT_DIR=$T/pkg
  export TT_T_ATUALIZACAO=999999 TT_ATALHOS_PADRAO=$T/pkg/atalhos-padrao
  unset TMUX TMUX_PANE TT_CLIENTE TT_PANE PREFIX
  printf 'nome=teste\n' >"$XDG_CONFIG_HOME/tt/config"
  : >"$XDG_CONFIG_HOME/tt/maquinas"
  TT=$T/pkg/tt
  trap limpar_isolado EXIT
}

limpar_isolado() {
  local st=$? s
  set +e
  fora kill-server 2>/dev/null
  for s in "$TMUX_TMPDIR"/tmux-*/*; do [[ -S $s ]] && tmux -S "$s" kill-server 2>/dev/null; done
  pkill -f "$T/pkg/tt" 2>/dev/null; pkill -f "$T/home/.local" 2>/dev/null
  rm -rf "$T"
  exit "$st"
}

# tmux "de fora": um servidor separado onde um cliente de verdade se anexa ao tmux do teste.
fora() { tmux -L "fora-$$" -f /dev/null "$@"; }
anexar() { # nome largura altura sessão
  fora new -d -s "$1" -x "$2" -y "$3" "env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t '$4'"
}

falhou() { echo "FALHOU — $*" >&2; exit 1; }
passou() { echo "ok: $*"; }

# Instala o pacote no HOME isolado (~/.local/share/tt, ~/.local/bin/tt, ~/.tmux.conf), para que
# atalhos e botões do tmux.conf chamem o tt de verdade.
instalar_isolado() {
  TT_DIR=$HOME/.local/share/tt "$T/pkg/tt" --instalar-aqui >/dev/null 2>&1 || falhou 'instalação isolada'
  export TT_DIR=$HOME/.local/share/tt
  TT=$HOME/.local/bin/tt
  export PATH=$HOME/.local/bin:$PATH
}
