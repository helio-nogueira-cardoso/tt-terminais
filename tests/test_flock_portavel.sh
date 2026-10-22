#!/usr/bin/env bash
# O fallback usado sem flock nativo precisa liberar o mesmo descritor e respeitar -s.
source "$(dirname "$0")/lib.sh"; isolar
sed -n '/^  flock() {$/,/^  }$/p' "$TT" >"$T/flock.sh"
[[ -s $T/flock.sh ]] || falhou 'fallback flock não encontrado'
source "$T/flock.sh"
exec 9>"$T/trava"
flock -n 9 || falhou 'não adquiriu trava exclusiva'
if flock -n "$T/trava" true; then falhou 'outro descritor entrou na trava exclusiva'; fi
flock -u 9 || falhou 'não liberou o descritor'
flock -n "$T/trava" true || falhou 'unlock deixou a trava ocupada'
passou 'fallback: exclusiva bloqueia outro descritor; -u libera a trava'
flock -s 9 || falhou 'não adquiriu trava compartilhada'
flock -n -s "$T/trava" true || falhou 'compartilhada bloqueou outro leitor'
if flock -n -x "$T/trava" true; then falhou 'exclusiva entrou com um leitor vivo'; fi
flock -u 9
exec 9>&-
passou 'fallback: leitores compartilham a trava e bloqueiam escrita'
