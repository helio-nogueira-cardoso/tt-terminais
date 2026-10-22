#!/usr/bin/env python3
"""Comparação em três vias das propostas de atualização de tarefas recebidas por e-mail.

Uma proposta é uma linha PENDENTE com meta upd=CÓDIGO (mais as filhas pendentes dela). Este módulo compara
três versões da mesma tarefa:
  atual   o que está no arquivo de tarefas agora;
  entrada o que o e-mail trouxe;
  base    a última versão que os dois lados viram (meta base= da tarefa, gravada ao enviar e ao aplicar).
Cada campo e cada subtarefa vira um ITEM com status:
  igual     nada a fazer;
  minha     só o lado de cá mexeu (entrada igual à base): mantém;
  entrada   só o e-mail mexeu (atual igual à base): entra sozinho;
  conflito  os dois mexeram de formas diferentes (ou não há base e eles diferem): alguém decide.
Escolhas: inc (aceitar recebida), cur (manter minha), ambas (etiquetas: união; descrição: as duas), manual:TEXTO.

Comandos (ARQ = arquivo de tarefas; nada é gravado: as linhas novas saem em stdout para o tt gravar de uma vez):
  plano    ARQ PROP            itens em TSV (um por linha) para a tela de revisão
  texto    ARQ PROP [--cor]    o mesmo, legível, para o terminal
  estado   ARQ PROP            "igual|limpo|conflito<TAB>mudanças<TAB>conflitos"
  aplicar  ARQ PROP --agora N [--decisoes ARQ|-] [--padrao inc|cur]
                               linhas TSV novas (tarefa, subtarefas, base); sai 3 se sobrar conflito sem decisão
  base     ARQ ID --agora N    linha da tarefa com base= igual ao estado de agora (ao enviar por e-mail)
  triagem  ARQ PROP            ids de propostas a descartar (igual ao atual, superada ou substituída)
Valores em TSV: \\ \\n \\t escapados. Nada do conteúdo do e-mail é executado.
"""
import base64
import hashlib
import json
import re
import secrets
import sys
import time

META_ORDEM = ["desc", "prazo", "hora", "prio", "rep", "ant", "antsub", "ciclos", "feito", "tags", "pai", "ord", "arq", "de", "upd", "scod", "sest",
              "colide", "iest", "rem", "v2", "v3", "base"]
CAMPOS = [("texto", "Título"), ("prazo", "Prazo"), ("prio", "Prioridade"), ("rep", "Repetição"),
          ("tags", "Etiquetas"), ("desc", "Descrição"), ("estado", "Situação")]
ROTULO = dict(CAMPOS)
HEX = re.compile(r"^[0-9a-f]{6,}$")
SUB_CAMPOS = ("desc", "prazo", "hora", "prio", "rep", "tags")


def tags_publicas(tags):
    return ",".join(dict.fromkeys(t for t in (tags or "").split(",") if t and not t.startswith("_")))


def tags_com_locais(publicas, *locais):
    return ",".join(dict.fromkeys([t for t in tags_publicas(publicas).split(",") if t] +
                                  [t for tags in locais for t in (tags or "").split(",") if t.startswith("_")]))


def desc_publica(texto):
    """O diário local nunca viaja, nem na extensão estruturada."""
    saida, log = [], False
    for linha in texto.splitlines():
        if linha.startswith("⟡ "):
            log = True
        if log and not linha:
            log = False
            continue
        if not log:
            saida.append(linha)
    return "\n".join(saida).strip()


def sub_atributos(meta):
    return {k: b64d(meta.get(k, "")) if k == "desc" else tags_publicas(meta.get(k, "")) if k == "tags" else meta.get(k, "") for k in SUB_CAMPOS}


def desc_com_diario(nova, anterior):
    logs = re.findall(r"(?ms)^⟡ .*?(?=\n\n|\Z)", anterior or "")
    return "\n\n".join(p for p in [nova or "", *logs] if p)


# ---------------------------------------------------------------------------------------------- arquivo
def meta_ler(m):
    d = {}
    for par in (m or "").split("|"):
        if "=" in par:
            k, v = par.split("=", 1)
            d[k] = v
    return d


def meta_fmt(d):
    chaves = [k for k in META_ORDEM if d.get(k)] + sorted(k for k in d if k not in META_ORDEM and d.get(k))
    return "|".join(f"{k}={d[k]}" for k in chaves)


def b64e(t):
    return base64.b64encode(t.encode("utf-8")).decode("ascii")


def b64d(t):
    try:
        return base64.b64decode(t.encode("ascii"), validate=False).decode("utf-8", "replace")
    except Exception:
        return ""


