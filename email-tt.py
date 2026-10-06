#!/usr/bin/env python3
"""Auxiliar de e-mail do tt (só biblioteca padrão; roda também no Termux).

  email-tt.py descobrir DOMINIO          -> imprime chave=valor (imap/smtp) pela base do Thunderbird
  email-tt.py oauth-autorizar CONF       -> fluxo OAuth2 (código no aparelho ou navegador); grava o token
  email-tt.py oauth-token CONF           -> imprime um access token novo (renova pelo refresh token)
  email-tt.py testar CONF                -> testa login IMAP e SMTP; imprime ✓/✗ por serviço (rc 0 se ambos ok)
  email-tt.py pastas CONF                -> pastas especiais pelo IMAP (SPECIAL-USE: todos, enviados, lixeira…)
  email-tt.py html                       -> filtro do aerc: HTML (stdin) → texto legível, links numerados no fim

CONF é o arquivo chave=valor da conta (~/.config/tt/email/<slug>.conf). Segredos ficam em
~/.secrets/aerc-<slug>.txt (senha ou refresh token) e ~/.secrets/aerc-<slug>.client_secret; este
programa nunca imprime senha nem refresh token (só o access token, quando pedido por oauth-token).
"""
import base64, imaplib, json, os, smtplib, socket, ssl, subprocess, sys, time
import urllib.parse, urllib.request, xml.etree.ElementTree as ET

SEGREDOS = os.path.expanduser("~/.secrets")
TIMEOUT = 15


def ler_conf(caminho):
    c = {}
    with open(caminho, encoding="utf-8") as f:
        for linha in f:
            linha = linha.rstrip("\n")
            if not linha or linha.startswith("#") or "=" not in linha:
                continue
            k, v = linha.split("=", 1)
            c[k.strip()] = v
    c["_slug"] = os.path.splitext(os.path.basename(caminho))[0]
    return c


def arq_segredo(c, sufixo="txt"):
    return os.path.join(SEGREDOS, f"aerc-{c['_slug']}.{sufixo}")


