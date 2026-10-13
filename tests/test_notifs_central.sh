#!/usr/bin/env bash
# tt-teste: sozinho (fzf de verdade com cliques e teclas: roda sem outros testes disputando a máquina)
# Central de notificações (o 🔔): abas de filtro e barra de botões no cabeçalho, como as do e-mail e do
# painel de tarefas. Cobre: o cabeçalho nunca passa da largura (encolhe em degraus: rótulo curto, ícone;
# as abas de origem viram 🤖 📧 📋) e o mapa de cliques cobre exatamente cada rótulo; o despachante
# único (notifs_acao) de teclas, cliques e botões — filtros, Tab, lida ⇄ não lida, ler todas, apagar,
# limpar as lidas com confirmação, abrir com e sem destino; e o fzf de verdade num tmux isolado,
# com cliques de mouse no cabeçalho e as teclas.
source "$(dirname "$0")/lib.sh"
isolar

ND=$HOME/.local/state/tt/notifs
UI=$TT_RT/tt-notifs-ui-$UID
MAPA=$TT_RT/tt-notifs-mapa-$UID
sem_cor() { sed 's/\x1b\[[0-9;]*m//g'; }
# Largura de exibição de cada linha (emoji = 2), como o fzf conta.
larguras() { python3 -c '
import sys, unicodedata
for l in sys.stdin.read().split("\n"):
    print(sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in l))'; }
