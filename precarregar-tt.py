#!/usr/bin/env python3
"""Preparação passiva de pontes. stdlib; nenhuma sessão remota é anexada antes do clique.

O coordenador pertence ao socket tmux da máquina da TELA. Cada candidato pertence a
um cliente (tty + pid + nascimento), não à sessão que vários aparelhos podem olhar.
O terminal SSH fica esperando um bilhete de ativação de uso único. Não recebe teclas,
saída de agentes ou foco durante a especulação. Protocolo v1, com nonce por ponte.
"""
import base64
import collections
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import secrets
import select
import shlex
import signal
import socket
import subprocess
import sys
import tempfile
import time

import precarregar_remoto as protocol


# Tab é preservado tanto pelo tmux 3.5 quanto pelo 3.8; 0x1f vira "\\037" no 3.5.
SEP = "\t"
PREFIX = "TT_PRE_1 "
TMUX = os.environ.get("TT_TMUX_BIN", "tmux")
HERE = Path(__file__).resolve().parent
CONF = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "tt"
STATE = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "tt/precarregamento"
SSH_ARGS = []
REMOTE_PATH = os.environ.get("TT_PRE_PATH_REMOTO", 'PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"; export PATH; ')
MAX_MESSAGE = 65536


def read_config():
    try:
        return dict(line.split("=", 1) for line in (CONF / "config").read_text().splitlines()
                    if "=" in line and not line.startswith("#"))
    except OSError:
        return {}


def integer(value, default, low, high):
    try:
        return max(low, min(high, int(value)))
    except (ValueError, TypeError):
        return default


def text_ok(value):
    return isinstance(value, str) and 0 < len(value) <= 512 and not any(ord(c) < 32 for c in value)


def execute(args, timeout=3, **kwargs):
    try:
        r = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, timeout=timeout, **kwargs)
        return r.returncode, r.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.TimeoutExpired):
        return 124, ""


def tmux(*args):
    return execute([TMUX, *args])


def atomic_json(path, value):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".novo-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(value, f, ensure_ascii=False, separators=(",", ":"))
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def identity(target):
    return target["machine"] + SEP + (target.get("id") or target["name"])


def rank(target, index, history, current, intent, now):
    """Sinais limitados: fixada/esquerda são fortes, mas não monopolizam a fila."""
    key = identity(target)
    reasons = []
    score = 0.0
    if index is not None:
        score += 40 + 35 / (1 + index * .45)
        reasons.append("fixada %d (esquerda)" % (index + 1))
    visits = [v for v in history if v.get("to") == key and 0 <= now - v.get("time", 0) < 7 * 86400]
    if visits:
        age = now - max(v["time"] for v in visits)
        recent = 50 * math.exp(-age / 1800)
        frequency = min(35, sum(6 * math.exp(-(now - v["time"]) / 86400) for v in visits))
        transitions = min(45, sum(12 * math.exp(-(now - v["time"]) / 14400)
                                  for v in visits if v.get("from") == current))
        score += recent + frequency + transitions
        reasons.append("recente/frequente")
        if transitions:
            reasons.append("alternância com a atual")
    if intent and intent.get("key") == key and .3 <= now - intent.get("time", 0) <= 8:
        score += 90
        reasons.append("seleção no menu")
    return score, reasons


def remote_command(*args):
    # Código pequeno, somente memória. Sem cópia/instalação ou versão nova obrigatória lá.
    return REMOTE_PATH + "exec python3 -c " + shlex.quote(Path(protocol.__file__).read_text()) + " " + shlex.join(args)


def decode_ticket(output, token):
    match = re.search(re.escape(PREFIX + token + " ") + r"([A-Za-z0-9+/=]+)", output)
    if not match:
        return None
    remote = json.loads(base64.b64decode(match[1], validate=True))
    if (not isinstance(remote, dict) or not re.fullmatch(r"\$[0-9]+", str(remote.get("sid", "")))
            or not str(remote.get("server", "")).isdigit() or not str(remote.get("pid", "")).isdigit()
            or not text_ok(remote.get("name")) or not isinstance(remote.get("id", ""), str)):
        raise ValueError("identidade inválida")
    return remote


class TmuxUnavailable(RuntimeError):
    """Sem servidor tmux: não há tela para preparar, mas o status continua disponível."""


