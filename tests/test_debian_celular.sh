#!/usr/bin/env bash
# Debian do celular (jube42): o PATH do tt entra no ~/.profile (o bash -lc não lê o ~/.bashrc) e o nome vem do Termux.
source "$(dirname "$0")/lib.sh"; isolar
export TT_SO_CARREGAR=1
mkdir -p "$T/th/.config/tt"; printf 'nome=s24\n' >"$T/th/.config/tt/config"
nome=$(TT_TERMUX_HOME="$T/th" bash -c 'source "$1"; termux_nome' _ "$TT")
[[ $nome == s24 ]] || falhou "o nome do Termux deveria ser lido, veio: '$nome'"
passou 'nome do Debian: lido da configuração do tt do Termux'

bash -c 'source "$1"; garantir_path_login; garantir_path_login' _ "$TT"
n=$(grep -c 'tt: PATH de login' "$HOME/.profile" 2>/dev/null)
[[ $n == 1 ]] || falhou "o PATH de login deveria entrar uma vez no ~/.profile, entrou $n"
grep -q 'export PATH="\$HOME/.local/bin' "$HOME/.profile" || falhou 'o ~/.profile deveria exportar o ~/.local/bin'
passou 'PATH de login no ~/.profile, sem duplicar'
