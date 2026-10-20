#!/usr/bin/env bash
# Snapshots do estado: ligam/desligam, gravam a cada evento (com debounce), não repetem estado igual, guardam no máximo TT_SNAP_MAX,
# mostram data/hora, restauram (aditivo e substituir) recriando abas, painéis, layout, fixadas e RETOMANDO a conversa de cada agente
# do jeito da máquina (direto, ou no Debian do proot do Termux), sempre sem pedir permissões (ia-conta retomar).
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
cli=$(tmux list-clients -F '#{client_name}' 2>/dev/null | head -1); : "${cli:=}"

# --- desligado por padrão: evento não grava nada
st=$("$TT" --snapshots status); [[ $st == *desligados* ]] || falhou 'deveria nascer desligado'
tmux new-session -d -s alfa -x 120 -y 40 -c "$T"
"$TT" --snapshot-evento sessao-criada alfa; sleep 2
[[ $(nlist) == 0 ]] || falhou 'desligado não deve gravar'

# --- um agente de mentira: um processo chamado "claude" no painel, com a conversa registrada pelo pid
mkdir -p "$T/proj" "$HOME/.claude/sessions"
CONV=0aaa1111-2222-4333-8444-555566667777
printf '#!/usr/bin/env bash\nsleep 600\n' >"$B/claude-falso"; chmod +x "$B/claude-falso"; nomear_script "$B/claude-falso" claude
tmux new-session -d -s beta -x 120 -y 40 -c "$T/proj" "$B/claude-falso"
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
# agente de mentira do ia-conta: registra os argumentos (é o que o painel restaurado executa)
cat >"$HOME/.local/bin/ia-conta" <<FIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$T/retomar.log"
FIM
chmod +x "$HOME/.local/bin/ia-conta"
tmux new-session -d -s gama -c "$T"   # sessão que o snapshot não tem
out=$("$TT" --snapshot-restaurar "$ID" aditivo gama 2>&1)
tmux has-session -t =alfa && tmux has-session -t =beta || falhou "aditivo não recriou: $out"
tmux has-session -t =gama || falhou 'aditivo não pode fechar sessão que não está no snapshot'
[[ $(tmux list-windows -t =alfa: | wc -l | tr -d ' ') == 3 ]] || falhou "alfa deveria ter 3 abas: $(tmux list-windows -t =alfa:)"
[[ $(tmux list-panes -t =alfa:segunda | wc -l | tr -d ' ') == 2 ]] || falhou 'a aba "segunda" deveria ter 2 painéis'
sleep 2
grep -q "retomar claude $CONV" "$T/retomar.log" 2>/dev/null || falhou "o agente não foi retomado na mesma conversa: $(cat "$T/retomar.log" 2>/dev/null)"
mot=$("$TT" --snapshots-listar | sed -n 1p | cut -f3); [[ $mot == *"restaurado de"* ]] || falhou "restaurar deveria gravar 'restaurado de': $mot"
mot=$("$TT" --snapshots-listar | cut -f3); [[ $mot == *"antes de restaurar"* ]] || falhou 'restaurar deveria gravar o estado de antes'

# aditivo de novo: tudo existe, nada muda
n=$(tmux list-windows -t =alfa: | wc -l | tr -d ' ')
"$TT" --snapshot-restaurar "$ID" aditivo gama >/dev/null 2>&1
[[ $(tmux list-windows -t =alfa: | wc -l | tr -d ' ') == "$n" ]] || falhou 'aditivo duplicou abas de sessão que já existia'

# --- substituir fecha o que não está no snapshot (menos a sessão em uso e as ocultas)
tmux new-session -d -s _oculta -c "$T"; tmux new-session -d -s delta -c "$T"
"$TT" --snapshot-restaurar "$ID" substituir gama >/dev/null 2>&1
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
"$TT" --snapshot-restaurar "$ID2" substituir gama >/dev/null 2>&1
[[ $(cut -f2 "$FIX" | tr '\n' ' ') == "alfa beta " ]] || falhou "substituir deveria deixar as fixadas do snapshot: $(cat "$FIX")"

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
