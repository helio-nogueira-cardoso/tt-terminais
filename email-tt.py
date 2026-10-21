#!/usr/bin/env python3
"""Auxiliar de e-mail do tt (só biblioteca padrão; roda também no Termux).

  email-tt.py descobrir DOMINIO          -> imprime chave=valor (imap/smtp; provedor= se for Microsoft/Google)
                                            pela base do Thunderbird ou pelo MX do domínio
  email-tt.py oauth-autorizar CONF       -> fluxo OAuth2 (código no aparelho ou navegador); grava o token
  email-tt.py oauth-token CONF           -> imprime um access token novo (renova pelo refresh token)
  email-tt.py testar CONF                -> testa login IMAP e SMTP; imprime ✓/✗ por serviço (rc 0 se ambos ok)
  email-tt.py graph-testar CONF          -> testa acesso e leitura pelo Microsoft Graph
  email-tt.py graph-sendmail CONF DEST…  -> sendmail do aerc: envia stdin pela API REST do Outlook
  email-tt.py enviar CONF OPÇÕES…        -> tt --email-enviar: monta e envia (SMTP ou Outlook REST); --ensaio só mostra
  email-tt.py pastas CONF                -> pastas especiais pelo IMAP (SPECIAL-USE: todos, enviados, lixeira…)
  email-tt.py lixeira CONF [--esvaziar]  -> pasta= e mensagens= da lixeira da conta (a pasta \\Trash do servidor);
                                            com --esvaziar, apaga todas de vez e imprime apagadas= e restam=
  email-tt.py lote-pastas CONF           -> nome de cada pasta que dá para abrir
  email-tt.py lote-contar CONF PASTA BUSCA [--amostra N] [--salvar ARQ]
                                         -> total= e amostra (data, remetente, assunto) do que casa com BUSCA;
                                            --salvar grava os UIDs exatos para o lote-agir
  email-tt.py lote-agir CONF ARQ apagar|mover|arquivar|lidas|nao-lidas [--destino PASTA] [--de-vez]
                                         -> age nos UIDs do ARQ, em blocos de 500 (progresso= no stderr)
  email-tt.py html                       -> filtro do aerc: HTML (stdin) → texto legível, links OSC 8 clicáveis
  email-tt.py linkify                    -> pós-filtro: texto (stdin) com [N]/References → links OSC 8 clicáveis
  email-tt.py imagens DESTINO            -> e-mail cru (stdin): salva as imagens embutidas/anexas em DESTINO e lista
                                            (TSV: arq|url, rótulo) também as <img> remotas do HTML; sem baixar nada
  email-tt.py baixar-imagem URL ARQUIVO  -> baixa uma imagem remota (só http/https, até 20 MB, só image/*)
  email-tt.py contatos-indexar [--sem=END,…] MAILDIR…
                                         -> "endereço<TAB>nome<TAB>vezes" dos remetentes e destinatários
                                            dos e-mails (só os cabeçalhos), os mais frequentes primeiro

CONF é o arquivo chave=valor da conta (~/.config/tt/email/<slug>.conf). Segredos ficam em
~/.secrets/aerc-<slug>.txt (senha ou refresh token) e ~/.secrets/aerc-<slug>.client_secret; este
programa nunca imprime senha nem refresh token (só o access token, quando pedido por oauth-token).
"""
import base64, imaplib, json, os, smtplib, socket, ssl, subprocess, sys, time
import email as email_lib
import email.policy
import urllib.parse, urllib.request, xml.etree.ElementTree as ET


def contexto_ssl():
    """Contexto TLS padrão, sem o modo ESTRITO de X.509 do Python 3.13+: uma CA de inspeção corporativa (Netskope e afins), que o
    sistema já confia mas não declara keyUsage, reprovava com "CA cert does not include key usage extension". A cadeia, o
    nome do servidor e a data continuam verificados."""
    c = ssl.create_default_context()
    c.verify_flags &= ~getattr(ssl, "VERIFY_X509_STRICT", 0)
    return c


SEGREDOS = os.path.expanduser("~/.secrets")
TIMEOUT = 15
# Espera pelo resto de uma tecla especial depois do ESC (seta, clique), a mesma das telas do tt (TT_ESC_SEQ).
try:
    ESC_SEQ = float(os.environ.get("TT_ESC_SEQ") or 0.3)
except ValueError:
    ESC_SEQ = 0.3


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
        with urllib.request.urlopen(base + urllib.parse.quote(dominio), timeout=TIMEOUT, context=contexto_ssl()) as r:
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
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=contexto_ssl()) as r:
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
                    if re.fullmatch(r"\033(?:\[[0-?]*[ -/]*|O)?", buf):
                        # Tecla especial pela metade: o resto pode chegar depois do ESC (máquina carregada, ssh
                        # lento). Com 50 ms a seta virava Esc, e com só o "\033[" o "B" virava tecla solta.
                        mais = ler(ESC_SEQ)
                        if mais:
                            buf += mais
                            continue
                        if len(buf) == 1:
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
    ctx = contexto_ssl()
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
    ctx = contexto_ssl()
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


def imap_conectar(c):
    """Conexão IMAP já autenticada (senha, comando ou OAuth2), como nos testes de conta."""
    tipo, segredo = credencial(c)
    host, porta, seg = c["imap_host"], int(c.get("imap_porta") or 993), c.get("imap_seg", "tls")
    ctx = contexto_ssl()
    m = imaplib.IMAP4_SSL(host, porta, ssl_context=ctx, timeout=TIMEOUT) if seg == "tls" else imaplib.IMAP4(host, porta, timeout=TIMEOUT)
    try:
        if seg == "starttls":
            m.starttls(ssl_context=ctx)
        usuario = c.get("usuario") or c.get("endereco")
        if tipo == "oauth":
            m.authenticate("XOAUTH2", lambda _: xoauth2(usuario, segredo).encode())
        else:
            m.login(usuario, segredo)
    except Exception:
        try:
            m.logout()
        except Exception:
            pass
        raise
    return m


def listar_pastas(m):
    """(marcas, nome como o servidor o escreve, nome legível) de cada pasta do LIST."""
    import re
    st, linhas = m.list()
    saida = []
    for l in linhas or []:
        l = l.decode("utf-8", "replace") if isinstance(l, bytes) else str(l)
        r = re.match(r'\((?P<f>[^)]*)\) (?:"[^"]*"|NIL) (?P<n>.*)$', l)
        if not r:
            continue
        nome = r.group("n").strip()
        if nome.startswith('"') and nome.endswith('"'):
            nome = nome[1:-1].replace('\\"', '"')
        saida.append((r.group("f"), nome, decodificar_utf7(nome)))
    return saida


def pastas(c):
    """Pastas especiais pelas marcas do servidor (RFC 6154), que não dependem do idioma."""
    m = imap_conectar(c)
    try:
        # \Important e \Flagged são as "pastas-rótulo" do Gmail (Importantes, Com estrela): o sync
        # local as deixa de fora, porque são visões do que já está nas outras pastas.
        marcas = {"\\All": "todos", "\\Sent": "enviados", "\\Trash": "lixeira", "\\Drafts": "rascunhos", "\\Junk": "spam", "\\Archive": "arquivo",
                  "\\Important": "importantes", "\\Flagged": "estrela"}
        for f, _, nome in listar_pastas(m):
            for marca, chave in marcas.items():
                if marca in f:
                    print(f"{chave}={nome}")
            if "\\Noselect" in f or "\\NoSelect" in f:
                print(f"naoabre={nome}")
        return 0
    finally:
        try:
            m.logout()
        except Exception:
            pass


