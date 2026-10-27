#!/usr/bin/env bash
# Snapshots do estado: ligam/desligam, gravam a cada evento (com debounce), não repetem estado igual, guardam no máximo TT_SNAP_MAX,
# mostram data/hora, restauram (aditivo e substituir) recriando abas, painéis, layout, fixadas e RETOMANDO a conversa de cada agente
# do jeito da máquina (direto, ou no Debian do proot do Termux), sempre sem pedir permissões (ia-conta retomar).
# tt-teste: sozinho
source "$(dirname "$0")/lib.sh"; isolar
source "$(dirname "$0")/tmux-isolado.sh"
TT="$RAIZ/tt"
export TT_SNAP_DIR="$T/snaps" TT_SNAP_ESPERA=1 TT_SNAP_MAX=5
B=$T/bin; mkdir -p "$B" "$HOME/.local/bin"
nlist() { "$TT" --snapshots-listar | wc -l | tr -d ' '; }

grep -Fq -- "--header='↩ Restaurar · Ctrl+R · ⏎'" "$TT" || falhou 'painel de snapshots sem botão Restaurar no cabeçalho'
grep -Fq -- "--bind='ctrl-r:accept,click-header:accept'" "$TT" || falhou 'botão Restaurar sem rota de clique ou Ctrl+R'

# --- o tmux.conf do pacote liga os ganchos (índice fixo: recarregar não acumula)
tmux new-session -d -s hk -x 80 -y 24
tmux source-file "$RAIZ/tmux.conf" >/dev/null 2>&1 || true; tmux source-file "$RAIZ/tmux.conf" >/dev/null 2>&1 || true
hk=$(tmux show-hooks -g; tmux show-hooks -gw)
for h in session-created session-closed session-renamed after-new-window window-unlinked window-renamed after-split-window; do
  [[ $hk == *"$h[20]"*"--snapshot-evento"* ]] || falhou "falta o gancho $h[20]"
done
[[ $(grep -c 'after-new-window\[20\]' <<<"$hk") == 1 ]] || falhou 'recarregar acumulou o gancho'
tmux kill-server 2>/dev/null || true

# --- caminhos pela interface: atalho de teclado, rota do clique, menu administrar e a tela (liga/desliga)
grep -q "bind S run-shell -b \"~/.local/bin/tt --clique snapshots " "$RAIZ/tmux.conf" || falhou 'Ctrl+B S não abre os snapshots'
grep -q '    snapshots) eval "$(popup_tt' "$RAIZ/tt" || falhou 'clique() sem a rota snapshots'
grep -q "📸 Snapshots do estado (histórico e restaurar)" "$RAIZ/tt" || falhou 'menu administrar sem o item dos snapshots'
grep -q "🔎 Busca na conversa inteira: " "$RAIZ/tt" || falhou 'menu administrar sem o item da busca (ligar/desligar)'
grep -q "🍎 Atalhos no Mac" "$RAIZ/tt" || falhou 'menu administrar sem o item dos atalhos do Mac'
grep -q -- '--expect=ctrl-o,ctrl-n' "$RAIZ/tt" || falhou 'tela dos snapshots sem ^o/^n'

# --- desligado por padrão: evento não grava nada
st=$("$TT" --snapshots status); [[ $st == *desligados* ]] || falhou 'deveria nascer desligado'
tmux new-session -d -s alfa -x 120 -y 40 -c "$T"
"$TT" --snapshot-evento sessao-criada alfa; sleep 2
[[ $(nlist) == 0 ]] || falhou 'desligado não deve gravar'

