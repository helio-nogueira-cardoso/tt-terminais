#!/usr/bin/env bash
# A instalação nunca substitui uma pasta que é um repositório git (TT_DIR apontado para um clone).
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
mkdir -p "$D/clone/.git" "$D/pacote" "$D/home/.config/tt"
echo marca >"$D/clone/arquivo-do-clone"
cp "$ROOT"/tt "$ROOT"/tmux.conf "$ROOT"/tema-*.sh "$ROOT"/tema-tmux.conf "$ROOT"/memoria-agentes.sh "$ROOT"/atalhos-padrao* "$ROOT"/README.md "$ROOT"/AI-DLC.md "$D/pacote/" 2>/dev/null || true
echo "999 abc 2099-01-01" >"$D/pacote/VERSAO"
HOME=$D/home XDG_CONFIG_HOME=$D/home/.config TT_DIR=$D/clone TMUX_TMPDIR=$D "$D/pacote/tt" --instalar-aqui >/dev/null 2>&1 || true
[[ -d $D/clone/.git && -f $D/clone/arquivo-do-clone ]] || { echo 'FALHOU — a instalação substituiu um repositório git' >&2; exit 1; }
echo 'ok: instalação recusa substituir um repositório git'