def ler(arq):
    linhas = {}
    try:
        with open(arq, encoding="utf-8") as f:
            for ln in f:
                p = ln.rstrip("\n").split("\t")
                if len(p) < 5 or not HEX.match(p[0]):
                    continue
                while len(p) < 6:
                    p.append("")
                linhas[p[0]] = p
    except FileNotFoundError:
        pass
    return linhas


def filhas(linhas, pai, estados=("aberta", "feita")):
    r = []
    for L in linhas.values():
        m = meta_ler(L[5])
        if m.get("pai") == pai and L[1] in estados:
            try:
                o = int(m.get("ord", "0") or 0)
            except ValueError:
                o = 0
            try:
                c = int(L[2])
            except ValueError:
                c = 0
            r.append((o, c, L[0], L, m))
    r.sort(key=lambda x: (x[0], x[1], x[2]))
    return r


# ---------------------------------------------------------------------------------------------- fichas
def ficha_atual(linhas, tid):
    L = linhas[tid]
    m = meta_ler(L[5])
    arq = m.get("arq", "")
    est = L[1]
    if est == "arquivada":
        est = "aberta" if arq.endswith(":a") else "feita"
    f = {"texto": L[4], "prazo": m.get("prazo", ""), "hora": m.get("hora", ""), "prio": m.get("prio", ""),
         "rep": m.get("rep", ""), "tags": tags_publicas(m.get("tags", "")), "desc": b64d(m.get("desc", "")),
         "estado": est, "arquivada": L[1] == "arquivada", "subs": {}}
    for _o, _c, sid, SL, _sm in filhas(linhas, tid, ("aberta", "feita", "arquivada")):
        e = SL[1]
        if e == "arquivada":
            e = "aberta" if meta_ler(SL[5]).get("arq", "").endswith(":a") else "feita"
        f["subs"][sid] = {"texto": SL[4], "estado": "f" if e == "feita" else "a", **sub_atributos(_sm)}
    return f


def ficha_entrada(linhas, pid):
    L = linhas[pid]
    m = meta_ler(L[5])
    f = {"texto": L[4], "prazo": m.get("prazo", ""), "hora": m.get("hora", ""), "prio": m.get("prio", ""),
         "rep": m.get("rep", ""), "tags": tags_publicas(m.get("tags", "")),
         "desc": b64d(m.get("desc", "")) if m.get("desc") or m.get("v3") else None,
         "estado": {"f": "feita", "a": "aberta"}.get(m.get("iest", "")), "subs": {}, "sem_codigo": [],
         "rem": {c for c in m.get("rem", "").split(",") if c}, "v2": m.get("v2") == "1", "de": m.get("de", "")}
    for _o, _c, sid, SL, sm in filhas(linhas, pid, ("pendente",)):
        cod = sm.get("scod", "")
        e = {"f": "f", "a": "a"}.get(sm.get("sest", ""))
        item = {"texto": SL[4], "estado": e, "colide": sm.get("colide", ""), "pid": sid}
        if sm.get("v3") == "1":
            item.update(sub_atributos(sm))
        if cod and HEX.match(cod):
            f["subs"][cod] = item
        else:
            f["sem_codigo"].append(item)
    return f


def h12(t):
    return hashlib.sha256((t or "").encode("utf-8")).hexdigest()[:12]


def snapshot(f):
    return {"t": f["texto"], "prazo": f["prazo"], "hora": f["hora"], "prio": f["prio"], "rep": f["rep"],
            "tags": tags_publicas(f["tags"]), "d": h12(desc_publica(f["desc"] or "")), "e": f["estado"],
            "s": {c: [s["texto"], s["estado"], {k: h12(desc_publica(s.get(k, ""))) if k == "desc" else tags_publicas(s.get(k, "")) if k == "tags" else s.get(k, "")
                                               for k in SUB_CAMPOS}] for c, s in f["subs"].items()}}


