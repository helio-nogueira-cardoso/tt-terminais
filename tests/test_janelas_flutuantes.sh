#!/usr/bin/env bash
# Janelas flutuantes: com painel_flutuante=1 e tmux 3.8+, TODO display-popup do tt (central, seletor, menus,
# agenda, notificações, fixadas, e-mail…) vira um painel modal que fecha ao clicar na janela fora dele; o título
# vai na borda; o comando recebe TT_CLIENTE e TT_EM_JANELA. Desligado, em tmux velho, com um modal já aberto, ou
# nos popups "fixos" (pendências com apt/sudo, navegador), é o display-popup de sempre. A parte com o painel real
# precisa de um tmux com new-pane -O -C -K; nos outros fica só a conferência do display-popup. Isolado.
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
tt() { "$TT" "$@"; }

# tmux de registro: anota cada display-popup que o tt pede e repassa ao tmux de verdade.
REAL=$(command -v tmux); mkdir -p "$T/binlog"; LOG=$T/popups.log; : >"$LOG"
printf '#!/usr/bin/env bash\n[[ ${1:-} == display-popup ]] && printf "%%s\\n" "$*" >>%q\nexec %q "$@"\n' "$LOG" "$REAL" >"$T/binlog/tmux"
chmod +x "$T/binlog/tmux"; export PATH="$T/binlog:$PATH"

uso=$(tmux list-commands new-pane 2>/dev/null) || uso=""
SUPORTA=0; [[ $uso =~ \[-([A-Za-z]+)\] && ${BASH_REMATCH[1]} == *O* && ${BASH_REMATCH[1]} == *C* && ${BASH_REMATCH[1]} == *K* ]] && SUPORTA=1

tmux -f "$HOME/.tmux.conf" new -d -s trabalho -x 100 -y 34 'echo SESSAO; sleep 600'
tmux new -d -s outra -x 100 -y 34 'sleep 600'
anexar cli 100 34 trabalho; sleep 2.5
c=$(tmux list-clients -F '#{client_name}' | head -1); [[ -n $c ]] || falhou 'o cliente de teste não anexou'
p=$(tmux display -p -t trabalho: '#{pane_id}')
flt() { tmux list-panes -a -F '#{pane_floating_flag}' | grep -c '^1$' || true; }
clica() { fora send-keys -t cli -l "$(printf '\033[<0;%s;%sM\033[<0;%s;%sm' "$1" "$2" "$1" "$2")"; sleep 0.9; }
fecha_tudo() { tmux list-panes -a -F '#{pane_floating_flag} #{pane_id}' | awk '$1 == 1 { print $2 }' | while read -r x; do tmux kill-pane -t "$x"; done
  tmux display-popup -C -c "$c" 2>/dev/null || true; sleep 0.3; }

# 1) desligado (padrão): tudo continua display-popup, com as opções que o código pediu
: >"$LOG"
( tt --popup -c "$c" -E -w 60 -h 10 -T ' fixo ' 'sleep 3' & ); sleep 1.5
[[ $(flt) == 0 ]] || falhou 'desligado, a janela não pode ser um painel flutuante'
grep -q -- "display-popup -c $c -E -w 60 -h 10 -T  fixo  sleep 3" "$LOG" || falhou "desligado deveria repassar as opções ao display-popup: $(cat "$LOG")"
fecha_tudo
passou 'desligado: tt --popup é o display-popup de sempre, com as mesmas opções'

if ((!SUPORTA)); then
  # tmux sem painel modal: ligar não quebra nada e o popup segue
  tt --flutuante on >/dev/null; : >"$LOG"
  ( tt --popup -c "$c" -E -w 60 -h 10 -T ' x ' 'sleep 3' & ); sleep 1.5
  grep -q 'display-popup' "$LOG" || falhou 'sem new-pane -O, ligar deveria deixar o display-popup'
  fecha_tudo
  passou 'tmux sem painel modal: ligado, o popup segue como display-popup'
  echo "pulado: este tmux ($(tmux -V)) não tem new-pane -O -C -K; a parte do painel real não roda aqui"
  echo "TODOS OS TESTES PASSARAM"; exit 0
