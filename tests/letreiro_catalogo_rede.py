#!/usr/bin/env python3
"""Valida o catálogo de fábrica do letreiro NA REDE REAL (ferramenta de manutenção; a suíte não usa a rede).

  tests/letreiro_catalogo_rede.py [--gravar] [NOME…]

Cada fonte de fábrica (e cada modelo, com as respostas padrão) roda pelo próprio letreiro-fontes.py, ao vivo, num
HOME de mentira. Imprime OK/XX e o item que a fonte desenharia. Sai com 1 se alguma falhar.

--gravar  para as que passaram: regrava tests/letreiro-amostras/NOME.amostra (a resposta real, reduzida) e o
          `exemplo` e a data `validada` no letreiro-catalogo.json. Rode quando uma fonte mudar de formato ou
          quando entrar fonte nova; depois rode tests/test_letreiro_catalogo.sh (offline) e confira o diff.
"""
import concurrent.futures as cf
import importlib.util
import json
import os
import sys
import tempfile
import threading
import time
import xml.etree.ElementTree as ET

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARQ_JSON = os.path.join(RAIZ, "letreiro-catalogo.json")
PASTA_AMOSTRAS = os.path.join(RAIZ, "tests", "letreiro-amostras")
H = tempfile.mkdtemp(prefix="tt-catalogo-rede-")
os.environ.update(HOME=H, XDG_CONFIG_HOME=H + "/cfg", TT_RT=H + "/rt", LC_ALL="C.utf8")
os.makedirs(H + "/cfg/tt", exist_ok=True)
_s = importlib.util.spec_from_file_location("lf", os.path.join(RAIZ, "letreiro-fontes.py"))
lf = importlib.util.module_from_spec(_s)
_s.loader.exec_module(lf)

ANONIMIZAR = {"ip-publico"}          # fontes cuja resposta traz dado seu (o IP): a amostra guardada é anonimizada
RE_IP = __import__("re").compile(r"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b")
LOC = threading.local()
_buscar = lf.buscar


def _buscar_gravando(req, estado=None):
    r = _buscar(req, estado)
    LOC.corpo = r.corpo
    return r


lf.buscar = _buscar_gravando


def podar(no, n=3):
    """Listas longas ficam com as 3 primeiras e a última (caminhos como [-1] continuam valendo)."""
    if isinstance(no, list):
        cab = no[:n] + (no[-1:] if len(no) > n + 1 else [])
        return [podar(x, n) for x in cab]
    if isinstance(no, dict):
        return {k: podar(v, n) for k, v in no.items()}
    if isinstance(no, str) and len(no) > 400:
        return no[:400]
    return no


PESSOAIS_JSON = {"maintainers", "_npmUser", "author", "contributors"}    # nomes e e-mails de pessoas: a amostra vai para o repositório público


def sem_pessoas(no):
    if isinstance(no, list):
        return [sem_pessoas(x) for x in no]
    if isinstance(no, dict):
        return {k: sem_pessoas(v) for k, v in no.items() if k not in PESSOAIS_JSON}
    return no


def reduzir(formato, corpo):
    if formato in ("rss", "atom", "xml"):
        raiz = ET.fromstring(corpo)
        pais = {c: p for p in raiz.iter() for c in p}
        for e in [e for e in raiz.iter() if isinstance(e.tag, str) and e.tag.split("}")[-1] in ("creator", "author")]:
            pais[e].remove(e)            # assinatura de jornalista: nenhuma fonte usa
        itens = [e for e in raiz.iter() if isinstance(e.tag, str) and e.tag.split("}")[-1] in ("item", "entry")]
        for e in itens[5:]:
            pais[e].remove(e)
        for e in raiz.iter():
            if isinstance(e.tag, str) and e.tag.split("}")[-1] in ("encoded", "content", "description", "summary") and e.text and len(e.text) > 300:
                e.text = e.text[:300]
        return ET.tostring(raiz, encoding="utf-8", xml_declaration=True)
    if formato == "json":
        dados = sem_pessoas(json.loads(corpo))
        if len(corpo) > 6000:
            dados = podar(dados)
        return json.dumps(dados, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return corpo[:30000]


def rodar(nome, conf, perguntas=()):
    d = dict(conf)
    for var, _perg, padrao in perguntas:
        d["var." + var] = padrao
    d["ativa"] = "1"
    n, erros, _a = lf.validar_fonte(d, completo=True)
    if erros:
        return nome, False, "; ".join(erros), "", None
    if n.get("origem") == "tt":
        return nome, True, "", "", None          # depende do tt instalado: o teste do tt cobre
    f = lf.efetiva_completa(n)
    LOC.corpo = None
    res = lf.executar(nome, n, time.time(), {}, {})
    if not res.ok:
        return nome, False, (res.erro or "falhou sem mensagem"), "", None
    if not res.itens:
        if f["condicao"]:                           # ex.: só aparece quando há algo (CI em andamento, tarefa atrasada)
            return nome, True, "(sem item agora: a condição não foi atendida)", "", None
        return nome, False, "sem itens (caminho?)", "", None
    return nome, True, "", lf.sem_marcas(res.itens[0].linha), reduzir(f["formato"], LOC.corpo or b"")


def main(argv):
    gravar = "--gravar" in argv
    nomes = [a for a in argv if not a.startswith("--")]
    cat = json.load(open(ARQ_JSON, encoding="utf-8"))
    tarefas = [(n, e["conf"], ()) for n, e in cat["fabrica"].items() if not nomes or n in nomes]
    tarefas += [("modelo:" + i, m["conf"], [tuple(p) for p in m.get("perguntas", [])]) for i, m in cat["modelos"].items() if not nomes or i in nomes]
    with cf.ThreadPoolExecutor(8) as ex:
        resultados = list(ex.map(lambda t: rodar(*t), tarefas))
    ruins = 0
    hoje = time.strftime("%Y-%m-%d")
    for nome, ok, erro, exemplo, amostra in resultados:
        ruins += not ok
        print("%s %-26s %s" % ("OK" if ok else "XX", nome, (exemplo or erro)[:110]))
        if ok and gravar and not nome.startswith("modelo:"):
            e = cat["fabrica"][nome]
            if nome in ANONIMIZAR:     # a amostra vai para o repositório público: o seu endereço nunca
                exemplo = RE_IP.sub("203.0.113.7", exemplo)          # (203.0.113.0/24 é a faixa de documentação)
                amostra = RE_IP.sub("203.0.113.7", amostra.decode("utf-8", "replace")).encode("utf-8") if amostra is not None else None
            if exemplo:
                e["exemplo"], e["validada"] = exemplo, hoje
            if amostra is not None:
                os.makedirs(PASTA_AMOSTRAS, exist_ok=True)
                with open(os.path.join(PASTA_AMOSTRAS, nome + ".amostra"), "wb") as f:
                    f.write(amostra)
    if gravar:
        with open(ARQ_JSON, "w", encoding="utf-8") as f:
            json.dump(cat, f, ensure_ascii=False, indent=1)
            f.write("\n")
        print("gravado: %s e %s" % (os.path.relpath(ARQ_JSON, RAIZ), os.path.relpath(PASTA_AMOSTRAS, RAIZ)))
    print("%d/%d ok" % (len(resultados) - ruins, len(resultados)))
    return 1 if ruins else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