def gravar_segredo(caminho, valor):
    os.makedirs(SEGREDOS, mode=0o700, exist_ok=True)
    fd = os.open(caminho + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(valor)
    os.replace(caminho + ".tmp", caminho)


def ler_arquivo(caminho):
    try:
        with open(caminho, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


# --- Descoberta pelo domínio (ISPDB do Thunderbird) ---------------------------------------------
def descobrir(dominio):
    url = f"https://autoconfig.thunderbird.net/v1.1/{urllib.parse.quote(dominio)}"
    try:
        with urllib.request.urlopen(url, timeout=TIMEOUT) as r:
            xml = r.read()
    except Exception:
        # Sem registro: o palpite mais comum (imap./smtp. do domínio).
        print(f"imap_host=imap.{dominio}\nimap_porta=993\nimap_seg=tls")
        print(f"smtp_host=smtp.{dominio}\nsmtp_porta=587\nsmtp_seg=starttls\norigem=palpite")
        return 0
    raiz = ET.fromstring(xml)
    def escolher(tipo):
        melhor = None
        for s in raiz.iter(f"{tipo}Server" if tipo == "incoming" else "outgoingServer"):
            if tipo == "incoming" and s.get("type") != "imap":
                continue
            seg = (s.findtext("socketType") or "").upper()
            nota = {"SSL": 0, "STARTTLS": 1}.get(seg, 2)
            if melhor is None or nota < melhor[0]:
                melhor = (nota, s)
        return melhor[1] if melhor else None
    for tipo, pref in (("incoming", "imap"), ("outgoing", "smtp")):
        s = escolher(tipo)
        if s is None:
            continue
        seg = {"SSL": "tls", "STARTTLS": "starttls"}.get((s.findtext("socketType") or "").upper(), "nenhuma")
        print(f"{pref}_host={s.findtext('hostname')}\n{pref}_porta={s.findtext('port')}\n{pref}_seg={seg}")
        auth = " ".join(a.text or "" for a in s.iter("authentication"))
        if pref == "imap" and "OAuth2" in auth:
            print("oauth_possivel=1")
    print("origem=ispdb")
    return 0


# --- OAuth2 --------------------------------------------------------------------------------------
def post(url, dados):
    req = urllib.request.Request(url, data=urllib.parse.urlencode(dados).encode(), method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read())
        except Exception:
            return {"error": f"http {e.code}"}


def base_oauth(c):
    d = {"client_id": c.get("oauth_client_id", "")}
    segredo = ler_arquivo(arq_segredo(c, "client_secret"))
    if segredo:
        d["client_secret"] = segredo
    return d


def oauth_autorizar(c):
    if not c.get("oauth_client_id"):
        print("✗ falta oauth_client_id na conta (edite a conta e informe o ID do app OAuth).")
        return 1
    escopo = c.get("oauth_scope", "")
    if c.get("oauth_device_endpoint"):
        # Fluxo de código no aparelho: funciona mesmo por ssh, com o navegador em outro aparelho.
        r = post(c["oauth_device_endpoint"], {**base_oauth(c), "scope": escopo})
        if "device_code" not in r:
            print(f"✗ não consegui iniciar a autorização: {r.get('error_description') or r.get('error')}")
            return 1
        print(f"\nAbra {r.get('verification_uri') or r.get('verification_url')} em qualquer aparelho")
        print(f"e digite o código:  {r['user_code']}\n\nAguardando a sua confirmação…", flush=True)
        prazo = time.time() + int(r.get("expires_in", 900))
        intervalo = int(r.get("interval", 5))
        while time.time() < prazo:
            time.sleep(intervalo)
            t = post(c["oauth_token_endpoint"], {**base_oauth(c), "device_code": r["device_code"],
                     "grant_type": "urn:ietf:params:oauth:grant-type:device_code"})
            if "refresh_token" in t:
                gravar_segredo(arq_segredo(c), t["refresh_token"])
                print("✓ autorizado; o token de renovação foi guardado em ~/.secrets (600).")
                return 0
            if t.get("error") == "slow_down":
                intervalo += 5
            elif t.get("error") not in ("authorization_pending", None):
                print(f"✗ {t.get('error_description') or t.get('error')}")
                return 1
        print("✗ o prazo para confirmar acabou; tente de novo.")
        return 1
    # Fluxo com navegador (Google e outros): o navegador volta para http://127.0.0.1:PORTA. Se o
    # navegador estiver em outro aparelho, a página "não abre": copie o endereço dela e cole aqui.
    import http.server, threading, secrets as sec
    estado = sec.token_urlsafe(16)
    recebido = {}
    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            recebido.update({k: v[0] for k, v in q.items()})
            self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8"); self.end_headers()
            self.wfile.write("<p>Pronto: pode fechar esta aba e voltar ao terminal.</p>".encode())
        def log_message(self, *a):
            pass
    srv = http.server.HTTPServer(("127.0.0.1", 0), H)
    redir = f"http://127.0.0.1:{srv.server_address[1]}/"
    threading.Thread(target=srv.handle_request, daemon=True).start()
    url = c["oauth_auth_endpoint"] + "?" + urllib.parse.urlencode({
        "client_id": c["oauth_client_id"], "response_type": "code", "redirect_uri": redir,
        "scope": escopo, "state": estado, "access_type": "offline", "prompt": "consent"})
    print(f"\nAbra no navegador:\n\n{url}\n")
    print("Depois de autorizar: se o navegador está NESTA máquina, aguarde; se está em outro aparelho,")
    print("copie o endereço da página que não abriu (começa com http://127.0.0.1) e cole aqui.\n")
    for _ in range(600):
        if recebido:
            break
        import select
        if select.select([sys.stdin], [], [], 1)[0]:
            linha = sys.stdin.readline().strip()
            if linha:
                q = urllib.parse.parse_qs(urllib.parse.urlparse(linha).query)
                recebido.update({k: v[0] for k, v in q.items()})
    if recebido.get("state") != estado or "code" not in recebido:
        print(f"✗ autorização não concluída ({recebido.get('error', 'sem código')}).")
        return 1
    t = post(c["oauth_token_endpoint"], {**base_oauth(c), "code": recebido["code"],
             "redirect_uri": redir, "grant_type": "authorization_code"})
    if "refresh_token" not in t:
        print(f"✗ {t.get('error_description') or t.get('error') or 'sem refresh token'}")
        return 1
    gravar_segredo(arq_segredo(c), t["refresh_token"])
    print("✓ autorizado; o token de renovação foi guardado em ~/.secrets (600).")
    return 0


def access_token(c):
    rt = ler_arquivo(arq_segredo(c))
    if not rt:
        raise RuntimeError("conta ainda não autorizada (use “autorizar”)")
    t = post(c["oauth_token_endpoint"], {**base_oauth(c), "refresh_token": rt,
             "grant_type": "refresh_token", "scope": c.get("oauth_scope", "")})
    if "access_token" not in t:
        raise RuntimeError(t.get("error_description") or t.get("error") or "falha ao renovar o token")
    if t.get("refresh_token") and t["refresh_token"] != rt:
        gravar_segredo(arq_segredo(c), t["refresh_token"])  # provedores que giram o refresh token
    return t["access_token"]


# --- Teste de conexão ------------------------------------------------------------------------------
def credencial(c):
    auth = c.get("auth", "senha")
    if auth == "comando":
        r = subprocess.run(c.get("cred_cmd", "false"), shell=True, capture_output=True, text=True, timeout=60)
        if r.returncode != 0:
            raise RuntimeError(f"o comando da senha falhou (código {r.returncode})")
        return "senha", r.stdout.strip()
    if auth.startswith("oauth"):
        return "oauth", access_token(c)
    s = ler_arquivo(arq_segredo(c))
    if not s:
        raise RuntimeError("senha não cadastrada")
    return "senha", s


def xoauth2(usuario, token):
    return f"user={usuario}\x01auth=Bearer {token}\x01\x01"


def testar_imap(c, tipo, segredo):
    host, porta, seg = c["imap_host"], int(c.get("imap_porta") or 993), c.get("imap_seg", "tls")
    ctx = ssl.create_default_context()
    m = imaplib.IMAP4_SSL(host, porta, ssl_context=ctx, timeout=TIMEOUT) if seg == "tls" else imaplib.IMAP4(host, porta, timeout=TIMEOUT)
    try:
        if seg == "starttls":
            m.starttls(ssl_context=ctx)
        usuario = c.get("usuario") or c.get("endereco")
        if tipo == "oauth":
            m.authenticate("XOAUTH2", lambda _: xoauth2(usuario, segredo).encode())
        else:
            m.login(usuario, segredo)
        st, dados = m.select(c.get("pasta") or "INBOX", readonly=True)
        n = dados[0].decode() if st == "OK" and dados and dados[0] else "?"
        return f"login ok, {c.get('pasta') or 'INBOX'} com {n} mensagens"
    finally:
        try:
            m.logout()
        except Exception:
            pass


def testar_smtp(c, tipo, segredo):
    host, porta, seg = c["smtp_host"], int(c.get("smtp_porta") or 587), c.get("smtp_seg", "starttls")
    ctx = ssl.create_default_context()
    s = smtplib.SMTP_SSL(host, porta, context=ctx, timeout=TIMEOUT) if seg == "tls" else smtplib.SMTP(host, porta, timeout=TIMEOUT)
    try:
        s.ehlo()
        if seg == "starttls":
            s.starttls(context=ctx); s.ehlo()
        usuario = c.get("usuario") or c.get("endereco")
        if tipo == "oauth":
            cod, resp = s.docmd("AUTH", "XOAUTH2 " + base64.b64encode(xoauth2(usuario, segredo).encode()).decode())
            if cod != 235:
                raise smtplib.SMTPAuthenticationError(cod, resp)
        else:
            s.login(usuario, segredo)
        return "login ok (nada foi enviado)"
    finally:
        try:
            s.quit()
        except Exception:
            pass


def erro_curto(e):
    if isinstance(e, (socket.timeout, TimeoutError)):
        return "sem resposta do servidor (porta bloqueada ou endereço errado?)"
    if isinstance(e, socket.gaierror):
        return "servidor não encontrado (endereço errado ou sem rede)"
    if isinstance(e, ConnectionRefusedError):
        return "conexão recusada (porta errada?)"
    if isinstance(e, ssl.SSLError):
        return f"falha de TLS ({e.reason or e}); confira a segurança (TLS/STARTTLS) e a porta"
    if isinstance(e, (imaplib.IMAP4.error, smtplib.SMTPAuthenticationError)):
        return "usuário ou senha recusados" + (f": {e}" if str(e) else "")
    return str(e) or e.__class__.__name__


def pastas(c):
    """Pastas especiais pelas marcas do servidor (RFC 6154), que não dependem do idioma."""
    tipo, segredo = credencial(c)
    host, porta, seg = c["imap_host"], int(c.get("imap_porta") or 993), c.get("imap_seg", "tls")
    ctx = ssl.create_default_context()
    m = imaplib.IMAP4_SSL(host, porta, ssl_context=ctx, timeout=TIMEOUT) if seg == "tls" else imaplib.IMAP4(host, porta, timeout=TIMEOUT)
    try:
        if seg == "starttls":
            m.starttls(ssl_context=ctx)
        usuario = c.get("usuario") or c.get("endereco")
        if tipo == "oauth":
            m.authenticate("XOAUTH2", lambda _: xoauth2(usuario, segredo).encode())
        else:
            m.login(usuario, segredo)
        st, linhas = m.list()
        import re
        marcas = {"\\All": "todos", "\\Sent": "enviados", "\\Trash": "lixeira", "\\Drafts": "rascunhos", "\\Junk": "spam", "\\Archive": "arquivo"}
        for l in linhas or []:
            l = l.decode("utf-8", "replace") if isinstance(l, bytes) else str(l)
            r = re.match(r'\((?P<f>[^)]*)\) (?:"[^"]*"|NIL) (?P<n>.*)$', l)
            if not r:
                continue
            nome = r.group("n").strip()
            if nome.startswith('"') and nome.endswith('"'):
                nome = nome[1:-1].replace('\\"', '"')
            nome = decodificar_utf7(nome)
            for marca, chave in marcas.items():
                if marca in r.group("f"):
                    print(f"{chave}={nome}")
            if "\\Noselect" in r.group("f") or "\\NoSelect" in r.group("f"):
                print(f"naoabre={nome}")
        return 0
    finally:
        try:
            m.logout()
        except Exception:
            pass


def decodificar_utf7(s):
    """Nomes de pasta IMAP vêm em UTF-7 modificado ("E-mails enviados" pode vir como &AOk-…)."""
    import re
    def dec(m):
        t = m.group(1)
        if t == "":
            return "&"
        b = t.replace(",", "/")
        b += "=" * (-len(b) % 4)
        return base64.b64decode(b).decode("utf-16-be")
    return re.sub(r"&([A-Za-z0-9+,]*)-", dec, s)


def testar(c):
    ok = True
    try:
        tipo, segredo = credencial(c)
    except Exception as e:
        print(f"✗ credencial: {erro_curto(e)}")
        return 1
    for nome, f in (("IMAP (receber)", testar_imap), ("SMTP (enviar)", testar_smtp)):
        try:
            print(f"✓ {nome}: {f(c, tipo, segredo)}", flush=True)
        except Exception as e:
            ok = False
            print(f"✗ {nome}: {erro_curto(e)}", flush=True)
    return 0 if ok else 1


# --- HTML → texto (filtro do aerc quando não há w3m/lynx) -----------------------------------------
def html_para_texto(html):
    from html.parser import HTMLParser
    import re, textwrap, shutil
    largura = max(40, min(int(os.environ.get("AERC_COLUMNS") or shutil.get_terminal_size((100, 24)).columns) - 2, 110))
    class P(HTMLParser):
        BLOCO = {"p", "div", "br", "tr", "table", "ul", "ol", "li", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "hr", "section", "article", "header", "footer"}
        def __init__(self):
            super().__init__(convert_charrefs=True)
            self.saida, self.links, self.ignorar, self.href = [], [], 0, None
        def handle_starttag(self, tag, attrs):
            a = dict(attrs)
            if tag in ("script", "style", "head", "title"):
                self.ignorar += 1
            elif tag == "a":
                self.href = a.get("href")
            elif tag == "img" and a.get("alt"):
                self.saida.append(f"[imagem: {a['alt']}]")
            if tag in self.BLOCO:
                self.saida.append("\n")
            if tag == "li":
                self.saida.append("  • ")
            if tag in ("h1", "h2", "h3"):
                self.saida.append("\n")
        def handle_endtag(self, tag):
            if tag in ("script", "style", "head", "title"):
                self.ignorar = max(0, self.ignorar - 1)
            elif tag == "a" and self.href:
                h = self.href
                if h.startswith(("http", "mailto:")) and h not in self.links:
                    self.links.append(h)
                if h in self.links:
                    self.saida.append(f" [{self.links.index(h) + 1}]")
                self.href = None
            if tag in self.BLOCO:
                self.saida.append("\n")
        def handle_data(self, d):
            if not self.ignorar:
                self.saida.append(re.sub(r"\s+", " ", d))
    p = P(); p.feed(html); p.close()
    texto = "".join(p.saida)
    linhas, vazio = [], 0
    for l in texto.split("\n"):
        l = l.strip()
        if not l:
            vazio += 1
            if vazio <= 1: linhas.append("")
            continue
        vazio = 0
        ind = "  " if l.startswith("•") else ""
        linhas.extend(textwrap.wrap(l, largura, subsequent_indent=ind + "  " if ind else "") or [""])
    corpo = "\n".join(linhas).strip()
    if p.links:
        corpo += "\n\n" + "\n".join(f"[{i}] {u}" for i, u in enumerate(p.links, 1))
    return corpo + "\n"


def main(a):
    if a[:1] == ["html"]:
        dados = sys.stdin.buffer.read()
        sys.stdout.write(html_para_texto(dados.decode("utf-8", "replace"))); return 0
    if len(a) < 2:
        print(__doc__); return 2
    cmd, arg = a[0], a[1]
    if cmd == "descobrir":
        return descobrir(arg)
    c = ler_conf(arg)
    if cmd == "oauth-autorizar":
        return oauth_autorizar(c)
    if cmd == "oauth-token":
        try:
            print(access_token(c)); return 0
        except Exception as e:
            print(f"✗ {e}", file=sys.stderr); return 1
    if cmd == "testar":
        return testar(c)
    if cmd == "pastas":
        try:
            return pastas(c)
        except Exception as e:
            print(f"✗ {erro_curto(e)}", file=sys.stderr); return 1
    print(__doc__); return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
