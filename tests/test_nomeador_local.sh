#!/usr/bin/env bash
# Nomeador local: instalação com sha256 conferido (motor e modelo de um servidor HTTP falso), pacote com
# caminho suspeito recusado, nome pelo llama-server (falso) com gramática e temperatura 0, servidor
# derrubado depois de cada nome, modos auto/local/claude/nenhum (local e nenhum nunca chamam o Claude)
# e remoção. Nada é baixado da internet.
source "$(dirname "$0")/lib.sh"; isolar
export TT_NOMEADOR_DIR=$T/nomeador TT_NOMEADOR_RAM_GB=16 TT_NOMEADOR_PRAZO=20
PY=$TT_DIR/nomeador-local.py
mkdir -p "$T/bin" "$T/srv/fonte/llama-b11455" "$T/mau/x"

# Claude falso: só deixa um rastro (os modos local e nenhum não podem chamá-lo).
printf '#!/bin/sh\ncat >/dev/null; touch %q; echo claude-falou\n' "$T/claude-chamado" >"$T/bin/claude"
chmod +x "$T/bin/claude"; export PATH=$T/bin:$PATH

# llama-server falso: /health e /v1/chat/completions; grava o pedido e o próprio PID.
cat >"$T/srv/fonte/llama-b11455/llama-server" <<'PY'
#!/usr/bin/env python3
import http.server, json, os, sys
a = sys.argv; porta = int(a[a.index("--port") + 1]); d = os.environ["TT_NOMEADOR_DIR"]
open(d + "/falso.pid", "w").write(str(os.getpid()))
if os.path.exists(d + "/falso.morre"):
    sys.exit(3)
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *x): pass
    def responder(self, obj):
        b = json.dumps(obj).encode(); self.send_response(200)
        self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def do_GET(self): self.responder({"status": "ok"})
    def do_POST(self):
        corpo = self.rfile.read(int(self.headers["Content-Length"]))
        open(d + "/pedido.json", "wb").write(corpo)
        nome = open(d + "/falso.nome").read().strip() if os.path.exists(d + "/falso.nome") else "tarefa-teste"
        self.responder({"choices": [{"message": {"content": nome}}]})
http.server.HTTPServer(("127.0.0.1", porta), H).serve_forever()
PY
chmod +x "$T/srv/fonte/llama-b11455/llama-server"
tar -czf "$T/srv/motor.tar.gz" -C "$T/srv/fonte" llama-b11455
head -c 4096 /dev/urandom >"$T/srv/modelo.gguf"
# Pacote malicioso: um arquivo que tenta sair da pasta de extração.
tar -czf "$T/srv/mau.tar.gz" -C "$T/mau" --transform 's|^x|../../fora|' x
sha() { sha256sum "$1" | cut -d' ' -f1; }
python3 -u -m http.server 0 --bind 127.0.0.1 --directory "$T/srv" >"$T/http.log" 2>&1 & HTTP_PID=$!
for _ in $(seq 50); do P=$(grep -oE 'port [0-9]+' "$T/http.log" | grep -oE '[0-9]+' || true); [[ -n $P ]] && break; sleep 0.1; done
[[ -n ${P:-} ]] || falhou 'servidor HTTP falso não subiu'
plat=$(python3 -c 'import platform as p; s,m=p.system(),p.machine().lower(); a="arm64" if m in("aarch64","arm64") else "x64"; print(("macos-" if s=="Darwin" else "linux-")+a)')
catalogo() { # arquivo-do-motor sha-do-motor sha-do-modelo
  printf '{"url_motor": "http://127.0.0.1:%s/", "motores": {"%s": ["%s", "%s"]}, "modelos": {"4b": ["modelo.gguf", 4096, "%s", "http://127.0.0.1:%s/modelo.gguf"]}}' \
    "$P" "$plat" "$1" "$2" "$3" "$P" >"$T/catalogo.json"
}
export TT_NOMEADOR_CATALOGO=$T/catalogo.json

