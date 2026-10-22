#!/usr/bin/env bash
# Ponte e painel remoto abrem conexão ssh própria (não um canal da mestra): no Tailscale SSH, fechar um canal da
# mestra não encerra o tmux attach de lá, que ficava preso animando a barra para ninguém. Os comandos rápidos
# seguem usando a mestra.
source "$(dirname "$0")/lib.sh"; isolar
r=$(bash -c "source <(sed -n '/^SSH_OPC=(/,/^SSH_OPC_TELA=/p' '$TT'); declare -p SSH_OPC SSH_OPC_TELA")
grep -q 'SSH_OPC_TELA=(\[0\]="-o" \[1\]="ControlPath=none" \[2\]="-o" \[3\]="ControlMaster=no"' <<<"$r" || falhou "conexão da tela não começa pela própria: $r"
grep -q 'ControlMaster=auto' <<<"$(grep -A3 '^SSH_OPC=(' "$TT")" || falhou 'comandos rápidos perderam a conexão mestra'
grep -q 'ssh -t "\${SSH_OPC_TELA\[@\]}" "\$dest"' "$TT" || falhou 'a ponte não usa a conexão própria'
grep -q 'echo "ssh -t \$(q "\${SSH_OPC_TELA\[@\]}")' "$TT" || falhou 'o painel remoto (cmd_ver) não usa a conexão própria'
passou 'ponte e painel remoto com conexão própria; comandos rápidos seguem na mestra'
