#!/usr/bin/env bash
# Faixa de fixadas que acompanha a largura de CADA cliente, com rótulo "selo da máquina + sessão
# abreviada por palavras": clientes de larguras diferentes veem versões diferentes ao mesmo tempo,
# redimensionar redesenha, nomes abreviados nunca ficam iguais, a máquina remota vira um selo de
# uma letra (sem "maquina:" ocupando o espaço), e no estouro cada cliente vê a SUA sessão em uso.
# tmux de verdade (servidor isolado) e clientes anexados por um 2º servidor.
source "$(dirname "$0")/lib.sh"; isolar
F=$XDG_CONFIG_HOME/tt/fixadas
src=$(sed -n '/^tt_largura() {/,/^}/p; /^fixada_abrev() {/,/^}/p' "$TT")

# 1) abreviação por palavras: cabe, mantém o começo de cada palavra e o fim do nome; números inteiros
abrev() { bash -c "$src"'; fixada_abrev "$1" "$2"; printf %s "$A"' _ "$1" "$2"; }
a=$(abrev confere-maquinas-futuro 12); ((${#a} <= 12)) || falhou "abrev passou de 12: $a"
[[ $a == con*-maq*-fu* ]] || falhou "abrev deveria manter as 3 palavras pelo começo: $a"
[[ $(abrev janela-12 8) == *-12 ]] || falhou "número no fim do nome não pode ser cortado: $(abrev janela-12 8)"
[[ $(abrev asd 6) == asd ]] || falhou 'nome curto não muda'
[[ $(bash -c "$src"'; tt_largura "📋 ab"; echo $W') == 5 ]] || falhou 'largura de emoji deveria contar 2'
passou 'abreviação por palavras (cabe, preserva começo e fim, números inteiros)'

# Sessões locais e uma máquina remota cadastrada ("empresa").
printf 'empresa-host user empresa\n' >"$XDG_CONFIG_HOME/tt/maquinas"
tmux -f /dev/null new -d -s relatorio-financeiro-2025 -x 200 -y 10 'sleep 600'
tmux new -d -s relatorio-financeiro-2026 'sleep 600'
tmux new -d -s planejamento-semanal 'sleep 600'
printf 'teste\trelatorio-financeiro-2025\t\nteste\trelatorio-financeiro-2026\t\nteste\tplanejamento-semanal\t\nempresa\tconfere-maquinas-futuro\t\n' >"$F"
"$TT" --barras >/dev/null 2>&1
fmt=$(tmux show -gqv @barra_fixadas)
tmux set -g 'status-format[0]' '#{E:@barra_fixadas}'; tmux set -g status on

# 2) clientes de larguras diferentes, ao mesmo tempo, veem versões diferentes da faixa
anexar largo 200 8 relatorio-financeiro-2025; anexar estreito 64 8 planejamento-semanal
fora set -g status off >/dev/null
sleep 1.5
faixa() { fora capture-pane -p -t "$1" | sed -n '8p'; }
L=$(faixa largo); E=$(faixa estreito)
grep -q 'relatorio-financeiro-2025' <<<"$L" || falhou "cliente largo deveria ver o nome inteiro: $L"
grep -q 'relatorio-financeiro-2025' <<<"$E" && falhou "cliente estreito deveria ver o nome abreviado: $E"
[[ $L != "$E" ]] || falhou 'larguras diferentes deveriam desenhar faixas diferentes'
passou 'cada cliente desenha a versão da sua largura (largo inteiro, estreito abreviado)'

# 3) máquina remota: selo "E" e o nome da sessão; nada de "empresa:" ocupando a faixa
grep -q 'E confere-maquinas-futuro' <<<"$L" || falhou "remota deveria aparecer como 'E confere-…': $L"
grep -q 'empresa:' <<<"$L$E" && falhou 'o nome da máquina não deveria ocupar a faixa'
passou 'máquina remota vira selo de uma letra; o espaço fica para o conteúdo'

# 4) abreviados nunca iguais: 2025 e 2026 continuam distinguíveis mesmo apertado
r25=$(grep -o '[^ ]*2025' <<<"$E" | head -1 || true); r26=$(grep -o '[^ ]*2026' <<<"$E" | head -1 || true)
[[ -n $r25 && -n $r26 && $r25 != "$r26" ]] || falhou "abreviados de 2025/2026 deveriam diferir e manter o ano: $E"
passou "nomes parecidos continuam distintos quando abreviados ($r25 / $r26)"

# 5) redimensionar o cliente redesenha na hora (sem recalcular nada no tt)
fora resize-window -t largo -x 64 -y 8 >/dev/null 2>&1; sleep 1.2
grep -q 'relatorio-financeiro-2025' <<<"$(faixa largo)" && falhou "depois de estreitar, o cliente ainda mostra o nome inteiro: $(faixa largo)"
fora resize-window -t largo -x 200 -y 8 >/dev/null 2>&1; sleep 1.2
grep -q 'relatorio-financeiro-2025' <<<"$(faixa largo)" || falhou "depois de alargar, o nome inteiro deveria voltar: $(faixa largo)"
passou 'redimensionar a janela redesenha a faixa na hora'

# 6) estouro: cada cliente vê a SUA sessão em uso, mesmo se ela estaria escondida
for n in 1 2 3 4 5 6 7 8; do tmux new -d -s "extra-sessao-$n" 'sleep 600'; printf 'teste\textra-sessao-%s\t\n' "$n" >>"$F"; done
"$TT" --barras >/dev/null 2>&1; tmux set -g status on; tmux set -g 'status-format[0]' '#{E:@barra_fixadas}'
anexar curto 46 8 extra-sessao-8; fora set -g status off >/dev/null; sleep 1.5
C=$(faixa curto)
grep -q '+[0-9]* ▾' <<<"$C" || falhou "46 colunas com 12 fixadas deveria ter o chip +N: $C"
grep -q 'ex[^ ]*8 ' <<<"$C" || falhou "a sessão em uso do cliente (extra-sessao-8) deveria estar visível: $C"
fora resize-window -t estreito -x 46 -y 8 >/dev/null 2>&1; sleep 1.2
grep -q 'ex[^ ]*8 ' <<<"$(faixa estreito)" && falhou "cliente em outra sessão não deveria ver extra-sessao-8 no lugar: $(faixa estreito)"
grep -q 'pl[a-z-]*' <<<"$(faixa estreito)" || falhou "cliente estreito deveria ver a sua (planejamento-semanal): $(faixa estreito)"
passou 'no estouro, cada cliente vê a sua sessão em uso'

# 7) o popup (lista completa) mostra o nome inteiro e a máquina por extenso
l=$("$TT" --fixadas-ui-lista | sed 's/\x1b\[[0-9;]*m//g')
grep -q '📌 E confere-maquinas-futuro  · empresa' <<<"$l" || falhou "popup deveria ter 'E sessão · máquina' por extenso: $l"
grep -q '📌 relatorio-financeiro-2025' <<<"$l" || falhou 'popup deveria ter o nome inteiro das locais'
passou 'popup das fixadas: nome inteiro e máquina por extenso, com o mesmo selo'
echo "ok: faixa por largura de cliente (formato com $(printf %s "$fmt" | wc -c) bytes)"
