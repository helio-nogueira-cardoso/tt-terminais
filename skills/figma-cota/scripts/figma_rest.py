#!/usr/bin/env python3
"""Figma pela API REST, gastando o minimo de cota, e consultas locais ao arquivo baixado.

Chamadas que gastam cota (registradas no livro de uso):
  figma_rest.py versao  CHAVE              1 chamada: version e lastModified; compara com o cache
  figma_rest.py baixar  CHAVE [--imagens]  1 chamada (+1 com --imagens): arquivo inteiro no cache

So locais (nao gastam nada):
  figma_rest.py resolver URL               extrai fileKey e nodeId sem rede
  figma_rest.py ler URL [--cache DIR]       le o frame do link no cache, sem rede
  figma_rest.py telas   CHAVE              paginas e frames de nivel de tela (id, nome, tamanho)
  figma_rest.py buscar  CHAVE TEXTO        nos cujo nome ou texto contem TEXTO
  figma_rest.py no      CHAVE ID [--prof N] subarvore do no: tipo, nome, tamanho, layout, cores, textos
  figma_rest.py uso                        chamadas do mes por canal (rest, mcp)
  figma_rest.py registrar CANAL DESCRICAO  anota uma chamada feita por fora (ex.: mcp get_design_context 200:3)

CHAVE pode ser a chave ou URL completa do arquivo/frame. Opcoes:
  --cache DIR   pasta do cache (padrao ~/.cache/figma/<CHAVE>)
Token: variavel FIGMA_TOKEN ou o arquivo de FIGMA_TOKEN_FILE (padrao ~/.secrets/figma.txt). Nunca e impresso.
"""
import datetime
import argparse
import json
import os
import re
import sys
import unicodedata
import urllib.error
import urllib.request
import urllib.parse

API = "https://api.figma.com/v1"
LIVRO = os.path.expanduser(os.environ.get("FIGMA_COTA_LIVRO", "~/.local/state/figma-cota/uso.tsv"))


def referencia(valor):
    """Resolve chave ou link de frame sem acessar a rede."""
    if re.fullmatch(r"[A-Za-z0-9]+", valor):
        return valor, None
    u = urllib.parse.urlsplit(valor)
    if (u.scheme != "https" or u.hostname not in ("figma.com", "www.figma.com")
            or u.username or u.password or u.port not in (None, 443)):
        raise ValueError("use uma chave ou URL HTTPS de figma.com")
    partes = u.path.strip("/").split("/")
    if len(partes) < 2 or partes[0] not in ("design", "file", "proto", "board"):
        raise ValueError("link sem chave de arquivo reconhecível")
    chave = partes[1]
    if not re.fullmatch(r"[A-Za-z0-9]+", chave):
        raise ValueError("chave de arquivo inválida")
    # Links de branches identificam outro arquivo; não usar o cache da main.
    if len(partes) > 2 and partes[2] == "branch":
        if len(partes) < 4 or not re.fullmatch(r"[A-Za-z0-9]+", partes[3]):
            raise ValueError("chave de branch inválida")
        chave = partes[3]
    ids = urllib.parse.parse_qs(u.query).get("node-id", [])
    if len(ids) > 1:
        raise ValueError("link com mais de um node-id")
    ident = normalizar_no(ids[0]) if ids else None
    return chave, ident


def normalizar_no(ident):
    ident = ident.replace("-", ":")
    if not re.fullmatch(r"\d+:\d+", ident):
        raise ValueError("node-id inválido; use o link de um frame ou ID como 12:34")
    return ident


def _token():
    tok = os.environ.get("FIGMA_TOKEN")
    if tok:
        return tok.strip()
    caminho = os.path.expanduser(os.environ.get("FIGMA_TOKEN_FILE", "~/.secrets/figma.txt"))
    try:
        with open(caminho) as f:
            return f.read().strip()
    except OSError:
        sys.exit(f"sem token: defina FIGMA_TOKEN ou crie {caminho}")


def registrar(canal, descricao):
    os.makedirs(os.path.dirname(LIVRO) or ".", exist_ok=True)
    agora = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    with open(LIVRO, "a") as f:
        descricao = descricao.replace("\t", " ").replace("\n", " ").replace("\r", " ")
        f.write(f"{agora}\t{canal}\t{descricao}\n")


def _get(url, descricao):
    req = urllib.request.Request(url, headers={"X-Figma-Token": _token()})
    registrar("rest", descricao)
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        espera = e.headers.get("Retry-After")
        sys.exit(f"Figma respondeu HTTP {e.code}" + (f" (Retry-After {espera}s)" if espera else "")
                 + {429: ": limite de chamadas; respeite Retry-After e use o cache, sem repetir automaticamente",
                    403: ": confira validade, escopos do token e acesso ao arquivo",
                    404: ": arquivo não encontrado ou sem acesso"}.get(e.code, ""))
    except urllib.error.URLError:
        sys.exit("Falha de conexão com Figma; use o cache e tente novamente depois")


def _cache(chave, pasta):
    return os.path.expanduser(pasta or f"~/.cache/figma/{chave}")


