#!/usr/bin/env python3
"""busca-tt.py — índice de texto completo (SQLite FTS5) das sessões do tt: a conversa INTEIRA do agente de IA de cada
painel (Claude, Codex, Kiro, lida pelo sessoes-ia.py) e o scrollback INTEIRO do tmux, não só as últimas linhas da tela.

  indexar ARQ        ARQ = linhas TSV "sessão<TAB>painel<TAB>provedor<TAB>código-da-conversa" (as de agora, deste servidor
                     tmux). Reindexa só o que mudou, esquece o que sumiu. Só stdlib.
  consultar TEXTO    sessões que casam, uma por linha: "sessão<TAB>pontuação<TAB>fonte<TAB>trecho" (melhor primeiro).
  trecho SESSÃO TEXTO   os trechos (com contexto, destacados em ANSI) onde o texto aparece na conversa/scrollback.
  estado             quantas fontes e quantos KB estão indexados.
  conversas-indexar [--dias N] [--orcamento S]
                     indexa TODAS as conversas antigas desta máquina (Claude, Codex e Kiro; todas as contas; dentro do proot do
                     Termux também), não só as de painéis abertos: mais novas primeiro, só o que mudou, no máximo S segundos por
                     volta (60), das últimas N dias (120). O vigia chama a cada volta até terminar.
  conversas-consultar TEXTO [N]
                     as N (8) conversas antigas que casam: "pontuação, provedor, código, quando, pasta, título, trecho" (TAB).

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
    # O índice copia as conversas inteiras, e o Claude grava as dele só para o dono (600): o banco também (o -wal e o -shm
    # nascem com o modo dele). O umask do main cobre o banco novo; isto, o que já existia com 644.
    for arq in (DB, DB + "-wal", DB + "-shm"):
        try:
            os.chmod(arq, 0o600)
        except OSError:
            pass
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("PRAGMA synchronous=NORMAL")
    c.execute("CREATE TABLE IF NOT EXISTS fontes(chave TEXT PRIMARY KEY, sessao TEXT, fonte TEXT, assinatura TEXT, kb INTEGER, quando INTEGER)")
    c.execute("CREATE TABLE IF NOT EXISTS hist(chave TEXT PRIMARY KEY, prov TEXT, id TEXT, arquivo TEXT, cwd TEXT, quando INTEGER, titulo TEXT)")
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
    # as conversas antigas (fonte "historico") são do conversas-indexar: a volta dos painéis não as conta como vivas e,
    # se as visse, apagava todas a cada volta (e a seguinte gastava o orçamento inteiro reindexando o que já tinha)
    conhecidas = {r[0]: (r[1], r[2]) for r in c.execute("SELECT chave, sessao, assinatura FROM fontes WHERE fonte != 'historico'")}
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
            "FROM fts JOIN fontes f ON f.chave = fts.chave WHERE fts MATCH ? AND f.fonte != 'historico' ORDER BY bm25(fts) LIMIT ?", (q, limite * 4)).fetchall()
    except sqlite3.OperationalError as e:
        print("busca: %s" % e, file=sys.stderr)
        return 1
    vistas = set()
    for sessao, fonte, score, trecho in linhas:
        if sessao in vistas:
            continue
        vistas.add(sessao)
        # O corte do trecho é aqui, por caractere: no awk da central (mawk, awk do macOS) o substr é por byte e partia o
        # "ç" e o "ã" ao meio (a lista mostrava "�").
        trecho = " ".join(trecho.split())
        if len(trecho) > 70:
            trecho = trecho[:70] + "…"
        print("%s\t%.3f\t%s\t%s" % (sessao, score, fonte, trecho))
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
        fontes = c.execute("SELECT f.chave, f.fonte FROM fts JOIN fontes f ON f.chave = fts.chave WHERE fts MATCH ? AND f.sessao = ? AND f.fonte != 'historico' ORDER BY bm25(fts)",
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
        onde = "na conversa inteira" if fonte == "conversa" else "no scrollback inteiro do painel"
        print("%s[90m🔎 %d ocorrência(s) %s · mostrando as últimas%s[0m" % (ESC, len(achou), onde, ESC))
        for i in achou[-3:]:
            print("%s[90m── linha %d de %d ──%s[0m" % (ESC, i + 1, len(linhas), ESC))
            for l in linhas[max(0, i - 4): i + 5]:
                print(padrao.sub(lambda m: ESC + "[30;43m" + m.group(0) + ESC + "[0m", l[:400]))
        saiu = True
    return 0 if saiu else 1


def sem_acento(s):
    import unicodedata
    return "".join(ch for ch in unicodedata.normalize("NFD", s) if unicodedata.category(ch) != "Mn")


# ---------- conversas antigas (todas as contas, todas as conversas em disco) ----------
MAX_CONVERSA = int(os.environ.get("TT_BUSCA_MAX_CONVERSA_MB", "40")) * 1024 * 1024


def modulo_sessoes():
    import importlib.util
    esp = importlib.util.spec_from_file_location("sessoes_ia", os.path.join(HERE, "sessoes-ia.py"))
    mod = importlib.util.module_from_spec(esp)
    esp.loader.exec_module(mod)
    return mod


def listar_conversas(mod, dias):
    """[(mtime, prov, id, arquivo, tamanho)] de todas as conversas em disco, das últimas DIAS, mais nova primeiro."""
    limite = time.time() - dias * 86400
    achadas = {}

    def anota(prov, i, arq):
        try:
            st = os.stat(arq)
        except OSError:
            return
        if st.st_mtime < limite or st.st_size > MAX_CONVERSA or st.st_size == 0:
            return
        k = (prov, i)
        if k not in achadas or achadas[k][0] < st.st_mtime:
            achadas[k] = (st.st_mtime, prov, i, arq, st.st_size)

    for d in mod.todas(".claude"):
        base = os.path.join(d, "projects")
        if not os.path.isdir(base):
            continue
        for pasta in os.listdir(base):
            pp = os.path.join(base, pasta)
            if os.path.isdir(pp):
                for fn in os.listdir(pp):
                    if fn.endswith(".jsonl"):
                        anota("claude", fn[:-6], os.path.join(pp, fn))
    for d in mod.todas(".codex"):
        for dp, _, fns in os.walk(os.path.join(d, "sessions")):
            for fn in fns:
                m = mod.Codex.RE_ID.search(fn)
                if m and fn.startswith("rollout-") and fn.endswith(".jsonl"):
                    anota("codex", m.group(1), os.path.join(dp, fn))
    for d in mod.todas(".kiro"):
        base = os.path.join(d, "sessions", "cli")
        if os.path.isdir(base):
            for fn in os.listdir(base):
                if fn.endswith(".jsonl"):
                    anota("kiro", fn[:-6], os.path.join(base, fn))
    return sorted(achadas.values(), reverse=True)


def texto_da_conversa(mod, prov, arq):
    """(texto, pasta, título) de uma conversa, sem subprocesso. Resultados de ferramentas vêm cortados (como no exportar)."""
    t = mod.Texto(400)
    fn = {"claude": mod.exportar_claude, "codex": mod.exportar_codex, "kiro": mod.exportar_kiro}[prov]
    meta = fn(arq, t) or {}
    titulo = ""
    pegar = False
    for pedaco in t.out:
        if "👤 Usuário" in pedaco:
            pegar = True
            continue
        if pegar:
            titulo = " ".join(pedaco.split())[:90]
            break
    return "".join(t.out), str(meta.get("cwd") or ""), titulo


def cmd_conversas_indexar(dias, orcamento):
    c = abrir()
    mod = modulo_sessoes()
    conhecidas = {r[0]: r[1] for r in c.execute("SELECT chave, assinatura FROM fontes WHERE fonte = 'historico'")}
    inicio = time.time()
    novas = feitas = 0
    arquivos = listar_conversas(mod, dias)
    vivas = set()
    for mtime, prov, i, arq, tam in arquivos:
        chave = "hist:%s:%s" % (prov, i)
        vivas.add(chave)
        assin = "%d:%d" % (mtime, tam)
        if conhecidas.get(chave) == assin:
            continue
        if time.time() - inicio > orcamento:
            feitas += 1  # fica para a próxima volta
            continue
        try:
            txt, cwd, titulo = texto_da_conversa(mod, prov, arq)
        except Exception:
            continue
        gravar(c, chave, "", "historico", assin, txt)
        c.execute("INSERT OR REPLACE INTO hist VALUES(?,?,?,?,?,?,?)", (chave, prov, i, arq, mod.sem_raiz_proot(cwd) if cwd else "", int(mtime), titulo))
        novas += 1
        if novas % 20 == 0:
            c.commit()
    # esquece as conversas que saíram do disco ou da janela de dias
    for chave in list(conhecidas):
        if chave not in vivas:
            c.execute("DELETE FROM fts WHERE chave = ?", (chave,))
            c.execute("DELETE FROM fontes WHERE chave = ?", (chave,))
            c.execute("DELETE FROM hist WHERE chave = ?", (chave,))
    c.commit()
    c.close()
    print("conversas: %d indexadas agora, %d na fila, %d no total" % (novas, feitas, len(arquivos)))
    return 0


def cmd_conversas_consultar(texto, n):
    q = consulta_fts(texto)
    if not q or not os.path.exists(DB):
        return 0
    c = abrir()
    try:
        linhas = c.execute(
            "SELECT bm25(fts), h.prov, h.id, h.quando, h.cwd, h.titulo, snippet(fts, 0, '', '', '…', 14) "
            "FROM fts JOIN hist h ON h.chave = fts.chave WHERE fts MATCH ? ORDER BY bm25(fts) LIMIT ?", (q, n)).fetchall()
    except sqlite3.OperationalError as e:
        print("busca: %s" % e, file=sys.stderr)
        return 1
    for score, prov, i, quando, cwd, titulo, trecho in linhas:
        print("\t".join(["%.3f" % score, prov, i, time.strftime("%Y-%m-%d %H:%M", time.localtime(quando)), cwd, titulo.replace("\t", " "),
                         " ".join(trecho.split())]))
    return 0


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
    os.umask(0o077)  # banco, -wal e -shm novos só para o dono (veja abrir)
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
    if a[0] == "conversas-indexar":
        dias, orc = 120, 60
        for k in range(1, len(a) - 1):
            if a[k] == "--dias":
                dias = int(a[k + 1])
            elif a[k] == "--orcamento":
                orc = float(a[k + 1])
        return cmd_conversas_indexar(dias, orc)
    if a[0] == "conversas-consultar" and len(a) >= 2:
        n = int(a[-1]) if len(a) >= 3 and a[-1].isdigit() else 8
        return cmd_conversas_consultar(" ".join(a[1:-1] if len(a) >= 3 and a[-1].isdigit() else a[1:]), n)
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