def cmd_email(arq, tid, frase):
    linhas = ler(arq)
    if tid not in linhas or linhas[tid][1] not in ("aberta", "feita") or meta_ler(linhas[tid][5]).get("pai"):
        print("tarefa indisponível para envio (use uma tarefa principal aberta ou concluída)", file=sys.stderr)
        return 2
    ficha = ficha_atual(linhas, tid)
    if len(ficha["subs"]) > 1000:
        print("tarefa excede o limite de 1000 subtarefas por e-mail", file=sys.stderr)
        return 2
    ficha["desc"] = desc_publica(ficha["desc"])
    partes = [re.sub(r"(?m)^(\s*)[-*•]\s", r"\1– ", ficha["desc"])] if ficha["desc"] else []
    for cod, sub in ficha["subs"].items():
        sub["desc"] = desc_publica(sub["desc"])
        partes.append(f"- [{cod}] [{'x' if sub['estado'] == 'f' else ' '}] {sub['texto']}")
        for campo in ("prazo", "prio", "rep", "tags"):
            if sub[campo]:
                partes.append(f"  {ROTULO[campo]}: {mostra(campo, comp_prazo(sub) if campo == 'prazo' else sub[campo])}")
        if sub["desc"]:
            partes.extend("  │ " + ln for ln in sub["desc"].splitlines())
    humano = "\n".join(partes)
    removidas = [L[0] for L in linhas.values() if L[1] == "removida" and meta_ler(L[5]).get("pai") == tid]
    if len(removidas) > 1000:
        print("tarefa excede o limite de 1000 remoções por e-mail", file=sys.stderr)
        return 2
    frase = " ".join(t for t in frase.split() if not t.startswith("#_"))
    assunto = "[tt] " + frase + " ~" + tid
    pacote = {"id": tid, "assunto": assunto, "tarefa": {k: ficha[k] for k in ("texto", "prazo", "hora", "prio", "rep", "tags")},
              "desc": ficha["desc"], "subs": ficha["subs"], "removidas": removidas,
              "sha256": hashlib.sha256(humano.rstrip().encode()).hexdigest()}
    rodape = "tt:2 estado=" + ficha["estado"] + (" removidas=" + ",".join(removidas) if removidas else "")
    corpo = humano + "\n\n-- \n" + rodape + "\ntt:3 " + b64e(json.dumps(pacote, ensure_ascii=False, separators=(",", ":"))) + "\n"
    if len(corpo.encode()) > 1_000_000:
        print("tarefa excede o limite de 1 MB para compartilhamento por e-mail", file=sys.stderr)
        return 2
    print("\t".join((b64e(assunto), b64e(corpo), base_fmt(snapshot(ficha)))))
    return 0


def base_ler(linhas, tid):
    b = meta_ler(linhas[tid][5]).get("base", "")
    if not b:
        return None
    try:
        base = json.loads(b64d(b))
        base["tags"] = tags_publicas(base.get("tags", ""))
        for sub in base.get("s", {}).values():
            if len(sub) > 2 and isinstance(sub[2], dict):
                sub[2]["tags"] = tags_publicas(sub[2].get("tags", ""))
        return base
    except Exception:
        return None


def base_fmt(snap):
    return b64e(json.dumps(snap, sort_keys=True, separators=(",", ":"), ensure_ascii=False))


# ---------------------------------------------------------------------------------------------- valores
def comp_prazo(f):
    return f"{f['prazo']}|{f['hora']}" if f["prazo"] else ""


def mostra(campo, v):
    """Valor legível de um campo composto."""
    if v is None:
        return "(não informado)"
    if campo == "prazo":
        if not v:
            return "(sem prazo)"
        ep, _, hora = v.partition("|")
        try:
            t = time.localtime(int(ep))
            return time.strftime("%d/%m/%Y", t) + (time.strftime(" %H:%M", t) if hora else "")
        except Exception:
            return v
    if campo == "prio":
        return {"1": "alta", "2": "média"}.get(v, "(normal)")
    if campo == "rep":
        return {"d": "diária", "w": "semanal", "m": "mensal"}.get(v, "(não repete)")
    if campo == "tags":
        return " ".join("#" + t for t in v.split(",") if t) or "(sem etiquetas)"
    if campo == "estado":
        return {"feita": "concluída", "aberta": "aberta"}.get(v, v)
    if campo == "desc":
        return v if v else "(sem descrição)"
    return v if v != "" else "(vazio)"


# ---------------------------------------------------------------------------------------------- comparação
def classificar(cur, inc, base, vazio_apaga=True):
    """status de um valor escalar; None em inc = não informado."""
    if inc is None or inc == cur:
        return "igual"
    if base is not None:
        if inc == base:
            return "minha"
        if cur == base:
            return "entrada"
        return "conflito"
    # sem base: onde não há o que perder, entra; senão, alguém decide
    if cur in ("", None):
        return "entrada"
    return "conflito"


