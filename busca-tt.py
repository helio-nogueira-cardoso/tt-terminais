#!/usr/bin/env python3
"""busca-tt.py — índice de texto completo (SQLite FTS5) das sessões do tt: a conversa INTEIRA do agente de IA de cada
painel (Claude, Codex, Kiro, lida pelo sessoes-ia.py) e o scrollback INTEIRO do tmux, não só as últimas linhas da tela.

  indexar ARQ        ARQ = linhas TSV "sessão<TAB>painel<TAB>provedor<TAB>código-da-conversa" (as de agora, deste servidor
                     tmux). Reindexa só o que mudou, esquece o que sumiu. Só stdlib.
  consultar TEXTO    sessões que casam, uma por linha: "sessão<TAB>pontuação<TAB>fonte<TAB>trecho" (melhor primeiro).
  trecho SESSÃO TEXTO   os trechos (com contexto, destacados em ANSI) onde o texto aparece na conversa/scrollback.
  estado             quantas fontes e quantos KB estão indexados.

TEXTO: palavras em qualquer ordem (E), sem acento nem caixa, com prefixo ("autent" acha "autenticação"); "frase exata"
entre aspas; !palavra exclui. A pasta do índice é $TT_BUSCA_DB ou ~/.cache/tt/busca.db.
"""
import hashlib
import os
import re
import sqlite3
import subprocess
import sys
import time

DB = os.environ.get("TT_BUSCA_DB") or os.path.expanduser("~/.cache/tt/busca.db")
TMUX = os.environ.get("TT_TMUX_BIN") or "tmux"
HERE = os.path.dirname(os.path.abspath(__file__))
MAX_FONTE = int(os.environ.get("TT_BUSCA_MAX_KB", "16384")) * 1024  # teto de texto por fonte (conversa ou scrollback)
ESC = "\033"


def abrir():
    os.makedirs(os.path.dirname(DB), exist_ok=True)
    c = sqlite3.connect(DB, timeout=30)
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("PRAGMA synchronous=NORMAL")
    c.execute("CREATE TABLE IF NOT EXISTS fontes(chave TEXT PRIMARY KEY, sessao TEXT, fonte TEXT, assinatura TEXT, kb INTEGER, quando INTEGER)")
    c.execute("CREATE VIRTUAL TABLE IF NOT EXISTS fts USING fts5(texto, chave UNINDEXED, tokenize='unicode61 remove_diacritics 2')")
    return c


def limpar(t):
    t = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", t)
    return t.replace("\r", "")


def tmux_tela(painel):
    try:
        r = subprocess.run([TMUX, "capture-pane", "-p", "-J", "-S", "-", "-t", painel], capture_output=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if r.returncode != 0:
        return None
    return r.stdout.decode("utf-8", "replace")


def tmux_hist(painel):
    try:
        r = subprocess.run([TMUX, "display-message", "-p", "-t", painel, "#{history_size}"], capture_output=True, timeout=10)
        return r.stdout.decode().strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def arquivo_conversa(cod):
    """Caminho do arquivo da conversa COD nesta máquina (pelo sessoes-ia.py), ou ""."""
    try:
        import importlib.util
        esp = importlib.util.spec_from_file_location("sessoes_ia", os.path.join(HERE, "sessoes-ia.py"))
        mod = importlib.util.module_from_spec(esp)
        esp.loader.exec_module(mod)
        return mod.achar_conversa(cod)[1] or ""
    except Exception:
        return ""


def conversa(cod):
    try:
        r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "sessoes-ia.py"), "exportar", cod, "--max-resultado", "600"],
                           capture_output=True, timeout=180)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if r.returncode != 0:
        return None
    return r.stdout.decode("utf-8", "replace")


def assinatura_arquivo(arq):
    try:
        st = os.stat(arq)
        return "%d:%d" % (st.st_mtime, st.st_size)
    except OSError:
        return ""


