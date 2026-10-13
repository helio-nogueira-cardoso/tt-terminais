#!/usr/bin/env bash
# Popup do e-mail: Esc volta um passo (limpa filtro/busca; sem nada, esconde o e-mail), ✉ Não lidas
# liga/desliga o filtro do aerc, e 🧹 esvazia a lixeira pelo IMAP — a pasta \Trash do servidor, nunca
# outra, só depois de perguntar (ou com --sim). IMAP falso no lugar do imaplib; aerc falso que
# registra os comandos do IPC; tmux isolado.
source "$(dirname "$0")/lib.sh"; isolar
PY=$TT_DIR/email-tt.py

# --- 1) email-tt.py lixeira, contra um servidor IMAP falso ------------------------------------------
python3 -I - "$PY" <<'EOF' || falhou "email-tt.py lixeira (IMAP falso)"
import importlib.util, io, contextlib, sys
spec = importlib.util.spec_from_file_location("et", sys.argv[1]); et = importlib.util.module_from_spec(spec); spec.loader.exec_module(et)
et.credencial = lambda c: ("senha", "x")
erros = []
class Falso:
    pastas, caixas, log = [], {}, []
    def __init__(self, *a, **k): pass
    def login(self, u, s): Falso.log.append("login")
    def list(self): return "OK", [p.encode() for p in Falso.pastas]
    def select(self, caixa, readonly=False):
        Falso.log.append(f"select {caixa} {'ro' if readonly else 'rw'}"); self.atual = caixa
        return ("OK", [str(Falso.caixas.get(caixa, 0)).encode()]) if caixa in Falso.caixas else ("NO", [b"nao existe"])
    def store(self, faixa, op, flags): Falso.log.append(f"store {self.atual} {faixa} {op} {flags}"); return "OK", [b""]
    def expunge(self): Falso.log.append(f"expunge {self.atual}"); Falso.caixas[self.atual] = 0; return "OK", [b""]
    def logout(self): pass
et.imaplib.IMAP4_SSL = Falso
def rodar(c, esvaziar=False):
    Falso.log = []; out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out): et.lixeira(c, esvaziar)
        return out.getvalue(), None
    except Exception as e:
        return out.getvalue(), str(e)
C = {"imap_host": "imap.gmail.com", "endereco": "a@x.com", "pasta_lixeira": "[Gmail]/Outra"}
Falso.pastas = ['(\\HasNoChildren) "/" "INBOX"', '(\\HasNoChildren \\Trash) "/" "[Gmail]/Lixeira"', '(\\All \\HasNoChildren) "/" "[Gmail]/Todos os e-mails"']
Falso.caixas = {'"INBOX"': 40, '"[Gmail]/Lixeira"': 3, '"[Gmail]/Todos os e-mails"': 900}
out, err = rodar(C)
if err or "pasta=[Gmail]/Lixeira" not in out or "mensagens=3" not in out: erros.append(f"contar: {out!r} {err}")
if any(l.startswith(("store", "expunge")) for l in Falso.log) or Falso.log[-1] != 'select "[Gmail]/Lixeira" ro': erros.append(f"contar só lê: {Falso.log}")
out, err = rodar(C, True)
if err or "apagadas=3" not in out or "restam=0" not in out: erros.append(f"esvaziar: {out!r} {err}")
mexeu = [l for l in Falso.log if l.startswith(("store", "expunge"))]
if mexeu != ['store "[Gmail]/Lixeira" 1:* +FLAGS.SILENT (\\Deleted)', 'expunge "[Gmail]/Lixeira"']: erros.append(f"esvaziar mexe só na lixeira (\\Trash, não a pasta do cadastro): {Falso.log}")
if Falso.caixas['"INBOX"'] != 40 or Falso.caixas['"[Gmail]/Todos os e-mails"'] != 900: erros.append("outra pasta perdeu mensagens")
out, err = rodar(C, True)
if err or "apagadas=0" not in out or any(l.startswith("store") for l in Falso.log): erros.append(f"lixeira vazia: nada a apagar: {Falso.log} {out!r}")
# sem a marca \Trash: só a pasta_lixeira do cadastro, se existir no servidor; senão, erro sem abrir nada
Falso.pastas = ['(\\HasNoChildren) "/" "INBOX"', '(\\HasNoChildren) "/" "Lixo &AOk- velho"']
Falso.caixas = {'"INBOX"': 5, '"Lixo &AOk- velho"': 2}
out, err = rodar({**C, "pasta_lixeira": "Lixo é velho"}, True)
if err or "apagadas=2" not in out or not any(l.startswith('store "Lixo &AOk- velho"') for l in Falso.log): erros.append(f"pasta do cadastro (nome em UTF-7): {Falso.log} {out!r} {err}")
out, err = rodar({**C, "pasta_lixeira": "Nao existe"}, True)
if not err or any(l.startswith("select") for l in Falso.log): erros.append(f"sem lixeira deveria recusar sem abrir pasta: {Falso.log} {err}")
Falso.pastas = ['(\\HasNoChildren \\Trash) "/" "INBOX"']; Falso.caixas = {'"INBOX"': 5}
out, err = rodar(C, True)
if not err or Falso.caixas['"INBOX"'] != 5: erros.append(f"\\Trash na Caixa de entrada deveria ser recusado: {Falso.log} {err}")
if erros: print("\n".join(erros), file=sys.stderr); sys.exit(1)
EOF
passou "email-tt.py lixeira: conta pela pasta \\Trash do servidor, esvazia só ela (STORE \\Deleted + EXPUNGE); recusa sem lixeira ou com a Caixa de entrada"

