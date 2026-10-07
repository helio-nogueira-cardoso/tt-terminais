#!/usr/bin/env python3
"""Percentual de uso da janela de cada conta de IA (usado pelo claude-conta e pelo claude-rot).

Uso: contas-uso.py [--ttl SEGUNDOS] CONTA=ALVO ...
  ALVO é a pasta da credencial do Claude (a principal é ~/.claude), ou "codex" / "kiro".

Uma linha TSV por conta, na ordem pedida:
  conta  pico  volta  texto  fonte  email  folga
pico   maior percentual entre as janelas (0–100, inteiro; "-" = desconhecido; todo campo vazio sai "-")
volta  epoch em que a janela mais cheia reinicia
texto  resumo para gente: "5h 23% · 7d 65%", "mês 40%"
fonte  ao-vivo | cache | reiniciou (a janela do cache já virou) | desconhecido
folga  quanto dá para usar agora, 0–100, olhando todas as janelas e quando cada uma reinicia
       (veja folga(); o ia-rot escolhe por ela)

Nada de segredo sai daqui: o token só vai no cabeçalho da consulta ao próprio provedor. Token
vencido não é renovado (a renovação troca o refresh token e derrubaria a sessão aberta da conta):
vale o último valor do cache, e ele é descartado quando a janela já reiniciou.
"""
import base64
import concurrent.futures
import datetime
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time
import urllib.request

AGORA = time.time()
CACHE = pathlib.Path(os.environ.get("XDG_CACHE_HOME", pathlib.Path.home() / ".cache")) / "claude-rot.uso.json"
TIMEOUT = 8


