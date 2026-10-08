#!/usr/bin/env bash
# Faixa de notificações (3ª linha, abaixo das fixadas): liga por padrão (status 3) e move 📧/📋/
# relógio/versão para a linha 2; faixa_notif=0 volta ao layout de 2 linhas; tt --notificar põe o
# aviso na faixa, expira sozinho e o histórico lista; lembrete de tarefas e e-mail novo espelham.
source "$(dirname "$0")/lib.sh"; isolar
tmux -f /dev/null new -d -s s1 'sleep 300'
tt() { "$TT" "$@"; }

tt --barras >/dev/null 2>&1
[[ $(tmux show -gqv status) == 4 ]] || falhou "faixa ligada deveria pôr status=4 (régua + faixa) (está $(tmux show -gqv status))"
f=$(tmux show -gqv @barra_faixa)
grep -q '@barra_email' <<<"$f" && grep -q '@barra_tarefas' <<<"$f" ||
  falhou "linha 2 sem os chips esperados: $f"
grep -q '@barra_notifs' <<<"$(tmux show -gqv @barra_notifs_slot)" || falhou "slot central dos avisos nao liga @barra_notifs"
grep -q 'align=centre.*@barra_notifs_slot' "$TT_DIR/tema-tmux.conf" || falhou "tema sem o segmento central do slot"
d=$(tmux show -gqv @barra_faixa_dir)
grep -q '@barra_data' <<<"$d" && grep -q '%H:%M' <<<"$d" && grep -q '@barra_versao' <<<"$d" ||
  falhou "lado direito da linha 2 sem data/hora/versão: $d"
[[ -z $(tmux show -gqv @barra_lado1) ]] || falhou 'com a faixa, a linha das fixadas deveria ficar só para elas'
[[ -z $(tmux show -gqv @barra_fim0) ]] || falhou 'com a faixa, o 📧/relógio deveriam sair da linha 0'
passou 'faixa ligada: status 3, blocos na linha 2, fixadas 100% livres'

TT_FAIXA_LARGURA=140 tt --notificar "📧 Ana — Reunião de sexta" 120 >/dev/null 2>&1
TT_FAIXA_LARGURA=140 tt --barras >/dev/null 2>&1; n=$(tmux show -gqv @barra_notifs)
grep -q 'Ana — Reunião' <<<"$n" || falhou "aviso não entrou na faixa: $n"
grep -q 'range=user|notifs' <<<"$n" || falhou "faixa de avisos sem o range clicável"
grep -q '│' <<<"$n" || falhou "slot sem os delimitadores │ │"
TT_FAIXA_LARGURA=140 tt --notificar "$(printf 'A%.0s' {1..200})" 120 >/dev/null 2>&1
TT_FAIXA_LARGURA=140 tt --barras >/dev/null 2>&1; n=$(tmux show -gqv @barra_notifs)
grep -q '…' <<<"$n" || falhou "aviso comprido não foi truncado pelo orçamento"
[[ ${#n} -lt 300 ]] || falhou "slot estourou o orçamento (len=${#n})"
TT_FAIXA_LARGURA=70 tt --barras >/dev/null 2>&1; n=$(tmux show -gqv @barra_notifs)
grep -q '🔔 [0-9]' <<<"$n" || falhou "janela estreita deveria virar crachá 🔔 N: $n"

# clique com destino: aviso guarda a ação; a mais recente com ação ganha o clique; histórico marca ↗
tt --notificar "📧 com destino" 120 email >/dev/null 2>&1
ult=$(ls -1r "$HOME/.local/state/tt/notifs" | head -1)
[[ $(cut -f3 "$HOME/.local/state/tt/notifs/$ult") == email ]] || falhou 'ação não gravada no aviso'
rg -q 'notifs\) notifs_clique' "$TT" || falhou 'clique na faixa não passa pelo notifs_clique'
rg -q 'email\) botao_email' "$TT" || falhou 'destino email não abre o 📧'
grep -q '↗' <<<"$("$TT" --notifs-ui 2>/dev/null)" || falhou 'histórico não marca avisos com destino (↗)'
passou 'clique nas notificações: 📧 abre o e-mail; histórico com ⏎ nos destinos'

# 🔔 sempre visível (porta do histórico mesmo sem aviso) e ticker: fontes, linha e passo do letreiro
rm -f "$HOME/.local/state/tt/notifs"/*; tt --barras >/dev/null 2>&1
grep -q 'range=user|notifs.* 🔔 ' <<<"$(tmux show -gqv @barra_faixa)" || falhou 'sininho não está ancorado à esquerda (junto aos chips)'
grep -q '@barra_ticker' <<<"$(tmux show -gqv @barra_notifs)" || falhou 'slot vazio não dá lugar ao ticker'
printf 'indicadores=frases
' >>"$XDG_CONFIG_HOME/tt/config"
"$TT" --ticker-fontes >/dev/null 2>&1
[[ -s $HOME/.cache/tt-ticker/frases ]] || falhou 'fonte frases não escreveu cache'
rg -q 'noticias\)' "$TT" && rg -q 'dolar\)' "$TT" || falhou 'fontes dolar/noticias ausentes do motor'
grep -q 'dolar,frases,noticias' "$TT" || falhou 'letreiro não vem ligado de fábrica'
passou 'sininho permanente e ticker: fontes com cache, dolar/frases/noticias no motor'
tt --notificar "📧 Ana — Reunião de sexta" 120 email >/dev/null 2>&1  # o histórico abaixo precisa dele
tt --notificar "⏳ efêmero" 1 >/dev/null 2>&1; sleep 2; tt --barras >/dev/null 2>&1
grep -q 'efêmero' <<<"$(tmux show -gqv @barra_notifs)" && falhou 'aviso expirado continuou na faixa'
grep -q 'Ana — Reunião' <<<"$("$TT" --notifs-ui)" || falhou 'histórico não lista o aviso'
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
[[ $(tmux show -gqv status) == 2 ]] || falhou 'faixa_notif=0 deveria voltar a 2 linhas'
grep -q '@barra_tarefas' <<<"$(tmux show -gqv @barra_lado1)" || falhou 'desligada, 📋/versão deveriam voltar à linha 1'
grep -q '@barra_email' <<<"$(tmux show -gqv @barra_fim0)" || falhou 'desligada, 📧/relógio deveriam voltar à linha 0'
passou 'faixa_notif=0: layout de 2 linhas de volta, sem perder nada'

echo 'ok: faixa de notificações — 3ª linha com 📧/📋/avisos/data/versão, espelho central, desligável'
