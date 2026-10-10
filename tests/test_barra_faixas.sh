#!/usr/bin/env bash
# A barra por fora: 4 linhas coladas — margem, janelas, fixadas e faixa —, sem réguas: o que separa as
# faixas é só o fundo levemente diferente. As fixadas e a faixa são pintadas em toda a largura, em qualquer
# largura e mesmo com muitas janelas, e o aviso do tmux (display-message) cai só na margem (linha 0), sem
# cobrir faixa nenhuma. Mede célula a célula o que o tmux manda a um cliente real (script + leitura de SGR).
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
mkdir -p "$HOME/.cache/tt-ticker"; printf '%s\n' 'Alfa bravo charlie delta echo foxtrot golf hotel india juliett kilo lima mike november oscar papa' >"$HOME/.cache/tt-ticker/frases"
printf 'indicadores=frases\n' >>"$XDG_CONFIG_HOME/tt/config"
tmux -f "$HOME/.tmux.conf" new -d -s s -x 160 -y 40 'sleep 600' 2>/dev/null
for i in 1 2 3 4 5 6; do tmux new-window -d -n "janela-comprida-numero-$i" 'sleep 600'; done
tt() { "$TT" "$@"; }
tt --barras >/dev/null 2>&1; sleep 2
[[ $(tmux show -gqv status) == 4 ]] || falhou "faixa ligada deveria pôr status=4 (está $(tmux show -gqv status))"
[[ $(tmux show -gqv message-line) == 0 ]] || falhou 'os avisos do tmux deveriam cair na linha 0 (a margem vazia)'

medir() { # largura termo [mensagem] -> "linha:glifos▁:glifos▔:fundos distintos:texto" das 5 linhas da barra
  local W=$1 term=$2 msg=${3:-}
  rm -f "$T/r.raw"
  script -q -c "stty cols $W rows 40; env -u TMUX TERM=$term timeout 5 tmux attach -t s -f ignore-size" "$T/r.raw" >/dev/null 2>&1 </dev/null &
  if [[ -n $msg ]]; then sleep 2; tmux display-message -c "$(tmux list-clients -F '#{client_name}' | head -1)" -d 20000 "$msg"; fi
  wait
  python3 -I - "$T/r.raw" "$W" <<'PY'
import re, sys, unicodedata
raw = open(sys.argv[1], 'rb').read().decode('utf8', 'replace').split('\x1b[?1l\x1b>')[0]
W, H = int(sys.argv[2]), 40
bg = [[None] * W for _ in range(H)]; ch = [[' '] * W for _ in range(H)]
r = c = 0; cur = None
tok = re.compile(r'\x1b\[([0-9;:?]*)([A-Za-z@])|\x1b[\(\)][0-9A-B]|\x1b[=>78M]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|(.)', re.S)
def sgr(p):
    global cur
    a = [int(x) if x else 0 for x in p.replace(':', ';').split(';')] if p else [0]
    i = 0
    while i < len(a):
        x = a[i]
        if x in (0, 49): cur = None
        elif 40 <= x <= 47: cur = ('c', x - 40)
        elif x == 48:
            if a[i + 1] == 2: cur = ('t', tuple(a[i + 2:i + 5])); i += 4
            else: cur = ('c', a[i + 2]); i += 2
        i += 1
for m in tok.finditer(raw):
    p, f, t = m.groups()
    if f:
        if f == 'm': sgr(p)
        elif f in 'Hf':
            q = (p or '1;1').split(';'); r = int(q[0] or 1) - 1; c = int((q + ['1'])[1] or 1) - 1
        elif f == 'd': r = max(0, int(p or 1) - 1)   # VPA: o tmux 3.5a posiciona o aviso assim (o 3.6 usa CUP)
        elif f == 'G': c = max(0, int(p or 1) - 1)   # CHA
        elif f == 'K':
            for x in range(c, W): bg[r][x] = cur; ch[r][x] = ' '
        elif f == 'J' and p in ('2', '3'):
            bg = [[None] * W for _ in range(H)]; ch = [[' '] * W for _ in range(H)]
    elif t:
        if t == '\r': c = 0
        elif t == '\n': r = min(H - 1, r + 1)
        elif t >= ' ' and r < H and c < W:
            w = 2 if unicodedata.east_asian_width(t) in 'WF' else (0 if unicodedata.combining(t) or t in '\ufe0f\u200d' else 1)
            if w == 0: continue
            bg[r][c] = cur; ch[r][c] = t
            if w == 2 and c + 1 < W: bg[r][c + 1] = cur; ch[r][c + 1] = '\0'
            c += w
out = []
for y in range(36, 40):
    texto = ''.join(x for x in ch[y] if x != '\0')
    fundo_ok = sum(1 for b in bg[y] if b is not None)
    out.append('%d:%d:%d:%d:%s' % (y - 36, texto.count('\u2581'), texto.count('\u2594'), fundo_ok, texto.strip()[:14].replace(' ', '_') or '-'))
print(' '.join(out))
PY
}
for W in 160 100 72; do
  s=$(medir $W xterm-256color)
  read -r l0 l1 l2 l3 <<<"$s"
  for n in 2 3; do eval "l=\$l$n"; f=$(cut -d: -f4 <<<"$l"); ((f >= W - 1)) || falhou "linha $n não está pintada de ponta a ponta ($f de $W) a $W colunas: $s"; done
  grep -q '[^_:0-9-]' <<<"$(cut -d: -f5 <<<"$l0")" && falhou "a margem (linha 0) deveria estar vazia a $W colunas: $s"
  [[ $(cut -d: -f2 <<<"$l0")$(cut -d: -f3 <<<"$l0")$(cut -d: -f2 <<<"$l1")$(cut -d: -f3 <<<"$l1") == 0000 ]] || falhou "não pode haver régua (▁ ▔) na barra a $W colunas: $s"
done
passou 'fixadas e faixa pintadas de ponta a ponta a 160/100/72 colunas, sem réguas'

s=$(medir 160 xterm-256color 'AVISO DO TMUX QUE NAO PODE COBRIR FAIXA')
read -r l0 l1 l2 l3 <<<"$s"
grep -q 'AVISO' <<<"$l0" || falhou "o aviso do tmux deveria cair na linha 0 (a margem vazia): $s"
grep -q 'AVISO' <<<"$l1$l2$l3" && falhou "o aviso do tmux cobriu uma faixa: $s"
passou 'display-message cai só na margem do topo; as faixas ficam intactas'
echo 'ok: barra por fora — faixas coladas e preenchidas, sem réguas, avisos fora das faixas'