def runtime():
    socket_name = os.environ.get("TMUX", "").split(",")[0]
    if not socket_name:
        rc, socket_name = tmux("display-message", "-p", "#{socket_path}")
        if rc:
            raise TmuxUnavailable("tmux indisponível")
    key = "|".join([str(Path.home()), os.environ.get("TT_RT", ""), socket_name.strip(), str(HERE)])
    digest = hashlib.sha256(key.encode()).hexdigest()[:16]
    # AF_UNIX no macOS aceita ~104 bytes: prefere /tmp curto. No Android essa
    # pasta não é gravável; o TMPDIR privado do Termux também cabe no socket.
    root = Path("/tmp")
    if not root.is_dir() or not os.access(root, os.W_OK | os.X_OK):
        root = Path(tempfile.gettempdir())
    folder = root / ("tt-pre-%d-%s" % (os.getuid(), digest))
    folder.mkdir(mode=0o700, exist_ok=True)
    st = folder.lstat()
    if folder.is_symlink() or st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise RuntimeError("runtime de pré-carregamento sem isolamento")
    return folder


class UncertainReply(Exception):
    """Pedido enviado; nunca repetir navegação pelo caminho legado após um timeout."""


def send_request(folder, data, timeout=3):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
        conn.settimeout(timeout)
        conn.connect(str(folder / "socket"))
        try:
            conn.sendall(json.dumps(data).encode() + b"\n")
            raw = b""
            while b"\n" not in raw and len(raw) < MAX_MESSAGE:
                block = conn.recv(4096)
                if not block:
                    break
                raw += block
            return json.loads(raw)
        except (OSError, ValueError) as exc:
            raise UncertainReply from exc


