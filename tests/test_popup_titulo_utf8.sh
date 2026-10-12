#!/usr/bin/env bash
# Regressão (projeto tt): o título dos popups (📰 letreiro, 📤 enviar…) aparecia como "\360\237\223\260 letreiro".
# O título passa por q() (printf %q); num locale não UTF-8 (o tmux e o run-shell dos menus costumam rodar sem LANG)
# o bash cita o emoji como $'\360\237\223\260', que o sh não entende e o tmux desenha literal.
source "$(dirname "$0")/lib.sh"; isolar

eval "$(sed -n '/^q() {/,/^}/p; /^popup_tt() {/,/^}/p' "$TT")"
tam_popup() { echo "-w 90% -h 85%"; }
EU=tt

# 1) q(), sem locale nenhum: o emoji sai inteiro e sem $'…'
for loc in POSIX C; do
  saida=$(env -i LC_ALL=$loc bash -c 'eval "$1"; q " 📰 letreiro "' _ "$(sed -n '/^q() {/,/^}/p' "$TT")")
  [[ $saida != *'\3'* && $saida != *"\$'"* ]] || falhou "q() em locale $loc escapou o emoji: $saida"
  [[ $saida == *📰* ]] || falhou "q() em locale $loc perdeu o emoji: $saida"
done
passou 'q(): emoji do título passa inteiro mesmo sem locale UTF-8'

# 2) o título que o sh recebe (como o tmux roda o comando do menu) é o texto, não os bytes em octal
export LC_ALL=POSIX
cmd=$(popup_tt cli "📰 letreiro" "tt --letreiro-ui")
saida=$(sh -c "set -- $cmd; while [ \"\$1\" != -T ]; do shift; done; printf %s \"\$2\"")
[[ $saida == " 📰 letreiro " ]] || falhou "título do popup chegou como '$saida'"
passou "popup_tt: o sh entrega o título '$saida' sem escapes"

# 3) o que q() já garantia segue valendo
[[ $(q '=igual') == '\=igual ' ]] || falhou "= inicial perdeu a barra: $(q '=igual')"
[[ $(q 'com espaço' "aspas'simples") == 'com\ espaço aspas\'\''simples ' ]] || falhou "citação comum mudou: $(q 'com espaço' "aspas'simples")"
passou 'q(): "=" inicial e aspas continuam citados'
