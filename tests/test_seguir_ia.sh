#!/usr/bin/env bash
# tt-teste: sozinho (depende de tela e tempo: roda sem outros testes disputando a máquina)
# ⏩ (atalho @seguir): a conversa de IA do painel segue com outra IA.
#  - acha a conversa e o código dela: Claude (registro do pid), Codex (mesma pasta, mexida desde que o agente
#    começou), Kiro (trava com o pid); painel sem agente não faz nada;
#  - tt --conversa-ia CÓDIGO: a conversa em Markdown (falas inteiras; o que as ferramentas devolveram, cortado;
#    sem pensamento nem mensagens internas), também de outra máquina (--de, pela rede do tt) e salva (--salvar);
#  - nesta máquina: encerra o agente e abre a nova IA no mesmo painel, com o pedido (--prompt-arquivo) e a conversa
#    já exportada;
#  - noutra (menu @maquinas): a de lá abre a nova IA numa sessão nova com o @seguir dela, o agente daqui fecha e a
#    tela vai para lá.
# Sem rede: agentes falsos (processos com o nome certo) e ssh falso que roda "na outra máquina" com outra HOME.
source "$(dirname "$0")/lib.sh"; isolar
O() { fora "$@"; }
B=$T/fb; mkdir -p "$B"
for n in claude codex kiro-cli; do
  printf '#!/usr/bin/env python3\nimport ctypes, time\nctypes.CDLL(None).prctl(15, b"%s", 0, 0, 0)\nwhile True:\n    time.sleep(1)\n' "$n" >"$B/falso-$n"
  chmod +x "$B/falso-$n"
  [[ $(uname -s) == Darwin ]] && { printf '#!/bin/bash\nwhile :; do sleep 1; done\n' >"$B/falso-$n"; nomear_script "$B/falso-$n" "$n"; }
done
cat >"$B/ia-conta" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$IA_LOG"
while (($#)); do [[ $1 == --prompt-arquivo ]] && { echo "=== $2" >>"$PROMPT_LOG"; cat "$2" >>"$PROMPT_LOG"; }; shift; done
EOF
chmod +x "$B/ia-conta"
ORIG=$HOME D=$T/dest
cat >"$B/ssh" <<'EOF'
#!/usr/bin/env bash
cmd=${*: -1}; host=""
for a in "$@"; do case $a in *@*-host) host=${a#*@} ;; esac; done
printf '%s %s\n' "$host" "$cmd" >>"$SSH_LOG"
case $host in destino-host) H=$DEST ;; origem-host) H=$ORIG ;; *) exit 255 ;; esac
exec env HOME="$H" XDG_CONFIG_HOME="$H/.config" TT_RT="$H/rt" bash -c "$cmd"
EOF
chmod +x "$B/ssh"
export PATH=$B:$PATH IA_LOG=$T/ia.log PROMPT_LOG=$T/prompt.log SSH_LOG=$T/ssh.log DEST=$D ORIG
mkdir -p "$D/.local/bin" "$D/.config/tt" "$D/rt" "$ORIG/.local/bin"
ln -s "$TT" "$D/.local/bin/tt"; ln -s "$TT" "$ORIG/.local/bin/tt"
printf 'nome=outra\n' >"$D/.config/tt/config"
printf 'origem-host helio teste\n' >"$D/.config/tt/maquinas"
printf 'destino-host helio outra\n' >"$XDG_CONFIG_HOME/tt/maquinas"
printf '⏩\tia-seguir\t@seguir %s abrir {prompt}\t#f9e2af\t@maquinas\n' "$B/ia-conta" | tee "$XDG_CONFIG_HOME/tt/atalhos" >"$D/.config/tt/atalhos"
espera() { local i; for i in $(seq 50); do [[ -s $1 ]] && return 0; sleep 0.2; done; return 1; }
enc() { sed 's/[^A-Za-z0-9]/-/g' <<<"$1"; }
sessao_de() { tmux list-clients -F '#{client_name} #{session_name}' | awk -v c="$1" '$1 == c { print $2; exit }'; }
pid_de() { local raiz; raiz=$(tmux display -p -t "$1" '#{pane_pid}'); for _ in $(seq 25); do pgrep -P "$raiz" -x "$2" && return 0; sleep 0.2; done; return 1; }

