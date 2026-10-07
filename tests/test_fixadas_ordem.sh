#!/usr/bin/env bash
# Reordenação e overflow da faixa de fixadas, com um tmux de verdade (servidor isolado):
#  - mover_fixada aceita índice de DESTINO absoluto (passo, início e fim) e desloca os demais;
#  - a faixa mostra uma janela de até TT_FIX_VISIVEIS itens, com setas ‹ › quando há itens ocultos;
#  - as setas (fixprev/fixnext) movem a janela por página e saturam nas pontas;
#  - a sessão em uso, se fixada, é sempre trazida para dentro da janela visível.
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

# --- Overflow: janela deslizante com setas ------------------------------------------------------
# Renderiza a faixa com um teto baixo e confere que só a janela aparece e que as setas surgem.
render() { TT_FIX_VISIVEIS=4 "$TT" --barras >/dev/null 2>&1; tmux show -gqv @barra_fixadas; }

tmux set -g @fix_off 0
faixa=$(render)
grep -q 'fx' <<<"$faixa" || falha 'faixa vazia inesperada'
[[ $(grep -o 'range=user|fx[0-9a-f]' <<<"$faixa" | wc -l) == 4 ]] || falha "janela deveria mostrar 4 itens (mostra $(grep -o 'range=user|fx[0-9a-f]' <<<"$faixa" | wc -l))"
grep -q 'range=user|fixnext' <<<"$faixa" || falha 'seta › ausente com itens à frente'
grep -q 'range=user|fixprev' <<<"$faixa" && falha 'seta ‹ não deveria aparecer no início'
passou 'overflow: janela limita itens visíveis e mostra › quando há mais à frente'

# Avança uma página: offset vai a 4, aparecem s5..s8 e a seta ‹.
TT_FIX_VISIVEIS=4 tt --fixada-scroll next
[[ $(tmux show -gqv @fix_off) == 4 ]] || falha "scroll next deveria levar offset a 4 (está $(tmux show -gqv @fix_off))"
faixa=$(render)
grep -q 'range=user|fixprev' <<<"$faixa" || falha 'seta ‹ ausente no meio'
grep -q 'range=user|fixnext' <<<"$faixa" || falha 'seta › ausente no meio (ainda há s9,s10)'

# Mais uma página: 10 itens, vis 4 -> offset máximo é 6; não passa disso.
TT_FIX_VISIVEIS=4 tt --fixada-scroll next
[[ $(tmux show -gqv @fix_off) == 6 ]] || falha "offset máximo deveria ser 6 (está $(tmux show -gqv @fix_off))"
TT_FIX_VISIVEIS=4 tt --fixada-scroll next
[[ $(tmux show -gqv @fix_off) == 6 ]] || falha 'scroll além do fim não pode ultrapassar o offset máximo'
faixa=$(render)
grep -q 'range=user|fixnext' <<<"$faixa" && falha 'seta › não deveria aparecer no fim'
grep -q 'range=user|fixprev' <<<"$faixa" || falha 'seta ‹ ausente no fim'
passou 'overflow: setas movem a janela por página e saturam nas pontas'

# Volta ao início pelas setas.
TT_FIX_VISIVEIS=4 tt --fixada-scroll prev
TT_FIX_VISIVEIS=4 tt --fixada-scroll prev
[[ $(tmux show -gqv @fix_off) == 0 ]] || falha "voltar deveria chegar a offset 0 (está $(tmux show -gqv @fix_off))"

# A sessão em uso, se fixada e fora da janela, é trazida para dentro ao redesenhar. Precisa de um
# cliente anexado de verdade (sem cliente a barra não é reposicionada). Anexa em s10 (o 10º item).
anexar cli 120 30 s10
sleep 0.5
tmux set -g @fix_off 0
TT_FIX_VISIVEIS=4 "$TT" --barras >/dev/null 2>&1
# s10 é o 10º; com vis=4 a janela deve ter deslizado para mostrá-lo (offset>0 -> seta ‹).
[[ $(tmux show -gqv @fix_off) -gt 0 ]] || falha "sessão em uso fora da janela não trouxe o offset (está $(tmux show -gqv @fix_off))"
tmux show -gqv @barra_fixadas | grep -q 's10' || falha 'sessão em uso (s10) não ficou visível na janela'
passou 'overflow: a sessão em uso é sempre trazida para a janela visível'

echo 'ok: reordenar (absoluto) e overflow (janela + setas) da faixa de fixadas'