# --- 2) tt --email-lixeira: pergunta antes; sem terminal e sem --sim só mostra -----------------------
instalar_isolado
mkdir -p "$T/bin"; LOG=$T/py.log
# email-tt.py falso (só para este verbo): registra os argumentos e responde como o de verdade
mv "$TT_DIR/email-tt.py" "$TT_DIR/email-tt.real.py"
cat >"$TT_DIR/email-tt.py" <<EOF
import sys
if sys.argv[1] != "lixeira":
    import runpy; sys.argv[0] = "$TT_DIR/email-tt.real.py"; runpy.run_path(sys.argv[0], run_name="__main__")
c = sys.argv[2].rsplit("/", 1)[-1][:-5]
open("$LOG", "a").write(" ".join(["lixeira", c] + sys.argv[3:]) + "\n")
n = {"gmail": 3, "vazia": 0}.get(c, 0)
print("pasta=[Gmail]/Lixeira"); print(f"mensagens={n}")
if sys.argv[3:] == ["--esvaziar"]: print(f"apagadas={n}"); print("restam=0")
EOF
echo 'S' | "$TT" --email-adicionar nome=Gmail endereco=g@gmail.com provedor=gmail auth=senha 'pasta_lixeira=[Gmail]/Lixeira' --senha-stdin >/dev/null || falhou 'cadastro gmail'
echo 'S' | "$TT" --email-adicionar nome=Vazia endereco=v@gmail.com provedor=gmail auth=senha 'pasta_lixeira=[Gmail]/Lixeira' --senha-stdin >/dev/null || falhou 'cadastro vazia'
: >"$LOG"; saida=$("$TT" --email-lixeira </dev/null 2>&1)
grep -q 'Gmail — \[Gmail\]/Lixeira: 3 mensagens' <<<"$saida" && grep -q 'Vazia — \[Gmail\]/Lixeira: 0 mensagens' <<<"$saida" || falhou "deveria mostrar a lixeira de cada conta: $saida"
grep -q -- '--esvaziar' "$LOG" && falhou "sem terminal e sem --sim nada pode ser apagado: $(cat "$LOG")"
passou 'sem terminal e sem --sim: só mostra quanto há em cada lixeira'
"$TT" --email-lixeira nenhuma </dev/null >/dev/null 2>&1 && falhou 'conta desconhecida deveria falhar'
# no terminal: a pergunta; qualquer tecla que não seja s cancela, s apaga (só as contas com mensagens)
no_terminal() { # tecla argumentos…
  python3 -I - "$@" <<'EOF'
import os, pty, sys, time
tecla, args = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(os.environ["TT"], [os.environ["TT"]] + args)
saida, enviou, fim = b"", False, time.time() + 20
while time.time() < fim:
    try: b = os.read(fd, 4096)
    except OSError: break
    if not b: break
    saida += b
    if not enviou and b"apagar" in saida: os.write(fd, tecla.encode()); enviou = True
os.waitpid(pid, 0); sys.stdout.write(saida.decode("utf-8", "replace"))
EOF
}
export TT
: >"$LOG"; saida=$(no_terminal n --email-lixeira)
grep -q 'Apagar DE VEZ 3 mensagens' <<<"$saida" && grep -q 'Nada foi apagado' <<<"$saida" || falhou "deveria perguntar e cancelar com n: $saida"
grep -q -- '--esvaziar' "$LOG" && falhou "n não pode apagar: $(cat "$LOG")"
: >"$LOG"; saida=$(no_terminal s --email-lixeira)
grep -q '✓ Gmail: 3 apagadas' <<<"$saida" || falhou "s deveria esvaziar: $saida"
[[ $(grep -c -- '--esvaziar' "$LOG") == 1 ]] && grep -q 'lixeira gmail --esvaziar' "$LOG" || falhou "só a conta com mensagens é esvaziada: $(cat "$LOG")"
: >"$LOG"; "$TT" --email-lixeira gmail --sim </dev/null >/dev/null 2>&1
grep -q 'lixeira gmail --esvaziar' "$LOG" && ! grep -q 'lixeira vazia' "$LOG" || falhou "--sim com a conta: só ela, sem perguntar: $(cat "$LOG")"
passou 'no terminal pergunta antes (n cancela, s apaga só as contas com mensagens); --sim e a conta escolhida dispensam a pergunta'

