#!/usr/bin/env bash
# voz: as ações que vão além das sessões. Esperar e falar sozinha depois, acompanhar até concluir, cancelar; a pergunta
# que aparece no meio do trabalho (rotina respondida sozinha numa sessão aberta pela voz, decisão lida para você);
# fixadas, tarefas, notificações e letreiro; fechar sessão (confirmação, dupla para a escolhida ou que trabalha) e a
# limpeza (analisa, sugere com o motivo, tira da lista, fecha em lote). O tt é o de verdade, isolado; os agentes são falsos.
source "$(dirname "$0")/lib.sh"; isolar
V=$RAIZ/voz
EST=$HOME/.local/state/tt-voz
B=$T/fake; mkdir -p "$B"
# o tt de verdade (o do pacote isolado); a lista da limpeza pode vir de um TSV pronto (as idades de verdade são segundos)
cat >"$B/tt" <<FIM
#!/usr/bin/env bash
if [[ "\$1 \${2:-}" == "--listar-tudo --tsv" && -s \${VOZ_TSV_FALSO:-/x} ]]; then cat "\$VOZ_TSV_FALSO"; exit 0; fi
exec "$TT" "\$@"
FIM
# agente lento: a cada pedido trabalha VOZ_T_AGENTE s (com o "esc to interrupt" dos agentes) e responde
cat >"$B/agente-lento.sh" <<'FIM'
#!/usr/bin/env bash
while IFS= read -r l; do
  for ((i = 0; i < ${VOZ_T_AGENTE:-4}; i++)); do printf '\r✻ Working… (%ds · esc to interrupt)' "$i"; sleep 1; done
  printf '\r\033[K● Feito: %s. Tudo certo.\n> ' "$l"
done
FIM
# agente que pergunta no meio do trabalho: o 1º pedido abre o menu de PERGUNTA (decisão ou rotina), depois responde
cat >"$B/agente-pergunta.sh" <<'FIM'
#!/usr/bin/env bash
menu() { local t=$1 sel=0 c i; shift; local ops=("$@")
  while :; do
    printf '\033[2J\033[H%s\n' "$t"
    for i in "${!ops[@]}"; do if ((i == sel)); then echo " ❯ $((i + 1)). ${ops[i]}"; else echo "   $((i + 1)). ${ops[i]}"; fi; done
    IFS= read -rsn1 c
    if [[ $c == $'\e' ]]; then read -rsn2 c; [[ $c == '[B' ]] && sel=$((sel + 1)); [[ $c == '[A' ]] && sel=$((sel - 1))
    elif [[ -z $c || $c == $'\r' ]]; then echo "escolheu: ${ops[sel]}" >>"$VOZ_AG_LOG"; return; fi
  done; }
IFS= read -r l
case $PERGUNTA in
  decisao) menu "Bash command: make deploy"$'\n'"Do you want to proceed?" "Yes" "No, and tell Claude what to do differently (esc)" ;;
  rotina) menu "Update available! 1.2 -> 1.3" "Update now" "Skip" "Skip until next version" ;;
esac
printf '\033[2J\033[H● Deploy pronto: %s.\n> ' "$l"
sleep 600
FIM
chmod +x "$B"/*
export PATH="$B:$PATH" VOZ_SDCARD=$T/sd VOZ_AG_LOG=$T/ag.log VOZ_DESTRAVAR_PAUSA=0.5 VOZ_ACOMPANHAR_PAUSA=0.5
mkdir -p "$T/sd"
v() { VOZ_MUDO=1 bash "$V" "$@"; }
esperar_fundo() { local i; for ((i = 0; i < ${1:-30}; i++)); do v --fundo-pronto >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }
EU=$(tt --listar-tudo --para-ia | sed -n '1s/.*— \([^ ]*\) —.*/\1/p')

tmux new-session -d -s trabalho "$B/agente-lento.sh"
tmux new-session -d -s outra 'sleep 600'
v "aba trabalho" >/dev/null