def _carregar(chave, pasta):
    caminho = os.path.join(_cache(chave, pasta), "arquivo.json")
    if not os.path.exists(caminho):
        sys.exit(f"sem cache em {caminho}: rode 'baixar {chave}' primeiro")
    meta = os.path.join(_cache(chave, pasta), "meta.json")
    if os.path.exists(meta):
        with open(meta) as f:
            origem = json.load(f).get("fileKey")
        if origem and origem != chave:
            sys.exit("cache pertence a outro arquivo; use uma pasta de cache por chave")
        if not origem and pasta:
            print("Aviso: cache legado sem fileKey; confirme que pertence ao link informado", file=sys.stderr)
    elif pasta:
        print("Aviso: cache legado sem metadados; confirme que pertence ao link informado", file=sys.stderr)
    with open(caminho) as f:
        return json.load(f)


def versao(chave, pasta):
    meta = os.path.join(_cache(chave, pasta), "meta.json")
    antes = {}
    if os.path.exists(meta):
        with open(meta) as f:
            antes = json.load(f)
        if antes.get("fileKey") and antes["fileKey"] != chave:
            sys.exit("cache pertence a outro arquivo; use uma pasta de cache por chave")
    arquivo = os.path.join(_cache(chave, pasta), "arquivo.json")
    if not antes and os.path.exists(arquivo):  # cache feito por outra ferramenta, sem meta.json
        with open(arquivo) as f:
            d0 = json.load(f)
        antes = {"version": d0.get("version"), "lastModified": d0.get("lastModified"), "baixado": "?"}
    d = _get(f"{API}/files/{chave}?depth=1", f"versao {chave}")
    print(f"{d['name']} · versao {d['version']} · {d['lastModified']}")
    if not antes:
        print("cache: vazio (rode baixar)")
    elif antes.get("version") == d["version"]:
        print(f"cache: IGUAL (baixado em {antes.get('baixado')}); trabalhe so no local")
    else:
        print(f"cache: DESATUALIZADO (cache {antes.get('version')} de {antes.get('lastModified')}); rode baixar")


def _telas(doc):
    """Frames filhos diretos de pagina ou de secao: as telas e quadros do arquivo."""
    saida = []

    def visitar(n, pagina):
        for c in n.get("children", []):
            if c["type"] == "SECTION":
                visitar(c, pagina)
            elif c["type"] in ("FRAME", "COMPONENT", "COMPONENT_SET"):
                saida.append((pagina, c))

    for p in doc["document"]["children"]:
        visitar(p, p)
    return saida


