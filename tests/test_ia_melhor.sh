#!/usr/bin/env bash
# A IA com mais folga agora: ia-rot --melhor (escolha pelo uso, não por roda fixa), ia-conta abrir
# (abre a escolhida sem pedir permissões, retomando a conversa do Claude) e os dois atalhos da barra
# do tt (ia-nova numa sessão nova; ia-aqui troca o que roda no painel atual).
# Sem rede: Claude e Codex são falsos e o uso vem do cache do contas-uso.py.
source "$(dirname "$0")/lib.sh"
isolar
mkdir -p "$HOME/.local/bin" "$HOME/.cache" "$HOME/.claude/sessions"
B=$HOME/.local/bin
# Agentes falsos: registram conta e argumentos.
cat >"$B/claude" <<'EOF'
#!/usr/bin/env bash
printf 'claude\t%s\t%s\t%s\n' "${CLAUDE_CONFIG_DIR:-principal}" "${IS_SANDBOX:-}" "$*" >>"$HOME/agente.log"
[[ $* == *--no-session-persistence ]] && exit 1
exit 0
EOF
cat >"$B/codex" <<'EOF'
#!/usr/bin/env bash
[[ $1 == login ]] && exit 0
printf 'codex\t%s\n' "$*" >>"$HOME/agente.log"
EOF
chmod +x "$B/claude" "$B/codex"
export PATH=$B:$PATH
instalar_isolado

R=$HOME/.local/share/claude-contas
cred='{"claudeAiOauth":{"accessToken":"t","expiresAt":0}}'
echo "$cred" >"$HOME/.claude/.credentials.json"
for c in alfa beta; do mkdir -p "$R/$c"; echo "$cred" >"$R/$c/.credentials.json"; done
agora=$(date +%s)
uso() { # principal alfa beta codex (pico de 5 h de cada)
  cat >"$HOME/.cache/claude-rot.uso.json" <<EOF
{"principal": {"alvo": "$HOME/.claude", "quando": $agora, "janelas": [["5h", $1, $((agora + 3600))]], "email": ""},
 "alfa": {"alvo": "$R/alfa", "quando": $agora, "janelas": [["5h", $2, $((agora + 3600))]], "email": ""},
 "beta": {"alvo": "$R/beta", "quando": $agora, "janelas": [["5h", $3, $((agora + 3600))]], "email": ""},
 "codex": {"alvo": "codex", "quando": $agora, "janelas": [["5h", $4, $((agora + 3600))]], "email": ""}}
EOF
}
melhor() { ia-rot --melhor "$@" | cut -f1; }

# --- ia-rot --melhor ------------------------------------------------------------------------------
uso 50 70 10 30
[[ $(melhor) == beta ]] || falhou "melhor deveria ser beta (10%): $(melhor)"
[[ $(melhor --exceto beta) == codex ]] || falhou "sem beta, codex (30%): $(melhor --exceto beta)"
uso 50 70 90 5
[[ $(melhor) == codex ]] || falhou "codex com 5% deveria vencer as do Claude: $(melhor)"
passou 'ia-rot --melhor: vence a conta de mais folga, entre Claude e Codex; --exceto tira da disputa'

# O semanal também pesa: pouco uso na janela de 5 h não salva quem gastou quase a semana toda com
# dias pela frente; mas sobra semanal perto do reinício é "use ou perde" e conta como folga.
semana() { # conta: 5h% 7d% horas-até-o-semanal-reiniciar
  printf '"%s": {"alvo": "%s", "quando": %s, "janelas": [["5h", %s, %s], ["7d", %s, %s]], "email": ""}' \
    "$1" "$2" "$agora" "$3" $((agora + 4 * 3600)) "$4" $((agora + $5 * 3600))
}
{ echo "{"; semana alfa "$R/alfa" 10 90 140; echo ","; semana beta "$R/beta" 40 30 140; echo "}"; } \
  >"$HOME/.cache/claude-rot.uso.json"