# ---- esperar: agenda, segue livre e fala sozinha na hora ----
saida=$(v "espere um minuto e meio e depois confira a sessão")
[[ $saida == *"Combinado: daqui a 1 minuto e meio, eu confiro a sessão trabalho"* ]] || falhou "esperar: $saida"
IFS=$'\t' read -r q dep m s _ <"$EST/agenda"
(( q - $(date +%s) > 80 && q - $(date +%s) <= 90 )) && [[ $dep == ler && $m == "$EU" && $s == trabalho ]] || falhou "agenda: $(cat "$EST/agenda")"
v --fundo-pronto && falhou "a espera de 90 s venceu na hora"
saida=$(v "o que você está esperando"); [[ $saida == *"conferir a sessão trabalho"* ]] || falhou "esperas: $saida"
saida=$(v "cancelar a espera"); [[ $saida == *"Cancelei a espera."* && ! -e $EST/agenda ]] || falhou "cancelar espera: $saida"
saida=$(v cancelar); [[ $saida == *Cancelado* ]] || falhou "cancelar (Esc no agente) continua: $saida"
saida=$(v "daqui a 2 segundos me avise"); [[ $saida == *"daqui a 2 segundos, eu aviso"* ]] || falhou "avisar: $saida"
esperar_fundo 10 || falhou "a espera de 2 s não venceu"
saida=$(v --turno-fundo); [[ $saida == *"Deu o tempo que você pediu."* && ! -e $EST/agenda ]] || falhou "aviso na hora: $saida"
tmux send-keys -t '=trabalho:' C-u 'olá' Enter; sleep 6
v "espere 1 segundo e depois leia a sessão" >/dev/null
esperar_fundo 10 || falhou "a espera de 1 s não venceu"
saida=$(v --turno-fundo); [[ $saida == *"Feito: olá"* ]] || falhou "conferir na hora: $saida"
printf '%s\t%s\t\t\t1\t\n' "$(( $(date +%s) - 3600 ))" avisar >"$EST/agenda"
v --fundo-pronto && falhou "a espera vencida há 1 h falou"; [[ ! -s $EST/agenda ]] || falhou "a espera velha ficou"
saida=$(v "espere 30 minutos e resuma a sessão outra"); [[ $saida == *"daqui a 30 minutos, eu resumo a sessão outra"* ]] || falhou "resumir: $saida"
saida=$(v "espere dez horas"); [[ $saida == *"entre um segundo e seis horas"* ]] || falhou "limite de seis horas: $saida"
v "cancelar espera" >/dev/null
passou 'voz: esperar (segundos, minutos, "e meio"), agendar e falar sozinha na hora; listar, cancelar e esquecer as velhas'

# ---- acompanhar até concluir ----
VOZ_ESPERA=1 v "conte até três" >/dev/null   # o agente fica trabalhando (pendente)
saida=$(v "me avise quando ele terminar"); [[ $saida == *"Vou acompanhar a sessão trabalho"* ]] || falhou "acompanhar: $saida"
[[ -e $EST/pendente ]] && falhou "o pendente ficou junto do acompanhamento (fala dupla)"
esperar_fundo 30 || falhou "o acompanhamento não viu o fim"
saida=$(v --turno-fundo); [[ $saida == *"A sessão trabalho terminou: "*"Feito: conte até três"* && ! -e $EST/acompanhar ]] || falhou "fim acompanhado: $saida"
saida=$(v "acompanhe a sessão outra"); [[ $saida == *"está parada agora"* ]] || falhou "acompanhar parada: $saida"
tmux kill-session -t '=outra'; esperar_fundo 10 || falhou "a sessão fechada não foi notada"
saida=$(v --turno-fundo); [[ $saida == *"que eu acompanhava fechou"* ]] || falhou "acompanhada fechou: $saida"
tmux new-session -d -s outra 'sleep 600'
passou 'voz: acompanhar até concluir (fala o fim uma vez só) e quando a sessão some'

