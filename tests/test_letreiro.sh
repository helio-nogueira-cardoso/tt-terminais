#!/usr/bin/env bash
# Letreiro fluido: o miolo da faixa é UM #() persistente por cliente (letreiro-tt.py fluxo). A barra
# rola sem redesenhar a tela inteira (nenhum set-option por passo: só a status line, ≤ 1 vez/s), cada
# cliente vê o recorte da própria largura, o aviso fresco toma a vez e devolve sozinho, e quem olha
# por uma ponte vê o letreiro parado.
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
tt() { "$TT" "$@"; }
frase='Alfa bravo charlie delta echo foxtrot golf hotel india juliett kilo lima mike november oscar papa'
mkdir -p "$HOME/.cache/tt-ticker"; printf '%s\n' "$frase" >"$HOME/.cache/tt-ticker/frases"
printf 'indicadores=frases\nticker_rolagem=continua\nticker_veloc=1\n' >>"$XDG_CONFIG_HOME/tt/config"
export TT_NOTIF_SLOT=4   # exportado ANTES do servidor: o tmux entrega o ambiente dele aos #() da barra
tmux -f "$HOME/.tmux.conf" new -d -s s -x 120 -y 30 'sleep 600' 2>/dev/null; sleep 2
grep -q 'letreiro-tt.py fluxo #{client_tty} #{client_pid}' <<<"$(tmux show -gqv @barra_notifs)" ||
  falhou "slot central não liga o letreiro por #(): $(tmux show -gqv @barra_notifs)"
palavra='bravo|charlie|delta|echo|foxtrot|golf|hotel|india|juliett|kilo|lima|mike|november'
faixa() { fora capture-pane -p -t "$1" | tail -1; }  # última linha do cliente de fora = faixa de notificações

# 1) cliente local: o letreiro aparece e desliza (continua, 1 caractere/s), com as divisórias │ │
anexar x 120 34 s; sleep 4
a=$(faixa x); grep -qE "$palavra" <<<"$a" && grep -q '│' <<<"$a" || falhou "letreiro não apareceu na faixa do cliente: [$a]"
sleep 2.2; b=$(faixa x)
[[ $a != "$b" ]] && grep -qE "$palavra" <<<"$b" || falhou "letreiro não rolou em 2 s: [$a] → [$b]"
passou 'letreiro rola na faixa do cliente local (fluxo por #(), largura do próprio terminal)'

# 2) nenhum redesenho completo em regime: só a status line muda. Medido nos bytes que o tmux manda a
#    um cliente de leitura: um redesenho da barra posiciona o cursor só nas 4 linhas dela (e o devolve
#    ao painel: 1 linha); um redesenho completo repinta as 30 linhas do painel (muitas linhas, muitos bytes).
rm -f "$T/cap.raw" "$T/cap.tm"
script -q -T "$T/cap.tm" -c "stty cols 120 rows 34; env -u TMUX timeout 7 tmux attach -t s -f read-only,ignore-size" "$T/cap.raw" >/dev/null 2>&1 </dev/null || true
python3 -I - "$T/cap.raw" "$T/cap.tm" <<'PY' || falhou 'redesenho completo (ou nenhum redesenho da barra) com o letreiro rolando'
import re, sys
raw = open(sys.argv[1], 'rb').read()
tempos = [l.split() for l in open(sys.argv[2]) if l.strip()]
cup = re.compile(rb'\x1b\[(\d+);\d+H')
t = 0.0; pos = 0; cheios = []; barra = 0; bytes_barra = []
for d, n in tempos:
    t += float(d); n = int(n); bloco = raw[pos:pos + n]; pos += n
    if t < 2.0: continue   # o attach em si redesenha tudo; depois disso, só a barra pode mudar
    linhas = {int(m.group(1)) for m in cup.finditer(bloco)}
    painel = {l for l in linhas if l < 31}
    if len(painel) >= 3 or n > 2500: cheios.append((round(t, 1), n, sorted(painel)[:8]))
    if any(l >= 31 for l in linhas): barra += 1; bytes_barra.append(n)
print(f"blocos: completos={len(cheios)} barra={barra} (média {sum(bytes_barra) // max(1, len(bytes_barra))} B) {cheios[:5]}")
sys.exit(0 if not cheios and barra >= 2 else 1)
PY
passou 'em regime, só a barra é redesenhada (zero redesenhos completos com o letreiro rolando)'

# 3) aviso fresco toma a vez no slot (negrito, range notifx) e devolve ao letreiro sozinho, sem o tt
#    gravar opção alguma por isso (o letreiro-tt.py decide lendo ~/.local/state/tt/notifs)
tt --notificar "Reunião às dez" 60 >/dev/null 2>&1; sleep 2.5
c=$(faixa x); grep -q 'Reunião às dez' <<<"$c" || falhou "aviso fresco não entrou no slot: [$c]"
grep -qE "$palavra" <<<"$c" && falhou "aviso fresco deveria esconder o letreiro: [$c]"
sleep 4; d=$(faixa x)
grep -qE "$palavra" <<<"$d" || falhou "letreiro não voltou depois do aviso (TT_NOTIF_SLOT=4): [$d]"
passou 'aviso fresco toma a vez e devolve (sem gravar opção)'

# 4) ponte (TT_PONTE= no ambiente do cliente): o letreiro fica parado — animar através da rede é
#    redesenho aninhado em outro terminal
fora new -d -s p -x 120 -y 34 "env -u TMUX TT_PONTE=teste TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t s"; sleep 4
p1=$(faixa p); sleep 2.2; p2=$(faixa p); x2=$(faixa x)
grep -qE "$palavra" <<<"$p1" || falhou "ponte sem letreiro: [$p1]"
[[ $p1 == "$p2" ]] || falhou "ponte não pode ser animada: [$p1] → [$p2]"
[[ $x2 != "$p2" ]] || falhou 'cliente local deveria estar em outro ponto do letreiro que a ponte'
passou 'ponte vê o letreiro parado; o cliente local segue rolando'

# 5) diagnóstico: tt --ticker-quadro imprime um quadro com a largura pedida
grep -qE "$palavra" <<<"$(tt --ticker-quadro 120)" || falhou 'tt --ticker-quadro não imprime o quadro'
[[ -z $(tt --ticker-quadro 70 | grep -E 'Reunião') ]] || falhou 'quadro estreito não deveria trazer aviso'
echo 'ok: letreiro fluido — #() por cliente, só a barra redesenha, aviso cede e devolve, ponte parada'
