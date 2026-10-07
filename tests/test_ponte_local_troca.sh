#!/usr/bin/env bash
# Regressao (projeto tt): um cliente que e ponte vinda de outra maquina (TT_PONTE setado) mas
# fisicamente nesta maquina, ao ir para uma sessao DESTA maquina (dest=.), nao pode refletir o
# pedido pela ponte (ssh --ir-ponte). O TT_PONTE fica congelado no rotulo da sessao em que a ponte
# nasceu e nao acompanha as trocas; refletir travava a troca. Deve trocar local.
#
# Exercita a GUARDA de decisao de ir_para (a condicao do reflexo), isolada das dependencias de tmux
# ao vivo: confere que a condicao-fonte exige dest != . e prova a booleana nos dois casos.
source "$(dirname "$0")/lib.sh"; isolar

cond=$(grep -n 'ssh "${SSH_OPC\[@\]}".*--ir-ponte' "$TT" | head -1)
[[ -n $cond ]] || falhou "nao achei a condicao de reflexo de ponte em ir_para"
linha=${cond#*:}

case $linha in
  *'$dest != .'*) : ;;
  *) falhou "a condicao de reflexo de ponte NAO exige 'dest != .': $linha" ;;
esac

origem="s23|empresa-origem"; op=${origem#*|}
reflete() { local dest=$1; [[ $dest != . && -n $origem && -n $op ]]; }
reflete . && falhou "dest=. ainda refletiria pela ponte (alvo local)"
reflete outra || falhou "dest=outra-maquina deveria refletir pela ponte"
passou "ponte local: dest=. troca local (sem reflexo), dest!=. reflete pela ponte"
