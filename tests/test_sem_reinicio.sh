#!/usr/bin/env bash
# Atualizar ou instalar o tt nunca reinicia o aparelho: nenhum reboot pelo adb no código do tt.
source "$(dirname "$0")/lib.sh"
grep -q 'svc power' "$RAIZ/tt" && falhou 'o tt não pode reiniciar o aparelho na instalação ou atualização (svc power)'
grep -q 'reinicio_unico' "$RAIZ/tt" && falhou 'reinício único não deve mais existir no tt'
passou 'instalar e atualizar não reiniciam o aparelho'
