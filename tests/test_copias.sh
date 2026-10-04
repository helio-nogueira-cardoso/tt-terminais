#!/usr/bin/env bash
# Histórico de cópias: registra com origem, não duplica repetição nem eco, guarda no máximo 100,
# pasta só do usuário. Sem envio para outras máquinas (copia_entre_maquinas=0).
source "$(dirname "$0")/lib.sh"; isolar
echo copia_entre_maquinas=0 >>"$XDG_CONFIG_HOME/tt/config"
d=$HOME/.cache/tt-copias
printf 'um ç' | "$TT" --copiar; printf 'um ç' | "$TT" --copiar
printf 'de lá' | "$TT" --receber-copia empresa; printf 'de lá' | "$TT" --receber-copia empresa
printf 'de lá' | "$TT" --copiar   # eco: a mesma cópia voltando por OSC 52 de uma ponte
printf '' | "$TT" --copiar
[[ $(ls "$d" | wc -l) == 2 ]] || falhou "esperava 2 cópias, há $(ls "$d" | wc -l)"
[[ $(ls "$d" | sort | tail -1) == *_empresa ]] || falhou 'origem da cópia recebida não registrada'
[[ $(stat -c %a "$d") == 700 ]] || falhou 'histórico visível para outros usuários'
for i in $(seq 1 110); do printf 'c%s' "$i" | "$TT" --copiar; done
[[ $(ls "$d" | wc -l) == 100 ]] || falhou "limite de 100 não respeitado: $(ls "$d" | wc -l)"
[[ $(cat "$d/$(ls "$d" | sort | tail -1)") == c110 ]] || falhou 'a mais recente não está no topo'
passou 'histórico: sem repetição/eco, origem, limite 100, pasta privada'
