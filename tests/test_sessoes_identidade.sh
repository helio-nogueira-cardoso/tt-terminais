#!/usr/bin/env bash
# tt-teste: sozinho
# ID persistente: criação concorrente, rename, grupos, exclusão/recriação e ambiguidade.
source "$(dirname "$0")/lib.sh"; isolar
TT_SO_CARREGAR=1 source "$TT"; EU=$TT

tmux -f /dev/null new-session -d -s original 'sleep 600'
tmux new-session -d -s origem 'sleep 600'
"$TT" --rapido gerar >/dev/null
pids=()
for i in {1..24}; do
  "$TT" --session-id original >"$T/id-$i" & pids+=("$!")
done
esperar "${pids[@]}"
id=$(cat "$T/id-1")
[[ $id =~ ^[0-9a-f]{32}$ ]] || falhou 'ID não foi atribuído'
for i in {1..24}; do [[ $(cat "$T/id-$i") == "$id" ]] || falhou 'criação concorrente trocou o ID'; done
passou '24 criadores concorrentes recebem um único ID, gravado uma vez'

tmux new-session -d -s agrupada -t original
id_grupo=$(session_id agrupada)
[[ -n $id_grupo && $id_grupo != "$id" ]] || falhou 'grupo de sessões herdou o ID da outra sessão'
tmux rename-session -t '=original' nome-completamente-diferente
[[ $(session_id nome-completamente-diferente) == "$id" ]] || falhou 'rename alterou ID'
[[ $(session_by_id "$id") == nome-completamente-diferente ]] || falhou 'ID não resolveu nome novo'
passou 'nome muda livremente; ID permanece e distingue sessões agrupadas'

fora new -d -s cliente -x 100 -y 30 "env -u TMUX TERM=xterm-256color TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t origem"
for i in {1..100}; do
  cliente=$(tmux list-clients -F '#{client_name}' 2>/dev/null | head -1)
  [[ -n $cliente ]] && break
  sleep .02
done
[[ -n $cliente ]] || falhou 'cliente de teste não anexou'
export TMUX=$(tmux display-message -p '#{socket_path},#{pid},0')
printf '%s\toriginal\t%s\n' "$MAQUINA" "$id" >"$CONF_FIX"
fixada_chave_em chave "$MAQUINA" original "$id"
"$TT" --ir-fixada "$cliente" "fx$chave"
[[ $(tmux list-clients -F '#{session_name}') == nome-completamente-diferente ]] || falhou 'fixada usou nome antigo em vez do ID'
passou 'fixada com nome antigo abre a sessão renomeada pelo mesmo ID'

tmux switch-client -c "$cliente" -t '=origem'
tmux kill-session -t '=nome-completamente-diferente'
tmux new-session -d -s original 'sleep 600'
id_novo=$(session_id original)
[[ $id_novo != "$id" ]] || falhou 'sessão recriada reutilizou ID'
[[ -z $(session_by_id "$id") ]] || falhou 'ID removido resolveu outra sessão'
"$TT" --ir-fixada "$cliente" "fx$chave" || true
[[ $(tmux list-clients -F '#{session_name}') == origem ]] || falhou 'fallback por nome abriu uma sessão recriada'
passou 'sessão removida/recriada com mesmo nome recebe outro ID e não herda o destino antigo'
# A conferência periódica também não pode substituir o UUID conhecido pelo da sessão homônima.
aplicar_fixadas() { :; }
propagar_fixadas() { :; }
reconciliar_fixadas
! grep -q "$id_novo" "$CONF_FIX" || falhou 'reconciliação herdou sessão homônima'
reconciliar_fixadas
! grep -q "$id_novo" "$CONF_FIX" || falhou 'segunda conferência herdou sessão homônima'
passou 'reconciliação mantém identidade conhecida ou retira o destino morto; nunca o reatribui pelo nome'


tmux new-session -d -s duplicada-a 'sleep 600'
tmux new-session -d -s duplicada-b 'sleep 600'
tmux set-option -t '=duplicada-a:' @tt_session_id cccccccccccccccccccccccccccccccc
tmux set-option -t '=duplicada-b:' @tt_session_id cccccccccccccccccccccccccccccccc
[[ -z $(session_by_id cccccccccccccccccccccccccccccccc) ]] || falhou 'ID ambíguo escolheu primeira sessão'
python3 - "$RAIZ" <<'PY'
import sys
sys.path.insert(0,sys.argv[1])
import precarregar_remoto as p
assert p.remote_target('duplicada-a','c'*32) is None
PY
passou 'ID duplicado por alteração externa é recusado, sem desempate pelo nome'

tmux new-session -d -s sem-id 'sleep 600'
id_remoto=$(python3 - "$RAIZ" <<'PY'
import sys
sys.path.insert(0,sys.argv[1])
import precarregar_remoto as p
value=p.remote_target('sem-id')
assert value and len(value['id'])==32
print(value['id'])
PY
)
[[ $(session_id sem-id) == "$id_remoto" ]] || falhou 'protocolo e CLI criaram IDs diferentes'
passou 'descoberta inicial atribui ID único e depois CLI/protocolo usam a mesma identidade'

# A trava cobre também a checagem de unicidade: uma colisão não é atribuída a outra sessão.
tmux new-session -d -s colisao 'sleep 600'
python3 - "$RAIZ" <<'PY_COLLISION'
import sys,subprocess
from types import SimpleNamespace
from unittest.mock import patch
sys.path.insert(0,sys.argv[1])
import precarregar_remoto as p
sid=subprocess.check_output(['tmux','display-message','-p','-t','=colisao:','#{session_id}'],text=True).strip()
with patch.object(p.uuid,'uuid4',side_effect=[SimpleNamespace(hex='c'*32),SimpleNamespace(hex='f'*32)]) as gen:
 assert p.ensure_identity(sid)=='f'*32
 assert gen.call_count==2
PY_COLLISION
passou 'colisão de ID detectada antes de gravar; identificador existente nunca é reutilizado'