# --- Conversa do Claude --------------------------------------------------------------------------
U1=aaaaaaaa-1111-4111-8111-111111111111
P=$T/proj; mkdir -p "$P" "$HOME/.claude/sessions"; PA=$HOME/.claude/projects/$(enc "$P"); mkdir -p "$PA"
longo=$(printf 'R%.0s' $(seq 3000))
{
  printf '{"type":"user","cwd":"%s","sessionId":"%s","timestamp":"2026-10-14T10:00:00Z","message":{"role":"user","content":"Implemente a rolagem nos chips"}}\n' "$P" "$U1"
  printf '{"type":"assistant","timestamp":"2026-10-14T10:00:05Z","message":{"content":[{"type":"text","text":"Vou ler o código."},{"type":"tool_use","name":"Bash","input":{"command":"ls -la"}}]}}\n'
  printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"x","content":"%s"}]}}\n' "$longo"
  printf '{"type":"user","isMeta":true,"message":{"content":"aviso interno meta"}}\n'
  printf '{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"pensamento secreto"},{"type":"text","text":"Pronto, falta o teste."}]}}\n'
} >"$PA/$U1.jsonl"
out=$("$TT" --conversa-ia "$U1")
for t in "# Conversa claude · $U1" 'Implemente a rolagem nos chips' 'Vou ler o código.' '🔧 **Bash**' 'ls -la' '[+1500 caracteres]' 'Pronto, falta o teste.'; do
  grep -qF -- "$t" <<<"$out" || falhou "exportação do Claude sem '$t': $out"
done
grep -q 'pensamento secreto\|aviso interno meta' <<<"$out" && falhou 'exportação levou pensamento ou mensagem interna'
"$TT" --conversa-ia nao-existe-1234 >/dev/null 2>&1 && falhou 'conversa inexistente deveria falhar'
passou 'tt --conversa-ia: Markdown com as falas, ferramentas e resultados cortados; sem pensamento nem internas'

tmux new -d -s trab -x 120 -y 30 -c "$P" "$B/falso-claude; exec bash"
anexar tela 120 30 trab; sleep 0.8
cli=$(tmux list-clients -F '#{client_name}' | head -1)
pane=$(tmux display -p -t '=trab:' '#{pane_id}')
cpid=$(pid_de "$pane" claude) || falhou 'Claude falso não subiu'
printf '{"pid": %s, "sessionId": "%s", "status": "idle"}\n' "$cpid" "$U1" >"$HOME/.claude/sessions/$cpid.json"

m=$("$TT" --atalho-menu-itens ia-seguir "$cli" "$pane")
grep -qP '^0\t⏩ Seguir com outra IA aqui mesmo \(o clique\)' <<<"$m" && grep -qP '^\w\t⏩ Seguir em outra\t.*maquina=outra' <<<"$m" ||
  falhou "menu da ⏩: $m"
passou 'menu da ⏩: o clique segue aqui; @maquinas oferece seguir noutra máquina'

"$TT" --atalho-rodar ia-seguir "$cli" "$pane"
espera "$IA_LOG" || falhou "a ⏩ não abriu a nova IA (sessões: $(tmux ls -F '#S'))"
grep -q "^abrir --prompt-arquivo $HOME/.cache/tt/seguir/$U1-" "$IA_LOG" || falhou "nova IA sem o pedido: $(cat "$IA_LOG")"
kill -0 "$cpid" 2>/dev/null && falhou 'a ⏩ não encerrou o Claude do painel'
[[ $(tmux display -p -t "$pane" '#{pane_id}') == "$pane" && $(tmux ls | wc -l) == 1 ]] || falhou 'a ⏩ abriu sessão nova em vez de seguir no mesmo painel'
for t in "Conversa: claude, código $U1" 'Máquina de origem: teste' "$HOME/.cache/tt/conversas/$U1.md" 'de forma integral'; do
  grep -qF -- "$t" "$PROMPT_LOG" || falhou "pedido sem '$t': $(cat "$PROMPT_LOG")"
done
grep -q 'ssh ' "$PROMPT_LOG" && falhou 'pedido na mesma máquina não precisa de ssh'
grep -q 'Implemente a rolagem' "$HOME/.cache/tt/conversas/$U1.md" 2>/dev/null || falhou 'a conversa não foi exportada antes da nova IA começar'
passou 'nesta máquina: encerra o Claude, exporta a conversa e abre a nova IA no mesmo painel com o pedido'

