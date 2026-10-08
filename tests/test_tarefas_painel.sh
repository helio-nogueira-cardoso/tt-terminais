#!/usr/bin/env bash
# Painel de tarefas: o despachante único (tarefa_acao) que teclado, mouse e botões usam; ▸/▾ em
# toda tarefa e ☐/☑; clique abre/fecha, 2º clique rápido marca feita; criar digitando na busca;
# menu de ações e ajuda no próprio painel; cabeçalho clicável sem botão partido nem separador
# solto; confirmação antes de apagar; renomear; e a lista rápida mesmo com muitas tarefas.
# Isola HOME/XDG e usa stub de tmux; nenhum arquivo real é tocado.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[[ -x "$TT" ]]; bash -n "$TT"

mkdir -p "$T/home/.config/tt" "$T/bin" "$T/rt"
printf 'nome=A\ntarefas_sync=off\n' >"$T/home/.config/tt/config"
printf '#!/usr/bin/env bash\ncase ${1:-} in list-sessions) exit 1;; display-message) echo cx;; *) exit 0;; esac\n' >"$T/bin/tmux"
chmod +x "$T/bin/tmux"
C="$T/home/.config/tt/tarefas"
UI="$T/rt/tt-tarefas-ui-$(id -u)"
run(){ env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" \
  TT_RT="$T/rt" TT_MACHINE=A LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH="$T/bin:$PATH" "$TT" "$@"; }
acao(){ FZF_QUERY=${Q:-} run --tarefa-acao "$@"; }
sem_cor(){ sed 's/\x1b\[[0-9;]*m//g'; }
lista(){ run --tarefas-lista "${1:-}" | sem_cor; }
id_de(){ awk -F'\t' -v t="$1" '$5==t{print $1; exit}' "$C"; }
est_de(){ awk -F'\t' -v t="$1" '$5==t{print $2; exit}' "$C"; }
fail(){ echo "FALHOU: $1" >&2; exit 1; }

printf 'filtro=todas\nmodo=lista\n' >"$UI"
run --tarefa-add "folha simples" >/dev/null
run --tarefa-add "mae" >/dev/null
mae=$(id_de mae)
run --tarefa-sub-prompt "$mae" <<<"filha" >/dev/null 2>&1
filha=$(id_de filha)

# 1) toda tarefa de topo tem o triângulo (▸ fechada, ▾ aberta) e a caixinha ☐; subtarefa indentada
l=$(lista)
grep -q '▸ ☐ folha simples' <<<"$l" || fail "folha sem ▸ ☐: $l"
grep -q '▾ ☐ mae' <<<"$l" || fail "mãe com subtarefa recém-criada deveria estar aberta (▾): $l"
grep -q '^filha\|	      ☐ filha' <<<"$(run --tarefas-lista | sem_cor)" || fail "subtarefa não aparece indentada"
grep -q '+ adicionar subtarefa' <<<"$l" || fail "tarefa aberta sem a linha clicável '+ adicionar subtarefa'"
grep -q '⋯ mais ações' <<<"$l" || fail "tarefa aberta sem a linha clicável '⋯ mais ações'"
echo "ok: ▸/▾ em toda tarefa, ☐ e linhas de ação clicáveis dentro da tarefa aberta"

# 2) clique numa tarefa de topo abre/fecha; clique na subtarefa marca
f=$(id_de "folha simples")
r=$(acao clique "$f"); grep -q 'reload' <<<"$r" || fail "clique não recarrega: $r"
grep -q '▾ ☐ folha simples' <<<"$(lista)" || fail "clique não abriu a tarefa"
[[ $(est_de "folha simples") == aberta ]] || fail "clique simples não pode marcar a tarefa de topo"
sleep 0.5
acao clique "$f" >/dev/null
grep -q '▸ ☐ folha simples' <<<"$(lista)" || fail "2º clique (devagar) não fechou a tarefa"
acao clique "$filha" >/dev/null
[[ $(est_de filha) == feita ]] || fail "clique na subtarefa não a marcou"
echo "ok: clique abre/fecha a tarefa (▸/▾) e marca a subtarefa"

# 3) 2º clique rápido na mesma linha = duplo: desfaz a abertura e marca feita; o double-click
#    nativo que chega depois é ignorado (não desmarca)
acao clique "$f" >/dev/null; acao clique "$f" >/dev/null
[[ $(est_de "folha simples") == feita ]] || fail "duplo clique não marcou a tarefa"
grep -q '▸ ☑ folha simples' <<<"$(lista)" || fail "duplo clique deveria deixar a tarefa fechada e ☑"
r=$(acao duplo "$f"); [[ $r == ignore ]] || fail "double-click nativo depois do duplo deveria ser ignorado: $r"
[[ $(est_de "folha simples") == feita ]] || fail "double-click nativo desmarcou a tarefa"
acao enter "$f" >/dev/null
[[ $(est_de "folha simples") == aberta ]] || fail "⏎ não desmarcou"
echo "ok: 2º clique rápido marca feita (duplo) e ⏎ alterna"

# 4) criar digitando na busca: a linha '+ criar' aparece; ⏎ cria com a sintaxe natural
l=$(lista 'comprar pao @amanha !alta #casa')
grep -q '+ criar tarefa: comprar pao @amanha !alta #casa' <<<"$l" || fail "busca sem a linha '+ criar': $l"
grep -q 'nenhuma tarefa existente' <<<"$l" || fail "busca sem resultado deveria avisar"
r=$(Q='comprar pao @amanha !alta #casa' acao enter '')
grep -q 'clear-query' <<<"$r" || fail "criar não limpa a busca: $r"
m=$(awk -F'\t' '$5=="comprar pao"{print $6}' "$C")
[[ $m == *prazo=* && $m == *prio=1* && $m == *tags=casa* ]] || fail "criar pela busca não leu prazo/prioridade/tag: '$m'"
grep -q 'comprar pao' <<<"$(lista pao)" || fail "busca não acha a tarefa criada"
grep -q 'comprar pao' <<<"$(lista '#casa')" || fail "busca por #tag não acha a tarefa"
echo "ok: digitar e ⏎ cria a tarefa (com @prazo !prio #tag); a busca acha texto e #tag"

# 5) teclas que digitam: espaço, ? e setas só agem com a busca vazia; esc volta/limpa/fecha
[[ $(Q=x acao espaco "$f") == 'put( )' ]] || fail "espaço com busca deveria digitar"
[[ $(Q=x acao interrogacao "$f") == 'put(?)' ]] || fail "? com busca deveria digitar"
[[ $(Q=x acao esc "$f") == clear-query ]] || fail "esc com busca deveria limpar a busca"
[[ $(acao esc "$f") == abort ]] || fail "esc com busca vazia na lista deveria fechar"
echo "ok: espaço/?/esc respeitam a busca"

# 6) ajuda e menu de ações no próprio painel
acao interrogacao "$f" >/dev/null
[[ $(sed -n 's/^modo=//p' "$UI" | tail -1) == ajuda ]] || fail "? não abriu a ajuda"
h=$(lista)
for k in CRIAR 'NO TÍTULO' DESCRIÇÃO 'PRAZO E HORÁRIO' MOUSE TECLADO '@amanha' '@sex 14h' '!alta' '*semanal' '#casa' 'Ctrl+E'; do
  grep -qF -- "$k" <<<"$h" || fail "ajuda sem '$k'"
done
grep -q 'Como usar' <<<"$(FZF_COLUMNS=70 run --tarefas-cabecalho | sem_cor)" || fail "cabeçalho da ajuda sem título"
acao esc voltar >/dev/null
[[ $(sed -n 's/^modo=//p' "$UI" | tail -1) == lista ]] || fail "esc na ajuda não voltou à lista"
run --tarefas-ajuda | grep -q 'PRAZO E HORÁRIO' || fail "tt --tarefas-ajuda não imprime a ajuda"
acao menu "$f" >/dev/null
mn=$(run --tarefas-lista)
grep -q "^act:prio1:$f" <<<"$mn" || fail "menu sem a escolha de prioridade alta"
grep -q "^act:apagar:$f" <<<"$mn" || fail "menu sem apagar"
acao clique "act:prio2:$f" >/dev/null
[[ $(awk -F'\t' -v id="$f" '$1==id{print $6}' "$C") == *prio=2* ]] || fail "clique em 'Média' no menu não gravou prio=2"
[[ $(sed -n 's/^modo=//p' "$UI" | tail -1) == lista ]] || fail "item do menu deveria voltar à lista"
acao menu "$f" >/dev/null; acao clique "act:repw:$f" >/dev/null
[[ $(awk -F'\t' -v id="$f" '$1==id{print $6}' "$C") == *rep=w* ]] || fail "menu 'Toda semana' não gravou rep=w"
echo "ok: ajuda (?) e menu de ações (botão direito) com escolhas clicáveis"

# 7) cabeçalho: cada item do mapa cobre exatamente o rótulo desenhado; botão não parte entre
#    linhas e nenhuma linha termina com separador solto
for larg in 40 64 72 120; do
  cab=$(FZF_COLUMNS=$larg run --tarefas-cabecalho | sem_cor)
  while read -r ln c1 c2 ac; do
    [[ -n $ac ]] || continue
    txt=$(sed -n "${ln}p" <<<"$cab"); pedaco=${txt:$((c1 - 1)):$((c2 - c1 + 1))}
    [[ -n ${pedaco// /} ]] || fail "mapa aponta para vazio ($ac em $larg)"
    case $ac in
      filtro:hoje) [[ $pedaco == *Hoje* ]] ;; nova) [[ $pedaco == *Nova* ]] ;; feita) [[ $pedaco == *Feita* ]] ;;
      ajuda) [[ $pedaco == *Ajuda* ]] ;; apagar) [[ $pedaco == *Apagar* ]] ;; cima) [[ $pedaco == *↑* ]] ;;
      baixo) [[ $pedaco == *↓* ]] ;; *) true ;;
    esac || fail "mapa do cabeçalho desalinhado em $larg colunas: $ac -> '$pedaco'"
    ((c2 <= larg - 3)) || fail "botão $ac passa da largura ($c2 > $((larg - 3)))"
  done <"$T/rt/tt-tarefas-mapa-$(id -u)"
  grep -qE '(·|•)\s*$' <<<"$cab" && fail "linha do cabeçalho termina com separador solto ($larg colunas)"
