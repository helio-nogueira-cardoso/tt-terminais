#!/usr/bin/env bash
# Abrir pelo aviso mostra a mensagem nova: o aviso "📧 Conta: N e-mails novos" sai com a ação
# email:SLUG; notif_abrir leva a email_ir_novo, que marca os avisos da conta como lidos e, pelo IPC
# do aerc (nunca teclas cegas), vai à conta (:change-tab), ao INBOX (:cf), foca a não lida mais
# recente (:select 0 + :search -u), abre a mensagem na tela estreita (:view) e confere (:check-mail);
# fecha antes a tela do tt que estiver na frente; sem socket, sem sessão ou com erro do aerc não
# manda nada. aerc falso que registra os comandos recebidos; sessão oculta com um "aerc" vivo.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
mkdir -p "$T/bin" "$T/rt-x"
export XDG_RUNTIME_DIR=$T/rt-x
# aerc falso: --version responde; qualquer outro argumento é um comando IPC, registrado; a aba
# "Nada" não existe (responde erro como o aerc real)
cat >"$T/bin/aerc" <<'EOF'
#!/usr/bin/env bash
[[ $1 == --version ]] && { echo "aerc 0.21.0"; exit 0; }
printf '%s\n' "$*" >>"${AERC_IPC_LOG:-/dev/null}"
[[ $* == *Nada* ]] && echo 'response: No tab with that name'
exit 0
EOF
chmod +x "$T/bin/aerc"; export PATH=$T/bin:$PATH AERC_IPC_LOG=$T/ipc.log
tt() { "$TT" "$@"; }
ipc() { cat "$AERC_IPC_LOG" 2>/dev/null; }
socket_criar() { python3 -I -c 'import socket, sys; s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$XDG_RUNTIME_DIR/aerc.sock"; }

grep -q 'email:\*) email_ir_novo' "$TT" || falhou 'notif_abrir sem a rota email:SLUG → email_ir_novo'
grep -q '"\$corpo" "email:\$slug"' "$TT" || falhou 'email_novos_avisar deveria avisar com a ação email:SLUG'
for fn in email_ipc email_saltar_novo email_ir_novo email_avisos_lidos; do grep -q "^$fn()" "$TT" || falhou "função $fn ausente"; done
passou 'rota email:SLUG no notif_abrir, aviso com a ação email:SLUG, funções do salto'

echo 'S' | tt --email-adicionar nome=Gmail endereco=g@gmail.com provedor=gmail auth=senha sync_local=1 --senha-stdin >/dev/null || falhou 'cadastro gmail'
echo 'S' | tt --email-adicionar nome=Nada endereco=n@gmail.com provedor=gmail auth=senha --senha-stdin >/dev/null || falhou 'cadastro nada'

# 1) sem sessão oculta e sem socket: nada vai ao aerc
tt --email-saltar-novo gmail && falhou 'sem sessão oculta deveria falhar'
[[ -z $(ipc) ]] || falhou "sem sessão nada deveria ir ao aerc: $(ipc)"
passou 'sem sessão oculta: nenhum comando ao aerc'

# 2) sessão oculta com aerc vivo + socket: a sequência certa, na ordem, sem :view (tela larga)
tmux new-session -d -s _tt-email -x 150 -y 40 'exec -a aerc python3 -c "import time; time.sleep(600)"'
tmux set -q -t =_tt-email: @ponte email; tmux set -q -t =_tt-email: @tt_email_modo largo
sleep 0.5
tt --email-saltar-novo gmail && falhou 'sem socket deveria falhar'
[[ -z $(ipc) ]] || falhou "sem socket nada deveria ir ao aerc: $(ipc)"
socket_criar
tt --email-saltar-novo gmail || falhou 'salto com sessão e socket deveria dar certo'
[[ $(ipc | tr '\n' '|') == ':change-tab Gmail|:cf INBOX|:select 0|:search -u|:check-mail|' ]] || falhou "sequência do salto errada: $(ipc | tr '\n' '|')"
passou 'salto: :change-tab Conta → :cf INBOX → :select 0 → :search -u → :check-mail (sem :view na tela larga)'

# 3) tela estreita (sem prévia): abre a mensagem (:view) depois de focar
: >"$AERC_IPC_LOG"; tmux set -q -t =_tt-email: @tt_email_modo estreito
tt --email-saltar-novo gmail || falhou 'salto na tela estreita'
[[ $(ipc | tr '\n' '|') == ':change-tab Gmail|:cf INBOX|:select 0|:search -u|:view|:check-mail|' ]] || falhou "estreito deveria abrir a mensagem: $(ipc | tr '\n' '|')"
tmux set -q -t =_tt-email: @tt_email_modo largo
passou 'tela estreita: :view depois de focar a não lida'

# 4) o aerc responde erro na troca de aba (conta sem aba): para ali, sem :cf nem :search
: >"$AERC_IPC_LOG"
tt --email-saltar-novo nada && falhou 'erro do aerc na troca de aba deveria falhar'
[[ $(ipc | tr '\n' '|') == ':change-tab Nada|' ]] || falhou "depois do erro nada mais deveria ir: $(ipc | tr '\n' '|')"
passou 'erro do aerc (response: …) interrompe o salto'

# 5) abrir pelo aviso: email_ir_novo fecha a tela do tt na frente, salta e marca os avisos da conta
#    como lidos (<id>.lida); avisos de outra conta e de outros destinos ficam
: >"$AERC_IPC_LOG"
tmux new-window -t =_tt-email: -n '👤 contas' 'sleep 600'; tmux set -wq -t =_tt-email: @tt_email_tela contas
[[ $(tmux list-windows -t =_tt-email | wc -l) == 2 ]] || falhou 'tela do tt não abriu na sessão oculta'
N=$HOME/.local/state/tt/notifs
tt --notificar '📧 Gmail: 1 e-mail novo · Ana — Oi' 600 email:gmail; sleep 0.01
tt --notificar '📧 Nada: 1 e-mail novo · Bob — Olá' 600 email:nada; sleep 0.01
tt --notificar '📋 hoje · pagar' 600 tarefas
[[ $(ls -1 "$N" | wc -l) == 3 ]] || falhou "deveriam existir 3 avisos: $(ls "$N")"
TT_EMAIL_SEM_POPUP=1 tt --email-ir-novo gmail base || falhou 'email_ir_novo falhou'
[[ $(tmux list-windows -t =_tt-email | wc -l) == 1 ]] || falhou 'a tela do tt na frente deveria ter sido fechada'
grep -q '^:change-tab Gmail$' "$AERC_IPC_LOG" && grep -q '^:search -u$' "$AERC_IPC_LOG" || falhou "ir-novo deveria saltar: $(ipc | tr '\n' '|')"
lidas=0; for f in "$N"/*; do [[ $f == *.lida ]] && continue; IFS=$'\t' read -r _ _ a <"$f"
  case $a in
    email:gmail) [[ -e $f.lida ]] || falhou "aviso do gmail deveria estar lido: $f"; lidas=$((lidas + 1)) ;;
    *) [[ -e $f.lida ]] && falhou "aviso $a não deveria ser marcado: $f" ;;
  esac; done
[[ $lidas == 1 ]] || falhou "deveria ter marcado 1 aviso do gmail, marcou $lidas"
passou 'abrir pelo aviso: fecha a tela do tt, salta e marca só os avisos da conta como lidos'

# 6) conta desconhecida: não salta (abre como sempre) e não derruba nada
: >"$AERC_IPC_LOG"
TT_EMAIL_SEM_POPUP=1 tt --email-ir-novo inexistente base || falhou 'conta desconhecida deveria só abrir'
[[ -z $(ipc) ]] || falhou "conta desconhecida não deveria mandar nada ao aerc: $(ipc)"
passou 'conta desconhecida: sem salto, sem erro'

# 7) sem sessão oculta: o salto fica agendado para quando o aerc subir (sessão + socket), em 2º plano
tmux kill-session -t _tt-email; rm -f "$XDG_RUNTIME_DIR/aerc.sock"; : >"$AERC_IPC_LOG"
TT_EMAIL_SEM_POPUP=1 tt --email-ir-novo gmail base || falhou 'ir-novo sem sessão'
sleep 1.2; [[ -z $(ipc) ]] || falhou "antes do aerc subir nada deveria ir: $(ipc)"
tmux new-session -d -s _tt-email -x 150 -y 40 'exec -a aerc python3 -c "import time; time.sleep(600)"'
tmux set -q -t =_tt-email: @tt_email_modo largo; socket_criar
for i in $(seq 1 20); do grep -q '^:check-mail$' "$AERC_IPC_LOG" 2>/dev/null && break; sleep 0.5; done
[[ $(ipc | tr '\n' '|') == ':change-tab Gmail|:cf INBOX|:select 0|:search -u|:check-mail|' ]] || falhou "salto adiado errado: $(ipc | tr '\n' '|')"
passou 'sessão oculta ausente: o salto espera o aerc subir e vai sozinho'

echo 'ok: abrir pelo aviso vai à conta e à mensagem nova pelo IPC do aerc, e marca o aviso como lido'
