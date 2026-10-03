#!/usr/bin/env bash
# Testes de regressão do tt. Uso:
#   tests/run.sh                         # fonte deste clone
#   TT_DIR=~/.local/share/tt tests/run.sh # instalação ativa
set -euo pipefail

raiz=${TT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}
tt=$raiz/tt
conf=$raiz/tmux.conf
tema=$raiz/tema-tmux.conf
falhas=0

ok() { printf 'ok — %s\n' "$1"; }
falha() { printf 'FALHOU — %s\n' "$1" >&2; falhas=$((falhas + 1)); }
exige() { command -v "$1" >/dev/null || { printf 'falta dependência de teste: %s\n' "$1" >&2; exit 2; }; }
tem() { rg -q -- "$2" "$1"; }

for cmd in bash python3 rg tmux; do exige "$cmd"; done
[[ -x $tt ]] || { printf 'tt não executável: %s\n' "$tt" >&2; exit 2; }
[[ -f $conf ]] || { printf 'tmux.conf não encontrado: %s\n' "$conf" >&2; exit 2; }
[[ -f $tema ]] || { printf 'tema-tmux.conf não encontrado: %s\n' "$tema" >&2; exit 2; }

if bash -n "$tt"; then ok 'sintaxe Bash'; else falha 'sintaxe Bash'; fi

awk '/^  codigo=\$\(cat <<'\''PYEOF'\''/{captura=1; next} captura && /^PYEOF$/{exit} captura {print}' "$tt" |
  python3 -c 'import sys; compile(sys.stdin.read(), "com_mouse", "exec")'
ok 'sintaxe Python da ponte de mouse'

tem "$tt" ': >"\$arq"' &&
  tem "$tt" "pendente = b''" &&
  tem "$tt" "\\(\[Mm\]\)" &&
  tem "$tt" 'dados = pendente \+ d' &&
  tem "$tt" 'resto\.rfind' && ok 'ponte de mouse: estado e pacotes fragmentados' ||
  falha 'ponte de mouse não protege contra coordenada velha/pacote fragmentado'

tem "$tt" 't_atualizacao=\$\{TT_T_ATUALIZACAO:-300\}' &&
  tem "$tt" -- '--garantir-atualizacao' &&
  tem "$tt" 'REPO_TT=\$DIR_FONTE' &&
  tem "$tt" '\(\(n > atual\)\)' && ok 'vigia exige a versão publicada mais nova' ||
  falha 'vigia não garante atualização publicada'

tem "$tt" '^versao_barra\(\)' &&
  tem "$tema" '@barra_versao' && ok 'versão exibida na faixa de fixadas' ||
  falha 'versão não foi ligada à faixa de fixadas'

tem "$tt" 'c\[3:4\] == \["oculta"\]' &&
  tem "$tt" '^ocultar_maquina\(\)' &&
  tem "$tt" '^mostrar_maquina\(\)' && ok 'ocultar/mostrar preserva máquinas cadastradas' ||
  falha 'ocultar/mostrar máquinas não está completo'

for evento in Status StatusLeft StatusRight; do
  if rg -q "MouseDown1$evento.*#\{m:(fx|fxx)\*" "$conf" &&
     rg -q "MouseUp1$evento.*#\{m:(fx|fxx)\*" "$conf"; then
    ok "fixadas em MouseDown/MouseUp$evento"
  else
    falha "fixadas sem proteção completa em $evento"
  fi
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/tt-test.XXXXXX")
sock=$tmp/tmux.sock
limpar() { tmux -S "$sock" kill-server >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap limpar EXIT
tmux -S "$sock" -f "$conf" new-session -d -s tt-test 'sleep 5'
tmux -S "$sock" list-keys -T root >"$tmp/keys"
for evento in MouseDown1Status MouseDown1StatusLeft MouseDown1StatusRight MouseUp1Status MouseUp1StatusLeft MouseUp1StatusRight; do
  rg -q " $evento " "$tmp/keys" || falha "binding tmux ausente: $evento"
done
((falhas == 0)) && ok 'configuração tmux isolada' || true

((falhas == 0)) || exit 1
printf 'Todos os testes passaram (%s).\n' "$raiz"
