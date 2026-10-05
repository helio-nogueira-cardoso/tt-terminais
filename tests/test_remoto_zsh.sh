#!/usr/bin/env bash
# Máquina remota com zsh (macOS): o comando que o ssh entrega é interpretado pelo zsh, que expande
# "=palavra" e, sem login, não tem o Homebrew nem ~/.local/bin no PATH. Simula esse lado com um zsh
# de verdade (TT_ZSH=/caminho/zsh, ou o do PATH; sem zsh, o teste é pulado).
source "$(dirname "$0")/lib.sh"; isolar
Z=${TT_ZSH:-$(command -v zsh || true)}
[[ -x $Z ]] || { passou 'zsh ausente: teste do lado macOS pulado'; exit 0; }

# Funções e constantes do tt, sem rodar o programa.
eval "$(sed -n '/^q() {/,/^}/p; /^cmd_ver() {/,/^}/p; /^PATH_REMOTO=/p; /^TT_REMOTO=/p' "$TT")"
SSH_OPC=(-o BatchMode=yes); MAQUINA=aqui
# "ssh": o último argumento é o comando remoto, rodado por um zsh com o PATH mínimo do sshd do macOS.
ssh() { local c=${*: -1}; env -i HOME="$HOME" PATH=/usr/bin:/bin "$Z" -c "$c"; }

mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\nfor a in "$@"; do printf "[%%s]" "$a"; done; echo; echo "TT_PONTE=$TT_PONTE"\n' >"$HOME/.local/bin/tmux"
printf '#!/bin/sh\nfor a in "$@"; do printf "[%%s]" "$a"; done; echo\n' >"$HOME/.local/bin/tt"
chmod +x "$HOME/.local/bin/tmux" "$HOME/.local/bin/tt"

for s in 'sessao' 'com espaço' "aspas'simples" '=igual' 'a=b'; do
  saida=$(eval "$(cmd_ver eu@mac "$s" ponte-1)" 2>&1) || true
  [[ $saida == "[attach][-t][=$s]"$'\n'"TT_PONTE=aqui|ponte-1" ]] || falhou "ponte para '$s' no zsh: $saida"
done
passou 'zsh remoto: ponte acha o tmux e recebe "=sessão" intacto'

saida=$(ssh eu@mac "$TT_REMOTO $(q --resolver-fixada '=x' 'y z' '~/a' '$HOME')" 2>&1) || true
[[ $saida == '[--resolver-fixada][=x][y z][~/a][$HOME]' ]] || falhou "TT_REMOTO no zsh: $saida"
passou 'zsh remoto: subcomandos do tt chegam com os argumentos intactos'

# Instalação no macOS: bloco no ~/.zshenv (idempotente, preserva o resto, sai na desinstalação).
echo 'export MEU=1' >"$HOME/.zshenv"
TT_ZSHENV=1 "$TT" --instalar-aqui >/dev/null 2>&1 || true
TT_ZSHENV=1 "$TT" --instalar-aqui >/dev/null 2>&1 || true
[[ $(grep -c '>>> tt (PATH' "$HOME/.zshenv") == 1 ]] || falhou 'bloco do ~/.zshenv duplicado ou ausente'
grep -qx 'export MEU=1' "$HOME/.zshenv" || falhou 'instalação apagou o ~/.zshenv do usuário'
p=$(env -i HOME="$HOME" PATH=/usr/bin:/bin "$Z" -c 'echo $PATH')
[[ $p == "$HOME/.local/bin:"* ]] || falhou "zsh não interativo sem ~/.local/bin no PATH: $p"
passou 'macOS: ~/.zshenv ganha o PATH para comandos via ssh, sem duplicar nem apagar nada'
