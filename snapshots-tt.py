#!/usr/bin/env python3
"""snapshots-tt.py — histórico de snapshots do estado do tt desta máquina (no máximo 50, só stdlib).

Um snapshot guarda: as sessões do tmux na ordem, as janelas (nome, ordem, layout), os painéis (pasta, programa), o agente de
IA de cada painel (provedor, código da conversa, conta) e as fixadas na ordem. Quem coleta os dados é o `tt`
(snapshot_capturar); aqui só se grava, lista, mostra e devolve os dados para restaurar.

  gravar MOTIVO [--forcar]   lê os dados (abaixo) no stdin; grava se o estado mudou desde o último (ou com --forcar)
  listar [--tsv]             "ID<TAB>quando<TAB>motivo<TAB>sessões<TAB>painéis<TAB>agentes<TAB>fixadas", do mais novo ao mais velho
  ver ID                     o snapshot em árvore, legível
  dados ID                   o snapshot de volta nesse formato (o que o `tt` lê para restaurar)
  existe ID                  sai 0 se o snapshot existe

Dados (uma linha por item; campos separados por 0x1F, que não é espaço: campo vazio não desloca as colunas no `read` do bash):
  M  maquina  foco(sessão em uso)
  S  ordem  sessao  id(o @tt_session_id: o código estável que fixadas e cliques usam; vazio se a sessão ainda não tem)
  W  sessao  indice  nome  layout  ativa(0|1)
  P  sessao  janela  painel  pasta  programa  provedor  codigo  conta  ativo(0|1)
  F  maquina  sessao  chave                         (fixadas, na ordem)

A pasta é $TT_SNAP_DIR ou ~/.local/state/tt/snapshots; o teto, $TT_SNAP_MAX (50).
"""
import hashlib
import json
import os
import sys
import time

DIR = os.environ.get("TT_SNAP_DIR") or os.path.expanduser("~/.local/state/tt/snapshots")
MAXIMO = int(os.environ.get("TT_SNAP_MAX", "50"))


def parse(texto):
    snap = {"maquina": "", "foco": "", "sessoes": [], "fixadas": []}
    por_s = {}
    por_w = {}
    for linha in texto.split("\n"):
        if not linha.strip():
            continue
        c = linha.split("\x1f")
        t = c[0]
        c += [""] * 12
        if t == "M":
            snap["maquina"], snap["foco"] = c[1], c[2]
        elif t == "S":
            s = {"nome": c[2], "ordem": int(c[1] or 0), "id": c[3], "janelas": []}
            por_s[c[2]] = s
            snap["sessoes"].append(s)
        elif t == "W" and c[1] in por_s:
            w = {"indice": int(c[2] or 0), "nome": c[3], "layout": c[4], "ativa": c[5] == "1", "paineis": []}
            por_w[(c[1], w["indice"])] = w
            por_s[c[1]]["janelas"].append(w)
        elif t == "P" and (c[1], int(c[2] or 0)) in por_w:
            por_w[(c[1], int(c[2] or 0))]["paineis"].append({
                "indice": int(c[3] or 0), "pasta": c[4], "programa": c[5], "provedor": c[6], "codigo": c[7], "conta": c[8],
                "ativo": c[9] == "1"})
        elif t == "F":
            snap["fixadas"].append({"maquina": c[1], "sessao": c[2], "chave": c[3]})
    return snap


