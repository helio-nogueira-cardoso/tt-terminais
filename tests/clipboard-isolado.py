#!/usr/bin/env python3
"""Receptor clip.exe de teste: nunca alcança o clipboard do sistema."""
from pathlib import Path
import shutil
import subprocess
import sys

base = Path(sys.argv[1]).resolve()
allowed = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else base
data = sys.stdin.buffer.read().decode('utf-16le').encode('utf-8')
for name in ('wl-copy', 'xclip', 'termux-clipboard-set', 'pbcopy'):
    command = shutil.which(name)
    if not command:
        continue
    try:
        Path(command).resolve().relative_to(allowed)
    except ValueError:
        continue
    args = [command] + (['-selection', 'clipboard'] if name == 'xclip' else [])
    sys.exit(subprocess.run(args, input=data).returncode)
(base / 'clipboard.txt').write_bytes(data)
