#!/usr/bin/env python3
# conversa-mesh.py — a conversa do tt-mesh de um dia, como chat (tt --conversa-mesh [DIA|hoje|ontem]).
# Lê channel/ e channel/arquivo/ do enxame (TT_MESH, padrão ~/tt-mesh): cada mensagem é um arquivo
# AAAAMMDDTHHMMSSZ-maquina-rand.md (UTC). Mostra o dia em ordem, com o nome e o tom da persona de cada máquina
# (## Personas da carta), a máquina de quem lê à direita. Saída pensada para um painel estreito do tmux.
import datetime, glob, os, re, sys, unicodedata

def _mesh_configurado():
    """O tt-mesh desta pessoa: TT_MESH, ou o caminho guardado ao ativar o plugin (tt --conversa-mesh-ativar)."""
    if os.environ.get("TT_MESH"):
        return os.environ["TT_MESH"]
    try:
        with open(os.path.expanduser("~/.config/tt/conversa-mesh.on"), encoding="utf-8") as f:
            caminho = f.read().strip()
        if caminho:
            return os.path.expanduser(caminho)
    except OSError:
        pass
    return os.path.expanduser("~/tt-mesh")


MESH = _mesh_configurado()
ME = os.environ.get("TT_MAQUINA", "")
LARGURA = int(os.environ.get("TT_CONVERSA_LARGURA", "44"))


def personas():
    nomes = {}
    try:
        with open(os.path.join(MESH, "mission.md"), encoding="utf-8") as f:
            for linha in f:
                # "- **mac** · Pedro Estêvão — o MacBook…": o nome vai até o travessão (pode ter mais de uma palavra e acento).
                m = re.match(r"- \*\*([\w-]+)\*\* · (.+?)(?:\s+[—–-]\s+.*)?$", linha.rstrip())
                if m:
                    nomes[m.group(1)] = m.group(2).strip(" *")
    except OSError:
        pass
    return nomes


def dia_alvo(arg):
    hoje = datetime.date.today()
    if not arg or arg == "hoje":
        return hoje
    if arg == "ontem":
        return hoje - datetime.timedelta(days=1)
    return datetime.date.fromisoformat(arg)


def mensagens(dia):
    """(hora local, máquina, tópico, corpo) das mensagens cujo horário local cai nesse dia."""
    achadas = []
    for arq in glob.glob(os.path.join(MESH, "channel", "*.md")) + glob.glob(os.path.join(MESH, "channel", "arquivo", "*.md")):
        base = os.path.basename(arq)
        m = re.match(r"(\d{8}T\d{6}Z)-", base)
        if not m:
            continue  # 0000-seed e afins
        quando = datetime.datetime.strptime(m.group(1), "%Y%m%dT%H%M%SZ").replace(tzinfo=datetime.timezone.utc).astimezone()
        agora = datetime.datetime.now().astimezone()
        if quando > agora + datetime.timedelta(minutes=5):
            # O nome veio com um horário no futuro (estimado por quem escreveu): vale a hora em que o arquivo foi gravado.
            quando = datetime.datetime.fromtimestamp(os.path.getmtime(arq)).astimezone()
        if quando.date() != dia:
            continue
        with open(arq, encoding="utf-8", errors="replace") as f:
            texto = f.read()
        cab, _, corpo = texto.partition("\n---\n") if texto.startswith("---\n") else ("", "", texto)
        campos = {}
        for linha in cab.splitlines():
            if ":" in linha:
                k, v = linha.split(":", 1)
                campos[k.strip()] = v.strip()
        if not campos and texto.startswith("from:"):
            corpo = texto
        maquina = campos.get("from") or re.sub(r"^\w+?-", "", base.split("-", 1)[-1]).split("-")[0]
        achadas.append((quando, maquina, campos.get("topic", ""), (corpo or "").strip()))
    return sorted(achadas, key=lambda x: x[0])


# Cores no terminal (como o WhatsApp: balão cinza para os outros, verde para a própria máquina). Sem terminal
# (teste, arquivo, pipe) sai texto puro.
COR = sys.stdout.isatty() and os.environ.get("TT_CORES", "1") != "0"
def _c(codigo, texto):
    return f"\033[{codigo}m{texto}\033[0m" if COR else texto


_ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def largura_visual(texto):
    """Número de colunas de terminal ocupadas pelo texto (sem sequências ANSI)."""
    texto = _ANSI.sub("", texto)
    total, grupo, juntando, regionais = 0, 0, False, 0
    for c in texto:
        cp = ord(c)
        if (unicodedata.category(c).startswith("M") or c == "\u200d" or
                0x1F3FB <= cp <= 0x1F3FF or 0xE0020 <= cp <= 0xE007F):
            juntando = c == "\u200d"
            continue
        emoji = 0x1F000 <= cp <= 0x1FAFF or 0x1F1E6 <= cp <= 0x1F1FF or 0x2600 <= cp <= 0x27BF
        colunas = 2 if emoji or unicodedata.east_asian_width(c) in ("W", "F") else 1
        if juntando or (0x1F1E6 <= cp <= 0x1F1FF and regionais == 1):
            grupo = max(grupo, colunas)
            juntando = False
            regionais = 0
        else:
            total += grupo
            grupo = colunas
            regionais = 1 if 0x1F1E6 <= cp <= 0x1F1FF else 0
    return total + grupo


