#!/usr/bin/env bash
# Instala o tt neste usuário em um passo: dependências, tt, ~/.tmux.conf e abertura automática
# no tmux (bloco no ~/.bashrc). Uso: ./instalar.sh [nome-desta-máquina]
# Só o bashrc: ./tt --configurar-bashrc   (desfazer: ./tt --remover-bashrc)
# Verificar/instalar as dependências é feito antes da instalação do tt.
#
# Roda em Linux (Debian/Ubuntu/WSL, Fedora/RHEL, openSUSE, Arch, Alpine, Void), macOS (Homebrew), Termux,
# Linux dentro do proot do Termux e FreeBSD/OpenBSD/NetBSD. A detecção do sistema, os nomes dos pacotes e a
# instalação robusta vêm do pacotes-tt.sh, o mesmo que o tt usa depois (tt --pendencias).

# O macOS traz o bash 3.2, velho demais para o tt (arrays associativos, mapfile). Se o Homebrew existe,
# instala o bash novo e recomeça com ele; sem Homebrew, explica como instalar. (Esta parte só usa sintaxe
# do bash 3.2, para poder rodar antes de tudo.)
if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew "$(command -v brew 2>/dev/null)"; do
    [ -n "$b" ] && [ -x "$b" ] && { BREW=$b; break; }
  done
  if [ -n "${BREW:-}" ]; then
    echo "O bash deste sistema é o ${BASH_VERSION}; instalando o bash atual pelo Homebrew…"
    "$BREW" install bash || exit 1
    NOVO_BASH="$("$BREW" --prefix)/bin/bash"
    exec "$NOVO_BASH" "$0" "$@"
  fi
  echo "O tt precisa do bash 4 ou mais novo (este é o ${BASH_VERSION})." >&2
  echo "No macOS, instale o Homebrew (https://brew.sh) e rode ./instalar.sh de novo; ele instala o bash." >&2
  exit 1
fi

set -euo pipefail
cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"

# shellcheck source=pacotes-tt.sh
source ./pacotes-tt.sh

necessarios=(bash git tmux fzf python3 ssh tar rg)
opcionais=(w3m curl unzip mbsync)

faltam_de() { # lista os comandos que faltam entre os dados
  local c; for c in "$@"; do command -v "$c" >/dev/null 2>&1 || printf '%s\n' "$c"; done
}

gerenciador=$(pk_gerenciador 2>/dev/null) || gerenciador=""
priv=$(pk_privilegio "$gerenciador" 2>/dev/null) || priv=indisponivel

echo "Sistema: $(pk_resumo)"

# instalar_pacotes comando… — instala o que falta com o gerenciador do sistema. Devolve 0 se instalou tudo.
instalar_pacotes() {
  local -a itens=("$@")
  ((${#itens[@]})) || return 0
  printf 'Dependências ausentes: %s\n' "${itens[*]}"
  if [[ -z $gerenciador ]]; then
    case "$(pk_so)" in
      macos) echo "Instale o Homebrew (https://brew.sh) e rode ./instalar.sh de novo." >&2 ;;
      *) echo 'Não encontrei um gerenciador de pacotes compatível.' >&2 ;;
    esac
    echo "Instale à mão: ${itens[*]}" >&2
    return 1
  fi
  pk_resolver "$gerenciador" "${itens[@]}"
  ((${#PK_NO_SISTEMA[@]})) && echo "(vêm com o sistema, mas não estão no PATH: ${PK_NO_SISTEMA[*]})" >&2
  ((${#PK_SEM_PACOTE[@]})) && echo "Sem pacote em $gerenciador para: ${PK_SEM_PACOTE[*]} (instale por outro meio)." >&2
  ((${#PK_PACOTES[@]})) || return 1
  if [[ $priv == indisponivel ]]; then
    echo 'Não encontrei sudo, doas nem su, e você não é administrador. Peça a quem administra, ou rode como root:' >&2
    echo "  $(pk_comando_texto "$gerenciador" nenhum "${PK_PACOTES[@]}")" >&2
    return 1
  fi
  pk_instalar "$gerenciador" "$priv" "${PK_PACOTES[@]}"
}

mapfile -t faltam < <(faltam_de "${necessarios[@]}")
if ((${#faltam[@]})); then
  instalar_pacotes "${faltam[@]}" || true
fi

# Opcionais que completam a primeira instalação: w3m (e-mails em HTML), curl/unzip (navegadores de links) e
# mbsync/isync (sync local do e-mail). Quem instala agora já leva tudo; se algo falhar, o tt pede depois o
# que fizer falta, num modal único (tt --pedir-sudo, ou menu administrar → 📦 Pendências).
mapfile -t faltam < <(faltam_de "${opcionais[@]}")
if ((${#faltam[@]})); then
  instalar_pacotes "${faltam[@]}" >/dev/null 2>&1 || echo "Aviso: não consegui instalar ${faltam[*]} (opcionais); o tt pede depois o que fizer falta, num modal." >&2
fi

mapfile -t faltam < <(faltam_de "${necessarios[@]}")
if ((${#faltam[@]})); then
  echo "Ainda faltam dependências após a instalação: ${faltam[*]}" >&2
  exit 1
fi

ver() { "$1" "$2" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1; }
antigo() { [[ $(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n | head -1) != "$2" ]]; }
t=$(ver tmux -V); f=$(ver fzf --version)
antigo "${t:-0}" 3.4 && echo "Aviso: tmux $t é mais antigo que o recomendado (3.4); algumas funções podem falhar (tt --pendencias explica)."
antigo "${f:-0}" 0.60 && echo "Aviso: fzf $f é mais antigo que o recomendado (0.60); o tt baixa o fzf atual para a sua pasta na primeira vez que você aceitar a pendência (tt --pedir-sudo fzf-novo)."

./tt --instalar "$@"

# Opcional: nomeador local de abas (modelo open source leve que roda só nesta máquina, sem conta).
# Baixa uma vez (~1–2,5 GB, conforme a memória); dá para fazer depois pelo menu ⋯ → 🧠 Nomeador de abas.
if [[ -t 0 ]] && sug=$(python3 -I ./nomeador-local.py estado 2>/dev/null | sed -n 's/^sugerido=//p') && [[ -n $sug ]]; then
  read -r -p "Instalar o nomeador local de abas (modelo $sug, roda só aqui, sem conta)? (s/N) " r
  [[ $r == [sSyY]* ]] && "$HOME/.local/bin/tt" --nomeador-local instalar "$sug" || true
fi