# --- um agente de mentira: um processo chamado "claude" no painel, com a conversa registrada pelo pid
mkdir -p "$T/proj" "$HOME/.claude/sessions"
CONV=0aaa1111-2222-4333-8444-555566667777
# No Linux o processo leva o nome do script só com o interpretador direto no #! (o "env bash" troca o nome para "bash"):
# o script se chama claude, numa pasta própria ($B/claude é outro falso, mais abaixo).
mkdir -p "$T/agente"; printf '#!/bin/sh\nsleep 600\n' >"$T/agente/claude"; chmod +x "$T/agente/claude"; nomear_script "$T/agente/claude" claude
tmux new-session -d -s beta -x 120 -y 40 -c "$T/proj" "$T/agente/claude"
PIDB=$(tmux list-panes -t =beta: -F '#{pane_pid}' | head -1)
printf '{"sessionId":"%s","status":"idle"}\n' "$CONV" >"$HOME/.claude/sessions/$PIDB.json"
tmux split-window -t =alfa: -c "$T"; tmux new-window -t =alfa: -n segunda -c "$T"; tmux split-window -t =alfa:segunda -h -c "$T"
sleep 1

# --- ligar grava o primeiro (forçado); ver mostra data/hora, abas e o agente
"$TT" --snapshots on >/dev/null
[[ $(nlist) == 1 ]] || falhou "ligar deveria gravar 1 snapshot, tem $(nlist)"
ver=$("$TT" --snapshot-ver "$("$TT" --snapshots-listar | sed -n 1p | cut -f1)")
[[ $ver == *alfa* && $ver == *beta* && $ver == *segunda* ]] || falhou "ver sem as sessões/abas: $ver"
[[ $ver == *"claude 0aaa1111"* ]] || falhou "ver sem o agente de IA: $ver"
"$TT" --snapshots-listar | sed -n 1p | cut -f2 | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' || falhou 'sem data e hora legíveis'

# --- estado igual não grava; rajada de eventos vira UM snapshot
"$TT" --snapshot-agora --auto >/dev/null; [[ $(nlist) == 1 ]] || falhou 'estado igual gravou de novo'
tmux new-window -t =alfa: -n terceira -c "$T"
for i in 1 2 3; do "$TT" --snapshot-evento janela-criada terceira; done
sleep 4
[[ $(nlist) == 2 ]] || falhou "rajada deveria virar 1 snapshot (total 2), tem $(nlist)"
mot=$("$TT" --snapshots-listar | sed -n 1p | cut -f3); [[ $mot == *"aba criada"* ]] || falhou "motivo sem 'aba criada': $mot"

# --- teto de TT_SNAP_MAX
for i in 1 2 3 4 5 6 7; do tmux rename-window -t "=alfa:$(tmux list-windows -t =alfa: -F "#{window_index}" | tail -1)" "t$i"; "$TT" --snapshot-agora >/dev/null; sleep 0.05; done
[[ $(nlist) == 5 ]] || falhou "teto de 5: tem $(nlist)"