# --- 3) Esc e ✉ Não lidas na sessão oculta: aerc falso (IPC registrado) e a linha de status dele ----
mkdir -p "$T/rt-x"; export XDG_RUNTIME_DIR=$T/rt-x AERC_IPC_LOG=$T/ipc.log
cat >"$T/bin/aerc" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AERC_IPC_LOG"
EOF
chmod +x "$T/bin/aerc"; export PATH=$T/bin:$PATH
python3 -I -c 'import socket, sys; s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$XDG_RUNTIME_DIR/aerc.sock"
printf '%s\n' 'INBOX     Ana   Oi' '' '[Gmail] Connected' >"$T/status"
# (redesenha só quando o status muda: limpar a tela a cada volta deixaria a captura pegar a tela vazia)
tmux new-session -d -s _tt-email -x 120 -y 20 "exec -a aerc bash -c 'while :; do h=\$(cksum <$T/status); [[ \$h != \$u ]] && { clear; cat $T/status; u=\$h; }; sleep 0.2; done'"
tmux set -q -t =_tt-email: @ponte email
anexar v 120 22 _tt-email; sleep 1.5
clientes() { tmux list-clients -t =_tt-email 2>/dev/null | wc -l; }
[[ $(clientes) == 1 ]] || falhou "cliente de teste não anexou ao e-mail"
: >"$AERC_IPC_LOG"; "$TT" --email-naolidas
[[ $(cat "$AERC_IPC_LOG") == ':filter -u' ]] || falhou "✉ sem filtro deveria ligar o filtro de não lidas: $(cat "$AERC_IPC_LOG")"
printf '%s\n' 'INBOX     Ana   Oi' '' '[Gmail] Connected | filter -u' >"$T/status"; sleep 1
: >"$AERC_IPC_LOG"; "$TT" --email-naolidas
[[ $(cat "$AERC_IPC_LOG") == ':clear' ]] || falhou "✉ com o filtro ligado deveria desligar: $(cat "$AERC_IPC_LOG")"
: >"$AERC_IPC_LOG"; "$TT" --email-esc; sleep 0.5
[[ $(cat "$AERC_IPC_LOG") == ':clear' && $(clientes) == 1 ]] || falhou "Esc com filtro deveria só limpar (e o e-mail seguir aberto): $(cat "$AERC_IPC_LOG") clientes=$(clientes)"
printf '%s\n' 'INBOX     Ana   Oi' '' '[Gmail] Connected | search Oi' >"$T/status"; sleep 1
: >"$AERC_IPC_LOG"; "$TT" --email-esc; sleep 0.5
[[ $(cat "$AERC_IPC_LOG") == ':clear' && $(clientes) == 1 ]] || falhou "Esc com busca deveria limpar a busca: $(cat "$AERC_IPC_LOG")"
printf '%s\n' 'INBOX     Ana   Oi' '' '[Gmail] Connected' >"$T/status"; sleep 1
: >"$AERC_IPC_LOG"; "$TT" --email-esc; sleep 0.5
[[ ! -s $AERC_IPC_LOG && $(clientes) == 0 ]] || falhou "Esc sem filtro deveria esconder o e-mail (desanexar): ipc=$(cat "$AERC_IPC_LOG") clientes=$(clientes)"
tmux has-session -t =_tt-email 2>/dev/null || falhou 'esconder não pode encerrar o aerc'
passou 'Esc: com filtro ou busca limpa; sem nada esconde o e-mail (o aerc segue aberto); ✉ liga e desliga o filtro de não lidas'