def epoch(iso):
    if not iso:
        return None
    try:
        return datetime.datetime.fromisoformat(str(iso).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def pedir(url, cabecalhos):
    req = urllib.request.Request(url, headers={"User-Agent": "tt-contas-uso", **cabecalhos})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.load(r)


def pct(v):
    return None if v is None else max(0, min(100, round(float(v))))


def claude(pasta):
    cred = json.loads((pathlib.Path(pasta) / ".credentials.json").read_text()).get("claudeAiOauth") or {}
    if not cred.get("accessToken"):
        raise LookupError("sem credencial")
    if cred.get("expiresAt", 0) / 1000 < AGORA + 30:
        raise TimeoutError("token vencido")
    d = pedir("https://api.anthropic.com/api/oauth/usage",
              {"Authorization": "Bearer " + cred["accessToken"], "anthropic-beta": "oauth-2025-04-20"})
    janelas = []
    for chave, rotulo in (("five_hour", "5h"), ("seven_day", "7d"), ("seven_day_opus", "7d-opus")):
        j = d.get(chave) or {}
        if j.get("utilization") is not None:
            janelas.append((rotulo, pct(j["utilization"]), epoch(j.get("resets_at"))))
    return janelas, ""


def codex(_):
    casa = pathlib.Path(os.environ.get("CODEX_HOME", pathlib.Path.home() / ".codex"))
    tokens = json.loads((casa / "auth.json").read_text()).get("tokens") or {}
    tok = tokens.get("access_token")
    if not tok:
        raise LookupError("sem login ChatGPT")
    try:
        exp = json.loads(base64.urlsafe_b64decode(tok.split(".")[1] + "==")).get("exp", 0)
    except (ValueError, IndexError):
        exp = 0
    if exp and exp < AGORA + 30:
        raise TimeoutError("token vencido")
    cab = {"Authorization": "Bearer " + tok}
    if tokens.get("account_id"):
        cab["chatgpt-account-id"] = tokens["account_id"]
    d = pedir("https://chatgpt.com/backend-api/wham/usage", cab)
    janelas = []
    rl = d.get("rate_limit") or {}
    for chave in ("primary_window", "secondary_window"):
        j = rl.get(chave) or {}
        if j.get("used_percent") is None:
            continue
        seg = j.get("limit_window_seconds") or 0
        rotulo = "5h" if seg == 18000 else "7d" if seg == 604800 else f"{round(seg / 3600)}h"
        volta = j.get("reset_at") or (AGORA + j["reset_after_seconds"] if j.get("reset_after_seconds") else None)
        janelas.append((rotulo, pct(j["used_percent"]), volta))
    if rl.get("limit_reached") and janelas and max(p for _, p, _ in janelas) < 100:
        janelas.append(("limite", 100, max(v or 0 for _, _, v in janelas) or None))
    return janelas, d.get("email") or ""


def kiro(_):
    kiro_cli = shutil.which("kiro-cli")
    if not kiro_cli:
        raise LookupError("kiro-cli não instalado")
    saida = subprocess.run([kiro_cli, "chat", "--no-interactive", "/usage"], capture_output=True, text=True,
                           timeout=40, stdin=subprocess.DEVNULL).stdout
    saida = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", saida)
    m = re.search(r"Credits \(([\d.,]+) of ([\d.,]+)[^)]*\),\s*([\d.]+)%", saida)
    if not m:
        raise LookupError("resposta do /usage sem créditos")
    volta = None
    r = re.search(r"resets on (\d{4}-\d{2}-\d{2})", saida)
    if r:
        volta = epoch(r.group(1) + "T00:00:00")
    return [("mês", pct(m.group(3)), volta)], ""


def consultar(alvo):
    if alvo == "codex":
        return codex(alvo)
    if alvo == "kiro":
        return kiro(alvo)
    return claude(alvo)


def hora(t):
    if not t:
        return ""
    d = datetime.datetime.fromtimestamp(t + 30)  # 20:49:59.6 é 20:50
    return d.strftime("%H:%M") if t - AGORA < 20 * 3600 else d.strftime("%d/%m")


def resumir(janelas):
    janelas = [j for j in janelas if j[0] != "limite"] or janelas
    return " · ".join(f"{r} {p}%" + (f" ({hora(v)})" if p >= 80 and v else "") for r, p, v in janelas)


DURACAO = {"5h": 5 * 3600, "7d": 7 * 86400, "7d-opus": 7 * 86400, "mês": 30 * 86400}


def duracao(rotulo):
    if rotulo in DURACAO:
        return DURACAO[rotulo]
    m = re.fullmatch(r"(\d+)h", rotulo)
    return int(m.group(1)) * 3600 if m else None


def folga(janelas):
    """Quanto dá para usar a conta agora, 0–100 (maior = melhor); a janela mais apertada manda.

    Janela curta (até 1 dia, a de 5 h): o que sobra, mais o que volta se ela reinicia logo (90% usada
    que vira em 10 min quase não pesa). Janela longa (semana, mês): o que sobra dividido pela fração
    do período que ainda falta, isto é, a folga em relação a gastar por igual até o reinício. 20%
    livres com 6 dias pela frente é pouco; os mesmos 20% a 3 h do reinício são "use ou perde".
    """
    notas = []
    for rotulo, p, volta in janelas:
        if rotulo == "limite":
            return 0
        resta = 100 - p
        d = duracao(rotulo)
        falta = 1.0 if not (d and volta) else max(0.02, min(1.0, (volta - AGORA) / d))
        notas.append(resta + p * (1 - falta) if d and d <= 86400 else min(100, resta / falta))
    return round(min(notas)) if notas else None


def linha(conta, janelas, fonte, email):
    if not janelas:
        return [conta, "", "", "", fonte, email, ""]
    rotulo, pico, volta = max(janelas, key=lambda j: (j[1], j[2] or 0))
    return [conta, str(pico), str(int(volta)) if volta else "", resumir(janelas), fonte, email, str(folga(janelas))]


def main(args):
    ttl = 0
    if args[:1] == ["--ttl"]:
        ttl, args = float(args[1]), args[2:]
    pedidos = [a.split("=", 1) for a in args if "=" in a]
    try:
        cache = json.loads(CACHE.read_text())
    except (OSError, ValueError):
        cache = {}

    def um(par):
        conta, alvo = par
        c = cache.get(conta) or {}
        if ttl and c.get("alvo") == alvo and AGORA - c.get("quando", 0) < ttl:
            return conta, alvo, c.get("janelas") or [], "cache", c.get("email", ""), False
        try:
            janelas, email = consultar(alvo)
            return conta, alvo, janelas, "ao-vivo", email, True
        except Exception:  # sem rede, token vencido, resposta nova: cai para o cache
            if c.get("alvo") != alvo or not c.get("janelas"):
                return conta, alvo, [], "desconhecido", c.get("email", ""), False
            # Janela que já virou desde a última consulta recomeça do zero.
            janelas = [j if not j[2] or j[2] > AGORA else (j[0], 0, None) for j in c["janelas"] if j[0] != "limite" or j[2] > AGORA]
            fonte = "cache" if any(j[2] for j in janelas) else "reiniciou"
            return conta, alvo, janelas, fonte, c.get("email", ""), False

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        resultados = list(ex.map(um, pedidos))
    mudou = False
    for conta, alvo, janelas, fonte, email, novo in resultados:
        if novo:
            cache[conta] = {"alvo": alvo, "quando": AGORA, "janelas": janelas, "email": email}
            mudou = True
        # "-" no lugar de vazio: o read do bash junta tabs seguidos (tab é espaço para o IFS).
        print("\t".join(x or "-" for x in linha(conta, janelas, fonte, email)))
    if mudou:
        try:
            CACHE.parent.mkdir(parents=True, exist_ok=True)
            tmp = CACHE.with_suffix(f".{os.getpid()}")
            tmp.write_text(json.dumps(cache))
            tmp.chmod(0o600)
            tmp.replace(CACHE)
        except OSError:
            pass


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        sys.exit(0)
    main(sys.argv[1:])
