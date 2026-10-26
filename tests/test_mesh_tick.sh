#!/usr/bin/env bash
# Tick do mesh: qualquer intervalo de 1 minuto em diante, no agendador da máquina (systemd, cron ou launchd), lido e
# gravado de volta sem erro, e a tela do tick que mostra o resultado de cada mudança. Isola HOME, e o systemctl e o
# crontab são falsos (o de verdade mexeria no timer e no cron do usuário que roda a suíte).
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin" "$HOME/.config/systemd/user"
CHAMADAS=$T/systemctl.chamadas
cat >"$T/bin/systemctl" <<EOF
#!/bin/sh
echo "\$@" >>"$CHAMADAS"
[ -n "\${SYSTEMCTL_FALHA:-}" ] && exit 1
exit 0
EOF
CRON=$T/crontab.arquivo
cat >"$T/bin/crontab" <<EOF
#!/bin/sh
case "\$1" in
  -l) [ -f "$CRON" ] && cat "$CRON" || exit 1 ;;
  -) cat >"$CRON.novo" && mv "$CRON.novo" "$CRON" ;;  # como o de verdade: lê tudo e só então troca (o -l da esquerda do pipe ainda lê)
esac
EOF
chmod +x "$T/bin/systemctl" "$T/bin/crontab"
export PATH="$T/bin:$PATH"
ARQ=$HOME/.config/systemd/user/tt-chief.timer
novo_timer() { printf '[Unit]\nDescription=tt-mesh chefe (x) a cada 10 min (y)\n[Timer]\nOnBootSec=3min\nOnUnitActiveSec=%s\nPersistent=true\n' "${1:-10min}" >"$ARQ"; }

# --- systemd: não há restrição de valor ---------------------------------------------------------------------------
novo_timer
for n in 1 3 8 20 123 1440; do
  "$TT" --mesh-tick "$n" >/dev/null 2>&1 || falhou "o verbo deveria aceitar $n minutos"
  grep -q "^OnUnitActiveSec=${n}min\$" "$ARQ" || falhou "o timer deveria passar a $n min: $(grep OnUnitActiveSec "$ARQ")"
  "$TT" --mesh-tick ver 2>/dev/null | grep -qx "systemd: a cada $n min" || falhou "o ver deveria mostrar $n: $("$TT" --mesh-tick ver 2>&1)"
done
grep -q '^Description=.*a cada 1440 min' "$ARQ" || falhou 'a descrição do timer deveria acompanhar o intervalo'
grep -q 'daemon-reload' "$CHAMADAS" && grep -q 'restart tt-chief.timer' "$CHAMADAS" || falhou 'deveria recarregar e reiniciar o timer'
passou 'tick do mesh: 1, 3, 8, 20, 123 e 1440 min entram no timer, aparecem no ver e o systemd é recarregado'

"$TT" --mesh-tick 2h >/dev/null 2>&1; grep -q '^OnUnitActiveSec=120min$' "$ARQ" || falhou '2h deveria virar 120 min'
"$TT" --mesh-tick 1h30 >/dev/null 2>&1; grep -q '^OnUnitActiveSec=90min$' "$ARQ" || falhou '1h30 deveria virar 90 min'
"$TT" --mesh-tick '45 minutos' >/dev/null 2>&1; grep -q '^OnUnitActiveSec=45min$' "$ARQ" || falhou '"45 minutos" deveria virar 45 min'
passou 'tick do mesh: aceita 2h, 1h30 e "45 minutos"'

novo_timer 20min
for ruim in 0 -3 abc 8x '' 99999999 1.5; do
  if "$TT" --mesh-tick "$ruim" >/dev/null 2>&1 && [[ -n $ruim ]]; then falhou "o valor '$ruim' deveria ser recusado"; fi
done
grep -q '^OnUnitActiveSec=20min$' "$ARQ" || falhou 'um valor inválido não pode mexer no timer'
passou 'tick do mesh: 0, negativo, texto e fração são recusados sem mexer no timer'

novo_timer '1h 30min'; "$TT" --mesh-tick ver 2>/dev/null | grep -qx 'systemd: a cada 90 min' || falhou 'duração "1h 30min" do systemd deveria virar 90 min'
novo_timer '1h'; "$TT" --mesh-tick ver 2>/dev/null | grep -qx 'systemd: a cada 60 min' || falhou 'duração "1h" deveria virar 60 min'
novo_timer '90s'; "$TT" --mesh-tick ver 2>/dev/null | grep -qx 'systemd: a cada 90 s' || falhou 'duração "90s" deveria aparecer em segundos'
passou 'tick do mesh: o ver entende as durações do systemd (1h, 1h 30min, 90s)'

