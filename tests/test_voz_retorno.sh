#!/usr/bin/env bash
# tt-teste: sozinho (prazo de 2 s durante agente de 12 s; carga paralela muda o cenário)
# voz: o modo retorno. Os ganchos dos agentes nas sessões da voz (ia-conta passa o Stop/Notification ao Claude e o notify
# ao Codex; voz --evento grava o aviso com a última mensagem, só na sessão da voz); o modo (microfone fechado, o pedido não
# espera ouvindo, a sessão chama quando responde, pede uma decisão ou fecha; a conferência de reserva para o agente sem
# gancho; o prazo sem notícia com o resumo do que mudou desde o pedido; sai sozinho sem nada em aberto); as frases, o
# cérebro e a janela (espera com o microfone fechado, fala o retorno e volta a esperar). O tt é o de verdade, isolado; os
# agentes são falsos.
source "$(dirname "$0")/lib.sh"; isolar
V=$RAIZ/voz; A=$RAIZ/voz-audio.py
EST=$HOME/.local/state/tt-voz
B=$T/fake; mkdir -p "$B"
cat >"$B/tt" <<FIM
#!/usr/bin/env bash
exec "$TT" "\$@"
FIM
# agente com gancho (como o Claude com o Stop): trabalha VOZ_T_AGENTE s, responde e avisa a voz com a última mensagem
cat >"$B/agente-gancho.sh" <<'FIM'
#!/usr/bin/env bash
while IFS= read -r l; do
  for ((i = 0; i < ${VOZ_T_AGENTE:-2}; i++)); do printf '\r✻ Working… (%ds · esc to interrupt)' "$i"; sleep 1; done
  printf '\r\033[K● Feito: %s. Tudo certo.\n> ' "$l"
  printf '{"hook_event_name":"Stop","last_assistant_message":"Feito: %s. Tudo **certo**."}' "$l" | "$VOZ_BIN" --evento terminou claude
done
FIM
# agente sem gancho (como o Kiro): só a tela muda; trabalha VOZ_T_LENTO s
cat >"$B/agente-lento.sh" <<'FIM'
#!/usr/bin/env bash
while IFS= read -r l; do
  for ((i = 0; i < ${VOZ_T_LENTO:-3}; i++)); do printf '\r✻ Working… (%ds · esc to interrupt)' "$i"; sleep 1; done
  printf '\r\033[K● Pronto: %s, sem erros.\n> ' "$l"
done
FIM
# agente que pede uma decisão antes de seguir (o menu de permissão do Claude)
cat >"$B/agente-pergunta.sh" <<'FIM'
#!/usr/bin/env bash
IFS= read -r l
printf '\033[2J\033[HBash command: make deploy\nDo you want to proceed?\n ❯ 1. Yes\n   2. No, and tell Claude what to do differently (esc)\n'
IFS= read -rsn1 c
printf '\033[2J\033[H● Deploy pronto: %s.\n> ' "$l"
sleep 600
FIM
chmod +x "$B"/*
export PATH="$B:$PATH" VOZ_SDCARD=$T/sd VOZ_BIN=$V VOZ_RETORNO_POLL=1 VOZ_DESTRAVAR_PAUSA=0.5
mkdir -p "$T/sd"
v() { VOZ_MUDO=1 bash "$V" "$@"; }
pronto() { local i; for ((i = 0; i < ${1:-30}; i++)); do v --fundo-pronto >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }
EU=$(tt --listar-tudo --para-ia | sed -n '1s/.*— \([^ ]*\) —.*/\1/p')

