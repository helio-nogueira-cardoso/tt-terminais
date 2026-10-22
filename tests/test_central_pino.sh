#!/usr/bin/env bash
# tt-teste: sozinho (mede tempo: roda sem outros testes disputando a máquina)
# Pino da central (tmux.conf instalado, cliente anexado, mouse SGR de verdade): clicar no 📍 de
# uma linha fixa a sessão E a própria central passa a mostrar 📌 na mesma linha; clicar de novo
# desafixa e volta a 📍. É o mesmo comportamento do pino da barra principal, agora consistente
# dentro da central. Regressão do bug em que com_x lia fixadas() com duas variáveis e o id entrava
# no nome da sessão, de modo que a chave nunca casava e o pino ficava sempre 📍.
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
echo copia_entre_maquinas=0 >>"$XDG_CONFIG_HOME/tt/config"
export TT_CLIQUE_LOG=${TT_CLIQUE_LOG-$T/cliques.log}
# Uma tecla sem efeito na lista confirma que o fzf já processou os eventos anteriores.
# Ver o pino pintado ainda não garante isso: o transform de load pode estar em execução.
export FZF_DEFAULT_OPTS="--bind='ctrl-]:execute-silent(touch $T/pronto)'"
tmux -f "$HOME/.tmux.conf" new -d -s minha -x 120 -y 30 'bash --norc' 2>/dev/null
tmux set-environment -g TT_CLIQUE_LOG "$TT_CLIQUE_LOG"
tmux set-environment -g FZF_DEFAULT_OPTS "$FZF_DEFAULT_OPTS"
tmux new -d -s outra 'bash --norc'
anexar v 120 32 minha; sleep 4
c=$(tmux list-clients -F '#{client_name}' | head -1)

tela() { fora capture-pane -p -t v; }
linha_minha() { tela | grep -n $'● minha' | head -1 | cut -d: -f1; }
coluna() { # linha alvo -> coluna 1-based (colunas de tela, emoji = 2)
  tela | sed -n "${1}p" | python3 -c '
import sys, unicodedata
alvo = sys.argv[1]; linha = sys.stdin.read().rstrip("\n")
i = linha.find(alvo)
if i >= 0:
    w = lambda ch: 2 if unicodedata.east_asian_width(ch) in "WF" else (0 if unicodedata.combining(ch) else 1)
    print(1 + sum(w(ch) for ch in linha[:i]))
' "$2"
}
# Gestos simples independentes precisam sair da janela de multiclíque (0,5 s do fzf).
# O teste específico abaixo ainda envia dois toques separados por apenas 0,1 s.
tocar() { fora send -t v -l $'\e[<0;'"$1;$2"$'M'; sleep 0.3; fora send -t v -l $'\e[<0;'"$1;$2"$'m'; sleep 0.6; }
# Dois toques no mesmo ponto em menos de 0,5 s: o fzf entrega o 2º como double-click.
tocar_duplo() { local i; for i in 1 2; do fora send -t v -l $'\e[<0;'"$1;$2"$'M'; fora send -t v -l $'\e[<0;'"$1;$2"$'m'; sleep 0.1; done; }
esperar() { local i; for ((i = 0; i < $2 * 2; i++)); do eval "$1" && return 0; sleep 0.5; done; return 1; }
pronto() {
  rm -f "$T/pronto"; fora send -t v C-]
  esperar '[[ -e $T/pronto ]]' 10 || falhou 'fzf não confirmou a entrada'
  sleep 0.6 # fora da janela de multiclíque, contada depois de o fzf processar a soltura
}
fixada() { grep -q $'\tminha\t' "$XDG_CONFIG_HOME/tt/fixadas" 2>/dev/null; }
# A linha de 'minha' na central mostra o emoji ALVO (📍 ou 📌).
pino_e() { local ln; ln=$(linha_minha); [[ -n $ln ]] && tela | sed -n "${ln}p" | grep -q "$1"; }

