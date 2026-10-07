#!/usr/bin/env bash
# Regressao: a troca de sessao que fecharia ciclo nao pode mais travar no "Enter para voltar".
# O escape automatico (quebrar_ciclo_para) desanexa as vistas aninhadas (clientes TERM tmux*/
# screen*) que estao DENTRO do alvo, liberando a troca. Prova que a vista aninhada em B e
# desanexada por quebrar_ciclo_para B.
source "$(dirname "$0")/lib.sh"; isolar
set +e  # este teste conta clientes com grep -c (retorna 1 quando zero); nao queremos abortar por isso

tmux -f /dev/null new -d -s B -x 120 -y 30 'sleep 600'
# cliente aninhado (TERM tmux*) anexado a B, como uma ponte/vista dentro de um painel
fora new -d -s aninhado -x 100 -y 24 "env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR TERM=tmux-256color tmux attach -t =B"
sleep 1

antes=$(tmux list-clients -t "=B" -F '#{client_termname}' 2>/dev/null | grep -c '^tmux')
[[ $antes -ge 1 ]] || falhou "pre-condicao: vista aninhada em B nao criada (tmux clients=$antes)"

mkdir -p "$HOME/.cache"
source <(sed -n '/^arestas_paineis()/,/^}/p;/^alcanca()/,/^}/p;/^quebrar_ciclo_para()/,/^}/p' "$TT")
[[ $(type -t quebrar_ciclo_para) == function ]] || falhou "nao consegui carregar quebrar_ciclo_para do tt"

quebrar_ciclo_para B
sleep 0.5
depois=$(tmux list-clients -t "=B" -F '#{client_termname}' 2>/dev/null | grep -c '^tmux')
[[ $depois -lt $antes ]] || falhou "escape nao desanexou a vista aninhada de B (antes=$antes depois=$depois)"
passou "escape de ciclo desanexa a vista aninhada do alvo (B: $antes -> $depois)"
