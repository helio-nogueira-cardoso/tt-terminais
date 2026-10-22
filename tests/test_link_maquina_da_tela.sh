#!/usr/bin/env bash
# Navegador abre na origem física do clique em qualquer plataforma; falha remota não muda o destino.
source "$(dirname "$0")/lib.sh"; isolar
export BROWSER=
path_sem_termux_open_url
O() { fora "$@"; }
B=$T/bin; mkdir -p "$B"
printf '#!/bin/sh\necho "$1" >> %s\n' "$T/xdg.log" >"$B/xdg-open"; chmod +x "$B/xdg-open"
local_log=$T/xdg.log
# ssh falso: registra o comando remoto; SSH_FALHA=1 simula a máquina de lá fora do ar.
cat >"$B/ssh" <<EOF
#!/bin/sh
for a; do last=\$a; done
echo "\$last" >> $T/ssh.log
[ -f $T/ssh-falha ] && exit 255
[ -f $T/ssh-sem-ack ] || echo tt-abriu
exit 0
EOF
chmod +x "$B/ssh"
export PATH="$B:$PATH"
printf 'nome=teste\nnavegador=sistema\n' >"$XDG_CONFIG_HOME/tt/config"
printf '192.0.2.7 ninguem book-x\n' >"$XDG_CONFIG_HOME/tt/maquinas"
U="https://exemplo.com/a?b=1&c='teste'&n=\$(nao-executar)#x"

tmux -f /dev/null new -d -s sessao 'sleep 600'
O new -d -s ponte -x 100 -y 20 "env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR TT_PONTE='book-x|ponte-1' tmux attach -t sessao"
O new -d -s local -x 90 -y 20 "env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t sessao"
O new -d -s email -x 80 -y 20 "env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR TT_ORIGEM=book-x tmux attach -t sessao"
sleep 1
cli() { tmux list-clients -F '#{client_width} #{client_name}' | awk -v w="$1" '$1 == w { print $2 }'; }
c_ponte=$(cli 100) c_local=$(cli 90) c_email=$(cli 80)
[[ -n $c_ponte && -n $c_local && -n $c_email ]] || falhou "clientes de teste não subiram: $(tmux list-clients)"
espera() { local i; for ((i = 0; i < 30; i++)); do [[ -s $1 ]] && return 0; sleep 0.1; done; return 1; }
limpa() { rm -f "$T/xdg.log" "$T/ssh.log"; }

# Mac e Linux seguem a origem da tela, não o sistema da sessão.
for so in macos linux; do
  for nav in chromium sistema; do
    printf 'nome=teste\nnavegador=%s\n' "$nav" >"$XDG_CONFIG_HOME/tt/config"
    limpa; TT_SO=$so TT_LINK_CLIENTE=$c_ponte "$TT" --abrir-link "$U" </dev/null
    espera "$T/ssh.log" || falhou "$so/$nav: não encaminhou à origem"
    grep -Eq -- "--abrir-aqui '?$nav'? " "$T/ssh.log" || falhou "navegador remoto errado: $(cat "$T/ssh.log")"
    python3 - "$T/ssh.log" "$U" <<'PY' || falhou 'URL alterada no encaminhamento remoto'
import pathlib, shlex, sys
args = shlex.split(pathlib.Path(sys.argv[1]).read_text())
assert args[args.index('--abrir-aqui')+2] == sys.argv[2], args
PY
    sleep 0.5
    [[ ! -s $local_log ]] || falhou "$so/$nav: abriu também nesta máquina"
  done
done
passou 'Mac e Linux encaminham Chromium e navegador do sistema para a origem do clique'
printf 'nome=teste\nnavegador=sistema\n' >"$XDG_CONFIG_HOME/tt/config"
limpa; TT_LINK_CLIENTE=$c_email "$TT" --abrir-link "$U" </dev/null
espera "$T/ssh.log" && grep -Eq -- "--abrir-aqui '?sistema'? " "$T/ssh.log" || falhou 'e-mail perdeu TT_ORIGEM'
sleep 0.5; [[ ! -s $local_log ]] || falhou 'popup de e-mail abriu na máquina errada'
passou 'popup de e-mail preserva a origem do clique'

for erro in ssh-falha ssh-sem-ack; do
  limpa; touch "$T/$erro"
  TT_LINK_CLIENTE=$c_ponte "$TT" --abrir-link "$U" </dev/null
  espera "$T/ssh.log" || falhou 'não tentou alcançar a origem'
  sleep 1
  [[ ! -s $local_log ]] || falhou 'falha remota abriu silenciosamente na máquina errada'
  rm -f "$T/$erro"
done
passou 'falha de SSH ou ausência de confirmação não redireciona para outra máquina'

limpa; TT_LINK_CLIENTE=$c_local "$TT" --abrir-link "$U" </dev/null
espera "$local_log" && [[ $(cat "$local_log") == "$U" ]] || falhou 'cliente desta máquina: não abriu aqui'
[[ ! -s $T/ssh.log ]] || falhou "cliente desta máquina: não deveria usar ssh ($(cat "$T/ssh.log"))"
passou 'cliente desta máquina: abre aqui, sem ssh'

src=$(sed -n '/^email_origem() {/p; /^maquina_da_tela() {/,/^}/p; /^env_do_pid() {/,/^}/p; /^do_cliente() {/,/^}/p; /^q() {/,/^}/p' "$TT")
grep -q '^email_origem()' <<<"$src" || falhou 'email_origem não encontrado'
[[ $(bash -c "$src"'
 email_origem "$1"' _ "$c_ponte") == "TT_ORIGEM=book-x " ]] || falhou "email_origem do cliente de ponte: '$(bash -c "$src"'
 email_origem "$1"' _ "$c_ponte")'"
[[ -z $(bash -c "$src"'
 email_origem "$1"' _ "$c_local") ]] || falhou 'email_origem de cliente local deveria ser vazio'
passou 'popup do e-mail aberto de uma ponte leva TT_ORIGEM ao cliente de dentro'
[[ $(bash -c "$src"'; email_origem "$1"' _ "$c_email") == 'TT_ORIGEM=book-x ' ]] || falhou 'e-mail aninhado perdeu a origem'

# No w3m do e-mail (unshare --map-root-user --net) o environ do cliente é negado: o servidor do tmux lê por ele.
if unshare --map-root-user --net true 2>/dev/null; then
  src_m=$(sed -n '/^maquina_da_tela() {/,/^}/p; /^do_cliente() {/,/^}/p; /^env_do_pid() {/,/^}/p' "$TT")
  # como no e-mail de verdade: o aerc roda num painel, com TMUX (dentro do namespace o uid é 0 e o socket padrão seria outro)
  r=$(MAQUINA=aqui TMUX="$TMUX_TMPDIR/tmux-$(id -u)/default,0,0" unshare --map-root-user --net bash -c "$src_m"$'\n''maquina_da_tela "$1"' _ "$c_ponte")
  [[ $r == book-x ]] || falhou "dentro do isolamento do w3m não achou a máquina da tela: '$r'"
  passou 'dentro do isolamento do w3m (environ negado) a máquina da tela vem pelo servidor do tmux'
else
  passou 'isolamento do w3m: unshare indisponível aqui (pulado)'
fi
