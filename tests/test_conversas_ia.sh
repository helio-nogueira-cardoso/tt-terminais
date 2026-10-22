#!/usr/bin/env bash
# tt --sessoes-ia-sync: conversas do Claude Code, do Codex e do Kiro CLI iguais em todas as máquinas.
# Sem rede: o ssh é falso e roda o comando remoto aqui mesmo, num segundo HOME ("a outra máquina",
# com outra home: /…/dest em vez de /…/home), com o mesmo tt. Cobre: cópia com a home traduzida
# (pasta do projeto do Claude, "cwd" das linhas, linha do banco do Codex, cwd do Kiro), ida e volta
# com os mesmos bytes, conversa que só cresceu do outro lado, nada a fazer na segunda volta,
# divergência (fica a mais nova, a outra guardada), conversa em uso fica para depois, memory/ do
# Claude fica em cada máquina, máquina desligada (sessoes_ia_sync=0) e tt antigo pulados.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
export TT_SESSOES_QUIETO=60 TT_SESSOES_LOTE=1 # um lote por conversa: a troca passa por vários lotes

D=$T/dest; mkdir -p "$D/.local/bin" "$D/.config/tt"; ln -s "$TT" "$D/.local/bin/tt"
export DEST=$D
B=$HOME/.local/bin
cat >"$B/ssh" <<'EOF'
#!/usr/bin/env bash
cmd=${*: -1}
printf '%s\n' "$cmd" >>"$SSH_LOG"
case ${MODO_SSH:-} in
  # a rede cai no 2º envio de lote (celular que dorme no meio da primeira troca)
  cai) [[ $cmd == *--sessoes-ia-aplicar* ]] && { n=$(($(cat "$SSH_LOG.cai" 2>/dev/null || echo 0) + 1)); echo $n >"$SSH_LOG.cai"
         ((n >= 2)) && { cat >/dev/null; echo "Connection reset" >&2; exit 255; }; } ;;
  antigo) echo "tt: opção desconhecida: ${cmd##* } (tt --help mostra as principais)" >&2; exit 2 ;;
  # o inventário responde e a puxada cai (o Mac que acorda um instante e volta a dormir)
  caipuxa) [[ $cmd == *--sessoes-ia-empacotar* ]] && { echo "Connection reset" >&2; exit 255; } ;;
esac
exec env HOME="$DEST" XDG_CONFIG_HOME="$DEST/.config" bash -c "$cmd"
EOF
chmod +x "$B/ssh"
export SSH_LOG=$T/ssh.log
printf 'destino-host helio outra\n' >"$XDG_CONFIG_HOME/tt/maquinas"
printf 'nome=outra\n' >"$D/.config/tt/config"

enc() { sed 's/[^A-Za-z0-9]/-/g' <<<"$1"; }
velho() { touch -d '-1 hour' "$@"; }
U1=11111111-1111-4111-8111-111111111111
C1=01a10711-53eb-7352-aae1-35b7464da130
K1=22222222-2222-4222-8222-222222222222

# --- Origem: uma conversa de cada IA, na pasta de um projeto dentro da home ---------------------
PA=$HOME/.claude/projects/$(enc "$HOME/proj")
mkdir -p "$PA/$U1/subagents" "$PA/memory" "$D/.claude"
printf '{"type":"user","cwd":"%s/proj","sessionId":"%s","message":"oi"}\n' "$HOME" "$U1" >"$PA/$U1.jsonl"
printf '{"type":"assistant","cwd":"%s/proj","sessionId":"%s","message":"ola"}\n' "$HOME" "$U1" >>"$PA/$U1.jsonl"
printf '{"type":"user","cwd":"%s/proj","agent":"a1"}\n' "$HOME" >"$PA/$U1/subagents/agent-a1.jsonl"
echo 'memoria desta maquina' >"$PA/memory/MEMORY.md"
cp "$PA/$U1.jsonl" "$T/original.jsonl"

