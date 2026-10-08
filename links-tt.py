#!/usr/bin/env python3
"""Links e quebras de linha na tela do tmux, para o tt.

Um endereço longo raramente cabe numa linha: o terminal o quebra (e o tmux sabe juntar), mas
programas como o Claude Code, o aerc ou uma caixa desenhada quebram por conta própria, com recuo
ou borda na linha seguinte. O tmux então vê linhas soltas: o clique pegava só um pedaço e a cópia
vinha com quebra e espaços no meio. Aqui as linhas da tela são religadas quando o que está na
borda direita continua, sem espaço, no começo da linha de baixo.

  links-tt.py clique CLIENTE PAINEL X Y LARGURA ALTURA simples|ctrl [HIPERLINK]
        clique do mouse (tmux.conf): 0 = havia link e a abertura já foi pedida; 1 = não havia
  links-tt.py copiar CLIENTE PAINEL X Y LARGURA ALTURA [HIPERLINK]
        duplo clique: 0 = havia link e ele foi copiado inteiro; 1 = não havia
  links-tt.py todos PAINEL        URLs da tela e do histórico, da mais recente para a mais antiga
  links-tt.py url-em LARGURA X Y  (stdin: linhas da tela) a URL nesse ponto (sai 1 se não há)
  links-tt.py listar LARGURA      (stdin: linhas da tela) todas as URLs, na ordem da tela
  links-tt.py desquebrar LARGURA X0  (stdin: texto copiado) o texto sem as quebras feitas pela tela
  links-tt.py com-ctrl-q CMD [ARG…]  roda CMD num pseudoterminal; Ctrl+Q o encerra (Carbonyl no popup)
"""
import os
import re
import subprocess
import sys
import time
import unicodedata

# Quantas colunas, no máximo, podem sobrar à direita de uma linha que "chegou na borda" (o Claude
# Code deixa uma; uma caixa, a borda e um espaço).
MARGEM = 2
BORDAS = "│┃║╎╏┆┇┊┋|"
URL_RE = re.compile(r"https?://[^\s<>\"'`─-╿]+")
ESQUEMA_RE = re.compile(r"https?://")
OSC8_RE = re.compile(r"\033\]8;[^;\033\a]*;([^\033\a]*)(?:\033\\|\a)")
FIM_SOLTO = ".,;:!?…"
PARES = {")": "(", "]": "[", "}": "{"}


def largura_car(c):
    if unicodedata.combining(c) or unicodedata.category(c) in ("Mn", "Me", "Cf"):
        return 0
    return 2 if unicodedata.east_asian_width(c) in ("W", "F") else 1


def car_de_token(c):
    """Caractere que pode estar no meio de uma URL, caminho ou código."""
    return not c.isspace() and not ("─" <= c <= "╿") and c not in "\"'`<>"


def tecnico(t):
    """Token que não é palavra de texto corrido: endereço, caminho, chave=valor, código."""
    return "://" in t or any(c in t for c in "/\\=&?%_#~@")


def aparar_url(u):
    while u:
        if u[-1] in FIM_SOLTO:
            u = u[:-1]
        elif u[-1] in PARES and u.count(PARES[u[-1]]) < u.count(u[-1]):
            u = u[:-1]
        else:
            break
    return u if len(u) > len("https://") and ESQUEMA_RE.match(u) else ""


class Linha:
    """Uma linha da tela: o texto, a coluna de cada caractere e onde o conteúdo começa e termina
    (sem o recuo, sem os espaços do fim e sem uma borda de caixa)."""

    def __init__(self, texto, x0=0):
        self.texto = texto
        self.cols = []
        col = x0
        for c in texto:
            self.cols.append(col)
            col += largura_car(c)
        fim = len(texto)
        while fim and texto[fim - 1].isspace():
            fim -= 1
        if fim and texto[fim - 1] in BORDAS:
            fim -= 1
            while fim and texto[fim - 1].isspace():
                fim -= 1
        self.fim = fim
        self.col_fim = (self.cols[fim - 1] + largura_car(texto[fim - 1])) if fim else x0
        ini = 0
        while ini < fim and (texto[ini].isspace() or texto[ini] in BORDAS):
            ini += 1
        self.ini = ini
        self.col_ini = self.cols[ini] if ini < len(texto) else x0

    def cabeca(self):
        """Primeiro token do conteúdo."""
        i = self.ini
        while i < self.fim and car_de_token(self.texto[i]):
            i += 1
        return self.texto[self.ini:i]


def cauda(texto):
    """Token que termina o texto (largura em colunas)."""
    i = len(texto)
    while i and car_de_token(texto[i - 1]):
        i -= 1
    return texto[i:]