# ---- a pergunta no meio do trabalho: decisão lida; rotina respondida sozinha só na sessão aberta pela voz ----
tmux new-session -d -s pede "PERGUNTA=decisao $B/agente-pergunta.sh"
v "aba pede" >/dev/null; : >"$T/ag.log"
saida=$(v "faça o deploy")
[[ $saida == *"A sessão pede pede uma decisão sua, porque pede permissão nova de execução. Do you want to proceed? Opções: 1, Yes."* ]] ||
  falhou "decisão no meio do trabalho: $saida"
grep -q escolheu "$T/ag.log" && falhou "respondeu sozinho uma decisão: $(cat "$T/ag.log")"
saida=$(v "sim"); grep -qx 'escolheu: Yes' "$T/ag.log" && [[ $saida == *"Deploy pronto: faça o deploy"* ]] || falhou "sim na decisão: $saida / $(cat "$T/ag.log")"
tmux kill-session -t '=pede'
tmux new-session -d -s pede "PERGUNTA=rotina $B/agente-pergunta.sh"; : >"$T/ag.log"
saida=$(v "faça o deploy"); [[ $saida == *"pergunta: Update available"* ]] || falhou "rotina em sessão que não é da voz é perguntada: $saida"
v "dois" >/dev/null; grep -qx 'escolheu: Skip' "$T/ag.log" || falhou "dois: $(cat "$T/ag.log")"
tmux kill-session -t '=pede'
tmux new-session -d -s pede "PERGUNTA=rotina $B/agente-pergunta.sh"; tmux set-option -t '=pede:' @tt_voz 1; : >"$T/ag.log"
saida=$(v "faça o deploy"); grep -qx 'escolheu: Skip' "$T/ag.log" && [[ $saida == *"Deploy pronto"* && $saida != *Update* ]] ||
  falhou "rotina na sessão da voz, sozinha: $saida / $(cat "$T/ag.log")"
tmux kill-session -t '=pede'
passou 'voz: no meio do trabalho, a decisão é lida e espera o sim; a rotina, só na sessão aberta pela voz, vai sozinha'

# ---- fixadas ----
v "aba trabalho" >/dev/null
saida=$(v "fixar esta sessão"); [[ $saida == *"Sessão trabalho fixada na barra, na posição 1"* ]] || falhou "fixar: $saida"
saida=$(v "fixar a sessão outra"); [[ $saida == *"posição 2"* ]] || falhou "fixar outra: $saida"
saida=$(v "fixar a sessão outra"); [[ $saida == *"já está fixada, na posição 2"* ]] || falhou "fixar de novo não desafixa: $saida"
saida=$(v fixadas); [[ $saida == *"1, trabalho, no $EU. 2, outra, no $EU."* ]] || falhou "fixadas: $saida"
saida=$(v "mover a fixada outra para o início"); [[ $saida == *"agora na posição 1"* ]] || falhou "mover: $saida"
[[ $(tt --fixadas | cut -f2 | tr '\n' ' ') == "outra trabalho " ]] || falhou "ordem das fixadas: $(tt --fixadas)"
saida=$(v "desafixar a sessão outra"); [[ $saida == *"fora das fixadas"* && $(tt --fixadas | cut -f2) == trabalho ]] || falhou "desafixar: $saida"
saida=$(v "desafixar a sessão outra"); [[ $saida == *"não está fixada"* ]] || falhou "desafixar de novo: $saida"
passou 'voz: fixar, listar, mover e desafixar as fixadas (fixar de novo não desfaz)'

