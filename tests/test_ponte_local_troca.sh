#!/usr/bin/env bash
# Regressao (projeto tt): um cliente que e ponte vinda de outra maquina (TT_PONTE setado) e vai para
# uma sessao DESTA maquina (dest=.). Antes (0823138) o reflexo pela ponte travava a troca porque o
# pedido levava o rotulo congelado do TT_PONTE (o da sessao em que a ponte nasceu). Desde 625326f o
# pedido vai SEMPRE a origem, para o cache de pontes de la (tt-pre-*) nao ficar com a identidade
# antiga; com dest=. ele leva o nome desta maquina ($MAQUINA), nunca o rotulo congelado.
#
# Exercita a escolha do alvo em ir_para, isolada das dependencias de tmux ao vivo: confere a fonte e
# prova a escolha nos dois casos.
source "$(dirname "$0")/lib.sh"; isolar

# o pedido à origem (pedir_na_origem … --ir-ponte) e a escolha do alvo logo antes dele
corpo=$(sed -n '/^ir_para() {/,/^}/p' "$TT")
grep -q 'pedir_na_origem "$om" --ir-ponte "$op" "$r"' <<<"$corpo" || falhou "nao achei o pedido --ir-ponte com o alvo \$r em ir_para"
linha=$(grep -B3 'pedir_na_origem "$om" --ir-ponte' <<<"$corpo" | grep 'r=' | tail -1)
[[ -n $linha ]] || falhou "nao achei a escolha do alvo (r=) antes do pedido --ir-ponte"
case $linha in
  *'$dest == .'*'r=$MAQUINA'*) : ;;
  *) falhou "com dest=. o alvo pedido a origem deveria ser \$MAQUINA: $linha" ;;
esac
grep -q 'TT_PONTE' <<<"$linha" && falhou "o alvo nao pode vir do TT_PONTE (rotulo congelado): $linha"

MAQUINA=este-mac
rotulo() { echo "rotulo-$1"; }
alvo() { local dest=$1 r; eval "${linha#"${linha%%if *}"}"; echo "$r"; }
[[ $(alvo .) == este-mac ]] || falhou "dest=. deveria pedir a origem a sessao desta maquina, nao $(alvo .)"
[[ $(alvo outra) == rotulo-outra ]] || falhou "dest=outra deveria pedir o rotulo da outra maquina, nao $(alvo outra)"
passou "ponte: dest=. pede a origem a sessao desta maquina (\$MAQUINA, nao o TT_PONTE); dest!=. pede o rotulo"