def lixeira(c, esvaziar=False):
    """Quantas mensagens há na lixeira e, com esvaziar, apaga todas de vez (STORE \\Deleted + EXPUNGE).
    A lixeira é a pasta que o servidor marca como \\Trash (RFC 6154; não depende do idioma). Sem essa
    marca, vale a pasta_lixeira do cadastro, se o servidor a tiver. Nunca toca outra pasta."""
    m = imap_conectar(c)
    try:
        todas = listar_pastas(m)
        alvo = [p for p in todas if "\\Trash" in p[0]]
        if not alvo and c.get("pasta_lixeira"):
            alvo = [p for p in todas if p[2] == c["pasta_lixeira"]]
        if not alvo:
            raise RuntimeError("não achei a lixeira desta conta no servidor")
        _, bruto, nome = alvo[0]
        if nome.upper() == "INBOX":
            raise RuntimeError("a pasta marcada como lixeira é a Caixa de entrada; não mexi")
        caixa = '"' + bruto.replace("\\", "\\\\").replace('"', '\\"') + '"'
        st, d = m.select(caixa, readonly=not esvaziar)
        if st != "OK":
            raise RuntimeError(f"não consegui abrir {nome}")
        n = int(d[0] or 0)
        print(f"pasta={nome}")
        print(f"mensagens={n}")
        if esvaziar:
            if n:
                st, _ = m.store("1:*", "+FLAGS.SILENT", "(\\Deleted)")
                if st != "OK":
                    raise RuntimeError("o servidor recusou marcar as mensagens para apagar")
                st, _ = m.expunge()
                if st != "OK":
                    raise RuntimeError("o servidor recusou apagar as mensagens")
                st, d = m.select(caixa, readonly=True)
                resta = int(d[0] or 0) if st == "OK" else 0
            else:
                resta = 0
            print(f"apagadas={max(n - resta, 0)}")
            print(f"restam={resta}")
        return 0
    finally:
        try:
            m.logout()
        except Exception:
            pass


LOTE_BLOCO = 500


def _capacidades(m):
    """CAPABILITY depois do login (a do cumprimento do servidor pode vir sem MOVE/UIDPLUS)."""
    try:
        st, d = m.capability()
        if st == "OK" and d and d[0]:
            t = d[0].decode() if isinstance(d[0], bytes) else str(d[0])
            return set(t.upper().split())
    except Exception:
        pass
    return {str(x).upper() for x in (getattr(m, "capabilities", ()) or ())}


def _q(nome):
    return '"' + nome.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lote_criterio(busca, caps=()):
    """Busca simples do tt → critérios do IMAP SEARCH. Termos (combinados com E):
    todas · nao-lidas · lidas · com-estrela · de:X · para:X · assunto:X · texto:X · antes:AAAA-MM-DD ·
    desde:AAAA-MM-DD · maior:N[k|m] · menor:N[k|m] · gmail:"busca do Gmail" (só no Gmail). Palavra solta = texto:."""
    import re, shlex, datetime
    meses = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
    try:
        termos = shlex.split(busca or "")
    except ValueError as e:
        raise RuntimeError(f"busca mal formada: {e}")
    crit = []
    for t in termos:
        k, sep, v = t.partition(":")
        k = k.lower()
        if not sep and k in ("todas", "tudo", "all"):
            continue
        if not sep and k in ("nao-lidas", "não-lidas", "naolidas"):
            crit.append("UNSEEN"); continue
        if not sep and k == "lidas":
            crit.append("SEEN"); continue
        if not sep and k in ("com-estrela", "estrela"):
            crit.append("FLAGGED"); continue
        if sep and k in ("de", "para", "assunto", "texto", "cc"):
            if not v:
                raise RuntimeError(f"faltou o valor em {t!r}")
            crit += [{"de": "FROM", "para": "TO", "assunto": "SUBJECT", "texto": "TEXT", "cc": "CC"}[k], _q(v)]; continue
        if sep and k in ("antes", "desde"):
            try:
                d = datetime.date.fromisoformat(v)
            except ValueError:
                raise RuntimeError(f"data inválida em {t!r} (use AAAA-MM-DD)")
            crit += ["BEFORE" if k == "antes" else "SINCE", f"{d.day:02d}-{meses[d.month - 1]}-{d.year}"]; continue
        if sep and k in ("maior", "menor"):
            r = re.fullmatch(r"(\d+)([kKmM]?)", v)
            if not r:
                raise RuntimeError(f"tamanho inválido em {t!r} (ex.: maior:5m)")
            n = int(r.group(1)) * {"": 1, "k": 1024, "m": 1048576}[r.group(2).lower()]
            crit += ["LARGER" if k == "maior" else "SMALLER", str(n)]; continue
        if sep and k == "gmail":
            if "X-GM-EXT-1" not in caps:
                raise RuntimeError("gmail: só vale em conta Gmail")
            crit += ["X-GM-RAW", _q(v)]; continue
        crit += ["TEXT", _q(t)]
    return crit or ["ALL"]


def _lote_abrir(m, pasta, rw):
    todas = listar_pastas(m)
    alvo = [p for p in todas if p[2] == pasta or p[1] == pasta]
    if not alvo:
        raise RuntimeError(f"a pasta {pasta!r} não existe nesta conta")
    st, d = m.select(_q(alvo[0][1]), readonly=not rw)
    if st != "OK":
        raise RuntimeError(f"não consegui abrir {pasta}")
    uv = ""
    try:
        _, v = m.response("UIDVALIDITY")
        uv = (v[0].decode() if isinstance(v[0], bytes) else str(v[0])) if v and v[0] else ""
    except Exception:
        pass
    return todas, alvo[0], uv


def _lote_utf8(m, crit):
    """Busca com acento pede UTF8=ACCEPT. O ENABLE só vale antes do SELECT (no estado AUTH), e o imaplib o
    confere contra as capacidades do cumprimento: o Gmail só anuncia ENABLE depois do login."""
    if any(ord(ch) > 127 for ch in " ".join(crit)):
        try:
            m.capabilities = tuple(set(getattr(m, "capabilities", ()) or ()) | _capacidades(m))
            m.enable("UTF8=ACCEPT"); m._encoding = "utf-8"
        except Exception:
            raise RuntimeError("este servidor não aceita busca com acento; tente sem os acentos")


def _lote_buscar(m, crit):
    st, d = m.uid("SEARCH", *crit)
    if st != "OK":
        raise RuntimeError("o servidor recusou a busca")
    return [u.decode() if isinstance(u, bytes) else str(u) for u in (d[0] or b"").split()]


