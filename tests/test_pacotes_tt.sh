#!/usr/bin/env bash
# pacotes-tt.sh (plataforma, gerenciadores, nomes de pacote, privilégio e instalação robusta), sem tocar no
# sistema: gerenciadores, sudo e apt-cache de mentira num PATH controlado; o /etc/os-release vem de arquivos.
source "$(dirname "$0")/lib.sh"; isolar
LIB=$RAIZ/pacotes-tt.sh
bash -n "$LIB" || falhou 'pacotes-tt.sh com erro de sintaxe'

# PATH limpo: só os utilitários que a biblioteca usa e o que o teste puser em $B (assim o sudo/apt do
# computador de quem roda o teste não interfere).
B=$T/bin; mkdir -p "$B" "$T/base"
for c in bash sh env cat sed awk grep cut tr sort head tail uname id dirname mktemp date tee rm mkdir mv cp chmod df printf true false sleep wc basename sha256sum timeout; do
  p=$(command -v "$c" 2>/dev/null) && ln -sf "$p" "$T/base/$c"
done
PATH_LIMPO="$B:$T/base"
lib() { env -i HOME="$HOME" TMPDIR="$T" PATH="$PATH_LIMPO" TT_PK_LOG="$T/pk.log" "$@" bash -c "source '$LIB'; $CMD"; }
# lib_com VAR=valor… -- comando: roda o comando com a biblioteca carregada e as variáveis dadas
rodar() { local -a vars=(); while [[ $1 != -- ]]; do vars+=("$1"); shift; done; shift; env -i HOME="$HOME" TMPDIR="$T" PATH="$PATH_LIMPO" TT_PK_LOG="$T/pk.log" "${vars[@]}" bash -c "source '$LIB'; $*"; }
fake() { printf '#!/bin/sh\n%s\n' "$2" >"$B/$1"; chmod +x "$B/$1"; }

# --- 1) Plataforma por variáveis e por /etc/os-release ---------------------------------------------
[[ $(rodar TT_SO=Darwin -- pk_so) == macos ]] && [[ $(rodar TT_SO=FreeBSD -- pk_so) == freebsd ]] && [[ $(rodar TT_SO=OpenBSD -- pk_so) == openbsd ]] &&
  [[ $(rodar TT_SO=Linux -- pk_so) == linux ]] && [[ $(rodar TT_SO=Plan9 -- pk_so) == outro ]] || falhou 'pk_so'
[[ $(rodar TT_ARCH=arm64 -- pk_arch) == aarch64 && $(rodar TT_ARCH=amd64 -- pk_arch) == x86_64 && $(rodar TT_ARCH=armv7l -- pk_arch) == armv7 ]] || falhou 'pk_arch'
[[ $(rodar TT_AMBIENTE=proot -- pk_ambiente) == proot ]] || falhou 'override do ambiente'
[[ $(rodar PREFIX=/data/data/com.termux/files/usr TT_SO=Linux -- pk_ambiente) == termux ]] || falhou 'Termux pelo PREFIX'
[[ $(rodar TT_SO=Linux TT_AMBIENTE=termux -- pk_libc) == bionic && $(rodar TT_SO=Linux TT_LIBC=musl -- pk_libc) == musl ]] || falhou 'pk_libc'
# proot-distro (Debian dentro do Termux) se anuncia como "PRoot-Distro", não "android": o kernel dele é fingido.
fake uname 'case "$1" in -r) echo 6.17.0-PRoot-Distro ;; *) exec /usr/bin/uname "$@" ;; esac'
[[ $(rodar TT_SO=Linux -- pk_ambiente) == proot ]] || falhou 'proot-distro deveria ser reconhecido pelo uname -r'
rm -f "$B/uname"
[[ $(rodar TT_SO=Linux PROOT_TMP_DIR=/tmp -- pk_ambiente) == proot ]] || falhou 'proot deveria ser reconhecido por PROOT_TMP_DIR'
# O proot do Android não tem /dev/fd: nada na biblioteca pode usar substituição de processo (<(...)).
! grep -v '^[[:space:]]*#' "$LIB" | grep -n '<(' || falhou 'pacotes-tt.sh usa <(...), que o proot do Android não suporta'
passou 'plataforma: sistema, arquitetura, ambiente (Termux/proot/WSL) e libc'

