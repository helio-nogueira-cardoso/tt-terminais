#!/usr/bin/env bash
# Guardião de portabilidade (Linux E macOS). O tt é escrito, na maior parte, em máquinas Linux, mas roda no macOS do dono.
# Este teste não roda o tt: lê o código e reprova quando alguém reintroduz um padrão que só funciona no Linux. Os "tetos"
# abaixo são o que existe hoje (cada um já tem retorno para o macOS); número maior = código novo que não tem. A saída diz
# o que usar no lugar. Veja a seção "Portabilidade" do AGENTS.md.
source "$(dirname "$0")/lib.sh"; isolar
cd "$RAIZ"

teto() { # arquivo padrão máximo explicação — reprova se o nº de linhas com o padrão passou do teto
  local arq=$1 pad=$2 max=$3 msg=$4 n
  [[ -f $arq ]] || return 0
  n=$(grep -c -E -- "$pad" "$arq" || true)
  ((n <= max)) || falhou "$arq: $n linhas com /$pad/ (o teto é $max). $msg"
}

# 1) /proc não existe no macOS. Use os auxiliares do tt (env_do_pid, cwd_do_pid, cmdline_do_pid: /proc no Linux, ps/lsof no
#    macOS) ou, em Python, o caminho com retorno (TEM_PROC, lsof, ps). Quem lê /proc direto leva o teto abaixo.
PROC='/proc/'
MSG_PROC='/proc não existe no macOS: use env_do_pid/cwd_do_pid/cmdline_do_pid (tt, voz) ou um retorno com ps/lsof (Python); se for mesmo só Linux, proteja com [[ -r /proc/… ]] e suba o teto aqui, explicando no commit.'
teto tt "$PROC" 24 "$MSG_PROC"
teto voz "$PROC" 1 "$MSG_PROC"
teto ia-conta "$PROC" 7 "$MSG_PROC"
teto ia-rot "$PROC" 2 "$MSG_PROC"
teto gatilho-tt.sh "$PROC" 2 "$MSG_PROC"
teto letreiro-tt.py "$PROC" 6 "$MSG_PROC"
teto links-tt.py "$PROC" 3 "$MSG_PROC"
teto sessoes-ia.py "$PROC" 5 "$MSG_PROC" # 5º: args_processo (/proc/PID/cmdline, com o ps de retorno no macOS)
teto voz-audio.py "$PROC" 2 "$MSG_PROC"
teto nomeador-local.py "$PROC" 1 "$MSG_PROC"
for f in email-tt.py contas-uso.py tarefas-merge.py letreiro-fontes.py telas-agentes.py aidlc-tt ia-login; do teto "$f" "$PROC" 0 "$MSG_PROC"; done
passou 'sem /proc novo (os existentes têm retorno para o macOS)'

# 2) Locale: o macOS não tem C.UTF-8 (tem en_US.UTF-8). No tt use $TT_UTF8; no voz já há o teste do sistema.
teto tt 'C\.UTF-8' 5 'o macOS não tem C.UTF-8: use $TT_UTF8 (definido no começo do tt).'
teto voz 'C\.UTF-8' 2 'o macOS não tem C.UTF-8 (veja como o voz escolhe por uname).'
passou 'sem C.UTF-8 novo'

# 3) zsh é o shell padrão do macOS e o tmux roda comandos de painel/popup por ele: "=sessão" sem aspas vira busca de comando
#    ("_tt-email not found"). Em string de comando use $(q "=$sessao") ou '=sessao' entre aspas.
teto tt "(attach|attach-session|switch-client)[^'\"]* -t =[A-Za-z_\$]" 3 \
  'um =alvo sem aspas dentro de um comando que o tmux roda pelo shell quebra no zsh: use -t $(q "=$sessao").'
teto voz "printf '%q' \"=" 0 \
  'no voz o comando vai pelo ssh, e o shell do ssh no Mac é o zsh: o printf %q não protege o "=" do começo; use $(q "=$sessao").'
passou 'sem =alvo novo fora de aspas em comandos de painel'