# ---- os ganchos: voz --evento grava só na sessão da voz; ia-conta os passa ao Claude e ao Codex só nela ----
tmux new-session -d -s gancho 'sleep 600'; tmux set-option -t '=gancho:' @tt_voz 1
tmux new-session -d -s solta 'sleep 600'
evento() { # SESSÃO TIPO AGENTE [JSON-ARG] < stdin
  TMUX="$(tmux display-message -p '#{socket_path}'),1,0" TMUX_PANE=$(tmux display-message -p -t "=$1:" '#{pane_id}') bash "$V" --evento "$2" "$3" ${4:+"$4"}
}
echo '{"last_assistant_message":"Pronto: os testes passaram."}' | evento gancho terminou claude
IFS=$'\t' read -r id s tipo ag arq <"$EST/eventos"
[[ $id =~ ^[0-9]+\.[0-9]+$ && $s == gancho && $tipo == terminou && $ag == claude && $(cat "$arq") == 'Pronto: os testes passaram.' ]] ||
  falhou "evento do Stop: $(cat "$EST/eventos")"
echo '{"last_assistant_message":"não devia"}' | evento solta terminou claude
[[ $(grep -c . "$EST/eventos") == 1 ]] || falhou "sessão que não é da voz gravou evento: $(cat "$EST/eventos")"
echo '{"notification_type":"idle_prompt","message":"Claude is waiting for your input"}' | evento gancho pergunta claude
[[ $(grep -c . "$EST/eventos") == 1 ]] || falhou "o idle_prompt (depois do fim da vez) virou evento"
echo '{"notification_type":"permission_prompt","message":"Claude needs your permission to use Bash"}' | evento gancho pergunta claude
evento gancho terminou codex '{"type":"agent-turn-complete","last-assistant-message":"Codex: feito."}' </dev/null
[[ $(sed -n 2p "$EST/eventos" | cut -f3) == pergunta && $(sed -n 3p "$EST/eventos" | cut -f3,4) == $'terminou\tcodex' &&
  $(cat "$(sed -n 3p "$EST/eventos" | cut -f5)") == 'Codex: feito.' ]] || falhou "Notification e notify do Codex: $(cat "$EST/eventos")"
[[ -z $(evento gancho terminou claude </dev/null 2>&1) ]] || falhou 'o gancho imprimiu algo (o Stop do Claude leria como resposta)'
tmux kill-session -t '=gancho'; tmux kill-session -t '=solta'; rm -rf "$EST/eventos" "$EST/eventos.d"
# ia-conta: nas sessões da voz, --settings com os ganchos ao Claude e -c notify ao Codex; nas outras, nada
mkdir -p "$HOME/.local/bin" "$HOME/.claude"
H=$HOME/.local/bin
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >"$HOME/claude.args"\n' >"$H/claude"
printf '#!/usr/bin/env bash\n[[ $1 == login ]] && exit 0\nprintf "%%s\\n" "$@" >"$HOME/codex.args"\n' >"$H/codex"
chmod +x "$H/claude" "$H/codex"
echo '{"claudeAiOauth":{"accessToken":"t","expiresAt":9999999999999}}' >"$HOME/.claude/.credentials.json"
PATH="$H:$PATH" TT_VOZ_EVENTOS=1 bash "$RAIZ/ia-conta" abrir --conta principal </dev/null >/dev/null 2>&1
grep -qx -- --settings "$HOME/claude.args" && python3 -I -c '
import json, sys
a = open(sys.argv[1]).read().split("\n")
h = json.loads(a[a.index("--settings") + 1])["hooks"]
assert h["Stop"][0]["hooks"][0]["command"].endswith("/voz --evento terminou claude"), h
assert h["Notification"][0]["hooks"][0]["command"].endswith("/voz --evento pergunta claude"), h' "$HOME/claude.args" ||
  falhou "ia-conta sem os ganchos do Claude na sessão da voz: $(cat "$HOME/claude.args")"
grep -qx -- --dangerously-skip-permissions "$HOME/claude.args" || falhou 'o resto dos argumentos do Claude sumiu'
PATH="$H:$PATH" TT_VOZ_EVENTOS=1 bash "$RAIZ/ia-conta" abrir --conta codex </dev/null >/dev/null 2>&1
grep -qxF -- "notify=[\"$(cd "$RAIZ" && pwd -P)/voz\",\"--evento\",\"terminou\",\"codex\"]" "$HOME/codex.args" && grep -qx -- --yolo "$HOME/codex.args" ||
  falhou "ia-conta sem o notify do Codex: $(cat "$HOME/codex.args")"
