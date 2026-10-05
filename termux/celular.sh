#!/usr/bin/env bash
# Monta um celular Android com Termux no mesmo padrão do tt: pacotes, barra de teclas, sshd por
# chave, serviços no boot, Debian (proot-distro) com o Claude Code e o tt instalado e integrado.
#
# Do zero, num Termux recém-instalado (F-Droid ou GitHub; os plugins precisam vir da mesma loja):
#   curl -fsSL https://raw.githubusercontent.com/helio-nogueira-cardoso/tt-terminais/main/termux/celular.sh | bash
#
# Depois, de dentro do clone (~/tt-terminais):
#   termux/celular.sh [instalar] [--nome N] [--chaves-github USUARIO] [--sem-debian] [--sem-claude]
#   termux/celular.sh verificar          o que está pronto e o que falta (não muda nada)
#   termux/celular.sh conectar USU@HOST  liga este celular a um PC do tt (chaves dos dois lados + cadastro)
#   termux/celular.sh android            ajustes do Android que o Termux sozinho não faz (adb/Shizuku)
#
# Tudo é idempotente: rodar de novo depois de um `git pull` aplica só o que mudou. Arquivos do
# usuário que seriam trocados ganham cópia *.antes-celular. CELULAR_SIMULAR=1 só mostra os comandos.
set -uo pipefail

CELULAR_VERSAO=1
REPO_URL=${TT_CELULAR_REPO:-https://github.com/helio-nogueira-cardoso/tt-terminais.git}
CLONE=${TT_CELULAR_CLONE:-$HOME/tt-terminais}
SIMULAR=${CELULAR_SIMULAR:-}
CONF_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/tt
CONF=$CONF_DIR/config
ESTADO=$CONF_DIR/celular

PACOTES=(git tmux fzf python openssh mosh ripgrep proot-distro termux-services termux-api curl tar zstd nano)
PACOTES_DEBIAN=(ca-certificates curl git python3 procps sudo)

# --- saída -----------------------------------------------------------------------------------
c_ok=$'\e[32m' c_av=$'\e[33m' c_er=$'\e[31m' c_t=$'\e[1;36m' c_0=$'\e[0m'
titulo() { printf '\n%s== %s%s\n' "$c_t" "$*" "$c_0"; }
ok() { printf '  %s✔%s %s\n' "$c_ok" "$c_0" "$*"; }
aviso() { printf '  %s!%s %s\n' "$c_av" "$c_0" "$*"; }
erro() { printf '  %s✘%s %s\n' "$c_er" "$c_0" "$*"; }
# Executa (ou só mostra, em simulação) um comando.
faz() {
  if [[ -n $SIMULAR ]]; then printf '  $ %s\n' "$*"; return 0; fi
  "$@"
}

# --- bootstrap: rodando por curl | bash, clona e se reexecuta do clone --------------------------
aqui=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
if [[ ! -f $aqui/../instalar.sh || ! -f $aqui/termux.properties ]]; then
  [[ ${PREFIX:-} == *com.termux* ]] || { echo "Rode no Termux (Android)."; exit 1; }
  command -v git >/dev/null || { pkg update -y && pkg install -y git; } || exit 1
  if [[ -d $CLONE/.git ]]; then git -C "$CLONE" pull --ff-only -q || true
  else git clone -q "$REPO_URL" "$CLONE" || exit 1; fi
  exec bash "$CLONE/termux/celular.sh" "$@" </dev/tty
fi
RAIZ=$(cd "$aqui/.." && pwd)

no_termux() { [[ ${PREFIX:-} == *com.termux* ]]; }
conf() { sed -n "s/^$1=//p" "$CONF" 2>/dev/null | tail -1; }
conf_padrao() { # chave valor: grava só se a chave ainda não existe (nunca sobrescreve o usuário)
  grep -q "^$1=" "$CONF" 2>/dev/null && return 0
  if [[ -n $SIMULAR ]]; then printf '  $ echo %q >> %s\n' "$1=$2" "$CONF"; return 0; fi
  mkdir -p "$CONF_DIR"; printf '%s=%s\n' "$1" "$2" >>"$CONF"
}
# Copia o arquivo do repositório para o destino; se já havia outro conteúdo, guarda *.antes-celular.
instalar_arquivo() { # origem destino [modo]
  local o=$1 d=$2 m=${3:-600}
  if cmp -s "$o" "$d" 2>/dev/null; then ok "${d/#$HOME/\~} já em dia"; return 0; fi
  if [[ -e $d && ! -e $d.antes-celular ]]; then faz cp -p "$d" "$d.antes-celular"; fi
  faz mkdir -p "$(dirname "$d")" && faz cp "$o" "$d" && faz chmod "$m" "$d" && ok "${d/#$HOME/\~} instalado"
}
debian_rootfs() { echo "${PREFIX:-}/var/lib/proot-distro/containers/debian/rootfs"; }
tem_debian() { [[ -d $(debian_rootfs)/usr || -d ${PREFIX:-}/var/lib/proot-distro/installed-rootfs/debian/usr ]]; }
no_debian() { proot-distro login debian -- bash -lc "$1"; }

# --- passos ----------------------------------------------------------------------------------
# F_DROID, GITHUB ou GOOGLE_PLAY_STORE; fora do app (ssh) só sobra o TERMUX_VERSION.
origem_termux() {
  if [[ -n ${TERMUX_APK_RELEASE:-} ]]; then echo "$TERMUX_APK_RELEASE"
  elif [[ ${TERMUX_VERSION:-} == googleplay* ]]; then echo GOOGLE_PLAY_STORE; fi
}

passo_origem() {
  titulo "Termux"
  case $(origem_termux) in
    F_DROID|GITHUB) ok "Termux do ${TERMUX_APK_RELEASE} (Termux:Boot e Termux:API da mesma origem)" ;;
    GOOGLE_PLAY_STORE) aviso "Termux da Play Store: use os plugins (Termux:Boot, Termux:API) da Play também, se existirem para a sua versão." ;;
    *) aviso "origem do Termux desconhecida; Termux:Boot e Termux:API precisam vir da mesma loja do Termux." ;;
  esac
}