class Coordinator:
    def __init__(self, folder):
        self.folder = folder
        self.machine = os.environ.get("TT_PRE_MACHINE") or read_config().get("nome", socket.gethostname().split(".")[0])
        self.tt = os.environ.get("TT_PRE_TT", str(HERE / "tt"))
        self.candidates = {}
        self.clients = {}
        self.current = {}
        self.requests = {}
        self.latest = {}
        self.intents = {}
        self.failures = {}
        self.metrics = collections.Counter()
        self.samples = collections.deque(maxlen=100)
        self.history = []
        self.running = True
        self.next_scan = 0
        self.last_event = time.monotonic()
        self.last_tick = time.monotonic()
        self.last_wall = time.time()
        self.cooldown_until = 0
        self.energy_at = 0
        self.energy = (None, False)
        self.history_file = STATE / (folder.name + ".json")
        self.package_stamp = (HERE / "precarregar-tt.py").stat().st_mtime_ns
        try:
            saved = json.loads(self.history_file.read_text())
            if isinstance(saved, list):
                self.history = [v for v in saved[-500:] if isinstance(v, dict) and
                                isinstance(v.get("time"), (int, float)) and
                                0 <= time.time() - v["time"] < 7 * 86400 and
                                isinstance(v.get("target"), dict) and
                                isinstance(v["target"].get("id", ""), str) and
                                all(text_ok(v["target"].get(k)) for k in ("machine", "name"))]
                if saved != self.history:
                    atomic_json(self.history_file, self.history)
        except (OSError, ValueError, TypeError):
            pass

    def settings(self):
        c = read_config()
        mode = c.get("precarregar", "auto")
        if os.environ.get("TT_PRECARREGAR") == "0":
            mode = "off"
        total = integer(c.get("precarregar_total"), 6, 1, 12)
        per_client = integer(c.get("precarregar_por_tela"), 3, 1, 6)
        if time.monotonic() >= self.energy_at:
            self.energy_at = time.monotonic() + 60
            self.energy = battery()
        pct, charging = self.energy
        eco = mode == "economico" or "com.termux" in os.environ.get("PREFIX", "") or (pct is not None and pct <= 20 and not charging)
        if eco:
            total, per_client = min(total, 2), 1
        if mode == "off" or (pct is not None and pct < 10 and not charging):
            total = 0
        return mode, total, per_client

    def machines(self):
        machines = {}
        try:
            for line in (CONF / "maquinas").read_text().splitlines():
                c = line.split()
                if len(c) >= 2 and not c[0].startswith("#") and c[1] != "-" and c[3:4] != ["oculta"]:
                    label = c[2] if len(c) > 2 else c[0].split(".")[0]
                    if label != self.machine:
                        machines[label] = c[1] + "@" + c[0]
        except OSError:
            pass
        return machines

    def resolve_machine(self, dest):
        for label, address in self.machines().items():
            if dest in (label, address):
                return label
            # O tt converte nome curto em DNS completo da MESMA tailnet; não confundir usuários.
            if "@" in dest and dest.split("@", 1)[0] == address.split("@", 1)[0]:
                h, other = address.split("@", 1)[1], dest.split("@", 1)[1]
                if "." not in h and other.startswith(h + "."):
                    return label
        return None

    def scan_clients(self):
        fmt = SEP.join(["#{client_name}", "#{client_pid}", "#{client_created}", "#{client_activity}",
                        "#{client_termname}", "#{session_name}", "#{@ponte_alvo}", "#{@ponte}",
                        "#{@tt_session_id}", "#{client_width}", "#{client_height}", "#{@tt_pre_id}"])
        rc, out = tmux("list-clients", "-F", fmt)
        if rc:
            self.running = False
            return
        clients = {}
        for line in out.splitlines():
            c = line.split(SEP)
            if len(c) != 12 or c[4].startswith(("tmux", "screen")):
                continue  # quem prepara é a máquina da tela, nunca cada salto da malha
            if not c[3].isdigit() or time.time() - int(c[3]) > 600:
                continue
            clients[c[0]] = {"generation": c[1] + ":" + c[2], "session": c[5],
                             "width": c[9], "height": c[10]}
            if c[6] and "|" in c[6]:
                dest, name = c[6].split("|", 1)
                label = self.resolve_machine(dest)
                target = {"machine": label, "name": name, "id": c[11]} if label else None
                known = next((v for v in self.candidates.values() if v["bridge"] == c[5]), None)
                if known:
                    target = known["target"]
            elif c[5].startswith("_") or c[7]:
                target = None
            else:
                target = {"machine": self.machine, "name": c[5], "id": c[8]}
            if target:
                key = identity(target)
                old = self.current.get(c[0])
                # Só transição observada na tela, nunca criação/preparação de ponte.
                if (old and old != key and c[0] in self.clients
                        and self.clients[c[0]]["generation"] == clients[c[0]]["generation"]
                        and self.clients[c[0]]["session"] != c[5]):
                    self.history.append({"from": old, "to": key, "time": time.time(), "target": target})
                    self.history = [v for v in self.history[-500:] if 0 <= time.time() - v["time"] < 7 * 86400]
                    atomic_json(self.history_file, self.history)
                self.current[c[0]] = key
        self.clients = clients
        for c in list(self.requests):
            if c not in clients:
                del self.requests[c]

    def fixed(self):
        result = []
        try:
            for line in (CONF / "fixadas").read_text().splitlines():
                c = line.split("\t")
                if len(c) >= 2 and all(text_ok(v) for v in c[:2]):
                    result.append({"machine": c[0], "name": c[1], "id": c[2] if len(c) > 2 else ""})
        except OSError:
            pass
        return result

    def ranking(self, client):
        fixed = self.fixed()
        targets = {identity(t): (t, i) for i, t in enumerate(fixed)}
        for visit in self.history:
            t = visit["target"]
            targets.setdefault(identity(t), (t, None))
        intent = self.intents.get(client)
        if intent:
            targets.setdefault(intent["key"], (intent["target"], None))
        machines = self.machines()
        now = time.time()
        ranked = []
        for key, (target, index) in targets.items():
            if target["machine"] not in machines or key == self.current.get(client):
                continue
            score, reasons = rank(target, index, self.history, self.current.get(client), intent, now)
            existing = self.candidates.get((client, key))
            if existing and existing["state"] in ("preparing", "ready"):
                score += 12  # margem para não desmontar trabalho por diferenças pequenas
                reasons.append("já preparada")
            blocked = any(self.failures.get(k, {}).get("until", 0) > time.monotonic()
                          for k in (target["machine"], key))
            if score > 0:
                ranked.append({"target": target, "key": key, "score": round(score, 1),
                               "reasons": reasons, "blocked": blocked})
        return sorted(ranked, key=lambda v: (-v["score"], v["key"]))

    def still_owned(self, item):
        rc, out = tmux("display-message", "-p", "-t", "=" + item["bridge"] + ":",
                       "#{@tt_pre_token}|#{session_attached}")
        return not rc and out.strip() == item["token"] + "|0"

    def discard(self, key):
        item = self.candidates.get(key)
        if not item or item["state"] == "active":
            return
        proc = item.get("confirm")
        if proc and proc.poll() is None:
            proc.kill()
            proc.communicate()
        if self.still_owned(item):
            tmux("kill-session", "-t", "=" + item["bridge"])
        self.candidates.pop(key, None)

    def prepare(self, client, target, demand=False):
        key = (client, identity(target))
        if key in self.candidates:
            return self.candidates[key]
        if client not in self.clients:
            return None
        dest = self.machines().get(target["machine"])
        if not dest:
            return None
        token = secrets.token_hex(16)
        bridge = "tt-pre-" + token[:16]
        args = [self.tt, "--precarregar-ponte", dest, target["name"], target.get("id", ""), token, bridge]
        client_data = self.clients[client]
        # A janela é só um transporte esperando bilhete; @ponte a mantém fora de listas/snapshots.
        cmd = ["new-session", "-d", "-s", bridge, "-x", client_data["width"], "-y", client_data["height"], shlex.join(args)]
        for option, value in [("@ponte", dest), ("@ponte_alvo", dest + "|" + target["name"]),
                              ("@ponte_dono", client), ("@tt_pre_token", token), ("@tt_pre_owner", self.folder.name),
                              ("@tt_pre_estado", "espera"), ("@nome_auto", "0"), ("status", "off")]:
            cmd.extend([";", "set-option", "-t", "=" + bridge + ":", option, value])
        cmd.extend([";", "set-option", "-p", "-t", "=" + bridge + ":", "remain-on-exit", "on"])
        started = time.monotonic()
        rc, _ = tmux(*cmd)
        item = {"target": target.copy(), "dest": dest, "bridge": bridge, "token": token,
                "client": client, "generation": client_data["generation"], "state": "preparing",
                "created": started, "demand": demand}
        self.candidates[key] = item
        if rc:
            self.failure(item, "não consegui criar o transporte local")
            self.discard(key)
            return None
        self.metrics["preparadas"] += 1
        return item

    def failure(self, item, reason, machine=False):
        label = item["target"]["machine"] if machine else identity(item["target"])
        previous = self.failures.get(label, {})
        n = min(5, previous.get("count", 0) + 1)
        self.failures[label] = {"count": n, "until": time.monotonic() + min(600, 15 * 2 ** n), "reason": reason}
        item["state"] = "failed"
        item["reason"] = reason
        self.metrics["falhas"] += 1

    def poll_preparations(self):
        for item in list(self.candidates.values()):
            if item["state"] != "preparing":
                continue
            rc, out = tmux("capture-pane", "-p", "-J", "-t", "=" + item["bridge"] + ":", "-S", "-20")
            try:
                remote = decode_ticket(out, item["token"])
                if remote and item["target"].get("id") and remote.get("id") != item["target"]["id"]:
                    raise ValueError("identidade inválida")
            except (ValueError, KeyError, TypeError):
                self.failure(item, "resposta inválida")
                continue
            if remote:
                item["remote"] = remote
                item["state"] = "ready"
                item["target"]["name"] = remote["name"]
                item["ready_at"] = time.monotonic()
                item["prepare_ms"] = round((item["ready_at"] - item["created"]) * 1000)
                item["identity_ms"] = integer(remote.get("identity_ms"), 0, 0, 30000)
                self.failures.pop(item["target"]["machine"], None)
                self.failures.pop(identity(item["target"]), None)
                self.metrics["prontas"] += 1
                continue
            rc2, dead = tmux("display-message", "-p", "-t", "=" + item["bridge"] + ":", "#{pane_dead}")
            if rc or rc2 or dead.strip() == "1" or time.monotonic() - item["created"] > 8:
                absent = "TT_PRE_FAIL %s 3" % item["token"] in out
                self.failure(item, "sessão ausente ou identidade alterada" if absent else "destino sem resposta",
                             machine=not absent)

    def notify(self, client, message):
        tmux("display-message", "-c", client, "-d", "4000", message)

    def log_switch(self, client, request, bridge):
        # Mesma trilha das trocas normais do tt, sem abrir um Bash nem consultar o tmux outra vez.
        try:
            path = Path.home() / ".cache/tt-troca.log"
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            line = "%s %s cliente=%s de=%s para=%s ssh=- via=precarregar preparada=%d\n" % (
                time.strftime("%Y-%m-%d %H:%M:%S"), self.machine, client, request["source"], bridge, request["hit"])
            fd = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
            try:
                os.write(fd, line.encode("utf-8"))
            finally:
                os.close(fd)
        except OSError:
            self.metrics["falhas_log"] += 1

    def navigate(self, data):
        client, dest, name = data.get("client"), data.get("dest"), data.get("name")
        self.scan_clients()
        old = self.requests.pop(client, None)
        label = self.resolve_machine(dest) if isinstance(dest, str) else None
        if client not in self.clients or not label or not text_ok(name):
            if old:
                self.discard(old["key"])
            return {"handled": False}
        stable = data.get("id", "")
        if not isinstance(stable, str):
            return {"handled": False}
        target = {"machine": label, "name": name, "id": stable}
        if not stable:
            # A central escolheu pelo nome atual. Uma fixada velha de mesmo nome não pode
            # sobrepor essa escolha; só reaproveita identidade de um transporte ainda válido.
            target = next((i["target"].copy() for i in self.candidates.values()
                           if i["client"] == client and i["target"]["machine"] == label
                           and i["target"]["name"] == name and i["state"] in ("ready", "preparing", "active")), target)
        # Cada clique substitui o pedido anterior; conclusão tardia nunca ganha do último clique.
        if old and old["key"] != (client, identity(target)):
            self.discard(old["key"])
        key = (client, identity(target))
        item = self.candidates.get(key)
        if item and item["state"] == "active":
            return {"handled": False}  # ponte visitada: caminho já existente do tt
        if item and (item["state"] == "failed" or time.monotonic() - item["created"] > 150):
            self.discard(key)
            item = None
        hit = bool(item and item["state"] == "ready")
        # Clique tem prioridade, mas não ultrapassa o limite do cache especulativo.
        if not item:
            limit = max(1, self.settings()[1])
            spare = [(k, v) for k, v in self.candidates.items() if v["state"] != "active"
                     and k not in {r["key"] for r in self.requests.values()}]
            if sum(v["state"] != "active" for v in self.candidates.values()) >= limit and spare:
                self.discard(min(spare, key=lambda kv: kv[1]["created"])[0])
        item = item or self.prepare(client, target, True)
        if not item:
            return {"handled": False}
        self.requests[client] = {"key": key, "generation": self.clients[client]["generation"],
                                 "source": self.clients[client]["session"],
                                 "time": min(time.monotonic(), data.get("order", time.monotonic_ns()) / 1e9), "hit": hit}
        self.metrics["cliques"] += 1
        self.metrics["acertos"] += int(hit)
        return {"handled": True}

    def begin_activation(self, item):
        if not self.still_owned(item):
            self.failure(item, "ponte mudou de dono")
            return
        rc, _ = tmux("send-keys", "-t", "=" + item["bridge"] + ":", "-l", "ATIVAR " + item["token"])
        if not rc:
            rc, _ = tmux("send-keys", "-t", "=" + item["bridge"] + ":", "Enter")
        if rc:
            self.failure(item, "não consegui ativar a ponte")
            return
        remote = item["remote"]
        cmd = remote_command("confirmar", item["token"], str(remote["pid"]), remote["sid"], remote["server"])
        item["confirm"] = subprocess.Popen(["ssh", *SSH_ARGS, item["dest"], cmd], stdin=subprocess.DEVNULL,
                                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        item["state"] = "activating"
        item["activating_at"] = time.monotonic()

    def poll_requests(self):
        for client, request in list(self.requests.items()):
            item = self.candidates.get(request["key"])
            owner = self.clients.get(client, {})
            if owner.get("generation") != request["generation"] or owner.get("session") != request["source"]:
                self.requests.pop(client, None)
                if item:
                    self.discard(request["key"])
                continue
            if not item or item["state"] == "failed" or time.monotonic() - request["time"] > 10:
                self.notify(client, "⚠ Não consegui preparar o destino; sua tela foi preservada")
                self.requests.pop(client, None)
                if item:
                    self.discard(request["key"])
                continue
            if item["state"] == "ready":
                self.begin_activation(item)
            if item["state"] != "activating":
                continue
            proc = item["confirm"]
            if proc.poll() is None:
                if time.monotonic() - item["activating_at"] > 4:
                    proc.kill()
                    proc.communicate()
                    self.failure(item, "ativação sem confirmação")
                continue
            if "confirmed" not in item:
                output, _ = proc.communicate()
                try:
                    confirmed = decode_ticket(output.decode("utf-8", "replace"), item["token"])
                    item["confirmed"] = bool(confirmed and all(confirmed[k] == item["remote"][k] for k in ("sid", "server", "pid", "id")))
                    if item["confirmed"]:
                        item["remote"] = confirmed
                        item["target"]["name"] = confirmed["name"]
                        item["confirmed_at"] = time.monotonic()
                except (ValueError, TypeError):
                    item["confirmed"] = False
            if not item["confirmed"]:
                self.failure(item, "sessão não confirmou a anexação")
                continue
            rc, frame = tmux("capture-pane", "-p", "-J", "-t", "=" + item["bridge"] + ":")
            if rc or PREFIX + item["token"] in frame:
                continue  # ainda é a tela do bilhete, não o primeiro desenho remoto
            frame_at = time.monotonic()
            # Confere a tela original novamente imediatamente antes da troca.
            rc, live = tmux("list-clients", "-F", SEP.join(["#{client_name}", "#{client_pid}", "#{client_created}", "#{session_name}"]))
            expected = SEP.join([client, *request["generation"].split(":"), request["source"]])
            if rc or expected not in live.splitlines():
                self.requests.pop(client, None)
                self.discard(request["key"])
                continue
            remote = item["remote"]
            tmux("set-option", "-t", "=" + item["bridge"] + ":", "@ponte_id", remote["sid"],
                 ";", "set-option", "-t", "=" + item["bridge"] + ":", "@ponte_srv", remote["server"],
                 ";", "set-option", "-t", "=" + item["bridge"] + ":", "@ponte_alvo", item["dest"] + "|" + remote["name"],
                 ";", "set-option", "-t", "=" + item["bridge"] + ":", "@tt_pre_id", remote["id"],
                 ";", "set-option", "-t", "=" + item["bridge"] + ":", "@tt_pre_estado", "ativa")
            rc, _ = tmux("switch-client", "-c", client, "-t", "=" + item["bridge"])
            if not rc:
                switched_at = time.monotonic()
                item["state"] = "active"
                # Uma escolha por nome passa a aprender a identidade real, igual à fixada.
                previous_key = request["key"]
                item["target"]["id"] = remote["id"]
                canonical = (client, identity(item["target"]))
                if canonical != previous_key:
                    self.discard(canonical)  # só transportes especulativos, nunca uma ponte ativa
                    self.candidates.pop(previous_key, None)
                    self.candidates[canonical] = item
                self.samples.append({"preparada": request["hit"],
                                     "preparacao_ms": item["prepare_ms"],
                                     "identidade_remota_ms": item["identity_ms"],
                                     "ativacao_confirmada_ms": round((item["confirmed_at"] - item["activating_at"]) * 1000),
                                     "primeiro_quadro_ms": round((frame_at - item["confirmed_at"]) * 1000),
                                     "clique_ms": round((switched_at - request["time"]) * 1000)})
                self.log_switch(client, request, item["bridge"])
                self.metrics["trocas"] += 1
                self.requests.pop(client, None)
                self.next_scan = 0
            else:
                self.failure(item, "cliente não aceitou a troca")

    def maintain(self):
        if time.monotonic() < self.cooldown_until:
            return
        mode, total, per_client = self.settings()
        pending = {r["key"] for r in self.requests.values()}
        choices = []
        for client in self.clients:
            eligible = [r for r in self.ranking(client) if not r["blocked"]]
            for r in eligible[:per_client]:
                choices.append((r["score"], client, r))
        choices.sort(key=lambda v: (-v[0], v[1], v[2]["key"]))
        wanted = {(c, r["key"]) for _, c, r in choices[:total]}
        for key, item in list(self.candidates.items()):
            if item["state"] == "active":
                if tmux("has-session", "-t", "=" + item["bridge"])[0]:
                    del self.candidates[key]
                continue
            if key in pending:
                continue
            age = time.monotonic() - item["created"]
            owner = self.clients.get(item["client"], {})
            if (mode == "off" or not total or item["state"] in ("failed", "activating") or age > 150
                    or owner.get("generation") != item["generation"] or (key not in wanted and age > 20)):
                self.discard(key)
        in_flight = sum(i["state"] == "preparing" for i in self.candidates.values())
        prepared = sum(i["state"] != "active" for i in self.candidates.values())
        for _, client, r in choices[:total]:
            if (client, r["key"]) in self.candidates or in_flight >= 2 or prepared >= total:
                continue
            if self.prepare(client, r["target"]):
                in_flight += 1
                prepared += 1

    def status(self):
        mode, total, per_client = self.settings()
        return {"modo": mode, "limite_total": total, "por_tela": per_client, "metricas": dict(self.metrics),
                "historico_eventos": len(self.history),
                "troca_ms": list(self.samples), "fila": {c: self.ranking(c) for c in self.clients},
                "pontes": [{k: v for k, v in item.items() if k in ("client", "target", "state", "bridge", "reason")}
                           for item in self.candidates.values()]}

    def handle(self, data):
        self.last_event = time.monotonic()
        op = data.get("op")
        if op in ("navigate", "cancel"):
            client = data.get("client")
            if not isinstance(client, str):
                return {"handled": False}
            order = data.get("order", time.monotonic_ns())
            if not isinstance(order, int) or order <= self.latest.get(client, 0):
                return {"handled": True}
            self.latest[client] = order
            if data.get("expires", float("inf")) < time.monotonic():
                old = self.requests.pop(client, None)
                if old:
                    self.discard(old["key"])
                return {"handled": True}  # pedido atrasado é cancelamento, nunca troca tardia
        if op == "status":
            return self.status()
        if op == "stop":
            self.requests.clear()
            self.running = False
            return {"ok": True}
        if op == "navigate":
            if self.settings()[0] == "off":
                return {"handled": False}
            return self.navigate(data)
        if op == "cancel":
            old = self.requests.pop(data.get("client"), None)
            if old:
                self.discard(old["key"])
        if op == "focus":
            client, name = data.get("client"), data.get("name")
            label = self.resolve_machine(data.get("dest", ""))
            if client in self.clients and label and text_ok(name) and not name.startswith(("!", "+", "%", "_")):
                target = next((t for t in self.fixed() if t["machine"] == label and t["name"] == name),
                              {"machine": label, "name": name, "id": ""})
                previous = self.intents.get(client, {})
                if previous.get("key") != identity(target):
                    self.intents[client] = {"key": identity(target), "target": target, "time": time.time()}
        self.next_scan = min(self.next_scan, time.monotonic() + .35)
        return {"ok": True}

    def reap_orphans(self):
        rc, out = tmux("list-sessions", "-F", SEP.join([
            "#{session_name}", "#{@tt_pre_owner}", "#{@tt_pre_token}", "#{@tt_pre_estado}", "#{session_attached}"]))
        for line in out.splitlines() if not rc else []:
            c = line.split(SEP)
            if (len(c) == 5 and c[1] == self.folder.name and c[3:] == ["espera", "0"]
                    and re.fullmatch(r"[a-f0-9]{32}", c[2]) and c[0] == "tt-pre-" + c[2][:16]):
                tmux("kill-session", "-t", "=" + c[0])

    def check_wake(self, now, wall):
        # CLOCK_MONOTONIC pode parar durante o suspend; compara também o relógio civil.
        if now - self.last_tick > 30 or abs((wall - self.last_wall) - (now - self.last_tick)) > 30:
            self.requests.clear()
            for key in list(self.candidates):
                self.discard(key)
            self.cooldown_until = now + 5
            self.next_scan = self.cooldown_until
            self.metrics["retomadas"] += 1
        self.last_tick, self.last_wall = now, wall

    def run(self):
        with open(self.folder / "lock", "a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                return
            self.reap_orphans()
            address = self.folder / "socket"
            if address.exists():
                address.unlink()
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
                listener.bind(str(address))
                listener.listen(16)
                listener.setblocking(False)
                signal.signal(signal.SIGTERM, lambda *_: setattr(self, "running", False))
                signal.signal(signal.SIGINT, lambda *_: setattr(self, "running", False))
                try:
                    while self.running:
                        now = time.monotonic()
                        self.check_wake(now, time.time())
                        if now >= self.next_scan:
                            if (HERE / "precarregar-tt.py").stat().st_mtime_ns != self.package_stamp:
                                break  # instalação nova: próximo evento inicia o código novo
                            self.scan_clients()
                            self.maintain()
                            self.next_scan = now + (1 if self.requests else 10)
                        ready, _, _ = select.select([listener], [], [], .2 if self.requests else .5)
                        drained = 0
                        while ready and self.running and drained < 32:
                            drained += 1
                            conn, _ = listener.accept()
                            with conn:
                                conn.settimeout(.5)
                                raw = b""
                                try:
                                    while b"\n" not in raw and len(raw) < MAX_MESSAGE:
                                        part = conn.recv(4096)
                                        if not part:
                                            break
                                        raw += part
                                    data = json.loads(raw)
                                    response = self.handle(data) if isinstance(data, dict) else {"error": "pedido inválido"}
                                    conn.sendall(json.dumps(response, ensure_ascii=False).encode() + b"\n")
                                except (ValueError, OSError, TypeError):
                                    pass
                            ready, _, _ = select.select([listener], [], [], 0)
                        if not self.running:
                            break
                        self.poll_preparations()
                        self.poll_requests()
                        if not self.clients and now - self.last_event > 60:
                            break
                finally:
                    for key, item in list(self.candidates.items()):
                        proc = item.get("confirm")
                        if proc and proc.poll() is None:
                            proc.kill()
                            proc.communicate()
                        self.discard(key)
                    address.unlink(missing_ok=True)


def battery():
    """Sonda lenta e cacheada; sem subprocesso por clique. Ausência de dado não é bateria cheia."""
    if sys.platform == "darwin":
        _, out = execute(["pmset", "-g", "batt"], timeout=1)
        found = re.search(r"(\d+)%;", out)
        return (int(found[1]), "AC Power" in out) if found else (None, False)
    if "com.termux" in os.environ.get("PREFIX", ""):
        _, out = execute(["termux-battery-status"], timeout=1)
        try:
            data = json.loads(out)
            return int(data["percentage"]), data.get("status") in ("CHARGING", "FULL")
        except (ValueError, KeyError, TypeError):
            return None, False
    for root in Path("/sys/class/power_supply").glob("BAT*"):
        try:
            return int((root / "capacity").read_text()), (root / "status").read_text().strip() != "Discharging"
        except (OSError, ValueError):
            pass
    return None, False


def format_status(data):
    mode = {"auto": "automático", "economico": "econômico", "off": "desligado"}.get(data["modo"], data["modo"])
    lines = ["Modo: " + mode]
    if data.get("coordenador") == "parado":
        if data.get("motivo") and data["modo"] != "off":
            return "\n".join(lines + ["Coordenador parado: " + data["motivo"] + "."])
        return "\n".join(lines + ["Coordenador parado." if data["modo"] == "off" else "Coordenador parado; inicia ao usar o tt."])
    lines.append("Limite: %s preparações no total · %s por tela" % (data["limite_total"], data["por_tela"]))
    metrics = data.get("metricas", {})
    lines.append("Cliques: %d · preparados: %d · trocas: %d · falhas: %d" %
                 tuple(metrics.get(k, 0) for k in ("cliques", "acertos", "trocas", "falhas")))
    samples = data.get("troca_ms", [])
    if samples:
        lines.append("Última troca confirmada: %d ms (%s)" %
                     (samples[-1]["clique_ms"], "já preparada" if samples[-1]["preparada"] else "sob demanda"))
    states = {"preparing": "preparando", "ready": "pronta", "activating": "abrindo", "active": "em uso", "failed": "falhou"}
    for client, queue in data.get("fila", {}).items():
        lines.extend(["", "Tela " + client])
        for r in queue[:3]:
            target = r["target"]
            item = next((i for i in data["pontes"] if i["client"] == client and identity(i["target"]) == r["key"]), {})
            state = "aguardando rede" if r["blocked"] else states.get(item.get("state"), "na fila")
            lines.append("  %s:%s · %s · %s" % (target["machine"], target["name"], state, ", ".join(r["reasons"])))
    return "\n".join(lines)


def main(argv):
    global SSH_ARGS
    if "--ssh-args" in argv:
        pos = argv.index("--ssh-args")
        SSH_ARGS, argv = argv[pos + 1:], argv[:pos]
    op = argv[0] if argv else "status"
    human = op == "status-text"
    if human:
        op = "status"
    if op in ("remoto", "confirmar"):
        return protocol.main(argv)
    if op == "transporte" and len(argv) == 7:
        return subprocess.call(["ssh", "-tt", *SSH_ARGS, argv[1], remote_command("remoto", *argv[2:])])
    try:
        folder = runtime()
    except TmuxUnavailable:
        if op == "status":
            mode = "off" if os.environ.get("TT_PRECARREGAR") == "0" else read_config().get("precarregar", "auto")
            response = {"modo": mode, "coordenador": "parado", "motivo": "aguardando sessão tmux"}
            print(format_status(response) if human else json.dumps(response, ensure_ascii=False))
        return 0 if op in ("status", "stop", "cancel", "evento", "focus") else 1
    if op == "daemon":
        os.umask(0o077)
        Coordinator(folder).run()
        return 0
    data = {"op": op, "order": time.monotonic_ns(), "expires": time.monotonic() + 3}
    if len(argv) > 1:
        data["client"] = argv[1]
    if len(argv) > 2:
        data["dest"] = argv[2]
    if len(argv) > 3:
        data["name"] = argv[3]
    if len(argv) > 4:
        data["id"] = argv[4]
    try:
        response = send_request(folder, data)
    except UncertainReply:
        return 0  # sem duplicar um clique cuja confirmação se perdeu
    except (OSError, ValueError):
        if op in ("status", "stop", "cancel"):
            if op == "status":
                response = {"modo": read_config().get("precarregar", "auto"), "coordenador": "parado"}
                print(format_status(response) if human else json.dumps(response))
            return 0
        if os.environ.get("TT_PRECARREGAR") == "0" or read_config().get("precarregar") == "off":
            return 1
        with open(folder / "erros.log", "ab", buffering=0) as log:
            subprocess.Popen([sys.executable, str(HERE / "precarregar-tt.py"), "daemon", "--ssh-args", *SSH_ARGS],
                             stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        for _ in range(20):
            time.sleep(.05)
            try:
                response = send_request(folder, data)
                break
            except UncertainReply:
                return 0
            except (OSError, ValueError):
                pass
        else:
            return 1
    if op == "status":
        print(format_status(response) if human else json.dumps(response, ensure_ascii=False, indent=2))
    if op == "navigate":
        return 0 if response.get("handled") else 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError, RuntimeError) as exc:
        print("pré-carregamento: " + str(exc), file=sys.stderr)
        sys.exit(1)