CX=$HOME/.codex; RO=sessions/2026/10/04/rollout-2026-10-04T10-18-58-$C1.jsonl
mkdir -p "$CX/${RO%/*}" "$D/.codex"
printf '{"type":"session_meta","payload":{"id":"%s","cwd":"%s/proj"}}\n{"type":"turn_context","payload":{"cwd":"file://%s/proj"}}\n' "$C1" "$HOME" "$HOME" >"$CX/$RO"
printf '{"id":"%s","thread_name":"Conversa do Codex","updated_at":"2026-10-04T13:20:00Z"}\n' "$C1" >"$CX/session_index.jsonl"
esquema='create table threads (id text primary key, rollout_path text not null, created_at integer not null, updated_at integer not null, cwd text not null, title text not null'
python3 - "$CX/state_5.sqlite" "$D/.codex/state_5.sqlite" "$esquema" "$C1" "$CX/$RO" "$HOME/proj" <<'PY'
import sqlite3, sys
a, b, esq, i, ro, cwd = sys.argv[1:]
c = sqlite3.connect(a); c.execute(esq + ", git_sha text)")
c.execute("insert into threads values (?,?,?,?,?,?,?)", (i, ro, 1, 100, cwd, "Conversa do Codex", "abc")); c.commit()
sqlite3.connect(b).execute(esq + ")")  # do outro lado, sem a coluna git_sha (versão diferente do Codex)
PY

KI=$HOME/.kiro/sessions/cli; mkdir -p "$KI" "$D/.kiro/sessions/cli"
printf '{\n  "session_id": "%s",\n  "cwd": "%s/proj",\n  "updated_at": "2026-10-06T18:24:51Z"\n}\n' "$K1" "$HOME" >"$KI/$K1.json"
printf '{"m":"oi kiro"}\n' >"$KI/$K1.jsonl"
velho "$PA/$U1.jsonl" "$PA/$U1/subagents/agent-a1.jsonl" "$PA/memory/MEMORY.md" "$CX/$RO" "$KI/$K1".*

# --- rede cai no meio: o lote entregue fica, a volta seguinte continua -------------------------
out=$(MODO_SSH=cai "$TT" --sessoes-ia-sync 2>&1)
grep -q 'outra .*falhou' <<<"$out" || falhou "queda no meio deveria aparecer como falha: $out"
n1=$( (find "$D/.claude" "$D/.codex/sessions" "$D/.kiro/sessions/cli" -type f 2>/dev/null || true) | wc -l)
((n1 >= 1)) || falhou 'o lote entregue antes da queda não ficou'
ls "$D/.local/state/tt/sessoes-ia" | grep -q '^entrada\.' && falhou 'sobrou pasta de recepção'
passou "rede caindo no meio: o lote entregue fica ($n1 arquivo(s)), sem sobra"

# --- 1ª volta completa: tudo chega do outro lado, com a home de lá ------------------------------
out=$("$TT" --sessoes-ia-sync 2>&1) || falhou "sync falhou: $out"
grep -q 'outra .*ok' <<<"$out" || falhou "sem resultado da máquina: $out"
PD=$D/.claude/projects/$(enc "$D/proj")
[[ -f $PD/$U1.jsonl ]] || falhou "conversa do Claude não chegou na pasta do projeto de lá: $(find "$D/.claude" -type f)"
grep -qF "\"cwd\":\"$D/proj\"" "$PD/$U1.jsonl" || falhou "cwd não foi traduzido: $(cat "$PD/$U1.jsonl")"
grep -qF "$HOME/" "$PD/$U1.jsonl" && falhou 'sobrou a home de origem na conversa copiada'
[[ -f $PD/$U1/subagents/agent-a1.jsonl ]] || falhou 'subagente não foi junto'
[[ -e $PD/memory ]] && falhou 'memory/ do Claude foi copiada (é de cada máquina)'
[[ $(stat -c %a "$PD/$U1.jsonl") == 600 ]] || falhou 'conversa copiada deveria ser 600'
passou 'Claude: conversa e subagente na pasta do projeto de lá, cwd traduzido, memory/ fica'

