#!/usr/bin/env bash
# A barra por fora: 4 linhas coladas (margem, janelas, fixadas, faixa), com a régua fina (sublinhado
# colorido us=) rente ao rodapé de cada uma das três primeiras — em toda a largura, em qualquer largura,
# mesmo com muitas janelas —, a faixa preenchida de ponta a ponta, o aviso do tmux (display-message) só na
# margem do topo (sem cobrir faixa) e nenhuma régua em terminal sem usstyle. Mede célula a célula o que o
# tmux manda a um cliente real (script + leitura de SGR), não o texto das opções.
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
mkdir -p "$HOME/.cache/tt-ticker"; printf '%s\n' 'Alfa bravo charlie delta echo foxtrot golf hotel india juliett kilo lima mike november oscar papa' >"$HOME/.cache/tt-ticker/frases"
printf 'indicadores=frases\n' >>"$XDG_CONFIG_HOME/tt/config"
tmux -f "$HOME/.tmux.conf" new -d -s s -x 160 -y 40 'sleep 600' 2>/dev/null
for i in 1 2 3 4 5 6; do tmux new-window -d -n "janela-comprida-numero-$i" 'sleep 600'; done
tt() { "$TT" "$@"; }
tt --barras >/dev/null 2>&1; sleep 2
[[ $(tmux show -gqv status) == 4 ]] || falhou "faixa ligada deveria pôr status=4 (está $(tmux show -gqv status))"
[[ $(tmux show -gqv message-line) == 0 ]] || falhou 'os avisos do tmux deveriam cair na linha 0 (a margem vazia)'

medir() { # largura termo [mensagem] -> imprime "linha:sublinhadas:fundo_ok ..." das 4 linhas da barra
  local W=$1 term=$2 msg=${3:-}
  rm -f "$T/r.raw"
  script -q -c "stty cols $W rows 40; env -u TMUX TERM=$term timeout 5 tmux attach -t s -f ignore-size" "$T/r.raw" >/dev/null 2>&1 </dev/null &
  if [[ -n $msg ]]; then sleep 2; tmux display-message -c "$(tmux list-clients -F '#{client_name}' | head -1)" -d 20000 "$msg"; fi
  wait
  python3 -I - "$T/r.raw" "$W" <<'PY'
import re, sys, unicodedata
raw = open(sys.argv[1], 'rb').read().decode('utf8', 'replace').split('\x1b[?1l\x1b>')[0]
W, H = int(sys.argv[2]), 40
bg = [[None] * W for _ in range(H)]; ul = [[0] * W for _ in range(H)]; ch = [[' '] * W for _ in range(H)]
r = c = 0; cur = None; u = 0
tok = re.compile(r'\x1b\[([0-9;:?]*)([A-Za-z@])|\x1b[\(\)][0-9A-B]|\x1b[=>78M]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|(.)', re.S)
def sgr(p):
    global cur, u
    a = [int(x) if x else 0 for x in p.replace(':', ';').split(';')] if p else [0]
    i = 0
    while i < len(a):
        x = a[i]
        if x == 0: cur = None; u = 0
        elif x == 49: cur = None
        elif x == 4: u = 1
        elif x == 24: u = 0
        elif 40 <= x <= 47: cur = ('c', x - 40)
        elif x == 48:
            if a[i + 1] == 2: cur = ('t', tuple(a[i + 2:i + 5])); i += 4
            else: cur = ('c', a[i + 2]); i += 2
        elif x == 58:  # cor do sublinhado: consome os parâmetros
            i += 4 if a[i + 1] == 2 else 2
        i += 1
for m in tok.finditer(raw):
    p, f, t = m.groups()
    if f:
        if f == 'm': sgr(p)
        elif f in 'Hf':
            q = (p or '1;1').split(';'); r = int(q[0] or 1) - 1; c = int((q + ['1'])[1] or 1) - 1
        elif f == 'K':
            for x in range(c, W): bg[r][x] = cur; ul[r][x] = 0; ch[r][x] = ' '
        elif f == 'J' and p in ('2', '3'):
            bg = [[None] * W for _ in range(H)]; ul = [[0] * W for _ in range(H)]; ch = [[' '] * W for _ in range(H)]
    elif t:
        if t == '\r': c = 0
        elif t == '\n': r = min(H - 1, r + 1)
        elif t >= ' ' and r < H and c < W:
            w = 2 if unicodedata.east_asian_width(t) in 'WF' else (0 if unicodedata.combining(t) or t in '️‍' else 1)
            if w == 0: continue
            bg[r][c] = cur; ul[r][c] = u; ch[r][c] = t
            if w == 2 and c + 1 < W: bg[r][c + 1] = cur; ul[r][c + 1] = u; ch[r][c + 1] = '\0'
            c += w
out = []
for y in range(36, 40):
    texto = ''.join(x for x in ch[y] if x != '\0').strip()
    out.append('%d:%d:%s:%s' % (y - 36, sum(ul[y]), len({b for b in bg[y] if b}) , texto[:18].replace(' ', '_') or '-'))
print(' '.join(out))
PY
}
for W in 160 100 72; do
  s=$(medir $W xterm-256color)
  read -r l0 l1 l2 l3 <<<"$s"
  for n in 0 1 2; do
    eval "l=\$l$n"; u=$(cut -d: -f2 <<<"$l")
    ((u >= W - 1)) || falhou "linha $n sem a régua de sublinhado em toda a largura ($u de $W) a $W colunas: $s"
  done
  u3=$(cut -d: -f2 <<<"$l3")
  ((u3 == 0)) || falhou "a faixa (última linha) não leva régua embaixo ($u3 células sublinhadas) a $W colunas: $s"
done
passou 'réguas finas (sublinhado) em cima da 1ª faixa e entre as faixas, em toda a largura, a 160/100/72 colunas'

s=$(medir 100 linux)
read -r l0 l1 l2 l3 <<<"$s"
for l in $l0 $l1 $l2; do ((10#$(cut -d: -f2 <<<"$l") == 0)) || falhou "terminal sem usstyle não pode ganhar sublinhado do texto: $s"; done
passou 'terminal sem cor de sublinhado: a régua some em vez de sublinhar o texto'

s=$(medir 160 xterm-256color 'AVISO DO TMUX QUE NAO PODE COBRIR FAIXA')
read -r l0 l1 l2 l3 <<<"$s"
grep -q 'AVISO' <<<"$l0" || falhou "o aviso do tmux deveria cair na margem do topo: $s"
grep -q 'AVISO' <<<"$l1$l2$l3" && falhou "o aviso do tmux cobriu uma faixa: $s"
passou 'display-message cai só na margem vazia do topo; as três faixas ficam intactas'
echo 'ok: barra por fora — réguas de sublinhado, linhas coladas e avisos fora das faixas'
