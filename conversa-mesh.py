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
    if git("commit", "-q", "-m", "mesh: recado do dono").returncode != 0:
        return caminho, "gravado (sem commit)"
    git("pull", "-q", "--rebase", "--autostash")
    if git("push", "-q").returncode == 0:
        return caminho, "publicado no mesh"
    return caminho, "commitado; envio pendente (sem rede?)"


def painel():
    """Conversa do dia com uma linha para escrever: cada recado vai ao canal. Enter vazio ou q fecha."""
    linhas = int(os.environ.get("LINES", "40"))
    while True:
        sys.stdout.write("\033[2J\033[H")
        corpo = render(datetime.date.today()).splitlines()
        sys.stdout.write("\n".join(corpo[-(linhas - 4):]) + "\n")
        try:
            msg = input(_c("48;5;22;38;5;255", " mensagem ") + " ➤ ").strip()
        except EOFError:
            break
        if not msg or msg == "q":
            break
        arq, situacao = enviar(msg)
        sys.stdout.write(f"  {situacao}: {os.path.basename(arq)}\n")
        import time; time.sleep(1)


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
