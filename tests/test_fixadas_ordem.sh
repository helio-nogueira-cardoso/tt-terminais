#!/usr/bin/env bash
# Reordenação e overflow da faixa de fixadas, com um tmux de verdade (servidor isolado):
#  - mover_fixada aceita índice de DESTINO absoluto (passo, início e fim) e desloca os demais;
#  - sem scroll: os rótulos encolhem por estágios até caberem na largura (TT_FIX_LARGURA);
#  - quando nem encolhido cabe, os excedentes viram o chip "+N ▾" (abre o popup de todas);
#  - a sessão em uso, se fixada e escondida, toma o último lugar visível;
#  - o popup reordena pelo índice ({n} do fzf): --mover-fixada-rel e --desafixar-n.
source "$(dirname "$0")/lib.sh"; isolar
tt() { "$TT" "$@"; }
lista() { cut -f1,2 "$XDG_CONFIG_HOME/tt/fixadas" | tr '\t' ':' | tr '\n' ' '; }
falha() { falhou "$1 (fixadas: $(lista))"; }

tmux -f /dev/null new -d -s s1 'sleep 600'
for n in 2 3 4 5 6 7 8 9 10; do tmux new -d -s "s$n" 'sleep 600'; done
for n in 1 2 3 4 5; do tt --fixar "s$n" >/dev/null; done
[[ $(lista) == "teste:s1 teste:s2 teste:s3 teste:s4 teste:s5 " ]] || falha 'ordem inicial'

# Mover o 1º para o fim (destino absoluto 5): os demais sobem.
tt --mover-fixada 1 5
[[ $(lista) == "teste:s2 teste:s3 teste:s4 teste:s5 teste:s1 " ]] || falha 'mover para o fim'

# Mover o último para o início (destino 1).
tt --mover-fixada 5 1
[[ $(lista) == "teste:s1 teste:s2 teste:s3 teste:s4 teste:s5 " ]] || falha 'mover para o início'

# Passo à direita (3 -> 4) e à esquerda (4 -> 3) voltam ao mesmo lugar.
tt --mover-fixada 3 4
[[ $(lista) == "teste:s1 teste:s2 teste:s4 teste:s3 teste:s5 " ]] || falha 'passo à direita'
tt --mover-fixada 4 3
[[ $(lista) == "teste:s1 teste:s2 teste:s3 teste:s4 teste:s5 " ]] || falha 'passo à esquerda'

# Destino fora da faixa é saturado, não quebra a lista.
tt --mover-fixada 2 99
[[ $(lista) == "teste:s1 teste:s3 teste:s4 teste:s5 teste:s2 " ]] || falha 'destino saturado no fim'
tt --mover-fixada 5 0
[[ $(lista) == "teste:s2 teste:s1 teste:s3 teste:s4 teste:s5 " ]] || falha 'destino saturado no início'
# volta à ordem natural para o resto do teste
: >"$XDG_CONFIG_HOME/tt/fixadas"
for n in 1 2 3 4 5 6 7 8 9 10; do tt --fixar "s$n" >/dev/null; done
[[ $(cut -f2 "$XDG_CONFIG_HOME/tt/fixadas" | tr '\n' ' ') == "s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 " ]] || falha 'refixar as 10'
passou 'reordenar: passo, início, fim e destino saturado (desloca os demais, lista íntegra)'

# --- Overflow: compressão por estágios e chip +N ------------------------------------------------
render() { "$TT" --barras >/dev/null 2>&1; tmux show -gqv @barra_fixadas; }
nitens() { grep -o 'range=user|fx[0-9a-f]' <<<"$1" | wc -l; }

# Largura folgada: todos os 10 itens aparecem, com rótulo inteiro e ✕, sem chip.
faixa=$(TT_FIX_LARGURA=300 render)
[[ $(nitens "$faixa") == 10 ]] || falha "largura folgada deveria mostrar 10 itens (mostra $(nitens "$faixa"))"
grep -q 'fxx' <<<"$faixa" || falha 'largura folgada deveria manter o ✕ dos itens'
grep -q 'fixmais' <<<"$faixa" && falha 'chip +N não deveria aparecer quando tudo cabe'
passou 'largura folgada: todos os itens, com ✕, sem chip'

