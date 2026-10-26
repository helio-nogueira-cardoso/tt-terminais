#!/usr/bin/env bash
# Boot do Termux (jube42): sshd supervisionado pelo runit no boot, laço de religamento fora do proot, sem sshd do Debian,
# e a checagem do celular.sh avisa quando o sshd não está no runit. (Estático: o Termux não roda no teste.)
source "$(dirname "$0")/lib.sh"
B=$RAIZ/termux/boot-tt
sh -n "$B" || falhou 'o boot do Termux tem erro de sintaxe'
grep -q 'sv up sshd' "$B" || falhou 'o boot deve subir o sshd pelo runit (sv up sshd)'
grep -q ': sshd-watch' "$B" || falhou 'o boot deve ter o laço que religa o sshd do Termux'
grep -q 'sshd-watch' "$B" && grep -q 'sshd >' "$B" || falhou 'o laço deve religar com o sshd do Termux'
grep -q 'debian' <(grep 'sshd-watch' "$B") && falhou 'o laço do sshd não pode subir sshd do Debian'
grep -q 'sv status sshd' "$RAIZ/termux/celular.sh" || falhou 'celular.sh verificar deve checar a supervisão do sshd'
grep -q 'tt-tmux/bin/tmux' "$B" || falhou 'o boot deve iniciar o servidor da tela com o tmux 3.8 do tt'
passou 'boot do Termux: sshd no runit, laço de religamento e checagem no celular.sh'
