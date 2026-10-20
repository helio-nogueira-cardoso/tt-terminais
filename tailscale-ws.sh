#!/usr/bin/env bash
# Fallback WebSocket local do Tailscale para macOS corporativo.
if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
  for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [ -x "$b" ] && exec "$b" "$0" "$@"; done
  echo 'tailscale-ws: precisa de bash 4+ (instale o bash do Homebrew).' >&2; exit 1
fi
set -u
die() { echo "tailscale-ws: $*" >&2; exit 1; }
[[ ${OSTYPE:-} == darwin* ]] || die 'este fallback é específico do macOS.'
ROOT=${1:-}; ACTION=${2:-status}
[[ -n $ROOT ]] || ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BRIDGE_SRC=$ROOT/tailscale-ws-bridge.cjs
[[ -r $BRIDGE_SRC ]] || die "não achei $BRIDGE_SRC"
BASE=$HOME/.local; RUNTIME=$BASE/libexec/tt-tailscale-ws-bridge.cjs
DATA=$BASE/share/tt-tailscale-ws; CA=$DATA/system-ca.pem; LOG=$HOME/.cache
PLIST_DIR=/Library/LaunchDaemons; TAILSCALE_PLIST=$PLIST_DIR/com.tailscale.tailscaled.plist
labels=(com.tailscale.tt-ws-control com.tailscale.tt-ws-control80 com.tailscale.tt-ws-derp)
node_bin() { command -v node 2>/dev/null || true; }
launch() { sudo launchctl "$@"; }

status() {
  echo 'Serviços:'
  for label in "${labels[@]}" com.tailscale.tailscaled; do
    launch print system/$label >/dev/null 2>&1 && echo "  ✓ $label" || echo "  – $label"
  done
  echo 'Listeners:'
  sudo lsof -nP -iTCP:80 -iTCP:18743 -iTCP:18744 -sTCP:LISTEN 2>/dev/null || true
  command -v tailscale >/dev/null 2>&1 && tailscale status || true
}

plist_bridge() {
  local out=$1 label=$2 port=$3 user=$4
  cat >"$out" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array><string>$(node_bin)</string><string>$RUNTIME</string></array>
<key>EnvironmentVariables</key><dict><key>BRIDGE_PORT</key><string>$port</string><key>NODE_EXTRA_CA_CERTS</key><string>$CA</string></dict>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>StandardOutPath</key><string>$LOG/tt-tailscale-ws-$label.log</string>
<key>StandardErrorPath</key><string>$LOG/tt-tailscale-ws-$label.err.log</string>
$([[ -n $user ]] && printf '<key>UserName</key><string>%s</string>\n' "$user")
</dict></plist>
EOF
}

