#!/usr/bin/env bash
# Hora confiável: o tt mede o desvio do relógio da máquina contra endpoints HTTPS (aqui, servidores
# locais falsos com o relógio adiantado), usa relógio + desvio nas tarefas e na barra, e volta ao
# relógio da máquina sem rede, desligado, com medida velha ou com fontes que não concordam.
# Isola HOME/XDG/TT_RT e o tmux; os servidores falsos morrem com a pasta do teste.
source "$(dirname "$0")/lib.sh"; isolar
tt() { "$TT" "$@"; }
fail() { echo "FALHOU: $1" >&2; exit 1; }
export no_proxy=127.0.0.1 NO_PROXY=127.0.0.1
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy

# Servidor falso: responde a qualquer GET com o relógio andado OFFSET segundos (cabeçalho Date em
# segundos inteiros; no caminho */trace, também "ts=" com milissegundos, como o cdn-cgi/trace).
cat >"$T/srv.py" <<'PY'
import sys, time, http.server, email.utils
off = float(sys.argv[2])
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        t = time.time() + off
        corpo = ("ts=%.3f\n" % t) if self.path.endswith("/trace") else "ok\n"
        self.send_response_only(200)          # sem o Date automático (esse é o relógio verdadeiro)
        self.send_header("Date", email.utils.formatdate(int(t), usegmt=True))
        self.send_header("Content-Length", str(len(corpo)))
        self.end_headers(); self.wfile.write(corpo.encode())
    def log_message(self, *a): pass
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(srv.server_address[1]))
srv.serve_forever()
PY
servidor() { # offset -> imprime a porta (roda em subshell: o arquivo da porta é único por mktemp, não por contador)
  local f; f=$(mktemp "$T/porta.XXXXXX")
  python3 -I "$T/srv.py" "$f" "$1" >/dev/null 2>&1 &
  for _ in $(seq 1 50); do [[ -s $f ]] && break; sleep 0.1; done
  [[ -s $f ]] || fail "servidor falso não subiu"
  cat "$f"
}
dentro() { # valor alvo tolerância
  local d=$(( $1 - $2 )); ((d < 0)) && d=$((-d)); ((d <= $3))
}
ARQ="$TT_RT/tt-hora"

P1=$(servidor 400); P2=$(servidor 400); P3=$(servidor 0); P4=$(servidor 172800)
U1="http://127.0.0.1:$P1/x/trace"; U2="http://127.0.0.1:$P2/x"; U0="http://127.0.0.1:$P3/x"; UL="http://127.0.0.1:$P4/x"

# 1) duas fontes concordando (uma com ts= em milissegundos, outra só com Date): grava o desvio
[[ ! -e $ARQ ]] || fail "não deveria haver medida antes de medir"
saida=$(tt --hora); grep -q 'sem medida' <<<"$saida" || fail "sem medida, tt --hora deveria dizer que vale o relógio da máquina"
TT_HORA_URLS="$U1 $U2" tt --hora --sincronizar >/dev/null || fail "medir com duas fontes concordando falhou"
d=$(cut -d' ' -f1 "$ARQ"); dentro "$d" 400 2 || fail "desvio medido deveria ser ~400 s (veio $d)"
dentro "$(tt --hora agora)" "$(( $(date +%s) + 400 ))" 2 || fail "tt --hora agora deveria somar o desvio ao relógio da máquina"
saida=$(tt --hora); grep -q "desvio .*+4[0-9][0-9] s" <<<"$saida" || fail "tt --hora não mostra o desvio: $saida"
echo "ok: mede o desvio contra duas fontes (ts= e Date) e tt --hora agora = relógio + desvio"

# 2) as tarefas usam a hora confiável (criada/mudada), não o relógio da máquina
tt --tarefa-add "relogio certo" >/dev/null
cr=$(awk -F'\t' '$5=="relogio certo"{print $3}' "$XDG_CONFIG_HOME/tt/tarefas")
dentro "$cr" "$(( $(date +%s) + 400 ))" 3 || fail "a tarefa deveria nascer com a hora confiável (criada=$cr, máquina+400=$(( $(date +%s) + 400 )))"
echo "ok: tarefa criada com a hora confiável"

