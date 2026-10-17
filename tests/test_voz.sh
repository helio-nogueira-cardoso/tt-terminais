#!/usr/bin/env bash
# voz (o utilitário da raiz; no celular, termux/bin/voz o roda): comandos por frase, troca de máquina/sessão, trava de sessões, resposta do agente e daemon.
# Tudo com tt/ssh/am falsos e um tmux isolado; nada toca máquinas, celular ou Tasker reais.
source "$(dirname "$0")/lib.sh"; isolar
V=$RAIZ/voz
bash -n "$V" || falhou "sintaxe: $V"

B=$T/fake; mkdir -p "$B" "$T/sd/Tasker"
cat >"$B/tt" <<'FIM'
#!/usr/bin/env bash
case $1 in
  --maquinas) printf 'u@h1 dell\nu@h2 book\n' ;;
  --saude) printf 'Saude das maquinas cadastradas:\n  \033[32m●\033[0m dell             ok\n  \033[31m●\033[0m book             timeout   tempo esgotado\n' ;;
  --listar-tudo) printf '# mestre de obras — celular — 20260101T000000Z\n' ;;
  --tarefas-lista) # a aba da voz (TT_RT/tt-tarefas-ui-UID): abertas, ou a agenda (hoje, prazo) com o dia no cabeçalho do grupo
    case $(sed -n 's/^filtro=//p' "${TT_RT:-/x}/tt-tarefas-ui-$UID" 2>/dev/null) in
      hoje|prazo) printf '\t \033[1mAtrasadas\033[0m\nbbb111bbb111\t ▸ ☐ ww03 Mandar a nota  bbb111bbb111  ◷ venceu ontem 14:00\n\t\ndia:20742\t Hoje · sexta, 16/10  ▦\nabc123abc123\t ▸ ☐ ● 12:00 zz01 Pagar o boleto  abc123abc123  ━━━ 1/3\n\t\ndia:20746\t Terça, 20/10  ▦\nccc222ccc222\t ▸ ☐ vv04 Revisar o PR  ccc222ccc222  #trabalho\n' ;;
      *) printf 'abc123abc123\t \033[1m▸\033[0m ☐ ● zz01 Pagar o boleto  abc123abc123  ◷ hoje 12:00  ━━━ 1/3\nfed321fed321\t ▸ ☐ yy02 BIMO-989/990 aceite  fed321fed321  ◷ qui 22/10  #etq  ≡\n' ;;
    esac ;;
  --tarefa-codigo) printf 'zz01\tabc123abc123\tPagar o boleto\tzz01\nqq02\tdef456def456\tLigar no banco\tzz01.qq02\n' ;;
  --tarefa-ia-prompt) printf 'TAREFA [abc123abc123]: Pagar o boleto\nPrazo: hoje às 12:00\n\nSubtarefas (código · estado · texto · apelido estável):\n  [111111111111] feita · Achar o boleto · zz01.ka11\n  [def456def456] aberta · Ligar no banco · zz01.qq02\n  [222222222222] aberta · Pagar no app · zz01.pe22\n' ;;
  --atalho-rodar|--seguir) echo "tt $*" >>"$VOZ_IA_LOG" ;;
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
# ia-conta falso: "abrir" mostra as perguntas de abertura (confiar, atualizar e uma desconhecida) como menus de setas
if [[ ${1:-} == abrir && ${2:-} == --listar-contas ]]; then
  printf 'principal\tclaude\tclaude · principal\t5h 10%% · 7d 1%%\nbeta\tclaude\tclaude · beta\t5h 2%% · 7d 1%%\ncodex\tcodex\tcodex · x\t5h 0%% · 7d 0%%\n'; exit
fi
if [[ ${1:-} == abrir ]]; then
  echo "args: $*" >>"$VOZ_IA_LOG"
  menu() { local t=$1 sel=0 c i; shift; local ops=("$@")
    while :; do
      clear; echo "$t"
      for i in "${!ops[@]}"; do if ((i == sel)); then echo " ❯ $((i + 1)). ${ops[i]}"; else echo "   $((i + 1)). ${ops[i]}"; fi; done
      IFS= read -rsn1 c
      if [[ $c == $'\e' ]]; then read -rsn2 c; [[ $c == '[B' ]] && sel=$((sel + 1)); [[ $c == '[A' ]] && sel=$((sel - 1))
      elif [[ -z $c || $c == $'\r' ]]; then echo "escolheu: ${ops[sel]}" >>"$VOZ_IA_LOG"; return; fi
    done; }
  menu "Do you trust the files in this folder?" "Yes, proceed" "No, exit"
  menu "Update available! 1.2 -> 1.3" "Update now" "Skip" "Skip until next version"
  menu "Qual cor você prefere?" "Azul" "Verde"
  clear; echo "● Pronto para trabalhar."; echo "> "; sleep 600; exit