def assinatura(snap):
    base = {k: snap[k] for k in ("maquina", "sessoes", "fixadas")}
    return hashlib.sha1(json.dumps(base, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def arquivos():
    if not os.path.isdir(DIR):
        return []
    return sorted((f for f in os.listdir(DIR) if f.endswith(".json")), reverse=True)


def carregar(i):
    for f in arquivos():
        if f[:-5] == i or f.startswith(i):
            with open(os.path.join(DIR, f), encoding="utf-8") as fh:
                return f[:-5], json.load(fh)
    return None, None


def contagens(s):
    paineis = [p for ss in s["sessoes"] for w in ss["janelas"] for p in w["paineis"]]
    return len(s["sessoes"]), len(paineis), sum(1 for p in paineis if p.get("codigo")), len(s["fixadas"])


def cmd_gravar(motivo, forcar):
    snap = parse(sys.stdin.read())
    if not snap["sessoes"] and not forcar:
        print("sem sessões: nada a gravar")
        return 0
    snap["assinatura"] = assinatura(snap)
    ar = arquivos()
    if ar and not forcar:
        with open(os.path.join(DIR, ar[0]), encoding="utf-8") as fh:
            if json.load(fh).get("assinatura") == snap["assinatura"]:
                print("igual ao último: não gravou")
                return 0
    os.makedirs(DIR, exist_ok=True)
    agora = time.time()
    snap["quando"] = agora
    snap["quando_texto"] = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(agora))
    snap["motivo"] = motivo
    i = "%d" % (time.time_ns())
    tmp = os.path.join(DIR, i + ".tmp")
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(snap, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, os.path.join(DIR, i + ".json"))
    for velho in arquivos()[MAXIMO:]:
        os.remove(os.path.join(DIR, velho))
    print(i)
    return 0


def cmd_listar(tsv):
    for f in arquivos():
        try:
            with open(os.path.join(DIR, f), encoding="utf-8") as fh:
                s = json.load(fh)
        except (OSError, ValueError):
            continue
        ns, npn, na, nf = contagens(s)
        print("\t".join([f[:-5], s.get("quando_texto", "?"), s.get("motivo", ""), str(ns), str(npn), str(na), str(nf)]))
    return 0


def cmd_ver(i):
    i, s = carregar(i)
    if not s:
        print("snapshot não encontrado", file=sys.stderr)
        return 1
    ns, npn, na, nf = contagens(s)
    print("📸 %s · %s" % (s.get("quando_texto", "?"), s.get("motivo", "")))
    print("   %s · %d sessão(ões) · %d painel(éis) · %d agente(s) de IA · %d fixada(s)\n" % (s.get("maquina", ""), ns, npn, na, nf))
    for ss in s["sessoes"]:
        foco = "  ◀ em uso" if ss["nome"] == s.get("foco") else ""
        print("▸ %s%s" % (ss["nome"], foco))
        for w in ss["janelas"]:
            print("   %s%d %s" % ("*" if w["ativa"] else " ", w["indice"], w["nome"]))
            for p in w["paineis"]:
                ia = ""
                if p.get("codigo"):
                    ia = "  🤖 %s %s%s" % (p["provedor"], p["codigo"][:8], (" · conta " + p["conta"]) if p.get("conta") else "")
                print("        %s %s%s%s" % ("▪" if p["ativo"] else "·", p["pasta"] or "?", "  [%s]" % p["programa"] if p["programa"] else "", ia))
    if s["fixadas"]:
        print("\n📌 fixadas, na ordem:")
        for n, f in enumerate(s["fixadas"], 1):
            print("   %d. %s:%s" % (n, f["maquina"], f["sessao"]))
    return 0


def cmd_dados(i):
    i, s = carregar(i)
    if not s:
        return 1
    out = ["M\x1f%s\x1f%s" % (s.get("maquina", ""), s.get("foco", ""))]
    for ss in s["sessoes"]:
        out.append("S\x1f%d\x1f%s\x1f%s" % (ss["ordem"], ss["nome"], ss.get("id", "")))
        for w in ss["janelas"]:
            out.append("W\x1f%s\x1f%d\x1f%s\x1f%s\x1f%d" % (ss["nome"], w["indice"], w["nome"], w["layout"], 1 if w["ativa"] else 0))
            for p in w["paineis"]:
                out.append("P\x1f%s\x1f%d\x1f%d\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%d" % (
                    ss["nome"], w["indice"], p["indice"], p["pasta"], p["programa"], p.get("provedor", ""), p.get("codigo", ""),
                    p.get("conta", ""), 1 if p["ativo"] else 0))
    for f in s["fixadas"]:
        out.append("F\x1f%s\x1f%s\x1f%s" % (f["maquina"], f["sessao"], f["chave"]))
    print("\n".join(out))
    return 0


def main(a):
    if not a:
        print(__doc__.strip())
        return 2
    if a[0] == "gravar" and len(a) >= 2:
        return cmd_gravar(a[1], "--forcar" in a[2:])
    if a[0] == "listar":
        return cmd_listar("--tsv" in a[1:])
    if a[0] == "ver" and len(a) == 2:
        return cmd_ver(a[1])
    if a[0] == "dados" and len(a) == 2:
        return cmd_dados(a[1])
    if a[0] == "existe" and len(a) == 2:
        return 0 if carregar(a[1])[1] else 1
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
