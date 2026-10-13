#!/usr/bin/env bash
# E-mail em lote e comandos garantidos: email-tt.py lote-contar/lote-agir contra um IMAP falso (busca do tt →
# SEARCH, só os UIDs contados, blocos de 500, MOVE ou COPY+EXPUNGE, lixeira/arquivo/destino, recusas
# seguras); tt --email-lote sem terminal exige --sim e chama contar → agir; ☑ Tudo (botão e Ctrl+a) marca e
# desmarca pelo IPC do aerc; toda conta com lixeira ganha d → lixeira, sem lixeira o d avisa que apaga de
# vez; tt --email-conferir e o tt --checar acusam lixeira desconhecida ou ausente do espelho e corrigem.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
PY=$TT_DIR/email-tt.py

# --- 1) email-tt.py contra um IMAP falso -------------------------------------------------------------------
python3 -I - "$PY" "$T" <<'EOF' || falhou "email-tt.py lote (IMAP falso)"
import importlib.util, io, contextlib, json, os, sys
spec = importlib.util.spec_from_file_location("et", sys.argv[1]); et = importlib.util.module_from_spec(spec); spec.loader.exec_module(et)
T = sys.argv[2]
et.credencial = lambda c: ("senha", "x")
erros = []
def ok(cond, msg):
    if not cond: erros.append(msg)
class Falso:
    caps = "IMAP4rev1 MOVE UIDPLUS X-GM-EXT-1 ENABLE UTF8=ACCEPT"
    pastas = ['(\\HasNoChildren) "/" "INBOX"', '(\\HasNoChildren \\Trash) "/" "[Gmail]/Lixeira"',
              '(\\HasNoChildren \\All) "/" "[Gmail]/Todos os e-mails"', '(\\HasNoChildren) "/" "Recibos"', '(\\Noselect \\HasChildren) "/" "[Gmail]"']
    uids = list(range(1, 1201)); uv = b"77"; log = []
    def __init__(self, *a, **k): self._encoding = "ascii"; self.capabilities = ("IMAP4REV1",)  # cumprimento: sem ENABLE (Gmail)
    def login(self, u, s): pass
    def capability(self): return "OK", [Falso.caps.encode()]
    def list(self): return "OK", [p.encode() for p in Falso.pastas]
    def select(self, caixa, readonly=False):
        self.state = "SELECTED"; Falso.log.append(f"select {caixa} {'ro' if readonly else 'rw'}"); return "OK", [b"1200"]
    def response(self, k): return k, [Falso.uv]
    def enable(self, c):  # como no imaplib: ENABLE só no estado AUTH (antes do SELECT)
        if getattr(self, "state", "AUTH") != "AUTH": raise et.imaplib.IMAP4.error(f"command ENABLE illegal in state {self.state}")
        if "ENABLE" not in self.capabilities: raise et.imaplib.IMAP4.error("Server does not support ENABLE")
        Falso.log.append(f"enable {c}")
    def uid(self, cmd, *args):
        Falso.log.append(f"{cmd} " + " ".join(str(a) for a in args))
        if cmd == "SEARCH": return "OK", [" ".join(map(str, Falso.uids)).encode()]
        if cmd == "FETCH": return "OK", [(b"1 (BODY[HEADER] {9}", b"From: Ana <ana@x.com>\r\nSubject: Oferta\r\nDate: Tue, 1 Oct 2024 10:00:00 +0000\r\n\r\n")]
        return "OK", [b""]
    def expunge(self): Falso.log.append("EXPUNGE-todas"); return "OK", [b""]
    def logout(self): pass
et.imaplib.IMAP4_SSL = Falso
c = {"imap_host": "imap.gmail.com", "endereco": "eu@x.com"}
def rodar(f, *a):
    Falso.log = []; out = io.StringIO(); err = io.StringIO(); rc = None; exc = None
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err): rc = f(*a)
    except Exception as e: exc = e
    return out.getvalue(), err.getvalue(), exc

# critérios
ok(et.lote_criterio("todas") == ["ALL"], "todas → ALL")
ok(et.lote_criterio('nao-lidas de:ana@x.com assunto:"fatura de" antes:2025-01-02 maior:5m') ==
   ["UNSEEN", "FROM", '"ana@x.com"', "SUBJECT", '"fatura de"', "BEFORE", "02-Jan-2025", "LARGER", str(5 * 1048576)], f"critérios: {et.lote_criterio('nao-lidas de:ana@x.com assunto:\"fatura de\" antes:2025-01-02 maior:5m')}")
ok(et.lote_criterio("gmail:'older_than:1y'", {"X-GM-EXT-1"}) == ["X-GM-RAW", '"older_than:1y"'], "gmail: → X-GM-RAW")
for ruim in ("gmail:x", "antes:ontem", "maior:muito"):
    try: et.lote_criterio(ruim); erros.append(f"{ruim} deveria ser recusado")
    except RuntimeError: pass