# Abre a central (mesma rota do botão ☰ / Ctrl+B s).
tmux run-shell -b "sleep 0.1; $TT --clique tt '$c' '' ''"
esperar '[[ -n $(linha_minha) ]]' 10 || falhou "central não abriu com a sessão minha: $(tela | sed -n '1,12p')"
esperar 'pino_e 📍' 6 || falhou "central não mostra 📍 antes de fixar: $(tela | sed -n "$(linha_minha)p")"
pronto

# Clica no pino 📍 da linha de 'minha'.
ln=$(linha_minha); col=$(coluna "$ln" '📍')
[[ -n $col ]] || falhou "📍 não encontrado na linha da central: $(tela | sed -n "${ln}p")"
# Força um transform lento: o fzf pausa o terminal após 1 s e precisa reativar o mouse.
mkdir "$XDG_CONFIG_HOME/tt/fixadas.trava"
(sleep 3; rmdir "$XDG_CONFIG_HOME/tt/fixadas.trava") & bloqueio=$!
tocar "$col" "$ln"
esperar fixada 8 || falhou 'clique no pino da central não fixou a sessão'
wait "$bloqueio"
esperar 'pino_e 📌' 8 || falhou "central não trocou 📍 por 📌 depois de fixar: $(tela | sed -n "$(linha_minha)p")"
passou 'pino da central fixa a sessão e a própria central passa a mostrar 📌'

# Clica de novo no pino (agora 📌) para desafixar.
pronto
ln=$(linha_minha); col=$(coluna "$ln" '📌')
[[ -n $col ]] || falhou "📌 não encontrado na linha da central: $(tela | sed -n "${ln}p")"
tocar "$col" "$ln"
esperar '! fixada' 8 || falhou "segundo clique no pino da central não desafixou a sessão: $(cat "${TT_CLIQUE_LOG:-/dev/null}"); tela: $(tela | sed -n '1,12p')"
esperar 'pino_e 📍' 8 || falhou "central não voltou 📌 para 📍 depois de desafixar: $(tela | sed -n "$(linha_minha)p")"
tmux has-session -t =minha 2>/dev/null || falhou 'clique no pino fechou a sessão em vez de só desafixar'
passou 'pino da central desafixa e volta a 📍, sem fechar a sessão'

# Toque duplo rápido no pino: são dois toques (fixa e desafixa) e a central continua aberta. O 2º chegava ao fzf
# como double-click, cujo padrão é aceitar a linha: a central fechava e entrava na sessão.
pronto
ln=$(linha_minha); col=$(coluna "$ln" '📍')
tocar_duplo "$col" "$ln"; sleep 1.5
[[ -n $(linha_minha) ]] || falhou "toque duplo no pino fechou a central: $(tela | grep -v '^$' | head -3)"
esperar '! fixada && pino_e 📍' 8 || falhou "toque duplo no pino deveria fixar e desafixar: $(tela | sed -n "$(linha_minha)p")"
passou 'toque duplo rápido no pino: fixa e desafixa, sem fechar a central'

# Toque duplo rápido no ✕: o 1º pede confirmação, o 2º confirma e fecha a sessão; a central continua aberta.
pronto
linha_outra() { tela | grep -n ' outra ' | head -1 | cut -d: -f1; }
ln=$(linha_outra); [[ -n $ln ]] || falhou "sessão outra fora da central: $(tela | sed -n '1,12p')"
col=$(coluna "$ln" '✕'); [[ -n $col ]] || falhou "✕ não encontrado: $(tela | sed -n "${ln}p")"
tocar_duplo "$col" "$ln"
esperar '! tmux has-session -t =outra 2>/dev/null' 8 || falhou "toque duplo no ✕ não fechou a sessão: $(tela | sed -n "${ln}p")"
sleep 0.5; [[ -n $(linha_minha) ]] || falhou 'toque duplo no ✕ fechou a central'
tmux has-session -t =minha 2>/dev/null || falhou 'toque duplo no ✕ fechou outra sessão'
passou 'toque duplo rápido no ✕: confirma e fecha a sessão, sem fechar a central'