# 4) tmux.conf: o tmux expande $nome no arquivo (vira vazio antes do shell ver). Em if-shell/run-shell evite $variável;
#    use #{formatos} do tmux ou comandos sem variável.
n=$(grep -E 'if-shell|run-shell|if -F' tmux.conf | grep -c -E '\$[A-Za-z_{]' || true)
((n == 0)) || falhou "tmux.conf: $n linhas com \$variável em if-shell/run-shell (o tmux a expande, vazia, ao carregar). Use #{formato} do tmux, não \$nome."
grep -q '/proc/#{pid}/exe' tmux.conf && ! grep -q 'tmux -S #{q:socket_path}' tmux.conf && falhou 'tmux.conf usa /proc/#{pid}/exe sem o retorno com tmux -S #{q:socket_path} (macOS)'
passou 'tmux.conf sem $variável em if-shell/run-shell'

# 5) Scripts bash executáveis: o `env bash` do macOS pode achar o bash 3.2 (o path_helper põe /usr/bin na frente). Quem usa
#    recursos do bash 4+ (declare -A, mapfile, EPOCHREALTIME, {fd}, @(…)) precisa da guarda que se reexecuta no do Homebrew.
#    Copie o bloco "BASH_VERSINFO" do começo do ia-conta. (instalar.sh, pacotes-tt.sh e tema-*.sh têm tratamento próprio.)
for f in *; do
  [[ -f $f && -x $f ]] || continue
  [[ $(head -1 "$f" 2>/dev/null | LC_ALL=C tr -d '\000-\010') == '#!/usr/bin/env bash' ]] || continue
  case $f in instalar.sh | pacotes-tt.sh | tema-terminal.sh | tema-agentes.sh | memoria-agentes.sh) continue ;; esac
  if grep -q -E 'declare -A|mapfile|readarray|EPOCHREALTIME|\{fd\}|== @\(' "$f"; then
    grep -q 'BASH_VERSINFO:-0' "$f" || falhou "$f usa recursos do bash 4+ e não tem a guarda de versão (o macOS pode rodá-lo no bash 3.2): copie o bloco BASH_VERSINFO do começo do ia-conta."
  fi
done
passou 'scripts bash com recursos do bash 4+ têm a guarda de versão'

# 6) O pintor da barra (letreiro-tt.py) roda para sempre: nada de lançar processos ali (test_redesenho cobre); no macOS o que
#    precisa de ps/lsof vem do shell, uma vez (tt --e-ponte).
grep -qE 'subprocess|os\.system|popen' letreiro-tt.py && falhou 'letreiro-tt.py não pode lançar processos: peça ao shell do tt (como o tt --e-ponte)'
passou 'letreiro-tt.py sem processos'

# 7) Testes: nome de processo falso, script(1), pgrep, /proc e getent são diferentes no macOS.
for f in tests/test_*.sh; do
  [[ $f == tests/test_portabilidade.sh ]] && continue
  grep -n 'exec -a' "$f" >/dev/null 2>&1 && ! grep -q 'mbsync' <(grep 'exec -a' "$f") &&
    falhou "$f usa 'exec -a' para fingir o nome de um processo: no macOS o tmux/ps leem o nome do executável. Use exec_como (comando) ou nomear_script (script) do tests/lib.sh."
  grep -n -E 'pgrep -[a-zA-Z]*[nc]( |$)' "$f" | grep -qE 'pgrep -f [^ ]+ -[nc]' &&
    falhou "$f: opção do pgrep depois do padrão (o BSD para de ler opções): 'pgrep -n -f padrão', nunca 'pgrep -f padrão -n'."
  grep -qE -- '-d /proc/\$' "$f" && falhou "$f testa -d /proc/\$PID: use kill -0 \$PID (vale no macOS)."
done
passou 'testes sem os padrões que só valem no Linux'

# 8) Os auxiliares de portabilidade continuam existindo (quem os apagar quebra o macOS sem aviso).
for fn in env_do_pid cwd_do_pid cmdline_do_pid soltos_bsd e_ponte_pid; do
  grep -q "^$fn()" tt || falhou "tt perdeu o auxiliar de portabilidade $fn"
done
grep -q '_TT_PATH_ORIGEM' tt || falhou 'tt perdeu o bloco que põe as ferramentas GNU do Homebrew no PATH no macOS'
grep -q 'BASH_VERSINFO' tt || falhou 'tt perdeu a guarda de versão do bash'
passou 'auxiliares de portabilidade presentes'
