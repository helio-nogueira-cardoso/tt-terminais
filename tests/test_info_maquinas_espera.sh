#!/usr/bin/env bash
# Menu de máquinas: a consulta de sessões e versão (tt --atualizar-info) espera cada máquina até TT_T_INFO_SSH s (8;
# o celular leva de 1 a 4 s). TT_T_INFO é outra coisa: o intervalo do vigia entre duas consultas (300 s). Na v1.28.11
# a espera do ssh lia o TT_T_INFO, e quem ajustasse o intervalo do vigia mudava também a espera (TT_T_INFO=1 cortava a
# máquina lenta; TT_T_INFO=300 esperava 5 min por uma muda). Sem rede: o ssh é falso.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"
cat >"$T/bin/ssh" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case $a in
    *@lenta-host) sleep 2; echo "2 399 1.28.11"; exit 0 ;;
    *@muda-host) sleep 30; exit 255 ;;
  esac
done
exit 255
EOF
printf '#!/bin/sh\nexit 1\n' >"$T/bin/tailscale"
chmod +x "$T/bin/ssh" "$T/bin/tailscale"
export PATH="$T/bin:$TT_PATH_BASE"
printf 'lenta-host helio lenta\n' >"$XDG_CONFIG_HOME/tt/maquinas"
info=$TT_RT/tt-info-$(id -u)-lenta

TT_T_INFO=1 "$TT" --atualizar-info
[[ $(cat "$info" 2>/dev/null) == "2 399 1.28.11" ]] ||
  falhou "TT_T_INFO=1 (intervalo do vigia) cortou a máquina que responde em 2 s: '$(cat "$info" 2>/dev/null)'"
passou 'menu de máquinas: o intervalo do vigia (TT_T_INFO) não muda a espera do ssh; a máquina de 2 s responde'

printf 'muda-host helio lenta\n' >"$XDG_CONFIG_HOME/tt/maquinas"; rm -f "$TT_RT/tt-maquinas-"*
ini=$(date +%s)
TT_T_INFO=300 TT_T_INFO_SSH=1 "$TT" --atualizar-info
dur=$(($(date +%s) - ini))
[[ $(cat "$info" 2>/dev/null) == "? ?" ]] || falhou "a máquina muda deveria virar '? ?': '$(cat "$info" 2>/dev/null)'"
((dur <= 5)) || falhou "TT_T_INFO_SSH=1 deveria cortar a máquina muda em ~1 s (levou ${dur} s com TT_T_INFO=300)"
passou "menu de máquinas: TT_T_INFO_SSH limita a espera da máquina muda (${dur} s, '? ?')"
