#!/usr/bin/env bash
# Ambiente isolado para os testes: HOME, config, tmux e estado do tt numa pasta temporária, e o
# pacote COPIADO para lá (TT_DIR nunca aponta para o repositório: a instalação troca a pasta
# inteira de TT_DIR). Uso: source "$(dirname "$0")/lib.sh"; isolar
set -euo pipefail
RAIZ=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# exec_como NOME CMD [ARGS…] — imprime um comando "exec …" que roda CMD aparecendo como NOME para o tmux e o ps.
# Linux: `exec -a` (o tmux lê o argv[0]). macOS: o tmux lê o nome do executável, então roda uma cópia do binário com o nome.
exec_como() {
  local nome=$1 cmd=$2; shift 2
  if [[ $(uname -s) != Darwin ]]; then printf 'exec -a %q %q' "$nome" "$cmd"; (($#)) && printf ' %q' "$@"; return; fi
  mkdir -p "$T/nomes/$nome"; [[ -x $T/nomes/$nome/$nome ]] || cp "$(command -v "$cmd")" "$T/nomes/$nome/$nome"
  printf 'exec %q' "$T/nomes/$nome/$nome"; (($#)) && printf ' %q' "$@"; return 0
}

isolar() {
  local home_real=${HOME_REAL:-${HOME:-}}
  T=$(mktemp -d)
  mkdir -p "$T/pkg" "$T/home/.config/tt" "$T/tmux" "$T/rt"
  local f
  for f in tt email-tt.py links-tt.py letreiro-tt.py letreiro-fontes.py letreiro-catalogo.json letreiro-padrao.json gatilho-tt.sh tmux.conf tema-tmux.conf tema-terminal.sh tema-agentes.sh memoria-agentes.sh \
           atalhos-padrao atalhos-padrao-mobile README.md AI-DLC.md ia-conta ia-rot ia-login contas-uso.py skill-rodizio-de-contas.md nomeador-local.py skill-tt-terminais.md skill-celular-android.md agentes-regras-tt.md aidlc-tt NOVIDADES.md pacotes-tt.sh sessoes-ia.py tarefas-merge.py tarefas-merge.vim checagens-tt.md checagem-prompt.md voz voz-audio.py voz-windows.ps1; do
    [[ -e $RAIZ/$f ]] && cp "$RAIZ/$f" "$T/pkg/"
  done
  echo "999 teste 2099-01-01" >"$T/pkg/VERSAO"
  # PATH enxuto dos testes que isolam o ambiente (PATH="$T/bin:$TT_PATH_BASE"). No Linux é /usr/bin:/bin; no macOS essas
  # pastas só têm as ferramentas BSD e o bash 3.2, então entram também o bash e o python3 de agora e os gnubin do PATH
  # (sem o resto do Homebrew: um aerc ou tmux "ausente" continua ausente).
  if [[ -z ${TT_PATH_BASE:-} ]]; then
    TT_PATH_BASE=/usr/bin:/bin
    if [[ $(uname -s) == Darwin ]]; then
      mkdir -p "$T/basebin"
      for c in bash python3 tmux fzf rg; do ln -sf "$(command -v "$c")" "$T/basebin/$c" 2>/dev/null || true; done
      # script(1): os testes usam a sintaxe do util-linux (-qfc "cmd" arquivo), que aceita stdin que não é terminal
      # (FIFO, arquivo); o do BSD exige tty. Este adaptador faz o mesmo com pty: roda cmd num pty novo, copia o
      # stdin para ele e a saída dele para o stdout e para o arquivo.
      cat >"$T/basebin/script" <<'SHIM'
#!/usr/bin/env python3
import fcntl, os, pty, select, struct, sys, termios
a = sys.argv[1:]; cmd = None; arq = []
while a:
    x = a.pop(0)
    if x == "-T": a.pop(0)
    elif x.startswith("-") and x.endswith("c") and x != "-": cmd = a.pop(0)
    elif x.startswith("-"): pass
    else: arq.append(x)
log = open(arq[0], "wb", buffering=0) if arq and arq[0] != "/dev/null" else None
pid, fd = pty.fork()
if pid == 0:
    os.execvp("/bin/bash", ["bash", "-c", cmd] if cmd else ["bash"])
try:
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", int(os.environ.get("LINES", 24)), int(os.environ.get("COLUMNS", 80)), 0, 0))
except OSError: pass
ent = sys.stdin.fileno(); vivo_ent = True
while True:
    fds = [fd] + ([ent] if vivo_ent else [])
    try: r, _, _ = select.select(fds, [], [], 0.2)
    except OSError: break
    if fd in r:
        try: d = os.read(fd, 65536)
        except OSError: break
        if not d: break
        if log: log.write(d)
        try: os.write(1, d)
        except OSError: pass
    if vivo_ent and ent in r:
        try: d = os.read(ent, 65536)
        except OSError: d = b""
        if not d: vivo_ent = False
        else: os.write(fd, d)
try: _, st = os.waitpid(pid, 0)
except ChildProcessError: st = 0
sys.exit(os.waitstatus_to_exitcode(st))
SHIM
      chmod +x "$T/basebin/script"
      export PATH="$T/basebin:$PATH"
      TT_PATH_BASE="$T/basebin:$(tr ':' '\n' <<<"$PATH" | grep -F gnubin | paste -sd: -):/usr/bin:/bin"
      TT_PATH_BASE=${TT_PATH_BASE//::/:}
    fi
  fi
  export TT_PATH_BASE
  export HOME=$T/home XDG_CONFIG_HOME=$T/home/.config TMUX_TMPDIR=$T/tmux TT_RT=$T/rt TT_DIR=$T/pkg
  sem_tela_real "$T/run"
  export TERM=xterm-256color LANG=C.UTF-8 LC_ALL=C.UTF-8  # ambiente controlavel: nao herdar TERM=dumb nem locale vazio do chamador
  export TT_LETREIRO_SEM_PADRAO=1 # a suíte começa com o cadastro vazio; o perfil de fábrica tem teste próprio
  export TT_EMAIL_SEM_REDE=1 TT_T_ATUALIZACAO=999999 TT_ATALHOS_PADRAO=$T/pkg/atalhos-padrao
  export TT_SEM_NAVEGADORES=1 # instalar no HOME temporário não baixa Chrome/Carbonyl em segundo plano
  export TT_PEND_SEM_NAVEGADORES=1 # o catálogo de pendências não oferece Chrome/Carbonyl (os testes que querem, esvaziam a variável)
  export TT_PEND_SEM_SUDO_SEM_SENHA=1 # nem o "sudo sem senha" (o sudo da máquina pede senha; test_sudo_sem_senha.sh a esvazia)
  export TT_FINGE_TMUX_VERSAO=${TT_FINGE_TMUX_VERSAO-3.8} # o catálogo não oferece o tmux 3.8 aos testes que não são dele (test_tmux_novo.sh a remove)
  # Sob a carga da suíte inteira, uma sequência de mouse pode chegar ao fzf partida (ESC num read, o
  # resto no seguinte) e o ESC sozinho fecha o menu: o teste do pino da central oscilava assim. O fzf
  # honra ESCDELAY (ms, padrão 100) para esperar o resto da sequência.
  export ESCDELAY=300
  unset TMUX TMUX_PANE TT_CLIENTE TT_PANE PREFIX ANDROID_ROOT XDG_STATE_HOME XDG_DATA_HOME TT_AI_MEMORY_DIR TT_AIDLC_POLICY
  printf 'nome=teste\n' >"$XDG_CONFIG_HOME/tt/config"
  : >"$XDG_CONFIG_HOME/tt/maquinas"
  TT=$T/pkg/tt
  if [[ -z ${HOME_REAL:-} ]]; then
    if command -v getent >/dev/null 2>&1; then HOME_REAL=$(getent passwd "$(id -un)" | cut -d: -f6); fi
    HOME_REAL=${HOME_REAL:-$home_real}
  fi
  export HOME_REAL
  trap limpar_isolado EXIT
  source "$RAIZ/tests/sem-notificacao-real.sh"; sem_notificacao_real "$T"
}

# A tela gráfica de quem roda a suíte fica inalcançável: o tt de um teste chamava o wl-copy/xclip de
# verdade (escrevia na área de transferência real e, às vezes, travava no compositor) — e ele acha o
# compositor sozinho (socket wayland-* no XDG_RUNTIME_DIR; DISPLAY vazio vira :0). Variável que existia
# continua existindo, com valor que não leva a lugar nenhum (o caminho do código não muda); a que não
# existia continua ausente. O teste que quer área de transferência põe um wl-copy falso no PATH.
sem_tela_real() { # pasta-de-runtime
  mkdir -p "$1" && chmod 700 "$1" && export XDG_RUNTIME_DIR=$1
  [[ -n ${WAYLAND_DISPLAY:-} ]] && export WAYLAND_DISPLAY=wayland-tt-teste
  [[ -n ${DISPLAY:-} ]] && export DISPLAY=:99999
  return 0
}

# Faz um teste Linux/glibc executável também no Termux: mantém as ferramentas do PATH atual, mas
# omite o opener gráfico próprio do Termux, cuja presença faria a sonda classificar o host como celular.
path_sem_termux_open_url() {
  local destino="$T/path-sem-termux-open-url" d f nome
  local -a dirs=()
  mkdir -p "$destino"
  IFS=: read -r -a dirs <<<"$PATH"
  for d in "${dirs[@]}"; do
    [[ -d $d ]] || continue
    for f in "$d"/*; do
      [[ -x $f && ! -d $f ]] || continue
      nome=${f##*/}; [[ $nome == termux-open-url ]] && continue
      [[ -e $destino/$nome ]] || ln -s "$f" "$destino/$nome"
    done
  done
  TT_PATH_SEM_TERMUX_OPEN=$destino
}

limpar_isolado() {
  local st=$? s
  set +e
  fora kill-server 2>/dev/null
  for s in "$TMUX_TMPDIR"/tmux-*/*; do [[ -S $s ]] && tmux -S "$s" kill-server 2>/dev/null; done
  # Tudo o que foi lançado de dentro da pasta do teste (tt, servidores falsos, vigias) termina junto.
  pkill -f "$T/" 2>/dev/null
  rm -rf "$T"
  exit "$st"
}

# tmux "de fora": um servidor separado onde um cliente de verdade se anexa ao tmux do teste.
fora() { tmux -L "fora-$$" -f /dev/null "$@"; }
anexar() { # nome largura altura sessão
  fora new -d -s "$1" -x "$2" -y "$3" "env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t '$4'"
}

falhou() { echo "FALHOU — $*" >&2; exit 1; }
passou() { echo "ok: $*"; }

# Instala o pacote no HOME isolado (~/.local/share/tt, ~/.local/bin/tt, ~/.tmux.conf), para que
# atalhos e botões do tmux.conf chamem o tt de verdade.
instalar_isolado() {
  TT_DIR=$HOME/.local/share/tt "$T/pkg/tt" --instalar-aqui >/dev/null 2>&1 || falhou 'instalação isolada'
  export TT_DIR=$HOME/.local/share/tt
  TT=$HOME/.local/bin/tt
  export PATH=$HOME/.local/bin:$PATH
}