# contar: total, amostra e UIDs salvos
sel = os.path.join(T, "sel.json")
out, err, exc = rodar(et.lote_contar, c, "INBOX", "todas", 3, sel)
ok(exc is None and "total=1200" in out and out.count("amostra\t2024-10-01\tAna\tOferta") == 3, f"contar: {out} {err} {exc}")
ok(json.load(open(sel))["uids"][:2] == ["1", "2"] and json.load(open(sel))["uidvalidity"] == "77", "UIDs e UIDVALIDITY salvos")
ok(all(not l.startswith(("STORE", "MOVE", "COPY")) for l in Falso.log) and "select \"INBOX\" ro" in Falso.log, f"contar só lê: {Falso.log}")
# busca com acento: o UTF8=ACCEPT é ligado antes do SELECT (depois dele o imaplib recusa o ENABLE) e com as
# capacidades de depois do login (o cumprimento do Gmail não anuncia ENABLE)
out, err, exc = rodar(et.lote_contar, c, "INBOX", 'assunto:"edição"', 0, None)
ok(exc is None and "total=1200" in out, f"busca com acento: {exc}")
ok("enable UTF8=ACCEPT" in Falso.log and Falso.log.index("enable UTF8=ACCEPT") < Falso.log.index('select "INBOX" ro'), f"ENABLE antes do SELECT: {Falso.log}")

# apagar no Gmail: MOVE para a lixeira em blocos de 500, só os UIDs contados
Falso.uids = list(range(1, 5000))  # chegaram mais depois da contagem: não entram
out, err, exc = rodar(et.lote_agir, c, sel, "apagar")
moves = [l for l in Falso.log if l.startswith("MOVE")]
ok(exc is None and len(moves) == 3 and all(l.endswith('"[Gmail]/Lixeira"') for l in moves) and "feito=1200" in out, f"apagar: {moves} {out} {exc}")
ok(moves[0].split()[1].split(",")[-1] == "500" and moves[2].split()[1].split(",")[-1] == "1200", "blocos de 500 com os UIDs contados")
ok("progresso=1200/1200" in err, f"progresso no stderr: {err}")
out, err, exc = rodar(et.lote_agir, c, sel, "apagar", None, True)
ok(exc is not None and "Gmail" in str(exc), "no Gmail, --de-vez fora da lixeira é recusado")
# arquivar no Gmail = tirar da pasta (STORE \Deleted + UID EXPUNGE), sem mover
out, err, exc = rodar(et.lote_agir, c, sel, "arquivar")
ok(exc is None and any(l.startswith("STORE") and "\\Deleted" in l for l in Falso.log) and any(l.startswith("EXPUNGE") for l in Falso.log) and not any(l.startswith("MOVE") for l in Falso.log), f"arquivar Gmail: {Falso.log[:6]}")
# mover para pasta que existe / que não existe
out, err, exc = rodar(et.lote_agir, c, sel, "mover", "Recibos")
ok(exc is None and all(l.endswith('"Recibos"') for l in Falso.log if l.startswith("MOVE")), "mover para Recibos")
out, err, exc = rodar(et.lote_agir, c, sel, "mover", "Nada")
ok(exc is not None and not any(l.startswith("MOVE") for l in Falso.log), "destino inexistente: recusa sem mexer")
# na lixeira: apaga de vez
json.dump({"pasta": "[Gmail]/Lixeira", "uidvalidity": "77", "uids": ["9"]}, open(sel, "w"))
out, err, exc = rodar(et.lote_agir, c, sel, "apagar")
ok(exc is None and any(l.startswith("STORE 9") for l in Falso.log) and not any(l.startswith("MOVE") for l in Falso.log), f"na lixeira apaga de vez: {Falso.log}")
# UIDVALIDITY mudou: recusa
Falso.uv = b"78"
out, err, exc = rodar(et.lote_agir, c, sel, "apagar")
ok(exc is not None and "mudou" in str(exc) and not any(l.startswith(("STORE", "MOVE")) for l in Falso.log), "UIDVALIDITY diferente: recusa")
Falso.uv = b"77"
# outro provedor, sem MOVE e sem lixeira
Falso.caps = "IMAP4rev1 UIDPLUS"; Falso.pastas = ['(\\HasNoChildren) "." "INBOX"', '(\\HasNoChildren \\Archive) "." "Arquivo"']
json.dump({"pasta": "INBOX", "uidvalidity": "77", "uids": ["1", "2"]}, open(sel, "w"))
out, err, exc = rodar(et.lote_agir, c, sel, "apagar")
ok(exc is not None and "lixeira" in str(exc) and not any(l.startswith(("STORE", "MOVE", "COPY")) for l in Falso.log), "sem lixeira: recusa sem --de-vez")
out, err, exc = rodar(et.lote_agir, c, sel, "apagar", None, True)
ok(exc is None and any(l.startswith("STORE 1,2") for l in Falso.log) and any(l.startswith("EXPUNGE 1,2") for l in Falso.log), "sem lixeira, --de-vez apaga com UID EXPUNGE")
out, err, exc = rodar(et.lote_agir, c, sel, "arquivar")
ok(exc is None and any(l.startswith("COPY 1,2") and l.endswith('"Arquivo"') for l in Falso.log) and any(l.startswith("EXPUNGE 1,2") for l in Falso.log), f"arquivar sem MOVE: COPY + STORE + UID EXPUNGE: {Falso.log}")
out, err, exc = rodar(et.lote_agir, c, sel, "lidas")
ok(exc is None and any(l.startswith("STORE 1,2 +FLAGS.SILENT (\\Seen)") for l in Falso.log), "marcar como lidas")
if erros:
    print("\n".join(erros)); sys.exit(1)
