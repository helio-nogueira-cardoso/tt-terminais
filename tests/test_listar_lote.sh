#!/usr/bin/env bash
# tt-teste: sozinho (mede tempo: roda sem outros testes disputando a máquina)
# Listas de sessões em lote (tt --listar, --listar-leve, --listar-tudo --tsv): duas idas ao tmux para
# sessões e painéis, nenhuma por painel (display-message, list-panes -s), as telas lidas em paralelo.
# Com o servidor do tmux ocupado (uma IA despejando a tela), cada ida esperava a fila; em fila, a lista
# da central chegava a levar 20 s. Também: o separador 0x1F não quebra rótulo com "|".
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin" "$T/log"
real=$(command -v tmux)
# tmux que registra cada chamada; com TT_LENTO=S, cada capture-pane demora S segundos (servidor ocupado)
cat >"$T/bin/tmux" <<EOF
#!/bin/sh
echo "\$*" >>"$T/log/\${TT_CONTA:-geral}"
case "\$1" in capture-pane) [ -n "\${TT_LENTO:-}" ] && sleep "\$TT_LENTO" ;; esac
exec $real "\$@"
EOF
chmod +x "$T/bin/tmux"
export PATH="$T/bin:$PATH"
nova() { tmux new -d -s "$1" -x 120 -y 30 "${@:2}"; }
nova alfa 'bash --norc --noprofile'; tmux send-keys -t alfa 'echo um; echo dois; echo tres; echo quatro' Enter
nova beta 'sleep 3600'; tmux split-window -t beta 'sleep 3601'; tmux split-window -t beta 'bash --norc --noprofile'
tmux set -p -t beta.0 @nome_painel 'painel um'; tmux set -p -t beta.1 @tt_rotulo 'rot|ulo'
tmux select-pane -t beta.1 -T 'titulo do painel'
nova vazia1 'bash --norc --noprofile'; nova vazia2 'bash --norc --noprofile'
nova _oculta 'sleep 3600'; nova ponte-x 'sleep 3600'; tmux set -t ponte-x @ponte 'outra:x'
nova 'gama dois' 'bash --norc --noprofile' # como na vida real: o Claude roda num shell interativo
printf -v comando 'bash -c %q' "$(exec_como claude sleep 3600)"
tmux send-keys -t 'gama dois' "$comando" Enter
pai=$(tmux display -p -t 'gama dois' '#{pane_pid}')
pid=""
for _ in {1..50}; do pid=$(pgrep -P "$pai" -x claude) && break; sleep 0.1; done
[[ $pid =~ ^[0-9]+$ ]] || falhou 'processo Claude simulado não iniciou'
mkdir -p "$HOME/.claude/sessions" "$HOME/.claude/projects/-tmp"
printf '{"pid":%s,"sessionId":"abc-123","status":"idle","name":"conversa"}\n' "$pid" >"$HOME/.claude/sessions/$pid.json"
printf '{"type":"user"}\n{"type":"ai-title","aiTitle":"Titulo da conversa falsa"}\n' >"$HOME/.claude/projects/-tmp/abc-123.jsonl"
sleep 1.5
limpa() { sed 's/\x1b\[[0-9;]*m//g'; }

# 1) --listar: linhas, ordem dos painéis, vazias no fim, oculta e ponte fora, busca com título e nomes
mapfile -t PB < <(tmux list-panes -t beta -F '#{pane_id}')
out=$(TT_CONTA=listar "$TT" --listar 2>"$T/err"); [[ -s $T/err ]] && falhou "stderr: $(head -3 "$T/err")"
chaves=$(cut -f1 <<<"$out" | sort | paste -sd' ')
[[ $chaves == "$(printf '%s\n' '!vazias' "${PB[@]}" alfa beta 'gama dois' vazia1 vazia2 | sort | paste -sd' ')" ]] || falhou "chaves: [$chaves]"
grep -q '_oculta\|ponte-x' <<<"$(cut -f1 <<<"$out")" && falhou 'oculta/ponte apareceram'
[[ $(cut -f1 <<<"$out" | grep -E '^%[0-9]+$' | paste -sd' ') == "${PB[*]}" ]] || falhou 'painéis fora de ordem'
[[ $(cut -f1 <<<"$out" | tail -3 | head -1) == '!vazias' ]] || falhou 'bloco de vazias não está no fim'
grep -P '^gama dois\t' <<<"$out" | grep -q 'Titulo da conversa falsa' || falhou 'busca do painel do Claude sem o título da conversa'
grep -P '^beta\t' <<<"$out" | grep -q 'titulo do painel' || falhou 'busca sem o título do painel'
grep -P '^alfa\t' <<<"$out" | grep -q 'quatro' || falhou 'busca sem o fim da tela'
grep -P "^${PB[1]}\t" <<<"$out" | limpa | grep -q '⧉ rot|ulo' || falhou "rótulo com | quebrado: $(grep -P "^${PB[1]}\t" <<<"$out" | limpa | cut -f2)"
grep -P "^${PB[0]}\t" <<<"$out" | limpa | grep -q 'painel um' || falhou 'nome do painel ausente'
passou 'listar: sessões, painéis, vazias, oculta/ponte fora, busca com títulos e rótulo com |'

