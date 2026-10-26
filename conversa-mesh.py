#!/usr/bin/env python3
# conversa-mesh.py — a conversa do tt-mesh de um dia, como chat (tt --conversa-mesh [DIA|hoje|ontem]).
# Lê channel/ e channel/arquivo/ do enxame (TT_MESH, padrão ~/tt-mesh): cada mensagem é um arquivo
# AAAAMMDDTHHMMSSZ-maquina-rand.md (UTC). Mostra o dia em ordem, com o nome e o tom da persona de cada máquina
# (## Personas da carta), a máquina de quem lê à direita. Saída pensada para um painel estreito do tmux.
import datetime, glob, os, re, sys, textwrap

MESH = os.environ.get("TT_MESH") or os.path.expanduser("~/tt-mesh")
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


def render(dia):
    nomes = personas()
    out = []
    out.append(f"  conversa do mesh · {dia.strftime('%d/%m/%Y')} ({['seg','ter','qua','qui','sex','sáb','dom'][dia.weekday()]})")
    out.append("─" * LARGURA)
    msgs = mensagens(dia)
    if not msgs:
        out.append("  (nenhuma mensagem neste dia)")
        return "\n".join(out) + "\n"
    topico_ant = None
    for quando, maquina, topico, corpo in msgs:
        if topico != topico_ant and topico:
            out.append(f"  ┄ {topico[:LARGURA - 6]} ┄")
            topico_ant = topico
        nome = nomes.get(maquina, maquina)
        eu = maquina == ME
        cab = f"{quando.strftime('%H:%M')}  {nome} · {maquina}"
        if eu:
            out.append(cab.rjust(LARGURA))
        else:
            out.append(cab)
        larg = LARGURA - 6
        for linha in (corpo or "(vazio)").splitlines() or [""]:
            for pedaco in textwrap.wrap(linha, larg) or [""]:
                out.append((pedaco.rjust(LARGURA - 2) if eu else "  " + pedaco))
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
        sys.stdout.write("\n".join(corpo[-(linhas - 4):]) + "\n\n")
        try:
            msg = input("recado (Enter sai)> ").strip()
        except EOFError:
            break
        if not msg or msg == "q":
            break
        arq, situacao = enviar(msg)
        sys.stdout.write(f"  {situacao}: {os.path.basename(arq)}\n")
        import time; time.sleep(1)


if __name__ == "__main__":
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