def continua(cauda_txt, a, b, largura, exigir_tecnico):
    """A linha b continua, sem espaço, o token que termina a linha a?"""
    if not a.fim or a.col_fim < largura - MARGEM or not car_de_token(a.texto[a.fim - 1]):
        return False
    if b.ini >= b.fim or not car_de_token(b.texto[b.ini]):
        return False
    cab = b.cabeca()
    if ESQUEMA_RE.match(cab):
        return False  # a linha de baixo começa outro endereço
    total = sum(largura_car(c) for c in cauda_txt + cab)
    # Quem quebra palavra para caber (Claude Code, wrap) só parte um token maior que a linha; um
    # token menor teria descido inteiro. Sem recuo, é a quebra do próprio terminal.
    if total > largura - 4:
        return True
    return b.col_ini == 0 and (not exigir_tecnico or tecnico(cauda_txt + cab))


def religar(linhas, largura):
    """Junta as linhas da tela num texto só, religando os tokens partidos na borda. Devolve o texto e,
    para cada caractere, (linha, coluna inicial, coluna final) na tela."""
    texto, mapa = [], []
    ant, cauda_txt = None, ""
    largura = max(largura, 10)
    for n, s in enumerate(linhas):
        ln = Linha(s)
        if ant is not None and continua(cauda_txt, ant, ln, largura, False):
            # tira o fim da anterior (espaços/borda) e o começo desta (recuo/borda)
            corte = len(texto) - (len(ant.texto) - ant.fim)
            del texto[corte:], mapa[corte:]
            de = ln.ini
        else:
            if ant is not None:
                texto.append("\n")
                mapa.append((n - 1, -1, -1))
            de = 0
        for i in range(de, len(s)):
            c = s[i]
            texto.append(c)
            mapa.append((n, ln.cols[i], ln.cols[i] + max(1, largura_car(c))))
        sobra = len(s) - ln.fim
        cauda_txt = cauda("".join(texto[-(largura * 4) - sobra:len(texto) - sobra]))
        ant = ln
    return "".join(texto), mapa


def urls(linhas, largura):
    texto, mapa = religar(linhas, largura)
    for m in URL_RE.finditer(texto):
        u = aparar_url(m.group(0))
        if u:
            yield u, m.start(), m.start() + len(u), mapa


def url_em(linhas, largura, x, y):
    for u, ini, fim, mapa in urls(linhas, largura):
        for i in range(ini, fim):
            n, c0, c1 = mapa[i]
            if n == y and c0 <= x < c1:
                return u
    return ""


def desquebrar(texto, largura, x0):
    """Texto copiado de uma seleção: religa endereços, caminhos e códigos partidos na borda da tela
    (sem a quebra e sem o recuo que a tela pôs), e deixa intactas as quebras de verdade."""
    if largura < 10:
        return texto
    linhas = texto.split("\n")
    saida = [linhas[0]]
    ant = Linha(linhas[0], x0)
    # Linha juntada pelo próprio tmux (quebra do terminal) pode ter mais de uma volta de tela.
    if ant.col_fim > largura:
        ant.col_fim = (ant.col_fim - 1) % largura + 1
    for s in linhas[1:]:
        ln = Linha(s)
        if ln.col_fim > largura:
            ln.col_fim = (ln.col_fim - 1) % largura + 1
        atual = saida[-1]
        if continua(cauda(atual[:len(atual) - (len(ant.texto) - ant.fim)]), ant, ln, largura, True):
            saida[-1] = atual[:len(atual) - (len(ant.texto) - ant.fim)] + s[ln.ini:]
        else:
            saida.append(s)
        ant = ln
    return "\n".join(saida)


