#!/usr/bin/env bash
# Envio de uma conta do Microsoft Graph (o "outgoing" do aerc é o email-tt.py graph-sendmail CONF, que recebe no
# envelope todos os destinatários, inclusive os da cópia oculta, cujo cabeçalho o aerc tira da mensagem):
#  - o envio não quebra antes da rede (a v2.2.0 dava "name 'field' is not defined" em todo envio; v2.5.0);
#  - Para e Cc saem dos cabeçalhos; quem só está no envelope vai em Cco, nunca no Para (o Cco ficava à vista);
#  - mensagem só em HTML vai como HTML (sem parte de texto, o envio quebrava).
source "$(dirname "$0")/lib.sh"; isolar
PY=$(command -v python3)
HOME=$HOME "$PY" -I - "$T/pkg/email-tt.py" <<'PY' || falhou 'graph-sendmail (email-tt.py)'
import importlib.util, io, json, sys
spec = importlib.util.spec_from_file_location("email_tt", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
enviados = []
class Resp:
    status = 202
    def __enter__(self): return self
    def __exit__(self, *a): return False
def urlopen(req, timeout=None, context=None):
    enviados.append((req.full_url, req.get_header("Authorization"), json.loads(req.data.decode("utf-8")))); return Resp()
m.graph_token = lambda c, recurso="": "tok"
m.urllib.request.urlopen = urlopen
c = {"_slug": "g", "auth": "oauth", "graph": "1", "provedor": "microsoft"}
msg = "From: Eu <eu@empresa.com>\nTo: Ana <ana@empresa.com>\nCc: bia@empresa.com\nSubject: Olá\n\ncorpo\n"
env = lambda *xs: [{"EmailAddress": {"Address": x}} for x in xs]
assert m.graph_enviar(c, env("ana@empresa.com", "Bia@empresa.com", "oculto@fora.com"), msg) == 202
url, aut, corpo = enviados[-1]
assert aut == "Bearer tok", aut
d = corpo["Message"]
quem = lambda k: [r["EmailAddress"]["Address"] for r in d[k]]
assert quem("ToRecipients") == ["ana@empresa.com"], d
assert quem("CcRecipients") == ["bia@empresa.com"], d
assert quem("BccRecipients") == ["oculto@fora.com"], d
assert d["Subject"] == "Olá" and d["Body"] == {"ContentType": "Text", "Content": "corpo\n"}, d
assert [r["EmailAddress"].get("Name") for r in d["ToRecipients"]] == ["Ana"], d
html = "From: eu@empresa.com\nTo: ana@empresa.com\nSubject: h\nMIME-Version: 1.0\nContent-Type: text/html; charset=utf-8\n\n<p>oi</p>\n"
m.graph_enviar(c, env("ana@empresa.com"), html)
d = enviados[-1][2]["Message"]
assert d["Body"]["ContentType"] == "HTML" and "<p>oi</p>" in d["Body"]["Content"], d
assert [r["EmailAddress"]["Address"] for r in d["BccRecipients"]] == [], d
# pela linha de comando, como o aerc chama (conf, envelope e a mensagem no stdin)
import os, tempfile
conf = os.path.join(tempfile.mkdtemp(), "g.conf")
open(conf, "w").write("nome=G\nendereco=eu@empresa.com\nprovedor=microsoft\nauth=oauth\ngraph=1\n")
sys.stdin = io.TextIOWrapper(io.BytesIO(msg.encode("utf-8")))  # o main lê o stdin.buffer
assert m.main(["graph-sendmail", conf, "ana@empresa.com", "bia@empresa.com", "oculto@fora.com"]) == 0
assert [r["EmailAddress"]["Address"] for r in enviados[-1][2]["Message"]["BccRecipients"]] == ["oculto@fora.com"]
PY
passou 'Graph: o envio monta Para/Cc dos cabeçalhos, o resto do envelope em Cco, e aceita mensagem só em HTML'
echo 'ok: envio de conta do Microsoft Graph'
