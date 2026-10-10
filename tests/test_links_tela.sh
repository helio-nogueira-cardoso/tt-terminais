#!/usr/bin/env bash
# Links em qualquer painel, de ponta a ponta (tmux.conf instalado, cliente anexado e mouse SGR de
# verdade): clique num endereço partido em várias linhas (quebra do terminal ou do próprio programa,
# com recuo, como no Claude Code) abre a URL inteira; duplo clique copia o link inteiro; arrastar
# copia sem a quebra e o recuo; num programa que captura o mouse, o clique fora de link continua
# indo para ele; Ctrl+B u lista os links; com navegador=perguntar, o clique abre a escolha do
# navegador. Antes, o links-tt.py puro: o que religa e o que deixa como está.
source "$(dirname "$0")/lib.sh"; isolar
PY=$TT_DIR/links-tt.py

# --- 1) links-tt.py: religar e desquebrar -----------------------------------------------------------
python3 -I - "$PY" <<'EOF' || falhou "links-tt.py (casos sintéticos)"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("lk", sys.argv[1]); lk = importlib.util.module_from_spec(spec); spec.loader.exec_module(lk)
U = "https://accounts.google.com/o/oauth2/auth?client_id=123&redirect_uri=http%3A%2F%2F127.0.0.1&scope=x&state=XYZ"
W, erros = 40, []
def chk(nome, obtido, esperado):
    if obtido != esperado:
        erros.append(f"{nome}: obtido={obtido!r} esperado={esperado!r}")
t1 = ["Abra:", "", U[:40], U[40:80], U[80:], "", "fim"]
for y in (2, 3, 4):
    chk(f"quebra do terminal, linha {y}", lk.url_em(t1, W, 5, y), U)
chk("fora do link", lk.url_em(t1, W, 1, 6), "")
cc = ["● Abra: " + U[:31], "  " + U[31:68], "  " + U[68:105], "  " + U[105:], "  e depois volte."]
for y in range(4):
    chk(f"recuo estilo Claude Code, linha {y}", lk.url_em(cc, W, 4, y) if y else lk.url_em(cc, W, 10, 0), U)
chk("texto depois do link", lk.url_em(cc, W, 5, 4), "")
caixa = ["╭" + "─" * 38 + "╮"] + ["│ " + U[i:i + 36].ljust(36) + " │" for i in range(0, len(U), 36)] + ["╰" + "─" * 38 + "╯"]
chk("dentro de caixa", lk.url_em(caixa, W, 20, 2), U)
curta = ["● Veja https://github.com/foo/barbazqux", "  para mais detalhes."]
chk("URL curta na borda não gruda no texto de baixo", lk.url_em(curta, W, 10, 0), "https://github.com/foo/barbazqux")
chk("linha seguinte começa outro link", [u for u, *_ in lk.urls([U[:40], "https://outro.com/x"], W)], [U[:40], "https://outro.com/x"])
chk("pontuação e parênteses", [u for u, *_ in lk.urls(["[aqui](https://x.com/a_(b)) e (https://y.com/z)."], 80)], ["https://x.com/a_(b)", "https://y.com/z"])
chk("emoji largo antes", lk.url_em(["📋 " + U[:36], U[36:76], U[76:]], W, 20, 1), U)
chk("cópia estilo Claude Code", lk.desquebrar("● Abra: " + U[:31] + "\n  " + U[31:68] + "\n  " + U[68:] + "\n  e depois volte.", W, 0), "● Abra: " + U + "\n  e depois volte.")
chk("cópia começando no meio da linha", lk.desquebrar(U[:31] + "\n  " + U[31:68] + "\n  " + U[68:], W, 8), U)
prosa = "Esta frase longa chega bem na bordaaaa\nseguinte linha comum de texto."
chk("prosa na borda fica", lk.desquebrar(prosa, W, 0), prosa)
cod = "    cp /home/helio/arquivo.txt /tmp/dest\n    echo pronto"
chk("código na borda fica", lk.desquebrar(cod, W, 0), cod)
cam = "/home/helio/.local/share/tt/um/caminho/muito/longo/arquivo.txt"
chk("caminho partido pelo terminal", lk.desquebrar(cam[:40] + "\n" + cam[40:], W, 0), cam)
chk("código longo partido com recuo", lk.desquebrar("  " + "a" * 38 + "\n  " + "b" * 22, W, 0), "  " + "a" * 38 + "b" * 22)
chk("linha já juntada pelo tmux", lk.desquebrar(U + "\nfim", W, 0), U + "\nfim")
chk("largura desconhecida não mexe", lk.desquebrar(U[:40] + "\n" + U[40:], 0, 0), U[:40] + "\n" + U[40:])
if erros:
    print("\n".join(erros), file=sys.stderr); sys.exit(1)
