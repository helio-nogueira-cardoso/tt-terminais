#!/usr/bin/env bash
# Rede simulada: retentativas limitadas no supervisor e criação só por escolha explícita.
source "$(dirname "$0")/lib.sh"; isolar
for f in ponte_tentar ponte_nova_janela; do
  eval "$(sed -n "/^$f() {/,/^}/p" "$TT")"
done
LOG=$T/chamadas
FILA=$T/fila
resolver_remota() {
  local rc
  rc=$(head -1 "$FILA"); [[ -n $rc ]] || rc=2
  sed -i '1d' "$FILA"
  printf 'resolver %s %s\n' "$rc" "$2" >>"$LOG"
  [[ $rc == 0 ]] && echo '$17|1792792741|sessao'
  return "$rc"
}
sleep() { echo "sleep $1" >>"$LOG"; }
rotulo_de() { echo remota; }
ponte_registrar() { echo "registrar $*" >>"$LOG"; }
log_ponte() { :; }
ssh() { echo "ssh $*" >>"$LOG"; }
ssh_pedir() { echo criar >>"$LOG"; printf -v "$1" '%s' "$NOVA"; return "$CRIAR_RC"; }
tmux() { [[ $1 == set-option ]] && echo "$*" >>"$LOG"; return 0; }
q() { printf '%q' "$1"; }
MAQUINA=teste; PATH_REMOTO=''; SSH_OPC_TELA=(); TT_REMOTO=tt
NOVA=sessao-nova; CRIAR_RC=0

printf '%s\n' 2 2 0 >"$FILA"; : >"$LOG"
ponte_tentar usuario@remota sessao ponte token >"$T/saida" || falhou 'não conectou quando a rede voltou'
grep -q '^sleep 2$' "$LOG" && grep -q '^sleep 4$' "$LOG" || falhou 'retentativas sem espera crescente'
[[ $(grep -c '^ssh ' "$LOG") == 1 ]] || falhou 'attach repetido'
passou 'rede volta: duas esperas, um attach, sem pedir Enter'

printf '%s\n' 2 2 2 2 >"$FILA"; : >"$LOG"
rc=0; ponte_tentar usuario@remota sessao ponte token >"$T/saida" || rc=$?
[[ $rc == 21 && $(grep -c '^sleep ' "$LOG") == 3 ]] || falhou 'rede muda não parou após três retentativas'
grep -q '^sleep 8$' "$LOG" || falhou 'terceira espera não é de 8 s'
! grep -q '^criar\|^ssh ' "$LOG" || falhou 'criou/anexou sem identidade confirmada'
passou 'rede muda: três retentativas no máximo e retorno para recuperação'

printf '%s\n' 1 1 >"$FILA"; : >"$LOG"
rc=0; ponte_tentar usuario@remota sessao ponte token >"$T/saida" || rc=$?
[[ $rc == 20 && $(grep -c '^resolver ' "$LOG") == 2 ]] || falhou 'alvo ausente não foi conferido duas vezes'
! grep -q 'kill-session' "$LOG" || falhou 'recuperação matou a ponte antes da escolha'
passou 'alvo ausente oferece saída local sem matar sessões'

printf '%s\n' 0 >"$FILA"; : >"$LOG"
ponte_tentar usuario@remota antiga ponte token nova >"$T/saida" || falhou 'N não criou e conectou'
[[ $(grep -c '^criar$' "$LOG") == 1 ]] || falhou 'criação repetida'
grep -q '^resolver 0 sessao-nova$' "$LOG" || falhou 'reconectou ao nome antigo'
for opc in ponte_uuid tt_pre_id ponte_id ponte_srv; do
  grep -q -- "-u -t =ponte: @$opc" "$LOG" || falhou "identidade @$opc antiga ficou"
done
passou 'nova sessão explícita limpa toda a identidade antiga antes de resolver'

CRIAR_RC=124; NOVA=''; : >"$LOG"
rc=0; ponte_tentar usuario@remota antiga ponte token nova >"$T/saida" || rc=$?
[[ $rc == 22 && $(grep -c '^criar$' "$LOG") == 1 ]] || falhou 'criação incerta foi repetida'
! grep -q '^resolver\|^set-option' "$LOG" || falhou 'criação incerta alterou o alvo'
passou 'criação sem resposta é informada e não se repete automaticamente'