def itens(linhas, pid):
    """Lista de itens da proposta PID contra a tarefa alvo. Cada item é um dict."""
    P = linhas[pid]
    alvo = meta_ler(P[5]).get("upd", "")
    if not alvo or alvo not in linhas:
        return None, None, []
    cur = ficha_atual(linhas, alvo)
    inc = ficha_entrada(linhas, pid)
    base = base_ler(linhas, alvo)
    its = []

    def add(iid, grupo, rotulo, campo, status, vcur, vinc, vbase, opcoes):
        its.append({"id": iid, "grupo": grupo, "rotulo": rotulo, "campo": campo, "status": status,
                    "cur": vcur, "inc": vinc, "base": vbase, "opcoes": opcoes,
                    "padrao": "inc" if status == "entrada" else ("cur" if status == "minha" else "")})

    for campo, rot in CAMPOS:
        if campo == "estado" and (cur["arquivada"] or inc["estado"] is None):
            continue
        if campo == "prazo":
            vc, vi = comp_prazo(cur), comp_prazo(inc)
            vb = None if base is None else (f"{base['prazo']}|{base['hora']}" if base["prazo"] else "")
        elif campo == "desc":
            vc, vi = desc_publica(cur["desc"]), inc["desc"]
            vb = None
        elif campo == "estado":
            vc, vi = cur["estado"], inc["estado"]
            vb = None if base is None else base.get("e")
        else:
            vc, vi = cur[campo], inc[campo]
            vb = None if base is None else base.get({"texto": "t"}.get(campo, campo), "")
        if campo == "desc":
            hb = None if base is None else base.get("d")
            if inc["desc"] is None or h12(vi) == h12(vc):
                st = "igual"
            elif hb is not None and h12(vi) == hb:
                st = "minha"
            elif hb is not None and h12(vc) == hb:
                st = "entrada"
            elif hb is None and not vc:
                st = "entrada"
            else:
                st = "conflito"
        else:
            st = classificar(vc, vi, vb)
        if st == "igual":
            continue
        opc = ["inc", "cur"] + (["ambas"] if campo in ("tags", "desc") else []) + (["manual"] if campo in ("texto", "tags", "desc") else [])
        add(f"campo:{campo}", "campo", rot, campo, st, vc, vi, vb, opc)

    # subtarefas por código
    vistos = set()
    for cod, s in inc["subs"].items():
        vistos.add(cod)
        c = cur["subs"].get(cod)
        b = None if base is None else base.get("s", {}).get(cod)
        rot = f"Subtarefa «{(c or s)['texto']}»"
        if c is None:
            LC = linhas.get(cod)
            ja_removida = LC is not None and LC[1] == "removida" and meta_ler(LC[5]).get("pai") == alvo
            outra = LC is not None and LC[1] != "removida" and meta_ler(LC[5]).get("pai") != alvo
            if outra or (LC is not None and LC[1] not in ("removida",) and meta_ler(LC[5]).get("pai") != alvo):
                # o código é de outra coisa: entra como subtarefa nova, sem o código (a menos que o texto já exista)
                if any(x["texto"].lower() == s["texto"].lower() for x in cur["subs"].values()):
                    continue
                add(f"sub:{cod}:novo", "sub", rot, "novo", "entrada", None, s["texto"] + ("  ☑" if s["estado"] == "f" else ""),
                    None, ["inc", "cur"])
                continue
            if ja_removida or (b is not None):
                # eu a removi (lápide ou presente na base): só volta se eles a mudaram
                mudou = b is not None and (s["texto"] != b[0] or (s["estado"] is not None and s["estado"] != b[1]))
                if not mudou:
                    continue
                add(f"sub:{cod}:novo", "sub", f"Subtarefa «{s['texto']}» (você a removeu)", "novo", "conflito", None,
                    s["texto"] + ("  ☑" if s["estado"] == "f" else ""), None, ["inc", "cur"])
                its[-1]["padrao"] = ""
                continue
            add(f"sub:{cod}:novo", "sub", f"Nova subtarefa «{s['texto']}»", "novo", "entrada", None,
                s["texto"] + ("  ☑" if s["estado"] == "f" else ""), None, ["inc", "cur"])
            continue
        # existe dos dois lados
        bt = None if b is None else b[0]
        be = None if b is None else b[1]
        st = classificar(c["texto"], s["texto"], bt)
        if st != "igual":
            add(f"sub:{cod}:texto", "sub", rot + " — texto", "texto", st, c["texto"], s["texto"], bt,
                ["inc", "cur", "manual"])
        if s["estado"] is not None and s["estado"] != c["estado"]:
            # concluir pelo e-mail (legado sem base) é baixo risco: entra; reabrir/mudar com base segue a regra geral
            st2 = classificar(c["estado"], s["estado"], be)
            if b is None and s["estado"] == "f" and c["estado"] == "a":
                st2 = "entrada"
            nome = {"f": "concluída", "a": "aberta"}
            add(f"sub:{cod}:estado", "sub", rot + " — situação", "estado", st2, nome[c["estado"]], nome[s["estado"]],
                None if be is None else nome[be], ["inc", "cur"])
        # v3: cada atributo da subtarefa participa da mesma revisão em três vias.
        for campo in ("desc", "prazo", "prio", "rep", "tags"):
            if campo not in s:
                continue  # e-mail legado não apaga atributos que não transportava
            vc, vi = c.get(campo, ""), s[campo]
            extras = b[2] if b is not None and len(b) > 2 else {}
            vb = extras.get(campo)
            if campo == "prazo":
                vc, vi = comp_prazo(c), comp_prazo(s)
                vb = (extras["prazo"] + "|" + extras.get("hora", "") if extras["prazo"] else "") if "prazo" in extras else None
            if campo == "desc":
                vc = desc_publica(vc)
                st3 = classificar(h12(vc) if vc else "", h12(vi) if vi else "", vb if vb != h12("") else "")
            else:
                st3 = classificar(vc, vi, vb)
            if st3 != "igual":
                opc = ["inc", "cur"] + (["ambas", "manual"] if campo in ("desc", "tags") else [])
                add(f"sub:{cod}:{campo}", "sub", rot + " — " + ROTULO[campo].lower(), campo, st3, vc, vi, None, opc)
    # remoções explícitas (v2)
    for cod in sorted(inc["rem"]):
        c = cur["subs"].get(cod)
        if c is None or cod in inc["subs"]:
            continue
        b = None if base is None else base.get("s", {}).get(cod)
        igual_meta = b is not None and len(b) > 2 and all(
            b[2].get(k, "") == (h12(desc_publica(c.get(k, ""))) if k == "desc" else c.get(k, "")) for k in SUB_CAMPOS)
        st = "entrada" if (b is not None and b[0] == c["texto"] and b[1] == c["estado"] and (len(b) < 3 or igual_meta)) else "conflito"
        add(f"sub:{cod}:remover", "sub", f"Subtarefa «{c['texto']}»", "remover", st, c["texto"], "(removida na origem)", None,
            ["inc", "cur"])
    # sem código: casa pelo texto
    for s in inc["sem_codigo"]:
        if any(x["texto"].lower() == s["texto"].lower() for x in cur["subs"].values()):
            continue
        add(f"sub:~{h12(s['texto'].lower())}:novo", "sub", f"Nova subtarefa «{s['texto']}»", "novo", "entrada", None,
            s["texto"] + ("  ☑" if s["estado"] == "f" else ""), None, ["inc", "cur"])
    return alvo, (cur, inc, base), its


