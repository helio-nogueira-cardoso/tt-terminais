#!/usr/bin/env python3
"""Bilhete passivo v1, executável por stdin/-c sem instalar nada na máquina remota.

Só usa Python 3 e tmux. O mesmo código atende preparação e confirmação, inclusive
em versões anteriores do tt: não depende de uma atualização simultânea da malha.
"""
import base64
import json
import os
import re
import select
import subprocess
import sys
import termios
import time

SEP = "\t"  # o tmux 3.5 escapa 0x1f; tab permanece literal em todas as versões suportadas
PREFIX = "TT_PRE_1 "
TMUX = os.environ.get("TT_TMUX_BIN", "tmux")


def tmux(*args):
    try:
        p = subprocess.run([TMUX, *args], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, timeout=3)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.TimeoutExpired):
        return 124, ""


def remote_target(name, stable="", expected=None):
    rc, out = tmux("list-sessions", "-F", SEP.join([
        "#{session_id}", "#{start_time}", "#{session_name}", "#{@tt_session_id}", "#{@ponte}"]))
    if rc:
        return None
    for line in out.splitlines():
        c = line.split(SEP)
        if len(c) != 5 or c[4] or c[2].startswith("_"):
            continue
        candidate = {"sid": c[0], "server": c[1], "name": c[2], "id": c[3]}
        if expected:
            match = candidate["sid"] == expected["sid"] and candidate["server"] == expected["server"]
            if stable:
                match = match and candidate["id"] == stable
        else:
            match = c[3] == stable if stable else c[2] == name
        if match:
            return candidate
    return None


def emit(token, payload):
    print(PREFIX + token + " " + base64.b64encode(json.dumps(payload).encode()).decode(), flush=True)


def remote_wait(token, name, stable, origin, ttl):
    if not re.fullmatch(r"[a-f0-9]{32}", token) or not name or not origin:
        return 2
    began = time.monotonic()
    target = remote_target(name, stable)
    if not target:
        return 3
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
    # Mesmo PID do bilhete; -E não altera o ambiente da sessão de destino.
    os.execvp(TMUX, [TMUX, "-u", "attach-session", "-E", "-t", target["sid"]])


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
