#!/usr/bin/env bash
# Tick do mesh: o intervalo muda no agendador da máquina (systemd aqui) e aparece no "ver". Isola HOME.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$HOME/.config/systemd/user"
printf '[Timer]\nOnBootSec=3min\nOnUnitActiveSec=10min\n' >"$HOME/.config/systemd/user/tt-chief.timer"
"$TT" --mesh-tick 20 >/dev/null 2>&1 || falhou 'o verbo deveria aceitar o intervalo'
grep -q '^OnUnitActiveSec=20min$' "$HOME/.config/systemd/user/tt-chief.timer" || falhou 'o timer deveria passar a 20 min'
"$TT" --mesh-tick ver 2>/dev/null | grep -q 'a cada 20' || falhou 'o ver deveria mostrar 20'
passou 'tick do mesh: o intervalo muda no agendador da máquina e aparece no ver'
