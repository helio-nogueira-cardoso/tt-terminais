#!/usr/bin/env bash
# O que ficou mais rápido continua dando o mesmo resultado (isolado; tmux de verdade num servidor próprio):
#  1) tem_cmd responde como o command -v: as pastas do Linux, funções e builtins são conferidas sempre; só a
#     resposta das pastas do Windows (no WSL) fica guardada, por TT_CMD_WIN_VALE s.
#  2) a chave das fixadas guardada (fixada_chave_em) é o sha256 de sempre, e lixo no arquivo dela não engana.
#  3) atualizar_barras grava tudo o que mudou numa ida só ao tmux (um redesenho), e nada quando nada mudou.
#  4) os pedidos da barra em 2º plano (painel de tarefas) se juntam e terminam no estado final, sem trava presa.
#  5) vários `tt --bordas gancho` juntos deixam a barrinha dos painéis certa.
#  6) clique num painel sem link chega ao programa sem rodar o python dos links; com link na tela, passa por ele.
source "$(dirname "$0")/lib.sh"; isolar
set +o pipefail

# --- 1) tem_cmd ----------------------------------------------------------------------------------------
src_tem=$(sed -n '/^declare -A _TEM_CMD=()/,/^}/p' "$TT")
grep -q '^tem_cmd() {' <<<"$src_tem" || falhou 'tem_cmd não encontrado no tt'
W=$T/win; mkdir -p "$W/c/bin" "$T/linbin"
tc() { # nome… → "0 1 …", cada nome perguntado num processo novo (como cada clique)
  env WSL_DISTRO_NAME=teste TT_CMD_WIN_RAIZ="$W" RT="$TT_RT" PATH="$T/linbin:$PATH:$W/c/bin" bash -c "$src_tem"'
    for c in "$@"; do tem_cmd "$c"; printf "%s " $?; done' _ "$@"
}
[[ $(tc bash printf nao-existe-tt-xyz) == "0 0 1 " ]] || falhou "tem_cmd deveria achar bash e printf e não achar o ausente: '$(tc bash printf nao-existe-tt-xyz)'"
[[ $(bash -c "$src_tem"'; minha_funcao() { :; }; tem_cmd minha_funcao; echo $?') == 0 ]] || falhou 'tem_cmd deveria achar uma função, como o command -v'
[[ $(tc win-tt-cmd) == "1 " ]] || falhou 'comando ausente deveria responder 1'
printf '#!/bin/sh\n' >"$W/c/bin/win-tt-cmd"; chmod +x "$W/c/bin/win-tt-cmd"
[[ $(tc win-tt-cmd) == "1 " ]] || falhou 'a resposta das pastas do Windows deveria ficar guardada (TT_CMD_WIN_VALE)'
[[ $(TT_CMD_WIN_VALE=0 tc win-tt-cmd) == "0 " ]] || falhou 'vencido o prazo, o que apareceu nas pastas do Windows deveria ser achado'
[[ $(tc lin-tt-cmd) == "1 " ]] || falhou 'ausente no Linux deveria responder 1'
printf '#!/bin/sh\n' >"$T/linbin/lin-tt-cmd"; chmod +x "$T/linbin/lin-tt-cmd"
[[ $(tc lin-tt-cmd) == "0 " ]] || falhou 'o que aparece numa pasta do Linux deveria ser achado na hora (sem esperar o prazo)'
rm -f "$T/linbin/lin-tt-cmd"
[[ $(tc lin-tt-cmd) == "1 " ]] || falhou 'o que some de uma pasta do Linux deveria deixar de ser achado na hora'
passou 'tem_cmd = command -v (Linux conferido sempre; pastas do Windows guardadas pelo prazo)'

# --- 2) chave das fixadas ------------------------------------------------------------------------------
src_fx=$(sed -n '/^fixada_chave() {/p; /^declare -A _FX_CHAVE=()/,/^}/p' "$TT")
ref() { printf '%s\t%s' "$1" "$2" | sha256sum | cut -c1-12; }
fk() { RT="$TT_RT" bash -c "$src_fx"'; fixada_chave "$@"' _ "$@"; }
for i in 1 2; do # 2ª vez: a resposta vem do arquivo guardado
  [[ $(fk empresa sessao-x abc123) == "$(ref empresa abc123)" ]] || falhou "chave com id difere do sha256 (volta $i)"
  [[ $(fk empresa 'sessão com espaço') == "$(ref empresa 'sessão com espaço')" ]] || falhou "chave sem id (usa a sessão) difere do sha256 (volta $i)"
