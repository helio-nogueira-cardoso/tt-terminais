#!/usr/bin/env bash
# Um aerc só para o e-mail. (1) Abrir de uma tela de outra largura (estreito/largo/amplo) reaproveita a
# sessão oculta e o mesmo processo e ajusta o layout pelo IPC (:split/:vsplit/:toggle-sidebar), em vez
# de recriar a sessão. (2) Quando a sessão é recriada de fato, o aerc antigo morre: ele ignora o SIGHUP
# do tmux e, só com kill-session, ficava vivo, adotado pelo launchd/init (dezenas em poucos dias).
# (3) aerc órfãos de antes são encerrados ao criar a sessão. (4) O socket do IPC no macOS sem
# XDG_RUNTIME_DIR fica em ~/Library/Application Support.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
mkdir -p "$T/bin" "$T/rt-x" ~/.config/aerc
export XDG_RUNTIME_DIR=$T/rt-x
# aerc falso: com :comando é o cliente do IPC (registra; com $T/recusar, :split responde erro, como o
# aerc real com uma mensagem aberta na frente); sem, é a interface e fica rodando (aceita o -B do tt).
cat >"$T/bin/aerc" <<EOF
#!/usr/bin/env bash
if [[ \${1:-} == :* ]]; then
  printf '%s\n' "\$*" >>"$T/ipc.log"
  [[ -e $T/recusar && \$1 == :split ]] && echo 'response: Unknown command split'
  exit 0
fi
printf '%s\n' "\$\$" >>"$T/aerc-pids"
EOF
printf '%s\n' "$(exec_como aerc sleep 600)" >>"$T/bin/aerc"
chmod +x "$T/bin/aerc"; export PATH=$T/bin:$PATH
# A coleta de órfãos enxerga somente os aerc criados por este ensaio.
ps_real=$(command -v ps)
cat >"$T/bin/ps" <<EOF
#!/bin/sh
"$ps_real" "\$@" | awk 'NR==FNR { own[\$1]=1; next } \$3 ~ /(^|\/)aerc\$/ && !(\$1 in own) { next } { print }' "$T/aerc-pids" -
EOF
: >"$T/aerc-pids"
chmod +x "$T/bin/ps"
printf '[ui]\nsidebar-width=24\nmessage-list-split=horizontal 14\n' >~/.config/aerc/aerc.conf
python3 -I -c 'import socket, sys; s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$XDG_RUNTIME_DIR/aerc.sock"
fn() { TT_SO_CARREGAR=1 bash -c 'source "$1" >/dev/null 2>&1; shift; "$@"' _ "$TT" "$@"; }
ipc() { [[ -s $T/ipc.log ]] && tr '\n' '|' <"$T/ipc.log"; : >"$T/ipc.log"; }
opt() { tmux show -qv -t =_tt-email: "$1"; }
ident() { tmux display -p -t =_tt-email: '#{session_id}:#{pane_pid}'; }

# 1) mesma sessão em outra largura: nada é recriado; o layout muda pelo IPC
cmd=$T/bin/aerc
fn email_sessao "$cmd" largo || falhou 'criar a sessão oculta'
[[ $(opt @tt_email_modo) == largo && $(opt @tt_email_lateral) == 1 ]] || falhou "sessão nova sem modo/lateral: $(opt @tt_email_modo) $(opt @tt_email_lateral)"
id=$(ident); ipc >/dev/null
fn email_sessao "$cmd" estreito || falhou 'reabrir estreito'
[[ $(ident) == "$id" ]] || falhou 'outra largura recriou a sessão do e-mail (um aerc novo)'
[[ $(ipc) == ':split 0|:toggle-sidebar|' ]] || falhou "estreito deveria tirar prévia e pastas"
[[ $(opt @tt_email_modo) == estreito && $(opt @tt_email_lateral) == 0 ]] || falhou 'modo/lateral não registrados (estreito)'
fn email_sessao "$cmd" amplo; [[ $(ipc) == ':split 0|:vsplit 70|:toggle-sidebar|' ]] || falhou 'amplo deveria pôr a prévia ao lado e as pastas'
fn email_sessao "$cmd" largo; [[ $(ipc) == ':split 0|:split 14|' ]] || falhou 'largo deveria voltar à prévia do aerc.conf'
fn email_sessao "$cmd" largo; [[ -z $(ipc) ]] || falhou 'mesmo modo não deveria mandar nada'
[[ $(ident) == "$id" ]] || falhou 'a sessão mudou ao trocar de largura'
passou 'outra largura reaproveita o mesmo aerc e ajusta o layout pelo IPC'

