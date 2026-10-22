#!/usr/bin/env bash
# tt --email-enviar: envia sem tela por qualquer conta. Um servidor SMTP falso (AUTH PLAIN) e uma API do Outlook
# falsa (token + sendmail) recebem de verdade; nada sai da máquina. Cobre: campos em português e apelidos em
# inglês, acentos, HTML, anexo, Cc/Cco (Cco no envelope e fora dos cabeçalhos), resposta (In-Reply-To), corpo pelo
# stdin, escolha da conta (slug, nome, endereço, email_padrao, conta única, ambígua), --ensaio, erros de uso e o
# sendmail do aerc nas contas Graph (o graph-sendmail, que falhava em todo envio com NameError).
source "$(dirname "$0")/lib.sh"; isolar
command -v python3 >/dev/null || { echo "ok: sem python3, nada a testar"; exit 0; }
SRV=$T/srv; mkdir -p "$SRV"
cat >"$SRV/falso.py" <<'EOF'
import base64, json, os, socketserver, sys, threading, http.server
pasta = sys.argv[1]
class Smtp(socketserver.StreamRequestHandler):
    def handle(self):
        w = lambda s: self.wfile.write((s + "\r\n").encode())
        w("220 falso"); env = {"rcpt": []}
        while True:
            l = self.rfile.readline()
            if not l: return
            l = l.decode().rstrip("\r\n"); u = l.upper()
            if u.startswith("EHLO"): w("250-falso"); w("250 AUTH PLAIN")
            elif u.startswith("AUTH PLAIN"):
                partes = base64.b64decode(l.split()[2]).split(b"\0"); env["auth"] = partes[1].decode() + ":" + partes[2].decode()
                w("235 ok")
            elif u.startswith("MAIL FROM:"): env["from"] = l[10:].strip("<> "); w("250 ok")
            elif u.startswith("RCPT TO:"): env["rcpt"].append(l[8:].strip("<> ")); w("250 ok")
            elif u == "DATA":
                w("354 manda"); dados = []
                while True:
                    x = self.rfile.readline()
                    if x in (b".\r\n", b".\n", b""): break
                    dados.append(x[1:] if x.startswith(b"..") else x)
                n = len(os.listdir(pasta))
                open(f"{pasta}/smtp-{n}.eml", "wb").write(b"".join(dados))
                json.dump(env, open(f"{pasta}/smtp-{n}.json", "w")); w("250 aceito")
            elif u == "QUIT": w("221 tchau"); return
            else: w("250 ok")
class Http(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        dados = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if self.path == "/token":
            r = json.dumps({"access_token": "tok-falso"}).encode(); self.send_response(200)
        else:
            n = len(os.listdir(pasta))
            json.dump({"path": self.path, "auth": self.headers.get("Authorization"), "corpo": json.loads(dados)},
                      open(f"{pasta}/outlook-{n}.json", "w"))
            r = b""; self.send_response(202)
        self.send_header("Content-Length", str(len(r))); self.end_headers(); self.wfile.write(r)
socketserver.TCPServer.allow_reuse_address = True
s = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Smtp); h = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Http)
open(f"{pasta}/../portas", "w").write(f"{s.server_address[1]} {h.server_address[1]}\n")
threading.Thread(target=s.serve_forever, daemon=True).start(); h.serve_forever()
EOF
mkdir -p "$SRV/caixa"; python3 "$SRV/falso.py" "$SRV/caixa" & PID_SRV=$!
for _ in $(seq 50); do [[ -s $SRV/portas ]] && break; sleep 0.1; done
read -r PS PH <"$SRV/portas"
export TT_EMAIL_OUTLOOK_API="http://127.0.0.1:$PH/api/v2.0"
E=$HOME/.config/tt/email; mkdir -p "$E" "$HOME/.secrets"
printf 'nome=Pessoal\nendereco=eu@exemplo.com\nusuario=eu@exemplo.com\nnome_exibicao=Hélio Teste\nprovedor=outro\nauth=senha\nsmtp_host=127.0.0.1\nsmtp_porta=%s\nsmtp_seg=nenhuma\n' "$PS" >"$E/pessoal.conf"
printf 'segredo-smtp' >"$HOME/.secrets/aerc-pessoal.txt"
printf 'nome=Trabalho\nendereco=eu@empresa.com\nprovedor=microsoft\nauth=oauth\ngraph=1\noauth_client_id=cid\noauth_token_endpoint=http://127.0.0.1:%s/token\n' "$PH" >"$E/trabalho.conf"
printf 'rt-falso' >"$HOME/.secrets/aerc-trabalho.txt"
printf 'Assinatura do Hélio\n' >"$E/pessoal.assinatura"
ANEXO=$T/relatório.txt; printf 'conteúdo do anexo ç\n' >"$ANEXO"
ultimo() { ls -t "$SRV/caixa"/$1-*.json 2>/dev/null | head -1; }

