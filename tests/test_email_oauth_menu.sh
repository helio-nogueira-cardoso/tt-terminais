#!/usr/bin/env bash
# Espera do OAuth num terminal de verdade: era uma leitura de linha e as setas viravam ^[[A na tela.
# Agora é um menu (↑/↓, roda ou clique escolhem, ⏎ ou a tecla confirma, Esc cancela) que continua
# esperando o navegador: copiar e abrir o link inteiro, colar o endereço de volta (digitado, colado
# com marcação ou clicando na opção) e o fluxo de código no aparelho (copiar o código, aprovação
# chegando sozinha). Também: as perguntas s/N e o "Enter volta" do cadastro usam read -e.
source "$(dirname "$0")/lib.sh"; isolar
B=$T/bin; mkdir -p "$B"; LOG=$T/aberto.log; CLIP=$T/clip.txt
printf '#!/bin/sh\necho "$1" >> %s\n' "$LOG" >"$B/xdg-open"
printf '#!/bin/sh\ncat > %s\n' "$CLIP" >"$B/clip.exe"   # nunca a área de transferência real
printf '#!/bin/sh\ncat\n' >"$B/iconv"
chmod +x "$B"/*
export PATH="$B:$PATH"
printf 'nome=teste\ncopia_entre_maquinas=0\nnavegador=sistema\n' >"$XDG_CONFIG_HOME/tt/config"

# Provedor falso: /device dá o código; /token troca o código (navegador) ou, no aparelho, responde
# "pendente" duas vezes antes de aprovar.
cat >"$T/oauth.py" <<'EOF'
import http.server, json, urllib.parse
n = {"poll": 0}
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        q = dict(urllib.parse.parse_qsl(self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()))
        if self.path == "/device":
            r = {"device_code": "DC", "user_code": "WXYZ-9876", "verification_uri": "https://aparelho.example/entrar", "interval": 1, "expires_in": 60}
        elif q.get("grant_type", "").endswith("device_code"):
            n["poll"] += 1
            r = {"refresh_token": "RT_APARELHO"} if n["poll"] > 2 else {"error": "authorization_pending"}
        else:
            r = {"refresh_token": "RT_MENU", "access_token": "AT"}
        b = json.dumps(r).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H); print(s.server_address[1], flush=True); s.serve_forever()
EOF
python3 "$T/oauth.py" >"$T/porta" 2>/dev/null & sleep 1; P=$(cat "$T/porta")
conta() { # slug [device]
  printf 'nome=%s\nendereco=eu@x.test\nauth=oauth\noauth_client_id=cid\noauth_auth_endpoint=http://127.0.0.1:%s/auth\noauth_token_endpoint=http://127.0.0.1:%s/token\noauth_scope=mail\n' "$1" "$P" "$P" >"$T/$1.conf"
  [[ -n ${2:-} ]] && printf 'oauth_device_endpoint=http://127.0.0.1:%s/device\n' "$P" >>"$T/$1.conf"
  return 0
}
rodar() { # slug
  tmux kill-server 2>/dev/null || true; sleep 0.2
  tmux new -d -s m -x 110 -y 32 "python3 $TT_DIR/email-tt.py oauth-autorizar $T/$1.conf; echo FIM=\$?; sleep 60"
}
tela() { tmux capture-pane -p -t m; }
esperar() { local i; for ((i = 0; i < $2 * 4; i++)); do eval "$1" && return 0; sleep 0.25; done; return 1; }
selecionada() { tela | grep '❯' | head -1; }
sem_lixo() { ! tela | grep -qE '\^\[|\[[AB]$|\[<'; }

# --- 1) Navegador: setas, copiar, abrir, clique em "Colar" e endereço digitado -----------------------
conta nav; rodar nav
esperar 'tela | grep -q "❯ 🌐 Abrir no navegador"' 10 || falhou "menu não apareceu: $(tela)"
tmux send-keys -t m Down Down Up; sleep 0.6
[[ $(selecionada) == *'📋 Copiar o link inteiro'* ]] || falhou "setas não moveram a seleção: $(selecionada)"
sem_lixo || falhou "setas escreveram caracteres na tela: $(tela)"
passou "setas navegam no menu da espera do OAuth, sem escrever ^[[A na tela"

: >"$CLIP"; tmux send-keys -t m Enter
esperar '[[ $(cat "$CLIP" 2>/dev/null) == http://127.0.0.1:$P/auth\?* ]]' 8 || falhou "⏎ em Copiar não copiou o link: '$(cat "$CLIP")' $(tela)"
URL=$(cat "$CLIP")
menu_depois() { tela | awk -v m="$1" 'index($0, m) { a = NR } /✕ Cancelar/ { c = NR } END { exit !(a && c > a) }'; }
esperar 'menu_depois "link copiado"' 5 || falhou "menu não voltou depois de copiar: $(tela)"
(( $(tela | grep -c '✕ Cancelar') == 1 )) || falhou "menu ficou duplicado na tela: $(tela)"
: >"$LOG"; tmux send-keys -t m Up Enter
esperar '[[ $(tail -1 "$LOG" 2>/dev/null) == "$URL" ]]' 8 || falhou "⏎ em Abrir não abriu a URL inteira: '$(cat "$LOG")' $(tela)"
passou "⏎ copia o link inteiro e abre no navegador escolhido, e o menu volta"

esperar 'tela | grep -q "📥 Colar o endereço de volta"' 5 || falhou "menu sumiu: $(tela)"
y=$(tela | grep -n '📥 Colar o endereço de volta' | tail -1 | cut -d: -f1)
tmux send-keys -t m -l $'\e[<0;6;'"$y"$'M'; tmux send-keys -t m -l $'\e[<0;6;'"$y"$'m'
esperar 'tela | grep -q "Endereço de volta"' 5 || falhou "clique em Colar não pediu o endereço: $(tela)"
redir=$(python3 -c 'import sys, urllib.parse as u; q = dict(u.parse_qsl(u.urlparse(sys.argv[1]).query)); print(q["redirect_uri"] + "?code=C1&state=" + q["state"])' "$URL")
tmux send-keys -t m -l "$redir"; tmux send-keys -t m Enter
esperar 'tela | grep -q "FIM=0"' 10 || falhou "endereço digitado não concluiu: $(tela)"
tela | grep -q 'autorizado' && [[ $(cat "$HOME/.secrets/aerc-nav.txt") == RT_MENU ]] || falhou "token não gravado: $(tela)"
passou "clique em Colar pede o endereço de volta; digitado, conclui a autorização"

# --- 2) Colagem marcada (Ctrl+Shift+V) direto no menu e Esc --------------------------------------------
conta nav2; rodar nav2
esperar 'tela | grep -q "❯ 🌐 Abrir no navegador"' 10 || falhou "menu não apareceu: $(tela)"
: >"$CLIP"; tmux send-keys -t m c
esperar '[[ -s $CLIP ]]' 8 || falhou "tecla c não copiou"
URL=$(cat "$CLIP"); redir=$(python3 -c 'import sys, urllib.parse as u; q = dict(u.parse_qsl(u.urlparse(sys.argv[1]).query)); print(q["redirect_uri"] + "?code=C2&state=" + q["state"])' "$URL")
sleep 0.5; tmux send-keys -t m -l $'\e[200~'"$redir"$'\e[201~'
esperar 'tela | grep -q "FIM=0"' 10 || falhou "colar o endereço no menu não concluiu: $(tela)"
passou "colar o endereço de volta direto no menu conclui (tecla c copia)"

conta nav3; rodar nav3
esperar 'tela | grep -q "❯ 🌐 Abrir no navegador"' 10 || falhou "menu não apareceu: $(tela)"
tmux send-keys -t m Escape
esperar 'tela | grep -q "FIM=1"' 5 && tela | grep -q 'autorização cancelada' || falhou "Esc não cancelou: $(tela)"
tmux send-keys -t m Up; sleep 0.3
[[ $(tmux display -p -t m '#{cursor_flag}') == 1 ]] || falhou "cursor ficou escondido depois do menu"
passou "Esc cancela e devolve o terminal como estava"

# --- 3) Código no aparelho: copiar o código e a aprovação chega sozinha -------------------------------
conta aparelho device; rodar aparelho
esperar 'tela | grep -q "❯ 🌐 Abrir https://aparelho.example/entrar"' 10 || falhou "menu do aparelho não apareceu: $(tela)"
: >"$CLIP"; tmux send-keys -t m Down Enter
esperar '[[ $(cat "$CLIP" 2>/dev/null) == WXYZ-9876 ]]' 8 || falhou "não copiou o código: '$(cat "$CLIP")'"
esperar 'tela | grep -q "FIM=0"' 15 || falhou "aprovação no aparelho não concluiu: $(tela)"
[[ $(cat "$HOME/.secrets/aerc-aparelho.txt") == RT_APARELHO ]] || falhou "token do aparelho não gravado"
sem_lixo || falhou "lixo na tela do aparelho: $(tela)"
passou "código no aparelho: copiar o código pelo menu; a aprovação chega sem tocar em nada"

# --- 4) Perguntas do cadastro com edição de linha ------------------------------------------------------
corpo=$(sed -n '/^email_pergunta()/,/^botao_email_contas()/p' "$RAIZ/tt")
sem_e=$(grep -nE 'read -r (-p|_;)' <<<"$corpo" || true)
[[ -z $sem_e ]] || falhou "pergunta do cadastro sem read -e (setas viram ^[[A): $sem_e"
grep -q 'read -r -e -p "${1:-Enter volta.}" _' <<<"$corpo" || falhou 'email_pausa sem read -e' 
passou "perguntas s/N e o Enter volta do cadastro usam read -e"

echo "TODOS OS TESTES PASSARAM"