def lote_contar(c, pasta, busca, amostra=10, salvar=None):
    """Quantas mensagens de PASTA casam com BUSCA, uma amostra das mais novas e, com salvar, os UIDs
    exatos (o lote_agir só mexe nestes: nada que chegou depois da contagem entra)."""
    import email, email.policy, email.utils
    m = imap_conectar(c)
    try:
        caps = _capacidades(m)
        crit = lote_criterio(busca, caps)
        _lote_utf8(m, crit)
        _, alvo, uv = _lote_abrir(m, pasta, False)
        uids = _lote_buscar(m, crit)
        print(f"pasta={alvo[2]}")
        print(f"total={len(uids)}")
        for u in reversed(uids[-amostra:] if amostra else []):
            st, d = m.uid("FETCH", u, "(BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])")
            bruto = b""
            for p in d or []:
                if isinstance(p, tuple) and len(p) > 1:
                    bruto = p[1]; break
            h = email.message_from_bytes(bruto or b"", policy=email.policy.default)
            nome, end = email.utils.parseaddr(str(h.get("From", "")))
            try:
                data = email.utils.parsedate_to_datetime(str(h.get("Date", ""))).strftime("%Y-%m-%d")
            except Exception:
                data = "?"
            assunto = " ".join(str(h.get("Subject", "") or "").split()) or "(sem assunto)"
            print(f"amostra\t{data}\t{nome or end or '?'}\t{assunto}")
        if salvar:
            with open(salvar, "w", encoding="utf-8") as f:
                json.dump({"pasta": alvo[2], "uidvalidity": uv, "busca": busca, "uids": uids}, f)
        return 0
    finally:
        try:
            m.logout()
        except Exception:
            pass


def lote_agir(c, arquivo, acao, destino=None, de_vez=False):
    """Aplica ACAO (apagar | mover | arquivar | lidas | nao-lidas) aos UIDs contados por lote_contar, em blocos.
    apagar: para a lixeira (\\Trash); na lixeira/spam, ou com de_vez fora do Gmail, apaga de vez.
    arquivar: no Gmail tira da pasta (segue em Todos os e-mails); nos outros, move para \\Archive."""
    with open(arquivo, encoding="utf-8") as f:
        sel = json.load(f)
    uids = [str(u) for u in sel.get("uids", [])]
    m = imap_conectar(c)
    try:
        caps = _capacidades(m)
        todas, alvo, uv = _lote_abrir(m, sel["pasta"], True)
        if sel.get("uidvalidity") and uv and uv != sel["uidvalidity"]:
            raise RuntimeError("a pasta mudou no servidor desde a contagem (UIDVALIDITY); conte de novo")
        gmail = "X-GM-EXT-1" in caps
        marca = lambda m_: next((p for p in todas if m_ in p[0]), None)
        lixo, spam, tudo, arq = marca("\\Trash"), marca("\\Junk"), marca("\\All"), marca("\\Archive")
        origem = alvo[1]
        def mover(s, dest):
            if "MOVE" in caps:
                st, _ = m.uid("MOVE", s, _q(dest[1]))
                if st != "OK":
                    raise RuntimeError(f"o servidor recusou mover para {dest[2]}")
            else:
                st, _ = m.uid("COPY", s, _q(dest[1]))
                if st != "OK":
                    raise RuntimeError(f"o servidor recusou copiar para {dest[2]}")
                tirar(s)
        def tirar(s):
            st, _ = m.uid("STORE", s, "+FLAGS.SILENT", "(\\Deleted)")
            if st != "OK":
                raise RuntimeError("o servidor recusou marcar para apagar")
            st, _ = (m.uid("EXPUNGE", s) if "UIDPLUS" in caps else m.expunge())
            if st != "OK":
                raise RuntimeError("o servidor recusou apagar")
        if acao == "apagar":
            na_lixeira = any(p and p[1] == origem for p in (lixo, spam))
            if na_lixeira:
                op = tirar
            elif de_vez:
                if gmail:
                    raise RuntimeError("no Gmail, apagar de vez é na Lixeira: apague para a lixeira e depois esvazie (🧹)")
                op = tirar
            elif lixo:
                op = lambda s: mover(s, lixo)
            else:
                raise RuntimeError("esta conta não tem lixeira (pasta \\Trash); para apagar de vez, use --de-vez")
        elif acao == "mover":
            dest = next((p for p in todas if destino in (p[1], p[2])), None)
            if not dest:
                raise RuntimeError(f"a pasta de destino {destino!r} não existe nesta conta")
            if dest[1] == origem:
                raise RuntimeError("o destino é a própria pasta")
            op = lambda s: mover(s, dest)
        elif acao == "arquivar":
            if gmail:
                if tudo and tudo[1] == origem:
                    raise RuntimeError("as mensagens já estão em Todos os e-mails")
                op = tirar
            elif arq and arq[1] != origem:
                op = lambda s: mover(s, arq)
            else:
                raise RuntimeError("esta conta não tem pasta de arquivo (\\Archive); use mover")
        elif acao in ("lidas", "nao-lidas"):
            sinal = "+" if acao == "lidas" else "-"
            def op(s):
                st, _ = m.uid("STORE", s, sinal + "FLAGS.SILENT", "(\\Seen)")
                if st != "OK":
                    raise RuntimeError("o servidor recusou marcar")
        else:
            raise RuntimeError(f"ação desconhecida: {acao}")
        feito = 0
        for i in range(0, len(uids), LOTE_BLOCO):
            bloco = uids[i:i + LOTE_BLOCO]
            op(",".join(bloco))
            feito += len(bloco)
            print(f"progresso={feito}/{len(uids)}", file=sys.stderr, flush=True)
        print(f"feito={feito}")
        return 0
    finally:
        try:
            m.logout()
        except Exception:
            pass


def lote_listar(c):
    """Nome legível de cada pasta que dá para abrir (para escolher origem e destino)."""
    m = imap_conectar(c)
    try:
        for f, _, nome in listar_pastas(m):
            if "\\Noselect" in f or "\\NoSelect" in f or "\\NonExistent" in f:
                continue
            print(nome)
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


def graph_token(c, recurso="https://graph.microsoft.com/.default"):
    if c.get("auth") != "oauth" or c.get("graph") != "1":
        raise RuntimeError("a conta não está configurada para Microsoft Graph")
    rt = ler_arquivo(arq_segredo(c))
    if not rt:
        raise RuntimeError("conta ainda não autorizada (tt --email-autorizar)")
    d = {**base_oauth(c), "grant_type": "refresh_token", "refresh_token": rt, "scope": "offline_access " + recurso}
    t = post(c["oauth_token_endpoint"], d)
    if "access_token" not in t:
        raise RuntimeError(t.get("error_description") or t.get("error") or "falha ao renovar o token")
    return t["access_token"]


def graph_get(c, caminho):
    req = urllib.request.Request("https://graph.microsoft.com/v1.0" + caminho,
                                headers={"Authorization": "Bearer " + graph_token(c)})
    with urllib.request.urlopen(req, timeout=TIMEOUT, context=contexto_ssl()) as r:
        return json.load(r)


def testar_graph(c):
    try:
        r = graph_get(c, "/me/mailFolders/inbox/messages?$top=1&$select=subject")
        n = len(r.get("value", []))
        print(f"✓ Graph (ler): autenticado, consulta do INBOX ok ({n} mensagem(ns) na amostra)")
    except Exception as e:
        print(f"✗ Graph (ler): {erro_curto(e)}")
        return 1
    return 0


