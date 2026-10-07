#!/usr/bin/env bash
# Tarefas: descrição editável, prazo (calendário), subtarefas (criar, listar, reordenar, cascata),
# filtro e render com indentação. Modelo estendido (6º campo meta) retrocompatível com linhas de 5
# campos. Isola HOME/XDG e usa stub de tmux; nenhum arquivo real é tocado.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[[ -x "$TT" ]]; bash -n "$TT"

for fn in tarefas_meta_get tarefas_meta_set tarefa_set_meta tarefa_set_desc tarefa_add_sub \
          tarefas_filhas tarefa_sub_mover calendario_tui tarefas_filtro_ciclar tarefas_prazo_rotulo; do
  grep -q "^$fn()" "$TT" || { echo "FALHOU: função $fn ausente"; exit 1; }
done
grep -q -- '--wrap' "$TT" || { echo "FALHOU: fzf de tarefas sem --wrap (texto não quebra)"; exit 1; }
grep -q 'range=user|relogio' "$ROOT/tema-tmux.conf" || { echo "FALHOU: relógio sem range p/ calendário"; exit 1; }

mkdir -p "$T/home/.config/tt" "$T/bin" "$T/rt"
printf 'nome=A\n' >"$T/home/.config/tt/config"
printf '#!/usr/bin/env bash\ncase ${1:-} in list-sessions) exit 1;; display-message) echo cx;; *) exit 0;; esac\n' >"$T/bin/tmux"
chmod +x "$T/bin/tmux"
C="$T/home/.config/tt/tarefas"
run(){ env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" \
  TT_RT="$T/rt" TT_MACHINE=A PATH="$T/bin:$PATH" "$TT" "$@"; }
cal(){ env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" \
  TT_RT="$T/rt" TT_MACHINE=A PATH="$T/bin:$PATH" TT_CAL_TECLAS="$1" "$TT" --calendario "" 2>/dev/null; }
fail(){ echo "FALHOU: $1" >&2; exit 1; }

# retrocompatibilidade: linha antiga de 5 campos
printf '%s\taberta\t100\t100\ttarefa antiga\n' aaaaaaaaaaaa >"$C"
grep -q 'tarefa antiga' <<<"$(run --tarefas-lista)" || fail "linha antiga de 5 campos não é lida"
echo "ok: modelo antigo (5 campos) continua válido"

# add + subtarefas
run --tarefa-add "mae com texto bem longo que precisaria de wrap no painel estreito" >/dev/null
id=$(awk -F'\t' '$5 ~ /^mae com texto/{print $1}' "$C")
[[ $id =~ ^[0-9a-f]{12}$ ]] || fail "id da mãe inválido"
run --tarefa-sub-prompt "$id" <<<"sub um" >/dev/null 2>&1
run --tarefa-sub-prompt "$id" <<<"sub dois" >/dev/null 2>&1
[[ $(grep -c "pai=$id" "$C") == 2 ]] || fail "deveriam existir 2 subtarefas com pai=$id"
echo "ok: subtarefas criadas com pai e ordem"

# render: mãe com texto + ▾ + subs indentadas
lista=$(run --tarefas-lista)
grep -q '▾ ▢ mae com texto' <<<"$lista" || fail "mãe não mostra texto nem o marcador ▾ ($lista)"
[[ $(grep -c '    ▢ sub' <<<"$lista") == 2 ]] || fail "subtarefas não aparecem indentadas sob a mãe"
echo "ok: render mostra o texto da mãe (não corta) e as subtarefas indentadas"

# reordenar subtarefa
sub2=$(awk -F'\t' '$5=="sub dois"{print $1}' "$C")
run --tarefa-sub-mover "$sub2" cima
lista2=$(run --tarefas-lista)
primeira_sub=$(grep -m1 '    ▢ sub' <<<"$lista2")
grep -q 'sub dois' <<<"$primeira_sub" || fail "mover sub p/ cima não reordenou (1ª sub: $primeira_sub)"
echo "ok: subtarefa reordenada (sub dois subiu)"

# descrição editável (editor simulado), guardada em base64, restaurada no preview
run --tarefa-add "com descricao" >/dev/null
idd=$(awk -F'\t' '$5=="com descricao"{print $1}' "$C")
printf '#!/bin/sh\nprintf "linha 1\\nlinha 2 com acento ção\\n" > "$1"\n' >"$T/bin/fakeed"; chmod +x "$T/bin/fakeed"
EDITOR="$T/bin/fakeed" run --tarefa-desc-prompt "$idd" >/dev/null 2>&1
grep -q 'desc=' "$C" || fail "descrição não gravou a chave desc na meta"
grep -q 'linha 2 com acento' "$C" && fail "descrição vazou em claro na linha (deveria ser base64)"
prev=$(run --tarefa-preview "$idd")
{ grep -q 'linha 1' <<<"$prev" && grep -q 'linha 2 com acento ção' <<<"$prev"; } || fail "preview não restaura a descrição multi-linha"
echo "ok: descrição editável multi-linha em base64, restaurada no preview"

# prazo via calendário headless
run --tarefa-add "com prazo" >/dev/null
[[ $(cal $'\n') == "$(date -d 'today 12:00' +%s)" ]] || fail "calendário: Enter em hoje deveria dar hoje 12:00"
[[ $(cal $'l\n') == "$(date -d 'tomorrow 12:00' +%s)" ]] || fail "calendário: l (→) deveria avançar um dia"
[[ $(cal 'x') == limpar ]] || fail "calendário: x deveria devolver 'limpar'"
echo "ok: calendário interativo escolhe data (hoje/+1), navega e limpa"
# grava o prazo de hoje na tarefa "com prazo" para o filtro de prazo
idp=$(awk -F'\t' '$5=="com prazo"{print $1}' "$C")
printf '#!/bin/sh\nexit 0\n' >"$T/bin/true2"  # placeholder
# usa o fluxo real: TT_CAL_TECLAS Enter via o prompt de prazo
env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" \
  TT_RT="$T/rt" TT_MACHINE=A PATH="$T/bin:$PATH" TT_CAL_TECLAS=$'\n' "$TT" --tarefa-prazo-prompt "$idp" >/dev/null 2>&1
grep -q 'prazo=' "$C" || fail "prazo não foi gravado na tarefa"
echo "ok: prazo gravado pelo prompt de calendário"

# filtro: abertas -> feitas -> prazo -> todas
run --tarefa-ok "$idd" >/dev/null
grep -q 'com descricao' <<<"$(run --tarefas-lista)" && fail "filtro abertas não deveria mostrar tarefa feita"
run --tarefa-filtro-ciclar; grep -q 'com descricao' <<<"$(run --tarefas-lista)" || fail "filtro feitas não mostra a feita"
run --tarefa-filtro-ciclar; grep -q 'com prazo' <<<"$(run --tarefas-lista)" || fail "filtro prazo não mostra tarefa com prazo"
run --tarefa-filtro-ciclar; grep -q 'mae com texto' <<<"$(run --tarefas-lista)" || fail "filtro todas não mostra tudo"
run --tarefa-filtro-ciclar >/dev/null  # volta p/ abertas
echo "ok: filtro cicla abertas → feitas → com prazo → todas"

# cabeçalho com abas: as 4 abas aparecem; clicar numa aba troca o filtro ativo
cab=$(run --tarefas-cabecalho)
{ grep -q 'abertas' <<<"$cab" && grep -q 'feitas' <<<"$cab" && grep -q 'prazo' <<<"$cab" && grep -q 'todas' <<<"$cab"; } || fail "cabeçalho não mostra as 4 abas de filtro"
run --tarefa-cabecalho-clique feitas
grep -q 'feitas' <<<"$(cat "$T/rt/"tt-tarefas-ui-* 2>/dev/null)" || fail "clique na aba não gravou o filtro"
run --tarefa-cabecalho-clique abertas
echo "ok: cabeçalho mostra abas de filtro e o clique troca o filtro ativo"

# cascata: remover a mãe remove as subtarefas
run --tarefa-rm "$id"
[[ $(awk -F'\t' -v p="pai=$id" '$6 ~ p && $2!="removida"' "$C" | grep -c .) == 0 ]] \
  || fail "remover a mãe deixou subtarefas vivas (órfãs)"
echo "ok: remover a mãe remove as subtarefas em cascata"

echo 'ok: tarefas ricas (descrição, prazo/calendário, subtarefas, filtro, wrap) — modelo retrocompatível'