# sha256 errado: nada fica instalado nem pela metade.
catalogo motor.tar.gz "$(sha "$T/srv/motor.tar.gz")" 0000
"$TT" --nomeador-local instalar >/dev/null 2>&1 && falhou 'instalou com sha256 errado do modelo'
[[ -e $TT_NOMEADOR_DIR/modelo.gguf || -e $TT_NOMEADOR_DIR/modelo.gguf.part ]] && falhou 'modelo com sha256 errado ficou no disco'
"$TT" --nomeador-local estado | grep -qx 'instalado=0' || falhou 'estado diz instalado sem modelo'
# Pacote com caminho para fora da pasta: recusado.
rm -rf "$TT_NOMEADOR_DIR"
catalogo mau.tar.gz "$(sha "$T/srv/mau.tar.gz")" "$(sha "$T/srv/modelo.gguf")"
r=$("$TT" --nomeador-local instalar 2>&1) && falhou 'aceitou pacote com caminho suspeito'
grep -q 'suspeito' <<<"$r" || falhou "recusa do pacote suspeito sem motivo: $r"
[[ -e $T/fora || -e $TT_NOMEADOR_DIR/../fora ]] && falhou 'pacote suspeito escreveu fora da pasta'
passou 'instalação recusa sha256 errado e pacote com caminho suspeito'

# Instalação certa.
rm -rf "$TT_NOMEADOR_DIR"
catalogo motor.tar.gz "$(sha "$T/srv/motor.tar.gz")" "$(sha "$T/srv/modelo.gguf")"
"$TT" --nomeador-local instalar >"$T/inst" 2>&1 || falhou "instalação: $(tail -3 "$T/inst")"
e=$("$TT" --nomeador-local estado)
grep -qx 'instalado=1' <<<"$e" && grep -qx 'modelo=modelo.gguf' <<<"$e" || falhou "estado depois de instalar: $e"
grep -qx "servidor=$TT_NOMEADOR_DIR/motor-b11455/llama-b11455/llama-server" <<<"$e" || falhou "servidor fora do lugar: $e"
[[ -e $TT_NOMEADOR_DIR/motor.tar.gz ]] && falhou 'tar do motor ficou para trás'
passou 'instalação baixa motor e modelo, confere sha256 e grava a configuração'

# Nome pelo modelo local (modo padrão auto): gramática, temperatura 0, e o servidor morre depois.
r=$(printf 'Pasta: ~/projeto\nÚltimos pedidos do usuário:\n- consertar o relatório\nTela:\n$ make\n' | "$TT" --nomear-texto) || falhou 'nomear-texto falhou com modelo local'
[[ $r == tarefa-teste ]] || falhou "nome do modelo local: $r"
python3 - "$TT_NOMEADOR_DIR/pedido.json" <<'PY' || falhou 'pedido ao llama-server sem gramática/temperatura/instrução'
import json, re, sys
p = json.load(open(sys.argv[1]))
assert "root ::=" in p["grammar"] and p["temperature"] == 0 and p["max_tokens"] <= 16
assert p["messages"][0]["role"] == "system" and "consertar o relatório" in p["messages"][1]["content"]
# A gramática aceita somente 1–3 palavras de 1–16 caracteres alfanuméricos.
regras = dict(l.split(" ::= ", 1) for l in p["grammar"].strip().splitlines())
palavra = regras["palavra"]
padrao = regras["root"].replace('"', '').replace('palavra', '(?:' + palavra + ')')
padrao = re.compile(re.sub(r'\s+', '', padrao))
for nome in ('a', 'contas-corrigidas', 'a-b-c', 'a' * 16, 'a' * 16 + '-0-' + 'b' * 16):
    assert padrao.fullmatch(nome), nome
for nome in ('', 'a' * 17, 'a-b-c-d', '-a', 'a-', 'a--b', 'Nome', 'ação', 'a b'):
    assert not padrao.fullmatch(nome), nome