# Texto das colunas INI..FIM (de exibição, 1 = 1ª) da linha L do cabeçalho.
fatia() { python3 -c '
import sys, unicodedata
txt, l, i, f = sys.stdin.read().split("\n"), int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
cel = []
for c in txt[l - 1]:
    cel.append(c)
    if unicodedata.east_asian_width(c) in "WF": cel.append("")
print("".join(cel[i - 1:f]))' "$@"; }

aviso() { # id texto ação [canal] [lida]
  printf '%s\t%s\t%s\t%s\n' 9999999999 "$2" "${3:--}" "${4:-}" >"$ND/$1"
  [[ -n ${5:-} ]] && : >"$ND/$1.lida"
  return 0
}
mkdir -p "$ND"
aviso 1791000000000000001 '📧 Conta: e-mail novo de Ana' 'email:conta'
aviso 1791000000000000002 '📋 Pagar aluguel · vence hoje' tarefas '' lida
aviso 1791000000000000003 '🤖 sessao-x · terminei a rodada' 'sessao:teste|sessao-x|%3' sino
aviso 1791000000000000004 '🤖 sem destino · olhe o log' - sino
aviso 1791000000000000005 '📰 Novidades do tt' novidades

acao() { "$TT" --notifs-acao "$@"; }
get() { sed -n "s/^$1=//p" "$UI" | tail -1; }
lista_de() { # a saída do despachante → o conteúdo da lista que ele mandou recarregar
  local f; f=$(sed -n "s/.*reload-sync(cat '\([^']*\)'.*/\1/p" <<<"$1")
  [[ -n $f && -f $f ]] && sem_cor <"$f"
}
cab_de() {
  local f; f=$(sed -n "s/.*transform-header(cat '\([^']*\)'.*/\1/p" <<<"$1")
  [[ -n $f && -f $f ]] && sem_cor <"$f"
}

# 1) cabeçalho largo: abas com contagem, origens só com avisos, botões com rótulo inteiro; o mapa
#    cobre exatamente cada rótulo e nada passa da largura
printf 'filtro=todas\nmodo=lista\n' >"$UI"
cab=$(FZF_COLUMNS=92 "$TT" --notifs-cabecalho | sem_cor)
l1=$(sed -n 1p <<<"$cab"); l2=$(sed -n 2p <<<"$cab")
[[ $l1 == *'Todas 5'*'Não lidas 4'*'Lidas 1'*'Agentes 2'*'E-mail 1'*'Tarefas 1'* ]] || falhou "abas largas: $l1"
[[ $l2 == *'↗ Abrir'*'◐ Lida/não lida'*'✓ Ler todas'*'✕ Apagar'*'🧹 Limpar lidas'* ]] || falhou "botões largos: $l2"
while read -r l w; do ((w <= 89)) || falhou "linha $l do cabeçalho passa da largura (92-3): $w"; done < <(larguras <<<"$cab" | nl -ba)
declare -A esperado=([filtro:todas]=' Todas 5 ' [filtro:naolidas]=' Não lidas 4 ' [filtro:lidas]=' Lidas 1 '
  [filtro:agentes]=' Agentes 2 ' [filtro:email]=' E-mail 1 ' [filtro:tarefas]=' Tarefas 1 ' [abrir]=' ↗ Abrir '
  [lida]=' ◐ Lida/não lida ' [todas_lidas]=' ✓ Ler todas ' [apagar]=' ✕ Apagar ' [limpar]=' 🧹 Limpar lidas ')
n=0
while read -r l i f a; do
  [[ -n ${a:-} ]] || continue
  [[ -n ${esperado[$a]:-} ]] || falhou "ação inesperada no mapa: $a"
  got=$(fatia "$l" "$i" "$f" <<<"$cab")
  [[ $got == "${esperado[$a]}" ]] || falhou "mapa de $a (linha $l, $i–$f) cobre «$got», esperado «${esperado[$a]}»"
  n=$((n + 1))
done <"$MAPA"
((n == ${#esperado[@]})) || falhou "mapa deveria ter ${#esperado[@]} itens clicáveis, tem $n"
passou 'cabeçalho largo: abas e botões com rótulo, mapa exato, dentro da largura'

# 2) degraus: celular (63) rótulos curtos e origens em ícone, numa linha cada; estreito, só ícones;
#    nunca passa da largura, em nenhuma largura
cab=$(FZF_COLUMNS=61 "$TT" --notifs-cabecalho | sem_cor)
[[ $(sed -n 1p <<<"$cab") == *'Todas 5'*'Não lidas 4'*'Lidas 1'*'🤖 2'*'📧 1'*'📋 1'* ]] || falhou "abas no celular: $cab"
[[ $(sed -n 2p <<<"$cab") == *'↗ Abrir'*'◐ Lida '*'✓ Ler todas'*'✕ Apagar'*'🧹 Limpar '* && $(sed -n 2p <<<"$cab") != *'não lida'* ]] || falhou "botões curtos no celular: $cab"
cab=$(FZF_COLUMNS=45 "$TT" --notifs-cabecalho | sem_cor)
grep -qx ' ↗   ◐   ✓   ✕   🧹 ' <<<"$cab" || falhou "tela estreita deveria ter só os ícones: $cab"
for c in 30 40 50 61 70 80 92 120; do
  cab=$(FZF_COLUMNS=$c "$TT" --notifs-cabecalho | sem_cor)
  while read -r w; do ((w <= c - 3)) || falhou "cabeçalho com $c colunas tem linha de $w (passa de $((c - 3)))"; done < <(larguras <<<"$cab")
  while read -r l i f a; do
    [[ -n ${a:-} ]] || continue
    got=$(fatia "$l" "$i" "$f" <<<"$cab")
    [[ $got == ' '*' ' && $got != '  '* ]] || falhou "com $c colunas, $a cobre «$got» (deveria ser o rótulo inteiro)"
  done <"$MAPA"
done
passou 'cabeçalho encolhe em degraus e nunca vaza da janela'

# 3) filtros: botão/clique, ^u/^a e Tab passam pelo mesmo despachante e recarregam a lista
out=$(acao filtro:naolidas '')
[[ $(get filtro) == naolidas ]] || falhou "filtro não gravado: $(cat "$UI")"
[[ $out == *reload-sync*+first*transform-header* ]] || falhou "filtro deveria recarregar a lista, ir ao topo e trocar o cabeçalho: $out"
l=$(lista_de "$out")
[[ $l == *'Ana'* && $l != *'aluguel'* ]] || falhou "Não lidas mostrou o que não devia: $l"
l=$(lista_de "$(acao filtro:lidas '')"); [[ $l == *'aluguel'* && $l != *'Ana'* ]] || falhou "Lidas: $l"
l=$(lista_de "$(acao filtro:agentes '')"); [[ $l == *'sessao-x'* && $l == *'sem destino'* && $l != *'Ana'* ]] || falhou "Agentes: $l"
l=$(lista_de "$(acao filtro:email '')"); [[ $l == *'Ana'* && $l != *'sessao-x'* ]] || falhou "E-mail: $l"
l=$(lista_de "$(acao filtro:tarefas '')"); [[ $l == *'aluguel'* && $l != *'Ana'* ]] || falhou "Tarefas: $l"
acao filtro:todas '' >/dev/null
seq=""; for _ in 1 2 3 4 5 6 7; do acao proximo '' >/dev/null; seq+="$(get filtro) "; done
[[ $seq == 'naolidas lidas agentes email tarefas todas naolidas ' ]] || falhou "Tab deveria percorrer as abas visíveis: $seq"
acao anterior '' >/dev/null; [[ $(get filtro) == todas ]] || falhou "Shift+Tab volta uma aba: $(get filtro)"
# clique no cabeçalho: a coluna clicada acha a aba pelo mapa
FZF_COLUMNS=92 "$TT" --notifs-cabecalho >/dev/null
read -r _ i _ _ < <(grep ' filtro:lidas$' "$MAPA")
FZF_CLICK_HEADER_LINE=1 FZF_CLICK_HEADER_COLUMN=$i acao cabecalho '' >/dev/null
[[ $(get filtro) == lidas ]] || falhou "clique na aba Lidas: $(get filtro)"
[[ $(FZF_CLICK_HEADER_LINE=1 FZF_CLICK_HEADER_COLUMN=$((i - 1)) acao cabecalho '') == ignore ]] || falhou 'clique entre as abas não deveria fazer nada'
acao filtro:todas '' >/dev/null
passou 'filtros por botão, clique, teclas e Tab'

# 4) lida ⇄ não lida, ler todas, apagar
acao lida 1791000000000000001 >/dev/null; [[ -f $ND/1791000000000000001.lida ]] || falhou '◐ deveria marcar como lida'
acao lida 1791000000000000001 >/dev/null; [[ ! -f $ND/1791000000000000001.lida ]] || falhou '◐ de novo deveria voltar a não lida'
[[ $(acao lida '') == ignore ]] || falhou '◐ sem aviso em foco (lista vazia) não faz nada'
out=$(acao todas_lidas ''); [[ $(ls "$ND" | grep -c '\.lida$') == 5 ]] || falhou "✓ Ler todas: $(ls "$ND")"
[[ $(cab_de "$out") == *'✓ 4 notificações marcadas como lidas.'* ]] || falhou "aviso do Ler todas: $(cab_de "$out")"
[[ $(cab_de "$(acao todas_lidas '')") == *'Nada a marcar'* ]] || falhou 'Ler todas sem nada novo deveria dizer'
rm -f -- "${ND:?}"/1791000000000000001.lida "${ND:?}"/1791000000000000003.lida "${ND:?}"/1791000000000000004.lida
out=$(acao apagar 1791000000000000005)
[[ ! -e $ND/1791000000000000005 && -f $ND/1791000000000000005.apagada ]] || falhou '✕ Apagar deveria apagar com lápide'
[[ $(lista_de "$out") != *'Novidades'* ]] || falhou 'a lista recarregada ainda mostra o apagado'
passou 'lida ⇄ não lida, ler todas e apagar'

# 5) 🧹 Limpar lidas pede confirmação no próprio cabeçalho; só ✕ Apagar/⏎ apagam, Esc/‹ Cancelar voltam
out=$(acao limpar '')
[[ $(get modo) == confirmar && $out != *reload* ]] || falhou "🧹 deveria só perguntar: $out"
cab=$(cab_de "$out"); [[ $cab == *'Apagar a notificação lida'*'✕ Apagar'*'‹ Cancelar'* ]] || falhou "pergunta: $cab"
[[ $(acao apagar 1791000000000000001) == ignore && -e $ND/1791000000000000001 ]] || falhou 'com a pergunta na tela, outra ação não age'
acao esc '' >/dev/null; [[ $(get modo) == lista && -e $ND/1791000000000000002 ]] || falhou 'Esc deveria cancelar sem apagar'
acao limpar '' >/dev/null
FZF_COLUMNS=92 "$TT" --notifs-cabecalho >/dev/null
read -r l i _ _ < <(grep ' confirmar$' "$MAPA")
out=$(FZF_CLICK_HEADER_LINE=$l FZF_CLICK_HEADER_COLUMN=$i acao cabecalho '')
[[ ! -e $ND/1791000000000000002 && -f $ND/1791000000000000002.apagada && -e $ND/1791000000000000001 ]] || falhou '✕ Apagar da confirmação deveria apagar só as lidas'
[[ $(get modo) == lista && $(cab_de "$out") == *'A notificação lida foi apagada.'* ]] || falhou "depois de apagar, volta à lista com o aviso: $(cab_de "$out")"
[[ $(cab_de "$(acao limpar '')") == *'Nenhuma notificação lida para apagar.'* && $(get modo) == lista ]] || falhou 'sem lidas, 🧹 só avisa'
passou '🧹 Limpar lidas com confirmação'

# 6) abrir: com destino, o fzf devolve a linha (notifs_ui abre); sem destino, marca lida e avisa
[[ $(acao enter 1791000000000000003) == accept ]] || falhou '⏎ num aviso com destino deveria aceitar'
[[ $(acao duplo 1791000000000000001) == accept ]] || falhou 'duplo clique abre como o ⏎'
[[ $(acao abrir 1791000000000000001) == accept ]] || falhou 'botão ↗ Abrir abre como o ⏎'
out=$(acao enter 1791000000000000004)
[[ -f $ND/1791000000000000004.lida && $(cab_de "$out") == *'não leva a outro lugar'* ]] || falhou "⏎ sem destino: $(cab_de "$out")"
[[ $(acao enter '') == ignore && $(acao enter 'lixo') == ignore ]] || falhou '⏎ na linha "nenhuma notificação" não faz nada'
[[ $(acao esc '') == abort && $(acao q '') == abort ]] || falhou 'Esc/q fecham a central'
passou 'abrir com e sem destino; Esc fecha'

# 7) lista vazia diz o que é, sem id (as ações a ignoram)
printf 'filtro=lidas\n' >"$UI"; rm -f -- "${ND:?}"/*.lida
l=$("$TT" --notifs-lista-ui | sem_cor)
[[ $(cut -f1,2 <<<"$l") == $'\t' && $l == *'Nenhuma notificação lida.'* ]] || falhou "lista vazia: $l"
passou 'aba vazia orienta'

# 7b) uma linha por aviso (sem --wrap), a linha em foco destacada de ponta a ponta, ↗ numa coluna antes
#     do texto; a prévia mostra estado, quando, origem, o texto inteiro e o que ⏎ faz
grep -q -- "--highlight-line" "$TT" || falhou 'a linha em foco deveria ser destacada de ponta a ponta (--highlight-line)'
! sed -n '/^notifs_ui() {/,/^}/p' "$TT" | grep -q -- '--wrap' || falhou 'a central não quebra linha: um aviso, uma linha (o texto inteiro vai na prévia)'
grep -q -- '--preview="$EU --notifs-previa {2}"' "$TT" || falhou 'a central deveria ter a prévia do aviso em foco'
printf 'filtro=todas\nmodo=lista\n' >"$UI"
printf '%s\t%s\t%s\t%s\n' 9999999999 '📧 Conta: um texto bem comprido que não cabe numa linha só da central e continua' 'email:conta' '' >"$ND/1791000000000000021"
l=$("$TT" --notifs-lista-ui | sem_cor | grep 'bem comprido')
[[ $l == *'● Não lida  ↗ 📧 Conta: um texto bem comprido'*'e continua' ]] || falhou "linha com destino: ↗ antes do texto: $l"
p=$("$TT" --notifs-previa 1791000000000000021 | sem_cor)
[[ $(sed -n 1p <<<"$p") == '● Não lida · 03/10 '*' · e-mail' ]] || falhou "prévia: 1ª linha com estado, quando e origem: $p"
[[ $(sed -n 2p <<<"$p") == '📧 Conta: um texto bem comprido que não cabe numa linha só da central e continua' ]] || falhou "prévia: texto inteiro: $p"
[[ $(sed -n 3p <<<"$p") == '↗ ⏎ ou duplo clique: abre o e-mail na mensagem nova (conta conta)' ]] || falhou "prévia: o que ⏎ faz: $p"
[[ $("$TT" --notifs-previa 1791000000000000004 | sem_cor | tail -1) == 'Sem destino: ⏎ só marca como lida.' ]] || falhou 'prévia de aviso sem destino'
[[ -z $("$TT" --notifs-previa '') && -z $("$TT" --notifs-previa 'x;y') ]] || falhou 'prévia sem aviso (linha vazia, id estranho) fica em branco'
rm -f -- "${ND:?}"/1791000000000000021
passou 'uma linha por aviso, ↗ antes do texto e a prévia com o aviso inteiro'

# 7c) desempenho: um clique na central não abre date/ls/sort/grep/mktemp (com 30 avisos eram ~100
#     processos por clique, e com o servidor do tmux ocupado isso virava um atraso grande)
mkdir -p "$T/espias"
for cmd in date ls sort grep mktemp; do
  real=$(command -v "$cmd")
  printf '#!/bin/sh\necho %s >>"%s"\nexec %s "$@"\n' "$cmd" "$T/espias.log" "$real" >"$T/espias/$cmd"; chmod +x "$T/espias/$cmd"
done
for i in $(seq 30 59); do aviso "17910000000000000$i" "📧 Conta $i: e-mail com um assunto bem comprido número $i para cortar" 'email:conta'; done
printf 'filtro=todas\nmodo=lista\n' >"$UI"
TT_SO_CARREGAR=1 PATH="$T/espias:$PATH" bash -c 'source "$1" >/dev/null 2>&1; : >"$2"
  notifs_acao filtro:naolidas "" >/dev/null; notifs_acao lida 1791000000000000030 >/dev/null; notifs_acao proximo "" >/dev/null
  notifs_previa 1791000000000000030 >/dev/null' _ "$TT" "$T/espias.log"
[[ ! -s $T/espias.log ]] || falhou "a central abriu processos por clique: $(sort "$T/espias.log" | uniq -c | tr '\n' ' ')"
[[ $(get filtro) == lidas && -f $ND/1791000000000000030.lida ]] || falhou "as ações da guarda de desempenho não rodaram: $(cat "$UI")"
for i in $(seq 30 59); do rm -f -- "${ND:?}/17910000000000000$i" "${ND:?}/17910000000000000$i.lida"; done
printf 'filtro=todas\nmodo=lista\n' >"$UI"
passou 'clique na central sem date/ls/sort/grep/mktemp'

# 8) cada atalho do teclado chama a mesma ação do botão (mesmo despachante)
for par in 'enter:transform($a enter' 'double-click:transform($a duplo' 'click-header:transform($a cabecalho' \
  'space:transform($a lida' 'ctrl-d:transform($a apagar' 'del:transform($a apagar' 'ctrl-r:transform($a limpar' \
  'ctrl-l:transform($a todas_lidas' 'ctrl-u:transform($a filtro:naolidas' 'ctrl-a:transform($a filtro:todas' \
  'tab:transform($a proximo' 'btab:transform($a anterior' 'esc:transform($a esc' 'q:transform($a q'; do
  grep -qF -- "--bind=\"$par" "$TT" || falhou "atalho ausente ou fora do despachante: $par"
done
passou 'atalhos do teclado = botões'

# 9) o fzf de verdade: clique de mouse na aba e no botão, Espaço, 🧹 + Esc, q fecha
printf '%s\t%s\t%s\t%s\n' 9999999999 '📧 Conta: e-mail de Bia' 'email:conta' '' >"$ND/1791000000000000011"
printf '%s\t%s\t%s\t%s\n' 9999999999 '📋 Lembrete lido' tarefas '' >"$ND/1791000000000000012"; : >"$ND/1791000000000000012.lida"
fora new-session -d -x 90 -y 18 -s nt "env HOME=$HOME XDG_CONFIG_HOME=$XDG_CONFIG_HOME TT_RT=$TT_RT TT_DIR=$TT_DIR LANG=C.UTF-8 LC_ALL=C.UTF-8 $TT --notifs-ui; echo CENTRAL-FECHOU; sleep 30"
tela() { fora capture-pane -p -t nt; }
esperar_tela() { # padrão (grep -E) [não: 1 = esperar sumir]
  local i
  for i in $(seq 1 50); do
    if [[ -z ${2:-} ]]; then grep -qE -- "$1" <<<"$(tela)" && return 0
    else grep -qE -- "$1" <<<"$(tela)" || return 0; fi
    sleep 0.1
  done
  return 1
}
clicar_em() { # texto da 1ª linha onde ele aparece
  local cap y lin pre x
  cap=$(tela); y=$(grep -nF -- "$1" <<<"$cap" | head -1 | cut -d: -f1)
  [[ -n $y ]] || falhou "«$1» não está na tela: $cap"
  lin=$(sed -n "${y}p" <<<"$cap"); pre=${lin%%"$1"*}
  x=$(( $(printf '%s' "$pre" | python3 -c 'import sys,unicodedata; print(sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in sys.stdin.read()))') + 2 ))
  fora send-keys -t nt -l $'\e[<0;'"$x;$y"'M'; fora send-keys -t nt -l $'\e[<0;'"$x;$y"'m'
}
esperar_tela 'Lembrete lido' || falhou "a central não abriu: $(tela)"
clicar_em 'Não lidas'
esperar_tela 'Lembrete lido' sumir || falhou "clique na aba Não lidas não filtrou: $(tela)"
esperar_tela 'Bia' || falhou "Não lidas deveria mostrar a não lida: $(tela)"
fora send-keys -t nt Space
esperar_tela 'Lidas 2|Lidas 3' || falhou "Espaço deveria marcar a em foco como lida: $(tela)"
clicar_em 'Limpar lidas'
esperar_tela 'aqui e nas outras máquinas\?' || falhou "🧹 deveria perguntar: $(tela)"
fora send-keys -t nt Escape
esperar_tela 'Ler todas' || falhou "Esc deveria voltar à barra de botões: $(tela)"
[[ -e $ND/1791000000000000012 ]] || falhou 'Esc na pergunta apagou'
# a roda do mouse anda pela lista (a prévia acompanha o aviso em foco)
clicar_em 'Todas'
esperar_tela 'Lembrete lido' || falhou "Todas deveria voltar a mostrar tudo: $(tela)"
antes=$(tela | tail -6)
read -r x y < <(tela | grep -nE '● Não lida|✓ Lida' | head -1 | awk -F: '{print 10, $1}')
for _ in 1 2 3; do fora send-keys -t nt -l $'\e[<65;'"$x;$y"'M'; done
for _ in $(seq 1 30); do [[ $(tela | tail -6) != "$antes" ]] && break; sleep 0.1; done
[[ $(tela | tail -6) != "$antes" ]] || falhou "a roda do mouse não andou pela lista: $(tela)"
fora send-keys -t nt q
esperar_tela 'CENTRAL-FECHOU' || falhou "q deveria fechar a central: $(tela)"
passou 'fzf de verdade: clique na aba, Espaço, 🧹 pergunta e Esc cancela, roda do mouse, q fecha'