# --- restaurar: aditivo recria o que falta e não mexe no que existe
ID=$("$TT" --snapshots-listar | sed -n 1p | cut -f1)
tmux kill-session -t =alfa; tmux kill-session -t =beta
# agente de mentira do ia-conta: registra os argumentos (é o que o painel restaurado executa) e, como um agente de verdade, só
# sobe alguns segundos depois, com a conversa na linha de comando.
cat >"$HOME/.local/bin/ia-conta" <<FIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$T/retomar.log"
sleep 2; exec "$T/agente/claude" --dangerously-skip-permissions --resume "\$3"
FIM
chmod +x "$HOME/.local/bin/ia-conta"
# O "restaurado de …" é gravado em 2º plano, quando os agentes retomados já subiram: espera ele terminar.
espera_restauro() {
  local i
  for i in $(seq 150); do [[ -e $TT_RT/tt-snap-$(id -u).restaurando ]] || return 0; sleep 0.2; done
  falhou 'o snapshot "restaurado de" não terminou'
}
tmux new-session -d -s gama -c "$T"   # sessão que o snapshot não tem
out=$("$TT" --snapshot-restaurar "$ID" aditivo gama 2>&1)
tmux has-session -t =alfa && tmux has-session -t =beta || falhou "aditivo não recriou: $out"
tmux has-session -t =gama || falhou 'aditivo não pode fechar sessão que não está no snapshot'
[[ $(tmux list-windows -t =alfa: | wc -l | tr -d ' ') == 3 ]] || falhou "alfa deveria ter 3 abas: $(tmux list-windows -t =alfa:)"
[[ $(tmux list-panes -t =alfa:segunda | wc -l | tr -d ' ') == 2 ]] || falhou 'a aba "segunda" deveria ter 2 painéis'
espera_restauro
grep -q "retomar claude $CONV" "$T/retomar.log" 2>/dev/null || falhou "o agente não foi retomado na mesma conversa: $(cat "$T/retomar.log" 2>/dev/null)"
mot=$("$TT" --snapshots-listar | sed -n 1p | cut -f3); [[ $mot == *"restaurado de"* ]] || falhou "restaurar deveria gravar 'restaurado de': $mot"
mot=$("$TT" --snapshots-listar | cut -f3); [[ $mot == *"antes de restaurar"* ]] || falhou 'restaurar deveria gravar o estado de antes'
# Gravado na hora, o "restaurado de" saía sem os agentes (eles levam segundos para subir); restaurar ESSE snapshot, o mais novo
# da lista, trazia só shells, que o vigia fechava 5 min depois como vazias.
ver=$("$TT" --snapshot-ver "$("$TT" --snapshots-listar | sed -n 1p | cut -f1)")
[[ $ver == *"claude 0aaa1111"* ]] || falhou "o 'restaurado de' deveria ter o agente retomado: $ver"

# aditivo de novo: tudo existe, nada muda
n=$(tmux list-windows -t =alfa: | wc -l | tr -d ' ')
"$TT" --snapshot-restaurar "$ID" aditivo gama >/dev/null 2>&1; espera_restauro
[[ $(tmux list-windows -t =alfa: | wc -l | tr -d ' ') == "$n" ]] || falhou 'aditivo duplicou abas de sessão que já existia'

# --- substituir fecha o que não está no snapshot (menos a sessão em uso e as ocultas)
tmux new-session -d -s _oculta -c "$T"; tmux new-session -d -s delta -c "$T"
"$TT" --snapshot-restaurar "$ID" substituir gama >/dev/null 2>&1; espera_restauro
tmux has-session -t =delta 2>/dev/null && falhou 'substituir deveria fechar "delta"'
tmux has-session -t =_oculta || falhou 'substituir não pode fechar sessão oculta'
tmux has-session -t =gama || falhou 'substituir não pode fechar a sessão em uso'
tmux has-session -t =alfa && tmux has-session -t =beta || falhou 'substituir deveria deixar alfa e beta'

# --- fixadas: aditivo acrescenta; substituir deixa como no snapshot
FIX=$HOME/.config/tt/fixadas; mkdir -p "$HOME/.config/tt"
printf '%s\talfa\tc1\n%s\tbeta\tc2\n' "$("$TT" --nome)" "$("$TT" --nome)" >"$FIX"
"$TT" --snapshot-agora >/dev/null
printf '%s\tbeta\tc2\n%s\talfa\tc1\n' "$("$TT" --nome)" "$("$TT" --nome)" >"$FIX"   # ordem invertida
ID2=$("$TT" --snapshots-listar | sed -n 1p | cut -f1)
printf '%s\talfa\tc1\n%s\tzeta\tc9\n' "$("$TT" --nome)" "$("$TT" --nome)" >"$FIX"
"$TT" --snapshot-restaurar "$ID2" substituir gama >/dev/null 2>&1; espera_restauro
[[ $(cut -f2 "$FIX" | tr '\n' ' ') == "alfa beta " ]] || falhou "substituir deveria deixar as fixadas do snapshot: $(cat "$FIX")"