# Conta derivações por comprimento: cada palavra precisa ter uma só. O padrão
# antigo de opcionais independentes tinha C(15, n-1) caminhos e travava no Termux.
token = r'\[a-z0-9\](?:\?|\{\d+,\d+\})?'
assert not re.sub(token, '', palavra).strip(), palavra
contagens = {0: 1}
for item in re.findall(token, palavra):
    if item.endswith('?'): minimo, maximo = 0, 1
    elif '{' in item: minimo, maximo = map(int, item.split('{')[1].rstrip('}').split(','))
    else: minimo = maximo = 1
    novas = {}
    for antes, caminhos in contagens.items():
        for tamanho in range(minimo, maximo + 1):
            novas[antes + tamanho] = novas.get(antes + tamanho, 0) + caminhos
    contagens = novas
assert contagens == dict.fromkeys(range(1, 17), 1), contagens
PY
pid=$(cat "$TT_NOMEADOR_DIR/falso.pid"); sleep 0.3
kill -0 "$pid" 2>/dev/null && falhou 'llama-server continuou rodando depois do nome'
[[ -e $T/claude-chamado ]] && falhou 'modo auto chamou o Claude mesmo com o modelo local respondendo'
passou 'nome vem do modelo local (gramática, temperatura 0) e o servidor é derrubado em seguida'

# Resposta fora do formato: rejeitada; no modo local não cai no Claude.
"$TT" --nomeador local >/dev/null
echo 'Nome Errado!' >"$TT_NOMEADOR_DIR/falso.nome"
echo 'Pasta: ~' | "$TT" --nomear-texto >/dev/null && falhou 'aceitou nome fora do formato'
rm -f "$TT_NOMEADOR_DIR/falso.nome"; touch "$TT_NOMEADOR_DIR/falso.morre"
echo 'Pasta: ~' | "$TT" --nomear-texto >/dev/null && falhou 'servidor que morre deu nome'
[[ -e $T/claude-chamado ]] && falhou 'modo local chamou o Claude'
# Modo auto com o local quebrado: cai no Claude (comportamento de antes).
"$TT" --nomeador auto >/dev/null
echo 'Pasta: ~' | "$TT" --nomear-texto >/dev/null 2>&1
[[ -e $T/claude-chamado ]] || falhou 'modo auto não caiu no Claude com o modelo local quebrado'
rm -f "$T/claude-chamado"
"$TT" --nomeador nenhum >/dev/null
echo 'Pasta: ~' | "$TT" --nomear-texto >/dev/null && falhou 'modo nenhum deu nome'
[[ -e $T/claude-chamado ]] && falhou 'modo nenhum chamou o Claude'
"$TT" --nomeador talvez >/dev/null && falhou 'aceitou modo inválido'
grep -qx 'nomeador=nenhum' "$XDG_CONFIG_HOME/tt/config" || falhou 'modo não gravado no config'
passou 'modos: local e nenhum nunca chamam o Claude; auto cai nele quando o local falha; formato validado'

"$TT" --nomeador-local remover >/dev/null || falhou 'remover'
[[ -e $TT_NOMEADOR_DIR ]] && falhou 'remover deixou a pasta'
passou 'remover apaga motor e modelo'
# Interface: o menu do painel tem o item e a rota existe; a tela sem terminal fecha sem travar.
grep -q '🧠 Nomeador de abas: \$(modo_nomeador)…' "$TT" || falhou 'menu do painel sem o item do nomeador'
grep -Fq -- '--nomeador-ui) nomeador_ui' "$TT" || falhou 'rota --nomeador-ui ausente'
timeout 10 "$TT" --nomeador-ui </dev/null >/dev/null 2>&1 || falhou 'tela do nomeador travou ou falhou sem terminal'
passou 'menu do painel → 🧠 Nomeador de abas abre a tela (rota --nomeador-ui)'
kill "$HTTP_PID" 2>/dev/null || true
