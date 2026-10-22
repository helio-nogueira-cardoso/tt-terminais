#!/usr/bin/env bash
# Atalhos no Mac: Option no lugar do Ctrl nos cliques, copiar sem mouse, F1–F10 sem a tecla fn (Ctrl+B g 1…0) e `tt --mac`.
source "$(dirname "$0")/lib.sh"; isolar # (o isolar já isola o tmux: sem o tmux-isolado.sh, cuja limpeza zerava o código de saída)
TT="$RAIZ/tt"

# 1) o tmux.conf do pacote carrega num servidor isolado e traz as ligações
tmux -f /dev/null new-session -d -s mac 2>/dev/null || falhou 'tmux isolado não subiu'
tmux source-file "$RAIZ/tmux.conf" >/dev/null 2>&1 || true
chaves=$(tmux list-keys)
for esperado in 'root +M-MouseDown1Pane' 'root +M-SecondClick1Pane' 'root +C-MouseDown1Pane' 'copy-mode-vi +y ' 'copy-mode +Enter ' 'prefix +g +switch-client -T tt-botoes'; do
  grep -Eq -- "$esperado" <<<"$chaves" || falhou "falta a ligação: $esperado"
done
# g, depois 1 a 9 e 0, equivale a F1…F10 (a mesma ação do tt --botao)
ordem=(cl clc clr dbn tela sair ant dv zm jn); i=0
for k in 1 2 3 4 5 6 7 8 9 0; do
  f=$((i+1)); acao=${ordem[i]}
  grep -E -- "-T tt-botoes +$k " <<<"$chaves" | grep -q -- "--botao $acao " || falhou "Ctrl+B g $k não chama --botao $acao"
  grep -E -- "-T prefix +F$f " <<<"$chaves" | grep -q -- "--botao $acao " || falhou "F$f não chama --botao $acao"
  i=$((i+1))
done
# Ctrl+B [ copia sem mouse: v marca e y (ou Enter) copia nos dois modos de teclas. O tmux nasce no emacs (o do
# dell e o do Mac em 20/10/2026), onde v e y não existiam; no vi o v padrão só alternava o retângulo.
tmux new-window -d -t mac -n copia "printf 'alfa beta gama\n'; exec sleep 60"
sleep 0.3
for modo in emacs vi; do
  for tecla in y Enter; do
    rm -f "$T/copiado"
    tmux set -g mode-keys "$modo"; tmux set -g @tt_copiar "cat > '$T/copiado'"
    tmux copy-mode -t mac:copia
    tmux send -t mac:copia -X history-top; tmux send -t mac:copia -X start-of-line
    tmux send -t mac:copia v
    for _ in 1 2 3; do tmux send -t mac:copia -X cursor-right; done
    tmux send -t mac:copia "$tecla"
    for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s $T/copiado ]] && break; sleep 0.1; done
    [[ $(cat "$T/copiado" 2>/dev/null) == alf* ]] || falhou "modo de cópia $modo: v e $tecla não copiaram ($(cat "$T/copiado" 2>/dev/null))"
    [[ $(tmux display -p -t mac:copia '#{pane_in_mode}') == 0 ]] || { tmux send -t mac:copia -X cancel; falhou "modo de cópia $modo: $tecla não saiu do modo"; }
  done
done
# o Option+clique num link é o mesmo comando do Ctrl+clique (argumento "ctrl")
diff <(grep -E 'root +C-MouseDown1Pane' <<<"$chaves" | sed -E 's/C-MouseDown1Pane/X/') \
     <(grep -E 'root +M-MouseDown1Pane' <<<"$chaves" | sed -E 's/M-MouseDown1Pane/X/') >/dev/null || falhou 'Option+clique difere do Ctrl+clique'

# 2) tt --mac
tab=$("$TT" --mac atalhos)
[[ $tab == *"Cmd+V"* ]] || falhou 'tabela sem Cmd+V'
[[ $tab == *"Ctrl+B g 1"* ]] || falhou 'tabela sem Ctrl+B g'
if [[ $(uname -s) == Darwin ]]; then
  # Ghostty: ativar grava a chave uma vez só, num config isolado
  export XDG_CONFIG_HOME="$T/cfg" TT_MAC_TERMINAL=ghostty TERM_PROGRAM=
  st=$("$TT" --mac status); [[ $st == *DESLIGADO* ]] || falhou "Ghostty deveria estar desligado: $st"
  "$TT" --mac ativar >/dev/null || falhou 'ativar (Ghostty)'
  "$TT" --mac ativar >/dev/null
  [[ $(grep -c '^macos-option-as-alt = true' "$T/cfg/ghostty/config") == 1 ]] || falhou 'macos-option-as-alt gravado mais de uma vez'
  st=$("$TT" --mac status); [[ $st == *"ligado"* && $st != *DESLIGADO* ]] || falhou "status não vê o Ghostty ligado: $st"
else
  st=$("$TT" --mac status); [[ $st == *"só faz sentido no macOS"* ]] || falhou "fora do Mac deveria avisar: $st"
fi
echo 'ok: atalhos do Mac (Option, Ctrl+B g, tt --mac)'
