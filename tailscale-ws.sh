#!/usr/bin/env bash
# Entrada comum, inclusive pelo ssh com o PATH mínimo do macOS.
raiz=${1:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
exec python3 "$raiz/tailscale-ws.py" "$raiz" "${2:-status}"
