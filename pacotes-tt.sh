#!/usr/bin/env bash
# pacotes-tt.sh — plataforma, gerenciadores de pacotes e instalação robusta, compartilhados pelo `tt`
# e pelo `instalar.sh`. É carregado com `source`: só define funções (prefixo pk_) e variáveis PK_*, não
# escreve nada na tela nem sai do shell de quem o carregou.
#
# Detecção (pk_so, pk_ambiente, pk_gerenciador, pk_privilegio…) usa só bash 3.2 (macOS puro, ssh em
# máquina remota); a instalação usa arrays (bash 4+, que o tt já exige).
#
# Plataformas tratadas: Linux (Debian/Ubuntu/WSL, Fedora/RHEL, openSUSE, Arch, Alpine, Void),
# macOS (Homebrew), Termux (pkg), Linux dentro do proot do Termux (Debian como root), FreeBSD
# (pkg-bsd), OpenBSD (pkg_add), NetBSD (pkgin). Em qualquer outra, o tt mostra o que falta e diz que
# a instalação é à mão.
#
# Ganchos de teste (nunca usados em produção): TT_SO, TT_ARCH, TT_AMBIENTE, TT_LIBC, TT_GERENCIADOR,
# TT_PRIV, TT_OS_RELEASE, TT_PK_LOG.

# --- Plataforma --------------------------------------------------------------------------------

pk_so() { # linux | macos | freebsd | dragonfly | openbsd | netbsd | outro
  case ${TT_SO:-$(uname -s 2>/dev/null)} in
    Linux|linux) echo linux ;;
    Darwin|macos) echo macos ;;
    FreeBSD|freebsd) echo freebsd ;;
    DragonFly*|dragonfly) echo dragonfly ;;
    OpenBSD|openbsd) echo openbsd ;;
    NetBSD|netbsd) echo netbsd ;;
    *) echo outro ;;
  esac
}

pk_arch() { # x86_64 | aarch64 | armv7 | …
  local a=${TT_ARCH:-$(uname -m 2>/dev/null)}
  case $a in
    amd64|x86_64) echo x86_64 ;;
    arm64|aarch64) echo aarch64 ;;
    armv7*|armhf) echo armv7 ;;
    *) echo "$a" ;;
  esac
}

# termux | proot (Linux de verdade rodando sobre o kernel do Android, como o Debian do proot-distro) |
# wsl | nativo. O PREFIX do Termux é sinal explícito; o proot não tem PREFIX, mas o kernel diz android.
pk_ambiente() {
  if [[ -n ${TT_AMBIENTE:-} ]]; then echo "$TT_AMBIENTE"; return 0; fi
  if [[ ${PREFIX:-} == *com.termux* ]]; then echo termux
  elif grep -qi microsoft /proc/version 2>/dev/null; then echo wsl
  elif [[ $(pk_so) == linux ]] && { grep -qi android /proc/version 2>/dev/null || uname -r 2>/dev/null | grep -qi android; }; then echo proot
  else echo nativo; fi
}

# "id|id_like|versão|nome bonito" de /etc/os-release (vazio se não houver). O separador não pode ser
# espaço em branco (tab): o `read` colapsaria os campos vazios (Debian não tem ID_LIKE).
pk_os_release() {
  local f=${TT_OS_RELEASE:-/etc/os-release}
  [[ -r $f ]] || f=/usr/lib/os-release
  [[ -r $f ]] || return 1
  ( ID=""; ID_LIKE=""; VERSION_ID=""; PRETTY_NAME=""
    # shellcheck disable=SC1090
    . "$f" 2>/dev/null
    printf '%s|%s|%s|%s\n' "${ID:-}" "${ID_LIKE:-}" "${VERSION_ID:-}" "${PRETTY_NAME:-}" )
}

pk_libc() { # glibc | musl | bionic | outra
  if [[ -n ${TT_LIBC:-} ]]; then echo "$TT_LIBC"; return 0; fi
  [[ $(pk_so) == linux ]] || { echo outra; return 0; }
  [[ $(pk_ambiente) == termux ]] && { echo bionic; return 0; }
  if compgen -G '/lib/ld-musl-*' >/dev/null 2>&1 || compgen -G '/usr/lib/ld-musl-*' >/dev/null 2>&1; then echo musl; else echo glibc; fi
}

