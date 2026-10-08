#!/usr/bin/env bash
# Tags: a captura natural reconhece #tag na frase e grava em meta tags=a,b; o render mostra as tags
# como #a #b (texto visível, logo o fzf as filtra ao digitar). Isola HOME/XDG; nenhum arquivo real.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[[ -x "$TT" ]] || { echo "FALHOU: tt não executável"; exit 1; }
bash -n "$TT" || { echo "FALHOU: sintaxe"; exit 1; }

mkdir -p "$T/home/.config/tt" "$T/bin" "$T/rt"
printf 'nome=A\n' >"$T/home/.config/tt/config"
printf '#!/usr/bin/env bash\ncase ${1:-} in list-sessions) exit 1;; display-message) echo cx;; *) exit 0;; esac\n' >"$T/bin/tmux"
chmod +x "$T/bin/tmux"
C="$T/home/.config/tt/tarefas"
run(){ env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" \
  TT_RT="$T/rt" TT_MACHINE=A PATH="$T/bin:$PATH" "$TT" "$@"; }
linha(){ awk -F'\t' -v t="$1" '$5==t{print; exit}' "$C"; }
fail(){ echo "FALHOU: $1" >&2; exit 1; }

# 1) duas tags viram tags=casa,mercado e saem do texto
run --tarefa-add-natural "Comprar leite #casa #mercado" >/dev/null
l=$(linha "Comprar leite")
[[ -n $l ]] || fail "texto não ficou limpo 'Comprar leite': $(cat "$C")"
grep -q 'tags=casa,mercado' <<<"$l" || fail "tags não viraram tags=casa,mercado: $l"
echo "ok: #tag na frase vira meta tags e sai do texto"

# 2) render mostra as tags como #casa #mercado
r=$(run --tarefas-lista)
grep -q '#casa' <<<"$r" && grep -q '#mercado' <<<"$r" || fail "render não mostra as tags: $r"
echo "ok: render mostra as tags (#casa #mercado) — fzf filtra por elas ao digitar"

# 3) preview lista as tags
id=$(awk -F'\t' '$5=="Comprar leite"{print $1}' "$C")
grep -q 'tags: #casa #mercado' <<<"$(run --tarefa-preview "$id")" || fail "preview não lista as tags"
echo "ok: preview lista as tags"

# 4) tags convivem com prazo/prioridade/recorrência na mesma frase
run --tarefa-add-natural "Reuniao #trabalho @hoje !alta *w" >/dev/null
l=$(linha "Reuniao")
{ grep -q 'tags=trabalho' <<<"$l" && grep -q 'prio=1' <<<"$l" && grep -q 'rep=w' <<<"$l" && grep -q 'prazo=' <<<"$l"; } \
  || fail "tags não convivem com os outros tokens: $l"
echo "ok: tags convivem com prazo, prioridade e recorrência"
