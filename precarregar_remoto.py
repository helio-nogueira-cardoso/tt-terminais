#!/usr/bin/env python3
"""Bilhete passivo v1, executável por stdin/-c sem instalar nada na máquina remota.

Só usa Python 3 e tmux. O mesmo código atende preparação e confirmação, inclusive
em versões anteriores do tt: não depende de uma atualização simultânea da malha.
"""
import base64
import fcntl
import hashlib
import json
import os
import re
import select
import shlex
import socket
import subprocess
import sys
import tempfile
from pathlib import Path
import termios
import uuid
import time

SEP = "\t"  # o tmux 3.5 escapa 0x1f; tab permanece literal em todas as versões suportadas
PREFIX = "TT_PRE_1 "
TMUX = os.environ.get("TT_TMUX_BIN", "tmux")
NAV_PREFIX = b"\x1b]777;tt-nav;"  # o mesmo do precarregar-tt.py
FRAME_MAX = 4096
BASE64 = frozenset(b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")


def tmux(*args):
    try:
        p = subprocess.run([TMUX, *args], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, timeout=3)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.TimeoutExpired):
        return 124, ""


def ensure_identity(sid):
    # Grava UMA vez. Trava por socket (canônico) também cobre criadores concorrentes.
    fmt = SEP.join(["#{@tt_session_id}", "#{host}", "#{socket_path}", "#{pid}",
                    "#{start_time}", "#{session_id}", "#{session_created}"])
    def read():
        rc, out = tmux("display-message", "-p", "-t", sid + ":", fmt)
        fields = out.rstrip("\r\n").split(SEP)
        return fields if not rc and len(fields) == 7 and re.fullmatch(r"\$[0-9]+", fields[5]) else None
    first = read()
    if not first:
        return ""
    if first[0]:
        return first[0]
    key = hashlib.sha256((os.path.realpath(first[2]) + "|" + first[3] + "|" + first[4]).encode()).hexdigest()[:16]
    root = Path("/tmp")
    if not root.is_dir() or not os.access(root, os.W_OK | os.X_OK):
        root = Path(tempfile.gettempdir())
    folder = root / ("tt-id-%s-%s" % (os.getuid(), key))
    folder.mkdir(mode=0o700, exist_ok=True)
    info = folder.lstat()
    if folder.is_symlink() or info.st_uid != os.getuid() or info.st_mode & 0o077:
        return ""
    fd = os.open(folder / "lock", os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0), 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        fields = read()
        if not fields or fields[3:6] != first[3:6]:
            return ""
        if fields[0]:
            return fields[0]
        rc, ids = tmux("list-sessions", "-F", "#{@tt_session_id}")
        if rc:
            return ""
        used = set(ids.splitlines())
        for _ in range(16):
            stable = uuid.uuid4().hex
            if stable not in used:
                break
        else:
            return ""
        target = fields[5] + ":"
        set_id = shlex.join(["set-option", "-q", "-t", target, "@tt_session_id", stable])
        inner = shlex.join(["if-shell", "-F", "-t", target, "#{==:#{@tt_session_id},}", set_id])
        read_id = shlex.join(["show-options", "-qv", "-t", target, "@tt_session_id"])
        guard = "#{&&:#{==:#{pid}," + fields[3] + "},#{==:#{start_time}," + fields[4] + "}}"
        rc, out = tmux("if-shell", "-F", "-t", target, guard, inner + " ; " + read_id)
        return out.strip() if not rc else ""
    finally:
        os.close(fd)


def remote_target(name, stable="", expected=None, allow_special=False):
    rc, out = tmux("list-sessions", "-F", SEP.join([
        "#{session_id}", "#{start_time}", "#{session_name}", "#{@tt_session_id}", "#{@ponte}"]))
    if rc:
        return None
    matches = []
    for line in out.splitlines():
        c = line.split(SEP)
        if len(c) != 5 or (not allow_special and (c[4] or c[2].startswith("_"))):
            continue
        candidate = {"sid": c[0], "server": c[1], "name": c[2], "id": c[3]}
        if expected:
            match = candidate["sid"] == expected["sid"] and candidate["server"] == expected["server"]
            expected_id = stable or expected.get("id", "")
            if expected_id:
                match = match and candidate["id"] == expected_id
        else:
            match = c[3] == stable if stable else c[2] == name
        if match:
            matches.append(candidate)
    if len(matches) != 1:
        return None  # ID ambíguo nunca escolhe a primeira sessão por acaso
    candidate = matches[0]
    if not candidate["id"]:
        candidate["id"] = ensure_identity(candidate["sid"])
    return candidate if candidate["id"] else None