# Binário de cada gerenciador (xbps e o pkg do Termux/FreeBSD têm nomes diferentes do rótulo).
pk_ger_bin() {
  case $1 in
    xbps) echo xbps-install ;;
    pkg|pkg-bsd) echo pkg ;;
    *) echo "$1" ;;
  esac
}

# Gerenciador de pacotes desta máquina: apt-get | dnf | yum | zypper | pacman | apk | xbps | brew |
# pkg (Termux) | pkg-bsd (FreeBSD) | pkg_add (OpenBSD) | pkgin (NetBSD). Vazio (rc 1) se não achar.
# Em Linux com mais de um instalado (Fedora com brew, Debian com nix…), a família da distro manda.
pk_gerenciador() {
  if [[ -n ${TT_GERENCIADOR:-} ]]; then echo "$TT_GERENCIADOR"; return 0; fi
  local so amb; so=$(pk_so); amb=$(pk_ambiente)
  if [[ $amb == termux ]]; then
    command -v pkg >/dev/null 2>&1 && { echo pkg; return 0; }
    return 1
  fi
  case $so in
    macos)
      command -v brew >/dev/null 2>&1 && { echo brew; return 0; }
      [[ -x /opt/homebrew/bin/brew || -x /usr/local/bin/brew ]] && { echo brew; return 0; }
      return 1 ;;
    freebsd|dragonfly) command -v pkg >/dev/null 2>&1 && { echo pkg-bsd; return 0; }; return 1 ;;
    openbsd) command -v pkg_add >/dev/null 2>&1 && { echo pkg_add; return 0; }; return 1 ;;
    netbsd) command -v pkgin >/dev/null 2>&1 && { echo pkgin; return 0; }; return 1 ;;
  esac
  local id="" like="" resto g ordem
  { IFS='|' read -r id like resto; } < <(pk_os_release 2>/dev/null) || true
  case " $id $like " in
    *" debian "*|*" ubuntu "*) ordem="apt-get dnf zypper pacman apk xbps yum" ;;
    *" fedora "*|*" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*|*" amzn "*) ordem="dnf yum zypper apt-get pacman apk xbps" ;;
    *" suse "*|*" opensuse "*|*" opensuse-tumbleweed "*|*" opensuse-leap "*|*" sles "*) ordem="zypper dnf apt-get pacman apk xbps yum" ;;
    *" arch "*) ordem="pacman apt-get dnf zypper apk xbps yum" ;;
    *" alpine "*) ordem="apk apt-get dnf zypper pacman xbps yum" ;;
    *" void "*) ordem="xbps apt-get dnf zypper pacman apk yum" ;;
    *) ordem="apt-get dnf zypper pacman apk xbps yum" ;;
  esac
  for g in $ordem; do
    command -v "$(pk_ger_bin "$g")" >/dev/null 2>&1 && { echo "$g"; return 0; }
  done
  # Último recurso: Linuxbrew (distros sem gerenciador próprio, como as imutáveis).
  command -v brew >/dev/null 2>&1 && { echo brew; return 0; }
  return 1
}

# Linha curta para a tela: "Ubuntu 24.04 LTS · WSL · x86_64 · apt-get · sudo".
pk_resumo() {
  local nome="" a b c ger priv amb
  { IFS='|' read -r a b c nome; } < <(pk_os_release 2>/dev/null) || true
  [[ -n $nome ]] || nome=$(uname -sr 2>/dev/null)
  amb=$(pk_ambiente); ger=$(pk_gerenciador 2>/dev/null) || ger="sem gerenciador"
  priv=$(pk_privilegio "$ger" 2>/dev/null)
  case $amb in termux) nome="Termux (Android)" ;; wsl) nome="$nome · WSL" ;; proot) nome="$nome · proot do Termux" ;; esac
  printf '%s · %s · %s · %s' "$nome" "$(pk_arch)" "$ger" "${priv:-?}"
}

