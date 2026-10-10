#!/usr/bin/env bash
# Painel de tarefas flutuante (tmux 3.8+, new-pane -O -C): desligado por padrão e igual a hoje (popup, só
# na tela que clicou); ligado, abre como painel modal à direita que fecha ao clicar fora, o 📋 de novo o
# fecha, e clicar dentro não fecha. Onde o tmux não sabe (3.5a, 3.6), ligar não quebra nada: o rótulo
# avisa e o painel segue como popup. A parte com o tmux real usa o do sistema se ele suportar, ou o que
# TT_TMUX_38 apontar; sem nenhum dos dois, é pulada. Isola HOME/XDG/TT_RT e o tmux.
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
tt() { "$TT" "$@"; }

suporta() { # binário -> 0 se o new-pane dele aceita -O -C -K
  local uso; uso=$("$1" -L "chk-$$" -f /dev/null list-commands new-pane 2>/dev/null) || return 1
  [[ $uso =~ \[-([A-Za-z]+)\] && ${BASH_REMATCH[1]} == *O* && ${BASH_REMATCH[1]} == *C* && ${BASH_REMATCH[1]} == *K* ]]
}
BIN38=""
for b in "$(command -v tmux)" "${TT_TMUX_38:-}"; do
  [[ -n $b && -x $b ]] && suporta "$b" && { BIN38=$b; break; }
done

# 1) padrão desligado; alternar liga e desliga; o rótulo diz a verdade sobre o tmux desta máquina
[[ $(conf_valor=$(grep -c '^painel_flutuante=' "$XDG_CONFIG_HOME/tt/config" || true); echo "$conf_valor") == 0 ]] || falhou "o padrão não pode gravar painel_flutuante"
saida=$(tt --flutuante); grep -q 'desligado' <<<"$saida" || falhou "padrão deveria ser desligado: $saida"
saida=$(tt --flutuante on); grep -q '^🪟 painel flutuante: ligado' <<<"$saida" || falhou "on deveria ligar: $saida"
grep -q '^painel_flutuante=1$' "$XDG_CONFIG_HOME/tt/config" || falhou "on deveria gravar painel_flutuante=1 no config"
saida=$(tt --flutuante alternar); grep -q 'desligado' <<<"$saida" || falhou "alternar de ligado deveria desligar: $saida"
saida=$(tt --flutuante alternar); grep -q 'ligado' <<<"$saida" || falhou "alternar de desligado deveria ligar: $saida"
[[ $(grep -c '^painel_flutuante=' "$XDG_CONFIG_HOME/tt/config") == 1 ]] || falhou "o config não pode acumular linhas painel_flutuante"
tt --flutuante xyz >/dev/null 2>&1 && falhou "argumento inválido deveria falhar"
if suporta "$(command -v tmux)"; then
  grep -q 'fecha ao clicar fora' <<<"$(tt --flutuante status)" || falhou "com tmux 3.8 o rótulo deveria dizer que fecha ao clicar fora"
else
  grep -q 'precisa ser 3.8+' <<<"$(tt --flutuante status)" || falhou "sem tmux 3.8 o rótulo deveria avisar que precisa ser 3.8+: $(tt --flutuante status)"
fi
tt --flutuante off >/dev/null
passou "painel flutuante: padrão desligado, alternar grava uma linha só e o rótulo diz a verdade"

# 2) o item do menu ⋯ do painel está ligado ao verbo
grep -q -- '--flutuante alternar' "$TT" && grep -q 'Painel de tarefas flutuante' "$TT" || falhou "o menu do painel não tem o item do painel flutuante"
passou "menu ⋯ do painel tem o toggle 🪟"

if [[ -z $BIN38 ]]; then
  echo "pulado: nenhum tmux 3.8+ (new-pane -O -C) — defina TT_TMUX_38 para testar o painel real"
  echo "TODOS OS TESTES PASSARAM"; exit 0
fi

