#!/usr/bin/env bash
# A roda sobre os chips da barra (sessão, máquina, fixadas) é o comportamento versionado no tmux.conf: vale em toda máquina
# que recebe o pacote. O chip 💬 (conversa) recebe a roda e não troca de janela.
source "$(dirname "$0")/lib.sh"; isolar
for faixa in sessao maquina fixmais conversa; do
  grep -q "WheelUpStatus.*mouse_status_range},$faixa" "$RAIZ/tmux.conf" || falhou "a roda sobre o chip $faixa deve estar no tmux.conf"
  grep -q "WheelDownStatus.*mouse_status_range},$faixa" "$RAIZ/tmux.conf" || falhou "a roda para baixo sobre $faixa deve estar no tmux.conf"
done
"$TT" --rolar conversa -1 /dev/null >/dev/null 2>&1 || falhou 'a roda sobre o 💬 não pode dar erro'
passou 'roda sobre os chips versionada: sessão, máquina, fixadas e 💬 (que não troca de janela)'