# --- Privilégio --------------------------------------------------------------------------------
# nenhum (já é root, ou o gerenciador roda como usuário: brew, pkg do Termux) | sudo | doas | su |
# indisponivel. O brew recusa rodar como root; o Termux não tem root.

pk_privilegio() {
  if [[ -n ${TT_PRIV:-} ]]; then echo "$TT_PRIV"; return 0; fi
  local ger=${1:-$(pk_gerenciador 2>/dev/null)}
  case $ger in brew|pkg) echo nenhum; return 0 ;; esac
  if (( ${EUID:-$(id -u)} == 0 )); then echo nenhum
  elif command -v sudo >/dev/null 2>&1; then echo sudo
  elif command -v doas >/dev/null 2>&1; then echo doas
  elif command -v su >/dev/null 2>&1; then echo su
  else echo indisponivel; fi
}

# A escalada funciona agora sem pedir senha? (vigia e scripts só agem assim)
pk_sem_senha() {
  case $1 in
    nenhum) return 0 ;;
    sudo) sudo -n true 2>/dev/null ;;
    doas) doas -n true 2>/dev/null ;;
    *) return 1 ;;
  esac
}

# pk_priv_exec PRIV cmd args… — roda com o privilégio dado. A senha, quando pedida, é lida pelo próprio
# sudo/doas/su no terminal: o tt nunca a vê.
pk_priv_exec() {
  local p=$1; shift
  case $p in
    nenhum) "$@" ;;
    sudo) sudo "$@" ;;
    doas) doas "$@" ;;
    su) su -c "$(printf '%q ' "$@")" ;;
    *) return 127 ;;
  esac
}

# --- Nomes de pacote por gerenciador ------------------------------------------------------------
# lógico | apt | dnf/yum | zypper | pacman | apk | xbps | brew | termux | freebsd | openbsd | netbsd
#   =  mesmo nome do lógico     -  não há pacote     ~  já vem com o sistema
#   a+b  vários pacotes
# Todos os nomes foram conferidos nos repositórios reais (Debian 12/13, Ubuntu 22.04/24.04, Fedora,
# openSUSE Tumbleweed, Arch, Alpine, Void, Termux; FreeBSD/OpenBSD/NetBSD/Homebrew pelo Repology).
PK_TABELA=$(cat <<'EOF'
bash|=|=|=|=|=|=|=|=|=|=|=
tmux|=|=|=|=|=|=|=|=|=|~|=
fzf|=|=|=|=|=|=|=|=|=|=|=
python3|=|=|=|python|=|=|python@3.13|python|=|python%3|python313
ssh|openssh-client|openssh-clients|openssh-clients|openssh|openssh-client|openssh|openssh|openssh|~|~|~
tar|=|=|=|=|=|=|gnu-tar|=|gtar|gtar|gtar
rg|ripgrep|ripgrep|ripgrep|ripgrep|ripgrep|ripgrep|ripgrep|ripgrep|ripgrep|ripgrep|ripgrep
git|=|=|=|=|=|=|=|=|=|=|=
curl|=|=|=|=|=|=|=|=|=|=|=
unzip|=|=|=|=|=|=|=|=|=|=|=
aerc|=|=|=|=|=|=|=|=|=|=|=
mbsync|isync|isync|isync|isync|isync|isync|isync|isync|isync|isync|isync
w3m|=|=|=|=|=|=|=|=|=|=|=
vim|=|vim-enhanced|=|=|=|=|=|=|=|=|=
wl-copy|wl-clipboard|wl-clipboard|wl-clipboard|wl-clipboard|wl-clipboard|wl-clipboard|-|-|wl-clipboard|wl-clipboard|wl-clipboard
xclip|=|=|=|=|=|=|-|-|=|=|=
notify-send|libnotify-bin|libnotify|libnotify-tools|libnotify|libnotify|libnotify|-|-|libnotify|libnotify|libnotify
xdg-open|xdg-utils|xdg-utils|xdg-utils|xdg-utils|xdg-utils|xdg-utils|-|-|xdg-utils|xdg-utils|xdg-utils
pv|=|=|=|=|=|=|=|=|=|=|=
mosh|=|=|=|=|=|=|=|=|=|=|=
qrencode|qrencode|qrencode|qrencode|qrencode|libqrencode-tools|qrencode|qrencode|libqrencode|libqrencode|libqrencode|qrencode
termux-api|-|-|-|-|-|-|-|termux-api|-|-|-
cc|gcc|gcc|gcc|gcc|gcc|base-devel|~|clang|~|~|~
libc-dev|libc6-dev|glibc-devel|glibc-devel|~|musl-dev|~|~|~|~|~|~
make|=|=|=|=|=|=|~|=|gmake|gmake|gmake
perl|=|=|=|=|=|=|~|=|perl5|~|=
pkg-config|pkg-config|pkgconf-pkg-config|pkg-config|pkgconf|pkgconf|pkgconf|pkgconf|pkg-config|pkgconf|pkgconf|pkgconf
sasl-dev|libsasl2-dev|cyrus-sasl-devel|cyrus-sasl-devel|libsasl|cyrus-sasl-dev|libsasl-devel|cyrus-sasl|libsasl|cyrus-sasl|cyrus-sasl|cyrus-sasl
ssl-dev|libssl-dev|openssl-devel|libopenssl-devel|openssl|openssl-dev|openssl-devel|openssl@3|openssl|~|~|openssl
zlib-dev|zlib1g-dev|zlib-devel|zlib-devel|zlib|zlib-dev|zlib-devel|~|zlib|~|~|zlib
fonts-liberation|fonts-liberation|liberation-fonts|liberation-fonts|ttf-liberation|-|liberation-fonts-ttf|-|-|-|-|-
EOF
)