done
[[ -s $TT_RT/tt-fixadas-chaves-$(id -u) ]] || falhou 'a chave calculada deveria ficar guardada'
printf 'lixo\nempresa\toutra\tdeadbe\nempresa\n\n' >>"$TT_RT/tt-fixadas-chaves-$(id -u)"
[[ $(fk empresa outra) == "$(ref empresa outra)" ]] || falhou 'linha truncada no arquivo das chaves não pode virar chave'
passou 'chave das fixadas guardada = sha256 de sempre (e lixo no arquivo é ignorado)'

# --- 3) atualizar_barras numa ida só --------------------------------------------------------------------
REAL=$(command -v tmux); mkdir -p "$T/tmuxlog"; LOGT=$T/tmux.log
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>%q\nexec %q "$@"\n' "$LOGT" "$REAL" >"$T/tmuxlog/tmux"; chmod +x "$T/tmuxlog/tmux"
tmux -f /dev/null new -d -s base -x 120 -y 30 'sleep 600'
tmux new -d -s outra 'sleep 600'
tl() { PATH="$T/tmuxlog:$PATH" "$TT" "$@"; }
tl --barras >/dev/null 2>&1
tl --fixar outra >/dev/null 2>&1
tl --tarefa-add 'tarefa de teste do desempenho' >/dev/null 2>&1
# Quatro segmentos apagados à mão: a volta seguinte regrava os quatro, numa ida só.
tmux set -gu @barra_tarefas \; set -gu @barra_fixadas \; set -gu @barra_versao \; set -gu @barra_faixa
: >"$LOGT"; tl --barras >/dev/null 2>&1
n_set=$(grep -c 'set -g @barra_' "$LOGT" || true)
[[ $n_set == 1 ]] || falhou "atualizar_barras deveria gravar numa ida só ao tmux; foram $n_set: $(grep 'set -g @barra_' "$LOGT" | cut -c1-120)"
for o in tarefas fixadas versao faixa; do grep 'set -g @barra_' "$LOGT" | grep -q "@barra_$o " || falhou "a ida única deveria regravar @barra_$o"; done
: >"$LOGT"; tl --barras >/dev/null 2>&1
grep -q 'set -g @barra_' "$LOGT" && falhou "sem mudança, atualizar_barras não deveria gravar nada: $(grep 'set -g @barra_' "$LOGT" | cut -c1-160)"
grep -q 'outra' <<<"$(tmux show -gqv @fx0_1)$(tmux show -gqv @fx0_2)" || falhou "a faixa das fixadas deveria mostrar a sessão fixada: $(tmux show -gqv @fx0_1)"
grep -q '📋 1 ' <<<"$(tmux show -gqv @barra_tarefas)" || falhou "o 📋 deveria contar a tarefa aberta: $(tmux show -gqv @barra_tarefas)"
[[ $(tmux show -gqv status) == 4 ]] || falhou "com a faixa ligada a barra tem 4 linhas (está $(tmux show -gqv status))"
passou 'atualizar_barras: o que mudou vai numa ida só ao tmux; nada mudou, nada gravado; valores certos'

# --- 4) barra em 2º plano (painel de tarefas) ----------------------------------------------------------
for i in 1 2 3; do TT_BARRA_FUNDO=1 "$TT" --tarefa-add "fundo $i" >/dev/null 2>&1; done
ok=0; for ((i = 0; i < 40; i++)); do grep -q '📋 4 ' <<<"$(tmux show -gqv @barra_tarefas)" && { ok=1; break; }; sleep 0.25; done
((ok)) || falhou "pedidos seguidos em 2º plano deveriam terminar no estado final (📋 4): $(tmux show -gqv @barra_tarefas)"
for ((i = 0; i < 40; i++)); do [[ -e $TT_RT/tt-barras-$(id -u).trava || -e $TT_RT/tt-barras-$(id -u).pedido ]] || break; sleep 0.1; done
[[ -e $TT_RT/tt-barras-$(id -u).trava ]] && falhou 'a volta em 2º plano deixou a trava presa'
passou 'barra em 2º plano: pedidos seguidos se juntam e terminam no estado final, sem trava presa'