# --- Codex: a conversa da mesma pasta, mexida depois que o agente começou ------------------------
P2=$T/proj2; mkdir -p "$P2"
C0=01a10711-0000-7000-8000-000000000000 C1=01a10711-1111-7111-8111-111111111111 C2=01a10711-2222-7222-8222-222222222222
tmux new -d -s cx -x 120 -y 30 -c "$P2" "$B/falso-codex; exec bash"
pane2=$(tmux display -p -t '=cx:' '#{pane_id}')
xpid=$(pid_de "$pane2" codex) || falhou 'Codex falso não subiu'
SD=$HOME/.codex/sessions/2026/10/14; mkdir -p "$SD"
rollout() { # id pasta texto
  printf '{"timestamp":"2026-10-14T10:00:00Z","type":"session_meta","payload":{"id":"%s","cwd":"%s","timestamp":"2026-10-14T10:00:00Z"}}\n' "$1" "$2"
  printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>ctx</environment_context>"}]}}\n'
  printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"%s"}]}}\n' "$3"
  printf '{"type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{\\"command\\":[\\"ls\\"]}"}}\n'
  printf '{"type":"response_item","payload":{"type":"function_call_output","output":"arquivo1"}}\n'
  printf '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Achei o bug."}]}}\n'
}
rollout "$C0" "$P2" 'antiga' >"$SD/rollout-2026-10-14T09-00-00-$C0.jsonl"; touch -d '-1 hour' "$SD/rollout-2026-10-14T09-00-00-$C0.jsonl"
sleep 1.2
rollout "$C1" "$P2" 'Corrija o bug Y' >"$SD/rollout-2026-10-14T10-00-00-$C1.jsonl"
rollout "$C2" "$T/outra-pasta" 'outra pasta' >"$SD/rollout-2026-10-14T10-00-01-$C2.jsonl"
out=$("$TT" --conversa-ia "$C1")
grep -q 'Corrija o bug Y' <<<"$out" && grep -q 'Achei o bug.' <<<"$out" && grep -q '🔧 \*\*shell\*\*' <<<"$out" && grep -q 'arquivo1' <<<"$out" ||
  falhou "exportação do Codex: $out"
grep -q 'environment_context' <<<"$out" && falhou 'exportação do Codex levou o contexto injetado'
: >"$IA_LOG"; : >"$PROMPT_LOG"
"$TT" --atalho-rodar ia-seguir "$cli" "$pane2"
espera "$PROMPT_LOG" || falhou 'a ⏩ não seguiu a conversa do Codex'
grep -qF "Conversa: codex, código $C1" "$PROMPT_LOG" || falhou "Codex: conversa errada: $(grep Conversa "$PROMPT_LOG")"
passou 'Codex: a conversa da mesma pasta, mexida depois que o agente começou (nem a antiga, nem a de outra pasta)'

# --- Kiro: a trava com o pid manda, mesmo com outra conversa da mesma pasta mais nova ---------------
P3=$T/proj3; mkdir -p "$P3"; KI=$HOME/.kiro/sessions/cli; mkdir -p "$KI"
K1=bbbbbbbb-1111-4111-8111-111111111111 K2=bbbbbbbb-2222-4222-8222-222222222222
tmux new -d -s kr -x 120 -y 30 -c "$P3" "$B/falso-kiro-cli; exec bash"
pane3=$(tmux display -p -t '=kr:' '#{pane_id}')
kpid=$(pid_de "$pane3" kiro-cli) || falhou 'Kiro falso não subiu'
for k in "$K1" "$K2"; do
  printf '{"session_id":"%s","cwd":"%s","created_at":"2026-10-14T10:00:00Z"}\n' "$k" "$P3" >"$KI/$k.json"
  printf '{"version":"v1","kind":"Prompt","data":{"content":[{"kind":"text","data":"Pedido ao Kiro %s"}],"meta":{"timestamp":1791964800}}}\n' "$k" >"$KI/$k.jsonl"
  printf '{"version":"v1","kind":"AssistantMessage","data":{"content":[{"kind":"text","data":"Ok."},{"kind":"toolUse","data":{"name":"shell","input":{"command":"pwd"}}}]}}\n' >>"$KI/$k.jsonl"
  printf '{"version":"v1","kind":"ToolResults","data":{"content":[{"kind":"toolResult","data":{"content":[{"kind":"json","data":{"stdout":"/proj3"}}]}}]}}\n' >>"$KI/$k.jsonl"
done
printf '{"pid": %s}\n' "$kpid" >"$KI/$K1.lock"; printf '{"pid": 1}\n' >"$KI/$K2.lock"; touch "$KI/$K2.jsonl"
out=$("$TT" --conversa-ia "$K1")
grep -q "Pedido ao Kiro $K1" <<<"$out" && grep -q '🔧 \*\*shell\*\*' <<<"$out" && grep -q '/proj3' <<<"$out" || falhou "exportação do Kiro: $out"
: >"$PROMPT_LOG"
"$TT" --atalho-rodar ia-seguir "$cli" "$pane3"
espera "$PROMPT_LOG" || falhou 'a ⏩ não seguiu a conversa do Kiro'
grep -qF "Conversa: kiro, código $K1" "$PROMPT_LOG" || falhou "Kiro: conversa errada: $(grep Conversa "$PROMPT_LOG")"
passou 'Kiro: a conversa da trava com o pid do agente'

