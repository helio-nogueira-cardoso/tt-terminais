#!/usr/bin/env python3
"""sessoes-ia.py — replica as conversas das IAs (Claude Code, Codex, Kiro CLI) entre as máquinas do tt.

Só stdlib (roda no Termux). O tt cuida do ssh; este utilitário faz a parte de dados:

  inventario              JSON por linha: {"p","k","h","n","m"[,"u"]} de cada conversa desta máquina,
                          mais um cabeçalho {"provedores":[...],"home":...}. Conversas mexidas há menos
                          de TT_SESSOES_QUIETO s (120) ficam de fora: estão em uso, vão na próxima volta.
  pedir ARQ [--enviar]    com o inventário de OUTRA máquina em ARQ, as chaves "p<TAB>k" que valem
                          buscar de lá (padrão) ou mandar para lá (--enviar).
  empacotar               lê chaves "p<TAB>k" no stdin e escreve um tar.gz no stdout.
  aplicar                 lê o tar.gz no stdin e mescla aqui; imprime o resumo "chave=valor".
  estado                  quantas conversas há aqui, por provedor.

Forma canônica: o caminho da home (e a pasta do Codex) dentro dos campos "cwd" vira um marcador, e a
pasta do projeto do Claude (o cwd codificado) também; quem recebe põe a home dele. Assim a conversa
aberta em /home/heliocardoso aparece no /resume de /home/helio, e a ida e a volta dão os mesmos bytes.

Mescla (quem recebe decide): falta aqui → grava; igual → nada; transcrição (.jsonl) que só cresceu →
fica a mais longa; divergiu (continuada nas duas máquinas) → fica a mais nova e a outra vai para
~/.local/state/tt/sessoes-ia/conflitos (nada se perde); conversa em uso aqui → espera a próxima volta.
"""
import hashlib
import io
import json
import os
import re
import shutil
import sqlite3
import sys
import tarfile
import tempfile
import time
from fnmatch import fnmatch

MARCA_HOME = "@@TT_HOME@@"
MARCA_CODEX = "@@TT_CODEX@@"
DIR_HOME = "@H"  # prefixo canônico da pasta de projeto do Claude
QUIETO = int(os.environ.get("TT_SESSOES_QUIETO", "120"))
HOME = os.path.expanduser("~")
ESTADO = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "tt", "sessoes-ia")
CACHE = os.path.join(HOME, ".cache", "tt", "sessoes-ia-hash.json")
EXCLUIR = (os.environ.get("TT_SESSOES_EXCLUIR") or "").split()


def raizes_proot():
    pre = os.environ.get("PREFIX")
    if not pre:
        return []
    base = os.path.join(pre, "var", "lib", "proot-distro")
    out = []
    for sub in ("containers",):
        d = os.path.join(base, sub)
        for n in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            out.append(os.path.join(d, n, "rootfs"))
    d = os.path.join(base, "installed-rootfs")
    for n in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        out.append(os.path.join(d, n))
    return out


def achar(ponto, sub=""):
    """(pasta real, home vista pelo agente) do ponto (.claude/.codex/.kiro): a da home e, no Termux,
    a do root de dentro do proot (onde o Claude do celular roda). Vale a primeira que já tem SUB
    (no Termux pode haver um ~/.claude quase vazio ao lado do de verdade, que fica no proot)."""
    cands = [(os.path.join(HOME, ponto), HOME)] + [(os.path.join(r, "root", ponto), "/root") for r in raizes_proot()]
    cands = [(d, h) for d, h in cands if os.path.isdir(d)]
    for d, h in cands:
        if os.path.isdir(os.path.join(d, sub)):
            return d, h
    return cands[0] if cands else (None, None)


def re_cwd(home):
    return re.compile(r'("cwd"\s*:\s*"(?:file://)?)' + re.escape(home) + r'(?=[/"])')


RE_MARCA = re.compile(r'("cwd"\s*:\s*"(?:file://)?)' + re.escape(MARCA_HOME))


def enc_claude(caminho):
    return re.sub(r"[^A-Za-z0-9]", "-", caminho)


def truncar_linha(b):
    """Transcrição em gravação: só até a última linha completa."""
    i = b.rfind(b"\n")
    return b[: i + 1] if i >= 0 else b""