# Timer sem OnUnitActiveSec: a linha entra no [Timer] em vez de a mudança sumir calada.
printf '[Timer]\nOnCalendar=hourly\n' >"$ARQ"
"$TT" --mesh-tick 7 >/dev/null 2>&1; grep -q '^OnUnitActiveSec=7min$' "$ARQ" || falhou 'sem OnUnitActiveSec, a linha deveria ser criada'
passou 'tick do mesh: timer sem OnUnitActiveSec ganha a linha'

# systemctl que falha: não diz que deu certo.
novo_timer
out=$(SYSTEMCTL_FALHA=1 "$TT" --mesh-tick 9 2>&1) && falhou 'systemctl falhando deveria dar erro'
grep -q 'não recarregou' <<<"$out" || falhou "o erro deveria dizer que o systemd não recarregou: $out"
passou 'tick do mesh: se o systemd não recarrega, o erro aparece (não finge que mudou)'

# O ssh não traz a sessão do usuário: sem XDG_RUNTIME_DIR o systemctl --user falhava calado.
novo_timer; : >"$CHAMADAS"
cat >"$T/bin/systemctl" <<EOF
#!/bin/sh
echo "XDG=\${XDG_RUNTIME_DIR:-} \$@" >>"$CHAMADAS"
EOF
(unset XDG_RUNTIME_DIR; "$TT" --mesh-tick 12 >/dev/null 2>&1)
grep -q "^XDG=/run/user/$UID " "$CHAMADAS" || falhou "sem XDG_RUNTIME_DIR o tt deveria usar /run/user/$UID: $(cat "$CHAMADAS")"
passou 'tick do mesh: sem XDG_RUNTIME_DIR (ssh) usa /run/user/UID para falar com o systemd'
rm -f "$ARQ"

# --- cron (Termux, Linux sem systemd): o ver não quebra e qualquer N vale ----------------------------------------------
CMD='/data/data/com.termux/files/home/bin/tt-chief-s23.sh >> /data/data/com.termux/files/home/.cache/tt-chief-s23-cron.log 2>&1'
printf '%s\n%s\n' '0 3 * * * /outro/job.sh' "*/5 * * * * $CMD" >"$CRON"
"$TT" --mesh-tick ver 2>&1 | grep -qx 'cron: a cada 5 min' || falhou "o ver do cron deveria mostrar 5 (era 'ver: unbound variable'): $("$TT" --mesh-tick ver 2>&1)"
"$TT" --mesh-tick 30 >/dev/null 2>&1; grep -qxF "*/30 * * * * $CMD" "$CRON" || falhou "30 deveria usar a agenda nativa */30: $(cat "$CRON")"
grep -qxF '0 3 * * * /outro/job.sh' "$CRON" || falhou 'as outras linhas do cron não podem sumir'
"$TT" --mesh-tick 120 >/dev/null 2>&1; grep -qxF "0 */2 * * * $CMD" "$CRON" || falhou "120 deveria usar 0 */2: $(cat "$CRON")"
"$TT" --mesh-tick ver 2>&1 | grep -qx 'cron: a cada 120 min' || falhou 'o ver deveria devolver 120'
"$TT" --mesh-tick 60 >/dev/null 2>&1; grep -qxF "0 * * * * $CMD" "$CRON" || falhou '60 deveria ser a cada hora'
"$TT" --mesh-tick ver 2>&1 | grep -qx 'cron: a cada 60 min' || falhou 'a cada hora deveria aparecer como 60 min (era 0)'
"$TT" --mesh-tick 1 >/dev/null 2>&1; grep -qxF "* * * * * $CMD" "$CRON" || falhou '1 deveria rodar a cada minuto'
passou 'tick do mesh: cron usa a agenda nativa quando N divide a hora/o dia e o ver devolve o mesmo N'

for n in 8 45 123; do
  "$TT" --mesh-tick "$n" >/dev/null 2>&1
  linha=$(grep 'tt-chief' "$CRON")
  [[ $linha == "* * * * * [ \$(( \$(date +\\%s) / 60 \\% $n )) -eq 0 ] && ( $CMD )" ]] || falhou "$n deveria rodar a cada minuto só nos múltiplos de $n: $linha"
  "$TT" --mesh-tick ver 2>&1 | grep -qx "cron: a cada $n min" || falhou "o ver deveria devolver $n: $("$TT" --mesh-tick ver 2>&1)"