osr() { printf 'ID=%s\nID_LIKE="%s"\nVERSION_ID=1\nPRETTY_NAME="%s 1"\n' "$1" "$2" "$1" >"$T/os-release-$1"; echo "$T/os-release-$1"; }
for g in apt-get dnf yum zypper pacman apk xbps-install brew; do fake "$g" ':'; done
# Todos os gerenciadores presentes: a família da distro decide.
declare -A ESPERADO=( [debian]=apt-get [ubuntu]=apt-get [linuxmint]=apt-get [fedora]=dnf [rhel]=dnf [rocky]=dnf [opensuse-tumbleweed]=zypper
                      [arch]=pacman [manjaro]=pacman [alpine]=apk [void]=xbps )
declare -A FAMILIA=( [debian]="" [ubuntu]="debian" [linuxmint]="ubuntu debian" [fedora]="" [rhel]="fedora" [rocky]="rhel centos fedora" [opensuse-tumbleweed]="opensuse suse"
                     [arch]="" [manjaro]="arch" [alpine]="" [void]="" )
for id in "${!ESPERADO[@]}"; do
  got=$(rodar TT_SO=Linux TT_OS_RELEASE="$(osr "$id" "${FAMILIA[$id]}")" -- pk_gerenciador)
  [[ $got == "${ESPERADO[$id]}" ]] || falhou "$id: esperava ${ESPERADO[$id]}, deu [$got]"
done
passou 'gerenciador pela família da distro (Debian/Ubuntu/Mint, Fedora/RHEL/Rocky, openSUSE, Arch/Manjaro, Alpine, Void), mesmo com vários instalados'

# Só um presente: acha-o; nenhum: falha; o brew serve de último recurso em Linux sem outro.
rm -f "$B"/{apt-get,dnf,yum,zypper,pacman,apk,xbps-install,brew}
fake pacman ':'
[[ $(rodar TT_SO=Linux TT_OS_RELEASE="$(osr debian '')" -- pk_gerenciador) == pacman ]] || falhou 'único gerenciador presente deveria valer'
rm -f "$B/pacman"
rodar TT_SO=Linux TT_OS_RELEASE="$(osr debian '')" -- pk_gerenciador >/dev/null && falhou 'sem gerenciador deveria falhar'
fake brew ':'
[[ $(rodar TT_SO=Linux TT_OS_RELEASE="$(osr debian '')" -- pk_gerenciador) == brew ]] || falhou 'Linuxbrew é o último recurso'
[[ $(rodar TT_SO=Darwin -- pk_gerenciador) == brew ]] || falhou 'macOS usa o brew'
rm -f "$B/brew"
fake pkg ':'
[[ $(rodar TT_SO=FreeBSD -- pk_gerenciador) == pkg-bsd ]] || falhou 'FreeBSD usa o pkg (rótulo pkg-bsd)'
[[ $(rodar TT_SO=Linux TT_AMBIENTE=termux -- pk_gerenciador) == pkg ]] || falhou 'Termux usa o pkg'
fake pkg_add ':'; fake pkgin ':'
[[ $(rodar TT_SO=OpenBSD -- pk_gerenciador) == pkg_add && $(rodar TT_SO=NetBSD -- pk_gerenciador) == pkgin ]] || falhou 'OpenBSD/NetBSD'
rm -f "$B"/{pkg,pkg_add,pkgin}
passou 'gerenciador: único presente, nenhum, Linuxbrew, macOS (brew), Termux/FreeBSD (pkg), OpenBSD (pkg_add), NetBSD (pkgin)'

# --- 2) Privilégio -----------------------------------------------------------------------------------
[[ $(rodar -- pk_privilegio brew) == nenhum && $(rodar -- pk_privilegio pkg) == nenhum ]] || falhou 'brew e o pkg do Termux dispensam privilégio (o brew recusa root)'
[[ $(rodar TT_PRIV=doas -- pk_privilegio apt-get) == doas ]] || falhou 'override do privilégio'
if (( EUID != 0 )); then
  rodar -- pk_privilegio apt-get | grep -qx indisponivel || falhou 'sem sudo/doas/su deveria ser indisponível'
  fake su ':'; [[ $(rodar -- pk_privilegio apt-get) == su ]] || falhou 'su como último recurso'
  fake doas ':'; [[ $(rodar -- pk_privilegio apt-get) == doas ]] || falhou 'doas antes do su'
  fake sudo ':'; [[ $(rodar -- pk_privilegio apt-get) == sudo ]] || falhou 'sudo primeiro'
  rodar -- 'pk_sem_senha sudo' || true
  fake sudo 'exit 1'; rodar -- 'pk_sem_senha sudo' && falhou 'sudo que pede senha não é "sem senha"'
  rm -f "$B"/{sudo,doas,su}
