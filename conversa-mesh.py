#!/usr/bin/env python3
# conversa-mesh.py — a conversa do tt-mesh de um dia, como chat (tt --conversa-mesh [DIA|hoje|ontem]).
# Lê channel/ e channel/arquivo/ do enxame (TT_MESH, padrão ~/tt-mesh): cada mensagem é um arquivo
# AAAAMMDDTHHMMSSZ-maquina-rand.md (UTC). Mostra o dia em ordem, com o nome e o tom da persona de cada máquina
# (## Personas da carta), a máquina de quem lê à direita. Saída pensada para um painel estreito do tmux.
import datetime, glob, os, re, sys, textwrap

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
                m = re.match(r"- \*\*([\w-]+)\*\* · (\w+)", linha)
                if m:
                    nomes[m.group(1)] = m.group(2)
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
CORES_MAQUINA = ["38;5;208", "38;5;78", "38;5;141", "38;5;81", "38;5;215", "38;5;250"]
DIAS = ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"]


def _balao(linhas, eu, largura):
    """Balão de texto dentro de um painel de `largura` colunas: à direita se for a própria máquina, à esquerda se não."""
    fundo = "48;5;22" if eu else "48;5;236"
    dentro = max(len(l) for l in linhas) if linhas else 0  # o balão se ajusta ao texto, como no WhatsApp
    dentro = min(dentro, largura - 6)
    saida = []
    for l in linhas:
        texto = " " + l.ljust(dentro) + " "
        bloco = _c(f"{fundo};38;5;255", texto)
        if eu:
            saida.append(" " * max(largura - len(texto), 0) + bloco)
        else:
            saida.append("  " + bloco)
    return saida


def render(dia, largura=None):
    largura = largura or LARGURA
    nomes = personas()
    cores = {}
    out = []
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
            out.append(_c("2", ("  ┄ " + topico[:largura - 8] + " ┄").center(largura)))
            topico_ant = topico
        if maquina not in cores:
            cores[maquina] = CORES_MAQUINA[len(cores) % len(CORES_MAQUINA)]
        eu = maquina == ME
        nome = nomes.get(maquina, maquina)
        hora = quando.strftime("%H:%M")
        cab = _c(cores[maquina] + ";1", nome) + _c("2", "  " + maquina) if not eu else _c("2", "você · " + maquina)
        linhas = []
        for linha in (corpo or "(vazio)").splitlines() or [""]:
            linhas.extend(textwrap.wrap(linha, largura - 8) or [""])
        linhas[-1] = linhas[-1] + "  " + _c("2", hora)
        out.append(("" if eu else "  ") + cab if not eu else cab.rjust(largura))
        out.extend(_balao(linhas, eu, largura))
        out.append("")
    return "\n".join(out) + "\n"


def enviar(texto):
    """Grava um recado do dono no canal (from: dono) e tenta o commit e o push do mesh. Devolve (arquivo, situação)."""
    import secrets, subprocess
    agora = datetime.datetime.now(datetime.timezone.utc)
    nome = f"{agora:%Y%m%dT%H%M%SZ}-dono-{secrets.token_hex(2)}.md"
    caminho = os.path.join(MESH, "channel", nome)
    with open(caminho, "w", encoding="utf-8") as f:
        f.write(f"---\nfrom: dono\nto: all\ntopic: recado do dono\n---\n{texto.strip()}\n")
    def git(*a):
        return subprocess.run(["git", "-C", MESH, *a], capture_output=True, text=True, timeout=60)
    git("add", caminho)
    identidade = []
    if not git("config", "--get", "user.email").stdout.strip():
        identidade = ["-c", "user.name=tt-mesh", "-c", "user.email=tt-mesh@localhost"]  # sem identidade no git: só para este commit
    if subprocess.run(["git", "-C", MESH, *identidade, "commit", "-q", "-m", "mesh: recado do dono"],
                      capture_output=True).returncode != 0:
        return caminho, "gravado (sem commit)"
    git("pull", "-q", "--rebase", "--autostash")
    if git("push", "-q").returncode == 0:
        _puxar_nas_outras()
        return caminho, "publicado no mesh"
    return caminho, "commitado; envio pendente (sem rede?)"


def _puxar_nas_outras():
    """Pede às outras máquinas da malha que puxem o mesh já (tt --mesh-puxar), em segundo plano."""
    import subprocess
    try:
        subprocess.Popen([os.environ.get("TT_BIN", "tt"), "--mesh-puxar"], start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def _tecla():
    """Uma tecla, sem esperar Enter. Esc sozinho vira "esc"; setas e outras sequências viram "" (ignoradas)."""
    import select, termios, tty
    fd = sys.stdin.fileno()
    antigo = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        c = os.read(fd, 1)
        if not c:
            return "esc"  # fim da entrada: sai
        if c == b"\x1b":
            if select.select([fd], [], [], 0.05)[0]:
                seq = os.read(fd, 16)
                if not seq:
                    return "esc"
                if seq.startswith(b"[<"):  # mouse (SGR): roda (64 cima, 65 baixo); clique pressionado (0, M) vira "clique:x:y"
                    corpo = seq[2:]
                    partes = corpo.rstrip(b"Mm").split(b";")
                    if len(partes) == 3 and partes[0] == b"0" and corpo[-1:] == b"M":
                        return f"clique:{partes[1].decode()}:{partes[2].decode()}"
                    return {b"64": "up", b"65": "down"}.get(partes[0], "")
                return {b"[A": "up", b"[B": "down", b"[5~": "pgup", b"[6~": "pgdn",
                        b"[H": "home", b"[1~": "home", b"[F": "end", b"[4~": "end"}.get(seq, "")
            return "esc"
        if c == b"\x03":
            return "esc"
        if c == b"\x12":
            return "atualizar"
        if c == b"\x14":
            return "tick"
        if c in (b"\r", b"\n"):
            return "enter"
        if c == b"\x7f":
            return "apagar"
        return c.decode("utf-8", "ignore") if c.isascii() or c[:1] >= b"\xc0" else ""
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, antigo)


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
MOUSE_LIGA = "\033[?1000h\033[?1006h"   # pede eventos de mouse (SGR): a roda chega ao painel
MOUSE_DESLIGA = "\033[?1000l\033[?1006l"


