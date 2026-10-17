#!/usr/bin/env python3
"""telas-agentes.py — as telas que os agentes de IA (Claude, Codex, Kiro, …) mostram antes da conversa de verdade, ou
no meio dela, pedindo uma resposta: decide se a voz do tt responde sozinha ou pergunta ao usuário. Só biblioteca padrão.

  telas-agentes.py decidir [--catalogo ARQ]... [--pastas ARQ] [--maquina M] [--casa DIR]... [--cwd DIR] [--agente A]
      lê a tela (texto, as cores tanto faz) no stdin e imprime UMA linha, campos separados por TAB:
        decisao  nada | auto | perguntar
        classe   rotina | pasta | decisao | desconhecida | senha | -
        id       o bloco do catálogo (ou "-")
        acao     "opcao N" | "teclas K ..." | "-"           (o que mandar, quando decisao=auto)
        marcada  a opção que o cursor marca agora (para andar pelas setas), ou 0
        tipo     menu | sn | enter | -                       (o jeito da pergunta)
        pasta    a pasta da pergunta de confiança, ou "-"
        pergunta o texto da pergunta (curto), ou "-"
        opcoes   "1=texto|2=texto" (num [s/n], "s=sim|n=não"), ou "-"
        motivo   por que perguntar (falado), ou "-"
  telas-agentes.py catalogo [--catalogo ARQ]...   o catálogo junto (id, agente, classe), para conferir
  telas-agentes.py validar  [--catalogo ARQ]...   sai 1 (e diz o quê) se algum bloco tem erro
  telas-agentes.py pasta-ok --pastas ARQ [--maquina M] [--casa DIR]... PASTA   sai 0 se a pasta está autorizada

O catálogo é o telas-agentes.conf ao lado deste arquivo, mais ~/.config/tt/telas-agentes.conf (o do usuário);
TT_TELAS_CATALOGO (caminhos separados por ":") troca os dois. A lista de pastas: linhas "[MÁQUINA:]PASTA", com
PASTA/** valendo também as subpastas e * qualquer coisa; # comenta.
"""
import fnmatch
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
CONF = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
CLASSES = ("rotina", "pasta", "decisao")
LINHAS = int(os.environ.get("TT_TELAS_LINHAS") or 25)  # o pedaço da tela onde a pergunta mora

# Trava do código (o catálogo não desliga): uma senha pedida na última linha nunca é respondida sozinha, e a opção
# escolhida sozinha nunca é das que dão permissão para sempre, abrem tudo ou apagam.
SENHA = re.compile(r"(password|passphrase|passcode|senha|\bpin\b|\botp\b|one.time (code|password)|verification code|"
                   r"c[oó]digo de verifica[cç][aã]o|2fa|token)[^:\n]{0,40}:\s*$", re.I)
NUNCA = re.compile(r"don.?t ask again|n[aã]o pergunt|\balways\b|\bsempre\b|all future|todos os futuros|"
                   r"for this session|nesta sess[aã]o|trust all|confiar em tod|allow all|permitir tod|full access|"
                   r"acesso total|\bdelet|\bremov|\bapag|\bexclu|overwrite|sobrescrev|bypass", re.I)
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[()][A-Za-z0-9]")
CURSOR = "❯›▶➜▸"
RE_CURSOR = re.compile(r"^(\s*)([%s]|>(?=\s*\d+[.)]\s))\s*(.*\S)\s*$" % CURSOR)
RE_NUM = re.compile(r"^(\d{1,2})[.)]\s+(.*\S)\s*$")
RE_SN = re.compile(r"[\[(]\s*[yYsS](es|im)?\s*/\s*[nN](o|ão|ao)?(\s*/\s*[a-zA-Z]+)*\s*[\])]\s*[:?]?\s*$")
RE_ENTER = re.compile(r"press enter to continue|pressione enter|press enter to|hit enter to|enter para continuar", re.I)
RE_PATH = re.compile(r"(?:^|\s|in\s|em\s)((?:~|/)[^\s'\"`,;)]*)")
AGENTES = (("claude", re.compile(r"claude", re.I)), ("codex", re.compile(r"codex|openai", re.I)),
           ("kiro", re.compile(r"\bkiro\b", re.I)), ("gemini", re.compile(r"gemini", re.I)))


