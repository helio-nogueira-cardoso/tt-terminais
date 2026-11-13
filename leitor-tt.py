#!/usr/bin/env python3
# leitor-tt.py — leitor rápido do tt: uma palavra por vez, sempre no mesmo lugar da tela (RSVP).
#
# Só biblioteca padrão (roda também no Termux). Três partes:
#   1. extração: txt, md, html, epub, docx, odt, fb2, rtf e pdf (pdftotext ou mutool) viram capítulos e parágrafos;
#   2. biblioteca: cada livro é uma pasta em ~/.local/share/tt-leitor/livros/ID (ID = 12 hex do sha256 do arquivo),
#      com o original, o texto extraído e o estado da leitura; o `tt --leitor-sync` troca tudo entre as máquinas
#      (inventario → mesclar → pedir → empacotar → aplicar), a posição mais nova vence;
#   3. tela: abas Biblioteca, Arquivos (pastas daqui e das outras máquinas) e Máquinas; leitura (ponto de foco fixo,
#      letras grandes desenhadas com o atlas leitor-fontes.bin, respiros com marca entre parágrafos, títulos e
#      capítulos), ajustes, índice, marcadores, busca e atalhos; teclado e mouse/toque.
#
# Uso (o tt chama; ver `tt --help`):
#   leitor-tt.py                       biblioteca
#   leitor-tt.py ler ARQUIVO|ID|-      abre (acrescenta à biblioteca se for arquivo; "-" lê o stdin)
#   leitor-tt.py adicionar ARQUIVO…    só acrescenta; imprime "id<TAB>título"
#   leitor-tt.py listar [--tsv]        os livros: id, %, palavras, título, última leitura
#   leitor-tt.py remover ID            apaga daqui e, pela lápide, das outras máquinas
#   leitor-tt.py extrair ARQUIVO       o texto extraído, sem guardar
#   leitor-tt.py estado                resumo (livros, onde estão os originais)
#   leitor-tt.py posicao ID [N|N%]     lê ou define a posição
#   leitor-tt.py quadro ID …           um quadro em texto puro (testes)
#   leitor-tt.py atalhos               a tela de atalhos, sozinha
#   leitor-tt.py ls [PASTA]            uma pasta em JSON: subpastas e arquivos legíveis (aba Arquivos; "@recentes")
#   leitor-tt.py rede-nota RÓTULO ok|pulada|falhou   como acabou a troca com a máquina (aba Máquinas)
#   leitor-tt.py inventario | mesclar ARQ | pedir ARQ [--enviar] [--so ID] | empacotar | aplicar   (sincronização)
#   leitor-tt.py fontes | fontes-gerar SAÍDA                                                       (atlas de letras)
import base64
import gzip
import hashlib
import html
import io
import json
import os
import posixpath
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
import unicodedata
import zipfile
import zlib
from html.parser import HTMLParser
from urllib.parse import unquote
from xml.etree import ElementTree as ET

AQUI = os.path.dirname(os.path.abspath(__file__))
CASA = os.path.expanduser("~")
DIR = os.environ.get("TT_LEITOR_DIR") or os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(CASA, ".local", "share"), "tt-leitor")
CONF_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(CASA, ".config"), "tt")
PREFS = os.path.join(CONF_DIR, "leitor.json")
LIVROS = os.path.join(DIR, "livros")
LAPIDES = os.path.join(DIR, "lapides.json")
MAQUINAS = os.path.join(DIR, "maquinas")
ATLAS = os.environ.get("TT_LEITOR_FONTES") or os.path.join(AQUI, "leitor-fontes.bin")
ID_RE = re.compile(r"^[0-9a-f]{12}$")
FORMATOS = ("txt", "md", "markdown", "text", "html", "htm", "xhtml", "epub", "docx", "odt", "fb2", "rtf", "pdf")
MAX_META = 1 << 20
MAX_TEXTO = 300 << 20
MAX_ORIGINAL = 4 << 30


class Erro(Exception):
    pass


def maquina():
    m = os.environ.get("TT_MAQUINA") or os.environ.get("TT_MACHINE")
    if not m:
        try:
            for linha in open(os.path.join(CONF_DIR, "config"), encoding="utf-8", errors="replace"):
                if linha.startswith("nome="):
                    m = linha[5:].strip()
        except OSError:
            pass
    if not m:
        import socket
        m = socket.gethostname().split(".")[0]
    return re.sub(r"[^\w.-]", "-", m.replace("_", "-")) or "maquina"


def agora_ms():
    return int(time.time() * 1000)


def gravar(caminho, dados):
    """Grava de uma vez (temporário ao lado + troca): quem lê nunca vê um arquivo pela metade."""
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    if isinstance(dados, str):
        dados = dados.encode("utf-8")
    fd, tmp = tempfile.mkstemp(prefix=".tmp-", dir=os.path.dirname(caminho))
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(dados)
        os.replace(tmp, caminho)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def ler_json(caminho, padrao=None):
    try:
        with open(caminho, encoding="utf-8") as f:
            v = json.load(f)
        return v if isinstance(v, type(padrao)) or padrao is None else padrao
    except (OSError, ValueError):
        return padrao


def gravar_json(caminho, valor):
    gravar(caminho, json.dumps(valor, ensure_ascii=False, sort_keys=True, indent=1) + "\n")


# --- Extração ---------------------------------------------------------------------------------------------------------

_ESPACOS = re.compile(r"[ \t\u00a0\u2000-\u200a\u202f\u205f\u3000]+")
_INVISIVEIS = re.compile("[\u00ad\u200b-\u200d\u2060\ufeff]")
_FIM_FRASE = ".!?…:;\"”’»)]"


def limpar(texto):
    texto = unicodedata.normalize("NFC", _INVISIVEIS.sub("", texto))
    return _ESPACOS.sub(" ", texto.replace("\r", " ").replace("\n", " ")).strip()


