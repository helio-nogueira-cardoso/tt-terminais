#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"; isolar
grep -q -- '--tailscale-ws' "$RAIZ/tt"
grep -q 'TS_DEBUG_USE_DERP_HTTP' "$RAIZ/tailscale-ws.py"
grep -q 'TS_USE_CONTROL_DIAL_PLAN' "$RAIZ/tailscale-ws.py"
grep -q '127.0.0.1:18744' "$RAIZ/tailscale-websocket.md"
node --check "$RAIZ/tailscale-ws-bridge.cjs"
"$BASH" -n "$RAIZ/tailscale-ws.sh"
python3 "$RAIZ/tests/tailscale_ws_cases.py"
echo 'ok: WebSocket: instalação real simulada, idempotência, reparo, rollback e isolamento'