def ler_catalogo(arqs):
    """Blocos {id, agente, classe, tela, opcao, evitar, tecla, motivo} na ordem; o mesmo id de um arquivo seguinte
    troca o anterior no lugar dele; classe "-" desliga."""
    ordem, blocos, erros = [], {}, []
    for arq in arqs:
        try:
            with open(arq, encoding="utf-8", errors="replace") as f:
                linhas = f.read().splitlines()
        except OSError:
            continue
        atual = None
        for n, l in enumerate(linhas, 1):
            s = l.strip()
            if not s or s.startswith("#"):
                continue
            m = re.match(r"^\[([A-Za-z0-9_.-]+)\]$", s)
            if m:
                atual = {"id": m.group(1), "arquivo": arq}
                if atual["id"] not in blocos:
                    ordem.append(atual["id"])
                blocos[atual["id"]] = atual
                continue
            if atual is None or "=" not in s:
                erros.append("%s:%d: linha fora de um bloco ou sem '='" % (arq, n))
                continue
            k, v = s.split("=", 1)
            atual[k.strip().lower()] = v.strip()
    lista = []
    for i in ordem:
        b = blocos[i]
        c = b.get("classe", "")
        if c == "-":
            continue
        if c not in CLASSES:
            erros.append("[%s]: classe '%s' (rotina, pasta, decisao ou -)" % (i, c))
            continue
        if not b.get("tela"):
            erros.append("[%s]: sem 'tela'" % i)
            continue
        try:
            b["re"] = re.compile(b["tela"], re.I | re.M)
            b["re_op"] = re.compile(b["opcao"], re.I) if b.get("opcao") and b["opcao"] != "@marcada" else None
            b["re_ev"] = re.compile(b["evitar"], re.I) if b.get("evitar") else None
        except re.error as e:
            erros.append("[%s]: expressão inválida (%s)" % (i, e))
            continue
        if c != "decisao" and not (b.get("opcao") or b.get("tecla")):
            erros.append("[%s]: rotina e pasta precisam de 'opcao' ou 'tecla'" % i)
            continue
        b["agente"] = (b.get("agente") or "*").lower()
        lista.append(b)
    return lista, erros


def catalogos(args):
    if args:
        return args
    env = os.environ.get("TT_TELAS_CATALOGO")
    if env:
        return [p for p in env.split(":") if p]
    return [os.path.join(AQUI, "telas-agentes.conf"), os.path.join(CONF, "tt", "telas-agentes.conf")]


def limpar(tela):
    t = ANSI.sub("", tela).replace("\r", "")
    out = []
    for l in t.split("\n"):
        l = re.sub(r"[│┃║╎╏┆┇┊┋]", " ", l).replace(" ", " ").rstrip()
        out.append(l)
    while out and not out[-1].strip():
        out.pop()
    return out


def borda(l):
    s = l.strip()
    return bool(s) and not re.sub(r"[─━═╭╮╰╯┌┐└┘├┤┬┴┼\-_=·•.\s]", "", s)


def achar_menu(linhas):
    """O último menu com cursor: (início, fim, opções [(n, texto)], marcada). Menu de verdade tem o cursor numa
    opção (❯ › ▶ ou "> 1."); uma lista numerada do texto do agente não tem, e fica de fora."""
    for c in range(len(linhas) - 1, -1, -1):
        m = RE_CURSOR.match(linhas[c])
        if not m:
            continue
        col = len(m.group(1)) + len(m.group(2))
        resto = linhas[c][col:]
        col += len(resto) - len(resto.lstrip())  # a coluna do texto da opção
        numerado = bool(RE_NUM.match(m.group(3)))

        def opcao(i):
            l = linhas[i]
            if i == c:
                return m.group(3)
            if not l.strip() or borda(l):
                return None
            ind = len(l) - len(l.lstrip())
            txt = l.strip()
            mm = RE_CURSOR.match(l)
            if mm:
                return None
            if numerado:
                return txt if RE_NUM.match(txt) and abs(ind - col) <= 2 else ("" if ind > col + 1 else None)
            return txt if ind == col else ("" if ind > col else None)

        ini, fim = c, c
        while ini - 1 >= 0 and opcao(ini - 1) is not None:
            ini -= 1
        while fim + 1 < len(linhas) and opcao(fim + 1) is not None:
            fim += 1
        ops, marc = [], 0
        for i in range(ini, fim + 1):
            t = opcao(i)
            if not t:
                continue  # linha de descrição de uma opção (mais à direita)
            mn = RE_NUM.match(t)
            if numerado and mn:
                n, txt = int(mn.group(1)), mn.group(2)
            elif numerado:
                continue
            else:
                n, txt = len(ops) + 1, t
            ops.append((n, re.sub(r"\s+", " ", txt)))
            if i == c:
                marc = n
        if len(ops) >= 2:
            return ini, fim, ops, marc
    return None


def agente_da_tela(linhas):
    texto = "\n".join(linhas)
    for nome, r in AGENTES:
        if r.search(texto):
            return nome
    return ""