activate() {
  [[ $(id -u) -ne 0 ]] || die 'rode como usuário normal; o script chama sudo quando necessário.'
  local node; node=$(node_bin); [[ -x $node ]] || die 'Node.js 18+ não encontrado no PATH.'
  command -v tailscaled >/dev/null 2>&1 || [[ -x /usr/local/bin/tailscaled ]] || die 'tailscaled não encontrado.'
  mkdir -p "$(dirname "$RUNTIME")" "$DATA" "$LOG"
  install -m 755 "$BRIDGE_SRC" "$RUNTIME"
  local ca_tmp=$CA.tmp
  security find-certificate -a -p /Library/Keychains/System.keychain >"$ca_tmp" || die 'não consegui exportar as CAs do System Keychain.'
  [[ -s $ca_tmp ]] || die 'o System Keychain não retornou CAs.'
  mv -f "$ca_tmp" "$CA"
  local td; td=$(mktemp -d)
  plist_bridge "$td/control.plist" com.tailscale.tt-ws-control 18743 "$(id -un)"
  plist_bridge "$td/control80.plist" com.tailscale.tt-ws-control80 80 ''
  plist_bridge "$td/derp.plist" com.tailscale.tt-ws-derp 18744 "$(id -un)"
  local tailscaled; tailscaled=$(command -v tailscaled 2>/dev/null || echo /usr/local/bin/tailscaled)
  cat >"$td/tailscaled.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>com.tailscale.tailscaled</string>
<key>ProgramArguments</key><array><string>$tailscaled</string></array>
<key>EnvironmentVariables</key><dict><key>HTTP_PROXY</key><string>http://127.0.0.1:18744</string><key>HTTPS_PROXY</key><string>http://127.0.0.1:18744</string><key>TS_DEBUG_USE_DERP_HTTP</key><string>true</string><key>TS_USE_CONTROL_DIAL_PLAN</key><string>false</string></dict>
<key>RunAtLoad</key><true/></dict></plist>
EOF
  if [[ -f $TAILSCALE_PLIST && ! -f $TAILSCALE_PLIST.antes-ws ]]; then sudo cp "$TAILSCALE_PLIST" "$TAILSCALE_PLIST.antes-ws"; fi
  local p label old_ts=$td/old-tailscaled.plist
  [[ -f $TAILSCALE_PLIST ]] && sudo cp "$TAILSCALE_PLIST" "$old_ts"
  for p in control control80 derp; do
    [[ -f "$PLIST_DIR/com.tailscale.tt-ws-$p.plist" ]] && sudo cp "$PLIST_DIR/com.tailscale.tt-ws-$p.plist" "$td/old-$p.plist"
  done
  rollback() {
    for label in "${labels[@]}" com.tailscale.tailscaled; do launch bootout system/$label >/dev/null 2>&1 || true; done
    for p in control control80 derp; do
      if [[ -f "$td/old-$p.plist" ]]; then
        sudo install -o root -g wheel -m 644 "$td/old-$p.plist" "$PLIST_DIR/com.tailscale.tt-ws-$p.plist"
        launch bootstrap system "$PLIST_DIR/com.tailscale.tt-ws-$p.plist" >/dev/null 2>&1 || true
      else
        sudo rm -f "$PLIST_DIR/com.tailscale.tt-ws-$p.plist"
      fi
    done
    if [[ -f $old_ts ]]; then
      sudo install -o root -g wheel -m 644 "$old_ts" "$TAILSCALE_PLIST"
      launch bootstrap system "$TAILSCALE_PLIST" >/dev/null 2>&1 || true
    fi
    rm -rf "$td"
  }
  sudo install -o root -g wheel -m 644 "$td/control.plist" "$PLIST_DIR/com.tailscale.tt-ws-control.plist" || { rollback; die 'não consegui instalar o serviço de controle WebSocket.'; }
  sudo install -o root -g wheel -m 644 "$td/control80.plist" "$PLIST_DIR/com.tailscale.tt-ws-control80.plist" || { rollback; die 'não consegui instalar o serviço WebSocket da porta 80.'; }
  sudo install -o root -g wheel -m 644 "$td/derp.plist" "$PLIST_DIR/com.tailscale.tt-ws-derp.plist" || { rollback; die 'não consegui instalar o serviço DERP WebSocket.'; }
  sudo install -o root -g wheel -m 644 "$td/tailscaled.plist" "$TAILSCALE_PLIST" || { rollback; die 'não consegui instalar a configuração do tailscaled.'; }
  for label in "${labels[@]}"; do launch bootout system/$label >/dev/null 2>&1 || true; done
  for p in control control80 derp; do
    launch bootstrap system "$PLIST_DIR/com.tailscale.tt-ws-$p.plist" || { rollback; die "não consegui iniciar o serviço WebSocket $p; configuração anterior restaurada."; }
  done
  launch bootout system/com.tailscale.tailscaled >/dev/null 2>&1 || true
  launch bootstrap system "$TAILSCALE_PLIST" || { rollback; die 'não consegui iniciar o tailscaled com o fallback; configuração anterior restaurada.'; }
  rm -rf "$td"
  echo '✓ fallback WebSocket local do Tailscale ativado.'
  status
}

deactivate() {
  local label
  for label in "${labels[@]}"; do launch bootout system/$label >/dev/null 2>&1 || true; done
  if [[ -f $TAILSCALE_PLIST.antes-ws ]]; then sudo install -o root -g wheel -m 644 "$TAILSCALE_PLIST.antes-ws" "$TAILSCALE_PLIST"; fi
  launch bootout system/com.tailscale.tailscaled >/dev/null 2>&1 || true
  launch bootstrap system "$TAILSCALE_PLIST" >/dev/null 2>&1 || true
  echo '✓ fallback WebSocket local desativado; configuração anterior restaurada quando havia backup.'
}

case $ACTION in
  ativar|on|enable) activate ;;
  desativar|off|disable) deactivate ;;
  status) status ;;
  testar|test) command -v tailscale >/dev/null 2>&1 && tailscale ping --c 1 dell || true; status ;;
  *) echo 'uso: tailscale-ws.sh RAIZ ativar|desativar|status|testar' >&2; exit 2 ;;
esac