fi
tt --flutuante on >/dev/null

# 2) ligado: geometria, título, ambiente, clicar fora e retorno de quem chamou
geo() { tmux list-panes -a -F '#{pane_floating_flag} #{pane_left} #{pane_top} #{pane_width} #{pane_height} #{window_width} #{window_height}' | awk '$1 == 1 { print $2, $3, $4, $5, $6, $7 }'; }
: >"$LOG"; rm -f "$T/env.out" "$T/volta"
( tt --popup -c "$c" -E -x 10 -y S -w 40 -h 8 -T ' meu titulo ' -b rounded -S 'fg=#89b4fa' \
    "echo \"cli=\$TT_CLIENTE janela=\$TT_EM_JANELA\" >$T/env.out; sleep 30"; echo "rc=$?" >"$T/volta" ) &
sleep 2
[[ $(flt) == 1 ]] || falhou "ligado, a janela deveria ser um painel flutuante (há $(flt))"
[[ ! -s $LOG ]] || falhou "ligado não deveria chamar display-popup: $(cat "$LOG")"
read -r pl pt pw ph ww wh <<<"$(geo)"
((pw == 38 && ph == 6)) || falhou "tamanho do conteúdo: ${pw}x${ph} (esperado 38x6 = 40x8 menos a borda)"
((pl == 11)) || falhou "esquerda do conteúdo $pl (esperado 11 = x 10 + borda)"
((pt + ph + 1 == wh)) || falhou "-y S deveria encostar na barra de status (topo $pt + altura $ph + borda, janela $wh)"
t=$(tmux list-panes -a -F '#{pane_floating_flag} #{pane_title}' | awk '$1 == 1 { $1 = ""; print }')
[[ $t == *"meu titulo"* ]] || falhou "o título deveria ser o do -T: '$t'"
[[ $(tmux display-message -p -t trabalho: '#{pane-border-status}') == top-floating ]] || falhou 'a borda deveria mostrar o título só do flutuante (top-floating)'
tela=$(fora capture-pane -p -t cli:); grep -q 'meu titulo' <<<"$tela" || falhou "o título não aparece na tela: $tela"
for _ in $(seq 1 20); do [[ -s $T/env.out ]] && break; sleep 0.2; done
[[ $(cat "$T/env.out") == "cli=$c janela=1" ]] || falhou "ambiente do comando: $(cat "$T/env.out" 2>/dev/null)"
clica 3 3
[[ $(flt) == 0 ]] || falhou 'clicar fora deveria fechar a janela'
for _ in $(seq 1 20); do [[ -s $T/volta ]] && break; sleep 0.2; done
[[ -s $T/volta ]] || falhou 'quem chamou deveria voltar quando a janela fecha (como o display-popup)'
[[ $(tmux display-message -p -t trabalho: '#{pane-border-status}') == off ]] || falhou 'fechada a janela, a borda deveria voltar a off'
passou 'ligado: painel flutuante com geometria, título, ambiente certos; clicar fora fecha e devolve o controle'

# 3) sem -x/-y centraliza, 100% ocupa a janela, e o painel de baixo não perde linha
base=$(tmux display -p -t "$p" '#{pane_height}')
( tt --popup -c "$c" -E -w 50% -h 50% 'sleep 30' & ); sleep 2
read -r pl pt pw ph ww wh <<<"$(geo)"
((pw == 48 && pl == 26)) || falhou "centralizado 50%: esquerda $pl largura $pw (esperado 26 e 48 em janela de $ww)"
[[ $(tmux display -p -t "$p" '#{pane_height}') == "$base" ]] || falhou 'o painel de baixo mudou de altura com a janela aberta'
fecha_tudo
( tt --popup -c "$c" -E -w 100% -h 100% 'sleep 30' & ); sleep 2
read -r pl pt pw ph ww wh <<<"$(geo)"
((pw == ww - 2 && ph == wh - 2)) || falhou "100% deveria ocupar a janela: ${pw}x${ph} em ${ww}x${wh}"
fecha_tudo
passou 'centralizado, 100% e o painel de baixo não perde linha'