# --- 4) binds da sessão oculta, botões e ajuda -----------------------------------------------------
mkdir -p ~/.config/aerc; printf '[messages]\nq = :quit<Enter>\n<Esc> = :clear<Enter>\n[view]\nq = :close<Enter>\n' >~/.config/aerc/binds.conf
tmux kill-session -t =_tt-email
printf '#!/bin/sh\nexec sleep 600\n' >"$T/bin/aerc-parado"; chmod +x "$T/bin/aerc-parado"
bash -c "source <(sed -n '/^tt_largura()/,/^}/p' '$TT'); source <(sed -n '/^EMAIL_SESSAO=/,/^# ─── Cadastro e gerência de contas de e-mail/p' '$TT' | sed '\$d'); email_sessao aerc-parado largo" || falhou 'email_sessao'
bo=~/.cache/tt-aerc-binds-oculto.conf
awk '/^\[messages\]/{s="m"} /^\[view\]/{s="v"} /^<Esc> = :exec .*tt --email-esc<Enter>$/{e[s]++} /^<Esc> = :close<Enter>$/{c[s]++} END{exit !(e["m"]==1 && !e["v"] && c["v"]==1 && !c["m"])}' "$bo" ||
  falhou "Esc: na lista tt --email-esc, na mensagem :close: $(grep -n 'Esc\|^\[' "$bo")"
[[ $(tmux show -qv -t =_tt-email: @tt_email_binds) == 5:* ]] || falhou 'versão dos binds deveria subir (sessões antigas recriadas com o Esc)'
fmt=$(tmux show -qv -t =_tt-email: 'status-format[0]')
grep -q 'range=user|em_naolidas' <<<"$fmt" && grep -q 'range=user|em_lixeira' <<<"$fmt" || falhou "botões ✉ e 🧹 ausentes: $fmt"
grep -q 'dica="Esc fecha"' "$TT" || falhou 'o título do popup deveria ensinar Esc'
ajuda=$("$TT" --email-atalhos </dev/null)
for ic in 📖 📂 💬 🔍 📎 📑 📝 👤 💡; do grep -q "^$ic " <<<"$ajuda" || falhou "ajuda sem o ícone $ic: $(head -3 <<<"$ajuda")"; done
grep -q 'Esc · voltar: fecha a mensagem' <<<"$ajuda" && grep -q 'botão 🧹' <<<"$ajuda" && grep -q 'botão ✉' <<<"$ajuda" || falhou "ajuda sem Esc/🧹/✉: $ajuda"
passou 'binds: Esc na lista (tt --email-esc) e na mensagem (:close); versão 4; botões ✉ e 🧹; título "Esc fecha"; ajuda com ícone por assunto'
