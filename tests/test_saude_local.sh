#!/usr/bin/env bash
# tt --saude: as ultimas falhas do unit-failures.tsv saem com o estado limpo, com 3 colunas ou com a
# 4a (assinatura do erro, gravada pelo tt-onfailure). Sem o `_` no read, saia FAILED<TAB>assinatura.
source "$(dirname "$0")/lib.sh"; isolar
fail() { echo "FALHOU: $1" >&2; exit 1; }
mkdir -p "$T/bin" "$HOME/.local/state/tt"
printf '#!/bin/sh\nexit 1\n' >"$T/bin/systemctl"; chmod +x "$T/bin/systemctl" # nada do systemd de quem roda a suíte
printf '2026-01-01T00:00:00Z\ta.service\tFAILED\n2026-01-01T00:01:00Z\tb.service\tFAILED\terro # no passo\n' \
  >"$HOME/.local/state/tt/unit-failures.tsv"
saida=$(PATH="$T/bin:$PATH" "$TT_DIR/tt" --saude)
grep -qxF '    2026-01-01T00:00:00Z  a.service FAILED' <<<"$saida" || fail "linha de 3 colunas: $saida"
grep -qxF '    2026-01-01T00:01:00Z  b.service FAILED' <<<"$saida" || fail "linha de 4 colunas: $saida"
echo "ok: tt --saude mostra só o estado, com 3 ou 4 colunas no unit-failures.tsv"