# --- identidade: a sessão restaurada volta com o MESMO código estável (@tt_session_id) e a fixada dela continua valendo. Sem isso
# a fixada restaurada apontava para um código que nenhuma sessão tinha: o clique não chegava à sessão e o vigia apagava a fixada
# ("sessão não existe mais neste tmux"). A restauração parecia feita, mas não era alcançável.
export TT_SNAP_MAX=50   # este bloco restaura o mesmo snapshot várias vezes (cada uma grava dois)
NOME=$("$TT" --nome)
tmux new-session -d -s kapa -c "$T"; tmux new-session -d -s lambda -c "$T"
IDK=$("$TT" --session-id kapa); IDL=$("$TT" --session-id lambda)
[[ $IDK =~ ^[0-9a-f]{32}$ && $IDL =~ ^[0-9a-f]{32}$ ]] || falhou "sem código estável: '$IDK' '$IDL'"
printf '%s\tkapa\t%s\n%s\tlambda\t%s\n' "$NOME" "$IDK" "$NOME" "$IDL" >"$FIX"
"$TT" --snapshot-agora >/dev/null
ID3=$("$TT" --snapshots-listar | sed -n 1p | cut -f1)
tmux kill-session -t =kapa; tmux kill-session -t =lambda
"$TT" --snapshot-restaurar "$ID3" aditivo gama >/dev/null 2>&1; espera_restauro
[[ $(tmux show-options -qv -t =kapa: @tt_session_id) == "$IDK" ]] || falhou "kapa voltou sem o código dela"
[[ $(tmux show-options -qv -t =lambda: @tt_session_id) == "$IDL" ]] || falhou "lambda voltou sem o código dela"
TT_RECONC_IMEDIATO=1 "$TT" --reconciliar-fixadas
grep -q "kapa	$IDK" "$FIX" && grep -q "lambda	$IDL" "$FIX" || falhou "a fixada restaurada não sobreviveu à conferência: $(cat "$FIX")"
# Sessão que existe com outro nome (renomeada depois do snapshot; o código é o mesmo): o aditivo não cria uma segunda, e a fixada
# não fica duplicada (uma pelo nome antigo, outra pelo novo).
tmux rename-session -t =kapa kapa2
"$TT" --snapshot-restaurar "$ID3" aditivo gama >/dev/null 2>&1; espera_restauro
tmux has-session -t =kapa 2>/dev/null && falhou 'o aditivo recriou "kapa", que existe renomeada (mesmo código)'
[[ $(tmux list-sessions -F '#{@tt_session_id}' | grep -c "$IDK") == 1 ]] || falhou 'código estável repetido em duas sessões'
[[ $(grep -c "$IDK" "$FIX") == 1 ]] || falhou "fixada duplicada pela sessão renomeada: $(cat "$FIX")"
# Snapshot de antes desta correção: as sessões sem o código; o das fixadas (que sempre o tiveram) vale para a sessão fixada.
python3 -I - "$TT_SNAP_DIR/$ID3.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8"))
for ss in s["sessoes"]:
    ss.pop("id", None)
json.dump(s, open(sys.argv[1], "w", encoding="utf-8"))
PY
tmux kill-session -t =kapa2; tmux kill-session -t =lambda
"$TT" --snapshot-restaurar "$ID3" aditivo gama >/dev/null 2>&1; espera_restauro
[[ $(tmux show-options -qv -t =kapa: @tt_session_id) == "$IDK" ]] || falhou "snapshot antigo: kapa sem o código da fixada"
[[ $(tmux show-options -qv -t =lambda: @tt_session_id) == "$IDL" ]] || falhou "snapshot antigo: lambda sem o código da fixada"

# --- sessão restaurada não é "vazia abandonada": o vigia fecha sessão nova sem uso há 5 min, e a restaurada (um shell recém-aberto,
# sem histórico) caía nessa regra. A sessão nova comum continua sendo fechada.
tmux new-session -d -s mu -c "$T"
TT_VAZIA_LIMITE=0 TT_SO_CARREGAR=1 bash -c 'source "$1"; fechar_vazias_expiradas "$(date +%s)"' _ "$TT" >/dev/null 2>&1
tmux has-session -t =mu 2>/dev/null && falhou 'a sessão vazia comum deveria ter sido fechada'
tmux has-session -t =lambda 2>/dev/null || falhou 'a sessão restaurada não pode ser fechada como vazia abandonada'