EOF
passou 'email-tt.py lote: busca → SEARCH, só os UIDs contados, blocos de 500, lixeira/arquivo/destino e recusas seguras'

# --- 2) tt --email-lote sem terminal: --sim obrigatório; contar → agir ---------------------------------------
mkdir -p "$XDG_CONFIG_HOME/tt/email"
printf 'nome=Pessoal\nendereco=eu@gmail.com\nprovedor=gmail\nimap_host=imap.gmail.com\npasta_naoabre=[Gmail]\npasta_lixeira=[Gmail]/Lixeira\npasta_spam=[Gmail]/Spam\npasta_todos=[Gmail]/Todos os e-mails\n' >"$XDG_CONFIG_HOME/tt/email/pessoal.conf"
cp "$PY" "$T/email-tt.py.real"
cat >"$PY" <<EOF
import sys, json
open("$T/py.log", "a").write(" ".join(sys.argv[1:]) + "\n")
if sys.argv[1] == "lote-contar":
    i = sys.argv.index("--salvar"); json.dump({"pasta": sys.argv[3], "uids": ["1", "2", "3"]}, open(sys.argv[i + 1], "w"))
    print("pasta=" + sys.argv[3]); print("total=3"); print("amostra\t2024-10-01\tAna\tOferta")
elif sys.argv[1] == "lote-agir":
    print("progresso=3/3", file=sys.stderr); print("feito=3")
EOF
: >"$T/py.log"
saida=$("$TT" --email-lote Pessoal --pasta INBOX --busca 'de:loja' --acao apagar </dev/null 2>&1) && falhou "sem --sim deveria recusar: $saida"
grep -q 'lote-agir' "$T/py.log" && falhou 'sem --sim não pode agir'
grep -q 'Nada foi feito' <<<"$saida" || falhou "deveria dizer que nada foi feito: $saida"
: >"$T/py.log"
saida=$("$TT" --email-lote Pessoal --pasta INBOX --busca 'de:loja' --acao mover --destino Recibos --sim </dev/null 2>&1) || falhou "lote com --sim: $saida"
grep -q '^lote-contar .*pessoal.conf INBOX de:loja --amostra 8 --salvar ' "$T/py.log" && grep -q '^lote-agir .*pessoal.conf .* mover --destino Recibos$' "$T/py.log" || falhou "chamadas: $(cat "$T/py.log")"
grep -q '3 mensagem(ns) em INBOX' <<<"$saida" && grep -q '✓ Mover para Recibos: 3' <<<"$saida" || falhou "saída: $saida"
ls "$TT_RT"/tt-email-lote.* >/dev/null 2>&1 && falhou 'sobrou arquivo temporário do lote'
cp "$T/email-tt.py.real" "$PY"
passou 'tt --email-lote: sem terminal exige --sim; conta, age só no contado e limpa o temporário'