EOF
passou "links-tt.py religa quebra do terminal, recuo e caixa, sem grudar prosa nem código"

# --- 2) De ponta a ponta no tmux ---------------------------------------------------------------------
B=$T/bin; mkdir -p "$B"; LOG=$T/aberto.log; CLIP=$T/clip.txt
printf '#!/bin/sh\necho "$1" >> %s\n' "$LOG" >"$B/xdg-open"
printf '#!/bin/sh\ncat > %s\n' "$CLIP" >"$B/clip.exe"   # nunca a área de transferência real
printf '#!/bin/sh\ncat\n' >"$B/iconv"
chmod +x "$B"/*
export PATH="$B:$PATH"
cfg() { printf 'nome=teste\ncopia_entre_maquinas=0\n%s\n' "$1" >"$XDG_CONFIG_HOME/tt/config"; }
cfg navegador=sistema
instalar_isolado

L=100
U="https://accounts.google.com/o/oauth2/auth?client_id=123456789-abcdefghijk.apps.googleusercontent.com&response_type=code&redirect_uri=http%3A%2F%2F127.0.0.1%3A40123%2F&scope=https%3A%2F%2Fmail.google.com%2F&state=Kq1-ZzT8#fim"
U2="https://example.com/um/endereco/que/o/terminal/quebra/sozinho/porque/passa/da/largura/da/tela/inteira?x=1&y=2"
# Tela no estilo do Claude Code: o programa quebra o endereço na coluna 99 e recua a continuação.
cat >"$T/tela.sh" <<EOF
printf '\033[2J\033[H'
printf '%s\n' "Abra no navegador:" "" "● Entre: ${U:0:90}" "  ${U:90:97}" "  ${U:187}" "  e volte aqui." "" "$U2" "" "texto sem link nenhum"
exec sleep 100000
EOF
tmux -f "$HOME/.tmux.conf" new -d -s minha -x $L -y 30 "bash --norc $T/tela.sh" 2>/dev/null
anexar v $L 32 minha; sleep 4

# Linha (1-based na tela do cliente) onde está o texto; o painel começa no topo.
linha() { fora capture-pane -p -t v | grep -nF -- "$1" | head -1 | cut -d: -f1; }
apertar() { fora send -t v -l $'\e[<'"${3:-0};$1;$2"$'M'; }
soltar() { fora send -t v -l $'\e[<'"${3:-0};$1;$2"$'m'; }
clicar() { apertar "$1" "$2" "${3:-0}"; sleep 0.05; soltar "$1" "$2" "${3:-0}"; }
esperar() { local i; for ((i = 0; i < $2 * 4; i++)); do eval "$1" && return 0; sleep 0.25; done; return 1; }
abriu() { [[ -s $LOG && $(tail -1 "$LOG") == "$1" ]]; }

y1=$(linha "● Entre: https"); y2=$((y1 + 1)); y3=$((y1 + 2)); ys=$(linha 'texto sem link')
[[ -n $y1 && -n $ys ]] || falhou "tela de teste não apareceu: $(fora capture-pane -p -t v)"

: >"$LOG"; clicar 20 "$y2"
esperar 'abriu "$U"' 6 || falhou "clique na 2ª linha não abriu a URL inteira: '$(cat "$LOG")'"
passou "clique no meio de um link partido pelo programa (com recuo) abre a URL inteira"

: >"$LOG"; clicar 3 "$y3"
esperar 'abriu "$U"' 6 || falhou "clique na última linha do link não abriu a URL inteira: '$(cat "$LOG")'"
yw=$(linha "${U2:0:40}"); : >"$LOG"; clicar 5 $((yw + 1))
esperar 'abriu "$U2"' 6 || falhou "clique na continuação da quebra do terminal não abriu a URL: '$(cat "$LOG")'"
passou "clique na última linha e na quebra do próprio terminal também abrem a URL inteira"

: >"$LOG"; clicar 5 "$ys"; sleep 1.5
[[ ! -s $LOG ]] || falhou "clique fora de link abriu algo: $(cat "$LOG")"
passou "clique fora de link não abre nada"

# Duplo clique: copia o link inteiro e não abre.
: >"$LOG"; : >"$CLIP"
clicar 30 "$y2"; sleep 0.08; clicar 30 "$y2"
esperar '[[ $(cat "$CLIP" 2>/dev/null) == "$U" ]]' 6 || falhou "duplo clique não copiou o link inteiro: '$(cat "$CLIP")'"
[[ $(tmux show-buffer) == "$U" ]] || falhou "buffer do tmux sem o link inteiro: '$(tmux show-buffer)'"
sleep 0.6; [[ ! -s $LOG ]] || falhou "duplo clique também abriu o link: $(cat "$LOG")"
passou "duplo clique num link copia o link inteiro (tmux e área de transferência) e não abre"

# Arrastar do começo do link até o fim da 3ª linha: a cópia vem sem a quebra e sem o recuo.
: >"$CLIP"; : >"$LOG"
x0=$(( $(fora capture-pane -p -t v | sed -n "${y1}p" | python3 -c 'import sys; print(sys.stdin.read().index("https"))') + 1 ))
apertar "$x0" "$y1"; sleep 0.1
fora send -t v -l $'\e[<32;'"$((x0 + 5));$y1"$'M'; sleep 0.1
fora send -t v -l $'\e[<32;30;'"$y2"$'M'; sleep 0.1
fora send -t v -l $'\e[<32;'"$((3 + ${#U} - 187));$y3"$'M'; sleep 0.1
soltar "$((3 + ${#U} - 187))" "$y3"
esperar '[[ $(cat "$CLIP" 2>/dev/null) == "$U" ]]' 6 || falhou "arrasto não religou o link: '$(cat "$CLIP" | cat -A | head -5)'"
[[ $(tmux show-buffer) == "$U" ]] || falhou "buffer do tmux ficou com a cópia partida: '$(tmux show-buffer | cat -A | head -3)'"
sleep 0.6; [[ ! -s $LOG ]] || falhou "arrastar a partir de um link abriu o link: $(cat "$LOG")"
passou "arrastar sobre um link partido copia a URL inteira, sem quebra nem recuo (e não abre)"

# Ctrl+B u: os links da tela num popup.
fora send -t v C-b u; sleep 2
tela=$(fora capture-pane -p -t v)
grep -q 'links da tela' <<<"$tela" && grep -qF "${U2:0:60}" <<<"$tela" || falhou "Ctrl+B u não listou os links: $tela"
fora send -t v Escape; sleep 1
passou "Ctrl+B u lista os links do painel"

# navegador=perguntar: o clique abre a escolha (as três opções do e-mail, mais copiar).
cfg navegador=perguntar; : >"$LOG"
clicar 20 "$y2"; sleep 2.5
tela=$(fora capture-pane -p -t v)
grep -q 'abrir link' <<<"$tela" && grep -q 'Google Chrome interno' <<<"$tela" && grep -q 'Carbonyl' <<<"$tela" &&
  grep -q 'Navegador padrão do sistema' <<<"$tela" || falhou "clique não abriu a escolha do navegador: $tela"
fora send -t v Down Down Enter; sleep 1.5
esperar 'abriu "$U"' 6 || falhou "escolher o navegador do sistema não abriu a URL inteira: '$(cat "$LOG")'"
passou "com navegador=perguntar, o clique abre a escolha e o navegador do sistema recebe a URL inteira"
cfg navegador=sistema

# Programa que captura o mouse (como o Claude Code): fora de link o clique continua indo para ele; num
# link, abre o link e o programa não recebe o clique.
cat >"$T/app.py" <<EOF
import os, sys, termios, tty
U = "$U"
sys.stdout.write("\033[?1000h\033[?1006h\033[2J\033[H")
sys.stdout.write("● Entre: " + U[:90] + "\r\n  " + U[90:187] + "\r\n  " + U[187:] + "\r\n\r\nclique aqui fora\r\n")
sys.stdout.flush()
tty.setraw(0)
with open("$T/app.log", "ab", buffering=0) as f:
    while True:
        f.write(os.read(0, 1024))
EOF
tmux new-window -t minha "python3 -I $T/app.py"; sleep 2
ya=$(linha 'clique aqui fora'); yl=$(( $(linha "● Entre: https") + 1 ))
: >"$T/app.log"; clicar 3 "$ya"; sleep 0.8
grep -q $'\e\\[<0;3;'"$ya"'M' "$T/app.log" || falhou "programa com mouse não recebeu o clique fora de link: '$(cat -v "$T/app.log")'"
: >"$T/app.log"; : >"$LOG"; clicar 20 "$yl"
esperar 'abriu "$U"' 6 || falhou "clique no link dentro de programa com mouse não abriu: '$(cat "$LOG")'"
grep -q $'\e\\[<0;20;'"$yl"'M' "$T/app.log" && falhou "o programa recebeu o clique que abriu o link"
passou "programa que captura o mouse: clique fora de link chega a ele; no link, abre o link"

# Ctrl+clique abre na hora (sem esperar o tempo do duplo clique).
: >"$LOG"; clicar 20 "$yl" 16
esperar 'abriu "$U"' 3 || falhou "Ctrl+clique não abriu o link: '$(cat "$LOG")'"
passou "Ctrl+clique num link abre a URL inteira"

# Carbonyl (navegador no terminal) sobe num popup grande. Escolhido no seletor (que já é um popup, e o
# tmux não abre popup sobre popup), ele sobe quando o seletor fecha. A URL tem "#", que o run-shell
# lia como formato do tmux: tem que chegar inteira.
car=$HOME/.local/share/tt-navegadores/carbonyl/carbonyl-0.0.3/carbonyl; mkdir -p "${car%/*}"
printf '#!/bin/sh\nfor a; do u=$a; done\necho "$u" >> %s\nsleep 1\n' "$T/carbonyl.log" >"$car"; chmod +x "$car"
cfg navegador=carbonyl; : >"$T/carbonyl.log"
clicar 20 "$yl"
esperar '[[ $(tail -1 "$T/carbonyl.log" 2>/dev/null) == "$U" ]]' 8 || falhou "navegador=carbonyl não recebeu a URL inteira: '$(cat "$T/carbonyl.log")'"
sleep 1.5; cfg navegador=perguntar; : >"$T/carbonyl.log"
clicar 20 "$yl"; sleep 2.5
grep -q 'Carbonyl' <<<"$(fora capture-pane -p -t v)" || falhou "seletor não apareceu: $(fora capture-pane -p -t v)"
fora send -t v Down Enter
esperar '[[ $(tail -1 "$T/carbonyl.log" 2>/dev/null) == "$U" ]]' 8 || falhou "Carbonyl escolhido no seletor não abriu (popup sobre popup?): '$(cat "$T/carbonyl.log")'"
passou "Carbonyl abre com a URL inteira (com #), direto ou escolhido no seletor"
cfg navegador=sistema

# O Carbonyl só sai com Ctrl+C e o popup só fecha quando ele sai: o Ctrl+Q do título tem que fechar.
# (espera o popup do caso anterior fechar antes de trocar o script: o sh lê o script aos poucos)
esperar '! fora capture-pane -p -t v | grep -q "navegador ·"' 6 || falhou "popup do caso anterior não fechou"
cat >"$car" <<FALSO
#!/usr/bin/env python3
import os, sys, tty
open("$T/carbonyl.log", "a").write(sys.argv[-1] + "\n")
open("$T/carbonyl.tam", "w").write("%d %d\n" % tuple(os.get_terminal_size()))
tty.setraw(0)
while b"\x03" not in os.read(0, 64): pass
FALSO
chmod +x "$car"; cfg navegador=carbonyl; : >"$T/carbonyl.log"
clicar 20 "$yl"
esperar '[[ $(tail -1 "$T/carbonyl.log" 2>/dev/null) == "$U" ]]' 8 || falhou "Carbonyl (que só sai com Ctrl+C) não abriu"
esperar 'fora capture-pane -p -t v | grep -q "Ctrl+Q (ou Ctrl+C) fecha"' 5 || falhou "popup do navegador não apareceu: $(fora capture-pane -p -t v)"
# Subjanela (tam_popup: 90% x 85% em tela grande), não tela cheia: menos que o cliente menos a borda.
read -r cc cl <"$T/carbonyl.tam"
(( cc < L - 2 && cl < 32 - 2 )) || falhou "popup do navegador em tela cheia (${cc}x${cl} num cliente ${L}x32)"
fora send -t v C-q
esperar '! fora capture-pane -p -t v | grep -q "Ctrl+Q (ou Ctrl+C) fecha"' 6 || falhou "Ctrl+Q não fechou o popup do Carbonyl: $(fora capture-pane -p -t v)"
passou "Ctrl+Q fecha o popup do Carbonyl (que sozinho só sai com Ctrl+C)"
cfg navegador=sistema

# --- 3) Cadastro OAuth com navegador: a URL é longa demais para uma linha ------------------------------
# c ⏎ copia o link inteiro, ⏎ abre pela escolha do navegador, e colar o endereço de volta conclui.
cat >"$T/token.py" <<'EOF'
import http.server, json
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        b = json.dumps({"refresh_token": "RT_NAV", "access_token": "AT"}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H); print(s.server_address[1], flush=True); s.serve_forever()
EOF
python3 "$T/token.py" >"$T/porta" 2>/dev/null & sleep 1; P=$(cat "$T/porta")
"$TT" --email-adicionar nome=Nav endereco=eu@nav.test imap_host=imap.nav.test imap_porta=993 imap_seg=tls smtp_host=smtp.nav.test \
  smtp_porta=587 smtp_seg=starttls auth=oauth oauth_client_id=cid "oauth_auth_endpoint=http://127.0.0.1:$P/auth" \
  "oauth_token_endpoint=http://127.0.0.1:$P/token" "oauth_scope=mail" >/dev/null || falhou 'cadastro OAuth com navegador'
: >"$LOG"; : >"$CLIP"
saida=$(python3 -I - "$TT_DIR/email-tt.py" "$XDG_CONFIG_HOME/tt/email/nav.conf" "$CLIP" "$LOG" <<'EOF'
import subprocess, sys, time, urllib.parse
py, conf, clip, log = sys.argv[1:5]
p = subprocess.Popen(["python3", py, "oauth-autorizar", conf], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
url = ""
while not url:
    l = p.stdout.readline()
    if not l: sys.exit("o fluxo terminou sem mostrar a URL")
    if "/auth?" in l: url = l.strip()
def espera(arq, alvo):
    for _ in range(40):
        if open(arq).read().strip() == alvo: return True
        time.sleep(0.25)
    return False
p.stdin.write("c\n"); p.stdin.flush()
if not espera(clip, url): sys.exit("c ⏎ não copiou a URL inteira: " + open(clip).read())
p.stdin.write("\n"); p.stdin.flush()
if not espera(log, url): sys.exit("⏎ não abriu a URL inteira: " + open(log).read())
q = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(url).query))
p.stdin.write(q["redirect_uri"] + "?code=CODIGO&state=" + q["state"] + "\n"); p.stdin.flush()
print(p.communicate(timeout=20)[0]); sys.exit(p.returncode)
EOF
) || falhou "fluxo OAuth com navegador: $saida"
grep -q 'autorizado' <<<"$saida" && [[ $(cat "$HOME/.secrets/aerc-nav.txt") == RT_NAV ]] || falhou "autorização não concluiu: $saida"
passou "cadastro OAuth: c ⏎ copia o link inteiro, ⏎ abre pela escolha do navegador, colar o retorno conclui"

echo "TODOS OS TESTES PASSARAM"