def cortar_visual(texto, largura):
    """Texto puro cortado em `largura` colunas (com … no fim quando perde algo)."""
    if largura_visual(texto) <= largura:
        return texto
    saida = ""
    for c in texto:
        if largura_visual(saida + c) > largura - 1:
            break
        saida += c
    return saida + "…"


def preencher_visual(texto, largura):
    return texto + " " * max(0, largura - largura_visual(texto))


def quebrar_visual(texto, largura):
    """Quebra por palavras sem exceder colunas, mesmo com emoji ou caracteres largos."""
    if largura < 1:
        return [texto] if texto else [""]
    palavras = texto.split()
    if not palavras:
        return [""]
    linhas, atual = [], ""
    for palavra in palavras:
        partes, parte = [], ""
        for caractere in palavra:
            if parte and largura_visual(parte + caractere) > largura:
                partes.append(parte)
                parte = ""
            parte += caractere
        if parte:
            partes.append(parte)
        for parte in partes:
            candidata = (atual + " " + parte).strip()
            if atual and largura_visual(candidata) > largura:
                linhas.append(atual)
                atual = parte
            else:
                atual = candidata
    if atual:
        linhas.append(atual)
    return linhas or [""]


CORES_MAQUINA = ["38;5;208", "38;5;78", "38;5;141", "38;5;81", "38;5;215", "38;5;250"]
DIAS = ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"]


def _balao(linhas, eu, largura):
    """Balão de texto dentro de um painel de `largura` colunas: à direita se for a própria máquina, à esquerda se não."""
    fundo = "48;5;22" if eu else "48;5;236"
    dentro = max((largura_visual(l) for l in linhas), default=0)  # o balão se ajusta ao texto, como no WhatsApp
    dentro = min(dentro, largura - 6)
    saida = []
    for l in linhas:
        texto = " " + preencher_visual(l, dentro) + " "
        bloco = _c(f"{fundo};38;5;255", texto)
        if eu:
            saida.append(" " * max(largura - largura_visual(texto), 0) + bloco)
        else:
            saida.append("  " + bloco)
    return saida