fi
echo "principal 12 por cento"
FIM
# proot-distro falso: registra a chamada; lá dentro estão as contas de IA do celular (o ia-conta do Termux não as vê)
cat >"$B/proot-distro" <<'FIM'
#!/usr/bin/env bash
echo "$*" >>"$VOZ_PROOT_LOG"
case $* in
  *"ia-conta uso"*) echo 'proot warning: aviso' >&2; printf 'devsblue\t36\tok\t5h 8%% · 7d 36%%\n' ;;
  *"--listar-contas"*) printf 'devsblue\tclaude\tclaude · devsblue\t5h 8%% · 7d 36%%\ncodex\tcodex\tcodex · y\t5h 1%% · 7d 1%%\n' ;;
  *"ia-rot -p"*) cat >/dev/null; echo '{"fala": "Do proot.", "acoes": []}' ;;
esac
exit 0
FIM
chmod +x "$B"/*
export PATH="$B:$PATH" VOZ_SDCARD=$T/sd VOZ_AM_LOG=$T/am.log VOZ_ESPERA_FALA=0 VOZ_CURL_LOG=$T/curl.log VOZ_PROOT_LOG=$T/proot.log
export VOZ_TELEGRAM=$T/segredos/telegram VOZ_TG_LIGAR=2 VOZ_TG_PAUSA=1 VOZ_IA_LOG=$T/ia.log VOZ_DESTRAVAR_PAUSA=0.5
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

# escolher já libera (sem "diga sim"); bloquear solta a sessão e o texto livre deixa de ir a ela
saida=$(v "aba agente"); [[ $saida == *"Sessão agente teste, em dell. Pode falar com ela."* && $saida != *"Diga sim"* ]] || falhou "aba: $saida"
grep -qx 'dell:agente-teste' "$HOME/.config/tt-voz/permitidas" || falhou 'escolher não liberou a sessão'
v bloquear sessao | grep -q 'solta' || falhou 'bloquear sessão'
[[ -z $(cat "$HOME/.local/state/tt-voz/alvo_s" 2>/dev/null) ]] && ! grep -qx 'dell:agente-teste' "$HOME/.config/tt-voz/permitidas" ||
  falhou 'bloquear não soltou a sessão'
saida=$(v "oi mundo"); [[ $saida == *"escolha uma sessão"* ]] || falhou "texto livre sem sessão escolhida: $saida"
tmux capture-pane -p -t '=agente-teste:' | grep -q 'oi mundo' && falhou 'enviou texto a uma sessão solta'
passou 'voz: escolher a sessão já libera; bloquear a solta'

v "aba agente" >/dev/null
v "permitir sessao" | grep -q liberada || falhou 'permitir sessão'
saida=$(v "oi mundo"); [[ $saida == *"Enviado para agente-teste"* && $saida == *"Entendi: oi mundo"* ]] || falhou "resposta do agente: $saida"
saida=$(v repetir); [[ $saida == *'Entendi: oi mundo'* && $saida != *Enviado* ]] || falhou "repetir (o aviso não conta): $saida"
saida=$(VOZ_ESPERA=1 v "devagar"); [[ $saida == *"Eu aviso quando terminar"* ]] || falhou "agente demorado: $saida"
saida=$(v repetir); [[ $saida == *'Entendi: devagar'* ]] || falhou "repetir depois da demora confere a sessão de novo: $saida"
[[ -e $HOME/.local/state/tt-voz/pendente ]] && falhou 'pendente ficou depois da resposta'
passou 'voz: texto vai à sessão escolhida e a resposta volta resumida'

# o estado sem esperar: com o agente trabalhando, diz há quanto tempo e fica pendente (o cérebro recebe a tela limpa);
# a janela confere (--pendente-pronto) e, quando ele termina, fala a resposta (--turno-pendente)
EST=$HOME/.local/state/tt-voz
tmux new-session -d -s ocupado-teste "printf '● Rodando a suíte inteira\n✶ Determining… (2m 5s · ↓ 3k tokens)\n  ⏵⏵ bypass permissions on · esc to interrupt\n'; sleep 600"
printf 'dell:ocupado-teste\n' >>"$HOME/.config/tt-voz/permitidas"; printf dell >"$EST/alvo_m"; printf ocupado-teste >"$EST/alvo_s"; sleep 0.5
saida=$(VOZ_CEREBRO_CMD="cat > '$T/pedido2.txt'; echo '{\"fala\": \"\", \"acoes\": [{\"acao\": \"ler\"}]}'" v "como está essa sessão")
[[ $saida == *"Ele está trabalhando há 2 minutos e 5 segundos. Eu aviso quando terminar."* ]] || falhou "estado com o agente trabalhando: $saida"
grep -q 'o agente está TRABALHANDO há 2 minutos e 5 segundos' "$T/pedido2.txt" && grep -qF '| ● Rodando a suíte inteira' "$T/pedido2.txt" ||
  falhou "contexto do cérebro sem a tela de agora: $(grep -A4 'tela de agora' "$T/pedido2.txt")"
grep -q 'bypass permissions' "$T/pedido2.txt" && falhou 'o rodapé do agente foi ao cérebro'
bash "$V" --pendente-pronto && falhou 'pendente pronto com o agente ainda trabalhando'
tmux respawn-pane -k -t '=ocupado-teste:' "printf '● Terminei: 12 testes passaram.\n'; sleep 600"; sleep 0.5
bash "$V" --pendente-pronto || falhou 'pendente não ficou pronto com o agente parado'
ev=$(VOZ_TELA_FD=3 bash "$V" --turno-pendente 3>&1 >/dev/null)
[[ $ev == $'fala\tTerminei: 12 testes passaram.' ]] || falhou "a resposta do agente que terminou: '$ev'"
[[ -e $EST/pendente ]] && falhou 'o pendente ficou depois da resposta'
tmux kill-session -t '=ocupado-teste'
passou 'voz: estado sem esperar (trabalhando há quanto tempo; a tela limpa vai ao cérebro); avisa quando o agente termina'

# ponte: "ponte-x" aqui mostra a sessão agente-teste de dell (o cliente dela leva TT_PONTE): ler e mandar vão à de verdade
ln -sf "$V" "$B/voz"
tmux new-session -d -s ponte-x 'sleep 600'; tmux set-option -t '=ponte-x:' @ponte u@h1
fora new -d -s cliponte -x 80 -y 20 "env -u TMUX TT_PONTE='celular|ponte-x' TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t agente-teste"
for i in $(seq 25); do [[ $(bash "$V" --cliente-ponte 'celular|ponte-x') == agente-teste ]] && break; sleep 0.2; done
[[ $(bash "$V" --cliente-ponte 'celular|ponte-x') == agente-teste ]] || falhou 'a sessão que o cliente da ponte mostra'
printf celular >"$EST/alvo_m"; printf ponte-x >"$EST/alvo_s"; printf 'celular:ponte-x\n' >>"$HOME/.config/tt-voz/permitidas"
saida=$(v "oi ponte"); [[ $saida == *"Entendi: oi ponte"* ]] || falhou "texto pela ponte: $saida"
tmux capture-pane -p -t '=agente-teste:' | grep -q 'oi ponte' || falhou 'o texto não chegou à sessão de verdade'
fora kill-server 2>/dev/null || true; tmux kill-session -t '=ponte-x'; printf dell >"$EST/alvo_m"; printf agente-teste >"$EST/alvo_s"
passou 'voz: numa ponte, lê e manda texto na sessão de verdade da outra máquina (a que o cliente da ponte mostra)'

# frases soltas: nome da máquina, "sessões do X", número da lista, "sim" para liberar, várias hipóteses, singular
saida=$(v "dell"); [[ $saida == *"Agora em dell"* && $saida == *"1, agente teste"* ]] || falhou "máquina pelo nome: $saida"
saida=$(v "quais as sessões do dell"); [[ $saida == *"Em dell: 1, agente teste"* ]] || falhou "sessões do dell: $saida"
grep -vx 'dell:agente-teste' "$HOME/.config/tt-voz/permitidas" >"$T/p"; cp "$T/p" "$HOME/.config/tt-voz/permitidas"
saida=$(v "um"); [[ $saida == *"Sessão agente teste, em dell. Pode falar com ela."* ]] && grep -qx 'dell:agente-teste' "$HOME/.config/tt-voz/permitidas" ||
  falhou "escolher pelo número (já libera): $saida"
saida=$(v "segunda"); [[ $saida == *"Não há sessão 2"* ]] || falhou "número fora da lista: $saida"
saida=$(v $'blablabla\nmaquinas'); [[ $saida == *"Máquinas:"* ]] || falhou "hipótese que é comando: $saida"
saida=$(v "máquina"); [[ $saida == *"Máquinas:"* ]] || falhou "singular: $saida"
saida=$(v "vai para o dell"); [[ $saida == *"Agora em dell"* ]] || falhou "vai para o dell: $saida"
v "aba agente" >/dev/null  # trocar de máquina limpa a sessão; os testes seguintes contam com ela
passou 'voz: frases soltas (nome da máquina, sessões do X, número, hipóteses do reconhecimento)'

# silêncio: na 1ª vez pede de novo (ouve), na 2ª encerra avisando o Tasker (fim=1)
: >"$T/am.log"; saida=$(VOZ_MUDO= bash "$V" __silencio__); [[ $saida == *"Não ouvi. Pode falar"* ]] || falhou "silêncio 1: $saida"
grep -q 'ouvir' "$T/am.log" && falhou '1º silêncio não deveria parar de ouvir'
: >"$T/am.log"; saida=$(VOZ_MUDO= bash "$V" __silencio__); [[ $saida == *"Terminal encerrado"* ]] || falhou "silêncio 2: $saida"
grep -q -- '--es fim 1' "$T/am.log" || falhou "2º silêncio não encerrou no Tasker: $(cat "$T/am.log")"
v __silencio__ >/dev/null; v status >/dev/null; [[ -e $HOME/.local/state/tt-voz/silencio ]] && falhou 'frase ouvida não zerou o silêncio'
passou 'voz: silêncio pede de novo e só encerra na segunda vez'

# cérebro: frase solta vai ao modelo (aqui um falso, que guarda o pedido e devolve o plano de $T/plano.json)
export VOZ_CEREBRO_CMD="cat > '$T/pedido.txt'; cat '$T/plano.json'"
printf '%s' '{"fala": "Vou ver como ele está.", "acoes": [{"acao": "escolher", "maquina": "dell", "sessao": "agente"}, {"acao": "ler"}]}' >"$T/plano.json"
: >"$T/am.log"; saida=$(VOZ_MUDO= bash "$V" "me conta como anda o agente lá do dell")
[[ $saida == *"Vou ver como ele está"* && $saida == *"Sessão agente teste, em dell"* && $saida == *"Entendi"* ]] || falhou "cérebro: plano não executado: $saida"
[[ $(grep -c 'tt.VOZ_FALAR' "$T/am.log") == 1 ]] || falhou "cérebro: devia falar uma vez só na volta: $(cat "$T/am.log")"
grep -q 'me conta como anda o agente' "$T/pedido.txt" && grep -q 'máquina atual: dell' "$T/pedido.txt" || falhou 'cérebro: pedido sem a frase ou o contexto'
grep -q 'você: me conta como anda' "$HOME/.local/state/tt-voz/historico" || falhou 'cérebro: histórico não gravado'
rm -f "$T/pedido.txt"; v status >/dev/null; [[ -e $T/pedido.txt ]] && falhou 'comando simples não deveria ir ao cérebro'
printf '%s' '{"fala": "Até logo.", "acoes": [{"acao": "encerrar"}]}' >"$T/plano.json"
: >"$T/am.log"; VOZ_MUDO= bash "$V" "pode desligar tudo por hoje" >/dev/null; grep -q -- '--es fim 1' "$T/am.log" || falhou "cérebro: encerrar não fechou: $(cat "$T/am.log")"
printf 'isto não é json' >"$T/plano.json"
saida=$(v "uma frase qualquer sem sentido"); [[ $saida == *"Enviado para agente-teste"* ]] || falhou "cérebro com resposta ruim: devia cair nas regras: $saida"
saida=$(VOZ_CEREBRO_CMD="exit 1" v "outra frase solta"); [[ $saida == *Enviado* ]] || falhou "cérebro fora do ar: devia cair nas regras: $saida"
unset VOZ_CEREBRO_CMD
passou 'voz: cérebro entende frase solta, age, fala uma vez só; sem resposta útil, valem as regras'

saida=$(v tarefas); [[ $saida == *"Tarefas abertas: 1, Pagar o boleto, prazo hoje 12:00, 1 de 3 subtarefas. 2, BIMO-989/990 aceite, prazo qui 22/10."* ]] ||
  falhou "tarefas (o N/M das subtarefas é só o da barra, não a data nem o título): $saida"
saida=$(VOZ_CEREBRO_CMD="cat >/dev/null; echo '{\"acoes\": [{\"acao\": \"tarefas\", \"filtro\": \"hoje\"}]}'" v "o que tenho para hoje")
[[ $saida == *"Tarefas para hoje: 1, Mandar a nota, prazo venceu ontem 14:00. 2, Pagar o boleto, prazo hoje 12:00, 1 de 3 subtarefas. 3, Revisar o PR, prazo terça, 20/10."* ]] ||
  falhou "tarefas da agenda (dia do cabeçalho e hora antes do apelido): $saida"
saida=$(v "tarefa boleto"); [[ $saida == *"Prazo: hoje às 12:00"* && $saida == *"1 de 3 subtarefas feitas"* && $saida == *"Faltam: Ligar no banco; Pagar no app"* ]] || falhou "tarefa com subtarefas: $saida"

# 🚀 com uma IA específica: abre em sessão nova; a pasta fora da lista autorizada é perguntada ("sempre" a põe na lista
# e confia), a atualização é pulada sozinha e a pergunta desconhecida é lida, com as opções. A pessoal vem por um link (como
# /tmp → /private/tmp no macOS): o tmux mostra o caminho físico, e ela continua sendo "a sua pasta pessoal"
ln -s "$T/home" "$T/casa"; rm -f "$EST"/casas-*
saida=$(HOME=$T/casa v "nova sessão com codex")
[[ $saida == *"quer confiar na pasta a sua pasta pessoal, que não está na sua lista"* && $saida == *"1, Yes, proceed. 2, No, exit."* &&
  $saida == *"Ou diga sempre"* ]] || falhou "pasta fora da lista: $saida"
grep -q 'escolheu:' "$T/ia.log" && falhou "respondeu sozinho fora da lista: $(cat "$T/ia.log")"
saida=$(v "sempre"); [[ $saida == *"pergunta: Qual cor você prefere? Opções: 1, Azul. 2, Verde. Diga o número."* ]] || falhou "sempre: $saida"
grep -qx 'dell:~' "$HOME/.config/tt-voz/pastas" || falhou "sempre não pôs a pasta na lista: $(cat "$HOME/.config/tt-voz/pastas")"
grep -q 'args: abrir --conta codex' "$T/ia.log" && grep -q 'escolheu: Yes, proceed' "$T/ia.log" && grep -q 'escolheu: Skip$' "$T/ia.log" || falhou "perguntas de abertura: $(cat "$T/ia.log")"
grep -q 'rotina "Skip" (sozinha)' "$EST/aprovacoes.log" && grep -q 'pasta "Yes, proceed" (você)' "$EST/aprovacoes.log" || falhou "registro das aprovações: $(cat "$EST/aprovacoes.log")"
saida=$(v "dois"); [[ $saida == *"Feito. Sessão voz codex"* ]] && grep -q 'escolheu: Verde' "$T/ia.log" || falhou "resposta à pergunta: $saida / $(cat "$T/ia.log")"
bash "$V" --pastas add '~' >/dev/null; [[ $(bash "$V" --pastas) == *'~'* ]] || falhou "voz --pastas: $(bash "$V" --pastas)"
[[ $(<"$HOME/.local/state/tt-voz/alvo_s") == voz-codex-* ]] && grep -q ':voz-codex-' "$HOME/.config/tt-voz/permitidas" || falhou 'sessão nova não virou o alvo liberado'
# 👇 e ⏩: a IA do provedor com menos uso (beta), e a conversa passada adiante pelo tt
: >"$T/ia.log"; saida=$(v "aba agente")
VOZ_CEREBRO_CMD="cat >/dev/null; echo '{\"acoes\": [{\"acao\": \"trocar_ia\", \"ia\": \"claude\"}, {\"acao\": \"passar\"}]}'" v "troca para o claude e depois passa adiante" >/dev/null
grep -q 'tt --atalho-rodar ia-aqui  %[0-9]* conta=beta' "$T/ia.log" && grep -q 'tt --seguir  %[0-9]*' "$T/ia.log" || falhou "👇/⏩: $(cat "$T/ia.log")"
passou 'voz: tarefas com subtarefas; 🚀 com IA escolhida passa pelas perguntas de abertura; 👇 e ⏩ pelo tt'

v tarefas >/dev/null || falhou 'tarefas'
v contas | grep -q 'principal' || falhou 'contas'
v "" | grep -q 'diga ajuda e um tema' || falhou 'ajuda geral'
v ajuda | grep -q 'diga ajuda e um tema' || falhou 'ajuda'
v "ajuda sessões" | grep -q 'aba e uma palavra do nome' || falhou 'ajuda sessões'
v "ajuda com o agente" | grep -q 'bloquear sessão a solta' || falhou 'ajuda agente'
v "ajuda maquinas" | grep -q 'por exemplo, notebook' || falhou 'ajuda máquinas'
v "ajuda conversa" | grep -q 'volto a ouvir' || falhou 'ajuda conversa'
v comandos | grep -q 'bloquear sessão' || falhou 'comandos'
saida=$(v terminal); [[ $saida == *"Máquina dell, sessão agente-teste"* && $saida == *"Pode falar"* ]] || falhou "abrir conversa: $saida"
v encerrar | grep -q 'Terminal encerrado' || falhou 'encerrar'
passou 'voz: tarefas, contas, ajuda, abrir e encerrar a conversa'

# "abra uma nova sessão em M com X" é o 🚀 (não a lista de sessões); frase longa que só cita a máquina vai ao cérebro
: >"$T/ia.log"; saida=$(VOZ_DESTRAVAR=1 v "abra uma nova sessão no book com o codex")
[[ $saida == *'Abrindo codex em book'* && $saida != *'Diga o número'* ]] && grep -q 'args: abrir --conta codex' "$T/ia.log" ||
  falhou "abrir sessão nova numa máquina: $saida / $(cat "$T/ia.log")"
[[ $(<"$EST/alvo_m") == book && $(<"$EST/alvo_s") == voz-codex-* ]] || falhou "a sessão nova não virou o alvo: $(cat "$EST/alvo_m"):$(cat "$EST/alvo_s")"
tmux kill-session -t "=$(<"$EST/alvo_s")" 2>/dev/null || true
: >"$T/ia.log"; VOZ_DESTRAVAR=1 v "crie uma sessão nova" >/dev/null; grep -qx 'args: abrir' "$T/ia.log" || falhou "crie uma sessão nova: $(cat "$T/ia.log")"
tmux kill-session -t "=$(<"$EST/alvo_s")" 2>/dev/null || true
printf '%s' '{"fala": "Entendi o pedido longo.", "acoes": []}' >"$T/plano.json"
saida=$(VOZ_CEREBRO_CMD="cat > '$T/pedido3.txt'; cat '$T/plano.json'" v "passe uma a uma das sessões tanto da empresa como do computador dell e resuma")
[[ $saida == *'Entendi o pedido longo.'* && $saida != *'Diga o número'* ]] || falhou "frase longa que cita a máquina foi tomada pelas regras: $saida"
saida=$(v "sessões do dell"); [[ $saida == *'Em dell:'* ]] || falhou "frase curta com a máquina continua listando: $saida"
v "aba agente" >/dev/null
passou 'voz: abrir sessão nova numa máquina pelo rodízio; frase longa que cita a máquina vai ao cérebro'

# índice: as sessões desta máquina (sem ocultas nem pontes) com estado e a tela; o de todas as máquinas ao mesmo tempo
tmux new-session -d -s ponte-z 'sleep 600'; tmux set-option -t '=ponte-z:' @ponte u@h1
r=$(bash "$V" --indice-local 2)
grep -qP '^celular\tagente-teste\t-\t\tparado' <<<"$r" && grep -qP '^\t\| ● Entendi' <<<"$r" || falhou "índice desta máquina: $r"
grep -q 'ponte-z\|_oculta' <<<"$r" && falhou "o índice trouxe ponte ou sessão oculta: $r"
mkdir -p "$HOME/.local/share/tt"; ln -sf "$V" "$HOME/.local/share/tt/voz"  # as outras máquinas (ssh falso) têm o voz novo
rm -f "$EST/indice"; bash "$V" --indice-atualizar
(($(grep -cP '^celular\tagente-teste\t' "$EST/indice") == 3)) || falhou "índice de todas as máquinas (3, pelo ssh falso): $(cat "$EST/indice")"
rm -f "$HOME/.local/share/tt/voz"; rm -f "$EST/indice"; bash "$V" --indice-atualizar  # lá, um voz antigo: nada, sem erro
(($(grep -cP '^celular\tagente-teste\t' "$EST/indice") == 1)) || falhou "máquina com voz antigo deveria ficar de fora: $(cat "$EST/indice")"
tmux kill-session -t '=ponte-z'
# escolher pelo nome ou pelo título, em qualquer máquina (pelo índice)
printf 'dell\tagente-teste\t-\t\tparado\nbook\tsessao-do-book\tclaude\tRevisar o bimo\ttrabalhando há 3 minutos\n' >"$EST/indice"
saida=$(v "aba revisar bimo"); [[ $saida == *'Sessão sessao do book, em book. Pode falar com ela.'* ]] || falhou "sessão de outra máquina pelo título: $saida"
[[ $(<"$EST/alvo_m") == book ]] && grep -qx 'book:sessao-do-book' "$HOME/.config/tt-voz/permitidas" || falhou 'a sessão de outra máquina não virou o alvo liberado'
saida=$(v "vai para a sessão revisar bimo"); [[ $saida == *'Sessão sessao do book, em book'* ]] || falhou "ir para a sessão: $saida"
printf '%s' '{"fala": "", "acoes": []}' >"$T/plano.json"
VOZ_CEREBRO_CMD="cat > '$T/pedido4.txt'; cat '$T/plano.json'" v "qual sessão está revisando o bimo" >/dev/null
grep -q 'book · sessao-do-book · claude · "Revisar o bimo" · trabalhando há 3 minutos' "$T/pedido4.txt" || falhou "o índice não foi ao cérebro: $(grep -A3 'índice' "$T/pedido4.txt")"
printf dell >"$EST/alvo_m"; v "aba agente" >/dev/null
passou 'voz: índice das sessões (todas as máquinas, sem ocultas nem pontes); escolher pelo nome ou título em qualquer máquina'

# panorama: todas as sessões numa leitura só, resumidas pelo cérebro numa volta; sem ele, o estado de cada uma
printf '%s' '{"fala": "agente teste está parado e respondeu.", "acoes": []}' >"$T/plano.json"
saida=$(VOZ_CEREBRO_CMD="cat > '$T/pedido5.txt'; cat '$T/plano.json'" v "resumo de todas as sessões")
[[ $saida == *'Vou olhar as sessões.'* && $saida == *'agente teste está parado e respondeu.'* ]] || falhou "panorama: $saida"
grep -q '^PANORAMA' "$T/pedido5.txt" && grep -q 'celular · agente-teste' "$T/pedido5.txt" && grep -q '| ● Entendi' "$T/pedido5.txt" ||
  falhou "o pedido do panorama: $(cat "$T/pedido5.txt" | head -40)"
saida=$(VOZ_CEREBRO_CMD="exit 1" v "o que está acontecendo nas sessões"); [[ $saida == *'agente teste em celular, sem agente, parado'* ]] ||
  falhou "panorama sem o cérebro: $saida"
printf '%s' '{"fala": "", "acoes": [{"acao": "panorama"}]}' >"$T/plano.json"
saida=$(VOZ_CEREBRO_CMD="cat > '$T/pedido6.txt'; cat '$T/plano.json'" v "me conta o que cada agente anda fazendo hoje")
grep -q '^PANORAMA' "$T/pedido6.txt" || falhou "a ação panorama do cérebro: $saida"
passou 'voz: panorama (todas as sessões numa leitura, um resumo do cérebro; sem ele, o estado de cada uma)'

# o Claude aberto da janela: o voz manda só o contexto (as regras ficam no system prompt) pelo socket; sem resposta, o de sempre
cat >"$T/sock.py" <<'FIM'
import os, socket, sys
s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(4)
for resp in sys.argv[3:]:
    c, _ = s.accept(); d = b""
    while True:
        b = c.recv(65536)
        if not b: break
        d += b
    open(sys.argv[2], "ab").write(d + b"\n====\n")
    if resp != "-": c.sendall(resp.encode())
    c.close()
FIM
python3 "$T/sock.py" "$T/cerebro.sock" "$T/sock.log" '{"fala": "Pelo socket.", "acoes": []}' - & sp=$!
for i in $(seq 25); do [[ -S $T/cerebro.sock ]] && break; sleep 0.2; done
saida=$(VOZ_CEREBRO_SOCK=$T/cerebro.sock VOZ_CEREBRO_CMD="cat >/dev/null; echo '{\"fala\": \"Pelo caminho de sempre.\", \"acoes\": []}'" v "uma frase solta pelo socket")
[[ $saida == *'Pelo socket.'* ]] || falhou "cérebro pelo socket: $saida"
grep -q '^Contexto:' "$T/sock.log" && ! grep -q 'Responda SÓ com um JSON' "$T/sock.log" || falhou "pelo socket vai só o contexto: $(head -5 "$T/sock.log")"
saida=$(VOZ_CEREBRO_SOCK=$T/cerebro.sock VOZ_CEREBRO_CMD="cat >/dev/null; echo '{\"fala\": \"Pelo caminho de sempre.\", \"acoes\": []}'" v "outra frase solta pelo socket")
[[ $saida == *'Pelo caminho de sempre.'* ]] || falhou "socket sem resposta: deveria usar o caminho de sempre: $saida"
wait "$sp" 2>/dev/null
# voz --cerebro-vivo-aqui: a conta do rodízio, o Claude em stream-json com as regras no system prompt
mkdir -p "$T/vivo"; printf '#!/usr/bin/env bash\necho "$*" >>%q\nprintf "beta\\t10\\tok\\n"\n' "$T/vivo/rot.log" >"$T/vivo/ia-rot"
printf '#!/usr/bin/env bash\necho "CCD=${CLAUDE_CONFIG_DIR:-} $*" >%q\n' "$T/vivo/claude.log" >"$T/vivo/claude"; chmod +x "$T/vivo"/*
PATH="$T/vivo:$PATH" bash "$V" --cerebro-vivo-aqui haiku
grep -q -- '--claude-only --melhor' "$T/vivo/rot.log" || falhou "a conta do cérebro aberto não veio do rodízio: $(cat "$T/vivo/rot.log")"
l=$(cat "$T/vivo/claude.log")
[[ $l == "CCD=$HOME/.local/share/claude-contas/beta -p --model haiku --input-format stream-json --output-format stream-json --verbose --tools  --no-session-persistence --system-prompt-file $EST/cerebro-regras.md" ]] ||
  falhou "o Claude do cérebro aberto: $l"
grep -q 'Responda SÓ com um JSON' "$EST/cerebro-regras.md" && grep -q 'microfone do computador' "$EST/cerebro-regras.md" || falhou 'as regras do cérebro aberto'
passou 'voz: cérebro aberto (só o contexto pelo socket; sem resposta, o caminho de sempre); conta do rodízio e stream-json'

# No celular as contas e os agentes ficam no proot onde o tt instalou o ia-conta: "contas", o 🚀 neste celular, as contas
# do contexto do cérebro e o cérebro "local" vão para lá; noutra máquina, o 🚀 abre o ia-conta de lá, como antes.
P=$T/com.termux/usr; R=$P/var/lib/proot-distro/containers/debian/rootfs/root/.local/share/tt
mkdir -p "$R"; printf '#!/bin/sh\n' >"$R/ia-conta"; chmod +x "$R/ia-conta"
saida=$(PREFIX=$P v contas); [[ $saida == *'devsblue: 5h 8%, 7d 36%.'* && $saida != *principal* && $saida != *warning* ]] || falhou "contas no proot: $saida"
grep -q '^login debian --shared-tmp -- bash -lc .*ia-conta uso$' "$T/proot.log" || falhou "contas: chamada ao proot: $(cat "$T/proot.log")"
v "ir para celular" >/dev/null; : >"$T/proot.log"
saida=$(PREFIX=$P v "nova sessão com codex"); [[ $saida == *'pronta em celular'* ]] || falhou "🚀 no celular: $saida"
s=$(<"$HOME/.local/state/tt-voz/alvo_s")
grep -q '^login debian --shared-tmp -- bash -lc PATH=.*ia-conta abrir --conta codex$' "$T/proot.log" || falhou "🚀 não abriu o agente no proot: $(cat "$T/proot.log")"
tmux kill-session -t "=$s" 2>/dev/null || true
printf '%s' '{"fala": "Ok.", "acoes": []}' >"$T/plano.json"
VOZ_CEREBRO_CMD="cat > '$T/pedido.txt'; cat '$T/plano.json'" PREFIX=$P v "como estão as minhas contas de ia" >/dev/null
grep -q 'contas de IA (desta máquina): devsblue:claude codex:codex' "$T/pedido.txt" || falhou "cérebro: contas do contexto não são as do proot: $(grep 'contas de IA' "$T/pedido.txt")"
echo local >"$HOME/.config/tt-voz/cerebro"
saida=$(PREFIX=$P v "uma frase solta para o cérebro do celular"); [[ $saida == *'Do proot.'* ]] || falhou "cérebro local não foi ao proot: $saida"
rm -f "$HOME/.config/tt-voz/cerebro"
v "ir para del" >/dev/null; : >"$T/proot.log"; : >"$T/ia.log"
saida=$(PREFIX=$P VOZ_DESTRAVAR=1 v "nova sessao"); [[ $saida == *'em dell'* ]] && grep -qx 'args: abrir' "$T/ia.log" || falhou "🚀 noutra máquina: $saida / $(cat "$T/ia.log")"
s=$(<"$HOME/.local/state/tt-voz/alvo_s"); tmux kill-session -t "=$s" 2>/dev/null || true
grep -q 'ia-conta abrir' "$T/proot.log" && falhou "🚀 noutra máquina passou pelo proot: $(cat "$T/proot.log")"
mkdir -p "$HOME/.local/bin"; printf '#!/bin/sh\n' >"$HOME/.local/bin/claude"; chmod +x "$HOME/.local/bin/claude"
saida=$(PREFIX=$P v contas); [[ $saida == *principal* ]] || falhou "com o claude no próprio Termux, contas deveria ficar fora do proot: $saida"
rm -f "$HOME/.local/bin/claude"; v "aba agente" >/dev/null
passou 'voz: no celular, contas, 🚀 e o cérebro local usam o proot das contas de IA'

# fala: grava o texto e avisa o Tasker (intent tt.VOZ_FALAR); com VOZ_MUDO não faz nada
: >"$T/am.log"; bash "$V" --falar "olá carro" >/dev/null
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