# 1) SMTP: campos em português, acentos, HTML, anexo, Cc e Cco, resposta; Cco no envelope e fora dos cabeçalhos
out=$("$TT" --email-enviar --conta pessoal --para a@x.com,b@x.com --cc c@x.com --cco oculto@x.com \
  --assunto "Relatório de ação" --corpo "Olá, segue o relatório." --html "<p>Olá <b>HTML</b></p>" \
  --anexo "$ANEXO" --responder-para resp@x.com --em-resposta-a "orig@x.com") || falhou "envio SMTP falhou: $out"
[[ $out == "✓ enviado de eu@exemplo.com para a@x.com, b@x.com, c@x.com, oculto@x.com por SMTP 127.0.0.1"* ]] || falhou "saída: $out"
j=$(ultimo smtp); eml=${j%.json}.eml
python3 - "$j" "$eml" <<'EOF' || falhou "mensagem SMTP diferente do esperado"
import json, sys, email, email.policy
env = json.load(open(sys.argv[1])); m = email.message_from_bytes(open(sys.argv[2], "rb").read(), policy=email.policy.default)
assert env["auth"] == "eu@exemplo.com:segredo-smtp", env
assert sorted(env["rcpt"]) == ["a@x.com", "b@x.com", "c@x.com", "oculto@x.com"], env
assert m["Subject"] == "Relatório de ação" and m["From"] == "Hélio Teste <eu@exemplo.com>", (m["Subject"], m["From"])
assert m["To"] == "a@x.com, b@x.com" and m["Cc"] == "c@x.com" and m["Bcc"] is None, (m["To"], m["Cc"], m["Bcc"])
assert m["Reply-To"] == "resp@x.com" and m["In-Reply-To"] == "<orig@x.com>" and m["References"] == "<orig@x.com>"
txt = m.get_body(("plain",)).get_content().replace("\r\n", "\n")
assert "Olá, segue o relatório." in txt and "-- \nAssinatura do Hélio" in txt, txt
assert "<b>HTML</b>" in m.get_body(("html",)).get_content()
an = list(m.iter_attachments()); assert len(an) == 1 and an[0].get_filename() == "relatório.txt", an
assert an[0].get_payload(decode=True).decode() == "conteúdo do anexo ç\n"
assert m["Message-ID"].endswith("@exemplo.com>")
EOF
passou 'SMTP: campos em português, acentos, HTML, anexo, Cc, Cco só no envelope, resposta e assinatura'

# 2) apelidos em inglês, corpo pelo stdin, conta pelo endereço e sem assinatura
printf 'corpo vindo do stdin\n' | "$TT" --email-enviar --from EU@EXEMPLO.COM --to d@x.com --subject "inglês" \
  --no-signature >/dev/null || falhou 'envio com apelidos em inglês falhou'
eml=$(ultimo smtp); eml=${eml%.json}.eml
grep -q '^To: d@x.com' "$eml" && grep -q 'corpo vindo do stdin' "$eml" || falhou "stdin/apelidos: $(cat "$eml")"
grep -q 'Assinatura do' "$eml" && falhou '--no-signature não tirou a assinatura'
passou 'apelidos em inglês, corpo pelo stdin, conta pelo endereço e --no-signature'

# 3) Microsoft (Graph): pela API do Outlook, com token renovado, HTML, anexo e Cco; conta pelo nome
"$TT" --email-enviar --conta Trabalho --para x@y.com --cco z@y.com --assunto "Pelo Outlook" --corpo "texto" \
  --html "<i>rico</i>" --anexo "$ANEXO" --responder-para r@y.com >/dev/null || falhou 'envio pelo Outlook falhou'