[[ $(melhor --exceto codex) == beta ]] || falhou "semanal quase no fim com 6 dias pela frente deveria perder: $(melhor --exceto codex)"
{ echo "{"; semana alfa "$R/alfa" 10 90 2; echo ","; semana beta "$R/beta" 40 30 140; echo "}"; } \
  >"$HOME/.cache/claude-rot.uso.json"
[[ $(melhor --exceto codex) == alfa ]] || falhou "semanal que reinicia em 2 h deveria valer como folga: $(melhor --exceto codex)"
passou 'folga: a janela de 5 h e a semanal juntas, pesando quanto falta para cada uma reiniciar'

uso 99 100 98 97
set +e; ia-rot --melhor >/dev/null 2>"$T/err"; rc=$?; set -e
[[ $rc == 2 ]] && grep -q 'nenhuma conta' "$T/err" || falhou "todas cheias: rc=$rc $(cat "$T/err")"
passou 'ia-rot --melhor: todas acima do limite → sai 2 dizendo quando a primeira volta'

# Marca de bloqueio (tirada do texto de um erro) contra o uso medido: a antiga, sem hora, cai quando o
# uso está abaixo do limite; a nova, com hora, só cai com leitura ao vivo (aqui é cache: fica).
: >"$HOME/.cache/claude-rot.state"
uso 50 70 10 30
printf 'beta\t%s\n' $((agora + 3600)) >"$HOME/.cache/claude-rot.state"
[[ $(melhor) == beta ]] || falhou "marca antiga sem hora deveria cair com uso 10%: $(melhor)"
printf 'beta\t%s\t%s\n' $((agora + 3600)) "$agora" >"$HOME/.cache/claude-rot.state"
[[ $(melhor) == codex ]] || falhou "marca com hora e uso só de cache deveria valer: $(melhor)"
: >"$HOME/.cache/claude-rot.state"
passou 'bloqueio: marca antiga cai pelo uso medido; marca recente só cai com leitura ao vivo'

# --- ia-conta abrir -------------------------------------------------------------------------------
uso 50 70 10 30
: >"$HOME/agente.log"
ia-conta abrir >"$T/saida" </dev/null || falhou "abrir saiu com erro: $(cat "$T/saida")"
grep -q '^→ beta' "$T/saida" || falhou "abrir não anunciou a escolhida: $(cat "$T/saida")"
grep -qP "^claude\t$R/beta\t\t--dangerously-skip-permissions$" "$HOME/agente.log" ||
  falhou "abrir não abriu o claude da beta sem permissões: $(cat "$HOME/agente.log")"
[[ $(cat "$HOME/.cache/claude-rot.current") == beta ]] || falhou 'abrir não marcou a conta atual do rotator'
: >"$HOME/agente.log"
ia-conta abrir --retomar 1234abcd-0000 >/dev/null </dev/null
grep -qP "\t--dangerously-skip-permissions --resume 1234abcd-0000$" "$HOME/agente.log" ||
  falhou "abrir --retomar não continuou a conversa: $(cat "$HOME/agente.log")"
passou 'ia-conta abrir: a conta com mais folga, sem permissões; --retomar continua a conversa'

uso 50 70 90 5
: >"$HOME/agente.log"
ia-conta abrir --retomar 1234abcd-0000 >"$T/saida" </dev/null
grep -qP '^codex\t--yolo$' "$HOME/agente.log" || falhou "abrir não abriu o codex --yolo: $(cat "$HOME/agente.log")"
grep -q 'sessão nova' "$T/saida" || falhou 'abrir no codex não avisou que a conversa do Claude não continua'
: >"$HOME/agente.log"
ANDROID_ROOT=/system ia-conta abrir >/dev/null </dev/null
grep -qP '^codex\t--no-daemon --yolo$' "$HOME/agente.log" || falhou "no Android o codex precisa de --no-daemon: $(cat "$HOME/agente.log")"
passou 'ia-conta abrir: codex com --yolo (e --no-daemon no Android); conversa do Claude vira sessão nova'