# ---- tarefas ----
saida=$(v "nova tarefa Comprar pão para amanhã às 14 horas"); [[ $saida == *"Tarefa criada: Comprar pão, apelido "* ]] || falhou "nova tarefa: $saida"
ap=$(tt --tarefa-codigo | awk -F'\t' '$3 == "Comprar pão" { print $1 }')
[[ -n $ap && $(tt --tarefa-frase "$ap") == "Comprar pão @"*" 14h" ]] || falhou "tarefa com prazo e hora: $(tt --tarefa-frase "$ap")"
saida=$(v "adicione a subtarefa ligar na padaria na tarefa comprar pão"); [[ $saida == *"Subtarefa criada em Comprar pão: ligar na padaria"* ]] || falhou "subtarefa: $saida"
saida=$(v "concluir a tarefa comprar pão"); [[ $saida == *"Não concluí Comprar pão"* ]] || falhou "mãe com subtarefa aberta: $saida"
saida=$(v "marque a tarefa ligar na padaria como feita"); [[ $saida == *"Concluída: ligar na padaria"* ]] || falhou "concluir a subtarefa: $saida"
saida=$(v "concluir a tarefa comprar pão"); [[ $saida == *"Concluída: Comprar pão"* ]] || falhou "concluir: $saida"
saida=$(v "reabrir a tarefa comprar pão"); [[ $saida == *"Reaberta: Comprar pão"* ]] || falhou "reabrir: $saida"
saida=$(v "mude o prazo da tarefa comprar pão para sexta"); [[ $saida == *"Prazo de Comprar pão:"* && $(tt --tarefa-frase "$ap") == *"@"* && $(tt --tarefa-frase "$ap") != *"14h"* ]] || falhou "prazo: $saida / $(tt --tarefa-frase "$ap")"
saida=$(v "tire o prazo da tarefa comprar pão"); [[ $saida == *"Tirei o prazo"* && $(tt --tarefa-frase "$ap") != *"@"* ]] || falhou "sem prazo: $saida"
saida=$(v "qual o apelido da tarefa comprar pão"); [[ $saida == *"tem o apelido $(sed -E 's/([0-9])/ \1/g' <<<"$ap")"* ]] || falhou "apelido: $saida"
saida=$(v "apagar a tarefa comprar pão"); [[ $saida == *"Apagar a tarefa Comprar pão, de vez? Diga sim"* ]] || falhou "apagar pede confirmação: $saida"
v "não" >/dev/null; tt --tarefa-codigo | grep -q "Comprar pão" || falhou "não apagou com o não"
v "apagar a tarefa comprar pão" >/dev/null; saida=$(v "sim"); [[ $saida == *"Apaguei a tarefa Comprar pão"* ]] && ! tt --tarefa-codigo | grep -q "Comprar pão" || falhou "apagar com o sim: $saida"
passou 'voz: tarefas (criar com prazo e hora, subtarefa, concluir, reabrir, prazo, apelido, apagar só com o sim)'

# ---- notificações e letreiro ----
tt --notificar "📧 e-mail novo de Ana: proposta" 3000 >/dev/null 2>&1; tt --notificar "🤖 sessão x terminou" 3000 >/dev/null 2>&1
saida=$(v "ler as notificações"); [[ $saida == *"2 não lidas: 1, "*"sessão x terminou"*"2, "*"e-mail novo de Ana: proposta"* ]] || falhou "notificações: $saida"
saida=$(v "marcar as notificações como lidas"); [[ $saida == *"Marquei 2 como lidas"* ]] || falhou "lidas: $saida"
saida=$(v notificações); [[ $saida == *"Nenhuma notificação não lida"* ]] || falhou "nada não lido: $saida"
saida=$(v "limpar as notificações"); [[ $saida == *"Apagar as 2 notificações já lidas"* ]] || falhou "limpar pede confirmação: $saida"
saida=$(v sim); [[ $saida == *"Apaguei 2 notificações lidas"* && -z $(tt --notifs-listar) ]] || falhou "limpar: $saida / $(tt --notifs-listar)"
saida=$(v "pausar o letreiro"); [[ $saida == *"Letreiro pausado"* && -s $TT_RT/tt-letreiro-pausa ]] || falhou "pausar o letreiro: $saida"
[[ $(tt --letreiro-pausa) == pausado ]] || falhou "estado do letreiro"
saida=$(v "pausar o letreiro"); [[ $saida == *"Letreiro pausado"* && -s $TT_RT/tt-letreiro-pausa ]] || falhou "pausar duas vezes não solta: $saida"
saida=$(v "continuar o letreiro"); [[ $saida == *"rolando de novo"* && ! -e $TT_RT/tt-letreiro-pausa ]] || falhou "continuar o letreiro: $saida"
saida=$(v "o que está no letreiro"); [[ $saida == *"O letreiro está vazio"* || $saida == *"No letreiro:"* ]] || falhou "ler o letreiro: $saida"
passou 'voz: notificações (ler, marcar lidas, limpar só com o sim) e o letreiro (pausar, continuar, ler)'

