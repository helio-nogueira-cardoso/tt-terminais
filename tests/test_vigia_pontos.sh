#!/usr/bin/env bash
# Vigia, renomeação por pontos numa aba de shell já nomeada: teclas de verdade (um cliente anexado)
# são pedidos e somam com os minutos de uso; saída na tela sozinha não renomeia nem chama o Haiku.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\ncat >/dev/null; echo "$(date +%%s%%N)" >>%s/haiku; echo assunto-novo\n' "$T" >"$HOME/.local/bin/claude"
chmod +x "$HOME/.local/bin/claude"
tmux -f /dev/null new -d -s com-teclas -x 80 -y 20 'bash --norc'
tmux -f /dev/null new -d -s so-saida -x 80 -y 20 'bash --norc'
tmux send -t =so-saida: 'while :; do date; sleep 1; done' Enter # uso sem pedido
anexar cliente 80 22 com-teclas; sleep 1

TT_PAUSA=1 TT_T_RENOMEAR=2 TT_PONTOS_RENOMEAR=7 TT_T_REVISAO=999999 "$TT" --vigia >/dev/null 2>&1 &
sleep 3
for i in 1 2 3 4 5 6; do fora send -t cliente "echo pedido $i" Enter; sleep 1.5; done
for ((i = 0; i < 20; i++)); do tmux has-session -t =assunto-novo 2>/dev/null && break; sleep 1; done
tmux has-session -t =assunto-novo 2>/dev/null || falhou "teclas e uso não renomearam: $(tmux ls -F '#S' | tr '\n' ' ')"
passou 'teclas de verdade + minutos de uso renomeiam a aba'
tmux has-session -t =so-saida 2>/dev/null || falhou 'aba só com saída na tela foi renomeada'
[[ $(wc -l <"$T/haiku") -eq 1 ]] || falhou "Haiku chamado $(wc -l <"$T/haiku") vezes (esperado 1)"
passou 'só saída na tela, sem pedido: nem renomeia nem chama o Haiku'
