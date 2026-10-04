#!/usr/bin/env bash
# A central abre na hora mesmo com uma máquina lenta: esta máquina e o cache das outras primeiro,
# a lista fresca depois (sem perder o item selecionado).
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
mkdir -p "$T/bin"
printf '#!/bin/sh\nsleep 3; printf "remota-1\\tfresca\\tbusca\\n"\n' >"$T/bin/ssh"
printf '#!/bin/sh\necho "{\\"Peer\\":{\\"x\\":{\\"DNSName\\":\\"lenta.exemplo.\\",\\"HostName\\":\\"lenta\\",\\"Online\\":true}}}"\n' >"$T/bin/tailscale"
chmod +x "$T/bin/ssh" "$T/bin/tailscale"; export PATH=$T/bin:$PATH
printf 'lenta.exemplo ninguem lenta\n' >"$XDG_CONFIG_HOME/tt/maquinas"
printf 'lenta.exemplo\tremota-1\tdo-cache\tremota-1 lenta\n' >"$TT_RT/tt-lista-$(id -u)-lenta"
tmux -f "$HOME/.tmux.conf" new -d -s local-1 -x 120 -y 35 'bash --norc' 2>/dev/null; anexar v 120 37 local-1; sleep 2
c=$(tmux list-clients -F '#{client_name}' | head -1)
t0=$(date +%s%N); tmux display-popup -c "$c" -E -w 90% -h 80% "PATH=$PATH TT_CLIENTE='$c' $TT" &
rapido=""; fresco=""
while :; do q=$(fora capture-pane -p -t v | grep '│' || true); ms=$(( ($(date +%s%N) - t0) / 1000000 ))
  [[ -z $rapido && $q == *local-1* && $q == *do-cache* ]] && rapido=$ms
  [[ -z $fresco && $q == *fresca* ]] && fresco=$ms
  [[ -n $rapido && -n $fresco ]] && break; ((ms > 8000)) && break; sleep 0.03; done
[[ -n $rapido ]] || falhou 'a central não mostrou esta máquina + cache da lenta'
((rapido < 1500)) || falhou "central demorou ${rapido} ms para abrir com máquina lenta"
[[ -n $fresco ]] || falhou 'a lista fresca nunca substituiu o cache'
passou "central abre em ${rapido} ms com máquina lenta; lista fresca em ${fresco} ms"
fora send -t v Escape; sleep 0.5
[[ -s $TT_RT/tt-lista-$(id -u)-lenta ]] && grep -q fresca "$TT_RT/tt-lista-$(id -u)-lenta" || falhou 'cache não foi atualizado com a lista fresca'
passou 'cache atualizado para a próxima abertura'
