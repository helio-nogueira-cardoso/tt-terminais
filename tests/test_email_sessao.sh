#!/usr/bin/env bash
# E-mail aberto em segundo plano: a 1ª abertura cria a sessão oculta; q só esconde (aerc segue vivo);
# as seguintes são instantâneas; a sessão não aparece nas listas; Ctrl+q encerra de verdade.
PATH="$(getent passwd "$(id -un)" | cut -d: -f6)/.local/bin:$PATH" command -v aerc >/dev/null || { echo "(aerc não instalado: teste pulado)"; exit 0; }
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
R=$HOME_REAL; mkdir -p ~/.local/opt ~/.local/share ~/.local/libexec; for x in aerc-0.20.0 w3m-0.5.3; do ln -s $R/.local/opt/$x ~/.local/opt/; done; ln -s $R/.local/share/aerc ~/.local/share/aerc; ln -s $R/.local/libexec/aerc ~/.local/libexec/aerc; cp $R/.local/bin/aerc $R/.local/bin/w3m ~/.local/bin/; export PATH=$HOME/.local/bin:$PATH
mkdir -p $T/m/INBOX/{cur,new,tmp}; printf 'From: X <x@x>\nSubject: Ola\nDate: %s\nMessage-ID: <1@a>\n\noi\n' "$(date -R)" > $T/m/INBOX/cur/1.x:2,S
mkdir -p ~/.config/aerc; printf '[Teste]\nsource = maildir://%s/m\nfrom = a@x\noutgoing = /bin/true\n' $T > ~/.config/aerc/accounts.conf; chmod 600 ~/.config/aerc/accounts.conf
bash -c "source <(sed -n '/^AERC_BINDS_INI=/,/^remover_aerc() {/p' '$TT' | sed '\$d'); DIR_TT='$TT_DIR'; conf() { :; }; configurar_aerc"
tmux -f "$HOME/.tmux.conf" new -d -s s -x 150 -y 36 'bash --norc' 2>/dev/null; anexar v 150 38 s; sleep 2; c=$(tmux list-clients -F '#{client_name}' | head -1)
ab() { local t0=$(date +%s%N); tmux run-shell -b "$TT --email '$c'"; while ! fora capture-pane -p -t v | grep -q 'Ola'; do sleep 0.05; (( ($(date +%s%N)-t0)/1000000 > 15000 )) && break; done; echo "$1: $(( ($(date +%s%N)-t0)/1000000 )) ms até a lista"; }
ab() { local t0=$(date +%s%N); tmux run-shell -b "$TT --email '$c'"; while ! fora capture-pane -p -t v | grep -q 'Ola'; do sleep 0.05; (( ($(date +%s%N)-t0)/1000000 > 15000 )) && { echo 15000; return; }; done; echo $(( ($(date +%s%N)-t0)/1000000 )); }
m1=$(ab); fora send -t v q; sleep 1
fora capture-pane -p -t v | grep -q 'Ola' && falhou 'q não escondeu a subjanela'
[[ $(tmux display -p -t =_tt-email: '#{pane_current_command}' 2>/dev/null) == aerc* ]] || falhou 'aerc não continuou aberto depois do q'
m2=$(ab); fora send -t v q; sleep 1
((m2 < 1500)) || falhou "reabrir levou ${m2} ms (deveria ser instantâneo)"
"$TT" --listar | grep -q '_tt-email' && falhou 'sessão oculta do e-mail apareceu na lista'
passou "e-mail aberto em segundo plano: 1ª ${m1} ms, reabrir ${m2} ms; fora das listas"
tmux run-shell -b "$TT --email '$c'"; sleep 1.5; fora send -t v C-q; sleep 2
tmux has-session -t =_tt-email 2>/dev/null && falhou 'Ctrl+q não encerrou o aerc'
passou 'Ctrl+q encerra o e-mail de verdade'
