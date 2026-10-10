#!/usr/bin/env bash
# Diagnóstico de lentidão: com ~/.config/tt/trace presente, os comandos de clique e troca gravam cada
# linha executada em ~/.cache/tt-trace.log; sem o arquivo nada é gravado.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$HOME/.cache" "$XDG_CONFIG_HOME/tt"
"$TT" --clique nada >/dev/null 2>&1
[[ ! -e $HOME/.cache/tt-trace.log ]] || falhou "gravou o trace sem o arquivo ~/.config/tt/trace"
passou "sem o arquivo trace, nada é gravado"
touch "$XDG_CONFIG_HOME/tt/trace"
"$TT" --clique nada >/dev/null 2>&1
grep -q '^=== .* --clique nada' "$HOME/.cache/tt-trace.log" 2>/dev/null || falhou "trace ligado não gravou o cabeçalho do comando"
grep -q '^+ [0-9.]* main:[0-9]*:' "$HOME/.cache/tt-trace.log" || falhou "trace ligado não gravou as linhas executadas"
passou "com o arquivo trace, o clique grava cada linha executada com a hora"