rm -f "$HOME/claude.args" "$HOME/codex.args"
PATH="$H:$PATH" TT_VOZ_EVENTOS= TMUX= bash "$RAIZ/ia-conta" abrir --conta principal </dev/null >/dev/null 2>&1
grep -q -- --settings "$HOME/claude.args" && falhou 'sessão que não é da voz ganhou os ganchos'
# dentro do tmux, a marca @tt_voz da sessão basta (o 👇 e o ⏩ marcam antes de abrir o agente)
tmux new-session -d -s marcada "sleep 600"; tmux set-option -t '=marcada:' @tt_voz 1
rm -f "$HOME/claude.args"
tmux respawn-pane -k -t '=marcada:' "PATH='$H:$PATH' TT_VOZ_EVENTOS= bash '$RAIZ/ia-conta' abrir --conta principal </dev/null; sleep 600"
for i in $(seq 50); do [[ -s $HOME/claude.args ]] && break; sleep 0.2; done
grep -qx -- --settings "$HOME/claude.args" || falhou "a sessão marcada @tt_voz não ganhou os ganchos: $(cat "$HOME/claude.args" 2>&1)"
tmux kill-session -t '=marcada'; rm -f "$H/claude" "$H/codex"
passou 'ganchos: voz --evento grava fim e pedido com a última mensagem só na sessão da voz (sem imprimir nada); ia-conta os passa ao Claude e ao Codex só nela'

# ---- o modo retorno, com um agente que avisa pelo gancho ----
tmux new-session -d -s rapida "$B/agente-gancho.sh"; tmux set-option -t '=rapida:' @tt_voz 1
tmux new-session -d -s lenta "$B/agente-lento.sh"
v "aba rapida" >/dev/null
saida=$(v "modo retorno"); [[ $saida == *"Modo retorno: fecho o microfone. Nenhuma sessão trabalha num pedido seu agora"* && -s $EST/retorno ]] ||
  falhou "entrar no modo retorno: $saida"
t0=$(date +%s); saida=$(v "rode a primeira verificação")
[[ $saida == *"Enviado para rapida. Te chamo quando responder."* ]] && (($(date +%s) - t0 < 8)) || falhou "no modo retorno o pedido esperou ouvindo: $saida"
[[ $(awk -F'\t' '$2 == "rapida" { print ($3 > $4) }' "$EST/chamadas") == 1 ]] || falhou "chamada em aberto: $(cat "$EST/chamadas")"
[[ $(v --retorno-pronto | head -n 1) == "rapida há "* ]] || falhou "linha de estado: $(v --retorno-pronto)"
saida=$(v "o que você está esperando"); [[ $saida == *"Modo retorno: espero a sessão rapida."* ]] || falhou "esperas: $saida"
pronto 20 || falhou 'o gancho não fez a sessão chamar'
saida=$(v --turno-fundo)
[[ $saida == *"A sessão rapida respondeu: Feito: rode a primeira verificação. Tudo certo."* &&
  $saida == *"Era a última resposta que eu esperava: saí do modo retorno."* && ! -e $EST/retorno ]] || falhou "retorno pelo gancho: $saida"
v --fundo-pronto && falhou 'a resposta já falada voltou a chamar'
passou 'modo retorno: o pedido não espera ouvindo; o gancho faz a sessão chamar com a última mensagem; sem nada em aberto, sai do modo'

# ---- o agente sem gancho: a conferência de reserva; o prazo sem notícia, com o resumo do que mudou desde o pedido ----
v "aba lenta" >/dev/null
saida=$(v "modo retorno por 2 segundos"); [[ $saida == *"se nada acontecer em 2 segundos, eu chamo mesmo assim, com um resumo"* ]] ||
  falhou "modo retorno com prazo: $saida"