# Bibliotecas que o Chrome e o Carbonyl baixados pedem (o ldd diz o nome do arquivo, não do pacote).
# soname | apt | dnf/yum | zypper | pacman | xbps
PK_TABELA_LIBS=$(cat <<'EOF'
libX11.so.6|libx11-6|libX11|libX11-6|libx11|libX11
libXcomposite.so.1|libxcomposite1|libXcomposite|libXcomposite1|libxcomposite|libXcomposite
libXdamage.so.1|libxdamage1|libXdamage|libXdamage1|libxdamage|libXdamage
libXext.so.6|libxext6|libXext|libXext6|libxext|libXext
libXfixes.so.3|libxfixes3|libXfixes|libXfixes3|libxfixes|libXfixes
libXrandr.so.2|libxrandr2|libXrandr|libXrandr2|libxrandr|libXrandr
libasound.so.2|libasound2|alsa-lib|libasound2|alsa-lib|alsa-lib
libatk-1.0.so.0|libatk1.0-0|atk|libatk-1_0-0|at-spi2-core|atk
libatk-bridge-2.0.so.0|libatk-bridge2.0-0|at-spi2-atk|libatk-bridge-2_0-0|at-spi2-core|at-spi2-atk
libatspi.so.0|libatspi2.0-0|at-spi2-core|libatspi0|at-spi2-core|at-spi2-core
libcairo.so.2|libcairo2|cairo|libcairo2|cairo|cairo
libcups.so.2|libcups2|cups-libs|libcups2|libcups|libcups
libdbus-1.so.3|libdbus-1-3|dbus-libs|libdbus-1-3|dbus|dbus-libs
libexpat.so.1|libexpat1|expat|libexpat1|expat|expat
libgbm.so.1|libgbm1|mesa-libgbm|libgbm1|mesa|libgbm
libgio-2.0.so.0|libglib2.0-0|glib2|libgio-2_0-0|glib2|glib
libglib-2.0.so.0|libglib2.0-0|glib2|libglib-2_0-0|glib2|glib
libgobject-2.0.so.0|libglib2.0-0|glib2|libgobject-2_0-0|glib2|glib
libnspr4.so|libnspr4|nspr|mozilla-nspr|nspr|nspr
libnss3.so|libnss3|nss|mozilla-nss|nss|nss
libnssutil3.so|libnss3|nss-util|mozilla-nss|nss|nss
libsmime3.so|libnss3|nss|mozilla-nss|nss|nss
libssl3.so|libnss3|nss|mozilla-nss|nss|nss
libpango-1.0.so.0|libpango-1.0-0|pango|libpango-1_0-0|pango|pango
libxcb.so.1|libxcb1|libxcb|libxcb1|libxcb|libxcb
libxkbcommon.so.0|libxkbcommon0|libxkbcommon|libxkbcommon0|libxkbcommon|libxkbcommon
libgtk-3.so.0|libgtk-3-0|gtk3|libgtk-3-0|gtk3|gtk+3
libvulkan.so.1|libvulkan1|vulkan-loader|libvulkan1|vulkan-icd-loader|vulkan-loader
libudev.so.1|libudev1|systemd-libs|libudev1|systemd-libs|libudev
libdrm.so.2|libdrm2|libdrm|libdrm2|libdrm|libdrm
EOF
)