# --- agente recém-retomado, ainda sem o sessions/<pid>.json: o Claude só o grava depois da pergunta "confia nesta pasta?", que na
# home ele faz toda vez. Vale o código da linha de comando (o ia-conta retomar do snapshot), e a conversa de OUTRO Claude vivo da
# mesma pasta nunca é a dele (era a mais nova da pasta: o snapshot guardava o código do vizinho). O Codex retomado, parado no
# aviso de atualização, não mexe no arquivo da conversa: também vale o código da linha de comando.
mkdir -p "$T/casa" "$T/ag2"; PJ=$HOME/.claude/projects/$(printf '%s' "$T/casa" | sed 's/[^A-Za-z0-9]/-/g'); mkdir -p "$PJ"
RET=0fff1111-2222-4333-8444-555566667777; VIZ=0eee1111-2222-4333-8444-555566667777; CXR=0aab1111-2222-4333-8444-555566667777
printf '{"type":"user"}\n' >"$PJ/$RET.jsonl"; touch -t 202610010000 "$PJ/$RET.jsonl"
mkdir -p "$HOME/.codex/sessions/2026/10/19"; RO=$HOME/.codex/sessions/2026/10/19/rollout-2026-10-19T10-00-00-$CXR.jsonl
printf '{"type":"session_meta","payload":{"cwd":"/outra/pasta"}}\n' >"$RO"; touch -t 202610010000 "$RO"
printf '#!/bin/sh\nsleep 600\n' >"$T/ag2/claude"; printf '#!/bin/sh\nsleep 600\n' >"$T/ag2/codex"; chmod +x "$T/ag2/claude" "$T/ag2/codex"
nomear_script "$T/ag2/claude" claude; nomear_script "$T/ag2/codex" codex
sleep 60 </dev/null >/dev/null 2>&1 & VIZPID=$!   # o Claude vizinho: vivo, registrado, conversa na mesma pasta e mexida agora
printf '{"sessionId":"%s","status":"busy"}\n' "$VIZ" >"$HOME/.claude/sessions/$VIZPID.json"
tmux new-session -d -s eta -x 120 -y 40 -c "$T/casa" "$T/ag2/claude --dangerously-skip-permissions --resume $RET"
tmux new-session -d -s teta -x 120 -y 40 -c "$T/casa" "$T/ag2/claude --dangerously-skip-permissions"
tmux new-session -d -s iota -x 120 -y 40 -c "$T/casa" "$T/ag2/codex resume $CXR --dangerously-bypass-approvals-and-sandbox"
sleep 1; printf '{"type":"user"}\n' >"$PJ/$VIZ.jsonl"
"$TT" --snapshot-agora >/dev/null
ver=$("$TT" --snapshot-ver "$("$TT" --snapshots-listar | sed -n 1p | cut -f1)")
[[ $ver == *"claude 0fff1111"* ]] || falhou "o Claude retomado sem sessions/<pid>.json deveria ser a conversa do --resume: $ver"
[[ $ver != *0eee1111* ]] || falhou "a conversa de outro Claude vivo da mesma pasta não pode ir para o snapshot: $ver"
[[ $ver == *"codex 0aab1111"* ]] || falhou "o Codex retomado (sem mexer na conversa) deveria ser a conversa do resume: $ver"
kill "$VIZPID" 2>/dev/null; wait "$VIZPID" 2>/dev/null || true
tmux kill-session -t =eta; tmux kill-session -t =teta; tmux kill-session -t =iota

