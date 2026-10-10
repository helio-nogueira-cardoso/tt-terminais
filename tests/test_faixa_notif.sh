#!/usr/bin/env bash
# Faixa de notificações (3ª linha, abaixo das fixadas): liga por padrão (status 3) e move 📧/📋/
# relógio/versão para a linha 2; faixa_notif=0 volta ao layout sem a faixa (3 linhas); tt --notificar põe o
# aviso na faixa, expira sozinho e o histórico lista; lembrete de tarefas e e-mail novo espelham.
source "$(dirname "$0")/lib.sh"; isolar
tmux -f /dev/null new -d -s s1 'sleep 300'
tt() { "$TT" "$@"; }

tt --barras >/dev/null 2>&1
[[ $(tmux show -gqv status) == 4 ]] || falhou "faixa ligada deveria pôr status=4 (margem + janelas + fixadas + faixa) (está $(tmux show -gqv status))"
f=$(tmux show -gqv @barra_faixa)
grep -q '@barra_email' <<<"$f" && grep -q '@barra_tarefas' <<<"$f" ||
  falhou "linha 2 sem os chips esperados: $f"
grep -q '@barra_notifs' <<<"$(tmux show -gqv @barra_notifs_slot)" || falhou "slot central dos avisos nao liga @barra_notifs"
grep -q 'align=centre.*@barra_notifs_slot' "$TT_DIR/tema-tmux.conf" || falhou "tema sem o segmento central do slot"
d=$(tmux show -gqv @barra_faixa_dir)
grep -q '@barra_data' <<<"$d" && grep -q '@barra_hora' <<<"$d" && grep -q '@barra_versao' <<<"$d" ||
  falhou "lado direito da linha 2 sem data/hora/versão: $d"
[[ $(tmux show -gqv @barra_hora) == '%H:%M' ]] || falhou "sem desvio medido, @barra_hora deveria ser o %H:%M do tmux (veio '$(tmux show -gqv @barra_hora)')"
# Estreito: o letreiro tem prioridade — o dia some abaixo de 120 colunas e a versão abaixo de 90.
grep -q 'e|<:#{client_width},120},,#{E:@barra_data}' <<<"$d" && grep -q 'e|<:#{client_width},90},, #{E:@barra_versao}' <<<"$d" ||
  falhou "lado direito da faixa não encolhe em terminal estreito: $d"
[[ -z $(tmux show -gqv @barra_lado1) ]] || falhou 'com a faixa, a linha das fixadas deveria ficar só para elas'
[[ -z $(tmux show -gqv @barra_fim0) ]] || falhou 'com a faixa, o 📧/relógio deveriam sair da linha 0'
passou 'faixa ligada: status 3, blocos na linha 2, fixadas 100% livres'
# Layout: 3 a 4 linhas coladas — margem, janelas, fixadas e faixa — SEM réguas: as faixas se distinguem só
# pelo fundo levemente diferente; cada linha é pintada em toda a largura (fill) e o #[default] volta ao
# fundo DELA (set-default).
tema="$TT_DIR/tema-tmux.conf"
fmt() { grep "^set -g 'status-format\\[$1\\]'" "$tema"; }
[[ -z $(fmt 4) ]] || falhou 'barra com mais de 4 linhas'
[[ $(fmt 0) == *'fill=#1e1e2e'* && $(fmt 0) != *─* ]] || falhou 'linha 0 deveria ser a margem vazia preenchida'
grep -q 'range=left' <<<"$(fmt 1)" || falhou 'linha 1 não é a das janelas'
l=$(fmt 2); grep -q 'fill=#181825' <<<"$l" && grep -q 'set-default' <<<"$l" || falhou "linha 2 (fixadas) sem fill/set-default: ${l:0:120}"
l=$(fmt 3); grep -q 'fill=#232838' <<<"$l" && grep -q 'set-default' <<<"$l" && grep -q 'barra_faixa_dir' <<<"$l" || falhou "linha 3 (faixa) sem fill/set-default: ${l:0:120}"
! grep -q '▁▁▁\|▔▔▔\|───\|usstyle\|underscore' "$tema" "$TT_DIR/tmux.conf" || falhou 'a barra não leva réguas nem sublinhado'
passou 'barra: linhas coladas e preenchidas, sem réguas (só o fundo distingue as faixas)'