def emit(token, payload):
    print(PREFIX + token + " " + base64.b64encode(json.dumps(payload).encode()).decode(), flush=True)


def relay_folder():
    """Pasta privada dos porteiros desta máquina (a mesma conta no bilhete e no coordenador)."""
    root = Path(os.environ.get("TT_PRE_RELAY_DIR") or "/tmp")  # a variável só existe nos testes
    if not root.is_dir() or not os.access(root, os.W_OK | os.X_OK):
        root = Path(tempfile.gettempdir())
    folder = root / ("tt-pre-relay-%d" % os.getuid())
    folder.mkdir(mode=0o700, exist_ok=True)
    info = folder.lstat()
    if folder.is_symlink() or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise OSError("pasta dos porteiros sem isolamento")
    return folder


def frame_ok(frame, token):
    head = NAV_PREFIX + token.encode() + b";"
    body = frame[len(head):-1]
    return (len(frame) <= FRAME_MAX and frame.startswith(head) and frame.endswith(b"\x07")
            and len(body) > 0 and all(c in BASE64 for c in body))


def write_all(fd, data, limit=.2):
    until = time.monotonic() + limit
    written = 0
    while written < len(data):
        try:
            written += os.write(fd, data[written:])
        except BlockingIOError:
            if time.monotonic() >= until:
                raise
            select.select([], [fd], [], .005)
    return written


def doorman_send(token, frame, timeout=.5):
    """Entrega o envelope ao porteiro da ponte TOKEN. False só se não chegou a ele (ou ele recusou)."""
    try:
        path = relay_folder() / token[:16]
        conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    except OSError:
        return False
    with conn:
        try:
            conn.settimeout(timeout)
            conn.connect(str(path))
        except OSError:
            return False
        try:
            conn.sendall(frame)
            conn.shutdown(socket.SHUT_WR)
            return not conn.recv(8).startswith(b"no")
        except OSError:
            return True  # já entregue: resposta perdida nunca dispara outra navegação


def serve_doorman(tty, path, token, owner):
    try:
        path.unlink()
    except FileNotFoundError:
        pass
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        listener.bind(str(path))
        listener.listen(4)
        os.set_blocking(tty, False)
        while True:
            ready, _, _ = select.select([listener], [], [], .2)
            try:
                os.kill(owner, 0)
            except ProcessLookupError:
                break  # o cliente tmux saiu: a ponte acabou
            except PermissionError:
                break  # o pid já é de outro usuário
            if not ready:
                continue
            try:
                conn, _ = listener.accept()
            except OSError:
                continue  # conexão desistida ou sem descritor livre: o porteiro segue de pé
            with conn:
                frame = b""
                try:
                    conn.settimeout(.5)
                    while len(frame) <= FRAME_MAX:
                        part = conn.recv(FRAME_MAX + 1 - len(frame))
                        if not part:
                            break
                        frame += part
                    ok = frame_ok(frame, token)
                    if ok:
                        write_all(tty, frame)
                    conn.sendall(b"ok\n" if ok else b"no\n")
                except BlockingIOError:
                    pass
                except OSError as exc:
                    if exc.errno in (5, 9):  # EIO/EBADF: o terminal foi fechado
                        break
    finally:
        listener.close()
        try:
            path.unlink()
        except OSError:
            pass


def start_doorman(token):
    """Porteiro do terminal desta ponte, só quando o caminho dele não aceita a nossa escrita.

    O Tailscale SSH cria o pty com dono root (modo 620, grupo tty): o coordenador desta máquina não
    abre o terminal para devolver o clique à máquina da tela. O porteiro herda o terminal já aberto e
    escreve nele só envelopes de navegação desta ponte. Sai quando o cliente tmux (este mesmo pid,
    depois do exec) termina.
    """
    try:
        name = os.ttyname(1)
        # A mesma regra do coordenador (relay_nested): só escreve direto no terminal que é nosso.
        if os.access(name, os.W_OK) and os.stat(name).st_uid == os.geteuid():
            return
        path = relay_folder() / token[:16]
        tty = os.dup(1)
    except OSError:
        return
    owner = os.getpid()
    try:
        pid = os.fork()
    except OSError:
        os.close(tty)
        return
    if pid:
        os.close(tty)
        try:
            os.waitpid(pid, 0)
        except OSError:
            pass
        return
    try:
        os.setsid()  # sem terminal de controle: o fim da sessão não o derruba no meio de uma escrita
        if os.fork():
            os._exit(0)  # o neto não vira zumbi do cliente tmux
        null = os.open(os.devnull, os.O_RDWR)
        for fd in (0, 1, 2):
            os.dup2(null, fd)
        serve_doorman(tty, path, token, owner)
    finally:
        os._exit(0)


