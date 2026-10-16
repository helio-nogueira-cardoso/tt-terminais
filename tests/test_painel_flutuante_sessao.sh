#!/usr/bin/env bash
# Janelas do tt abertas por cima de uma sessão (e-mail, menus, tarefas, a própria central: painéis
# flutuantes do tmux 3.8, que ficam como o painel ATIVO da sessão enquanto abertos) não são a sessão. O
# nomeador, a lista e a prévia da central e o mestre de obras leem o painel de trabalho de baixo. Antes,
# com o e-mail aberto, o nomeador dava à sessão o assunto de um e-mail. Precisa de um tmux 3.8+ (o do
# sistema, TT_TMUX_38 ou ~/.local/share/tt-tmux/bin/tmux de quem roda); sem ele, é pulado.
source "$(dirname "$0")/lib.sh"; isolar
suporta() { # binário -> 0 se o new-pane dele aceita -O -C -K (painel flutuante modal)
  local uso; uso=$("$1" -L "chk-$$" -f /dev/null list-commands new-pane 2>/dev/null) || return 1
  [[ $uso =~ \[-([A-Za-z]+)\] && ${BASH_REMATCH[1]} == *O* && ${BASH_REMATCH[1]} == *C* && ${BASH_REMATCH[1]} == *K* ]]
}
BIN38=""
for b in "$(command -v tmux)" "${TT_TMUX_38:-}" "$HOME_REAL/.local/share/tt-tmux/bin/tmux"; do
  [[ -n $b && -x $b ]] && suporta "$b" && { BIN38=$b; break; }
done
if [[ -z $BIN38 ]]; then echo "pulado: nenhum tmux 3.8+ (defina TT_TMUX_38)"; exit 0; fi
mkdir -p "$T/bin" "$T/proj"; ln -s "$BIN38" "$T/bin/tmux"; export PATH="$T/bin:$PATH"
# Nomeador falso (modo local): guarda o texto que recebeu e responde um nome.
cat >"$T/pkg/nomeador-local.py" <<'EOF'
import sys
if sys.argv[1:2] == ["nomear"]:
    open(sys.argv[0] + ".entrada", "w").write(sys.stdin.read())
    print("nome-falso")
EOF
printf 'nomeador=local\n' >>"$XDG_CONFIG_HOME/tt/config"
tmux new -d -s trabalho -x 120 -y 30 -c "$T/proj" 'bash --norc --noprofile'
tmux send-keys -t trabalho 'echo TRABALHO-REAL-1; echo TRABALHO-REAL-2; echo TRABALHO-REAL-3' Enter
sleep 0.5
base=$(tmux display -p -t trabalho '#{pane_id}')
# O e-mail do tt por cima, aberto como o popup_janela abre (flutuante, modal, vira o painel ativo).
( tmux new-pane -d -W -t "$base" -O -C -K -B single -X 5 -Y 3 -x 80 -y 20 -c "$HOME" -- \
  bash --norc --noprofile -c 'echo EMAIL-ASSUNTO-SECRETO; exec sleep 600' >/dev/null 2>&1 & )
for _ in $(seq 30); do [[ $(tmux display -p -t '=trabalho:' '#{pane_floating_flag}') == 1 ]] && break; sleep 0.1; done
[[ $(tmux display -p -t '=trabalho:' '#{pane_floating_flag}') == 1 ]] || falhou 'cenário: o painel flutuante não ficou ativo'
tmux capture-pane -p -t '=trabalho:' | grep -q EMAIL-ASSUNTO || falhou 'cenário: =sessão: deveria apontar para o e-mail'

# 1) o nomeador lê a pasta, o programa e a tela da sessão, nunca o e-mail
"$TT" --sugerir trabalho >/dev/null 2>&1
e=$(cat "$T/pkg/nomeador-local.py.entrada" 2>/dev/null)
[[ -n $e ]] || falhou 'o nomeador não foi chamado'
grep -q 'EMAIL-ASSUNTO' <<<"$e" && falhou "o nomeador leu o e-mail aberto por cima: $e"
grep -q 'TRABALHO-REAL-3' <<<"$e" && grep -qE "Pasta: (/private)?$T/proj" <<<"$e" && grep -q 'primeiro plano: bash' <<<"$e" ||
  falhou "o nomeador não leu a sessão: $e"
passou 'nomeador: tela, pasta e programa da sessão, não do e-mail aberto por cima'

# 2) a central: a linha da sessão, a busca e a prévia são da sessão; o e-mail não vira um painel dela
l=$("$TT" --listar)
grep -q 'EMAIL-ASSUNTO' <<<"$l" && falhou 'a busca da central pegou o e-mail'
grep -P '^trabalho\t' <<<"$l" | grep -q 'TRABALHO-REAL-3' || falhou "a busca da central sem a tela da sessão: $l"
grep -P '^trabalho\t' <<<"$l" | sed 's/\x1b\[[0-9;]*m//g' | cut -f2 | grep -qE "bash *(/private)?$T/proj" || falhou "linha da sessão sem o programa/pasta dela: $(grep -P '^trabalho\t' <<<"$l" | cut -f2)"
grep -qP '^%[0-9]+\t' <<<"$l" && falhou 'o e-mail apareceu como painel da sessão na central'
p=$("$TT" --previa trabalho)
grep -q 'TRABALHO-REAL-3' <<<"$p" && ! grep -q 'EMAIL-ASSUNTO' <<<"$p" || falhou "prévia da central: $p"
passou 'central: linha, busca e prévia da sessão; o e-mail por cima não é um painel dela'

# 3) mestre de obras: programa e última linha da sessão
t=$("$TT" --listar-tudo --tsv | grep -P '^[^\t]*\ttrabalho\t')
[[ $(cut -f6 <<<"$t") == bash && $(cut -f12 <<<"$t") == bash-* ]] || falhou "mestre de obras: $t" # a última linha da sessão é o prompt
grep -q 'EMAIL-ASSUNTO' <<<"$("$TT" --listar-tudo --para-ia)" && falhou 'mestre de obras (--para-ia) leu o e-mail'
passou 'mestre de obras: programa e última linha da sessão, não do e-mail'
