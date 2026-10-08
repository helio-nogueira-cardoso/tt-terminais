#!/usr/bin/env python3
"""letreiro-tt.py — o miolo da faixa de notificações do tt: letreiro, aviso fresco e transferências.

Por que um programa à parte: no tmux, QUALQUER set-option — até de uma @opção que nada desenha —
redesenha a tela inteira de todos os clientes (options_push_changes → server_redraw_client). O laço
antigo gravava @barra_ticker a cada passo do letreiro: ~2 redesenhos completos por segundo (8 KB
cada) em cada terminal, com o cursor sumindo e voltando — o flicker. A única via que atualiza SÓ a
barra é a saída de um #(comando) da status line: o tmux lê cada linha que o processo imprime e
redesenha apenas a status line (format_job_update → server_status_client), no máximo uma vez por
segundo por cliente. Este programa é esse comando: um processo leve por cliente (o tmux cria um por
cliente e o encerra quando o cliente sai), que dorme, lê arquivos e imprime uma linha SÓ quando o
conteúdo muda. Ele nunca chama o tmux nem grava opção alguma.

Modos:
  fluxo TTY PID     o que o tt liga na barra (@barra_notifs = "#(… fluxo #{client_tty} #{client_pid})").
                    A largura vem do terminal do próprio cliente (ioctl TIOCGWINSZ): redimensionar não
                    reinicia o processo e cada cliente vê o recorte do seu tamanho.
  quadro [LARGURA]  imprime um quadro e sai (testes, `tt --ticker-quadro`).

Regras (as mesmas que a barra em bash seguia):
  - orçamento = largura − 66 (chips, relógio, divisórias e margens), mínimo 12; aviso só com ≥ 90;
  - aviso fresco (nascido há < TT_NOTIF_SLOT s, padrão 10; não lido; não expirado) tem a vez, em
    negrito (aviso_pisca=1 alterna a cada segundo); depois a transferência ativa; depois o letreiro;
  - letreiro: fontes em ~/.cache/tt-ticker/<fonte> (o vigia atualiza com TTL; rede nunca aqui), itens
    separados por " • ", numa roda. ticker_rolagem=paginas (padrão) troca de bloco a cada ticker_veloc s
    (padrão 6); continua desliza round(1/ticker_veloc) caracteres por segundo (padrão 0,35 s → 3/s):
    um quadro por segundo é o teto em que o tmux redesenha a barra de um cliente;
  - a posição é função da hora, não de um contador: todos os clientes mostram o mesmo trecho e um
    reinício (o tmux recria os #() da barra num refresh-client) não dá salto;
  - cliente de ponte (outra máquina olhando por ssh: TT_PONTE= no ambiente do cliente ou sshd na
    linhagem) nunca é animado: vê o começo do letreiro, parado, até o conteúdo mudar;
  - a janela tem largura fixa em células (emoji conta 2): as divisórias │ não balançam.
"""
import glob
import os
import shutil
import sys
import time
import unicodedata

HOME = os.path.expanduser("~")
CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "tt", "config")
ESTADO = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "tt")
DIR_NOTIFS = os.path.join(ESTADO, "notifs")
DIR_TICKER = os.path.join(HOME, ".cache", "tt-ticker")
RT = os.environ.get("TT_RT") or "/run/user/%d" % os.getuid()
DIR_TRANSF = os.path.join(RT, "tt-transferencias-%d" % os.getuid())
CINZA, TEXTO, AVISO, TRANSF = "#45475a", "#7f849c", "#f9e2af", "#89b4fa"
MARGEM = 20 + 34 + 12  # chips à esquerda, relógio/versão à direita, divisórias e margens


def ler_conf():
    """~/.config/tt/config: chave=valor; a última ocorrência vale (como conf() do tt)."""
    d = {}
    try:
        with open(CONF, encoding="utf-8", errors="replace") as f:
            for l in f:
                l = l.rstrip("\n")
                if "=" in l:
                    k, v = l.split("=", 1)
                    d[k] = v
    except OSError:
        pass
    return d


def faixa_ativa(cfg):
    v = cfg.get("faixa_notif", "")
    if v:
        return v != "0"
    return shutil.which("termux-open-url") is None  # no Termux a tela é baixa: desligada de fábrica


def fontes(cfg):
    v = cfg.get("indicadores", "")
    if v == "0":
        return []
    if not v:
        v = "dolar,frases,noticias"  # ligado de fábrica; indicadores=0 desliga
    return [x for x in v.replace(",", " ").split() if x]


