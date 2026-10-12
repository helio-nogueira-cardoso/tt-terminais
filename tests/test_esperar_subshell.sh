#!/usr/bin/env bash
# No bash 5.3, um "wait" sem pids dentro de um subshell ($(...) ou < <(...)) cujo shell de cima tem um
# trabalho em 2º plano ainda vivo gira a 100% de CPU para sempre. O vigia ficou horas assim (12/10), preso
# no par_fim de sessoes_vazias_de. Aqui:
#  1) par/par_fim e esperar terminam nesse cenário (em qualquer bash) e esperam os trabalhos de verdade;
#  2) nenhum "wait" sem pids sobrou no tt nem no ia-login.
source "$(dirname "$0")/lib.sh"; isolar
set +o pipefail

src=$(sed -n '/^PAR_PIDS=()/,/^esperar() {/p' "$TT")
grep -q '^par_fim() {' <<<"$src" && grep -q '^esperar() {' <<<"$src" || falhou 'par/par_fim/esperar não encontrados no tt'
cat >"$T/cena.sh" <<EOF
$src
( sleep 4 ) >/dev/null 2>&1 &                                  # trabalho do shell de cima ainda vivo (como o do vigia)
conta() { sleep 0.2; echo x >"\$1"; }
g() { par conta "$T/a"; par conta "$T/b"; par_fim; local -a pids=(); ( sleep 0.2; echo y >"$T/c" ) & pids+=(\$!); esperar "\${pids[@]}"; echo fim; }
r=\$(while read -r l; do echo "\$l"; done < <(g)); echo "\$r"
EOF
ini=$(date +%s%N)
saida=$(timeout 3 bash "$T/cena.sh" 2>/dev/null); rc=$?
ms=$(( ($(date +%s%N) - ini) / 1000000 ))
((rc == 0)) || falhou "par_fim/esperar travaram num subshell com trabalho do shell de cima vivo (rc=$rc, ${ms} ms)"
[[ $saida == fim && -s $T/a && -s $T/b && -s $T/c ]] || falhou "par_fim/esperar voltaram antes dos trabalhos terminarem (saída '$saida')"
passou "par_fim e esperar terminam num subshell com trabalho do shell de cima vivo (${ms} ms)"

sobra=$(grep -n -E '(^|[;&|{(]|then|do|else)[[:space:]]*wait[[:space:]]*($|[;)}&|]|2>)' "$RAIZ/tt" "$RAIZ/ia-login" | grep -v -E '"wait"' || true)
[[ -z $sobra ]] || falhou "\"wait\" sem pids no código (use esperar com os pids):
$sobra"
passou 'nenhum "wait" sem pids no tt nem no ia-login'
