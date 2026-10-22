#!/usr/bin/env bash
# tt-teste: sozinho (mede tempo: roda sem outros testes disputando a máquina)
# E-mail aberto em segundo plano: a 1ª abertura cria a sessão oculta; q só esconde (aerc segue vivo);
# as seguintes são instantâneas; a sessão não aparece nas listas; Ctrl+q encerra de verdade.
PATH="$HOME/.local/bin:$PATH" command -v aerc >/dev/null || { echo "(aerc não instalado: teste pulado)"; exit 0; }
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
# aerc/w3m instalados na pasta do usuário (opt/share/libexec + bin) são trazidos para o HOME isolado; os do
# sistema (/usr/bin) já estão no PATH e não precisam de nada.
R=$HOME_REAL; mkdir -p ~/.local/opt ~/.local/share ~/.local/libexec ~/.local/bin
for x in aerc-0.20.0 w3m-0.5.3; do [[ -e $R/.local/opt/$x ]] && ln -s "$R/.local/opt/$x" ~/.local/opt/; done
[[ -e $R/.local/share/aerc ]] && ln -s "$R/.local/share/aerc" ~/.local/share/aerc
[[ -e $R/.local/libexec/aerc ]] && ln -s "$R/.local/libexec/aerc" ~/.local/libexec/aerc
for b in aerc w3m; do [[ -e $R/.local/bin/$b ]] && cp "$R/.local/bin/$b" ~/.local/bin/; done
export PATH=$HOME/.local/bin:$PATH
mkdir -p $T/m/INBOX/{cur,new,tmp}; printf 'From: X <x@x>\nSubject: Ola\nDate: %s\nMessage-ID: <1@a>\n\noi\n' "$(date -R)" > $T/m/INBOX/cur/1.x:2,S
mkdir -p ~/.config/aerc; printf '[Teste]\nsource = maildir://%s/m\nfrom = a@x\noutgoing = /bin/true\n' $T > ~/.config/aerc/accounts.conf; chmod 600 ~/.config/aerc/accounts.conf
bash -c "source <(sed -n '/^AERC_BINDS_INI=/,/^remover_aerc() {/p' '$TT' | sed '\$d'); DIR_TT='$TT_DIR'; conf() { :; }; configurar_aerc"
tmux -f "$HOME/.tmux.conf" new -d -s s -x 150 -y 36 'bash --norc' 2>/dev/null; anexar v 150 38 s; sleep 2; c=$(tmux list-clients -F '#{client_name}' | head -1)
ab() { local t0=$(date +%s%N); tmux run-shell -b "$TT --email '$c'"; while ! fora capture-pane -p -t v | grep -q 'Ola'; do sleep 0.05; (( ($(date +%s%N)-t0)/1000000 > 15000 )) && { echo "lista do e-mail não apareceu em 15 s" >&2; return 1; }; done; echo $(( ($(date +%s%N)-t0)/1000000 )); }
m1=$(ab) || falhou "primeira abertura do e-mail"
identidade=$(tmux display -p -t =_tt-email: '#{session_id}:#{pane_id}:#{pane_pid}')
fora send -t v q; sleep 1
fora capture-pane -p -t v | grep -q 'Ola' && falhou 'q não escondeu a subjanela'
[[ $(tmux display -p -t =_tt-email: '#{pane_current_command}' 2>/dev/null) == aerc* ]] || falhou 'aerc não continuou aberto depois do q'
m2=$(ab) || falhou "reabertura do e-mail"
[[ $(tmux display -p -t =_tt-email: '#{session_id}:#{pane_id}:#{pane_pid}') == "$identidade" ]] || falhou 'reabrir recriou a sessão ou o processo do aerc'
fora send -t v q; sleep 1
# A interface nativa do Mac tem custo maior; preservar o processo é a prova de cache.
# Mantém um orçamento explícito de resposta, com margem para o agendamento do host.
limite=1500; if [[ $(uname -s) == Darwin ]]; then limite=2500; fi
((m2 < limite)) || falhou "reabrir levou ${m2} ms (limite ${limite} ms)"
"$TT" --listar | grep -q '_tt-email' && falhou 'sessão oculta do e-mail apareceu na lista'
passou "e-mail aberto em segundo plano: 1ª ${m1} ms, reabrir ${m2} ms; fora das listas"
ab >/dev/null || falhou 'e-mail não reabriu antes do Ctrl+q'
fora send -t v C-q
for _ in {1..50}; do tmux has-session -t =_tt-email 2>/dev/null || break; sleep 0.1; done
tmux has-session -t =_tt-email 2>/dev/null && falhou 'Ctrl+q não encerrou o aerc'
passou 'Ctrl+q encerra o e-mail de verdade'

# Emoji com seletor de variação no assunto (🕸️, ⚠️): o aerc da sessão mede igual ao tmux; nada
# transborda para a linha de baixo (dígitos soltos na coluna de pastas).
[[ $(tmux show-environment -t =_tt-email VAXIS_FORCE_UNICODE 2>/dev/null) == VAXIS_FORCE_UNICODE=1 ]] ||
  { tmux run-shell -b "$TT --email '$c'"; sleep 2; fora send -t v q; sleep 1; }
[[ $(tmux show-environment -t =_tt-email VAXIS_FORCE_UNICODE 2>/dev/null) == VAXIS_FORCE_UNICODE=1 ]] || falhou 'aerc da sessão sem VAXIS_FORCE_UNICODE=1'
passou 'aerc mede emoji com seletor de variação igual ao tmux'
