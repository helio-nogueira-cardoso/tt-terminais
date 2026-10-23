#!/usr/bin/env bash
# tt-teste: sozinho (observa os retornos do daemon, sem outro fluxo de voz disputando o prazo)
# O retorno sozinho deve acordar o daemon e responder no canal do pedido.
source "$(dirname "$0")/lib.sh"; isolar
V=$T/pkg/voz; EST=$HOME/.local/state/tt-voz; B=$T/bin; daemon_pid=
mkdir -p "$B" "$T/sd/Tasker/voz/in"
export VOZ_SDCARD=$T/sd VOZ_TELEGRAM=$T/telegram VOZ_TG_API=http://telegram.invalid
export VOZ_T_FUNDO=1 VOZ_RETORNO_POLL=1 VOZ_CEREBRO_CMD='exit 1' VOZ_BIN=$V
cat >"$B/tt" <<FIM
#!/usr/bin/env bash
exec "$TT" "\$@"
FIM
cat >"$B/am" <<'FIM'
#!/usr/bin/env bash
cat "$VOZ_SDCARD/Tasker/voz/fala.txt" >>"$VOZ_SDCARD/tasker.log"
printf '\n' >>"$VOZ_SDCARD/tasker.log"
printf 0 >"$VOZ_SDCARD/Tasker/voz/falando"
FIM
cat >"$B/curl" <<'FIM'
#!/usr/bin/env bash
case "$*" in
  *http://telegram.invalid/*getUpdates*) sleep 0.2; printf '{"ok":true,"result":[]}' ;;
  *http://telegram.invalid/*sendMessage*)
    for a; do [[ $a == text=* ]] && printf '%s\n' "${a#text=}" >>"$VOZ_SDCARD/telegram.log"; done ;;
  *) exit 1 ;;
esac
FIM
cat >"$B/agente" <<'FIM'
#!/usr/bin/env bash
printf 'AGENTE PRONTO\n> '
while IFS= read -r l; do
  printf 'Working… (esc to interrupt)\n'; sleep 1
  printf 'Feito: %s.\n> ' "$l"
  printf '{"last_assistant_message":"Feito: %s."}' "$l" | "$VOZ_BIN" --evento terminou claude
done
FIM
chmod +x "$B"/*; export PATH="$B:$PATH"
encerrar_daemon() {
  if [[ -n $daemon_pid ]]; then kill "$daemon_pid" 2>/dev/null || true; wait "$daemon_pid" 2>/dev/null || true; daemon_pid=; fi
}
esperar_texto() {
  local f=$1 texto=$2 i
  for ((i=0; i<200; i++)); do grep -qF "$texto" "$f" 2>/dev/null && return 0; sleep 0.1; done
  falhou "não chegou '$texto' em ${f##*/}: $(tail -10 "$T/daemon.log" 2>/dev/null)"
}
enviar() { printf '%s\n' "$2" >"$T/entrada.tmp"; mv "$T/entrada.tmp" "$VOZ_SDCARD/Tasker/voz/in/$1.txt"; }
tmux new-session -d -s trabalho "$B/agente"; tmux set-option -t '=trabalho:' @tt_voz 1
for i in {1..100}; do tmux capture-pane -p -t '=trabalho:' | grep -q 'AGENTE PRONTO' && break; sleep 0.1; done
VOZ_MUDO=1 bash "$V" 'aba trabalho' >/dev/null

for canal in tasker telegram; do
  prefixo=cmd; [[ $canal == telegram ]] && { prefixo=tg; printf 'TOKEN=teste\nCHAT=42\n' >"$VOZ_TELEGRAM"; }
  log=$VOZ_SDCARD/$canal.log
  tarefa_antes=0; [[ -f $VOZ_SDCARD/tasker.log ]] && tarefa_antes=$(wc -l <"$VOZ_SDCARD/tasker.log")
  VOZ_MUDO= bash "$V" --daemon >"$T/daemon.log" 2>&1 & daemon_pid=$!
  enviar "$prefixo-modo" 'modo retorno'
  esperar_texto "$log" 'Modo retorno: fecho o microfone.'
  enviar "$prefixo-pedido" "verifique pelo $canal"
  esperar_texto "$log" "Enviado para trabalho. Te chamo quando responder."
  for f in agenda acompanhar pendente; do [[ ! -s $EST/$f ]] || falhou "retorno dependeu de $f"; done
  esperar_texto "$log" "A sessão trabalho respondeu: Feito: verifique pelo $canal."
  esperar_texto "$log" 'Era a última resposta que eu esperava: saí do modo retorno.'
  [[ ! -e $EST/retorno ]] || falhou 'o daemon não saiu do modo após o último retorno'
  enviar "$prefixo-prazo" 'modo retorno por 1 segundo'
  esperar_texto "$log" 'Passou o prazo e nada mudou: nenhuma sessão trabalha num pedido seu.'
  encerrar_daemon
  [[ $(grep -cF "A sessão trabalho respondeu: Feito: verifique pelo $canal." "$log") == 1 ]] || falhou 'o daemon repetiu a resposta'
  if [[ $canal == telegram ]]; then
    [[ $(wc -l <"$VOZ_SDCARD/tasker.log") == "$tarefa_antes" ]] || falhou 'retorno do Telegram foi para o Tasker'
  fi
  passou "daemon: retorno e prazo sozinhos acordam pelo $canal, sem fala duplicada"
done