[[ $(cut -f2 "$EST/retorno") == 2 ]] || falhou "prazo gravado: $(cat "$EST/retorno")"
tmux kill-session -t '=lenta'; tmux new-session -d -s lenta "VOZ_T_LENTO=12 $B/agente-lento.sh"
v "aba lenta" >/dev/null
v "conte até doze devagar" >/dev/null
pronto 15 || falhou 'o prazo não venceu'
saida=$(VOZ_CEREBRO_CMD="cat >'$T/cerebro.txt'; echo '{\"fala\": \"Lenta: ainda contando, sem erro.\", \"acoes\": []}'" v --turno-fundo)
[[ $saida == *"Passou o prazo sem notícia. Lenta: ainda contando, sem erro."* ]] || falhou "resumo do prazo: $saida"
grep -q '^RETORNO\.' "$T/cerebro.txt" && grep -q '«conte até doze devagar»' "$T/cerebro.txt" && grep -q 'TRABALHANDO' "$T/cerebro.txt" ||
  falhou "o cérebro não recebeu o pedido e o estado: $(cat "$T/cerebro.txt")"
grep -q 'aba rapida' "$T/cerebro.txt" && falhou 'o resumo levou a tela de antes do pedido (devia ser só o que mudou)'
[[ -s $EST/retorno ]] || falhou 'o prazo tirou do modo com a sessão ainda em aberto'
pronto 15 || falhou 'o segundo prazo não venceu'
saida=$(VOZ_CEREBRO_CMD="exit 1" v --turno-fundo)
[[ $saida == *"Passou o prazo sem notícia. A sessão lenta ainda trabalha há"* ]] || falhou "prazo sem o cérebro: $saida"
printf '%s\t0\t%s\t\n' "$(date +%s)" "$(date +%s)" >"$EST/retorno"  # sem prazo: só a reserva
pronto 25 || falhou 'a conferência de reserva não viu o fim'
saida=$(v --turno-fundo); [[ $saida == *"A sessão lenta respondeu: Pronto: conte até doze devagar, sem erros."* ]] || falhou "fim pela reserva: $saida"
passou 'modo retorno: o agente sem gancho chama pela conferência de reserva; o prazo sem notícia resume o que mudou desde o pedido (sem o cérebro, o estado)'

# ---- a decisão no meio do trabalho: lida; respondida, a sessão volta a ser esperada; a sessão que fecha também chama ----
tmux new-session -d -s decide "$B/agente-pergunta.sh"; v "aba decide" >/dev/null
v "modo retorno" >/dev/null; v "faça o deploy" >/dev/null
pronto 15 || falhou 'a decisão não chamou'
saida=$(v --turno-fundo); [[ $saida == *"pede uma decisão sua"* && $saida == *"1, Yes. 2, No"* ]] || falhou "decisão no retorno: $saida"
[[ -s $EST/retorno ]] || falhou 'a pergunta tirou do modo'
saida=$(v "um"); [[ $saida == *"Respondido. Te chamo quando a sessão decide responder."* ]] || falhou "responder no retorno: $saida"
pronto 15 || falhou 'o fim depois da decisão não chamou'
saida=$(v --turno-fundo); [[ $saida == *"A sessão decide respondeu: Deploy pronto: faça o deploy."* ]] || falhou "fim depois da decisão: $saida"
tmux new-session -d -s some "$B/agente-lento.sh"; v "aba some" >/dev/null
v "modo retorno" >/dev/null; v "trabalhe bastante" >/dev/null; tmux kill-session -t '=some'
pronto 15 || falhou 'a sessão que fechou não chamou'
saida=$(v --turno-fundo); [[ $saida == *"A sessão some, que eu esperava, fechou."* ]] || falhou "sessão fechada: $saida"
passou 'modo retorno: a decisão é lida (e, respondida, a sessão volta a ser esperada); a sessão que fecha também chama'

