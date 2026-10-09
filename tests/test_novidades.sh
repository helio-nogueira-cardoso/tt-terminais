#!/usr/bin/env bash
# Novidades do tt: mostra só o que saiu depois da última versão vista, --todas mostra tudo, o vigia
# avisa uma vez por versão nova (sem avisar máquina recém-instalada), e o clique no aviso do agente
# vai ao painel mesmo com a sessão renomeada.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado; TT=$HOME/.local/bin/tt
ES=$HOME/.local/state/tt
cat >"$TT_DIR/NOVIDADES.md" <<'N'
# Novidades
## v1.5.12 · 01/01/2099
- coisa nova C
## v1.5.11 · 01/01/2099
- coisa nova B
## v1.5.10 · 01/01/2099
- coisa velha A
N
echo "12 teste 2099-01-01" >"$TT_DIR/VERSAO"
echo 10 >"$(mkdir -p "$ES"; echo "$ES/novidades-visto")"
saida=$("$TT" --novidades)
grep -q 'coisa nova C' <<<"$saida" && grep -q 'coisa nova B' <<<"$saida" || falhou "faltou novidade: $saida"
grep -q 'coisa velha A' <<<"$saida" && falhou 'mostrou o que já foi visto'
[[ $(cat "$ES/novidades-visto") == 12 ]] || falhou 'não marcou como visto'
passou 'mostra só o que saiu depois da última versão vista, e marca como visto'
saida=$("$TT" --novidades --todas); grep -q 'coisa velha A' <<<"$saida" || falhou '--todas deveria mostrar tudo'
passou '--todas mostra tudo'

# Vigia: versão nova → um aviso (ação novidades); repetido na mesma versão → nada.
rm -rf "$ES/notifs" "$ES/novidades-avisada"; echo 10 >"$ES/novidades-visto"
"$TT" --novidades-avisar; "$TT" --novidades-avisar
n=$(grep -l 'novidades$' "$ES"/notifs/* 2>/dev/null | wc -l); ((n == 1)) || falhou "esperava 1 aviso, vi $n"
# Máquina recém-instalada (sem registro do que foi visto): não avisa.
rm -rf "$ES/notifs" "$ES/novidades-avisada" "$ES/novidades-visto"; "$TT" --novidades-avisar
[[ -z $(ls "$ES/notifs" 2>/dev/null) ]] || falhou 'avisou numa máquina recém-instalada'
[[ $(cat "$ES/novidades-visto") == 12 ]] || falhou 'recém-instalada deveria marcar a versão atual'
passou 'vigia avisa uma vez por versão nova; instalação nova não é incomodada'

# Clique do agente: vale o nome ATUAL da sessão do painel.
tmux -f /dev/null new -d -s antigo -x 120 -y 30 'sleep 300'; tmux new -d -s outra 'sleep 300'
anexar cli 120 30 outra; sleep 1.2
c=$(tmux list-clients -F "#{client_name}" | head -1); p=$(tmux list-panes -t antigo -F '#{pane_id}')
tmux rename-session -t antigo novo
TMUX="$(tmux display -p "#{socket_path}"),1,0" "$TT" --notif-abrir "sessao:antigo|$p" "$c"; sleep 0.7
[[ $(tmux list-clients -F '#{client_session}' | head -1) == novo ]] || falhou "não foi à sessão renomeada: $(tmux list-clients -F '#{client_session}')"
passou 'o clique do aviso do agente acha a sessão renomeada pelo id do painel'
echo "TODOS OS TESTES PASSARAM"