passo_pacotes() {
  titulo "Pacotes do Termux"
  local falta=() p
  for p in "${PACOTES[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || falta+=("$p"); done
  if ((${#falta[@]} == 0)); then ok "todos instalados"; return 0; fi
  echo "  instalando: ${falta[*]}"
  faz env DEBIAN_FRONTEND=noninteractive pkg update -y || return 1
  faz env DEBIAN_FRONTEND=noninteractive pkg install -y -o Dpkg::Options::=--force-confold "${falta[@]}" || return 1
  ok "pacotes instalados"
}

passo_armazenamento() {
  titulo "Armazenamento do Android"
  if [[ -d $HOME/storage/downloads ]]; then ok "~/storage pronto (Download visível para o tt)"; return 0; fi
  aviso "o Android vai pedir acesso aos arquivos: toque em Permitir."
  faz termux-setup-storage
  [[ -n $SIMULAR ]] || sleep 4
}

passo_teclas() {
  titulo "Barra de teclas extras (botões do tt)"
  instalar_arquivo "$RAIZ/termux/termux.properties" "$HOME/.termux/termux.properties"
  command -v termux-reload-settings >/dev/null && faz termux-reload-settings
}

passo_sshd() {
  titulo "Acesso por SSH (porta 8022, só chave)"
  local ak=$HOME/.ssh/authorized_keys u=${1:-}
  faz mkdir -p "$HOME/.ssh" && faz chmod 700 "$HOME/.ssh"
  if [[ -n $u ]]; then
    local k
    k=$(curl -fsSL "https://github.com/$u.keys") && [[ -n $k ]] || { erro "não achei chaves públicas de $u no GitHub"; return 1; }
    while IFS= read -r l; do
      grep -qxF "$l" "$ak" 2>/dev/null || { [[ -n $SIMULAR ]] && echo "  $ echo '${l:0:30}…' >> $ak" || echo "$l" >>"$ak"; }
    done <<<"$k"
    ok "chaves do GitHub ($u) autorizadas"
  fi
  [[ -f $ak ]] && faz chmod 600 "$ak"
  [[ -f $HOME/.ssh/id_ed25519 ]] || faz ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519" -C "$(conf nome || true)@celular"
  # Senha só fica desligada quando já há chave autorizada: senão ninguém entraria.
  local dconf=${PREFIX:-}/etc/ssh/sshd_config.d/tt-celular.conf
  if [[ -s $ak ]]; then
    if [[ ! -f $dconf ]]; then
      if [[ -n $SIMULAR ]]; then echo "  $ echo 'PasswordAuthentication no' > $dconf"
      else mkdir -p "$(dirname "$dconf")"; echo 'PasswordAuthentication no' >"$dconf"; fi
    fi
    ok "senha desligada; entra quem tem chave ($(grep -c . "$ak" 2>/dev/null || echo 0) autorizada(s))"
  else
    aviso "nenhuma chave autorizada ainda: use 'conectar usuario@pc' ou --chaves-github USUARIO"
  fi
  command -v sv-enable >/dev/null && faz sv-enable sshd >/dev/null 2>&1
  pgrep -x sshd >/dev/null || faz sshd
  ok "sshd ativo em $(id -un)@<este celular>:8022"
}

passo_boot() {
  titulo "Início automático (Termux:Boot)"
  instalar_arquivo "$RAIZ/termux/boot-tt" "$HOME/.termux/boot/00-tt" 700
  aviso "instale o app Termux:Boot e abra-o uma vez para ele ser autorizado a rodar no boot"
}

passo_tt() {
  titulo "tt (central de terminais)"
  local nome=${1:-$(conf nome)}
  nome=${nome:-celular}
  if [[ -n $SIMULAR ]]; then echo "  $ $RAIZ/instalar.sh $nome"
  else (cd "$RAIZ" && ./instalar.sh "$nome") | tail -3 || { erro "instalação do tt falhou"; return 1; }; fi
  # Atalhos do Debian/Claude no shell (dbn, cl, clc, clr, clu): lidos do clone, seguem o git pull.
  local linha="[ -r \"$RAIZ/termux/atalhos.sh\" ] && . \"$RAIZ/termux/atalhos.sh\"  # tt-celular"
  if ! grep -qF '# tt-celular' "$HOME/.bashrc" 2>/dev/null; then
    if [[ -n $SIMULAR ]]; then echo "  $ echo '…atalhos.sh  # tt-celular' >> ~/.bashrc"
    else printf '%s\n' "$linha" >>"$HOME/.bashrc"; fi
  fi
  ok "tt instalado como \"$nome\"; atalhos dbn/cl/clc/clr no shell"
}

passo_debian() {
  local com_claude=$1
  titulo "Debian (proot-distro)"
  if tem_debian; then ok "Debian instalado"
  else
    echo "  baixando o Debian (uns 100 MB)…"
    faz proot-distro install debian || { erro "proot-distro install debian falhou"; return 1; }
  fi
  local falta
  falta=$( [[ -n $SIMULAR ]] && echo "${PACOTES_DEBIAN[*]}" ||
    no_debian "for p in ${PACOTES_DEBIAN[*]}; do dpkg -s \$p >/dev/null 2>&1 || printf '%s ' \$p; done" 2>/dev/null)
  if [[ -n ${falta// /} ]]; then
    echo "  apt no Debian: $falta"
    faz no_debian "export DEBIAN_FRONTEND=noninteractive; apt-get update -q && apt-get install -yq $falta" ||
      { erro "apt no Debian falhou"; return 1; }
  fi
  ok "pacotes básicos no Debian"
  # ~/.local/bin no PATH do root, onde o instalador do Claude põe o binário.
  faz no_debian 'grep -q "\.local/bin" ~/.bashrc 2>/dev/null || echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.bashrc'
  [[ $com_claude ]] || return 0
  if [[ -z $SIMULAR ]] && no_debian 'command -v claude' >/dev/null 2>&1; then ok "Claude Code no Debian ($(no_debian 'claude --version' 2>/dev/null | head -1))"
  else
    echo "  instalando o Claude Code no Debian…"
    faz no_debian 'curl -fsSL https://claude.ai/install.sh | bash' || { erro "instalador do Claude falhou"; return 1; }
    ok "Claude Code instalado; o primeiro 'cl' pede o login"
  fi
  # Root no proot: o claude só aceita pular permissões com IS_SANDBOX=1; o socket de mensagens vai
  # num caminho explícito porque o proot não mapeia uid. Só grava se a máquina ainda não tem os seus.
  conf_padrao claude_env 'IS_SANDBOX=1'
  conf_padrao claude_flags "--dangerously-skip-permissions --messaging-socket-path $HOME/.claude/run/msg-\$\$.sock"
}

registrar_estado() {
  [[ -n $SIMULAR ]] && return 0
  mkdir -p "$CONF_DIR"
  printf 'versao=%s\ncommit=%s\ndata=%s\n' "$CELULAR_VERSAO" \
    "$(git -C "$RAIZ" rev-parse --short HEAD 2>/dev/null)" "$(date +%F\ %T)" >"$ESTADO"
}

instalar() {
  local nome='' gh='' debian=1 claude=1
  while (($#)); do
    case $1 in
      --nome) nome=$2; shift ;;
      --chaves-github) gh=$2; shift ;;
      --sem-debian) debian='' ;;
      --sem-claude) claude='' ;;
      *) echo "opção desconhecida: $1"; exit 2 ;;
    esac; shift
  done
  no_termux || [[ -n $SIMULAR ]] || { echo "Rode no Termux (Android)."; exit 1; }
  passo_origem
  passo_pacotes || { erro "sem os pacotes não dá para continuar"; exit 1; }
  passo_armazenamento
  passo_teclas
  passo_sshd "$gh"
  passo_boot
  passo_tt "$nome"
  [[ $debian ]] && passo_debian "$claude"
  registrar_estado
  titulo "Falta fazer à mão"
  echo "  1. App Tailscale: entrar na mesma conta dos PCs (é por ele que as máquinas se acham)."
  echo "  2. Ajustes do Android (evita o Termux ser morto em segundo plano): $0 android"
  echo "  3. Ligar a um PC: $0 conectar usuario@pc   (depois o tt mostra as sessões dele)"
  echo "  4. Abra uma aba nova do Termux: ela já entra no tmux com a barra do tt."
}

verificar() {
  local p falta=() v
  titulo "Verificação (perfil do celular v$CELULAR_VERSAO)"
  v=$(sed -n 's/^versao=//p' "$ESTADO" 2>/dev/null)
  if [[ -z $v ]]; then aviso "perfil nunca aplicado aqui"
  elif ((v < CELULAR_VERSAO)); then aviso "perfil v$v aplicado; há v$CELULAR_VERSAO: rode $0 instalar"
  else ok "perfil v$v aplicado em $(sed -n 's/^data=//p' "$ESTADO")"; fi
  no_termux && ok "Termux ${TERMUX_VERSION:-} ($(origem_termux || true))" || erro "não é Termux"
  for p in "${PACOTES[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || falta+=("$p"); done
  ((${#falta[@]})) && erro "pacotes faltando: ${falta[*]}" || ok "pacotes do Termux"
  [[ -d $HOME/storage/downloads ]] && ok "armazenamento" || erro "armazenamento: rode termux-setup-storage"
  cmp -s "$RAIZ/termux/termux.properties" "$HOME/.termux/termux.properties" && ok "barra de teclas" ||
    aviso "barra de teclas diferente da do tt (ok se você personalizou)"
  [[ -s $HOME/.ssh/authorized_keys ]] && ok "chaves SSH autorizadas: $(grep -c . "$HOME/.ssh/authorized_keys")" ||
    erro "nenhuma chave SSH autorizada"
  pgrep -x sshd >/dev/null && ok "sshd rodando" || erro "sshd parado"
  compgen -G "$HOME/.termux/boot/*" >/dev/null && ok "script de boot: $(ls "$HOME/.termux/boot" | tr '\n' ' ')" || aviso "sem script de boot"
  [[ -x $HOME/.local/bin/tt ]] && ok "tt $(cut -d' ' -f1 "$HOME/.local/share/tt/VERSAO" 2>/dev/null) como \"$(conf nome)\"" ||
    erro "tt não instalado"
  grep -qF '# tt-celular' "$HOME/.bashrc" 2>/dev/null && ok "atalhos dbn/cl" || aviso "atalhos dbn/cl fora do ~/.bashrc"
  if tem_debian; then
    ok "Debian"
    [[ -e $(debian_rootfs)/root/.local/bin/claude || -L $(debian_rootfs)/root/.local/bin/claude ]] && ok "Claude Code no Debian" || aviso "Debian sem Claude Code"
  else aviso "sem Debian (proot-distro)"; fi
  [[ -n $(sed -n '/./p' "$CONF_DIR/maquinas" 2>/dev/null) ]] && ok "máquinas: $(awk '!/^#/ && NF {print $3}' "$CONF_DIR/maquinas" | tr '\n' ' ')" ||
    aviso "nenhuma máquina ligada: $0 conectar usuario@pc"
  echo "  (os ajustes do Android só são vistos pelo adb/Shizuku: $0 android)"
}

# Liga a um PC que já tem o tt: autoriza a chave do celular lá e a do PC aqui, ensina ao PC a porta
# 8022 e o usuário do Termux, e cadastra pelos dois lados (tt --cadastrar faz o resto).
conectar() {
  local dest=${1:-} host usu ip nome_ts eu=$(id -un) pc_pub
  [[ $dest == *@* ]] || { echo "Uso: $0 conectar usuario@host-do-pc"; exit 2; }
  usu=${dest%@*} host=${dest#*@}
  titulo "Conectando a $dest"
  [[ -f $HOME/.ssh/id_ed25519.pub ]] || faz ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519"
  echo "  (se pedir senha, é a do PC; o Tailscale SSH costuma entrar direto)"
  faz ssh -o StrictHostKeyChecking=accept-new "$dest" \
    'mkdir -p ~/.ssh && chmod 700 ~/.ssh && k=$(cat) && { grep -qxF "$k" ~/.ssh/authorized_keys 2>/dev/null || echo "$k" >> ~/.ssh/authorized_keys; }' \
    <"$HOME/.ssh/id_ed25519.pub" || { erro "ssh $dest falhou"; exit 1; }
  ok "chave do celular autorizada no PC"
  # O IP pelo qual o PC nos vê (o da tailnet) dá o nome do celular no Tailscale.
  ip=$( [[ -n $SIMULAR ]] && echo 100.64.0.1 || ssh "$dest" 'echo ${SSH_CONNECTION%% *}')
  nome_ts=$( [[ -n $SIMULAR ]] && echo celular || ssh "$dest" "tailscale status 2>/dev/null | awk '\$1==\"$ip\"{print \$2; exit}'")
  nome_ts=${nome_ts:-$ip}
  pc_pub=$( [[ -n $SIMULAR ]] && echo 'ssh-ed25519 AAAA pc' ||
    ssh "$dest" '[ -f ~/.ssh/id_ed25519.pub ] || ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519; cat ~/.ssh/id_ed25519.pub')
  if [[ -n $pc_pub ]] && ! grep -qxF "$pc_pub" "$HOME/.ssh/authorized_keys" 2>/dev/null; then
    [[ -n $SIMULAR ]] && echo "  $ echo '<chave do PC>' >> ~/.ssh/authorized_keys" || echo "$pc_pub" >>"$HOME/.ssh/authorized_keys"
  fi
  chmod 600 "$HOME/.ssh/authorized_keys" 2>/dev/null
  ok "chave do PC autorizada aqui"
  faz ssh "$dest" "grep -q '^Host $nome_ts' ~/.ssh/config 2>/dev/null || printf '\nHost $nome_ts $nome_ts.*\n  Port 8022\n  User $eu\n' >> ~/.ssh/config"
  ok "PC sabe entrar aqui: ssh $nome_ts (porta 8022, usuário $eu)"
  passo_sshd >/dev/null
  echo "  cadastrando no tt (confirme usuário e nome)…"
  faz "$HOME/.local/bin/tt" --cadastrar "$host" "$usu"
}

android() {
  titulo "Ajustes do Android"
  cat <<EOF
  O Android 12+ mata processos "fantasmas" (as abas do Termux somem juntas) e põe apps para
  dormir. O script $RAIZ/termux/android-ajustes.sh desliga isso e libera da economia de bateria
  o Termux, o Termux:Boot e o Tailscale. Ele roda no shell do sistema, por um destes caminhos:

  • Do PC, com o celular no cabo ou na depuração sem fio:
      adb shell sh < termux/android-ajustes.sh
  • No próprio celular, com o Shizuku ativo e o rish copiado para ~/bin:
      RISH_APPLICATION_ID=com.termux sh ~/bin/rish -c "sh $RAIZ/termux/android-ajustes.sh"
  • Sem adb nem Shizuku: Configurações → Apps → Termux → Bateria → Sem restrições
    (repita para Termux:Boot e Tailscale) e, nas Opções do desenvolvedor, "Desativar
    restrições de processos filhos" (Android 14+).
EOF
  if [[ -x $HOME/bin/rish ]] && [[ -z $SIMULAR ]]; then
    read -rp "  Achei ~/bin/rish. Aplicar agora pelo Shizuku? [s/N] " r
    [[ $r == [sS]* ]] && RISH_APPLICATION_ID=com.termux sh "$HOME/bin/rish" -c "sh $RAIZ/termux/android-ajustes.sh"
  fi
}

case ${1:-instalar} in
  instalar) shift 2>/dev/null; instalar "$@" ;;
  --*) instalar "$@" ;;
  verificar) verificar ;;
  conectar) conectar "${2:-}" ;;
  android) android ;;
  -h|--ajuda|ajuda) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "comando desconhecido: $1 (veja $0 --ajuda)"; exit 2 ;;
esac