python3 - "$(ultimo outlook)" <<'EOF' || falhou "JSON do Outlook diferente do esperado: $(cat "$(ultimo outlook)")"
import json, sys, base64
d = json.load(open(sys.argv[1])); m = d["corpo"]["Message"]
assert d["path"] == "/api/v2.0/me/sendmail" and d["auth"] == "Bearer tok-falso", d
assert d["corpo"]["SaveToSentItems"] is True
assert m["Subject"] == "Pelo Outlook" and m["Body"]["ContentType"] == "HTML" and "<i>rico</i>" in m["Body"]["Content"]
assert [r["EmailAddress"]["Address"] for r in m["ToRecipients"]] == ["x@y.com"]
assert [r["EmailAddress"]["Address"] for r in m["BccRecipients"]] == ["z@y.com"]
assert [r["EmailAddress"]["Address"] for r in m["ReplyTo"]] == ["r@y.com"]
a = m["Attachments"]; assert len(a) == 1 and a[0]["Name"] == "relatório.txt"
assert base64.b64decode(a[0]["ContentBytes"]).decode() == "conteúdo do anexo ç\n"
EOF
passou 'Microsoft/Graph: API do Outlook com HTML, anexo, Cco e Reply-To; conta pelo nome'

# 4) sendmail do aerc nas contas Graph: mensagem crua no stdin, envelope nos argumentos (o Cco só no envelope)
printf 'From: eu@empresa.com\nTo: x@y.com\nSubject: do aerc\nContent-Type: text/plain; charset=utf-8\n\ncorpo do aerc ç\n' |
  python3 "$TT_DIR/email-tt.py" graph-sendmail "$E/trabalho.conf" x@y.com escondido@y.com || falhou 'graph-sendmail falhou'
python3 - "$(ultimo outlook)" <<'EOF' || falhou "graph-sendmail: $(cat "$(ultimo outlook)")"
import json, sys
m = json.load(open(sys.argv[1]))["corpo"]["Message"]
assert m["Subject"] == "do aerc" and m["Body"]["Content"].strip() == "corpo do aerc ç", m
assert [r["EmailAddress"]["Address"] for r in m["ToRecipients"]] == ["x@y.com"]
assert [r["EmailAddress"]["Address"] for r in m["BccRecipients"]] == ["escondido@y.com"]
EOF
passou 'graph-sendmail do aerc envia (texto, envelope com Cco)'

# 5) --ensaio não envia nada e mostra a mensagem; escolha da conta e erros de uso
antes=$(ls "$SRV/caixa" | wc -l)
out=$("$TT" --email-enviar --conta pessoal --para a@x.com --assunto "só ver" --corpo "corpo" --anexo "$ANEXO" --ensaio)
[[ $(ls "$SRV/caixa" | wc -l) == "$antes" ]] || falhou '--ensaio enviou'
grep -q '^# ensaio: nada foi enviado' <<<"$out" && grep -q '^Subject: só ver' <<<"$out" && grep -q '# anexo: relatório.txt' <<<"$out" ||
  falhou "ensaio: $out"
rc=0; "$TT" --email-enviar --para a@x.com --assunto a --corpo b --ensaio >/dev/null 2>&1 || rc=$?
[[ $rc == 2 ]] || falhou "duas contas sem --conta deveria dar rc 2 (deu $rc)"
printf 'email_padrao=Pessoal\n' >>"$HOME/.config/tt/config"
"$TT" --email-enviar --para a@x.com --assunto a --corpo b --ensaio | grep -q 'conta pessoal' || falhou 'email_padrao= não valeu'
for args in "--conta nenhuma --para a@x.com --assunto a" "--conta pessoal --assunto a" "--conta pessoal --para a@x.com" \
            "--conta pessoal --para a@x.com --assunto a --anexo /nao/existe" "--conta pessoal --para a@x.com --assunto a --xyz"; do
  rc=0; "$TT" --email-enviar $args --corpo b >/dev/null 2>&1 </dev/null || rc=$?
  [[ $rc == 2 ]] || falhou "uso errado ($args) deveria dar rc 2 (deu $rc)"
done
"$TT" --email-enviar --ajuda | grep -q -- '--para' || falhou '--ajuda'
[[ $(ls "$SRV/caixa" | wc -l) == "$antes" ]] || falhou 'erro de uso enviou algo'
passou '--ensaio não envia; conta padrão, ambígua e inexistente; destinatário, assunto, anexo e opção inválidos dão rc 2'