# --- 3) binds: toda conta com lixeira; sem lixeira, o d avisa que apaga de vez; Ctrl+a ----------------------
B=$HOME/.config/aerc/binds.conf
sec() { sed -n "/^\[$1\]\$/,/^\[/p" "$B" | sed '1d;$d'; }
echo S | "$TT" --email-adicionar nome=Trabalho endereco=eu@fastmail.com provedor=fastmail auth=senha 'pasta_lixeira=Trash' 'pasta_spam=Junk' --senha-stdin >/dev/null || falhou 'cadastro fastmail'
echo S | "$TT" --email-adicionar nome=Antigo endereco=velho@fastmail.com provedor=fastmail auth=senha --senha-stdin >/dev/null || falhou 'cadastro sem lixeira'
s=$(sec 'messages:account=^Trabalho$')
grep -q "^d = :choose -o y 'Apagar (vai para a lixeira)' 'move Trash'<Enter>$" <<<"$s" || falhou "conta com lixeira (não Gmail): d → lixeira: $s"
grep -q '^a = ' <<<"$s" && falhou 'fora do Gmail o a fica com o :archive de fábrica'
grep -q 'delete-message' <<<"$(sec 'messages:folder=^Trash$')" || falhou 'na Trash, d apaga de vez'
grep -q "^d = :choose -o y 'Apagar de vez (esta conta não tem lixeira)' delete-message<Enter>$" <<<"$(sec 'messages:account=^Antigo$')" || falhou "sem lixeira, o d avisa: $(sec 'messages:account=^Antigo$')"
grep -q "^<C-a> = :exec .*tt --email-tudo<Enter>$" <<<"$(sed -n '/^# >>> tt (saída rápida/,$p' "$B" | sed -n '/^\[messages\]$/,/^\[/p')" || falhou 'Ctrl+a na lista deveria selecionar tudo'
passou 'binds: toda conta com lixeira manda para ela; sem lixeira o d avisa que apaga de vez; Ctrl+a seleciona tudo'

# --- 4) conferir: lixeira desconhecida (Gmail) e lixeira fora do espelho ---------------------------------------
printf 'nome=Velha\nendereco=v@gmail.com\nprovedor=gmail\nimap_host=imap.gmail.com\n' >"$XDG_CONFIG_HOME/tt/email/velha.conf"
saida=$("$TT" --email-conferir velha 2>&1) && falhou "Gmail sem lixeira deveria falhar: $saida"
grep -q 'só arquivaria' <<<"$saida" || falhou "conferir: $saida"
grep -q $'^email-cmd:velha\tfalha\t' <<<"$("$TT" --checar --tsv)" || falhou 'o tt --checar deveria acusar a lixeira desconhecida'
md=$HOME/.cache/tt/maildir/pessoal; mkdir -p "$md/INBOX"
echo sync_local=1 >>"$XDG_CONFIG_HOME/tt/email/pessoal.conf"
grep -q 'não existe no espelho' <<<"$("$TT" --email-conferir pessoal 2>&1)" || falhou 'lixeira fora do espelho deveria ser acusada'
mkdir -p "$md/[Gmail]/Lixeira"; "$TT" --email-regerar pessoal >/dev/null 2>&1 || true
grep -q '✓ pessoal' <<<"$("$TT" --email-conferir pessoal 2>&1)" || falhou "com a lixeira no espelho e os binds em dia: $("$TT" --email-conferir pessoal 2>&1)"
rm -f "$XDG_CONFIG_HOME/tt/email/velha.conf"
passou 'conferir: Gmail sem lixeira e lixeira fora do espelho são acusados (também no tt --checar)'

# --- 5) ☑ Tudo: marca e desmarca pelo IPC do aerc; botão e rota ---------------------------------------------
mkdir -p "$T/rt-x" "$T/bin"; export XDG_RUNTIME_DIR=$T/rt-x AERC_IPC_LOG=$T/ipc.log
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"$AERC_IPC_LOG"\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"; export PATH=$T/bin:$PATH
python3 -I -c 'import socket, sys; s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$XDG_RUNTIME_DIR/aerc.sock"
tmux new-session -d -s _tt-email -x 120 -y 20 "exec -a aerc sleep 600"
: >"$AERC_IPC_LOG"; "$TT" --email-tudo; "$TT" --email-tudo
[[ $(cat "$AERC_IPC_LOG") == $':mark -a\n:unmark -a' ]] || falhou "☑ deveria marcar e depois desmarcar: $(cat "$AERC_IPC_LOG")"
fn=$(TT_COMPLETO=1 bash -c 'TT_SO_CARREGAR=1 source "$1" >/dev/null 2>&1; declare -p EMAIL_BOTOES; declare -f email_botao_acao email_tela menu_email' _ "$TT_DIR/tt")
grep -q "tudo|☑|Tudo|" <<<"$fn" && grep -q "lote|⚡|Em lote|" <<<"$fn" || falhou 'botões ☑ e ⚡ fora da barra do e-mail'
grep -q 'tudo) email_tela_fechar; email_tudo' "$TT_DIR/tt" && grep -q "lote)    nome='⚡ em lote'" "$TT_DIR/tt" && grep -q -- '--email-lote --tela' <<<"$fn" || falhou 'rotas dos botões ☑ e ⚡'
grep -q -- '--email-conferir --corrigir' <<<"$fn" || falhou 'menu do 📧 sem conferir os comandos'
passou '☑ Tudo marca e desmarca (botão = Ctrl+a); ⚡ Em lote e 🩺 conferir no e-mail'