# 3) a barra: desvio ≥ 60 s mostra a hora já corrigida; desvio pequeno volta ao %H:%M do tmux
tmux -f /dev/null new -d -s s1 'sleep 300'
tt --barras >/dev/null 2>&1
h=$(tmux show -gqv @barra_hora)
c1=$(date -d "@$(( $(date +%s) + 398 ))" +%H:%M); c2=$(date -d "@$(( $(date +%s) + 402 ))" +%H:%M)
[[ $h == "$c1" || $h == "$c2" ]] || fail "@barra_hora deveria ser a hora corrigida ($c1), veio '$h'"
grep -q '@barra_hora' <<<"$(tmux show -gqv @barra_faixa_dir)" || fail "o lado direito da faixa não usa @barra_hora"
printf '10 %s teste\n' "$(date +%s)" >"$ARQ"
tt --barras >/dev/null 2>&1
[[ $(tmux show -gqv @barra_hora) == '%H:%M' ]] || fail "com desvio pequeno a barra deveria voltar ao %H:%M do tmux (veio '$(tmux show -gqv @barra_hora)')"
echo "ok: barra mostra a hora corrigida com desvio ≥ 60 s e o %H:%M do tmux com desvio pequeno"

# 4) fontes que discordam, uma fonte absurda, endpoint morto e hora_sync=0: nada é gravado
rm -f "$ARQ"
TT_HORA_URLS="$U1 $U0" tt --hora --sincronizar >/dev/null 2>&1 && fail "duas fontes discordando (+400 e 0) não deveriam valer"
[[ ! -e $ARQ ]] || fail "fontes discordando não podem gravar medida"
TT_HORA_URLS="$UL" tt --hora --sincronizar >/dev/null 2>&1 && fail "uma fonte só com 2 dias de desvio não deveria valer"
[[ ! -e $ARQ ]] || fail "desvio absurdo de uma fonte só não pode gravar medida"
TT_HORA_URLS="http://127.0.0.1:9/x" tt --hora --sincronizar >/dev/null 2>&1 && fail "endpoint morto não deveria medir nada"
[[ ! -e $ARQ ]] || fail "endpoint morto não pode gravar medida"
printf 'hora_sync=0\n' >>"$XDG_CONFIG_HOME/tt/config"
TT_HORA_URLS="$U1 $U2" tt --hora --sincronizar >/dev/null 2>&1 && fail "hora_sync=0 deveria desligar a medida"
[[ ! -e $ARQ ]] || fail "hora_sync=0 não pode gravar medida"
sed -i '/^hora_sync=0$/d' "$XDG_CONFIG_HOME/tt/config"
dentro "$(tt --hora agora)" "$(date +%s)" 2 || fail "sem medida, vale o relógio da máquina"
echo "ok: discordância, fonte absurda, endpoint morto e hora_sync=0 deixam o relógio da máquina"

# 5) uma fonte plausível basta; medida velha demais é ignorada (e dita)
TT_HORA_URLS="$U1" tt --hora --sincronizar >/dev/null || fail "uma fonte plausível deveria bastar"
dentro "$(cut -d' ' -f1 "$ARQ")" 400 2 || fail "desvio de uma fonte só: $(cat "$ARQ")"
printf '500 %s teste\n' "$(( $(date +%s) - 90000 ))" >"$ARQ"
dentro "$(tt --hora agora)" "$(date +%s)" 2 || fail "medida de 25 h atrás não pode valer"
saida=$(tt --hora); grep -q 'velho demais' <<<"$saida" || fail "tt --hora deveria dizer que a medida está velha"
dentro "$(TT_HORA_VALE=100000 tt --hora agora)" "$(( $(date +%s) + 500 ))" 2 || fail "TT_HORA_VALE deveria alargar a validade"
echo "ok: uma fonte plausível basta; medida velha demais é ignorada"

# 6) o vigia mede sozinho (a cada TT_T_HORA, e de 15 em 15 min enquanto não houver medida)
grep -q -- '--hora --sincronizar' "$TT" && grep -q 'TT_T_HORA' "$TT" || fail "o vigia não agenda a medição da hora"
echo "ok: vigia agenda a medição"
echo "TODOS OS TESTES PASSARAM"