def painel():
    """Conversa do dia com a linha de digitação, como o WhatsApp: digita, Enter envia, Esc fecha (ou Ctrl+C).
    Setas, Page Up/Down, Home, End, a roda do mouse e Ctrl+R rolam e atualizam. Sem terminal (teste, pipe), só mostra a conversa.
    Redesenho sem piscar: a tela não é apagada; cada linha é sobrescrita e o cursor fica escondido durante o desenho."""
    if not sys.stdin.isatty():
        sys.stdout.write(render(datetime.date.today()))
        return
    linhas_tela = int(os.environ.get("LINES", "40"))
    altura = max(5, linhas_tela - 5)
    est = {"buf": "", "aviso": "", "desloc": 0, "corpo": []}

    def montar():
        est["corpo"] = render(datetime.date.today()).splitlines()

    def desenhar():
        visivel, d = janela(est["corpo"], altura, est["desloc"])
        quadro = ["\033[H"]
        for linha in visivel + [""] * (altura - len(visivel)):
            quadro.append(linha + "\033[K\n")
        if d:
            quadro.append(_c("2", f"  ↓ {d} linha(s) abaixo · End volta ao fim") + "\033[K\n")
        else:
            quadro.append((_c("2", est["aviso"]) if est["aviso"] else "") + "\033[K\n")
        # botões: linha própria (linha altura+2), clicáveis; as posições (x) ficam guardadas para o clique
        x, botoes, faixa = 2, [], ""
        for nome, rotulo, cor in BOTOES:
            trecho = f" {rotulo} "
            botoes.append((nome, x, x + len(trecho) - 1))
            faixa += _c(cor + ";38;5;255;1", trecho) + "  "
            x += len(trecho) + 2
        est["botoes"] = botoes
        quadro.append("\r\033[K  " + faixa + "\033[K\n")
        quadro.append("\r\033[K" + _c("48;5;22;38;5;255", " mensagem ") + " ➤ " + est["buf"] + "\033[J")
        sys.stdout.write("\033[?25l" + "".join(quadro) + "\033[?25h")
        sys.stdout.flush()

    def tratar(tecla):
        maximo = max(0, len(est["corpo"]) - altura)
        if tecla == "up":
            est["desloc"] = min(est["desloc"] + 1, maximo)
        elif tecla == "down":
            est["desloc"] = max(est["desloc"] - 1, 0)
        elif tecla == "pgup":
            est["desloc"] = min(est["desloc"] + altura // 2, maximo)
        elif tecla == "pgdn":
            est["desloc"] = max(est["desloc"] - altura // 2, 0)
        elif tecla == "home":
            est["desloc"] = maximo
        elif tecla == "end":
            est["desloc"] = 0
        elif tecla == "enter":
            if est["buf"].strip():
                arq, situacao = enviar(est["buf"])
                est["aviso"] = f"{situacao}: {os.path.basename(arq)}"
                est["buf"], est["desloc"] = "", 0
                montar()
        elif tecla == "apagar":
            est["buf"] = est["buf"][:-1]
        elif len(tecla) == 1 and tecla.isprintable():
            est["buf"] += tecla

    sys.stdout.write(MOUSE_LIGA + "\033[2J")  # só a abertura apaga a tela
    sys.stdout.flush()
    try:
        est["aviso"] = "atualizando…" if atualizar_mesh() else "sem atualizar (sem rede): mostrando o que já tem"
        montar()
        desenhar()
        while True:
            tecla = _tecla()
            if tecla == "esc":
                break
            if tecla.startswith("clique:"):
                _, x, y = tecla.split(":")
                if int(y) == altura + 2:
                    alvo = next((n for n, a, b in est.get("botoes", []) if a <= int(x) <= b), None)
                    if alvo == "fechar":
                        break
                    tecla = alvo or ""
                else:
                    tecla = ""
            if tecla == "atualizar":
                est["aviso"] = "atualizado" if atualizar_mesh() else "sem atualizar (sem rede)"
                montar()
            elif tecla == "tick":
                # Menu do tick (o mesmo do menu de administração): roda com o terminal normal e volta ao painel.
                sys.stdout.write("\033[2J")
                sys.stdout.flush()
                import subprocess
                try:
                    subprocess.run([os.environ.get("TT_BIN", "tt"), "--mesh-tick-menu"])
                except OSError:
                    est["aviso"] = "tt não encontrado: o menu do tick não abriu"
                est["aviso"] = est["aviso"] or "tick ajustado"
                montar()
            else:
                tratar(tecla)
            desenhar()
    finally:
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
