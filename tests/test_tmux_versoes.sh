#!/usr/bin/env bash
# Versões de tmux misturadas na mesma máquina: um cliente 3.5a NÃO conversa com um servidor 3.6/3.8 ("server
# exited unexpectedly"; medido com 3.5a, 3.6b e 3.8: os outros pares funcionam). O PATH de um painel pode achar o
# tmux do sistema, mais velho que o que o tt compilou. Dentro do tmux o tt chama o binário do próprio servidor
# ($TMUX = socket,PID,sessão → /proc/PID/exe): as listagens, o vigia, os auxiliares em python e os comandos
# montados para popups funcionam mesmo com o PATH apontando para o tmux errado. Pulado se esta máquina não tem
# um par (velho que NÃO fala com o novo, novo): aponte TT_TMUX_VELHO e TT_TMUX_NOVO para testar em outra.
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado

fala() { # cliente servidor → 0 se o cliente conversa com um servidor desse binário (socket só deste teste)
  local sock="par-$$"
  "$2" -L "$sock" -f /dev/null kill-server 2>/dev/null
  "$2" -L "$sock" -f /dev/null new-session -d -s par 'sleep 30' 2>/dev/null || return 2
  "$1" -L "$sock" list-sessions >/dev/null 2>&1; local rc=$?
  "$2" -L "$sock" kill-server 2>/dev/null
  return $rc
}
VELHO="" NOVO=""
cands=()
for c in "${TT_TMUX_VELHO:-}" "${TT_TMUX_NOVO:-}" /usr/bin/tmux "$(command -v tmux)" "$HOME_REAL/.local/share/tt-tmux/bin/tmux" "$HOME_REAL/.local/bin/tmux"; do
  [[ -n $c && -x $c ]] && cands+=("$c")
done
for v in "${cands[@]}"; do
  for n in "${cands[@]}"; do
    [[ $(readlink -f "$v") == "$(readlink -f "$n")" ]] && continue
    if ! fala "$v" "$n"; then VELHO=$v NOVO=$n; break 2; fi
  done
done
if [[ -z $VELHO ]]; then
  echo "pulado: nenhum par de tmux que não conversa nesta máquina (um 3.5a contra um 3.6/3.8): o problema não existe aqui"
  echo "TODOS OS TESTES PASSARAM"; exit 0
fi
echo "par de teste: cliente $("$VELHO" -V) NÃO fala com servidor $("$NOVO" -V)"

# O PATH dos painéis: o tmux velho na frente.
mkdir -p "$T/shim-velho"; ln -sf "$VELHO" "$T/shim-velho/tmux"
mkdir -p "$T/shim-novo"; ln -sf "$NOVO" "$T/shim-novo/tmux"

sobe() { # binário-do-servidor → sobe o servidor do teste (conf do tt) e imprime "socket,PID,0"
  local b=$1
  "$b" -f "$HOME/.tmux.conf" new-session -d -s trabalho -x 120 -y 40 'sleep 600'
  "$b" new-session -d -s outra -x 120 -y 40 'sleep 600'
  "$b" new-session -d -s _oculta -x 120 -y 40 'sleep 600'
  "$b" display-message -p '#{socket_path},#{pid},0'
}
no_painel() { # TMUX PATH-extra comando... → como se rodasse num painel cujo PATH acha o tmux errado
  local tm=$1 pre=$2; shift 2
  env TMUX="$tm" PATH="$pre:$PATH" "$@"
}

# 1) servidor novo, PATH achando o cliente velho
tm=$(sobe "$NOVO")
saida=$(no_painel "$tm" "$T/shim-velho" tmux list-sessions 2>&1) && falhou "o cenário é vácuo: o tmux do PATH deveria falhar contra o servidor ($saida)"
grep -q 'server exited unexpectedly' <<<"$saida" || falhou "mensagem inesperada do cliente velho: $saida"
out=$(no_painel "$tm" "$T/shim-velho" "$TT" --listar-leve 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
grep -q 'trabalho' <<<"$out" && grep -q 'outra' <<<"$out" || falhou "tt --listar-leve não achou as sessões com o tmux velho no PATH: $out"
grep -q '_oculta' <<<"$out" && falhou "a sessão _oculta apareceu: $out"
out=$(no_painel "$tm" "$T/shim-velho" "$TT" --listar 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
grep -q 'trabalho' <<<"$out" || falhou "tt --listar com o tmux velho no PATH: $out"
passou 'servidor novo + tmux velho no PATH: o tt chama o tmux do servidor e lista as sessões'

# 2) o tt manda o binário certo aos filhos e às strings de comando dos popups
b=$(no_painel "$tm" "$T/shim-velho" bash -c 'source <(sed -n "/^TT_TMUX_BIN=tmux/,/^export TT_TMUX_BIN/p" "$1"); echo "$TT_TMUX_BIN"' _ "$TT")
[[ $(readlink -f "$b") == "$(readlink -f "$NOVO")" ]] || falhou "TT_TMUX_BIN deveria ser o do servidor ($NOVO): $b"
no_painel "$tm" "$T/shim-novo" bash -c 'source <(sed -n "/^TT_TMUX_BIN=tmux/,/^export TT_TMUX_BIN/p" "$1"); echo "$TT_TMUX_BIN"' _ "$TT" | grep -qx tmux ||
  falhou 'com o tmux certo no PATH nada muda (TT_TMUX_BIN fica "tmux")'
passou 'TT_TMUX_BIN aponta para o servidor só quando o PATH acha outro; igual ao PATH, fica "tmux"'

# 3) a barrinha de painéis e a poda (comandos que o tmux.conf dispara por gancho) funcionam com o tmux velho no PATH
no_painel "$tm" "$T/shim-velho" "$TT" --bordas >/dev/null 2>&1 || falhou 'tt --bordas falhou com o tmux velho no PATH'
n=$(no_painel "$tm" "$T/shim-velho" "$TT" --fechar-vazias 2>&1) || falhou "tt --fechar-vazias falhou com o tmux velho no PATH: $n"
[[ $n =~ ^[0-9]+$ ]] || falhou "--fechar-vazias deveria imprimir um número: $n"
passou 'ganchos do tmux.conf (--bordas) e poda (--fechar-vazias) funcionam com o tmux velho no PATH'

# 4) o auxiliar de links em python acha o servidor pelo $TMUX
pid=${tm#*,}; pid=${pid%%,*}
r=$(no_painel "$tm" "$T/shim-velho" python3 -I - "$RAIZ/links-tt.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("links_tt", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.tmux("display-message", "-p", "#{pid}").strip())
PY
)
[[ $r == "$pid" ]] || falhou "links-tt.py não falou com o servidor (esperado pid $pid, veio '$r')"
passou 'links-tt.py usa o tmux do servidor (pelo $TMUX)'
"$NOVO" kill-server 2>/dev/null
# O servidor só sai depois de despachar os ganchos do fechamento (session-closed e window-unlinked, um run-shell por sessão e
# aba): até lá o socket é dele, e o cliente velho do 5) dava "server exited unexpectedly" e não criava a sessão "trabalho".
for _ in $(seq 1 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done

# 5) o inverso: servidor velho, PATH achando o novo (clientes novos falam com servidores velhos)
tm=$(sobe "$VELHO")
out=$(no_painel "$tm" "$T/shim-novo" "$TT" --listar-leve 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
grep -q 'trabalho' <<<"$out" || falhou "servidor velho + tmux novo no PATH: $out"
passou 'servidor velho + tmux novo no PATH: também funciona'
"$VELHO" kill-server 2>/dev/null
echo "TODOS OS TESTES PASSARAM"
