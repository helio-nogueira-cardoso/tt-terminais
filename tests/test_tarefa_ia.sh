#!/usr/bin/env bash
# 🤖 Implementar com a melhor IA (botão ✦ IA do painel, ^g, ⋯ menu e CLI --tarefa-implementar): o pedido
# lista a tarefa, a descrição e as subtarefas com os ids; a sessão nova roda `ia-conta abrir
# --prompt-arquivo`; subtarefa pede só ela; o painel fecha (abort) depois de abrir. Tudo isolado, com
# tmux e ia-conta de mentira.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash -n "$TT"; bash -n "$ROOT/ia-conta"
fail(){ echo "FALHOU: $1" >&2; exit 1; }

grep -Fq -- "_botao '✦ IA' ia" "$TT" || fail "cabeçalho sem o botão ✦ IA"
grep -Fq -- 'ctrl-g:transform($a ia {1})' "$TT" || fail "^g não vai para o evento ia"
grep -Fq -- '--tarefa-implementar)' "$TT" || fail "verbo --tarefa-implementar ausente"
grep -Fq -- '--prompt-arquivo' "$ROOT/ia-conta" || fail "ia-conta abrir sem --prompt-arquivo"

mkdir -p "$T/home/.config/tt" "$T/bin" "$T/rt" "$T/proj"
printf 'nome=A\ntarefas_sync=off\n' >"$T/home/.config/tt/config"
# tmux de mentira: registra as chamadas; display-message devolve a pasta do projeto
cat >"$T/bin/tmux" <<FIM
#!/usr/bin/env bash
echo "\$*" >>"$T/tmux.log"
case \${1:-} in
  has-session) exit 1;;
  list-clients) printf 'cx\t$T/proj\n'; exit 0;;
  *) exit 0;;
esac
FIM
chmod +x "$T/bin/tmux"
printf '#!/usr/bin/env bash\nexit 0\n' >"$T/bin/ia-conta"; chmod +x "$T/bin/ia-conta"
run(){ env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" \
  TT_RT="$T/rt" TT_DIR="$T/pacote" TMUX=/x,1,0 TT_MACHINE=A LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH="$T/bin:$PATH" "$TT" "$@"; }
mkdir -p "$T/pacote"; cp "$T/bin/ia-conta" "$T/pacote/ia-conta"

run --tarefa-add "Trocar o botão de salvar @sex" >/dev/null
C="$T/home/.config/tt/tarefas"
id=$(awk -F'\t' '$5 ~ /^Trocar o botão/{print $1; exit}' "$C")
[[ -n $id ]] || fail "tarefa não criada"
run --tarefa-sub-add "$id" "Mudar o ícone" >/dev/null 2>&1 || run --tarefa-sub-prompt "$id" >/dev/null 2>&1 || true
sub=$(awk -F'\t' '$5=="Mudar o ícone"{print $1; exit}' "$C")
[[ -n $sub ]] || fail "subtarefa não criada"

p=$(run --tarefa-ia-prompt "$id")
grep -Fq "TAREFA [$id]: Trocar o botão de salvar" <<<"$p" || fail "pedido sem a tarefa"
grep -Fq "[$sub] aberta · Mudar o ícone" <<<"$p" || fail "pedido sem a subtarefa e o id"
grep -Fq "tt --tarefa-ok <id>" <<<"$p" || fail "pedido sem a instrução de marcar como feita"
grep -Fq "não faça push" <<<"$p" || fail "pedido sem a trava de publicar"
ps=$(run --tarefa-ia-prompt "$sub")
grep -Fq "SUBTAREFA [$sub]" <<<"$ps" || fail "pedido da subtarefa sem o rótulo"
grep -Fq "da tarefa [$id]" <<<"$ps" || fail "pedido da subtarefa sem a mãe"
echo "ok: o pedido traz tarefa, subtarefas com ids e as regras"

n=$(run --tarefa-implementar "$id" cx) || fail "implementar falhou"
[[ $n == impl-1 ]] || fail "nome da sessão: '$n'"
grep -q "^new-session -d -s impl-1 -c $T/proj .*abrir --prompt-arquivo .*tt-impl-$id.md" "$T/tmux.log" || fail "new-session sem ia-conta abrir --prompt-arquivo na pasta do cliente: $(grep new-session "$T/tmux.log")"
grep -q "^switch-client -c cx -t =impl-1" "$T/tmux.log" || fail "cliente não foi levado à sessão"
[[ -s $T/rt/tt-impl-$id.md ]] || fail "arquivo do pedido não gravado"
echo "ok: sessão nova na pasta do cliente com a IA e o pedido"

: >"$T/tmux.log"
out=$(TT_CLIENTE=cx run --tarefa-acao ia "$id")
[[ $out == abort ]] || fail "o painel deveria fechar (abort), veio '$out'"
grep -q '^new-session' "$T/tmux.log" || fail "a ação ia não abriu a sessão"
out=$(run --tarefa-acao ia "act:ia:$id")
[[ $out == abort ]] || fail "pelo menu (act:ia:ID) deveria fechar, veio '$out'"
echo "ok: ação ia do painel abre a sessão e fecha o painel"

run --tarefa-implementar nao-existe >/dev/null 2>&1 && fail "id inexistente deveria falhar"
echo "ok: id inexistente falha"