pk_coluna() { # gerenciador → número da coluna em PK_TABELA
  case $1 in
    apt-get) echo 2 ;; dnf|yum) echo 3 ;; zypper) echo 4 ;; pacman) echo 5 ;; apk) echo 6 ;; xbps) echo 7 ;;
    brew) echo 8 ;; pkg) echo 9 ;; pkg-bsd) echo 10 ;; pkg_add) echo 11 ;; pkgin) echo 12 ;;
    *) return 1 ;;
  esac
}

# Conteúdo cru da célula (lógico não listado = "=": o próprio nome do pacote).
pk_celula() { # gerenciador lógico
  local c; c=$(pk_coluna "$1") || return 1
  printf '%s\n' "$PK_TABELA" | awk -F'|' -v l="$2" -v c="$c" '
    $1 == l { found = 1; v = $c; if (v == "=") v = l; print v; exit }
    END { if (!found) print l }'
}

pk_apt_candidato() { # o apt tem versão instalável deste nome?
  local c; c=$(apt-cache policy "$1" 2>/dev/null | sed -n 's/^ *Candidate: //p')
  [[ -n $c && $c != '(none)' ]]
}

# apt: depois da transição t64 (Debian 13, Ubuntu 24.04) vários nomes ganharam "t64"; o nome antigo
# vira virtual e não instala. Usa o nome que tiver candidato.
pk_resolver_nome() { # gerenciador nome
  if [[ $1 == apt-get ]] && command -v apt-cache >/dev/null 2>&1; then
    if ! pk_apt_candidato "$2" && pk_apt_candidato "${2}t64"; then echo "${2}t64"; return 0; fi
  fi
  echo "$2"
}

# pk_resolver GER lógico… — preenche PK_PACOTES (nomes finais, sem repetir), PK_SEM_PACOTE (lógicos que
# este gerenciador não oferece) e PK_NO_SISTEMA (lógicos que já deveriam vir com o sistema).
pk_resolver() {
  local ger=$1 l v n; shift
  PK_PACOTES=(); PK_SEM_PACOTE=(); PK_NO_SISTEMA=()
  for l in "$@"; do
    [[ $l == - || -z $l ]] && continue
    v=$(pk_celula "$ger" "$l") || { PK_SEM_PACOTE+=("$l"); continue; }
    case $v in
      -) PK_SEM_PACOTE+=("$l") ;;
      '~') PK_NO_SISTEMA+=("$l") ;;
      *)
        for n in ${v//+/ }; do
          n=$(pk_resolver_nome "$ger" "$n")
          case " ${PK_PACOTES[*]-} " in *" $n "*) ;; *) PK_PACOTES+=("$n") ;; esac
        done ;;
    esac
  done
}