# 2) nenhuma ida ao tmux por painel: só list-sessions, list-panes -a e capture-pane
grep -Ev '^(list-sessions|list-panes -a|capture-pane)' "$T/log/listar" && falhou 'chamada ao tmux por painel/sessão (acima)'
n=$(wc -l <"$T/log/listar"); np=$(tmux list-panes -a | wc -l)
((n <= 2 + 2 * np)) || falhou "$n idas ao tmux para $np painéis"
passou "listar: $n idas ao tmux para $np painéis, nenhuma por painel além da captura da tela"

# 3) --listar-leve e --listar-tudo --tsv em lote, com as mesmas vazias
leve=$(TT_CONTA=leve "$TT" --listar-leve)
[[ $(grep -c 'vazia[12]' <<<"$leve") == 2 && $(grep -c '^!vazias' <<<"$leve") == 1 ]] || falhou "leve: $leve"
grep -Ev '^(list-sessions|list-panes -a|capture-pane)' "$T/log/leve" && falhou 'listar-leve: chamada por sessão'
tsv=$(TT_CONTA=tsv "$TT" --listar-tudo --tsv)
[[ $(tail -n +2 <<<"$tsv" | cut -f2 | sort | paste -sd' ') == 'alfa beta gama dois ponte-x vazia1 vazia2' ]] || falhou "tsv: $(cut -f2 <<<"$tsv")"
grep -P '^[^\t]*\tgama dois\t' <<<"$tsv" | cut -f7 | grep -qx claude || falhou "tsv: agente do painel do Claude: $(grep 'gama' <<<"$tsv")"
grep -Ev '^(list-sessions|list-windows -a|list-panes -a|capture-pane)' "$T/log/tsv" && falhou 'tsv: chamada por sessão'
passou 'listar-leve e --tsv: em lote, mesmas vazias, agente detectado'

# 4) em paralelo: com cada captura levando 0,5 s, as 10 do --listar não podem somar (em fila: ≥ 5 s)
t0=$(date +%s%N); TT_LENTO=0.5 "$TT" --listar >/dev/null; ms=$(( ($(date +%s%N) - t0) / 1000000 ))
((ms < 3500)) || falhou "listar com capturas lentas levou $ms ms (em fila seriam ≥ 5000)"
passou "listar com capturas lentas (0,5 s cada): $ms ms, em paralelo"

# 5) a central abre na hora: a recarga guarda a lista local com a assinatura (sessões e painéis); a lista
#    rápida a usa com uma ida só ao tmux enquanto nada mudou, e refaz ao vivo quando muda
TT_CONTA=tudo "$TT" --listar-tudo >"$T/tudo.txt"
[[ -s $TT_RT/tt-lista-$(id -u)-teste && -s $TT_RT/tt-lista-$(id -u)-teste.assinatura ]] || falhou 'a recarga não guardou a lista local'
rapida=$(TT_CONTA=rapida "$TT" --lista-rapida-central)
[[ $rapida == "$(cat "$T/tudo.txt")" ]] || falhou 'lista rápida diferente da guardada'
[[ $(grep -cv '^list-panes -a' "$T/log/rapida") == 0 && $(wc -l <"$T/log/rapida") == 1 ]] || falhou "lista rápida com a guardada deveria ir ao tmux uma vez: $(cat "$T/log/rapida")"
nova recente 'sleep 600'
grep -q 'recente' <<<"$(TT_CONTA=rapida2 "$TT" --lista-rapida-central)" || falhou 'sessão nova não apareceu: a assinatura deveria invalidar a lista guardada'
passou 'central abre da lista guardada (uma ida ao tmux) e refaz ao vivo quando as sessões mudam'
