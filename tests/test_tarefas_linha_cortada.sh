#!/usr/bin/env bash
# Linha cortada vinda de outra máquina (16 e 19/11/2026): o `puxar_tarefas` emendava a saída de cada
# máquina na da seguinte; a máquina lenta, cortada pelo timeout do cat_remoto, deixava a última linha pela
# metade e ela grudava na 1ª linha da próxima. Resultado: tarefas novas com um pedaço de outro código na
# frente (ids de 17 a 74 hex; as cópias do HB-1104 ganhavam o mesmo prefixo a cada volta) e descrições
# cortadas. O mesmo valia para o envio por ssh (--receber-tarefas) e para a volta do git (cat de dois arquivos).
# Cobre: tarefas_completas; o merge só aceita código de 12 hex; --tarefas-puxar com uma máquina cortada;
# --receber-tarefas com a versão mais nova cortada no meio da descrição; nenhum cat de dois arquivos de tarefas.
source "$(dirname "$0")/lib.sh"; isolar
eval "$(sed -n '/^tarefas_merge() {/,/^}/p;/^tarefas_completas() {/,/^}/p' "$TT")"
A="$HOME/a.tsv"; B="$HOME/b.tsv"
hb=$'c9795b9a26b7\taberta\t1792000000\t1795000000\tHB-1104: reset mensal do Ofertado\tdesc=SEItMTEwNA=='
outra=$'bf7d9e48b80a\taberta\t1792000000\t1794000000\tRevisar o 1012\tdesc=UmV2aXNhcg=='

# 1) tarefas_completas: só linhas com quebra no fim; a cortada some; arquivo inteiro passa igual
printf '%s\n%s' "$outra" "${hb:0:11}" >"$A"
r=$(tarefas_completas "$A")
[[ $r == "$outra" ]] || falhou "a linha cortada deveria sumir: $(printf '%q' "$r")"
printf '%s\n%s\n' "$outra" "$hb" >"$B"
[[ $(tarefas_completas "$B") == "$(cat "$B")" ]] || falhou "arquivo inteiro deveria passar igual"
: >"$A"; [[ -z $(tarefas_completas "$A" "$HOME/nao-existe") ]] || falhou "vazio ou ausente deveria dar nada"
printf '%s' "${hb:0:11}" >"$A"
r=$(tarefas_completas "$A" "$B")
grep -q '^bf7d9e48b80c9795' <<<"$r" && falhou "pedaço grudou na linha do arquivo seguinte: $r"
[[ $r == "$(cat "$B")" ]] || falhou "o arquivo seguinte deveria vir inteiro: $r"
passou 'tarefas_completas descarta a última linha sem quebra e não deixa ela grudar na próxima fonte'

# 2) o merge só aceita código de exatamente 12 hex (as cópias coladas tinham 17 a 74)
printf '%s\n%s\n' "bf7d9e48b80${hb}" "bf7d9e48b80bf7d9e48b80${hb}" >"$A"; printf '%s\n' "$hb" >"$B"
r=$(tarefas_merge "$A" "$B")
[[ $r == "$hb" ]] || falhou "só a tarefa de 12 hex deveria sobrar: $r"
passou 'merge descarta código colado (mais de 12 hex)'

# 3) --tarefas-puxar: a 1ª máquina cortada no meio de uma linha, a 2ª inteira
mkdir -p "$T/bin"; printf '%s\n%s' "$outra" "${outra:0:11}" >"$T/corta.tsv"; printf '%s\n%s\n' "$hb" "$outra" >"$T/inteira.tsv"
cat >"$T/bin/ssh" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  case \$a in
    *@corta-host) cat "$T/corta.tsv"; exit 0 ;;
    *@inteira-host) cat "$T/inteira.tsv"; exit 0 ;;
  esac
done
exit 255
EOF
printf '#!/bin/sh\nexit 1\n' >"$T/bin/tailscale"; chmod +x "$T/bin/ssh" "$T/bin/tailscale"
C="$XDG_CONFIG_HOME/tt"; mkdir -p "$C"
printf 'nome=local\ntarefas_sync=p2p\n' >"$C/config"
printf 'corta-host helio corta\ninteira-host helio inteira\n' >"$C/maquinas"
: >"$C/tarefas"
PATH="$T/bin:$TT_PATH_BASE" "$TT" --tarefas-puxar >/dev/null 2>&1
awk -F'\t' 'length($1) != 12 { print "id ruim: " $1 }' "$C/tarefas" | grep . && falhou "entrou código colado: $(cut -f1 "$C/tarefas" | paste -sd' ')"
grep -qF "$hb" "$C/tarefas" || falhou "a 1ª linha da máquina inteira deveria entrar intacta: $(cat "$C/tarefas")"
grep -qF "$outra" "$C/tarefas" || falhou "a linha completa da máquina cortada deveria entrar: $(cat "$C/tarefas")"
[[ $(grep -c . "$C/tarefas") == 2 ]] || falhou "deveriam ser 2 tarefas: $(cat "$C/tarefas")"
passou '--tarefas-puxar com uma máquina cortada pelo timeout não cola código nem perde a 1ª linha da seguinte'

# 4) --receber-tarefas: a versão mais nova chega cortada no meio da descrição e não vence a inteira
velha=$'abcdef012345\taberta\t1792000000\t1793000000\tNeura: recuperar o SSH\tdesc=SGFuZG9mZiBwYXJhIEjDqWxpbw=='
nova=$'abcdef012345\taberta\t1792000000\t1796000000\tNeura: recuperar o SSH\tdesc=SGFuZG9mZiBwYXJhIEjDqWxpbyAoaGVsaW9uYzE5OTlAZ21haWwuY29tKQ=='
printf '%s\n' "$velha" >"$C/tarefas"
printf '%s' "${nova:0:90}" | PATH="$T/bin:$TT_PATH_BASE" "$TT" --receber-tarefas >/dev/null 2>&1
[[ $(cat "$C/tarefas") == "$velha" ]] || falhou "a versão cortada não deveria entrar: $(cat "$C/tarefas")"
printf '%s\n' "$nova" | PATH="$T/bin:$TT_PATH_BASE" "$TT" --receber-tarefas >/dev/null 2>&1
[[ $(cat "$C/tarefas") == "$nova" ]] || falhou "a versão nova inteira deveria entrar: $(cat "$C/tarefas")"
passou '--receber-tarefas ignora a última linha cortada e aceita a versão inteira'

# 5) nenhum ponto do tt concatena dois arquivos de tarefas com cat nem emenda saídas de máquinas sem cortar
if grep -nE 'cat "\$dir/tarefas"|nas_maquinas cat_remoto [^|]*tarefas' "$TT" | grep -v '^\s*[0-9]*:\s*#'; then
  falhou 'cat de dois arquivos de tarefas, ou saídas de máquinas emendadas sem tarefas_completas'
fi
grep -q 'HEX.match(p\[0\])' "$RAIZ/tarefas-merge.py" 2>/dev/null && falhou 'tarefas-merge.py lê linha com código de 6+ hex (use ID, 12 hex)'
passou 'sem cat de dois arquivos de tarefas e leitor do merge com código de 12 hex'

