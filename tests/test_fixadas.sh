#!/usr/bin/env bash
# Teste de regressão dos cliques na faixa de sessões fixadas.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

[[ -x "$TT" ]]
bash -n "$TT"
grep -q 'fixada_chave()' "$TT"
grep -q 'range=user|fx%s' "$TT"
grep -q 'range=user|fxx%s' "$TT"

mkdir -p "$TEST_DIR/home/.config/tt" "$TEST_DIR/bin"
printf 'nome=dell\n' >"$TEST_DIR/home/.config/tt/config"
printf 'dell\tsessao-a\ndell\tsessao-b\n' >"$TEST_DIR/home/.config/tt/fixadas"

cat >"$TEST_DIR/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
case ${1:-} in
  list-clients) exit 0 ;;
  has-session) exit 0 ;;
  attach-session|switch-client) printf '%s\n' "$*" >"$TT_TEST_LOG"; exit 0 ;;
  *) exit 0 ;;
esac
TMUX
chmod +x "$TEST_DIR/bin/tmux"

key=$(printf '%s\t%s' dell sessao-b | sha256sum | cut -c1-16)
env HOME="$TEST_DIR/home" XDG_CONFIG_HOME="$TEST_DIR/home/.config" \
  TT_DIR="$ROOT" TT_TEST_LOG="$TEST_DIR/tmux.log" \
  TMUX= TMUX_PANE= \
  PATH="$TEST_DIR/bin:$PATH" "$TT" --ir-fixada cliente "fx$key"

grep -qx 'attach-session -t =sessao-b' "$TEST_DIR/tmux.log"

env HOME="$TEST_DIR/home" XDG_CONFIG_HOME="$TEST_DIR/home/.config" \
  TT_DIR="$ROOT" TT_TEST_LOG="$TEST_DIR/tmux.log" \
  TMUX=tmux-test TMUX_PANE=%1 \
  PATH="$TEST_DIR/bin:$PATH" "$TT" --ir-fixada cliente "fx$key"

grep -qx 'switch-client -c cliente -t =sessao-b' "$TEST_DIR/tmux.log"

key_again=$(printf '%s\t%s' dell sessao-b | sha256sum | cut -c1-16)
key_other=$(printf '%s\t%s' dell sessao-a | sha256sum | cut -c1-16)
[[ $key == "$key_again" ]]
[[ $key != "$key_other" ]]

echo 'ok: cliques fixados usam identidade estável'
