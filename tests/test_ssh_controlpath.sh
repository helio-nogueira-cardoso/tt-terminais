#!/usr/bin/env bash
# O socket multiplexado precisa distinguir porta, usuário e host; sem rede nem servidor SSH.
source "$(dirname "$0")/lib.sh"; isolar
linha=$(sed -n '/-o ControlMaster=auto -o .*ControlPath=/p' "$TT")
[[ $linha == *'ControlPath=$HOME/.cache/tt-ssh-%C'* ]] || falhou 'ControlPath não usa a identidade completa da conexão'
socket() { ssh -G -o "ControlPath=$T/tt-ssh-%C" -p "$1" "$2" 2>/dev/null | awk '$1 == "controlpath" {print $2}'; }
a=$(socket 22 usuario@exemplo); b=$(socket 8022 usuario@exemplo); c=$(socket 22 outro@exemplo)
[[ -n $a && -n $b && -n $c && $a != "$b" && $a != "$c" ]] || falhou "sockets colidem: $a $b $c"
passou 'sockets SSH diferentes para portas e usuários diferentes'
# O voz reaproveita a conexão aberta pelo tt (~0,35 s por comando, não ~0,75 s): o socket tem de ter o mesmo nome.
# Com o tt em %C e o voz ainda em %r@%h, cada máquina segurava duas conexões com cada outra.
grep -qF -- '-o "ControlPath=$HOME/.cache/tt-ssh-%C"' "$RAIZ/voz" || falhou 'o voz não usa o ControlPath do tt'
grep -qF -- '"ControlPath=%s/.cache/tt-ssh-%%C" % CASA' "$RAIZ/voz-audio.py" || falhou 'o voz-audio.py não usa o ControlPath do tt'
[[ $(grep -c 'tt-ssh-%r@%h\|tt-ssh-%%r@%%h' "$RAIZ/voz" "$RAIZ/voz-audio.py" "$TT" | awk -F: '{s += $2} END {print s}') == 0 ]] ||
  falhou 'sobrou ControlPath antigo (%r@%h)'
passou 'voz e voz-audio.py usam o mesmo socket do tt'