[[ -f $D/.codex/$RO ]] || falhou 'rollout do Codex não chegou'
grep -qF "\"cwd\":\"file://$D/proj\"" "$D/.codex/$RO" || falhou "cwd file:// do Codex não traduzido: $(cat "$D/.codex/$RO")"
linha=$(python3 -c 'import sqlite3,sys; print("|".join(map(str, sqlite3.connect(sys.argv[1]).execute("select rollout_path,cwd,title from threads").fetchone() or ())))' "$D/.codex/state_5.sqlite")
[[ $linha == "$D/.codex/$RO|$D/proj|Conversa do Codex" ]] || falhou "linha do banco do Codex errada: $linha"
grep -q "$C1" "$D/.codex/session_index.jsonl" || falhou 'nome da conversa do Codex (session_index) não chegou'
passou 'Codex: rollout, linha do banco (colunas em comum) e índice de nomes, com a home de lá'

grep -qF "\"cwd\": \"$D/proj\"" "$D/.kiro/sessions/cli/$K1.json" || falhou "Kiro: cwd não traduzido: $(cat "$D/.kiro/sessions/cli/$K1.json")"
[[ -f $D/.kiro/sessions/cli/$K1.jsonl ]] || falhou 'Kiro: .jsonl não foi junto'
passou 'Kiro: estado e transcrição, com a home de lá'

# --- 2ª volta: nada a fazer ---------------------------------------------------------------------
out=$("$TT" --sessoes-ia-sync 2>&1)
grep -q 'outra .*ok .*trazidas 0 .*levadas 0' <<<"$out" || falhou "segunda volta deveria não trocar nada: $out"
passou 'segunda volta: nada a trocar'

# --- continuada lá: volta mais longa, e com os bytes de cá -------------------------------------
printf '{"type":"user","cwd":"%s/proj","sessionId":"%s","message":"continuei la"}\n' "$D" "$U1" >>"$PD/$U1.jsonl"
velho "$PD/$U1.jsonl"
out=$("$TT" --sessoes-ia-sync 2>&1)
grep -q 'continuei la' "$PA/$U1.jsonl" || falhou "a continuação de lá não voltou: $out"
head -c "$(stat -c %s "$T/original.jsonl")" "$PA/$U1.jsonl" | cmp -s - "$T/original.jsonl" || falhou 'a ida e a volta mudaram os bytes do começo'
tail -n 1 "$PA/$U1.jsonl" | grep -qF "\"cwd\":\"$HOME/proj\"" || falhou 'a linha nova não voltou com a home de cá'
passou 'continuada na outra máquina: volta mais longa, mesmos bytes, home de cá'

# --- divergiu: fica a mais nova e a outra é guardada --------------------------------------------
printf '{"type":"user","cwd":"%s/proj","message":"aqui A"}\n' "$HOME" >>"$PA/$U1.jsonl"; touch -d '-50 minutes' "$PA/$U1.jsonl"
printf '{"type":"user","cwd":"%s/proj","message":"la B"}\n' "$D" >>"$PD/$U1.jsonl"; touch -d '-40 minutes' "$PD/$U1.jsonl"
out=$("$TT" --sessoes-ia-sync 2>&1)
grep -q 'la B' "$PA/$U1.jsonl" || falhou "a mais nova (de lá) deveria ter ficado: $out"
grep -rq 'aqui A' "$HOME/.local/state/tt/sessoes-ia/conflitos/claude" || falhou 'a versão daqui não foi guardada nos conflitos'
cmp -s "$PA/$U1.jsonl" <(sed "s#$D/proj#$HOME/proj#g" "$PD/$U1.jsonl") || falhou 'depois do conflito as duas máquinas deveriam ter a mesma conversa'
passou 'divergência: fica a mais nova nas duas, a outra guardada em conflitos/'

# --- em uso: fica para a próxima volta ----------------------------------------------------------
printf '{"type":"user","cwd":"%s/proj","message":"em uso"}\n' "$HOME" >>"$PA/$U1.jsonl"
out=$("$TT" --sessoes-ia-sync 2>&1)
grep -q 'em uso' "$PD/$U1.jsonl" && falhou 'conversa em uso (mexida agora) foi copiada'
passou 'conversa em uso fica para a próxima volta'

