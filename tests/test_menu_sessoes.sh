#!/usr/bin/env bash
# Menu de sessões não trava (26/10, empresa): um ssh que deixa um filho segurando a saída não pode prender a listagem
# de uma máquina. A saída vai para um arquivo, e o tt segue quando o ssh sai.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"
cat >"$T/bin/ssh" <<'SH'
#!/bin/sh
( sleep 60 ) &
echo "sessao-remota"
exit 0
SH
chmod +x "$T/bin/ssh"
export PATH="$T/bin:$TT_PATH_BASE"
ini=$(date +%s)
linha=$(TT_SO_CARREGAR=1 bash -c 'source "$1"; TT_REMOTO=true; SSH_OPC=(); bloco_vivo helio@maquina.exemplo maquina >/dev/null; cat "$(cache_bloco maquina)" 2>/dev/null' _ "$TT" | head -1)
gasto=$(( $(date +%s) - ini ))
(( gasto < 20 )) || falhou "a listagem de uma máquina ficou presa ${gasto}s esperando um filho do ssh"
passou "listagem de uma máquina não fica presa por filho do ssh (${gasto}s)"
