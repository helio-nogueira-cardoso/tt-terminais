#!/usr/bin/env bash
# Mestre de obras (fase 1): `tt --listar-tudo --tsv|--para-ia` descreve as sessões sem fechar nada.
# agente vem dos descendentes do pane (o cmd mente em atalho); rascunho distingue texto digitado de
# placeholder esmaecido (SGR 2) e de status do agente; ultima_linha pula rodapé de TUI.
source "$(dirname "$0")/lib.sh"; isolar
T_() { tmux -f /dev/null "$@"; }
mkdir -p "$T/bin"; ln -s "$(command -v sleep)" "$T/bin/claude"
T_ new -d -s shell -x 120 -y 20 'bash --norc'
T_ new -d -s agente -x 120 -y 20 "bash --norc -c '$T/bin/claude 900; exec bash --norc'"
T_ new -d -s rasc -x 120 -y 20 "printf 'resposta real\n› texto nao enviado\n? for shortcuts\n'; exec sleep 900"
T_ new -d -s plac -x 120 -y 20 "printf 'oi\n› \033[2mAsk Codex to do anything\033[0m\n'; exec sleep 900"
T_ new -d -s ocup -x 120 -y 20 "printf '› Kiro is working · Type to steer\n'; exec sleep 900"
T_ new -d -s fixa -x 120 -y 20 'bash --norc'; printf 'teste\tfixa\t\n' >"$XDG_CONFIG_HOME/tt/fixadas"
sleep 1
saida=$(TT_MACHINE=book_hl "$TT" --listar-tudo --tsv)
col() { awk -F'\t' -v s="$1" -v c="$2" 'NR==1 { for (i=1;i<=NF;i++) k[$i]=i; next } $2==s { print $k[c] }' <<<"$saida"; }
[[ $(head -1 <<<"$saida") == $'maquina\tsessao\tanexada\tocioso_s\tjanelas\tcmd_1oplano\tagente\tfixada\tpapel\trascunho\ttitulo\tultima_linha' ]] || falhou "cabeçalho: $(head -1 <<<"$saida")"
[[ $(tail -n +2 <<<"$saida" | awk -F'\t' '{print NF}' | sort -u) == 12 ]] || falhou 'linha sem 12 colunas'
[[ $(col shell maquina) == book-hl ]] || falhou "maquina não normalizada: $(col shell maquina)"
passou 'listar-tudo --tsv: cabeçalho fixo, 12 colunas, máquina normalizada'
[[ $(col agente agente) == claude ]] || falhou "agente nos descendentes: $(col agente agente)"
[[ $(col shell agente) == - ]] || falhou "shell com agente: $(col shell agente)"
[[ $(col fixa fixada) == 1 && $(col shell fixada) == 0 ]] || falhou 'fixada'
passou 'agente pelos descendentes do pane; fixada pela lista'
[[ $(col rasc rascunho) == 1 ]] || falhou "rascunho real: $(col rasc rascunho)"
[[ $(col plac rascunho) == 0 ]] || falhou "placeholder esmaecido: $(col plac rascunho)"
[[ $(col ocup rascunho) == 0 ]] || falhou "status do agente: $(col ocup rascunho)"
[[ $(col shell rascunho) == - ]] || falhou "shell sem prompt: $(col shell rascunho)"
[[ $(col rasc ultima_linha) == 'resposta real' ]] || falhou "ultima_linha: $(col rasc ultima_linha)"
passou 'rascunho (texto/placeholder/status/sem prompt) e ultima_linha sem rodapé'
ia=$("$TT" --listar-tudo --para-ia -n 2)
grep -q '^Regras: NUNCA fechar' <<<"$ia" && grep -q '^## rasc (últimas 2 linhas)' <<<"$ia" || falhou '--para-ia sem regras/trechos'
[[ $(tmux ls -F '#S' | wc -l) == 6 ]] || falhou 'fechou sessão'
passou 'listar-tudo --para-ia: regras + trechos, nada fechado'
