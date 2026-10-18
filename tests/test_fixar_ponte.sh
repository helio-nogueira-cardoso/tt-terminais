#!/usr/bin/env bash
# O 📌/📍 da barra numa sessão de PONTE vale para a sessão real da outra máquina, não para a ponte (que o vigia
# encerra por ociosidade e o reconciliador apagava da lista). O soltar (u) do toque é ignorado; o pressionar (d),
# e o clique sem evento (CLI), alternam.
source "$(dirname "$0")/lib.sh"; isolar
tt() { "$TT" "$@"; }
lista() { cut -f1,2 "$XDG_CONFIG_HOME/tt/fixadas" 2>/dev/null | tr '\t' ':' | sort | tr '\n' ' '; }
falha() { falhou "$1 (fixadas: $(lista))"; }

mkdir -p "$T/bin"
printf '#!/bin/sh\ncase "$*" in *--session-id*) echo id-remoto ;; esac\nexit 0\n' >"$T/bin/ssh"; chmod +x "$T/bin/ssh"
export PATH=$T/bin:$PATH
printf '192.0.2.1 ninguem remota\n' >"$XDG_CONFIG_HOME/tt/maquinas"

# A ponte tem o nome que quiser; o alvo real fica em @ponte_alvo ("destino|sessão lá").
tmux -f /dev/null new -d -s ponte-local 'sleep 600'
tmux set -t =ponte-local: @ponte 'ninguem@192.0.2.1'
tmux set -t =ponte-local: @ponte_alvo 'ninguem@192.0.2.1|alvo-real'
anexar v 120 32 ponte-local; sleep 2
cli=$(tmux list-clients -F '#{client_name}' | head -1)
[[ -n $cli ]] || falhou 'cliente tmux não anexou'

tt --clique fixar "$cli" '' "$HOME" 0 u
[[ -z $(lista) ]] || falha 'o soltar (u) do toque alterou as fixadas'

tt --clique fixar "$cli" '' "$HOME" 0 d
[[ $(lista) == "remota:alvo-real " ]] || falha 'o 📌 numa ponte devia fixar remota:alvo-real (a sessão real), não a ponte'
[[ $(tmux show -v -t =ponte-local: @tt_fixada 2>/dev/null) == 1 ]] || falha 'o pino da barra não acendeu na ponte cuja sessão real está fixada'
passou '📌 numa ponte fixa a sessão real da outra máquina e acende o pino'

sleep 1
tt --clique fixar "$cli" '' "$HOME" 0 d
[[ -z $(lista) ]] || falha 'o segundo 📌 numa ponte devia desafixar a sessão real'
[[ -z $(tmux show -v -t =ponte-local: @tt_fixada 2>/dev/null) ]] || falha 'o pino da barra continuou aceso depois de desafixar'
passou '📌 numa ponte desafixa a sessão real e apaga o pino'

# Sem @ponte_alvo (sessão comum), nada muda: fixa a sessão daqui e o CLI sem evento ainda alterna.
tmux new -d -s comum 'sleep 600'
tmux switch-client -c "$cli" -t =comum 2>/dev/null || tmux -L "fora-$$" send -t v ''
sleep 1
tmux switch-client -c "$cli" -t =comum; sleep 1
tt --clique fixar "$cli" '' "$HOME" 0
[[ $(lista) == "teste:comum " ]] || falha 'sessão comum devia fixar teste:comum'
passou 'sessão comum continua fixando a própria sessão (clique sem evento alterna)'
