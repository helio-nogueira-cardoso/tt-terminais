#!/usr/bin/env python3
"""Auxiliar de e-mail do tt (só biblioteca padrão; roda também no Termux).

  email-tt.py descobrir DOMINIO          -> imprime chave=valor (imap/smtp; provedor= se for Microsoft/Google)
                                            pela base do Thunderbird ou pelo MX do domínio
  email-tt.py oauth-autorizar CONF       -> fluxo OAuth2 (código no aparelho ou navegador); grava o token
  email-tt.py oauth-token CONF           -> imprime um access token novo (renova pelo refresh token)
  email-tt.py testar CONF                -> testa login IMAP e SMTP; imprime ✓/✗ por serviço (rc 0 se ambos ok)
  email-tt.py pastas CONF                -> pastas especiais pelo IMAP (SPECIAL-USE: todos, enviados, lixeira…)
  email-tt.py html                       -> filtro do aerc: HTML (stdin) → texto legível, links OSC 8 clicáveis
  email-tt.py linkify                    -> pós-filtro: texto (stdin) com [N]/References → links OSC 8 clicáveis
  email-tt.py imagens DESTINO            -> e-mail cru (stdin): salva as imagens embutidas/anexas em DESTINO e lista
                                            (TSV: arq|url, rótulo) também as <img> remotas do HTML; sem baixar nada
  email-tt.py baixar-imagem URL ARQUIVO  -> baixa uma imagem remota (só http/https, até 20 MB, só image/*)

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
# Provedor pelo nome do servidor (MX ou IMAP): domínio próprio hospedado na Microsoft ou no Google.
PROVEDOR_POR_HOST = (("outlook.com", "microsoft"), ("office365.com", "microsoft"),
                     ("google.com", "gmail"), ("googlemail.com", "gmail"), ("gmail.com", "gmail"))


def provedor_de(host):
    host = (host or "").lower().rstrip(".")
    for sufixo, prov in PROVEDOR_POR_HOST:
        if host == sufixo or host.endswith("." + sufixo):
            return prov
    return ""


def servidores_dns():
    """Servidor de nomes: TT_EMAIL_DNS (ip[:porta]) ou o do sistema (/etc/resolv.conf; no Termux, $PREFIX/etc)."""
    if os.environ.get("TT_EMAIL_DNS"):
        ip, _, porta = os.environ["TT_EMAIL_DNS"].rpartition(":") if os.environ["TT_EMAIL_DNS"].count(":") == 1 \
            else (os.environ["TT_EMAIL_DNS"], "", "53")
        return [(ip, int(porta or 53))]
    ns = []
    for arq in ("/etc/resolv.conf", os.path.join(os.environ.get("PREFIX", "/usr"), "etc/resolv.conf")):
        try:
            for linha in open(arq):
                p = linha.split()
                if len(p) >= 2 and p[0] == "nameserver" and (p[1], 53) not in ns:
                    ns.append((p[1], 53))
        except OSError:
            pass
    return ns


def registros_mx(dominio):
    """Servidores MX do domínio, do mais preferido ao menos (consulta DNS direta, só biblioteca padrão)."""
    import random, struct
    ident = random.randrange(65536)
    pergunta = b"".join(bytes([len(r)]) + r.encode("idna") for r in dominio.rstrip(".").split(".")) + b"\0"
    pacote = struct.pack(">HHHHHH", ident, 0x0100, 1, 0, 0, 0) + pergunta + struct.pack(">HH", 15, 1)

    def nome(dados, i):
        partes, saltou, fim = [], False, i
        for _ in range(64):
            n = dados[i]
            if n == 0:
                i += 1
                break
            if n & 0xC0 == 0xC0:
                if not saltou:
                    fim = i + 2
                saltou, i = True, ((n & 0x3F) << 8) | dados[i + 1]
                continue
            partes.append(dados[i + 1:i + 1 + n].decode("ascii", "replace"))
            i += 1 + n
        return ".".join(partes), (fim if saltou else i)

    for ip, porta in servidores_dns():
        try:
            fam = socket.getaddrinfo(ip, porta, proto=socket.IPPROTO_UDP)[0]
            with socket.socket(fam[0], socket.SOCK_DGRAM) as s:
                s.settimeout(3)
                s.sendto(pacote, fam[4])
                dados = s.recv(4096)
            rid, flags, qd, an = struct.unpack(">HHHH", dados[:8])
            if rid != ident or flags & 0x000F:
                continue
            i = 12
            for _ in range(qd):
                i = nome(dados, i)[1] + 4
            mx = []
            for _ in range(an):
                i = nome(dados, i)[1]
                tipo, _cls, _ttl, tam = struct.unpack(">HHIH", dados[i:i + 10])
                i += 10
                if tipo == 15:
                    mx.append((struct.unpack(">H", dados[i:i + 2])[0], nome(dados, i + 2)[0]))
                i += tam
            return [h for _, h in sorted(mx)]
        except (OSError, struct.error, IndexError, UnicodeError):
            continue
    return []


def ispdb(dominio):
    """Linhas chave=valor da base do Thunderbird (ISPDB) para o domínio, ou None se ela não o conhece."""
    base = os.environ.get("TT_EMAIL_ISPDB", "https://autoconfig.thunderbird.net/v1.1/")
    try:
        with urllib.request.urlopen(base + urllib.parse.quote(dominio), timeout=TIMEOUT) as r:
            raiz = ET.fromstring(r.read())
    except Exception:
        return None
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
    linhas = []
    for tipo, pref in (("incoming", "imap"), ("outgoing", "smtp")):
        s = escolher(tipo)
        if s is None:
            continue
        seg = {"SSL": "tls", "STARTTLS": "starttls"}.get((s.findtext("socketType") or "").upper(), "nenhuma")
        linhas += [f"{pref}_host={s.findtext('hostname')}", f"{pref}_porta={s.findtext('port')}", f"{pref}_seg={seg}"]
        auth = " ".join(a.text or "" for a in s.iter("authentication"))
        if pref == "imap" and "OAuth2" in auth:
            linhas.append("oauth_possivel=1")
    return linhas or None


def descobrir(dominio):
    """Como o Thunderbird: base ISPDB pelo domínio; senão, pelo MX (Microsoft 365 e Google Workspace
    hospedam domínios próprios, e o MX entrega quem é); por fim, o palpite imap./smtp. do domínio."""
    linhas, origem = ispdb(dominio), "ispdb"
    if linhas is None:
        mx = registros_mx(dominio)
        if mx and provedor_de(mx[0]):
            print(f"provedor={provedor_de(mx[0])}\nmx={mx[0].rstrip('.')}\norigem=mx")
            return 0
        if mx:
            base = ".".join(mx[0].rstrip(".").split(".")[-2:])
            if base != dominio:
                linhas, origem = ispdb(base), "ispdb-mx"
    if linhas is None:
        print(f"imap_host=imap.{dominio}\nimap_porta=993\nimap_seg=tls")
        print(f"smtp_host=smtp.{dominio}\nsmtp_porta=587\nsmtp_seg=starttls\norigem=palpite")
        return 0
    print("\n".join(linhas))
    imap = next((l.split("=", 1)[1] for l in linhas if l.startswith("imap_host=")), "")
    if provedor_de(imap):
        print(f"provedor={provedor_de(imap)}")
    print(f"origem={origem}")
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


def link_na_tela(url):
    return osc8(url, url) if sys.stdout.isatty() else url


def link_pelo_tt(url, acao):
    """Abre (escolha do navegador: tt --abrir-link) ou copia inteiro (tt --link-copiar) um link."""
    tt = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tt")
    if not os.access(tt, os.X_OK):
        tt = "tt"
    try:
        subprocess.run([tt, "--abrir-link", url] if acao == "abrir" else [tt, "--link-copiar", "", url])
    except OSError:
        print("✗ não achei o tt para isso; copie o link acima.")


def copiar_texto(texto, rotulo):
    tt = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tt")
    try:
        subprocess.run([tt if os.access(tt, os.X_OK) else "tt", "--copiar"], input=texto, text=True)
        print(f"✓ {rotulo} copiado.")
    except OSError:
        print(f"✗ não achei o tt para copiar; o {rotulo} está acima.")


def no_terminal():
    return sys.stdin.isatty() and sys.stdout.isatty()


def menu_espera(opcoes, pronto, prazo, colado=None):
    """Menu enquanto o OAuth espera o navegador: ↑/↓, roda ou clique escolhem, ⏎ (ou a tecla da
    opção) confirma, Esc/q/Ctrl+C cancela. Antes, a espera era uma leitura de linha: as setas viravam
    ^[[A na tela. opcoes: [(tecla, rótulo, ação[, usa_terminal])]; a ação devolve None para voltar ao
    menu ou um valor para sair com ele; só a que usa_terminal (seletor, digitar) devolve o terminal ao
    modo normal enquanto roda — nas outras, tecla apertada no meio não vira ^[[A. pronto() é olhado a cada meio segundo e sai com o que devolver (não None).
    Texto colado (ou digitado fora das teclas) vai para colado(texto). Devolve "prazo" no fim do prazo
    e "cancelado" se o usuário desistir."""
    import re, select, shutil, termios, tty
    fd, out = sys.stdin.fileno(), sys.stdout
    antigo = termios.tcgetattr(fd)
    n, sel, topo, na_tela = len(opcoes), 0, None, [False]
    largura = max(20, shutil.get_terminal_size((80, 24)).columns - 4)

    def desenhar(de_novo):
        na_tela[0] = True
        if de_novo:
            out.write(f"\033[{n}A")
        for i, (tecla, rot, *_) in enumerate(opcoes):
            rot = rot if len(rot) <= largura - 4 else rot[:largura - 5] + "…"
            if i == sel:
                out.write(f"\r\033[K\033[1;36m❯ {rot}\033[0m \033[90m{tecla}\033[0m\n")
            else:
                out.write(f"\r\033[K  {rot} \033[90m{tecla}\033[0m\n")
        out.flush()

    def entrar():
        tty.setcbreak(fd, termios.TCSANOW)  # o padrão (TCSAFLUSH) jogava fora as teclas já apertadas
        # sem cursor, com mouse (SGR) e colagem marcada; pergunta onde o cursor ficou (para o clique)
        out.write("\033[?25l\033[?1000h\033[?1006h\033[?2004h")
        desenhar(False)
        out.write("\033[6n")
        out.flush()

    def sair():
        out.write("\033[?2004l\033[?1006l\033[?1000l\033[?25h")
        out.flush()
        termios.tcsetattr(fd, termios.TCSADRAIN, antigo)

    def ler(espera):
        if not select.select([fd], [], [], espera)[0]:
            return ""
        return os.read(fd, 4096).decode("utf-8", "replace")

    def apagar():  # tira o menu da tela: a saída da ação e o menu de novo ocupam o lugar dele
        if na_tela[0]:
            out.write(f"\033[{n}A\r\033[J")
            na_tela[0] = False

    def agir(i):
        terminal = len(opcoes[i]) > 3 and opcoes[i][3]
        apagar()
        if terminal:
            sair()
        else:
            out.write("\033[?25h")
            out.flush()
        r = opcoes[i][2]()
        if r is None:
            if terminal:
                entrar()
            else:
                out.write("\033[?25l")
                desenhar(False)
                out.write("\033[6n")
                out.flush()
        return r

    def colar(texto):
        apagar()
        sair()
        r = colado(texto.strip()) if colado else None
        if r is None:
            entrar()
        return r

    entrar()
    buf = ""
    try:
        while True:
            r = pronto()
            if r is not None:
                return r
            if time.time() > prazo:
                return "prazo"
            buf += ler(0.5)
            while buf:
                if buf.startswith("\033[200~"):  # colagem marcada (Ctrl+Shift+V, botão do meio)
                    fim = buf.find("\033[201~")
                    if fim < 0:
                        buf += ler(0.5)
                        if "\033[201~" not in buf:
                            break
                        continue
                    texto, buf = buf[6:fim], buf[fim + 6:]
                    r = colar(texto)
                    if r is not None:
                        return r
                    continue
                m = re.match(r"\033\[<(\d+);(\d+);(\d+)([Mm])", buf)
                if m:
                    buf = buf[m.end():]
                    b, y = int(m.group(1)), int(m.group(3))
                    if b in (64, 65):
                        sel = (sel + (1 if b == 65 else -1)) % n
                        desenhar(True)
                    elif b == 0 and m.group(4) == "M" and topo is not None and 0 <= y - topo < n:
                        sel = y - topo
                        desenhar(True)
                        r = agir(sel)
                        if r is not None:
                            return r
                    continue
                m = re.match(r"\033\[(\d+);(\d+)R", buf)
                if m:  # resposta do \033[6n: o cursor está na linha logo abaixo do menu
                    buf, topo = buf[m.end():], int(m.group(1)) - n
                    continue
                m = re.match(r"\033(?:\[|O)([AB])", buf)
                if m:
                    buf = buf[m.end():]
                    sel = (sel + (1 if m.group(1) == "B" else -1)) % n
                    desenhar(True)
                    continue
                if buf.startswith("\033"):
                    m = re.match(r"\033\[[0-9;?]*[ -/]*[@-~]", buf)
                    if m:  # outra tecla especial (Home, F1…): ignora
                        buf = buf[m.end():]
                        continue
                    if len(buf) == 1:
                        mais = ler(0.05)
                        if mais:
                            buf += mais
                            continue
                        return "cancelado"  # Esc sozinho
                    buf = buf[1:]
                    continue
                c, buf = buf[0], buf[1:]
                if c in "\r\n":
                    r = agir(sel)
                elif c in "kK":
                    sel = (sel - 1) % n
                    desenhar(True)
                    continue
                elif c in "jJ":
                    sel = (sel + 1) % n
                    desenhar(True)
                    continue
                elif c in ("\x03", "\x04"):
                    return "cancelado"
                elif any(c == o[0] for o in opcoes):
                    sel = next(i for i, o in enumerate(opcoes) if c == o[0])
                    desenhar(True)
                    r = agir(sel)
                elif colado and c.isprintable() and not c.isspace():
                    # endereço colado sem a marcação (ou digitado): junta o resto que chegar
                    texto = c + buf
                    buf = ""
                    while True:
                        mais = ler(0.3)
                        if not mais:
                            break
                        texto += mais
                    r = colar(texto.split("\n")[0])
                else:
                    continue
                if r is not None:
                    return r
    except KeyboardInterrupt:
        return "cancelado"
    finally:
        apagar()
        sair()


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
        v, codigo = r.get('verification_uri') or r.get('verification_url'), r['user_code']
        print(f"\nAbra {link_na_tela(v)} em qualquer aparelho")
        print(f"e digite o código:  {codigo}\n")
        prazo = time.time() + int(r.get("expires_in", 900))
        intervalo, res = [int(r.get("interval", 5))], {}

        def checar():
            t = post(c["oauth_token_endpoint"], {**base_oauth(c), "device_code": r["device_code"],
                     "grant_type": "urn:ietf:params:oauth:grant-type:device_code"})
            if "refresh_token" in t:
                res["rt"] = t["refresh_token"]
                return "ok"
            if t.get("error") == "slow_down":
                intervalo[0] += 5
            elif t.get("error") not in ("authorization_pending", None):
                res["erro"] = t.get("error_description") or t.get("error")
                return "erro"
            return None
        if no_terminal():
            print("Aguardando a sua confirmação… (escolher no menu não interrompe a espera)\n", flush=True)
            prox = [time.time() + intervalo[0]]

            def pronto():
                if time.time() < prox[0]:
                    return None
                prox[0] = time.time() + intervalo[0]
                return checar()
            fim = menu_espera([
                ("a", f"🌐 Abrir {v} (Chrome interno, Carbonyl ou o do sistema)", lambda: link_pelo_tt(v, "abrir"), True),
                ("c", f"📋 Copiar o código {codigo}", lambda: copiar_texto(codigo, "código")),
                ("q", "✕ Cancelar", lambda: "cancelado")], pronto, prazo)
        else:
            print("Aguardando a sua confirmação…", flush=True)
            fim = None
            while time.time() < prazo and fim is None:
                time.sleep(intervalo[0])
                fim = checar()
        if fim == "ok":
            gravar_segredo(arq_segredo(c), res["rt"])
            print("✓ autorizado; o token de renovação foi guardado em ~/.secrets (600).")
            return 0
        if fim == "erro":
            print(f"✗ {res['erro']}")
        elif fim == "cancelado":
            print("✗ autorização cancelada.")
        else:
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
    # O endereço passa da largura da tela e quebra em várias linhas: copiar ou clicar pegava um pedaço.
    # Vai como hyperlink OSC 8 (a URL inteira em cada pedaço) e com atalhos que usam a URL inteira.
    print(f"\nAbra no navegador:\n\n{link_na_tela(url)}\n")

    def colado(texto):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(texto).query)
        if "code" in q or "error" in q:
            recebido.update({k: v[0] for k, v in q.items()})
            return "colado"
        print("✗ isso não parece o endereço de volta (ele começa com http://127.0.0.1 e tem code=…).")
        return None

    def colar_digitando():
        try:
            import readline  # noqa: F401 — setas e edição na linha
        except ImportError:
            pass
        try:
            texto = input("Endereço de volta (⏎ confirma; vazio volta ao menu): ").strip()
        except EOFError:
            texto = ""
        return colado(texto) if texto else None
    if no_terminal():
        print("Depois de autorizar, o tt segue sozinho. Com o navegador em outro aparelho a página de volta")
        print("não abre: copie o endereço dela (começa com http://127.0.0.1) e cole aqui (Ctrl+Shift+V).\n", flush=True)
        fim = menu_espera([
            ("a", "🌐 Abrir no navegador (Chrome interno, Carbonyl ou o do sistema)", lambda: link_pelo_tt(url, "abrir"), True),
            ("c", "📋 Copiar o link inteiro", lambda: link_pelo_tt(url, "copiar")),
            ("v", "📥 Colar o endereço de volta (navegador em outro aparelho)", colar_digitando, True),
            ("q", "✕ Cancelar", lambda: "cancelado")], lambda: "ok" if recebido else None, time.time() + 600, colado)
        if fim == "cancelado":
            print("✗ autorização cancelada.")
            return 1
    else:
        print("⏎ abre este link (Chrome interno, Carbonyl ou o navegador do sistema) · c ⏎ copia o link inteiro.")
        print("Depois de autorizar: se o navegador está NESTA máquina, aguarde; se está em outro aparelho,")
        print("copie o endereço da página que não abriu (começa com http://127.0.0.1) e cole aqui.\n", flush=True)
    for _ in range(0 if no_terminal() else 600):
        if recebido:
            break
        import select
        if select.select([sys.stdin], [], [], 1)[0]:
            bruta = sys.stdin.readline()
            linha = bruta.strip()
            if bruta and (not linha or linha.lower() == "c"):
                link_pelo_tt(url, "copiar" if linha else "abrir")
            elif linha:
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
# --- Links clicáveis (OSC 8) ----------------------------------------------------------------------
# Hyperlink de terminal: a URL fica no escape, o texto visível é o rótulo. O terminal abre a URL
# inteira num clique (Ctrl+clique no GNOME Terminal/VTE; toque no Termux), mesmo que o rótulo esteja
# quebrado em várias linhas na tela — era aí que o clique pegava só um pedaço e caía em "wrong link".
# Terminais sem suporte a OSC 8 ignoram o escape e mostram só o rótulo, sem prejuízo.
def osc8(url, texto):
    return "\033]8;;{}\033\\{}\033]8;;\033\\".format(url, texto)


# Pós-filtro para a saída do w3m/lynx, inclusive já colorida pelo filtro "colorize" do aerc (que
# roda antes): torna cada [N] e cada URL da seção "References" clicáveis via OSC 8. É tolerante a
# códigos ANSI (SGR) ao redor do texto: a URL dentro do escape OSC 8 fica SEM ANSI (senão o terminal
# recebe uma URL corrompida e o clique falha), e o texto visível mantém as cores. Idempotente e
# seguro: sem References, devolve a entrada intacta.
def linkify(texto):
    import re
    ANSI = re.compile(r'\033\[[0-9;]*m')
    def limpo(s):
        return ANSI.sub('', s)
    # "References:" pode vir cercado de ANSI (ex.: \033[1;34mReferences:\033[0m).
    partes = re.split(r'\n[ \t]*(?:\033\[[0-9;]*m)*References:(?:\033\[[0-9;]*m)*[ \t]*\n', texto, maxsplit=1)
    corpo = partes[0]
    refs = {}
    if len(partes) == 2:
        for linha in partes[1].splitlines():
            m = re.match(r'\s*\[(\d+)\]\s+(.+?)\s*$', limpo(linha))
            if m and m.group(2):
                refs[m.group(1)] = m.group(2)
    if not refs:
        return texto
    # No corpo, o [N] também pode estar colorido; casa o número ignorando ANSI entre os colchetes.
    def env_marca(m):
        n = re.match(r'\[(\d+)\]', limpo(m.group(0)))
        return osc8(refs[n.group(1)], m.group(0)) if n and n.group(1) in refs else m.group(0)
    corpo = re.sub(r'\[(?:\033\[[0-9;]*m)*\d+(?:\033\[[0-9;]*m)*\]', env_marca, corpo)
    linhas = [corpo.rstrip("\n"), "", "References:", ""]
    for n, u in sorted(refs.items(), key=lambda x: int(x[0])):
        # Rótulo visível = a URL (sem ANSI, para ficar legível e copiável); alvo = a mesma URL limpa.
        linhas.append("[{}] {}".format(n, osc8(u, u)))
    return "\n".join(linhas) + "\n"


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


def lista_imagens(bruto, destino):
    """Imagens de um e-mail cru: partes image/* viram arquivos em DESTINO; <img src=http…> do HTML
    só são listadas (nada é baixado sem o usuário pedir). Imprime linhas 'arq<TAB>caminho<TAB>rótulo'
    e 'url<TAB>URL<TAB>rótulo'."""
    import email, email.policy, html.parser, mimetypes, re
    msg = email.message_from_bytes(bruto, policy=email.policy.default)
    os.makedirs(destino, exist_ok=True)
    saida, vistos, n = [], set(), 0
    htmls = []
    for parte in msg.walk():
        tipo = parte.get_content_type()
        if tipo == "text/html":
            try:
                htmls.append(parte.get_content())
            except Exception:
                pass
        if parte.get_content_maintype() != "image":
            continue
        dados = parte.get_payload(decode=True)
        if not dados:
            continue
        n += 1
        nome = parte.get_filename() or ""
        nome = re.sub(r"[^\w.\- ]", "_", os.path.basename(nome)).strip() or "imagem"
        if "." not in nome:
            nome += mimetypes.guess_extension(tipo) or ".img"
        caminho = os.path.join(destino, f"{n:02d}-{nome}")
        with open(caminho, "wb") as f:
            f.write(dados)
        saida.append(("arq", caminho, f"{nome} · {len(dados) // 1024 or 1} KB · anexada"))

    class Img(html.parser.HTMLParser):
        def handle_starttag(self, tag, atributos):
            if tag != "img":
                return
            a = dict(atributos)
            u = (a.get("src") or "").strip()
            if not u.lower().startswith(("http://", "https://")) or u in vistos:
                return
            vistos.add(u)
            def lado(k):
                m = re.match(r"\d+", a.get(k) or "")
                return int(m.group()) if m else None
            if (lado("width") or 99) <= 2 or (lado("height") or 99) <= 2:
                return  # pixel de rastreamento: não vale listar
            host = urllib.parse.urlparse(u).netloc
            saida.append(("url", u, f"{(a.get('alt') or '').strip()[:40] or os.path.basename(urllib.parse.urlparse(u).path)[:40] or 'imagem'} · {host} · da web"))
    for h in htmls:
        Img().feed(h)
    for linha in saida:
        print("\t".join(linha))
    return 0


def baixar_imagem(url, arquivo):
    if not url.lower().startswith(("http://", "https://")):
        print("✗ só http/https", file=sys.stderr); return 1
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (tt)"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            if not (r.headers.get_content_type() or "").startswith("image/"):
                print(f"✗ não é imagem ({r.headers.get_content_type()})", file=sys.stderr); return 1
            dados = r.read(20 * 1024 * 1024 + 1)
    except Exception as e:
        print(f"✗ {erro_curto(e)}", file=sys.stderr); return 1
    if len(dados) > 20 * 1024 * 1024:
        print("✗ maior que 20 MB", file=sys.stderr); return 1
    with open(arquivo, "wb") as f:
        f.write(dados)
    return 0


def main(a):
    if a[:1] == ["html"]:
        dados = sys.stdin.buffer.read()
        sys.stdout.write(html_para_texto(dados.decode("utf-8", "replace"))); return 0
    if a[:1] == ["linkify"]:
        sys.stdout.write(linkify(sys.stdin.buffer.read().decode("utf-8", "replace"))); return 0
    if a[:1] == ["imagens"] and len(a) == 2:
        return lista_imagens(sys.stdin.buffer.read(), a[1])
    if a[:1] == ["baixar-imagem"] and len(a) == 3:
        return baixar_imagem(a[1], a[2])
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