class Provedor:
    nome = ""
    tipo = "anexa"  # anexa (.jsonl que só cresce) | grupo (arquivos que são reescritos juntos)

    def __init__(self):
        self.base, self.home = self.descobrir()
        if self.base:
            self._re = re_cwd(self.home)

    def ativo(self):
        return bool(self.base)

    def canon(self, b):
        t = b.decode("utf-8", "surrogateescape")
        return self._re.sub(lambda m: m.group(1) + MARCA_HOME, t).encode("utf-8", "surrogateescape")

    def decanon(self, b):
        t = b.decode("utf-8", "surrogateescape")
        return RE_MARCA.sub(lambda m: m.group(1) + self.home, t).encode("utf-8", "surrogateescape")

    # chave canônica <-> caminho relativo à base
    def chave(self, rel):
        return rel

    def rel(self, chave):
        return chave


class Claude(Provedor):
    nome = "claude"

    def descobrir(self):
        d, h = achar(".claude", "projects")
        return (os.path.join(d, "projects"), h) if d else (None, None)

    def unidades(self):
        if not os.path.isdir(self.base):
            return
        for pasta in os.listdir(self.base):
            raiz = os.path.join(self.base, pasta)
            if not os.path.isdir(raiz):
                continue
            for dp, dns, fns in os.walk(raiz):
                # memory/ é a memória do agente por projeto: cada máquina tem a sua (o tt já trata a
                # memória dos agentes à parte); copiá-la faria uma máquina apagar a da outra.
                dns[:] = [n for n in dns if not (dp == raiz and n == "memory")]
                for fn in fns:
                    rel = os.path.relpath(os.path.join(dp, fn), self.base)
                    yield self.chave(rel), [rel], ("anexa" if fn.endswith(".jsonl") else "inteiro")

    def chave(self, rel):
        pasta, _, resto = rel.partition("/")
        e = enc_claude(self.home)
        if pasta == e:
            pasta = DIR_HOME
        elif pasta.startswith(e + "-"):
            pasta = DIR_HOME + pasta[len(e):]
        return pasta + "/" + resto

    def rel(self, chave):
        pasta, _, resto = chave.partition("/")
        if pasta == DIR_HOME or pasta.startswith(DIR_HOME + "-"):
            pasta = enc_claude(self.home) + pasta[len(DIR_HOME):]
        return pasta + "/" + resto