# 6) integração com tarefas: protocolo completo (código, subtarefa e rodapé v2) pelo mesmo transporte SMTP
TIT='Demanda completa por e-mail'; SUB='Subtarefa com prazo'
"$TT" --tarefa-add "$TIT" >/dev/null
TID=$(awk -F'\t' -v t="$TIT" '$5==t && $2!="removida"{print $1; exit}' "$HOME/.config/tt/tarefas")
"$TT" --tarefa-desc "$TID" 'Descrição íntegra da tarefa.' >/dev/null
"$TT" --tarefa-sub-add "$TID" "$SUB" >/dev/null
SID=$(awk -F'\t' -v t="$SUB" '$5==t && $2!="removida"{print $1; exit}' "$HOME/.config/tt/tarefas")
"$TT" --tarefa-desc "$SID" $'Descrição da subtarefa.\n- detalhe que não é outra subtarefa' >/dev/null
antes=$(ls "$SRV/caixa"/smtp-*.json 2>/dev/null | wc -l)
cp "$HOME/.config/tt/tarefas" "$T/antes-ensaio"
"$TT" --email-enviar --conta pessoal --para=netto@x.com --tarefa "$TID" --dry-run >"$T/previa"
cmp -s "$HOME/.config/tt/tarefas" "$T/antes-ensaio" || falhou 'ensaio alterou tarefa/base'
[[ $(ls "$SRV/caixa"/smtp-*.json | wc -l) == "$antes" ]] || falhou 'ensaio de tarefa enviou'
grep -q '^tt:3 ' "$T/previa" && falhou 'prévia visual expôs o pacote técnico'
rc=0; "$TT" --email-enviar --conta pessoal --para=netto@x.com --tarefa "$TID" --tarefa inexistente >/dev/null 2>&1 || rc=$?
[[ $rc == 2 && $(ls "$SRV/caixa"/smtp-*.json | wc -l) == "$antes" ]] || falhou 'lote inválido enviou parcialmente'
for conflito in --corpo=manual --body=manual --subject=manual --html=manual; do
  rc=0; "$TT" --email-enviar --conta pessoal --para=netto@x.com --tarefa "$TID" "$conflito" >/dev/null 2>&1 || rc=$?
  [[ $rc == 2 ]] || falhou "campo manual aceito com tarefa: $conflito"
done
"$TT" --email-enviar --conta pessoal --para=netto@x.com --assunto literal --corpo --tarefa --ensaio | grep -q '^--tarefa$' || falhou 'valor literal de corpo foi interpretado como opção'
"$TT" --email-enviar --conta pessoal --para netto@x.com --tarefa "$TID" >/dev/null || falhou 'envio integrado de tarefa falhou'
[[ $(ls "$SRV/caixa"/smtp-*.json 2>/dev/null | wc -l) == $((antes + 1)) ]] || falhou 'uma tarefa deve gerar exatamente um e-mail'
eml=$(ultimo smtp); eml=${eml%.json}.eml
python3 - "$eml" "$TID" "$SID" <<'EOF' || falhou 'e-mail de tarefa não preservou protocolo e árvore'
import email, email.policy, sys
m = email.message_from_bytes(open(sys.argv[1], "rb").read(), policy=email.policy.default)
body = m.get_body(("plain",)).get_content().replace("\r\n", "\n")
assert m["To"] == "netto@x.com" and m["Subject"].endswith("~" + sys.argv[2]), (m["To"], m["Subject"])
assert "Descrição íntegra da tarefa." in body and f"- [{sys.argv[3]}] [ ] Subtarefa com prazo" in body, body
assert "tt:2 estado=aberta" in body, body
assert "Descrição da subtarefa." in body
EOF
passou 'tt --email-enviar --tarefa: tarefa completa com IDs e subtarefas pelo transporte SMTP'

