#!/usr/bin/env bash
# A skill versionada funciona sem token, rede ou configuração real do usuário.
set -euo pipefail
source "$(dirname "$0")/lib.sh"; isolar
python3 -m unittest discover -s "$RAIZ/skills/figma-cota/tests" -v
