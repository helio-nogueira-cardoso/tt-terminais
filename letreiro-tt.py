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
  clique PID X      o que fazer com um clique na coluna X do terminal de PID: imprime "acao<TAB>alvo"
                    (url | copiar | painel | pausa | nada). Usa a geometria que o `fluxo` deixou em
                    $TT_RT/tt-letreiro-PID.geo e o mesmo tempo do quadro: o item sob o mouse é o que se vê.
  pausar            alterna a pausa do letreiro (congela o quadro; vale nesta máquina).

Regras (as mesmas que a barra em bash seguia):
  - orçamento = largura − OCUPADO − 12 (divisórias e respiro); abaixo de 8 células o slot some; aviso só com ≥ 90;
  - aviso fresco (nascido há < TT_NOTIF_SLOT s, padrão 10; não lido; não expirado) tem a vez, em
    negrito (aviso_pisca=1 alterna a cada segundo); depois a transferência ativa; depois o letreiro;
  - letreiro: fontes em ~/.cache/tt-ticker/<fonte> (o vigia atualiza com TTL, via letreiro-fontes.py;
    rede nunca aqui), na ordem/peso de _roda.json (a lista compilada das fontes ativas desta máquina; sem
    ela, vale indicadores= como sempre valeu), itens separados por ticker_separador (" • "), numa roda.
    O texto da rede já chega limpo (sem escapes de terminal nem #[ #( ); aqui o # ainda é dobrado) e as
    cores de alta/baixa vêm como marcas \x01-\x04 no cache. O padrão desliza (ticker_rolagem=continua): 1/ticker_veloc colunas
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
import json
import re
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
ESTILOS = {"alta": "#a6e3a1", "baixa": "#f38ba8", "neutra": "#9399b2", "velho": "#585b70", "erro": "#fab387"}
MARC = {"\x01": "alta", "\x02": "baixa", "\x03": "neutra", "\x04": None}  # marcas de cor do cache
ARQ_RODA = os.path.join(DIR_TICKER, "_roda.json")
PAUSA = os.path.join(RT, "tt-letreiro-pausa")
LADO = 5           # "  │  " antes do texto do slot (2 espaços, divisória, 2 espaços)
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


_ESC = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?|\x1b[PX^_][^\x1b]*(?:\x1b\\)?|\x1b\[[0-?]*[ -/]*[@-~]|\x1b[ -/]*[0-~]|\x9b[0-?]*[ -/]*[@-~]")
_CTRL = re.compile(r"[\x00\x05-\x1f\x7f-\x9f]")


def limpa(l):
    """Defesa em profundidade: o cache já vem limpo do letreiro-fontes.py, mas um arquivo adulterado (ou de
    uma versão antiga) não pode injetar escape de terminal nem sintaxe do tmux (o # vira ## ao desenhar)."""
    return _CTRL.sub("", _ESC.sub("", l)).strip()


_mod_cache = []


def modulo():
    """letreiro-fontes.py, carregado só quando preciso (janelas de exibição); sem ele, o item aparece sempre."""
    if not _mod_cache:
        try:
            import importlib.util
            sp = importlib.util.spec_from_file_location("letreiro_fontes", os.path.join(os.path.dirname(os.path.abspath(__file__)), "letreiro-fontes.py"))
            m = importlib.util.module_from_spec(sp)
            sp.loader.exec_module(m)
            _mod_cache.append(m)
        except Exception:
            _mod_cache.append(None)
    return _mod_cache[0]


_roda_cache = {"mtime": None, "dados": None}


def carregar_roda():
    """_roda.json (compilado pelo letreiro-fontes.py) ou None. Relido só quando o arquivo muda."""
    try:
        mt = os.stat(ARQ_RODA).st_mtime_ns
    except OSError:
        _roda_cache.update(mtime=None, dados=None)
        return None
    if _roda_cache["mtime"] != mt:
        try:
            with open(ARQ_RODA, encoding="utf-8") as f:
                _roda_cache.update(mtime=mt, dados=json.load(f))
        except (OSError, ValueError):
            _roda_cache.update(mtime=mt, dados=None)
    return _roda_cache["dados"]


def ligado(cfg):
    return cfg.get("ticker_ligado", "1") != "0"


def entradas_roda(cfg):
    """[(nome, entrada)] na ordem manual. Sem _roda.json (antes da 1ª atualização ou versão antiga): indicadores=."""
    if not ligado(cfg):
        return []
    r = carregar_roda()
    if r is not None and isinstance(r.get("itens"), list):
        return [(e.get("nome", ""), e) for e in r["itens"] if e.get("nome")]
    return [(f, {"nome": f, "peso": 1, "cache_max": 0, "se_faltar": "ultimo"}) for f in fontes(cfg)]


def _janela_ok(e, agora, cfg):
    if not (e.get("mostrar_dias") or e.get("mostrar_horas")):
        return True
    m = modulo()
    if m is None:
        return True
    try:
        return m.na_janela(agora, e.get("mostrar_dias", ""), e.get("mostrar_horas", ""), cfg)
    except Exception:
        return True


def linhas_da_fonte(nome, e, agora):
    """[(texto com marcas, estilo base)] — aplica a política de dado velho/ausente (se_faltar, cache_max)."""
    arq = os.path.join(DIR_TICKER, nome)
    try:
        st = os.stat(arq)
    except OSError:
        st = None
    linhas = [limpa(l) for l in ler(arq).splitlines()] if st else []
    linhas = [l for l in linhas if l]
    cm = int(e.get("cache_max", 0) or 0)
    velho = bool(st) and cm > 0 and (agora - st.st_mtime) / 60 > cm
    sem_dado = st is None
    if not sem_dado and not velho:
        return [(capitalizar_inicio(l), None) for l in linhas]
    pol = e.get("se_faltar", "ultimo")
    if pol == "esconder":
        return []
    if pol == "erro":
        nome_tela = e.get("rotulo") or nome
        return [(capitalizar_inicio("⚠ %s: sem dado atual" % nome_tela), "erro")]
    if not linhas:
        return []
    return [(capitalizar_inicio("⏳ " + linhas[0]), "velho")] + [(capitalizar_inicio(l), "velho") for l in linhas[1:]]


def capitalizar_inicio(texto):
    """Capitaliza a primeira letra visível do item, preservando ícones, espaços e marcas de cor."""
    for i, c in enumerate(texto):
        if c.isalpha():
            return texto[:i] + c.upper() + texto[i + 1:]
    return texto


class Roda:
    """A roda do letreiro como células (caractere, estilo) + a que fonte/linha cada trecho pertence.
    `fim_roda` é o separador que fecha a volta (conteúdo + separador, repetidos, é a roda)."""
    def __init__(self):
        self.cel = []
        self.fim_roda = []
        self.segs = []   # (início, fim, nome, índice da linha na fonte)

    def __len__(self):
        return len(self.cel)


def _celulas(texto, base):
    out, est = [], base
    for c in texto:
        if c in MARC:
            est = MARC[c] or base
            continue
        out.append((c, est))
    return out


def montar_roda(cfg, agora):
    sep = cfg.get("ticker_separador", " • ") or " • "
    ent = entradas_roda(cfg)
    # ticker_ordem: sequencial (a ordem das fontes; "manual" é o nome antigo), aleatoria (mistura as ENTRADAS de todas
    # as fontes, não só a ordem delas) ou peso
    ordem = cfg.get("ticker_ordem", "sequencial")
    if ordem == "peso":
        ent = sorted(ent, key=lambda x: -int(x[1].get("peso", 1) or 1))
    voltas = max([int(e.get("peso", 1) or 1) for _n, e in ent] or [1])
    cor_ok = cfg.get("ticker_cor", "1") != "0"
    itens = []   # (chave de sorteio, nome da fonte, índice da linha, células), na ordem sequencial
    cache = {}
    for k in range(voltas):
        for nome, e in ent:
            if int(e.get("peso", 1) or 1) <= k or not _janela_ok(e, agora, cfg):
                continue
            if nome not in cache:
                cache[nome] = linhas_da_fonte(nome, e, agora)
            for i, (txt, base) in enumerate(cache[nome]):
                cel = _celulas(txt, base)
                if not cor_ok:
                    cel = [(c, None if est in ("alta", "baixa", "neutra") else est) for c, est in cel]
                if not cel:
                    continue
                itens.append(("%d:%s:%d:%d" % (int(agora // 3600), nome, i, k), nome, i, cel))
    if ordem == "aleatoria":
        # A posição de cada entrada sai de um hash da hora + fonte + linha + volta, não do sorteio da lista inteira:
        # quando UMA fonte atualiza (entra ou sai manchete, muda um valor), as outras entradas ficam onde estavam e o
        # letreiro não "pula" no meio da rolagem. A ordem muda sozinha a cada hora.
        import hashlib
        itens.sort(key=lambda x: hashlib.md5(x[0].encode("utf-8")).digest())
    r = Roda()
    for _chave, nome, i, cel in itens:
        if r.cel:
            r.cel += [(c, None) for c in sep]
        r.segs.append((len(r.cel), len(r.cel) + len(cel), nome, i))
        r.cel += cel
    r.fim_roda = [(c, None) for c in sep] if r.cel else []
    return r


def linha_letreiro(cfg):
    """O letreiro como texto simples (sem cores): serve ao diagnóstico e a quem importa este módulo."""
    return "".join(c for c, _e in montar_roda(cfg, time.time()).cel)


def larg(c):
    """Largura em células: emoji e ideogramas ocupam 2, marcas combinantes e de formato 0."""
    if c in MARC:
        return 0
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


def fatia(roda, w, off):
    """As células visíveis de uma janela de w colunas da roda (repetida), a partir do índice off:
    [(índice na roda, caractere, estilo, largura)] e o total de colunas ocupadas."""
    base = roda.cel + roda.fim_roda
    if not base:
        return [], 0
    ini = off % len(base)
    vis, tot = [], 0
    pos = ini
    for _ in range(w + 16):
        c, est = base[pos % len(base)]
        lc = larg(c)
        if tot + lc > w:
            break
        vis.append((pos % len(base), c, est, lc))
        tot += lc
        pos += 1
    return vis, tot


def janela_roda(roda, w, off):
    """Como janela(), para a roda de células: devolve o texto do slot já em formato tmux (cores por
    trecho, # dobrado) preenchido até w colunas."""
    vis, tot = fatia(roda, w, off)
    out, est_ant, buf = [], None, []

    def fecha():
        if buf:
            t = esc("".join(buf))
            out.append(t if est_ant is None else "#[fg=%s]%s#[fg=%s]" % (ESTILOS[est_ant], t, TEXTO))
            buf.clear()
    for _i, c, est, _l in vis:
        if est != est_ant:
            fecha()
            est_ant = est
        buf.append(c)
    fecha()
    return "".join(out) + " " * (w - tot)


def pausado():
    """Epoch em que o letreiro foi congelado (clique), ou 0."""
    try:
        return float(ler(PAUSA).strip() or 0)
    except ValueError:
        return 0.0


def alternar_pausa():
    if pausado():
        try:
            os.unlink(PAUSA)
        except OSError:
            pass
        return "continua"
    try:
        os.makedirs(os.path.dirname(PAUSA), exist_ok=True)
        with open(PAUSA, "w") as f:
            f.write("%.3f\n" % time.time())
    except OSError:
        return "erro"
    return "pausado"


def economia_estatica(cfg):
    """Modo economia: com a bateria baixa (e sem carregar) o letreiro vira páginas (não anima)."""
    e = cfg.get("ticker_economia", "auto")
    if e == "0" or (e == "auto" and shutil.which("termux-open-url") is None):
        return False
    try:
        with open(os.path.join(DIR_TICKER, "_energia")) as f:
            pct, carregando, quando = f.read().split()
        return (time.time() - float(quando) < 1800 and int(pct) < int(cfg.get("ticker_bateria_min", "20") or 20)
                and carregando == "0")
    except (OSError, ValueError):
        return False


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
        if len(campos) > 3 and campos[3] == "sino":
            continue  # aviso de agente: só no contador do 🔔 e na central, nunca piscando no slot
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
    """Quadros por segundo do letreiro (ticker_fps, 1 a 20, padrão 6). O teto existe porque cada quadro além do
    primeiro custa um gatilho (um processo bash por cliente); remover o teto não é seguro."""
    try:
        return min(20, max(1, int(cfg.get("ticker_fps", "") or 6)))
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
    try:
        maxima = int(cfg.get("ticker_largura", "") or 400)
    except ValueError:
        maxima = 400
    orc = min(orc, max(8, min(maxima, 400)))
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
    parado = pausado()
    t_roda = parado or agora          # pausado: o tempo congela e o quadro fica igual
    roda = montar_roda(cfg, t_roda)
    if not len(roda):
        return "", False
    cfg_rolagem = dict(cfg, ticker_rolagem="paginas") if economia_estatica(cfg) else cfg
    animado = (cfg_rolagem.get("ticker_rolagem", "") != "paginas" and not parado
               and not (ponte and cfg.get("ticker_ponte", "") == "parado"))
    corpo = janela_roda(roda, orc, deslocamento(cfg_rolagem, orc, t_roda, ponte, fps))
    # (#[default] volta ao status-style, de fundo escuro: o fundo da faixa é devolvido logo depois)
    return "  #[fg=%s]│#[range=user|letreiro]#[fg=%s]  %s  #[norange]#[fg=%s]│#[default]#[bg=%s]  " % (
        CINZA, TEXTO, corpo, CINZA, FUNDO), animado


def item_sob_mouse(cfg, geo, x, agora, ponte=False):
    """(nome da fonte, índice da linha) do item que está na coluna x do terminal, ou None."""
    orc = geo["cols"] - geo["ocupado"] - ENQUADRA
    try:
        maxima = int(cfg.get("ticker_largura", "") or 400)
    except ValueError:
        maxima = 400
    orc = min(orc, max(8, min(maxima, 400)))
    if orc < 8:
        return None
    rel = x - geo["esq"] - LADO
    if rel < 0 or rel >= orc:
        return None
    t_roda = pausado() or agora
    roda = montar_roda(cfg, t_roda)
    cfg_rolagem = dict(cfg, ticker_rolagem="paginas") if economia_estatica(cfg) else cfg
    vis, _tot = fatia(roda, orc, deslocamento(cfg_rolagem, orc, t_roda, ponte, geo.get("fps", 1)))
    col = 0
    base_n = len(roda.cel)
    for i, _c, _e, lc in vis:
        if col <= rel < col + max(lc, 1):
            if i >= base_n:
                return None            # separador final da volta
            for ini, fim, nome, idx in roda.segs:
                if ini <= i < fim:
                    return nome, idx
            return None                # separador entre itens
        col += lc
    return None


def acao_clique(cfg, geo, x, agora, ponte=False):
    """'acao<TAB>alvo' para um clique na coluna x: a ação do item sob o mouse (cadastrada na fonte) ou,
    sem ação, alternar a pausa (ticker_pausa=nunca desliga)."""
    alvo = item_sob_mouse(cfg, geo, x, agora, ponte)
    if alvo is None:
        return "nada\t"
    nome, idx = alvo
    try:
        with open(os.path.join(DIR_TICKER, nome + ".itens"), encoding="utf-8") as f:
            itens = json.load(f)
        it = itens[idx]
        if it.get("acao") in ("url", "copiar", "painel") and it.get("alvo"):
            return "%s\t%s" % (it["acao"], str(it["alvo"]).replace("\t", " ").replace("\n", " "))
        if it.get("acao") == "bloqueado":
            return "nada\t"          # ação configurada mas inválida (ex.: javascript:): não faz nada, nem pausa
    except (OSError, ValueError, IndexError, TypeError):
        pass
    return ("pausa\t" if cfg.get("ticker_pausa", "clique") != "nunca" else "nada\t")


def tmux_para_ansi(q):
    """Formato do tmux (#[fg=#rrggbb] …) → ANSI de 24 bits, para mostrar o quadro num terminal comum."""
    def troca(m):
        out = []
        for p in m.group(1).split(","):
            p = p.strip()
            if p.startswith("fg=#") or p.startswith("bg=#"):
                h = p[4:]
                if len(h) == 6:
                    out.append("\033[%d;2;%d;%d;%dm" % (38 if p[0] == "f" else 48, int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)))
            elif p == "bold":
                out.append("\033[1m")
            elif p in ("nobold",):
                out.append("\033[22m")
            elif p == "default":
                out.append("\033[0m")
        return "".join(out)
    return re.sub(r"#\[([^\]]*)\]", troca, q).replace("##", "#") + "\033[0m"


TEM_PROC = os.path.isdir("/proc/self")


def e_ponte(pid):
    """TT_PONTE= no ambiente do cliente, ou um sshd na linhagem dele (ponte de outra máquina). Sem /proc (macOS) quem
    decide é o shell do tt, uma vez, na partida (tt --e-ponte): chega em TT_LETREIRO_PONTE. Este processo não lança nada."""
    if not TEM_PROC:
        return os.environ.get("TT_LETREIRO_PONTE") == "1"
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
    if not TEM_PROC:
        # sem /proc: o processo mais novo do cliente grava o token dele num arquivo (marca_token); o mais velho vê o token trocado
        try:
            with open(arq_token(pid)) as f:
                return f.read().strip() != TOKEN
        except OSError:
            return False

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


TOKEN = "%d.%d" % (os.getpid(), time.time_ns())


def arq_token(pid):
    d = RT if os.path.isdir(RT) else "/tmp"
    return os.path.join(d, "tt-letreiro-%d.tok" % pid)


def marca_token(pid):
    """Sem /proc: este é o pintor mais novo do cliente PID; quem leu outro token aí foi substituído."""
    try:
        with open(arq_token(pid), "w") as f:
            f.write(TOKEN)
    except OSError:
        pass


def marca_anim(pid):
    """Arquivo-marca do pintor: enquanto o letreiro desliza ele o toca; os gatilhos só disparam com ele."""
    d = RT if os.path.isdir(RT) else "/tmp"
    return os.path.join(d, "tt-letreiro-%d.anim" % pid)


def arq_geo(pid):
    return os.path.join(RT if os.path.isdir(RT) else "/tmp", "tt-letreiro-%s.geo" % pid)


def grava_geo(pid, geo):
    """Geometria do slot para o clique (ver acao_clique): só quando muda (ou quando o arquivo sumiu)."""
    try:
        tmp = "%s.%d" % (arq_geo(pid), os.getpid())
        with open(tmp, "w") as f:
            json.dump(geo, f)
        os.replace(tmp, arq_geo(pid))
    except OSError:
        pass


def fluxo(tty, pid, ocupado=OCUPADO, cols_tmux=0, fps=1, esq=0):
    """O pintor: imprime o quadro do letreiro. O tmux só redesenha a barra 1 vez por segundo por #(),
    mas guarda a ÚLTIMA linha lida de cada um na hora: com fps > 1 ele imprime um quadro novo a cada
    1/fps s e os gatilhos (fps-1 #() quase vazios, ver gatilho-tt.sh) provocam os redesenhos entre os
    segundos — cada um logo depois de um quadro novo, de modo que a barra nunca mostra um quadro velho."""
    ponte = e_ponte(pid)
    if not TEM_PROC:
        marca_token(pid)
    fd = None
    try:
        fd = os.open(tty, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
    except OSError:
        pass
    marca = marca_anim(pid)
    ultimo, repetir, impresso_em, ciclo, tocado = None, False, 0.0, 0, 0.0
    geo_ant, trocado = None, False
    try:
        while pid_vivo(pid):
            ciclo += 1
            if ciclo % (5 * max(1, fps)) == 0 and substituido(tty, pid):
                trocado = True
                return 0
            cfg = ler_conf()
            if not faixa_ativa(cfg):
                return 0
            agora = time.time()
            cols = largura(fd, cols_tmux)
            geo = {"cols": cols, "ocupado": ocupado, "esq": esq, "fps": fps, "ponte": ponte}
            if geo != geo_ant or not os.path.exists(arq_geo(pid)):
                grava_geo(pid, geo)
                geo_ant = geo
            q, anim = _quadro(cfg, cols, ponte, agora, ocupado, fps)
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
        # Substituído por um desenhista mais novo do MESMO cliente: a geometria é dele agora (mesmo
        # arquivo); apagá-la deixaria o clique mudo até o tamanho da tela mudar.
        for arq in (marca,) if trocado else (marca, arq_geo(pid)):
            try:
                os.unlink(arq)
            except OSError:
                pass
    return 0


def main(argv):
    modo = argv[1] if len(argv) > 1 else ""
    if modo == "fluxo" and len(argv) >= 4 and argv[3].isdigit():
        n = lambda i, d: int(argv[i]) if len(argv) > i and argv[i].isdigit() else d
        return fluxo(argv[2], int(argv[3]), n(4, OCUPADO), n(5, 0), n(6, 1), n(7, 0))
    if modo == "quadro":
        cfg = ler_conf()
        cols = int(argv[2]) if len(argv) > 2 and argv[2].isdigit() else largura(None)
        if len(argv) > 4 and argv[4] == "ansi":   # pré-visualização no painel: o slot ocupa a largura toda
            q = quadro(cfg, cols, False, time.time(), ocupado=0, fps=fps_de(cfg))
            emitir(tmux_para_ansi(q) if q else "")
            return 0
        emitir(quadro(cfg, cols, len(argv) > 3 and argv[3] == "ponte", time.time(), fps=fps_de(cfg)) if faixa_ativa(cfg) else "")
        return 0
    if modo == "pausar":
        print(alternar_pausa())
        return 0
    if modo == "clique" and len(argv) >= 4 and argv[2].isdigit() and argv[3].lstrip("-").isdigit():
        cfg = ler_conf()
        try:
            with open(arq_geo(argv[2])) as f:
                geo = json.load(f)
        except (OSError, ValueError):
            print("nada\t")
            return 0
        agora = float(os.environ.get("TT_AGORA") or time.time())
        print(acao_clique(cfg, geo, int(argv[3]), agora, bool(geo.get("ponte"))))
        return 0
    sys.stderr.write("uso: letreiro-tt.py fluxo TTY PID [OCUPADO [COLUNAS [FPS [ESQ]]]] | quadro [LARGURA [ponte]] | clique PID X | pausar\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