# --- Envio (tt --email-enviar e o sendmail do aerc nas contas Graph) ------------------------------
# Uma mensagem só (MIME, montada pelo email.message) e dois caminhos: SMTP (senha, comando ou XOAUTH2) ou, nas
# contas Microsoft em modo Graph, a API REST do Outlook. O Graph /v1.0/me/sendMail exigiria Mail.Send no recurso
# do Graph, que o app do Outlook Mobile (o padrão do tt) não tem; no recurso do Outlook ele tem.
OUTLOOK_API = os.environ.get("TT_EMAIL_OUTLOOK_API") or "https://outlook.office365.com/api/v2.0"
OUTLOOK_LIMITE_ANEXOS = 3 * 1024 * 1024  # o sendmail do Outlook REST aceita anexos de até ~3 MB por chamada


def conta_graph(c):
    return c.get("provedor") == "microsoft" and c.get("graph") == "1"


def outlook_json(m, destinatarios=None):
    """Mensagem MIME → corpo JSON do sendmail do Outlook REST (texto ou HTML, anexos, Reply-To)."""
    def enderecos(campo):
        return [{"EmailAddress": {"Address": a, **({"Name": n} if n else {})}}
                for n, a in email_lib.utils.getaddresses(m.get_all(campo, [])) if a]
    corpo_html = m.get_body(preferencelist=("html",))
    corpo_txt = m.get_body(preferencelist=("plain",))
    if corpo_html is not None:
        corpo = {"ContentType": "HTML", "Content": corpo_html.get_content()}
    else:
        corpo = {"ContentType": "Text", "Content": corpo_txt.get_content() if corpo_txt is not None else ""}
    anexos, total = [], 0
    for parte in m.iter_attachments():
        dados = parte.get_payload(decode=True) or b""
        total += len(dados)
        anexos.append({"@odata.type": "#Microsoft.OutlookServices.FileAttachment",
                       "Name": parte.get_filename() or "anexo", "ContentType": parte.get_content_type(),
                       "ContentBytes": base64.b64encode(dados).decode()})
    if total > OUTLOOK_LIMITE_ANEXOS:
        raise RuntimeError(f"anexos somam {total // 1024} KB; o envio pela API do Outlook aceita até "
                           f"{OUTLOOK_LIMITE_ANEXOS // 1024 // 1024} MB")
    msg = {"Subject": str(m.get("Subject", "")), "Body": corpo,
           "ToRecipients": destinatarios if destinatarios is not None else enderecos("To"),
           "CcRecipients": enderecos("Cc") if destinatarios is None else [],
           "BccRecipients": enderecos("Bcc") if destinatarios is None else []}
    if m.get_all("Reply-To"):
        msg["ReplyTo"] = enderecos("Reply-To")
    if anexos:
        msg["Attachments"] = anexos
    return {"Message": msg, "SaveToSentItems": True}


def graph_enviar(c, destinatarios, mensagem):
    """sendmail do aerc nas contas Graph: o aerc passa a mensagem crua no stdin e os destinatários (To, Cc e Bcc
    juntos) nos argumentos, que viram o envelope; os cabeçalhos ficam só como estão."""
    if isinstance(mensagem, (bytes, bytearray)):
        m = email_lib.message_from_bytes(mensagem, policy=email_lib.policy.default)
    else:
        m = email_lib.message_from_string(mensagem, policy=email_lib.policy.default)
    corpo = outlook_json(m)
    if destinatarios:  # o envelope manda: quem está nos argumentos e não aparece em To/Cc vai como Bcc
        vistos = {r["EmailAddress"]["Address"].lower() for k in ("ToRecipients", "CcRecipients")
                  for r in corpo["Message"][k]}
        extras = [d for d in destinatarios if d["EmailAddress"]["Address"].lower() not in vistos]
        corpo["Message"]["BccRecipients"] = extras
    return outlook_postar(c, corpo)