# --- 5) --bordas gancho em rajada ------------------------------------------------------------------------
w=$(tmux display -p -t =base: '#{window_id}')
bs() { tmux display-message -p -t "$w" '#{pane-border-status}'; }
tmux split-window -d -t =base: 'sleep 600'
for i in 1 2 3 4; do "$TT" --bordas gancho & done; wait
[[ $(bs) == top ]] || falhou "rajada de ganchos com 2 painéis divididos deveria ligar a barrinha (está $(bs))"
tmux kill-pane -t "$(tmux list-panes -t "$w" -F '#{pane_id}' | tail -1)"
for i in 1 2 3 4; do "$TT" --bordas gancho & done; wait
[[ $(bs) == off ]] || falhou "rajada de ganchos com 1 painel deveria desligar a barrinha (está $(bs))"
[[ -e $TT_RT/tt-bordas-$(id -u).pend ]] && falhou 'a rajada de ganchos deixou a marca presa'
passou '--bordas gancho em rajada deixa a barrinha certa (e não deixa marca)'

# --- 6) clique no painel: sem link, direto ao programa ---------------------------------------------------
instalar_isolado
PY=$(command -v python3); mkdir -p "$T/pylog"; LOGP=$T/python.log; : >"$LOGP"
printf '#!/bin/sh\necho "$*" >>%q\nexec %q "$@"\n' "$LOGP" "$PY" >"$T/pylog/python3"; chmod +x "$T/pylog/python3"
cat >"$T/rato.sh" <<'R'
printf '\033[?1000h\033[?1006h\033[2J\033[H'
[ -n "$1" ] && printf '%s\n' "$1"
printf 'texto qualquer\n'
stty -echo -icanon min 1 2>/dev/null
n=0; while IFS= read -r -s -n1 c; do [ "$c" = M ] && { n=$((n+1)); printf '\033[8;1HEVENTO-%d   ' "$n"; }; done
R
tmux kill-server 2>/dev/null; sleep 0.3
PATH="$T/pylog:$PATH" tmux -f "$HOME/.tmux.conf" new -d -s semlink -x 100 -y 30 "bash --norc $T/rato.sh ''"
PATH="$T/pylog:$PATH" tmux new -d -s comlink -x 100 -y 30 "bash --norc $T/rato.sh 'veja https://example.com/caminho aqui'"
anexar cli 100 32 semlink; sleep 3
clicar() { fora send -t cli -l $'\e[<0;'"$1;$2"$'M'; sleep 0.05; fora send -t cli -l $'\e[<0;'"$1;$2"$'m'; }
evento() { local i; for ((i = 0; i < 40; i++)); do fora capture-pane -p -t cli | grep -qE "EVENTO-$1( |$)" && return 0; sleep 0.25; done; return 1; }
: >"$LOGP"; clicar 5 4
evento 1 || falhou "clique num painel sem link não chegou ao programa: $(fora capture-pane -p -t cli | head -9)"
grep -q 'links-tt.py clique' "$LOGP" && falhou "sem link na tela, o python dos links não deveria rodar: $(cat "$LOGP")"
tmux switch-client -c "$(tmux list-clients -F '#{client_name}' | head -1)" -t comlink; sleep 1
: >"$LOGP"; clicar 5 4
evento 1 || falhou "clique fora do link (com link na tela) não chegou ao programa: $(fora capture-pane -p -t cli | head -9)"
grep -q 'links-tt.py clique' "$LOGP" || falhou 'com link na tela, o clique deveria passar pelo links-tt.py'
passou 'clique no painel: sem link vai direto ao programa (sem python); com link na tela, passa pelo links-tt.py'

echo "TODOS OS TESTES PASSARAM"