# O receptor usa seu próprio perfil: só o remetente autorizado entra, e a atualização exige aprovação.
mkdir -p "$T/receptor/.config/tt" "$T/receptor/.cache/tt/maildir/recebida/INBOX/new" "$T/receptor/rt"
printf 'nome=receptor\n' >"$T/receptor/.config/tt/config"
: >"$T/receptor/.config/tt/maquinas"
B() { HOME="$T/receptor" XDG_CONFIG_HOME="$T/receptor/.config" TT_RT="$T/receptor/rt" "$TT" "$@"; }
CB="$T/receptor/.config/tt/tarefas"
cp "$eml" "$T/receptor/.cache/tt/maildir/recebida/INBOX/new/primeira"
B --demandas-processar recebida
[[ ! -s $CB ]] || falhou 'remetente não autorizado criou tarefa'
B --demanda-autorizar eu@exemplo.com - relaxado >/dev/null
B --demandas-processar recebida
[[ $(awk -F'\t' -v i="$TID" '$1==i{print $2}' "$CB") == pendente ]] || falhou 'não apareceu na Entrada'
B --demanda-aprovar "$TID" >/dev/null
B --tarefa-ia-prompt "$SID" >"$T/sub-recebida"
grep -q 'detalhe que não é outra subtarefa' "$T/sub-recebida" || falhou 'descrição da subtarefa não chegou'
"$TT" --tarefa-desc "$SID" 'Descrição atualizada pelo remetente.' >/dev/null
B --tarefa-desc "$SID" 'Descrição alterada pelo destinatário.' >/dev/null
"$TT" --email-enviar --conta pessoal --para netto@x.com --tarefa "$TID" >/dev/null
eml=$(ultimo smtp); eml=${eml%.json}.eml
cp "$eml" "$T/receptor/.cache/tt/maildir/recebida/INBOX/new/atualizacao"
B --demandas-processar recebida
PROP=$(awk -F'\t' '$2=="pendente" && $6 ~ /(^|\|)upd=/{print $1; exit}' "$CB")
[[ -n $PROP ]] || falhou 'atualização não gerou proposta'
grep -q 'descrição' <<<"$(B --demanda-diff "$PROP")" || falhou 'revisão não mostra descrição da subtarefa'
rc=0; B --demanda-aprovar "$PROP" >/dev/null 2>&1 || rc=$?
[[ $rc == 4 ]] || falhou 'conflito foi aplicado sem escolha'
grep -q 'alterada pelo destinatário' <<<"$(B --tarefa-ia-prompt "$SID")" || falhou 'conflito alterou tarefa local'
B --demanda-aprovar --recebida "$PROP" >/dev/null
grep -q 'atualizada pelo remetente' <<<"$(B --tarefa-ia-prompt "$SID")" || falhou 'escolha recebida não aplicou descrição'
passou 'SMTP → Entrada → aprovação; atualização rica mostra conflito e respeita escolha do destinatário'

# Fluxo visual: conta escolhida, destinatário, revisão e cancelamento/confirmar; IDs repetidos não duplicam.
antes=$(ls "$SRV/caixa"/smtp-*.json | wc -l)
printf 'pessoal\nnetto@x.com\nn\n' | "$TT" --email-enviar --tarefas-ui --tarefa "$TID" >"$T/ui-cancelada"
[[ $(ls "$SRV/caixa"/smtp-*.json | wc -l) == "$antes" ]] || falhou 'cancelar na tela enviou'
printf 'pessoal\nnetto@x.com\nsim\n' | "$TT" --email-enviar --tarefas-ui --tarefa "$TID" --tarefa "$TID" >"$T/ui-enviada"
[[ $(ls "$SRV/caixa"/smtp-*.json | wc -l) == $((antes + 1)) ]] || falhou 'tela não enviou uma única cópia'
grep -q 'conta pessoal' "$T/ui-enviada" || falhou 'tela não mostrou conta escolhida'
passou 'tela integrada: escolhe conta, mostra prévia, cancela ou confirma; tarefa repetida deduplicada'

# O mesmo seletor fzf usado pelos menus (sem ID antecipado), em modo de filtro sem tela.
antes=$(ls "$SRV/caixa"/smtp-*.json | wc -l)
printf 'pessoal\nnetto@x.com\nn\n' | FZF_DEFAULT_OPTS='--filter=Demanda' "$TT" --email-enviar --tarefas-ui >"$T/ui-selecao"
grep -q "~$TID" "$T/ui-selecao" || falhou 'seletor não levou a tarefa escolhida à prévia'
grep -q 'Envio cancelado' "$T/ui-selecao" || falhou 'seletor não passou pela confirmação'
[[ $(ls "$SRV/caixa"/smtp-*.json | wc -l) == "$antes" ]] || falhou 'cancelamento depois do seletor enviou'
passou 'seletor dos menus: encontra a tarefa, prepara a prévia e respeita o cancelamento'

# 7) falha do servidor vira rc 1 com mensagem curta
kill $PID_SRV 2>/dev/null; wait $PID_SRV 2>/dev/null || true
rc=0; err=$("$TT" --email-enviar --conta pessoal --para a@x.com --assunto a --corpo b 2>&1) || rc=$?
[[ $rc == 1 && $err == "✗ não enviado:"* ]] || falhou "servidor fora deveria dar rc 1 e ✗ (rc $rc: $err)"
passou 'servidor fora do ar: rc 1 e mensagem curta'
