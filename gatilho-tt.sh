#!/usr/bin/env bash
# Gatilho do letreiro (ver letreiro-tt.py): uma linha VAZIA por segundo, 30 ms depois do quadro K do
# pintor, só enquanto ele desliza o letreiro. Uma linha impressa por um #() da barra redesenha a
# barra (no máximo 1 vez/s por #()): com FPS-1 gatilhos defasados de 1/FPS s a barra muda FPS vezes
# por segundo, sem set-option e sem tocar nos painéis. Só builtins do bash (sem fork, ~3 MB em vez
# dos ~12 MB de um python): a espera é um `read -t` num fifo que ninguém escreve.
# uso: gatilho-tt.sh PID_DO_CLIENTE K FPS
pid=$1 k=$2 fps=$3
[[ $pid =~ ^[0-9]+$ && $k =~ ^[0-9]+$ && $fps =~ ^[0-9]+$ ]] && ((fps > 0)) || exit 2
rt=${TT_RT:-/run/user/$(id -u)}
[[ -d $rt ]] || rt=/tmp
marca=$rt/tt-letreiro-$pid.anim
fifo=$rt/tt-gatilho-$pid-$k.$$
mkfifo "$fifo" 2>/dev/null && exec {fd}<>"$fifo" && rm -f "$fifo" || exit 1
printf '\n' || exit 0  # sem uma 1ª linha o tmux mostra "<'comando' not ready>" no lugar do #()
while [[ -d /proc/$pid ]]; do
  agora=${EPOCHREALTIME/[.,]/}  # microssegundos
  seg=$((agora / 1000000))
  alvo=$(( (seg * 1000000) + (k * 1000000 / fps) + 30000 ))
  ((alvo <= agora)) && alvo=$((alvo + 1000000))
  falta=$((alvo - agora))
  printf -v t '%d.%06d' $((falta / 1000000)) $((falta % 1000000))
  read -rt "$t" -u "$fd"
  t0=
  { read -r t0 <"$marca"; } 2>/dev/null
  if [[ $t0 =~ ^[0-9]+$ ]] && (( ${EPOCHREALTIME%[.,]*} - t0 < 3 )); then
    printf '\n' || exit 0  # o tmux fechou o cano: o cliente foi embora
  fi
done