def outlook_postar(c, corpo):
    token = graph_token(c, "https://outlook.office.com/.default")
    req = urllib.request.Request(OUTLOOK_API + "/me/sendmail", data=json.dumps(corpo).encode("utf-8"),
                                 headers={"Authorization": "Bearer " + token,
                                          "Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60, context=contexto_ssl()) as r:
            return r.status
    except urllib.error.HTTPError as e:
        detalhe = e.read().decode("utf-8", "replace")
        try:
            detalhe = json.loads(detalhe).get("error", {}).get("message") or detalhe
        except Exception:
            pass
        raise RuntimeError(f"a API do Outlook recusou o envio (http {e.code}): {detalhe[:300]}")


def smtp_enviar(c, m, destinatarios):
    tipo, segredo = credencial(c)
    host, porta, seg = c["smtp_host"], int(c.get("smtp_porta") or 587), c.get("smtp_seg", "starttls")
    ctx = contexto_ssl()
    s = smtplib.SMTP_SSL(host, porta, context=ctx, timeout=60) if seg == "tls" else smtplib.SMTP(host, porta, timeout=60)
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
        recusados = s.send_message(m, to_addrs=destinatarios)
        if recusados:
            raise RuntimeError("o servidor recusou: " + ", ".join(recusados))
    finally:
        try:
            s.quit()
        except Exception:
            pass


def copia_enviados(c, m):
    """Gmail e Microsoft guardam sozinhos o que sai por SMTP; nos outros, grava a cópia na pasta de enviados."""
    if c.get("provedor") in ("gmail", "microsoft") or not c.get("pasta_enviados"):
        return ""
    im = imap_conectar(c)
    try:
        st, _ = im.append(imap_nome(c["pasta_enviados"]), "\\Seen", imaplib.Time2Internaldate(time.time()),
                          m.as_bytes(policy=email_lib.policy.SMTP))
        return "" if st == "OK" else f"não gravei a cópia em {c['pasta_enviados']}"
    finally:
        try:
            im.logout()
        except Exception:
            pass


def imap_nome(pasta):
    return '"' + pasta.replace("\\", "\\\\").replace('"', '\\"') + '"'


ENVIAR_AJUDA = """uso: tt --email-enviar [--conta CONTA] --para END[,END…] [--cc END…] [--cco END…] --assunto TEXTO
       [--corpo TEXTO | --corpo-arquivo ARQ | corpo no stdin] [--html TEXTO | --html-arquivo ARQ]
       [--anexo ARQ]… [--responder-para END] [--em-resposta-a MESSAGE-ID] [--sem-assinatura] [--ensaio]
apelidos em inglês: --account/--from, --to, --bcc, --subject, --body, --body-file, --html-file, --attach,
       --reply-to, --in-reply-to, --no-signature, --dry-run"""
ENVIAR_APELIDOS = {"--to": "--para", "--bcc": "--cco", "--subject": "--assunto", "--body": "--corpo",
                   "--body-file": "--corpo-arquivo", "--html-file": "--html-arquivo", "--attach": "--anexo",
                   "--attachment": "--anexo", "--reply-to": "--responder-para", "--in-reply-to": "--em-resposta-a",
                   "--no-signature": "--sem-assinatura", "--dry-run": "--ensaio"}
ENVIAR_LISTAS = ("--para", "--cc", "--cco", "--anexo")
ENVIAR_VALORES = ("--assunto", "--corpo", "--corpo-arquivo", "--html", "--html-arquivo", "--responder-para",
                  "--em-resposta-a")


def enviar_args(args):
    o = {k: [] for k in ENVIAR_LISTAS}
    o.update({"--sem-assinatura": False, "--ensaio": False})
    i = 0
    while i < len(args):
        a = ENVIAR_APELIDOS.get(args[i], args[i])
        if "=" in a and a.startswith("--") and a.split("=", 1)[0] in ENVIAR_APELIDOS.keys() | set(ENVIAR_LISTAS + ENVIAR_VALORES):
            k, v = a.split("=", 1); args = args[:i] + [ENVIAR_APELIDOS.get(k, k), v] + args[i + 1:]; continue
        if a in ("--sem-assinatura", "--ensaio"):
            o[a] = True; i += 1; continue
        if a in ENVIAR_LISTAS + ENVIAR_VALORES:
            if i + 1 >= len(args):
                raise ValueError(f"{args[i]} pede um valor")
            v = args[i + 1]
            if a in ENVIAR_LISTAS:
                o[a] += [x.strip() for x in v.split(",") if x.strip()] if a != "--anexo" else [v]
            else:
                o[a] = v
            i += 2; continue
        raise ValueError(f"opção desconhecida: {args[i]}")
    return o


def montar_mensagem(c, o, corpo):
    from email.message import EmailMessage
    from email.utils import formataddr, formatdate, make_msgid
    import mimetypes
    m = EmailMessage(policy=email_lib.policy.SMTP)
    endereco = c.get("endereco", "")
    m["From"] = formataddr((c.get("nome_exibicao") or "", endereco))
    for campo, chave in (("To", "--para"), ("Cc", "--cc")):
        if o[chave]:
            m[campo] = ", ".join(o[chave])
    m["Subject"] = o["--assunto"]
    m["Date"] = formatdate(localtime=True)
    m["Message-ID"] = make_msgid(domain=endereco.rpartition("@")[2] or None)
    if o.get("--responder-para"):
        m["Reply-To"] = o["--responder-para"]
    if o.get("--em-resposta-a"):
        mid = o["--em-resposta-a"].strip()
        mid = mid if mid.startswith("<") else f"<{mid}>"
        m["In-Reply-To"] = mid; m["References"] = mid
    assinatura = "" if o["--sem-assinatura"] else ler_arquivo(
        os.path.join(os.path.dirname(c["_conf"]), c["_slug"] + ".assinatura"))
    texto = corpo + (("\n\n-- \n" + assinatura) if assinatura else "")
    m.set_content(texto if texto.endswith("\n") else texto + "\n")
    html = o.get("--html")
    if o.get("--html-arquivo"):
        with open(o["--html-arquivo"], encoding="utf-8") as f:
            html = f.read()
    if html:
        m.add_alternative(html, subtype="html")
    for caminho in o["--anexo"]:
        with open(caminho, "rb") as f:
            dados = f.read()
        tipo = (mimetypes.guess_type(caminho)[0] or "application/octet-stream").split("/", 1)
        m.add_attachment(dados, maintype=tipo[0], subtype=tipo[1], filename=os.path.basename(caminho))
    return m


def enviar(caminho_conf, args):
    """tt --email-enviar: envia uma mensagem pela conta, sem abrir tela. rc 0 enviado, 1 falhou, 2 uso errado."""
    if args[:1] in (["-h"], ["--help"], ["--ajuda"]):
        print(ENVIAR_AJUDA); return 0
    try:
        o = enviar_args(args)
    except ValueError as e:
        print(f"✗ {e}\n{ENVIAR_AJUDA}", file=sys.stderr); return 2
    destinatarios = o["--para"] + o["--cc"] + o["--cco"]
    if not destinatarios:
        print("✗ falta destinatário (--para, --cc ou --cco)", file=sys.stderr); return 2
    if o.get("--assunto") is None:
        print("✗ falta --assunto (use --assunto \"\" para mandar sem assunto)", file=sys.stderr); return 2
    for chave in ("--corpo-arquivo", "--html-arquivo"):
        if o.get(chave) and not os.path.isfile(o[chave]):
            print(f"✗ {chave}: arquivo não encontrado: {o[chave]}", file=sys.stderr); return 2
    for a in o["--anexo"]:
        if not os.path.isfile(a):
            print(f"✗ anexo não encontrado: {a}", file=sys.stderr); return 2
    if o.get("--corpo") is not None:
        corpo = o["--corpo"]
    elif o.get("--corpo-arquivo"):
        with open(o["--corpo-arquivo"], encoding="utf-8") as f:
            corpo = f.read()
    elif not sys.stdin.isatty():
        corpo = sys.stdin.read()
    else:
        corpo = ""
    c = ler_conf(caminho_conf); c["_conf"] = os.path.abspath(caminho_conf)
    m = montar_mensagem(c, o, corpo)
    if o["--cco"]:
        m["Bcc"] = ", ".join(o["--cco"])  # só para o caminho do Outlook e para o ensaio; o SMTP o tira antes
    caminho = "Outlook (API REST)" if conta_graph(c) else f"SMTP {c.get('smtp_host', '?')}"
    if o["--ensaio"]:
        print(f"# ensaio: nada foi enviado · conta {c['_slug']} · envio por {caminho}")
        sem_anexos = email_lib.message_from_bytes(m.as_bytes(), policy=email_lib.policy.default)
        for campo in ("From", "To", "Cc", "Bcc", "Reply-To", "Subject", "In-Reply-To", "Message-ID"):
            if sem_anexos.get(campo):
                print(f"{campo}: {sem_anexos[campo]}")
        print()
        print(m.get_body(preferencelist=("plain",)).get_content().rstrip("\n"))
        if m.get_body(preferencelist=("html",)) is not None:
            print("\n# + versão HTML")
        for p in m.iter_attachments():
            print(f"# anexo: {p.get_filename()} ({len(p.get_payload(decode=True) or b'')} bytes, {p.get_content_type()})")
        return 0
    try:
        if conta_graph(c):
            outlook_postar(c, outlook_json(m))
            aviso = ""
        else:
            del m["Bcc"]
            smtp_enviar(c, m, destinatarios)
            try:
                aviso = copia_enviados(c, m)
            except Exception as e:
                aviso = f"enviado, mas não gravei a cópia nos enviados: {erro_curto(e)}"
    except Exception as e:
        print(f"✗ não enviado: {erro_curto(e)}", file=sys.stderr); return 1
    print(f"✓ enviado de {c.get('endereco')} para {', '.join(destinatarios)} por {caminho} · Message-ID: {m['Message-ID']}")
    if aviso:
        print(f"⚠ {aviso}", file=sys.stderr)
    return 0


GRAPH_PASTAS_EXTRA = [
    ("sentitems", "Enviados"), ("deleteditems", "Lixeira"), ("drafts", "Rascunhos"),
    ("junkemail", "Spam"), ("archive", "Arquivo"),
]


def graph_sync(c, base, limite, completo=False):
    """Espelha o INBOX como maildir; no modo completo, também Enviados/Lixeira/Rascunhos/Spam/
    Arquivo. Cada pasta é reconstruída do servidor a cada sync (o id do Graph é a verdade: evita
    duplicar quando o cliente renomeia arquivos ao marcar lido/arquivar)."""
    pastas = [("inbox", "INBOX")] + (GRAPH_PASTAS_EXTRA if completo else [])
    total = 0
    for wk, nome_pasta in pastas:
        try:
            r = graph_get(c, f"/me/mailFolders/{wk}/messages?$top={int(limite)}&$select=id,subject,from,receivedDateTime,isRead,bodyPreview,internetMessageHeaders")
        except urllib.error.HTTPError as e:
            if e.code == 404:   # pasta inexistente nesta conta: ignora
                continue
            raise
        destino = os.path.join(base, nome_pasta)
        # Reconstrói a pasta (só é lida pelo cliente com cur/new/tmp; limpar evita duplicatas).
        for sub in ("cur", "new", "tmp"):
            d = os.path.join(destino, sub)
            if os.path.isdir(d):
                for f in os.listdir(d):
                    try:
                        os.remove(os.path.join(d, f))
                    except OSError:
                        pass
            os.makedirs(d, exist_ok=True)
        for m in r.get("value", []):
            ident = m.get("id", "")
            if not ident:
                continue
            nome = ident.replace("/", "_").replace(":", "_")
            lido = bool(m.get("isRead"))
            de = m.get("from", {}).get("emailAddress", {})
            # The local demand filter relies on the receiving provider's verdict. Graph omits these
            # headers unless explicitly selected; preserve only Authentication-Results, in provider
            # order, so the parser can continue trusting the first (newest) result.
            auth_headers = []
            for h in m.get("internetMessageHeaders", []) or []:
                if str(h.get("name", "")).lower() != "authentication-results":
                    continue
                value = " ".join(str(h.get("value", "")).replace("\r", " ").replace("\n", " ").split())
                if value:
                    auth_headers.append(f"Authentication-Results: {value}\n")
            texto = ("".join(auth_headers)
                     + f"From: {de.get('name', '')} <{de.get('address', '')}>\n"
                     f"Subject: {m.get('subject', '')}\n"
                     f"Date: {m.get('receivedDateTime', '')}\n"
                     f"X-Graph-Id: {ident}\n\n{m.get('bodyPreview', '')}\n")
            tmp = os.path.join(destino, "tmp", nome)
            dst = os.path.join(destino, "cur", nome + ":2,S") if lido else os.path.join(destino, "new", nome)
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(texto)
            os.replace(tmp, dst)
            total += 1
    print(f"mensagens={total}")
    return 0


# --- Classificação automática (server-side, só com token de escrita Mail.ReadWrite) ---------------
# Mantém o INBOX organizado na taxonomia do usuário movendo cada mensagem para a pasta da categoria.
# Determinístico (regras por remetente/assunto); o que não casa fica no INBOX. Idempotente: já movido
# não está mais no INBOX. Precisa de Mail.ReadWrite (criar pasta, mover); sem ele, sai sem erro fatal.
TAXONOMIA = ["@ Ação", "@ Aguardando Resposta", "Automações", "Códigos", "Segurança", "Notificações", "Newsletters"]


def classificar_email(frm, subj):
    """(remetente, assunto) -> nome da categoria, ou None para deixar no INBOX."""
    import re
    a = (frm or "").lower()
    d = a.split("@")[-1] if "@" in a else a
    s = (subj or "").lower()
    if d in ("itau.com.br", "itau-unibanco.com.br", "minhaclaro.com.br"):
        if re.search(r'dispositivo autorizado', s):
            return "Segurança"
        if re.search(r'fatura|cart[aã]o|\bconta\b|boleto|cadastro', s) and not re.search(r'pix gr[aá]tis|isen|tarifa|promo', s):
            return None
        if re.search(r'pix gr[aá]tis|isen|tarifa|promo|oferta|conhe[cç]a|cuidado|desconto|\boff\b', s):
            return "Newsletters"
    if re.search(r'confirme seu (e-?mail|endere)|confirm your email|sign in to|entrar na sua conta|acesse sua conta', s):
        return "Códigos"
    if re.search(r'c[oó]digo|verif|verify|\botp\b|one-time|senha.*(reset|redefin)|password.*reset|security code', s):
        return "Códigos"
    if d in ("accounts.google.com", "accountprotection.microsoft.com", "acesso.gov.br", "id.apple.com") or \
       re.search(r'nova entrada|novo login|new sign|senha.*alterad|password was|aplicativo.*conectad|security alert|dispositivo autorizado', s):
        return "Segurança"
    if re.search(r'a[cç][aã]o necess|action required|atribuiu|mencionou|assigned|mentioned|\balerta\b|anomalia|inconsist|\berro\b', s):
        return "@ Ação"
    if d in ("make.com", "us2.make.com") or re.search(r'triagem|resumo|relat[oó]rio|digest|reserva confirmada|pipeline|failed|fixed|voluntariado', s):
        return "Automações"
    if d in ("jetbrains.com", "discord.com", "onedrive.com", "paypal.com", "paypal.com.br", "communications.paypal.com",
             "fly.io", "email.fly.io", "calendly.com", "twitch.tv", "alerts.udemy.com", "e.udemymail.com", "amazonaws.com",
             "reservio.com", "ebanx.com", "shop.app") or \
       ("microsoft" in d and any(x in d for x in ("store", "notification", "communication", "info"))) or \
       "familysafety" in a or \
       any(x in d for x in ("atlassian", "sharepoint", "wellhub", "gympass", "tldv", "sunsama", "zenklub", "feedz",
                            "teams", "islandcloud", "shopifyemail")) or \
       re.search(r'order #|pedido\b.*confirmad|agendamento|pagamento autom|status do seu pagamento|download your purchased', s):
        return "Notificações"
    if d in ("lumine.tv", "email.granado.com.br", "merchtraffic.com", "springframework.guru", "myjotform.com",
             "livrariatravessa.com.br", "lofigirl.com") or \
       any(x in d for x in ("globo", "evangelizar", "estadao", "udemy", "hbomax", "mails.microsoft", "engage.microsoft",
                            "engagemail", "customermail.microsoft", "microsoftrewards")) or \
       re.search(r'desconto|oferta|\boff\b|novidade|boletim|newsletter|unsubscribe|course sale|sale ends|announcing|acontece em|appreciation|thanks for subscrib|follow us', s):
        return "Newsletters"
    return None


def graph_classificar(c, limite=500):
    tok = graph_token(c)

    def req(metodo, caminho, corpo=None):
        data = json.dumps(corpo).encode() if corpo is not None else None
        r = urllib.request.Request("https://graph.microsoft.com/v1.0" + caminho, data=data,
                                   headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"},
                                   method=metodo)
        with urllib.request.urlopen(r, timeout=TIMEOUT, context=contexto_ssl()) as resp:
            return json.load(resp)
    fid = {f["displayName"]: f["id"] for f in req("GET", "/me/mailFolders?$top=100&$select=displayName,id").get("value", [])}
    for nome in TAXONOMIA:
        if nome not in fid:
            try:
                fid[nome] = req("POST", "/me/mailFolders", {"displayName": nome})["id"]
            except urllib.error.HTTPError as e:
                print(f"✗ classificação exige Mail.ReadWrite (criar pasta deu {e.code})", file=sys.stderr)
                return 1
    msgs = req("GET", f"/me/mailFolders/inbox/messages?$top={int(limite)}&$select=id,from,subject").get("value", [])
    plano = []
    for msg in msgs:
        frm = (msg.get("from") or {}).get("emailAddress", {}).get("address", "")
        cat = classificar_email(frm, msg.get("subject", ""))
        if cat and cat in fid:
            plano.append((msg["id"], fid[cat]))
    movidos = 0
    for i in range(0, len(plano), 20):
        lote = plano[i:i + 20]
        reqs = [{"id": str(j), "method": "POST", "url": f"/me/messages/{mid}/move",
                 "body": {"destinationId": dst}, "headers": {"Content-Type": "application/json"}}
                for j, (mid, dst) in enumerate(lote)]
        try:
            resp = req("POST", "/$batch", {"requests": reqs})
            movidos += sum(1 for rr in resp.get("responses", []) if 200 <= rr.get("status", 0) < 300)
        except urllib.error.HTTPError as e:
            print(f"✗ mover falhou ({e.code})", file=sys.stderr)
            break
    print(f"classificadas={movidos}")
    return 0


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
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=contexto_ssl()) as r:
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


# --- Destinatários: quem já escreveu e para quem já se escreveu ---------------------------------
def _cabecalhos(caminho, limite=65536):
    """Os bytes do cabeçalho de uma mensagem (até a linha em branco), sem ler o corpo."""
    dados = b""
    with open(caminho, "rb") as f:
        while len(dados) < limite:
            bloco = f.read(8192)
            if not bloco:
                break
            dados += bloco
            cortes = [i for i in (dados.find(b"\n\n"), dados.find(b"\r\n\r\n")) if i >= 0]
            if cortes:
                return dados[:min(cortes)]
    return dados


# Endereços automáticos (ninguém escreve para eles).
AUTOMATICOS = ("noreply", "no-reply", "no_reply", "naoresponda", "nao-responda", "nao_responda",
               "donotreply", "do-not-reply", "mailer-daemon", "postmaster", "bounce")


def contatos_indexar(args):
    import email, email.policy, email.utils
    from collections import Counter, defaultdict
    sem, raizes = set(), []
    for a in args:
        if a.startswith("--sem="):
            sem.update(x.strip().lower() for x in a[6:].split(",") if x.strip())
        else:
            raizes.append(a)
    vezes, nomes = Counter(), defaultdict(Counter)
    for raiz in raizes:
        for pasta, _, arquivos in os.walk(raiz):
            if os.path.basename(pasta) not in ("cur", "new"):
                continue
            for arq in arquivos:
                try:
                    msg = email.message_from_bytes(_cabecalhos(os.path.join(pasta, arq)) + b"\n\n",
                                                   policy=email.policy.default)
                    campos = []
                    for h in ("From", "To", "Cc", "Reply-To"):
                        campos.extend(str(v) for v in (msg.get_all(h) or []))
                    pares = email.utils.getaddresses(campos)
                except Exception:
                    continue
                for nome, end in pares:
                    end = end.strip().lower()
                    if "@" not in end or end in sem:
                        continue
                    local = end.split("@", 1)[0]
                    if any(local.startswith(p) or local.endswith(p) for p in AUTOMATICOS):
                        continue
                    vezes[end] += 1
                    nome = " ".join(nome.split())
                    if nome and nome.lower() != end:
                        nomes[end][nome] += 1
    for end, n in sorted(vezes.items(), key=lambda kv: (-kv[1], kv[0])):
        nome = nomes[end].most_common(1)[0][0] if nomes[end] else ""
        print(f"{end}\t{nome}\t{n}")
    return 0


# --- Demandas por e-mail: uma mensagem vira (talvez) uma tarefa pendente -----------------------
def _dominio(end):
    return end.rsplit("@", 1)[-1].strip().lower().strip(">")


def _alinhado(a, b):
    """Domínios alinhados (relaxado): iguais, ou um é subdomínio do outro."""
    a, b = (a or "").lower().strip("."), (b or "").lower().strip(".")
    return bool(a) and bool(b) and (a == b or a.endswith("." + b) or b.endswith("." + a))


def autenticacao(msg, de):
    """'pass' | 'fail' | 'none': o veredito do PROVEDOR que recebeu (cabeçalho Authentication-Results
    MAIS NOVO, o do topo, que o servidor final põe por cima do que o remetente tenha forjado) para o
    domínio do From. pass = dmarc=pass, ou dkim=pass / spf=pass com domínio alinhado ao do From."""
    import re
    ars = msg.get_all("Authentication-Results") or []
    if not ars:
        return "none"
    ar = " ".join(str(ars[0]).split()).lower()
    dom = _dominio(de)
    if re.search(r"\bdmarc=pass\b", ar):
        return "pass"
    for m in re.finditer(r"\bdkim=pass\b([^;]*)", ar):
        d = re.search(r"header\.(?:d|i)=@?([^\s;]+)", m.group(1))
        if d and _alinhado(d.group(1).split("@")[-1], dom):
            return "pass"
    for m in re.finditer(r"\bspf=pass\b([^;]*)", ar):
        d = re.search(r"smtp\.(?:mailfrom|helo)=([^\s;]+)", m.group(1))
        if d and _alinhado(d.group(1).split("@")[-1], dom):
            return "pass"
    return "fail"


def demanda(caminho):
    """Uma linha TSV: de, message-id, epoch, auth, assunto, descrição, subtarefas — os três últimos em
    base64 (podem ter TAB e quebras de linha). Nada do conteúdo é executado; subtarefa = linha '- texto'."""
    import base64, email, email.policy, email.utils, hashlib, re, time
    with open(caminho, "rb") as f:
        bruto = f.read(2_000_000)
    msg = email.message_from_bytes(bruto, policy=email.policy.default)
    _, de = email.utils.parseaddr(str(msg.get("From", "")))
    de = de.strip().lower()
    mid = str(msg.get("Message-ID", "") or "").strip().strip("<>")
    if not mid:
        mid = "sem-id-" + hashlib.sha256(bruto).hexdigest()[:24]
    agora = int(time.time())
    try:
        epoch = int(email.utils.parsedate_to_datetime(str(msg.get("Date"))).timestamp())
    except Exception:
        try:
            epoch = int(os.path.getmtime(caminho))
        except Exception:
            epoch = agora
    epoch = max(1, min(epoch, agora))
    assunto = " ".join(str(msg.get("Subject", "") or "").split())
    corpo = ""
    try:
        parte = msg.get_body(preferencelist=("plain",))
        if parte is None:
            parte = msg.get_body(preferencelist=("html",))
            corpo = html_para_texto(parte.get_content()) if parte is not None else ""
        else:
            corpo = parte.get_content()
    except Exception:
        corpo = ""
    subs, desc = [], []
    trailer = ""
    linhas = corpo.replace("\r", "").split("\n")
    for i, ln in enumerate(linhas):
        if ln.rstrip() == "--":                      # assinatura ("-- " com espaço também)
            # o tt escreve aqui, depois da assinatura, a linha "tt:2 estado=… removidas=…" (protocolo v2): um tt
            # antigo ignora tudo depois da assinatura, então o e-mail continua legível e válido para ele
            for t in linhas[i + 1:i + 6]:
                mt = re.match(r"^tt:2(?:\s+(.*))?$", t.strip())
                if mt:
                    trailer = mt.group(1) or ""
                    break
            break
        if ln.startswith(">"):                       # citação de resposta
            continue
        m = re.match(r"^\s*[-*•]\s+(?:\[([0-9a-fA-F]{6,16})\]\s+)?(?:\[([xX ])\]\s+)?(\S.*)$", ln)
        if m and len(subs) < 30:
            # cod<TAB>estado<TAB>texto: "- [código] [x] texto" (código e [x] opcionais; "-" quando faltam;
            # "a" = "[ ]" explícito, "f" = "[x]")
            marca = m.group(2)
            est = "-" if marca is None else ("f" if marca.lower() == "x" else "a")
            subs.append("\t".join([(m.group(1) or "-").lower(), est, " ".join(m.group(3).split())]))
        else:
            desc.append(ln.rstrip())
    descricao = "\n".join(desc).strip()   # sem corte: a tarefa chega inteira (um handoff passa de 10 mil caracteres)
    # "-" no lugar de vazio: o read do Bash com IFS=TAB juntaria os campos vazios vizinhos.
    b = lambda t: base64.b64encode(t.encode("utf-8")).decode("ascii") or "-"
    # só valores conhecidos passam do rodapé (é dado não confiável): estado aberta|feita e até 30 códigos hex
    kv = {}
    for tok in trailer.split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            kv[k] = v
    est = kv.get("estado", "")
    rem = [c for c in kv.get("removidas", "").lower().split(",") if re.fullmatch(r"[0-9a-f]{6,16}", c)][:30]
    ext = ("estado=" + est + "\n" if est in ("aberta", "feita") else "") + ("removidas=" + ",".join(rem) + "\n" if rem else "")
    ext = ("v2=1\n" + ext) if trailer != "" or ext else ""
    print("\t".join([de or "-", mid, str(epoch), autenticacao(msg, de), b(assunto), b(descricao), b("\n".join(subs)), b(ext) if ext else "-"]))
    return 0


def cabecalhos(arquivos):
    """Uma linha "chave<TAB>remetente<TAB>assunto" por arquivo de maildir, na ordem dada, para o aviso de
    e-mail novo. A chave é a identidade da MENSAGEM, igual em todas as máquinas que espelham a conta (o nome
    do arquivo não é: cada mbsync cria o seu): 12 hex do sha1 do Message-ID ou, sem ele, de remetente, data
    e assunto. Só lê os cabeçalhos."""
    import email.parser, email.policy, email.utils, hashlib
    p = email.parser.BytesHeaderParser(policy=email.policy.default)
    for arq in arquivos:
        try:
            with open(arq, "rb") as f:
                msg = p.parse(f)
            de = str(msg.get("From", "") or "")
            assunto = " ".join(str(msg.get("Subject", "") or "").split())
            mid = str(msg.get("Message-ID", "") or "").strip().strip("<>")
            base = mid or "\0".join([de, str(msg.get("Date", "") or ""), assunto])
        except Exception:
            de, assunto, base = "", "", arq
        nome, end = email.utils.parseaddr(de)
        nome = " ".join(nome.split())
        chave = hashlib.sha1(base.encode("utf-8", "replace")).hexdigest()[:12]
        print(f"{chave}\t{nome or end or '?'}\t{assunto or '(sem assunto)'}")
    return 0


def main(a):
    if a[:1] == ["contatos-indexar"] and len(a) >= 2:
        return contatos_indexar(a[1:])
    if a[:1] == ["html"]:
        dados = sys.stdin.buffer.read()
        sys.stdout.write(html_para_texto(dados.decode("utf-8", "replace"))); return 0
    if a[:1] == ["linkify"]:
        sys.stdout.write(linkify(sys.stdin.buffer.read().decode("utf-8", "replace"))); return 0
    if a[:1] == ["imagens"] and len(a) == 2:
        return lista_imagens(sys.stdin.buffer.read(), a[1])
    if a[:1] == ["baixar-imagem"] and len(a) == 3:
        return baixar_imagem(a[1], a[2])
    if a[:1] == ["demanda"] and len(a) == 2:
        return demanda(a[1])
    if a[:1] == ["cabecalhos"]:
        return cabecalhos(a[1:])
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
    if cmd == "graph-testar":
        return testar_graph(c)
    if cmd == "graph-sync":
        try:
            return graph_sync(c, a[2], int(a[3]) if len(a) > 3 else 500, len(a) > 4 and a[4] == "completo")
        except Exception as e:
            print(f"✗ {erro_curto(e)}", file=sys.stderr); return 1
    if cmd == "graph-classificar":
        try:
            return graph_classificar(c, int(a[2]) if len(a) > 2 else 500)
        except Exception as e:
            print(f"✗ {erro_curto(e)}", file=sys.stderr); return 1
    if cmd == "enviar":
        return enviar(arg, a[2:])
    if cmd == "graph-sendmail":
        try:
            graph_enviar(c, [{"EmailAddress": {"Address": x}} for x in a[2:]],
                         sys.stdin.buffer.read())
            return 0
        except Exception as e:
            print(f"✗ {erro_curto(e)}", file=sys.stderr); return 1
    if cmd == "pastas":
        try:
            return pastas(c)
        except Exception as e:
            print(f"✗ {erro_curto(e)}", file=sys.stderr); return 1
    if cmd == "lixeira" and a[2:] in ([], ["--esvaziar"]):
        try:
            return lixeira(c, a[2:] == ["--esvaziar"])
        except Exception as e:
            print(f"✗ {erro_curto(e)}", file=sys.stderr); return 1
    if cmd == "lote-pastas":
        try:
            return lote_listar(c)
        except Exception as e:
            print(f"✗ {erro_curto(e)}", file=sys.stderr); return 1
    if cmd in ("lote-contar", "lote-agir"):
        resto, opc = [], {}
        i = 2
        while i < len(a):
            if a[i] in ("--amostra", "--salvar", "--destino"):
                if i + 1 >= len(a):
                    print(__doc__); return 2
                opc[a[i]] = a[i + 1]; i += 2
            elif a[i] == "--de-vez":
                opc["--de-vez"] = True; i += 1
            else:
                resto.append(a[i]); i += 1
        try:
            if cmd == "lote-contar" and len(resto) == 2:
                return lote_contar(c, resto[0], resto[1], int(opc.get("--amostra", 10)), opc.get("--salvar"))
            if cmd == "lote-agir" and len(resto) == 2:
                return lote_agir(c, resto[0], resto[1], opc.get("--destino"), bool(opc.get("--de-vez")))
        except Exception as e:
            print(f"✗ {erro_curto(e)}", file=sys.stderr); return 1
    print(__doc__); return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