# Largura apertada (mas suficiente comprimido): todos aparecem, SEM o ✕ (estágio comprimido).
faixa=$(TT_FIX_LARGURA=70 render)
[[ $(nitens "$faixa") == 10 ]] || falha "comprimido deveria mostrar os 10 (mostra $(nitens "$faixa"))"
grep -q 'fxx' <<<"$faixa" && falha 'comprimido até 8/5 não deveria ter o ✕ (desafixa pelo popup)'
grep -q 'fixmais' <<<"$faixa" && falha 'chip +N não deveria aparecer se comprimido coube'
passou 'compressão progressiva: encolhe os rótulos e tira o ✕ antes de esconder qualquer item'

# Largura mínima: nem comprimido cabe; os excedentes viram o chip "+N ▾" (sem setas ‹ ›).
faixa=$(TT_FIX_LARGURA=50 render)
n=$(nitens "$faixa")
(( n >= 1 && n < 10 )) || falha "largura mínima deveria esconder parte dos itens (mostra $n)"
grep -q 'range=user|fixmais' <<<"$faixa" || falha 'chip +N ▾ ausente com itens escondidos'
grep -qE '\+[0-9]+ ▾' <<<"$faixa" || falha 'chip não mostra a contagem +N'
oc=$(grep -oE '\+[0-9]+ ▾' <<<"$faixa" | grep -oE '[0-9]+')
[[ $((n + oc)) == 10 ]] || falha "visíveis ($n) + escondidos ($oc) deveriam somar 10"
grep -q 'fixprev\|fixnext' <<<"$faixa" && falha 'as setas de scroll não existem mais'
passou 'estouro: chip +N ▾ com a contagem certa; sem setas de scroll'

# A sessão em uso, se fixada e escondida, toma o último lugar visível (precisa de cliente anexado).
anexar cli 120 30 s10
sleep 0.5
faixa=$(TT_FIX_LARGURA=50 render)
grep -q 's10' <<<"$faixa" || falha 'sessão em uso (s10) não ficou visível no estouro'
passou 'estouro: a sessão em uso nunca some da faixa'

# --- Popup: reordenar e desafixar pelo índice ---------------------------------------------------
"$TT" --mover-fixada-rel 0 1   # s1 (índice 0) desce um
[[ $(cut -f2 "$XDG_CONFIG_HOME/tt/fixadas" | head -2 | tr '\n' ' ') == "s2 s1 " ]] || falha 'mover-fixada-rel +1 não desceu o item'
"$TT" --mover-fixada-rel 1 -1  # volta
[[ $(cut -f2 "$XDG_CONFIG_HOME/tt/fixadas" | head -2 | tr '\n' ' ') == "s1 s2 " ]] || falha 'mover-fixada-rel -1 não subiu o item'
"$TT" --mover-fixada-rel 0 -1  # topo não passa do topo
[[ $(cut -f2 "$XDG_CONFIG_HOME/tt/fixadas" | head -1) == s1 ]] || falha 'mover-fixada-rel saturou errado no topo'
"$TT" --desafixar-n 9          # desafixa o último (s10)
[[ $(grep -c . "$XDG_CONFIG_HOME/tt/fixadas") == 9 && -z $(grep -F $'\ts10' "$XDG_CONFIG_HOME/tt/fixadas") ]] || falha 'desafixar-n não tirou o s10'
lin=$("$TT" --fixadas-ui-lista); lin=$(head -1 <<<"$lin")
grep -q $'fx[0-9a-f]*\t' <<<"$lin" && grep -q '📌 s1' <<<"$lin" || falha "lista do popup sem chave+rótulo: $lin"
[[ $("$TT" --fixadas-ui-lista | wc -l) == 9 ]] || falha 'lista do popup não reflete as 9 restantes'
passou 'popup: reordena e desafixa pelo índice; lista com chave estável e rótulo'

echo 'ok: reordenar (absoluto e relativo), compressão por largura e chip +N da faixa de fixadas'