# ---------------------------------------------------------------------------------------------- saída
def esc(t):
    return str(t if t is not None else "").replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t")


def unesc(t):
    out, i = [], 0
    while i < len(t):
        if t[i] == "\\" and i + 1 < len(t):
            out.append({"n": "\n", "t": "\t", "\\": "\\"}.get(t[i + 1], t[i + 1]))
            i += 2
        else:
            out.append(t[i])
            i += 1
    return "".join(out)


def cmd_plano(arq, pid):
    linhas = ler(arq)
    alvo, _f, its = itens(linhas, pid)
    if alvo is None:
        print("proposta inválida", file=sys.stderr)
        return 1
    print("\t".join(["#", "alvo", alvo, esc(linhas[alvo][4]), esc(linhas[pid][5] and meta_ler(linhas[pid][5]).get("de", ""))]))
    for it in its:
        mv = lambda v: esc(mostra(it["campo"], v) if it["grupo"] == "campo" or it["campo"] in SUB_CAMPOS else (v if v is not None else ""))
        print("\t".join([it["id"], it["grupo"], esc(it["rotulo"]), it["status"], mv(it["cur"]), mv(it["inc"]),
                         mv(it["base"]) if it["base"] is not None else "", it["padrao"], ",".join(it["opcoes"])]))
    return 0


def cmd_texto(arq, pid, cor):
    linhas = ler(arq)
    alvo, _f, its = itens(linhas, pid)
    if alvo is None:
        print("proposta inválida", file=sys.stderr)
        return 1
    c = (lambda k, t: f"\x1b[{k}m{t}\x1b[0m") if cor else (lambda k, t: t)
    de = meta_ler(linhas[pid][5]).get("de", "?")
    print(c("1", f"Atualização de {de} para «{linhas[alvo][4]}»"))
    if not its:
        print("  sem diferenças em relação à sua tarefa.")
        return 0
    nome = {"conflito": ("31", "⚡ conflito"), "entrada": ("32", "← entra")}
    plano = lambda t: " ⏎ ".join(str(t).split("\n"))[:300]
    mv = lambda it, v: plano(mostra(it["campo"], v) if it["grupo"] == "campo" or it["campo"] in SUB_CAMPOS else (v if v is not None else ""))
    minhas = []
    for it in its:
        if it["status"] == "minha":
            minhas.append(it["rotulo"])
            continue
        k, rot = nome[it["status"]]
        print(f"  {c(k, rot):<22} {c('1', it['rotulo'])}")
        if it["cur"] is not None or it["grupo"] == "campo":
            print(f"      minha    │ {mv(it, it['cur'])}")
        print(f"      recebida │ {mv(it, it['inc'])}")
        if it["base"] is not None:
            print(c("2", f"      original │ {mv(it, it['base'])}"))
    if minhas:
        print(c("2", "  = suas mudanças mantidas (a origem não mexeu): " + ", ".join(minhas)))
    return 0


