#!/usr/bin/env bash
# voz (termux/bin/voz): comandos por frase, troca de máquina/sessão, trava de sessões, resposta do agente e daemon.
# Tudo com tt/ssh/am falsos e um tmux isolado; nada toca máquinas, celular ou Tasker reais.
source "$(dirname "$0")/lib.sh"; isolar
V=$RAIZ/termux/bin/voz
bash -n "$V" || falhou "sintaxe: $V"

B=$T/fake; mkdir -p "$B" "$T/sd/Tasker"
cat >"$B/tt" <<'FIM'
#!/usr/bin/env bash
case $1 in
  --maquinas) printf 'u@h1 dell\nu@h2 book\n' ;;
  --saude) printf 'Saude das maquinas cadastradas:\n  \033[32m●\033[0m dell             ok\n  \033[31m●\033[0m book             timeout   tempo esgotado\n' ;;
  --listar-tudo) printf '# mestre de obras — celular — 20260101T000000Z\n' ;;
  --tarefas-lista) printf 'abc123abc123\t \033[1m▸\033[0m ☐ ● zz01 Pagar o boleto  abc123abc123\n' ;;
esac
FIM
cat >"$B/ssh" <<'FIM'
#!/usr/bin/env bash
# ssh falso: descarta opções e o destino, roda o comando aqui
while [[ $1 == -* ]]; do [[ $1 == -o ]] && shift; shift; done; shift
exec bash -c "$*"
FIM
cat >"$B/am" <<'FIM'
#!/usr/bin/env bash
echo "$*" >>"$VOZ_AM_LOG"
FIM
cat >"$B/agente.sh" <<'FIM'
#!/usr/bin/env bash
while IFS= read -r l; do sleep 1; printf '● Entendi: %s. Tudo certo por aqui.\n' "$l"; done
FIM
printf '#!/usr/bin/env bash\necho isKeyguardShowing=false\n' >"$B/tt-rish"
cat >"$B/curl" <<'FIM'
#!/usr/bin/env bash
# Telegram falso: getMe, getUpdates (um /start do chat 42, de um estranho e um texto do 42) e sendMessage (registrado)
echo "$*" >>"$VOZ_CURL_LOG"
agora=$(date +%s)
case "$*" in
  *getMe*) echo '{"ok":true,"result":{"username":"bot_teste"}}' ;;
  *getUpdates*offset=0*|*getUpdates*timeout=0*)
    printf '{"ok":true,"result":[{"update_id":7,"message":{"date":%s,"chat":{"id":42,"type":"private","first_name":"Dono"},"text":"/start"}},{"update_id":8,"message":{"date":%s,"chat":{"id":99,"type":"private"},"text":"estranho"}},{"update_id":9,"message":{"date":%s,"chat":{"id":42,"type":"private"},"text":"onde"}}]}\n' "$agora" "$agora" "$agora" ;;
  *getUpdates*) sleep 1; echo '{"ok":true,"result":[]}' ;;
