#!/usr/bin/env bash
# Plugin da conversa do mesh: o atalho NÃO existe por padrão; só com o plugin ativado com o tt-mesh desta pessoa.
source "$(dirname "$0")/lib.sh"; isolar
grep -q '^bind M display-popup' "$RAIZ/tmux.conf" && falhou 'o atalho não pode vir ligado direto no tmux.conf'
grep -q 'if-shell "test -f ~/.config/tt/conversa-mesh.on"' "$RAIZ/tmux.conf" || falhou 'o atalho deve depender do marcador de ativação'
mesh="$T/meu-mesh"; mkdir -p "$mesh/channel"
"$TT" --conversa-mesh-ativar "$mesh" >/dev/null || falhou 'ativar deveria funcionar com um tt-mesh'
[[ $(cat "$HOME/.config/tt/conversa-mesh.on") == "$mesh" ]] || falhou 'o caminho do tt-mesh deveria ficar guardado'
"$TT" --conversa-mesh-desativar >/dev/null
[[ -e $HOME/.config/tt/conversa-mesh.on ]] && falhou 'desativar deveria remover o marcador'
"$TT" --conversa-mesh-ativar "$T/nao-existe" >/dev/null 2>&1 && falhou 'ativar com caminho que não é tt-mesh deveria recusar'
passou 'plugin da conversa: fica desligado por padrão, liga com o tt-mesh desta pessoa e desliga'

# Controle da conversa: o botão 💬 na primeira faixa só com o plugin ligado; o clique alterna o painel.
grep -q 'range=user|conversa' "$RAIZ/tt" || falhou 'a primeira faixa deve ter o botão da conversa'
grep -q 'conversa) conversa_mesh_alternar' "$RAIZ/tt" || falhou 'o clique no botão deve alternar a conversa'
grep -q 'conversa-mesh-alternar' "$RAIZ/tmux.conf" || falhou 'prefix+M deve usar o mesmo alternador'
printf '' | python3 -I "$RAIZ/conversa-mesh.py" --painel >/dev/null || falhou 'o painel sem terminal deve sair na hora'
passou 'controle da conversa: botão na faixa, clique alterna, prefix+M usa o mesmo alternador'
