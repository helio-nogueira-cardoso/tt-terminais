#!/usr/bin/env bash
# tt-teste: sozinho (abre modais reais e valida recuperação de navegação nativa)
# Sem contas/aerc/rede: a sessão de e-mail contém somente um sleep de teste.
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
fn() { TT_SO_CARREGAR=1 bash -c 'source "$1"; shift; "$@"' _ "$TT" "$@"; }
espera() { local n; for ((n=0; n<80; n++)); do "$@" && return 0; sleep .05; done; return 1; }
tmux -f "$HOME/.tmux.conf" new-session -d -s trabalho -x 120 -y 36 'sleep 600'
tmux new-session -d -s outra 'sleep 600'
tmux new-session -d -s _tt-email 'sleep 600'
fora new -d -s tela -x 120 -y 36 "env -u TMUX TERM=xterm-256color TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t '=trabalho'"
cliente_raiz() { tmux list-clients -F '#{client_name} #{client_termname}' | awk '$2 !~ /^(tmux|screen)/ {print $1; exit}'; }
tem_raiz() { [[ -n $(cliente_raiz) ]]; }
espera tem_raiz || falhou 'cliente físico não abriu'
c=$(cliente_raiz); dono_pid=$(fn do_cliente "$c" '#{client_pid}')
export TMUX=$(tmux display -p -t =trabalho: '#{socket_path},#{pid},0')
# Um painel comum reproduz a relação de posse também no tmux anterior ao modal 3.8.
# Com 3.8, exige o modal real (o caminho que provocava a cascata relatada).
args=(split-window -d -t =trabalho: -P -F '#{pane_id}')
if fn flutuante_suportado; then
  args=(new-pane -d -t =trabalho: -O -C -K -x 100 -y 25 -P -F '#{pane_id}')
fi
panel=$(tmux "${args[@]}" "env -u TMUX TT_EMAIL_CLIENTE=1 TT_EMAIL_DONO=$c TT_EMAIL_DONO_PID=$dono_pid tmux -u attach -t '=_tt-email'")
cliente_email() { tmux list-clients -t =_tt-email -F '#{client_name}' | head -1; }
tem_email() { [[ -n $(cliente_email) ]]; }
espera tem_email || falhou 'vista do e-mail não abriu'
inner=$(cliente_email)
[[ $(fn cliente_de_fora "$inner") == "$c" ]] || falhou 'dono da vista não identificado'
tt_before=$(tmux display -p -t =_tt-email: '#{session_id}:#{pane_pid}')
TT_CLIENTE=$inner fn ir_para . outra || falhou 'navegação pela vista falhou'
[[ $(fn do_cliente "$c" '#{session_name}') == outra ]] || falhou 'navegação não foi para a tela externa'
[[ $(fn do_cliente "$inner" '#{session_name}') == _tt-email ]] || falhou 'vista interna saiu do e-mail'
[[ $(tmux display -p -t =_tt-email: '#{session_id}:#{pane_pid}') == "$tt_before" ]] || falhou 'navegação recriou o e-mail'
passou 'navegação do e-mail troca a tela dona e preserva a vista, sessão e processo'

tmux switch-client -c "$c" -t =trabalho
# Simula atalho nativo que contorna o tt: guarda do próprio tmux interrompe a redução
# recursiva de tamanho imediatamente; o helper confirma o retorno, sem sucesso fictício.
tmux switch-client -c "$inner" -t =trabalho
voltou() { [[ $(fn do_cliente "$inner" '#{session_name}' 2>/dev/null) == _tt-email ]]; }
espera voltou || falhou 'guarda não recuperou a navegação nativa'
tmux has-session -t =trabalho || falhou 'ciclo derrubou a sessão externa'
[[ $(fn do_cliente "$c" '#{session_name}') == trabalho ]] || falhou 'guarda arrastou a tela externa'
le_tamanho() { local w h; read -r w h < <(tmux display -p -t =trabalho: '#{window_width} #{window_height}'); ((w >= 100 && h >= 20)); }
espera le_tamanho || falhou 'a tela encolheu recursivamente'
passou 'atalho nativo não provoca cascata; retorna ao e-mail com tamanho útil'

# Se o tty foi reciclado, não navegar outra tela só por ela ter o mesmo nome.
tmux set-environment -g TT_EMAIL_DONO_PID 999999
C_TESTE=$c TT_SO_CARREGAR=1 bash -c '
  source "$1"
  env_do_pid() { case $2 in TT_EMAIL_CLIENTE) echo 1;; TT_EMAIL_DONO) echo "$C_TESTE";; TT_EMAIL_DONO_PID) echo 999999;; esac; }
  cliente_de_fora "$2" && exit 1
  exit 0
' _ "$TT" "$inner" || falhou 'aceitou dono de identidade substituída'
passou 'tty com PID diferente não autoriza navegação'

# Não depender da igualdade pane_pid == client_pid: wrapper shell com filho tmux.
tmux new-session -d -s container "sh -c 'env -u TMUX tmux attach -t \"=outra\"; sleep 600'"
wrapped() { tmux list-clients -t =outra -F '#{client_name} #{client_termname}' | awk '$2 ~ /^(tmux|screen)/ {print $1; exit}'; }
tem_wrapper() { [[ -n $(wrapped) ]]; }
espera tem_wrapper || falhou 'cliente via wrapper não abriu'
wrapped_client=$(wrapped)
[[ $(fn contem_cliente "$wrapped_client") == container ]] || falhou 'wrapper ocultou o contêiner'
fn arestas_paineis | grep -q '^container outra$' || falhou 'grafo perdeu a aresta do wrapper'
TT_CLIENTE=$wrapped_client fn ir_para . container || falhou 'escape do ciclo com wrapper falhou'
[[ -z $(wrapped) ]] || falhou 'vista que fecharia ciclo não foi desanexada'
tmux has-session -t =outra && tmux has-session -t =container || falhou 'escape matou uma sessão de trabalho'
passou 'wrapper não esconde ciclo; escape fecha apenas a vista que pediu a troca'