# ---- as frases, o automático, o cancelar e o cérebro ----
r() { VOZ_CEREBRO_CMD="exit 1" v "$@"; }
for f in "modo retorno por 5 minutos:300" "entrar no modo callback:0" "me chama quando elas terminarem:0" \
  "pode ir que eu espero no máximo 2 minutos:120" "modo retorno de meia hora:1800" "me avise assim que alguma responder:0"; do
  rm -f "$EST/retorno"; r "${f%:*}" >/dev/null
  [[ $(cut -f2 "$EST/retorno" 2>/dev/null) == "${f##*:}" ]] || falhou "frase '${f%:*}': $(cat "$EST/retorno" 2>&1)"
done
saida=$(r "sair do modo retorno"); [[ $saida == *"Saí do modo retorno."* && ! -e $EST/retorno ]] || falhou "sair: $saida"
for f in "pode ir para a sessão lenta" "vai fazer o deploy agora" "me chama a sessão lenta"; do
  rm -f "$EST/retorno"; r "$f" >/dev/null; [[ -e $EST/retorno ]] && falhou "frase que não é do retorno ligou o modo: $f"
done
r "modo retorno" >/dev/null; saida=$(r "cancele a espera"); [[ ! -e $EST/retorno && $saida == *Cancelei* ]] || falhou "cancelar espera e o modo: $saida"
saida=$(r "ligar o retorno automático"); [[ -e $HOME/.config/tt-voz/retorno-auto && $saida == *"Retorno automático ligado"* ]] || falhou "automático: $saida"
tmux new-session -d -s auto "$B/agente-gancho.sh"; tmux set-option -t '=auto:' @tt_voz 1; r "aba auto" >/dev/null
t0=$(date +%s); saida=$(r "faça a segunda"); (($(date +%s) - t0 < 8)) && [[ $saida == *"Fecho o microfone e te chamo quando responder."* && -s $EST/retorno ]] ||
  falhou "retorno automático ao mandar: $saida"
pronto 20 && saida=$(r --turno-fundo); [[ $saida == *"A sessão auto respondeu: Feito: faça a segunda."* ]] || falhou "retorno automático: $saida"
r "desligar o retorno automático" >/dev/null; [[ -e $HOME/.config/tt-voz/retorno-auto ]] && falhou 'desligar o automático'
saida=$(VOZ_CEREBRO_CMD="cat >/dev/null; echo '{\"fala\": \"\", \"acoes\": [{\"acao\": \"retorno\", \"segundos\": 240}]}'" v "vou almoçar, me liga se algo acontecer")
[[ $(cut -f2 "$EST/retorno") == 240 && $saida == *"Modo retorno"* ]] || falhou "cérebro: retorno: $saida"
VOZ_CEREBRO_CMD="cat >/dev/null; echo '{\"fala\": \"\", \"acoes\": [{\"acao\": \"sair_retorno\"}]}'" v "voltei, pode me ouvir de novo" >/dev/null
[[ -e $EST/retorno ]] && falhou 'cérebro: sair_retorno'
regras=$(bash -c "source <(sed -n '/^cerebro_regras()/,/^}/p' '$V'); cerebro_regras")
for a in retorno sair_retorno retorno_auto; do grep -q "\"acao\":\"$a\"" <<<"$regras" || falhou "o prompt do Terminal não tem a ação $a"; done
saida=$(r "ajuda retorno"); [[ $saida == *"Modo retorno: diga modo retorno"* ]] || falhou "ajuda retorno: $saida"
passou 'modo retorno: frases (com prazo; as parecidas não ligam), sair, cancelar, o automático e o cérebro'

