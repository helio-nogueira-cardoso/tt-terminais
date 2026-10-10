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

# 1) toda tarefa de topo tem o triângulo, pela uniformidade: azul (▸ fechada, ▾ aberta) quando tem
#    subtarefa, ▸ apagado quando não tem o que abrir; toda tarefa tem a caixinha ☐; subtarefa indentada
l=$(lista)
grep -qE $'\t ▸ ☐ folha simples' <<<"$l" || fail "folha deveria ter o ▸ (apagado) no lugar, alinhado: $l"
grep 'folha simples' <<<"$(run --tarefas-lista)" | grep -qF $'\e[38;2;69;71;90m▸' || fail "o ▸ da folha deveria ser apagado (#45475a)"
grep -q '▾ ☐ folha simples' <<<"$l" && fail "folha (sem subtarefa) não pode aparecer aberta (▾): $l"
grep -q '▾ ☐ mae' <<<"$l" || fail "mãe com subtarefa recém-criada deveria estar aberta (▾): $l"
grep -q '^filha\|	      ☐ filha' <<<"$(run --tarefas-lista | sem_cor)" || fail "subtarefa não aparece indentada"
grep -q "^menu:$mae	 *⋯ menu$" <<<"$(run --tarefas-lista | sem_cor)" || fail "tarefa aberta sem o '⋯ menu' discreto (uma linha só, à direita)"
grep -q 'adicionar subtarefa\|mais ações\|escrever uma descrição' <<<"$l" && fail "as linhas de ação sob a tarefa deveriam ter virado só o ⋯ menu: $l"
[[ $(FZF_COLUMNS=80 run --tarefas-lista | sem_cor | grep "^menu:$mae" | cut -f2 | wc -L) -ge 70 ]] || fail "o ⋯ menu deveria ficar encostado à direita"
echo "ok: ▸ em todas (apagado sem subtarefa), ▾ só em quem abre, ☐ em todas, e só um ⋯ menu discreto à direita dentro da tarefa aberta"

# 2) clique numa tarefa COM subtarefa abre/fecha; sem subtarefa não há o que abrir (ignorado, nem o
#    espaço nem a seta abrem); clique na subtarefa marca
f=$(id_de "folha simples")
r=$(acao clique "$f"); [[ $r == ignore ]] || fail "clique em tarefa sem subtarefa deveria ser ignorado: $r"
[[ $(acao espaco "$f") == ignore ]] || fail "espaço em tarefa sem subtarefa deveria ser ignorado"
acao direita "$f" >/dev/null
grep -q '▾ ☐ folha simples' <<<"$(lista)" && fail "tarefa sem subtarefa não pode abrir (clique/espaço/seta)"
[[ $(est_de "folha simples") == aberta ]] || fail "clique simples não pode marcar a tarefa de topo"
sleep 0.5
r=$(acao clique "$mae"); grep -q 'reload' <<<"$r" || fail "clique na mãe não recarrega: $r"
grep -q '▸ ☐ mae' <<<"$(lista)" || fail "clique não fechou a mãe (estava aberta)"
sleep 0.5
acao clique "$mae" >/dev/null
grep -q '▾ ☐ mae' <<<"$(lista)" || fail "2º clique (devagar) não reabriu a mãe"
acao clique "$filha" >/dev/null
[[ $(est_de filha) == feita ]] || fail "clique na subtarefa não a marcou"
acao clique "$filha" >/dev/null
echo "ok: clique abre/fecha só a tarefa com subtarefa (▸/▾) e marca a subtarefa"

# 2b) descrição não conta como "ter o que abrir"; marca de aberta que sobrou é ignorada
run --tarefa-add "so nota" >/dev/null; n=$(id_de "so nota")
printf 'uma nota longa\n' | run --tarefa-desc "$n" - >/dev/null
printf 'exp=%s\n' "$n" >>"$UI"
l=$(lista)
grep -qE $'\t ▸ ☐ so nota' <<<"$l" && ! grep -q '▾ ☐ so nota' <<<"$l" || fail "tarefa só com descrição deveria ficar com o ▸ apagado, sem abrir: $l"
grep -qE '▾ ☐ so nota|^menu:'"$n" <<<"$l" && fail "exp= antigo de tarefa sem subtarefa não pode abrir os detalhes: $l"
grep -q 'so nota.*≡' <<<"$l" || fail "a descrição deveria seguir marcada com ≡"
sed -i "/^exp=$n\$/d" "$UI"
echo "ok: só descrição não abre nada (▸ apagado) e exp= sobrando é ignorado"

# 3) 2º clique rápido na mesma linha = duplo: marca feita (e, se a abriu, desfaz); o double-click
#    nativo que chega depois é ignorado (não desmarca)
acao clique "$f" >/dev/null; acao clique "$f" >/dev/null
[[ $(est_de "folha simples") == feita ]] || fail "duplo clique não marcou a tarefa"
grep -qE $'\t ▸ ☑ folha simples' <<<"$(lista)" || fail "duplo clique deveria deixar a tarefa ☑ (▸ apagado, sem abrir)"
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
      filtro:hoje) [[ $pedaco == *Hoje* ]] ;; nova) [[ $pedaco == *+* ]] ;; feita) [[ $pedaco == *Feita* ]] ;;
      ajuda) [[ $pedaco == *\?* ]] ;; calendario) [[ $pedaco == *▦* ]] ;; mais) [[ $pedaco == *⋯* ]] ;;
      sub) [[ $pedaco == *↳* ]] ;; editar) [[ $pedaco == *✎* ]] ;; prazo) [[ $pedaco == *◷* ]] ;; ia) [[ $pedaco == *✦* ]] ;;
      filtro:*) [[ -n ${pedaco// /} ]] ;; *) true ;;
    esac || fail "mapa do cabeçalho desalinhado em $larg colunas: $ac -> '$pedaco'"
    ((c2 <= larg - 3)) || fail "botão $ac passa da largura ($c2 > $((larg - 3)))"
  done <"$T/rt/tt-tarefas-mapa-$(id -u)"
  grep -qE '(·|•)\s*$' <<<"$cab" && fail "linha do cabeçalho termina com separador solto ($larg colunas)"
done
# Duas linhas fixas no painel (72 colunas): abas numa linha, ações na outra com ▦ ? ⋯ Mais encostados à
# direita; o que saiu do topo (feita, descrição, prioridade, repetir, mover, apagar) segue no ⋯ Mais.
cab=$(FZF_COLUMNS=72 run --tarefas-cabecalho | sem_cor)
[[ $(wc -l <<<"$cab") == 3 ]] || fail "cabeçalho a 72 colunas deveria ter 2 linhas + régua: $cab"
mp="$T/rt/tt-tarefas-mapa-$(id -u)"
[[ $(awk '$4 ~ /^filtro:/ {print $1}' "$mp" | sort -u) == 1 ]] || fail "as abas deveriam caber na 1ª linha"
[[ $(awk '$4=="mais"{print $1, $3}' "$mp") == "2 69" ]] || fail "⋯ Mais deveria fechar a 2ª linha, encostado à direita: $(awk '$4=="mais"' "$mp")"
for ac in nova sub editar prazo ia calendario ajuda; do awk -v a=$ac '$4==a{f=1} END{exit !f}' "$mp" || fail "cabeçalho sem o botão $ac"; done
for ac in feita prio rep apagar cima baixo desc; do awk -v a=$ac '$4==a{f=1} END{exit f}' "$mp" || fail "botão $ac deveria ter ido para o ⋯ Mais"; done
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
