#!/usr/bin/env bash
# Instala o tt neste usuário em um passo: dependências, tt, ~/.tmux.conf e abertura automática
# no tmux (bloco no ~/.bashrc). Uso: ./instalar.sh [nome-desta-máquina]
# Só o bashrc: ./tt --configurar-bashrc   (desfazer: ./tt --remover-bashrc)
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

faltam=()
for c in tmux fzf python3 ssh tar; do command -v "$c" >/dev/null || faltam+=("$c"); done
if ((${#faltam[@]})); then
  echo "Faltam: ${faltam[*]}"
  if command -v apt-get >/dev/null; then
    pacotes=(); for c in "${faltam[@]}"; do [[ $c == ssh ]] && pacotes+=(openssh-client) || pacotes+=("$c"); done
    sudo apt-get install -y "${pacotes[@]}"
  else
    echo "Instale-os com o gerenciador de pacotes da sua distribuição e rode de novo."; exit 1
  fi
fi

ver() { "$1" "$2" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1; }
antigo() { [[ $(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1) != "$2" ]]; }
t=$(ver tmux -V); f=$(ver fzf --version)
antigo "${t:-0}" 3.4 && echo "Aviso: tmux $t é mais antigo que o recomendado (3.4); algumas funções podem falhar."
antigo "${f:-0}" 0.60 && echo "Aviso: fzf $f é mais antigo que o recomendado (0.60); a central pode não abrir direito."

./tt --instalar "$@"
