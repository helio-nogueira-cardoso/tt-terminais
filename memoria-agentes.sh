#!/usr/bin/env bash
# Inicializa e atualiza o repositório local de memória/telemetria do tt.
# Guarda somente metadados de agentes e sessões; não copia credenciais nem transcripts.

set -u

# Fica no estado do tt (~/.local/state/tt), fora do pacote: a pasta do pacote é trocada inteira a
# cada instalação. A pasta antiga, dentro do pacote, é migrada uma vez.
raiz=${TT_AI_MEMORY_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tt/ai-memory}
antiga=${XDG_DATA_HOME:-$HOME/.local/share}/tt/ai-memory
if [[ -z ${TT_AI_MEMORY_DIR:-} && -d $antiga && ! -e $raiz ]]; then
  mkdir -p "$(dirname "$raiz")" && mv "$antiga" "$raiz"
fi
mkdir -p "$raiz/agents" "$raiz/sessions" "$raiz/events"

python3 - "$raiz" <<'PY'
import datetime as dt
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
machine = os.environ.get("TT_NOME", "")
if not machine:
    config = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", str(pathlib.Path.home() / ".config"))) / "tt/config"
    try:
        machine = next((line.split("=", 1)[1].strip() for line in config.read_text(encoding="utf-8").splitlines() if line.startswith("nome=") and "=" in line), "")
    except OSError:
        machine = ""
machine = machine or os.uname().nodename
for directory in (root, root / "agents", root / "sessions", root / "events"):
    try:
        directory.chmod(0o700)
    except OSError:
        pass

def executable(name):
    candidates = [shutil.which(name), str(pathlib.Path.home() / ".local/bin" / name)]
    for candidate in candidates:
        if candidate and pathlib.Path(candidate).is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None

agents = []
for name, aliases in {
    "claude": ("claude", "claude-conta"),
    "codex": ("codex",),
    "kiro": ("kiro", "kiro-cli", "kiro-cli-chat"),
}.items():
    paths = {p for alias in aliases if (p := executable(alias))}
    agents.append({"id": name, "installed": bool(paths), "paths": sorted(paths)})

def run(*args):
    try:
        return subprocess.run(args, text=True, capture_output=True, check=False).stdout
    except OSError:
        return ""

sessions = []
for row in run("tmux", "list-sessions", "-F", "#{session_name}\t#{session_created}\t#{window_activity}").splitlines():
    parts = row.split("\t")
    if not parts:
        continue
    name = parts[0]
    panes = []
    for pane in run("tmux", "list-panes", "-a", "-F", "#{session_name}\t#{pane_current_path}\t#{pane_current_command}\t#{pane_pid}").splitlines():
        p = pane.split("\t")
        if len(p) >= 4 and p[0] == name:
            panes.append({"path": p[1], "command": p[2], "pid": p[3]})
    sessions.append({"name": name, "created": parts[1] if len(parts) > 1 else "", "activity": parts[2] if len(parts) > 2 else "", "panes": panes})

snapshot = {"machine": machine, "sessions": sessions}
session_file = root / "sessions" / "current.json"
previous = None
try:
    previous = json.loads(session_file.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    pass

def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".ai-memory-", dir=path.parent, text=True)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    os.chmod(temp, 0o600)
    os.replace(temp, path)

atomic_json(session_file, {**snapshot, "updated_at": now})
atomic_json(root / "agents" / "installed.json", {"machine": machine, "updated_at": now, "agents": agents})
atomic_json(root / "index.json", {"format": 1, "machine": machine, "updated_at": now, "agents": "agents/installed.json", "sessions": "sessions/current.json", "memory": "memory.md", "decisions": "decisions.md"})

if previous is None or previous.get("sessions") != sessions:
    event = {"at": now, "machine": machine, "event": "sessions-snapshot", "count": len(sessions)}
    event_file = root / "events" / (dt.datetime.now().date().isoformat() + ".jsonl")
    with event_file.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(event, ensure_ascii=False) + "\n")

readme = root / "README.md"
if not readme.exists():
    readme.write_text("""# Memória local dos agentes\n\nEste diretório é o repositório padrão do tt para contexto compartilhado entre Claude, Codex, Kiro e outros agentes.\n\n- `memory.md`: fatos e contexto duradouros.\n- `decisions.md`: decisões e preferências entre sessões.\n- `agents/installed.json`: agentes detectados nesta máquina.\n- `sessions/current.json`: metadados das sessões tmux atuais, sem transcripts ou credenciais.\n- `events/`: mudanças de presença das sessões em JSONL.\n\nO tt nunca copia tokens, chaves, cookies, históricos completos ou arquivos privados dos agentes para cá.\n""", encoding="utf-8")
    os.chmod(readme, 0o600)
for name, title in (("memory.md", "# Memória compartilhada\n\n"), ("decisions.md", "# Decisões e preferências\n\n")):
    path = root / name
    if not path.exists():
        path.write_text(title, encoding="utf-8")
        os.chmod(path, 0o600)
PY
