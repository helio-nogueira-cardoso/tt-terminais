#!/usr/bin/env bash
# Simulações não dependem do sleep do host nem alcançam o clipboard real.
source "$(dirname "$0")/lib.sh"; isolar
echo copia_entre_maquinas=0 >>"$XDG_CONFIG_HOME/tt/config"
runtime=$(TT_RT="$T/runtime-novo" bash -c 'TT_SO_CARREGAR=1 source "$1"; printf "%s" "$RT"' _ "$TT")
[[ $runtime == "$T/runtime-novo" && -d $runtime ]] || falhou 'runtime explícito caiu no temporário compartilhado'
touch "$T/runtime-invalido"
TT_RT="$T/runtime-invalido" "$TT" --versao >"$T/runtime.out" 2>&1 && falhou 'runtime inválido foi aceito'
passou 'runtime explícito é criado e caminho inválido falha sem usar o runtime real'
printf 'ação 🐈' | "$TT" --copiar
[[ $(cat "$T/clipboard.txt") == 'ação 🐈' ]] || falhou 'receptor isolado perdeu UTF-8/UTF-16'
mkdir -p "$T/bin"
printf '#!/bin/sh\ncat >"%s/clip-falso"\n' "$T" >"$T/bin/wl-copy"; chmod +x "$T/bin/wl-copy"
printf 'outra ação' | PATH="$T/bin:$PATH" "$TT" --copiar
[[ $(cat "$T/clip-falso") == 'outra ação' ]] || falhou 'não encaminhou ao backend falso'
passou 'clipboard fica no ambiente isolado e encaminha UTF-8 ao substituto do teste'
mkdir "$T/restrito"
printf 'não encaminhar' | iconv -f utf-8 -t utf-16le | PATH="$T/bin:$PATH" python3 -I "$RAIZ/tests/clipboard-isolado.py" "$T/restrito"
[[ $(cat "$T/clip-falso") == 'outra ação' && $(cat "$T/restrito/clipboard.txt") == 'não encaminhar' ]] || falhou 'alcançou backend fora da pasta permitida'
passou 'backend fora da pasta permitida não é executado'

tmux new -d -s falso "$(exec_como claude sleep 60)"
for _ in {1..50}; do [[ $(tmux display -p -t falso '#{pane_current_command}') == claude ]] && break; sleep 0.1; done
[[ $(tmux display -p -t falso '#{pane_current_command}') == claude ]] || falhou 'processo simulado depende do applet sleep'
passou 'processo ocioso tem o nome solicitado no tmux'
