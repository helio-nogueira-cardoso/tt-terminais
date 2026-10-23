#!/usr/bin/env bash
# Fluxo real: nome antigo na fixada, anexar fora do tmux e trocar o cliente exato por UUID.
source "$(dirname "$0")/lib.sh"; isolar
printf 'nome=dell\n' >"$XDG_CONFIG_HOME/tt/config"
TT_SO_CARREGAR=1 source "$TT"; EU=$TT
tmux -f /dev/null new-session -d -s sessao-a 'sleep 600'
tmux new-session -d -s sessao-b 'sleep 600'
tmux set-option -t '=sessao-a:' @tt_session_id aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
tmux set-option -t '=sessao-b:' @tt_session_id bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
printf 'dell\tnome-antigo\tbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n' >"$CONF_FIX"
fixada_chave_em key dell nome-antigo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
espera() { local i; for i in {1..150}; do "$@" && return; sleep .02; done; falhou "espera: $*"; }
quantos() { [[ $(tmux list-clients -F '#{client_name}' 2>/dev/null | wc -l) == "$1" ]]; }
sessao() { tmux list-clients -F '#{client_name} #{session_name}' | awk -v c="$1" '$1==c {print $2}'; }

# Sem TMUX: o cliente é anexado em um PTY real à identidade, apesar do nome antigo.
fora new -d -s externo -x 100 -y 30 "env -u TMUX $(q "$TT") --ir-fixada '' fx$key"
espera quantos 1
externo=$(tmux list-clients -F '#{client_name}')
[[ $(sessao "$externo") == sessao-b ]] || falhou 'anexar usou o nome antigo'
passou 'fora do tmux: fixada anexa pela identidade, sem depender do nome salvo'

# Dentro: só o cliente indicado muda; a outra tela continua independente.
fora new -d -s interno -x 90 -y 25 "env -u TMUX TERM=xterm-256color TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t sessao-a"
espera quantos 2
interno=$(tmux list-clients -F '#{client_width} #{client_name}' | awk '$1==90 {print $2}')
export TMUX=$(tmux display-message -p '#{socket_path},#{pid},0')
"$TT" --ir-fixada "$interno" "fx$key"
[[ $(sessao "$interno") == sessao-b && $(sessao "$externo") == sessao-b ]] || falhou 'troca não preservou as duas telas'
passou 'cliente explícito troca para o UUID certo, sem arrastar outra tela'

# Sem cliente explícito: resolve pelo painel que abriu o seletor.
tmux switch-client -c "$interno" -t '=sessao-a'
painel=$(tmux display-message -p -t '=sessao-a:' '#{pane_id}')
TMUX_PANE=$painel TT_CLIENTE= "$TT" --ir-fixada '' "fx$key"
[[ $(sessao "$interno") == sessao-b ]] || falhou 'não usou o cliente do painel'
[[ $(sessao "$externo") == sessao-b ]] || falhou 'alterou cliente de outra tela'
passou 'cliente ausente é resolvido pelo painel correto'

tmux rename-session -t '=sessao-b' nome-novo
fixada_chave_em again dell nome-novo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
fixada_chave_em other dell nome-novo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
[[ $key == "$again" && $key != "$other" ]] || falhou 'nome participou da chave persistente'
passou 'a chave da faixa depende de máquina/ID; renomear não a muda'
