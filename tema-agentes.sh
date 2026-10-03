#!/usr/bin/env bash
# Uniformiza somente as preferências visuais dos agentes instalados nesta máquina.
# Não lê nem copia credenciais, MCPs, permissões ou outras preferências.

set -u

json_theme() {
  local arquivo=$1 chave=$2 valor=$3
  python3 - "$arquivo" "$chave" "$valor" <<'PY'
import json, os, sys, tempfile

path, key, value = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as source:
        data = json.load(source)
except FileNotFoundError:
    data = {}
except (OSError, json.JSONDecodeError) as exc:
    print(f"tema-agentes: não alterei {path}: {exc}", file=sys.stderr)
    raise SystemExit(1)

if data.get(key) == value:
    raise SystemExit(0)
data[key] = value
directory = os.path.dirname(path)
os.makedirs(directory, mode=0o700, exist_ok=True)
fd, temporary = tempfile.mkstemp(prefix=".tema-", dir=directory, text=True)
with os.fdopen(fd, "w", encoding="utf-8") as output:
    json.dump(data, output, ensure_ascii=False, indent=2)
    output.write("\n")
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
}

codex_theme() {
  local arquivo=${CODEX_HOME:-$HOME/.codex}/config.toml
  python3 - "$arquivo" <<'PY'
import os, re, sys, tempfile

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as source:
        text = source.read()
except FileNotFoundError:
    text = ""
except OSError as exc:
    print(f"tema-agentes: não alterei {path}: {exc}", file=sys.stderr)
    raise SystemExit(1)

original = text
# Repara a forma literal "\\n" que uma versão inicial deste sincronizador poderia gravar
# imediatamente antes da seção criada por ele; não altera outros textos ou preferências.
text = text.replace(r"[tui]\ntheme = ", "[tui]\ntheme = ")
header = re.compile(r"(?m)^\[tui\]\s*$")
section = header.search(text)
if section:
    next_header = re.search(r"(?m)^\[[^]]+\]\s*$", text[section.end():])
    end = section.end() + (next_header.start() if next_header else len(text[section.end():]))
    body = text[section.end():end]
    if re.search(r"(?m)^theme\s*=", body):
        body = re.sub(r'(?m)^theme\s*=.*$', 'theme = "catppuccin-mocha"', body)
    else:
        body = "\ntheme = \"catppuccin-mocha\"" + body
    updated = text[:section.end()] + body + text[end:]
else:
    updated = text.rstrip() + "\n\n[tui]\ntheme = \"catppuccin-mocha\"\n"

if updated == original:
    raise SystemExit(0)
directory = os.path.dirname(path)
os.makedirs(directory, mode=0o700, exist_ok=True)
fd, temporary = tempfile.mkstemp(prefix=".tema-", dir=directory, text=True)
with os.fdopen(fd, "w", encoding="utf-8") as output:
    output.write(updated)
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
}

claude_theme() {
  local perfil
  if command -v claude >/dev/null 2>&1 || [[ -d $HOME/.claude ]]; then
    json_theme "$HOME/.claude/settings.json" theme dark || true
  fi
  # Perfis de claude-conta guardam credenciais separadas, mas também podem ter settings próprios.
  # Só a chave visual é alterada; links simbólicos para a configuração compartilhada são seguros.
  for perfil in "$HOME"/.local/share/claude-contas/*; do
    [[ -d $perfil ]] || continue
    json_theme "$perfil/settings.json" theme dark || true
  done
}

claude_theme
[[ -d $HOME/.claude || -d $HOME/.local/share/claude-contas ]] &&
  printf '%s\n' 'Claude: dark + paleta ANSI Catppuccin Mocha'

if command -v codex >/dev/null 2>&1 || [[ -d ${CODEX_HOME:-$HOME/.codex} ]]; then
  codex_theme || true
  printf '%s\n' 'Codex: catppuccin-mocha'
fi

if command -v kiro >/dev/null 2>&1 || [[ -d $HOME/.config/Kiro || -d $HOME/.config/kiro ]]; then
  kiro_config=${XDG_CONFIG_HOME:-$HOME/.config}/Kiro/User/settings.json
  json_theme "$kiro_config" workbench.colorTheme 'Catppuccin Mocha' || true
  printf '%s\n' 'Kiro: Catppuccin Mocha'
fi