# ---- fechar uma sessão: confirmação; a escolhida que trabalha pede duas vezes ----
saida=$(v "fechar a sessão outra"); [[ $saida == *"Fechar a sessão outra, em $EU? Diga sim para fechar."* ]] || falhou "fechar pede confirmação: $saida"
v "não" >/dev/null; tmux has-session -t '=outra' || falhou "fechou com o não"
v "fechar a sessão outra" >/dev/null; saida=$(v sim); [[ $saida == *"Fechei a sessão outra"* ]] && ! tmux has-session -t '=outra' 2>/dev/null || falhou "fechar: $saida"
v "aba trabalho" >/dev/null; tmux send-keys -t '=trabalho:' 'mais um' Enter; sleep 1.5
saida=$(v "feche esta sessão"); [[ $saida == *"Diga sim para fechar"* ]] || falhou "fechar a escolhida: $saida"
saida=$(v sim); [[ $saida == *"Atenção: ela está trabalhando agora e é a sessão escolhida. Tem certeza? Diga sim de novo"* ]] && tmux has-session -t '=trabalho' ||
  falhou "a escolhida que trabalha não pediu de novo: $saida"
saida=$(v sim); [[ $saida == *"Fechei a sessão trabalho"* ]] && ! tmux has-session -t '=trabalho' 2>/dev/null && [[ ! -s $EST/alvo_s ]] || falhou "fechar na 2ª: $saida"
saida=$(v "fechar a sessão _interna"); [[ $saida == *"Não achei"* || $saida == *"interna"* || $saida == *"Qual sessão"* ]] || falhou "sessão oculta: $saida"
passou 'voz: fechar uma sessão (com confirmação; a escolhida ou que trabalha pede o sim duas vezes)'

# ---- limpeza: analisa, sugere com o motivo, tira da lista e fecha em lote ----
for s in velha agente-velho pergunta olhando fixa editor recente; do tmux new-session -d -s "$s" 'sleep 600'; done
tmux new-session -d -s escolhida 'sleep 600'; v "aba escolhida" >/dev/null
cab=$'maquina\tsessao\tanexada\tocioso_s\tjanelas\tcmd_1oplano\tagente\tfixada\tpapel\trascunho\ttitulo\tultima_linha'
{ echo "$cab"
  printf '%s\tvelha\t0\t200000\t1\tbash\t-\t0\t-\t-\t-\thelio@dell:~$\n' "$EU"
  printf '%s\tagente-velho\t0\t20000\t1\tclaude\tclaude\t0\tatalho\t0\t-\t● Pronto, terminei o relatório.\n' "$EU"
  printf '%s\tpergunta\t0\t20000\t1\tclaude\tclaude\t0\tatalho\t0\t-\t● Posso seguir com o deploy?\n' "$EU"
  printf '%s\tolhando\t1\t20000\t1\tbash\t-\t0\t-\t-\t-\t$\n' "$EU"
  printf '%s\tfixa\t0\t20000\t1\tbash\t-\t1\t-\t-\t-\t$\n' "$EU"
  printf '%s\teditor\t0\t20000\t1\tvim\tvim\t0\t-\t-\t-\t~\n' "$EU"
  printf '%s\trecente\t0\t600\t1\tbash\t-\t0\t-\t-\t-\t$\n' "$EU"
  printf '%s\tescolhida\t0\t90000\t1\tbash\t-\t0\t-\t-\t-\t$\n' "$EU"; } >"$T/tsv"