def pergunta_de(linhas, ini):
    """A pergunta: a frase com "?" do último parágrafo que tem uma, acima do menu (até 15 linhas); senão a linha que
    termina em ":" (ex.: "Select login method:"); senão o título do diálogo."""
    pars, atual = [], []
    for l in linhas[max(0, ini - 15):ini]:
        if not l.strip() or borda(l):
            if atual:
                pars.append(atual)
            atual = []
        else:
            atual.append(l.strip())
    if atual:
        pars.append(atual)
    for p in reversed(pars):
        for i in range(len(p) - 1, -1, -1):
            if "?" not in p[i]:
                continue
            ini_l = i  # a frase quebrada pela largura continua numa linha que começa em minúscula
            while ini_l > 0 and re.match(r"^[a-zà-ü(\"'«]", p[ini_l]):
                ini_l -= 1
            frase = " ".join(p[ini_l:i + 1])
            frase = frase[:frase.rfind("?") + 1]
            frase = re.split(r"(?<=[.!])\s+", frase)[-1]
            return frase[-220:].strip()
    pars = [" ".join(p) for p in pars]
    for p in reversed(pars):
        if p.endswith(":"):
            return p[-220:]
    return pars[0][:220] if pars else ""


def pasta_de(linhas, cwd):
    for l in linhas:
        s = l.strip()
        if re.match(r"^(~|/)[^\s]*$", s) and not s.startswith("//"):
            return s.rstrip("/.:") or "/"
    for l in linhas:
        for m in RE_PATH.finditer(l):
            p = m.group(1).rstrip(".:,;")
            if p and p != "/" and "://" not in l[max(0, m.start() - 8):m.end()]:
                return p
    return cwd or ""


def ler_pastas(arq):
    ent = []
    try:
        with open(arq, encoding="utf-8", errors="replace") as f:
            for l in f:
                s = l.strip()
                if not s or s.startswith("#"):
                    continue
                m = re.match(r"^([A-Za-z0-9._-]+):((?:~|/).*)$", s)
                ent.append((m.group(1).lower(), m.group(2)) if m else ("", s))
    except OSError:
        pass
    return ent


def _norm(p):
    if p in ("~", "/"):
        return p
    if p.startswith("~/"):
        return "~/" + os.path.normpath(p[2:]).lstrip("/")
    return os.path.normpath(p)


def formas(pasta, casas):
    f = {_norm(pasta)}
    for h in casas:
        h = _norm(h)
        if not h.startswith("/"):
            continue
        for x in list(f):
            if x == h:
                f.add("~")
            elif x.startswith(h.rstrip("/") + "/"):
                f.add("~/" + x[len(h.rstrip("/")) + 1:])
            elif x == "~":
                f.add(h)
            elif x.startswith("~/"):
                f.add(h.rstrip("/") + x[1:])
    return f


def autorizada(pasta, maquina, casas, entradas):
    if not pasta or ".." in pasta.split("/"):
        return False
    fs = formas(pasta, casas)
    for maq, pad in entradas:
        if maq and maq != (maquina or "").lower():
            continue
        pad = pad.rstrip("/") if pad not in ("/", "~") else pad
        for x in fs:
            if pad.endswith("/**"):
                base = _norm(pad[:-3] or "/")
                if x == base or x.startswith(base.rstrip("/") + "/"):
                    return True
            elif "*" in pad or "?" in pad or "[" in pad:
                if fnmatch.fnmatchcase(x, pad):
                    return True
            elif x == _norm(pad):
                return True
    return False


def campo(v):
    v = re.sub(r"[\t\r\n]+", " ", str(v or "")).strip()
    return v or "-"


def saida(decisao, classe="-", ident="-", acao="-", marcada=0, tipo="-", pasta="-", pergunta="-", opcoes="-",
          motivo="-"):
    print("\t".join(campo(x) for x in (decisao, classe, ident, acao, marcada, tipo, pasta, pergunta, opcoes, motivo)))