# Pacote de uma biblioteca (soname). Fora da tabela, dnf/yum/zypper/apk instalam por capability
# ("libfoo.so.1()(64bit)", "so:libfoo.so.1"), o que cobre bibliotecas que o Chrome passe a pedir.
pk_pacote_lib() { # gerenciador soname → nome (rc 1 se não houver como)
  local ger=$1 s=$2 c v
  case $ger in apt-get) c=2 ;; dnf|yum) c=3 ;; zypper) c=4 ;; pacman) c=5 ;; xbps) c=6 ;; apk) c=0 ;; *) return 1 ;; esac
  if (( c > 0 )); then
    v=$(printf '%s\n' "$PK_TABELA_LIBS" | awk -F'|' -v s="$s" -v c="$c" '$1 == s { print $c; exit }')
    [[ -z $v ]] && v=$(printf '%s\n' "$PK_TABELA_LIBS" | awk -F'|' -v s="${s%%.so*}.so" -v c="$c" 'index($1, s) == 1 { print $c; exit }')
    if [[ -n $v ]]; then pk_resolver_nome "$ger" "$v"; return 0; fi
  fi
  case $ger in
    dnf|yum|zypper) [[ $(pk_arch) == x86_64 || $(pk_arch) == aarch64 ]] && { echo "$s()(64bit)"; return 0; }; echo "$s"; return 0 ;;
    apk) echo "so:$s"; return 0 ;;
  esac
  return 1
}

# --- Comandos de cada gerenciador ----------------------------------------------------------------

pk_cmd_instalar() { # gerenciador → palavras do comando (para mostrar e para montar o real)
  case $1 in
    apt-get) echo "apt-get install -y" ;;
    dnf) echo "dnf install -y" ;;
    yum) echo "yum install -y" ;;
    zypper) echo "zypper --non-interactive install" ;;
    pacman) echo "pacman -S --needed --noconfirm" ;;
    apk) echo "apk add" ;;
    xbps) echo "xbps-install -y" ;;
    brew) echo "brew install" ;;
    pkg|pkg-bsd) echo "pkg install -y" ;;
    pkg_add) echo "pkg_add" ;;
    pkgin) echo "pkgin -y install" ;;
    *) return 1 ;;
  esac
}

# Comando completo como o usuário o digitaria (com sudo/doas/su na frente), só para mostrar.
pk_comando_texto() { # gerenciador privilégio pacote…
  local ger=$1 priv=$2; shift 2
  local base; base=$(pk_cmd_instalar "$ger") || return 1
  case $priv in
    sudo|doas) printf '%s %s %s' "$priv" "$base" "$*" ;;
    su) printf "su -c '%s %s'" "$base" "$*" ;;
    *) printf '%s %s' "$base" "$*" ;;
  esac
}

# Ambiente sem perguntas para cada gerenciador (passado por `env`, porque sudo/doas/su o descartam).
pk_ambiente_instalacao() {
  case $1 in
    apt-get) echo "DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a" ;;
    pkg-bsd) echo "ASSUME_ALWAYS_YES=yes" ;;
    brew) echo "HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1" ;;
  esac
}

# argv completo do "instalar" (um argumento por linha), com as opções que o tornam robusto:
# apt espera a trava do dpkg (outro apt rodando) em vez de falhar, e no proot do Android não tenta
# largar privilégio para o usuário _apt (o proot não deixa).
pk_argv_instalar() { # gerenciador pacote…
  local ger=$1 e; shift
  local -a pre=()
  for e in $(pk_ambiente_instalacao "$ger"); do pre+=("$e"); done
  ((${#pre[@]})) && { printf '%s\n' env "${pre[@]}"; }
  case $ger in
    apt-get)
      printf '%s\n' apt-get -y -o DPkg::Lock::Timeout=120
      [[ $(pk_ambiente) == proot ]] && printf '%s\n' -o APT::Sandbox::User=root
      printf '%s\n' install "$@" ;;
    zypper) printf '%s\n' zypper --non-interactive install --auto-agree-with-licenses "$@" ;;
    *) local w; for w in $(pk_cmd_instalar "$ger"); do printf '%s\n' "$w"; done; printf '%s\n' "$@" ;;
  esac
}

pk_argv_atualizar() { # gerenciador → índices de pacotes
  local ger=$1 e
  local -a pre=()
  for e in $(pk_ambiente_instalacao "$ger"); do pre+=("$e"); done
  ((${#pre[@]})) && { printf '%s\n' env "${pre[@]}"; }
  case $ger in
    apt-get) printf '%s\n' apt-get -o DPkg::Lock::Timeout=120 update ;;
    dnf) printf '%s\n' dnf makecache ;;
    yum) printf '%s\n' yum makecache ;;
    zypper) printf '%s\n' zypper --non-interactive refresh ;;
    pacman) printf '%s\n' pacman -Sy --noconfirm ;;
    apk) printf '%s\n' apk update ;;
    xbps) printf '%s\n' xbps-install -S -y ;;
    brew) printf '%s\n' brew update ;;
    pkg) printf '%s\n' pkg update -y ;;
    pkg-bsd) printf '%s\n' pkg update -f ;;
    pkgin) printf '%s\n' pkgin -y update ;;
    *) return 1 ;;
  esac
}