def remote_wait(token, name, stable, origin, ttl):
    if not re.fullmatch(r"[a-f0-9]{32}", token) or not name or not origin:
        return 2
    began = time.monotonic()
    target = remote_target(name, stable)
    if not target:
        # 3 = a sessão não existe (inclusive sem servidor tmux: sessões não voltam com o mesmo ID); 5 = o tmux daqui
        # não respondeu a tempo, falha passageira que não pode apagar nada lá na origem.
        return 5 if tmux("list-sessions", "-F", "x")[0] == 124 else 3
    old = termios.tcgetattr(0)
    quiet = termios.tcgetattr(0)
    quiet[3] &= ~termios.ECHO
    termios.tcsetattr(0, termios.TCSANOW, quiet)
    try:
        emit(token, dict(target, pid=os.getpid(), identity_ms=round((time.monotonic() - began) * 1000)))
        ready, _, _ = select.select([sys.stdin], [], [], max(10, min(600, int(ttl))))
        if not ready or sys.stdin.readline(128).strip() != "ATIVAR " + token:
            return 4
        target = remote_target(name, stable, target)
        if not target:
            return 3
    finally:
        termios.tcsetattr(0, termios.TCSANOW, old)
    os.environ["TT_PONTE"] = origin
    # Só o cliente de transporte recebe a capacidade; -E não a publica na sessão.
    os.environ["TT_PRE_TOKEN"] = token
    start_doorman(token)
    # Mesmo PID do bilhete; -E não altera o ambiente da sessão de destino.
    guard = "#{&&:#{==:#{@tt_session_id}," + target["id"] + "},#{==:#{start_time}," + target["server"] + "}}"
    attach = shlex.join(["attach-session", "-E", "-t", target["sid"]])
    os.execvp(TMUX, [TMUX, "-u", "if-shell", "-F", "-t", target["sid"] + ":", guard, attach])


def remote_confirm(token, pid, sid, server):
    if not re.fullmatch(r"[a-f0-9]{32}", token) or not str(pid).isdigit():
        return 2
    until = time.monotonic() + 2
    while time.monotonic() < until:
        rc, out = tmux("list-clients", "-F", SEP.join([
            "#{client_pid}", "#{session_id}", "#{start_time}", "#{session_name}", "#{@tt_session_id}"]))
        for line in out.splitlines() if not rc else []:
            c = line.split(SEP)
            if len(c) == 5 and c[:3] == [pid, sid, server]:
                emit(token, {"sid": sid, "server": server, "pid": int(pid), "name": c[3], "id": c[4]})
                return 0
        time.sleep(.05)
    return 1


def main(argv):
    if len(argv) == 5 and argv[0] == "resolver":
        name, stable, sid, server = argv[1:]
        expected = {"sid": sid, "server": server, "id": stable} if sid and server else None
        print(json.dumps({"target": remote_target(name, stable, expected, allow_special=True)}))
        return 0
    if len(argv) == 2 and argv[0] == "identidade":
        value = ensure_identity(argv[1])
        if value:
            print(value)
        return 0 if value else 1
    if len(argv) == 6 and argv[0] == "remoto":
        return remote_wait(*argv[1:])
    if len(argv) == 5 and argv[0] == "confirmar":
        return remote_confirm(*argv[1:])
    return 2


if __name__ == "__main__":
    try:
        result = main(sys.argv[1:])
    except (OSError, ValueError, termios.error):
        result = 1
    if result and len(sys.argv) > 2 and re.fullmatch(r"[a-f0-9]{32}", sys.argv[2]):
        print("TT_PRE_FAIL %s %s" % (sys.argv[2], result), flush=True)
    sys.exit(result)