fi
rodar -- 'pk_sem_senha nenhum' || falhou 'privilégio nenhum não pede senha'
[[ $(rodar -- pk_comando_texto apt-get sudo curl unzip) == 'sudo apt-get install -y curl unzip' ]] || falhou 'texto do comando com sudo'
[[ $(rodar -- pk_comando_texto dnf nenhum git) == 'dnf install -y git' ]] || falhou 'texto do comando sem privilégio'
[[ $(rodar -- pk_comando_texto pacman su vim) == "su -c 'pacman -S --needed --noconfirm vim'" ]] || falhou 'texto do comando com su'
[[ $(rodar -- pk_comando_texto zypper doas vim) == 'doas zypper --non-interactive install vim' ]] || falhou 'texto do comando do zypper'
passou 'privilégio: brew/pkg sem, sudo > doas > su, indisponível, "sem senha", texto do comando'

# --- 3) Tabela de nomes ------------------------------------------------------------------------------
n() { rodar -- "pk_resolver $1 $2; printf '%s ' \"\${PK_PACOTES[@]-}\""; }
[[ $(n apt-get 'tmux python3 ssh mbsync vim notify-send') == 'tmux python3 openssh-client isync vim libnotify-bin ' ]] || falhou "apt: $(n apt-get 'tmux python3 ssh mbsync vim notify-send')"
[[ $(n dnf 'python3 ssh vim notify-send pkg-config') == 'python3 openssh-clients vim-enhanced libnotify pkgconf-pkg-config ' ]] || falhou 'dnf'
[[ $(n zypper 'ssh notify-send ssl-dev') == 'openssh-clients libnotify-tools libopenssl-devel ' ]] || falhou 'zypper'
[[ $(n pacman 'python3 ssh sasl-dev') == 'python openssh libsasl ' ]] || falhou 'pacman'
[[ $(n apk 'ssh qrencode cc libc-dev') == 'openssh-client libqrencode-tools gcc musl-dev ' ]] || falhou 'apk'
[[ $(n xbps 'cc sasl-dev ssl-dev') == 'base-devel libsasl-devel openssl-devel ' ]] || falhou 'xbps'
[[ $(n brew 'python3 tar ssl-dev') == 'python@3.13 gnu-tar openssl@3 ' ]] || falhou 'brew'
[[ $(n pkg 'python3 cc sasl-dev termux-api') == 'python clang libsasl termux-api ' ]] || falhou 'Termux'
[[ $(n pkg-bsd 'tar make perl rg') == 'gtar gmake perl5 ripgrep ' ]] || falhou 'FreeBSD'
[[ $(n pkg_add 'python3 make') == 'python%3 gmake ' ]] || falhou 'OpenBSD'
[[ $(n apt-get 'coisa-fora-da-tabela') == 'coisa-fora-da-tabela ' ]] || falhou 'nome fora da tabela vale como está'
passou 'tabela de nomes: apt, dnf, zypper, pacman, apk, xbps, brew, Termux, FreeBSD e OpenBSD'

# "-" = sem pacote; "~" = vem com o sistema; "a+b" = vários; sem repetir
[[ $(rodar -- "pk_resolver brew wl-copy tmux; echo \"\${PK_SEM_PACOTE[*]}|\${PK_PACOTES[*]}\"") == 'wl-copy|tmux' ]] || falhou 'item sem pacote deveria ir para PK_SEM_PACOTE'
[[ $(rodar -- "pk_resolver pkg-bsd ssh; echo \"\${PK_NO_SISTEMA[*]}|\${PK_PACOTES[*]-}\"") == 'ssh|' ]] || falhou 'item do sistema base deveria ir para PK_NO_SISTEMA'
[[ $(rodar -- "pk_resolver apt-get tmux tmux fzf tmux; echo \${#PK_PACOTES[@]}") == 2 ]] || falhou 'pacotes repetidos'
passou 'itens sem pacote, do sistema base e repetidos'