# --- Painel sem agente: nada muda ---------------------------------------------------------------
tmux new -d -s vazio -x 120 -y 30 'sleep 600'
pane4=$(tmux display -p -t '=vazio:' '#{pane_id}'); antes=$(tmux display -p -t "$pane4" '#{pane_pid}')
: >"$IA_LOG"
"$TT" --atalho-rodar ia-seguir "$cli" "$pane4"; sleep 1
[[ ! -s $IA_LOG && $(tmux display -p -t "$pane4" '#{pane_pid}') == "$antes" ]] || falhou 'painel sem agente: a ⏩ mexeu nele'
passou 'painel sem conversa de IA: a ⏩ só avisa, sem mexer no painel'

# --- Noutra máquina ------------------------------------------------------------------------------
U2=cccccccc-2222-4222-8222-222222222222
sed "s/$U1/$U2/g" "$PA/$U1.jsonl" >"$PA/$U2.jsonl"
tmux new -d -s trab2 -x 120 -y 30 -c "$P" "$B/falso-claude; exec bash"
pane5=$(tmux display -p -t '=trab2:' '#{pane_id}')
cpid=$(pid_de "$pane5" claude) || falhou 'Claude falso (2) não subiu'
printf '{"pid": %s, "sessionId": "%s", "status": "idle"}\n' "$cpid" "$U2" >"$HOME/.claude/sessions/$cpid.json"
tmux switch-client -c "$cli" -t =trab2; sleep 0.3
: >"$IA_LOG"; : >"$PROMPT_LOG"; : >"$SSH_LOG"
TMUX=$(tmux display -p '#{socket_path}'),1,0 "$TT" --atalho-rodar ia-seguir "$cli" "$pane5" maquina=outra
espera "$PROMPT_LOG" || falhou "a outra máquina não abriu a nova IA: $(cat "$SSH_LOG")"
grep -q "^destino-host .*--seguir-abrir teste claude $U2 " "$SSH_LOG" || falhou "não pediu à outra: $(cat "$SSH_LOG")"
pedido=$(ls "$D/.cache/tt/seguir/$U2"-*.md 2>/dev/null | head -1)
[[ -n $pedido ]] || falhou 'o pedido não foi escrito na outra máquina'
for t in 'Máquina de origem: teste' 'Você está em: outra' 'ssh helio@origem-host' "tt --conversa-ia $U2 --de teste --salvar"; do
  grep -qF -- "$t" "$pedido" || falhou "pedido da outra máquina sem '$t': $(cat "$pedido")"
done
grep -q "^abrir --prompt-arquivo $pedido" "$IA_LOG" || falhou "a nova IA não recebeu o pedido de lá: $(cat "$IA_LOG")"
kill -0 "$cpid" 2>/dev/null && falhou 'o Claude daqui não fechou depois que a outra abriu'
for _ in $(seq 20); do tmux capture-pane -p -t "$pane5" | grep -q 'seguiu em outra' && break; sleep 0.2; done
tmux capture-pane -p -t "$pane5" | grep -q "seguiu em outra" || falhou "o painel daqui não diz onde a conversa seguiu: $(tmux capture-pane -p -t "$pane5")"
s=$(sessao_de "$cli"); alvo=$(tmux show -qv -t "=$s:" @ponte_alvo)
[[ $alvo == helio@destino-host\|atalho-* ]] || falhou "a tela não foi para a sessão nova da outra máquina: sessão=$s alvo=$alvo"
passou "noutra máquina: ela abre a nova IA com o @seguir dela, o agente daqui fecha e a tela vai para lá ($alvo)"

HOME=$D XDG_CONFIG_HOME=$D/.config TT_RT=$D/rt "$TT" --conversa-ia "$U2" --de teste --salvar >/dev/null
grep -q 'Implemente a rolagem' "$D/.cache/tt/conversas/$U2.md" 2>/dev/null || falhou 'a outra máquina não buscou a conversa pela rede do tt'
grep -q "^origem-host .*--conversa-ia $U2" "$SSH_LOG" || falhou "a busca não foi à máquina de origem: $(cat "$SSH_LOG")"
# A conversa inteira e o pedido só para o dono (o Claude grava as conversas com 600; a cópia saía 644 numa pasta 755).
modo() { ls -ldn "$1" | cut -c1-10; }
[[ $(modo "$D/.cache/tt/conversas/$U2.md") == -rw------- ]] || falhou "conversa salva com modo aberto: $(modo "$D/.cache/tt/conversas/$U2.md")"
[[ $(modo "$D/.cache/tt/conversas") == drwx------ ]] || falhou "pasta das conversas aberta: $(modo "$D/.cache/tt/conversas")"
[[ $(modo "$pedido") == -rw------- && $(modo "$D/.cache/tt/seguir") == drwx------ ]] || falhou "pedido da ⏩ aberto: $(modo "$pedido") $(modo "$D/.cache/tt/seguir")"
passou 'tt --conversa-ia --de: a outra máquina busca a conversa na de origem e salva'
