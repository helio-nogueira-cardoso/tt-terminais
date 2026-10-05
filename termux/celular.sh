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
#   termux/celular.sh adb                passo a passo: adb do próprio aparelho, Shizuku e Tasker, para o
#                                        Shizuku voltar sozinho depois do reboot (ver termux/ANDROID-ADB.md)
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
ESTADO=${XDG_STATE_HOME:-$HOME/.local/state}/tt/celular

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
# Barra de teclas: a do perfil (~/.config/tt/termux.properties), se o usuário tiver a própria; senão a geral.
barra_teclas() {
  if [[ -r $CONF_DIR/termux.properties ]]; then echo "$CONF_DIR/termux.properties"; else echo "$RAIZ/termux/termux.properties"; fi
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
  instalar_arquivo "$(barra_teclas)" "$HOME/.termux/termux.properties"
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
  mkdir -p "$(dirname "$ESTADO")"
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
  cmp -s "$(barra_teclas)" "$HOME/.termux/termux.properties" && ok "barra de teclas ($(barra_teclas | sed "s|^$HOME|~|"))" ||
    aviso "barra de teclas diferente da do tt; para manter a sua, guarde-a em ~/.config/tt/termux.properties"
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
  command -v adb-local >/dev/null && { adb-local status >/dev/null 2>&1 && ok "adb local: $(adb-local status)" || aviso "adb local desconectado"; }
  if command -v tt-rish >/dev/null; then tt-rish --ok && ok "Shizuku ativo (tt-rish)" || aviso "Shizuku parado"
  else aviso "sem adb/Shizuku/Tasker: $0 adb"; fi
  crontab -l 2>/dev/null | grep -q 'shizuku-vigia\|shizuku-guard' && ok "vigia do Shizuku no cron"
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

# --- adb do próprio aparelho + Shizuku + Tasker (termux/ANDROID-ADB.md) ------------------------
pergunta() { [[ -n $SIMULAR ]] && return 1; local r; read -rp "  $1 " r </dev/tty; [[ $r == [sSyY]* ]]; }
espera() { [[ -n $SIMULAR ]] || read -rp "  $1 (Enter para seguir) " _ </dev/tty; }
app_instalado() { adb -s "$2" shell pm path "$1" 2>/dev/null | grep -q package:; }

# Liga os utilitários do clone em ~/.local/bin (symlinks: seguem o git pull). Nunca troca um arquivo
# que não seja link nosso.
ligar_utilitarios() {
  local f d
  faz mkdir -p "$HOME/.local/bin"
  for f in "$RAIZ"/termux/bin/*; do
    d=$HOME/.local/bin/$(basename "$f")
    if [[ -e $d && ! -L $d ]]; then aviso "~/.local/bin/$(basename "$f") já existe e não é do tt; deixei como está"; continue; fi
    [[ $(readlink "$d" 2>/dev/null) == "$f" ]] || faz ln -sfn "$f" "$d"
  done
  ok "utilitários: $(cd "$RAIZ/termux/bin" && echo *)"
}

# rish exportado pelo app Shizuku → ~/.local/lib/rish (dex sem escrita: o Android 14+ exige).
instalar_rish() {
  local dex d=$HOME/.local/lib/rish
  [[ -f $d/rish && -f $d/rish_shizuku.dex ]] && return 0
  dex=$(find "$HOME/storage/downloads" "$HOME/storage/shared" -maxdepth 3 -name rish_shizuku.dex 2>/dev/null | head -1)
  [[ -n $dex && -f $(dirname "$dex")/rish ]] || return 1
  faz mkdir -p "$d" && faz cp "$(dirname "$dex")/rish" "$dex" "$d/" && faz chmod 700 "$d/rish" && faz chmod 400 "$d/rish_shizuku.dex"
}

adb_guiado() {
  no_termux || [[ -n $SIMULAR ]] || { echo "Rode no Termux (Android)."; exit 1; }
  local s='' p c
  titulo "1/6 Ferramentas"
  for p in android-tools cronie termux-api; do
    dpkg -s "$p" >/dev/null 2>&1 || faz env DEBIAN_FRONTEND=noninteractive pkg install -y "$p"
  done
  ligar_utilitarios
  export PATH="$HOME/.local/bin:$PATH"

  titulo "2/6 adb do próprio aparelho (depuração sem fio)"
  if [[ -z $SIMULAR ]] && s=$(adb-local conectar 2>/dev/null); then ok "adb já conecta: $s"
  else
    cat <<'TXT'
  a) Configurações → Sobre o telefone → Informações do software → toque 7× em "Número de compilação".
  b) Opções do desenvolvedor → Depuração sem fio → ligar (com Wi-Fi) → "Parear dispositivo com código".
  c) Deixe essa tela visível (tela dividida ou janela pop-up com o Termux): o código some se ela fechar.
TXT
    if [[ -z $SIMULAR ]]; then
      read -rp "  Porta mostrada no pareamento (depois do ':'): " p </dev/tty
      read -rp "  Código de 6 dígitos: " c </dev/tty
      adb-local parear "$p" "$c" || { erro "pareamento falhou; rode de novo"; exit 1; }
      s=$(adb-local conectar) || { erro "pareou, mas não conectou; confira se a depuração sem fio está ligada"; exit 1; }
    else faz adb-local parear PORTA CODIGO; faz adb-local conectar; fi
    ok "adb conectado: $s"
  fi

  titulo "3/6 Ajustes do Android (pelo adb que acabou de conectar)"
  if [[ -n $SIMULAR ]]; then faz "adb -s \$s shell sh < $RAIZ/termux/android-ajustes.sh"
  else adb -s "$s" shell sh <"$RAIZ/termux/android-ajustes.sh" | sed 's/^/  /'; fi

  titulo "4/6 Shizuku (shell do sistema sem adb nem Wi-Fi)"
  if [[ -z $SIMULAR ]] && ! app_instalado moe.shizuku.privileged.api "$s"; then
    espera "Instale o app Shizuku (Play Store ou GitHub RikkaApps/Shizuku)."
  fi
  faz shizuku-ligar || aviso "o Shizuku não subiu; abra o app Shizuku e toque em Iniciar (depuração sem fio)"
  if ! instalar_rish; then
    echo "  No app Shizuku: \"Usar o Shizuku em apps de terminal\" → Exportar arquivos → escolha a pasta Download."
    espera "Exportou?"
    instalar_rish || aviso "não achei rish e rish_shizuku.dex em Download"
  fi
  [[ -n $SIMULAR ]] || { tt-rish --ok && ok "Shizuku responde ao Termux (tt-rish)" ||
    aviso "o Shizuku vai perguntar se o Termux pode usá-lo: permita e rode este passo de novo"; }

  titulo "5/6 Tasker (modo dev, depuração sem fio e boot sem tocar na tela)"
  if [[ -z $SIMULAR ]] && ! app_instalado net.dinglisch.android.taskerm "$s"; then
    aviso "Tasker não instalado: sem ele, depois de um reboot a depuração sem fio volta a ser ligada à mão"
  else
    faz mkdir -p /sdcard/Tasker/projects
    faz cp "$RAIZ/termux/tasker/tt-celular.prj.xml" /sdcard/Tasker/projects/
    [[ -n $SIMULAR ]] || adb -s "$s" shell pm grant net.dinglisch.android.taskerm android.permission.WRITE_SECURE_SETTINGS
    echo "  No Tasker: segure o nome de um projeto (abas de baixo) → Importar projeto → tt-celular → ✓."
    echo "  Ele traz 4 perfis: ligar/desligar modo dev (intents tt.MODO_DEV_ON/OFF), abrir no boot, estado do Wi-Fi."
    espera "Importou?"
    [[ -n $SIMULAR || -f /sdcard/Tasker/estado/wifi ]] && ok "Tasker grava o estado do Wi-Fi" ||
      aviso "/sdcard/Tasker/estado/wifi ainda não existe: confira se os perfis tt: estão ligados"
  fi

  titulo "6/6 Vigia e adb sem Wi-Fi"
  local cron
  cron=$(crontab -l 2>/dev/null)
  if grep -q 'shizuku-guard' <<<"$cron"; then aviso "já há um shizuku-guard próprio no cron; não acrescentei o shizuku-vigia"
  elif ! grep -q 'shizuku-vigia' <<<"$cron"; then
    if [[ -n $SIMULAR ]]; then faz "crontab: */2 * * * * \$HOME/.local/bin/shizuku-vigia"
    else { [[ -n $cron ]] && echo "$cron"; echo "*/2 * * * * PATH=$HOME/.local/bin:\$PATH $HOME/.local/bin/shizuku-vigia"; } | crontab -; fi
  fi
  command -v sv-enable >/dev/null && faz sv-enable crond >/dev/null 2>&1
  ok "shizuku-vigia no cron (a cada 2 min)"
  [[ -n $SIMULAR ]] || { adb-local tcpip >/dev/null 2>&1 && ok "adb em 127.0.0.1:5555: sem Wi-Fi até o próximo reboot" ||
    aviso "não abri o 5555 agora; o shizuku-ligar tenta de novo"; }
  titulo "Depois de um reboot"
  echo "  O Tasker liga o modo dev e abre o Termux; na primeira conexão Wi-Fi o shizuku-vigia sobe o"
  echo "  Shizuku e reabre o adb local. Não precisa tocar em nada. Log: ~/.local/state/tt/shizuku.log"
}

case ${1:-instalar} in
  instalar) shift 2>/dev/null; instalar "$@" ;;
  --*) instalar "$@" ;;
  verificar) verificar ;;
  conectar) conectar "${2:-}" ;;
  android) android ;;
  adb) adb_guiado ;;
  -h|--ajuda|ajuda) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "comando desconhecido: $1 (veja $0 --ajuda)"; exit 2 ;;
esac
