#!/usr/bin/env bash
# Regressao (projeto tt): um cliente que e ponte vinda de outra maquina (TT_PONTE setado) mas
# fisicamente nesta maquina, ao ir para uma sessao DESTA maquina (dest=.), nao pode refletir o
# pedido pela ponte (ssh --ir-ponte). O TT_PONTE fica congelado no rotulo da sessao em que a ponte
# nasceu e nao acompanha as trocas; refletir travava a troca. Deve trocar local.
#
# Exercita a GUARDA de decisao de ir_para (a condicao do reflexo), isolada das dependencias de tmux
# ao vivo: confere que a condicao-fonte exige dest != . e prova a booleana nos dois casos.
source "$(dirname "$0")/lib.sh"; isolar

# a guarda é o "if" de ir_para logo antes do pedido à origem (pedir_na_origem … --ir-ponte)
corpo=$(sed -n '/^ir_para() {/,/^}/p' "$TT")
grep -q 'pedir_na_origem "$om" --ir-ponte' <<<"$corpo" || falhou "nao achei o pedido --ir-ponte em ir_para"
linha=$(grep -B8 'pedir_na_origem "$om" --ir-ponte' <<<"$corpo" | grep 'if \[\[' | tail -1)
[[ -n $linha ]] || falhou "nao achei a condicao de reflexo de ponte em ir_para"

case $linha in
  *'$dest != .'*) : ;;
  *) falhou "a condicao de reflexo de ponte NAO exige 'dest != .': $linha" ;;
esac

origem="s23|empresa-origem"; op=${origem#*|}
reflete() { local dest=$1; [[ $dest != . && -n $origem && -n $op ]]; }
reflete . && falhou "dest=. ainda refletiria pela ponte (alvo local)"
reflete outra || falhou "dest=outra-maquina deveria refletir pela ponte"
passou "ponte local: dest=. troca local (sem reflexo), dest!=. reflete pela ponte"