# apt: nomes t64 (Debian 13, Ubuntu 24.04) — o nome antigo é virtual e não instala
fake apt-cache 'case "$2" in libasound2t64|libgtk-3-0t64) echo "  Candidate: 1.2" ;; libasound2|libgtk-3-0) echo "  Candidate: (none)" ;; *) echo "  Candidate: 1.0" ;; esac'
[[ $(rodar -- pk_pacote_lib apt-get libasound.so.2) == libasound2t64 ]] || falhou 't64: libasound2'
[[ $(rodar -- pk_pacote_lib apt-get libgtk-3.so.0) == libgtk-3-0t64 ]] || falhou 't64: gtk'
[[ $(rodar -- pk_pacote_lib apt-get libX11.so.6) == libx11-6 ]] || falhou 'sem t64 quando o nome antigo existe'
rm -f "$B/apt-cache"
passou 'apt escolhe o nome t64 só quando o antigo não tem candidato'

# Bibliotecas por arquivo (ldd): tabela primeiro; fora dela, dnf/zypper por capability e apk por so:
[[ $(rodar -- pk_pacote_lib dnf libnss3.so) == nss && $(rodar -- pk_pacote_lib zypper libcups.so.2) == libcups2 && $(rodar -- pk_pacote_lib pacman libgbm.so.1) == mesa ]] || falhou 'bibliotecas na tabela'
[[ $(rodar TT_ARCH=x86_64 -- pk_pacote_lib dnf libnovo.so.5) == 'libnovo.so.5()(64bit)' ]] || falhou 'dnf por capability'
[[ $(rodar -- pk_pacote_lib apk libnovo.so.5) == so:libnovo.so.5 ]] || falhou 'apk por so:'
rodar -- pk_pacote_lib pacman libnovo.so.5 >/dev/null && falhou 'pacman sem mapeamento deveria falhar'
passou 'bibliotecas por distro: tabela, capability (dnf/zypper/apk) e sem mapa (pacman)'

# --- 4) Instalação robusta ---------------------------------------------------------------------------
# apt-get de mentira: registra tudo, "instala" menos o que tem "ruim" no nome, e imita o apt sem índice.
cat >"$B/apt-get" <<'EOF'
#!/bin/sh
echo "apt-get $*" >> "$LOG"
case "$*" in *update*) : > "$ATUALIZADO"; exit 0 ;; esac
if [ -n "$EXIGE_INDICE" ] && [ ! -e "$ATUALIZADO" ]; then echo "E: Unable to locate package $*" >&2; exit 100; fi
if [ -n "$SEM_SENHA" ]; then echo "sudo: 3 incorrect password attempts" >&2; exit 1; fi
for a; do case "$a" in *ruim*) echo "E: Unable to locate package $a" >&2; exit 100 ;; esac; done
exit 0
EOF
chmod +x "$B/apt-get"
fake sudo 'echo "sudo $*" >> "$LOG"; exec "$@"'
export LOG=$T/chamadas.log ATUALIZADO=$T/atualizado
inst() { : >"$LOG"; rm -f "$ATUALIZADO"
  rodar LOG="$LOG" ATUALIZADO="$ATUALIZADO" EXIGE_INDICE="${EXIGE_INDICE:-}" SEM_SENHA="${SEM_SENHA:-}" TT_SO=Linux TT_AMBIENTE="${AMB:-nativo}" -- "$@" 2>&1; }

# (a) tudo certo: uma chamada só, com sudo, ambiente sem perguntas e espera da trava do dpkg
saida=$(inst "pk_instalar apt-get sudo curl unzip; echo \"rc=\$? ok=\${PK_OK[*]} falhos=\${PK_FALHOS[*]-}\"")
grep -q 'rc=0 ok=curl unzip falhos=$' <<<"$saida" || falhou "instalação simples: $saida"
[[ $(grep -c '^apt-get' "$LOG") == 1 ]] || falhou 'tudo certo deveria ser uma chamada só'
grep -q '^sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -y -o DPkg::Lock::Timeout=120 install curl unzip$' "$LOG" || falhou "linha de comando: $(cat "$LOG")"
passou 'instalar: uma chamada, via sudo, sem perguntas e esperando a trava do dpkg'

# (b) índice velho/ausente: falha, atualiza e repete — e dá certo
saida=$(EXIGE_INDICE=1 inst "pk_instalar apt-get sudo curl; echo \"rc=\$? ok=\${PK_OK[*]}\"")
grep -q 'rc=0 ok=curl' <<<"$saida" || falhou "recuperação por atualização do índice: $saida"
grep -q 'apt-get.*update' "$LOG" || falhou 'deveria ter rodado o update'
passou 'instalar: índice ausente → atualiza e repete'

