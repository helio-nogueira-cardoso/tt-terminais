#!/usr/bin/env python3
"""Confere TODO o catálogo de fábrica do letreiro SEM rede (usado por tests/test_letreiro_catalogo.sh).

Para cada fonte de fábrica do letreiro-catalogo.json:
  - estrutura: nome válido, categoria conhecida, descrição, exemplo e data da validação, passa na validação completa;
  - segurança: só https, host público (nada de localhost/IP privado), nenhum segredo embutido, desligada de fábrica;
  - comportamento: roda pelo letreiro-fontes.py contra a resposta REAL guardada em tests/letreiro-amostras/NOME.amostra
    (servida por um servidor local) e tem de dar exatamente o item do `exemplo`.
E para cada modelo: as respostas padrão dão uma fonte válida (e, quando há amostra parecida, um item).
Imprime uma linha por problema; sai com 1 se houve algum.
"""
import http.server
import importlib.util
import ipaddress
import json
import os
import re
import sys
import tempfile
import threading
import urllib.parse
from datetime import datetime, timezone

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
H = tempfile.mkdtemp(prefix="tt-catalogo-offline-")
os.environ.update(HOME=H, XDG_CONFIG_HOME=H + "/cfg", TT_RT=H + "/rt", LC_ALL="C.utf8", TT_LETREIRO_TESTE="1")
os.makedirs(H + "/cfg/tt", exist_ok=True)
_s = importlib.util.spec_from_file_location("lf", os.path.join(RAIZ, "letreiro-fontes.py"))
lf = importlib.util.module_from_spec(_s)
_s.loader.exec_module(lf)
cat = json.load(open(os.path.join(RAIZ, "letreiro-catalogo.json"), encoding="utf-8"))
PASTA = os.path.join(RAIZ, "tests", "letreiro-amostras")
problemas = []


def p(msg):
    problemas.append(msg)
    print("XX " + msg)


class Servidor(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        nome = self.path.lstrip("/").split("/")[0].split("?")[0]
        try:
            corpo = open(os.path.join(PASTA, nome + ".amostra"), "rb").read()
        except OSError:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(corpo)))
        self.end_headers()
        self.wfile.write(corpo)


srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Servidor)
PORTA = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
CATS = {c[0] for c in cat["categorias"]}


def rodar(nome, conf, perguntas, amostra):
    """Roda a fonte contra a amostra servida localmente; devolve (ok, texto do 1º item ou erro)."""
    d = dict(conf)
    for var, _perg, padrao in perguntas:
        d["var." + var] = padrao
    d["ativa"] = "1"
    n, erros, _a = lf.validar_fonte(d, completo=True)
    if erros:
        return False, "; ".join(erros)
    f = lf.efetiva_completa(n)
    vars_ = lf.variaveis_fonte(f, 0, {})
    u = urllib.parse.urlsplit(lf.aplicar_vars_url(f["url"], vars_))
    os.environ["TT_LETREIRO_REMAP"] = "%s://%s=>http://127.0.0.1:%d/%s" % (u.scheme, u.netloc, PORTA, amostra)
    res = lf.executar(nome, n, ts_validacao, {}, {})
    if not res.ok:
        return False, res.erro or "falhou"
    if not res.itens:
        return (True, "") if f["condicao"] else (False, "sem itens")
    return True, lf.sem_marcas(res.itens[0].linha)


def segredo_embutido(conf):
    for k, v in conf.items():
        for x in (v if isinstance(v, list) else [v]):
            x = str(x)
            if k in ("header", "query") and re.search(r"(authorization|api[_-]?key|token|secret)\s*[:=]\s*[^@\s{]", x, re.I):
                return "%s: %s" % (k, x[:40])
            if re.search(r"(sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{12,}|Bearer\s+[A-Za-z0-9._-]{20,})", x):
                return "%s: parece um segredo" % k
    return ""


vistos = set()
for nome, e in cat["fabrica"].items():
    conf = e["conf"]
    if not lf.RE_NOME.match(nome):
        p("%s: nome inválido" % nome)
    if nome in vistos or nome in lf.ORIGINAIS:
        p("%s: nome repetido ou igual a uma das 3 que já vêm ligadas" % nome)
    vistos.add(nome)
    if conf.get("tags", "").split(",")[0] not in CATS:
        p("%s: a 1ª etiqueta (tags) tem de ser uma categoria do catálogo (%s): %r" % (nome, ",".join(sorted(CATS)), conf.get("tags")))
    if len(conf.get("descricao", "")) < 12:
        p("%s: falta a descrição" % nome)
    if not e.get("exemplo") and conf.get("origem") != "tt" and not conf.get("condicao"):
        p("%s: falta o exemplo (rode tests/letreiro_catalogo_rede.py --gravar)" % nome)
    if not re.match(r"^\d{4}-\d\d-\d\d$", e.get("validada", "x")) and conf.get("origem") != "tt":
        p("%s: falta a data da validação" % nome)
    if conf.get("ativa") not in (None, "0"):
        p("%s: fonte de fábrica tem de vir desligada (ativa=0)" % nome)
    if lf.NATIVAS.get(nome, {}).get("ativa") != "0":
        p("%s: não entrou desligada em NATIVAS" % nome)
    s = segredo_embutido(conf)
    if s:
        p("%s: segredo embutido no catálogo (%s)" % (nome, s))
    if conf.get("origem", "rede") == "rede":
        u = urllib.parse.urlsplit(conf.get("url", ""))
        if u.scheme != "https":
            p("%s: só https (url=%s)" % (nome, conf.get("url")))
        host = u.hostname or ""
        try:
            ip = ipaddress.ip_address(host)
            if not lf._ip_publico(ip):
                p("%s: host local/privado" % nome)
        except ValueError:
            if host in ("localhost",) or host.endswith((".local", ".internal", ".lan")):
                p("%s: host local" % nome)
        if conf.get("permitir_http") == "1" or conf.get("tls_verificar") == "0" or conf.get("proxy"):
            p("%s: catálogo de fábrica não afrouxa TLS/https nem usa proxy" % nome)