# O miolo da faixa (aviso fresco / transferência / letreiro) é o letreiro-tt.py de cada cliente, ligado
# como #() em @barra_notifs: quadro N imprime o que ele mostraria num terminal de N colunas.
quadro() { python3 -I "$TT_DIR/letreiro-tt.py" quadro "$@"; }
tt --notificar "📧 Ana — Reunião de sexta" 120 >/dev/null 2>&1
n=$(quadro 140)
grep -q 'Ana — Reunião' <<<"$n" || falhou "aviso fresco não entrou no slot: $n"
grep -q 'range=user|notifx' <<<"$n" || falhou "faixa de avisos sem o range clicável (notifx)"
grep -q '│' <<<"$n" || falhou "slot sem os delimitadores │ │"
grep -q '#\[bold\]' <<<"$n" || falhou "aviso fresco deveria estar em negrito"
grep -q 'letreiro-tt.py fluxo' <<<"$(tmux show -gqv @barra_notifs)" || falhou 'o slot deve seguir ligado ao letreiro (quem alterna aviso/letreiro é ele, sem gravar opções)'
tt --notificar "$(printf 'A%.0s' {1..200})" 120 >/dev/null 2>&1
n=$(quadro 140)
grep -q '…' <<<"$n" || falhou "aviso comprido não foi truncado pelo orçamento"
[[ ${#n} -lt 300 ]] || falhou "slot estourou o orçamento (len=${#n})"
n=$(quadro 70)
[[ -z $n ]] || falhou "estreito (< 90) deve deixar o miolo vazio — o sino com o contador conta a história: $n"
tt --barras >/dev/null 2>&1
grep -q "notifs_n" <<<"$(tmux show -gqv @barra_faixa)" || falhou "contador do sino ausente do segmento esquerdo"

# clique com destino: aviso guarda a ação; a mais recente com ação ganha o clique; histórico marca ↗
tt --notificar "📧 com destino" 120 email >/dev/null 2>&1
ult=$(ls -1r "$HOME/.local/state/tt/notifs" | head -1)
[[ $(cut -f3 "$HOME/.local/state/tt/notifs/$ult") == email ]] || falhou 'ação não gravada no aviso'
rg -q 'notifs\) notifs_popup' "$TT" || falhou 'sino não abre sempre a central'
rg -q 'notifx\) notifs_clique' "$TT" || falhou 'texto do aviso não abre o destino (range notifx)' 
rg -q 'email\) botao_email' "$TT" || falhou 'destino email não abre o 📧'
grep -q '↗' <<<"$("$TT" --notifs-ui 2>/dev/null)" || falhou 'histórico não marca avisos com destino (↗)'
passou 'clique nas notificações: 📧 abre o e-mail; histórico com ⏎ nos destinos'

# 🔔 sempre visível (porta do histórico mesmo sem aviso) e ticker: fontes, linha e passo do letreiro
rm -f "$HOME/.local/state/tt/notifs"/*; tt --barras >/dev/null 2>&1
grep -q 'range=user|notifs.* 🔔' <<<"$(tmux show -gqv @barra_faixa)" || falhou 'sininho não está ancorado à esquerda (junto aos chips)'
grep -q 'letreiro-tt.py fluxo #{client_tty} #{client_pid}' <<<"$(tmux show -gqv @barra_notifs)" || falhou 'slot central não liga o letreiro por #() (letreiro-tt.py fluxo)'
printf 'indicadores=frases
' >>"$XDG_CONFIG_HOME/tt/config"
"$TT" --ticker-fontes >/dev/null 2>&1
[[ -s $HOME/.cache/tt-ticker/frases ]] || falhou 'fonte frases não escreveu cache'
grep -qF "$(cut -c1-12 "$HOME/.cache/tt-ticker/frases")" <<<"$(quadro 140)" || falhou "slot sem aviso não mostra o letreiro (frase da fonte): $(quadro 140)"
grep -q 'A%' <<<"$(quadro 140)" && falhou 'aviso já expirado/lido não deveria estar no slot'
rg -q 'noticias\)' "$TT" && rg -q 'dolar\)' "$TT" || falhou 'fontes dolar/noticias ausentes do motor'
grep -q 'dolar,frases,noticias' "$TT" || falhou 'letreiro não vem ligado de fábrica'
passou 'sininho permanente e ticker: fontes com cache, dolar/frases/noticias no motor'
tt --notificar "📧 Ana — Reunião de sexta" 120 email >/dev/null 2>&1  # o histórico abaixo precisa dele
tt --notificar "⏳ efêmero" 1 >/dev/null 2>&1; sleep 2; tt --barras >/dev/null 2>&1
grep -q 'efêmero' <<<"$(quadro 140)" && falhou "aviso expirado continuou no slot"
grep -q 'Ana — Reunião' <<<"$("$TT" --notifs-ui)" || falhou 'histórico não lista o aviso'
# a central diz o DIA, não só a hora: "Hoje", "Ontem" ou dd/mm (hoje e ontem se distinguem)
hist=$("$TT" --notifs-ui | sed "s/\x1b\[[0-9;]*m//g")
grep -qE '^Hoje  [0-9]{2}:[0-9]{2}  .*Ana — Reunião' <<<"$hist" || falhou "aviso novo deveria sair como 'Hoje HH:MM': $hist"
nd="$HOME/.local/state/tt/notifs"
printf '%s\t%s\t\n' "$(( $(date +%s) + 600 ))" "aviso de ontem" >"$nd/$(date -d 'yesterday 22:05' +%s)000000000"
printf '%s\t%s\t\n' "$(( $(date +%s) + 600 ))" "aviso antigo" >"$nd/$(date -d '5 days ago 09:30' +%s)000000000"
hist=$("$TT" --notifs-ui | sed "s/\x1b\[[0-9;]*m//g")
grep -qE '^Ontem 22:05  aviso de ontem' <<<"$hist" || falhou "aviso de ontem deveria sair como 'Ontem 22:05': $hist"
grep -qE '^[0-9]{2}/[0-9]{2} 09:30  aviso antigo' <<<"$hist" || falhou "aviso antigo deveria sair como dd/mm HH:MM: $hist"
passou 'notificar: aparece com range, expira sozinho, histórico lista'

# espelho automático: o notificador central alimenta a faixa — ponta a ponta com um lembrete real
rm -f "$HOME/.local/state/tt/notifs"/*
tt --tarefa-add-natural "Pagar aluguel @hoje" >/dev/null 2>&1
tt --tarefas-lembrete >/dev/null 2>&1
grep -q 'Pagar aluguel' <<<"$(cat "$HOME/.local/state/tt/notifs"/* 2>/dev/null)" || falhou 'lembrete de tarefa não espelhou na faixa'
rg -q 'notificar "\$t · \$c"' "$TT" || falhou 'tarefas_notificar sem o espelho para a faixa (contrato)'
passou 'lembretes (tarefas/e-mail) espelham na faixa pelo notificador central'

printf 'faixa_notif=0\n' >>"$XDG_CONFIG_HOME/tt/config"
tt --barras >/dev/null 2>&1
[[ $(tmux show -gqv status) == 3 ]] || falhou 'faixa_notif=0 deveria voltar a 3 linhas (margem, janelas, fixadas)'
grep -q '@barra_tarefas' <<<"$(tmux show -gqv @barra_lado1)" || falhou 'desligada, 📋/versão deveriam voltar à linha 1'
grep -q '@barra_email' <<<"$(tmux show -gqv @barra_fim0)" || falhou 'desligada, 📧/relógio deveriam voltar à linha 0'
passou 'faixa_notif=0: layout sem a faixa de volta, sem perder nada'

rg -qF "pkill -f 'tt --ticker-loop$'" "$TT" || falhou 'instalador não mata o laço antigo do letreiro (ficava rodando com código velho)'
rg -q -- '--ticker-loop\) exit 0' "$TT" || falhou '--ticker-loop deve ser um no-op de compatibilidade (o vigia antigo ainda o chama durante a troca de versão)'
grep -qE 'subprocess|os\.system|popen|os\.exec' "$TT_DIR/letreiro-tt.py" && falhou 'letreiro-tt.py não pode lançar processos nem falar com o tmux (cada set-option redesenha tudo)'
echo 'ok: faixa de notificações — 3ª linha com 📧/📋/avisos/data/versão, espelho central, desligável'