def decodificar(dados):
    if dados[:3] == b"\xef\xbb\xbf":
        return dados[3:].decode("utf-8", "replace")
    if dados[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return dados.decode("utf-16", "replace")
    try:
        return dados.decode("utf-8")
    except UnicodeDecodeError:
        return dados.decode("cp1252", "replace")


_CAP_RE = re.compile(r"^(cap[ií]tulo|chapter|parte|part|livro|book|pr[oó]logo|ep[ií]logo|pref[aá]cio|introdu[cç][aã]o)\b.{0,70}$", re.I)


def blocos_de_texto(texto, juntar_soltos=False, markdown=False):
    """Linhas → parágrafos. Com linhas em branco, cada bloco é um parágrafo (as quebras de dentro são da margem, e a
    palavra partida por hífen no fim da linha volta a ser uma); sem nenhuma, cada linha é um parágrafo."""
    texto = texto.replace("\r\n", "\n").replace("\r", "\n")
    linhas = texto.split("\n")
    tem_branco = any(not l.strip() for l in linhas[:-1]) and any(
        linhas[i].strip() and linhas[i + 1].strip() for i in range(len(linhas) - 1))
    blocos = []
    if tem_branco:
        atual = []
        for l in linhas + [""]:
            if l.strip():
                if markdown and atual and re.match(r"\s*([-*+]|\d+[.)])\s+|#{1,6}\s|>", l):
                    blocos.append(" ".join(atual))  # item de lista, título ou citação começa parágrafo novo
                    atual = []
                atual.append(l.strip())
                continue
            if atual:
                p = atual[0]
                for seg in atual[1:]:
                    if p.endswith("-") and len(p) > 1 and p[-2].isalpha() and seg[:1].islower():
                        p = p[:-1] + seg
                    else:
                        p += " " + seg
                blocos.append(p)
                atual = []
    else:
        blocos = [l.strip() for l in linhas if l.strip()]
    blocos = [b for b in (limpar(b) for b in blocos) if b]
    if juntar_soltos:  # pdf: um parágrafo partido pela página ou pela coluna volta a ser um
        juntos = []
        for b in blocos:
            if juntos and juntos[-1][-1] not in _FIM_FRASE and b[:1].islower() and not _CAP_RE.match(b):
                ant = juntos[-1]
                juntos[-1] = ant[:-1] + b if ant.endswith("-") and len(ant) > 1 and ant[-2].isalpha() else ant + " " + b
            else:
                juntos.append(b)
        blocos = juntos
    return blocos


def capitulos_de_blocos(blocos, markdown=False):
    caps = [{"titulo": "", "paragrafos": []}]
    for b in blocos:
        titulo = None
        if markdown:
            m = re.match(r"^(#{1,3})\s+(.*?)\s*#*$", b)
            if m:
                titulo = m.group(2)
            b = _md_limpar(b)
            if not b:
                continue
        if titulo is None and len(b) <= 80 and _CAP_RE.match(b) and b[-1] not in ".,;":
            titulo = b
        if titulo is not None:
            caps.append({"titulo": _md_limpar(titulo) if markdown else titulo, "paragrafos": []})
            if markdown and m and len(m.group(1)) >= 3:
                caps[-1]["nivel"] = 2  # ### é seção de um capítulo: o respiro antes dela é menor
            b = caps[-1]["titulo"]
        caps[-1]["paragrafos"].append(b)
    return [c for c in caps if c["paragrafos"]]


def _md_limpar(b):
    b = re.sub(r"^#{1,6}\s+", "", b)
    b = re.sub(r"^\s*(>+\s*)+", "", b)
    b = re.sub(r"^\s*([-*+]|\d+[.)])\s+", "", b)
    b = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", b)
    b = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", b)
    b = re.sub(r"(\*\*|__|~~|`+)", "", b)
    b = re.sub(r"(?<!\w)[*_](?=\S)|(?<=\S)[*_](?!\w)", "", b)
    b = re.sub(r"<[^>]{1,80}>", "", b)
    if re.fullmatch(r"[-=*_| :]{3,}", b):
        return ""
    return limpar(b.replace("|", " "))


class _Html(HTMLParser):
    BLOCO = {"p", "div", "br", "li", "ul", "ol", "tr", "blockquote", "section", "article", "dt", "dd", "pre", "table",
             "h1", "h2", "h3", "h4", "h5", "h6", "hr", "figcaption", "header", "footer", "aside", "main", "body", "td", "th"}
    IGNORA = {"script", "style", "svg", "noscript", "template", "nav", "math", "iframe", "select", "button", "form"}
    TITULO = {"h1", "h2", "h3"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.caps = [{"titulo": "", "paragrafos": []}]
        self.buf = []
        self.ign = 0
        self.em_titulo = None
        self.em_title = False
        self.titulo_doc = ""

    def _fechar(self, titulo=False):
        t = limpar("".join(self.buf))
        self.buf = []
        if not t:
            return
        if titulo:
            self.caps.append({"titulo": t, "paragrafos": []})
            if titulo == "h3":
                self.caps[-1]["nivel"] = 2
        self.caps[-1]["paragrafos"].append(t)

    def handle_starttag(self, tag, attrs):
        if tag in self.IGNORA:
            self.ign += 1
        elif tag == "title":
            self.em_title = True
        elif tag in self.BLOCO:
            self._fechar()
            if tag in self.TITULO:
                self.em_titulo = tag

    def handle_endtag(self, tag):
        if tag in self.IGNORA:
            self.ign = max(0, self.ign - 1)
        elif tag == "title":
            self.em_title = False
        elif tag in self.BLOCO:
            self._fechar(titulo=(tag if tag == self.em_titulo else False))
            if tag == self.em_titulo:
                self.em_titulo = None

    def handle_data(self, data):
        if self.em_title:
            self.titulo_doc += data
        elif not self.ign:
            self.buf.append(data)

    def fim(self):
        self._fechar()
        return [c for c in self.caps if c["paragrafos"]]


def extrair_html(texto):
    p = _Html()
    try:
        p.feed(texto)
        p.close()
    except Exception:
        pass
    return {"titulo": limpar(p.titulo_doc), "autor": "", "capitulos": p.fim()}


def _local(tag):
    return tag.rsplit("}", 1)[-1] if isinstance(tag, str) else ""


def extrair_epub(caminho):
    with zipfile.ZipFile(caminho) as z:
        try:
            cont = ET.fromstring(z.read("META-INF/container.xml"))
            raiz = next(e.get("full-path") for e in cont.iter() if _local(e.tag) == "rootfile" and e.get("full-path"))
            opf = ET.fromstring(z.read(raiz))
        except (KeyError, StopIteration, ET.ParseError) as e:
            raise Erro("epub sem índice legível (%s)" % e)
        base = posixpath.dirname(raiz)
        titulo = autor = ""
        itens, ordem = {}, []
        for e in opf.iter():
            nome = _local(e.tag)
            if nome == "title" and not titulo:
                titulo = limpar(e.text or "")
            elif nome == "creator" and not autor:
                autor = limpar(e.text or "")
            elif nome == "item" and e.get("id"):
                itens[e.get("id")] = (e.get("href") or "", e.get("media-type") or "", e.get("properties") or "")
            elif nome == "itemref" and e.get("idref"):
                ordem.append(e.get("idref"))
        nomes = set(z.namelist())
        caps = []
        for ref in ordem:
            href, tipo, props = itens.get(ref, ("", "", ""))
            if not href or "nav" in props.split() or (tipo and "html" not in tipo and "xml" not in tipo):
                continue
            alvo = posixpath.normpath(posixpath.join(base, unquote(href.split("#")[0])))
            if alvo not in nomes:
                continue
            doc = extrair_html(decodificar(z.read(alvo)))
            for c in doc["capitulos"]:
                if not c["titulo"] and caps:
                    caps[-1]["paragrafos"].extend(c["paragrafos"])
                else:
                    caps.append(c)
    return {"titulo": titulo, "autor": autor, "capitulos": caps}


def extrair_docx(caminho):
    W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
    with zipfile.ZipFile(caminho) as z:
        try:
            doc = ET.fromstring(z.read("word/document.xml"))
        except (KeyError, ET.ParseError) as e:
            raise Erro("docx sem word/document.xml legível (%s)" % e)
        titulo = autor = ""
        try:
            for e in ET.fromstring(z.read("docProps/core.xml")).iter():
                if _local(e.tag) == "title":
                    titulo = limpar(e.text or "")
                elif _local(e.tag) == "creator":
                    autor = limpar(e.text or "")
        except (KeyError, ET.ParseError):
            pass
    caps = [{"titulo": "", "paragrafos": []}]
    for p in doc.iter(W + "p"):
        partes, estilo = [], ""
        for e in p.iter():
            if e.tag == W + "t":
                partes.append(e.text or "")
            elif e.tag in (W + "tab", W + "br", W + "cr"):
                partes.append(" ")
            elif e.tag == W + "pStyle":
                estilo = e.get(W + "val") or ""
        t = limpar("".join(partes))
        if not t:
            continue
        if re.match(r"(?i)^(heading|t[ií]tulo|title|cabe[cç]alho)\s*[1-3]?$", estilo):
            caps.append({"titulo": t, "paragrafos": []})
        caps[-1]["paragrafos"].append(t)
    return {"titulo": titulo, "autor": autor, "capitulos": [c for c in caps if c["paragrafos"]]}


def extrair_odt(caminho):
    with zipfile.ZipFile(caminho) as z:
        try:
            doc = ET.fromstring(z.read("content.xml"))
        except (KeyError, ET.ParseError) as e:
            raise Erro("odt sem content.xml legível (%s)" % e)
    caps = [{"titulo": "", "paragrafos": []}]
    for e in doc.iter():
        nome = _local(e.tag)
        if nome not in ("h", "p"):
            continue
        t = limpar("".join(e.itertext()))
        if not t:
            continue
        if nome == "h":
            caps.append({"titulo": t, "paragrafos": []})
        caps[-1]["paragrafos"].append(t)
    return {"titulo": "", "autor": "", "capitulos": [c for c in caps if c["paragrafos"]]}


def extrair_fb2(dados):
    try:
        doc = ET.fromstring(dados)
    except ET.ParseError as e:
        raise Erro("fb2 ilegível (%s)" % e)
    titulo = autor = ""
    caps = [{"titulo": "", "paragrafos": []}]

    def andar(e, em_titulo=False):
        nonlocal titulo, autor
        nome = _local(e.tag)
        if nome == "binary":
            return
        if nome == "book-title" and not titulo:
            titulo = limpar("".join(e.itertext()))
            return
        if nome == "author" and not autor:
            autor = limpar(" ".join(x for x in e.itertext() if x.strip()))
            return
        if nome == "description":
            for f in e:
                andar(f)
            return
        if nome == "title":
            t = limpar(" ".join(x for x in e.itertext() if x.strip()))
            if t:
                caps.append({"titulo": t, "paragrafos": [t]})
            return
        if nome in ("p", "v", "subtitle", "text-author"):
            t = limpar("".join(e.itertext()))
            if t:
                caps[-1]["paragrafos"].append(t)
            return
        for f in e:
            andar(f)

    for corpo in doc:
        if _local(corpo.tag) in ("body", "description"):
            andar(corpo)
    return {"titulo": titulo, "autor": autor, "capitulos": [c for c in caps if c["paragrafos"]]}


_RTF_DESTINOS = {"fonttbl", "colortbl", "stylesheet", "info", "pict", "header", "footer", "headerl", "headerr", "footerl",
                 "footerr", "ftnsep", "object", "themedata", "colorschememapping", "latentstyles", "datastore", "generator",
                 "listtable", "listoverridetable", "rsidtbl", "xmlnstbl", "mmathPr", "fldinst", "filetbl", "revtbl"}
_RTF_RE = re.compile(r"\\([a-zA-Z]{1,32})(-?\d{1,10})?[ ]?|\\'([0-9a-fA-F]{2})|\\([^a-zA-Z])|([{}])|[\r\n]+|(.)", re.S)


def extrair_rtf(dados):
    texto = dados.decode("latin-1")
    pilha, ignorar, pular_uc, saida = [], False, 0, []
    for m in _RTF_RE.finditer(texto):
        palavra, arg, hexa, simbolo, chave, char = m.groups()
        if chave == "{":
            pilha.append(ignorar)
        elif chave == "}":
            ignorar = pilha.pop() if pilha else False
        elif simbolo:
            if simbolo == "*":
                ignorar = True
            elif not ignorar:
                saida.append({"~": " ", "_": "-", "-": ""}.get(simbolo, simbolo if simbolo in "\\{}" else ""))
        elif palavra:
            if palavra in _RTF_DESTINOS:
                ignorar = True
            elif not ignorar:
                if palavra in ("par", "sect", "page", "line"):
                    saida.append("\n\n" if palavra != "line" else "\n")
                elif palavra == "tab":
                    saida.append(" ")
                elif palavra == "u" and arg:
                    n = int(arg)
                    saida.append(chr(n + 65536 if n < 0 else n))
                    pular_uc = 1
                elif palavra in ("emdash", "endash", "lquote", "rquote", "ldblquote", "rdblquote", "bullet"):
                    saida.append({"emdash": "—", "endash": "–", "lquote": "‘", "rquote": "’", "ldblquote": "“",
                                  "rdblquote": "”", "bullet": "•"}[palavra])
        elif hexa:
            if pular_uc:
                pular_uc -= 1
            elif not ignorar:
                saida.append(bytes([int(hexa, 16)]).decode("cp1252", "replace"))
        elif char:
            if pular_uc:
                pular_uc -= 1
            elif not ignorar:
                saida.append(char)
    return {"titulo": "", "autor": "", "capitulos": capitulos_de_blocos(blocos_de_texto("".join(saida)))}


def _rodar(cmd, prazo=180):
    try:
        r = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=prazo)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, str(e)
    if r.returncode != 0:
        return None, r.stderr.decode("utf-8", "replace").strip()[-300:]
    return r.stdout, ""


def extrair_pdf(caminho):
    saida = erro = None
    if shutil.which("pdftotext"):
        saida, erro = _rodar(["pdftotext", "-enc", "UTF-8", "-q", caminho, "-"])
    if saida is None and shutil.which("mutool"):
        saida, erro = _rodar(["mutool", "draw", "-q", "-F", "txt", "-o", "-", caminho])
        if saida is not None and b"\f" not in saida:
            saida = saida.replace(b"\n\n\n", b"\n\f")
    if saida is None:
        if erro:
            raise Erro("não consegui ler o pdf: %s" % erro)
        raise Erro("para ler pdf nesta máquina falta o pdftotext (pacote poppler-utils; no Mac: brew install poppler; "
                   "no Termux: pkg install poppler). Dica: acrescente o pdf numa máquina que o tenha, e o texto chega aqui pela rede do tt.")
    paginas = [p.split("\n") for p in decodificar(saida).split("\f")]
    paginas = [p for p in paginas if any(l.strip() for l in p)]
    if not paginas:
        raise Erro("o pdf não tem texto (parece ser só imagem; passe um OCR antes, por exemplo com ocrmypdf)")

    # Cabeçalho e rodapé: a primeira e a última linha que se repetem na maioria das páginas (número à parte) saem.
    def norma(l):
        return re.sub(r"\d+", "#", l.strip().lower())

    def ponta(p, fim):
        linhas = [l for l in p if l.strip()]
        return norma(linhas[-1 if fim else 0]) if linhas else ""

    repetidas = set()
    if len(paginas) >= 4:
        for fim in (False, True):
            conta = {}
            for p in paginas:
                k = ponta(p, fim)
                if k:
                    conta[k] = conta.get(k, 0) + 1
            repetidas.update(k for k, n in conta.items() if n >= max(3, len(paginas) * 0.4) and len(k) <= 90)
    texto = []
    for p in paginas:
        linhas = list(p)
        for fim in (False, True):
            idx = [i for i, l in enumerate(linhas) if l.strip()]
            if not idx:
                break
            i = idx[-1 if fim else 0]
            if norma(linhas[i]) in repetidas or re.fullmatch(r"\s*[-–—]?\s*\d{1,4}\s*[-–—]?\s*", linhas[i]):
                linhas[i] = ""
        texto.append("\n".join(linhas))
    blocos = blocos_de_texto("\n\n".join(texto), juntar_soltos=True)
    titulo = autor = ""
    if shutil.which("pdfinfo"):  # o título que o próprio pdf declara, quando parece um título
        info, _ = _rodar(["pdfinfo", "-enc", "UTF-8", caminho], 20)
        for linha in decodificar(info or b"").splitlines():
            chave, _, valor = linha.partition(":")
            valor = limpar(valor)
            if chave == "Title" and len(valor) >= 4 and not re.search(r"(?i)\.(docx?|indd|pdf|qxd|pptx?|dvi|tex)$|^untitled|^microsoft word", valor):
                titulo = valor[:200]
            elif chave == "Author" and valor:
                autor = valor[:120]
    return {"titulo": titulo, "autor": autor, "capitulos": capitulos_de_blocos(blocos)}


def formato_de(nome, dados=b""):
    ext = os.path.splitext(nome)[1].lower().lstrip(".")
    if ext in FORMATOS:
        return {"markdown": "md", "text": "txt", "htm": "html", "xhtml": "html"}.get(ext, ext)
    cab = dados[:2048]
    if cab.startswith(b"%PDF"):
        return "pdf"
    if cab.startswith(b"{\\rtf"):
        return "rtf"
    if cab.startswith(b"PK"):
        try:
            with zipfile.ZipFile(io.BytesIO(dados)) as z:
                nomes = z.namelist()
            if "word/document.xml" in nomes:
                return "docx"
            if "META-INF/container.xml" in nomes:
                return "epub"
            if "content.xml" in nomes:
                return "odt"
        except zipfile.BadZipFile:
            pass
        return ""
    baixo = cab.lower()
    if b"<fictionbook" in baixo:
        return "fb2"
    if b"<html" in baixo or b"<!doctype html" in baixo:
        return "html"
    if b"\x00" in cab:
        return ""
    return "txt"


def extrair(caminho, nome=None):
    """Arquivo → {"titulo", "autor", "capitulos": [{"titulo", "paragrafos": [...]}]} (Erro se não der)."""
    nome = nome or os.path.basename(caminho)
    with open(caminho, "rb") as f:
        cab = f.read(1 << 16)
    fmt = formato_de(nome, cab)
    if not fmt and cab.startswith(b"PK"):
        with open(caminho, "rb") as f:
            fmt = formato_de("", f.read())
    if not fmt:
        raise Erro("formato não reconhecido: %s (leio %s)" % (nome, ", ".join(sorted(set(FORMATOS) - {"markdown", "text", "htm", "xhtml"}))))
    try:
        if fmt == "pdf":
            livro = extrair_pdf(caminho)
        elif fmt == "epub":
            livro = extrair_epub(caminho)
        elif fmt == "docx":
            livro = extrair_docx(caminho)
        elif fmt == "odt":
            livro = extrair_odt(caminho)
        else:
            with open(caminho, "rb") as f:
                dados = f.read()
            if fmt == "rtf":
                livro = extrair_rtf(dados)
            elif fmt == "fb2":
                livro = extrair_fb2(dados)
            elif fmt == "html":
                livro = extrair_html(decodificar(dados))
            else:
                livro = {"titulo": "", "autor": "", "capitulos": capitulos_de_blocos(blocos_de_texto(decodificar(dados), markdown=(fmt == "md")), markdown=(fmt == "md"))}
    except zipfile.BadZipFile:
        raise Erro("%s: o arquivo está corrompido (não abre como %s)" % (nome, fmt))
    if not any(c["paragrafos"] for c in livro["capitulos"]):
        raise Erro("%s: não achei texto para ler" % nome)
    if not livro.get("titulo"):
        base = os.path.splitext(nome)[0]
        livro["titulo"] = limpar(re.sub(r"[_]+" if " " in base else r"[_-]+", " ", base)) or "sem título"
    livro["formato"] = fmt
    return livro


# --- Biblioteca -------------------------------------------------------------------------------------------------------

def pasta(lid):
    if not ID_RE.match(lid or ""):
        raise Erro("código de livro inválido: %r" % lid)
    return os.path.join(LIVROS, lid)


def ler_meta(lid):
    return ler_json(os.path.join(pasta(lid), "meta.json"), {})


def ler_estado(lid):
    e = ler_json(os.path.join(pasta(lid), "estado.json"), {})
    e.setdefault("pos", 0)
    e.setdefault("mudada", 0)
    e.setdefault("marcadores", {})
    return e


def gravar_estado(lid, estado):
    gravar_json(os.path.join(pasta(lid), "estado.json"), estado)


def arquivo_original(lid, meta=None):
    meta = meta or ler_meta(lid)
    nome = meta.get("original") or ""
    if nome and re.fullmatch(r"original(\.[a-z0-9]{1,8})?", nome):
        c = os.path.join(pasta(lid), nome)
        if os.path.isfile(c):
            return c
    return ""


def arquivo_texto(lid):
    c = os.path.join(pasta(lid), "texto.json.gz")
    return c if os.path.isfile(c) else ""


def ler_texto(lid):
    c = arquivo_texto(lid)
    if not c:
        raise Erro("o texto deste livro ainda não chegou a esta máquina (tt --leitor-sync traz)")
    with gzip.open(c, "rt", encoding="utf-8") as f:
        return json.load(f)


def ids():
    try:
        return sorted(n for n in os.listdir(LIVROS) if ID_RE.match(n) and os.path.isfile(os.path.join(LIVROS, n, "meta.json")))
    except OSError:
        return []


def lapides():
    d = ler_json(LAPIDES, {})
    return {k: int(v) for k, v in d.items() if ID_RE.match(k) and isinstance(v, (int, float))}


def resolver(ref):
    """Código inteiro, prefixo (4+ hex) ou pedaço do título → id. Ambíguo ou inexistente: Erro."""
    todos = ids()
    if ref in todos:
        return ref
    r = ref.lower()
    cand = [i for i in todos if len(r) >= 4 and i.startswith(r)]
    if not cand:
        cand = [i for i in todos if r in (ler_meta(i).get("titulo") or "").lower()]
    if len(cand) == 1:
        return cand[0]
    if not cand:
        raise Erro("não achei o livro “%s” (tt --leitor-listar mostra os que há)" % ref)
    raise Erro("“%s” serve para mais de um livro:\n%s" % (ref, "\n".join("  %s  %s" % (i, ler_meta(i).get("titulo", "")) for i in cand)))


def contar_palavras(livro):
    return sum(len(p.split()) for c in livro["capitulos"] for p in c["paragrafos"])


def adicionar(caminho, nome=None, titulo=None):
    """Acrescenta o arquivo à biblioteca (ou reconhece o que já está lá). Devolve (id, meta, novo)."""
    nome = nome or os.path.basename(caminho)
    h = hashlib.sha256()
    tam = 0
    with open(caminho, "rb") as f:
        for bloco in iter(lambda: f.read(1 << 20), b""):
            h.update(bloco)
            tam += len(bloco)
    if not tam:
        raise Erro("%s está vazio" % nome)
    lid = h.hexdigest()[:12]
    d = pasta(lid)
    meta = ler_meta(lid) if os.path.isdir(d) else {}
    if meta and arquivo_texto(lid):
        if not arquivo_original(lid, meta):  # o texto veio pela rede; o original, agora, daqui
            _guardar_original(lid, meta, caminho, nome)
        return lid, meta, False
    livro = extrair(caminho, nome)
    fmt = livro.pop("formato")
    corpo = json.dumps({"titulo": livro["titulo"], "autor": livro.get("autor", ""), "capitulos": livro["capitulos"]},
                       ensure_ascii=False, sort_keys=True).encode("utf-8")
    os.makedirs(d, exist_ok=True)
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", mtime=0) as g:
        g.write(corpo)
    gravar(os.path.join(d, "texto.json.gz"), buf.getvalue())
    meta = {"id": lid, "titulo": titulo or livro["titulo"], "autor": livro.get("autor", ""), "nome": nome, "formato": fmt,
            "bytes": tam, "palavras": contar_palavras(livro), "adicionada": agora_ms(), "maquina": maquina(),
            "texto_sha": hashlib.sha256(corpo).hexdigest()[:16], "original": ""}
    _guardar_original(lid, meta, caminho, nome)
    lap = lapides()
    if lid in lap:  # acrescentar de novo, de propósito, vale mais que a remoção antiga
        del lap[lid]
        gravar_json(LAPIDES, lap)
    if not os.path.isfile(os.path.join(d, "estado.json")):
        gravar_estado(lid, {"pos": 0, "mudada": 0, "marcadores": {}})
    return lid, meta, True


def _guardar_original(lid, meta, caminho, nome):
    ext = re.sub(r"[^a-z0-9]", "", os.path.splitext(nome)[1].lower())[:8]
    alvo = "original" + ("." + ext if ext else "")
    d = pasta(lid)
    tmp = os.path.join(d, ".tmp-original-%d" % os.getpid())
    shutil.copyfile(caminho, tmp)
    os.replace(tmp, os.path.join(d, alvo))
    meta["original"] = alvo
    gravar_json(os.path.join(d, "meta.json"), meta)


def remover(lid):
    meta = ler_meta(lid)
    lap = lapides()
    lap[lid] = agora_ms()
    gravar_json(LAPIDES, lap)
    shutil.rmtree(pasta(lid), ignore_errors=True)
    return meta


def marcar_posicao(lid, pos, total=None, **extra):
    e = ler_estado(lid)
    e["pos"] = max(0, int(pos))
    e["mudada"] = agora_ms()
    e["maquina"] = maquina()
    pm = e.get("por_maquina") if isinstance(e.get("por_maquina"), dict) else {}
    pm[maquina()] = {"pos": e["pos"], "mudada": e["mudada"]}  # onde ESTA máquina parou (a posição do livro é a mais nova)
    e["por_maquina"] = pm
    if total:
        e["concluido"] = e["pos"] >= total - 1
    e.update(extra)
    gravar_estado(lid, e)
    return e


def resumo(lid):
    meta, est = ler_meta(lid), ler_estado(lid)
    total = max(1, int(meta.get("palavras") or 1))
    pos = min(int(est.get("pos") or 0), total)
    pm = est.get("por_maquina") if isinstance(est.get("por_maquina"), dict) else {}
    maqs = {}
    for k, v in pm.items():
        try:
            vp = int(v.get("pos") or 0)
            maqs[k] = (100 if vp >= total - 1 else vp * 100 // total, int(v.get("mudada") or 0))
        except (TypeError, ValueError, AttributeError):
            pass
    marc = est.get("marcadores") if isinstance(est.get("marcadores"), dict) else {}
    return {"id": lid, "titulo": meta.get("titulo") or "?", "autor": meta.get("autor") or "", "palavras": total, "pos": pos,
            "maquinas": maqs, "marcadores": sum(1 for v in marc.values() if isinstance(v, dict) and not v.get("removido")),
            "nome": meta.get("nome") or "",
            "pct": 100 if est.get("concluido") else int(pos * 100 / total), "mudada": int(est.get("mudada") or 0),
            "maquina": est.get("maquina") or "", "adicionada": int(meta.get("adicionada") or 0), "formato": meta.get("formato") or "",
            "bytes": int(meta.get("bytes") or 0), "texto": bool(arquivo_texto(lid)), "original": bool(arquivo_original(lid, meta)),
            "origem": meta.get("maquina") or "", "concluido": bool(est.get("concluido"))}


def listar():
    r = [resumo(i) for i in ids()]
    r.sort(key=lambda x: -max(x["mudada"], x["adicionada"]))
    return r


def onde_original(lid):
    """Rótulos das outras máquinas que disseram, na última troca, ter o arquivo original."""
    tem = []
    try:
        nomes = sorted(os.listdir(MAQUINAS))
    except OSError:
        nomes = []
    for n in nomes:
        inv = ler_json(os.path.join(MAQUINAS, n), {})
        if (inv.get("livros") or {}).get(lid, {}).get("original"):
            tem.append(n[:-5] if n.endswith(".json") else n)
    return tem


REDE = os.path.join(DIR, "rede.json")


def rede_nota(rotulo, estado):
    """A troca com a máquina RÓTULO acabou assim (ok|pulada|falhou): fica para a aba Máquinas."""
    r = ler_json(REDE, {})
    if not isinstance(r, dict):
        r = {}
    ant = r.get(rotulo) if isinstance(r.get(rotulo), dict) else {}
    r[rotulo] = {"quando": agora_ms(), "estado": estado, "ok": agora_ms() if estado == "ok" else int(ant.get("ok") or 0)}
    gravar_json(REDE, r)


def rede():
    """{máquina: {estado, quando, ok, livros, originais}} do que as trocas deixaram anotado aqui."""
    r = {}
    notas = ler_json(REDE, {})
    for k, v in (notas.items() if isinstance(notas, dict) else ()):
        if isinstance(v, dict):
            r[k] = {"estado": str(v.get("estado") or ""), "quando": int(v.get("quando") or 0), "ok": int(v.get("ok") or 0), "livros": None, "originais": 0}
    try:
        nomes = sorted(os.listdir(MAQUINAS))
    except OSError:
        nomes = []
    for n in nomes:
        if not n.endswith(".json"):
            continue
        inv = ler_json(os.path.join(MAQUINAS, n), {})
        liv = inv.get("livros") if isinstance(inv.get("livros"), dict) else {}
        d = r.setdefault(n[:-5], {"estado": "", "quando": 0, "ok": 0, "livros": None, "originais": 0})
        d["livros"] = len(liv)
        d["originais"] = sum(1 for i in liv.values() if isinstance(i, dict) and i.get("original"))
        d["ids"] = set(liv)
        d["ok"] = max(d["ok"], int(inv.get("quando") or 0))
    return r


LS_MAX = 3000


def ls(onde=""):
    """Uma pasta para o navegador de arquivos (daqui ou, por ssh, de outra máquina): subpastas e os arquivos que o
    leitor sabe ler. "" = a pasta pessoal; "@recentes" = os arquivos legíveis mais novos das pastas de costume."""
    exts = tuple("." + f for f in FORMATOS)
    if onde == "@recentes":
        itens = []
        for c in arquivos_recentes(200):
            try:
                st = os.stat(c)
                itens.append([c, "f", st.st_size, int(st.st_mtime)])
            except OSError:
                pass
        return {"leitor_ls": 1, "pasta": "@recentes", "acima": "", "casa": CASA, "itens": itens, "erro": ""}
    d = os.path.abspath(os.path.expanduser(onde or "~"))
    r = {"leitor_ls": 1, "pasta": d, "acima": os.path.dirname(d) if d != "/" else "", "casa": CASA, "itens": [], "erro": ""}
    try:
        with os.scandir(d) as it:
            for e in it:
                if e.name.startswith(".") or len(r["itens"]) >= LS_MAX:
                    continue
                try:
                    if e.is_dir():
                        r["itens"].append([e.name, "d", 0, int(e.stat().st_mtime)])
                    elif e.name.lower().endswith(exts) and e.is_file():
                        st = e.stat()
                        r["itens"].append([e.name, "f", st.st_size, int(st.st_mtime)])
                except OSError:
                    continue
    except OSError as e:
        r["erro"] = e.strerror or str(e)
    r["itens"].sort(key=lambda i: (i[1] != "d", sem_acento(i[0])))
    return r


def tamanho_legivel(n):
    n = float(n or 0)
    for u in ("B", "KB", "MB", "GB"):
        if n < 1024 or u == "GB":
            return ("%d %s" % (n, u)) if u == "B" else ("%.1f %s" % (n, u)).replace(".", ",")
        n /= 1024


def ha_quanto(ms):
    if not ms:
        return "nunca"
    s = max(0, (agora_ms() - ms) // 1000)
    if s < 90:
        return "agora"
    if s < 3600:
        return "há %d min" % (s // 60)
    if s < 86400:
        return "há %d h" % (s // 3600)
    if s < 86400 * 60:
        return "há %d d" % (s // 86400)
    return time.strftime("%d/%m/%Y", time.localtime(ms / 1000))


def duracao(seg):
    seg = int(max(0, seg))
    if seg < 60:
        return "%d s" % seg
    if seg < 3600:
        return "%d min" % round(seg / 60)
    return "%d h %02d" % (seg // 3600, (seg % 3600) // 60)


# --- Sincronização ----------------------------------------------------------------------------------------------------
# Quem conduz é o `tt --leitor-sync` de uma máquina, com cada outra: lê o inventário de lá e o mescla aqui (posições,
# marcadores, lápides, livros que ainda não conhece); manda o inventário daqui para lá mesclar; puxa os arquivos que
# faltam aqui e leva os que faltam lá. O texto extraído viaja sempre (é o que permite ler um pdf no celular, que não
# tem pdftotext); o original, até o limite de cada máquina (leitor_original_max_mb; 0 = nunca; --so ID fura o limite).

def limite_original():
    try:
        mb = float(os.environ.get("TT_LEITOR_ORIGINAL_MAX_MB", "") or 200)
    except ValueError:
        mb = 200
    return int(mb * (1 << 20))


def meta_vence(a, b):
    """True se a meta `a` é a que fica quando as duas máquinas extraíram o mesmo arquivo por conta própria."""
    return (int(a.get("adicionada") or 0), a.get("texto_sha") or "") < (int(b.get("adicionada") or 0), b.get("texto_sha") or "")


def mesclar_estado(meu, outro):
    """Posição: a mudada mais nova vence. Marcadores: por posição, a mudança mais nova. Devolve (estado, mudou)."""
    a = dict(meu or {})
    b = outro or {}
    antes = json.dumps(a, sort_keys=True)
    ma = dict(a.get("marcadores") or {})
    for k, v in (b.get("marcadores") or {}).items():
        if isinstance(v, dict) and re.fullmatch(r"\d{1,9}", str(k)) and int(v.get("mudada") or 0) > int((ma.get(k) or {}).get("mudada") or 0):
            ma[k] = {"nome": str(v.get("nome") or "")[:200], "mudada": int(v.get("mudada") or 0), "removido": bool(v.get("removido"))}
    if int(b.get("mudada") or 0) > int(a.get("mudada") or 0):
        for k in ("pos", "mudada", "maquina", "concluido"):
            if k in b:
                a[k] = b[k]
        a["pos"] = max(0, int(a.get("pos") or 0))
        a["maquina"] = str(a.get("maquina") or "")[:60]
    a["marcadores"] = ma
    pm = {k: v for k, v in (a.get("por_maquina") or {}).items() if isinstance(v, dict)} if isinstance(a.get("por_maquina"), dict) else {}
    if isinstance(b.get("por_maquina"), dict):
        for k, v in b["por_maquina"].items():
            try:
                if (isinstance(v, dict) and re.fullmatch(r"[\w.-]{1,60}", str(k)) and
                        int(v.get("mudada") or 0) > int((pm.get(k) or {}).get("mudada") or 0) and (k in pm or len(pm) < 32)):
                    pm[str(k)] = {"pos": max(0, int(v.get("pos") or 0)), "mudada": int(v.get("mudada") or 0)}
            except (TypeError, ValueError):
                pass
    if pm:
        a["por_maquina"] = pm
    a.setdefault("pos", 0)
    a.setdefault("mudada", 0)
    return a, json.dumps(a, sort_keys=True) != antes


def meta_limpa(m):
    """Só os campos conhecidos, com os tipos certos: a meta vem de outra máquina."""
    if not isinstance(m, dict):
        return None
    try:
        r = {"id": str(m["id"]), "titulo": str(m.get("titulo") or "?")[:300], "autor": str(m.get("autor") or "")[:200],
             "nome": os.path.basename(str(m.get("nome") or ""))[:200], "formato": str(m.get("formato") or "")[:12],
             "bytes": int(m.get("bytes") or 0), "palavras": int(m.get("palavras") or 0), "adicionada": int(m.get("adicionada") or 0),
             "maquina": str(m.get("maquina") or "")[:60], "texto_sha": str(m.get("texto_sha") or "")[:16], "original": ""}
    except (KeyError, TypeError, ValueError):
        return None
    o = str(m.get("original") or "")
    if re.fullmatch(r"original(\.[a-z0-9]{1,8})?", o):
        r["original"] = o
    return r if ID_RE.match(r["id"]) else None


def inventario():
    livros = {}
    for lid in ids():
        meta = ler_meta(lid)
        livros[lid] = {"meta": meta, "estado": ler_estado(lid), "texto": bool(arquivo_texto(lid)),
                       "original": bool(arquivo_original(lid, meta))}
    return {"leitor": 1, "maquina": maquina(), "livros": livros, "lapides": lapides(), "original_max": limite_original()}


def ler_inventario(caminho):
    inv = ler_json(caminho, {}) if caminho != "-" else json.load(sys.stdin)
    if not isinstance(inv, dict) or inv.get("leitor") != 1 or not isinstance(inv.get("livros"), dict):
        raise Erro("inventário inválido")
    return inv


def mesclar(inv):
    """Traz do inventário de outra máquina o que é pequeno: lápides, livros novos (meta) e estados. Devolve contagens."""
    n = {"novos": 0, "estados": 0, "removidos": 0}
    lap = lapides()
    mudou_lap = False
    for lid, t in (inv.get("lapides") or {}).items():
        if not ID_RE.match(lid) or not isinstance(t, (int, float)):
            continue
        t = int(t)
        if t > lap.get(lid, 0):
            lap[lid] = t
            mudou_lap = True
        if os.path.isdir(pasta(lid)) and int(ler_meta(lid).get("adicionada") or 0) < lap[lid]:
            shutil.rmtree(pasta(lid), ignore_errors=True)
            n["removidos"] += 1
    for lid, item in inv["livros"].items():
        if not ID_RE.match(lid) or not isinstance(item, dict):
            continue
        meta = meta_limpa(item.get("meta"))
        if not meta or meta["id"] != lid:
            continue
        if lap.get(lid, 0) >= meta["adicionada"]:
            continue
        if lid in lap:  # acrescentado de novo depois da remoção: a lápide perde
            del lap[lid]
            mudou_lap = True
        d = pasta(lid)
        if not os.path.isfile(os.path.join(d, "meta.json")):
            meta["original"] = ""  # o arquivo ainda não está aqui
            gravar_json(os.path.join(d, "meta.json"), meta)
            n["novos"] += 1
        est, mudou = mesclar_estado(ler_estado(lid), item.get("estado") if isinstance(item.get("estado"), dict) else {})
        if mudou or not os.path.isfile(os.path.join(d, "estado.json")):
            gravar_estado(lid, est)
            n["estados"] += int(mudou)
    if mudou_lap:
        gravar_json(LAPIDES, lap)
    nome = re.sub(r"[^\w.-]", "-", str(inv.get("maquina") or ""))[:60]
    if nome and nome != maquina():
        gravar_json(os.path.join(MAQUINAS, nome + ".json"), {"quando": agora_ms(), "livros": {
            lid: {"original": bool(i.get("original")), "texto": bool(i.get("texto"))} for lid, i in inv["livros"].items()
            if ID_RE.match(lid) and isinstance(i, dict)}})
    return n


def pedir(inv, enviar=False, so=None):
    """Linhas "id<TAB>parte" (texto|original): o que puxar de lá, ou (enviar) o que levar para lá."""
    pedidos = []
    lap_la = {k: v for k, v in (inv.get("lapides") or {}).items() if ID_RE.match(k) and isinstance(v, (int, float))}
    lap_aqui = lapides()
    limite_la = inv.get("original_max")
    limite_la = int(limite_la) if isinstance(limite_la, (int, float)) else limite_original()
    aqui = set(ids())
    if not enviar:
        for lid, item in sorted(inv["livros"].items()):
            meta = meta_limpa(item.get("meta")) if isinstance(item, dict) else None
            if not meta or meta["id"] != lid or (so and lid != so) or lap_aqui.get(lid, 0) >= meta["adicionada"]:
                continue
            minha = ler_meta(lid) if lid in aqui else {}
            if item.get("texto") and (not (lid in aqui and arquivo_texto(lid)) or
                                      (minha.get("texto_sha") != meta["texto_sha"] and meta_vence(meta, minha))):
                pedidos.append((lid, "texto"))
            if item.get("original") and not (lid in aqui and arquivo_original(lid, minha)) and (so or meta["bytes"] <= limite_original()):
                pedidos.append((lid, "original"))
    else:
        for lid in sorted(aqui):
            minha = ler_meta(lid)
            if (so and lid != so) or lap_la.get(lid, 0) >= int(minha.get("adicionada") or 0):
                continue
            item = inv["livros"].get(lid) if isinstance(inv["livros"].get(lid), dict) else {}
            deles = meta_limpa(item.get("meta")) or {}
            if arquivo_texto(lid) and (not item.get("texto") or (deles.get("texto_sha") != minha.get("texto_sha") and meta_vence(minha, deles))):
                pedidos.append((lid, "texto"))
            if arquivo_original(lid, minha) and not item.get("original") and (so or int(minha.get("bytes") or 0) <= limite_la):
                pedidos.append((lid, "original"))
    return pedidos


def empacotar(pedidos, saida):
    """Tar (sem compressão: o texto já vai em gzip) com meta, estado e as partes pedidas de cada livro."""
    with tarfile.open(fileobj=saida, mode="w|", format=tarfile.PAX_FORMAT) as tar:
        feitos = set()

        def por(nome, caminho=None, dados=None):
            info = tarfile.TarInfo(nome)
            info.mode, info.mtime = 0o600, int(time.time())
            if dados is not None:
                info.size = len(dados)
                tar.addfile(info, io.BytesIO(dados))
            else:
                info.size = os.path.getsize(caminho)
                with open(caminho, "rb") as f:
                    tar.addfile(info, f)

        for lid, parte in pedidos:
            if not ID_RE.match(lid) or lid not in ids():
                continue
            meta = ler_meta(lid)
            if lid not in feitos:
                feitos.add(lid)
                por(lid + "/meta.json", dados=json.dumps(meta, ensure_ascii=False).encode("utf-8"))
                por(lid + "/estado.json", dados=json.dumps(ler_estado(lid), ensure_ascii=False).encode("utf-8"))
            if parte == "texto" and arquivo_texto(lid):
                por(lid + "/texto.json.gz", caminho=arquivo_texto(lid))
            elif parte == "original" and arquivo_original(lid, meta):
                por(lid + "/original", caminho=arquivo_original(lid, meta))


_MEMBRO_RE = re.compile(r"^([0-9a-f]{12})/(meta\.json|estado\.json|texto\.json\.gz|original)$")


def aplicar(entrada):
    """Recebe o tar de outra máquina. Só nomes conhecidos, tamanhos limitados; o original só fica se o sha256 dele
    for o código do livro, e o texto só se abrir como texto de livro. Nada de fora da pasta do livro é escrito."""
    n = {"livros": 0, "textos": 0, "originais": 0, "recusados": 0}
    lap = lapides()
    metas, estados = {}, {}
    os.makedirs(LIVROS, exist_ok=True)

    def nasceu(lid):
        n["livros"] += 1
        gravar_estado(lid, mesclar_estado(ler_estado(lid), estados.get(lid) or {})[0])

    with tarfile.open(fileobj=entrada, mode="r|") as tar:
        for info in tar:
            m = _MEMBRO_RE.match(info.name)
            if not m or not info.isfile():
                n["recusados"] += 1
                continue
            lid, parte = m.groups()
            limite = {"meta.json": MAX_META, "estado.json": MAX_META, "texto.json.gz": MAX_TEXTO, "original": MAX_ORIGINAL}[parte]
            if info.size > limite:
                n["recusados"] += 1
                continue
            f = tar.extractfile(info)
            d = pasta(lid)
            if parte == "meta.json":
                try:
                    meta = meta_limpa(json.loads(f.read().decode("utf-8")))
                except ValueError:
                    meta = None
                if not meta or meta["id"] != lid or lap.get(lid, 0) >= meta["adicionada"]:
                    n["recusados"] += 1
                    continue
                metas[lid] = meta  # o livro que esta máquina não conhece só nasce quando um arquivo válido dele chega
                continue
            if lid not in metas:  # a meta vem antes; sem ela (ou recusada) o resto do livro não entra
                n["recusados"] += 1
                continue
            meta = metas[lid]
            if parte == "estado.json":
                try:
                    outro = json.loads(f.read().decode("utf-8"))
                except ValueError:
                    outro = {}
                estados[lid] = outro if isinstance(outro, dict) else {}
                if os.path.isfile(os.path.join(d, "meta.json")):
                    est, mudou = mesclar_estado(ler_estado(lid), estados[lid])
                    if mudou or not os.path.isfile(os.path.join(d, "estado.json")):
                        gravar_estado(lid, est)
                continue
            os.makedirs(os.path.join(DIR, "chegando"), exist_ok=True)
            tmp = os.path.join(DIR, "chegando", "%s-%s-%d" % (lid, parte, os.getpid()))
            h = hashlib.sha256()
            try:
                with open(tmp, "wb") as out:
                    for bloco in iter(lambda: f.read(1 << 20), b""):
                        h.update(bloco)
                        out.write(bloco)
                novo_aqui = not os.path.isfile(os.path.join(d, "meta.json"))
                local = ler_meta(lid) or dict(meta, original="")
                if parte == "original":
                    if h.hexdigest()[:12] != lid or arquivo_original(lid, local):
                        n["recusados"] += h.hexdigest()[:12] != lid
                        continue
                    nome = meta["original"] or "original"
                    os.makedirs(d, exist_ok=True)
                    os.replace(tmp, os.path.join(d, nome))
                    local["original"] = nome
                    local["bytes"] = local.get("bytes") or meta["bytes"]
                    gravar_json(os.path.join(d, "meta.json"), local)
                    n["originais"] += 1
                    if novo_aqui:
                        nasceu(lid)
                else:
                    try:
                        with gzip.open(tmp, "rb") as g:
                            corpo = g.read(MAX_TEXTO + 1)
                        livro = json.loads(corpo.decode("utf-8"))
                        ok = (len(corpo) <= MAX_TEXTO and isinstance(livro.get("capitulos"), list) and
                              all(isinstance(c, dict) and isinstance(c.get("paragrafos"), list) and
                                  all(isinstance(p, str) for p in c["paragrafos"]) for c in livro["capitulos"]) and
                              hashlib.sha256(corpo).hexdigest()[:16] == meta["texto_sha"])
                    except (OSError, ValueError, EOFError, AttributeError, zlib.error):
                        ok = False
                    if not ok:
                        n["recusados"] += 1
                        continue
                    if arquivo_texto(lid) and not (local.get("texto_sha") != meta["texto_sha"] and meta_vence(meta, local)):
                        continue
                    os.makedirs(d, exist_ok=True)
                    os.replace(tmp, os.path.join(d, "texto.json.gz"))
                    novo = dict(meta, original=local.get("original") or "")
                    gravar_json(os.path.join(d, "meta.json"), novo)
                    n["textos"] += 1
                    if novo_aqui:
                        nasceu(lid)
            finally:
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
    return n


# --- Letras grandes (atlas) -------------------------------------------------------------------------------------------
# O terminal não troca de fonte nem de tamanho; o leitor desenha as letras. O atlas (leitor-fontes.bin) traz cada
# família em dois pesos, rasterizada com ajuste fino nas alturas pequenas (8 a 24 pontos) e numa matriz de 48 de onde
# saem as outras. Um "ponto" é quadrado; cada traço junta os pontos de um jeito na célula do terminal:
#   pontos (braille, 2×4 por célula) · fino (quadrantes, 2×2) · blocos (meio bloco, 1×2) · cheio (bloco inteiro).
# Formato: "TTLF1\n" + uma linha JSON (famílias, pesos → [início, tamanho]) + os pesos em zlib. Cada peso: nº de alturas;
# por altura: altura (1 byte), tamanho (4); por letra: código (2), largura (1), linhas de bits (altura × ceil(largura/8)).

ALTURAS_ATLAS = (8, 10, 12, 14, 16, 20, 24, 48)
MESTRE = 48
TRACOS = ("fino", "pontos", "blocos", "cheio")
TRACO_NOME = {"fino": "fino (quadrantes)", "pontos": "pontilhado (braille)", "blocos": "blocos", "cheio": "cheio (blocos grandes)"}
TAMANHOS = (1, 2, 3, 4, 5, 6, 7, 8, 10, 12)
_QUADRANTES = " ▘▝▀▖▌▞▛▗▚▐▜▄▙▟█"
LETRAS_ATLAS = ("".join(chr(c) for c in range(0x20, 0x7f)) + "".join(chr(c) for c in range(0xa1, 0x180)) +
                "–—‘’‚“”„†‡•…‰‹›€™−≤≥≠≈×÷√∞←→↑↓ﬁﬂ№")
FAMILIAS_GERAR = (  # chave, nome, normal, negrito, licença
    ("sans", "DejaVu Sans", "dejavu/DejaVuSans.ttf", "dejavu/DejaVuSans-Bold.ttf", "Bitstream Vera/DejaVu (livre)"),
    ("serif", "DejaVu Serif", "dejavu/DejaVuSerif.ttf", "dejavu/DejaVuSerif-Bold.ttf", "Bitstream Vera/DejaVu (livre)"),
    ("mono", "DejaVu Sans Mono", "dejavu/DejaVuSansMono.ttf", "dejavu/DejaVuSansMono-Bold.ttf", "Bitstream Vera/DejaVu (livre)"),
    ("lato", "Lato", "lato/Lato-Medium.ttf", "lato/Lato-Black.ttf", "SIL OFL 1.1 © Łukasz Dziedzic"),
    ("fira", "Fira Sans", "fira/FiraSans-Regular.otf", "fira/FiraSans-Bold.otf", "SIL OFL 1.1 © The Mozilla Foundation, Telefonica S.A."),
    ("redonda", "Quicksand", "quicksand/Quicksand-Medium.ttf", "quicksand/Quicksand-Bold.ttf", "SIL OFL 1.1 © The Quicksand Project Authors"),
)


def rasterizar(caminho, altura, letras):
    """{código: (largura, bytes das linhas)} na altura dada, com o FreeType em modo 1 bit (precisa do Pillow)."""
    from PIL import Image, ImageDraw, ImageFont
    ref = "ÉÂÃÕbdfhklgjpqyç,;|"

    def caixa(tam):
        f = ImageFont.truetype(caminho, tam)
        b = f.getbbox(ref)
        return f, b[1], b[3]

    lo, hi = 4, altura * 2
    while lo < hi:  # o maior corpo cuja caixa (do acento do É à perna do g) cabe na altura
        meio = (lo + hi + 1) // 2
        _, topo, base = caixa(meio)
        if base - topo <= altura:
            lo = meio
        else:
            hi = meio - 1
    fonte, topo, base = caixa(lo)
    dy = -topo + (altura - (base - topo)) // 2

    def desenhar(ch):
        larg = max(1, int(round(fonte.getlength(ch))))
        b = fonte.getbbox(ch)
        esq = -b[0] if b and b[0] < 0 else 0
        larg = min(255, max(larg + esq, (b[2] + esq) if b else larg))
        im = Image.new("1", (larg, altura), 0)
        d = ImageDraw.Draw(im)
        d.fontmode = "1"
        d.text((esq, dy), ch, font=fonte, fill=1)
        return larg, im.tobytes()

    vazio = desenhar("\U0010fffe")
    glifos = {}
    for ch in letras:
        g = desenhar(ch)
        if ch != " " and (g == vazio or not any(g[1])):
            continue
        glifos[ord(ch)] = g
    return glifos


def gerar_atlas(saida, pasta_fontes=None):
    pastas = [pasta_fontes] if pasta_fontes else ["/usr/share/fonts/truetype", os.path.join(CASA, ".local/share/fonts"), "/usr/share/fonts/opentype"]

    def achar(rel):
        for p in pastas:
            c = os.path.join(p, rel)
            if os.path.isfile(c):
                return c
        raise Erro("fonte não encontrada: %s" % rel)

    indice, blobs, pos = {"alturas": list(ALTURAS_ATLAS), "faces": {}}, [], 0
    for chave, nome, normal, negrito, licenca in FAMILIAS_GERAR:
        pesos = {}
        for peso, rel in (("normal", normal), ("negrito", negrito)):
            partes = [bytes([len(ALTURAS_ATLAS)])]
            for h in ALTURAS_ATLAS:
                corpo = b"".join(struct.pack(">HB", cp, w) + linhas for cp, (w, linhas) in sorted(rasterizar(achar(rel), h, LETRAS_ATLAS).items()) if cp < 65536)
                partes.append(struct.pack(">BI", h, len(corpo)) + corpo)
            z = zlib.compress(b"".join(partes), 9)
            pesos[peso] = [pos, len(z)]
            blobs.append(z)
            pos += len(z)
        indice["faces"][chave] = {"nome": nome, "licenca": licenca, "pesos": pesos}
    with open(saida, "wb") as f:
        f.write(b"TTLF1\n" + json.dumps(indice, ensure_ascii=False, sort_keys=True).encode("utf-8") + b"\n" + b"".join(blobs))
    return indice, pos


class Atlas:
    def __init__(self, caminho=ATLAS):
        self.faces, self._base, self._caminho, self._pesos = {}, 0, caminho, {}
        try:
            with open(caminho, "rb") as f:
                if f.readline() != b"TTLF1\n":
                    return
                indice = json.loads(f.readline().decode("utf-8"))
                self._base = f.tell()
            self.faces = indice.get("faces") or {}
        except (OSError, ValueError):
            self.faces = {}

    def familias(self):
        return list(self.faces)

    def nome(self, familia):
        return (self.faces.get(familia) or {}).get("nome") or familia

    def peso(self, familia, negrito):
        """{altura: {código: (largura, [linhas como inteiros])}} do peso pedido (lido e descomprimido uma vez)."""
        chave = (familia, bool(negrito))
        if chave not in self._pesos:
            alturas = {}
            face = self.faces.get(familia) or {}
            ref = (face.get("pesos") or {}).get("negrito" if negrito else "normal") or (face.get("pesos") or {}).get("normal")
            if ref:
                with open(self._caminho, "rb") as f:
                    f.seek(self._base + ref[0])
                    dados = zlib.decompress(f.read(ref[1]))
                p = 1
                for _ in range(dados[0]):
                    h, tam = struct.unpack_from(">BI", dados, p)
                    p += 5
                    alturas[h] = (dados, p, p + tam, {})
                    p += tam
            self._pesos[chave] = alturas
        return self._pesos[chave]


class Fonte:
    """Uma família num peso: dá a letra em qualquer altura (guardada, ou reduzida/ampliada da matriz de 48)."""

    def __init__(self, atlas, familia, negrito):
        self.alturas = atlas.peso(familia, negrito)
        self._indices = {}
        self._cache = {}

    def _guardado(self, h, cp):
        ref = self.alturas.get(h)
        if not ref:
            return None
        dados, ini, fim, _ = ref
        idx = self._indices.get(h)
        if idx is None:
            idx, p = {}, ini
            while p < fim:
                c, w = struct.unpack_from(">HB", dados, p)
                idx[c] = (p + 3, w)
                p += 3 + h * ((w + 7) // 8)
            self._indices[h] = idx
        if cp not in idx:
            return None
        p, w = idx[cp]
        nb = (w + 7) // 8
        desloc = nb * 8 - w
        return w, [int.from_bytes(dados[p + y * nb:p + (y + 1) * nb], "big") >> desloc for y in range(h)]

    def tem(self, ch):
        return self._guardado(MESTRE, ord(ch)) is not None

    def glifo(self, ch, h):
        chave = (ch, h)
        g = self._cache.get(chave)
        if g is None:
            g = self._guardado(h, ord(ch))
            if g is None:
                m = self._guardado(MESTRE, ord(ch))
                g = _escalar(m, MESTRE, h) if m else None
            self._cache[chave] = g
        return g


def _escalar(glifo, de, para):
    w, linhas = glifo
    f = para / de
    tw = max(1, int(round(w * f)))
    limiar = 0.42 if f < 1 else 0.5
    saida = []
    for ty in range(para):
        y0 = int(ty / f)
        y1 = min(de, max(y0 + 1, int((ty + 1) / f + 0.999)))
        acc = 0
        for tx in range(tw):
            x0 = int(tx / f)
            x1 = min(w, max(x0 + 1, int((tx + 1) / f + 0.999)))
            mascara = ((1 << (x1 - x0)) - 1) << (w - x1)
            n = 0
            for y in range(y0, y1):
                n += bin(linhas[y] & mascara).count("1")
            acc = (acc << 1) | (1 if n >= limiar * (y1 - y0) * (x1 - x0) and n else 0)
        saida.append(acc)
    return tw, saida


def letras_grandes(fonte, texto, linhas, traco, italico=False, destaque=None):
    """Desenha `texto` em `linhas` linhas do terminal. Devolve (largura em células, [linhas], (c0, c1) do destaque):
    cada linha é uma lista de (trecho, destacado). None se alguma letra não existe no atlas."""
    pts = linhas * (4 if traco in ("pontos", "fino") else 2)
    glifos = []
    for ch in texto:
        g = fonte.glifo(ch, pts)
        if g is None:
            base = unicodedata.normalize("NFKD", ch)[:1]
            g = fonte.glifo(base, pts) if base and base != ch else None
            if g is None:
                return None
        glifos.append(g)
    larg = sum(g[0] for g in glifos) or 1
    bits = [0] * pts
    faixas, x = [], 0
    for w, rows in glifos:
        for y in range(pts):
            bits[y] = (bits[y] << w) | rows[y]
        faixas.append((x, x + w))
        x += w
    if traco in ("fino", "cheio"):  # o ponto destes traços é o dobro mais alto: junta as linhas duas a duas
        bits = [bits[y] | bits[y + 1] for y in range(0, pts, 2)]
        pts //= 2
    incl = [int((pts - 1 - y) * 0.22 + 0.5) if italico else 0 for y in range(pts)]
    extra = max(incl) if incl else 0
    total = larg + extra
    mapa = [format(bits[y] << (extra - incl[y]), "0%db" % total) for y in range(pts)]
    px, py = {"pontos": (2, 4), "fino": (2, 2), "blocos": (1, 2), "cheio": (1, 1)}[traco]
    if total % px:
        mapa = [l + "0" * (px - total % px) for l in mapa]
        total += px - total % px
    cols = total // px
    d0 = d1 = -1
    if destaque is not None and 0 <= destaque < len(faixas):
        meio = extra // 2
        d0, d1 = (faixas[destaque][0] + meio) // px, (faixas[destaque][1] + meio + px - 1) // px
    saida = []
    for r in range(0, pts, py):
        chars = []
        for c in range(cols):
            x = c * px
            if traco == "pontos":
                a, b, c2, d = mapa[r], mapa[r + 1], mapa[r + 2], mapa[r + 3]
                v = ((a[x] == "1") | (b[x] == "1") << 1 | (c2[x] == "1") << 2 | (a[x + 1] == "1") << 3 |
                     (b[x + 1] == "1") << 4 | (c2[x + 1] == "1") << 5 | (d[x] == "1") << 6 | (d[x + 1] == "1") << 7)
                chars.append(chr(0x2800 + v) if v else " ")
            elif traco == "fino":
                a, b = mapa[r], mapa[r + 1]
                chars.append(_QUADRANTES[(a[x] == "1") | (a[x + 1] == "1") << 1 | (b[x] == "1") << 2 | (b[x + 1] == "1") << 3])
            elif traco == "blocos":
                chars.append(" ▀▄█"[(mapa[r][x] == "1") | (mapa[r + 1][x] == "1") << 1])
            else:
                chars.append("█" if mapa[r][x] == "1" else " ")
        s = "".join(chars)
        if d0 >= 0:
            saida.append([(s[:d0], False), (s[d0:d1], True), (s[d1:], False)])
        else:
            saida.append([(s, False)])
    return cols, saida, (d0, d1)


# --- Motor: palavras, ponto de foco, tempos ---------------------------------------------------------------------------

_FECHOS = "\"'”’»)]}"


def termina_frase(p):
    return p.rstrip(_FECHOS)[-1:] in ".!?…"


class Texto:
    """As palavras do livro em sequência, com o que separa uma da outra. `quebra[i]` diz o que vem depois da palavra i:
    0 nada, 1 fim de parágrafo, 2 fim de um título (o texto dele começa), 3 fim de uma seção (vem um título),
    4 fim de capítulo. `titulo[i]` = a palavra faz parte de um título."""

    def __init__(self, livro):
        self.pal, self.fim_par, self.caps, self.par_ini = [], bytearray(), [], []
        self.quebra, self.titulo = bytearray(), bytearray()
        pars = []  # (início, fim, é título, capítulo)
        niveis = []
        for c in livro.get("capitulos") or []:
            ini = len(self.pal)
            tit = " ".join((c.get("titulo") or "").split())
            primeiro = True
            for p in c.get("paragrafos") or []:
                ws = p.split()
                if not ws:
                    continue
                self.par_ini.append(len(self.pal))
                pars.append([len(self.pal), len(self.pal) + len(ws), bool(primeiro and tit and " ".join(ws) == tit), len(self.caps)])
                primeiro = False
                self.pal.extend(ws)
                self.fim_par.extend(b"\0" * (len(ws) - 1) + b"\1")
            if len(self.pal) > ini:
                self.caps.append((ini, c.get("titulo") or ""))
                try:
                    niveis.append(max(1, int(c.get("nivel") or 1)))
                except (TypeError, ValueError):
                    niveis.append(1)
        self.n = len(self.pal)
        if not self.caps:
            self.caps = [(0, "")]
        self.cap_nivel = niveis or [1]
        # subtítulo sem marca: linha curta, sem ponto no fim, entre parágrafos de verdade
        def solta(k):
            a, b = pars[k][0], pars[k][1]
            return b - a <= 12 and sum(len(w) for w in self.pal[a:b]) <= 80 and self.pal[b - 1][-1:] not in ".,;:!?…\"”’»)" \
                and (self.pal[a][:1].isupper() or self.pal[a][:1].isdigit())
        soltas = [solta(k) for k in range(len(pars))]
        for k in range(1, len(pars) - 1):
            if (soltas[k] and not pars[k][2] and not soltas[k - 1] and not soltas[k + 1] and pars[k + 1][3] == pars[k][3]
                    and pars[k + 1][1] - pars[k + 1][0] > 12):
                pars[k][2] = True
        self.quebra = bytearray(self.n)
        self.titulo = bytearray(self.n)
        for k, (a, b, tit, cap) in enumerate(pars):
            if tit:
                self.titulo[a:b] = b"\1" * (b - a)
            if k + 1 >= len(pars):
                q = 0
            elif pars[k + 1][3] != cap:
                q = 4 if niveis[pars[k + 1][3]] <= 1 else 3
            elif tit:
                q = 2
            elif pars[k + 1][2]:
                q = 3
            else:
                q = 1
            self.quebra[b - 1] = q

    def _antes(self, lista, i):
        import bisect
        return max(0, bisect.bisect_right(lista, i) - 1)

    def ini_frase(self, i):
        i = max(0, min(i, self.n - 1))
        while i > 0 and not self.fim_par[i - 1] and not termina_frase(self.pal[i - 1]):
            i -= 1
        return i

    def prox_frase(self, i):
        i = max(0, i)
        while i < self.n - 1 and not self.fim_par[i] and not termina_frase(self.pal[i]):
            i += 1
        return min(self.n - 1, i + 1)

    def par(self, i):
        k = self._antes(self.par_ini, i)
        fim = self.par_ini[k + 1] if k + 1 < len(self.par_ini) else self.n
        return k, self.par_ini[k], fim

    def cap(self, i):
        k = self._antes([c[0] for c in self.caps], i)
        return k, self.caps[k][1]

    def buscar(self, termo, de, para_tras=False):
        alvo = sem_acento(termo).split()
        if not alvo or not self.n:
            return -1
        if not hasattr(self, "_chave"):
            self._chave = [sem_acento(p) for p in self.pal]
        ordem = range(de - 1, -1, -1) if para_tras else range(de + 1, self.n)
        for volta in (ordem, range(self.n - 1, de, -1) if para_tras else range(0, de + 1)):
            for i in volta:
                if alvo[0] in self._chave[i] and all(i + k < self.n and a in self._chave[i + k] for k, a in enumerate(alvo)):
                    return i
        return -1


def sem_acento(s):
    return "".join(c for c in unicodedata.normalize("NFKD", s.lower()) if not unicodedata.combining(c))


def ponto_foco(p):
    """Índice da letra em que o olho pousa (um pouco antes do meio): é ela que fica sempre na mesma coluna."""
    i0, j = 0, len(p)
    while i0 < j - 1 and not p[i0].isalnum():
        i0 += 1
    while j > i0 + 1 and not p[j - 1].isalnum():
        j -= 1
    n = j - i0
    return i0 + (0 if n <= 1 else 1 if n <= 5 else 2 if n <= 9 else 3 if n <= 13 else 4)


def fator_tempo(p, fim_par, prefs, titulo=False):
    """Quanto tempo a palavra fica na tela, em múltiplos de 60/ppm: palavra longa, número e pontuação pedem mais.
    O respiro entre parágrafos, títulos e capítulos é outro tempo, com a tela vazia: ver pausa_apos."""
    f = 1.0
    n = len(p)
    if prefs["longas"] and n > 7:
        f += min(0.8, (n - 7) * 0.07)
    pont = prefs["pontuacao"]
    u = p.rstrip(_FECHOS)[-1:]
    extra = 0.0
    if u in ".!?…":
        extra = 1.1
    elif u in ",;:" or p in ("—", "–", "-"):
        extra = 0.5
    if fim_par:
        extra = max(extra, 1.1)
    f += extra * pont
    if any(c.isdigit() for c in p):
        f += 0.35
    if titulo:
        f *= 1.3
    return f


# quebra → (palavras de tempo, segundos): o respiro cresce do parágrafo ao capítulo e não some em velocidade alta
# (um pouco, e um pouco mais conforme a importância: parágrafo < título < capítulo). Em cada respiro a tela mostra,
# apagada e no lugar do foco, a marca do que acabou: | parágrafo, * título (antes e depois dele), # capítulo.
PAUSAS = {1: (0.7, 0.16), 2: (1.2, 0.30), 3: (1.2, 0.30), 4: (1.8, 0.50)}
PAUSA_MARCA = {1: "|", 2: "*", 3: "*", 4: "#"}


def pausa_apos(quebra, prefs):
    """Segundos de tela vazia depois de uma palavra que fecha parágrafo (1), título (2), seção (3) ou capítulo (4)."""
    if not quebra or not prefs.get("respiro"):
        return 0.0
    pal, seg = PAUSAS.get(int(quebra), (0, 0))
    return (pal * 60.0 / prefs["ppm"] + seg) * prefs["respiro"]


def partir(palavra, cabe):
    """A palavra que não cabe na tela vira pedaços que cabem: primeiro nos hifens; depois em partes iguais, as
    maiores que couberem, com hífen no fim de cada uma menos a última."""
    if cabe(palavra) or len(palavra) < 4:
        return [palavra]
    pedacos = [x for x in re.split(r"(?<=[-–—/_.])(?=\w)", palavra) if x]
    if len(pedacos) > 1:
        saida = []
        for x in pedacos:
            saida.extend(partir(x, cabe))
        return saida
    maior = len(palavra) - 1
    while maior > 2 and not cabe(palavra[:maior] + "-"):
        maior -= 1
    n = -(-len(palavra) // maior)
    tam = -(-len(palavra) // n)
    partes = [palavra[i:i + tam] for i in range(0, len(palavra), tam)]
    if len(partes) > 1 and len(partes[-1]) < 2:  # nunca uma letra sozinha no fim
        partes[-2:] = [partes[-2] + partes[-1]]
    return [x + "-" for x in partes[:-1]] + [partes[-1]]


def larg_c(ch):
    o = ord(ch)
    if o < 0x300:
        return 1 if o >= 32 else 0
    if unicodedata.combining(ch) or o == 0x200d or 0xfe00 <= o <= 0xfe0f:
        return 0
    return 2 if unicodedata.east_asian_width(ch) in "WF" else 1


def larg(s):
    return len(s) if s.isascii() else sum(larg_c(c) for c in s)


def cortar(s, n):
    if larg(s) <= n:
        return s
    saida, w = [], 0
    for ch in s:
        cw = larg_c(ch)
        if w + cw > max(0, n - 1):
            break
        saida.append(ch)
        w += cw
    return "".join(saida) + ("…" if n > 0 else "")


# --- Leitura na faixa do tt (motor) -----------------------------------------------------------------------------------
# Na barra do tt a leitura acontece no lugar do letreiro: quem pinta é o letreiro-tt.py de cada cliente (o único
# caminho que muda a barra sem redesenhar a tela), que só LÊ o roteiro que este motor escreve. O motor é um processo
# por máquina: guarda o texto, recebe os comandos por um fifo (`tt --leitor-ctl`), agenda cada palavra numa hora
# exata, alinhada à grade de quadros da barra (1/fps s), grava a posição na biblioteca e chama a troca entre as
# máquinas ao pausar e ao parar. Pasta: ~/.cache/tt-leitor/barra/{roteiro.json, ctl, pid, fps}.

BARRA = os.environ.get("TT_LEITOR_BARRA_DIR") or os.path.join(CASA, ".cache", "tt-leitor", "barra")
BARRA_MAX_PALAVRA = 28   # palavra maior que isto é mostrada em pedaços (o miolo da faixa é estreito)
BARRA_HORIZONTE = 40     # segundos de leitura agendados à frente
BARRA_OCIOSO = 8 * 3600  # pausado por tanto tempo, o motor devolve a faixa ao letreiro


def motor_pid():
    try:
        with open(os.path.join(BARRA, "pid")) as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
        return pid
    except (OSError, ValueError):
        return 0


def motor_ctl(comando):
    """Manda um comando ao motor em execução (False se não há motor)."""
    if not motor_pid():
        return False
    try:
        fd = os.open(os.path.join(BARRA, "ctl"), os.O_WRONLY | os.O_NONBLOCK)
        try:
            os.write(fd, (comando + "\n").encode("utf-8"))
        finally:
            os.close(fd)
        return True
    except OSError:
        return False


def fps_para(ppm):
    """Quadros por segundo da barra para a velocidade: pelo menos dois quadros por palavra comum, de 8 a 20."""
    return max(8, min(20, -(-ppm * 2 // 60)))


class Motor:
    def __init__(self, lid):
        self.prefs = ler_prefs()
        self.v = 0
        self.msg = ("", 0)
        self.fila = []
        self.tocando = False
        self.voltar = False
        self.salvo_pos = -1
        self.salvo_em = 0
        self.pausado_em = time.time()
        self.ultimo_sync = 0
        self.falta_sync = False
        self.estado_mtime = 0
        self.lid = None
        if not self.abrir(lid):
            raise Erro("não consegui abrir o texto %s" % lid)

    def abrir(self, lid):
        try:
            txt = Texto(ler_texto(lid))
        except (Erro, OSError, ValueError):
            return False
        if not txt.n:
            return False
        if self.lid:
            self.pausar()
        self.lid, self.txt, self.meta = lid, txt, ler_meta(lid)
        est = ler_estado(lid)
        self.pos = max(0, min(int(est.get("pos") or 0), txt.n - 1))
        if est.get("concluido") and self.pos >= txt.n - 1:
            self.pos = 0
        self.sub, self.fila, self.tocando, self.voltar = 0, [], False, False
        self.salvo_pos = self.pos
        self.estado_mtime = self._mtime()
        outra = est.get("maquina")
        if outra and outra != maquina() and self.pos:
            self.avisar("continuando de onde você parou em %s" % outra, 4)
        return True

    def _mtime(self):
        try:
            return os.stat(os.path.join(pasta(self.lid), "estado.json")).st_mtime_ns
        except OSError:
            return 0

    def avisar(self, texto, seg=2.5):
        self.msg = (texto, time.time() + seg)

    def fps(self):
        return fps_para(self.prefs["ppm"])

    # -- unidades e agenda --
    def unidade(self, pos):
        t = self.txt
        k = 1
        while k < self.prefs["grupo"] and pos + k < t.n and not t.fim_par[pos + k - 1] and not termina_frase(t.pal[pos + k - 1]):
            k += 1
        while k > 1 and larg(" ".join(t.pal[pos:pos + k])) > BARRA_MAX_PALAVRA + 12:
            k -= 1
        if k > 1:
            return k, [" ".join(t.pal[pos:pos + k])]
        return 1, partir(t.pal[pos], lambda x: larg(x) <= BARRA_MAX_PALAVRA)

    def _entrada(self, pos, sub):
        k, partes = self.unidade(pos)
        texto = partes[min(sub, len(partes) - 1)]
        return k, partes, texto, (ponto_foco(texto) if " " not in texto else -1)

    def agendar(self, agora):
        """Completa a fila até o horizonte. Cada entrada: [hora, texto, letra de foco, posição, pedaço]."""
        t, fps = self.txt, self.fps()
        if not self.fila:
            quadro_n = int(agora * fps) + 2
            pos, sub, rampa = self.pos, self.sub, (4 if self.prefs["arranque"] else 0)
        else:
            ult = self.fila[-1]
            quadro_n, pos, sub, rampa = ult[5], ult[6], ult[7], ult[8]
        mudou = False
        while pos < t.n and quadro_n / fps < agora + BARRA_HORIZONTE:
            k, partes, texto, foco = self._entrada(pos, sub)
            dur = sum(fator_tempo(t.pal[i], t.fim_par[i], self.prefs, t.titulo[i]) for i in range(pos, min(t.n, pos + k)))
            if k > 1:
                dur *= 0.9
            if len(partes) > 1:
                dur = max(0.7, dur * len(partes[sub]) / max(1, sum(len(x) for x in partes)))
            if rampa > 0:
                dur *= 1 + 0.25 * rampa
                rampa -= 1
            quadros = max(1, int(round(dur * 60.0 / self.prefs["ppm"] * fps)))
            if sub + 1 < len(partes):
                prox_pos, prox_sub = pos, sub + 1
            else:
                prox_pos, prox_sub = pos + k, 0
            # [hora, texto, foco, pos, pedaço, quadro seguinte, posição seguinte, pedaço seguinte, rampa que resta, tipo]
            # tipo: 0 palavra, 1 palavra de título, 2 respiro (tela vazia entre parágrafos, títulos e capítulos)
            self.fila.append([quadro_n / fps, texto, foco, pos, sub, quadro_n + quadros, prox_pos, prox_sub, rampa, int(t.titulo[pos])])
            quadro_n, pos, sub = quadro_n + quadros, prox_pos, prox_sub
            q = t.quebra[pos - 1] if sub == 0 and 0 < pos < t.n else 0
            resp = pausa_apos(q, self.prefs)
            if resp > 0:
                quadros = max(1, int(round(resp * fps)))
                self.fila.append([quadro_n / fps, PAUSA_MARCA.get(q, "") if self.prefs["marcas"] else "", 0, pos, 0, quadro_n + quadros, pos, 0, rampa, 2])
                quadro_n += quadros
            mudou = True
        return mudou

    def atual(self, agora):
        """Põe self.pos na palavra que a barra mostra agora. True se o texto acabou."""
        if not self.tocando or not self.fila:
            return False
        i = 0
        while i + 1 < len(self.fila) and self.fila[i + 1][0] <= agora:
            i += 1
        if i:
            del self.fila[:i]
        e = self.fila[0]
        if e[0] <= agora:
            self.pos, self.sub = e[3], e[4]
        return len(self.fila) == 1 and e[6] >= self.txt.n and agora >= e[5] / self.fps()

    # -- comandos --
    def tocar(self):
        if self.pos >= self.txt.n - 1:
            self.pos, self.sub = 0, 0
        elif self.prefs["retomada"] and self.pos > 0 and self.voltar:
            self.pos, self.sub = max(self.txt.par(self.pos)[1], self.pos - self.prefs["retomada"]), 0
        self.voltar, self.tocando, self.fila = False, True, []
        self.msg = ("", 0)  # tocando, o miolo é das palavras
        self.agendar(time.time())

    def pausar(self):
        if self.tocando:
            self.atual(time.time())
            self.tocando, self.fila, self.voltar = False, [], True
            self.pausado_em = time.time()
        self.salvar()
        self.sincronizar()

    def ir(self, pos):
        self.pos, self.sub = max(0, min(int(pos), self.txt.n - 1)), 0
        self.voltar = False
        if self.tocando:
            self.fila = []
            self.agendar(time.time())
        else:
            self.pausado_em = time.time()

    def saltar(self, direcao, longo):
        if self.tocando:
            self.atual(time.time())
        seg = self.prefs["salto_longo" if longo else "salto_curto"]
        t = self.txt
        if seg:
            self.ir(self.pos + direcao * max(1, round(self.prefs["ppm"] * seg / 60 / 1.2)))
        elif longo:
            k, ini, fim = t.par(self.pos)
            self.ir(fim if direcao > 0 else (ini if self.pos > ini else t.par_ini[max(0, k - 1)]))
        else:
            ini = t.ini_frase(self.pos)
            self.ir(t.prox_frase(self.pos) if direcao > 0 else (ini if self.pos > ini else t.ini_frase(max(0, ini - 1))))

    def ppm(self, d):
        self.prefs["ppm"] = max(PPM_MIN, min(PPM_MAX, self.prefs["ppm"] + d))
        gravar_prefs(self.prefs)
        if self.tocando:
            self.atual(time.time())
            self.fila = []
            self.agendar(time.time())
        else:  # tocando, o número ao lado do − e do + já mostra; o aviso taparia as palavras
            self.avisar("%d palavras por minuto" % self.prefs["ppm"], 1.2)

    def comando(self, linha):
        """Executa um comando. False = parar o motor."""
        partes = linha.split()
        if not partes:
            return True
        c, arg = partes[0], (partes[1] if len(partes) > 1 else "")
        t = self.txt
        if c == "parar":
            return False
        if c == "alternar":
            self.pausar() if self.tocando else self.tocar()
        elif c == "tocar":
            self.tocando or self.tocar()
        elif c == "pausar":
            self.pausar()
        elif c in ("curto-", "curto+", "longo-", "longo+"):
            self.saltar(1 if c.endswith("+") else -1, c.startswith("longo"))
        elif c in ("palavra-", "palavra+", "frase-", "frase+", "par-", "par+", "cap-", "cap+"):
            if self.tocando:
                self.atual(time.time())
            d = 1 if c.endswith("+") else -1
            if c.startswith("palavra"):
                self.ir(self.pos + d)
            elif c.startswith("frase"):
                ini = t.ini_frase(self.pos)
                self.ir(t.prox_frase(self.pos) if d > 0 else (ini if self.pos > ini else t.ini_frase(max(0, ini - 1))))
            elif c.startswith("par"):
                k, ini, fim = t.par(self.pos)
                self.ir(fim if d > 0 else (ini if self.pos > ini else t.par_ini[max(0, k - 1)]))
            else:
                k, _ = t.cap(self.pos)
                if d < 0 and self.pos > t.caps[k][0]:
                    self.ir(t.caps[k][0])
                else:
                    self.ir(t.caps[max(0, min(len(t.caps) - 1, k + d))][0])
                self.avisar(cortar(t.cap(self.pos)[1] or "parte %d" % (t.cap(self.pos)[0] + 1), 40), 2)
        elif c == "inicio":
            self.ir(0)
        elif c == "decimo" and arg.isdigit():  # as teclas 0…9: 0%, 10% … 90% do texto
            self.ir(t.n * min(9, int(arg)) // 10)
            self.avisar("%d%% do texto" % (min(9, int(arg)) * 10), 1.5)
        elif c == "marcar":
            if self.tocando:
                self.atual(time.time())
            est = ler_estado(self.lid)
            ini = t.ini_frase(self.pos)
            nome = cortar(" ".join(t.pal[ini:ini + 8]), 60)
            est["marcadores"][str(self.pos)] = {"nome": nome, "mudada": agora_ms(), "removido": False}
            gravar_estado(self.lid, est)
            self.estado_mtime, self.falta_sync = self._mtime(), True
            self.avisar("marcado: " + cortar(nome, 30), 2.5)
        elif c == "ir" and arg:
            try:
                self.ir(int(float(arg[:-1]) * t.n / 100) if arg.endswith("%") else int(arg))
            except ValueError:
                pass
        elif c == "ppm+":
            self.ppm(25)
        elif c == "ppm-":
            self.ppm(-25)
        elif c == "abrir" and ID_RE.match(arg):
            if arg != self.lid and not self.abrir(arg):
                self.avisar("não consegui abrir esse texto", 4)
        elif c == "recarregar":
            ppm = self.prefs["ppm"]
            self.prefs = ler_prefs()
            if self.tocando:
                self.atual(time.time())
                self.fila = []
                self.agendar(time.time())
            if ppm != self.prefs["ppm"]:
                self.avisar("%d palavras por minuto" % self.prefs["ppm"], 1.2)
        return True

    # -- disco --
    def salvar(self):
        if self.pos != self.salvo_pos:
            try:
                marcar_posicao(self.lid, self.pos, self.txt.n)
                self.falta_sync = True
            except OSError:
                pass
            self.salvo_pos = self.pos
            self.estado_mtime = self._mtime()
        self.salvo_em = time.time()

    def sincronizar(self):
        tt = os.environ.get("TT_LEITOR_TT")
        if not tt or not self.falta_sync or time.time() - self.ultimo_sync < 20:
            return
        self.ultimo_sync, self.falta_sync = time.time(), False
        try:
            subprocess.Popen([tt, "--leitor-sync", "--quieto"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError:
            pass

    def conferir_rede(self):
        """Pausado: se a troca trouxe uma posição mais nova de outra máquina, a leitura passa a estar lá."""
        m = self._mtime()
        if m == self.estado_mtime:
            return False
        self.estado_mtime = m
        est = ler_estado(self.lid)
        p = max(0, min(int(est.get("pos") or 0), self.txt.n - 1))
        if est.get("maquina") in (None, "", maquina()) or p == self.pos:
            return False
        self.pos, self.sub, self.salvo_pos, self.voltar = p, 0, p, False
        self.avisar("%s está em %d%%: continuo de lá" % (est["maquina"], p * 100 // max(1, self.txt.n)), 5)
        return True

    def gravar_roteiro(self):
        self.v += 1
        t = self.txt
        if self.tocando and self.fila:
            palavras = [e[:4] + [e[9]] for e in self.fila]
        else:
            _, _, texto, foco = self._entrada(self.pos, self.sub)
            palavras = [[0, texto, foco, self.pos, int(t.titulo[self.pos])]]
        gravar_json(os.path.join(BARRA, "roteiro.json"), {
            "v": self.v, "pid": os.getpid(), "lid": self.lid, "titulo": self.meta.get("titulo") or "", "tocando": self.tocando,
            "ppm": self.prefs["ppm"], "fps": self.fps(), "n": t.n, "pos": self.pos, "palavras": palavras,
            "fim": (self.fila[-1][5] / self.fps()) if self.tocando and self.fila else 0,
            "msg": list(self.msg) if self.msg[1] > time.time() else ["", 0],
            "salto_curto": self.prefs["salto_curto"], "salto_longo": self.prefs["salto_longo"]})
        try:
            with open(os.path.join(BARRA, "fps")) as f:
                antes = f.read().strip()
        except OSError:
            antes = ""
        if antes != str(self.fps()):
            gravar(os.path.join(BARRA, "fps"), "%d\n" % self.fps())

    def rodar(self):
        fifo = os.path.join(BARRA, "ctl")
        try:
            os.unlink(fifo)
        except OSError:
            pass
        os.mkfifo(fifo, 0o600)
        fd = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)  # leitura e escrita: o fifo nunca dá fim de arquivo
        gravar(os.path.join(BARRA, "pid"), "%d\n" % os.getpid())
        self.gravar_roteiro()
        resto = b""
        try:
            while True:
                agora = time.time()
                if self.tocando:
                    prazo = min(10.0, max(0.05, (self.fila[-1][5] / self.fps() - agora) if len(self.fila) == 1 else 10.0))
                else:
                    prazo = 30.0
                if self.msg[1] > agora:
                    prazo = min(prazo, self.msg[1] - agora + 0.05)
                prontos, _, _ = select.select([fd], [], [], prazo)
                mudou = False
                if prontos:
                    try:
                        resto += os.read(fd, 4096)
                    except BlockingIOError:
                        pass
                    while b"\n" in resto:
                        linha, resto = resto.split(b"\n", 1)
                        if not self.comando(linha.decode("utf-8", "replace").strip()):
                            return
                        mudou = True
                agora = time.time()
                if self.tocando:
                    if self.atual(agora):
                        self.tocando, self.fila = False, []
                        self.pos, self.sub = self.txt.n - 1, 0
                        self.pausado_em = agora
                        self.avisar("fim do texto", 6)
                        self.salvar()
                        self.sincronizar()
                        mudou = True
                    else:
                        mudou = self.agendar(agora) or mudou
                        if agora - self.salvo_em > 15:
                            self.salvar()
                        if agora - self.ultimo_sync > 300:  # leitura longa sem pausa: as outras máquinas acompanham
                            self.sincronizar()
                else:
                    mudou = self.conferir_rede() or mudou
                    if agora - self.pausado_em > BARRA_OCIOSO:
                        return
                if self.msg[0] and self.msg[1] <= agora:
                    self.msg, mudou = ("", 0), True
                if mudou:
                    self.gravar_roteiro()
        finally:
            if self.tocando:
                self.atual(time.time())
            self.salvar()
            self.falta_sync = self.falta_sync or self.ultimo_sync > 0
            self.ultimo_sync = 0
            self.sincronizar()
            os.close(fd)
            for n in ("roteiro.json", "ctl", "pid", "fps"):
                try:
                    os.unlink(os.path.join(BARRA, n))
                except OSError:
                    pass


def cmd_motor(args):
    """leitor-tt.py motor ID [--frente] [--tocar]: põe a leitura na faixa do tt (um motor por máquina)."""
    lid = resolver(args[0])
    if motor_pid():
        motor_ctl("abrir " + lid)
        if "--tocar" in args:
            motor_ctl("tocar")
        return 0
    ler_texto(lid)  # falha aqui, com a mensagem, e não num processo que ninguém vê
    os.makedirs(BARRA, exist_ok=True)
    if "--frente" not in args:
        if os.fork():
            fim = time.time() + 5  # só volta quando o roteiro existe: quem chamou já pode desenhar a barra
            while time.time() < fim and not os.path.exists(os.path.join(BARRA, "roteiro.json")):
                time.sleep(0.02)
            return 0
        os.setsid()
        if os.fork():
            os._exit(0)
        nulo = os.open(os.devnull, os.O_RDWR)
        for fd in (0, 1, 2):
            os.dup2(nulo, fd)
    for s_ in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(s_, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    m = Motor(lid)
    if "--tocar" in args:
        m.tocar()
    try:
        m.rodar()
    except KeyboardInterrupt:
        pass
    if "--frente" not in args:
        os._exit(0)
    return 0


# --- Preferências -----------------------------------------------------------------------------------------------------

TEMAS = {  # fundo, letra, apagado, foco, destaque
    "noite": ("#1e1e2e", "#cdd6f4", "#6c7086", "#f38ba8", "#89b4fa"),
    "preto": ("#000000", "#e4e4e4", "#5c5c5c", "#ff5c57", "#57c7ff"),
    "grafite": ("#2b2b2b", "#d6d6d6", "#7a7a7a", "#ff8a65", "#80cbc4"),
    "sépia": ("#f4ecd8", "#433422", "#a08f6c", "#b5451b", "#7a5c2e"),
    "papel": ("#fbfbf8", "#1c1c1c", "#9b9b9b", "#d32f2f", "#1565c0"),
    "fósforo": ("#001a06", "#33ff66", "#1b8a3a", "#ffffff", "#b6ff00"),
    "âmbar": ("#1a1000", "#ffb000", "#8a6000", "#ffffff", "#ffd966"),
    "contraste": ("#000000", "#ffffff", "#b0b0b0", "#ffff00", "#00ffff"),
    "terminal": (None, None, None, "#ff5555", None),
}
CORES_LETRA = (("do tema", None), ("branco", "#ffffff"), ("creme", "#f5e6c8"), ("cinza claro", "#c8c8c8"), ("verde", "#a6e3a1"),
               ("âmbar", "#ffcb6b"), ("azul", "#89b4fa"), ("rosa", "#f5c2e7"), ("preto", "#101010"), ("marrom", "#4e342e"))
CORES_FOCO = (("do tema", None), ("vermelho", "#ff5555"), ("laranja", "#ff9e64"), ("amarelo", "#ffe066"), ("verde", "#50fa7b"),
              ("ciano", "#8be9fd"), ("azul", "#5c9dff"), ("magenta", "#ff79c6"), ("igual à letra", "letra"))
ESTILOS = ("negrito", "normal", "negrito itálico", "itálico")
PADRAO = {"ppm": 300, "grupo": 1, "fonte": "sans", "tamanho": 6, "traco": "fino", "estilo": "negrito", "tema": "noite",
          "cor_letra": 0, "cor_foco": 0, "guia": True, "foco_pos": "esquerda", "pontuacao": 1.0, "respiro": 1.0, "marcas": True, "longas": True, "arranque": True,
          "salto_curto": 5, "salto_longo": 30, "contexto": "pausado", "botoes": True, "retomada": 3, "cores": "auto"}
PPM_MIN, PPM_MAX = 60, 1500
SALTOS_CURTOS = (0, 2, 3, 5, 8, 10, 15)
SALTOS_LONGOS = (0, 15, 20, 30, 45, 60, 120)


def ler_prefs():
    p = dict(PADRAO)
    lido = ler_json(PREFS, {})
    for k, v in lido.items():
        if k in PADRAO and type(v) is type(PADRAO[k]) or (k in ("pontuacao", "respiro") and isinstance(v, (int, float)) and not isinstance(v, bool)):
            p[k] = v
    p["ppm"] = max(PPM_MIN, min(PPM_MAX, int(p["ppm"])))
    p["grupo"] = max(1, min(4, int(p["grupo"])))
    p["pontuacao"] = max(0.0, min(2.0, float(p["pontuacao"])))
    p["respiro"] = max(0.0, min(3.0, float(p["respiro"])))
    if p["tamanho"] not in TAMANHOS:
        p["tamanho"] = PADRAO["tamanho"]
    if p["traco"] not in TRACOS:
        p["traco"] = PADRAO["traco"]
    if p["estilo"] not in ESTILOS:
        p["estilo"] = PADRAO["estilo"]
    if p["tema"] not in TEMAS:
        p["tema"] = PADRAO["tema"]
    p["cor_letra"] %= len(CORES_LETRA)
    p["cor_foco"] %= len(CORES_FOCO)
    return p


def gravar_prefs(p):
    try:
        gravar_json(PREFS, {k: p[k] for k in PADRAO})
    except OSError:
        pass


# --- Tela -------------------------------------------------------------------------------------------------------------

NEG, ITA, SUB, INV = 1, 2, 4, 8
ESC_SEQ = float(os.environ.get("TT_ESC_SEQ") or 0.3)


def _rgb(cor):
    return int(cor[1:3], 16), int(cor[3:5], 16), int(cor[5:7], 16)


def _c256(cor):
    r, g, b = _rgb(cor)
    if abs(r - g) < 10 and abs(g - b) < 10:
        if r < 5:
            return 16
        if r > 246:
            return 231
        return 232 + min(23, max(0, round((r - 8) / 10)))
    return 16 + 36 * round(r / 255 * 5) + 6 * round(g / 255 * 5) + round(b / 255 * 5)


def modo_cores(pref="auto"):
    """24 (cor exata), 256 ou 0 (sem cor): pela preferência, pelo ambiente ou perguntando ao tmux o que o terminal aceita."""
    pref = os.environ.get("TT_LEITOR_CORES") or pref
    if pref in ("24", "256", "0"):
        return int(pref)
    if os.environ.get("NO_COLOR"):
        return 0
    if os.environ.get("COLORTERM", "").lower() in ("truecolor", "24bit"):
        return 24
    if os.environ.get("TERM_PROGRAM") == "Apple_Terminal":
        return 256
    if os.environ.get("TMUX"):
        try:
            r = subprocess.run([os.environ.get("TT_TMUX_BIN") or "tmux", "display-message", "-p", "#{client_termfeatures}"],
                               stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=2)
            return 24 if b"RGB" in r.stdout else 256
        except (OSError, subprocess.TimeoutExpired):
            return 256
    return 24 if "direct" in os.environ.get("TERM", "") or os.environ.get("TERMUX_VERSION") else 256


class Pintor:
    def __init__(self, modo):
        self.modo = modo
        self._cache = {}

    def sgr(self, fg, bg, attr):
        chave = (fg, bg, attr)
        s = self._cache.get(chave)
        if s is None:
            cod = ["0"]
            if attr & NEG:
                cod.append("1")
            if attr & ITA:
                cod.append("3")
            if attr & SUB:
                cod.append("4")
            if attr & INV:
                cod.append("7")
            if self.modo:
                for base, cor in ((38, fg), (48, bg)):
                    if cor:
                        cod.append("%d;2;%d;%d;%d" % ((base,) + _rgb(cor)) if self.modo == 24 else "%d;5;%d" % (base, _c256(cor)))
            s = self._cache[chave] = "\x1b[" + ";".join(cod) + "m"
        return s

    def montar(self, segs, W, fundo):
        saida, usado = [], 0
        for t, fg, bg, attr in segs:
            if usado >= W or not t:
                continue
            w = larg(t)
            if usado + w > W:
                corte, w = [], 0
                for ch in t:
                    cw = larg_c(ch)
                    if usado + w + cw > W:
                        break
                    corte.append(ch)
                    w += cw
                t = "".join(corte)
            saida.append(self.sgr(fg, bg or fundo, attr) + t)
            usado += w
        if usado < W:
            saida.append(self.sgr(None, fundo, 0) + " " * (W - usado))
        return "".join(saida) + "\x1b[0m"


class Tela:
    """O terminal em modo cru: tela alternativa, mouse, colagem; pinta só as linhas que mudaram."""

    def __init__(self):
        import termios
        self.termios = termios
        self.fd = sys.stdin.fileno()
        self.antigo = termios.tcgetattr(self.fd)
        novo = termios.tcgetattr(self.fd)
        novo[0] &= ~(termios.IXON | termios.ICRNL | termios.INLCR | termios.IGNCR | termios.ISTRIP)
        novo[3] &= ~(termios.ECHO | termios.ICANON | termios.ISIG | termios.IEXTEN)
        novo[6][termios.VMIN], novo[6][termios.VTIME] = 1, 0
        termios.tcsetattr(self.fd, termios.TCSADRAIN, novo)
        self.r, self.w = os.pipe()
        os.set_blocking(self.w, False)
        self.redim = True
        self.anterior = []
        self.buf = b""
        self.aberta = True
        signal.signal(signal.SIGWINCH, self._winch)
        for s in (signal.SIGTERM, signal.SIGHUP):
            signal.signal(s, self._sair)
        self._escrever("\x1b[?1049h\x1b[?25l\x1b[?1000h\x1b[?1006h\x1b[?2004h\x1b[2J")

    def _winch(self, *_):
        self.redim = True
        try:
            os.write(self.w, b"w")
        except OSError:
            pass

    def _sair(self, *_):
        raise KeyboardInterrupt

    def _escrever(self, s):
        dados = s.encode("utf-8", "replace")
        while dados:
            try:
                n = os.write(sys.stdout.fileno(), dados)
                dados = dados[n:]
            except BlockingIOError:
                select.select([], [sys.stdout.fileno()], [], 1)
            except InterruptedError:
                pass

    def fechar(self):
        if not self.aberta:
            return
        self.aberta = False
        try:
            self._escrever("\x1b[0m\x1b[?2004l\x1b[?1006l\x1b[?1000l\x1b[?25h\x1b[?1049l")
        except OSError:
            pass
        try:
            self.termios.tcsetattr(self.fd, self.termios.TCSADRAIN, self.antigo)
        except Exception:
            pass

    def tamanho(self):
        try:
            t = os.get_terminal_size(sys.stdout.fileno())
            return max(20, t.columns), max(6, t.lines)
        except OSError:
            return 80, 24

    def pintar(self, linhas):
        if self.redim or len(linhas) != len(self.anterior):
            self.anterior = [None] * len(linhas)
            self.redim = False
        saida = []
        for y, l in enumerate(linhas):
            if l != self.anterior[y]:
                saida.append("\x1b[%d;1H%s" % (y + 1, l))
        if saida:
            self._escrever("\x1b[?2026h" + "".join(saida) + "\x1b[?2026l")
            self.anterior = list(linhas)

    def ler(self, prazo):
        """Eventos até `prazo` segundos: ("tecla", nome), ("mouse", botão, x, y, apertou) ou ("cola", texto)."""
        eventos = self._decodificar()
        if eventos:
            return eventos
        try:
            prontos, _, _ = select.select([self.fd, self.r], [], [], max(0, prazo))
        except InterruptedError:
            return []
        if self.r in prontos:
            try:
                os.read(self.r, 64)
            except OSError:
                pass
        if self.fd in prontos:
            dados = os.read(self.fd, 4096)
            if not dados:
                raise KeyboardInterrupt
            self.buf += dados
            if self.buf.endswith(b"\x1b") or (self.buf.rfind(b"\x1b") >= 0 and not self._completa(self.buf[self.buf.rfind(b"\x1b"):])):
                fim = time.monotonic() + ESC_SEQ  # o resto da seta ou do clique pode chegar depois (ssh, mosh, carga)
                while time.monotonic() < fim:
                    r, _, _ = select.select([self.fd], [], [], fim - time.monotonic())
                    if not r:
                        break
                    self.buf += os.read(self.fd, 4096)
                    if self._completa(self.buf[self.buf.rfind(b"\x1b"):]):
                        break
        return self._decodificar()

    @staticmethod
    def _completa(seq):
        if seq == b"\x1b":
            return False
        if seq.startswith(b"\x1b[200~"):
            return b"\x1b[201~" in seq
        if seq[1:2] in (b"[", b"O"):
            return len(seq) > 2 and 0x40 <= seq[-1] <= 0x7e and not (seq[1:2] == b"[" and len(seq) == 3 and seq[2:3] == b"<")
        return len(seq) >= 2

    _CSI = {"A": "cima", "B": "baixo", "C": "direita", "D": "esquerda", "H": "home", "F": "end", "Z": "s-tab",
            "1~": "home", "4~": "end", "7~": "home", "8~": "end", "5~": "pgup", "6~": "pgdn", "3~": "del", "2~": "ins",
            "11~": "f1", "12~": "f2", "P": "f1", "Q": "f2"}

    def _decodificar(self):
        eventos = []
        b = self.buf
        i = 0
        while i < len(b):
            c = b[i]
            if c == 0x1b:
                if b.startswith(b"\x1b[200~", i):
                    fim = b.find(b"\x1b[201~", i)
                    if fim < 0:
                        break
                    eventos.append(("cola", b[i + 6:fim].decode("utf-8", "replace")))
                    i = fim + 6
                    continue
                if i + 1 >= len(b):
                    eventos.append(("tecla", "esc"))
                    i += 1
                    continue
                if b[i + 1:i + 2] in (b"[", b"O"):
                    j = i + 2
                    while j < len(b) and not 0x40 <= b[j] <= 0x7e:
                        j += 1
                    if j >= len(b):
                        break
                    corpo = b[i + 2:j + 1].decode("ascii", "replace")
                    i = j + 1
                    if corpo.startswith("<") and corpo[-1] in "Mm":
                        try:
                            bt, x, y = (int(v) for v in corpo[1:-1].split(";"))
                            eventos.append(("mouse", bt, x - 1, y - 1, corpo[-1] == "M"))
                        except ValueError:
                            pass
                        continue
                    mod = ""
                    m = re.fullmatch(r"(\d*);(\d+)([A-Z~])", corpo)
                    if m:
                        n = int(m.group(2)) - 1
                        mod = ("s-" if n & 1 else "") + ("a-" if n & 2 else "") + ("c-" if n & 4 else "")
                        corpo = (m.group(1) if m.group(3) == "~" else "") + m.group(3)
                    nome = self._CSI.get(corpo)
                    if nome:
                        eventos.append(("tecla", mod + nome))
                    continue
                eventos.append(("tecla", "esc"))
                i += 1
                continue
            if c < 0x20 or c == 0x7f:
                nome = {0x0d: "enter", 0x0a: "enter", 0x09: "tab", 0x7f: "backspace", 0x08: "backspace", 0x03: "c-c",
                        0x04: "c-d", 0x0c: "c-l", 0x15: "c-u", 0x17: "c-w"}.get(c)
                if nome:
                    eventos.append(("tecla", nome))
                i += 1
                continue
            n = 1 if c < 0x80 else 2 if c < 0xe0 else 3 if c < 0xf0 else 4
            if i + n > len(b):
                break
            eventos.append(("tecla", b[i:i + n].decode("utf-8", "replace")))
            i += n
        self.buf = b[i:]
        return eventos


LARANJA = "#fab387"  # a marca do respiro (| * #): outra cor, para ninguém achar que é texto

# (seção, nota, [(teclas, o que fazem)]): a tela de atalhos (?), igual na biblioteca, na leitura e na faixa.
ATALHOS = [
    ("Na faixa do tt", "Ctrl+B L liga estas teclas; outra tecla desliga", [
        ("Espaço ⏎", "tocar ou pausar"),
        ("← →", "salto curto para trás / para a frente"),
        ("PgUp PgDn", "salto longo"),
        ("↑ ↓", "mais rápido / mais devagar"),
        (", .", "uma palavra para trás / para a frente"),
        ("( )", "frase anterior / próxima"),
        ("{ }", "parágrafo anterior / próximo"),
        ("[ ]", "capítulo anterior / próximo"),
        ("0 … 9", "vai a 0%, 10% … 90% do texto"),
        ("Home", "começo do texto"),
        ("b", "marcar este ponto"),
        ("o", "abrir a biblioteca"),
        ("?", "esta tela"),
        ("x", "fechar a leitura (volta o letreiro)"),
        ("q Esc", "devolver o teclado; a leitura continua"),
    ]),
    ("Leitura em tela cheia", "T na biblioteca; letras grandes", [
        ("Espaço ⏎", "tocar ou pausar"),
        ("← →", "salto curto"),
        ("PgUp PgDn", "salto longo (Shift+← → também)"),
        ("↑ ↓", "velocidade, de 25 em 25 (Shift: 5)"),
        (", .", "uma palavra"),
        ("( )", "frase"),
        ("{ }", "parágrafo"),
        ("[ ]", "capítulo"),
        ("Home End", "começo e fim"),
        ("0 … 9", "vai a 0%, 10% … 90%"),
        ("/ n N", "buscar; próxima e anterior"),
        ("b m", "marcar este ponto; ver os marcadores"),
        ("i", "índice de capítulos"),
        ("q Esc", "voltar à biblioteca"),
    ]),
    ("Aparência", "na tela cheia", [
        ("+ -", "letra maior / menor"),
        ("f e r", "fonte; estilo; traço da letra"),
        ("t c v", "tema; cor da letra; cor do foco"),
        ("w", "palavras por vez (1 a 4)"),
        ("d x", "linhas de foco; trecho em volta"),
        ("o", "todos os ajustes (ritmo, respiros…)"),
    ]),
    ("Biblioteca", "o que está aqui aparece nas outras máquinas", [
        ("1 2 3", "as três abas (Tab também troca)"),
        ("↑ ↓", "escolher"),
        ("⏎", "ler na faixa do tt"),
        ("T", "ler em tela cheia"),
        ("a", "acrescentar um arquivo pelo caminho"),
        ("x", "apagar daqui e das outras máquinas"),
        ("s", "trocar agora com as outras máquinas"),
        ("o ?", "ajustes; esta tela"),
        ("q Esc", "sair"),
    ]),
    ("Arquivos", "as pastas desta máquina e das outras", [
        ("m", "trocar de máquina"),
        ("⏎ →", "entrar na pasta; acrescentar o arquivo"),
        ("← ⌫", "pasta de cima"),
        ("r ~", "arquivos recentes; pasta pessoal"),
        ("/", "filtrar pelo nome"),
    ]),
    ("Mouse e toque", "", [
        ("toque", "na palavra: tocar ou pausar"),
        ("roda", "velocidade (na leitura) ou a lista"),
        ("barra", "de progresso: vai ao ponto tocado"),
        ("faixa", "« ‹ ▶ › » − + ? ✕ são botões"),
    ]),
]


def _ajustar(segs, w, bg=None):
    """Os trechos em exatamente `w` células; onde o trecho não tem fundo, entra `bg`."""
    saida, usado = [], 0
    for t, fg, b, at in segs:
        if usado >= w or not t:
            continue
        lw = larg(t)
        if usado + lw > w:  # corte seco: quem quer reticências corta antes
            corte, lw = [], 0
            for ch in t:
                cw = larg_c(ch)
                if usado + lw + cw > w:
                    break
                corte.append(ch)
                lw += cw
            t = "".join(corte)
        saida.append((t, fg, b or bg, at))
        usado += lw
    if usado < w:
        saida.append((" " * (w - usado), None, bg, 0))
    return saida


def _larg_segs(segs):
    return sum(larg(t[0]) for t in segs)


def _claro(cor):
    if not cor:
        return False
    r, g, b = _rgb(cor)
    return (r * 299 + g * 587 + b * 114) / 1000 > 140


class Paleta:
    """As cores da tela a partir do tema: além das cinco do tema, o fundo dos painéis, o da linha escolhida, o das
    teclas e as de estado. No tema "terminal" (sem cores próprias) quase tudo é None e o realce é negrito/inverso."""

    def __init__(self, tema):
        self.fundo, self.letra, self.apagado, self.foco, self.destaque, self.letra_w = tema
        f, l = self.fundo, self.letra
        self.painel = _mistura(f, l, 0.06) if f and l else None
        self.realce = _mistura(f, self.destaque, 0.20) if f and self.destaque else None
        self.tecla = _mistura(f, l, 0.20) if f and l else None
        self.fraco = _mistura(f, self.apagado, 0.55) if f and self.apagado else self.apagado
        claro = _claro(f)
        self.verde, self.amarelo, self.vermelho = ("#2e7d32", "#b26a00", "#c62828") if claro else ("#a6e3a1", "#f9e2af", "#f38ba8")
        self.laranja = "#c75b12" if claro else LARANJA


class App:
    def __init__(self, prefs=None, W=80, H=24, cores=24):
        self.prefs = prefs or ler_prefs()
        self.W, self.H = W, H
        self.pintor = Pintor(cores)
        self.atlas = Atlas()
        self._fontes = {}
        self.modo = "bib"
        self.aba = "bib"  # bib | arq | maq
        self.maqs = [m for m in (os.environ.get("TT_LEITOR_MAQUINAS") or "").split() if re.fullmatch(r"[\w.-]{1,60}", m) and m != maquina()]
        self.arq = {"maq": "", "pasta": "", "acima": "", "casa": CASA, "itens": [], "sel": 0, "rol": 0, "erro": "", "carregando": False,
                    "filtro": "", "seq": 0, "aberta": False}
        self.maq_sel = 0
        self.tarefas = []  # [processo, saída, ao_fim(rc, texto), prazo]
        self.so_ajuda = False
        self._rede = None
        self.sobre = None
        self.zonas = []
        self.sujo = True
        self.sair = False
        self.toast = ""
        self.toast_fim = 0
        self.livros = []
        self.sel = 0
        self.rolagem = 0
        self.ver = 0  # muda quando a aparência muda: invalida os caches de desenho
        self.pendente = None
        self.sync_proc = None
        self.sync_saida = None
        self.falta_sync = False
        self.aj_sel = 0
        self.lista_sel = 0
        self.entrada = ""
        self.sugestoes = None
        self.confirmar = None
        self.ultima_busca = ""
        # leitura
        self.lid = None
        self.meta = {}
        self.txt = None
        self.pos = 0
        self.sub = 0
        self.tocando = False
        self.voltar_ao_tocar = False
        self.prox = 0
        self.rampa = 0
        self.salvo_pos = -1
        self.salvo_em = 0
        self.oferta = None
        self.respiro = 0  # > 0: a tela está no respiro entre parágrafos (o valor é o tipo da quebra)
        self.estado_mtime = 0
        self.media = 1.2
        self._cache_un = {}
        self._cache_ctx = {}
        self.recarregar()

    # -- geral --
    def avisar(self, texto, seg=4):
        self.toast, self.toast_fim, self.sujo = texto, time.monotonic() + seg, True

    def recarregar(self):
        ant = self.livros[self.sel]["id"] if self.livros and self.sel < len(self.livros) else None
        self._rede = None
        self.livros = listar()
        # lendo (do mais recente), para ler, lidos: a ordem da tela
        self.livros.sort(key=lambda l: (2 if l["concluido"] else 0 if l["pos"] else 1, -max(l["mudada"], l["adicionada"])))
        self.sel = next((i for i, l in enumerate(self.livros) if l["id"] == ant), min(self.sel, max(0, len(self.livros) - 1)))
        self.sujo = True

    def tema(self):
        fundo, letra, apagado, foco, destaque = TEMAS[self.prefs["tema"]]
        cl = CORES_LETRA[self.prefs["cor_letra"]][1]
        cf = CORES_FOCO[self.prefs["cor_foco"]][1]
        letra_w = cl or letra
        foco = letra_w if cf == "letra" else (cf or foco)
        return fundo, letra, apagado, foco, destaque, letra_w

    def fonte(self):
        fam = self.prefs["fonte"] if self.prefs["fonte"] in self.atlas.faces else next(iter(self.atlas.faces), None)
        if fam is None:
            return None
        chave = (fam, "negrito" in self.prefs["estilo"])
        if chave not in self._fontes:
            self._fontes[chave] = Fonte(self.atlas, *chave)
        return self._fontes[chave]

    def mudou_aparencia(self):
        self.ver += 1
        self._cache_un.clear()
        self._cache_ctx.clear()
        self.sujo = True
        gravar_prefs(self.prefs)
        motor_ctl("recarregar")  # a leitura que estiver na faixa passa a valer com o ajuste novo

    # -- biblioteca --
    def abrir(self, lid):
        try:
            livro = ler_texto(lid)
        except Erro as e:
            self.avisar(str(e), 6)
            return False
        except (OSError, ValueError):
            self.avisar("o texto deste livro está corrompido; apague e acrescente de novo", 6)
            return False
        self.lid, self.meta, self.txt = lid, ler_meta(lid), Texto(livro)
        if not self.txt.n:
            self.avisar("este livro não tem texto")
            return False
        est = ler_estado(lid)
        self.pos = max(0, min(int(est.get("pos") or 0), self.txt.n - 1))
        if est.get("concluido") and self.pos >= self.txt.n - 1:
            self.pos = 0
        self.sub, self.tocando, self.oferta = 0, False, None
        self.salvo_pos, self.salvo_em = self.pos, time.monotonic()
        self.estado_mtime = self._mtime_estado()
        self._cache_un.clear()
        self._cache_ctx.clear()
        passo = max(1, self.txt.n // 4000)
        amostra = range(0, self.txt.n, passo)
        self.media = sum(fator_tempo(self.txt.pal[i], self.txt.fim_par[i], self.prefs) for i in amostra) / max(1, len(amostra))
        self.modo, self.sobre, self.sujo = "ler", None, True
        outra = est.get("maquina")
        if outra and outra != maquina() and self.pos:
            self.avisar("continuando de onde você parou em %s (%s)" % (outra, ha_quanto(est.get("mudada"))), 5)
        return True

    def _mtime_estado(self):
        try:
            return os.stat(os.path.join(pasta(self.lid), "estado.json")).st_mtime_ns
        except OSError:
            return 0

    def salvar(self, forcar=False):
        if self.lid and self.txt and (forcar or self.pos != self.salvo_pos):
            if self.pos != self.salvo_pos:
                try:
                    marcar_posicao(self.lid, self.pos, self.txt.n)
                    self.falta_sync = True
                except OSError:
                    pass
            self.salvo_pos, self.salvo_em = self.pos, time.monotonic()
            self.estado_mtime = self._mtime_estado()

    def fechar_livro(self):
        self.pausar()
        self.salvar()
        if self.falta_sync:
            self.sincronizar(silencio=True)
        self.modo, self.sobre, self.lid, self.txt = "bib", None, None, None
        self.recarregar()

    def sincronizar(self, silencio=False):
        tt = os.environ.get("TT_LEITOR_TT")
        if not tt or (self.sync_proc and self.sync_proc.poll() is None):
            if not silencio:
                self.avisar("sincronização já em andamento" if tt else "fora do tt: sem rede para sincronizar")
            return
        try:
            self.sync_saida = tempfile.TemporaryFile()
            self.sync_proc = subprocess.Popen([tt, "--leitor-sync"], stdin=subprocess.DEVNULL, stdout=self.sync_saida,
                                              stderr=subprocess.DEVNULL, start_new_session=True)
            self.sync_proc.silencio = silencio
            self.falta_sync = False
            if not silencio:
                self.avisar("sincronizando com as outras máquinas…", 30)
        except OSError:
            self.sync_proc = None

    def _lancar(self, args, ao_fim, prazo=60):
        try:
            f = tempfile.TemporaryFile()
            p = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=f, stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError:
            ao_fim(127, "")
            return
        self.tarefas.append([p, f, ao_fim, time.monotonic() + prazo])

    def _conferir_tarefas(self):
        for t in list(self.tarefas):
            p, f, ao_fim, prazo = t
            rc = p.poll()
            if rc is None and time.monotonic() < prazo:
                continue
            if rc is None:
                try:
                    os.killpg(p.pid, signal.SIGTERM)
                except OSError:
                    pass
                rc = 124
            self.tarefas.remove(t)
            try:
                f.seek(0)
                txt = f.read().decode("utf-8", "replace")
                f.close()
            except (OSError, ValueError):
                txt = ""
            ao_fim(rc, txt)
            self.sujo = True

    def rede(self):
        if self._rede is None:
            self._rede = rede()
        return self._rede

    # -- aba Arquivos: as pastas daqui e das outras máquinas --
    def arq_abrir(self, maq=None, onde=None):
        a = self.arq
        if maq is not None:
            a["maq"] = maq
        if onde is not None:
            a["pasta"] = onde
        a.update(sel=0, rol=0, erro="", filtro="", aberta=True)
        a["seq"] += 1
        seq = a["seq"]
        tt = os.environ.get("TT_LEITOR_TT")
        if not a["maq"]:
            self._arq_chegou(seq, ls(a["pasta"] or "@recentes"))
            if a["pasta"] in ("", "@recentes") and not a["itens"]:
                self._arq_chegou(seq, ls("~"))
            return
        if not tt:
            self._arq_chegou(seq, {"erro": "fora do tt: sem caminho até as outras máquinas"})
            return
        a["carregando"], a["itens"] = True, []
        maq_ = a["maq"]

        def fim(rc, txt):
            try:
                d = json.loads(txt)
                if not isinstance(d, dict) or d.get("leitor_ls") != 1:
                    raise ValueError
            except ValueError:
                d = {"erro": "%s não respondeu (desligada, sem rede ou com um tt mais antigo)" % maq_}
            if not d.get("erro") and not d.get("itens") and d.get("pasta") == "@recentes" and seq == a["seq"]:
                return self.arq_abrir(onde="~")  # nada recente lá: começa pela pasta pessoal
            self._arq_chegou(seq, d)
        self._lancar([tt, "--leitor-ls", maq_, a["pasta"] or "@recentes"], fim, 40)

    def _arq_chegou(self, seq, d):
        a = self.arq
        if seq != a["seq"]:
            return
        itens = []
        for i in d.get("itens") or []:
            try:
                nome, tipo, tam, quando = str(i[0]), str(i[1]), int(i[2]), int(i[3])
            except (TypeError, ValueError, IndexError):
                continue
            if nome and tipo in ("d", "f") and not any(ord(c) < 32 or c == "\x7f" for c in nome):
                itens.append((nome, tipo, tam, quando))
        a.update(itens=itens, carregando=False, erro=str(d.get("erro") or "")[:200], acima=str(d.get("acima") or ""),
                 casa=str(d.get("casa") or ""), pasta=str(d.get("pasta") or a["pasta"]))
        self.sujo = True

    def arq_visiveis(self):
        a = self.arq
        f = sem_acento(a["filtro"]).split()
        if not f:
            return a["itens"]
        return [i for i in a["itens"] if all(t in sem_acento(posixpath.basename(i[0])) for t in f)]

    def arq_caminho(self, item):
        a = self.arq
        return item[0] if a["pasta"] == "@recentes" or item[0].startswith("/") else posixpath.join(a["pasta"], item[0])

    def arq_entrar(self, i=None):
        vis = self.arq_visiveis()
        i = self.arq["sel"] if i is None else i
        if not (0 <= i < len(vis)):
            return
        item = vis[i]
        cam = self.arq_caminho(item)
        if item[1] == "d":
            self.arq_abrir(onde=cam)
        elif not self.arq["maq"]:
            self.acrescentar(cam)
        else:
            self.arq_pegar(self.arq["maq"], cam)

    def arq_subir(self):
        a = self.arq
        if a["pasta"] == "@recentes":
            self.arq_abrir(onde="~")
        elif a["acima"]:
            self.arq_abrir(onde=a["acima"])

    def arq_pegar(self, maq_, caminho):
        tt = os.environ.get("TT_LEITOR_TT")
        nome = posixpath.basename(caminho)
        self.avisar("trazendo %s de %s…" % (cortar(nome, 40), maq_), 3600)

        def fim(rc, txt):
            linhas = [l for l in txt.splitlines() if l.strip()]
            partes = linhas[-1].split("\t") if linhas else [""]
            if rc == 0 and ID_RE.match(partes[0]):
                self.recarregar()
                self.aba = "bib"
                self.sel = next((i for i, l in enumerate(self.livros) if l["id"] == partes[0]), 0)
                self.avisar("veio de %s: %s" % (maq_, partes[1] if len(partes) > 1 else nome), 6)
            else:
                self.avisar("não consegui trazer %s de %s%s" % (cortar(nome, 30), maq_, (": " + cortar(linhas[-1].lstrip("✗ "), 60)) if linhas else ""), 10)
        self._lancar([tt, "--leitor-pegar", maq_, caminho], fim, 3600)

    def arq_maquina(self, d=1):
        todas = [""] + self.maqs
        i = todas.index(self.arq["maq"]) if self.arq["maq"] in todas else 0
        self.arq_abrir(maq=todas[(i + d) % len(todas)], onde="")

    # -- aba Máquinas --
    def maq_linhas(self):
        """[(rótulo, dados da rede ou None)]: esta máquina primeiro, depois as cadastradas e as que já trocaram."""
        r = self.rede()
        nomes = list(self.maqs) + sorted(k for k in r if k not in self.maqs and k != maquina())
        return [(maquina(), None)] + [(n, r.get(n) or {}) for n in nomes]

    def maq_lendo(self, nome):
        """(título, %, quando) do que a máquina leu por último."""
        melhor = None
        for l in self.livros:
            v = l["maquinas"].get(nome)
            if v and (melhor is None or v[1] > melhor[2]):
                melhor = (l["titulo"], v[0], v[1])
        return melhor

    def sincronizar_uma(self, nome):
        tt = os.environ.get("TT_LEITOR_TT")
        if not tt:
            self.avisar("fora do tt: sem rede para sincronizar")
            return
        self.avisar("trocando com %s…" % nome, 120)

        def fim(rc, txt):
            linhas = [l for l in txt.splitlines() if l.strip()]
            self.recarregar()
            self.avisar(linhas[-1] if linhas else "troca com %s terminada" % nome, 6)
        self._lancar([tt, "--leitor-sync", nome], fim, 3700)

    def trocar_aba(self, aba):
        self.aba, self.sujo = aba, True
        if aba == "arq" and not self.arq["aberta"]:
            self.arq_abrir()
        if aba == "maq":
            self._rede = None

    def _conferir_sync(self):
        p = self.sync_proc
        if p is None or p.poll() is None:
            return
        self.sync_proc = None
        try:
            self.sync_saida.seek(0)
            linhas = [l for l in self.sync_saida.read().decode("utf-8", "replace").splitlines() if l.strip()]
            self.sync_saida.close()
        except (OSError, ValueError):
            linhas = []
        if self.modo == "bib":
            self.recarregar()
        if not getattr(p, "silencio", False):
            self.avisar(linhas[-1] if linhas else "sincronização terminada", 6)

    # -- leitura: unidades de exibição --
    def area_palavra(self):
        """(coluna do foco, largura útil)."""
        W = self.W
        foco = int(W * 0.36) if self.prefs["foco_pos"] == "esquerda" else W // 2
        return max(2, min(W - 3, foco)), W - 2

    def _tamanhos(self):
        t = self.prefs["tamanho"]
        if t <= 1 or self.fonte() is None:
            return [1]
        livre = self.H - 8 - (2 if self.prefs["guia"] else 0)
        t = max(1, min(t, livre))
        if t < 2:
            return [1]
        i = TAMANHOS.index(max(x for x in TAMANHOS if x <= t))
        # a palavra que não cabe no tamanho escolhido encolhe, enquanto continuar legível, antes de ser partida
        piso = 3 if self.prefs["traco"] == "pontos" else 5
        return [TAMANHOS[i]] + [x for x in reversed(TAMANHOS[:i]) if x >= piso]

    def desenho(self, texto):
        """Como mostrar `texto`: ("grande", linhas, colunas, [linhas de trechos], (d0, d1)) ou ("texto", …) ou None."""
        chave = (texto, self.W, self.H, self.ver)
        r = self._cache_un.get(chave)
        if r is not None or chave in self._cache_un:
            return r
        _, util = self.area_palavra()
        r = None
        foco = ponto_foco(texto) if self.prefs["grupo"] == 1 or " " not in texto else None
        tams = self._tamanhos()
        if tams != [1]:
            ital = "itálico" in self.prefs["estilo"]
            falta = False
            for t in tams:
                g = letras_grandes(self.fonte(), texto, t, self.prefs["traco"], ital, foco)
                if g is None:
                    falta = True
                    break
                if g[0] <= util:
                    r = ("grande", t, g[0], g[1], g[2])
                    break
            if r is None and falta and larg(texto) <= util:  # letra fora do atlas: texto do terminal
                r = ("texto", 1, larg(texto), texto, foco)
        elif larg(texto) <= util:
            r = ("texto", 1, larg(texto), texto, foco)
        if len(self._cache_un) > 3000:
            self._cache_un.clear()
        self._cache_un[chave] = r
        return r

    def unidade(self, pos=None):
        """(nº de palavras, [textos mostrados em sequência]) a partir de `pos`."""
        pos = self.pos if pos is None else pos
        t = self.txt
        k = 1
        while k < self.prefs["grupo"] and pos + k < t.n and not t.fim_par[pos + k - 1] and not termina_frase(t.pal[pos + k - 1]):
            k += 1
        while k > 1 and self.desenho(" ".join(t.pal[pos:pos + k])) is None:
            k -= 1
        if k > 1:
            return k, [" ".join(t.pal[pos:pos + k])]
        return 1, partir(t.pal[pos], lambda x: self.desenho(x) is not None)

    def espera(self):
        t = self.txt
        k, partes = self.unidade()
        total = sum(fator_tempo(t.pal[i], t.fim_par[i], self.prefs, t.titulo[i]) for i in range(self.pos, min(t.n, self.pos + k)))
        if k > 1:
            total *= 0.9
        if len(partes) > 1:
            total = max(0.7, total * len(partes[self.sub]) / max(1, sum(len(x) for x in partes)))
        if self.rampa > 0:
            total *= 1 + 0.25 * self.rampa
            self.rampa -= 1
        return total * 60.0 / self.prefs["ppm"]

    def tocar(self):
        if not self.txt:
            return
        if self.pos >= self.txt.n - 1 and self.sub == 0:
            self.pos = 0
        elif self.prefs["retomada"] and self.pos > 0 and self.voltar_ao_tocar:
            # retoma um pouco antes de onde a leitura foi pausada (não depois de um salto ou de uma busca)
            self.pos = max(self.txt.par(self.pos)[1], self.pos - self.prefs["retomada"])
            self.sub = 0
        self.voltar_ao_tocar = False
        self.tocando, self.oferta, self.respiro = True, None, 0
        self.rampa = 4 if self.prefs["arranque"] else 0
        self.prox = time.monotonic() + self.espera()
        self.sujo = True

    def pausar(self):
        if self.tocando:
            self.tocando, self.sujo, self.respiro = False, True, 0
            self.voltar_ao_tocar = True
            self.salvar()

    def alternar(self):
        self.pausar() if self.tocando else self.tocar()

    def ir(self, pos, manter=False):
        if not self.txt:
            return
        self.pos, self.sub = max(0, min(int(pos), self.txt.n - 1)), 0
        self.oferta, self.respiro = None, 0
        self.voltar_ao_tocar = False
        if self.tocando:
            self.rampa = 2 if self.prefs["arranque"] else 0
            self.prox = time.monotonic() + self.espera()
        self.sujo = True

    def saltar(self, direcao, longo=False):
        seg = self.prefs["salto_longo" if longo else "salto_curto"]
        t = self.txt
        if seg:
            self.ir(self.pos + direcao * max(1, round(self.prefs["ppm"] * seg / 60 / self.media)))
        elif longo:
            k, ini, fim = t.par(self.pos)
            self.ir(fim if direcao > 0 else (ini if self.pos > ini else t.par_ini[max(0, k - 1)]))
        else:
            ini = t.ini_frase(self.pos)
            self.ir(t.prox_frase(self.pos) if direcao > 0 else (ini if self.pos > ini else t.ini_frase(max(0, ini - 1))))

    def capitulo(self, direcao):
        k, _ = self.txt.cap(self.pos)
        if direcao < 0 and self.pos > self.txt.caps[k][0]:
            self.ir(self.txt.caps[k][0])
        else:
            self.ir(self.txt.caps[max(0, min(len(self.txt.caps) - 1, k + direcao))][0])

    def mudar_ppm(self, d):
        self.prefs["ppm"] = max(PPM_MIN, min(PPM_MAX, self.prefs["ppm"] + d))
        gravar_prefs(self.prefs)
        self.avisar("%d palavras por minuto" % self.prefs["ppm"], 1.5)

    def tick(self):
        agora = time.monotonic()
        if self.toast and agora > self.toast_fim:
            self.toast, self.sujo = "", True
        self._conferir_sync()
        if self.tarefas:
            self._conferir_tarefas()
        if self.modo != "ler" or not self.txt:
            return
        if self.tocando and agora >= self.prox and self.respiro:  # o respiro acabou: entra a palavra que já é a atual
            self.respiro = 0
            self.prox = max(self.prox, agora - 0.05) + self.espera()
            self.sujo = True
        elif self.tocando and agora >= self.prox:
            k, partes = self.unidade()
            if self.sub + 1 < len(partes):
                self.sub += 1
            elif self.pos + k >= self.txt.n:
                self.pos, self.sub = self.txt.n - 1, 0
                self.tocando = False
                self.salvar(forcar=True)
                self.avisar("fim do texto", 8)
                self.sincronizar(silencio=True)
                return
            else:
                q = self.txt.quebra[self.pos + k - 1]
                resp = pausa_apos(q, self.prefs)
                self.pos, self.sub = self.pos + k, 0
                if resp > 0:  # tela vazia antes do parágrafo, do título ou do capítulo que começa
                    self.respiro = q
                    self.prox = max(self.prox, agora - 0.05) + resp
                    self.sujo = True
                    return
            self.respiro = 0
            self.prox = max(self.prox, agora - 0.05) + self.espera()
            self.sujo = True
        if self.tocando and agora - self.salvo_em > 15:
            self.salvar()
        if not self.tocando and agora - self.salvo_em > 3:
            self.salvo_em = agora
            m = self._mtime_estado()
            if m != self.estado_mtime:  # a sincronização trouxe uma posição mais nova de outra máquina
                self.estado_mtime = m
                est = ler_estado(self.lid)
                p = max(0, min(int(est.get("pos") or 0), self.txt.n - 1))
                if est.get("maquina") not in (None, "", maquina()) and p != self.pos:
                    self.oferta = p
                    self.avisar("%s está em %d%% — ⏎ vai para lá, Esc fica aqui" % (est["maquina"], p * 100 // max(1, self.txt.n)), 20)

    def prazo(self):
        if self.pendente:
            return 0
        if self.modo == "ler" and self.tocando:
            return max(0.0, min(0.5, self.prox - time.monotonic()))
        return 0.15 if self.tarefas else 0.5 if (self.toast or self.sync_proc) else 2.0

    # -- ajustes --
    def itens_ajustes(self):
        p = self.prefs

        def ciclo(chave, valores):
            def f(d):
                i = valores.index(p[chave]) if p[chave] in valores else 0
                p[chave] = valores[(i + d) % len(valores)]
            return f

        def passo(chave, valores):
            def f(d):
                i = valores.index(p[chave]) if p[chave] in valores else 0
                p[chave] = valores[max(0, min(len(valores) - 1, i + d))]
            return f

        def soma(chave, n, lo, hi, arred=None):
            def f(d):
                v = max(lo, min(hi, p[chave] + n * d))
                p[chave] = round(v, 2) if arred else v
            return f

        def troca(chave):
            def f(d):
                p[chave] = not p[chave]
            return f

        fams = self.atlas.familias() or [p["fonte"]]
        sn = lambda v: "sim" if v else "não"
        pont = {0.0: "nenhuma", 0.5: "curta", 1.0: "normal", 1.5: "longa", 2.0: "bem longa"}
        return [
            ("Velocidade", "%d palavras por minuto" % p["ppm"], soma("ppm", 25, PPM_MIN, PPM_MAX)),
            ("Palavras por vez", str(p["grupo"]), soma("grupo", 1, 1, 4)),
            ("Tamanho da letra", "texto do terminal" if p["tamanho"] == 1 else "%d linhas" % p["tamanho"], passo("tamanho", list(TAMANHOS))),
            ("Fonte", self.atlas.nome(p["fonte"]) + ("" if p["tamanho"] > 1 else " (vale com letra grande)"), ciclo("fonte", fams)),
            ("Estilo", p["estilo"], ciclo("estilo", list(ESTILOS))),
            ("Traço da letra grande", TRACO_NOME[p["traco"]], ciclo("traco", list(TRACOS))),
            ("Tema (fundo e cores)", p["tema"], ciclo("tema", list(TEMAS))),
            ("Cor da letra", CORES_LETRA[p["cor_letra"]][0], soma("cor_letra", 1, -1, len(CORES_LETRA))),
            ("Cor da letra de foco", CORES_FOCO[p["cor_foco"]][0], soma("cor_foco", 1, -1, len(CORES_FOCO))),
            ("Linhas de foco", sn(p["guia"]), troca("guia")),
            ("Posição do foco", "à esquerda do centro" if p["foco_pos"] == "esquerda" else "no centro", ciclo("foco_pos", ["esquerda", "centro"])),
            ("Pausa na pontuação", pont.get(p["pontuacao"], "%.2g×" % p["pontuacao"]), soma("pontuacao", 0.25, 0.0, 2.0, True)),
            ("Respiro: parágrafo, título, capítulo", pont.get(p["respiro"], "%.2g×" % p["respiro"]) +
             ("" if not p["respiro"] else " (%.1f / %.1f / %.1f s)" % tuple(pausa_apos(q, p) for q in (1, 2, 4))),
             soma("respiro", 0.25, 0.0, 3.0, True)),
            ("Mais tempo em palavra longa", sn(p["longas"]), troca("longas")),
            ("Marca no respiro (| parágrafo, * título, # capítulo)", sn(p["marcas"]), troca("marcas")),
            ("Arranque suave ao tocar", sn(p["arranque"]), troca("arranque")),
            ("Ao retomar, voltar", "%d palavras" % p["retomada"] if p["retomada"] else "nada", passo("retomada", [0, 1, 2, 3, 5, 8, 12])),
            ("Salto curto (← →)", "%d s" % p["salto_curto"] if p["salto_curto"] else "uma frase", passo("salto_curto", list(SALTOS_CURTOS))),
            ("Salto longo (PgUp PgDn)", "%d s" % p["salto_longo"] if p["salto_longo"] else "um parágrafo", passo("salto_longo", list(SALTOS_LONGOS))),
            ("Trecho do texto em volta", {"nunca": "nunca", "pausado": "quando pausado", "sempre": "sempre"}[p["contexto"]],
             ciclo("contexto", ["pausado", "sempre", "nunca"])),
            ("Botões na tela", sn(p["botoes"]), troca("botoes")),
        ]

    def ajustar(self, i, d):
        itens = self.itens_ajustes()
        if 0 <= i < len(itens):
            itens[i][2](d)
            p = self.prefs
            p["cor_letra"] %= len(CORES_LETRA)
            p["cor_foco"] %= len(CORES_FOCO)
            self.mudou_aparencia()

    def ajuste_rapido(self, rotulo, d=1):
        for i, it in enumerate(self.itens_ajustes()):
            if it[0].startswith(rotulo):
                self.ajustar(i, d)
                novo = self.itens_ajustes()[i]
                self.avisar("%s: %s" % (novo[0], novo[1]), 2)
                return

    # -- marcadores --
    def marcadores(self):
        est = ler_estado(self.lid)
        r = [(int(k), v.get("nome") or "") for k, v in est["marcadores"].items() if not v.get("removido") and int(k) < self.txt.n]
        return sorted(r)

    def marcar(self):
        est = ler_estado(self.lid)
        ini = self.txt.ini_frase(self.pos)
        nome = cortar(" ".join(self.txt.pal[ini:ini + 8]), 60)
        est["marcadores"][str(self.pos)] = {"nome": nome, "mudada": agora_ms(), "removido": False}
        gravar_estado(self.lid, est)
        self.estado_mtime = self._mtime_estado()
        self.avisar("marcado: " + nome, 3)

    def desmarcar(self, pos):
        est = ler_estado(self.lid)
        if str(pos) in est["marcadores"]:
            est["marcadores"][str(pos)] = {"nome": est["marcadores"][str(pos)].get("nome", ""), "mudada": agora_ms(), "removido": True}
            gravar_estado(self.lid, est)
            self.estado_mtime = self._mtime_estado()

    # -- acrescentar --
    def abrir_adicionar(self):
        self.sobre, self.entrada, self.lista_sel, self.sugestoes, self.sujo = "adicionar", "", 0, None, True

    def _sugestoes(self):
        if self.sugestoes is None:
            self.sugestoes = arquivos_recentes()
        termo = self.entrada.strip()
        if not termo or termo[0] in "/~.":
            return self.sugestoes
        ts = sem_acento(termo).split()
        return [s for s in self.sugestoes if all(t in sem_acento(os.path.basename(s)) for t in ts)]

    def _caminho_entrada(self):
        e = self.entrada.strip().strip("'\"")
        if e.startswith("file://"):
            e = unquote(e[7:])
        e = os.path.expanduser(e)
        return e if e and os.path.isfile(e) else ""

    def _completar(self):
        e = os.path.expanduser(self.entrada.strip())
        if not e or e[0] not in "/~.":
            return
        d, base = os.path.split(e)
        try:
            cand = sorted(n for n in os.listdir(d or ".") if n.startswith(base) and not (n.startswith(".") and not base.startswith(".")))
        except OSError:
            return
        if not cand:
            return
        comum = os.path.commonprefix(cand)
        alvo = os.path.join(d, comum)
        if len(cand) == 1 and os.path.isdir(alvo):
            alvo += "/"
        self.entrada = alvo
        self.sujo = True

    def acrescentar(self, caminho):
        self.sobre = None
        self.avisar("lendo %s…" % os.path.basename(caminho), 60)

        def fazer():
            try:
                lid, meta, novo = adicionar(caminho)
            except Erro as e:
                self.avisar(str(e), 10)
                return
            except (OSError, ValueError, zipfile.BadZipFile, ET.ParseError) as e:
                self.avisar("não consegui ler: %s" % e, 10)
                return
            self.recarregar()
            self.sel = next((i for i, l in enumerate(self.livros) if l["id"] == lid), 0)
            self.avisar(("acrescentado: %s (%s palavras)" if novo else "já estava na biblioteca: %s (%s palavras)") %
                        (meta.get("titulo"), milhar(meta.get("palavras") or 0)), 5)
            self.sincronizar(silencio=True)

        self.pendente = fazer

    # -- eventos --
    def evento(self, ev):
        self.sujo = True
        if ev[0] == "mouse":
            return self.mouse(*ev[1:])
        if ev[0] == "cola":
            if self.sobre in ("adicionar", "busca", "filtro"):
                self.entrada += ev[1].strip().replace("\n", " ")
                if self.sobre == "filtro":
                    self.arq["filtro"] = self.entrada
            elif self.modo == "bib":
                self.abrir_adicionar()
                self.entrada = ev[1].strip().split("\n")[0]
            return
        k = ev[1]
        if k == "c-c":
            self.sair = True
            return
        if self.sobre:
            return self.tecla_sobre(k)
        if self.modo == "bib":
            return self.tecla_bib(k)
        return self.tecla_ler(k)

    def tecla_bib(self, k):
        if k in ("1", "2", "3"):
            return self.trocar_aba(("bib", "arq", "maq")[int(k) - 1])
        if k in ("tab", "s-tab") and not (self.aba == "arq" and k == "tab" and False):
            ordem = ("bib", "arq", "maq")
            return self.trocar_aba(ordem[(ordem.index(self.aba) + (1 if k == "tab" else -1)) % 3])
        if k == "q" or (k == "esc" and not (self.aba == "arq" and self.arq["filtro"])):
            self.sair = True
        elif k == "s":
            self.sincronizar()
        elif k == "o":
            self.sobre, self.aj_sel = "ajustes", 0
        elif k in ("?", "f1"):
            self.sobre, self.lista_sel = "ajuda", 0
        elif k == "c-l":
            self.recarregar()
        elif k in ("a", "ins"):
            self.abrir_adicionar()
        elif self.aba == "arq":
            self.tecla_arq(k)
        elif self.aba == "maq":
            self.tecla_maq(k)
        else:
            self.tecla_livros(k)

    @staticmethod
    def _mover(sel, n, k, pagina=10):
        if k in ("baixo", "j"):
            return min(n - 1, sel + 1) if n else 0
        if k in ("cima", "k"):
            return max(0, sel - 1)
        if k == "pgdn":
            return min(n - 1, sel + pagina) if n else 0
        if k == "pgup":
            return max(0, sel - pagina)
        if k in ("home", "g"):
            return 0
        if k in ("end", "G"):
            return max(0, n - 1)
        return None

    def tecla_livros(self, k):
        n = len(self.livros)
        novo = self._mover(self.sel, n, k, 5)
        if novo is not None:
            self.sel = novo
        elif k in ("enter", " ", "l", "direita") and n:
            self.ler_livro(self.livros[self.sel]["id"])
        elif k == "T" and n:
            self.abrir(self.livros[self.sel]["id"])
        elif k == "+":
            self.abrir_adicionar()
        elif k in ("x", "del") and n:
            l = self.livros[self.sel]
            self.confirmar = ("Apagar “%s” daqui e das outras máquinas?" % cortar(l["titulo"], 40), lambda: self._apagar(l["id"]))
            self.sobre = "confirmar"

    def tecla_arq(self, k):
        a = self.arq
        vis = self.arq_visiveis()
        novo = self._mover(a["sel"], len(vis), k)
        if novo is not None:
            a["sel"] = novo
        elif k in ("enter", "direita", "l", " "):
            self.arq_entrar()
        elif k in ("esquerda", "h", "backspace"):
            self.arq_subir()
        elif k == "m":
            self.arq_maquina(1)
        elif k == "M":
            self.arq_maquina(-1)
        elif k == "r":
            self.arq_abrir(onde="@recentes")
        elif k == "~":
            self.arq_abrir(onde="~")
        elif k == "/":
            self.sobre, self.entrada = "filtro", a["filtro"]
        elif k == "esc":
            a["filtro"], a["sel"] = "", 0

    def tecla_maq(self, k):
        linhas = self.maq_linhas()
        novo = self._mover(self.maq_sel, len(linhas), k)
        if novo is not None:
            self.maq_sel = novo
        elif k in ("enter", " ") and linhas:
            nome = linhas[min(self.maq_sel, len(linhas) - 1)][0]
            if nome == maquina():
                self.sincronizar()
            else:
                self.sincronizar_uma(nome)
        elif k in ("direita", "l") and linhas:
            nome = linhas[min(self.maq_sel, len(linhas) - 1)][0]
            self.aba = "arq"
            self.arq_abrir(maq="" if nome == maquina() else nome, onde="")

    def _apagar(self, lid):
        meta = remover(lid)
        self.recarregar()
        self.avisar("apagado: %s" % (meta.get("titulo") or lid))
        self.sincronizar(silencio=True)

    def tecla_ler(self, k):
        t = self.txt
        if k == "enter" and self.oferta is not None:
            self.ir(self.oferta)
            self.toast = ""
        elif k in (" ", "enter", "p"):
            self.alternar()
        elif k == "esc":
            if self.oferta is not None:
                self.oferta, self.toast = None, ""
            elif self.tocando:
                self.pausar()
            else:
                self.fechar_livro()
        elif k == "q":
            self.fechar_livro()
        elif k == "cima":
            self.mudar_ppm(25)
        elif k == "baixo":
            self.mudar_ppm(-25)
        elif k in ("s-cima", "K"):
            self.mudar_ppm(5)
        elif k in ("s-baixo", "J"):
            self.mudar_ppm(-5)
        elif k in ("esquerda", "h"):
            self.saltar(-1)
        elif k in ("direita", "l"):
            self.saltar(1)
        elif k in ("pgup", "s-esquerda", "c-esquerda", "a-esquerda", "H"):
            self.saltar(-1, True)
        elif k in ("pgdn", "s-direita", "c-direita", "a-direita", "L"):
            self.saltar(1, True)
        elif k == ",":
            self.ir(self.pos - 1)
        elif k == ".":
            self.ir(self.pos + 1)
        elif k == "(":
            ini = t.ini_frase(self.pos)
            self.ir(ini if self.pos > ini else t.ini_frase(max(0, ini - 1)))
        elif k == ")":
            self.ir(t.prox_frase(self.pos))
        elif k == "{":
            n, ini, _ = t.par(self.pos)
            self.ir(ini if self.pos > ini else t.par_ini[max(0, n - 1)])
        elif k == "}":
            self.ir(t.par(self.pos)[2])
        elif k == "[":
            self.capitulo(-1)
        elif k == "]":
            self.capitulo(1)
        elif k in ("home", "g"):
            self.ir(0)
        elif k in ("end", "G"):
            self.ir(t.n - 1)
        elif len(k) == 1 and k.isdigit():
            self.ir(t.n * int(k) // 10)
        elif k in ("+", "="):
            self.ajuste_rapido("Tamanho", 1)
        elif k in ("-", "_"):
            self.ajuste_rapido("Tamanho", -1)
        elif k == "f":
            self.ajuste_rapido("Fonte")
        elif k == "F":
            self.ajuste_rapido("Fonte", -1)
        elif k == "e":
            self.ajuste_rapido("Estilo")
        elif k == "r":
            self.ajuste_rapido("Traço")
        elif k == "t":
            self.ajuste_rapido("Tema")
        elif k == "T":
            self.ajuste_rapido("Tema", -1)
        elif k == "c":
            self.ajuste_rapido("Cor da letra")
        elif k == "v":
            self.ajuste_rapido("Cor da letra de foco")
        elif k == "w":
            self.prefs["grupo"] = self.prefs["grupo"] % 4 + 1
            self.mudou_aparencia()
            self.avisar("%d palavra%s por vez" % (self.prefs["grupo"], "s" if self.prefs["grupo"] > 1 else ""), 2)
        elif k == "d":
            self.ajuste_rapido("Linhas de foco")
        elif k == "x":
            self.ajuste_rapido("Trecho")
        elif k == "b":
            self.marcar()
        elif k in ("m", "'"):
            self.pausar()
            self.sobre, self.lista_sel = "marcadores", 0
        elif k == "i":
            self.pausar()
            self.sobre, self.lista_sel = "indice", t.cap(self.pos)[0]
        elif k == "/":
            self.pausar()
            self.sobre, self.entrada = "busca", ""
        elif k in ("n", "N"):
            self.buscar(self.ultima_busca, k == "N")
        elif k == "o":
            self.sobre, self.aj_sel = "ajustes", 0
        elif k in ("?", "f1"):
            self.pausar()
            self.sobre, self.lista_sel = "ajuda", 0

    def buscar(self, termo, para_tras=False):
        if not termo:
            self.avisar("nada para buscar (/ começa uma busca)")
            return
        self.ultima_busca = termo
        i = self.txt.buscar(termo, self.pos, para_tras)
        if i < 0:
            self.avisar("não achei “%s”" % termo)
        else:
            self.ir(i)
            self.avisar("“%s” em %d%% · n próxima, N anterior" % (termo, i * 100 // max(1, self.txt.n)), 3)

    def tecla_sobre(self, k):
        s = self.sobre
        if s == "confirmar":
            self.sobre = None
            if k in ("s", "S", "y", "Y") and self.confirmar:
                self.confirmar[1]()
            self.confirmar = None
        elif s == "ajuda":
            if k in ("baixo", "j", "pgdn", " "):
                self.lista_sel += 1 if k in ("baixo", "j") else 10
            elif k in ("cima", "k", "pgup"):
                self.lista_sel = max(0, self.lista_sel - (1 if k in ("cima", "k") else 10))
            else:
                self.sobre = None
                self.sair = self.sair or self.so_ajuda
        elif s == "filtro":
            if k == "esc":
                self.sobre, self.arq["filtro"], self.arq["sel"] = None, "", 0
            elif k == "enter":
                self.sobre = None
            else:
                self._editar(k)
                self.arq["filtro"], self.arq["sel"] = self.entrada, 0
        elif s == "ajustes":
            n = len(self.itens_ajustes())
            if k in ("esc", "q", "o"):
                self.sobre = None
            elif k in ("baixo", "j", "tab"):
                self.aj_sel = (self.aj_sel + 1) % n
            elif k in ("cima", "k", "s-tab"):
                self.aj_sel = (self.aj_sel - 1) % n
            elif k in ("direita", "l", "enter", "+", "="):
                self.ajustar(self.aj_sel, 1)
            elif k in ("esquerda", "h", "-"):
                self.ajustar(self.aj_sel, -1)
            elif k == " " and self.modo == "ler":
                self.alternar()
        elif s in ("indice", "marcadores"):
            itens = self.txt.caps if s == "indice" else self.marcadores()
            n = len(itens)
            if k in ("esc", "q", "i", "m"):
                self.sobre = None
            elif k in ("baixo", "j"):
                self.lista_sel = min(n - 1, self.lista_sel + 1) if n else 0
            elif k in ("cima", "k"):
                self.lista_sel = max(0, self.lista_sel - 1)
            elif k == "pgdn":
                self.lista_sel = min(n - 1, self.lista_sel + 10) if n else 0
            elif k == "pgup":
                self.lista_sel = max(0, self.lista_sel - 10)
            elif k in ("home", "g"):
                self.lista_sel = 0
            elif k in ("end", "G"):
                self.lista_sel = max(0, n - 1)
            elif k in ("enter", " ") and n:
                self.sobre = None
                self.ir(itens[self.lista_sel][0])
            elif k in ("x", "del") and s == "marcadores" and n:
                self.desmarcar(itens[self.lista_sel][0])
                self.lista_sel = max(0, min(self.lista_sel, n - 2))
        elif s == "busca":
            if k == "esc":
                self.sobre = None
            elif k == "enter":
                self.sobre = None
                self.buscar(self.entrada.strip() or self.ultima_busca)
            else:
                self._editar(k)
        elif s == "adicionar":
            sug = self._sugestoes()
            if k == "esc":
                self.sobre = None
            elif k == "baixo":
                self.lista_sel = min(len(sug) - 1, self.lista_sel + 1) if sug else 0
            elif k == "cima":
                self.lista_sel = max(0, self.lista_sel - 1)
            elif k == "pgdn":
                self.lista_sel = min(len(sug) - 1, self.lista_sel + 10) if sug else 0
            elif k == "pgup":
                self.lista_sel = max(0, self.lista_sel - 10)
            elif k == "tab":
                self._completar()
            elif k == "enter":
                alvo = self._caminho_entrada() or (sug[self.lista_sel] if sug and self.lista_sel < len(sug) and
                                                    not self.entrada.strip().startswith(("/", "~", ".")) else "")
                if alvo:
                    self.acrescentar(alvo)
                else:
                    self.avisar("não achei esse arquivo (Tab completa o caminho)")
            else:
                self._editar(k)
                self.lista_sel = 0

    def _editar(self, k):
        if k == "backspace":
            self.entrada = self.entrada[:-1]
        elif k == "c-u":
            self.entrada = ""
        elif k == "c-w":
            self.entrada = re.sub(r"\S+\s*$", "", self.entrada)
        elif len(k) == 1 or (len(k) > 1 and not k.isascii() and len(k) <= 4 and "-" not in k):
            self.entrada += k

    def mouse(self, botao, x, y, apertou):
        if botao in (64, 65):  # roda
            d = 1 if botao == 64 else -1
            if self.sobre == "ajustes":
                self.aj_sel = (self.aj_sel - d) % len(self.itens_ajustes())
            elif self.sobre in ("indice", "marcadores", "adicionar", "ajuda"):
                self.lista_sel = max(0, self.lista_sel - d * (3 if self.sobre == "ajuda" else 1))
            elif self.modo == "bib" and not self.sobre:
                if self.aba == "arq":
                    self.arq["sel"] = max(0, min(len(self.arq_visiveis()) - 1, self.arq["sel"] - d * 3))
                elif self.aba == "maq":
                    self.maq_sel = max(0, min(len(self.maq_linhas()) - 1, self.maq_sel - d))
                else:
                    self.sel = max(0, min(len(self.livros) - 1, self.sel - d))
            elif not self.sobre:
                self.mudar_ppm(25 * d)
            return
        if not apertou or botao & 3 != 0 or botao & 32:
            return
        for zy, x0, x1, acao in reversed(self.zonas):
            if zy == y and x0 <= x < x1:
                acao(x - x0)
                return
        if self.sobre in ("ajuda", "confirmar"):
            self.sobre = None
            self.sair = self.sair or self.so_ajuda
        elif self.modo == "ler" and not self.sobre and 0 < y < self.H - 3:
            self.alternar()

    # -- composição --
    def compor(self):
        """A tela inteira como linhas de trechos (texto, cor, fundo, atributos)."""
        self.zonas = []
        W, H = self.W, self.H
        L = [[] for _ in range(H)]
        if self.modo == "ler" and self.txt:
            base_painel = self.compor_ler(L)
        else:
            self.compor_bib(L)
            base_painel = None
        if self.sobre:
            self.compor_sobre(L, base_painel)
        if self.toast and not (self.sobre in ("busca", "adicionar", "filtro")):
            fundo, letra, apagado, foco, destaque, _ = self.tema()
            y = H - 4 if self.modo == "ler" and H >= 12 and not self.sobre else H - 2
            y = max(1, min(H - 1, y))
            giro = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[int(time.monotonic() * 8) % 10] + " " if self.tarefas or self.sync_proc else ""
            t = cortar("  " + giro + self.toast + "  ", W - 2)
            L[y] = [(" " * max(0, (W - larg(t)) // 2), None, None, 0), (t, fundo or None, destaque or None, NEG if fundo else INV)]
        return L

    def linhas(self):
        fundo = self.tema()[0]
        return [self.pintor.montar(l, self.W, fundo) for l in self.compor()]

    def texto_puro(self):
        saida = []
        for l in self.compor():
            s = "".join(t for t, _, _, _ in l)
            saida.append(s.rstrip())
        return saida

    def pal(self):
        return Paleta(self.tema())

    def _tecla(self, P, k):
        if k in ("…", "/", "·"):
            return (k, P.apagado, None, 0)
        return (" %s " % k, P.letra, P.tecla, NEG) if P.tecla else ("[%s]" % k, None, None, NEG)

    def _botoes(self, L, y, botoes):
        """Uma linha de botões centrada; os que não cabem (do fim da lista) ficam de fora."""
        P = self.pal()
        W = self.W
        botoes = [b for b in botoes if b[0]]
        while botoes and sum(larg(b[0]) + 3 for b in botoes) - 1 > W - 2:
            botoes = [b for b in botoes if b[2] != max(x[2] for x in botoes)] if len({x[2] for x in botoes}) > 1 else botoes[:-1]
        total = sum(larg(b[0]) + 3 for b in botoes) - 1
        x = max(0, (W - total) // 2)
        segs = [(" " * x, None, None, 0)]
        for rot, acao, _prio in botoes:
            t = " " + rot + " "
            if acao:
                segs.append((t, P.letra, P.tecla, 0) if P.tecla else (t, None, None, INV))
                self.zonas.append((y, x, x + larg(t), lambda _x, a=acao: a()))
            else:
                segs.append((t, P.destaque, None, NEG))
            segs.append((" ", None, None, 0))
            x += larg(t) + 1
        L[y] = segs

    def _rodape(self, L, y, itens):
        """Dicas de teclas na última linha: [(teclas, rótulo, ação ou None, prioridade)]; as menos importantes saem
        primeiro quando não cabem. Cada dica é também um botão."""
        P = self.pal()
        W = self.W

        def largura(it):
            return sum(larg(k) + (2 if k not in ("…", "/", "·") else 0) for k in it[0].split()) + len(it[0].split()) + larg(it[1]) + 2
        itens = [i for i in itens if i]
        while itens and sum(largura(i) for i in itens) > W - 2:
            pior = max(i[3] for i in itens)
            for n in range(len(itens) - 1, -1, -1):
                if itens[n][3] == pior:
                    del itens[n]
                    break
        segs, x = [(" ", None, None, 0)], 1
        for teclas, rot, acao, _prio in itens:
            x0 = x
            for k in teclas.split():
                t = self._tecla(P, k)
                segs.append(t)
                segs.append((" ", None, None, 0))
                x += larg(t[0]) + 1
            segs.append((rot + "  ", P.apagado, None, 0))
            x += larg(rot) + 2
            if acao:
                self.zonas.append((y, x0, x - 1, lambda _x, a=acao: a()))
        L[y] = segs

    def _estado_maquina(self, P, r):
        """(cor da bolinha, texto) do que a última troca com a máquina deixou."""
        if not r or not (r.get("quando") or r.get("ok")):
            return P.fraco, "ainda não trocou com esta máquina"
        agora = agora_ms()
        if r.get("estado") == "falhou":
            return P.vermelho, "a troca falhou %s%s" % (ha_quanto(r["quando"]), (" · em dia " + ha_quanto(r["ok"])) if r.get("ok") else "")
        if r.get("estado") == "pulada":
            return P.amarelo, "sem resposta %s%s" % (ha_quanto(r["quando"]), (" · em dia " + ha_quanto(r["ok"])) if r.get("ok") else "")
        if r.get("ok") and agora - r["ok"] < 45 * 60 * 1000:
            return P.verde, "em dia %s" % ha_quanto(r["ok"])
        return P.amarelo, "última troca %s" % ha_quanto(r.get("ok") or r.get("quando"))

    def _cabecalho(self, L):
        P = self.pal()
        W = self.W
        segs = [(" ▍", P.destaque, None, NEG), ("Leitor rápido", P.letra, None, NEG), ("   ", None, None, 0)]
        x = _larg_segs(segs)
        abas = (("bib", "1", "Biblioteca", len(self.livros)), ("arq", "2", "Arquivos", None), ("maq", "3", "Máquinas", len(self.maqs) + 1))
        curto = W < 72
        for chave, tecla, nome, n in abas:
            t = " %s %s%s " % (tecla, nome[:3] if curto else nome, " %d" % n if n is not None and not curto else "")
            if chave == self.aba:
                segs.append((t, P.fundo, P.destaque, NEG) if P.fundo and P.destaque else (t, None, None, INV | NEG))
            else:
                segs.append((t, P.apagado, None, 0))
            self.zonas.append((0, x, x + larg(t), lambda _x, c=chave: self.trocar_aba(c)))
            segs.append((" ", None, None, 0))
            x += larg(t) + 1
        r = self.rede()
        dir_ = []
        for m in self.maqs:
            cor, _ = self._estado_maquina(P, r.get(m))
            item = [("● ", cor, None, 0), (m + "  ", P.apagado, None, 0)]
            if x + _larg_segs(dir_) + _larg_segs(item) + 2 > W:
                break
            dir_ += item
        if dir_:
            segs.append((" " * max(1, W - x - _larg_segs(dir_)), None, None, 0))
            self.zonas.append((0, W - _larg_segs(dir_), W, lambda _x: self.trocar_aba("maq")))
            segs += dir_
        L[0] = _ajustar(segs, W, P.painel)

    def compor_bib(self, L):
        H = self.H
        self._cabecalho(L)
        y0, y1 = 2, H - 2
        na_faixa = os.environ.get("TT_LEITOR_BARRA") == "1"
        n = len(self.livros)
        if self.aba == "arq":
            self._aba_arquivos(L, y0, y1)
            rod = [("⏎", "abrir / acrescentar", self.arq_entrar, 0), ("←", "pasta de cima", self.arq_subir, 1),
                   ("m", "outra máquina", self.arq_maquina, 1) if self.maqs else None, ("r", "recentes", lambda: self.tecla_arq("r"), 3),
                   ("~", "pasta pessoal", lambda: self.tecla_arq("~"), 4), ("/", "filtrar", lambda: self.tecla_arq("/"), 2),
                   ("a", "digitar o caminho", self.abrir_adicionar, 5), ("?", "atalhos", lambda: self.tecla_bib("?"), 2),
                   ("q", "sair", lambda: self.tecla_bib("q"), 3)]
        elif self.aba == "maq":
            self._aba_maquinas(L, y0, y1)
            rod = [("s", "trocar com todas", self.sincronizar, 0), ("⏎", "trocar só com esta", lambda: self.tecla_maq("enter"), 1),
                   ("→", "ver os arquivos dela", lambda: self.tecla_maq("direita"), 2), ("?", "atalhos", lambda: self.tecla_bib("?"), 3),
                   ("q", "sair", lambda: self.tecla_bib("q"), 3)]
        else:
            self._aba_livros(L, y0, y1)
            rod = [("⏎", "ler na faixa" if na_faixa else "ler", (lambda: self.tecla_livros("enter")) if n else None, 0),
                   ("T", "tela cheia", lambda: self.tecla_livros("T"), 2) if na_faixa and n else None,
                   ("2", "procurar arquivos", lambda: self.trocar_aba("arq"), 1),
                   ("x", "apagar", lambda: self.tecla_livros("x"), 4) if n else None, ("s", "trocar com as máquinas", self.sincronizar, 3),
                   ("o", "ajustes", lambda: self.tecla_bib("o"), 5), ("?", "atalhos", lambda: self.tecla_bib("?"), 1),
                   ("q", "sair", lambda: self.tecla_bib("q"), 2)]
        if H >= 6:
            self._rodape(L, H - 1, rod)

    # -- aba Biblioteca --
    def _aba_livros(self, L, y0, y1):
        P = self.pal()
        W = self.W
        n = len(self.livros)
        alt = y1 - y0
        if not n:
            msg = [("Sua biblioteca está vazia", P.letra, NEG), ("", None, 0),
                   ("2   procure um arquivo nesta máquina ou nas outras", P.apagado, 0),
                   ("a   digite o caminho de um arquivo", P.apagado, 0),
                   ("    ou, no terminal:  tt --leitor ARQUIVO", P.apagado, 0), ("", None, 0),
                   ("txt · md · html · epub · docx · odt · fb2 · rtf · pdf", P.fraco, 0), ("", None, 0),
                   ("O que entra aqui aparece nas suas outras máquinas do tt,", P.apagado, 0),
                   ("com o ponto em que você parou.", P.apagado, 0)]
            y = y0 + max(0, (alt - len(msg)) // 2)
            x = max(2, (W - 56) // 2)
            for i, (m, cor, at) in enumerate(msg):
                if y + i < y1:
                    L[y + i] = [(" " * x, None, None, 0), (cortar(m, W - x - 1), cor, None, at)]
            return
        det_w = min(46, W // 3) if W >= 100 and alt >= 12 else 0
        w = W - det_w - (2 if det_w else 0)
        compacto = alt < 14
        h_cartao = 2 if compacto else 4
        # linhas da lista: títulos de grupo e cartões
        grupos = ("LENDO", "PARA LER", "LIDOS")
        itens, ant = [], None
        for i, l in enumerate(self.livros):
            g = 2 if l["concluido"] else 0 if l["pos"] else 1
            if g != ant:
                itens.append(("grupo", grupos[g], 1 if compacto else 2))
                ant = g
            itens.append(("livro", i, h_cartao))
        topo, tops = 0, []
        for it in itens:
            tops.append(topo)
            topo += it[2]
        k = next(j for j, it in enumerate(itens) if it[0] == "livro" and it[1] == self.sel)
        ini = tops[k - 1] if k and itens[k - 1][0] == "grupo" else tops[k]
        fim = tops[k] + (h_cartao - (0 if compacto else 1))
        if ini < self.rolagem:
            self.rolagem = ini
        if fim > self.rolagem + alt:
            self.rolagem = fim - alt
        self.rolagem = max(0, min(self.rolagem, max(0, topo - alt)))
        for it, t in zip(itens, tops):
            y = y0 + t - self.rolagem
            if it[0] == "grupo":
                yy = y + (it[2] - 1)
                if y0 <= yy < y1:
                    L[yy] = _ajustar([(" " + it[1] + " ", P.destaque, None, NEG), ("─" * max(0, w - larg(it[1]) - 3), P.fraco, None, 0)], w)
                continue
            i = it[1]
            l = self.livros[i]
            sel = i == self.sel
            bg = P.realce if sel else None
            marca = ("▌ ", P.foco, bg, NEG) if sel else ("  ", None, bg, 0)
            if l["concluido"]:
                chip = ("✓ lido", P.verde)
            elif not l["texto"]:
                chip = ("a caminho", P.amarelo)
            elif l["pos"]:
                chip = ("%d%%" % l["pct"], P.letra)
            else:
                chip = ("novo", P.destaque)
            resta = (l["palavras"] - l["pos"]) * 60 / self.prefs["ppm"] * 1.2
            tit = cortar(l["titulo"], max(8, w - 6 - larg(chip[0])))
            autor = cortar("  " + l["autor"], max(0, w - 6 - larg(chip[0]) - larg(tit))) if l["autor"] else ""
            esp = max(1, w - 3 - larg(tit) - larg(autor) - larg(chip[0]))
            l1 = [marca, (tit, P.letra, bg, NEG), (autor, P.apagado, bg, 0), (" " * esp, None, bg, 0), (chip[0] + " ", chip[1], bg, NEG)]
            det = []
            if not l["texto"]:
                det.append("o texto ainda não chegou a esta máquina (s troca agora)")
            elif l["concluido"]:
                det.append("%s palavras" % milhar(l["palavras"]))
            elif l["pos"]:
                det.append("faltam %s" % duracao(resta))
            else:
                det.append("%s palavras · %s de leitura" % (milhar(l["palavras"]), duracao(resta)))
            if l["mudada"] and (l["pos"] or l["concluido"]):
                det.append("lido %s%s" % (ha_quanto(l["mudada"]), " em " + l["maquina"] if l["maquina"] and l["maquina"] != maquina() else ""))
            else:
                det.append("acrescentado %s%s" % (ha_quanto(l["adicionada"]), " em " + l["origem"] if l["origem"] and l["origem"] != maquina() else ""))
            det.append(l["formato"])
            if not det_w:
                det += ["%s %d%%" % (m, v[0]) for m, v in sorted(l["maquinas"].items()) if m != maquina()][:3]
            l3 = [("  ", None, bg, 0), (cortar(" · ".join(det), w - 4), P.apagado, bg, 0)]
            if compacto:
                linhas = [l1, l3]
            else:
                bw = max(4, w - 4)
                cheio = min(bw, round(bw * l["pct"] / 100)) if l["pos"] or l["concluido"] else 0
                l2 = [("  ", None, bg, 0), ("━" * cheio, P.verde if l["concluido"] else P.destaque, bg, 0), ("━" * (bw - cheio), P.fraco, bg, 0)]
                linhas = [l1, l2, l3]
            for j, segs in enumerate(linhas):
                yy = y + j
                if y0 <= yy < y1:
                    L[yy] = _ajustar(segs, w, bg)
                    self.zonas.append((yy, 0, w, lambda _x, i=i: self._clicar_livro(i)))
        if det_w:
            self._detalhes(L, y0, y1, W - det_w - 1, det_w, self.livros[self.sel])

    def _detalhes(self, L, y0, y1, x, w, l):
        """O painel à direita: o livro escolhido por inteiro e onde cada máquina parou nele."""
        P = self.pal()
        dentro = w - 4
        corpo = []

        def campo(rot, val, cor=None):
            corpo.append([("%-11s" % rot, P.apagado, None, 0), (cortar(val, dentro - 11), cor or P.letra, None, 0)])
        tit = l["titulo"]
        while tit and len(corpo) < 3:
            pedaco = tit if larg(tit) <= dentro else tit[:max(1, tit.rfind(" ", 0, dentro) if tit.rfind(" ", 0, dentro) > 8 else dentro - 1)]
            if len(corpo) == 2 and pedaco != tit:
                pedaco = cortar(tit, dentro)
                tit = ""
            else:
                tit = tit[len(pedaco):].strip()
            corpo.append([(cortar(pedaco, dentro), P.letra, None, NEG)])
        if l["autor"]:
            corpo.append([(cortar(l["autor"], dentro), P.apagado, None, ITA)])
        corpo.append([])
        bw = max(4, dentro - 6)
        cheio = min(bw, round(bw * l["pct"] / 100))
        corpo.append([("━" * cheio, P.verde if l["concluido"] else P.destaque, None, 0), ("━" * (bw - cheio), P.fraco, None, 0),
                      (" %4s" % ("%d%%" % l["pct"]), P.letra, None, NEG)])
        corpo.append([])
        resta = (l["palavras"] - l["pos"]) * 60 / self.prefs["ppm"] * 1.2
        onde = "%s de %s" % (milhar(l["pos"]), milhar(l["palavras"]))
        campo("posição", onde + (" palavras" if larg(onde) + 9 <= dentro - 11 else ""))
        if not l["concluido"]:
            campo("faltam", "%s a %d ppm" % (duracao(resta), self.prefs["ppm"]))
        campo("formato", "%s · %s" % (l["formato"], tamanho_legivel(l["bytes"])))
        if l["original"]:
            campo("arquivo", "nesta máquina")
        else:
            fora = onde_original(l["id"])
            campo("arquivo", ("em " + ", ".join(fora)) if fora else "só o texto", P.amarelo)
        if not l["texto"]:
            campo("texto", "ainda não chegou (s troca)", P.amarelo)
        if l["marcadores"]:
            campo("marcadores", str(l["marcadores"]))
        campo("entrou", "%s%s" % (ha_quanto(l["adicionada"]), " em " + l["origem"] if l["origem"] else ""))
        corpo.append([])
        corpo.append([("ONDE CADA MÁQUINA PAROU", P.destaque, None, NEG)])
        nomes = [maquina()] + [m for m in self.maqs] + sorted(m for m in l["maquinas"] if m != maquina() and m not in self.maqs)
        nw = min(12, max(larg(m) for m in nomes))
        mb = max(4, dentro - nw - 20)
        for m in nomes:
            v = l["maquinas"].get(m)
            nome = "%-*s" % (nw, cortar(m, nw))
            if v:
                c = min(mb, round(mb * v[0] / 100))
                corpo.append([(nome + " ", P.letra if m == maquina() else P.apagado, None, 0), ("━" * c, P.destaque, None, 0), ("━" * (mb - c), P.fraco, None, 0),
                              (" %3d%% " % v[0], P.letra, None, 0), (cortar(ha_quanto(v[1]), max(0, dentro - nw - mb - 7)), P.apagado, None, 0)])
            else:
                corpo.append([(nome + " ", P.apagado, None, 0), ("━" * mb, P.fraco, None, 0), ("   —", P.fraco, None, 0)])
        alt = min(y1 - y0, len(corpo) + 2)
        cx = self._caixa_em(L, x, y0, w, alt, "este texto", corpo)
        return cx

    def _caixa_em(self, L, x, y, w, h, titulo, corpo, rodape=""):
        """Caixa de cantos redondos num ponto da tela, por cima do que já está nas linhas."""
        P = self.pal()
        bg = P.painel

        def por(yy, segs):
            if 0 <= yy < len(L):
                L[yy] = _ajustar(L[yy], x) + _ajustar(segs, w, bg) + [(" " * max(0, self.W - x - w), None, None, 0)]
        tit = cortar(" " + titulo + " ", w - 4)
        por(y, [("╭─", P.fraco, None, 0), (tit, P.destaque, None, NEG), ("─" * max(0, w - 3 - larg(tit)) + "╮", P.fraco, None, 0)])
        for i in range(h - 2):
            segs = corpo[i] if i < len(corpo) else []
            por(y + 1 + i, [("│ ", P.fraco, None, 0)] + _ajustar(list(segs), w - 4, bg) + [(" │", P.fraco, None, 0)])
        rod = cortar(" " + rodape + " ", w - 4) if rodape else ""
        por(y + h - 1, [("╰─", P.fraco, None, 0), (rod, P.apagado, None, 0), ("─" * max(0, w - 3 - larg(rod)) + "╯", P.fraco, None, 0)])
        return x + 2

    # -- aba Arquivos --
    def _aba_arquivos(self, L, y0, y1):
        P = self.pal()
        W = self.W
        a = self.arq
        col = 22 if W >= 76 and self.maqs else 0
        if col:
            L[y0] = _ajustar([(" MÁQUINAS", P.destaque, None, NEG)], col)
            r = self.rede()
            for i, m in enumerate([""] + self.maqs):
                yy = y0 + 2 + i
                if yy >= y1:
                    break
                sel = m == a["maq"]
                bg = P.realce if sel else None
                cor = P.verde if not m else self._estado_maquina(P, r.get(m))[0]
                nome = cortar(m or "esta (%s)" % maquina(), col - 5)
                L[yy] = _ajustar([("▌" if sel else " ", P.foco, bg, NEG), (" ● ", cor, bg, 0), (nome, P.letra if sel else P.apagado, bg, NEG if sel else 0)], col, bg)
                self.zonas.append((yy, 0, col, lambda _x, m=m: self.arq_abrir(maq=m, onde="")))
        x0 = col + (2 if col else 1)
        w = W - x0 - 1
        vis = self.arq_visiveis()
        casa = a["casa"] or CASA
        onde = "arquivos recentes" if a["pasta"] == "@recentes" else (("~" + a["pasta"][len(casa):]) if casa and a["pasta"].startswith(casa) else a["pasta"])
        cab = [(a["maq"] or maquina(), P.destaque, None, NEG), (" › ", P.fraco, None, 0), (cortar(onde, max(8, w - 30)), P.letra, None, NEG)]
        dir_ = "%d %s" % (len(vis), "item" if len(vis) == 1 else "itens") + (" · filtro: " + a["filtro"] if a["filtro"] else "")
        cab.append((" " * max(1, w - _larg_segs(cab) - larg(dir_)), None, None, 0))
        cab.append((dir_, P.amarelo if a["filtro"] else P.apagado, None, 0))

        def por(yy, segs):
            if y0 <= yy < y1:
                L[yy] = _ajustar(L[yy], x0) + _ajustar(segs, w)
        por(y0, cab)
        por(y0 + 1, [("─" * w, P.fraco, None, 0)])
        topo, alt = y0 + 2, y1 - y0 - 2
        if a["carregando"]:
            giro = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[int(time.monotonic() * 8) % 10]
            por(topo + 1, [("  " + giro + " lendo a pasta em %s…" % a["maq"], P.apagado, None, 0)])
            return
        if a["erro"]:
            por(topo + 1, [("  " + cortar(a["erro"], w - 4), P.vermelho, None, 0)])
            por(topo + 3, [("  ← volta à pasta de cima · m troca de máquina", P.apagado, None, 0)])
            return
        if not vis:
            por(topo + 1, [("  nada aqui que o leitor leia" + (" com esse filtro (Esc limpa)" if a["filtro"] else " (← sobe uma pasta)"), P.apagado, None, 0)])
            return
        a["sel"] = max(0, min(a["sel"], len(vis) - 1))
        if a["sel"] < a["rol"]:
            a["rol"] = a["sel"]
        if a["sel"] >= a["rol"] + alt:
            a["rol"] = a["sel"] - alt + 1
        a["rol"] = max(0, min(a["rol"], max(0, len(vis) - alt)))
        tenho = {(l["nome"], l["bytes"]) for l in self.livros}
        for n in range(alt):
            i = a["rol"] + n
            if i >= len(vis):
                break
            nome, tipo, tam, quando = vis[i]
            sel = i == a["sel"]
            bg = P.realce if sel else None
            base = posixpath.basename(nome) or nome
            marca = ("▌", P.foco, bg, NEG) if sel else (" ", None, bg, 0)
            if tipo == "d":
                segs = [marca, (" ▸ ", P.destaque, bg, NEG), (cortar(base + "/", w - 6), P.destaque if not sel else P.letra, bg, NEG if sel else 0)]
            else:
                ja = (base, tam) in tenho
                dir_ = "%9s" % tamanho_legivel(tam) + ("  " + time.strftime("%d/%m/%Y", time.localtime(quando)) if w >= 60 else "")
                if ja:
                    dir_ = ("✓ na biblioteca  " if w >= 84 else "✓  ") + dir_
                nm = cortar(base, max(6, w - 6 - larg(dir_)))
                pasta_ = ""
                if a["pasta"] == "@recentes":
                    d = posixpath.dirname(nome)
                    d = "~" + d[len(casa):] if casa and d.startswith(casa) else d
                    pasta_ = cortar("  " + d, max(0, w - 6 - larg(dir_) - larg(nm)))
                esp = max(1, w - 4 - larg(nm) - larg(pasta_) - larg(dir_))
                segs = [marca, ("   ", None, bg, 0), (nm, P.letra, bg, NEG if sel else 0), (pasta_, P.fraco, bg, 0), (" " * esp, None, bg, 0),
                        (dir_, P.verde if ja else P.apagado, bg, 0)]
            yy = topo + n
            L[yy] = _ajustar(L[yy], x0) + _ajustar(segs, w, bg)
            self.zonas.append((yy, x0, x0 + w, lambda _x, i=i: self._clicar_arquivo(i)))

    def _clicar_arquivo(self, i):
        if i == self.arq["sel"]:
            self.arq_entrar(i)
        else:
            self.arq["sel"] = i

    # -- aba Máquinas --
    def _aba_maquinas(self, L, y0, y1):
        P = self.pal()
        W = self.W
        w = min(W - 2, 110)
        linhas = self.maq_linhas()
        self.maq_sel = max(0, min(self.maq_sel, len(linhas) - 1))
        intro = "Sem servidor no meio: cada máquina troca direto com as outras a biblioteca, o ponto em que você parou, os marcadores e os arquivos."
        y = y0
        while intro and y < y0 + 2:
            corte = len(intro) if larg(intro) <= W - 2 else max(1, intro.rfind(" ", 0, W - 2))
            L[y] = [(" " + intro[:corte], P.apagado, None, 0)]
            intro = intro[corte:].strip()
            y += 1
        y += 1
        h = 4 if y1 - y - len(linhas) * 4 >= 0 else 3
        for i, (nome, r) in enumerate(linhas):
            if y + h - 1 > y1:
                break
            sel = i == self.maq_sel
            bg = P.realce if sel else None
            eu = r is None
            if eu:
                cor, est = P.verde, "esta máquina"
                n_liv, n_orig = len(self.livros), sum(1 for l in self.livros if l["original"])
            else:
                cor, est = self._estado_maquina(P, r)
                n_liv, n_orig = r.get("livros"), r.get("originais") or 0
            marca = ("▌", P.foco, bg, NEG) if sel else (" ", None, bg, 0)
            esp = max(1, w - 5 - larg(nome) - larg(est))
            l1 = [marca, (" ● ", cor, bg, 0), (nome, P.letra, bg, NEG), (" " * esp, None, bg, 0), (est + " ", cor if not eu else P.apagado, bg, 0)]
            if n_liv is None:
                t2 = "ainda não sei o que ela tem (⏎ troca agora)"
            else:
                t2 = "%d %s · %d com o arquivo original" % (n_liv, "texto" if n_liv == 1 else "textos", n_orig)
                if not eu and "ids" in r:
                    falta = sum(1 for l in self.livros if l["id"] not in r["ids"])
                    if falta:
                        t2 += " · %d daqui ainda não chegaram lá" % falta
            l2 = [("    ", None, bg, 0), (cortar(t2, w - 6), P.apagado, bg, 0)]
            lendo = self.maq_lendo(nome)
            if lendo:
                bw = 12
                c = min(bw, round(bw * lendo[1] / 100))
                tl = cortar(lendo[0], max(6, w - 50))
                l3 = [("    ", None, bg, 0), ("lendo  ", P.apagado, bg, 0), (tl + "  ", P.letra, bg, 0), ("━" * c, P.destaque, bg, 0), ("━" * (bw - c), P.fraco, bg, 0),
                      (" %d%%  " % lendo[1], P.letra, bg, 0), (ha_quanto(lendo[2]), P.apagado, bg, 0)]
            else:
                l3 = [("    ", None, bg, 0), ("ainda não leu nada por aqui", P.fraco, bg, 0)]
            for j, segs in enumerate((l1, l2, l3)):
                if y + j < y1:
                    L[y + j] = [(" ", None, None, 0)] + _ajustar(segs, w, bg)
                    self.zonas.append((y + j, 0, W, lambda _x, i=i: self._clicar_maquina(i)))
            y += h

    def _clicar_maquina(self, i):
        if i == self.maq_sel:
            self.tecla_maq("enter")
        else:
            self.maq_sel = i

    def ler_livro(self, lid, tela=False):
        """Na faixa do tt (quando há faixa: a leitura acontece lá e esta tela fecha) ou, sem ela, aqui."""
        tt = os.environ.get("TT_LEITOR_TT")
        if tela or os.environ.get("TT_LEITOR_BARRA") != "1" or not tt:
            return self.abrir(lid)
        if not resumo(lid)["texto"]:
            self.avisar("o texto deste livro ainda não chegou a esta máquina (s sincroniza)", 6)
            return False
        try:
            r = subprocess.run([tt, "--leitor-barra", lid], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        except (OSError, subprocess.TimeoutExpired):
            return self.abrir(lid)
        if r.returncode != 0:
            return self.abrir(lid)
        self.sair = True
        return True

    def _clicar_livro(self, i):
        if i == self.sel:
            self.ler_livro(self.livros[i]["id"])
        else:
            self.sel = i

    def compor_ler(self, L):
        fundo, letra, apagado, foco, destaque, letra_w = self.tema()
        W, H = self.W, self.H
        t, p = self.txt, self.prefs
        painel = self.sobre == "ajustes" and H >= 22
        n_aj = min(len(self.itens_ajustes()) + 2, H - 9) if painel else 0
        rodape = n_aj if painel else (3 if (p["botoes"] and H >= 10) else 2 if H >= 8 else 1)
        base = H - rodape
        # cabeçalho
        k, cap = t.cap(self.pos)
        tit = " " + cortar(self.meta.get("titulo") or "?", max(8, W // 2 - 2))
        if cap and cap != self.meta.get("titulo"):
            tit += "  ·  " + cortar(cap, max(0, W - larg(tit) - 22))
        P = self.pal()
        est = (" ▶ %d ppm " if self.tocando else " ‖ pausado · %d ppm ") % p["ppm"]
        chip = (est, fundo, destaque, NEG) if self.tocando and fundo and destaque else (est, destaque if self.tocando else apagado, None, NEG)
        L[0] = _ajustar([(" ▍", destaque, None, NEG), (tit.strip(), letra, None, 0), (" " * max(1, W - larg(tit) - 1 - larg(est)), None, None, 0), chip], W, P.painel)
        # palavra
        _, partes = self.unidade()
        texto = partes[min(self.sub, len(partes) - 1)]
        em_respiro = self.tocando and self.respiro
        if em_respiro:  # entre parágrafos, títulos e capítulos: só a marca do que acabou, noutra cor
            texto = PAUSA_MARCA.get(self.respiro, "") if p["marcas"] else ""
            letra_w = foco = P.laranja
        elif t.titulo[self.pos]:
            letra_w = destaque or letra_w
        des = self.desenho(texto or " ") or ("texto", 1, min(larg(texto), W - 2), cortar(texto, W - 2), None)
        col, util = self.area_palavra()
        alt = des[1]
        guia = p["guia"] and base - 1 >= alt + 4
        bloco = alt + (2 if guia else 0)
        mostra_ctx = p["contexto"] == "sempre" or (p["contexto"] == "pausado" and not self.tocando)
        ctx_h = 0
        if mostra_ctx and base - 1 - bloco >= 5:
            ctx_h = max(3, min((base - 1) // 3, base - 1 - bloco - 2))
        livre = base - 1 - ctx_h
        y0 = 1 + max(0, (livre - bloco) // 2)
        if guia:
            esq = max(0, col - 12)
            dir_ = min(W - 1, col + 12)
            for yy, marca in ((y0, "┬"), (y0 + bloco - 1, "┴")):
                L[yy] = [(" " * esq, None, None, 0), ("─" * (col - esq), apagado, None, 0), (marca, foco, None, 0), ("─" * (dir_ - col), apagado, None, 0)]
            y0 += 1
        if des[0] == "grande":
            _, _, cols, linhas, (d0, d1) = des
            x = col - (d0 + d1) // 2 if d0 >= 0 else (W - cols) // 2
            x = max(1, min(W - 1 - cols, x))
            for i, linha in enumerate(linhas):
                L[y0 + i] = [(" " * x, None, None, 0)] + [(s, foco if dest else letra_w, None, 0) for s, dest in linha]
            if em_respiro and not texto:
                for i in range(len(linhas)):
                    L[y0 + i] = []
        else:
            _, _, cols, s, f = des
            attr = (NEG if "negrito" in p["estilo"] else 0) | (ITA if "itálico" in p["estilo"] else 0)
            if em_respiro:
                f = 0 if s.strip() else None
            if f is not None and f < len(s):
                x = max(1, min(W - 1 - cols, col - larg(s[:f])))
                L[y0] = [(" " * x, None, None, 0), (s[:f], letra_w, None, attr), (s[f], foco, None, attr | NEG), (s[f + 1:], letra_w, None, attr)]
            else:
                L[y0] = [(" " * max(1, (W - cols) // 2), None, None, 0), (s, letra_w, None, attr)]
        self.col_foco = col
        # trecho em volta
        if ctx_h:
            self._compor_contexto(L, base - ctx_h, ctx_h)
        if painel:
            return base
        # rodapé
        if rodape >= 2:
            cheio = round((W - 2) * (self.pos + 1) / max(1, t.n)) if t.n > 1 else W - 2
            yb = base
            # a barra de progresso, com um tracinho onde começa cada capítulo
            marcas = {c[0] * (W - 2) // max(1, t.n) for c, nv in zip(t.caps[1:], t.cap_nivel[1:]) if nv <= 1}
            if len(marcas) > (W - 2) // 3:
                marcas = set()
            barra, x = [(" ", None, None, 0)], 0
            while x < W - 2:
                tick = x in marcas
                x1 = x + 1
                while not tick and x1 < W - 2 and x1 not in marcas and (x1 < cheio) == (x < cheio):
                    x1 += 1
                barra.append((("╋" if x < cheio else "┿") if tick else ("━" if x < cheio else "─") * (x1 - x), destaque if x < cheio else P.fraco, None, 0))
                x = x1
            L[yb] = barra
            self.zonas.append((yb, 1, W - 1, lambda x: self.ir(x * t.n // max(1, W - 2))))
            ys = base + 1
        else:
            ys = base
        pct = (self.pos + 1) * 100 // max(1, t.n)
        resta = (t.n - 1 - self.pos) * 60 / p["ppm"] * self.media
        esq = " %d%% · %s de %s" % (pct, milhar(self.pos + 1), milhar(t.n))
        if len(t.caps) > 1 and W >= 70:
            esq += " · cap. %d/%d" % (k + 1, len(t.caps))
        dir_ = ("restam %s " % duracao(resta)) if self.pos < t.n - 1 else "fim "
        if larg(esq) + larg(dir_) + 1 > W:
            esq = " %d%%" % pct
        L[ys] = [(esq, apagado, None, 0), (" " * max(1, W - larg(esq) - larg(dir_)), None, None, 0), (dir_, apagado, None, 0)]
        if rodape >= 3:
            sc = "%ds" % p["salto_curto"] if p["salto_curto"] else "frase"
            sl = "%ds" % p["salto_longo"] if p["salto_longo"] else "parág."
            self._botoes(L, H - 1, [
                ("« " + sl, lambda: self.saltar(-1, True), 2), ("‹ " + sc, lambda: self.saltar(-1), 1),
                ("‖ pausar" if self.tocando else "▶ tocar", self.alternar, 0),
                (sc + " ›", lambda: self.saltar(1), 1), (sl + " »", lambda: self.saltar(1, True), 2),
                ("−", lambda: self.mudar_ppm(-25), 3), ("%d ppm" % p["ppm"], None, 3), ("+", lambda: self.mudar_ppm(25), 3),
                ("A−", lambda: self.ajuste_rapido("Tamanho", -1), 5), ("A+", lambda: self.ajuste_rapido("Tamanho", 1), 5),
                ("≡ ajustes", lambda: self.tecla_ler("o"), 4), ("? atalhos", lambda: self.tecla_ler("?"), 4), ("✕", self.fechar_livro, 6)])
        return None

    def _compor_contexto(self, L, y0, alt):
        fundo, letra, apagado, foco, destaque, _ = self.tema()
        W = self.W
        larg_txt = min(W - 4, 96)
        margem = (W - larg_txt) // 2
        t = self.txt
        k, ini, fim = t.par(self.pos)
        chave = (k, larg_txt)
        linhas = self._cache_ctx.get(chave)
        if linhas is None:
            linhas, atual, w = [], [], 0
            for i in range(ini, fim):
                lw = larg(t.pal[i])
                if atual and w + 1 + lw > larg_txt:
                    linhas.append(atual)
                    atual, w = [], 0
                atual.append(i)
                w += lw + (1 if len(atual) > 1 else 0)
            if atual:
                linhas.append(atual)
            self._cache_ctx = {chave: linhas}
        li = next((n for n, l in enumerate(linhas) if l[0] <= self.pos <= l[-1]), 0)
        topo = max(0, min(li - alt // 2, len(linhas) - alt))
        for n in range(alt):
            if topo + n >= len(linhas):
                break
            segs, x = [(" " * margem, None, None, 0)], margem
            for i in linhas[topo + n]:
                pal = cortar(t.pal[i], larg_txt)
                if i == self.pos:
                    segs.append((pal, foco, None, NEG | SUB))
                else:
                    segs.append((pal, apagado, None, 0))
                if not self.tocando:
                    self.zonas.append((y0 + n, x, x + larg(pal) + 1, lambda _x, i=i: self.ir(i)))
                segs.append((" ", None, None, 0))
                x += larg(pal) + 1
            L[y0 + n] = segs

    def _caixa(self, L, titulo, linhas, largura, y0=None, altura=None, rodape=""):
        """Caixa com borda sobre a tela. `linhas`: listas de trechos. Devolve (x de dentro, y da 1ª linha, linhas visíveis)."""
        W, H = self.W, self.H
        w = max(10, min(W - 2, largura))
        h = min(H - 2 if altura is None else altura, len(linhas) + 2 if altura is None else altura)
        h = max(3, min(H, h))
        x = (W - w) // 2
        y = max(0, (H - h) // 2) if y0 is None else y0
        self._caixa_em(L, x, y, w, h, titulo, linhas, rodape)
        return x + 2, y + 1, h - 2

    def _linhas_atalhos(self, colw, ncol):
        """A tela de atalhos em `ncol` colunas de `colw` células: seções inteiras, teclas desenhadas como teclas."""
        P = self.pal()
        secoes = list(ATALHOS)
        primeiro = "Na faixa do tt" if (self.so_ajuda or self.modo != "ler") and os.environ.get("TT_LEITOR_BARRA") == "1" else \
            "Leitura em tela cheia" if self.modo == "ler" else "Biblioteca"
        secoes.sort(key=lambda s_: s_[0] != primeiro)
        tw = 15
        blocos = []
        for nome, nota, linhas in secoes:
            b = [[(nome.upper(), P.destaque, None, NEG)]]
            if nota:
                b.append([(cortar(nota, colw), P.fraco, None, ITA)])
            for teclas, desc in linhas:
                ks = [self._tecla(P, k) for k in teclas.split()]
                lw = sum(larg(k[0]) for k in ks) + len(ks) - 1
                segs = [(" " * max(0, tw - lw), None, None, 0)]
                for n, k in enumerate(ks):
                    segs.append(k)
                    if n < len(ks) - 1:
                        segs.append((" ", None, None, 0))
                segs.append(("  " + cortar(desc, colw - tw - 2), P.letra, None, 0))
                b.append(segs)
            b.append([])
            blocos.append(b)
        total = sum(len(b) for b in blocos)
        alvo = -(-total // ncol)
        cols = [[]]
        for b in blocos:
            if cols[-1] and len(cols[-1]) + len(b) - 1 > alvo and len(cols) < ncol:
                cols.append([])
            cols[-1] += b
        linhas = []
        for r in range(max(len(c) for c in cols)):
            segs = []
            for n, c in enumerate(cols):
                segs += _ajustar(c[r] if r < len(c) else [], colw) + ([("   ", None, None, 0)] if n < len(cols) - 1 else [])
            linhas.append(segs)
        while linhas and not any(t[0].strip() for t in linhas[-1]):
            linhas.pop()
        return linhas

    def compor_sobre(self, L, base_painel):
        fundo, letra, apagado, foco, destaque, _ = self.tema()
        W, H = self.W, self.H
        s = self.sobre
        if s == "confirmar":
            self._caixa(L, "confirmar", [[(cortar(self.confirmar[0], W - 8), letra, None, 0)], [], [("s  sim      qualquer outra tecla  não", apagado, None, 0)]],
                        max(44, larg(self.confirmar[0]) + 4))
        elif s == "ajuda":
            ncol = max(1, min(3, (W - 6) // 53))
            colw = min(56, (W - 6 - 3 * (ncol - 1)) // ncol)
            linhas = self._linhas_atalhos(colw, ncol)
            vis = H - 4
            self.lista_sel = max(0, min(self.lista_sel, max(0, len(linhas) - vis)))
            corpo = linhas[self.lista_sel:self.lista_sel + vis]
            self._caixa(L, "atalhos", corpo, ncol * colw + 3 * (ncol - 1) + 4,
                        rodape=("↑ ↓ rolam · " if len(linhas) > vis else "") + "qualquer outra tecla fecha")
        elif s == "filtro":
            y = max(1, H - 2)
            L[y] = [(cortar(" filtrar pelo nome: " + self.entrada + "▏", W - 1), letra, None, NEG)]
            L[H - 1] = [(" ⏎ fica com o filtro · Esc limpa", apagado, None, 0)]
        elif s == "ajustes":
            itens = self.itens_ajustes()
            w = min(W - 2, 74)
            if base_painel is not None:
                y0, alt = base_painel, H - base_painel
            else:
                alt = min(H, len(itens) + 2)
                y0 = max(0, (H - alt) // 2)
            vis = alt - 2
            topo = max(0, min(self.aj_sel - vis // 2, len(itens) - vis))
            corpo = []
            cx = (W - max(10, w)) // 2 + 2
            for i in range(topo, min(len(itens), topo + vis)):
                rot, val, _ = itens[i]
                sel = i == self.aj_sel
                esq = ("▸ " if sel else "  ") + cortar(rot, 30)
                v = cortar(val, w - 46)
                esp = max(1, w - 4 - larg(esq) - larg(v) - 8)
                corpo.append([(esq, letra if sel else apagado, None, NEG if sel else 0), (" " * esp, None, None, 0),
                              (" ‹ ", letra, None, 0), (v, destaque if sel else letra, None, NEG if sel else 0), (" › ", letra, None, 0)])
                yy = y0 + 1 + (i - topo)
                xv = cx + larg(esq) + esp
                self.zonas.append((yy, cx, xv, lambda _x, i=i: setattr(self, "aj_sel", i)))
                self.zonas.append((yy, xv, xv + 3, lambda _x, i=i: (setattr(self, "aj_sel", i), self.ajustar(i, -1))))
                self.zonas.append((yy, xv + 3, cx + w - 3, lambda _x, i=i: (setattr(self, "aj_sel", i), self.ajustar(i, 1))))
            self._caixa(L, "ajustes", corpo, w, y0=y0, altura=alt, rodape="↑ ↓ escolhe · ← → muda · Esc fecha" + (" · Espaço toca" if self.modo == "ler" else ""))
        elif s in ("indice", "marcadores"):
            t = self.txt
            itens = t.caps if s == "indice" else self.marcadores()
            vis = max(1, min(H - 4, max(3, len(itens))))
            self.lista_sel = max(0, min(self.lista_sel, max(0, len(itens) - 1)))
            topo = max(0, min(self.lista_sel - vis // 2, len(itens) - vis))
            w = min(W - 2, 78)
            corpo = []
            y_ini = max(0, (H - (vis + 2)) // 2) + 1
            for i in range(topo, min(len(itens), topo + vis)):
                pos, nome = itens[i]
                sel = i == self.lista_sel
                pct = "%3d%%" % (pos * 100 // max(1, t.n))
                rot = cortar(nome or ("parte %d" % (i + 1)), w - 14)
                corpo.append([("▸ " if sel else "  ", foco, None, NEG), (pct + "  ", apagado, None, 0), (rot, letra if sel else apagado, None, NEG if sel else 0)])
                self.zonas.append((y_ini + i - topo, 0, W, lambda _x, i=i, pos=pos: (setattr(self, "sobre", None), self.ir(pos))))
            if not itens:
                corpo = [[("nenhum marcador ainda: b marca o ponto em que você está", apagado, None, 0)]]
            self._caixa(L, "índice" if s == "indice" else "marcadores", corpo, w, altura=vis + 2,
                        rodape="⏎ vai · Esc fecha" + (" · x apaga" if s == "marcadores" else ""))
        elif s == "busca":
            y = max(1, H - 2)
            t = " buscar: " + self.entrada + "▏"
            L[y] = [(cortar(t, W - 1), letra, None, NEG)]
            L[H - 1] = [(" ⏎ procura · Esc cancela · depois: n próxima, N anterior", apagado, None, 0)]
        elif s == "adicionar":
            sug = self._sugestoes()
            vis = max(1, H - 8)
            self.lista_sel = max(0, min(self.lista_sel, max(0, len(sug) - 1)))
            topo = max(0, min(self.lista_sel - vis // 2, len(sug) - vis))
            w = min(W - 2, 100)
            corpo = [[("arquivo: ", apagado, None, 0), (cortar(self.entrada, w - 16) + "▏", letra, None, NEG)], []]
            y_ini = max(0, (H - min(H - 2, vis + 4)) // 2) + 3
            for i in range(topo, min(len(sug), topo + vis)):
                sel = i == self.lista_sel
                nome = os.path.basename(sug[i])
                onde = os.path.dirname(sug[i]).replace(CASA, "~", 1)
                nome_c = cortar(nome, w - 8)
                corpo.append([("▸ " if sel else "  ", foco, None, NEG), (nome_c, letra if sel else apagado, None, NEG if sel else 0),
                              ("  " + cortar(onde, max(0, w - 8 - larg(nome_c))), apagado, None, 0)])
                self.zonas.append((y_ini + i - topo, 0, W, lambda _x, i=i: self._clicar_sugestao(i)))
            if not sug:
                corpo.append([("(nenhum arquivo recente com esse nome; digite o caminho, Tab completa)", apagado, None, 0)])
            self._caixa(L, "acrescentar um texto", corpo, w, altura=min(H - 2, vis + 4),
                        rodape="digite para filtrar ou um caminho · ↑ ↓ · ⏎ acrescenta · Esc cancela")

    def _clicar_sugestao(self, i):
        sug = self._sugestoes()
        if i < len(sug):
            if i == self.lista_sel:
                self.acrescentar(sug[i])
            else:
                self.lista_sel = i


def _mistura(a, b, f):
    if not a or not b:
        return b
    ra, ga, ba = _rgb(a)
    rb, gb, bb = _rgb(b)
    return "#%02x%02x%02x" % (int(ra + (rb - ra) * f), int(ga + (gb - ga) * f), int(ba + (bb - ba) * f))


def milhar(n):
    return "{:,}".format(int(n)).replace(",", ".")


def arquivos_recentes(limite=300):
    """Arquivos que o leitor sabe ler, nas pastas de costume, do mais novo ao mais velho."""
    pastas = [os.environ.get("TT_LEITOR_PASTA") or os.getcwd(), os.environ.get("TT_RECEBIDOS") or os.path.join(CASA, "Recebidos")]
    pastas += [os.path.join(CASA, n) for n in ("Downloads", "Documentos", "Documents", "Desktop", "Área de Trabalho", "AreaDeTrabalho", "Livros", "Books",
                                              "storage/downloads", "storage/shared/Download", "storage/shared/Documents")]
    vistos, achados, exts = set(), [], tuple("." + f for f in FORMATOS)
    conta = 0
    for raiz in pastas:
        raiz = os.path.realpath(raiz)
        if raiz in vistos or not os.path.isdir(raiz) or raiz == os.path.realpath(CASA):
            continue
        vistos.add(raiz)
        prof0 = raiz.count(os.sep)
        for d, subs, arqs in os.walk(raiz):
            subs[:] = [s for s in subs if not s.startswith(".") and s not in ("node_modules", "__pycache__", "venv")][:60]
            if d.count(os.sep) - prof0 >= 2:
                subs[:] = []
            for a in arqs:
                conta += 1
                if a.lower().endswith(exts) and not a.startswith("."):
                    c = os.path.join(d, a)
                    if c in vistos:
                        continue
                    vistos.add(c)
                    try:
                        achados.append((os.path.getmtime(c), c))
                    except OSError:
                        pass
            if conta > 20000:
                break
    achados.sort(reverse=True)
    return [c for _, c in achados[:limite]]


def interface(abrir=None, ajuda=False):
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        raise Erro("a tela do leitor precisa de um terminal (tt --leitor-listar e tt --leitor-add funcionam sem)")
    prefs = ler_prefs()
    cores = modo_cores(prefs.get("cores", "auto"))
    tela = Tela()
    try:
        W, H = tela.tamanho()
        app = App(prefs, W, H, cores)
        if abrir:
            direto = app.abrir(abrir)
        else:
            direto = False
        if ajuda:  # a tela de atalhos sozinha (o ? da faixa): fecha com qualquer tecla
            app.sobre, app.so_ajuda, app.lista_sel = "ajuda", True, 0
        while not app.sair:
            if tela.redim:
                app.W, app.H = tela.tamanho()
                app.mudou_aparencia()
            app.tick()
            if app.sujo:
                app.sujo = False
                tela.pintar(app.linhas())
            if app.pendente:
                f, app.pendente = app.pendente, None
                f()
                continue
            for ev in tela.ler(app.prazo()):
                app.evento(ev)
                if abrir and direto and app.modo == "bib" and not app.sobre and ev[1] in ("q", "esc"):
                    app.sair = True  # aberto direto num arquivo: sair do livro é sair do leitor
        if app.modo == "ler":
            app.pausar()
            app.salvar()
        if app.falta_sync:
            app.sincronizar(silencio=True)
    except KeyboardInterrupt:
        try:
            if app.modo == "ler":
                app.salvar()
        except Exception:
            pass
    finally:
        tela.fechar()


# --- Linha de comando -------------------------------------------------------------------------------------------------

def _texto_stdin():
    dados = sys.stdin.buffer.read()
    if not dados.strip():
        raise Erro("nada chegou pelo stdin")
    fd, tmp = tempfile.mkstemp(prefix="tt-leitor-", suffix=".txt")
    with os.fdopen(fd, "wb") as f:
        f.write(dados)
    primeira = limpar(decodificar(dados[:400]).strip().split("\n")[0])
    return tmp, cortar(primeira, 60) or "texto colado"


def _reabrir_terminal():
    """Depois de ler o texto do stdin, a tela precisa do terminal de volta."""
    try:
        fd = os.open("/dev/tty", os.O_RDWR)
    except OSError:
        raise Erro("texto acrescentado, mas não há terminal para abrir a tela (tt --leitor abre)")
    os.dup2(fd, 0)
    sys.stdin = open(0, closefd=False)


def cmd_quadro(args):
    """Um quadro em texto puro: leitor-tt.py quadro ID|- [--pos N] [--largura L] [--altura A] [--aba bib|arq|maq]
    [--pasta P] [--sel N] [--atalhos] [--respiro Q] [--cores] [chave=valor…] [--json]."""
    lid = resolver(args[0]) if args and args[0] != "-" else None
    op = {"--pos": None, "--largura": "80", "--altura": "24", "--aba": "bib", "--pasta": None, "--sel": None, "--respiro": None}
    prefs = ler_prefs()
    em_json = False
    i = 1
    while i < len(args):
        a = args[i]
        if a in op:
            op[a] = args[i + 1]
            i += 1
        elif a == "--json":
            em_json = True
        elif a == "--tocando":
            op["tocando"] = True
        elif a in ("--atalhos", "--cores"):
            op[a] = True
        elif "=" in a:
            k, v = a.split("=", 1)
            if k in PADRAO:
                prefs[k] = type(PADRAO[k])(v) if not isinstance(PADRAO[k], bool) else v in ("1", "sim", "true")
        i += 1
    app = App(prefs, int(op["--largura"]), int(op["--altura"]), 24 if op.get("--cores") else 0)
    if op["--sel"] is not None:
        app.sel = max(0, min(len(app.livros) - 1, int(op["--sel"])))
    if op["--aba"] != "bib" and not lid:
        if op["--aba"] == "arq":
            app.aba = "arq"
            app.arq_abrir(onde=op["--pasta"] or "")
        else:
            app.trocar_aba(op["--aba"])
    if op.get("--atalhos"):
        app.sobre = "ajuda"
    if lid:
        if not app.abrir(lid):
            raise Erro(app.toast or "não abriu")
        app.toast = ""
        if op["--pos"] is not None:
            app.ir(int(op["--pos"]))
        app.tocando = bool(op.get("tocando"))
        if op["--respiro"] is not None:
            app.tocando, app.respiro = True, int(op["--respiro"])
    if op.get("--cores"):
        print("\n".join(app.linhas()))
        return
    linhas = app.texto_puro()
    if em_json:
        _, partes = app.unidade() if lid else (0, [""])
        print(json.dumps({"linhas": linhas, "foco": getattr(app, "col_foco", -1), "texto": partes[0], "pos": app.pos,
                          "espera": round(app.espera(), 4) if lid else 0}, ensure_ascii=False))
    else:
        print("\n".join(linhas))


def principal(argv):
    cmd = argv[0] if argv else "tela"
    args = argv[1:]
    if cmd in ("-h", "--help", "ajuda"):
        with open(__file__, encoding="utf-8") as f:
            cab = [l[2:].rstrip("\n") for l in f.read().split("import ", 1)[0].splitlines()[1:] if l.startswith("#")]
        print("\n".join(cab))
        return 0
    if cmd == "tela":
        interface()
    elif cmd == "atalhos":
        interface(ajuda=True)
    elif cmd == "ler":
        if not args:
            interface()
        elif args[0] == "-":
            tmp, titulo = _texto_stdin()
            try:
                lid, _, _ = adicionar(tmp, nome=titulo + ".txt", titulo=titulo)
            finally:
                os.unlink(tmp)
            _reabrir_terminal()
            interface(lid)
        elif os.path.isfile(os.path.expanduser(args[0])):
            lid, meta, novo = adicionar(os.path.expanduser(args[0]))
            interface(lid)
        else:
            interface(resolver(args[0]))
    elif cmd == "adicionar":
        if not args:
            raise Erro("uso: tt --leitor-add ARQUIVO… (ou - para o stdin)")
        rc = 0
        for a in args:
            try:
                if a == "-":
                    tmp, titulo = _texto_stdin()
                    try:
                        lid, meta, novo = adicionar(tmp, nome=titulo + ".txt", titulo=titulo)
                    finally:
                        os.unlink(tmp)
                else:
                    c = os.path.expanduser(a)
                    if not os.path.isfile(c):
                        raise Erro("não achei o arquivo %s" % a)
                    lid, meta, novo = adicionar(c)
                print("%s\t%s\t%s" % (lid, meta.get("titulo"), "novo" if novo else "já estava"))
            except (Erro, OSError, zipfile.BadZipFile, ET.ParseError) as e:
                print("✗ %s: %s" % (a, e), file=sys.stderr)
                rc = 1
        return rc
    elif cmd == "listar":
        livros = listar()
        if "--tsv" in args:
            for l in livros:
                print("\t".join(str(l[k]) for k in ("id", "pct", "pos", "palavras", "titulo", "mudada", "maquina", "formato")) +
                      "\t%d\t%d" % (l["texto"], l["original"]))
        elif not livros:
            print("Nenhum texto na biblioteca. Acrescente um: tt --leitor ARQUIVO")
        else:
            for l in livros:
                print("%s  %3d%%  %9s palavras  %-40s %s%s" % (l["id"], l["pct"], milhar(l["palavras"]), cortar(l["titulo"], 40),
                      ("lido " + ha_quanto(l["mudada"])) if l["mudada"] else "não começado",
                      (" em " + l["maquina"]) if l["maquina"] and l["maquina"] != maquina() else ""))
    elif cmd == "remover":
        if not args:
            raise Erro("uso: tt --leitor-rm ID")
        meta = remover(resolver(args[0]))
        print("apagado: %s (some das outras máquinas na próxima sincronização)" % (meta.get("titulo") or args[0]))
    elif cmd == "extrair":
        livro = extrair(os.path.expanduser(args[0]))
        print("# %s%s\n" % (livro["titulo"], " — " + livro["autor"] if livro.get("autor") else ""))
        for c in livro["capitulos"]:
            if c["titulo"]:
                print("## %s\n" % c["titulo"])
            for p in c["paragrafos"]:
                print(p + "\n")
    elif cmd == "posicao":
        lid = resolver(args[0])
        total = int(ler_meta(lid).get("palavras") or 0)
        if len(args) > 1:
            v = args[1]
            pos = int(float(v[:-1]) * total / 100) if v.endswith("%") else int(v)
            marcar_posicao(lid, min(pos, max(0, total - 1)), total)
        e = ler_estado(lid)
        print("%d\t%d\t%d\t%s" % (e["pos"], total, e["mudada"], e.get("maquina") or ""))
    elif cmd == "estado":
        livros = listar()
        tam = sum(l["bytes"] for l in livros if l["original"])
        print("📖 leitor: %d %s nesta máquina (%s), %d com o arquivo original (%.1f MB)" % (
            len(livros), "livro" if len(livros) == 1 else "livros", DIR.replace(CASA, "~", 1), sum(l["original"] for l in livros), tam / (1 << 20)))
        for l in livros:
            fora = onde_original(l["id"])
            print("  %s %3d%%  %s%s" % (l["id"], l["pct"], cortar(l["titulo"], 50),
                  "" if l["original"] else ("  · arquivo em: " + ", ".join(fora) if fora else "  · só o texto")))
    elif cmd == "ls":
        json.dump(ls(args[0] if args else ""), sys.stdout, ensure_ascii=False)
        print()
    elif cmd == "rede-nota":
        rede_nota(re.sub(r"[^\w.-]", "-", args[0])[:60], args[1] if len(args) > 1 else "ok")
    elif cmd == "inventario":
        json.dump(inventario(), sys.stdout, ensure_ascii=False)
        print()
    elif cmd == "mesclar":
        n = mesclar(ler_inventario(args[0] if args else "-"))
        print(" ".join("%s=%d" % kv for kv in n.items()))
    elif cmd == "pedir":
        so = None
        if "--so" in args:
            so = resolver(args[args.index("--so") + 1]) if not ID_RE.match(args[args.index("--so") + 1]) else args[args.index("--so") + 1]
        for lid, parte in pedir(ler_inventario(args[0]), enviar="--enviar" in args, so=so):
            print("%s\t%s" % (lid, parte))
    elif cmd == "empacotar":
        pedidos = [tuple(l.split("\t")[:2]) for l in sys.stdin.read().splitlines() if "\t" in l]
        empacotar(pedidos, sys.stdout.buffer)
    elif cmd == "aplicar":
        n = aplicar(sys.stdin.buffer)
        print(" ".join("%s=%d" % kv for kv in n.items()))
    elif cmd == "quadro":
        cmd_quadro(args)
    elif cmd == "motor":
        return cmd_motor(args)
    elif cmd == "ctl":
        if not motor_ctl(" ".join(args)):
            raise Erro("nenhuma leitura na faixa (tt --leitor abre a biblioteca)")
    elif cmd == "fontes":
        a = Atlas()
        if not a.faces:
            print("sem atlas de letras grandes (%s): só o texto do terminal" % ATLAS)
        for k, f in a.faces.items():
            print("%-8s %-18s %s" % (k, f.get("nome"), f.get("licenca")))
    elif cmd == "fontes-gerar":
        indice, tam = gerar_atlas(args[0], args[1] if len(args) > 1 else None)
        print("%s: %d famílias, %.0f KB" % (args[0], len(indice["faces"]), tam / 1024))
    else:
        raise Erro("comando desconhecido: %s" % cmd)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(principal(sys.argv[1:]))
    except Erro as e:
        print("✗ %s" % e, file=sys.stderr)
        sys.exit(1)
    except BrokenPipeError:
        sys.exit(0)
    except KeyboardInterrupt:
        sys.exit(130)
