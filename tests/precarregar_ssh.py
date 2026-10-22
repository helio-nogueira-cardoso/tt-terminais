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
os.execvp("bash", ["bash", "-c", command])