def contagem(its):
    return sum(1 for i in its if i["status"] in ("entrada", "conflito")), sum(1 for i in its if i["status"] == "conflito")


def cmd_estado(arq, pid):
    linhas = ler(arq)
    alvo, _f, its = itens(linhas, pid)
    if alvo is None:
        print("invalida\t0\t0")
        return 1
    mud, conf = contagem(its)
    print("\t".join(["conflito" if conf else ("limpo" if mud else "igual"), str(mud), str(conf)]))
    return 0


def novo_codigo(linhas, usados):
    while True:
        c = secrets.token_hex(6)
        if c not in linhas and c not in usados:
            usados.add(c)
            return c


def cmd_aplicar(arq, pid, agora, decisoes, padrao):
    linhas = ler(arq)
    alvo, fichas, its = itens(linhas, pid)
    if alvo is None:
        print("proposta inválida", file=sys.stderr)
        return 1
    cur, inc, base = fichas
    dec = {}
    for ln in (decisoes or "").splitlines():
        p = ln.split("\t")
        if len(p) >= 2:
            dec[p[0]] = (p[1], unesc(p[2]) if len(p) > 2 else "")
    esc_item = {}
    pend = []
    for it in its:
        if it["id"] in dec:
            esc_item[it["id"]] = dec[it["id"]]
        elif it["status"] == "conflito":
            if padrao in ("inc", "cur"):
                esc_item[it["id"]] = (padrao, "")
            else:
                pend.append(it["id"])
        else:
            esc_item[it["id"]] = (it["padrao"], "")
    if pend:
        print("conflitos sem decisão: " + " ".join(pend), file=sys.stderr)
        return 3
    for it in its:
        escolha, manual = esc_item[it["id"]]
        if escolha == "manual" and it["campo"] == "tags" and any(
                t.startswith("_") for t in re.split(r"[,\s#]+", manual) if t):
            print("etiquetas #_ são reservadas à origem de recebimento", file=sys.stderr)
            return 2

    saida = {}  # id -> linha (lista)

    def tocar(lid):
        if lid not in saida:
            saida[lid] = list(linhas[lid])
        return saida[lid]

    def mudada(L):
        try:
            antigo = int(L[3])
        except ValueError:
            antigo = 0
        L[3] = str(max(agora, antigo + 1))

    M = tocar(alvo)
    mm = meta_ler(M[5])
    it_por = {i["id"]: i for i in its}

    def valor(iid):
        it = it_por[iid]
        ch, manual = esc_item[iid]
        if ch == "inc":
            return it["inc"]
        if ch == "cur":
            return it["cur"]
        if ch == "ambas":
            if it["campo"] == "tags":
                return ",".join(dict.fromkeys([t for t in (it["cur"] or "").split(",") + (it["inc"] or "").split(",") if t]))
            if it["campo"] == "desc":
                a, b = (it["cur"] or "").strip(), (it["inc"] or "").strip()
                return a if a == b or not b else (b if not a else a + "\n\n──── recebida ────\n\n" + b)
        if ch == "manual":
            if it["campo"] == "tags":      # "a, #b c" → a,b,c
                ts = [t.lower() for t in re.split(r"[,\s#]+", manual) if t]
                return ",".join(dict.fromkeys(ts))
            return manual
        return it["cur"]

    for campo, _rot in CAMPOS:
        iid = f"campo:{campo}"
        if iid not in it_por:
            continue
        v = valor(iid)
        if campo == "texto":
            M[4] = " ".join((v or "").split()) or M[4]
        elif campo == "prazo":
            ep, _, hora = (v or "").partition("|")
            mm["prazo"], mm["hora"] = ep, ("1" if (ep and hora) else "")
            if not ep:
                mm["prazo"] = ""
        elif campo == "desc":
            v = desc_com_diario(v, b64d(mm.get("desc", "")))
            mm["desc"] = b64e(v) if v else ""
        elif campo == "estado":
            if M[1] != "arquivada":
                M[1] = v if v in ("aberta", "feita") else M[1]
        elif campo == "tags":
            mm[campo] = tags_com_locais(v, mm.get("tags", ""))
        else:
            mm[campo] = v or ""

    # A etiqueta de quem enviou é local, não participa do conflito de etiquetas públicas.
    mm["tags"] = tags_com_locais(mm.get("tags", ""), mm.get("tags", ""),
                                 meta_ler(linhas[pid][5]).get("tags", ""))
    usados = set()
    ord_prox = max([o for o, *_ in filhas(linhas, alvo, ("aberta", "feita", "arquivada", "removida"))] + [0]) + 1
    for iid, it in it_por.items():
        if it["grupo"] != "sub":
            continue
        _, cod, tipo = iid.split(":")
        ch, manual = esc_item[iid]
        if tipo == "novo":
            if ch != "inc":
                continue
            if cod.startswith("~") or not HEX.match(cod):
                novo = novo_codigo(linhas, usados)
            elif cod in linhas:
                # só reaproveita o código se era uma subtarefa DESTA tarefa que você removeu e agora aceita de volta;
                # se é de outra coisa, a subtarefa entra com código novo (nunca toma o lugar de uma alheia)
                L0 = linhas[cod]
                novo = cod if (L0[1] == "removida" and meta_ler(L0[5]).get("pai") == alvo) else novo_codigo(linhas, usados)
            else:
                novo = cod
            texto = re.sub(r"\s+☑$", "", it["inc"] or "")
            feita = (it["inc"] or "").endswith("☑")
            sm = {"pai": alvo, "ord": str(ord_prox)}
            for k in SUB_CAMPOS:
                v = inc["subs"].get(cod, {}).get(k, "")
                if v:
                    sm[k] = b64e(v) if k == "desc" else v
            ord_prox += 1
            if novo in linhas:
                L = tocar(novo)
                L[1] = "feita" if feita else "aberta"
                L[4] = texto
                L[5] = meta_fmt(sm)
                mudada(L)
            else:
                saida[novo] = [novo, "feita" if feita else "aberta", str(agora), str(agora), texto, meta_fmt(sm)]
            continue
        if cod not in linhas:
            continue
        L = tocar(cod)
        if tipo == "texto":
            v = {"inc": it["inc"], "cur": it["cur"], "manual": manual}.get(ch, it["cur"])
            L[4] = " ".join((v or "").split()) or L[4]
            mudada(L)
        elif tipo == "estado":
            if ch == "inc":
                L[1] = "feita" if inc["subs"][cod]["estado"] == "f" else "aberta"
                mudada(L)
        elif tipo == "remover":
            if ch == "inc":
                L[1] = "removida"
                mudada(L)
        elif tipo in SUB_CAMPOS:
            sm = meta_ler(L[5])
            v = valor(iid)
            if tipo == "prazo":
                sm["prazo"], _, sm["hora"] = (v or "").partition("|")
            elif tipo == "desc":
                v = desc_com_diario(v, b64d(sm.get("desc", "")))
                sm["desc"] = b64e(v) if v else ""
            elif tipo == "tags":
                sm[tipo] = tags_com_locais(v, sm.get("tags", ""))
            else:
                sm[tipo] = v or ""
            L[5] = meta_fmt(sm)
            mudada(L)
    # regra: mãe concluída com subtarefa aberta volta a ficar aberta
    vivas = {}
    for cod, s in cur["subs"].items():
        vivas[cod] = s["estado"]
    for cod, L in saida.items():
        if cod == alvo:
            continue
        if meta_ler(L[5]).get("pai") == alvo:
            vivas[cod] = "f" if L[1] == "feita" else ("a" if L[1] == "aberta" else None)
    if M[1] == "feita" and any(v == "a" for v in vivas.values()):
        M[1] = "aberta"
    M[5] = meta_fmt(mm)
    # base := o que o remetente tem (a versão que chegou), para a próxima comparação
    snap = snapshot(inc_para_base(inc, cur))
    mm["base"] = base_fmt(snap)
    M[5] = meta_fmt(mm)
    mudada(M)
    for L in saida.values():
        print("\t".join(L))
    return 0


