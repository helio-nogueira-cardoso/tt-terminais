#!/usr/bin/env bash
# tt-teste: sozinho (mede tempo e atividade real do tmux; roda sem outros testes disputando a máquina)
# Vigia, revisão de uma aba já nomeada: se o nome sugerido pela IA já é de OUTRA sessão, a aba mantém o nome atual
# (nada de "-2") e o vigia registra; e todo nome sugerido por IA deixa a origem em ~/.cache/tt-nomes.log.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\ncat >/dev/null; echo assunto-ocupado\n' >"$HOME/.local/bin/claude"
chmod +x "$HOME/.local/bin/claude"
tmux -f /dev/null new -d -s com-teclas -x 80 -y 20 'bash --norc'
tmux -f /dev/null new -d -s assunto-ocupado -x 80 -y 20 'bash --norc'
anexar cliente 80 22 com-teclas; sleep 1

TT_PAUSA=1 TT_T_RENOMEAR=2 TT_PONTOS_RENOMEAR=5 TT_T_REVISAO=999999 "$TT" --vigia >/dev/null 2>&1 &
sleep 3
for i in 1 2 3 4 5 6; do fora send -t cliente "echo pedido $i" Enter; sleep 1.5; done
for ((i = 0; i < 60; i++)); do grep -q 'mantida: o nome sugerido (assunto-ocupado)' "$HOME/.cache/tt-vigia.log" 2>/dev/null && break; sleep 1; done
grep -q 'com-teclas mantida: o nome sugerido (assunto-ocupado) já é de outra sessão' "$HOME/.cache/tt-vigia.log" ||
  falhou "o vigia não registrou a colisão: $(tail -3 "$HOME/.cache/tt-vigia.log" 2>/dev/null)"
tmux has-session -t =com-teclas 2>/dev/null || falhou "a aba perdeu o nome atual: $(tmux ls -F '#S' | tr '\n' ' ')"
tmux has-session -t =assunto-ocupado-2 2>/dev/null && falhou 'a revisão criou o nome duplicado -2'
passou 'nome sugerido que já é de outra sessão: a aba mantém o nome e o vigia registra'
grep -q 'com-teclas conversa=.* sugerido=assunto-ocupado$' "$HOME/.cache/tt-nomes.log" ||
  falhou "a origem do nome não foi registrada: $(cat "$HOME/.cache/tt-nomes.log" 2>/dev/null | tail -2)"
passou 'a origem de cada nome sugerido por IA fica em tt-nomes.log'