class Codex(Provedor):
    nome = "codex"
    RE_ID = re.compile(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$")

    def descobrir(self):
        d = os.environ.get("CODEX_HOME")
        if d and os.path.isdir(d):
            return d, HOME
        return achar(".codex", "sessions")

    def unidades(self):
        s = os.path.join(self.base, "sessions")
        for dp, _, fns in os.walk(s):
            for fn in fns:
                if fn.startswith("rollout-") and fn.endswith(".jsonl"):
                    rel = os.path.relpath(os.path.join(dp, fn), self.base)
                    yield rel, [rel], "anexa"

    def banco(self):
        n = [(int(m.group(1)), f) for f in os.listdir(self.base) for m in [re.match(r"state_(\d+)\.sqlite$", f)] if m]
        return os.path.join(self.base, max(n)[1]) if n else None

    def id_de(self, chave):
        m = self.RE_ID.search(chave)
        return m.group(1) if m else None

    def linhas_banco(self, ids):
        """Linhas da tabela threads (o /resume do Codex lista por ela), na forma canônica."""
        b = self.banco()
        if not b or not ids:
            return {}
        out = {}
        try:
            c = sqlite3.connect("file:%s?mode=ro" % b, uri=True, timeout=5)
            c.row_factory = sqlite3.Row
            for i in ids:
                r = c.execute("select * from threads where id=?", (i,)).fetchone()
                if r:
                    d = dict(r)
                    if isinstance(d.get("cwd"), str):
                        d["cwd"] = self.canon_caminho(d["cwd"])
                    if isinstance(d.get("rollout_path"), str) and d["rollout_path"].startswith(self.base + "/"):
                        d["rollout_path"] = MARCA_CODEX + d["rollout_path"][len(self.base):]
                    out[i] = d
            c.close()
        except sqlite3.Error:
            return {}
        return out

    def indice(self, ids):
        f = os.path.join(self.base, "session_index.jsonl")
        out = {}
        try:
            with open(f, encoding="utf-8") as fh:
                for l in fh:
                    try:
                        i = json.loads(l).get("id")
                    except ValueError:
                        continue
                    if i in ids:
                        out[i] = l if l.endswith("\n") else l + "\n"
        except OSError:
            pass
        return out

    def canon_caminho(self, p):
        if p == self.home or p.startswith(self.home + "/"):
            return MARCA_HOME + p[len(self.home):]
        return p

    def decanon_caminho(self, p):
        return self.home + p[len(MARCA_HOME):] if p.startswith(MARCA_HOME) else p

    def gravar_banco(self, linhas):
        b = self.banco()
        if not b or not linhas:
            return 0
        n = 0
        try:
            c = sqlite3.connect(b, timeout=10)
            cols = [r[1] for r in c.execute("pragma table_info(threads)")]
            for i, d in linhas.items():
                d = dict(d)
                d["cwd"] = self.decanon_caminho(d.get("cwd") or "")
                rp = d.get("rollout_path") or ""
                if rp.startswith(MARCA_CODEX):
                    d["rollout_path"] = self.base + rp[len(MARCA_CODEX):]
                d = {k: v for k, v in d.items() if k in cols}
                atual = c.execute("select updated_at from threads where id=?", (i,)).fetchone()
                if atual is None:
                    ks = list(d)
                    c.execute("insert or ignore into threads (%s) values (%s)" % (",".join(ks), ",".join("?" * len(ks))),
                              [d[k] for k in ks])
                    n += 1
                elif (d.get("updated_at") or 0) > (atual[0] or 0):
                    ks = [k for k in d if k != "id"]
                    c.execute("update threads set %s where id=?" % ",".join(k + "=?" for k in ks), [d[k] for k in ks] + [i])
                    n += 1
            c.commit()
            c.close()
        except sqlite3.Error as e:
            print("aviso: banco do Codex: %s" % e, file=sys.stderr)
        return n

    def gravar_indice(self, linhas):
        if not linhas:
            return
        f = os.path.join(self.base, "session_index.jsonl")
        tem = set(self.indice(set(linhas)))
        novas = [l for i, l in linhas.items() if i not in tem]
        if novas:
            with open(f, "a", encoding="utf-8") as fh:
                fh.writelines(novas)


class Kiro(Provedor):
    """Kiro CLI: sessions/cli/<uuid>.json (estado, reescrito inteiro) + .jsonl + .history."""
    nome = "kiro"
    tipo = "grupo"
    SUFIXOS = (".json", ".jsonl", ".history")

    def descobrir(self):
        d, h = achar(".kiro", os.path.join("sessions", "cli"))
        return (os.path.join(d, "sessions", "cli"), h) if d else (None, None)

    def ativo(self):
        return bool(self.base) and os.path.isdir(self.base)

    def unidades(self):
        if not os.path.isdir(self.base):
            return
        fns = set(os.listdir(self.base))
        for fn in sorted(fns):
            if fn.endswith(".json"):
                u = fn[:-5]
                yield u, [u + s for s in self.SUFIXOS if u + s in fns], "grupo"


PROVEDORES = [Claude, Codex, Kiro]


def provedores():
    return {p.nome: p for p in (c() for c in PROVEDORES) if p.ativo()}


def excluida(p, k):
    return any(fnmatch(p + "/" + k, pad) for pad in EXCLUIR)


# --- inventário com cache de hash --------------------------------------------------------------

class Hashes:
    def __init__(self):
        try:
            with open(CACHE) as f:
                self.c = json.load(f)
        except (OSError, ValueError):
            self.c = {}
        self.usado = {}

    def de(self, prov, caminho, st, anexa):
        chave = "%s|%s" % (prov.home, caminho)
        e = self.c.get(chave)
        if e and e[0] == st.st_size and e[1] == st.st_mtime_ns:
            self.usado[chave] = e
            return e[2], e[3]
        with open(caminho, "rb") as f:
            b = f.read()
        if anexa:
            b = truncar_linha(b)
        b = prov.canon(b)
        e = [st.st_size, st.st_mtime_ns, hashlib.sha1(b).hexdigest(), len(b)]
        self.usado[chave] = e
        return e[2], e[3]

    def salvar(self):
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        t = CACHE + ".%d" % os.getpid()
        with open(t, "w") as f:
            json.dump(self.usado, f)
        os.replace(t, CACHE)


def inventario_de(provs, quieto=QUIETO):
    agora = time.time()
    hs = Hashes()
    itens = {}
    for p in provs.values():
        for k, rels, tipo in p.unidades():
            if excluida(p.nome, k):
                continue
            try:
                sts = [(r, os.stat(os.path.join(p.base, r))) for r in rels]
            except OSError:
                continue
            m = max(st.st_mtime for _, st in sts)
            if agora - m < quieto:
                continue
            if tipo == "grupo":
                partes = []
                for r, st in sts:
                    h, _ = hs.de(p, os.path.join(p.base, r), st, r.endswith(".jsonl"))
                    partes.append("%s:%s" % (r[len(k):], h))
                h = hashlib.sha1(";".join(partes).encode()).hexdigest()
                n = 0
                u = kiro_atualizada(os.path.join(p.base, k + ".json"))
                if u is None:  # json em gravação ou estragado: fica para a próxima volta
                    continue
                itens[(p.nome, k)] = {"p": p.nome, "k": k, "h": h, "n": n, "m": int(m), "u": u}
            else:
                h, n = hs.de(p, os.path.join(p.base, rels[0]), sts[0][1], tipo == "anexa")
                itens[(p.nome, k)] = {"p": p.nome, "k": k, "h": h, "n": n, "m": int(m), "t": tipo}
    hs.salvar()
    return itens


def kiro_atualizada(arq):
    try:
        with open(arq, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return None
    return str(d.get("updated_at") or "")


def cmd_inventario():
    provs = provedores()
    print(json.dumps({"provedores": sorted(provs), "versao": 1}))
    for it in inventario_de(provs).values():
        print(json.dumps(it, separators=(",", ":")))


def ler_inventario(arq):
    cab, itens = None, {}
    with open(arq, encoding="utf-8") as f:
        for l in f:
            try:
                d = json.loads(l)
            except ValueError:
                continue
            if "provedores" in d:
                cab = d
            elif "p" in d and "k" in d and ".." not in d["k"].split("/") and not d["k"].startswith("/"):
                itens[(d["p"], d["k"])] = d
    return cab, itens


def ler_canon(p, k, tipo):
    """Conteúdo canônico de uma unidade simples, ou None."""
    try:
        with open(os.path.join(p.base, p.rel(k)), "rb") as f:
            b = f.read()
    except OSError:
        return None
    return p.canon(truncar_linha(b) if tipo == "anexa" else b)


def cmd_pedir(arq, enviar):
    cab, remoto = ler_inventario(arq)
    if cab is None:
        return
    provs = provedores()
    local = inventario_de(provs)
    lado_provs = set(cab.get("provedores") or [])
    if not enviar:
        for key, r in remoto.items():
            p = provs.get(r["p"])
            if not p or excluida(*key):
                continue
            l = local.get(key)
            if l and l["h"] == r["h"]:
                continue
            if l and r.get("t") == "anexa" and l.get("n", 0) > r.get("n", 0):
                b = ler_canon(p, r["k"], "anexa")
                if b is not None and hashlib.sha1(b[: r["n"]]).hexdigest() == r["h"]:
                    continue  # a daqui só cresceu: vai no envio
            if l and p.tipo == "grupo" and l.get("u", "") >= r.get("u", ""):
                continue  # a daqui é a mais nova (ou igual): vai no envio
            print("%s\t%s" % key)
    else:
        for key, l in local.items():
            if key[0] not in lado_provs or excluida(*key):
                continue
            r = remoto.get(key)
            if r and r["h"] == l["h"]:
                continue
            if r and provs[key[0]].tipo == "grupo" and r.get("u", "") >= l.get("u", ""):
                continue
            print("%s\t%s" % key)


def cmd_empacotar():
    provs = provedores()
    pedidos = []
    for l in sys.stdin:
        p, _, k = l.rstrip("\n").partition("\t")
        if p in provs and k and ".." not in k.split("/") and not k.startswith("/"):
            pedidos.append((provs[p], k))
    meta = {"versao": 1, "codex_threads": {}, "codex_indice": {}}
    ids_codex = set()
    with tarfile.open(fileobj=sys.stdout.buffer, mode="w|gz") as tar:
        for p, k in pedidos:
            if p.tipo == "grupo":
                nomes = [k + s for s in Kiro.SUFIXOS if os.path.exists(os.path.join(p.base, k + s))]
                if not nomes or kiro_atualizada(os.path.join(p.base, k + ".json")) is None:
                    continue
                membros = [(k + "/" + n[len(k):], os.path.join(p.base, n), n.endswith(".jsonl")) for n in nomes]
            else:
                tipo = "anexa" if k.endswith(".jsonl") else "inteiro"
                membros = [(k, os.path.join(p.base, p.rel(k)), tipo == "anexa")]
            for nome, cam, anexa in membros:
                try:
                    st = os.stat(cam)
                    with open(cam, "rb") as f:
                        b = f.read()
                except OSError:
                    continue
                b = p.canon(truncar_linha(b) if anexa else b)
                ti = tarfile.TarInfo(p.nome + "/" + nome)
                ti.size, ti.mtime, ti.mode = len(b), int(st.st_mtime), 0o600
                tar.addfile(ti, io.BytesIO(b))
            if p.nome == "codex":
                i = p.id_de(k)
                if i:
                    ids_codex.add(i)
        cx = provs.get("codex")
        if cx and ids_codex:
            meta["codex_threads"] = cx.linhas_banco(ids_codex)
            meta["codex_indice"] = cx.indice(ids_codex)
        b = json.dumps(meta).encode()
        ti = tarfile.TarInfo("meta.json")
        ti.size, ti.mtime = len(b), int(time.time())
        tar.addfile(ti, io.BytesIO(b))


# --- aplicar ------------------------------------------------------------------------------------

class Trava:
    def __init__(self, d):
        self.d = d

    def __enter__(self):
        os.makedirs(os.path.dirname(self.d), exist_ok=True)
        for _ in range(600):
            try:
                os.mkdir(self.d)
                return self
            except FileExistsError:
                try:
                    if time.time() - os.stat(self.d).st_mtime > 900:
                        os.rmdir(self.d)
                        continue
                except OSError:
                    pass
                time.sleep(0.5)
        raise SystemExit("trava ocupada: %s" % self.d)

    def __exit__(self, *a):
        try:
            os.rmdir(self.d)
        except OSError:
            pass


def em_uso(caminho):
    try:
        return time.time() - os.stat(caminho).st_mtime < QUIETO
    except OSError:
        return False


def guardar_conflito(p, k, caminhos):
    """A versão daqui que vai ser trocada por outra que divergiu dela: guardada, nunca apagada."""
    d = os.path.join(ESTADO, "conflitos", p.nome, time.strftime("%Y%m%d-%H%M%S"), k)
    for c in caminhos:
        if os.path.exists(c):
            alvo = os.path.join(d, os.path.basename(c)) if p.tipo == "grupo" else d
            os.makedirs(os.path.dirname(alvo), exist_ok=True)
            shutil.copy2(c, alvo)


def gravar(caminho, b, mtime):
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    fd, t = tempfile.mkstemp(dir=os.path.dirname(caminho), prefix=".tt-sessao.")
    with os.fdopen(fd, "wb") as f:
        f.write(b)
    os.chmod(t, 0o600)
    os.utime(t, (mtime, mtime))
    os.replace(t, caminho)


def cmd_aplicar():
    provs = provedores()
    res = {"novas": 0, "atualizadas": 0, "conflitos": 0, "em_uso": 0, "iguais": 0, "mantidas": 0}
    with Trava(os.path.join(ESTADO, "trava")):
        os.makedirs(ESTADO, exist_ok=True)
        stg = tempfile.mkdtemp(dir=ESTADO, prefix="entrada.")
        try:
            meta = {}
            entradas = []  # (provedor, chave, membro relativo, caminho no staging, mtime)
            with tarfile.open(fileobj=sys.stdin.buffer, mode="r|gz") as tar:
                for ti in tar:
                    if not ti.isfile() or ".." in ti.name.split("/") or ti.name.startswith("/"):
                        continue
                    f = tar.extractfile(ti)
                    b = f.read() if f else b""
                    if ti.name == "meta.json":
                        try:
                            meta = json.loads(b)
                        except ValueError:
                            meta = {}
                        continue
                    pn, _, resto = ti.name.partition("/")
                    if pn not in provs or not resto:
                        continue
                    sc = os.path.join(stg, "%06d" % len(entradas))
                    with open(sc, "wb") as fh:
                        fh.write(b)
                    entradas.append((pn, resto, sc, ti.mtime))
            grupos = {}
            for pn, resto, sc, mt in entradas:
                p = provs[pn]
                if p.tipo == "grupo":
                    k, _, suf = resto.partition("/")
                    grupos.setdefault((pn, k), []).append((suf, sc, mt))
                    continue
                aplicar_simples(p, resto, sc, mt, res)
            for (pn, k), membros in grupos.items():
                aplicar_grupo(provs[pn], k, membros, res)
            cx = provs.get("codex")
            if cx and meta.get("codex_threads"):
                cx.gravar_banco(meta["codex_threads"])
                cx.gravar_indice(meta.get("codex_indice") or {})
        finally:
            shutil.rmtree(stg, ignore_errors=True)
    print(" ".join("%s=%d" % kv for kv in res.items()))


def aplicar_simples(p, k, sc, mt, res):
    with open(sc, "rb") as f:
        novo = f.read()
    cam = os.path.join(p.base, p.rel(k))
    anexa = k.endswith(".jsonl")
    if not os.path.exists(cam):
        gravar(cam, p.decanon(novo), mt)
        res["novas"] += 1
        return
    atual = ler_canon(p, k, "anexa" if anexa else "inteiro")
    if atual == novo:
        res["iguais"] += 1
        return
    if anexa and atual is not None and atual.startswith(novo):
        res["mantidas"] += 1  # a daqui já tem tudo e mais
        return
    if em_uso(cam):
        res["em_uso"] += 1
        return
    if anexa and atual is not None and novo.startswith(atual):
        gravar(cam, p.decanon(novo), mt)
        res["atualizadas"] += 1
        return
    if mt <= os.stat(cam).st_mtime:
        res["mantidas"] += 1  # divergiu e a daqui é a mais nova: ela vai para lá no envio
        return
    guardar_conflito(p, k, [cam])
    gravar(cam, p.decanon(novo), mt)
    res["conflitos"] += 1


def aplicar_grupo(p, k, membros, res):
    js = [sc for suf, sc, _ in membros if suf == ".json"]
    if not js:
        return
    u_nova = kiro_atualizada(js[0])
    if u_nova is None:
        return
    caminhos = [os.path.join(p.base, k + s) for s in Kiro.SUFIXOS]
    if os.path.exists(caminhos[0]):
        u_atual = kiro_atualizada(caminhos[0]) or ""
        if u_atual >= u_nova:
            res["iguais" if u_atual == u_nova else "mantidas"] += 1
            return
        if any(em_uso(c) for c in caminhos) or kiro_aberta(p, k):
            res["em_uso"] += 1
            return
        # O .jsonl do Kiro também só cresce: se o daqui é começo do que chegou, é só uma atualização;
        # senão a conversa foi continuada nas duas máquinas e a daqui fica guardada.
        jn = [sc for suf, sc, _ in membros if suf == ".jsonl"]
        atual = ler_canon(p, k + ".jsonl", "anexa") or b""
        novo = b""
        if jn:
            with open(jn[0], "rb") as f:
                novo = f.read()
        if novo.startswith(atual):
            res["atualizadas"] += 1
        else:
            guardar_conflito(p, k, caminhos)
            res["conflitos"] += 1
    else:
        res["novas"] += 1
    for suf, sc, mt in membros:
        if suf not in Kiro.SUFIXOS:
            continue
        with open(sc, "rb") as f:
            b = f.read()
        gravar(os.path.join(p.base, k + suf), p.decanon(b), mt)


def kiro_aberta(p, k):
    """O Kiro deixa <uuid>.lock com o pid de quem está com a conversa aberta."""
    try:
        with open(os.path.join(p.base, k + ".lock"), encoding="utf-8") as f:
            pid = int(json.load(f).get("pid") or 0)
    except (OSError, ValueError, AttributeError):
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def cmd_estado():
    provs = provedores()
    for nome in ("claude", "codex", "kiro"):
        p = provs.get(nome)
        if not p:
            print("%s\t-\tnão usado nesta máquina" % nome)
            continue
        # Conversas, não arquivos: no Claude, só o <uuid>.jsonl da pasta do projeto (subagentes à parte).
        n = sum(1 for k, _, t in p.unidades() if t != "inteiro" and (nome != "claude" or k.count("/") == 1))
        print("%s\t%d\t%s" % (nome, n, p.base))


def main(a):
    if not a:
        print(__doc__.strip())
        return 2
    c = a[0]
    if c == "inventario":
        cmd_inventario()
    elif c == "pedir" and len(a) >= 2:
        cmd_pedir(a[1], "--enviar" in a[2:])
    elif c == "empacotar":
        cmd_empacotar()
    elif c == "aplicar":
        try:
            cmd_aplicar()
        except (tarfile.TarError, EOFError, OSError) as e:  # pacote vazio ou cortado (ssh caiu): nada gravado pela metade
            print("pacote ilegível: %s" % e, file=sys.stderr)
            return 1
    elif c == "estado":
        cmd_estado()
    else:
        print("uso: sessoes-ia.py inventario|pedir ARQ [--enviar]|empacotar|aplicar|estado", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