# 2) aerc recusa (mensagem aberta): abre como está, o modo fica o antigo e a próxima abertura tenta de novo
touch "$T/recusar"
fn email_sessao "$cmd" amplo || falhou 'reabrir com recusa'
[[ $(ident) == "$id" && $(opt @tt_email_modo) == largo ]] || falhou 'recusa do aerc deveria manter a sessão e o modo antigo'
rm -f "$T/recusar"; ipc >/dev/null
fn email_sessao "$cmd" amplo; [[ $(opt @tt_email_modo) == amplo ]] || falhou 'a próxima abertura deveria aplicar o modo'
passou 'aerc ocupado: abre como está e ajusta na próxima'

# 3) recriar mata o aerc antigo mesmo que ele ignore o SIGHUP
cat >"$T/teimoso" <<'EOF'
#!/usr/bin/env bash
trap '' HUP
printf '%s\n' "$$" >"${0%/*}/teimoso.pid"
while :; do sleep 0.2; done
EOF
chmod +x "$T/teimoso"
teimoso_iniciar() {
  rm -f "$T/teimoso.pid"
  tmux new-session -d -s _tt-email "$T/teimoso"
  local n
  for ((n=0; n<100; n++)); do
    [[ -s $T/teimoso.pid ]] && { read -r p <"$T/teimoso.pid"; kill -0 "$p" 2>/dev/null && return 0; }
    sleep .05
  done
  falhou 'falso aerc não instalou a guarda de SIGHUP'
}
tmux kill-session -t =_tt-email
teimoso_iniciar
tmux kill-session -t =_tt-email; sleep 0.5
kill -0 "$p" 2>/dev/null || falhou 'premissa: o falso deveria sobreviver ao kill-session (como o aerc real)'
kill "$p"
teimoso_iniciar
fn email_sessao_encerrar
tmux has-session -t =_tt-email 2>/dev/null && falhou 'a sessão do e-mail deveria ter fechado'
kill -0 "$p" 2>/dev/null && { kill -9 "$p"; falhou 'email_sessao_encerrar deixou o aerc vivo'; }
[[ $(grep -c 'tmux kill-session -t "=\$EMAIL_SESSAO"' "$TT_DIR/tt") == 1 ]] ||
  falhou 'kill-session da sessão do e-mail fora de email_sessao_encerrar (deixa o aerc órfão)'
passou 'recriar a sessão encerra o aerc antigo (ele ignora o SIGHUP)'

# 4) aerc órfão (pai = launchd/init) é encerrado ao criar a sessão; o vivo com pai não
( "$T/bin/aerc" & ); sleep 0.3
o=$(ps -o pid=,ppid=,comm= -u "$(id -u)" | awk '$2 == 1 && $3 ~ /(^|\/)aerc$/ { print $1 }' | tail -1)
"$T/bin/aerc" & vivo=$!
if [[ -n $o ]]; then
  fn email_sessao "$cmd" largo || falhou 'criar com órfão'
  sleep 0.3; kill -0 "$o" 2>/dev/null && falhou 'aerc órfão continuou vivo'
  kill -0 "$vivo" 2>/dev/null || falhou 'aerc com pai vivo não deveria ser encerrado'
  passou 'aerc órfão de antes é encerrado ao abrir o e-mail'
else
  echo '(sem adoção pelo init aqui — subreaper —: verificação do órfão pulada)'
fi
kill "$vivo" 2>/dev/null

# 5) socket do IPC: XDG_RUNTIME_DIR; sem ele, ~/Library/Application Support no macOS e /run/user no resto
[[ $(fn email_ipc_socket) == "$T/rt-x/aerc.sock" ]] || falhou 'com XDG_RUNTIME_DIR o socket fica nele'
s=$(env -u XDG_RUNTIME_DIR TT_SO_CARREGAR=1 bash -c 'source "$1" >/dev/null 2>&1; email_ipc_socket' _ "$TT")
if [[ $(uname -s) == Darwin ]]; then esperado="$HOME/Library/Application Support/aerc.sock"; else esperado=/run/user/$(id -u)/aerc.sock; fi
[[ $s == "$esperado" ]] || falhou "socket sem XDG_RUNTIME_DIR: $s (esperado $esperado)"
passou 'socket do IPC no lugar certo em cada sistema'

echo 'ok: um aerc só — reaproveitado em qualquer largura, encerrado de verdade ao recriar'
