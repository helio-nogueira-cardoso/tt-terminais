#!/usr/bin/env bash
# Pino da central (tmux.conf instalado, cliente anexado, mouse SGR de verdade): clicar no 📍 de
# uma linha fixa a sessão E a própria central passa a mostrar 📌 na mesma linha; clicar de novo
# desafixa e volta a 📍. É o mesmo comportamento do pino da barra principal, agora consistente
# dentro da central. Regressão do bug em que com_x lia fixadas() com duas variáveis e o id entrava
# no nome da sessão, de modo que a chave nunca casava e o pino ficava sempre 📍.
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
echo copia_entre_maquinas=0 >>"$XDG_CONFIG_HOME/tt/config"
tmux -f "$HOME/.tmux.conf" new -d -s minha -x 120 -y 30 'bash --norc' 2>/dev/null
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
tocar() { fora send -t v -l $'\e[<0;'"$1;$2"$'M'; sleep 0.3; fora send -t v -l $'\e[<0;'"$1;$2"$'m'; }
esperar() { local i; for ((i = 0; i < $2 * 2; i++)); do eval "$1" && return 0; sleep 0.5; done; return 1; }
fixada() { grep -q $'\tminha\t' "$XDG_CONFIG_HOME/tt/fixadas" 2>/dev/null; }
# A linha de 'minha' na central mostra o emoji ALVO (📍 ou 📌).
pino_e() { local ln; ln=$(linha_minha); [[ -n $ln ]] && tela | sed -n "${ln}p" | grep -q "$1"; }

# Abre a central (mesma rota do botão ☰ / Ctrl+B s).
tmux run-shell -b "sleep 0.1; $TT --clique tt '$c' '' ''"
esperar '[[ -n $(linha_minha) ]]' 10 || falhou "central não abriu com a sessão minha: $(tela | sed -n '1,12p')"
esperar 'pino_e 📍' 6 || falhou "central não mostra 📍 antes de fixar: $(tela | sed -n "$(linha_minha)p")"

# Clica no pino 📍 da linha de 'minha'.
ln=$(linha_minha); col=$(coluna "$ln" '📍')
[[ -n $col ]] || falhou "📍 não encontrado na linha da central: $(tela | sed -n "${ln}p")"
tocar "$col" "$ln"
esperar fixada 8 || falhou 'clique no pino da central não fixou a sessão'
esperar 'pino_e 📌' 8 || falhou "central não trocou 📍 por 📌 depois de fixar: $(tela | sed -n "$(linha_minha)p")"
passou 'pino da central fixa a sessão e a própria central passa a mostrar 📌'

# Clica de novo no pino (agora 📌) para desafixar.
ln=$(linha_minha); col=$(coluna "$ln" '📌')
[[ -n $col ]] || falhou "📌 não encontrado na linha da central: $(tela | sed -n "${ln}p")"
tocar "$col" "$ln"
esperar '! fixada' 8 || falhou 'segundo clique no pino da central não desafixou a sessão'
esperar 'pino_e 📍' 8 || falhou "central não voltou 📌 para 📍 depois de desafixar: $(tela | sed -n "$(linha_minha)p")"
tmux has-session -t =minha 2>/dev/null || falhou 'clique no pino fechou a sessão em vez de só desafixar'
passou 'pino da central desafixa e volta a 📍, sem fechar a sessão'