# 4) as janelas do tt de verdade: abrem como flutuantes, com o título, e fecham ao clicar fora
for v in tt painel sessao notifs relogio transferencias copias; do
  ( tt --clique $v "$c" "$p" "$HOME" 20 >/dev/null 2>&1 & ); sleep 3
  [[ $(flt) == 1 ]] || { fecha_tudo; falhou "clique '$v' deveria abrir uma janela flutuante (há $(flt))"; }
  clica 2 2
  [[ $(flt) == 0 ]] || { fecha_tudo; falhou "clicar fora deveria fechar a janela de '$v'"; }
done
: >"$LOG"
( tt --clique sessao "$c" "$p" "$HOME" 20 >/dev/null 2>&1 & ); sleep 3
t=$(tmux list-panes -a -F '#{pane_floating_flag} #{pane_title}' | awk '$1 == 1 { $1 = ""; print }')
[[ $t == *"sessões"* ]] || falhou "título do seletor: '$t'"
fora send-keys -t cli Escape; sleep 1.5
[[ $(flt) == 0 ]] || falhou 'Esc no seletor deveria fechar a janela'
( tt --clique sessao "$c" "$p" "$HOME" 20 >/dev/null 2>&1 & ); sleep 3
fora send-keys -t cli -l 'outra'; sleep 0.8; fora send-keys -t cli Enter; sleep 2
[[ $(tmux list-clients -F '#{session_name}') == outra ]] || falhou "escolher a sessão deveria trocar a tela do cliente (está em $(tmux list-clients -F '#{session_name}'))"
[[ $(flt) == 0 ]] || falhou 'escolhida a sessão, a janela deveria fechar'
tmux switch-client -c "$c" -t =trabalho
[[ ! -s $LOG ]] || falhou "as janelas do tt não deveriam usar display-popup: $(cat "$LOG")"
passou 'central, menus, seletor, notificações, agenda, transferências e cópias: flutuantes, com título, fecham ao clicar fora/Esc/escolher'

# 5) já há um modal na janela (o painel de tarefas): outra janela cai no display-popup, sem erro
tt --tarefas "$c"; sleep 2
[[ $(flt) == 1 ]] || falhou 'o painel de tarefas deveria estar aberto como modal'
: >"$LOG"
( tt --popup -c "$c" -E -w 40 -h 8 -T ' por cima ' 'sleep 3' & ); sleep 1.5
[[ $(flt) == 1 ]] || falhou 'com um modal aberto não pode surgir um segundo painel flutuante'
grep -q 'display-popup' "$LOG" || falhou 'com um modal aberto a janela nova deveria cair no display-popup'
fecha_tudo
passou 'com o painel de tarefas aberto, outra janela vira display-popup por cima (sem erro)'

# 6) popups fixos continuam popup mesmo ligado (apt/sudo no meio, navegador)
fixos=$(grep -c 'popup_fixo -c' "$RAIZ/tt")
((fixos >= 4)) || falhou "esperava os 4 popups fixos (pendências ×3, navegador) usando popup_fixo; achei $fixos"
grep -q 'pendências de instalação' <(grep 'popup_fixo' "$RAIZ/tt") || falhou 'o modal das pendências deveria ser popup_fixo'
passou 'pendências (apt/sudo) e navegador seguem como popup fixo'

# 7) o menu oferece o interruptor com o nome novo
grep -q 'Janelas flutuantes (clicar fora fecha)' "$RAIZ/tt" || falhou 'o menu do painel deveria chamar o interruptor de "Janelas flutuantes"'
tt --flutuante off >/dev/null
echo "TODOS OS TESTES PASSARAM"
