#!/usr/bin/env bash
# O receptor simulado precede clip.exe/pbcopy do host, inclusive com PATH enxuto.
sem_clipboard_real() {
  local base=$1 auxiliar
  auxiliar=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/clipboard-isolado.py
  mkdir -p "$base/clipboard-bin"
  printf '#!/usr/bin/env bash\nexec python3 -I %s %s %s\n' "$(printf '%q' "$auxiliar")" "$(printf '%q' "$base")" "$(printf '%q' "${T:-$base}")" >"$base/clipboard-bin/clip.exe"
  chmod +x "$base/clipboard-bin/clip.exe"
  export PATH="$base/clipboard-bin:$PATH"
  TT_PATH_BASE="$base/clipboard-bin:${TT_PATH_BASE:-/usr/bin:/bin}"; export TT_PATH_BASE
}
