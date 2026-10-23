#!/usr/bin/env bash
# Regressão (projeto tt): a sessão de OUTRA máquina é renomeada (o vigia renomeia sozinho) e a ponte
# daqui guardava o nome antigo. A sonda de órfãs (a cada 5 min) achava que a sessão sumiu, matava a
# ponte COM VOCÊ DENTRO e o tmux (detach-on-destroy off) te jogava em outra sessão "sem motivo".
# Agora a ponte identifica o alvo por id de sessão + start_time do servidor. Usa as funções REAIS do
# tt (extraídas), um tmux isolado e um ssh simulado; sem rede.
set -u
source "$(dirname "$0")/tmux-isolado.sh"
TT="$(cd "$(dirname "$0")/.." && pwd)/tt"
HOME=$(mktemp -d); export HOME
falhas=0
ok()   { echo "  ok: $1"; }
erro() { echo "  ERRO: $1"; falhas=$((falhas+1)); }

for f in resolver_remota ponte_registrar log_ponte fechar_pontes_ociosas; do
  eval "$(sed -n "/^$f() {/,/^}/p" "$TT")"
done
[[ $(type -t resolver_remota) == function && $(type -t fechar_pontes_ociosas) == function ]] || { echo "não extraí as funções"; exit 1; }

SSH_OPC=(); PATH_REMOTO=''
# O que o "destino" responde a list-sessions; REMOTO_RC: 0 ok, 1 sem servidor tmux, 255 ssh caiu.
REMOTO=""; REMOTO_RC=0
timeout() { shift; "$@"; }
ssh() { printf '%s' "$REMOTO"; return "$REMOTO_RC"; }

existe() { tmux has-session -t "=$1" 2>/dev/null; }
opt() { tmux show-options -qv -t "=$1:" "$2"; }
cria() { # nome dest alvo [id srv]
  tmux new-session -d -s "$1" "sleep 600"
  tmux set-option -t "=$1:" @ponte "$2"; tmux set-option -t "=$1:" @ponte_alvo "$3"
  [[ -n ${4:-} ]] && { tmux set-option -t "=$1:" @ponte_id "$4"; tmux set-option -t "=$1:" @ponte_srv "$5"; }
  return 0
}
AGORA=$(date +%s)
sonda() { fechar_pontes_ociosas "$AGORA" 1; }

# 1) renomeada lá: sobrevive a quantas sondagens forem, e o alvo acompanha o nome novo
cria p-renom destX 'destX|janela-1' '$3' 100
REMOTO=$'$3|100|titulo-novo\n$4|100|outra\n'
sonda; sonda; sonda
existe p-renom && ok "ponte de sessão renomeada lá sobrevive às sondagens" || erro "ponte de sessão renomeada foi MORTA"
[[ $(opt p-renom @ponte_alvo) == 'destX|titulo-novo' ]] && ok "alvo acompanhou o nome novo" || erro "alvo ficou '$(opt p-renom @ponte_alvo)'"

# 2) sumiu de verdade: marcada na 1ª sondagem, encerrada na 2ª (e deixa rastro no log)
cria p-sumiu destX 'destX|x' '$9' 100
REMOTO=$'$3|100|titulo-novo\n'
sonda
existe p-sumiu && ok "1ª sondagem só marca (grace)" || erro "morta na 1ª sondagem"
sonda
existe p-sumiu && erro "ponte de sessão que sumiu sobreviveu" || ok "ponte de sessão que sumiu é encerrada na 2ª sondagem"
grep -q 'p-sumiu' "$HOME/.cache/tt-vigia.log" 2>/dev/null && ok "encerramento ficou no log" || erro "encerramento sem log"

# 3) destino mudo (ssh caiu / timeout): nada se conclui
cria p-mudo destY 'destY|qq' '$1' 100
REMOTO=""; REMOTO_RC=255
sonda; sonda; sonda
existe p-mudo && ok "destino mudo preserva a ponte" || erro "ponte morta com destino mudo"
REMOTO_RC=0

# 4) servidor de lá reiniciou: o id $3 voltou a existir, mas é OUTRA sessão (start_time diferente)
cria p-reinicio destX 'destX|janela-1' '$3' 100
REMOTO=$'$3|999|estranha\n'
sonda; sonda
existe p-reinicio && erro "id reaproveitado por outro servidor foi tomado como a mesma sessão" || ok "id de outro servidor (start_time diferente) não vale"

# 5) mesmo nome em um servidor novo é OUTRA sessão: identidade conhecida não reata por nome.
cria p-reata destX 'destX|janela-2' '$3' 100
REMOTO=$'$7|999|janela-2\n'
sonda
existe p-reata && ok "identidade antiga: primeira sonda preserva para confirmar" || erro "morta sem confirmação"
sonda
existe p-reata && erro "ponte herdou sessão homônima de outro servidor" || ok "mesmo nome não substitui identidade conhecida"

# 6) ponte antiga (sem id) cujo nome existe: ganha o id
cria p-antiga destX 'destX|viva'
REMOTO=$'$2|50|viva\n'
sonda
[[ $(opt p-antiga @ponte_id) == '$2' ]] && ok "ponte antiga ganha o id" || erro "ponte antiga sem id"

# 7) sem servidor tmux no destino (rc 1, saída vazia) conta como "sumiu" só após 2 sondagens
cria p-semsrv destZ 'destZ|a' '$1' 5
REMOTO=""; REMOTO_RC=1
sonda; existe p-semsrv && ok "sem servidor: poupada na 1ª" || erro "morta na 1ª"
sonda; existe p-semsrv && erro "sem servidor: sobreviveu" || ok "sem servidor: encerrada na 2ª"
REMOTO_RC=0

# 8) ociosa (sem cliente há mais que o limite): continua sendo encerrada, com log
cria p-ociosa destX 'destX|viva' '$2' 50
REMOTO=$'$2|50|viva\n'
TT_T_PONTE=1 fechar_pontes_ociosas $((AGORA + 3600)) ""
existe p-ociosa && erro "ponte ociosa sobreviveu" || ok "ponte ociosa continua sendo encerrada"

anexadas() { tmux list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null | awk -v n="$1" '$1 == n { print $2 }'; }
# 9) ponte antiga (sem id) COM cliente anexado de verdade, cujo nome não existe mais lá (foi renomeada): preservada.
#    É exatamente o caso que te jogava para outra sessão. Um cliente de verdade (pty via script) conta como anexado.
cria p-anexada destX 'destX|nome-velho'
if command -v script >/dev/null; then ( sleep 60 | script -qec "tmux attach -t p-anexada" /dev/null ) >/dev/null 2>&1 &
else ( sleep 60 | tmux -C attach -t p-anexada ) >/dev/null 2>&1 &
fi
for _ in $(seq 1 20); do [[ $(anexadas p-anexada) == 1 ]] && break; sleep 0.3; done
REMOTO=$'$3|100|titulo-novo\n'
if [[ $(anexadas p-anexada) == 1 ]]; then
  sonda; sonda; sonda
  existe p-anexada && ok "ponte antiga ANEXADA e sem id nunca é morta pela sonda (renomeação não é sumiço)" || erro "ponte anexada foi MORTA"
else
  echo "  (pulado: não consegui anexar um cliente neste tmux)"
fi
# 10) sessão local comum (sem @ponte) jamais é tocada
tmux new-session -d -s real-local "sleep 600"
sonda; sonda
existe real-local && ok "sessão local comum nunca é tocada" || erro "sessão local sumiu"

echo
if ((falhas == 0)); then echo "TODOS OS TESTES PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit $falhas
