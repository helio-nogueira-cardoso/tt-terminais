#!/usr/bin/env bash
# Regressão (book-hl → s23, 20/10/2026): o malha_provar tentava 3 usuários em cada porta mesmo quando a falha era da
# rede ou da porta. Cada tentativa ficava presa no sshd do celular até o LoginGraceTime, lotava o MaxStartups dele e o
# PerSourcePenalties passava a recusar esta máquina (e as outras). Outro usuário só se o sshd respondeu. Sem rede.
source "$(dirname "$0")/lib.sh"; isolar
eval "$(sed -n '/^malha_provar() {/,/^}/p' "$TT")"
SSH_OPC=(); TT_REMOTO=tt
export TMPDIR=$T/tmp; mkdir -p "$TMPDIR"
CHAMADAS=$T/chamadas
ssh_porta_garantir() { echo "garantir $*" >>"$CHAMADAS"; }
timeout() { shift; [[ ${SSH_MODO:-} == preso ]] && return 124; "$@"; }
ssh() { # ssh [-p N] destino comando
  local porta=22
  [[ $1 == -p ]] && { porta=$2; shift 2; }
  echo "ssh $porta $1" >>"$CHAMADAS"
  case $SSH_MODO in
    reset) echo 'kex_exchange_identification: read: Connection reset by peer' >&2; return 255 ;;
    negado) echo 'u@h: Permission denied (publickey).' >&2; return 255 ;;
    8022) if [[ $porta == 8022 ]]; then printf 'EU\th\tu\talvo\t0\t8022\n'; return 0; fi
      echo 'ssh: connect to host h port 22: Connection refused' >&2; return 255 ;;
  esac
}
n() { grep -c '^ssh ' "$CHAMADAS" 2>/dev/null || echo 0; }

: >"$CHAMADAS"; SSH_MODO=reset malha_provar alvo h u >/dev/null && falhou 'reset não deveria provar'
[[ $(n) == 2 ]] || falhou "reset: uma tentativa por porta, foram $(n): $(tr '\n' ' ' <"$CHAMADAS")"
: >"$CHAMADAS"; SSH_MODO=preso malha_provar alvo h u >/dev/null && falhou 'preso não deveria provar'
passou 'erro de rede ou ssh preso: uma tentativa por porta (não 3 usuários)'
: >"$CHAMADAS"; SSH_MODO=negado malha_provar alvo h u >/dev/null && falhou 'chave recusada não deveria provar'
[[ $(n) == 6 ]] || falhou "chave recusada: os 3 usuários nas 2 portas, foram $(n)"
passou 'chave recusada: tenta os outros usuários'
: >"$CHAMADAS"; r=$(SSH_MODO=8022 malha_provar alvo h u) || falhou 'deveria provar pela 8022'
[[ $r == u && $(n) == 2 ]] || falhou "porta fechada na 22: direto para a 8022 (r=$r, $(n) chamadas)"
grep -q '^garantir h 8022$' "$CHAMADAS" || falhou 'a 8022 que serviu não foi para o ~/.ssh/config'
passou 'porta 22 fechada: vai direto à 8022 e grava a porta'
[[ -z $(ls -A "$TMPDIR") ]] || falhou "sobrou arquivo temporário: $(ls "$TMPDIR")"
passou 'sem sobras'