# ---- a janela: espera com o microfone fechado, fala o retorno e volta a esperar; pausar e retomar o gravador ----
r=$(VOZ_GRAVADOR="while :; do head -c 3200 /dev/zero || exit 0; sleep 0.1; done" python3 - "$A" <<'EOF'
import importlib.util, sys, time
spec = importlib.util.spec_from_file_location("va", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
g = m.Gravador(); assert g.escolher(); p = g.fluxo.p; time.sleep(0.3)
g.pausar(); time.sleep(0.3)
assert g.fluxo is None and p.poll() is not None, "pausar não fechou o gravador"
assert g.retomar() and g.fluxo.vivo and g.fluxo.p is not p, "retomar não reabriu"
assert g.fluxo.quadro(2.0) is not None, "o gravador reaberto não manda áudio"
g.fechar()
w = m.som_plim(); assert w[:4] == b"RIFF" and len(w) > 4000, "o som do aviso"
f = m.Falador.__new__(m.Falador); f.qual = "cmd"; tocou = []; f._tocar_wav = tocou.append
m.tocador = lambda saida=None: ["x"]; f.plim(); assert tocou and tocou[0][:4] == b"RIFF", "plim não tocou"
import os; os.environ["VOZ_PLIM"] = "0"; tocou.clear(); f.plim(); assert not tocou, "VOZ_PLIM=0 não desligou"
print("ok")
EOF
)
[[ $r == ok ]] || falhou "gravador e aviso: $r"
tmux new-session -d -s jan "$B/agente-gancho.sh"; tmux set-option -t '=jan:' @tt_voz 1; v "aba jan" >/dev/null
rm -f "$EST/retorno" "$EST/chamadas"
J=$T/janela; mkdir -p "$J"
tmux new-session -d -s conversa -x 110 -y 30 -e VOZ_T_RETORNO=1 -e VOZ_PLIM=0 -e VOZ_FALA=nenhum -e VOZ_CEREBRO_VIVO=0 \
  -e PATH="$PATH" -e VOZ_BIN="$V" -e VOZ_RETORNO_POLL=1 "bash '$V' --conversa --digitar; echo SAIU=\$? >'$J/saiu'; sleep 60"
tela() { tmux capture-pane -p -J -t '=conversa:' 2>/dev/null; }
espera_tela() { local i; for i in $(seq 100); do tela | grep -qF "$1" && return 0; sleep 0.2; done; return 1; }
digitar() { tmux send-keys -t '=conversa:' -l "$1"; tmux send-keys -t '=conversa:' Enter; }
espera_tela 'você>' || falhou "a janela não abriu: $(tela)"
digitar 'modo retorno'
espera_tela '⏸ retorno: nada em andamento' || falhou "a janela não foi esperar no modo retorno: $(tela)"
tmux send-keys -t '=conversa:' t; sleep 0.5; digitar 'conte as linhas'
espera_tela 'Enviado para jan. Te chamo quando responder.' && espera_tela '⏸ retorno: jan há' ||
  falhou "pedido no modo retorno, na janela: $(tela)"
espera_tela 'tt: A sessão jan respondeu: Feito: conte as linhas. Tudo certo.' && tela | grep -qx 'retorno:' ||
  falhou "a janela não falou o retorno sozinha: $(tela)"
espera_tela 'saí do modo retorno' || falhou "a janela não saiu do modo: $(tela)"
digitar 'modo retorno'; espera_tela '⏸ retorno:' || falhou 'de volta ao modo'
tmux send-keys -t '=conversa:' r; espera_tela 'Saí do modo retorno. Pode falar.' || falhou "r não saiu do modo: $(tela)"
espera_tela 'você>' || falhou 'depois do r, não voltou a ouvir (digitar)'
tmux send-keys -t '=conversa:' Escape
for i in $(seq 50); do [[ -s $J/saiu ]] && break; sleep 0.2; done
[[ $(cat "$J/saiu" 2>/dev/null) == SAIU=0 ]] || falhou "Esc não fechou a janela: $(cat "$J/saiu" 2>&1) $(tela)"
passou 'janela: no modo retorno espera com o microfone fechado (pausar/retomar), fala o retorno sozinha e volta; r sai do modo; o aviso tem som (VOZ_PLIM=0 desliga)'