done
# A condição, tirado o escape do cron, é sh válido e dispara exatamente nos múltiplos (data falsa: 246 min desde 1970 = 123 × 2).
cond='[ $(( $(date +%s) / 60 % 123 )) -eq 0 ]'
sh -c "date() { echo 14760; }; $cond" || falhou 'a condição deveria disparar quando os minutos são múltiplo de 123'
sh -c "date() { echo 14820; }; $cond" && falhou 'a condição não deveria disparar fora do múltiplo'
"$TT" --mesh-tick 15 >/dev/null 2>&1; grep -qxF "*/15 * * * * $CMD" "$CRON" || falhou "voltar a um divisor deveria restaurar o comando sem a condição: $(grep chief "$CRON")"
passou 'tick do mesh: 8, 45 e 123 min no cron (condição por minuto), reversível sem perder o comando'

# --- launchd (Mac): o ver devolve minutos, não segundos --------------------------------------------------------------
rm -f "$CRON"
mkdir -p "$HOME/Library/LaunchAgents"
PL=$HOME/Library/LaunchAgents/com.helio.tt-chief.plist
printf '<plist><dict>\n<key>Label</key>\n<string>x</string>\n<key>StartInterval</key>\n<integer>600</integer>\n</dict></plist>\n' >"$PL"
"$TT" --mesh-tick ver 2>&1 | grep -qx 'launchd: a cada 10 min' || falhou "o ver do launchd deveria mostrar 10 min (eram 600 s): $("$TT" --mesh-tick ver 2>&1)"
"$TT" --mesh-tick 123 >/dev/null 2>&1; grep -q '<integer>7380</integer>' "$PL" || falhou "123 min deveriam virar 7380 s: $(cat "$PL")"
"$TT" --mesh-tick ver 2>&1 | grep -qx 'launchd: a cada 123 min' || falhou 'o ver do launchd deveria devolver 123'
grep -q '<string>x</string>' "$PL" || falhou 'o resto do plist não pode mudar'
passou 'tick do mesh: launchd mostra minutos e aceita qualquer intervalo'
rm -f "$PL"
out=$("$TT" --mesh-tick 5 2>&1 || true); grep -q 'sem agendador' <<<"$out" || falhou 'sem agendador nenhum deveria dizer isso'

# --- a tela do tick -----------------------------------------------------------------------------------------------
novo_timer 10min
out=$(printf '\n' | "$TT" --mesh-tick-menu 2>&1) || falhou 'a tela do tick deveria sair com Enter'
grep -q 'Tick do mesh' <<<"$out" || falhou 'a tela do tick deveria mostrar o título'
grep -q 'maquina' <<<"$out" || falhou 'a tela do tick deveria mostrar a tabela das máquinas'
grep -q 'a cada 10 min' <<<"$out" || falhou 'a tela do tick deveria mostrar o intervalo atual'
passou 'tela do tick: mostra as máquinas com o intervalo e sai com Enter'

# "1 8": máquina 1, 8 minutos, numa linha só; o resultado fica na tela e a tabela já mostra o novo valor.
out=$(printf '1 8\n\n' | "$TT" --mesh-tick-menu 2>&1) || falhou 'a tela do tick deveria aceitar "1 8"'
grep -q '^OnUnitActiveSec=8min$' "$ARQ" || falhou 'a tela deveria gravar 8 min no timer'
grep -q '✔' <<<"$out" || falhou "a tela deveria mostrar o resultado da mudança: $out"
[[ $(grep -c 'a cada 8 min' <<<"$out") -ge 2 ]] || falhou 'depois de mudar, a tabela deveria mostrar 8 min'
# Pergunta em dois passos, com um valor que a tela antiga recusava.
printf '1\n123\n\n' | "$TT" --mesh-tick-menu >/dev/null 2>&1
grep -q '^OnUnitActiveSec=123min$' "$ARQ" || falhou 'a tela deveria aceitar 123 min no passo a passo'
# T = todas.
printf 'T 3\n\n' | "$TT" --mesh-tick-menu >/dev/null 2>&1
grep -q '^OnUnitActiveSec=3min$' "$ARQ" || falhou 'T deveria aplicar a todas (inclui esta)'
# Entrada ruim: diz o motivo e não muda nada.
out=$(printf '1 banana\n\n' | "$TT" --mesh-tick-menu 2>&1)
grep -q '✘' <<<"$out" || falhou 'valor inválido deveria aparecer com ✘'
grep -q '^OnUnitActiveSec=3min$' "$ARQ" || falhou 'valor inválido não pode mexer no timer'
out=$(printf '9 5\n\n' | "$TT" --mesh-tick-menu 2>&1)
grep -q 'não é uma máquina' <<<"$out" || falhou 'número de máquina inexistente deveria ser avisado'
# Fim da entrada (sem Enter final) não pode deixar a tela em laço.
printf '' | timeout 20 "$TT" --mesh-tick-menu >/dev/null 2>&1 || falhou 'sem entrada a tela deveria sair, não ficar em laço'
passou 'tela do tick: "1 8", passo a passo (123), T para todas, entrada ruim avisada, fim de entrada sai'

