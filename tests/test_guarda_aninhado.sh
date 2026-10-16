#!/usr/bin/env bash
# Vista aninhada que troca de sessão (gancho client-session-changed do tmux.conf): o cliente do e-mail (o
# "attach -t =_tt-email" do popup/painel flutuante) volta na hora ao e-mail — antes, uma tecla do tt digitada lá
# dentro o levava à sessão que contém o próprio painel e a tela se desenhava dentro de si até o tmux cair; outra
# vista aninhada que passa a mostrar a sessão onde ela mesma está (ciclo) é desanexada; cliente de verdade
# (terminal) trocando de sessão não chama o tt.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
T_TMUX=$(command -v tmux)
log=$HOME/.cache/tt-vigia.log
tmux -f "$HOME/.tmux.conf" new -d -s trabalho -x 120 -y 30 'sleep 600' 2>/dev/null
tmux new -d -s _tt-email -x 100 -y 25 'sleep 600'
tmux new -d -s outra -x 100 -y 25 'sleep 600'
[[ -n $(tmux show-hooks -g client-session-changed 2>/dev/null) ]] || falhou 'gancho client-session-changed não carregado do tmux.conf'
# O e-mail como painel (como o painel flutuante): um cliente aninhado preso à _tt-email dentro de "trabalho".
# (o painel nasce primeiro e só então recebe o attach: nascendo já com ele, o cliente começa minúsculo e a guarda
# de tamanho o desliga antes do teste)
pe=$(tmux split-window -d -P -F '#{pane_id}' -t =trabalho: 'sleep 600'); sleep 0.3
tmux respawn-pane -k -t "$pe" "env -u TMUX $T_TMUX -u attach -t '=_tt-email'"
cli_de() { tmux list-clients -F '#{client_name} #{session_name} #{client_termname}' | awk -v s="$1" '$2 == s { print $1; exit }'; }
for i in $(seq 1 30); do c=$(cli_de _tt-email); [[ -n $c ]] && break; sleep 0.2; done
[[ -n $c ]] || falhou 'o cliente aninhado do e-mail não anexou'
tmux list-clients -F '#{client_name} #{client_termname}' | grep -q "^$c \(tmux\|screen\)" || falhou "o cliente aninhado deveria ter TERM tmux*/screen*: $(tmux list-clients -F '#{client_name} #{client_termname}')"

# Uma tecla do tt lá dentro o levaria à sessão que contém o próprio painel (o espelho infinito): volta ao e-mail.
tmux switch-client -c "$c" -t =trabalho
for i in $(seq 1 25); do [[ $(tmux display -p -c "$c" '#{session_name}' 2>/dev/null) == _tt-email ]] && break; sleep 0.2; done
[[ $(tmux display -p -c "$c" '#{session_name}' 2>/dev/null) == _tt-email ]] || falhou "o cliente do e-mail deveria voltar ao e-mail: está em $(tmux display -p -c "$c" '#{session_name}' 2>/dev/null)"
for i in $(seq 1 25); do grep -qs "o cliente do e-mail $c foi para trabalho; voltou ao e-mail" "$log" && break; sleep 0.2; done
grep -q "o cliente do e-mail $c foi para trabalho; voltou ao e-mail" "$log" || falhou "a volta deveria ficar no log do vigia: $(cat "$log" 2>/dev/null)"
# Para qualquer outra sessão também (ele nunca sai do e-mail).
tmux switch-client -c "$c" -t =outra; sleep 2
[[ $(tmux display -p -c "$c" '#{session_name}' 2>/dev/null) == _tt-email ]] || falhou 'o cliente do e-mail não pode ficar em outra sessão'
passou 'o cliente do e-mail que sai da sessão dele volta na hora (sem a tela de si mesmo dentro de si)'

# Vista aninhada comum (painel que mostra "outra") levada à sessão que a contém: ciclo, desanexada.
po=$(tmux split-window -d -P -F '#{pane_id}' -t =trabalho: 'sleep 600'); sleep 0.3
tmux respawn-pane -k -t "$po" "env -u TMUX $T_TMUX -u attach -t '=outra'"
for i in $(seq 1 30); do v=$(cli_de outra); [[ -n $v ]] && break; sleep 0.2; done
[[ -n $v ]] || falhou 'a vista aninhada comum não anexou'
tmux switch-client -c "$v" -t =trabalho
for i in $(seq 1 25); do tmux list-clients -F '#{client_name}' | grep -qx "$v" || break; sleep 0.2; done
tmux list-clients -F '#{client_name}' | grep -qx "$v" && falhou 'a vista que passou a mostrar a sessão onde ela está deveria ser desanexada'
# (quem desliga pode ser esta guarda ou a guarda de tamanho, se a tela encolher antes: as duas registram)
for i in $(seq 1 25); do grep -qsE "vista aninhada $v (passou a mostrar trabalho|\\()" "$log" && break; sleep 0.2; done
grep -qE "vista aninhada $v (passou a mostrar trabalho|\\()" "$log" || falhou "o ciclo desfeito deveria ficar no log: $(cat "$log" 2>/dev/null)"
passou 'vista aninhada que fecha um ciclo é desanexada'