def render(dia, largura=None, cabecalho=True):
    largura = largura or LARGURA
    nomes = personas()
    cores = {}
    out = []
    if cabecalho:
        out.append(_c("1", f"  {('hoje' if dia == datetime.date.today() else '')}".rstrip() or f"  {dia.strftime('%d/%m/%Y')}"))
        out.append(_c("2", "  " + dia.strftime("%d/%m/%Y") + " (" + DIAS[dia.weekday()] + ")"))
        out.append(_c("2", "─" * largura))
    msgs = mensagens(dia)
    if not msgs:
        out.append(_c("2", "  (nenhuma mensagem neste dia)"))
        return "\n".join(out) + "\n"
    topico_ant = None
    for quando, maquina, topico, corpo in msgs:
        if topico != topico_ant and topico:
            titulo = "  ┄ " + topico + " ┄"
            if largura_visual(titulo) > largura:
                titulo = "  ┄ " + quebrar_visual(topico, max(1, largura - 6))[0] + " ┄"
            out.append(_c("2", " " * max(0, (largura - largura_visual(titulo)) // 2) + titulo))
            topico_ant = topico
        if maquina not in cores:
            cores[maquina] = CORES_MAQUINA[len(cores) % len(CORES_MAQUINA)]
        eu = maquina == "dono"  # à direita (verde) só as mensagens do dono; cada máquina fica à esquerda, com a sua cor
        nome = nomes.get(maquina, maquina)
        hora = quando.strftime("%H:%M")
        cab = _c(cores[maquina] + ";1", nome) + _c("2", "  " + maquina) if not eu else _c("2", "você")
        linhas = []
        for linha in (corpo or "(vazio)").splitlines() or [""]:
            linhas.extend(quebrar_visual(linha, largura - 8))
        horario = "  " + _c("2", hora)
        if largura_visual(linhas[-1] + horario) <= largura - 6:
            linhas[-1] += horario
        else:
            linhas.append(horario.strip())
        out.append(("" if eu else "  ") + cab if not eu else " " * max(0, largura - largura_visual(cab)) + cab)
        out.extend(_balao(linhas, eu, largura))
        out.append("")
    return "\n".join(out) + "\n"


def _gravar(texto):
    """Grava o recado do dono no canal (from: dono) e devolve o caminho do arquivo."""
    import secrets
    agora = datetime.datetime.now(datetime.timezone.utc)
    nome = f"{agora:%Y%m%dT%H%M%SZ}-dono-{secrets.token_hex(2)}.md"
    caminho = os.path.join(MESH, "channel", nome)
    with open(caminho, "w", encoding="utf-8") as f:
        f.write(f"---\nfrom: dono\nto: all\ntopic: recado do dono\n---\n{texto.strip()}\n")
    return caminho


def _publicar(caminho):
    """Commit e push do recado no mesh (o que pode demorar). Devolve a situação em texto."""
    import subprocess
    def git(*a):
        return subprocess.run(["git", "-C", MESH, *a], capture_output=True, text=True, timeout=60)
    git("add", caminho)
    identidade = []
    if not git("config", "--get", "user.email").stdout.strip():
        identidade = ["-c", "user.name=tt-mesh", "-c", "user.email=tt-mesh@localhost"]  # sem identidade no git: só para este commit
    if subprocess.run(["git", "-C", MESH, *identidade, "commit", "-q", "-m", "mesh: recado do dono"],
                      capture_output=True).returncode != 0:
        return "gravado (sem commit)"
    git("pull", "-q", "--rebase", "--autostash")
    if git("push", "-q").returncode == 0:
        _puxar_nas_outras()
        return "publicado no mesh"
    return "commitado; envio pendente (sem rede?)"


def enviar(texto):
    """Grava um recado do dono no canal (from: dono) e tenta o commit e o push do mesh. Devolve (arquivo, situação)."""
    caminho = _gravar(texto)
    return caminho, _publicar(caminho)


def _puxar_nas_outras():
    """Pede às outras máquinas da malha que puxem o mesh já (tt --mesh-puxar), em segundo plano."""
    import subprocess
    try:
        subprocess.Popen([os.environ.get("TT_BIN", "tt"), "--mesh-puxar"], start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


# --- Teclado ---------------------------------------------------------------------------------------------------------
# _tecla() devolve um texto por evento: o próprio caractere digitado (inclusive acentuado, que chega em 2 a 4 bytes),
# "colar:TEXTO" (colagem), "clique:x:y", um nome de tecla ("left", "ctrl_left", "delete", "home"…), "tempo" (nada chegou
# em `espera` segundos) ou "" (tecla sem uso).
_CSI = {b"A": "up", b"B": "down", b"C": "right", b"D": "left", b"H": "home", b"F": "end",
        b"1~": "home", b"4~": "end", b"7~": "home", b"8~": "end", b"3~": "delete", b"5~": "pgup", b"6~": "pgdn",
        b"1;5C": "ctrl_right", b"1;5D": "ctrl_left", b"1;3C": "alt_right", b"1;3D": "alt_left",
        b"1;5H": "ctrl_home", b"1;5F": "ctrl_end", b"1;2C": "ctrl_right", b"1;2D": "ctrl_left"}
_CONTROLE = {b"\x01": "ctrl_a", b"\x05": "ctrl_e", b"\x0b": "ctrl_k", b"\x15": "ctrl_u", b"\x17": "ctrl_w",
             b"\x0c": "redesenhar", b"\x12": "atualizar", b"\x14": "tick", b"\x7f": "apagar", b"\x08": "apagar",
             b"\r": "enter", b"\n": "nova_linha", b"\x03": "esc"}


def _byte(fd, espera=None):
    """Um byte; None se `espera` segundos passaram sem nada; b"" no fim da entrada."""
    import select
    if espera is not None and not select.select([fd], [], [], espera)[0]:
        return None
    return os.read(fd, 1)


def _utf8(fd, lider):
    """Completa um caractere UTF-8 a partir do primeiro byte (os acentos têm 2 bytes; emoji, 4)."""
    falta = 0 if lider[0] < 0xC0 else 1 if lider[0] < 0xE0 else 2 if lider[0] < 0xF0 else 3 if lider[0] < 0xF8 else 0
    dados = bytearray(lider)
    for _ in range(falta):
        b = _byte(fd, 0.2)
        if not b:
            break
        dados.extend(b)
    return bytes(dados).decode("utf-8", "ignore")


def _colagem(fd):
    """Texto entre ESC[200~ e ESC[201~ (colagem em bloco: o Enter dentro dela não envia)."""
    fim = b"\x1b[201~"
    dados = bytearray()
    while not dados.endswith(fim):
        b = _byte(fd, 1.0)
        if not b:
            break
        dados.extend(b)
    if dados.endswith(fim):
        del dados[-len(fim):]
    texto = bytes(dados).decode("utf-8", "ignore").replace("\r\n", "\n").replace("\r", "\n")
    return "colar:" + "".join(c for c in texto if c == "\n" or c.isprintable())


def _escape(fd):
    b = _byte(fd, 0.05)
    if not b:
        return "esc"  # Esc sozinho
    if b == b"[":
        seq = bytearray()
        while len(seq) < 40:
            p = _byte(fd, 0.05)
            if not p:
                break
            seq.extend(p)
            if 0x40 <= p[0] <= 0x7e:
                break
        seq = bytes(seq)
        if seq == b"200~":
            return _colagem(fd)
        if seq.startswith(b"<"):  # mouse SGR: roda (64 cima, 65 baixo); clique pressionado (0, M) vira "clique:x:y"
            partes = seq[1:-1].split(b";") if seq[-1:] in (b"M", b"m") else []
            if len(partes) == 3:
                try:
                    botao, x, y = (int(q) for q in partes)
                except ValueError:
                    return ""
                if botao == 0 and seq[-1:] == b"M":
                    return f"clique:{x}:{y}"
                if botao in (64, 65):
                    return {64: "roda_up", 65: "roda_down"}[botao]
            return ""
        return _CSI.get(seq, "")
    if b == b"O":  # SS3 (teclado em modo aplicação)
        p = _byte(fd, 0.05)
        return {b"A": "up", b"B": "down", b"C": "right", b"D": "left", b"H": "home", b"F": "end"}.get(p or b"", "")
    if b in (b"\r", b"\n"):
        return "nova_linha"  # Alt+Enter
    if b == b"b":
        return "ctrl_left"
    if b == b"f":
        return "ctrl_right"
    if b == b"\x7f":
        return "ctrl_w"  # Alt+Backspace
    return ""


def _tecla(espera=None):
    """Um evento do teclado ou do mouse, sem esperar Enter (ver acima). Fim da entrada sai ("esc")."""
    fd = sys.stdin.fileno()
    c = _byte(fd, espera)
    if c is None:
        return "tempo"
    if not c:
        return "esc"
    if c == b"\x1b":
        return _escape(fd)
    if c in _CONTROLE:
        return _CONTROLE[c]
    if c[0] < 0x20:
        return ""
    if c[0] < 0x80:
        return c.decode("ascii")
    return _utf8(fd, c)


# --- Edição da mensagem ------------------------------------------------------------------------------------------------
ENTRADA_MAX = 5          # linhas da caixa de mensagem (depois disso ela rola)
PROMPT = " mensagem "    # etiqueta verde da 1ª linha (10 colunas) + " ➤ " (3)
PROMPT_COLUNAS = 13


def _sem_largura(c):
    cp = ord(c)
    return (unicodedata.category(c).startswith("M") or c in "‍︎️" or
            0x1F3FB <= cp <= 0x1F3FF or 0xE0020 <= cp <= 0xE007F)


def cursor_prox(t, i):
    """Índice depois da letra que começa em i (a letra leva consigo acentos soltos e emoji compostos)."""
    n = len(t)
    if i >= n:
        return n
    i += 1
    while i < n and (_sem_largura(t[i]) or t[i - 1] == "‍"):
        i += 1
    return i


def cursor_ant(t, i):
    """Índice do começo da letra que termina em i."""
    if i <= 0:
        return 0
    i -= 1
    while i > 0 and (_sem_largura(t[i]) or t[i - 1] == "‍"):
        i -= 1
    return i


def _palavra(c):
    return c.isalnum() or c == "_"


def palavra_ant(t, i):
    while i > 0 and not _palavra(t[i - 1]):
        i -= 1
    while i > 0 and _palavra(t[i - 1]):
        i -= 1
    return i


def palavra_prox(t, i):
    n = len(t)
    while i < n and not _palavra(t[i]):
        i += 1
    while i < n and _palavra(t[i]):
        i += 1
    return i


def inicio_linha(t, i):
    return t.rfind("\n", 0, i) + 1


def fim_linha(t, i):
    j = t.find("\n", i)
    return len(t) if j < 0 else j


def linhas_entrada(texto, largura):
    """Linhas visuais do texto digitado: [(inicio, fim)], índices no texto (`fim` não inclui a quebra). Quebra depois do
    último espaço que cabe; palavra maior que a linha parte no meio dela; "\\n" força linha nova."""
    largura = max(1, largura)
    n = len(texto)
    linhas, ini = [], 0
    while True:
        j, col, espaco = ini, 0, -1
        while j < n and texto[j] != "\n":
            k = cursor_prox(texto, j)
            w = largura_visual(texto[j:k])
            if col + w > largura and j > ini:
                break
            col += w
            if texto[j] == " ":
                espaco = k
            j = k
        if j >= n:
            linhas.append((ini, n))
            return linhas
        if texto[j] == "\n":
            linhas.append((ini, j))
            ini = j + 1
        elif espaco > ini:
            linhas.append((ini, espaco))
            ini = espaco
        else:
            linhas.append((ini, j))
            ini = j


def linha_do_cursor(linhas, cur):
    """Índice da linha visual onde o cursor aparece (na quebra suave, no começo da linha de baixo)."""
    for r, (a, b) in enumerate(linhas):
        if a <= cur < b:
            return r
        if cur == b and (r + 1 == len(linhas) or linhas[r + 1][0] > b):
            return r
    return len(linhas) - 1


def indice_na_coluna(texto, a, b, coluna, ultima=True):
    """Índice no texto da linha visual [a, b) para um clique na coluna dada (0 = primeira coluna do texto)."""
    i, w = a, 0
    while i < b:
        k = cursor_prox(texto, i)
        w += largura_visual(texto[i:k])
        if coluna < w:
            return i
        i = k
    return b if ultima else max(a, cursor_ant(texto, b))


def _inserir(est, texto):
    est["buf"] = est["buf"][:est["cur"]] + texto + est["buf"][est["cur"]:]
    est["cur"] += len(texto)


def _apagar(est, de, ate):
    est["buf"] = est["buf"][:de] + est["buf"][ate:]
    est["cur"] = de


def editar(est, tecla, linhas=None):
    """Aplica uma tecla de edição à mensagem (est["buf"] e est["cur"]). Devolve True se a tecla era de edição."""
    buf, cur = est["buf"], est["cur"]
    if tecla.startswith("colar:"):
        _inserir(est, tecla[6:])
    elif tecla == "nova_linha":
        _inserir(est, "\n")
    elif len(tecla) >= 1 and not tecla.startswith("clique:") and tecla not in _NOMES and all(c.isprintable() for c in tecla):
        _inserir(est, tecla)
    elif tecla == "apagar":
        if cur:
            _apagar(est, cursor_ant(buf, cur), cur)
    elif tecla == "delete":
        if cur < len(buf):
            _apagar(est, cur, cursor_prox(buf, cur))
    elif tecla == "left":
        est["cur"] = cursor_ant(buf, cur)
    elif tecla == "right":
        est["cur"] = cursor_prox(buf, cur)
    elif tecla in ("ctrl_left", "alt_left"):
        est["cur"] = palavra_ant(buf, cur)
    elif tecla in ("ctrl_right", "alt_right"):
        est["cur"] = palavra_prox(buf, cur)
    elif tecla in ("home", "ctrl_a"):   # começo da linha que se vê (a quebra automática conta)
        est["cur"] = linhas[linha_do_cursor(linhas, cur)][0] if linhas else inicio_linha(buf, cur)
    elif tecla in ("end", "ctrl_e"):
        if linhas:
            r = linha_do_cursor(linhas, cur)
            fim = linhas[r][1]
            suave = r + 1 < len(linhas) and linhas[r + 1][0] == fim   # quebra automática: fica antes do último caractere
            est["cur"] = max(linhas[r][0], cursor_ant(buf, fim)) if suave else fim
        else:
            est["cur"] = fim_linha(buf, cur)
    elif tecla == "ctrl_u":
        _apagar(est, inicio_linha(buf, cur), cur)
    elif tecla == "ctrl_k":
        _apagar(est, cur, fim_linha(buf, cur))
    elif tecla == "ctrl_w":
        i = cur
        while i > 0 and buf[i - 1].isspace():
            i -= 1
        while i > 0 and not buf[i - 1].isspace():
            i -= 1
        _apagar(est, i, cur)
    else:
        return False
    return True


_NOMES = {"esc", "enter", "tempo", "up", "down", "pgup", "pgdn", "ctrl_home", "ctrl_end", "roda_up", "roda_down",
          "atualizar", "tick", "redesenhar", "apagar", "delete", "left", "right", "home", "end", "alt_left", "alt_right",
          "ctrl_left", "ctrl_right", "ctrl_a", "ctrl_e", "ctrl_k", "ctrl_u", "ctrl_w", "nova_linha"}


def janela(linhas, altura, desloc):
    """As `altura` linhas visíveis de `linhas`, `desloc` linhas para trás do fim (0 = o mais recente)."""
    total = len(linhas)
    desloc = max(0, min(desloc, max(0, total - altura)))
    fim = total - desloc
    return linhas[max(0, fim - altura):fim], desloc


def atualizar_mesh():
    """Traz as mensagens novas do tt-mesh (git pull, com tempo limite). Sem rede ou sem remoto, segue com o que tem."""
    import subprocess
    if not os.path.isdir(os.path.join(MESH, ".git")):
        return False
    try:
        r = subprocess.run(["git", "-C", MESH, "pull", "-q", "--rebase", "--autostash"],
                           capture_output=True, text=True, timeout=10)
        return r.returncode == 0
    except (subprocess.TimeoutExpired, OSError):
        return False


BOTOES = [("atualizar", "↻ atualizar", "48;5;24"), ("tick", "⏱ tick", "48;5;94"), ("fechar", "✕ fechar", "48;5;124")]
MOUSE_LIGA = "\033[?1000h\033[?1006h\033[?2004h"      # mouse (SGR) e colagem em bloco
MOUSE_DESLIGA = "\033[?2004l\033[?1000l\033[?1006l"
DIAS_LONGOS = ["segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo"]
RODA = 3  # linhas por "clique" da roda do mouse
ESPERA_TELA = 2.0      # a cada tanto o painel confere se chegou mensagem ou se a tela mudou de tamanho
PUXAR_A_CADA = 120     # e puxa o mesh (git pull) em segundo plano


def _assinatura():
    try:
        return os.stat(os.path.join(MESH, "channel")).st_mtime_ns
    except OSError:
        return 0


def painel():
    """Conversa do dia com a caixa de mensagem, como o WhatsApp: digita (com acento), Enter envia, Ctrl+J ou Alt+Enter
    quebram a linha, Esc fecha (ou Ctrl+C). Na caixa: setas, Ctrl+setas (palavra), Home/End, Delete, Ctrl+A/E/U/K/W e o
    clique do mouse movem o cursor para qualquer posição; a colagem em bloco entra inteira. Na conversa: roda do mouse,
    ↑/↓ (quando a caixa tem uma linha só), Page Up/Down e, com a caixa vazia, Home/End e Ctrl+Home/End (com texto na caixa,
    Ctrl+Home/End vão ao começo e ao fim da mensagem). Alt+←/→ ou as setas da barra do alto trocam o dia. Ctrl+R atualiza, Ctrl+T abre o menu do tick, Ctrl+L redesenha.
    As mensagens novas aparecem sozinhas. Sem terminal (teste, pipe), só mostra a conversa.
    Redesenho sem piscar: a tela não é apagada; só as linhas que mudaram são sobrescritas."""
    if not sys.stdin.isatty():
        sys.stdout.write(render(datetime.date.today()))
        return
    import threading

    def terminal():
        try:
            colunas, linhas = os.get_terminal_size(sys.stdout.fileno())
        except OSError:
            colunas, linhas = 0, 0
        if colunas < 12 or linhas < 10:
            colunas = max(colunas, int(os.environ.get("COLUMNS", "44")))
            linhas = max(linhas, int(os.environ.get("LINES", "40")))
        return max(14, colunas), max(8, linhas - 2)   # duas linhas de folga no fim, como sempre

    largura, util = terminal()
    est = {"buf": "", "cur": 0, "aviso": "", "desloc": 0, "corpo": [], "frame": None, "dia": datetime.date.today(),
           "largura": largura, "util": util, "altura": 1, "topo": 0, "assinatura": 0, "botoes": [], "setas": [],
           "caixa": (0, 0, []), "pronto": [], "puxando": None, "puxou_em": 0.0}

    def colunas_texto():
        return max(4, est["largura"] - PROMPT_COLUNAS - 1)

    def geometria():
        """Linhas da caixa de mensagem e altura da conversa para o tamanho e o texto de agora."""
        linhas = linhas_entrada(est["buf"], colunas_texto())
        nvis = min(len(linhas), ENTRADA_MAX, max(1, est["util"] - 7))
        est["altura"] = max(2, est["util"] - 3 - nvis)   # topo(1) + conversa + aviso(1) + botões(1) + caixa
        return linhas, nvis

    def montar():
        est["corpo"] = render(est["dia"], est["largura"], cabecalho=False).splitlines()
        est["assinatura"] = _assinatura()

    def barra_do_alto():
        dia, hoje = est["dia"], datetime.date.today()
        nome = DIAS_LONGOS[dia.weekday()] + ", " + dia.strftime("%d/%m/%Y")
        if dia == hoje:
            nome += " · hoje"
        elif dia == hoje - datetime.timedelta(days=1):
            nome += " · ontem"
        corpo = nome[:max(1, est["largura"] - 12)]
        miolo = " " * max(1, (est["largura"] - 8 - largura_visual(corpo)) // 2) + corpo
        direita = " ▶ " if dia < hoje else "   "
        est["setas"] = [(1, 5, "dia_ant")] + ([(est["largura"] - 4, est["largura"], "dia_prox")] if dia < hoje else [])
        return _c("48;5;236;38;5;255;1", " ◀ ") + _c("1", preencher_visual(miolo, est["largura"] - 6)) + _c("48;5;236;38;5;255;1" if dia < hoje else "2", direita)

    def desenhar():
        entrada, nvis = geometria()
        h = est["altura"]
        visivel, d = janela(est["corpo"], h, est["desloc"])
        quadro = [barra_do_alto()] + visivel + [""] * (h - len(visivel))
        if d:
            quadro.append(_c("2", cortar_visual(f"  ↓ {d} linha(s) abaixo · Ctrl+End = fim", est["largura"] - 1)))
        else:
            quadro.append(_c("2", cortar_visual("  " + est["aviso"], est["largura"] - 1)) if est["aviso"] else "")
        x, botoes, faixa = 2, [], ""
        for nome, rotulo, cor in BOTOES:
            trecho = f" {rotulo} "
            botoes.append((nome, x, x + largura_visual(trecho) - 1))
            faixa += _c(cor + ";38;5;255;1", trecho) + "  "
            x += largura_visual(trecho) + 2
        est["botoes"] = botoes
        quadro.append("  " + faixa)
        # caixa de mensagem: mostra as linhas que contêm o cursor
        r_cur = linha_do_cursor(entrada, est["cur"])
        est["topo"] = max(0, min(est["topo"], len(entrada) - nvis))
        if r_cur < est["topo"]:
            est["topo"] = r_cur
        elif r_cur >= est["topo"] + nvis:
            est["topo"] = r_cur - nvis + 1
        for i in range(nvis):
            a, b = entrada[est["topo"] + i]
            etiqueta = (_c("48;5;22;38;5;255", PROMPT) + " ➤ ") if i == 0 else " " * PROMPT_COLUNAS
            texto = est["buf"][a:b]
            if not est["buf"] and i == 0:
                texto = _c("2", "escreva aqui · Enter envia · Ctrl+J quebra a linha"[:colunas_texto()])
            quadro.append(etiqueta + texto)
        est["caixa"] = (len(quadro) - nvis + 1, nvis, entrada)   # linha da tela (1-based) da 1ª linha da caixa
        anterior = est["frame"] or [None] * len(quadro)
        saida = ["\033[?25l"]
        for indice, linha in enumerate(quadro):
            if indice >= len(anterior) or anterior[indice] != linha:
                saida.append(f"\033[{indice + 1};1H" + linha + "\033[K")
        for indice in range(len(quadro), len(anterior)):
            saida.append(f"\033[{indice + 1};1H\033[K")
        est["frame"] = quadro
        a, b = entrada[r_cur]
        coluna = PROMPT_COLUNAS + largura_visual(est["buf"][a:est["cur"]]) + 1
        saida.append(f"\033[{len(quadro) - nvis + 1 + (r_cur - est['topo'])};{coluna}H\033[?25h")
        sys.stdout.write("".join(saida))
        sys.stdout.flush()

    def trocar_dia(delta):
        novo = est["dia"] + datetime.timedelta(days=delta)
        if novo > datetime.date.today():
            return
        est["dia"], est["desloc"] = novo, 0
        montar()

    def clique_na_caixa(x, y):
        linha0, nvis, entrada = est["caixa"]
        if not (linha0 <= y < linha0 + nvis):
            return False
        a, b = entrada[est["topo"] + (y - linha0)]
        proxima = entrada[est["topo"] + (y - linha0) + 1][0] if est["topo"] + (y - linha0) + 1 < len(entrada) else None
        suave = proxima is not None and proxima == b
        est["cur"] = indice_na_coluna(est["buf"], a, b, max(0, x - 1 - PROMPT_COLUNAS), ultima=not suave)
        return True

    def tratar(tecla):
        h = est["altura"]
        maximo = max(0, len(est["corpo"]) - h)
        vazia = not est["buf"]
        entrada = geometria()[0]
        if tecla in ("roda_up", "up") and (tecla == "roda_up" or len(entrada) == 1):
            est["desloc"] = min(est["desloc"] + (RODA if tecla == "roda_up" else 1), maximo)
        elif tecla in ("roda_down", "down") and (tecla == "roda_down" or len(entrada) == 1):
            est["desloc"] = max(est["desloc"] - (RODA if tecla == "roda_down" else 1), 0)
        elif tecla in ("up", "down"):   # caixa com várias linhas: o cursor sobe e desce nela
            r = linha_do_cursor(entrada, est["cur"])
            alvo = r - 1 if tecla == "up" else r + 1
            if 0 <= alvo < len(entrada):
                a, b = entrada[r]
                col = largura_visual(est["buf"][a:est["cur"]])
                ta, tb = entrada[alvo]
                est["cur"] = indice_na_coluna(est["buf"], ta, tb, col, ultima=alvo + 1 == len(entrada) or entrada[alvo + 1][0] > tb)
        elif tecla == "pgup":
            est["desloc"] = min(est["desloc"] + h // 2, maximo)
        elif tecla == "pgdn":
            est["desloc"] = max(est["desloc"] - h // 2, 0)
        elif tecla in ("ctrl_home", "ctrl_end") and not vazia:   # com texto na caixa: começo e fim da mensagem toda
            est["cur"] = 0 if tecla == "ctrl_home" else len(est["buf"])
        elif tecla == "ctrl_home" or (tecla == "home" and vazia):
            est["desloc"] = maximo
        elif tecla == "ctrl_end" or (tecla == "end" and vazia):
            est["desloc"] = 0
        elif tecla == "alt_left" and vazia:
            trocar_dia(-1)
        elif tecla == "alt_right" and vazia:
            trocar_dia(1)
        elif tecla == "enter":
            if est["buf"].strip():
                texto = est["buf"]
                est["buf"], est["cur"], est["desloc"], est["topo"] = "", 0, 0, 0
                est["dia"] = datetime.date.today()
                arq = _gravar(texto)
                montar()
                est["aviso"] = "enviando…"
                def publicar():
                    est["pronto"].append(f"{_publicar(arq)}: {os.path.basename(arq)}")
                t = threading.Thread(target=publicar)
                t.start()
                est.setdefault("publicando", []).append(t)
        else:
            editar(est, tecla, entrada)

    def puxar_em_segundo_plano():
        import time
        def trabalho():
            ok = atualizar_mesh()
            est["pronto"].append("atualizado" if ok else "sem rede: mostrando o que já tem")
        est["puxando"] = threading.Thread(target=trabalho, daemon=True)
        est["puxou_em"] = time.monotonic()
        est["puxando"].start()

    import termios, time, tty
    fd = sys.stdin.fileno()
    modo_terminal = termios.tcgetattr(fd)
    tty.setraw(fd)
    sys.stdout.write(MOUSE_LIGA + "\033[2J")
    sys.stdout.flush()
    try:
        est["aviso"] = "atualizando…"
        montar()
        desenhar()
        puxar_em_segundo_plano()
        while True:
            tecla = _tecla(ESPERA_TELA)
            if tecla == "esc":
                break
            mudou = False
            # recados de segundo plano (git pull, publicação)
            while est["pronto"]:
                est["aviso"] = est["pronto"].pop(0)
                mudou = True
            if est["puxando"] is not None and not est["puxando"].is_alive() and time.monotonic() - est["puxou_em"] > PUXAR_A_CADA:
                puxar_em_segundo_plano()
            if _assinatura() != est["assinatura"]:   # chegou mensagem (pull, outra máquina, este recado)
                antes = len(est["corpo"])
                montar()
                if est["desloc"] > 0:
                    est["desloc"] += max(0, len(est["corpo"]) - antes)  # quem está lendo mais acima não perde o lugar
                mudou = True
            novas_largura, novo_util = terminal()
            if (novas_largura, novo_util) != (est["largura"], est["util"]):
                est["largura"], est["util"], est["desloc"], est["frame"] = novas_largura, novo_util, 0, None
                montar()
                sys.stdout.write("\033[2J")
                mudou = True
            if tecla == "tempo":
                if mudou:
                    desenhar()
                continue
            if tecla.startswith("clique:"):
                _, x, y = tecla.split(":")
                x, y = int(x), int(y)
                tecla = ""
                if y == est["altura"] + 3:   # linha dos botões (a barra do alto é a 1ª linha)
                    alvo = next((n for n, a, b in est["botoes"] if a <= x <= b), None)
                    if alvo == "fechar":
                        break
                    tecla = alvo or ""
                elif y == 1:
                    for a, b, acao in est["setas"]:
                        if a <= x <= b:
                            trocar_dia(-1 if acao == "dia_ant" else 1)
                elif not clique_na_caixa(x, y):
                    tecla = ""
            if tecla == "atualizar":
                est["aviso"] = "atualizando…"
                montar()
                if est["puxando"] is None or not est["puxando"].is_alive():
                    puxar_em_segundo_plano()
            elif tecla == "redesenhar":
                est["frame"] = None
                sys.stdout.write("\033[2J")
            elif tecla == "tick":
                # Menu do tick (o mesmo do menu de administração): roda com o terminal normal e volta ao painel.
                # O clique pode deixar o evento de soltura do mouse no stdin do menu.
                # Desligue o protocolo de mouse durante a tela filha e religue ao voltar.
                sys.stdout.write(MOUSE_DESLIGA + "\033[2J")
                sys.stdout.flush()
                import subprocess
                try:
                    candidato = os.environ.get("TT_BIN") or os.path.join(os.path.expanduser("~"), ".local", "bin", "tt")
                    if not os.path.isfile(candidato):
                        import shutil
                        candidato = shutil.which("tt") or candidato
                    termios.tcsetattr(fd, termios.TCSADRAIN, modo_terminal)
                    r = subprocess.run([candidato, "--mesh-tick-menu"])
                    if r.returncode:
                        est["aviso"] = f"menu do tick terminou com erro ({r.returncode})"
                    else:
                        est["aviso"] = "tick ajustado"
                except OSError as e:
                    est["aviso"] = f"não abriu o menu do tick: {e.strerror}"
                finally:
                    tty.setraw(fd)
                    sys.stdout.write(MOUSE_LIGA + "\033[2J")
                    sys.stdout.flush()
                    est["frame"] = None
                montar()
            elif tecla:
                tratar(tecla)
            desenhar()
    finally:
        for t in est.get("publicando", []):
            t.join(timeout=70)   # não deixa o recado pela metade (commit/push em andamento)
        termios.tcsetattr(fd, termios.TCSADRAIN, modo_terminal)
        sys.stdout.write(MOUSE_DESLIGA + "\033[?25h\n")
        sys.stdout.flush()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--ativar":
        # Liga o plugin com o tt-mesh desta pessoa (o atalho passa a existir depois de recarregar o tmux).
        caminho = os.path.expanduser(sys.argv[2] if len(sys.argv) > 2 else "~/tt-mesh")
        if not os.path.isdir(os.path.join(caminho, "channel")):
            sys.exit(f"✗ {caminho} não é um tt-mesh (falta channel/)")
        os.makedirs(os.path.expanduser("~/.config/tt"), exist_ok=True)
        with open(os.path.expanduser("~/.config/tt/conversa-mesh.on"), "w", encoding="utf-8") as f:
            f.write(caminho + "\n")
        print(f"conversa do mesh ativada com {caminho} (tmux: prefix + M depois de recarregar)")
        sys.exit(0)
    if len(sys.argv) > 1 and sys.argv[1] == "--desativar":
        try:
            os.unlink(os.path.expanduser("~/.config/tt/conversa-mesh.on"))
        except OSError:
            pass
        print("conversa do mesh desativada")
        sys.exit(0)
    if len(sys.argv) > 2 and sys.argv[1] == "--enviar":
        arq, situacao = enviar(" ".join(sys.argv[2:]))
        print(f"{situacao}: {os.path.basename(arq)}")
        sys.exit(0)
    if len(sys.argv) > 1 and sys.argv[1] == "--painel":
        painel()
        sys.exit(0)
    try:
        dia = dia_alvo(sys.argv[1] if len(sys.argv) > 1 else "")
    except ValueError:
        sys.exit("uso: tt --conversa-mesh [AAAA-MM-DD|hoje|ontem] | --painel | --enviar TEXTO")
    sys.stdout.write(render(dia))