# --- atalhos da barra do tt -----------------------------------------------------------------------
ids() { "$TT" --atalhos-lista | cut -f2 | tr '\n' ' '; }
[[ $(ids) == "ia-nova ia-aqui " ]] || falhou "padrão deveria ter só ia-nova e ia-aqui: $(ids)"
m=$(PREFIX=/data/data/com.termux/files/usr "$TT" --atalhos-lista)
[[ $(cut -f2 <<<"$m" | tr '\n' ' ') == "ia-nova ia-aqui " ]] || falhou "celular: $(cut -f2 <<<"$m")"
grep -q "^👇"$'\t'"ia-aqui"$'\t'"@aqui proot-distro login debian .*'ia-conta abrir {retomar}'" <<<"$m" ||
  falhou "celular: ia-aqui não entra no Debian: $m"
passou 'atalhos: dois padrões (ia-nova, ia-aqui) no PC e no celular (via proot)'

# @aqui num painel com um Claude (falso, mas com o nome do processo "claude") e sua conversa: o painel
# é reaberto ali mesmo com {retomar} trocado pelo ID, e o agente antigo é fechado.
mkdir -p "$T/falso"
# O processo se chama claude, como o de verdade (um link para o sleep não serve: ele pode ser multichamada).
printf '#!/usr/bin/env bash\nprintf claude >/proc/$$/comm\nwhile :; do sleep 1; done\n' >"$T/falso/claude"
chmod +x "$T/falso/claude"
printf '👇\tia-aqui\t@aqui echo "[{retomar}]" >%q\t\n' "$T/aqui.out" >"$XDG_CONFIG_HOME/tt/atalhos"
tmux new-session -d -s trabalho -x 120 -y 30 -c "$T" "bash -c '$T/falso/claude; exec bash'"
pane=$(tmux display-message -p -t '=trabalho:' '#{pane_id}')
sleep 0.5
pid=$(tmux display-message -p -t "$pane" '#{pane_pid}')
cpid=$(pgrep -P "$pid" -x claude || pgrep -f "$T/falso/claude" | head -1)
[[ -n $cpid ]] || falhou 'Claude falso não subiu'
printf '{"pid": %s, "sessionId": "abcdef12-3456-7890-abcd-ef1234567890", "status": "idle"}\n' "$cpid" \
  >"$HOME/.claude/sessions/$cpid.json"
i=$(ids | tr ' ' '\n' | grep -n '^ia-aqui$' | cut -d: -f1)
"$TT" --clique "at$i" cliente-falso "$pane" "$HOME" 2>/dev/null || true
for _ in $(seq 30); do [[ -s $T/aqui.out ]] && break; sleep 0.2; done
[[ $(cat "$T/aqui.out" 2>/dev/null) == '[--retomar abcdef12-3456-7890-abcd-ef1234567890]' ]] ||
  falhou "@aqui não retomou a conversa do painel: '$(cat "$T/aqui.out" 2>/dev/null)'"
kill -0 "$cpid" 2>/dev/null && falhou '@aqui não fechou o agente que estava no painel'
[[ $(tmux list-sessions -F '#{session_name}' | wc -l) == 1 ]] || falhou '@aqui abriu sessão nova em vez de usar o painel'
[[ $(tmux display-message -p -t "$pane" '#{pane_current_path}') == "$T" ]] || falhou '@aqui mudou a pasta do painel'
passou '@aqui: fecha o agente do painel e abre o novo ali mesmo, na mesma pasta, retomando a conversa'

# Painel só com shell: {retomar} some.
rm -f "$T/aqui.out"; sleep 0.6  # o clique ignora repetição em menos de 0,5 s
"$TT" --clique "at$i" cliente-falso "$pane" "$HOME" 2>/dev/null || true
for _ in $(seq 30); do [[ -s $T/aqui.out ]] && break; sleep 0.2; done
[[ $(cat "$T/aqui.out" 2>/dev/null) == '[]' ]] || falhou "@aqui sem Claude: '$(cat "$T/aqui.out" 2>/dev/null)'"
passou '@aqui num painel sem Claude: abre sem retomar'
