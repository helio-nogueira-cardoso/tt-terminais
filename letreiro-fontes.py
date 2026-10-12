#!/usr/bin/env python3
"""letreiro-fontes.py — as FONTES (APIs) do letreiro do tt: cadastro, rede, formatos, transformação,
agenda, diagnóstico e propagação. Um módulo só, sem dependências além da biblioteca padrão.

Quem desenha o letreiro (letreiro-tt.py, um processo por terminal) NUNCA fala com a rede: ele só lê o que
este módulo deixa em ~/.cache/tt-ticker/ (uma linha por item em NOME, os alvos de clique em NOME.itens, o
estado em NOME.meta e o índice da roda em _roda.json). Quem chama este módulo é o vigia do tt
(`atualizar`, a cada volta), os verbos `tt --letreiro-*` e os testes.

Cada fonte é um arquivo ~/.config/tt/letreiro/NOME.conf (chave=valor, versao=1; ver CAMPOS) — perfil do
usuário, nunca sobrescrito pela instalação. As fontes nativas (dolar, frases, noticias) vivem no código;
um NOME.conf com o mesmo nome só sobrepõe as chaves que traz. As linhas antigas indicador_NOME= do config
continuam valendo e são migradas sem perda (`migrar`). Segredo mora SÓ em ~/.secrets (referência @nome):
nunca no .conf, no log, na tela nem na propagação.

Uso: letreiro-fontes.py COMANDO [args]   (letreiro-fontes.py ajuda)
"""
import base64
import csv
import fcntl
import hashlib
import html
import http.client
import io
import ipaddress
import json
import os
import re
import signal
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import unicodedata
import urllib.parse
import zlib
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta
from decimal import Decimal, InvalidOperation, ROUND_CEILING, ROUND_DOWN, ROUND_FLOOR, ROUND_HALF_UP

VERSAO_FORMATO = 1
HOME = os.path.expanduser("~")
CONF_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "tt")
CONF = os.path.join(CONF_DIR, "config")
DIR_FONTES = os.path.join(CONF_DIR, "letreiro")
DIR_LOCAL = os.path.join(DIR_FONTES, "local")       # sobrescritas SÓ desta máquina (nunca propagadas)
ARQ_REMOVIDAS = os.path.join(DIR_FONTES, ".removidas")  # lápides: nome<TAB>epoch (fonte global apagada)
ARQ_MIGRADO = os.path.join(DIR_FONTES, ".migrado")      # valor de indicadores= já aplicado
DIR_TICKER = os.path.join(HOME, ".cache", "tt-ticker")
ARQ_RODA = os.path.join(DIR_TICKER, "_roda.json")
ARQ_LOG = os.path.join(HOME, ".cache", "tt-letreiro.log")
LOG_MAX = 256 * 1024
SECRETS = os.path.join(HOME, ".secrets")
RT = os.environ.get("TT_RT") or "/run/user/%d" % os.getuid()
RE_NOME = re.compile(r"^[a-z0-9][a-z0-9_-]{0,31}$")
RE_SEGREDO = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
MARCAS = {"alta": "\x01", "baixa": "\x02", "neutra": "\x03", "fim": "\x04"}  # só entram por modelo próprio
UA_PADRAO = "tt-letreiro/1 (+https://github.com/helio-nogueira-cardoso/tt-terminais)"


class Erro(Exception):
    """Erro de uso ou de dados com mensagem pronta para o usuário (sem segredo)."""


# --------------------------------------------------------------------------------------------------
# Esquema: todos os campos de uma fonte. (chave, tipo, padrão, grupo, descrição)
#   tipos: str, int, float, bool, lista (chave repetida), enum:a|b|c  (enum com "" no fim aceita vazio)
# --------------------------------------------------------------------------------------------------
CAMPOS = [
    # identidade
    ("rotulo", "str", "", "identidade", "texto que rotula o valor (ex.: dólar)"),
    ("icone", "str", "", "identidade", "ícone/emoji do item (ex.: 💵)"),
    ("descricao", "str", "", "identidade", "descrição livre"),
    ("ativa", "bool", "1", "identidade", "1 = entra na roda"),
    ("ordem", "int:0:9999", "100", "identidade", "posição na roda (menor primeiro)"),
    ("peso", "int:1:9", "1", "identidade", "quantas vezes aparece por volta"),
    ("tags", "str", "", "identidade", "etiquetas separadas por vírgula"),
    ("escopo", "enum:local|global", "local", "identidade", "global = propagada pela rede (a mudança mais nova vence)"),
    ("perfil", "enum:todos|desktop|celular", "todos", "identidade", "só nas máquinas deste perfil"),
    ("maquinas", "str", "", "identidade", "só nestas máquinas (nomes separados por vírgula; !nome exclui)"),
    # origem e requisição
    ("origem", "enum:rede|lista|tt", "rede", "requisicao", "rede = HTTP; lista = itens fixos do arquivo; tt = dado do próprio tt"),
    ("dado", "str", "", "requisicao", "origem=tt: tarefas-atrasadas | emails-nao-lidos"),
    ("item", "lista", "", "requisicao", "origem=lista: um item por linha (sorteia entre eles)"),
    ("url", "str", "", "requisicao", "endereço https (aceita {data} {moeda} {segredo} e var.NOME=)"),
    ("metodo", "enum:GET|POST", "GET", "requisicao", "método HTTP"),
    ("header", "lista", "", "requisicao", "cabeçalho extra 'Nome: valor' (valor secreto: @arquivo)"),
    ("query", "lista", "", "requisicao", "parâmetro de query 'nome=valor' (repetível)"),
    ("corpo", "str", "", "requisicao", "corpo do POST (aceita {variáveis})"),
    ("timeout", "float:1:60", "10", "requisicao", "segundos por tentativa"),
    ("tentativas", "int:1:5", "2", "requisicao", "tentativas por atualização"),
    ("espera", "float:0:60", "2", "requisicao", "espera entre tentativas (dobra a cada uma)"),
    ("user_agent", "str", "", "requisicao", "User-Agent (padrão do tt)"),
    ("tls_verificar", "bool", "1", "requisicao", "0 = não verificar o certificado TLS (evite)"),
    ("proxy", "str", "", "requisicao", "proxy http://host:porta (opcional)"),
    ("permitir_http", "bool", "0", "requisicao", "1 = aceita http:// (sem criptografia; evite)"),
    ("tamanho_max", "int:1024:8388608", "1048576", "requisicao", "bytes máximos da resposta"),
    # autenticação (o segredo fica em ~/.secrets, referenciado por @nome)
    ("auth", "enum:nenhuma|header|query|bearer|basic", "nenhuma", "autenticacao", "como enviar o segredo"),
    ("auth_nome", "str", "", "autenticacao", "nome do header ou do parâmetro (auth=header|query)"),
    ("segredo", "str", "", "autenticacao", "@arquivo em ~/.secrets (basic: usuario:senha)"),
    # resposta
    ("formato", "enum:json|xml|rss|atom|csv|texto|regex", "json", "resposta", "formato da resposta"),
    ("caminho", "str", "", "resposta", "o que extrair: JSONPath simples, XPath, coluna, regex ou linha"),
    ("itens", "int:1:20", "1", "resposta", "quantos itens tirar da resposta"),
    ("de", "enum:inicio|fim", "inicio", "resposta", "tirar os itens do início ou do fim da resposta"),
    ("csv_sep", "str", ",", "resposta", "separador do CSV"),
    ("csv_cabecalho", "enum:auto|1|0", "auto", "resposta", "CSV com linha de cabeçalho"),
    ("codificacao", "str", "utf-8", "resposta", "codificação do texto (utf-8, latin-1…)"),
    # transformação
    ("decimais", "int:0:8:vazio", "", "transformacao", "casas decimais (vazio = como veio)"),
    ("separador", "enum:pt|en|", "", "transformacao", "pt = 1.234,56; en = 1,234.56 (vazio = como veio)"),
    ("entrada", "enum:auto|pt|en", "auto", "transformacao", "como o número chega na resposta"),
    ("milhar", "bool", "1", "transformacao", "separador de milhar ao formatar"),
    ("moeda", "str", "", "transformacao", "prefixo do valor (R$, US$…)"),
    ("escala", "enum:nenhuma|mil|mi|bi", "nenhuma", "transformacao", "divide o valor e põe o sufixo"),
    ("arredondar", "enum:normal|cima|baixo|truncar", "normal", "transformacao", "como arredondar"),
    ("variacao", "str", "", "transformacao", "caminho da variação % na resposta, ou 'calculada' (contra o valor anterior)"),
    ("var_base", "str", "", "transformacao", "caminho do valor de referência: variação = (valor-base)/base"),
    ("var_decimais", "int:0:4", "1", "transformacao", "casas da variação"),
    ("setas", "bool", "1", "transformacao", "▲/▼ na variação (0 = +/-)"),
    ("traduzir", "lista", "", "transformacao", "troca de texto fixo 'origem>destino'"),
    ("valor_max", "int:0:400", "0", "transformacao", "corta o valor bruto em N caracteres (0 = não corta)"),
    # exibição
    ("modelo", "str", "{icone} {rotulo} {valor} {var}", "exibicao", "modelo do item: {icone} {rotulo} {valor} {var} {seta} {pct}…"),
    ("truncar", "int:0:400", "0", "exibicao", "largura máxima do item em células (0 = não corta, o padrão)"),
    ("prefixo", "str", "", "exibicao", "texto antes do item"),
    ("sufixo", "str", "", "exibicao", "texto depois do item"),
    ("cor", "bool", "1", "exibicao", "cor por sinal (alta verde, baixa vermelha)"),
    ("se_faltar", "enum:esconder|ultimo|erro", "ultimo", "exibicao", "sem dado novo: esconde, mostra o último (marcado) ou o erro"),
    ("cache_max", "int:0:100000", "360", "exibicao", "minutos de cache aceitos sem marca (0 = sem limite)"),
    # agenda e cache
    ("ttl", "int:10:604800", "600", "agenda", "segundos entre atualizações"),
    ("dias", "str", "", "agenda", "dias em que atualiza (seg-sex, sab,dom…)"),
    ("horas", "str", "", "agenda", "horas em que atualiza (10-18, 9:30-12,14-17:45)"),
    ("so_com_cliente", "bool", "0", "agenda", "1 = só atualiza com um terminal tmux em uso"),
    ("limite_hora", "int:0:3600", "0", "agenda", "máximo de requisições por hora (0 = sem limite)"),
    ("alerta_falhas", "int:0:100", "5", "agenda", "avisa na central de notificações após N falhas seguidas (0 = nunca)"),
    # condições
    ("condicao", "lista", "", "condicoes", "mostra só se: valor>N · var>N · abs>N · cruza N · contem T · mudou"),
    ("mostrar_dias", "str", "", "condicoes", "dias em que o item aparece"),
    ("mostrar_horas", "str", "", "condicoes", "horas em que o item aparece"),
    # clique
    ("clique", "enum:nada|url|painel|copiar", "nada", "clique", "o que o clique no item faz"),
    ("clique_alvo", "str", "", "clique", "url (aceita {link} {valor}…) | painel (tarefas, email, calendario, notificacoes, letreiro) | texto a copiar"),
    # gerenciados
    ("versao", "int", "1", "controle", "versão do formato do arquivo"),
    ("mudada", "int", "0", "controle", "hora da última mudança (a mais nova vence ao propagar)"),
]
TIPO = {c[0]: c[1] for c in CAMPOS}
PADRAO = {c[0]: c[2] for c in CAMPOS}
DESCR = {c[0]: c[4] for c in CAMPOS}
GRUPO = {c[0]: c[3] for c in CAMPOS}
REPETE = {c[0] for c in CAMPOS if c[1] == "lista"}
# Campos que NÃO são personalizações de aparência e identificam uma requisição
CAMPOS_REQ = {"url", "origem", "dado", "formato", "caminho", "variacao", "var_base"}
# Header que carrega credencial: o valor tem que ser @arquivo (ou {segredo}), nunca literal
RE_HEADER_SECRETO = re.compile(r"^(authorization|proxy-authorization|x-api-key|api-key|apikey|x-auth-token|"
                               r"x-access-token|x-token|token|cookie|x-secret|secret)$", re.I)
RE_QUERY_SECRETA = re.compile(r"^(api[_-]?key|apikey|key|token|access[_-]?token|secret|auth|password|senha|pwd|sig|signature)$", re.I)


# --------------------------------------------------------------------------------------------------
# Tempo, config global e utilidades pequenas
# --------------------------------------------------------------------------------------------------
def agora():
    v = os.environ.get("TT_AGORA", "")
    try:
        return float(v) if v else time.time()
    except ValueError:
        return time.time()


def ler_conf():
    """~/.config/tt/config: chave=valor; a última ocorrência vale (como conf() do tt)."""
    d = {}
    try:
        with open(CONF, encoding="utf-8", errors="replace") as f:
            for linha in f:
                linha = linha.rstrip("\n")
                if "=" in linha and not linha.startswith("#"):
                    k, v = linha.split("=", 1)
                    d[k] = v
    except OSError:
        pass
    return d


def fuso(cfg):
    nome = cfg.get("ticker_fuso", "")
    if nome:
        try:
            from zoneinfo import ZoneInfo
            return ZoneInfo(nome)
        except Exception:
            pass
    return None


def dt_local(ts, cfg=None):
    return datetime.fromtimestamp(ts, fuso(cfg or {}))


def maquina_nome():
    n = os.environ.get("TT_MACHINE") or ler_conf().get("nome") or ""
    if n:
        return n
    try:
        return socket.gethostname().split(".")[0]
    except OSError:
        return ""


def perfil_maquina():
    """celular (Termux) ou desktop. TT_PERFIL força (testes)."""
    p = os.environ.get("TT_PERFIL", "")
    if p in ("celular", "desktop"):
        return p
    if "com.termux" in os.environ.get("PREFIX", "") or os.path.exists("/data/data/com.termux"):
        return "celular"
    return "desktop"


def ha(seg):
    """Tempo decorrido legível: 'agora', 'há 5 s', 'há 3 min', 'há 2 h', 'há 4 d'."""
    seg = int(seg)
    if seg < 0:
        seg = 0
    if seg < 5:
        return "agora"
    if seg < 90:
        return "há %d s" % seg
    if seg < 5400:
        return "há %d min" % round(seg / 60)
    if seg < 172800:
        return "há %d h" % round(seg / 3600)
    return "há %d d" % round(seg / 86400)