total = 0
ts_validacao = 0
for nome, e in cat["fabrica"].items():
    conf = e["conf"]
    if conf.get("origem") == "tt":
        continue
    if not os.path.exists(os.path.join(PASTA, nome + ".amostra")):
        p("%s: falta tests/letreiro-amostras/%s.amostra" % (nome, nome))
        continue
    v = e.get("validada", "2026-01-01")
    ts_validacao = datetime.strptime(v, "%Y-%m-%d").replace(hour=15, tzinfo=timezone.utc).timestamp()
    ok, item = rodar(nome, conf, (), nome)
    total += 1
    if not ok:
        p("%s: contra a amostra real: %s" % (nome, item))
    elif item != e.get("exemplo", ""):
        p("%s: o item mudou. exemplo=%r  agora=%r" % (nome, e.get("exemplo"), item))
    elif re.search(r"[\x00-\x1f\x7f-\x9f]", item):
        p("%s: item com caracteres de controle" % nome)
    elif len(item) < 3:
        p("%s: item vazio" % nome)

# modelos: respostas padrão dão fonte válida; com amostra parecida, dão item
MODELO_AMOSTRA = {"cotacao": "euro", "acao": "petr4", "bcb-serie": "selic", "github-release": "tmux-ultimo", "npm-pacote": "claude-code-ultimo",
                  "fim-de-vida": "python-ultimo", "clima": "clima-temperatura", "rss": "g1-economia", "status": "status-github"}
ts_validacao = datetime.now(timezone.utc).timestamp()
for id_, m in cat["modelos"].items():
    perg = [tuple(x) for x in m.get("perguntas", [])]
    if not perg:
        p("modelo %s: sem perguntas (então seria de fábrica)" % id_)
    if m.get("categoria") not in CATS:
        p("modelo %s: categoria desconhecida" % id_)
    s = segredo_embutido(m["conf"])
    if s:
        p("modelo %s: segredo embutido (%s)" % (id_, s))
    if id_ in lf.NATIVAS:
        p("modelo %s tem o mesmo nome de uma fonte de fábrica" % id_)
    d = dict(m["conf"])
    for var, _q, padrao in perg:
        d["var." + var] = padrao
    d["ativa"] = "1"
    _n, erros, _a = lf.validar_fonte(d, completo=True)
    if erros:
        p("modelo %s: %s" % (id_, "; ".join(erros)))
    am = MODELO_AMOSTRA.get(id_)
    if am:
        ok, item = rodar("modelo-" + id_, m["conf"], perg, am)
        total += 1
        if not ok:
            p("modelo %s contra a amostra %s: %s" % (id_, am, item))

# sobrando: amostra sem fonte
for f in os.listdir(PASTA):
    if f.endswith(".amostra") and f[:-8] not in cat["fabrica"]:
        p("amostra %s sem fonte no catálogo" % f)

# privacidade: as amostras vão para o repositório público. Nada de e-mail de pessoa (só os de contato dos próprios
# veículos, listados aqui) nem de IP que não seja o de documentação.
CONTATOS_OK = {"webmaster@grupofolha.com.br", "apps.support@aljazeera.net", "lwn@lwn.net"}
RE_EMAIL = re.compile(rb"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")
RE_IPV4 = re.compile(rb"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")
for f in sorted(os.listdir(PASTA)):
    corpo = open(os.path.join(PASTA, f), "rb").read()
    for m in set(RE_EMAIL.findall(corpo)):
        if m.decode("utf-8", "replace").lower() not in CONTATOS_OK:
            p("amostra %s tem e-mail de pessoa (%s): tire na ferramenta de rede (reduzir)" % (f, m.decode("utf-8", "replace")))
    for m in set(RE_IPV4.findall(corpo)):
        if all(int(x) <= 255 for x in m.split(b".")) and not m.startswith(b"203.0.113."):
            p("amostra %s tem endereço IP (%s)" % (f, m.decode()))

print("%d fonte(s) de fábrica, %d modelo(s), %d execução(ões) offline, %d problema(s)" % (len(cat["fabrica"]), len(cat["modelos"]), total, len(problemas)))
sys.exit(1 if problemas else 0)