def baixar(chave, pasta, imagens):
    destino = _cache(chave, pasta)
    os.makedirs(destino, exist_ok=True)
    doc = _get(f"{API}/files/{chave}", f"baixar {chave}")
    with open(os.path.join(destino, "arquivo.json"), "w") as f:
        json.dump(doc, f)
    meta = {k: doc.get(k) for k in ("name", "version", "lastModified")}
    meta["fileKey"] = chave
    meta["baixado"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    with open(os.path.join(destino, "meta.json"), "w") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    telas = _telas(doc)
    if imagens and telas:
        ids = ",".join(n["id"] for _, n in telas)
        query = urllib.parse.urlencode({"format": "png", "scale": 2, "ids": ids, "version": doc["version"]})
        urls = _get(f"{API}/images/{chave}?{query}", f"imagens {chave}")["images"]
        os.makedirs(os.path.join(destino, "telas"), exist_ok=True)
        for _, n in telas:
            if urls.get(n["id"]):  # o download das URLs devolvidas nao conta na cota
                nome = n["id"].replace(":", "-") + ".png"
                urllib.request.urlretrieve(urls[n["id"]], os.path.join(destino, "telas", nome))
    print(f"{doc['name']} · versao {doc['version']} · {doc['lastModified']} · {len(telas)} frames · {destino}")


def _tam(n):
    b = n.get("absoluteBoundingBox") or {}
    return f"{round(b.get('width', 0))}x{round(b.get('height', 0))}"


def telas(chave, pasta):
    for pagina, n in _telas(_carregar(chave, pasta)):
        print(f"{n['id']}\t{_tam(n)}\t{pagina['name']} › {n['name']}")


def _sem_acento(t):
    return unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode().lower()


def buscar(chave, pasta, texto):
    alvo = _sem_acento(texto)
    achados = 0

    def visitar(n, caminho):
        nonlocal achados
        nome = n.get("name", "")
        conteudo = n.get("characters", "")
        if alvo in _sem_acento(nome) or alvo in _sem_acento(conteudo):
            extra = f' t="{conteudo[:60]}"' if conteudo else ""
            print(f"{n['id']}\t{n['type']}\t{_tam(n)}\t{caminho} › {nome}{extra}")
            achados += 1
        for c in n.get("children", []):
            visitar(c, f"{caminho} › {nome}"[-90:] if n["type"] != "DOCUMENT" else "")

    visitar(_carregar(chave, pasta)["document"], "")
    print(f"{achados} no(s)", file=sys.stderr)


def _cor(p):
    c = p.get("color", {})
    hexa = "#{:02X}{:02X}{:02X}".format(*(round(c.get(k, 0) * 255) for k in "rgb"))
    alfa = round(c.get("a", 1) * p.get("opacity", 1), 2)
    return hexa if alfa == 1 else f"{hexa}/{alfa}"


def _resumo(n):
    partes = [n["type"], repr(n.get("name", "")), _tam(n)]
    if n.get("layoutMode"):
        pad = [n.get(k, 0) for k in ("paddingTop", "paddingRight", "paddingBottom", "paddingLeft")]
        partes.append(f"{n['layoutMode'].lower()} gap {n.get('itemSpacing', 0)} pad {'/'.join(str(round(v)) for v in pad)}")
    fills = [_cor(p) for p in n.get("fills", []) if p.get("type") == "SOLID" and p.get("visible", True)]
    if fills:
        partes.append("fill " + ",".join(fills))
    strokes = [_cor(p) for p in n.get("strokes", []) if p.get("type") == "SOLID"]
    if strokes:
        partes.append(f"stroke {','.join(strokes)} {n.get('strokeWeight', '')}")
    if n.get("cornerRadius"):
        partes.append(f"raio {n['cornerRadius']}")
    st = n.get("style") or {}
    if n["type"] == "TEXT":
        partes.append(f"{st.get('fontFamily', '')} {st.get('fontWeight', '')} {st.get('fontSize', '')}/{round(st.get('lineHeightPx', 0), 1)}")
        partes.append(f't="{n.get("characters", "")[:80]}"')
    if n.get("boundVariables"):
        partes.append("vars " + ",".join(sorted(n["boundVariables"])))
    return " · ".join(partes)


def no(chave, pasta, ident, prof):
    alvo = None

    def achar(n):
        nonlocal alvo
        if n["id"] == ident:
            alvo = n
            return
        for c in n.get("children", []):
            if alvo is None:
                achar(c)

    achar(_carregar(chave, pasta)["document"])
    if alvo is None:
        sys.exit(f"no {ident} nao esta no cache (arquivo mudou? rode versao)")

    def imprimir(n, nivel):
        print("  " * nivel + f"{n['id']} " + _resumo(n))
        if nivel < prof:
            for c in n.get("children", []):
                imprimir(c, nivel + 1)

    imprimir(alvo, 0)


def uso():
    mes = datetime.date.today().strftime("%Y-%m")
    contagem = {}
    if os.path.exists(LIVRO):
        with open(LIVRO) as f:
            linhas = f.readlines()
        for linha in linhas:
            campos = linha.rstrip("\n").split("\t")
            if len(campos) >= 2 and campos[0].startswith(mes):
                contagem[campos[1]] = contagem.get(campos[1], 0) + 1
    for canal in ("rest", "mcp"):
        print(f"{canal}\t{contagem.get(canal, 0)} chamada(s) em {mes} (livro: {LIVRO})")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("comando", choices=("ajuda", "uso", "registrar", "resolver", "ler", "versao", "baixar", "telas", "buscar", "no"))
    parser.add_argument("argumentos", nargs="*")
    parser.add_argument("--cache")
    parser.add_argument("--prof", type=int, default=3)
    parser.add_argument("--imagens", action="store_true")
    args = parser.parse_args()
    if args.prof < 0:
        parser.error("--prof deve ser não negativo")
    cmd, resto = args.comando, args.argumentos
    pasta, prof, imagens = args.cache, args.prof, args.imagens
    if cmd == "ajuda":
        parser.print_help()
        return
    if cmd == "uso":
        uso()
        return
    if cmd == "registrar" and len(resto) >= 2:
        if resto[0] not in ("rest", "mcp", "mcp-local"):
            parser.error("canal: rest, mcp ou mcp-local")
        registrar(resto[0], " ".join(resto[1:]))
        return
    if not resto:
        parser.error("informe a chave ou URL do frame")
    try:
        chave, ident = referencia(resto[0])
        resto[0] = chave
        if cmd in ("no", "ler"):
            if len(resto) >= 2:
                explicito = normalizar_no(resto[1])
                if ident and explicito != ident:
                    raise ValueError("ID explícito difere do node-id da URL")
                ident = explicito
            if not ident:
                raise ValueError("informe URL com node-id ou chave e ID do frame")
    except ValueError as e:
        parser.error(str(e))
    if cmd == "resolver":
        print(json.dumps({"fileKey": chave, "nodeId": ident}))
    elif cmd == "versao":
        versao(resto[0], pasta)
    elif cmd == "baixar":
        baixar(resto[0], pasta, imagens)
    elif cmd == "telas":
        telas(resto[0], pasta)
    elif cmd == "buscar" and len(resto) >= 2:
        buscar(resto[0], pasta, " ".join(resto[1:]))
    elif cmd in ("no", "ler"):
        no(chave, pasta, ident, prof)
    else:
        parser.error("argumentos insuficientes para o comando")


if __name__ == "__main__":
    main()