def escrever_atomico(caminho, conteudo, modo=0o600):
    """Grava num temporário da mesma pasta e troca (o desenhista nunca lê um arquivo pela metade)."""
    pasta = os.path.dirname(caminho)
    os.makedirs(pasta, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=os.path.basename(caminho) + ".", dir=pasta)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(conteudo)
        os.chmod(tmp, modo)
        os.replace(tmp, caminho)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def ler_texto(caminho):
    try:
        with open(caminho, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def ler_json(caminho, padrao=None):
    try:
        with open(caminho, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {} if padrao is None else padrao


def rotacionar_log():
    try:
        if os.path.getsize(ARQ_LOG) > LOG_MAX:
            os.replace(ARQ_LOG, ARQ_LOG + ".1")
    except OSError:
        pass


# --------------------------------------------------------------------------------------------------
# Segredos: ~/.secrets/<nome>, referência @nome. O valor nunca sai daqui sem passar por redigir().
# --------------------------------------------------------------------------------------------------
_SEGREDOS_VISTOS = set()


def ref_segredo(ref):
    """'@nome' → nome do arquivo em ~/.secrets (validado: nada de caminho)."""
    if not ref.startswith("@"):
        raise Erro("o segredo tem que ser uma referência @arquivo (o valor fica em ~/.secrets, nunca na configuração)")
    nome = ref[1:]
    if not RE_SEGREDO.match(nome):
        raise Erro("nome de segredo inválido: %s (letras, números, . _ -)" % nome)
    return nome


def ler_segredo(ref):
    nome = ref_segredo(ref)
    caminho = os.path.join(SECRETS, nome)
    try:
        st = os.stat(caminho)
        with open(caminho, encoding="utf-8", errors="replace") as f:
            valor = f.read(4096).strip()
    except OSError:
        raise Erro("segredo %s não encontrado (crie ~/.secrets/%s com modo 600: tt --letreiro-segredo)" % (ref, nome))
    if not valor:
        raise Erro("segredo %s está vazio" % ref)
    for parte in re.split(r"[\s:]+", valor):
        if len(parte) >= 4:
            _SEGREDOS_VISTOS.add(parte)
    _SEGREDOS_VISTOS.add(valor)
    _SEGREDOS_VISTOS.add(base64.b64encode(valor.encode()).decode())
    _SEGREDOS_VISTOS.add(urllib.parse.quote(valor, safe=""))
    if st.st_mode & 0o077:
        AVISOS_SEGREDO.add("permissões frouxas em ~/.secrets/%s (chmod 600)" % nome)
    return valor


AVISOS_SEGREDO = set()


def redigir(txt):
    """Tira de um texto qualquer coisa que pareça segredo (valores lidos de ~/.secrets, tokens Bearer,
    parâmetros de chave na query). Todo erro, log e relatório passa por aqui."""
    if not txt:
        return txt
    txt = str(txt)
    for s in sorted(_SEGREDOS_VISTOS, key=len, reverse=True):
        if s and s in txt:
            txt = txt.replace(s, "***")
    txt = re.sub(r"(?i)(authorization:\s*(?:bearer|basic)\s+)[A-Za-z0-9._~+/=-]{6,}", r"\1***", txt)
    txt = re.sub(r"(?i)([?&](?:api[_-]?key|apikey|key|token|access[_-]?token|secret|password|senha|pwd|sig)=)[^&\s]+", r"\1***", txt)
    return txt


def segredo_gravar(nome, valor):
    if not RE_SEGREDO.match(nome):
        raise Erro("nome de segredo inválido: %s" % nome)
    os.makedirs(SECRETS, mode=0o700, exist_ok=True)
    caminho = os.path.join(SECRETS, nome)
    fd = os.open(caminho, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(valor.strip() + "\n")
    os.chmod(caminho, 0o600)
    return "@" + nome


# --------------------------------------------------------------------------------------------------
# Sanitização: texto vindo da rede é dado não confiável
# --------------------------------------------------------------------------------------------------
_RE_ESC = re.compile(
    r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?"        # OSC (título, hyperlink, área de transferência…)
    r"|\x1b[PX^_][^\x1b]*(?:\x1b\\)?"           # DCS, SOS, PM, APC
    r"|\x1b\[[0-?]*[ -/]*[@-~]"                  # CSI (cores, cursor, apagar tela…)
    r"|\x1b[ -/]*[0-~]"                          # demais escapes de 2 bytes
    r"|\x9b[0-?]*[ -/]*[@-~]|\x9d[^\x07\x9c]*[\x07\x9c]?")  # CSI/OSC de 8 bits
_RE_CTRL = re.compile(r"[\x00-\x1f\x7f-\x9f]")
_RE_CTRL_MARCAS = re.compile(r"[\x00\x05-\x1f\x7f-\x9f]")  # preserva \x01-\x04 (as marcas de cor do próprio tt)
_RE_BIDI = re.compile("[‎‏؜‪-‮⁦-⁩﻿-]")
_RE_TMUX = re.compile(r"#(?=[\[({])")


def limpar_texto(t, manter_marcas=False):
    """Texto remoto → texto inofensivo de uma linha: sem sequências de escape de terminal, sem caracteres
    de controle (nem as marcas de cor do tt), sem controles de direção do Unicode e sem a sintaxe de
    formatação do tmux (#[ #( #{ ), que executaria comando ou pintaria a barra."""
    if t is None:
        return ""
    t = str(t)
    t = _RE_ESC.sub("", t)
    t = re.sub(r"[\t\r\n\v\f]+", " ", t)
    t = (_RE_CTRL_MARCAS if manter_marcas else _RE_CTRL).sub("", t)
    t = _RE_BIDI.sub("", t)
    prev = None
    while prev != t:                       # "#[[" e "##[" não escondem a sintaxe depois da limpeza
        prev = t
        t = _RE_TMUX.sub("", t)
    return re.sub(r" {2,}", " ", t).strip()


def larg(c):
    """Largura em células: emoji e ideogramas ocupam 2, marcas combinantes e de formato 0."""
    if c in MARCAS.values():
        return 0
    if unicodedata.category(c) in ("Mn", "Me", "Cf"):
        return 0
    if unicodedata.east_asian_width(c) in "WF" or ord(c) >= 0x1F000:
        return 2
    return 1


def cortar_celulas(t, orc):
    """Trunca por células com … (as marcas de cor não contam e o estilo aberto é fechado)."""
    tot = 0
    for i, c in enumerate(t):
        tot += larg(c)
        if tot > orc:
            corte = i
            while corte > 0 and sum(larg(x) for x in t[:corte]) + 1 > orc:
                corte -= 1
            r = t[:corte].rstrip() + "…"
            if r.count("\x01") + r.count("\x02") + r.count("\x03") > r.count("\x04"):
                r += "\x04"
            return r
    return t


# --------------------------------------------------------------------------------------------------
# Números
# --------------------------------------------------------------------------------------------------
def parse_num(s, entrada="auto"):
    """'5.1234' / '1.234,56' / '1,234.56' / 12 → Decimal, ou None se não for número."""
    if s is None:
        return None
    if isinstance(s, (int, Decimal)):
        return Decimal(s)
    t = str(s).strip().replace(" ", "").replace(" ", "")
    t = re.sub(r"^(R\$|US\$|\$|€|£)", "", t)
    t = t.rstrip("%")
    if not re.fullmatch(r"[+-]?[\d.,]+(?:[eE][+-]?\d+)?", t) or not re.search(r"\d", t):
        return None
    if entrada == "pt":
        t = t.replace(".", "").replace(",", ".")
    elif entrada == "en":
        t = t.replace(",", "")
    else:
        if "," in t and "." in t:
            if t.rfind(",") > t.rfind("."):
                t = t.replace(".", "").replace(",", ".")
            else:
                t = t.replace(",", "")
        elif "," in t:
            # uma vírgula só = decimal ("5,12"); várias = milhar ("1,234,567")
            t = t.replace(",", "") if t.count(",") > 1 else t.replace(",", ".")
        elif t.count(".") > 1:
            t = t.replace(".", "")  # "1.234.567": pontos de milhar
    try:
        return Decimal(t)
    except InvalidOperation:
        return None


ARRED = {"normal": ROUND_HALF_UP, "cima": ROUND_CEILING, "baixo": ROUND_FLOOR, "truncar": ROUND_DOWN}


def formatar_num(x, decimais=None, sep="pt", milhar=True, arred="normal"):
    """Decimal → texto com separadores pt (1.234,56) ou en (1,234.56)."""
    if decimais is not None:
        q = Decimal(1).scaleb(-decimais)
        x = x.quantize(q, rounding=ARRED.get(arred, ROUND_HALF_UP))
    neg = x < 0
    txt = format(abs(x), "f")
    inteiro, _, frac = txt.partition(".")
    if milhar and sep:
        inteiro = "{:,}".format(int(inteiro))
        if sep == "pt":
            inteiro = inteiro.replace(",", ".")
    dec = "," if sep == "pt" else "."
    out = inteiro + (dec + frac if frac else "")
    return ("-" if neg and x != 0 else "") + out


ESCALAS = {"mil": (Decimal(1000), " mil"), "mi": (Decimal(1000000), " mi"), "bi": (Decimal(1000000000), " bi")}


# --------------------------------------------------------------------------------------------------
# Janelas de dias e horas
# --------------------------------------------------------------------------------------------------
_DIAS = {"dom": 0, "seg": 1, "ter": 2, "qua": 3, "qui": 4, "sex": 5, "sab": 6,
         "sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6}


def _dia_idx(tok):
    tok = unicodedata.normalize("NFKD", tok.strip().lower())
    tok = "".join(c for c in tok if not unicodedata.combining(c))
    if tok.isdigit() and 0 <= int(tok) <= 7:
        return int(tok) % 7
    if tok[:3] in _DIAS:
        return _DIAS[tok[:3]]
    raise Erro("dia inválido: %r (use seg, ter, qua, qui, sex, sab, dom ou 0-7)" % tok)


def parse_dias(s):
    """'seg-sex', 'sab,dom', 'sex-seg' (dá a volta na semana) → conjunto de 0 (dom) a 6 (sab)."""
    dias = set()
    for parte in re.split(r"[,\s]+", (s or "").strip()):
        if not parte:
            continue
        if "-" in parte:
            a, b = (_dia_idx(x) for x in parte.split("-", 1))
            i = a
            while True:
                dias.add(i)
                if i == b:
                    break
                i = (i + 1) % 7
        else:
            dias.add(_dia_idx(parte))
    return dias


def _hm(tok):
    m = re.fullmatch(r"(\d{1,2})(?:[:h](\d{2}))?h?", tok.strip().lower())
    if not m:
        raise Erro("hora inválida: %r (use 10, 9:30, 17h45)" % tok)
    h, mi = int(m.group(1)), int(m.group(2) or 0)
    if h > 24 or mi > 59 or (h == 24 and mi):
        raise Erro("hora fora do intervalo: %r" % tok)
    return h * 60 + mi


def parse_horas(s):
    """'10-18' = das 10:00 até 17:59; '9:30-12,14-17:45'; '22-6' atravessa a meia-noite."""
    faixas = []
    for parte in re.split(r"[,;]+", (s or "").strip()):
        parte = parte.strip()
        if not parte:
            continue
        if "-" not in parte:
            raise Erro("faixa de horas inválida: %r (use 10-18)" % parte)
        a, b = parte.split("-", 1)
        faixas.append((_hm(a), _hm(b)))
    return faixas


def na_janela(ts, dias_txt, horas_txt, cfg=None):
    """True se o instante cai nos dias e nas horas pedidos (vazio = sempre)."""
    if not dias_txt and not horas_txt:
        return True
    dt = dt_local(ts, cfg)
    if dias_txt and ((dt.weekday() + 1) % 7) not in parse_dias(dias_txt):
        return False
    if horas_txt:
        m = dt.hour * 60 + dt.minute
        ok = False
        for a, b in parse_horas(horas_txt):
            if (a <= b and a <= m < b) or (a > b and (m >= a or m < b)):
                ok = True
        return ok
    return True


# --------------------------------------------------------------------------------------------------
# Modelos ({variável}) — só troca o que é conhecido; o resto (chaves de um JSON no corpo) fica intacto
# --------------------------------------------------------------------------------------------------
_RE_VAR = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)\}")


def vars_tempo(ts, cfg=None):
    dt = dt_local(ts, cfg)
    return {
        "data": dt.strftime("%Y-%m-%d"), "hoje": dt.strftime("%Y-%m-%d"),
        "ontem": (dt - timedelta(days=1)).strftime("%Y-%m-%d"),
        "amanha": (dt + timedelta(days=1)).strftime("%Y-%m-%d"),
        "data_br": dt.strftime("%d/%m/%Y"), "ano": dt.strftime("%Y"), "mes": dt.strftime("%m"),
        "dia": dt.strftime("%d"), "hora": dt.strftime("%H:%M"), "epoch": str(int(ts)),
    }


def aplicar_vars(txt, vars_, codificar=False, seguro="-_.~"):
    def troca(m):
        k = m.group(1)
        if k not in vars_:
            return m.group(0)
        v = str(vars_[k])
        return urllib.parse.quote(v, safe=seguro) if codificar else v
    return _RE_VAR.sub(troca, txt or "")


def aplicar_vars_url(url, vars_):
    """Variáveis numa URL: os valores são codificados (%xx), exceto uma variável que seja a URL inteira
    (`url={feed}`), que entra como veio."""
    m = _RE_VAR.match(url or "")
    if m and m.group(1) in vars_:
        return str(vars_[m.group(1)]) + aplicar_vars(url[m.end():], vars_, codificar=True, seguro="-_.~/")
    return aplicar_vars(url, vars_, codificar=True, seguro="-_.~/")   # "dono/nome" (repositório) fica com a barra


def vars_sobrando(txt, vars_):
    return sorted({m for m in _RE_VAR.findall(txt or "") if m not in vars_})


# --------------------------------------------------------------------------------------------------
# Arquivo da fonte: leitura, validação e escrita
# --------------------------------------------------------------------------------------------------
def chave_valida(k):
    return k in TIPO or bool(re.fullmatch(r"(?:campo|var)\.[A-Za-z_][A-Za-z0-9_]{0,31}", k))


def _desaspar(v):
    """"  texto com espaços nas pontas" entre aspas guarda os espaços (prefixo, sufixo, separador)."""
    if len(v) >= 2 and v[0] == '"' and v[-1] == '"' and (v[1:-1] != v[1:-1].strip()):
        return v[1:-1]
    return v


def ler_arquivo_conf(caminho):
    d = {}
    for linha in ler_texto(caminho).splitlines():
        l = linha.strip()
        if not l or l.startswith("#") or "=" not in l:
            continue
        k, v = l.split("=", 1)
        k, v = k.strip(), _desaspar(v.strip())
        if k in REPETE:
            d.setdefault(k, []).append(v)
        else:
            d[k] = v
    return d


def serializar(d):
    """Dicionário → texto do .conf (campos na ordem do esquema, agrupados; listas em linhas repetidas)."""
    out = ["# tt letreiro — fonte do letreiro (versao=%d). Edite aqui, por `tt --letreiro-editar` ou pelo painel." % VERSAO_FORMATO,
           "# Segredos NUNCA entram neste arquivo: use segredo=@arquivo (o valor fica em ~/.secrets)."]
    d = dict(d)
    d["versao"] = str(VERSAO_FORMATO)
    grupo_ant = None
    for k, _t, _p, grupo, _dsc in CAMPOS:
        if k not in d or d[k] in ([], None):
            continue
        if grupo != grupo_ant:
            out.append("")
            out.append("# " + grupo)
            grupo_ant = grupo
        for v in (d[k] if isinstance(d[k], list) else [d[k]]):
            v = str(v).replace("\n", " ")
            out.append("%s=%s" % (k, '"%s"' % v if v != v.strip() else v))
    extras = sorted(k for k in d if k not in TIPO)
    if extras:
        out.append("")
        out.append("# campos extras e variáveis")
        for k in extras:
            out.append("%s=%s" % (k, str(d[k]).replace("\n", " ")))
    return "\n".join(out) + "\n"


def _tipo_num(tipo):
    partes = tipo.split(":")
    lo = float(partes[1]) if len(partes) > 1 and partes[1] != "" else None
    hi = float(partes[2]) if len(partes) > 2 and partes[2] != "" else None
    vazio = len(partes) > 3 and partes[3] == "vazio"
    return lo, hi, vazio


def normalizar_valor(k, v):
    """Valida o valor de UMA chave e devolve a forma canônica (texto). Levanta Erro com mensagem clara."""
    t = TIPO.get(k, "str")
    if t == "lista":
        return str(v).strip()
    v = str(v)
    if t == "str":
        return v if v != v.strip() and v.strip() else v.strip()
    v = v.strip()
    if t == "bool":
        if v.lower() in ("1", "sim", "s", "true", "on", "yes", "y"):
            return "1"
        if v.lower() in ("0", "nao", "não", "n", "false", "off", "no"):
            return "0"
        raise Erro("%s: use 1 ou 0 (recebi %r)" % (k, v))
    if t.startswith("enum:"):
        op = t[5:].split("|")
        if v in op or (v.lower() in op):
            return v if v in op else v.lower()
        if v == "" and "" in op:
            return ""
        raise Erro("%s: use um de %s (recebi %r)" % (k, "/".join(o for o in op if o) or "?", v))
    if t.startswith("int"):
        lo, hi, vazio = _tipo_num(t)
        if v == "" and vazio:
            return ""
        if not re.fullmatch(r"-?\d+", v):
            raise Erro("%s: precisa ser um número inteiro (recebi %r)" % (k, v))
        n = int(v)
        if (lo is not None and n < lo) or (hi is not None and n > hi):
            raise Erro("%s: fora do intervalo %g a %g (recebi %d)" % (k, lo if lo is not None else float("-inf"), hi if hi is not None else float("inf"), n))
        return str(n)
    if t.startswith("float"):
        lo, hi, _ = _tipo_num(t)
        try:
            x = float(v.replace(",", "."))
        except ValueError:
            raise Erro("%s: precisa ser um número (recebi %r)" % (k, v))
        if (lo is not None and x < lo) or (hi is not None and x > hi):
            raise Erro("%s: fora do intervalo %g a %g (recebi %g)" % (k, lo, hi, x))
        return ("%g" % x)
    return v


def _ip_literal_privado(host):
    try:
        ip = ipaddress.ip_address(host.strip("[]"))
    except ValueError:
        return False
    return not _ip_publico(ip) and not (modo_teste() and ip.is_loopback)


def validar_fonte(d, completo=True):
    """Valida um dicionário de fonte. Devolve (normalizado, erros, avisos). `completo=False` aceita uma
    sobreposição parcial (nativa ou override desta máquina)."""
    erros, avisos, n = [], [], {}
    for k, v in d.items():
        if not chave_valida(k):
            erros.append("chave desconhecida: %s" % k)
            continue
        try:
            if isinstance(v, list):
                n[k] = [normalizar_valor(k, x) for x in v if str(x).strip()]
            elif k in TIPO or k.startswith(("campo.", "var.")):
                n[k] = normalizar_valor(k, v) if k in TIPO else str(v).strip()
        except Erro as e:
            erros.append(str(e))
    g = lambda k: n.get(k, PADRAO.get(k, ""))
    origem = g("origem")
    if completo or "url" in n:
        url = n.get("url", "")
        if origem == "rede":
            if completo and not url and "_sub" not in d:
                erros.append("url: falta o endereço da fonte")
            if url:
                vars_u = vars_tempo(agora(), None)
                vars_u.update({k[4:]: x for k, x in n.items() if k.startswith("var.")})
                vars_u["segredo"] = "x"
                try:
                    u = urllib.parse.urlsplit(aplicar_vars_url(url, vars_u))
                except ValueError:
                    erros.append("url: endereço inválido")
                    u = None
                if u is not None:
                    if u.scheme not in ("http", "https"):
                        erros.append("url: só http(s) (recebi %r)" % u.scheme)
                    elif u.scheme == "http":
                        if g("permitir_http") != "1":
                            erros.append("url: http:// não é criptografado — use https://, ou permitir_http=1 (por sua conta e risco)")
                        else:
                            avisos.append("url: http:// sem criptografia (permitir_http=1)")
                    if u.username or u.password or "@" in (u.netloc or ""):
                        erros.append("url: usuário/senha dentro do endereço não são aceitos (use auth=basic e segredo=@arquivo)")
                    if u.hostname and _ip_literal_privado(u.hostname):
                        erros.append("url: destino local ou de rede privada bloqueado (segurança)")
                    elif u.hostname and not modo_teste() and (u.hostname == "localhost" or u.hostname.endswith((".localhost", ".local", ".internal"))):
                        erros.append("url: destino local bloqueado (segurança)")
                    for qk, qv in urllib.parse.parse_qsl(u.query, keep_blank_values=True):
                        if RE_QUERY_SECRETA.match(qk) and qv and "{segredo}" not in qv:
                            erros.append("url: a chave '%s' não pode ficar na URL — use auth=query, auth_nome=%s e segredo=@arquivo" % (qk, qk))
    for h in n.get("header", []):
        if ":" not in h:
            erros.append("header: use 'Nome: valor' (recebi %r)" % h)
            continue
        hk, hv = (x.strip() for x in h.split(":", 1))
        if RE_HEADER_SECRETO.match(hk) and not (hv.startswith("@") or "{segredo}" in hv):
            erros.append("header %s: credencial literal não é aceita — use auth=header|bearer|basic e segredo=@arquivo" % hk)
        if hv.startswith("@"):
            try:
                ref_segredo(hv)
            except Erro as e:
                erros.append("header %s: %s" % (hk, e))
    for q in n.get("query", []):
        if "=" not in q:
            erros.append("query: use 'nome=valor' (recebi %r)" % q)
            continue
        qk, qv = q.split("=", 1)
        if RE_QUERY_SECRETA.match(qk.strip()) and qv.strip() and not (qv.strip().startswith("@") or "{segredo}" in qv):
            erros.append("query %s: credencial literal não é aceita — use auth=query e segredo=@arquivo" % qk)
        if qv.strip().startswith("@"):
            try:
                ref_segredo(qv.strip())
            except Erro as e:
                erros.append("query %s: %s" % (qk, e))
    auth = g("auth")
    if auth != "nenhuma":
        if not g("segredo") and (completo or "auth" in n):
            erros.append("auth=%s precisa de segredo=@arquivo (o valor fica em ~/.secrets)" % auth)
        if auth in ("header", "query") and not g("auth_nome") and (completo or "auth" in n):
            avisos.append("auth_nome vazio: usarei %s" % ("X-API-Key" if auth == "header" else "api_key"))
    if n.get("segredo"):
        try:
            ref_segredo(n["segredo"])
        except Erro as e:
            erros.append("segredo: %s" % e)
    if g("proxy"):
        pu = urllib.parse.urlsplit(g("proxy"))
        if pu.scheme not in ("http",) or not pu.hostname:
            erros.append("proxy: use http://host:porta")
        elif pu.username or pu.password:
            erros.append("proxy: usuário/senha no proxy não são aceitos")
    if g("tls_verificar") == "0":
        avisos.append("tls_verificar=0: o certificado do servidor NÃO será verificado")
    if "_sub" not in d:
        if g("formato") == "regex" and n.get("caminho"):
            try:
                re.compile(n["caminho"])
            except re.error as e:
                erros.append("caminho (regex) inválido: %s" % e)
        if g("formato") == "json" and n.get("caminho") and "{" not in n["caminho"]:
            try:
                _tokens_json(n["caminho"])
            except Erro as e:
                erros.append(str(e))
        if g("formato") in ("xml", "rss", "atom") and n.get("caminho") and "{" not in n["caminho"]:
            try:
                ET.Element("x").findall(_xpath_final(n["caminho"], None)[0])
            except (SyntaxError, KeyError, ValueError) as e:
                erros.append("caminho (XPath) inválido: %s" % e)
    for k in ("dias", "horas", "mostrar_dias", "mostrar_horas"):
        if n.get(k):
            try:
                (parse_dias if "dias" in k else parse_horas)(n[k])
            except Erro as e:
                erros.append("%s: %s" % (k, e))
    for c in n.get("condicao", []):
        try:
            _parse_condicao(c)
        except Erro as e:
            erros.append(str(e))
    for t in n.get("traduzir", []):
        if ">" not in t:
            erros.append("traduzir: use 'origem>destino' (recebi %r)" % t)
    if g("clique") == "url" and not g("clique_alvo") and (completo or "clique" in n):
        avisos.append("clique=url sem clique_alvo: abrirei o campo {link} (se existir) ou a url da fonte")
    if g("clique") == "painel" and n.get("clique_alvo") and n["clique_alvo"] not in PAINEIS:
        erros.append("clique_alvo: painel desconhecido (use %s)" % ", ".join(PAINEIS))
    if g("origem") == "tt" and completo and g("dado") not in DADOS_TT:
        erros.append("dado: use %s" % " ou ".join(DADOS_TT))
    if g("origem") == "lista" and completo and not n.get("item"):
        erros.append("origem=lista precisa de ao menos um item=")
    if "{" in g("modelo") and completo:
        conhecidas = set(VARS_MODELO) | {k[6:] for k in n if k.startswith("campo.")} | {k[4:] for k in n if k.startswith("var.")}
        sobra = vars_sobrando(g("modelo"), {x: 1 for x in conhecidas})
        if sobra:
            avisos.append("modelo usa {%s}, que não existe (variáveis: %s)" % (", ".join(sobra), " ".join("{%s}" % v for v in VARS_MODELO)))
    return n, erros, avisos


PAINEIS = ("tarefas", "email", "calendario", "notificacoes", "letreiro", "central")
DADOS_TT = ("tarefas-atrasadas", "emails-nao-lidos")
VARS_MODELO = ("icone", "rotulo", "valor", "var", "seta", "pct", "nome", "hora", "data", "item")


# --------------------------------------------------------------------------------------------------
# Fontes nativas, catálogo de um clique e resolução da fonte efetiva
# --------------------------------------------------------------------------------------------------
FRASES = [
    "“A simplicidade é o último grau de sofisticação.” — Leonardo da Vinci",
    "“Feito é melhor que perfeito.”",
    "“O obstáculo é o caminho.” — Marco Aurélio",
    "“Quem controla o passado controla o futuro.” — Orwell",
    "“Deixe o código melhor do que o encontrou.”",
    "“Nada é tão permanente quanto uma solução temporária.”",
]

NATIVAS = {
    "dolar": {
        "descricao": "Dólar comercial em reais (AwesomeAPI, sem chave)", "tags": "moeda",
        "url": "https://economia.awesomeapi.com.br/json/last/USD-BRL", "formato": "json",
        "caminho": "USDBRL.bid", "variacao": "USDBRL.pctChange", "icone": "💵", "rotulo": "dólar",
        "moeda": "R$", "decimais": "3", "separador": "pt", "arredondar": "truncar", "ttl": "600", "ordem": "10",
    },
    "frases": {
        "descricao": "Frases (lista embutida; troque pelos seus item=)", "tags": "curiosidade",
        "origem": "lista", "item": FRASES, "modelo": "{valor}", "ttl": "600", "ordem": "20",
    },
    "noticias": {
        "descricao": "Manchetes do g1 e da BBC World (RSS, sem chave)", "tags": "noticias",
        "formato": "rss", "modelo": "{icone} {valor}", "ttl": "900", "ordem": "30",
        "_sub": [
            {"url": "https://g1.globo.com/rss/g1/", "icone": "📰", "itens": "2"},
            {"url": "https://feeds.bbci.co.uk/news/world/rss.xml", "icone": "🌍", "itens": "2"},
        ],
    },
}

# Fontes de fábrica e modelos: letreiro-catalogo.json (ao lado deste módulo). As de fábrica entram em NATIVAS
# DESLIGADAS (ativa=0): aparecem na lista do painel, mas não buscam nada até você ligar. Os modelos
# (CATALOGO) perguntam o que falta (um repositório, um par de moedas, um feed…) e criam uma fonte sua.
ORIGINAIS = ("dolar", "frases", "noticias")          # as três que vêm ligadas de fábrica
ARQ_CATALOGO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "letreiro-catalogo.json")
ARQ_OCULTAS = os.path.join(DIR_FONTES, ".ocultas")   # fontes de fábrica que você tirou da lista (nome por linha)


def _carregar_catalogo():
    try:
        with open(ARQ_CATALOGO, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return [], {}, {}
    fab = {n: e for n, e in (d.get("fabrica") or {}).items() if RE_NOME.match(n) and isinstance(e, dict) and isinstance(e.get("conf"), dict)}
    return d.get("categorias") or [], fab, d.get("modelos") or {}


CATEGORIAS, FABRICA, MODELOS = _carregar_catalogo()
for _n, _e in FABRICA.items():
    if _n not in NATIVAS:
        NATIVAS[_n] = {**{k: (list(v) if isinstance(v, list) else v) for k, v in _e["conf"].items()}, "ativa": "0"}
CAT_ROTULO = {c[0]: "%s %s" % (c[1], c[2]) for c in CATEGORIAS if len(c) >= 3}
CAT_ROTULO.update({"minhas": "🧩 Minhas fontes", "outras": "📦 Outras"})
CATALOGO = {i: (m.get("descricao", i), m["conf"], [tuple(p) for p in m.get("perguntas", [])])
            for i, m in MODELOS.items() if isinstance(m.get("conf"), dict)}


def categoria_de(nome, f, origem):
    """Categoria no painel: a 1ª etiqueta (tags) das fontes de fábrica; as suas ficam em 'minhas'."""
    if origem != "nativa":
        return "minhas"
    t = [x.strip() for x in (f.get("tags") or "").split(",") if x.strip()]
    return t[0] if t and t[0] in CAT_ROTULO else "outras"


def ler_ocultas():
    return {l.strip() for l in ler_texto(ARQ_OCULTAS).splitlines() if RE_NOME.match(l.strip())}


def gravar_ocultas(conj):
    escrever_atomico(ARQ_OCULTAS, "".join(n + "\n" for n in sorted(conj)), 0o644)


def desocultar(nome):
    o = ler_ocultas()
    if nome in o:
        o.discard(nome)
        gravar_ocultas(o)


def pode_ocultar(nome):
    return nome in NATIVAS and nome not in ORIGINAIS


def restaurar_fonte(nome):
    """Fonte de fábrica: apaga o que você mudou (arquivo e sobrescrita desta máquina) e a deixa na lista."""
    _nome_valido(nome)
    if nome not in NATIVAS:
        raise Erro("%s não é de fábrica: não tem padrão para voltar" % nome)
    remover_fonte(nome)
    desocultar(nome)
    compilar()
    return ["%s: voltou ao padrão de fábrica" % nome]


def legado_lista(cfg):
    """Lista de `indicadores=` ainda NÃO aplicada ao novo formato (ou None). Nomes na ordem escrita."""
    if "indicadores" not in cfg:
        return None
    v = cfg["indicadores"].strip()
    aplicado = ler_texto(ARQ_MIGRADO).strip() if os.path.exists(ARQ_MIGRADO) else None
    if aplicado is not None and aplicado == v:
        return None
    if v == "0":
        return []                           # indicadores=0: o letreiro todo desligado
    if v == "":
        return ["dolar", "frases", "noticias"]  # vazio = o padrão de fábrica (como sempre foi)
    return [x for x in v.replace(",", " ").split() if x]


def legado_linha(cfg, nome):
    v = cfg.get("indicador_" + nome, "")
    return v or None


def converter_legado(nome, linha):
    """indicador_NOME=URL ;; rótulo ;; caminho ;; ttl ;; Header: valor  → conf equivalente (e o segredo a mover)."""
    p = [x.strip() for x in re.split(r"\s*;;\s*", linha)]
    url = p[0] if p else ""
    rot = p[1] if len(p) > 1 else ""
    cam = p[2] if len(p) > 2 else ""
    ttl = p[3] if len(p) > 3 and p[3].isdigit() else "600"
    hdr = p[4] if len(p) > 4 else ""
    d = {"descricao": "Migrada de indicador_%s= do config" % nome, "url": url, "rotulo": rot, "ttl": str(max(10, int(ttl))),
         "modelo": "{rotulo} {valor}"}
    if cam == "-" or cam == "":
        d["formato"] = "texto"
    else:
        d["formato"] = "json"
        d["caminho"] = cam
    segredo = None
    if hdr and ":" in hdr:
        hk, hv = (x.strip() for x in hdr.split(":", 1))
        if hv.startswith("@"):
            d["header"] = ["%s: %s" % (hk, hv)]
        elif hv:
            segredo = (hk, hv)
            d["header"] = ["%s: @letreiro-%s" % (hk, nome)]
    return d, segredo


def _nome_valido(nome):
    if not RE_NOME.match(nome or ""):
        raise Erro("nome inválido: %r (use minúsculas, números, - e _; até 32 caracteres)" % nome)
    return nome


def arq_fonte(nome):
    return os.path.join(DIR_FONTES, _nome_valido(nome) + ".conf")


def arq_local(nome):
    return os.path.join(DIR_LOCAL, _nome_valido(nome) + ".conf")


def nomes_conhecidos(cfg=None, ocultas=False):
    cfg = cfg if cfg is not None else ler_conf()
    nomes = set(NATIVAS)
    for pasta in (DIR_FONTES, DIR_LOCAL):
        try:
            for f in os.listdir(pasta):
                if f.endswith(".conf") and RE_NOME.match(f[:-5]):
                    nomes.add(f[:-5])
        except OSError:
            pass
    for k in cfg:
        if k.startswith("indicador_") and RE_NOME.match(k[10:]):
            nomes.add(k[10:])
    if not ocultas:
        nomes -= {n for n in ler_ocultas() if pode_ocultar(n)}
    return sorted(nomes)


def fonte_efetiva(nome, cfg=None):
    """A fonte como vale AQUI: nativa ← linha antiga do config ← NOME.conf ← sobrescrita desta máquina.
    Devolve (dicionário, origem) ou (None, None). `origem` = nativa | arquivo | legado."""
    cfg = cfg if cfg is not None else ler_conf()
    base, origem = {}, None
    arq = ler_arquivo_conf(arq_fonte(nome)) if os.path.exists(arq_fonte(nome)) else None
    leg = legado_linha(cfg, nome)
    if nome in NATIVAS:
        base = {k: (list(v) if isinstance(v, list) else v) for k, v in NATIVAS[nome].items()}
        origem = "nativa"
    elif arq is None and leg is None and not os.path.exists(arq_local(nome)):
        return None, None
    if leg is not None and arq is None and nome not in NATIVAS:
        base, _s = converter_legado(nome, leg)
        origem = "legado"
    if arq is not None:
        if origem is None:
            origem = "arquivo"
        if "url" in arq:
            base.pop("_sub", None)
        base.update(arq)
    pend = legado_lista(cfg)
    if pend is not None and (nome in NATIVAS or leg is not None):
        # a lista antiga indicadores= ainda não foi aplicada: vale como se já tivesse sido
        base["ativa"] = "1" if nome in pend else "0"
        if nome in pend:
            base["ordem"] = str((pend.index(nome) + 1) * 10)
    elif leg is not None and arq is None and nome not in NATIVAS:
        base["ativa"] = "0"  # linha antiga que não está em indicadores=: nunca esteve ligada
    loc = ler_arquivo_conf(arq_local(nome)) if os.path.exists(arq_local(nome)) else {}
    if loc:
        if "url" in loc:
            base.pop("_sub", None)
        base.update(loc)
        origem = origem or "arquivo"
    if origem is None:
        return None, None
    if base.get("formato") in ("rss", "atom") and "origem" not in base:
        base["origem"] = "rede"
    base.pop("versao", None)
    return base, origem


def efetiva_completa(base):
    """Preenche os padrões do esquema (sem tocar nas chaves de lista vazias)."""
    f = dict(PADRAO)
    for k in REPETE:
        f[k] = []
    f.update(base)
    return f


def vale_aqui(f, cfg=None):
    """Perfil e máquinas: a fonte vale NESTA máquina?"""
    perfil = f.get("perfil", "todos")
    if perfil not in ("", "todos") and perfil != perfil_maquina():
        return False
    ms = [m.strip() for m in f.get("maquinas", "").split(",") if m.strip()]
    if ms:
        eu = maquina_nome()
        incl = [m for m in ms if not m.startswith("!")]
        excl = [m[1:] for m in ms if m.startswith("!")]
        if eu in excl:
            return False
        if incl and eu not in incl:
            return False
    return True


# --------------------------------------------------------------------------------------------------
# Gravação: criar, alterar, remover (com a hora da mudança para a propagação)
# --------------------------------------------------------------------------------------------------
def hora_mudanca():
    v = os.environ.get("TT_HORA_AGORA", "")
    return str(int(float(v))) if v else str(int(agora()))


def ler_removidas():
    d = {}
    for l in ler_texto(ARQ_REMOVIDAS).splitlines():
        p = l.split("\t")
        if len(p) == 2 and RE_NOME.match(p[0]) and p[1].isdigit():
            d[p[0]] = int(p[1])
    return d


def gravar_removidas(d):
    escrever_atomico(ARQ_REMOVIDAS, "".join("%s\t%d\n" % (k, d[k]) for k in sorted(d)), 0o644)


def gravar_fonte(nome, d, local=False):
    """Grava o arquivo da fonte (ou a sobrescrita desta máquina). Fontes globais ganham `mudada` e saem
    da lista de removidas."""
    _nome_valido(nome)
    d = dict(d)
    desocultar(nome)
    if local:
        escrever_atomico(arq_local(nome), serializar(d), 0o644)
        return
    if d.get("escopo") == "global":
        d["mudada"] = hora_mudanca()
        rem = ler_removidas()
        if nome in rem:
            del rem[nome]
            gravar_removidas(rem)
    escrever_atomico(arq_fonte(nome), serializar(d), 0o644)


def criar_fonte(nome, kv, local=False, sobrescrever=False):
    """Cria uma fonte nova a partir de pares chave=valor. Devolve (erros, avisos)."""
    _nome_valido(nome)
    if not sobrescrever and (os.path.exists(arq_fonte(nome)) or nome in NATIVAS):
        if nome in NATIVAS:
            raise Erro("%s é uma fonte de fábrica (tt --letreiro-ativar %s liga; tt --letreiro-editar %s ajusta) — ou escolha outro nome" % (nome, nome, nome))
        raise Erro("já existe uma fonte chamada %s (use --letreiro-editar, ou outro nome)" % nome)
    d = juntar_kv({}, kv)
    n, erros, avisos = validar_fonte(d, completo=nome not in NATIVAS)
    if erros:
        return erros, avisos
    gravar_fonte(nome, n, local=local)
    compilar()
    return [], avisos


def juntar_kv(base, kv, nativa=None):
    """Aplica pares chave=valor (chave repetida em lista acrescenta; `-chave` remove; `chave=` esvazia).
    `nativa` = a definição de fábrica: nela, `chave=` grava um vazio explícito (para desfazer o padrão)."""
    d = {k: (list(v) if isinstance(v, list) else v) for k, v in base.items()}
    for item in kv:
        if item.startswith("-") and "=" not in item and chave_valida(item[1:]):
            d.pop(item[1:], None)
            continue
        if "=" not in item:
            raise Erro("esperava chave=valor (recebi %r)" % item)
        k, v = item.split("=", 1)
        k = k.strip()
        v = _desaspar(v.strip())
        if not chave_valida(k):
            raise Erro("chave desconhecida: %s (veja `letreiro-fontes.py campos`)" % k)
        if k in REPETE:
            if v.strip() == "":
                d.pop(k, None)
            else:
                d.setdefault(k, []).append(v if v != v.strip() else v.strip())
        elif v.strip() == "" and v == "":
            if nativa and nativa.get(k) not in (None, "", []):
                d[k] = ""
            else:
                d.pop(k, None)
        else:
            d[k] = v
    return d


def editar_fonte(nome, kv, local=False):
    """Altera chaves de uma fonte existente (ou personaliza uma nativa). Devolve (erros, avisos)."""
    _nome_valido(nome)
    existe = os.path.exists(arq_fonte(nome))
    if not existe and nome not in NATIVAS and not os.path.exists(arq_local(nome)) and legado_linha(ler_conf(), nome) is None:
        raise Erro("não existe a fonte %s (tt --letreiro-listar)" % nome)
    if not existe and nome not in NATIVAS and not local:
        # fonte só no config antigo: materializa antes de editar
        migrar()
    destino = arq_local(nome) if local else arq_fonte(nome)
    atual = ler_arquivo_conf(destino) if os.path.exists(destino) else {}
    d = juntar_kv(atual, kv, NATIVAS.get(nome))
    completo = (nome not in NATIVAS) and not local
    n, erros, avisos = validar_fonte(d, completo=completo)
    if erros:
        return erros, avisos
    if completo and not n.get("url") and n.get("origem", "rede") == "rede":
        return ["url: falta o endereço da fonte"], avisos
    gravar_fonte(nome, n, local=local)
    compilar()
    return [], avisos


def remover_fonte(nome):
    """Apaga o arquivo da fonte. Nativa: só tira a personalização. Global: deixa lápide para a propagação."""
    _nome_valido(nome)
    msg = []
    arq = arq_fonte(nome)
    f = ler_arquivo_conf(arq) if os.path.exists(arq) else {}
    if os.path.exists(arq):
        os.unlink(arq)
        msg.append("arquivo removido")
        if f.get("escopo") == "global":
            rem = ler_removidas()
            rem[nome] = int(hora_mudanca())
            gravar_removidas(rem)
            msg.append("lápide gravada (a remoção se propaga)")
    if os.path.exists(arq_local(nome)):
        os.unlink(arq_local(nome))
        msg.append("sobrescrita desta máquina removida")
    if legado_linha(ler_conf(), nome) is not None:
        msg.append("a linha antiga indicador_%s= do config continua lá (apague-a à mão)" % nome)
    if pode_ocultar(nome):
        o = ler_ocultas()
        if nome in o and not msg:
            msg.append("já estava fora da lista (tt --letreiro-catalogo %s traz de volta)" % nome)
        else:
            o.add(nome)
            gravar_ocultas(o)
            msg.append("%s é de fábrica: voltou ao padrão e saiu da lista (tt --letreiro-catalogo %s traz de volta)" % (nome, nome))
    elif nome in NATIVAS:
        msg.append("%s é nativa: voltou ao padrão (use --letreiro-desativar para tirá-la da roda)" % nome)
    if not msg:
        raise Erro("não existe a fonte %s" % nome)
    for ext in ("", ".itens", ".meta"):
        try:
            os.unlink(os.path.join(DIR_TICKER, nome + ext))
        except OSError:
            pass
    compilar()
    return msg


def duplicar_fonte(origem, novo):
    _nome_valido(novo)
    f, _o = fonte_efetiva(origem)
    if f is None:
        raise Erro("não existe a fonte %s" % origem)
    if os.path.exists(arq_fonte(novo)) or novo in NATIVAS:
        raise Erro("já existe uma fonte chamada %s" % novo)
    d = {k: v for k, v in f.items() if k != "_sub" and k != "mudada"}
    if "_sub" in f:
        raise Erro("%s é composta (várias fontes em uma); personalize-a com url= antes de duplicar" % origem)
    d["descricao"] = ("Cópia de %s. " % origem) + d.get("descricao", "")
    try:
        d["ordem"] = str(int(d.get("ordem", "100")) + 1)
    except ValueError:
        pass
    n, erros, _a = validar_fonte(d, completo=True)
    if erros:
        raise Erro("; ".join(erros))
    gravar_fonte(novo, n)
    compilar()


def rascunho_de(nome):
    """A fonte efetiva como rascunho editável (nativa composta: sem _sub)."""
    f, _o = fonte_efetiva(nome)
    if f is None:
        raise Erro("não existe a fonte %s" % nome)
    return {k: v for k, v in f.items() if k not in ("_sub", "mudada", "versao")}


def salvar_rascunho(nome, d, local=False):
    """Grava um rascunho completo numa fonte: nova (cria), comum (troca o arquivo) ou nativa/local (só a
    diferença para o padrão — a personalização não congela a definição de fábrica). Devolve (erros, avisos)."""
    _nome_valido(nome)
    existe = os.path.exists(arq_fonte(nome)) or nome in NATIVAS
    if not existe:
        return criar_fonte(nome, ["%s=%s" % (k, x) for k, v in d.items() for x in (v if isinstance(v, list) else [v])], local=local)
    n, erros, avisos = validar_fonte(d, completo=(nome not in NATIVAS and not local))
    if erros:
        return erros, avisos
    if local or nome in NATIVAS:
        base = {}
        if nome in NATIVAS:
            base = {k: v for k, v in NATIVAS[nome].items() if k != "_sub"}
        if local and os.path.exists(arq_fonte(nome)):
            base.update(ler_arquivo_conf(arq_fonte(nome)))
        diff = {}
        for k, v in n.items():
            if base.get(k) != v:
                diff[k] = v
        for k in base:
            if k not in n and k not in ("mudada", "versao"):
                diff[k] = [] if k in REPETE else ""
        diff = {k: v for k, v in diff.items() if not (v == [] and k in REPETE and k not in base)}
        if "url" in diff and nome in NATIVAS and "_sub" in NATIVAS[nome]:
            pass
        gravar_fonte(nome, diff, local=local)
    else:
        antigo = ler_arquivo_conf(arq_fonte(nome))
        if antigo.get("escopo") == "global" and "escopo" not in n:
            n["escopo"] = "global"
        gravar_fonte(nome, n)
    compilar()
    return [], avisos


def ativar_fonte(nome, ligar, local=False):
    return editar_fonte(nome, ["ativa=%s" % ("1" if ligar else "0")], local=local)


def listar_ordenadas(cfg=None, so_ativas=False, so_ocultas=False):
    """[(nome, efetiva_completa, origem)] ordenadas por ordem, nome. As de fábrica que você tirou da lista só
    aparecem com so_ocultas."""
    cfg = cfg if cfg is not None else ler_conf()
    out = []
    ocultas = {n for n in ler_ocultas() if pode_ocultar(n)}
    for nome in (sorted(ocultas) if so_ocultas else nomes_conhecidos(cfg)):
        base, origem = fonte_efetiva(nome, cfg)
        if base is None:
            continue
        f = efetiva_completa(base)
        if so_ativas and (f["ativa"] != "1" or not vale_aqui(f, cfg)):
            continue
        out.append((nome, f, origem))
    def chave(x):
        try:
            return (int(x[1]["ordem"]), x[0])
        except ValueError:
            return (100, x[0])
    return sorted(out, key=chave)


def mover_fonte(nome, destino):
    """Reordena a roda: destino = +1/-1 (um passo), 'inicio', 'fim' ou uma posição (1..N)."""
    todas = [x for x in listar_ordenadas() if x[1]["ativa"] == "1" or x[0] == nome]
    nomes = [x[0] for x in todas]
    if nome not in nomes:
        raise Erro("não existe a fonte %s" % nome)
    i = nomes.index(nome)
    if destino in ("+1", "-1"):
        j = max(0, min(len(nomes) - 1, i + int(destino)))
    elif destino == "inicio":
        j = 0
    elif destino == "fim":
        j = len(nomes) - 1
    elif destino.isdigit():
        j = max(0, min(len(nomes) - 1, int(destino) - 1))
    else:
        raise Erro("destino inválido: %s (+1, -1, inicio, fim ou posição)" % destino)
    nomes.insert(j, nomes.pop(i))
    for k, n in enumerate(nomes):
        nova = str((k + 1) * 10)
        f, _o = fonte_efetiva(n)
        if f is not None and efetiva_completa(f)["ordem"] != nova:
            editar_fonte(n, ["ordem=" + nova])
    compilar()
    return nomes


# --------------------------------------------------------------------------------------------------
# Migração: indicador_NOME= e indicadores= → arquivos em ~/.config/tt/letreiro/
# --------------------------------------------------------------------------------------------------
def migrar():
    """Idempotente. Devolve a lista de mensagens do que fez."""
    cfg = ler_conf()
    msgs = []
    pend = legado_lista(cfg)
    nomes_leg = [k[10:] for k in cfg if k.startswith("indicador_") and RE_NOME.match(k[10:])]
    lista = pend if pend is not None else []
    for nome in nomes_leg:
        if os.path.exists(arq_fonte(nome)) or nome in NATIVAS:
            continue
        d, segredo = converter_legado(nome, cfg["indicador_" + nome])
        if segredo:
            hk, hv = segredo
            segredo_gravar("letreiro-" + nome, hv)
            msgs.append("%s: o segredo do header %s foi movido para ~/.secrets/letreiro-%s (modo 600)" % (nome, hk, nome))
            limpar_linha_legada(nome, cfg["indicador_" + nome])
        d["ativa"] = "1" if (pend is not None and nome in pend) else "0"
        if pend is not None and nome in pend:
            d["ordem"] = str((pend.index(nome) + 1) * 10)
        n, erros, _a = validar_fonte(d, completo=True)
        if erros:
            msgs.append("%s: não migrada (%s)" % (nome, "; ".join(erros)))
            continue
        gravar_fonte(nome, n)
        msgs.append("%s: migrada de indicador_%s= para letreiro/%s.conf" % (nome, nome, nome))
    if pend is not None:
        for nome in set(NATIVAS) | set(nomes_leg):
            if (nome in NATIVAS and (nome in ORIGINAIS or nome in pend)) or os.path.exists(arq_fonte(nome)):
                ja = ler_arquivo_conf(arq_fonte(nome)) if os.path.exists(arq_fonte(nome)) else {}
                ja["ativa"] = "1" if nome in pend else "0"
                if nome in pend:
                    ja["ordem"] = str((pend.index(nome) + 1) * 10)
                gravar_fonte(nome, ja)
        escrever_atomico(ARQ_MIGRADO, cfg["indicadores"].strip() + "\n", 0o644)
        msgs.append("indicadores=%s aplicado ao novo formato" % cfg["indicadores"].strip())
    if msgs:
        compilar()
    return msgs


def limpar_linha_legada(nome, linha):
    """Tira o header com segredo literal da linha antiga do config (o segredo agora está em ~/.secrets)."""
    try:
        txt = ler_texto(CONF)
        novas = []
        for l in txt.splitlines():
            if l.startswith("indicador_%s=" % nome):
                partes = re.split(r"(\s*;;\s*)", l)
                # chave=URL ;; rot ;; cam ;; ttl ;; header  → corta do 4º separador em diante
                seps = [i for i, p in enumerate(partes) if re.fullmatch(r"\s*;;\s*", p)]
                if len(seps) >= 4:
                    l = "".join(partes[:seps[3]])
            novas.append(l)
        if not os.path.exists(CONF + ".antes-letreiro"):
            escrever_atomico(CONF + ".antes-letreiro", "", 0o600)
            os.chmod(CONF + ".antes-letreiro", 0o600)
        escrever_atomico(CONF, "\n".join(novas) + "\n", 0o644)
    except OSError:
        pass


# --------------------------------------------------------------------------------------------------
# Rede: https, sem destino local/privado (SSRF), tempo e tamanho limitados, sem rede no desenhista
# --------------------------------------------------------------------------------------------------
def modo_teste():
    """TT_LETREIRO_TESTE=1 (só nos testes) libera http e o loopback para falar com o servidor de mentira."""
    return os.environ.get("TT_LETREIRO_TESTE") == "1"


def _ip_publico(ip):
    if getattr(ip, "ipv4_mapped", None):
        ip = ip.ipv4_mapped
    if getattr(ip, "sixtofour", None) and not ip.sixtofour.is_global:
        return False
    return ip.is_global and not ip.is_multicast


def resolver(host):
    """host → [ip,...] públicos. Bloqueia qualquer resposta com destino local, privado, link-local,
    CGNAT (Tailscale), multicast ou reservado — um nome que resolve para um deles inteiro é recusado,
    e a conexão usa o IP validado (sem segunda resolução: nada de DNS rebinding)."""
    mapa = os.environ.get("TT_LETREIRO_HOSTS", "")   # teste: nome=ip,nome=ip
    for par in filter(None, mapa.split(",")):
        n, _, ip = par.partition("=")
        if n == host:
            ips = ip.split("|")       # nome=ip1|ip2: um nome que resolve para vários endereços
            break
    else:
        try:
            ips = sorted({r[4][0] for r in socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)})
        except socket.gaierror as e:
            raise ErroHTTP("não consegui resolver %s (%s)" % (host, e.strerror or e), tentar_de_novo=True)
    if not ips:
        raise Erro("sem endereço para %s" % host)
    for ip in ips:
        a = ipaddress.ip_address(ip.split("%")[0])
        if modo_teste():
            if not a.is_loopback:        # nos testes só o servidor de mentira: nunca a rede real
                raise Erro("destino bloqueado: %s resolve para %s (modo de teste: só o servidor local)" % (host, ip))
        elif not _ip_publico(a):
            raise Erro("destino bloqueado: %s resolve para %s (local/rede privada — segurança)" % (host, ip))
    return ips


class Resposta:
    def __init__(self, status, headers, corpo, url, ms):
        self.status, self.headers, self.corpo, self.url, self.ms = status, headers, corpo, url, ms


class ErroHTTP(Erro):
    def __init__(self, msg, status=0, tentar_de_novo=False, espera=0):
        super().__init__(msg)
        self.status, self.tentar_de_novo, self.espera = status, tentar_de_novo, espera


def _contexto_tls(verificar):
    ctx = ssl.create_default_context()
    ca = os.environ.get("TT_LETREIRO_CA", "")
    if ca and modo_teste():                      # só nos testes: confia no certificado do servidor de mentira
        ctx.load_verify_locations(ca)
    if not verificar:
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    return ctx


def _abrir(url, req):
    """Abre a conexão com o IP já validado. Devolve (conexão http.client com .sock pronto, alvo, host_header)."""
    u = urllib.parse.urlsplit(url)
    esquema = u.scheme
    if esquema not in ("http", "https"):
        raise Erro("só http(s) é aceito (recebi %r)" % esquema)
    if esquema == "http" and not (req["permitir_http"] or modo_teste()):
        raise Erro("http:// bloqueado — use https:// (ou permitir_http=1 por sua conta e risco)")
    if u.username or u.password:
        raise Erro("usuário/senha dentro do endereço não são aceitos")
    host = u.hostname
    if not host:
        raise Erro("endereço sem servidor")
    porta = u.port or (443 if esquema == "https" else 80)
    ips = resolver(host)                     # valida SEMPRE o destino final, mesmo com proxy
    timeout = req["timeout"]
    proxy = req.get("proxy") or ""
    if proxy:
        pu = urllib.parse.urlsplit(proxy)
        alvo = (pu.hostname, pu.port or 80)
    else:
        alvo = (ips[0], porta)
    try:
        sock = socket.create_connection(alvo, timeout=timeout)
    except OSError as e:
        raise ErroHTTP("não consegui conectar a %s: %s" % (host, e.strerror or e), tentar_de_novo=True)
    if proxy and esquema == "https":
        sock.sendall(("CONNECT %s:%d HTTP/1.1\r\nHost: %s:%d\r\n\r\n" % (host, porta, host, porta)).encode())
        cab = b""
        while b"\r\n\r\n" not in cab and len(cab) < 8192:
            pedaco = sock.recv(1024)
            if not pedaco:
                break
            cab += pedaco
        if not cab.startswith((b"HTTP/1.1 200", b"HTTP/1.0 200")):
            sock.close()
            raise ErroHTTP("o proxy recusou o túnel (%s)" % cab.split(b"\r\n", 1)[0].decode("latin-1")[:60], tentar_de_novo=True)
    if esquema == "https":
        try:
            sock = _contexto_tls(req["tls_verificar"]).wrap_socket(sock, server_hostname=host)
        except ssl.SSLCertVerificationError as e:
            sock.close()
            raise Erro("certificado TLS não confere para %s: %s" % (host, e.verify_message or e))
        except (ssl.SSLError, OSError) as e:
            sock.close()
            raise ErroHTTP("falha TLS com %s: %s" % (host, e), tentar_de_novo=True)
    cls = http.client.HTTPSConnection if esquema == "https" else http.client.HTTPConnection
    con = cls(host, porta, timeout=timeout)
    con.sock = sock
    return con, u, proxy and esquema == "http"


def _ler_corpo(r, sock, limite, prazo):
    """Lê a resposta aos pedaços: tamanho e tempo totais limitados (um servidor que goteja não prende o tt)."""
    partes, total = [], 0
    while True:
        falta = prazo - time.time()
        if falta <= 0:
            raise ErroHTTP("tempo esgotado lendo a resposta", tentar_de_novo=True)
        try:
            sock.settimeout(max(0.2, falta))
        except OSError:
            pass
        try:
            b = r.read(65536)
        except (OSError, http.client.HTTPException) as e:
            raise ErroHTTP("falha lendo a resposta: %s" % e, tentar_de_novo=True)
        if not b:
            break
        total += len(b)
        if total > limite:
            raise Erro("resposta maior que o limite (%d bytes; tamanho_max)" % limite)
        partes.append(b)
    return b"".join(partes)


def _descomprimir(corpo, enc, limite):
    if not enc or enc == "identity":
        return corpo
    if enc in ("gzip", "x-gzip", "deflate"):
        try:
            out = zlib.decompressobj(47).decompress(corpo, limite + 1)        # gzip ou zlib
        except zlib.error:
            try:
                out = zlib.decompressobj(-15).decompress(corpo, limite + 1)   # deflate cru
            except zlib.error:
                raise Erro("resposta comprimida inválida")
        if len(out) > limite:
            raise Erro("resposta descomprimida maior que o limite (%d bytes)" % limite)
        return out
    raise Erro("codificação de conteúdo não suportada: %s" % enc)


def buscar_uma_vez(req):
    """Uma tentativa (com até 3 redirecionamentos, cada um revalidado). Devolve Resposta."""
    url, metodo, corpo = req["url"], req["metodo"], req.get("corpo")
    headers = dict(req["headers"])
    inicio = time.time()
    prazo = inicio + req["timeout"] * 2
    host0 = urllib.parse.urlsplit(url).hostname
    for salto in range(4):
        con, u, absoluto = _abrir(url, req)
        sock = con.sock          # getresponse() solta con.sock quando a conexão vai fechar
        try:
            caminho = (url if absoluto else (u.path or "/") + ("?" + u.query if u.query else ""))
            h = {"Accept-Encoding": "gzip, identity", "Accept": "*/*", "Connection": "close"}
            h.update(headers)
            if u.hostname != host0:
                for k in list(h):
                    if k.lower() in ("authorization", "cookie", "proxy-authorization") or k.lower() == req.get("auth_header", "").lower():
                        h.pop(k)
            try:
                con.request(metodo, caminho, body=corpo.encode("utf-8") if corpo else None, headers=h)
                r = con.getresponse()
            except socket.timeout:
                raise ErroHTTP("tempo esgotado (%gs)" % req["timeout"], tentar_de_novo=True)
            except (OSError, http.client.HTTPException) as e:
                raise ErroHTTP("falha na requisição: %s" % e, tentar_de_novo=True)
            if r.status in (301, 302, 303, 307, 308) and r.getheader("Location"):
                alvo = urllib.parse.urljoin(url, r.getheader("Location"))
                r.read(0)
                if salto == 3:
                    raise Erro("redirecionamentos demais")
                if u.scheme == "https" and urllib.parse.urlsplit(alvo).scheme != "https":
                    raise Erro("redirecionamento de https para http recusado")
                if r.status in (301, 302, 303) and metodo != "GET":
                    metodo, corpo = "GET", None
                url = alvo
                continue
            cl = r.getheader("Content-Length")
            if cl and cl.isdigit() and int(cl) > req["tamanho_max"] * 4:
                raise Erro("resposta maior que o limite (%d bytes; tamanho_max)" % req["tamanho_max"])
            bruto = _ler_corpo(r, sock, req["tamanho_max"], prazo)
            bruto = _descomprimir(bruto, (r.getheader("Content-Encoding") or "").lower(), req["tamanho_max"])
            ms = int((time.time() - inicio) * 1000)
            if r.status >= 500 or r.status in (408, 429):
                esp = 0
                ra = r.getheader("Retry-After") or ""
                if ra.isdigit():
                    esp = min(60, int(ra))
                raise ErroHTTP("HTTP %d" % r.status, r.status, True, esp)
            if r.status >= 400:
                raise ErroHTTP("HTTP %d" % r.status, r.status, False)
            if r.status < 200 or r.status >= 300:
                raise ErroHTTP("HTTP %d inesperado" % r.status, r.status, False)
            return Resposta(r.status, {k.lower(): v for k, v in r.getheaders()}, bruto, url, ms)
        finally:
            try:
                con.close()
            except Exception:
                pass
    raise Erro("redirecionamentos demais")


def buscar(req, estado=None):
    """Com tentativas e espera crescente. `estado` (dict) recebe 'tentativas_feitas' e 'ultimo_http'."""
    ultimo = None
    n = req["tentativas"]
    for i in range(n):
        if estado is not None:
            estado["tentativas_feitas"] = i + 1
            estado.setdefault("quando", []).append(agora())
        try:
            r = buscar_uma_vez(req)
            if estado is not None:
                estado["ultimo_http"] = r.status
            return r
        except ErroHTTP as e:
            ultimo = e
            if estado is not None:
                estado["ultimo_http"] = e.status or estado.get("ultimo_http", 0)
            if not e.tentar_de_novo or i == n - 1:
                break
            time.sleep(min(60, max(e.espera, req["espera"] * (2 ** i))))
    raise ultimo


# --------------------------------------------------------------------------------------------------
# Montagem da requisição a partir da fonte (variáveis, query, autenticação)
# --------------------------------------------------------------------------------------------------
def variaveis_fonte(f, ts, cfg=None):
    v = vars_tempo(ts, cfg)
    for k, val in f.items():
        if k.startswith("var."):
            v[k[4:]] = val
    return v


def montar_requisicao(f, ts, cfg=None, sub=None):
    """Fonte efetiva → dicionário da requisição (segredos já lidos; só para uso em memória)."""
    f = efetiva_completa(f)
    if sub:
        f.update(sub)
    vars_ = variaveis_fonte(f, ts, cfg)
    if f["segredo"]:
        vars_["segredo"] = ler_segredo(f["segredo"])
    url = aplicar_vars_url(f["url"], vars_)
    u = urllib.parse.urlsplit(url)
    pares = urllib.parse.parse_qsl(u.query, keep_blank_values=True)
    for q in f["query"]:
        k, _, val = q.partition("=")
        val = val.strip()
        if val.startswith("@"):
            val = ler_segredo(val)
        pares.append((k.strip(), aplicar_vars(val, vars_)))
    headers = {"User-Agent": f["user_agent"] or UA_PADRAO}
    auth_header = ""
    for h in f["header"]:
        k, _, val = h.partition(":")
        val = val.strip()
        if val.startswith("@"):
            val = ler_segredo(val)
        headers[k.strip()] = aplicar_vars(val, vars_)
    a = f["auth"]
    if a != "nenhuma":
        seg = vars_["segredo"] if "segredo" in vars_ else ler_segredo(f["segredo"])
        if a == "bearer":
            headers["Authorization"] = "Bearer " + seg
            auth_header = "Authorization"
        elif a == "basic":
            headers["Authorization"] = "Basic " + base64.b64encode(seg.encode()).decode()
            auth_header = "Authorization"
        elif a == "header":
            auth_header = f["auth_nome"] or "X-API-Key"
            headers[auth_header] = seg
        elif a == "query":
            pares.append((f["auth_nome"] or "api_key", seg))
    corpo = aplicar_vars(f["corpo"], vars_) if f["corpo"] else None
    if f["metodo"] == "POST" and corpo is not None and not any(k.lower() == "content-type" for k in headers):
        headers["Content-Type"] = "application/json" if corpo.lstrip()[:1] in "{[" else "application/x-www-form-urlencoded"
    query = urllib.parse.urlencode(pares)
    url = _remapear(urllib.parse.urlunsplit((u.scheme, u.netloc, u.path, query, "")))
    return {
        "url": url, "metodo": f["metodo"], "headers": headers, "corpo": corpo, "auth_header": auth_header,
        "timeout": float(f["timeout"]), "tentativas": int(f["tentativas"]), "espera": float(f["espera"]),
        "tls_verificar": f["tls_verificar"] != "0", "proxy": f["proxy"], "permitir_http": f["permitir_http"] == "1",
        "tamanho_max": int(f["tamanho_max"]), "vars": vars_,
    }


def _remapear(url):
    """Só nos testes (TT_LETREIRO_TESTE=1): TT_LETREIRO_REMAP='prefixo=>destino;…' leva as URLs das fontes
    nativas ao servidor de mentira sem mexer na definição de fábrica."""
    if modo_teste():
        for par in os.environ.get("TT_LETREIRO_REMAP", "").split(";"):
            a, _, b = par.partition("=>")
            if a and url.startswith(a):
                return b + url[len(a):]
    return url


def url_publica(url):
    """A URL sem segredo e sem valores de query (para tela e log): host + caminho + nomes dos parâmetros."""
    u = urllib.parse.urlsplit(url)
    nomes = [k for k, _ in urllib.parse.parse_qsl(u.query, keep_blank_values=True)]
    return redigir("%s://%s%s%s" % (u.scheme, u.netloc, u.path, ("?" + "&".join(k + "=…" for k in nomes)) if nomes else ""))


# --------------------------------------------------------------------------------------------------
# Extração por formato: json (caminho), xml/rss/atom (XPath), csv (coluna), texto (linha), regex
# --------------------------------------------------------------------------------------------------
def _tokens_json(caminho):
    s = (caminho or "").strip()
    if s.startswith("$"):
        s = s[1:]
    toks, i = [], 0
    while i < len(s):
        c = s[i]
        if c == ".":
            i += 1
            continue
        if c == "[":
            j, asp = i + 1, None
            while j < len(s):
                if asp:
                    if s[j] == asp:
                        asp = None
                elif s[j] in "\"'":
                    asp = s[j]
                elif s[j] == "]":
                    break
                j += 1
            if j >= len(s):
                raise Erro("caminho %r: falta fechar ] " % caminho)
            dentro = s[i + 1:j].strip()
            if dentro == "*":
                toks.append(("todos",))
            elif dentro.startswith("?"):
                toks.append(("filtro", dentro[1:].strip()))
            elif re.fullmatch(r"-?\d+", dentro):
                toks.append(("idx", int(dentro)))
            elif re.fullmatch(r"(-?\d*):(-?\d*)", dentro):
                a, b = dentro.split(":")
                toks.append(("fatia", int(a) if a else None, int(b) if b else None))
            elif len(dentro) >= 2 and dentro[0] in "\"'" and dentro[-1] == dentro[0]:
                toks.append(("chave", dentro[1:-1]))
            else:
                raise Erro("caminho %r: [%s] não entendido (use [0], [-1], [*], [0:3], ['chave'] ou [?campo>=valor])" % (caminho, dentro))
            i = j + 1
        else:
            j = i
            while j < len(s) and s[j] not in ".[":
                j += 1
            nome = s[i:j]
            toks.append(("todos",) if nome == "*" else ("num", int(nome)) if re.fullmatch(r"\d+", nome) else ("chave", nome))
            i = j
    return toks


def _comparar(a, op, b):
    na, nb = parse_num(a, "en"), parse_num(b, "en")
    if na is not None and nb is not None and re.fullmatch(r"[+-]?\d+(?:\.\d+)?", str(a).strip()) and re.fullmatch(r"[+-]?\d+(?:\.\d+)?", str(b).strip()):
        a, b = na, nb
    else:
        a, b = str(a), str(b)
    return {"==": a == b, "!=": a != b, ">=": a >= b, "<=": a <= b, ">": a > b, "<": a < b}[op]


def _filtro(no, expr):
    m = re.fullmatch(r"\(?\s*([A-Za-z0-9_.-]+)\s*(==|!=|>=|<=|>|<)\s*(.+?)\s*\)?", expr)
    if not m:
        raise Erro("filtro [?%s] não entendido (use [?campo>=valor])" % expr)
    chave, op, val = m.groups()
    val = val.strip("\"'")
    if not isinstance(no, dict) or chave not in no or no[chave] is None:
        return False
    return _comparar(_texto_no(no[chave]), op, val)


def _texto_no(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (dict, list)):
        return json.dumps(v, ensure_ascii=False, separators=(",", ":"), default=str)
    return str(v)


def extrair_json(texto, caminho):
    try:
        dados = json.loads(texto, parse_float=Decimal)
    except ValueError as e:
        raise Erro("a resposta não é JSON válido (%s)" % str(e)[:60])
    toks = _tokens_json(caminho)
    nos = [dados]
    for n, t in enumerate(toks):
        prox = []
        for no in nos:
            if t[0] == "chave":
                if isinstance(no, dict) and t[1] in no:
                    prox.append(no[t[1]])
                elif isinstance(no, list):
                    prox += [x[t[1]] for x in no if isinstance(x, dict) and t[1] in x]
            elif t[0] == "num":
                if isinstance(no, list) and -len(no) <= t[1] < len(no):
                    prox.append(no[t[1]])
                elif isinstance(no, dict) and str(t[1]) in no:
                    prox.append(no[str(t[1])])
            elif t[0] == "idx":
                if isinstance(no, list) and -len(no) <= t[1] < len(no):
                    prox.append(no[t[1]])
            elif t[0] == "todos":
                if isinstance(no, list):
                    prox += no
                elif isinstance(no, dict):
                    prox += list(no.values())
            elif t[0] == "fatia":
                if isinstance(no, list):
                    prox += no[t[1]:t[2]]
            elif t[0] == "filtro":
                if isinstance(no, list):
                    prox += [x for x in no if _filtro(x, t[1])]
                elif isinstance(no, dict) and _filtro(no, t[1]):
                    prox.append(no)
        if not prox:
            onde = "".join(("." + x[1]) if x[0] in ("chave",) else "[%s]" % (x[1] if x[0] in ("idx", "num") else "*") for x in toks[:n + 1]).lstrip(".")
            chaves = ""
            ant = nos[0] if nos else None
            if isinstance(ant, dict):
                chaves = " (chaves ali: %s)" % ", ".join(list(ant)[:8])
            elif isinstance(ant, list):
                chaves = " (lista com %d itens)" % len(ant)
            raise Erro("caminho %r: nada em '%s'%s" % (caminho, onde, chaves))
        nos = prox
    return [_texto_no(x) for x in nos if x is not None]


def _tira_ns(raiz):
    for el in raiz.iter():
        if isinstance(el.tag, str) and "}" in el.tag:
            el.tag = el.tag.split("}", 1)[1]
        for k in list(el.attrib):
            if "}" in k:
                el.attrib[k.split("}", 1)[1]] = el.attrib.pop(k)


def _xpath_normal(caminho):
    """('caminho para findall', 'atributo' ou None)."""
    c = (caminho or "").strip()
    attr = None
    m = re.search(r"/@([A-Za-z_][\w.-]*)$", c)
    if m:
        attr, c = m.group(1), c[:m.start()]
    elif re.fullmatch(r"@[A-Za-z_][\w.-]*", c):
        attr, c = c[1:], "."
    c = re.sub(r"/text\(\)$", "", c)
    return (c or "."), attr


def _xpath_final(caminho, tag_raiz=None):
    """Caminho do usuário → (caminho para findall a partir da raiz, atributo). '/a/b' = absoluto, '//b' = em qualquer lugar."""
    if caminho.startswith("//"):
        caminho = "." + caminho
    elif caminho.startswith("/"):
        passos = [p for p in caminho[1:].split("/") if p]
        if passos and passos[0] == tag_raiz:
            passos = passos[1:]
        caminho = "./" + "/".join(passos) if passos else "."
    return _xpath_normal(caminho)


def _html_para_texto(t):
    return html.unescape(re.sub(r"<[^>]+>", " ", t))


def extrair_xml(corpo, caminho, formato):
    if re.search(rb"<!DOCTYPE|<!ENTITY", corpo, re.I):
        raise Erro("XML com DOCTYPE/ENTITY recusado (segurança: expansão de entidades)")
    try:
        raiz = ET.fromstring(corpo)
    except ET.ParseError as e:
        raise Erro("a resposta não é XML válido (%s)" % str(e)[:60])
    _tira_ns(raiz)
    if not caminho:
        caminho = ".//entry/title" if (formato == "atom" or raiz.tag == "feed") else ".//item/title"
    path, attr = _xpath_final(caminho, raiz.tag)
    try:
        els = raiz.findall(path) if path != "." else [raiz]
    except (SyntaxError, KeyError, ValueError) as e:
        raise Erro("caminho XPath %r inválido: %s" % (caminho, e))
    vals = []
    for el in els:
        v = el.get(attr) if attr else "".join(el.itertext())
        if v is not None and v.strip():
            vals.append(_html_para_texto(v).strip() if not attr else v.strip())
    if not vals:
        raise Erro("caminho %r: nada encontrado no XML (raiz <%s>)" % (caminho, raiz.tag))
    return vals


def extrair_csv(texto, caminho, sep, cabecalho):
    linhas = [l for l in csv.reader(io.StringIO(texto), delimiter=(sep or ",")[0]) if l]
    if not linhas:
        raise Erro("CSV vazio")
    col = (caminho or "1").strip()
    numerica = bool(re.fullmatch(r"\d+", col))
    tem_cab = (not numerica) if cabecalho == "auto" else cabecalho == "1"
    idx = int(col) - 1 if numerica else None
    if tem_cab:
        cab = [c.strip() for c in linhas[0]]
        linhas = linhas[1:]
        if not numerica:
            if col not in cab:
                raise Erro("coluna %r não existe no CSV (colunas: %s)" % (col, ", ".join(cab[:10])))
            idx = cab.index(col)
    if idx is None or idx < 0:
        raise Erro("coluna inválida: %r" % caminho)
    vals = [l[idx].strip() for l in linhas if len(l) > idx and l[idx].strip()]
    if not vals:
        raise Erro("coluna %r sem valores no CSV" % caminho)
    return vals


def extrair_texto(texto, caminho):
    linhas = [l.strip() for l in texto.splitlines() if l.strip()]
    if not linhas:
        raise Erro("a resposta está vazia")
    c = (caminho or "").strip()
    if c in ("", "-"):
        return linhas
    m = re.fullmatch(r"linha:(-?\d+)", c)
    if m:
        n = int(m.group(1))
        n = n - 1 if n > 0 else n
        if not -len(linhas) <= n < len(linhas):
            raise Erro("a resposta só tem %d linhas" % len(linhas))
        return [linhas[n]]
    raise Erro("caminho de texto: use vazio, - ou linha:N (recebi %r)" % c)


def extrair_regex(texto, caminho):
    try:
        rx = re.compile(caminho, re.M)
    except re.error as e:
        raise Erro("regex inválida: %s" % e)
    vals = []
    for m in rx.finditer(texto):
        vals.append((m.group(1) if rx.groups else m.group(0)) or "")
        if len(vals) >= 200:
            break
    vals = [v.strip() for v in vals if v and v.strip()]
    if not vals:
        raise Erro("a regex não achou nada na resposta")
    return vals


def extrair(formato, corpo, caminho, f):
    """bytes da resposta → lista de textos brutos (todos os achados; quem chama escolhe N)."""
    if formato in ("xml", "rss", "atom"):
        return extrair_xml(corpo, caminho, formato)
    enc = (f.get("codificacao") or "utf-8")
    try:
        texto = corpo.decode(enc, errors="replace")
    except LookupError:
        raise Erro("codificação desconhecida: %s" % enc)
    if formato == "json":
        return extrair_json(texto, caminho)
    if formato == "csv":
        return extrair_csv(texto, caminho, f.get("csv_sep", ","), f.get("csv_cabecalho", "auto"))
    if formato == "texto":
        return extrair_texto(texto, caminho)
    if formato == "regex":
        return extrair_regex(texto, caminho)
    raise Erro("formato desconhecido: %s" % formato)


def escolher(vals, n, de):
    return vals[-n:] if de == "fim" else vals[:n]


# --------------------------------------------------------------------------------------------------
# Condições de exibição (valor>N, var>N, abs>N, cruza N, contem T, mudou)
# --------------------------------------------------------------------------------------------------
_RE_COND = re.compile(r"^\s*(valor|var|abs|var_abs)\s*(>=|<=|==|!=|>|<)\s*(-?[\d.,]+)\s*$")


def _parse_condicao(c):
    c = c.strip()
    m = _RE_COND.match(c)
    if m:
        n = parse_num(m.group(3), "auto")
        if n is None:
            raise Erro("condicao %r: número inválido" % c)
        return ("num", "abs" if m.group(1) == "var_abs" else m.group(1), m.group(2), n)
    m = re.match(r"^cruza\s+(-?[\d.,]+)\s*$", c)
    if m:
        n = parse_num(m.group(1), "auto")
        if n is None:
            raise Erro("condicao %r: número inválido" % c)
        return ("cruza", n)
    m = re.match(r"^(contem|nao_contem)\s+(.+)$", c)
    if m:
        return (m.group(1), m.group(2).strip().lower())
    if c == "mudou":
        return ("mudou",)
    raise Erro("condicao %r não entendida (valor>N, var>N, abs>N, cruza N, contem TEXTO, nao_contem TEXTO, mudou)" % c)


def avaliar_condicoes(conds, num, var, texto, meta, primeiro, ts):
    """True se o item passa por TODAS as condições. `meta` é mutável: guarda o alerta de cruzamento."""
    for c in conds:
        p = _parse_condicao(c)
        if p[0] == "num":
            alvo = {"valor": num, "var": var, "abs": abs(var) if var is not None else None}[p[1]]
            if alvo is None:
                return False
            if not {">": alvo > p[3], "<": alvo < p[3], ">=": alvo >= p[3], "<=": alvo <= p[3], "==": alvo == p[3], "!=": alvo != p[3]}[p[2]]:
                return False
        elif p[0] == "cruza":
            if not primeiro:
                continue
            al = meta.setdefault("alerta", {})
            chave = str(p[1])
            ant = meta.get("anterior_cond")
            if num is not None and ant is not None and ((ant < p[1] <= num) or (ant > p[1] >= num)):
                al[chave] = ts + 3600     # o alerta fica visível por 1 h depois de cruzar o limite
            if al.get(chave, 0) <= ts:
                return False
        elif p[0] == "contem":
            if p[1] not in texto.lower():
                return False
        elif p[0] == "nao_contem":
            if p[1] in texto.lower():
                return False
        elif p[0] == "mudou":
            if primeiro and meta.get("mudou_em", 0) + 3600 <= ts:
                return False
    return True


# --------------------------------------------------------------------------------------------------
# Transformação e exibição de um item
# --------------------------------------------------------------------------------------------------
def idioma_sep(f, cfg):
    s = f.get("separador", "")
    if s in ("pt", "en"):
        return s
    return "en" if (cfg or {}).get("ticker_idioma", "pt").lower().startswith("en") else "pt"


def traduzir(txt, regras):
    for r in regras:
        a, _, b = r.partition(">")
        if a:
            txt = txt.replace(a.strip(), b.strip())
    return txt


def formatar_valor(f, bruto, cfg):
    """texto bruto → (texto do valor, Decimal ou None, Decimal bruto ou None)."""
    txt = limpar_texto(bruto)
    if f["valor_max"] and int(f["valor_max"]) > 0:
        txt = txt[:int(f["valor_max"])]
    txt = traduzir(txt, f["traduzir"])
    num = parse_num(txt, f["entrada"])
    quer_num = f["decimais"] != "" or f["separador"] != "" or f["escala"] != "nenhuma" or f["moeda"] != ""
    if num is None or not quer_num:
        return txt, num, num
    x, suf = num, ""
    if f["escala"] in ESCALAS:
        div, suf = ESCALAS[f["escala"]]
        x = num / div
    dec = int(f["decimais"]) if f["decimais"] != "" else None
    out = formatar_num(x, dec, idioma_sep(f, cfg), f["milhar"] != "0", f["arredondar"]) + suf
    if f["moeda"]:
        out = f["moeda"] + " " + out
    return out, x, num


def formatar_variacao(f, p, cfg):
    """p (%) → (texto completo {var}, seta, pct) com marcas de cor quando permitido."""
    if p is None:
        return "", "", ""
    dec = int(f["var_decimais"])
    arr = p.quantize(Decimal(1).scaleb(-dec), rounding=ROUND_HALF_UP)
    sinal = "alta" if arr > 0 else "baixa" if arr < 0 else "neutra"
    num = formatar_num(abs(arr), dec, idioma_sep(f, cfg), False, "normal")
    cor = f["cor"] != "0" and (cfg or {}).get("ticker_cor", "1") != "0"
    if f["setas"] != "0":
        seta = {"alta": "▲", "baixa": "▼", "neutra": "•"}[sinal]
        corpo = "%s%s%%" % (seta, num)
    else:
        seta = ""
        corpo = ("+" if sinal == "alta" else "-" if sinal == "baixa" else "") + num + "%"
    pct = num + "%"
    if cor:
        ini, fim = MARCAS[sinal], MARCAS["fim"]
        return ini + corpo + fim, (ini + seta + fim if seta else ""), ini + pct + fim
    return corpo, seta, pct


def segredo_nos_valores(vars_, txt):
    return txt


def renderizar_item(f, nome, valor_txt, var_txt, seta, pct, ctx, ts, cfg):
    """Monta a linha do item pelo modelo. `ctx` = variáveis extras (campos e var.*) já resolvidas."""
    dt = dt_local(ts, cfg)
    v = dict(ctx)
    v.update({
        "icone": limpar_texto(aplicar_vars(f["icone"], ctx)), "rotulo": limpar_texto(aplicar_vars(f["rotulo"], ctx)),
        "valor": valor_txt, "item": valor_txt, "var": var_txt, "seta": seta, "pct": pct, "nome": nome,
        "hora": dt.strftime("%H:%M"), "data": dt.strftime("%d/%m"),
    })
    linha = aplicar_vars(f["modelo"], v)
    linha = re.sub(r"[ ]{2,}", " ", limpar_texto(linha, manter_marcas=True)).strip()
    pre = limpar_borda(aplicar_vars(f["prefixo"], v)) if f["prefixo"] else ""
    suf = limpar_borda(aplicar_vars(f["sufixo"], v)) if f["sufixo"] else ""
    # truncar só corta quando o usuário pede (> 0): vale para o item inteiro, prefixo e sufixo ficam, o miolo é que encurta
    if int(f["truncar"] or 0) > 0:
        linha = cortar_celulas(linha, max(1, int(f["truncar"]) - sum(larg(c) for c in pre + suf)))
    linha = pre + linha + suf
    return redigir(linha), v   # uma API que ecoa a chave não a põe na faixa


def limpar_borda(t):
    """limpar_texto que preserva os espaços das pontas (prefixo/sufixo aspados)."""
    esq = " " * (len(t) - len(t.lstrip(" ")))
    dir_ = " " * (len(t) - len(t.rstrip(" ")))
    return esq + limpar_texto(t) + dir_


def sem_marcas(t):
    return re.sub("[\x01-\x04]", "", t)


class Item:
    def __init__(self, linha, vars_, num, var, bruto, acao="nada", alvo=""):
        self.linha, self.vars, self.num, self.var, self.bruto, self.acao, self.alvo = linha, vars_, num, var, bruto, acao, alvo


class Resultado:
    def __init__(self):
        self.ok = False
        self.erro = ""
        self.http = 0
        self.ms = 0
        self.bytes = 0
        self.itens = []
        self.avisos = []
        self.previa = ""
        self.extraidos = []
        self.url = ""
        self.tentativas = 0
        self.quando = []


def _alvo_clique(f, v, nome):
    a = f["clique"]
    if a == "url":
        alvo = limpar_texto(aplicar_vars(f["clique_alvo"] or ("{link}" if v.get("link") else f["url"]), v))
        return ("url", alvo) if re.match(r"^https?://", alvo) else ("bloqueado", "")   # só http(s); o resto nunca abre
    if a == "copiar":
        return "copiar", limpar_texto(aplicar_vars(f["clique_alvo"] or "{valor}", v))
    if a == "painel":
        return ("painel", f["clique_alvo"]) if f["clique_alvo"] in PAINEIS else ("bloqueado", "")
    return "nada", ""


def processar(f, nome, corpo, ts, meta, cfg, res):
    """Corpo da resposta → lista de Item (aplica extração, variação, transformação, condições, modelo)."""
    vars_ = variaveis_fonte(f, ts, cfg)
    fmt = f["formato"]
    cam = aplicar_vars(f["caminho"], vars_)
    todos = extrair(fmt, corpo, cam, f)
    res.extraidos = todos[:20]
    brutos = escolher(todos, int(f["itens"]), f["de"])
    # variação: campo da resposta, valor de referência ou calculada contra o valor anterior
    var = None
    vcam = f["variacao"]
    num0 = parse_num(brutos[0], f["entrada"]) if brutos else None
    if vcam and vcam != "calculada":
        try:
            var = parse_num(extrair(fmt, corpo, aplicar_vars(vcam, vars_), f)[0], "auto")
        except Erro as e:
            res.avisos.append("variação: %s" % e)
    elif f["var_base"]:
        try:
            base = parse_num(extrair(fmt, corpo, aplicar_vars(f["var_base"], vars_), f)[0], "auto")
            if base and num0 is not None:
                var = (num0 - base) / base * 100
        except Erro as e:
            res.avisos.append("var_base: %s" % e)
    elif vcam == "calculada" and num0 is not None:
        ant = parse_num(meta.get("valor"), "en") if meta.get("valor") is not None else None
        prev = parse_num(meta.get("anterior"), "en") if meta.get("anterior") is not None else None
        if ant is not None and num0 != ant:
            prev = ant
        if prev:
            var = (num0 - prev) / prev * 100
    # campos extras (campo.NOME=caminho): um valor serve a todos os itens; vários acompanham os itens
    extras = {}
    for k, v in f.items():
        if k.startswith("campo."):
            try:
                extras[k[6:]] = [limpar_texto(x) for x in extrair(fmt, corpo, aplicar_vars(v, vars_), f)]
            except Erro as e:
                res.avisos.append("%s: %s" % (k, e))
                extras[k[6:]] = []
    ctx_base = {k: v for k, v in vars_.items() if k not in ("segredo",)}
    itens = []
    mm = {"alerta": meta.get("alerta", {}), "mudou_em": meta.get("mudou_em", 0)}
    ant_c = parse_num(meta.get("valor"), "en") if meta.get("valor") is not None else None
    mm["anterior_cond"] = ant_c
    for i, bruto in enumerate(brutos):
        valor_txt, x, num = formatar_valor(f, bruto, cfg)
        v_i = var if i == 0 else None
        if not avaliar_condicoes(f["condicao"], num, v_i, valor_txt, mm, i == 0, ts):
            continue
        var_txt, seta, pct = formatar_variacao(f, v_i, cfg)
        ctx = dict(ctx_base)
        for k, lst in extras.items():
            ctx[k] = lst[0] if len(lst) == 1 else (lst[i] if i < len(lst) else "")
        linha, v = renderizar_item(f, nome, valor_txt, var_txt, seta, pct, ctx, ts, cfg)
        if not sem_marcas(linha).strip():
            continue
        acao, alvo = _alvo_clique(f, dict(v, valor=sem_marcas(valor_txt)), nome)
        itens.append(Item(linha, v, num, v_i, bruto, acao, alvo))
    meta["alerta"] = mm["alerta"]
    # estado para a variação calculada e para os alertas (sempre do 1º item, antes de filtrar)
    if brutos:
        num0 = parse_num(brutos[0], f["entrada"])
        atual = str(num0) if num0 is not None else limpar_texto(brutos[0])
        if meta.get("valor") is not None and meta["valor"] != atual:
            meta["anterior"] = meta["valor"]
            meta["mudou_em"] = ts
        elif meta.get("valor") is None:
            meta["mudou_em"] = ts
        meta["valor"] = atual
    return itens


def _dado_tt(dado, timeout=15):
    tt = os.environ.get("TT_BIN") or os.path.join(HOME, ".local", "bin", "tt")
    try:
        p = subprocess.run([tt, "--letreiro-dado", dado], capture_output=True, text=True, timeout=timeout,
                           stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise Erro("não consegui obter %s do tt: %s" % (dado, e))
    saida = p.stdout.strip().splitlines()
    if p.returncode != 0 or not saida:
        raise Erro("tt --letreiro-dado %s falhou (%s)" % (dado, (p.stderr.strip() or "sem saída")[:80]))
    return saida[0].strip()


def executar(nome, f_base, ts=None, meta=None, cfg=None):
    """Roda UMA fonte: busca, extrai, transforma e renderiza. NÃO grava nada (quem chama decide).
    Devolve Resultado; erros viram res.ok=False e res.erro (redigido)."""
    ts = ts if ts is not None else agora()
    cfg = cfg if cfg is not None else ler_conf()
    meta = meta if meta is not None else {}
    res = Resultado()
    f = efetiva_completa(f_base)
    t0 = time.time()
    try:
        origem = f["origem"]
        if origem == "lista":
            itens = list(f["item"])
            import random
            escolhidos = random.SystemRandom().sample(itens, min(int(f["itens"]), len(itens))) if itens else []
            vars_ = variaveis_fonte(f, ts, cfg)
            for bruto in escolhidos:
                valor_txt, _x, num = formatar_valor(f, bruto, cfg)
                linha, v = renderizar_item(f, nome, valor_txt, "", "", "", {k: x for k, x in vars_.items()}, ts, cfg)
                acao, alvo = _alvo_clique(f, dict(v, valor=valor_txt), nome)
                if sem_marcas(linha).strip():
                    res.itens.append(Item(linha, v, num, None, bruto, acao, alvo))
            res.extraidos = escolhidos
            res.ok = True
        elif origem == "tt":
            bruto = _dado_tt(f["dado"])
            valor_txt, _x, num = formatar_valor(f, bruto, cfg)
            mm = {"alerta": meta.get("alerta", {}), "mudou_em": meta.get("mudou_em", 0), "anterior_cond": parse_num(meta.get("valor"), "en") if meta.get("valor") else None}
            res.extraidos = [bruto]
            if avaliar_condicoes(f["condicao"], num, None, valor_txt, mm, True, ts):
                linha, v = renderizar_item(f, nome, valor_txt, "", "", "", {}, ts, cfg)
                acao, alvo = _alvo_clique(f, dict(v, valor=valor_txt), nome)
                if sem_marcas(linha).strip():
                    res.itens.append(Item(linha, v, num, None, bruto, acao, alvo))
            meta["alerta"] = mm["alerta"]
            atual = str(num) if num is not None else bruto
            if meta.get("valor") != atual:
                meta["anterior"] = meta.get("valor")
                meta["mudou_em"] = ts
            meta["valor"] = atual
            res.ok = True
        else:
            subs = f_base.get("_sub") or [None]
            algum, ultimo_erro = False, ""
            for sub in subs:
                fs = dict(f)
                if sub:
                    fs.update({k: v for k, v in sub.items() if k not in ("ativa", "ordem", "peso", "ttl")})
                    fs = efetiva_completa({k: v for k, v in fs.items() if k != "_sub"})
                req = montar_requisicao({k: v for k, v in fs.items() if k != "_sub"}, ts, cfg)
                res.url = url_publica(req["url"])
                est = {}
                try:
                    r = buscar(req, est)
                    res.http, res.bytes, res.ms = r.status, res.bytes + len(r.corpo), max(res.ms, r.ms)
                    res.tentativas += est.get("tentativas_feitas", 1)
                    res.quando += est.get("quando", [])
                    res.previa = redigir(limpar_texto(r.corpo[:600].decode(fs["codificacao"] or "utf-8", errors="replace")))[:400]
                    res.itens += processar(fs, nome, r.corpo, ts, meta, cfg, res)
                    algum = True
                except Erro as e:
                    res.http = est.get("ultimo_http", res.http) or getattr(e, "status", 0) or res.http
                    res.tentativas += est.get("tentativas_feitas", 0)
                    res.quando += est.get("quando", [])
                    ultimo_erro = redigir(str(e))
                    res.avisos.append("%s: %s" % (res.url or nome, ultimo_erro))
            if not algum:
                raise Erro(ultimo_erro or "sem resposta")
            res.ok = True
            if res.ok and len(subs) > 1 and ultimo_erro:
                res.avisos.append("uma das fontes compostas falhou: %s" % ultimo_erro)
    except Erro as e:
        res.ok = False
        res.erro = redigir(str(e))[:240]
        if isinstance(e, ErroHTTP) and e.status:
            res.http = e.status
    except Exception as e:      # bug ou surpresa: nunca derruba o letreiro
        res.ok = False
        res.erro = redigir("%s: %s" % (type(e).__name__, e))[:240]
    if not res.ms:
        res.ms = int((time.time() - t0) * 1000)
    res.avisos = [redigir(a) for a in res.avisos] + sorted(AVISOS_SEGREDO)
    return res


# --------------------------------------------------------------------------------------------------
# Estado por fonte (meta), cache, log, economia, avisos
# --------------------------------------------------------------------------------------------------
def arq_cache(nome, ext=""):
    return os.path.join(DIR_TICKER, nome + ext)


def ler_meta(nome):
    return ler_json(arq_cache(nome, ".meta"))


def gravar_meta(nome, meta):
    escrever_atomico(arq_cache(nome, ".meta"), json.dumps(meta, ensure_ascii=False, sort_keys=True), 0o600)


def log(nome, msg):
    try:
        os.makedirs(os.path.dirname(ARQ_LOG), exist_ok=True)
        rotacionar_log()
        with open(ARQ_LOG, "a", encoding="utf-8") as fh:
            fh.write("%s %s %s\n" % (datetime.fromtimestamp(agora()).strftime("%F %T"), nome, redigir(msg)))
    except OSError:
        pass


def gravar_cache(nome, itens):
    texto = "".join(it.linha + "\n" for it in itens)
    escrever_atomico(arq_cache(nome), texto, 0o600)
    dados = [{"t": sem_marcas(it.linha), "acao": it.acao, "alvo": it.alvo} for it in itens]
    escrever_atomico(arq_cache(nome, ".itens"), json.dumps(dados, ensure_ascii=False), 0o600)


def bateria():
    """(porcentagem, carregando) ou (None, None). TT_LETREIRO_BATERIA='15 Discharging' força (testes)."""
    v = os.environ.get("TT_LETREIRO_BATERIA", "")
    if v:
        p = v.split()
        return int(p[0]), (p[1].lower() if len(p) > 1 else "") not in ("discharging", "descarregando")
    try:
        import glob
        for d in glob.glob("/sys/class/power_supply/BAT*"):
            cap = int(ler_texto(os.path.join(d, "capacity")).strip() or "-1")
            st = ler_texto(os.path.join(d, "status")).strip().lower()
            if cap >= 0:
                return cap, st != "discharging"
    except (OSError, ValueError):
        pass
    if perfil_maquina() == "celular":
        try:
            p = subprocess.run(["termux-battery-status"], capture_output=True, text=True, timeout=5, stdin=subprocess.DEVNULL)
            j = json.loads(p.stdout)
            return int(j["percentage"]), str(j.get("status", "")).lower() != "discharging"
        except Exception:
            pass
    return None, None


def clientes_ativos(minutos=15):
    """Quantos terminais tmux tiveram atividade nos últimos `minutos`. TT_LETREIRO_CLIENTES força (testes)."""
    v = os.environ.get("TT_LETREIRO_CLIENTES", "")
    if v.isdigit():
        return int(v)
    try:
        p = subprocess.run(["tmux", "list-clients", "-F", "#{client_activity}"], capture_output=True, text=True,
                           timeout=4, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return 0
    n = 0
    for l in p.stdout.split():
        if l.isdigit() and agora() - int(l) <= minutos * 60:
            n += 1
    return n


def economia_ativa(cfg):
    e = cfg.get("ticker_economia", "auto")
    return e == "1" or (e == "auto" and perfil_maquina() == "celular")


def motivo_economia(cfg):
    """Por que NÃO atualizar agora (modo economia), ou ''."""
    if not economia_ativa(cfg):
        return ""
    pct, carregando = bateria()
    if pct is not None and not carregando and pct < int(cfg.get("ticker_bateria_min", "20") or 20):
        return "bateria baixa (%d%%)" % pct
    if clientes_ativos(30) == 0:
        return "nenhum terminal em uso"
    return ""


def avisar_falhas(nome, f, meta, falhas):
    tt = os.environ.get("TT_BIN") or os.path.join(HOME, ".local", "bin", "tt")
    texto = "⚠ letreiro: a fonte %s falhou %d vezes seguidas (%s) — tt --letreiro-testar %s" % (
        nome, falhas, (meta.get("erro") or "?")[:60], nome)
    try:
        subprocess.run([tt, "--notificar", redigir(texto), "900", "letreiro"], capture_output=True, timeout=10,
                       stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        pass


def motivo_pular(nome, f, meta, cfg, ts, forcar):
    """Por que a fonte NÃO deve atualizar agora ('' = deve)."""
    if not forcar:
        if f["ativa"] != "1":
            return "desligada"
        if not vale_aqui(f, cfg):
            return "não vale nesta máquina"
        m = motivo_economia(cfg)
        if m:
            return "economia: " + m
        try:
            if not na_janela(ts, f["dias"], f["horas"], cfg):
                return "fora da janela"
        except Erro:
            pass
        if f["so_com_cliente"] == "1" and clientes_ativos(15) == 0:
            return "sem terminal em uso"
        ultimo = meta.get("sucesso") or 0
        if not ultimo:
            try:
                ultimo = os.stat(arq_cache(nome)).st_mtime     # cache de antes da migração vale como último sucesso
            except OSError:
                ultimo = 0
        if ts - ultimo < int(f["ttl"]):
            return "ttl"
        if ts < meta.get("espera_ate", 0):
            return "espera após erro (%ds)" % int(meta["espera_ate"] - ts)
        lim = int(f["limite_hora"])
        if lim:
            recentes = [t for t in meta.get("reqs", []) if ts - t < 3600]
            if len(recentes) >= lim:
                return "cota de %d requisições/hora" % lim
    return ""


def atualizar_fonte(nome, f_base, cfg, forcar=False, ts=None):
    """Uma fonte: decide, executa e GRAVA cache/meta/log. Devolve 'ok', 'erro' ou 'pulada: motivo'."""
    ts = int(ts if ts is not None else agora())
    f = efetiva_completa(f_base)
    meta = ler_meta(nome)
    motivo = motivo_pular(nome, f, meta, cfg, ts, forcar)
    if motivo:
        return "pulada: " + motivo
    meta["tentativa"] = ts
    res = executar(nome, f_base, ts, meta, cfg)
    meta["reqs"] = [t for t in meta.get("reqs", []) if ts - t < 3600] + [int(q) for q in res.quando]
    meta["http"], meta["latencia_ms"], meta["bytes"] = res.http, res.ms, res.bytes
    if res.ok:
        gravar_cache(nome, res.itens)
        meta.update({"sucesso": ts, "falhas": 0, "erro": "", "espera_ate": 0, "notificado": 0, "itens": len(res.itens)})
        gravar_meta(nome, meta)
        log(nome, "ok http=%s %dms %dB %d item(ns)%s" % (res.http or "-", res.ms, res.bytes, len(res.itens),
                                                          (" · " + "; ".join(res.avisos)[:160]) if res.avisos else ""))
        return "ok"
    falhas = int(meta.get("falhas", 0)) + 1
    meta.update({"falhas": falhas, "erro": res.erro, "espera_ate": ts + min(3600, 60 * 2 ** (falhas - 1)),
                 "ultimo_erro_em": ts})
    limite = int(f["alerta_falhas"])
    if limite and falhas >= limite and not meta.get("notificado"):
        meta["notificado"] = 1
        avisar_falhas(nome, f, meta, falhas)
    gravar_meta(nome, meta)
    log(nome, "ERRO http=%s %dms falhas=%d próxima tentativa em %ds: %s" % (res.http or "-", res.ms, falhas,
                                                                              min(3600, 60 * 2 ** (falhas - 1)), res.erro))
    return "erro"


class Trava:
    """Uma atualização por vez (o vigia chama a cada volta; a anterior pode ainda estar na rede)."""
    def __init__(self, esperar=0):
        self.esperar, self.fd = esperar, None

    def __enter__(self):
        os.makedirs(DIR_TICKER, exist_ok=True)
        self.fd = os.open(os.path.join(DIR_TICKER, ".trava"), os.O_CREAT | os.O_RDWR, 0o600)
        fim = time.time() + self.esperar
        while True:
            try:
                fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return self
            except OSError:
                if time.time() >= fim:
                    os.close(self.fd)
                    self.fd = None
                    return None
                time.sleep(0.2)

    def __exit__(self, *a):
        if self.fd is not None:
            os.close(self.fd)


def atualizar(nomes=None, forcar=False):
    """O que o vigia chama: migra o que for antigo, atualiza as fontes vencidas e recompila a roda."""
    cfg = ler_conf()
    if cfg.get("ticker_ligado", "1") == "0":
        return {}
    with Trava(esperar=60 if forcar else 0) as t:
        if t is None:
            return {"": "pulada: outra atualização em andamento"}
        migrar()
        compilar()
        if economia_ativa(cfg):      # o desenhista lê isto: bateria baixa sem carregar = páginas, sem animação
            pct, carregando = bateria()
            if pct is not None:
                escrever_atomico(os.path.join(DIR_TICKER, "_energia"), "%d %d %d\n" % (pct, 1 if carregando else 0, int(agora())), 0o644)
        prazo = time.time() + 110
        saida = {}
        for nome, f, _o in listar_ordenadas(cfg):
            if nomes and nome not in nomes:
                continue
            if not nomes and f["ativa"] != "1":
                continue
            if time.time() > prazo:
                saida[nome] = "pulada: tempo da rodada esgotado"
                continue
            base, _x = fonte_efetiva(nome, cfg)
            saida[nome] = atualizar_fonte(nome, base, cfg, forcar=forcar)
        return saida


# --------------------------------------------------------------------------------------------------
# Roda (índice para o desenhista), estado e listagem
# --------------------------------------------------------------------------------------------------
def compilar():
    """Escreve ~/.cache/tt-ticker/_roda.json: as fontes ativas DESTA máquina, na ordem, com o que o
    desenhista precisa (peso, janela de exibição, política de dado velho, clique). Só reescreve se mudou."""
    cfg = ler_conf()
    itens = []
    if cfg.get("ticker_ligado", "1") != "0":
        for nome, f, _o in listar_ordenadas(cfg, so_ativas=True):
            cm = int(f["cache_max"])
            if cm:   # velho de verdade = muito além do TTL: o limite nunca fica abaixo de 2×ttl (+2 min)
                cm = max(cm, (2 * int(f["ttl"])) // 60 + 2)
            itens.append({
                "nome": nome, "ordem": int(f["ordem"]), "peso": int(f["peso"]), "ttl": int(f["ttl"]),
                "mostrar_dias": f["mostrar_dias"], "mostrar_horas": f["mostrar_horas"],
                "cache_max": cm, "se_faltar": f["se_faltar"], "clique": f["clique"],
                "rotulo": f["rotulo"] if "{" not in f["rotulo"] else nome, "icone": f["icone"],
            })
    texto = json.dumps({"v": VERSAO_FORMATO, "itens": itens}, ensure_ascii=False, sort_keys=True)
    if ler_texto(ARQ_RODA) != texto:
        escrever_atomico(ARQ_RODA, texto, 0o644)
    return itens


def estado_fonte(nome, f, origem, cfg, ts):
    meta = ler_meta(nome)
    suc = meta.get("sucesso") or 0
    if not suc:
        try:
            suc = os.stat(arq_cache(nome)).st_mtime
        except OSError:
            suc = 0
    falhas = int(meta.get("falhas", 0))
    ttl = int(f["ttl"])
    nota = ""
    if f["ativa"] != "1":
        estado = "desligada"
    elif not vale_aqui(f, cfg):
        estado, nota = "fora", "não vale nesta máquina (perfil/máquinas)"
    elif not suc and not meta.get("tentativa"):
        estado = "aguardando"
    elif falhas > 0 and (not suc or ts - suc > 2 * ttl + 120):
        estado = "erro"
    elif falhas > 0:
        estado, nota = "ok", "falha recente"
    elif ts - suc <= 2 * ttl + 120:
        estado = "ok"
    else:
        estado = "velha"
    if estado in ("velha", "aguardando", "ok") and f["ativa"] == "1":
        m = motivo_pular(nome, f, meta, cfg, ts, False)
        if m and m != "ttl":
            nota = nota or m
    return {
        "nome": nome, "origem": origem, "ativa": f["ativa"], "estado": estado, "nota": nota, "escopo": f["escopo"],
        "rotulo": (f["icone"] + " " + f["rotulo"]).strip(), "ordem": f["ordem"], "peso": f["peso"], "ttl": ttl,
        "sucesso": suc, "ha": ha(ts - suc) if suc else "nunca", "ms": meta.get("latencia_ms", ""), "http": meta.get("http", ""),
        "falhas": falhas, "erro": meta.get("erro", ""), "tags": f["tags"], "descricao": f["descricao"], "formato": f["formato"],
        "url": url_publica(f["url"]) if f["url"] else "(%s)" % f["origem"], "itens": meta.get("itens", ""),
        "local": os.path.exists(arq_local(nome)), "categoria": categoria_de(nome, f, origem),
        "de_fabrica": nome in NATIVAS, "mexida": os.path.exists(arq_fonte(nome)) or os.path.exists(arq_local(nome)),
    }


def listar_estados(cfg=None, ts=None, filtro="padrao", categoria="", ocultas=False):
    """filtro: padrao (as ligadas, as suas e as de fábrica que você já mexeu) | todas | ativas | inativas."""
    cfg = cfg if cfg is not None else ler_conf()
    ts = ts if ts is not None else agora()
    est = [estado_fonte(n, f, o, cfg, ts) for n, f, o in listar_ordenadas(cfg, so_ocultas=ocultas)]
    if filtro == "ativas":
        est = [e for e in est if e["ativa"] == "1"]
    elif filtro == "inativas":
        est = [e for e in est if e["ativa"] != "1"]
    elif filtro == "padrao":
        est = [e for e in est if e["ativa"] == "1" or e["nome"] in ORIGINAIS or not e["de_fabrica"] or e["mexida"]]
    if categoria:
        est = [e for e in est if e["categoria"] == categoria]
    return est


def tabela(estados):
    if not estados:
        return "nenhuma fonte cadastrada — tt --letreiro-catalogo"
    lg = max(14, max(len(e["nome"]) for e in estados))
    linhas = ["%-*s %-10s %-6s %-5s %-6s %-10s %-7s %s" % (lg, "NOME", "ESTADO", "ORDEM", "PESO", "TTL", "ATUALIZADA", "LAT.", "ROTULO · OBSERVAÇÃO")]
    for e in estados:
        obs = e["rotulo"] or e["descricao"]
        if e["nota"]:
            obs += " · " + e["nota"]
        if e["estado"] == "erro" and e["erro"]:
            obs += " · " + e["erro"][:70]
        if e["escopo"] == "global":
            obs += " · 🌐"
        if e["local"]:
            obs += " · ✎ só aqui"
        linhas.append("%-*s %-10s %-6s %-5s %-6s %-10s %-7s %s" % (
            lg, e["nome"], e["estado"], e["ordem"], e["peso"], "%ds" % e["ttl"], e["ha"], ("%sms" % e["ms"]) if e["ms"] != "" else "-", obs.strip()))
    return "\n".join(linhas)


def tsv(estados):
    out = []
    for e in estados:
        out.append("\t".join(str(x).replace("\t", " ") for x in (
            e["nome"], e["ativa"], e["estado"], e["origem"], e["escopo"], (e["rotulo"] or e["descricao"][:48]), e["ordem"], e["peso"], e["ttl"],
            e["ha"], e["ms"], e["http"], e["falhas"], (e["erro"] or e["nota"] or (e["descricao"] if e["ativa"] != "1" else "")), e["url"],
            int(e["local"]), e["formato"], e["itens"], e["categoria"])))
    return "\n".join(out)


def ver_log(nome, n=40):
    linhas = []
    for arq in (ARQ_LOG + ".1", ARQ_LOG):
        for l in ler_texto(arq).splitlines():
            p = l.split(" ", 3)
            if len(p) >= 3 and (not nome or p[2] == nome):
                linhas.append(l)
    return "\n".join(linhas[-n:])


def linha_atual():
    """As linhas das fontes ativas como estão no cache (sem marcas), unidas por ' • ' (tt --ticker-fontes)."""
    partes = []
    for nome, f, _o in listar_ordenadas(None, so_ativas=True):
        for l in ler_texto(arq_cache(nome)).splitlines():
            if l.strip():
                partes.append(sem_marcas(limpar_texto(l, manter_marcas=True)))
    return " • ".join(partes)


# --------------------------------------------------------------------------------------------------
# Pacote de fontes: exportar, importar e propagar pela rede (a mudança mais nova vence)
# --------------------------------------------------------------------------------------------------
def _credencial_literal(d):
    """Mensagem se o dicionário carrega um segredo no lugar de uma referência; senão ''."""
    _n, erros, _a = validar_fonte(d, completo=False)
    return "; ".join(e for e in erros if "credencial" in e or "chave '" in e or "senha" in e)


def pacote_texto(nomes=None, so_globais=False, com_removidas=False):
    saida = ["# tt letreiro — pacote de fontes (versao=%d)" % VERSAO_FORMATO]
    erros = []
    for nome in sorted(os.listdir(DIR_FONTES)) if os.path.isdir(DIR_FONTES) else []:
        if not nome.endswith(".conf") or not RE_NOME.match(nome[:-5]):
            continue
        n = nome[:-5]
        if nomes and n not in nomes:
            continue
        d = ler_arquivo_conf(os.path.join(DIR_FONTES, nome))
        if so_globais and d.get("escopo") != "global":
            continue
        problema = _credencial_literal(d)
        if problema:
            erros.append("%s: %s" % (n, problema))
            continue
        saida.append("@@fonte %s mudada=%s" % (n, d.get("mudada", "0") or "0"))
        saida.append(serializar(d).rstrip("\n"))
        saida.append("@@fim")
    if com_removidas:
        for n, t in sorted(ler_removidas().items()):
            saida.append("@@fonte %s mudada=%d removida=1" % (n, t))
            saida.append("@@fim")
    return "\n".join(saida) + "\n", erros


def _blocos(texto):
    """Itera (nome, atributos, linhas) de um pacote."""
    nome, attrs, corpo = None, {}, []
    total = 0
    for linha in texto.splitlines():
        total += len(linha) + 1
        if total > 2_000_000:
            raise Erro("pacote grande demais")
        if linha.startswith("@@fonte "):
            partes = linha.split()
            nome = partes[1] if len(partes) > 1 else ""
            attrs = dict(p.split("=", 1) for p in partes[2:] if "=" in p)
            corpo = []
        elif linha.startswith("@@fim"):
            if nome is not None:
                yield nome, attrs, corpo
            nome = None
        elif nome is not None:
            corpo.append(linha)
            if sum(len(x) for x in corpo) > 20000:
                nome = None


def _dict_de_linhas(linhas):
    d = {}
    for l in linhas:
        l = l.strip()
        if not l or l.startswith("#") or "=" not in l:
            continue
        k, v = l.split("=", 1)
        k, v = k.strip(), _desaspar(v.strip())
        if k in REPETE:
            d.setdefault(k, []).append(v)
        else:
            d[k] = v
    return d


def receber(texto):
    """Funde um pacote vindo de outra máquina. Só fontes `escopo=global`; vale a `mudada` mais nova; nada
    com credencial literal; uma fonte local desta máquina nunca é tocada. Devolve mensagens."""
    msgs, mudou = [], False
    rem = ler_removidas()
    for nome, attrs, linhas in _blocos(texto):
        if not RE_NOME.match(nome):
            msgs.append("ignorada (nome inválido): %r" % nome[:30])
            continue
        try:
            ts = int(attrs.get("mudada", "0"))
        except ValueError:
            ts = 0
        local = ler_arquivo_conf(arq_fonte(nome)) if os.path.exists(arq_fonte(nome)) else None
        ts_local = int((local or {}).get("mudada", "0") or 0) if local else 0
        ts_rem = rem.get(nome, 0)
        if attrs.get("removida") == "1":
            if local is not None and local.get("escopo") == "global" and ts >= ts_local and ts > ts_rem:   # empate: a remoção vence
                os.unlink(arq_fonte(nome))
                rem[nome] = ts
                msgs.append("%s: removida (decisão de outra máquina)" % nome)
                mudou = True
            elif local is None and ts > ts_rem:
                rem[nome] = ts
                mudou = True
            continue
        d = _dict_de_linhas(linhas)
        if d.get("escopo") != "global":
            msgs.append("%s: ignorada (só fontes globais se propagam)" % nome)
            continue
        if local is not None and local.get("escopo") != "global":
            msgs.append("%s: ignorada (existe uma fonte local com esse nome)" % nome)
            continue
        problema = _credencial_literal(d)
        if problema:
            msgs.append("%s: recusada (%s)" % (nome, problema))
            continue
        n, erros, _a = validar_fonte(d, completo=nome not in NATIVAS)
        if erros:
            msgs.append("%s: recusada (%s)" % (nome, "; ".join(erros)[:120]))
            continue
        if ts <= ts_rem:
            continue                                   # a lápide é mais nova: não ressuscita
        if local is not None and (ts < ts_local or (ts == ts_local and serializar(n) <= serializar(local))):
            continue
        n["mudada"] = str(ts)
        n["escopo"] = "global"
        escrever_atomico(arq_fonte(nome), serializar(n), 0o644)
        if nome in rem:
            del rem[nome]
        msgs.append("%s: %s" % (nome, "atualizada" if local else "nova"))
        mudou = True
    if mudou:
        gravar_removidas(rem)
        compilar()
    return msgs


def importar(texto, sobrescrever=False, nome_unico=None):
    """Importa um pacote (ou um .conf avulso, com nome_unico). Devolve mensagens."""
    msgs = []
    blocos = list(_blocos(texto))
    if not blocos:
        if not nome_unico:
            raise Erro("não achei fontes no arquivo (esperava '@@fonte NOME … @@fim', ou informe o nome)")
        blocos = [(nome_unico, {}, texto.splitlines())]
    for nome, attrs, linhas in blocos:
        if attrs.get("removida") == "1":
            continue
        if not RE_NOME.match(nome):
            msgs.append("%s: nome inválido" % nome[:30])
            continue
        d = _dict_de_linhas(linhas)
        d.pop("mudada", None)
        problema = _credencial_literal(d)
        if problema:
            msgs.append("%s: recusada (%s)" % (nome, problema))
            continue
        n, erros, avisos = validar_fonte(d, completo=nome not in NATIVAS)
        if erros:
            msgs.append("%s: recusada (%s)" % (nome, "; ".join(erros)[:160]))
            continue
        if os.path.exists(arq_fonte(nome)) and not sobrescrever:
            msgs.append("%s: já existe (use --sobrescrever)" % nome)
            continue
        gravar_fonte(nome, n)
        msgs.append("%s: importada%s" % (nome, (" · " + "; ".join(avisos)) if avisos else ""))
    compilar()
    return msgs


# --------------------------------------------------------------------------------------------------
# Catálogo de um clique
# --------------------------------------------------------------------------------------------------
def catalogo_instalar(id_, kv, nome=None):
    if id_ in NATIVAS:                                # de fábrica: liga (e volta à lista, se você a tinha tirado)
        if nome and nome != id_:
            raise Erro("%s é de fábrica e não tem perguntas: --nome só vale para modelos (tt --letreiro-duplicar %s %s)" % (id_, id_, nome))
        erros, avisos = ativar_fonte(id_, True)
        return id_, erros, avisos
    if id_ not in CATALOGO:
        raise Erro("não existe '%s' no catálogo (tt --letreiro-catalogo)" % id_)
    desc, conf, perguntas = CATALOGO[id_]
    nome = nome or id_
    _nome_valido(nome)
    if conf is None:                                  # nativa: só liga
        erros, avisos = ativar_fonte(id_, True)
        return id_, erros, avisos
    if os.path.exists(arq_fonte(nome)):
        raise Erro("já existe uma fonte chamada %s (use --nome outro)" % nome)
    d = {k: (list(v) if isinstance(v, list) else v) for k, v in conf.items()}
    dados = dict(x.split("=", 1) for x in kv if "=" in x and not x.startswith("var."))
    for x in kv:
        if x.startswith("var.") and "=" in x:
            dados[x[4:].split("=", 1)[0]] = x.split("=", 1)[1]
    for var, _perg, padrao in perguntas:
        d["var." + var] = dados.pop(var, padrao)
    outros = [f"{k}={v}" for k, v in dados.items()]
    d = juntar_kv(d, outros)
    if "ordem" not in d:
        ordens = [int(f["ordem"]) for _n, f, _o in listar_ordenadas() if f["ordem"].lstrip("-").isdigit()]
        d["ordem"] = str((max(ordens) if ordens else 0) + 10)
    d["ativa"] = "1"
    n, erros, avisos = validar_fonte(d, completo=True)
    if erros:
        return nome, erros, avisos
    gravar_fonte(nome, n)
    compilar()
    return nome, [], avisos


# --------------------------------------------------------------------------------------------------
# Assistente: buscar a resposta, detectar o formato e listar os caminhos
# --------------------------------------------------------------------------------------------------
def detectar_formato(corpo, ctype=""):
    cabeca = corpo[:2000].lstrip()
    t = corpo[:200000].decode("utf-8", errors="replace")
    if cabeca[:1] in (b"{", b"["):
        try:
            json.loads(corpo.decode("utf-8", errors="replace"))
            return "json"
        except ValueError:
            pass
    if cabeca[:5] == b"<?xml" or cabeca[:1] == b"<":
        if re.search(r"<feed[\s>]", t):
            return "atom"
        if re.search(r"<(rss|rdf:RDF)[\s>]", t):
            return "rss"
        return "xml"
    linhas = [l for l in t.splitlines() if l.strip()]
    if len(linhas) >= 2 and all(l.count(",") == linhas[0].count(",") and l.count(",") >= 1 for l in linhas[:5]):
        return "csv"
    if len(linhas) >= 2 and all(l.count(";") == linhas[0].count(";") and l.count(";") >= 1 for l in linhas[:5]):
        return "csv"
    return "texto"


def _caminhos_json(no, prefixo, saida, prof=0):
    if len(saida) >= 400 or prof > 6:
        return
    if isinstance(no, dict):
        for k, v in no.items():
            ks = str(k)
            p = (prefixo + "." if prefixo else "") + ks if re.fullmatch(r"[A-Za-z_][\w-]*", ks) else prefixo + "['%s']" % ks
            if isinstance(v, (dict, list)):
                _caminhos_json(v, p, saida, prof + 1)
            else:
                saida.append((p, _texto_no(v)))
    elif isinstance(no, list):
        if not no:
            return
        for i, v in enumerate(no[:3]):
            p = "%s[%d]" % (prefixo, i)
            if isinstance(v, (dict, list)):
                _caminhos_json(v, p, saida, prof + 1)
            else:
                saida.append((p, _texto_no(v)))
        if len(no) > 3:
            saida.append(("%s[*]" % prefixo + ("." + next(iter(no[0])) if isinstance(no[0], dict) and no[0] else ""),
                          "(todos os %d itens)" % len(no)))


def listar_caminhos(corpo, formato, f=None):
    """[(caminho, valor de exemplo)] para escolher no fzf."""
    f = f or {}
    if formato == "json":
        dados = json.loads(corpo.decode(f.get("codificacao") or "utf-8", errors="replace"), parse_float=Decimal)
        saida = []
        _caminhos_json(dados, "", saida)
        return [(p, v) for p, v in saida]
    if formato in ("xml", "rss", "atom"):
        if re.search(rb"<!DOCTYPE|<!ENTITY", corpo, re.I):
            raise Erro("XML com DOCTYPE/ENTITY recusado")
        raiz = ET.fromstring(corpo)
        _tira_ns(raiz)
        vistos, saida = set(), []
        def anda(el, caminho):
            if len(saida) >= 300:
                return
            cam = caminho + "/" + el.tag if caminho else el.tag
            txt = (el.text or "").strip()
            if cam not in vistos:
                vistos.add(cam)
                if txt:
                    saida.append((".//" + cam.split("/", 1)[-1] if "/" in cam else cam, _html_para_texto(txt)[:100]))
                for a, v in el.attrib.items():
                    saida.append((".//%s/@%s" % (cam.split("/", 1)[-1] if "/" in cam else cam, a), v[:100]))
            for c in el:
                anda(c, cam)
        anda(raiz, "")
        return saida
    if formato == "csv":
        texto = corpo.decode(f.get("codificacao") or "utf-8", errors="replace")
        sep = f.get("csv_sep") or (";" if texto.count(";") > texto.count(",") else ",")
        linhas = list(csv.reader(io.StringIO(texto), delimiter=sep[0]))
        if len(linhas) < 2:
            return []
        return [(c.strip(), linhas[1][i].strip() if i < len(linhas[1]) else "") for i, c in enumerate(linhas[0])]
    texto = corpo.decode(f.get("codificacao") or "utf-8", errors="replace")
    return [("linha:%d" % (i + 1), l.strip()[:100]) for i, l in enumerate([x for x in texto.splitlines() if x.strip()][:30])]


def buscar_para_assistente(f_base, ts=None):
    """Busca a resposta de uma fonte (rascunho) e devolve (formato_detectado, Resposta)."""
    cfg = ler_conf()
    ts = ts if ts is not None else agora()
    f = efetiva_completa(f_base)
    req = montar_requisicao(f, ts, cfg)
    est = {}
    r = buscar(req, est)
    return detectar_formato(r.corpo, r.headers.get("content-type", "")), r, req


def bonito(corpo, formato, limite=3500):
    t = corpo.decode("utf-8", errors="replace")
    if formato == "json":
        try:
            t = json.dumps(json.loads(t, parse_float=Decimal), ensure_ascii=False, indent=2, default=str)
        except ValueError:
            pass
    t = limpar_texto_bloco(redigir(t))
    return t[:limite] + ("\n… (%d caracteres a mais)" % (len(t) - limite) if len(t) > limite else "")


def limpar_texto_bloco(t):
    """Como limpar_texto, mas preserva quebras de linha e recuo (para mostrar uma resposta inteira)."""
    t = _RE_ESC.sub("", t)
    t = _RE_BIDI.sub("", t)
    return re.sub(r"[\x00-\x08\x0b-\x1f\x7f-\x9f]", "", t)


def cor_ansi(t, ligar):
    """Marcas de cor do tt → ANSI (ou nada)."""
    if ligar:
        t = t.replace(MARCAS["alta"], "\033[32m").replace(MARCAS["baixa"], "\033[31m").replace(MARCAS["neutra"], "\033[90m").replace(MARCAS["fim"], "\033[0m")
        return t + "\033[0m"
    return sem_marcas(t)


def relatorio(nome, f_base, origem, res, cor, meta_antes=None):
    f = efetiva_completa(f_base)
    out = []
    out.append("Fonte: %s  (%s · escopo %s · %s)" % (nome, origem, f["escopo"], "ativa" if f["ativa"] == "1" else "desligada"))
    if f["origem"] == "rede":
        out.append("Pedido: %s %s" % (f["metodo"], res.url or url_publica(f["url"]) or "(sem url)"))
        aut = f["auth"]
        if aut != "nenhuma":
            try:
                ler_segredo(f["segredo"])
                out.append("Autenticação: %s · segredo %s lido de ~/.secrets ✓ (o valor não é mostrado)" % (aut, f["segredo"]))
            except Erro as e:
                out.append("Autenticação: %s · %s" % (aut, e))
        out.append("Resposta: HTTP %s · %d B · %d ms · %d tentativa(s)" % (res.http or "-", res.bytes, res.ms, res.tentativas or 1))
        if res.previa:
            out.append("Início da resposta: " + res.previa[:200])
    elif f["origem"] == "tt":
        out.append("Dado do tt: %s" % f["dado"])
    else:
        out.append("Itens fixos: %d" % len(f["item"]))
    if res.ok:
        if res.extraidos:
            out.append("Extraído (%s, caminho %r): %s" % (f["formato"], f["caminho"] or "(padrão)",
                                                         " | ".join(limpar_texto(x)[:60] for x in res.extraidos[:5])))
        for it in res.itens:
            extra = ""
            if it.var is not None:
                extra = " · variação %s%%" % formatar_num(it.var, 4, "en", False)
            out.append("Resultado: " + cor_ansi(it.linha, cor) + extra)
            if it.acao != "nada":
                out.append("   clique → %s %s" % (it.acao, it.alvo[:80]))
        if not res.itens:
            out.append("Resultado: (nada para mostrar — as condições esconderam o item)")
        out.append("Estado: ok")
    else:
        out.append("ERRO: " + res.erro)
    _n, _e, avisos_cfg = validar_fonte({k: v for k, v in f_base.items() if k != "_sub"}, completo=False)
    for a in avisos_cfg + res.avisos:
        out.append("Aviso: " + a)
    return "\n".join(out)


# --------------------------------------------------------------------------------------------------
# Linha de comando
# --------------------------------------------------------------------------------------------------
AJUDA = """letreiro-fontes.py — fontes (APIs) do letreiro do tt

  listar [--tsv|--nomes] [--todas|--ativas|--inativas] [--categoria C] [--ocultas]
                                    fontes com estado, última atualização, latência e erro (padrão: as ligadas, as suas
                                    e as de fábrica que você já mexeu; --todas inclui as ~150 de fábrica desligadas)
  info NOME                         categoria, descrição, exemplo (validado) e endereço de uma fonte
  ler NOME [--campos]               o arquivo da fonte (ou todos os campos: chave<TAB>valor<TAB>padrão)
  campos                            todos os campos: chave, tipo, padrão, grupo, descrição
  criar NOME chave=valor… [--local] cria a fonte (valida antes; --arquivo F usa um rascunho)
  editar NOME chave=valor… [--local]  altera (-chave remove; --local = só esta máquina)
  remover NOME | restaurar NOME | duplicar A B | ativar NOME | desativar NOME [--local] | mover NOME +1|-1|inicio|fim|N
  testar NOME|--arquivo F [--cor] [--gravar]   busca ao vivo e mostra cada etapa (não grava, salvo --gravar)
  atualizar [NOME…] [--forcar]      o que o vigia chama; respeita ttl, janela, cota, espera após erro
  log [NOME] [N]                    log rotativo (~/.cache/tt-letreiro.log)
  migrar | compilar                 indicador_NOME=/indicadores= → arquivos; recompila a roda
  exportar [NOME…] | importar [ARQ|-] [--sobrescrever] [--nome N]
  pacote | receber                  propagação entre máquinas (stdout/stdin)
  catalogo [listar [--adicionaveis]|perguntas ID|instalar ID [chave=valor…] [--nome N]]
                                    de fábrica: instalar = ligar (traz de volta a que você tirou); modelo: pergunta e cria
  explorar --arquivo F|URL [--caminhos|--bruto]    assistente: formato, resposta formatada, caminhos
  aplicar F chave=valor…            edita um rascunho (validação parcial)    salvar F NOME [--local]   rascunho → fonte
  rascunho NOME                     a fonte como rascunho editável (para o formulário do painel)
  validar --arquivo F | segredo NOME (valor no stdin) | linha
"""


def _kv_e_flags(args):
    kv, flags, pos = [], {}, []
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("--local", "--cor", "--gravar", "--forcar", "--tsv", "--nomes", "--campos", "--caminhos", "--bruto", "--sobrescrever",
                 "--todas", "--ativas", "--inativas", "--ocultas", "--adicionaveis"):
            flags[a[2:]] = True
        elif a in ("--arquivo", "--nome", "--categoria") and i + 1 < len(args):
            flags[a[2:]] = args[i + 1]
            i += 1
        elif "=" in a and re.match(r"^-?[A-Za-z_][\w.]*=", a.lstrip("-")) and not a.startswith("--"):
            kv.append(a)
        elif a.startswith("-") and len(a) > 1 and not a.startswith("--") and chave_valida(a[1:]):
            kv.append(a)
        else:
            pos.append(a)
        i += 1
    return pos, kv, flags


def _saida(t=""):
    sys.stdout.write(t + ("\n" if not t.endswith("\n") else ""))


def _falha(msg, codigo=1):
    sys.stderr.write("tt: %s\n" % redigir(msg))
    return codigo


def _ler_rascunho(caminho):
    if not os.path.exists(caminho):
        return {}
    return ler_arquivo_conf(caminho)


def _fonte_para_teste(pos, flags):
    if flags.get("arquivo"):
        d = _ler_rascunho(flags["arquivo"])
        n, erros, _a = validar_fonte(d, completo=False)
        if erros:
            raise Erro("; ".join(erros))
        return "(rascunho)", n, "rascunho"
    if not pos:
        raise Erro("diga o nome da fonte (ou --arquivo RASCUNHO)")
    f, o = fonte_efetiva(pos[0])
    if f is None:
        raise Erro("não existe a fonte %s (tt --letreiro-listar)" % pos[0])
    return pos[0], f, o


def cli(argv):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    if len(argv) < 2 or argv[1] in ("ajuda", "-h", "--help"):
        _saida(AJUDA)
        return 0 if len(argv) >= 2 else 2
    cmd, resto = argv[1], argv[2:]
    pos, kv, flags = _kv_e_flags(resto)
    try:
        if cmd == "campos":
            for k, t, p, g, d in CAMPOS:
                _saida("\t".join((k, t, p, g, d)))
        elif cmd == "listar":
            filtro = "todas" if (flags.get("todas") or flags.get("ocultas")) else "ativas" if flags.get("ativas") else "inativas" if flags.get("inativas") else "padrao"
            est = listar_estados(filtro=filtro, categoria=flags.get("categoria") or "", ocultas=bool(flags.get("ocultas")))
            if flags.get("tsv"):
                _saida(tsv(est))
            elif flags.get("nomes"):
                _saida("\n".join(e["nome"] for e in est))
            else:
                _saida(tabela(est))
        elif cmd == "info":
            if not pos:
                return _falha("uso: info NOME  (descrição, categoria e exemplo de uma fonte)", 2)
            f, o = fonte_efetiva(pos[0])
            if f is None:
                return _falha("não existe a fonte %s" % pos[0])
            e = FABRICA.get(pos[0]) or {}
            _saida("categoria\t%s" % CAT_ROTULO.get(categoria_de(pos[0], f, o), "?"))
            _saida("origem\t%s" % ("de fábrica" if pos[0] in NATIVAS else "sua"))
            _saida("descricao\t%s" % limpar_texto(f.get("descricao", "")))
            if e.get("exemplo"):
                _saida("exemplo\t%s" % limpar_texto(e["exemplo"]))
                _saida("validada\t%s" % e.get("validada", ""))
            _saida("url\t%s" % (url_publica(f["url"]) if f.get("url") else "(%s)" % f.get("origem", "")))
        elif cmd == "ler":
            if not pos:
                return _falha("uso: ler NOME [--campos]", 2)
            f, o = fonte_efetiva(pos[0])
            if f is None:
                return _falha("não existe a fonte %s" % pos[0])
            if flags.get("campos"):
                c = efetiva_completa(f)
                no_arq = set(f)
                for k, t, p, g, d in CAMPOS:
                    if k in ("versao", "mudada"):
                        continue
                    v = c[k]
                    for x in (v if isinstance(v, list) else [v]):
                        _saida("\t".join((k, str(x), p, "1" if k in no_arq else "0")))
                    if isinstance(v, list) and not v:
                        _saida("\t".join((k, "", p, "0")))
                for k in sorted(k for k in f if k.startswith(("campo.", "var."))):
                    _saida("\t".join((k, str(f[k]), "", "1")))
            else:
                _saida("# %s (%s)" % (pos[0], o))
                _saida(serializar({k: v for k, v in f.items() if k != "_sub"}))
        elif cmd in ("criar", "editar"):
            if not pos:
                return _falha("uso: %s NOME chave=valor…" % cmd, 2)
            if cmd == "criar":
                if flags.get("arquivo"):
                    kv = ["%s=%s" % (k, x) for k, v in _ler_rascunho(flags["arquivo"]).items() for x in (v if isinstance(v, list) else [v])] + kv
                erros, avisos = criar_fonte(pos[0], kv, local=bool(flags.get("local")))
            else:
                erros, avisos = editar_fonte(pos[0], kv, local=bool(flags.get("local")))
            for a in avisos:
                sys.stderr.write("aviso: %s\n" % redigir(a))
            if erros:
                for e in erros:
                    sys.stderr.write("erro: %s\n" % redigir(e))
                return 1
            _saida("%s: %s" % (pos[0], "criada" if cmd == "criar" else "alterada"))
        elif cmd == "remover":
            for m in remover_fonte(pos[0] if pos else ""):
                _saida(pos[0] + ": " + m)
        elif cmd == "restaurar":
            if not pos:
                return _falha("uso: restaurar NOME  (fonte de fábrica: volta ao padrão e fica na lista)", 2)
            for m in restaurar_fonte(pos[0]):
                _saida(m)
        elif cmd == "categorias":
            for k, rot in CAT_ROTULO.items():
                _saida("%s\t%s" % (k, rot))
        elif cmd == "duplicar":
            if len(pos) != 2:
                return _falha("uso: duplicar ORIGEM NOVO", 2)
            duplicar_fonte(pos[0], pos[1])
            _saida("%s: duplicada de %s" % (pos[1], pos[0]))
        elif cmd in ("ativar", "desativar"):
            if not pos:
                return _falha("uso: %s NOME [--local]" % cmd, 2)
            erros, _a = ativar_fonte(pos[0], cmd == "ativar", local=bool(flags.get("local")))
            if erros:
                return _falha("; ".join(erros))
            _saida("%s: %s%s" % (pos[0], "ativada" if cmd == "ativar" else "desativada", " (só nesta máquina)" if flags.get("local") else ""))
        elif cmd == "mover":
            if len(pos) != 2:
                return _falha("uso: mover NOME +1|-1|inicio|fim|N", 2)
            _saida(" ".join(mover_fonte(pos[0], pos[1])))
        elif cmd == "testar":
            signal.alarm(120)
            nome, f, o = _fonte_para_teste(pos, flags)
            cfg = ler_conf()
            if flags.get("gravar") and nome != "(rascunho)":
                with Trava(esperar=30) as t:
                    r = atualizar_fonte(nome, f, cfg, forcar=True) if t else "pulada: ocupado"
                _saida("atualização gravada: " + r)
            meta = dict(ler_meta(nome)) if nome != "(rascunho)" else {}
            res = executar(nome, f, agora(), meta, cfg)
            _saida(relatorio(nome, f, o, res, bool(flags.get("cor"))))
            return 0 if res.ok else 1
        elif cmd == "atualizar":
            signal.alarm(170)
            r = atualizar(pos or None, forcar=bool(flags.get("forcar")))
            if os.environ.get("TT_LETREIRO_VERBOSO") == "1" or flags.get("forcar"):
                for n, v in r.items():
                    _saida("%s: %s" % (n or "-", v))
        elif cmd == "log":
            nome = pos[0] if pos and not pos[0].isdigit() else ""
            n = int(pos[-1]) if pos and pos[-1].isdigit() else 40
            _saida(ver_log(nome, n) or "(sem registros)")
        elif cmd == "migrar":
            for m in migrar() or ["nada a migrar"]:
                _saida(m)
        elif cmd == "compilar":
            _saida("%d fonte(s) na roda" % len(compilar()))
        elif cmd == "exportar":
            t, erros = pacote_texto(pos or None)
            sys.stdout.write(t)
            for e in erros:
                sys.stderr.write("tt: não exportada — %s\n" % redigir(e))
            return 1 if erros else 0
        elif cmd == "importar":
            if not pos or pos[0] == "-":
                texto = sys.stdin.read(2_000_000)
            else:
                texto = ler_texto(pos[0])
                if not texto:
                    return _falha("não consegui ler %s" % pos[0])
            for m in importar(texto, bool(flags.get("sobrescrever")), flags.get("nome")):
                _saida(m)
        elif cmd == "pacote":
            t, erros = pacote_texto(None, so_globais=True, com_removidas=True)
            sys.stdout.write(t)
            for e in erros:
                sys.stderr.write("tt: não propagada — %s\n" % redigir(e))
        elif cmd == "receber":
            for m in receber(sys.stdin.read(2_000_000)):
                _saida(m)
        elif cmd == "catalogo":
            sub = pos[0] if pos else "listar"
            if sub == "listar":
                ocultas = {n for n in ler_ocultas() if pode_ocultar(n)}
                linhas = []
                if not flags.get("adicionaveis"):
                    for n in sorted(NATIVAS, key=lambda x: (x not in ORIGINAIS, categoria_de(x, NATIVAS[x], "nativa"), x)):
                        f, o = fonte_efetiva(n)
                        est = "fora da lista" if n in ocultas else ("ligada" if f.get("ativa", "1") == "1" else "desligada")
                        linhas.append((n, NATIVAS[n].get("descricao", n), "", "fabrica", categoria_de(n, NATIVAS[n], "nativa"), est))
                else:
                    for n in sorted(ocultas):
                        linhas.append((n, NATIVAS[n].get("descricao", n), "", "fabrica", categoria_de(n, NATIVAS[n], "nativa"), "fora da lista"))
                for id_, (d, conf, perg) in CATALOGO.items():
                    linhas.append((id_, d, " ".join(p[0] for p in perg), "modelo", (MODELOS.get(id_) or {}).get("categoria", "outras"), "novo"))
                for n, d, perg, tipo, cat, est in linhas:
                    if flags.get("tsv"):
                        _saida("\t".join((n, d, perg, tipo, cat, est)))
                    else:
                        _saida("%-22s %-10s %s%s" % (n, est if tipo == "fabrica" else "modelo", d, ("  [pergunta: %s]" % ", ".join(perg.split())) if perg else ""))
            elif sub == "perguntas" and len(pos) > 1:
                for var, perg, padrao in CATALOGO.get(pos[1], ("", None, []))[2]:
                    _saida("%s\t%s\t%s" % (var, perg, padrao))
            elif sub == "instalar" and len(pos) > 1:
                nome, erros, avisos = catalogo_instalar(pos[1], [x for x in resto if "=" in x and not x.startswith("--")], flags.get("nome"))
                for a in avisos:
                    sys.stderr.write("aviso: %s\n" % redigir(a))
                if erros:
                    for e in erros:
                        sys.stderr.write("erro: %s\n" % redigir(e))
                    return 1
                _saida("%s: instalada e ativa" % nome)
            else:
                return _falha("uso: catalogo [listar|perguntas ID|instalar ID [chave=valor…] [--nome N]]", 2)
        elif cmd == "explorar":
            signal.alarm(90)
            if flags.get("arquivo"):
                base = _ler_rascunho(flags["arquivo"])
            elif pos:
                base = {"url": pos[0]}
            else:
                return _falha("uso: explorar --arquivo RASCUNHO | URL", 2)
            n, erros, _a = validar_fonte(base, completo=False)
            if erros:
                raise Erro("; ".join(erros))
            fmt, r, req = buscar_para_assistente(n)
            if n.get("formato") and flags.get("arquivo") and base.get("formato"):
                fmt = n["formato"] if n["formato"] != "json" or fmt == "json" else fmt
            if flags.get("caminhos"):
                for c, v in listar_caminhos(r.corpo, fmt, efetiva_completa(n)):
                    _saida("%s\t%s" % (c, limpar_texto(redigir(v))[:100]))
            elif flags.get("bruto"):
                _saida(bonito(r.corpo, fmt))
            else:
                _saida("#formato=%s" % fmt)
                _saida("#http=%s · %d B · %d ms · %s" % (r.status, len(r.corpo), r.ms, url_publica(req["url"])))
                _saida(bonito(r.corpo, fmt))
        elif cmd == "aplicar":
            if not pos:
                return _falha("uso: aplicar RASCUNHO chave=valor…", 2)
            d = juntar_kv(_ler_rascunho(pos[0]), kv)
            n, erros, avisos = validar_fonte(d, completo=False)
            if erros:
                for e in erros:
                    sys.stderr.write("erro: %s\n" % redigir(e))
                return 1
            escrever_atomico(pos[0], serializar(n), 0o600)
            for a in avisos:
                _saida("aviso: " + redigir(a))
        elif cmd == "salvar":
            if len(pos) != 2:
                return _falha("uso: salvar RASCUNHO NOME", 2)
            erros, avisos = salvar_rascunho(pos[1], _ler_rascunho(pos[0]), local=bool(flags.get("local")))
            for a in avisos:
                sys.stderr.write("aviso: %s\n" % redigir(a))
            if erros:
                for e in erros:
                    sys.stderr.write("erro: %s\n" % redigir(e))
                return 1
            _saida("%s: salva" % pos[1])
        elif cmd == "rascunho":
            if not pos:
                return _falha("uso: rascunho NOME  (imprime a fonte como rascunho editável)", 2)
            _saida(serializar(rascunho_de(pos[0])))
        elif cmd == "validar":
            d = _ler_rascunho(flags["arquivo"]) if flags.get("arquivo") else {}
            n, erros, avisos = validar_fonte(d, completo=True)
            for a in avisos:
                _saida("aviso: " + redigir(a))
            for e in erros:
                _saida("erro: " + redigir(e))
            return 1 if erros else 0
        elif cmd == "segredo":
            if not pos:
                return _falha("uso: segredo NOME  (o valor vem pelo stdin)", 2)
            valor = sys.stdin.read(4096)
            if not valor.strip():
                return _falha("valor vazio — nada gravado")
            _saida(segredo_gravar(pos[0], valor))
        elif cmd == "linha":
            _saida(linha_atual())
        else:
            return _falha("comando desconhecido: %s (letreiro-fontes.py ajuda)" % cmd, 2)
    except Erro as e:
        return _falha(str(e))
    except BrokenPipeError:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(cli(sys.argv))
