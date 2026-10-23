#!/usr/bin/env python3
"""Transporte SSH falso: executa o lado remoto em HOME/socket isolados, nunca rede."""
import os
from pathlib import Path
import sys
import time

root = Path(os.environ["TT_TEST_PRE_REMOTE"])
args = sys.argv[1:]
destination, command = args[-2:]
with open(root / "ssh.log", "a") as log:
    log.write(destination + "\t" + ("pty" if "-tt" in args else "cmd") + "\n")
if "offline" in destination:
    sys.exit(255)
if "lenta" in destination:
    time.sleep(1.5)
os.environ.update(HOME=str(root / "home"), XDG_CONFIG_HOME=str(root / "home/.config"),
                  TT_DIR=str(root / "home/.local/share/tt"), TMUX_TMPDIR=str(root / "tmux"),
                  TT_RT=str(root / "rt"), TT_PRECARREGAR="0", TT_SEM_VIGIA_AUTO="1")
for key in ("TMUX", "TMUX_PANE", "XDG_STATE_HOME", "_TT_PATH_ORIGEM", "TT_CLIENTE"):
    os.environ.pop(key, None)
# Sentido de volta só no cenário empresa→Mac: simula o SSH que a versão antiga abria por clique.
if destination == "usuario@origem" and (root / "origin.json").is_file():
    import json
    time.sleep(.25)
    os.environ.update(json.loads((root / "origin.json").read_text()))
    os.environ["TT_PRECARREGAR"] = "1"
    os.execvp("bash", ["bash", "-c", command])
if "-tt" in args:
    # SSH real aloca OUTRO PTY no destino, mesmo quando stdout daqui é um pipe.
    import fcntl
    import pty
    import signal
    import termios
    master = [None]
    def resize(*_):
        if master[0] is not None:
            size = fcntl.ioctl(0, termios.TIOCGWINSZ, b"\0" * 8)
            fcntl.ioctl(master[0], termios.TIOCSWINSZ, size)
    def read(fd):
        if master[0] is None:
            master[0] = fd
            resize()
        return os.read(fd, 65536)
    signal.signal(signal.SIGWINCH, resize)
    status = pty.spawn(["bash", "-c", command], master_read=read)
    sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 128 + os.WTERMSIG(status))
os.execvp("bash", ["bash", "-c", command])