def inc_para_base(inc, cur):
    f = {"texto": inc["texto"], "prazo": inc["prazo"], "hora": inc["hora"], "prio": inc["prio"], "rep": inc["rep"],
         "tags": inc["tags"], "desc": inc["desc"] if inc["desc"] is not None else cur["desc"],
         "estado": inc["estado"] or cur["estado"], "subs": {}}
    for c, s in inc["subs"].items():
        antiga = cur["subs"].get(c) or {}
        f["subs"][c] = {"texto": s["texto"], "estado": s["estado"] or antiga.get("estado", "a"),
                        **{k: s.get(k, antiga.get(k, "")) for k in SUB_CAMPOS}}
    return f


def cmd_base(arq, tid, agora, enviada=""):
    linhas = ler(arq)
    if tid not in linhas:
        return 1
    L = list(linhas[tid])
    mm = meta_ler(L[5])
    mm["base"] = enviada or base_fmt(snapshot(ficha_atual(linhas, tid)))
    L[5] = meta_fmt(mm)
    try:
        antigo = int(L[3])
    except ValueError:
        antigo = 0
    L[3] = str(max(agora, antigo + 1))
    print("\t".join(L))
    return 0


def cmd_triagem(arq, pid):
    """Imprime ids de propostas pendentes a descartar. Regras: sem diferenças em relação à tarefa; superada por uma
    proposta mais nova do mesmo remetente para o mesmo código; ou substitui as mais velhas do mesmo remetente."""
    linhas = ler(arq)
    P = linhas.get(pid)
    if not P:
        return 1
    m = meta_ler(P[5])
    alvo, de = m.get("upd", ""), m.get("de", "")
    try:
        t = int(P[3])
    except ValueError:
        t = 0
    outras = []
    for L in linhas.values():
        mm = meta_ler(L[5])
        if L[1] == "pendente" and mm.get("upd") == alvo and mm.get("de", "") == de and L[0] != pid and not mm.get("pai"):
            try:
                outras.append((int(L[3]), L[0]))
            except ValueError:
                outras.append((0, L[0]))
    if any(o > t for o, _ in outras):
        print(pid)                       # superada: já há uma mais nova do mesmo remetente
        return 0
    for _o, i in outras:
        print(i)                         # esta é a mais nova: as velhas saem
    _a, _f, its = itens(linhas, pid)
    if _a is not None and not [i for i in its if i["status"] in ("entrada", "conflito")]:
        print(pid)                       # nada a rever
    return 0