export VOZ_TSV_FALSO=$T/tsv VOZ_LIMPEZA_RECENTE=0
saida=$(v "quais sessões posso fechar")
[[ $saida == *"Analisei 8 sessões: 6 em uso, e 2 paradas que podem fechar."* && $saida == *"1, velha, no $EU: terminal sem programa, parado há 2 dias."* &&
  $saida == *"2, agente velho, no $EU: Claude parado há 5 horas; por último: ● Pronto, terminei o relatório."* && $saida == *"Diga fechar"* ]] ||
  falhou "limpeza sugere: $saida"
grep -q $'\tpergunta\tClaude espera sua resposta' "$EST/limpeza.analise" && grep -q $'\tolhando\talguém está olhando' "$EST/limpeza.analise" &&
  grep -q $'\tfixa\testá fixada' "$EST/limpeza.analise" && grep -q $'\teditor\tprograma aberto' "$EST/limpeza.analise" &&
  grep -q $'\tescolhida\té a sessão escolhida' "$EST/limpeza.analise" || falhou "motivos de manter: $(cat "$EST/limpeza.analise")"
saida=$(v "tira a dois"); [[ $saida == *"Tirei. Ficam 1: 1, velha"* && $saida != *"agente velho"* ]] || falhou "tirar da lista: $saida"
saida=$(v fechar); [[ $saida == *"Fechei 1: velha."* ]] && ! tmux has-session -t '=velha' 2>/dev/null && tmux has-session -t '=agente-velho' || falhou "fechar em lote: $saida"
saida=$(v limpeza); v "cancelar" >/dev/null; tmux has-session -t '=agente-velho' || falhou "cancelar a limpeza fechou"
printf '%s\n' "$cab" >"$T/tsv"; saida=$(v limpeza); [[ $saida == *"Nada para fechar"* ]] || falhou "nada a fechar: $saida"
passou 'voz: limpeza (motivos de manter e de fechar, tirar da lista, fechar em lote, cancelar)'

# ---- pelo cérebro: as ações novas chegam do JSON ----
unset VOZ_TSV_FALSO
tmux new-session -d -s cerebro 'sleep 600'
c() { VOZ_CEREBRO_CMD="cat >/dev/null; echo '$1'" v "$2"; }
saida=$(c '{"fala": "", "acoes": [{"acao": "esperar", "segundos": 120, "depois": "avisar"}]}' "me chama em dois minutinhos")
[[ $saida == *"daqui a 2 minutos, eu aviso"* ]] || falhou "cérebro esperar: $saida"
saida=$(c '{"fala": "", "acoes": [{"acao": "fechar_sessao", "sessao": "cerebro"}]}' "pode encerrar aquela sessão do cérebro")
[[ $saida == *"Fechar a sessão cerebro"* ]] && tmux has-session -t '=cerebro' || falhou "cérebro fechar pede confirmação: $saida"
v "não" >/dev/null
saida=$(c '{"fala": "", "acoes": [{"acao": "tarefa_nova", "texto": "Revisar o PR @amanha 9h !alta"}]}' "me lembra de revisar o PR amanhã cedo, é urgente")
[[ $saida == *"Tarefa criada: Revisar o PR"* ]] && [[ $(tt --tarefa-frase "$(tt --tarefa-codigo | awk -F'\t' '$3 == "Revisar o PR" { print $1 }')") == *"9h !alta"* ]] || falhou "cérebro tarefa: $saida"
v "cancelar espera" >/dev/null
regras=$(bash -c "source <(sed -n '/^cerebro_regras()/,/^}/p' '$V'); cerebro_regras")
for a in esperar acompanhar cancelar_espera fixar mover_fixada tarefa_nova subtarefa prazo_tarefa notificacoes letreiro fechar_sessao limpeza; do
  grep -q "\"acao\":\"$a\"" <<<"$regras" || falhou "o prompt do Terminal não tem a ação $a"
done
passou 'voz: o cérebro (prompt do Terminal) usa as ações novas: esperar, fechar com confirmação, tarefa com marcadores'