# (c) um nome ruim no meio: os bons ficam instalados, o ruim é apontado
saida=$(inst "pk_instalar apt-get sudo curl pacote-ruim unzip; echo \"rc=\$? ok=\${PK_OK[*]} falhos=\${PK_FALHOS[*]} motivo=\$PK_MOTIVO\"")
grep -q 'rc=1 ok=curl unzip falhos=pacote-ruim motivo=indice_ou_nome' <<<"$saida" || falhou "nome ruim derrubou os outros: $saida"
passou 'instalar: um pacote inexistente não derruba os demais (um a um) e o motivo é identificado'

# (d) sem permissão: para na hora, sem repetir pedidos de senha
saida=$(SEM_SENHA=1 inst "pk_instalar apt-get sudo curl unzip git; echo \"rc=\$? motivo=\$PK_MOTIVO falhos=\${PK_FALHOS[*]}\"")
grep -q 'rc=1 motivo=permissao' <<<"$saida" || falhou "senha errada: $saida"
[[ $(grep -c '^apt-get' "$LOG") == 1 ]] || falhou "senha errada tentou $(grep -c '^apt-get' "$LOG") vezes"
passou 'instalar: senha errada para na primeira tentativa'

# (e) proot do Android: o apt não larga privilégio para o usuário _apt
inst "pk_instalar apt-get nenhum curl" >/dev/null; AMB=proot inst "pk_instalar apt-get nenhum curl" >/dev/null
grep -q 'APT::Sandbox::User=root' "$LOG" || falhou 'no proot o apt deveria rodar com Sandbox::User=root'
AMB=nativo inst "pk_instalar apt-get nenhum curl" >/dev/null
grep -q 'Sandbox' "$LOG" && falhou 'fora do proot não deve ter Sandbox::User'
passou 'proot do Termux: apt com APT::Sandbox::User=root'

# (f) outros gerenciadores: argumentos de cada um
for par in "dnf:dnf install -y" "yum:yum install -y" "pacman:pacman -S --needed --noconfirm" "apk:apk add" "xbps:xbps-install -y" "pkg:pkg install -y" "pkg-bsd:pkg install -y" "pkg_add:pkg_add" "pkgin:pkgin -y install"; do
  ger=${par%%:*}; esperado=${par#*:}
  [[ $(rodar -- "pk_cmd_instalar $ger") == "$esperado" ]] || falhou "comando do $ger"
done
[[ $(rodar -- "pk_argv_instalar zypper vim" | tr '\n' ' ') == 'zypper --non-interactive install --auto-agree-with-licenses vim ' ]] || falhou 'argv do zypper'
[[ $(rodar -- "pk_argv_instalar pkg-bsd vim" | tr '\n' ' ') == 'env ASSUME_ALWAYS_YES=yes pkg install -y vim ' ]] || falhou 'argv do pkg do FreeBSD'
passou 'comandos de instalar de cada gerenciador (dnf, yum, pacman, apk, xbps, pkg, FreeBSD, OpenBSD, NetBSD, zypper)'

# --- 5) Download ---------------------------------------------------------------------------------------
echo conteudo >"$T/origem.txt"; sha=$(sha256sum "$T/origem.txt" | cut -d' ' -f1)
fake curl 'while [ $# -gt 0 ]; do case "$1" in -o) o=$2; shift ;; file://*) u=${1#file://} ;; esac; shift; done; cp "$u" "$o"'
rodar -- "pk_baixar file://$T/origem.txt $T/dl/ok.txt $sha 1" || falhou 'download com sha certo'
[[ $(cat "$T/dl/ok.txt") == conteudo ]] || falhou 'conteúdo baixado'
rodar -- "pk_baixar file://$T/origem.txt $T/dl/ruim.txt 0000 1" 2>/dev/null && falhou 'sha errado deveria falhar'
[[ ! -e $T/dl/ruim.txt ]] || falhou 'download com sha errado não pode deixar o arquivo'
ls -A "$T/dl" | grep -q '^\.dl\.' && falhou 'sobrou temporário do download'
rodar -- "pk_baixar file://$T/origem.txt $T/dl/grande.txt $sha 99999999" 2>/dev/null && falhou 'pouco espaço deveria falhar antes de baixar'
rm -f "$B/curl"
passou 'download: sha256 conferido, nada pela metade, espaço livre checado antes'

# --- 6) A mesma biblioteca roda no bash 3.2 do macOS? (só a parte de detecção; sintaxe) -------------
rodar -- 'pk_resumo' | grep -q ' · ' || falhou 'resumo da plataforma'
echo "TODOS OS TESTES PASSARAM"