def gravar(c, chave, sessao, fonte, assin, texto):
    texto = texto[-MAX_FONTE:] if len(texto) > MAX_FONTE else texto
    c.execute("DELETE FROM fts WHERE chave = ?", (chave,))
    c.execute("INSERT INTO fts(texto, chave) VALUES(?, ?)", (texto, chave))
    c.execute("INSERT OR REPLACE INTO fontes VALUES(?,?,?,?,?,?)", (chave, sessao, fonte, assin, len(texto) // 1024, int(time.time())))


def cmd_indexar(arq):
    c = abrir()
    vivas = set()
    novas = 0
    with open(arq, encoding="utf-8") as f:
        linhas = [l.rstrip("\n").split("\t") for l in f if l.strip()]
    conhecidas = {r[0]: (r[1], r[2]) for r in c.execute("SELECT chave, sessao, assinatura FROM fontes")}
    for l in linhas:
        l += [""] * (4 - len(l))
        sessao, painel, prov, cod = l[:4]
        # 1) a conversa do agente (uma só por código, mesmo que dois painéis a mostrem)
        if cod:
            chave = "conversa:%s" % cod
            vivas.add(chave)
            if chave in conhecidas and conhecidas[chave][0] != sessao:
                c.execute("UPDATE fontes SET sessao=? WHERE chave=?", (sessao, chave))
            # a assinatura é a do arquivo da conversa (mtime:tamanho): só relê o texto se mudou
            assin = assinatura_arquivo(arquivo_conversa(cod))
            if not assin:
                vivas.discard(chave)  # conversa que não está nesta máquina: nada a indexar
            elif chave not in conhecidas or conhecidas[chave][1] != assin:
                txt = conversa(cod)
                if txt is not None:
                    gravar(c, chave, sessao, "conversa", assin, txt)
                    novas += 1
        # 2) o scrollback inteiro do painel
        if painel:
            chave = "tela:%s:%s" % (sessao, painel)
            vivas.add(chave)
            h = tmux_hist(painel)
            tela = tmux_tela(painel)
            if tela is not None:
                assin = "%s:%s" % (h, hashlib.sha1(tela[-4000:].encode("utf-8", "replace")).hexdigest()[:12])
                if chave not in conhecidas or conhecidas[chave][1] != assin:
                    gravar(c, chave, sessao, "tela", assin, limpar(tela))
                    novas += 1
    # esquece o que sumiu (painel fechado, conversa que nenhum painel mostra mais)
    for chave in list(conhecidas):
        if chave not in vivas:
            c.execute("DELETE FROM fts WHERE chave = ?", (chave,))
            c.execute("DELETE FROM fontes WHERE chave = ?", (chave,))
    c.commit()
    c.close()
    print("indexadas %d fonte(s) novas/mudadas; %d vivas" % (novas, len(vivas)))
    return 0


def consulta_fts(texto):
    """TEXTO do usuário → expressão do FTS5, ou None se não sobrou nada para procurar."""
    partes, nao = [], []
    for m in re.finditer(r'(!?)"([^"]+)"|(!?)(\S+)', texto):
        neg = (m.group(1) or m.group(3)) == "!"
        bruto = m.group(2) or m.group(4)
        if m.group(2):  # frase exata
            toks = re.findall(r"\w+", bruto, re.U)
            if not toks:
                continue
            ex = '"%s"' % " ".join(toks)
        else:
            toks = re.findall(r"\w+", bruto.strip("^$'"), re.U)
            if not toks:
                continue
            ex = " ".join('"%s"*' % t for t in toks)
            if len(toks) > 1:
                ex = "(%s)" % ex
        (nao if neg else partes).append(ex)
    if not partes:
        return None
    q = " AND ".join(partes)
    if nao:
        q = "(%s) NOT (%s)" % (q, " OR ".join(nao))
    return q


def cmd_consultar(texto, limite=200):
    q = consulta_fts(texto)
    if not q or not os.path.exists(DB):
        return 0
    c = abrir()
    try:
        linhas = c.execute(
            "SELECT f.sessao, f.fonte, bm25(fts), snippet(fts, 0, '', '', '…', 12) "
            "FROM fts JOIN fontes f ON f.chave = fts.chave WHERE fts MATCH ? ORDER BY bm25(fts) LIMIT ?", (q, limite * 4)).fetchall()
    except sqlite3.OperationalError as e:
        print("busca: %s" % e, file=sys.stderr)
        return 1
    vistas = set()
    for sessao, fonte, score, trecho in linhas:
        if sessao in vistas:
            continue
        vistas.add(sessao)
        print("%s\t%.3f\t%s\t%s" % (sessao, score, fonte, " ".join(trecho.split())))
        if len(vistas) >= limite:
            break
    return 0


def cmd_trecho(sessao, texto):
    q = consulta_fts(texto)
    if not q or not os.path.exists(DB):
        return 1
    termos = [t for t in re.findall(r"\w+", re.sub(r"(^|\s)![^\s]+", " ", texto), re.U) if len(t) > 0]
    if not termos:
        return 1
    padrao = re.compile("|".join(re.escape(t) for t in termos), re.I)
    c = abrir()
    try:
        fontes = c.execute("SELECT f.chave, f.fonte FROM fts JOIN fontes f ON f.chave = fts.chave WHERE fts MATCH ? AND f.sessao = ? ORDER BY bm25(fts)",
                           (q, sessao)).fetchall()
    except sqlite3.OperationalError:
        return 1
    if not fontes:
        return 1
    saiu = False
    for chave, fonte in fontes[:2]:
        linha = c.execute("SELECT texto FROM fts WHERE chave = ?", (chave,)).fetchone()
        if not linha:
            continue
        linhas = linha[0].split("\n")
        achou = [i for i, l in enumerate(linhas) if padrao.search(l) or padrao.search(sem_acento(l))]
        if not achou:
            continue
        onde = "conversa" if fonte == "conversa" else "scrollback do painel"
        print("%s[90m🔎 %d ocorrência(s) na %s inteira · mostrando as últimas%s[0m" % (ESC, len(achou), onde, ESC))
        for i in achou[-3:]:
            print("%s[90m── linha %d de %d ──%s[0m" % (ESC, i + 1, len(linhas), ESC))
            for l in linhas[max(0, i - 4): i + 5]:
                print(padrao.sub(lambda m: ESC + "[30;43m" + m.group(0) + ESC + "[0m", l[:400]))
        saiu = True
    return 0 if saiu else 1


def sem_acento(s):
    import unicodedata
    return "".join(ch for ch in unicodedata.normalize("NFD", s) if unicodedata.category(ch) != "Mn")


def cmd_estado():
    if not os.path.exists(DB):
        print("sem índice ainda")
        return 0
    c = abrir()
    n, kb = c.execute("SELECT COUNT(*), COALESCE(SUM(kb), 0) FROM fontes").fetchone()
    por = c.execute("SELECT fonte, COUNT(*), COALESCE(SUM(kb), 0) FROM fontes GROUP BY fonte").fetchall()
    print("%d fonte(s), %d KB de texto indexado (%s) · %s" % (n, kb, ", ".join("%s: %d (%d KB)" % p for p in por) or "vazio", DB))
    return 0


def main(a):
    if not a:
        print(__doc__.strip())
        return 2
    if a[0] == "indexar" and len(a) == 2:
        return cmd_indexar(a[1])
    if a[0] == "consultar" and len(a) >= 2:
        return cmd_consultar(" ".join(a[1:]))
    if a[0] == "trecho" and len(a) >= 3:
        return cmd_trecho(a[1], " ".join(a[2:]))
    if a[0] == "estado":
        return cmd_estado()
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
