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
  fluxo TTY PID [OCUPADO [COLUNAS]]
                    o que o tt liga na barra (@barra_notifs = "#(… fluxo #{client_tty} #{client_pid})").
                    A largura vem do terminal do próprio cliente (ioctl TIOCGWINSZ): redimensionar não
                    reinicia o processo e cada cliente vê o recorte do seu tamanho.
                    OCUPADO = largura que o tmux mede (#{w:}) das partes esquerda e direita da linha: o
                    slot usa exatamente o que sobra (sem ele, supõe 54).
                    COLUNAS = #{client_width}, usada quando o tty do cliente não abre (ssh).
  quadro [LARGURA]  imprime um quadro e sai (testes, `tt --ticker-quadro`).

Regras (as mesmas que a barra em bash seguia):
  - orçamento = largura − OCUPADO − 12 (divisórias e respiro); abaixo de 8 células o slot some; aviso só com ≥ 90;
  - aviso fresco (nascido há < TT_NOTIF_SLOT s, padrão 10; não lido; não expirado) tem a vez, em
    negrito (aviso_pisca=1 alterna a cada segundo); depois a transferência ativa; depois o letreiro;
  - letreiro: fontes em ~/.cache/tt-ticker/<fonte> (o vigia atualiza com TTL; rede nunca aqui), itens
    separados por " • ", numa roda. O padrão desliza (ticker_rolagem=continua): 1/ticker_veloc colunas
    por segundo (padrão 1/ticker_fps s = 1 coluna por quadro, a ticker_fps=6 quadros/s). Cada #() só
    redesenha a barra 1 vez/s, mas o tmux guarda a última linha lida de cada um: o pintor (fluxo)
    imprime um quadro a cada 1/fps s e fps-1 gatilhos (linhas vazias, 1/s, defasadas) provocam os
    redesenhos entre os segundos. ticker_rolagem=paginas troca de bloco a cada ticker_veloc s (padrão 6);
  - a posição é função da hora, não de um contador: todos os clientes mostram o mesmo trecho e um
    reinício (o tmux recria os #() da barra num refresh-client) não dá salto;
  - cliente de ponte (outra máquina olhando por ssh): anima como os outros — sem redesenho de tela
    inteira o custo é só a barra (~2 KB/s); ticker_ponte=parado devolve o começo do letreiro, parado;
  - a janela tem largura fixa em células (emoji conta 2): as divisórias │ não balançam.
"""
import os
import sys
import time


import glob
import shutil
import unicodedata

HOME = os.path.expanduser("~")
CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "tt", "config")
ESTADO = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "tt")
DIR_NOTIFS = os.path.join(ESTADO, "notifs")
DIR_TICKER = os.path.join(HOME, ".cache", "tt-ticker")
RT = os.environ.get("TT_RT") or "/run/user/%d" % os.getuid()
DIR_TRANSF = os.path.join(RT, "tt-transferencias-%d" % os.getuid())
CINZA, TEXTO, AVISO, TRANSF, FUNDO = "#45475a", "#7f849c", "#f9e2af", "#89b4fa", "#232838"
OCUPADO = 20 + 34  # sem medida do tmux: chips à esquerda + relógio/versão à direita
ENQUADRA = 12      # divisórias │ e respiro dos dois lados do texto do slot


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


def fps_de(cfg):
    """Quadros por segundo do letreiro (ticker_fps, 1 a 10, padrão 6)."""
    try:
        return min(10, max(1, int(cfg.get("ticker_fps", "") or 6)))
    except ValueError:
        return 6


def deslocamento(cfg, orc, agora, ponte, fps=1):
    if ponte and cfg.get("ticker_ponte", "") == "parado":
        return 0
    veloc = cfg.get("ticker_veloc", "")
    try:
        v = float(veloc)
    except ValueError:
        v = 0
    if cfg.get("ticker_rolagem", "") == "paginas":
        if v <= 0:
            v = 6
        return int(int(agora) // v) * orc
    if v <= 0:
        v = 1 / fps  # 1 coluna por quadro: o passo mínimo de um terminal, o mais suave possível
    por_seg = 1 / v
    quadro_n = int(agora * fps)
    if por_seg >= fps:
        return quadro_n * round(por_seg / fps)  # colunas por quadro
    return quadro_n // max(1, round(fps / por_seg))  # quadros por coluna (mais lento que 1/quadro)


def quadro(cfg, cols, ponte, agora, ocupado=OCUPADO, fps=1):
    return _quadro(cfg, cols, ponte, agora, ocupado, fps)[0]


def _quadro(cfg, cols, ponte, agora, ocupado=OCUPADO, fps=1):
    """(texto, animado): animado = o letreiro que desliza quadro a quadro (aviso, transferência e
    páginas só mudam de segundo em segundo)."""
    # ocupado = células que o tmux gasta com as partes esquerda e direita da linha (medidas por ele,
    # #{w:}); o slot ocupa todo o resto, menos as divisórias e o respiro.
    orc = cols - ocupado - ENQUADRA
    if orc < 8:
        return "", False  # não sobra lugar para um letreiro legível: o slot some e as pontas ficam inteiras
    orc = min(orc, 400)
    try:
        slot = int(os.environ.get("TT_NOTIF_SLOT") or 10)
    except ValueError:
        slot = 10
    frescos = avisos_frescos(int(agora), slot)
    if frescos:
        if cols < 90:
            return "", False  # estreito: o sino com o contador, à esquerda, já conta a história
        txt = esc(cortar("  ·  ".join(frescos), orc))
        if cfg.get("aviso_pisca", "") == "1" and int(agora) % 2:
            miolo = txt
        else:
            miolo = "#[bold]%s#[nobold]" % txt
        return "  #[fg=%s]│#[range=user|notifx]#[fg=%s]  %s  #[norange]#[fg=%s]│#[default]#[bg=%s]  " % (CINZA, AVISO, miolo, CINZA, FUNDO), False
    tx = transferencias(agora)
    if tx:
        return "  #[fg=%s]│#[range=user|transferencias]#[fg=%s]  %s  #[norange]#[fg=%s]│#[default]#[bg=%s]  " % (
            CINZA, TRANSF, esc(cortar(tx, orc)), CINZA, FUNDO), False
    linha = linha_letreiro(cfg)
    if not linha:
        return "", False
    animado = cfg.get("ticker_rolagem", "") != "paginas" and not (ponte and cfg.get("ticker_ponte", "") == "parado")
    # (#[default] volta ao status-style, de fundo escuro: o fundo da faixa é devolvido logo depois)
    return "  #[fg=%s]│#[fg=%s]  %s  #[fg=%s]│#[default]#[bg=%s]  " % (
        CINZA, TEXTO, esc(janela(linha, orc, deslocamento(cfg, orc, agora, ponte, fps))), CINZA, FUNDO), animado


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


def largura(fd, tmux=0):
    """Colunas do cliente: o ioctl no tty dele é a medida exata e acompanha redimensionamento sem
    reiniciar nada; mas o tty de um cliente por ssh (Tailscale SSH) pertence ao root e o tmux, que roda
    como o usuário, não consegue abri-lo — aí vale a largura que o próprio tmux passou na linha de comando
    (#{client_width}); só sem as duas é que cai nas 80 colunas."""
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
    return tmux if tmux > 0 else 80


def emitir(q):
    try:
        os.write(1, (q + "\n").encode("utf-8"))
    except OSError:  # o tmux fechou o cano: o cliente foi embora
        sys.exit(0)


def substituido(tty, pid):
    """True se existe outro `letreiro-tt.py fluxo` MAIS NOVO para o mesmo cliente. O tmux identifica o
    #() pela linha de comando inteira: ao redimensionar (a largura vai nela) ele cria um processo novo
    e só aposenta o antigo depois de 1 h. Quem foi substituído sai, para não acumular."""
    def inicio(p):
        with open("/proc/%s/stat" % p) as f:
            return (int(f.read().rsplit(")", 1)[1].split()[19]), int(p))
    meu = inicio(os.getpid())
    for p in os.listdir("/proc"):
        if not p.isdigit() or int(p) == os.getpid():
            continue
        try:
            with open("/proc/%s/cmdline" % p, "rb") as f:
                a = f.read().split(b"\0")
            if len(a) >= 6 and a[2].endswith(b"letreiro-tt.py") and a[3] == b"fluxo" and a[4] == tty.encode() and a[5] == str(pid).encode() and inicio(p) > meu:
                return True
        except (OSError, ValueError, IndexError):
            continue
    return False


def marca_anim(pid):
    """Arquivo-marca do pintor: enquanto o letreiro desliza ele o toca; os gatilhos só disparam com ele."""
    d = RT if os.path.isdir(RT) else "/tmp"
    return os.path.join(d, "tt-letreiro-%d.anim" % pid)


def fluxo(tty, pid, ocupado=OCUPADO, cols_tmux=0, fps=1):
    """O pintor: imprime o quadro do letreiro. O tmux só redesenha a barra 1 vez por segundo por #(),
    mas guarda a ÚLTIMA linha lida de cada um na hora: com fps > 1 ele imprime um quadro novo a cada
    1/fps s e os gatilhos (fps-1 #() quase vazios, ver gatilho-tt.sh) provocam os redesenhos entre os
    segundos — cada um logo depois de um quadro novo, de modo que a barra nunca mostra um quadro velho."""
    ponte = e_ponte(pid)
    fd = None
    try:
        fd = os.open(tty, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
    except OSError:
        pass
    marca = marca_anim(pid)
    ultimo, repetir, impresso_em, ciclo, tocado = None, False, 0.0, 0, 0.0
    try:
        while pid_vivo(pid):
            ciclo += 1
            if ciclo % (5 * max(1, fps)) == 0 and substituido(tty, pid):
                return 0
            cfg = ler_conf()
            if not faixa_ativa(cfg):
                return 0
            agora = time.time()
            q, anim = _quadro(cfg, largura(fd, cols_tmux), ponte, agora, ocupado, fps)
            # Sem imprimir por 1 h o tmux dá o #() por abandonado e o recria (format_job_tidy): uma
            # linha igual de tempos em tempos (ponte parada, letreiro desligado) mantém o processo vivo.
            if q != ultimo or repetir or agora - impresso_em > 1500:
                # Uma linha que chega no MESMO segundo em que o tmux criou o processo (ou disparou o
                # redesenho anterior) não dispara outro redesenho; a repetição no segundo seguinte
                # garante que a última mudança seja pintada.
                emitir(q)
                repetir = q != ultimo and not (anim and fps > 1)
                ultimo, impresso_em = q, agora
            if anim and fps > 1:
                if agora - tocado >= 1:
                    try:
                        with open(marca, "w") as f:  # o gatilho (bash) lê a hora daqui
                            f.write("%d\n" % agora)
                    except OSError:
                        pass
                    tocado = agora
                # próximo quadro: um fio depois da fronteira, para o índice do quadro já ter virado
                espera = (int(agora * fps) + 1) / fps - time.time() + 0.002
            else:
                if tocado:
                    try:
                        os.unlink(marca)
                    except OSError:
                        pass
                    tocado = 0.0
                espera = 1.05 - agora % 1  # um tique por segundo, logo após a virada do segundo
            time.sleep(max(0.01 if anim and fps > 1 else 0.2, espera))
    finally:
        try:
            os.unlink(marca)
        except OSError:
            pass
    return 0


def main(argv):
    modo = argv[1] if len(argv) > 1 else ""
    if modo == "fluxo" and len(argv) >= 4 and argv[3].isdigit():
        n = lambda i, d: int(argv[i]) if len(argv) > i and argv[i].isdigit() else d
        return fluxo(argv[2], int(argv[3]), n(4, OCUPADO), n(5, 0), n(6, 1))
    if modo == "quadro":
        cfg = ler_conf()
        cols = int(argv[2]) if len(argv) > 2 and argv[2].isdigit() else largura(None)
        emitir(quadro(cfg, cols, len(argv) > 3 and argv[3] == "ponte", time.time(), fps=fps_de(cfg)) if faixa_ativa(cfg) else "")
        return 0
    sys.stderr.write("uso: letreiro-tt.py fluxo TTY PID [OCUPADO [COLUNAS [FPS]]] | quadro [LARGURA [ponte]]\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
