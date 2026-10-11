#!/usr/bin/env bash
# Sessões "_nome" são ocultas (infraestrutura: _tt-email, _tt-vigia…): fora da central, do seletor, da
# poda de vazias/paradas e do vigia, mesmo sem a marca @ponte. E o painel flutuante (tmux 3.7+) não conta
# como divisão da janela: abrir o painel de tarefas não liga a barrinha de título nem encolhe o painel de
# baixo. Isola HOME/XDG/TT_RT e o tmux; a parte do painel flutuante é pulada em tmux sem new-pane.
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
tt() { "$TT" "$@"; }

tmux -f "$HOME/.tmux.conf" new -d -s visivel -x 120 -y 40 'sleep 600'
# Sessões "vazias" (só um shell parado) escondidas e comuns: a poda só pode levar a comum.
tmux new -d -s _oculta -x 120 -y 40 bash
tmux new -d -s comum -x 120 -y 40 bash
sleep 1

# 1) nenhuma listagem mostra a oculta
for v in --listar --listar-leve --lista-rapida-central; do
  saida=$(timeout 20 "$TT" $v </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
  grep -q '_oculta' <<<"$saida" && falhou "tt $v mostrou a sessão _oculta: $saida"
  grep -q 'visivel' <<<"$saida" || falhou "tt $v deveria listar a sessão visível: $saida"
done
tsv=$(timeout 20 "$TT" --listar-tudo --tsv </dev/null 2>&1)
grep -q '_oculta' <<<"$tsv" && falhou "--listar-tudo --tsv mostrou a sessão _oculta (entraria na poda do mestre de obras)"
passou 'sessão _nome fica fora da central, do seletor e do mestre de obras'

# 2) a poda de vazias leva a comum e poupa a oculta
n=$(tt --fechar-vazias)
tmux has-session -t =_oculta 2>/dev/null || falhou "--fechar-vazias fechou a sessão oculta _oculta"
tmux has-session -t =comum 2>/dev/null && falhou "--fechar-vazias deveria fechar a sessão vazia comum (fechou $n)"
passou 'a poda de vazias poupa a sessão _nome'

# 3) o vigia não renomeia nem fecha a oculta: mesmo código do loop, conferido no fonte
grep -qF 'Sessões "_nome" são ocultas de propósito (infraestrutura): ninguém as renomeia.' "$RAIZ/tt" &&
  grep -qF '[[ -n $ponte || $s == _* ]] && continue' "$RAIZ/tt" || falhou 'o vigia deveria pular sessões _nome ao renomear'
passou 'o vigia pula sessões _nome ao renomear'

# 4) painel flutuante não liga a barrinha de título
uso=$(tmux list-commands new-pane 2>/dev/null) || uso=""
if [[ $uso =~ \[-([A-Za-z]+)\] && ${BASH_REMATCH[1]} == *O* ]]; then
  tmux new -d -s janela -x 120 -y 40 'sleep 600'
  w=$(tmux display -p -t =janela: '#{window_id}')
  bs() { tmux display-message -p -t "$w" '#{pane-border-status}'; }
  tt --bordas; [[ $(bs) == off ]] || falhou "com 1 painel a barrinha deveria estar desligada (está $(bs))"
  alt0=$(tmux list-panes -t "$w" -F '#{pane_floating_flag} #{pane_height}' | awk '$1 == 0 { print $2 }')
  tmux new-pane -d -t "=janela:" -O -C -K 'sleep 600'; sleep 0.5
  [[ $(tmux list-panes -t "$w" -F '#{pane_floating_flag}' | grep -c '^1$') == 1 ]] || falhou 'o painel flutuante de teste não abriu'
  tt --bordas
  # só o flutuante ganha a linha de título (top-floating); o painel dividido não perde linha
  [[ $(bs) == top-floating ]] || falhou "painel flutuante contou como divisão: barrinha ficou '$(bs)' (esperado top-floating)"
  [[ $(tmux list-panes -t "$w" -F '#{pane_floating_flag} #{pane_height}' | awk '$1 == 0 { print $2 }') == "$alt0" ]] || falhou 'o painel dividido mudou de altura com o flutuante aberto'
  tmux kill-pane -t "$(tmux list-panes -t "$w" -F '#{pane_floating_flag} #{pane_id}' | awk '$1 == 1 { print $2 }')"
  tt --bordas; [[ $(bs) == off ]] || falhou "fechado o flutuante a barrinha deveria voltar a off (está $(bs))"
  tmux split-window -d -t "=janela:" 'sleep 600'; sleep 0.3
  tt --bordas; [[ $(bs) == top ]] || falhou "com 2 painéis divididos a barrinha deveria ligar (está $(bs))"
  passou 'painel flutuante não conta como divisão da janela (barrinha só com 2+ painéis divididos)'
else
  echo "pulado: este tmux ($(tmux -V)) não tem painel flutuante (new-pane -O)"
fi
echo "TODOS OS TESTES PASSARAM"
