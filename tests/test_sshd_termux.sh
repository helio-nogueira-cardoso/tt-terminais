#!/usr/bin/env bash
# sshd do Termux supervisionado: configuração inválida vira erro no log (sem subir nada); vigia sem pidfile não está vivo.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"
cat >"$T/bin/sshd" <<'SH'
#!/bin/sh
if [ "$1" = "-t" ]; then echo "/data/x/sshd_config: line 3: Bad configuration option: lixo" >&2; exit 1; fi
exit 0
SH
chmod +x "$T/bin/sshd"
export PATH="$T/bin:$TT_PATH_BASE"
TT_SO_CARREGAR=1 bash -c 'source "$1"; sshd_termux_subir' _ "$TT" && falhou 'configuração inválida não pode subir o sshd'
grep -q 'configuração inválida' "$HOME/.local/state/tt/sshd/garantir.log" || falhou "o erro do sshd -t deveria ficar no log: $(cat "$HOME/.local/state/tt/sshd/garantir.log" 2>/dev/null)"
passou 'sshd do Termux com configuração inválida: não sobe e o erro do sshd -t fica no log'

"$TT" --vigia-vivo && falhou 'sem pidfile o vigia não pode estar vivo'
passou 'vigia sem pidfile: --vigia-vivo diz que não está de pé'