# --- Execução robusta ---------------------------------------------------------------------------

PK_LOG=${TT_PK_LOG:-$HOME/.cache/tt/pendencias.log}
PK_PACOTES=(); PK_SEM_PACOTE=(); PK_NO_SISTEMA=(); PK_OK=(); PK_FALHOS=(); PK_MOTIVO=""

pk_log() { mkdir -p "${PK_LOG%/*}" 2>/dev/null; printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$PK_LOG" 2>/dev/null; return 0; }

# O índice do apt está vazio (máquina recém-criada, WSL novo)? Sem ele nenhum pacote tem candidato.
pk_apt_sem_indice() { ! compgen -G '/var/lib/apt/lists/*_Packages*' >/dev/null 2>&1 && ! compgen -G '/var/lib/apt/lists/*_Packages.*' >/dev/null 2>&1; }

# Roda um comando de gerenciador com privilégio, mostrando a saída e guardando-a no log e num arquivo
# para o diagnóstico. Devolve o código do comando. PK_MOTIVO diz por que falhou quando dá para saber.
pk_rodar() { # privilégio argv…
  local priv=$1; shift
  local out rc; out=$(mktemp "${TMPDIR:-/tmp}/tt-pk.XXXXXX") || return 1
  pk_log "\$ [$priv] $*"
  pk_priv_exec "$priv" "$@" 2>&1 | tee -a "$out" >&2
  rc=${PIPESTATUS[0]}
  { tail -n 25 "$out" | sed 's/^/    | /' >>"$PK_LOG"; } 2>/dev/null
  PK_MOTIVO=""
  if (( rc != 0 )); then
    if grep -qiE 'incorrect password|a password is required|no tty present|not in the sudoers|is not allowed to run sudo|Authentication failure|doas: .*(authentication|permission)|Permission denied.*(dpkg|lock)' "$out"; then PK_MOTIVO=permissao
    elif grep -qiE 'Could not resolve|Temporary failure in name resolution|Failed to fetch|Could not connect|Connection (refused|timed out)|Network is unreachable|failed to retrieve|Unable to connect|curl: \(6\)|curl: \(7\)' "$out"; then PK_MOTIVO=rede
    elif grep -qiE 'Unable to locate package|has no installation candidate|No match for argument|no package.*found|target not found|unable to select package|Package .* not found|nothing provides|not found in repositor|No packages? (found|matching)' "$out"; then PK_MOTIVO=indice_ou_nome
    fi
  fi
  rm -f "$out"
  return "$rc"
}

pk_instalar_lote() { # gerenciador privilégio pacote…
  local ger=$1 priv=$2; shift 2
  local -a argv=()
  mapfile -t argv < <(pk_argv_instalar "$ger" "$@")
  pk_rodar "$priv" "${argv[@]}"
}

pk_atualizar_indice() { # gerenciador privilégio
  local -a argv=()
  mapfile -t argv < <(pk_argv_atualizar "$1") || return 1
  ((${#argv[@]})) || return 1
  pk_rodar "$2" "${argv[@]}"
}

# pk_instalar GER PRIV pacote… — instala o lote; se falhar, atualiza os índices e repete; se ainda
# falhar, tenta um a um, para um nome inexistente nesta distro não derrubar os demais. Preenche PK_OK e
# PK_FALHOS; devolve 0 só se tudo ficou instalado. Sem permissão (senha errada), para na hora.
pk_instalar() {
  local ger=$1 priv=$2; shift 2
  PK_OK=(); PK_FALHOS=(); PK_MOTIVO=""
  (($#)) || return 0
  local -a todos=("$@")
  pk_log "instalar (${ger}, ${priv}, $(pk_ambiente)): ${todos[*]}"
  # Máquina nova: sem índice o apt não acha nada; atualiza antes e resolve os nomes t64 de novo.
  if [[ $ger == apt-get ]] && pk_apt_sem_indice; then
    pk_atualizar_indice "$ger" "$priv" || true
    local -a novos=() p
    for p in "${todos[@]}"; do novos+=("$(pk_resolver_nome "$ger" "${p%t64}")"); done
    todos=("${novos[@]}")
  fi
  if pk_instalar_lote "$ger" "$priv" "${todos[@]}"; then PK_OK=("${todos[@]}"); return 0; fi
  [[ $PK_MOTIVO == permissao ]] && { PK_FALHOS=("${todos[@]}"); return 1; }
  if pk_atualizar_indice "$ger" "$priv"; then
    if pk_instalar_lote "$ger" "$priv" "${todos[@]}"; then PK_OK=("${todos[@]}"); return 0; fi
  fi
  [[ $PK_MOTIVO == permissao ]] && { PK_FALHOS=("${todos[@]}"); return 1; }
  if ((${#todos[@]} > 1)); then
    local q motivo=""
    for q in "${todos[@]}"; do
      if pk_instalar_lote "$ger" "$priv" "$q"; then PK_OK+=("$q"); else PK_FALHOS+=("$q"); motivo=$PK_MOTIVO; fi
    done
    PK_MOTIVO=$motivo   # o motivo da última falha, não o do último que deu certo
  else PK_FALHOS=("${todos[@]}"); fi
  ((${#PK_FALHOS[@]} == 0))
}

# --- Download -----------------------------------------------------------------------------------

pk_sha256() { # arquivo → hash
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v sha256 >/dev/null 2>&1; then sha256 -q "$1"
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$1" | sed 's/^.*= *//'
  else return 1; fi
}

# Espaço livre (MB) na pasta onde o arquivo será gravado.
pk_livre_mb() { # pasta
  df -Pk "$1" 2>/dev/null | awk 'NR == 2 { printf "%d", $4 / 1024 }'
}

# pk_baixar URL DESTINO [SHA256] [MB_NECESSARIOS] — baixa com tentativas, confere o sha256 se vier e só
# então move para o destino (nunca deixa arquivo pela metade). Mensagens no stderr; rc 0 = ok.
pk_baixar() {
  local url=$1 dest=$2 sha=${3:-} mb=${4:-0} dir tmp livre
  dir=$(dirname "$dest"); mkdir -p "$dir" || { echo "✗ não consegui criar $dir." >&2; return 1; }
  if (( mb > 0 )); then
    livre=$(pk_livre_mb "$dir")
    if [[ -n $livre ]] && (( livre < mb )); then echo "✗ pouco espaço em $dir: ${livre} MB livres, preciso de ~${mb} MB." >&2; return 1; fi
  fi
  tmp=$(mktemp "$dir/.dl.XXXXXX") || return 1
  if command -v curl >/dev/null 2>&1; then
    local -a prog=(-s -S); [[ -t 2 && -z ${TT_PK_QUIETO:-} ]] && prog=(-#)
    curl -fSL --connect-timeout 15 --retry 3 --retry-delay 2 "${prog[@]}" -m "${TT_PK_TIMEOUT:-1200}" -o "$tmp" "$url" || { rm -f "$tmp"; echo "✗ download falhou: $url" >&2; return 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 30 -t 3 -O "$tmp" "$url" || { rm -f "$tmp"; echo "✗ download falhou: $url" >&2; return 1; }
  else rm -f "$tmp"; echo "✗ preciso do curl (ou wget) para baixar." >&2; return 1; fi
  if [[ -n $sha ]]; then
    local got; got=$(pk_sha256 "$tmp") || { rm -f "$tmp"; echo "✗ sem sha256sum/shasum para conferir o download." >&2; return 1; }
    if [[ $got != "$sha" ]]; then rm -f "$tmp"; echo "✗ sha256 não confere ($url); nada foi instalado." >&2; return 1; fi
  fi
  chmod 644 "$tmp" 2>/dev/null
  mv -f "$tmp" "$dest"
}
