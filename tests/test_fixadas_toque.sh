#!/usr/bin/env bash
# Fixar e desafixar por toque, de ponta a ponta: tmux.conf instalado, cliente anexado e mouse SGR de
# verdade. Toque no 📍 da barra fixa (o item aparece na faixa); toque no ✕ do item desafixa (some
# da faixa e da lista). Cada toque é pressionar + soltar, como no celular.
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
tmux -f "$HOME/.tmux.conf" new -d -s minha -x 120 -y 30 'bash --norc' 2>/dev/null
anexar v 120 32 minha; sleep 4

# Coluna (1-based, em colunas de tela) do texto ALVO na linha LINHA da tela do cliente; vazio se
# não estiver lá. Emojis e outros caracteres largos ocupam 2 colunas.
coluna() { # linha alvo
  fora capture-pane -p -t v | sed -n "${1}p" | python3 -c '
import sys, unicodedata
alvo = sys.argv[1]; linha = sys.stdin.read().rstrip("\n")
i = linha.find(alvo)
if i >= 0:
    w = lambda c: 2 if unicodedata.east_asian_width(c) in "WF" else (0 if unicodedata.combining(c) else 1)
    print(1 + sum(w(c) for c in linha[:i]))
' "$2"
}
tocar() { # coluna linha
  fora send -t v -l $'\e[<0;'"$1;$2"$'M'; sleep 0.3; fora send -t v -l $'\e[<0;'"$1;$2"$'m'
}
esperar() { # condição (comando) segundos
  local i; for ((i = 0; i < $2 * 2; i++)); do eval "$1" && return 0; sleep 0.5; done; return 1
}
barra=31 faixa=32
fixada() { grep -q $'\tminha\t' "$XDG_CONFIG_HOME/tt/fixadas" 2>/dev/null; }
na_faixa() { [[ -n $(coluna $faixa 'minha') ]]; }

x=$(coluna $barra '📍'); [[ -n $x ]] || falhou "📍 não está na barra: $(fora capture-pane -p -t v | sed -n "${barra}p")"
tocar "$x" $barra
esperar fixada 10 || falhou 'toque no 📍 não fixou a sessão'
esperar na_faixa 10 || falhou "fixada não apareceu na faixa: $(fora capture-pane -p -t v | sed -n "${faixa}p")"
[[ -n $(coluna $barra '📌') ]] || falhou 'o pino da barra não virou 📌 depois de fixar'
passou 'toque no 📍 da barra fixa a sessão e ela aparece na faixa'

# O ✕ do item: o primeiro ✕ depois do nome, na linha da faixa.
xn=$(coluna $faixa 'minha'); resto=$(fora capture-pane -p -t v | sed -n "${faixa}p")
xx=$(python3 -c '
import sys, unicodedata
l, n = sys.argv[1], int(sys.argv[2])
w = lambda c: 2 if unicodedata.east_asian_width(c) in "WF" else 1
col = 1
for c in l:
    if col > n and c == "✕": print(col); break
    col += w(c)
' "$resto" "$xn")
[[ -n $xx ]] || falhou "✕ do item não encontrado na faixa: $resto"
tocar "$xx" $faixa
esperar '! fixada' 10 || falhou 'toque no ✕ não desafixou a sessão'
esperar '! na_faixa' 10 || falhou "item continuou na faixa depois do ✕: $(fora capture-pane -p -t v | sed -n "${faixa}p")"
tmux has-session -t =minha 2>/dev/null || falhou 'o ✕ da faixa fechou a sessão em vez de só desafixar'
esperar '[[ -n $(coluna $barra "📍") ]]' 10 || falhou 'o pino da barra não voltou a 📍 depois de desafixar'
passou 'toque no ✕ da faixa desafixa (some da faixa e da lista) sem fechar a sessão'
