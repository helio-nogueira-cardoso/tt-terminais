#!/usr/bin/env bash
# Navegador gráfico abre na máquina da TELA em que se clicou, não na da sessão; no macOS, o navegador
# padrão do sistema fica local no MacBook:
#  1) fora do macOS, cliente que é ponte de outra máquina (TT_PONTE): vai por ssh para lá (tt --abrir-aqui);
#  2) fora do macOS, cliente de dentro do popup do e-mail (TT_ORIGEM, posto pelo email_origem): idem;
#  3) a de lá não responde: abre aqui, como antes;
#  4) cliente desta máquina: abre aqui, sem ssh;
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
exit 0
EOF
chmod +x "$B/ssh"
export PATH="$B:$PATH"
printf 'nome=teste\nnavegador=sistema\n' >"$XDG_CONFIG_HOME/tt/config"
printf '192.0.2.7 ninguem book-x\n' >"$XDG_CONFIG_HOME/tt/maquinas"
U='https://exemplo.com/a?b=1&c=#x'

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

# Mesmo com a tela em ponte para outra máquina, no macOS o Chromium é o Chrome.app local.
# Simulação independente do host: app bundle e LaunchServices são falsos, nenhuma GUI é aberta.
MACAPP="$HOME/Applications/Google Chrome.app"
mkdir -p "$MACAPP/Contents/MacOS"; : >"$MACAPP/Contents/Info.plist"
cat >"$B/open" <<EOF
#!/bin/sh
printf '<%s>\\n' "\$@" >>$T/mac-open.log
EOF
chmod +x "$B/open"
printf 'nome=teste\nnavegador=chromium\n' >"$XDG_CONFIG_HOME/tt/config"
limpa; TT_SO=macos TT_LINK_CLIENTE=$c_ponte "$TT" --abrir-link "$U" </dev/null
espera "$T/mac-open.log" && grep -Fq "<$U>" "$T/mac-open.log" && ! [[ -s $T/ssh.log ]] ||
  falhou "Chromium do Mac foi encaminhado à máquina da sessão ou não abriu localmente (open=$(cat "$T/mac-open.log" 2>/dev/null), ssh=$(cat "$T/ssh.log" 2>/dev/null))"
passou 'Chromium interno: cliente em ponte abre o Chrome.app local do Mac, não na máquina remota'

printf 'nome=teste\nnavegador=sistema\n' >"$XDG_CONFIG_HOME/tt/config"
limpa; TT_LINK_CLIENTE=$c_ponte "$TT" --abrir-link "$U" </dev/null
if [[ $(uname -s) == Darwin ]]; then
  espera "$local_log" && [[ $(cat "$local_log") == "$U" && ! -s $T/ssh.log ]] || falhou 'no MacBook o navegador nativo não deveria ser encaminhado à máquina TT_PONTE'
  passou 'cliente ponte no MacBook: navegador nativo abre localmente, não na máquina da sessão'
else
espera "$T/ssh.log" || falhou 'cliente de ponte: não foi por ssh para a máquina da tela'
grep -q -- '--abrir-aqui sistema' "$T/ssh.log" || falhou "comando remoto inesperado: $(cat "$T/ssh.log")"
[[ $(bash -c "set -- $(sed 's/.*--abrir-aqui //' "$T/ssh.log"); printf %s \"\$2\"") == "$U" ]] || falhou "URL chegou partida: $(cat "$T/ssh.log")"
sleep 0.5; [[ ! -s $T/xdg.log ]] || falhou "cliente de ponte: abriu também aqui: $(cat "$T/xdg.log")"
passou 'ponte de outra máquina: o link vai por ssh para a máquina da tela, com a URL inteira'
fi

limpa; TT_LINK_CLIENTE=$c_email "$TT" --abrir-link "$U" </dev/null
if [[ $(uname -s) == Darwin ]]; then
  espera "$local_log" && [[ $(cat "$local_log") == "$U" && ! -s $T/ssh.log ]] || falhou 'cliente de e-mail no MacBook deveria abrir o navegador nativo local'
else
espera "$T/ssh.log" && grep -q -- '--abrir-aqui sistema' "$T/ssh.log" || falhou 'cliente do e-mail (TT_ORIGEM): não foi para a máquina da tela'
fi
passou 'cliente de dentro do popup do e-mail (TT_ORIGEM): idem'

limpa; touch "$T/ssh-falha"; TT_LINK_CLIENTE=$c_ponte "$TT" --abrir-link "$U" </dev/null
espera "$local_log" && [[ $(cat "$local_log") == "$U" ]] || falhou "máquina da tela fora do ar ou Mac local: deveria abrir aqui ('$(cat "$local_log" 2>/dev/null)')"
rm -f "$T/ssh-falha"
passou 'máquina da tela fora do ar: abre aqui, como antes'

limpa; TT_LINK_CLIENTE=$c_local "$TT" --abrir-link "$U" </dev/null
espera "$local_log" && [[ $(cat "$local_log") == "$U" ]] || falhou 'cliente desta máquina: não abriu aqui'
[[ ! -s $T/ssh.log ]] || falhou "cliente desta máquina: não deveria usar ssh ($(cat "$T/ssh.log"))"
passou 'cliente desta máquina: abre aqui, sem ssh'

src=$(sed -n '/^email_origem() {/p; /^origem_ponte() {/,/^}/p; /^env_do_pid() {/,/^}/p; /^do_cliente() {/,/^}/p; /^q() {/,/^}/p' "$TT")
grep -q '^email_origem()' <<<"$src" || falhou 'email_origem não encontrado'
[[ $(bash -c "$src"'
 email_origem "$1"' _ "$c_ponte") == "TT_ORIGEM=book-x " ]] || falhou "email_origem do cliente de ponte: '$(bash -c "$src"'
 email_origem "$1"' _ "$c_ponte")'"
[[ -z $(bash -c "$src"'
 email_origem "$1"' _ "$c_local") ]] || falhou 'email_origem de cliente local deveria ser vazio'
passou 'popup do e-mail aberto de uma ponte leva TT_ORIGEM ao cliente de dentro'

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