# --- tmux ------------------------------------------------------------------------------------------
def tmux(*args):
    try:
        return subprocess.run(("tmux",) + args, capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return ""


def tt():
    aqui = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tt")
    return aqui if os.access(aqui, os.X_OK) else "tt"


def url_no_painel(painel, x, y, largura, altura, hiperlink):
    if hiperlink and aparar_url(hiperlink) == hiperlink:
        return hiperlink
    linhas = tmux("capture-pane", "-p", "-t", painel, "-S", "-80").split("\n")
    if linhas and linhas[-1] == "":
        linhas.pop()
    return url_em(linhas, largura, x, y + max(0, len(linhas) - altura))


def soltar(*args):
    subprocess.Popen([tt()] + list(args), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def clique(cliente, painel, x, y, largura, altura, ctrl, hiperlink):
    u = url_no_painel(painel, x, y, largura, altura, hiperlink)
    if not u:
        return 1
    # Clique simples espera o tempo de um duplo clique (o duplo copia, não abre): o tmux.conf limpa
    # @tt_link_id no 2º clique e no arrasto. Ctrl+clique abre na hora.
    ident = "" if ctrl else str(time.time_ns())
    if ident:
        tmux("set", "-g", "@tt_link_id", ident)
    soltar("--link-abrir", ident, cliente, painel, u)
    return 0


def copiar(cliente, painel, x, y, largura, altura, hiperlink):
    u = url_no_painel(painel, x, y, largura, altura, hiperlink)
    if not u:
        return 1
    soltar("--link-copiar", cliente, u)
    return 0


def todos(painel):
    largura = int((tmux("display", "-p", "-t", painel, "#{pane_width}").strip() or "80"))
    texto = tmux("capture-pane", "-p", "-t", painel, "-S", "-3000")
    vistos, saida = set(), []
    for u, *_ in urls(texto.split("\n"), largura):
        saida.append(u)
    for u in OSC8_RE.findall(tmux("capture-pane", "-p", "-e", "-t", painel, "-S", "-3000")):
        if aparar_url(u) == u:
            saida.append(u)
    for u in reversed(saida):
        if u not in vistos:
            vistos.add(u)
            print(u)
    return 0


def com_ctrl_q(cmd):
    """Roda CMD num pseudoterminal, repassando tudo, e faz Ctrl+Q encerrá-lo. O Carbonyl só sai com
    Ctrl+C (que num navegador ninguém adivinha), e o popup do tmux só fecha quando o programa sai:
    Ctrl+Q vira Ctrl+C para ele e, se ele não sair, TERM e depois KILL."""
    import pty, select, signal, termios, tty, fcntl
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execvp(cmd[0], cmd)
        except OSError as e:
            print(f"✗ {cmd[0]}: {e.strerror}", file=sys.stderr)
        os._exit(127)

    def tamanho(*_):
        try:
            fcntl.ioctl(fd, termios.TIOCSWINSZ, fcntl.ioctl(0, termios.TIOCGWINSZ, b"\0" * 8))
        except OSError:
            pass

    def escrever(alvo, dados):
        while dados:
            try:
                dados = dados[os.write(alvo, dados):]
            except BlockingIOError:
                select.select([], [alvo], [], 1)
    tamanho()
    signal.signal(signal.SIGWINCH, tamanho)
    antigo = termios.tcgetattr(0) if os.isatty(0) else None
    if antigo:
        tty.setraw(0)
    pedido = None
    try:
        while True:
            r, _, _ = select.select([0, fd], [], [], 0.5)
            if fd in r:
                try:
                    d = os.read(fd, 65536)
                except OSError:
                    d = b""
                if not d:
                    break
                escrever(1, d)
            if 0 in r:
                d = os.read(0, 4096)
                if b"\x11" in d or not d:
                    pedido = pedido or time.time()
                    d = d.replace(b"\x11", b"\x03")
                if d:
                    escrever(fd, d)
            if pedido:
                passou = time.time() - pedido
                for limite, sinal in ((2, signal.SIGTERM), (4, signal.SIGKILL)):
                    if passou > limite:
                        try:
                            os.kill(pid, sinal)
                        except ProcessLookupError:
                            pass
    finally:
        if antigo:
            termios.tcsetattr(0, termios.TCSADRAIN, antigo)
        try:
            _, st = os.waitpid(pid, 0)
        except ChildProcessError:
            st = 0
    return os.waitstatus_to_exitcode(st) if hasattr(os, "waitstatus_to_exitcode") else 0


def main(a):
    if a[:1] == ["com-ctrl-q"] and len(a) >= 2:
        return com_ctrl_q(a[1:])
    try:
        if a[:1] == ["clique"] and len(a) in (8, 9):
            return clique(a[1], a[2], int(a[3]), int(a[4]), int(a[5]), int(a[6]), a[7] == "ctrl", "".join(a[8:]))
        if a[:1] == ["copiar"] and len(a) in (7, 8):
            return copiar(a[1], a[2], int(a[3]), int(a[4]), int(a[5]), int(a[6]), "".join(a[7:]))
        if a[:1] == ["todos"] and len(a) == 2:
            return todos(a[1])
        if a[:1] == ["url-em"] and len(a) == 4:
            u = url_em(sys.stdin.read().split("\n"), int(a[1]), int(a[2]), int(a[3]))
            print(u)
            return 0 if u else 1
        if a[:1] == ["listar"] and len(a) == 2:
            for u, *_ in urls(sys.stdin.read().split("\n"), int(a[1])):
                print(u)
            return 0
        if a[:1] == ["desquebrar"] and len(a) == 3:
            sys.stdout.write(desquebrar(sys.stdin.read(), int(a[1]), int(a[2])))
            return 0
    except (ValueError, OSError):
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