def ler(caminho):
    try:
        with open(caminho, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def linha_letreiro(cfg):
    partes = []
    for f in fontes(cfg):
        partes += [l.strip() for l in ler(os.path.join(DIR_TICKER, f)).splitlines() if l.strip()]
    return " • ".join(partes)


def larg(c):
    """Largura em células: emoji e ideogramas ocupam 2, marcas combinantes e de formato 0."""
    if unicodedata.category(c) in ("Mn", "Me", "Cf"):
        return 0
    if unicodedata.east_asian_width(c) in "WF" or ord(c) >= 0x1F000:
        return 2
    return 1


def cortar(t, orc):
    """Trunca por células, com … dentro do orçamento."""
    tot = 0
    for i, c in enumerate(t):
        tot += larg(c)
        if tot > orc:
            corte = i
            while corte > 0 and sum(larg(x) for x in t[:corte]) + 1 > orc:
                corte -= 1
            return t[:corte].rstrip() + "…"
    return t


def janela(linha, w, off):
    """Recorte de w células da roda (linha + " • " repetida), a partir do caractere off."""
    l = linha + " • "
    n = len(l)
    if n == 0:
        return ""
    ini = off % n
    s = (l * (3 + w // n))[ini:ini + w + 16]
    out, tot = [], 0
    for c in s:
        lc = larg(c)
        if tot + lc > w:
            break
        out.append(c)
        tot += lc
    return "".join(out) + " " * (w - tot)


def esc(t):
    return t.replace("#", "##")  # a linha impressa é um formato do tmux: # literal vira ##


def avisos_frescos(agora, slot):
    """Textos dos avisos nascidos há < slot s, não lidos (sem <id>.lida) e não expirados; até 6."""
    itens = []
    try:
        nomes = sorted(os.listdir(DIR_NOTIFS), reverse=True)
    except OSError:
        return itens
    vistos = 0
    for nome in nomes:
        if nome.endswith(".lida"):
            continue
        vistos += 1
        if vistos > 6:
            break
        if os.path.exists(os.path.join(DIR_NOTIFS, nome + ".lida")):
            continue  # já aberto pelo clique: sai do slot (na central segue, sem negrito)
        campos = ler(os.path.join(DIR_NOTIFS, nome)).split("\n", 1)[0].split("\t")
        if len(campos) < 2:
            continue
        exp, txt = campos[0], campos[1]
        if not exp.isdigit() or int(exp) <= agora:
            continue
        ns = nome[:10]
        if not ns.isdigit() or agora - int(ns) >= slot:
            continue
        itens.append(txt)
    return itens


def pid_vivo(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def humano(b):
    u = "BKMGT"
    i = 0
    b = float(b)
    while b >= 1024 and i < 4:
        b /= 1024
        i += 1
    return "%d%s" % (b, u[i]) if i == 0 else "%.1f%s" % (b, u[i])


def transferencias(agora):
    """Andamento somado dos trabalhos ativos ("⇅ 62% 14M/s", "⇅ 2 · 62% 14M/s"); só leitura."""
    n = st = sf = sx = 0
    for arq in glob.glob(os.path.join(DIR_TRANSF, "*.status")):
        estado = ler(arq).strip()
        if not (estado == "na fila" or estado.startswith("calculando") or estado.startswith("transferindo")):
            continue
        base = arq[:-len(".status")]
        pid = ler(base + ".pid").strip()
        if not (pid.isdigit() and pid_vivo(int(pid))):
            # sem pid ainda, o trabalhador acabou de ser lançado (vale uns segundos); pid morto é
            # trabalho interrompido — quem grava isso no .status é o tt, aqui só não conta
            try:
                idade = agora - os.stat(arq).st_mtime
            except OSError:
                idade = 1e9
            if pid or idade >= 10:
                continue
        n += 1
        prog = ler(base + ".prog").split()
        if len(prog) >= 3 and all(p.isdigit() for p in prog[:3]):
            st += int(prog[0])
            sf += int(prog[1])
            sx += int(prog[2])
    if n == 0:
        return ""
    txt = "%d em andamento" % n
    if st > 0:
        txt = "%d%% %s/s" % (min(99, sf * 100 // st), humano(sx))
        if n > 1:
            txt = "%d · %s" % (n, txt)
    return "⇅ " + txt


def deslocamento(cfg, orc, agora, ponte):
    if ponte:
        return 0
    veloc = cfg.get("ticker_veloc", "")
    try:
        v = float(veloc)
    except ValueError:
        v = 0
    if cfg.get("ticker_rolagem", "") == "continua":
        if v <= 0:
            v = 0.35
        return int(agora) * max(1, round(1 / v))
    if v <= 0:
        v = 6
    return int(int(agora) // v) * orc


def quadro(cfg, cols, ponte, agora):
    orc = max(12, cols - MARGEM)
    try:
        slot = int(os.environ.get("TT_NOTIF_SLOT") or 10)
    except ValueError:
        slot = 10
    frescos = avisos_frescos(int(agora), slot)
    if frescos:
        if cols < 90:
            return ""  # estreito: o sino com o contador, à esquerda, já conta a história
        txt = esc(cortar("  ·  ".join(frescos), orc))
        if cfg.get("aviso_pisca", "") == "1" and int(agora) % 2:
            miolo = txt
        else:
            miolo = "#[bold]%s#[nobold]" % txt
        return "  #[fg=%s]│#[range=user|notifx]#[fg=%s]  %s  #[norange]#[fg=%s]│#[default]  " % (CINZA, AVISO, miolo, CINZA)
    tx = transferencias(agora)
    if tx:
        return "  #[fg=%s]│#[range=user|transferencias]#[fg=%s]  %s  #[norange]#[fg=%s]│#[default]  " % (
            CINZA, TRANSF, esc(cortar(tx, orc)), CINZA)
    linha = linha_letreiro(cfg)
    if not linha:
        return ""
    return "  #[fg=%s]│#[fg=%s]  %s  #[fg=%s]│#[default]  " % (
        CINZA, TEXTO, esc(janela(linha, orc, deslocamento(cfg, orc, agora, ponte))), CINZA)


def e_ponte(pid):
    """TT_PONTE= no ambiente do cliente, ou um sshd na linhagem dele (ponte de outra máquina)."""
    try:
        with open("/proc/%d/environ" % pid, "rb") as f:
            if any(v.startswith(b"TT_PONTE=") for v in f.read().split(b"\0")):
                return True
    except OSError:
        pass
    for _ in range(12):
        if pid <= 1:
            break
        try:
            with open("/proc/%d/comm" % pid) as f:
                if f.read().startswith("sshd"):
                    return True
            with open("/proc/%d/stat" % pid) as f:
                pid = int(f.read().rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            break
    return False


def largura(fd):
    v = os.environ.get("TT_FAIXA_LARGURA", "")
    if v.isdigit():
        return int(v)
    if fd is not None:
        try:
            import fcntl
            import struct
            import termios
            cols = struct.unpack("HHHH", fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\0" * 8))[1]
            if cols > 0:
                return cols
        except OSError:
            pass
    return 80


def emitir(q):
    try:
        os.write(1, (q + "\n").encode("utf-8"))
    except OSError:  # o tmux fechou o cano: o cliente foi embora
        sys.exit(0)


def fluxo(tty, pid):
    ponte = e_ponte(pid)
    fd = None
    try:
        fd = os.open(tty, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
    except OSError:
        pass
    ultimo, repetir, impresso_em = None, False, 0.0
    while pid_vivo(pid):
        cfg = ler_conf()
        if not faixa_ativa(cfg):
            return 0
        agora = time.time()
        q = quadro(cfg, largura(fd), ponte, agora)
        # Sem imprimir por 1 h o tmux dá o #() por abandonado e o recria (format_job_tidy): uma
        # linha igual de tempos em tempos (ponte parada, letreiro desligado) mantém o processo vivo.
        if q != ultimo or repetir or agora - impresso_em > 1500:
            # Uma linha que chega no MESMO segundo em que o tmux criou o processo (ou disparou o
            # redesenho anterior) não dispara outro redesenho; a repetição no segundo seguinte
            # garante que a última mudança seja pintada.
            emitir(q)
            repetir = q != ultimo
            ultimo, impresso_em = q, agora
        agora = time.time()
        time.sleep(max(0.2, 1.05 - agora % 1))  # um tique por segundo, logo após a virada do segundo
    return 0


def main(argv):
    modo = argv[1] if len(argv) > 1 else ""
    if modo == "fluxo" and len(argv) >= 4 and argv[3].isdigit():
        return fluxo(argv[2], int(argv[3]))
    if modo == "quadro":
        cfg = ler_conf()
        cols = int(argv[2]) if len(argv) > 2 and argv[2].isdigit() else largura(None)
        emitir(quadro(cfg, cols, len(argv) > 3 and argv[3] == "ponte", time.time()) if faixa_ativa(cfg) else "")
        return 0
    sys.stderr.write("uso: letreiro-tt.py fluxo TTY PID | quadro [LARGURA [ponte]]\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
