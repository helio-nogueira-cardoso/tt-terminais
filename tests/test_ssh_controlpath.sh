#!/usr/bin/env bash
# O socket multiplexado precisa distinguir porta, usuário e host; sem rede nem servidor SSH.
source "$(dirname "$0")/lib.sh"; isolar
linha=$(sed -n '/-o ControlMaster=auto -o .*ControlPath=/p' "$TT")
[[ $linha == *'ControlPath=$HOME/.cache/tt-ssh-%C'* ]] || falhou 'ControlPath não usa a identidade completa da conexão'
socket() { ssh -G -o "ControlPath=$T/tt-ssh-%C" -p "$1" "$2" 2>/dev/null | awk '$1 == "controlpath" {print $2}'; }
a=$(socket 22 usuario@exemplo); b=$(socket 8022 usuario@exemplo); c=$(socket 22 outro@exemplo)
[[ -n $a && -n $b && -n $c && $a != "$b" && $a != "$c" ]] || falhou "sockets colidem: $a $b $c"
passou 'sockets SSH diferentes para portas e usuários diferentes'
