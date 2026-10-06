#!/usr/bin/env bash
# v138: client-attached deve usar o ajuste leve por cliente, nunca o redesenho global.
set -u
raiz=$(cd "$(dirname "$0")/.." && pwd)
conf="$raiz/tmux.conf"
falhas=0
ok() { echo "  ok: $1"; }
erro() { echo "  ERRO: $1"; falhas=$((falhas+1)); }

linha=$(grep '^set-hook -g client-attached ' "$conf" 2>/dev/null || true)
[[ $linha == *'--ajustar'*'#{client_name}'* ]] && ok "attach usa --ajustar no cliente novo" || erro "hook attach nao usa ajuste local: $linha"
[[ $linha != *'--redesenhar'* ]] && ok "attach nao dispara redesenho global" || erro "hook ainda dispara --redesenhar"
[[ $linha != *'--ao-anexar'* ]] && ok "caminho experimental ao_anexar removido" || erro "hook usa ao_anexar (quebra Ctrl+q)"
grep -q '^ajustar()' "$raiz/tt" && ok "funcao ajustar presente" || erro "funcao ajustar ausente"

echo
if ((falhas==0)); then echo "TODOS OS TESTES PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit $falhas
