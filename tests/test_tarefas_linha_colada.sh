#!/usr/bin/env bash
# Linha colada no arquivo de tarefas (incidente de 21/10/2026): o arquivo local terminou truncado e sem
# quebra de linha ("70b808f6d574<TAB>arqui"), o `cat local remoto | tarefas_merge` grudou nele a primeira
# linha do outro arquivo e o texto da tarefa caiu na coluna de meta. A cada merge o `unir` acrescentava o
# texto de novo (não é chave=valor) e a linha passou de 9 MB em todas as máquinas, travando o merge.
# Cobre: linha malformada não entra no merge; meta só leva pares chave=valor (e limpa o lixo que já
# tinha); arquivo sem quebra no fim não gruda na linha seguinte, no merge e nos verbos que gravam.
source "$(dirname "$0")/lib.sh"; isolar
eval "$(sed -n '/^tarefas_merge() {/,/^}/p' "$TT")"
A="$HOME/a.tsv"; B="$HOME/b.tsv"
boa=$'70b808f6d574\tarquivada\t1791570084\t1791995787\tendpoint de hora\tdesc=QUJD'
outra=$'1f23ab6ab2d5\taberta\t1792581674\t1792603729\tConfigurar o tt via OAuth\tdesc=WFla'
colada=$'70b808f6d574\tarqui1f23ab6ab2d5\taberta\t1792581674\t1792603729\tConfigurar o tt via OAuth|Configurar o tt via OAuth'

# 1) a linha colada (estado inválido) não vence a versão boa nem aparece no resultado
printf '%s\n%s\n' "$colada" "$outra" >"$A"; printf '%s\n' "$boa" >"$B"
r=$(tarefas_merge "$A" "$B")
[[ $(grep -c '^70b808f6d574' <<<"$r") == 1 ]] || falhou "70b808f6d574 deveria aparecer uma vez: $r"
grep -qF "$boa" <<<"$r" || falhou "a versão boa deveria vencer a colada: $r"
grep -q 'arqui1f23' <<<"$r" && falhou "a linha colada passou pelo merge: $r"
printf '%s\n' "$colada" >"$A"
[[ -z $(tarefas_merge "$A") ]] || falhou "linha com estado inválido deveria sumir: $(tarefas_merge "$A")"
printf 'zzzz\taberta\t1\t2\tid inválido\nabcdef123456\taberta\tx\t2\tcriada não numérica\n' >"$A"
[[ -z $(tarefas_merge "$A") ]] || falhou "id ou data inválidos deveriam sumir: $(tarefas_merge "$A")"
passou 'linha malformada (estado, id ou data inválidos) não entra no merge'

# 2) no empate, o meta só junta pares chave=valor; o lixo que já estava no meta some e não cresce
l1=$'abcdef123456\taberta\t1\t100\ttexto\tdesc=QQ|Configurar o tt via OAuth|pai=111111111111'
l2=$'abcdef123456\taberta\t1\t100\ttexto\tord=2|outro lixo sem igual|=semchave'
printf '%s\n' "$l1" >"$A"; printf '%s\n' "$l2" >"$B"
r=$(tarefas_merge "$A" "$B"); m=$(cut -f6 <<<"$r")
[[ $(tr '|' '\n' <<<"$m" | sort | paste -sd'|' -) == 'desc=QQ|ord=2|pai=111111111111' ]] || falhou "meta esperado desc, ord e pai, veio: $m"
[[ $(tarefas_merge "$B" "$A") == "$r" ]] || falhou "merge depende da ordem: $r // $(tarefas_merge "$B" "$A")"
printf '%s\n' "$r" >"$A"
for i in 1 2 3; do r=$(tarefas_merge "$A" "$B"); printf '%s\n' "$r" >"$A"; done
[[ $(cut -f6 <<<"$r") == "$m" ]] || falhou "meta cresceu com merges repetidos: $(cut -f6 <<<"$r")"
r=$(printf '%s\n' "$l1" | tarefas_merge /dev/stdin)
[[ $(cut -f6 <<<"$r") == 'desc=QQ|pai=111111111111' ]] || falhou "lixo no meta de linha única deveria sumir: $r"
passou 'meta só leva chave=valor; lixo antigo é limpo e merges repetidos não fazem a linha crescer'

# 3) arquivo sem quebra de linha no fim não gruda na primeira linha do outro
printf '%s' "$boa" >"$A"; printf '%s\n' "$outra" >"$B"
r=$(tarefas_merge "$A" "$B")
[[ $(grep -c . <<<"$r") == 2 ]] || falhou "deveriam ser 2 linhas: $r"
grep -qF "$boa" <<<"$r" && grep -qF "$outra" <<<"$r" || falhou "linhas grudaram no merge: $r"
passou 'arquivo sem quebra no fim não gruda no merge de dois arquivos'

# 4) nenhum ponto do tt concatena o arquivo de tarefas com cat antes do merge
if grep -nE 'cat "\$CONF_TAREFAS"[^|]*(;|"\$dir)' "$TT" | grep -v '^\s*#'; then
  falhou 'concatenação com cat do arquivo de tarefas (use tarefas_merge ARQ1 ARQ2 ou tarefas_linhas)'
fi
grep -q '"\$CONF_TAREFAS.tmp"' "$TT" && falhou 'temporário de nome fixo $CONF_TAREFAS.tmp (use mktemp)'
passou 'sem cat do arquivo de tarefas antes do merge e sem temporário de nome fixo'

# 5) os verbos que gravam também não grudam: tarefa nova num arquivo que terminou sem quebra
C="$HOME/.config/tt"; mkdir -p "$C"; printf 'nome=A\ntarefas_sync=off\n' >"$C/config"
printf '%s' "$boa" >"$C/tarefas"
"$TT" --tarefa-add "nova depois do arquivo truncado" >/dev/null 2>&1 || falhou 'tarefa-add falhou'
grep -qF "$boa" "$C/tarefas" || falhou "a linha que estava sem quebra grudou: $(cat "$C/tarefas")"
grep -q $'\taberta\t.*\tnova depois do arquivo truncado' "$C/tarefas" || falhou "a nova não entrou: $(cat "$C/tarefas")"
passou 'tarefa-add num arquivo sem quebra no fim mantém as linhas separadas'
