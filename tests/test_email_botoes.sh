#!/usr/bin/env bash
# Botões clicáveis no popup do e-mail: a sessão oculta do aerc ganha uma linha de status com um botão
# por ação (range user|em_<ação>), roteada pelo mesmo caminho dos botões da barra (tt --clique) e
# traduzida na tecla do aerc; em tela estreita ficam só os ícones; aplicada também a uma sessão
# oculta antiga; duplo clique no painel do e-mail abre a mensagem (Enter) e nas outras sessões segue
# copiando a palavra. tmux isolado; o "aerc" é um programa que registra o que recebe.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"
# aerc falso: põe o terminal em modo cru e grava cada byte recebido, na hora (sem buffer)
cat >"$T/bin/aerc" <<PY
#!/usr/bin/env python3
import os, tty
tty.setraw(0)
f = open("$T/aerc.in", "ab", buffering=0)
while True:
    b = os.read(0, 1024)
    if not b: break
    f.write(b)
PY
chmod +x "$T/bin/aerc"
export PATH="$T/bin:$PATH"
mkdir -p ~/.config/aerc; printf '[Teste]\nsource = maildir://%s/m\nfrom = a@x\noutgoing = /bin/true\n' "$T" >~/.config/aerc/accounts.conf
tmux -f /dev/null new -d -s base -x 150 -y 40 'sleep 600'
tmux set -g mouse on >/dev/null
tt() { "$TT" "$@"; }

# 1) a sessão oculta nasce com a barra de botões (linha de status própria, um range por ação)
bash -c "source <(sed -n '/^EMAIL_SESSAO=/,/^# ─── Cadastro e gerência de contas de e-mail/p' '$TT' | sed '\$d'); email_sessao 'aerc' largo" || falhou 'email_sessao'
tmux has-session -t =_tt-email 2>/dev/null || falhou 'sessão oculta não foi criada'
[[ $(tmux show -qv -t =_tt-email: status) == on ]] || falhou 'sessão do e-mail deveria ter a linha de status (botões) ligada'
fmt=$(tmux show -qv -t =_tt-email: 'status-format[0]')
for a in abrir nova resp todos enc arq apagar pasta contas atalhos; do grep -q "range=user|em_$a" <<<"$fmt" || falhou "botão em_$a ausente da barra: $fmt"; done
grep -q 'client_width},100},, Abrir' <<<"$fmt" || falhou 'em tela estreita deveriam ficar só os ícones'
passou 'barra de botões do e-mail: um range por ação, rótulo só em tela larga'

# 2) clique num botão (rota em_*) vira a tecla do aerc
: >"$T/aerc.in"; sleep 0.3
tt --clique em_nova base '' "$HOME" 0; sleep 0.6; tt --clique em_abrir base '' "$HOME" 0; sleep 0.6
tt --clique em_resp base '' "$HOME" 0; sleep 0.6; tt --clique em_contas base '' "$HOME" 0; sleep 0.8
rec=$(cat -v "$T/aerc.in")
grep -q 'm' <<<"$rec" || falhou "+ Nova deveria mandar 'm' ao aerc: $rec"
grep -q '\^M' <<<"$rec" || falhou "Abrir deveria mandar Enter: $rec"
grep -q 'Rr' <<<"$rec" || falhou "Responder deveria mandar Rr: $rec"
grep -q '\^\[OQ\|\^\[\[12~' <<<"$rec" || falhou "Contas deveria mandar F2: $rec"
passou 'clique nos botões manda a tecla certa ao aerc (m, Enter, Rr, F2)'

# 3) sessão oculta antiga (sem a barra) ganha a barra quando o popup abre de novo
tmux set -q -t =_tt-email: status off; tmux set -qu -t =_tt-email: 'status-format[0]'
bash -c "source <(sed -n '/^EMAIL_SESSAO=/,/^# ─── Cadastro e gerência de contas de e-mail/p' '$TT' | sed '\$d'); email_sessao 'aerc' largo" || falhou 'email_sessao de novo'
[[ $(tmux show -qv -t =_tt-email: status) == on ]] && grep -q 'em_abrir' <<<"$(tmux show -qv -t =_tt-email: 'status-format[0]')" || falhou 'sessão antiga não ganhou a barra'
passou 'sessão oculta antiga ganha a barra ao reabrir'

# 4) duplo clique: na sessão do e-mail abre (Enter); noutra sessão não manda Enter ao programa
grep -q "DoubleClick1Pane if -F '#{==:#{session_name},_tt-email}' { send Enter }" "$RAIZ/tmux.conf" || falhou 'tmux.conf: duplo clique no e-mail não abre a mensagem'
grep -q 'links-tt.py copiar' "$RAIZ/tmux.conf" || falhou 'tmux.conf: o ramo de copiar a palavra no duplo clique sumiu'
tmux source-file "$RAIZ/tmux.conf" >/dev/null 2>&1 || true
# o gancho de anexar chama ~/.local/bin/tt, que não existe no HOME isolado: a mensagem de erro na
# tela engoliria o 1º clique do duplo
tmux set-hook -gu client-attached 2>/dev/null; tmux set -g mouse on >/dev/null
tmux list-keys -T root DoubleClick1Pane 2>/dev/null | grep -q '_tt-email' || falhou "tmux.conf não ligou o duplo clique do e-mail no servidor de teste: $(tmux list-keys -T root DoubleClick1Pane 2>&1 | head -c 200)"
anexar cli 150 40 _tt-email; sleep 2
fora send -t cli Escape; sleep 0.5
: >"$T/aerc.in"
fora send -t cli -l $'\e[<0;30;10M'; fora send -t cli -l $'\e[<0;30;10m'; sleep 0.08; fora send -t cli -l $'\e[<0;30;10M'; fora send -t cli -l $'\e[<0;30;10m'; sleep 1
grep -q '\^M' <<<"$(cat -v "$T/aerc.in")" || falhou "duplo clique no popup do e-mail deveria mandar Enter: $(cat -v "$T/aerc.in")"
fora kill-session -t cli 2>/dev/null
passou 'duplo clique no painel do e-mail abre a mensagem (Enter)'

echo 'ok: botões clicáveis no popup do e-mail e duplo clique abre a mensagem'