# --- outras máquinas, pelo ssh (falso: roda o tt isolado com o HOME da "outra máquina") ------------------------------------
# bom = responde e muda; velho = tt de antes do --mesh-tick; mudo = não responde. O ssh de verdade usaria login shell (PATH
# novo, systemctl de verdade): o falso tira o -l para o systemctl falso continuar na frente.
mkdir -p "$T/rem-bom/.config/systemd/user"
printf '[Unit]\nDescription=tt-mesh chefe (bom) a cada 10 min\n[Timer]\nOnUnitActiveSec=10min\n' >"$T/rem-bom/.config/systemd/user/tt-chief.timer"
printf 'bom-host u bom\nvelho-host u velho\nmudo-host u mudo\n' >"$HOME/.config/tt/maquinas"
cat >"$T/bin/ssh" <<'SSH'
#!/bin/bash
cmd=${@: -1}; dest=${@: -2:1}
case $dest in
  *bom-host) cmd=${cmd/bash -lc /bash -c }; HOME=$T/rem-bom exec bash -c "${cmd//\~\/.local\/bin\/tt/$TT}" ;;
  *velho-host) echo "tt: opção desconhecida: --mesh-tick" >&2; exit 2 ;;
  *) exit 255 ;;
esac
SSH
chmod +x "$T/bin/ssh"; export T TT
novo_timer 10min
out=$("$TT" --mesh-tick 9 --todas 2>&1) && falhou '--todas com máquina que não confirmou deveria sair com erro'
grep -q "^bom: systemd: a cada 9 min$" <<<"$out" || falhou "a máquina que respondeu deveria confirmar 9 min: $out"
grep -q '^velho: tt antigo' <<<"$out" || falhou "a máquina de tt antigo deveria dizer que precisa atualizar: $out"
grep -q '^mudo: sem resposta' <<<"$out" || falhou "a máquina muda deveria aparecer como sem resposta: $out"
grep -q '^OnUnitActiveSec=9min$' "$T/rem-bom/.config/systemd/user/tt-chief.timer" || falhou 'o timer da outra máquina deveria ter mudado'
grep -q '^OnUnitActiveSec=9min$' "$ARQ" || falhou 'o timer desta máquina deveria ter mudado'
passou 'tick do mesh: --todas muda cada máquina, confirma o que ela respondeu e conta a que não deu'

out=$(printf '2 17\n\n' | "$TT" --mesh-tick-menu 2>&1)
grep -q '^OnUnitActiveSec=17min$' "$T/rem-bom/.config/systemd/user/tt-chief.timer" || falhou 'a tela deveria mudar a outra máquina'
grep -q '^OnUnitActiveSec=9min$' "$ARQ" || falhou 'mudar a máquina 2 não pode mexer nesta'
grep -q 'bom' <<<"$out" && grep -q 'velho' <<<"$out" && grep -q 'mudo' <<<"$out" || falhou "a tabela deveria listar as quatro máquinas: $out"
grep -q 'tt antigo' <<<"$out" && grep -q 'sem resposta' <<<"$out" || falhou 'a tabela deveria dizer por que uma máquina não mostra o intervalo'
passou 'tela do tick: muda a máquina escolhida (só ela) e explica as que não responderam'

out=$(printf 'T 5\n\n' | "$TT" --mesh-tick-menu 2>&1)
grep -c '✘' <<<"$out" | grep -qx 2 || falhou "T deveria marcar com ✘ as duas máquinas que não confirmaram: $out"
grep -c '✔' <<<"$out" | grep -qx 2 || falhou "T deveria marcar com ✔ as duas que confirmaram: $out"
passou 'tela do tick: T mostra o resultado de cada máquina (✔ confirmou, ✘ não)'