def decidir(tela, cats, pastas, maquina, casas, cwd, agente):
    blocos, _erros = ler_catalogo(cats)
    linhas = limpar(tela)
    if not linhas:
        return saida("nada")
    menu = achar_menu(linhas[-max(LINHAS, 40):])
    base = len(linhas) - len(linhas[-max(LINHAS, 40):])
    ultimas = [l for l in linhas if l.strip()][-6:]
    tipo, ops, marc, ini = "-", [], 0, len(linhas)
    if menu:
        tipo, ops, marc, ini = "menu", menu[2], menu[3], base + menu[0]
        # depois do menu só pode haver rodapé curto (dicas de teclas): um menu velho, lá em cima, não vale
        depois = [l for l in linhas[base + menu[1] + 1:] if l.strip() and not borda(l)]
        if len(depois) > 4:
            menu, tipo, ops, marc, ini = None, "-", [], 0, len(linhas)
    if tipo == "-" and ultimas and RE_SN.search(ultimas[-1]):
        tipo, ini = "sn", len(linhas) - 1
        ops = [("s", "sim"), ("n", "não")]
    if tipo == "-" and any(RE_ENTER.search(l) for l in ultimas):
        tipo = "enter"
        ini = len(linhas) - 1
    if tipo == "-":
        # senha pedida sem menu (sudo, ssh, um login): só a voz pergunta
        if ultimas and SENHA.search(ultimas[-1]):
            return saida("perguntar", "senha", "senha", tipo="senha", pergunta=ultimas[-1].strip()[:200],
                         motivo="pede uma senha")
        return saida("nada")
    regiao_l = linhas[max(0, ini - LINHAS):]
    regiao = "\n".join(regiao_l)
    perg = pergunta_de(linhas, ini) if tipo == "menu" else (ultimas[-1].strip()[:220] if ultimas else "")
    opstr = "|".join("%s=%s" % (n, t) for n, t in ops) if ops else "-"
    ag = (agente or agente_da_tela(linhas)).lower()

    def vale(b):
        return b["agente"] in ("*", "") or not ag or b["agente"] == ag

    if SENHA.search(ultimas[-1] if ultimas else ""):
        return saida("perguntar", "senha", "senha", "-", marc, tipo, "-", perg, opstr, "pede uma senha")
    for b in blocos:
        if b["classe"] == "decisao" and vale(b) and b["re"].search(regiao):
            return saida("perguntar", "decisao", b["id"], "-", marc, tipo, "-", perg, opstr,
                         b.get("motivo") or "pede uma decisão sua")
    for b in blocos:
        if b["classe"] == "decisao" or not vale(b) or not b["re"].search(regiao):
            continue
        acao = resposta(b, tipo, ops, marc)
        if not acao:
            continue  # reconheceu a tela, mas não há opção segura: segue procurando; no fim, pergunta
        if b["classe"] == "pasta":
            p = pasta_de(regiao_l, cwd)
            if not autorizada(p, maquina, casas, ler_pastas(pastas) if pastas else []):
                return saida("perguntar", "pasta", b["id"], acao, marc, tipo, p or "-", perg, opstr,
                             "a pasta não está na sua lista autorizada")
            return saida("auto", "pasta", b["id"], acao, marc, tipo, p, perg, opstr)
        return saida("auto", "rotina", b["id"], acao, marc, tipo, "-", perg, opstr)
    return saida("perguntar", "desconhecida", "-", "-", marc, tipo, "-", perg, opstr, "uma pergunta que não conheço")


def resposta(b, tipo, ops, marc):
    """A ação de um bloco de rotina/pasta nesta tela, ou "" (nenhuma opção segura)."""
    if b.get("tecla"):
        if tipo != "enter":
            return ""  # tecla só onde a tela pede só Enter: num menu desconhecido ela escolheria às cegas
        return "teclas " + b["tecla"]
    if tipo == "sn":
        for n, t in (("s", "yes"), ("n", "no")):
            if b["re_op"] and b["re_op"].search(t) and not (b["re_ev"] and b["re_ev"].search(t)):
                return "teclas %s Enter" % ("y" if n == "s" else "n")
        return ""
    if tipo != "menu":
        return ""
    if b.get("opcao") == "@marcada":
        t = dict(ops).get(marc, "")
        return "opcao %d" % marc if marc and not NUNCA.search(t) else ""
    for n, t in ops:
        if b["re_op"].search(t) and not (b["re_ev"] and b["re_ev"].search(t)) and not NUNCA.search(t):
            return "opcao %d" % n
    return ""


def args_de(argv):
    a = {"catalogo": [], "casa": [], "pastas": "", "maquina": "", "cwd": "", "agente": "", "resto": []}
    i = 0
    while i < len(argv):
        k = argv[i]
        if k.startswith("--") and k[2:] in a and i + 1 < len(argv):
            if isinstance(a[k[2:]], list):
                a[k[2:]].append(argv[i + 1])
            else:
                a[k[2:]] = argv[i + 1]
            i += 2
            continue
        a["resto"].append(k)
        i += 1
    return a


def main(argv):
    if not argv:
        print(__doc__.strip())
        return 2
    cmd, a = argv[0], args_de(argv[1:])
    if cmd == "decidir":
        tela = sys.stdin.buffer.read().decode("utf-8", "replace")
        decidir(tela, catalogos(a["catalogo"]), a["pastas"], a["maquina"], a["casa"], a["cwd"], a["agente"])
        return 0
    if cmd in ("catalogo", "validar"):
        blocos, erros = ler_catalogo(catalogos(a["catalogo"]))
        if cmd == "catalogo":
            for b in blocos:
                print("%s\t%s\t%s" % (b["id"], b["agente"], b["classe"]))
        for e in erros:
            print("erro: " + e, file=sys.stderr)
        return 1 if erros else 0
    if cmd == "pasta-ok":
        p = a["resto"][0] if a["resto"] else ""
        return 0 if autorizada(p, a["maquina"], a["casa"], ler_pastas(a["pastas"])) else 1
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
