#!/usr/bin/env bash
# O pacote sai do repositório também quando ele é uma worktree do git (lá o .git é um arquivo,
# não uma pasta): antes, o tt caía no pacote instalado e instalava a versão velha.
set -euo pipefail
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'git -C "$T/repo" worktree remove --force "$T/wt" >/dev/null 2>&1; rm -rf "$T"' EXIT
fail() { echo "FALHOU: $*" >&2; exit 1; }

git clone -q "$RAIZ" "$T/repo"
git -C "$T/repo" worktree add -q --detach "$T/wt"
[[ -f $T/wt/.git ]] || fail "a worktree deveria ter .git como arquivo"
esperado=$(git -C "$T/wt" rev-parse --short HEAD)
v=$(env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" TT_REPO="$T/wt" TT_DIR="$T/inst" \
  "$RAIZ/tt" --pacote 2>/dev/null | tar -xOf - VERSAO) || fail "pacote não saiu da worktree"
[[ $v == *" $esperado "* ]] || fail "VERSAO do pacote ($v) não é a da worktree ($esperado)"
echo "ok: pacote montado a partir de uma worktree"
