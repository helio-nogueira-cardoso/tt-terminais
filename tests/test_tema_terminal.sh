#!/usr/bin/env bash
# tema-terminal.sh é carregado com source pelo ~/.bashrc: nunca pode encerrar o shell nem deixar
# funções/variáveis para trás, com ou sem terminal, dentro ou fora do tmux.
source "$(dirname "$0")/lib.sh"; isolar
f=$T/pkg/tema-terminal.sh
r=$(bash -c "source '$f'; echo VIVO; declare -F | grep -c _tt_ || true; declare -p cores 2>/dev/null | wc -l")
[[ $r == $'VIVO\n0\n0' ]] || falhou "sem terminal: shell encerrado ou sobras ($r)"
r=$(TMUX=x script -qc "bash -c \"source '$f'; echo VIVO\"" /dev/null | tr -d '\r')
[[ $r == *VIVO* ]] || falhou 'dentro do tmux: shell encerrado'
r=$(script -qc "env -u TMUX bash -c \"source '$f'; echo; echo VIVO\"" /dev/null | tr -d '\r')
[[ $r == *VIVO* && $r == *$'\e]11;#1e1e2e'* ]] || falhou 'com terminal: paleta não aplicada ou shell encerrado'
passou 'tema-terminal.sh: nunca encerra o shell, aplica a paleta só onde deve, não deixa sobras'

echo "source '$f'" >"$T/rc"
tmux -f /dev/null new -d -s s "bash --rcfile '$T/rc' -i"; sleep 1.5
tmux has-session -t =s 2>/dev/null && [[ $(tmux display -p -t '=s:' '#{pane_current_command}') == bash ]] ||
  falhou 'sessão tmux nova com o tema no rc fechou'
passou 'sessão tmux nova com o tema no rc continua viva'