def cmd_tags_migrar(arq, cadastro, agora):
    """Converte só a etiqueta associada ao remetente comprovado; preserva linhas desconhecidas."""
    remetentes = {}
    with open(cadastro, encoding="utf-8") as f:
        for linha in f:
            p = linha.rstrip("\n").split("\t")
            if len(p) >= 5 and p[2] != "-" and p[1] not in ("", "-"):
                remetentes[p[0].lower()] = p[1].lstrip("_")
    with open(arq, encoding="utf-8") as f:
        for linha in f:
            p = linha.rstrip("\n").split("\t")
            if len(p) != 6:
                sys.stdout.write(linha)
                continue
            m = meta_ler(p[5])
            tag = remetentes.get(m.get("de", "").lower())
            if not tag or tag not in m.get("tags", "").split(","):
                sys.stdout.write(linha)
                continue
            m["tags"] = ",".join(dict.fromkeys("_" + tag if t == tag else t for t in m["tags"].split(",")))
            if m.get("base"):
                try:
                    base = json.loads(b64d(m["base"]))
                    base["tags"] = ",".join(t for t in base.get("tags", "").split(",") if t != tag and not t.startswith("_"))
                    m["base"] = base_fmt(base)
                except (ValueError, TypeError, AttributeError):
                    pass  # base desconhecida não autoriza perda de dados
            p[5] = meta_fmt(m)
            try:
                p[3] = str(max(agora, int(p[3]) + 1))
            except ValueError:
                sys.stdout.write(linha)
                continue
            print("\t".join(p))
    return 0


def main(a):
    if len(a) < 3:
        print(__doc__)
        return 2
    cmd, arq, alvo = a[0], a[1], a[2]
    opc = a[3:]

    def val(nome, padrao=None):
        return opc[opc.index(nome) + 1] if nome in opc and opc.index(nome) + 1 < len(opc) else padrao

    if cmd == "tags-migrar":
        return cmd_tags_migrar(arq, alvo, int(val("--agora", str(int(time.time())))))
    if cmd == "plano":
        return cmd_plano(arq, alvo)
    if cmd == "email":
        return cmd_email(arq, alvo, opc[0])
    if cmd == "texto":
        return cmd_texto(arq, alvo, "--cor" in opc)
    if cmd == "estado":
        return cmd_estado(arq, alvo)
    if cmd == "aplicar":
        dec = val("--decisoes")
        txt = sys.stdin.read() if dec == "-" else (open(dec, encoding="utf-8").read() if dec else "")
        return cmd_aplicar(arq, alvo, int(val("--agora", str(int(time.time())))), txt, val("--padrao"))
    if cmd == "base":
        return cmd_base(arq, alvo, int(val("--agora", str(int(time.time())))), sys.stdin.read() if "--snapshot-stdin" in opc else "")
    if cmd == "triagem":
        return cmd_triagem(arq, alvo)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
