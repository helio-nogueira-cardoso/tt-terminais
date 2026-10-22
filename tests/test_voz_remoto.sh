#!/usr/bin/env bash
# voz 2.1.0 com as sessões em OUTRA máquina (o Mac): o plano de um ok, juntar e as sessões que conversam passam pelo ssh.
# O ssh falso faz o que o de verdade faz e o teste local não via: sem -n, lê o stdin inteiro de quem o chama (dentro de um
# "while read" comia os passos seguintes do plano); e o shell de lá é o zsh do Mac, que lê "=nome" sem aspas como o
# caminho do comando "nome" e não roda a linha ("zsh:1: nome not found"). Os comandos rodam aqui, no tmux isolado.
source "$(dirname "$0")/lib.sh"; isolar
V=$RAIZ/voz
EST=$HOME/.local/state/tt-voz
B=$T/fake; mkdir -p "$B" "$EST"
cat >"$B/tt" <<FIM
#!/usr/bin/env bash
[[ \$1 == --maquinas ]] && { echo 'eu@mac mac'; exit 0; }
exec "$TT" "\$@"
FIM
cat >"$B/ssh" <<'FIM'
#!/usr/bin/env bash
n=0
while [[ $1 == -* ]]; do case $1 in -n) n=1 ;; -o) shift ;; esac; shift; done; shift   # opções e o destino
((n)) || timeout 3 cat >/dev/null   # o ssh sem -n manda o stdin para lá (e o tira de quem chamou)
echo "$*" >>"$SSH_LOG"
if [[ " $*" =~ [[:space:]]=([A-Za-z_][^[:space:]]*) ]]; then echo "zsh:1: ${BASH_REMATCH[1]%%:*} not found" >&2; exit 1; fi
exec bash -c "$*"
FIM
# agente de mentira: a cada pedido trabalha 1 s e responde repetindo o que recebeu
cat >"$B/agente.sh" <<'FIM'
#!/usr/bin/env bash
while IFS= read -r l; do
  printf '\r✻ Working… (0s · esc to interrupt)'; sleep 1
  printf '\r\033[K● Feito: %s. Tudo certo.\n> ' "${l:0:200}"
done
FIM
chmod +x "$B"/*
export PATH="$B:$PATH" SSH_LOG=$T/ssh.log VOZ_SDCARD=$T/sd VOZ_DESTRAVAR_PAUSA=0.3 VOZ_ESPERA=8 VOZ_CONVERSA_ESPERA=30
mkdir -p "$T/sd"
v() { VOZ_MUDO=1 bash "$V" "$@" </dev/null; }
vc() { VOZ_CEREBRO_CMD="cat > '$T/pedido.txt'; printf '%s' '$1'" v "$2"; }
tem() { tmux has-session -t "=$1" 2>/dev/null; }
nj() { tmux list-windows -t "=$1:" 2>/dev/null | wc -l | tr -d ' '; }

tmux new-session -d -s site "$B/agente.sh"
tmux new-session -d -s backend "$B/agente.sh"
tmux new-session -d -s deploy-a 'sleep 600'
tmux new-session -d -s deploy-b 'sleep 600'
tmux new-session -d -s deploy-c 'sleep 600'
tmux new-session -d -s sobra 'sleep 600'; tmux new-window -t =sobra: 'sleep 600'
sleep 1

# ---- 1) o plano inteiro chega à pergunta, mesmo com cada passo indo pelo ssh ----
saida=$(vc '{"fala":"","acoes":[{"acao":"fechar_sessao","maquina":"mac","sessao":"deploy-b"},{"acao":"fechar_sessao","maquina":"mac","sessao":"deploy-c"},{"acao":"juntar_sessoes","maquina":"mac","sessao":"deploy-a","origem":"sobra"}]}' "no mac feche o deploy b e o deploy c e junte a sobra no deploy a")
[[ $saida == *"1, fechar a sessão deploy b"* && $saida == *"2, fechar a sessão deploy c"* && $saida == *"3, juntar as abas de sobra"* ]] ||
  falhou "o ssh do 1º passo comeu os outros do plano: $saida"
[[ $(grep -c . "$EST/lote" 2>/dev/null) == 3 ]] || falhou "fila com 3 itens: $(tr '\037' '|' <"$EST/lote" 2>/dev/null)"
grep -q ' -t =' "$SSH_LOG" && falhou "comando para o Mac com =sessão sem aspas: $(grep ' -t =' "$SSH_LOG" | head -n 2)"
passou 'plano em outra máquina: os três passos chegam à pergunta (o ssh não come o resto)'

# ---- 2) o sim executa tudo lá, em ordem ----
saida=$(v "sim")
tem deploy-b && falhou "deploy-b não fechou no sim: $saida"
tem deploy-c && falhou "deploy-c não fechou (o ssh do 1º fechamento comeu o resto da fila): $saida"
tem sobra && falhou "sobra não foi juntada: $saida"
[[ $(nj deploy-a) == 3 ]] || falhou "deploy-a deveria ter 3 abas (1 + as 2 da sobra): $(nj deploy-a); $saida"
[[ $saida == *"Juntei 2 abas"* ]] || falhou "juntar no Mac: $saida"
[[ ! -e $EST/lote ]] || falhou 'a fila deveria sumir depois do sim'
passou 'sim do plano em outra máquina: fecha as duas e junta as abas (zsh: =sessão com a barra)'

# ---- 3) sessões que conversam, as duas no Mac ----
: >"$SSH_LOG"
saida=$(VOZ_MUDO=1 timeout 90 "$TT" --sessao-falar mac:backend mac:site "valide o login novo" </dev/null 2>&1)
[[ $saida != *"não existe"* ]] || falhou "--sessao-falar no Mac deu a sessão como inexistente: $saida"
tela=$(tmux capture-pane -p -J -t =site: -S -50)
[[ $tela == *"Mensagem da sessão 'backend' (mac)"*"valide o login novo"* ]] || falhou "a mensagem não chegou à site: $tela"
tela=$(tmux capture-pane -p -J -t =backend: -S -50)
[[ $tela == *"Resposta da sessão 'site' (mac)"* ]] || falhou "a resposta não voltou à backend: $tela"
passou 'sessões que conversam no Mac: a mensagem vai e a resposta volta'