# --- ia-conta retomar: cada provedor com o jeito certo de retomar e SEMPRE sem pedir permissões
mkdir -p "$HOME/.claude/projects/-p" "$HOME/.codex/sessions/2026/10/20" "$HOME/.kiro/sessions/cli"
CX=0bbb1111-2222-4333-8444-555566667777; KR=0ccc1111-2222-4333-8444-555566667777
: >"$HOME/.claude/projects/-p/$CONV.jsonl"; : >"$HOME/.codex/sessions/2026/10/20/rollout-2026-10-20T10-00-00-$CX.jsonl"; : >"$HOME/.kiro/sessions/cli/$KR.jsonl"
for prog in claude codex kiro-cli; do
  cat >"$B/$prog" <<FIM
#!/usr/bin/env bash
printf '$prog %s\n' "\$*" >>"$T/agentes.log"
FIM
  chmod +x "$B/$prog"
done
cp "$B/claude" "$HOME/.local/bin/claude"
rm -f "$HOME/.local/bin/ia-conta"
export PATH="$B:$PATH"
"$RAIZ/ia-conta" retomar claude "$CONV" --conta principal >/dev/null 2>&1
"$RAIZ/ia-conta" retomar codex "$CX" >/dev/null 2>&1
"$RAIZ/ia-conta" retomar kiro "$KR" >/dev/null 2>&1
grep -q "claude --dangerously-skip-permissions --resume $CONV" "$T/agentes.log" || falhou "claude: $(cat "$T/agentes.log")"
grep -q "codex .*resume $CX --dangerously-bypass-approvals-and-sandbox" "$T/agentes.log" || falhou "codex: $(cat "$T/agentes.log")"
grep -q "kiro-cli chat --v3 --trust-all-tools --resume-id $KR" "$T/agentes.log" || falhou "kiro: $(cat "$T/agentes.log")"
# conversa que não está nesta máquina: sessão nova do mesmo agente, ainda sem pedir permissões
: >"$T/agentes.log"
"$RAIZ/ia-conta" retomar codex 0ddd1111-2222-4333-8444-555566667777 >/dev/null 2>&1
grep -q -- '--yolo' "$T/agentes.log" && ! grep -q resume "$T/agentes.log" || falhou "sem a conversa: deveria abrir nova com yolo: $(cat "$T/agentes.log")"
"$RAIZ/ia-conta" retomar xyz "$CONV" >/dev/null 2>&1 && falhou 'provedor desconhecido deveria falhar'

# --- jeito de cada máquina: Termux entra no Debian do proot; Linux, Mac e WSL chamam direto
printf '#!/bin/sh\nexit 0\n' >"$B/proot-distro"; chmod +x "$B/proot-distro"
c=$(TT_AMBIENTE=termux "$TT" --snapshot-cmd-agente claude "$CONV" trabalho /root/proj)
eval "arr=($c)"; ult=${arr[${#arr[@]} - 1]}
[[ ${arr[0]} == proot-distro && ${arr[1]} == login && ${arr[2]} == debian && ${arr[*]:3:3} == "--shared-tmp -- bash" ]] || falhou "termux: $c"
[[ $ult == *"ia-conta retomar claude $CONV --conta trabalho"* && $ult == "cd /root/proj"* ]] || falhou "termux (comando de dentro): $ult"
for amb in nativo wsl proot; do
  c=$(TT_AMBIENTE=$amb "$TT" --snapshot-cmd-agente codex "$CX" "" /x)
  [[ $c == *"ia-conta retomar codex $CX"* && $c != proot-distro* ]] || falhou "$amb: $c"
done

# --- desligar para de gravar
"$TT" --snapshots off >/dev/null; n=$(nlist)
tmux new-window -t =alfa: -n quarta; "$TT" --snapshot-evento janela-criada quarta; sleep 3
[[ $(nlist) == "$n" ]] || falhou 'desligado gravou'
echo 'ok: snapshots (eventos com debounce, sem repetir, teto, restaurar aditivo/substituir com agentes retomados por máquina)'
