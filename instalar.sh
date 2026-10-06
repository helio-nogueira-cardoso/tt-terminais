#!/usr/bin/env bash
# Instala o tt neste usuário em um passo: dependências, tt, ~/.tmux.conf e abertura automática
# no tmux (bloco no ~/.bashrc). Uso: ./instalar.sh [nome-desta-máquina]
# Só o bashrc: ./tt --configurar-bashrc   (desfazer: ./tt --remover-bashrc)
# Verificar/instalar as dependências é feito antes da instalação do tt.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

declare -A PACOTE_APT=( [w3m]=w3m
  [bash]=bash [git]=git [tmux]=tmux [fzf]=fzf [python3]=python3
  [ssh]=openssh-client [tar]=tar [rg]=ripgrep
)
declare -A PACOTE_DNF=( [w3m]=w3m
  [bash]=bash [git]=git [tmux]=tmux [fzf]=fzf [python3]=python3
  [ssh]=openssh-clients [tar]=tar [rg]=ripgrep
)
declare -A PACOTE_PACMAN=( [w3m]=w3m
  [bash]=bash [git]=git [tmux]=tmux [fzf]=fzf [python3]=python
  [ssh]=openssh [tar]=tar [rg]=ripgrep
)
declare -A PACOTE_APK=( [w3m]=w3m
  [bash]=bash [git]=git [tmux]=tmux [fzf]=fzf [python3]=python3
  [ssh]=openssh-client [tar]=tar [rg]=ripgrep
)
declare -A PACOTE_BREW=( [w3m]=w3m
  [bash]=bash [git]=git [tmux]=tmux [fzf]=fzf [python3]=python
  [ssh]=openssh [tar]=gnu-tar [rg]=ripgrep
)
declare -A PACOTE_PKG=( [w3m]=w3m
  [bash]=bash [git]=git [tmux]=tmux [fzf]=fzf [python3]=python
  [ssh]=openssh [tar]=tar [rg]=ripgrep
)

necessarios=(bash git tmux fzf python3 ssh tar rg)
faltam=()
for c in "${necessarios[@]}"; do command -v "$c" >/dev/null 2>&1 || faltam+=("$c"); done

gerenciador=""
case "$(uname -s)" in
  Darwin) command -v brew >/dev/null 2>&1 && gerenciador=brew ;;
  *)
    for candidato in apt-get dnf pacman apk; do
      command -v "$candidato" >/dev/null 2>&1 && { gerenciador=$candidato; break; }
    done
    [[ -n $gerenciador ]] || command -v pkg >/dev/null 2>&1 && gerenciador=pkg
    ;;
esac

instalar_pacotes() {
  local -a pacotes=() c
  for c in "${faltam[@]}"; do
    case $gerenciador in
      apt-get) pacotes+=("${PACOTE_APT[$c]}") ;;
      dnf) pacotes+=("${PACOTE_DNF[$c]}") ;;
      pacman) pacotes+=("${PACOTE_PACMAN[$c]}") ;;
      apk) pacotes+=("${PACOTE_APK[$c]}") ;;
      brew) pacotes+=("${PACOTE_BREW[$c]}") ;;
      pkg) pacotes+=("${PACOTE_PKG[$c]}") ;;
    esac
  done
  ((${#pacotes[@]})) || return 0
  printf 'Dependências ausentes: %s\n' "${faltam[*]}"
  case $gerenciador in
    apt-get)
      if ((EUID == 0)); then apt-get update && apt-get install -y "${pacotes[@]}"
      elif command -v sudo >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y "${pacotes[@]}"
      else echo 'Não encontrei sudo; execute como administrador:' >&2; printf '  sudo apt-get install -y %q ' "${pacotes[@]}"; echo >&2; return 1; fi ;;
    dnf)
      if ((EUID == 0)); then dnf install -y "${pacotes[@]}"
      elif command -v sudo >/dev/null 2>&1; then sudo dnf install -y "${pacotes[@]}"
      else echo 'Não encontrei sudo; execute como administrador:' >&2; printf '  sudo dnf install -y %q ' "${pacotes[@]}"; echo >&2; return 1; fi ;;
    pacman)
      if ((EUID == 0)); then pacman -Sy --needed --noconfirm "${pacotes[@]}"
      elif command -v sudo >/dev/null 2>&1; then sudo pacman -Sy --needed --noconfirm "${pacotes[@]}"
      else echo 'Não encontrei sudo; execute como administrador:' >&2; printf '  sudo pacman -Sy --needed --noconfirm %q ' "${pacotes[@]}"; echo >&2; return 1; fi ;;
    apk)
      if ((EUID == 0)); then apk add "${pacotes[@]}"
      elif command -v sudo >/dev/null 2>&1; then sudo apk add "${pacotes[@]}"
      else echo 'Não encontrei sudo; execute como administrador:' >&2; printf '  sudo apk add %q ' "${pacotes[@]}"; echo >&2; return 1; fi ;;
    brew) brew install "${pacotes[@]}" ;;
    pkg) pkg install -y "${pacotes[@]}" ;;
    *)
      echo 'Não encontrei um gerenciador de pacotes compatível.' >&2
      echo "Instale manualmente: ${faltam[*]}" >&2
      return 1 ;;
  esac
}

if ((${#faltam[@]})); then instalar_pacotes; fi

# Opcional: com o aerc, o w3m mostra e-mails em HTML bem (tabelas, cores, links). Se não der para
# instalar, segue: o tt usa o lynx ou o conversor próprio.
if command -v aerc >/dev/null 2>&1 && ! command -v w3m >/dev/null 2>&1; then
  faltam=(w3m); instalar_pacotes >/dev/null 2>&1 || echo "Aviso: não consegui instalar o w3m (opcional); e-mails em HTML usarão outro conversor." >&2
fi

faltam=()
for c in "${necessarios[@]}"; do command -v "$c" >/dev/null 2>&1 || faltam+=("$c"); done
if ((${#faltam[@]})); then
  echo "Ainda faltam dependências após a instalação: ${faltam[*]}" >&2
  exit 1
fi

ver() { "$1" "$2" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1; }
antigo() { [[ $(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1) != "$2" ]]; }
t=$(ver tmux -V); f=$(ver fzf --version)
antigo "${t:-0}" 3.4 && echo "Aviso: tmux $t é mais antigo que o recomendado (3.4); algumas funções podem falhar."
antigo "${f:-0}" 0.60 && echo "Aviso: fzf $f é mais antigo que o recomendado (0.60); a central pode não abrir direito."

./tt --instalar "$@"
