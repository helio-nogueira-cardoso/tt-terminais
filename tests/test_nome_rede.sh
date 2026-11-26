#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
isolar
mkdir -p "$T/bin"
cat > "$T/bin/tailscale" <<'STUB'
#!/bin/sh
cat "$TT_RT/status"
STUB
chmod +x "$T/bin/tailscale"
export PATH="$T/bin:$PATH" XDG_STATE_HOME="$T/state"
echo nome=local >"$XDG_CONFIG_HOME/tt/config"
tmux new-session -d -s teste
TT_SO_CARREGAR=1 source "$TT"
[[ $(nome_exibido) == local ]]
for par in 'pcPedro pcPedro' 'Outro nome-2'; do
  read -r host dns <<<"$par"
  printf '{"BackendState":"Running","Self":{"HostName":"%s","DNSName":"%s.rede.ts.net."}}' "$host" "$(echo "$dns" | tr "[:upper:]" "[:lower:]")" >"$TT_RT/status"
  nome_rede_atualizar
  [[ $("$TT" --nome) == "$dns" && $(tmux show-option -gv @maquina) == "$dns" ]]
done
echo '{"BackendState":"Stopped"}' >"$TT_RT/status"
nome_rede_atualizar
[[ $(nome_exibido) == nome-2 && $MAQUINA == local && $(conf nome) == local ]]