# 3) com o tmux real: abre modal à direita, altura toda; 📋 de novo fecha; clicar dentro mantém; fora fecha
mkdir -p "$T/bin38"; ln -sf "$BIN38" "$T/bin38/tmux"; export PATH="$T/bin38:$PATH"
tmux -f "$HOME/.tmux.conf" new -d -s s -x 120 -y 40 'sleep 600'
tmux split-window -h -t s 'sleep 600'
anexar cli 120 40 s; sleep 2
c=$(tmux list-clients -F '#{client_name}' | head -1); [[ -n $c ]] || falhou "o cliente de teste não anexou"
flt() { tmux list-panes -a -F '#{pane_floating_flag}' | grep -c '^1$' || true; }
tt --flutuante on >/dev/null

tt --tarefas "$c"; sleep 1
[[ $(flt) == 1 ]] || falhou "ligado, o painel deveria abrir como floating pane (há $(flt))"
geo=$(tmux list-panes -a -F '#{pane_floating_flag} #{pane_left} #{pane_top} #{pane_width} #{pane_height} #{window_width} #{window_height}' | awk '$1 == 1 { print }')
read -r _ pl pt pw ph ww wh <<<"$geo"
((pl + pw + 1 == ww)) || falhou "o painel deveria encostar na borda direita (esquerda=$pl largura=$pw janela=$ww)"
((pt == 1 && ph + 2 == wh)) || falhou "o painel deveria ter a altura toda da janela (topo=$pt altura=$ph janela=$wh)"
fp=$(tmux list-panes -a -F '#{pane_floating_flag} #{pane_id}' | awk '$1 == 1 { print $2 }')
ok=0; for _ in $(seq 1 20); do grep -q 'Hoje' <<<"$(tmux capture-pane -p -t "$fp" 2>/dev/null)" && { ok=1; break; }; sleep 0.25; done
((ok)) || falhou "a UI de tarefas não apareceu dentro do painel: $(tmux capture-pane -p -t "$fp" | head -5)"
passou "ligado, abre como painel modal à direita (altura toda) com a UI de tarefas dentro"

tt --tarefas "$c"; sleep 0.5
[[ $(flt) == 0 ]] || falhou "chamar de novo (tt --tarefas) deveria fechar o painel"
passou "tt --tarefas de novo fecha o painel"

# Teclado dentro do painel (como no popup): ? abre a ajuda, Esc volta, Esc na lista fecha o painel.
tt --tarefas "$c"; sleep 1
fp=$(tmux list-panes -a -F '#{pane_floating_flag} #{pane_id}' | awk '$1 == 1 { print $2 }')
tmux send-keys -t "$fp" '?'; sleep 0.8
grep -q 'Como usar' <<<"$(tmux capture-pane -p -t "$fp")" || falhou "? não abriu a ajuda dentro do painel"
tmux send-keys -t "$fp" Escape; sleep 0.8
grep -q 'Hoje' <<<"$(tmux capture-pane -p -t "$fp")" && [[ $(flt) == 1 ]] || falhou "Esc na ajuda deveria voltar à lista sem fechar o painel"
tmux send-keys -t "$fp" Escape; sleep 1.2
[[ $(flt) == 0 ]] || falhou "Esc na lista deveria fechar o painel"
passou "teclado: ? abre a ajuda, Esc volta, Esc na lista fecha o painel"

clica() { # x y — aperta e solta no mesmo send-keys
  fora send-keys -t cli -l "$(printf '\033[<0;%s;%sM\033[<0;%s;%sm' "$1" "$2" "$1" "$2")"; sleep 0.8
}
tt --tarefas "$c"; sleep 1
[[ $(flt) == 1 ]] || falhou "o painel não reabriu"
clica 100 12
[[ $(flt) == 1 ]] || falhou "clicar DENTRO do painel não pode fechá-lo"
clica 5 12
[[ $(flt) == 0 ]] || falhou "clicar FORA do painel deveria fechá-lo"
passou "clicar dentro mantém; clicar fora fecha"

# 4) desligado: nada de floating pane (volta ao popup de sempre)
tt --flutuante off >/dev/null
( timeout 4 "$TT" --tarefas "$c" >/dev/null 2>&1 & ); sleep 1.5
[[ $(flt) == 0 ]] || falhou "desligado, o painel não pode ser floating pane"
tmux display-popup -C -c "$c" 2>/dev/null || true
passou "desligado, o painel segue como popup (nenhum floating pane)"
echo "TODOS OS TESTES PASSARAM"