# --- volta que falha no meio: a hora da última boa fica, e o --checar não acusa -----------------
est=$HOME/.local/state/tt/sessoes-ia/maquinas/outra
IFS=$'\t' read -r t_ok st_ok _ _ _ _ boa <"$est"
[[ $st_ok == ok && $boa == "$t_ok" ]] || falhou "volta boa deveria gravar a hora dela no 7º campo: $(cat "$est")"
U2=33333333-3333-4333-8333-333333333333
printf '{"type":"user","cwd":"%s/proj","sessionId":"%s","message":"nova la"}\n' "$D" "$U2" >"$PD/$U2.jsonl"; velho "$PD/$U2.jsonl"
out=$(MODO_SSH=caipuxa "$TT" --sessoes-ia-sync 2>&1)
grep -q 'outra .*falhou' <<<"$out" || falhou "a puxada que cai deveria dar falha: $out"
IFS=$'\t' read -r _ st _ _ _ _ boa <"$est"
[[ $st == falhou && $boa == "$t_ok" ]] || falhou "a falha apagou a hora da última boa: $(cat "$est")"
grep -q 'outra .*falhou.*(última boa: ' <<<"$("$TT" --sessoes-ia)" || falhou "o estado não mostra a última boa: $("$TT" --sessoes-ia)"
linha=$( ("$TT" --checar --tsv || true) | grep $'^sessoes-ia\t')   # sai 1 se outra checagem falha aqui
[[ $linha == $'sessoes-ia\tok\t'* ]] || falhou "uma falha logo depois de uma troca boa não é aviso: $linha"
printf '%s\tfalhou\t1\t0\t-\t-\t%s\n' "$(date +%s)" "$(($(date +%s) - 3 * 86400))" >"$est"
linha=$( ("$TT" --checar --tsv || true) | grep $'^sessoes-ia\t')   # sai 1 se outra checagem falha aqui
[[ $linha == $'sessoes-ia\taviso\t'*outra* ]] || falhou "sem troca boa há 3 dias deveria ser aviso: $linha"
out=$("$TT" --sessoes-ia-sync 2>&1); grep -q 'outra .*ok' <<<"$out" || falhou "a volta seguinte deveria trazer a conversa nova: $out"
[[ -f $PA/$U2.jsonl ]] || falhou 'a conversa que ficou para trás não chegou na volta seguinte'
passou 'volta que falha no meio: a última boa fica guardada, o --checar só acusa depois de 2 dias'

# --- desligada lá e tt antigo: pulada, sem erro --------------------------------------------------
echo 'sessoes_ia_sync=0' >>"$D/.config/tt/config"
out=$("$TT" --sessoes-ia-sync 2>&1) || falhou "falhou com a outra desligada: $out"
grep -q 'outra .*pulada' <<<"$out" || falhou "máquina desligada deveria ser pulada: $out"
sed -i '/^sessoes_ia_sync=/d' "$D/.config/tt/config"
out=$(MODO_SSH=antigo "$TT" --sessoes-ia-sync 2>&1) || falhou "falhou com tt antigo: $out"
grep -q 'outra .*pulada' <<<"$out" || falhou "tt antigo deveria ser pulado: $out"
passou 'máquina com o sync desligado e tt antigo: pulados sem erro'

# --- liga/desliga e estado ----------------------------------------------------------------------
out=$("$TT" --sessoes-ia off 2>&1); grep -q 'desligada' <<<"$out" || falhou "off não desligou: $out"
out=$("$TT" --sessoes-ia-sync); grep -q 'desligada' <<<"$out" || falhou "desligado aqui ainda sincronizou: $out"
"$TT" --sessoes-ia on >/dev/null
out=$("$TT" --sessoes-ia)
grep -q 'sincronizadas entre as máquinas' <<<"$out" && grep -q 'claude .*2 conversas' <<<"$out" && grep -q 'outra ' <<<"$out" ||
  falhou "estado incompleto: $out"
passou 'tt --sessoes-ia on/off/status'