esac
FIM
cat >"$B/ia-conta" <<'FIM'
#!/usr/bin/env bash
echo "principal 12 por cento"
FIM
chmod +x "$B"/*
export PATH="$B:$PATH" VOZ_SDCARD=$T/sd VOZ_AM_LOG=$T/am.log VOZ_ESPERA_FALA=0 VOZ_CURL_LOG=$T/curl.log
export VOZ_TELEGRAM=$T/segredos/telegram VOZ_TG_LIGAR=2 VOZ_TG_PAUSA=1
tmux new-session -d -s agente-teste "$B/agente.sh"
tmux new-session -d -s _oculta 'sleep 600'
v() { VOZ_MUDO=1 bash "$V" "$@"; }

[[ $(v maquinas) == *dell* && $(v maquinas) == *book* && $(v maquinas) == *celular* ]] || falhou "máquinas: $(v maquinas)"
saida=$(v status); [[ $saida == *"dell ok"* && $saida == *"book fora do ar"* ]] || falhou "status: $saida"
passou 'voz: máquinas e status'

saida=$(v "ir para del"); [[ $saida == *"Agora em dell"* ]] || falhou "ir para: $saida"
[[ $(<"$HOME/.local/state/tt-voz/alvo_m") == dell ]] || falhou 'alvo_m não gravado'
saida=$(v sessoes); [[ $saida == *agente* && $saida != *oculta* ]] || falhou "sessões (as _ocultas ficam fora): $saida"
v "ir para marte" | grep -q 'Não achei' || falhou 'máquina inexistente não foi recusada'
passou 'voz: trocar de máquina e listar sessões (ocultas fora)'

saida=$(v "aba agente"); [[ $saida == *"Não liberada"* ]] || falhou "aba: $saida"
saida=$(v "oi mundo"); [[ $saida == *"não está liberada"* ]] || falhou "texto livre sem liberação: $saida"
tmux capture-pane -p -t '=agente-teste:' | grep -q 'oi mundo' && falhou 'enviou texto a sessão não liberada'
passou 'voz: sessão não liberada não recebe texto'

v "permitir sessao" | grep -q liberada || falhou 'permitir sessão'
saida=$(v "oi mundo"); [[ $saida == *"Enviado para agente-teste"* && $saida == *"Entendi: oi mundo"* ]] || falhou "resposta do agente: $saida"
saida=$(v repetir); [[ $saida == *'Entendi: oi mundo'* && $saida != *Enviado* ]] || falhou "repetir (o aviso não conta): $saida"
saida=$(VOZ_ESPERA=1 v "devagar"); [[ $saida == *"ainda está trabalhando"* ]] || falhou "agente demorado: $saida"
saida=$(v repetir); [[ $saida == *'Entendi: devagar'* ]] || falhou "repetir depois da demora confere a sessão de novo: $saida"
[[ -e $HOME/.local/state/tt-voz/pendente ]] && falhou 'pendente ficou depois da resposta'
v bloquear sessao >/dev/null; v "qualquer coisa" | grep -q 'não está liberada' || falhou 'bloquear sessão'
passou 'voz: texto vai à sessão liberada e a resposta volta resumida'

v tarefas | grep -q 'Pagar o boleto' || falhou 'tarefas'
v contas | grep -q 'principal' || falhou 'contas'
v "" | grep -q 'diga ajuda e um tema' || falhou 'ajuda geral'
v ajuda | grep -q 'diga ajuda e um tema' || falhou 'ajuda'
v "ajuda sessões" | grep -q 'aba e uma palavra do nome' || falhou 'ajuda sessões'
v "ajuda com o agente" | grep -q 'permitir sessão' || falhou 'ajuda agente'
v "ajuda maquinas" | grep -q 'ir para notebook' || falhou 'ajuda máquinas'
v "ajuda conversa" | grep -q 'volto a ouvir' || falhou 'ajuda conversa'
v comandos | grep -q 'bloquear sessão' || falhou 'comandos'
saida=$(v terminal); [[ $saida == *"Máquina dell, sessão agente-teste"* && $saida == *"Pode falar"* ]] || falhou "abrir conversa: $saida"
v encerrar | grep -q 'Terminal encerrado' || falhou 'encerrar'
passou 'voz: tarefas, contas, ajuda, abrir e encerrar a conversa'

# fala: grava o texto e avisa o Tasker (intent tt.VOZ_FALAR); com VOZ_MUDO não faz nada
bash "$V" --falar "olá carro" >/dev/null
[[ $(<"$T/sd/Tasker/voz/fala.txt") == "olá carro" ]] && grep -q 'tt.VOZ_FALAR' "$T/am.log" || falhou 'fala não chegou ao Tasker'
grep -q 'ouvir' "$T/am.log" && falhou 'fala comum não deveria levar ouvir=0'
[[ $(<"$T/sd/Tasker/voz/falando") == 1 ]] || falhou 'falando não marcado'
: >"$T/am.log"; VOZ_MUDO= bash "$V" encerrar >/dev/null; grep -q -- '--es ouvir 0' "$T/am.log" || falhou "aviso sem ouvir=0: $(cat "$T/am.log")"
# o Tasker zera "falando" quando termina; enquanto está em 1 (e é recente), a próxima fala espera
printf 1 >"$T/sd/Tasker/voz/falando"; ( sleep 2; printf 0 >"$T/sd/Tasker/voz/falando" ) &
ini=$SECONDS; VOZ_ESPERA_FALA=20 bash "$V" --falar "depois" >/dev/null; (( SECONDS - ini >= 2 )) || falhou 'fala atropelou a anterior'
wait
: >"$T/am.log"; v --falar mudo >/dev/null; [[ -s $T/am.log ]] && falhou 'VOZ_MUDO falou'
passou 'voz: fala via intent tt.VOZ_FALAR, avisos sem ouvir e sem atropelar'

# --abrir manda tt.VOZ_ABRIR; sem microfone e sem Telegram: pede para desbloquear (uma vez por conversa)
: >"$T/am.log"; bash "$V" --abrir >/dev/null; grep -q 'tt.VOZ_ABRIR' "$T/am.log" || falhou '--abrir não chamou o Tasker'
v __sem_microfone__ | grep -q 'Desbloqueie' || falhou 'sem microfone: instrução'
[[ -z $(v __sem_microfone__) ]] || falhou 'sem microfone: instrução repetida na mesma conversa'
v __android_auto__ | grep -q . && falhou 'Android Auto sem Telegram não deveria dizer nada'
bash "$V" --carro CarMode >/dev/null; [[ $(<"$T/sd/Tasker/voz/carro.txt") == CarMode ]] || falhou '--carro'
bash "$V" --carro - >/dev/null; [[ -e $T/sd/Tasker/voz/carro.txt ]] && falhou '--carro - não desligou'
passou 'voz: --abrir, --carro e o aviso de microfone indisponível'

# Telegram: --telegram confere o token, pega o chat de quem tocou em Começar e guarda tudo em arquivo 600
bash "$V" --telegram semdoispontos >/dev/null 2>&1 && falhou '--telegram aceitou token inválido'
saida=$(bash "$V" --telegram 123:abc 2>&1); [[ $saida == *bot_teste* && $saida == *Dono* ]] || falhou "--telegram: $saida"
grep -qx 'TOKEN=123:abc' "$VOZ_TELEGRAM" && grep -qx 'CHAT=42' "$VOZ_TELEGRAM" || falhou 'segredo do Telegram incompleto'
[[ $(stat -c %a "$VOZ_TELEGRAM") == 600 ]] || falhou 'segredo do Telegram não é 600'
grep -q 'sendMessage' "$T/curl.log" || falhou '--telegram não confirmou no chat'
bash "$V" --contato "Terminal de Teste" >/dev/null; v terminal >/dev/null
saida=$(v __sem_microfone__); [[ $saida == *'pelo Telegram, na conversa do Terminal de Teste'* ]] || falhou "sem microfone com Telegram: $saida"
: >"$T/curl.log"; VOZ_MUDO= bash "$V" __android_auto__ >/dev/null
grep -q 'Terminal de Teste pronto' <(sed 's/+/ /g; s/%20/ /g' "$T/curl.log") || falhou "Android Auto: aviso do bot: $(cat "$T/curl.log")"
: >"$T/curl.log"; VOZ_MUDO= bash "$V" __android_auto__ >/dev/null; grep -q sendMessage "$T/curl.log" && falhou 'Android Auto avisou duas vezes em 30 min'
passou 'voz: --telegram liga o bot; Android Auto avisa pelo bot uma vez'

# daemon e garantir: nada sobe sem o marcador de ativação
bash "$V" --garantir; sleep 1; [[ -e $HOME/.local/state/tt-voz/daemon.pid ]] && falhou 'garantir subiu o daemon sem ativação'
mkdir -p "$T/sd/Tasker/voz/in"; echo "onde" >"$T/sd/Tasker/voz/in/1.txt"
VOZ_MUDO= bash "$V" --daemon >/dev/null 2>&1 & dp=$!
for i in $(seq 20); do [[ -e $T/sd/Tasker/voz/in/1.txt ]] || break; sleep 0.5; done
sleep 1; kill "$dp" 2>/dev/null; wait "$dp" 2>/dev/null || true
grep -q 'Máquina dell' "$T/sd/Tasker/voz/fala.txt" || falhou "daemon não respondeu: $(cat "$T/sd/Tasker/voz/fala.txt")"
passou 'voz: daemon lê a entrada do Tasker e responde; garantir só age depois de ativado'

# daemon com Telegram: o que chega do seu chat é respondido pelo bot, não pelo Tasker; estranhos são ignorados
rm -f "$HOME/.local/state/tt-voz/tg_offset"; : >"$T/curl.log"; : >"$T/am.log"
VOZ_MUDO= bash "$V" --daemon >/dev/null 2>&1 & dp=$!
for i in $(seq 60); do grep -q 'sendMessage.*Pode' "$T/curl.log" 2>/dev/null && grep -q 'sendMessage.*dell' "$T/curl.log" && break; sleep 0.5; done
kill "$dp" 2>/dev/null; wait "$dp" 2>/dev/null || true
grep -q 'sendMessage.*dell' "$T/curl.log" || falhou "daemon não respondeu pelo bot: $(grep -c . "$T/curl.log") chamadas"
grep -q 'estranho' "$T/curl.log" && falhou 'mensagem de estranho foi processada'
grep -q 'VOZ_FALAR' "$T/am.log" && falhou 'resposta do Telegram foi também ao Tasker'
[[ $(<"$HOME/.local/state/tt-voz/tg_offset") == 10 ]] || falhou "offset do Telegram: $(cat "$HOME/.local/state/tt-voz/tg_offset")"
passou 'voz: daemon atende o Telegram e responde pelo bot'