done
FZF_COLUMNS=72 run --tarefas-cabecalho >/dev/null
colf=$(awk '$4=="filtro:feitas"{print $2 + 1}' "$T/rt/tt-tarefas-mapa-$(id -u)")
r=$(FZF_CLICK_HEADER_LINE=1 FZF_CLICK_HEADER_COLUMN=$colf acao cabecalho "$f")
grep -q reload <<<"$r" || fail "clique na aba não recarrega: $r"
[[ $(sed -n 's/^filtro=//p' "$UI" | tail -1) == feitas ]] || fail "clique na aba Feitas não trocou o filtro"
echo "ok: cabeçalho clicável, alinhado ao mapa, sem botão partido nem separador solto"

# 8) apagar e limpar pedem confirmação; renomear troca só o texto
printf 'filtro=todas\nmodo=lista\n' >"$UI"
run --tarefa-remover-prompt "$f" <<<"" >/dev/null 2>&1
[[ $(est_de "folha simples") != removida ]] || fail "apagar sem confirmar removeu a tarefa"
run --tarefa-remover-prompt "$f" <<<"s" >/dev/null 2>&1
[[ $(est_de "folha simples") == removida ]] || fail "apagar confirmado não removeu"
run --tarefa-limpar-prompt <<<"n" >/dev/null 2>&1
[[ $(est_de filha) == feita ]] || fail "limpar sem confirmar removeu as feitas"
run --tarefa-renomear "$mae" "mae renomeada" >/dev/null
[[ $(awk -F'\t' -v id="$mae" '$1==id{print $5}' "$C") == "mae renomeada" ]] || fail "renomear não trocou o texto"
grep -q "pai=$mae" "$C" || fail "renomear perdeu as subtarefas"
echo "ok: apagar/limpar confirmam e renomear preserva id e subtarefas"

# 9) desempenho: 300 tarefas renderizam rápido (a versão antiga levava segundos com 45)
h=$(date +%s)
for ((i = 1; i <= 300; i++)); do
  printf 'b%011d\taberta\t%s\t%s\tTarefa %s #t%s\tprazo=%s|prio=%s|tags=x\n' "$i" "$h" "$h" "$i" "$i" $((h + i * 3600)) $((i % 3)) >>"$C"
done
t0=$(date +%s%N); n=$(run --tarefas-lista | grep -c 'Tarefa '); t1=$(date +%s%N)
((n == 300)) || fail "lista deveria ter 300 tarefas, tem $n"
(( (t1 - t0) / 1000000 < 2000 )) || fail "lista com 300 tarefas levou $(( (t1 - t0) / 1000000 )) ms"
echo "ok: 300 tarefas em $(( (t1 - t0) / 1000000 )) ms"
