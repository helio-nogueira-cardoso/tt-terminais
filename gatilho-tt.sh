#!/usr/bin/env bash
# bash 4+ (o `env bash` pode achar o 3.2 do macOS: o path_helper põe /usr/bin na frente): recomeça com o do Homebrew.
if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
  for _tt_b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [ -x "$_tt_b" ] && exec "$_tt_b" "$0" "$@"; done
  echo "$0: precisa do bash 4 ou mais novo (este é o $BASH_VERSION). No macOS: brew install bash" >&2; exit 1
fi
# Gatilho do letreiro (ver letreiro-tt.py): uma linha VAZIA por segundo, 30 ms depois do quadro K do
# pintor, só enquanto ele desliza o letreiro. Uma linha impressa por um #() da barra redesenha a
# barra (no máximo 1 vez/s por #()): com FPS-1 gatilhos defasados de 1/FPS s a barra muda FPS vezes
# por segundo, sem set-option e sem tocar nos painéis. Só builtins do bash (sem fork, ~3 MB em vez
# dos ~12 MB de um python): a espera é um `read -t` num fifo (só o pintor escreve nele, na leitura).
# uso: gatilho-tt.sh PID_DO_CLIENTE K FPS
pid=$1 k=$2 fps=$3
[[ $pid =~ ^[0-9]+$ && $k =~ ^[0-9]+$ && $fps =~ ^[0-9]+$ ]] && ((fps > 0)) || exit 2
rt=${TT_RT:-/run/user/$(id -u)}
[[ -d $rt ]] || rt=/tmp
marca=$rt/tt-letreiro-$pid.anim
# O fifo fica no disco, com nome sabido: o pintor escreve uma linha nele para pedir um redesenho JÁ (a leitura na
# faixa troca de palavra na hora exata, fora da grade de quadros; ver disparar no letreiro-tt.py). Quem apaga é o
# pintor, quando o cliente vai embora; um gatilho novo do mesmo cliente toma o nome (o antigo fica com o fifo dele).
fifo=$rt/tt-gatilho-$pid-$k
rm -f "$fifo"; mkfifo -m 600 "$fifo" 2>/dev/null && exec {fd}<>"$fifo" || exit 1
printf '\n' || exit 0  # sem uma 1ª linha o tmux mostra "<'comando' not ready>" no lugar do #()
# (/proc/PID no Linux; sem /proc, no macOS, kill -0: builtin, sem fork)
while [[ -d /proc/$pid ]] || { [[ ! -d /proc/self ]] && kill -0 "$pid" 2>/dev/null; }; do
  agora=${EPOCHREALTIME/[.,]/}  # microssegundos
  seg=$((agora / 1000000))
  alvo=$(( (seg * 1000000) + (k * 1000000 / fps) + 30000 ))
  ((alvo <= agora)) && alvo=$((alvo + 1000000))
  falta=$((alvo - agora))
  printf -v t '%d.%06d' $((falta / 1000000)) $((falta % 1000000))
  if read -rt "$t" -u "$fd"; then
    printf '\n' || exit 0  # pedido do pintor: redesenha agora
    continue
  fi
  t0=
  { read -r t0 <"$marca"; } 2>/dev/null
  if [[ $t0 =~ ^[0-9]+$ ]] && (( ${EPOCHREALTIME%[.,]*} - t0 < 3 )); then
    printf '\n' || exit 0  # o tmux fechou o cano: o cliente foi embora
  fi
done
