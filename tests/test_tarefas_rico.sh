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
          tarefas_filhas tarefa_sub_mover calendario_tui tarefas_filtro_ciclar tarefas_prazo_texto; do
  grep -q "^$fn()" "$TT" || { echo "FALHOU: função $fn ausente"; exit 1; }
done
grep -q -- '--wrap' "$TT" || { echo "FALHOU: fzf de tarefas sem --wrap (texto não quebra)"; exit 1; }
grep -q 'range=user|relogio' "$ROOT/tt" || { echo "FALHOU: relógio sem range p/ calendário"; exit 1; }

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

# render (sem as cores): mãe com texto + ▾ + subs indentadas
sem_cor(){ sed 's/\x1b\[[0-9;]*m//g' | cut -f2-; }
lista=$(run --tarefas-lista | sem_cor)
grep -q '▾ ☐ mae com texto' <<<"$lista" || fail "mãe não mostra texto nem o marcador ▾ ($lista)"
[[ $(grep -c '    ☐ sub' <<<"$lista") == 2 ]] || fail "subtarefas não aparecem indentadas sob a mãe"
echo "ok: render mostra o texto da mãe (não corta) e as subtarefas indentadas"

# reordenar subtarefa
sub2=$(awk -F'\t' '$5=="sub dois"{print $1}' "$C")
run --tarefa-sub-mover "$sub2" cima
lista2=$(run --tarefas-lista | sem_cor)
primeira_sub=$(grep -m1 '    ☐ sub' <<<"$lista2")
grep -q 'sub dois' <<<"$primeira_sub" || fail "mover sub p/ cima não reordenou (1ª sub: $primeira_sub)"
echo "ok: subtarefa reordenada (sub dois subiu)"

# clique na mãe expande e recolhe (toggle). Mãe começa expandida (criar sub expande).
grep -q '▾' <<<"$(run --tarefas-lista)" || fail "mãe deveria iniciar expandida (▾) após criar subtarefas"
run --tarefa-clique "$id" >/dev/null 2>&1   # 1º clique: recolhe
lista_rec=$(run --tarefas-lista | sem_cor)
grep -q '▸ ☐ mae com texto' <<<"$lista_rec" || fail "clique na mãe não recolheu (sem ▸)"
[[ $(grep -c '    ☐ sub' <<<"$lista_rec") == 0 ]] || fail "mãe recolhida ainda mostra subtarefas"
run --tarefa-clique "$id" >/dev/null 2>&1   # 2º clique: expande de novo (regressão do grep rc=1)
lista_exp=$(run --tarefas-lista | sem_cor)
grep -q '▾ ☐ mae com texto' <<<"$lista_exp" || fail "clique na mãe não expandiu de volta (bug grep rc=1)"
[[ $(grep -c '    ☐ sub' <<<"$lista_exp") == 2 ]] || fail "mãe reexpandida não mostra as 2 subtarefas"
echo "ok: clique na mãe expande e recolhe (toggle estável nos dois sentidos)"

# descrição editável (editor simulado), guardada em base64, restaurada no preview
run --tarefa-add "com descricao" >/dev/null
idd=$(awk -F'\t' '$5=="com descricao"{print $1}' "$C")
printf '#!/bin/sh\nprintf "linha 1\\nlinha 2 com acento ção\\n" > "$1"\n' >"$T/bin/fakeed"; chmod +x "$T/bin/fakeed"
EDITOR="$T/bin/fakeed" run --tarefa-desc-editor "$idd" >/dev/null 2>&1
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

# filtro: default = todas; ciclo todas -> hoje -> abertas -> feitas -> prazo -> todas
run --tarefa-ok "$idd" >/dev/null
grep -q 'com descricao' <<<"$(run --tarefas-lista)" || fail "filtro default (todas) deveria mostrar a tarefa feita"
run --tarefa-filtro-ciclar; grep -q 'com prazo' <<<"$(run --tarefas-lista)" || fail "filtro hoje deveria mostrar a tarefa com prazo de hoje"
run --tarefa-filtro-ciclar; grep -q 'com descricao' <<<"$(run --tarefas-lista)" && fail "filtro abertas não deveria mostrar tarefa feita"
run --tarefa-filtro-ciclar; grep -q 'com descricao' <<<"$(run --tarefas-lista)" || fail "filtro feitas não mostra a feita"
run --tarefa-filtro-ciclar; grep -q 'com prazo' <<<"$(run --tarefas-lista)" || fail "filtro prazo não mostra tarefa com prazo"
run --tarefa-filtro-ciclar; grep -q 'mae com texto' <<<"$(run --tarefas-lista)" || fail "filtro todas não mostra tudo"
echo "ok: filtro cicla todas → hoje → abertas → feitas → com prazo → todas (default todas)"

# cabeçalho com abas: as 4 abas aparecem; clicar numa aba troca o filtro ativo
cab=$(run --tarefas-cabecalho)
{ grep -qi 'abertas' <<<"$cab" && grep -qi 'feitas' <<<"$cab" && grep -qi 'prazo' <<<"$cab" && grep -qi 'todas' <<<"$cab"; } || fail "cabeçalho não mostra as 4 abas de filtro"
# simula o clique do fzf na aba "Feitas": linha 1, coluna da palavra (env FZF_CLICK_HEADER_*). A coluna
# é em CÉLULAS de tela, como o fzf informa (wc -L): index() do awk conta bytes no mawk e caracteres no
# gawk, e um "·" ou emoji antes da palavra já desloca o clique.
l1=$(run --tarefas-cabecalho | sed -n '1p' | sed 's/\x1b\[[0-9;]*m//g')
colf=$(( $(printf '%s' "${l1%%Feitas*}" | wc -L) + 1 ))
acoes=$(env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" \
  TT_RT="$T/rt" TT_MACHINE=A PATH="$T/bin:$PATH" FZF_CLICK_HEADER_LINE=1 FZF_CLICK_HEADER_COLUMN="$colf" \
  "$TT" --tarefa-cabecalho-clique)
grep -q 'reload' <<<"$acoes" || fail "clique no cabeçalho não devolve ações do fzf (reload)"
grep -q 'feitas' <<<"$(cat "$T/rt/"tt-tarefas-ui-* 2>/dev/null)" || fail "clique na aba não gravou o filtro feitas"
run --tarefa-cabecalho-clique >/dev/null 2>&1 || true  # clique fora de aba não quebra
echo "ok: cabeçalho mostra abas de filtro e o clique troca o filtro ativo"

# cascata: remover a mãe remove as subtarefas
run --tarefa-rm "$id"
[[ $(awk -F'\t' -v p="pai=$id" '$6 ~ p && $2!="removida"' "$C" | grep -c .) == 0 ]] \
  || fail "remover a mãe deixou subtarefas vivas (órfãs)"
echo "ok: remover a mãe remove as subtarefas em cascata"

echo 'ok: tarefas ricas (descrição, prazo/calendário, subtarefas, filtro, wrap) — modelo retrocompatível'
