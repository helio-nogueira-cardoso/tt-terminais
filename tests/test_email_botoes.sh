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

# 2) clique num botão (rota em_*) vira a tecla de função do aerc (nunca uma letra, que cairia no
#    que estivesse na frente — editor, terminal)
: >"$T/aerc.in"; sleep 0.3
tt --clique em_nova base '' "$HOME" 0; sleep 0.6; tt --clique em_abrir base '' "$HOME" 0; sleep 0.6
tt --clique em_resp base '' "$HOME" 0; sleep 0.6; tt --clique em_apagar base '' "$HOME" 0; sleep 0.8
rec=$(cat -v "$T/aerc.in")
grep -q '\^\[OS\|\^\[\[14~' <<<"$rec" || falhou "+ Nova deveria mandar F4 ao aerc: $rec"
grep -q '\^\[OR\|\^\[\[13~' <<<"$rec" || falhou "Abrir deveria mandar F3: $rec"
grep -q '\^\[\[15~' <<<"$rec" || falhou "Responder deveria mandar F5: $rec"
grep -q '\^\[\[20~' <<<"$rec" || falhou "Apagar deveria mandar F9: $rec"
grep -q '[[:alpha:]]' <<<"$(sed 's/\^\[O[PQRS]//g; s/\^\[\[[0-9]*~//g' <<<"$rec")" && falhou "nenhuma letra deveria ir ao aerc: $rec"
passou 'clique nos botões manda a tecla de função certa ao aerc (F3 abrir, F4 nova, F5 responder, F9 apagar), nunca letras'

# 2b) contas e atalhos são telas do tt: janelas da sessão oculta, com a barra; funcionam de qualquer
#     lugar — abrir uma com a outra aberta troca; o mesmo botão de novo fecha; uma ação do aerc fecha
#     a tela e age no aerc
telas() { tmux list-windows -t =_tt-email -F '#{window_active}:#{@tt_email_tela}' | tr '\n' ' '; }
tt --clique em_atalhos base '' "$HOME" 0; sleep 1
[[ $(telas) == '0: 1:atalhos ' ]] || falhou "botão atalhos deveria abrir a janela da tela de atalhos: $(telas)"
tt --clique em_contas base '' "$HOME" 0; sleep 1
[[ $(telas) == '0: 1:contas ' ]] || falhou "contas com atalhos aberto deveria trocar a tela: $(telas)"
tt --clique em_contas base '' "$HOME" 0; sleep 1
[[ $(telas) == '1: ' ]] || falhou "o mesmo botão de novo deveria fechar a tela: $(telas)"
tt --clique em_contas base '' "$HOME" 0; sleep 1
[[ $(telas) == '0: 1:contas ' ]] || falhou "contas deveria abrir de novo: $(telas)"
: >"$T/aerc.in"
tt --clique em_abrir base '' "$HOME" 0; sleep 1
[[ $(telas) == '1: ' ]] || falhou "abrir com a tela de contas na frente deveria fechá-la: $(telas)"
grep -q '\^\[OR\|\^\[\[13~' <<<"$(cat -v "$T/aerc.in")" || falhou "…e mandar F3 ao aerc: $(cat -v "$T/aerc.in")"
tt --email-tela atalhos; sleep 1; [[ $(telas) == '0: 1:atalhos ' ]] || falhou "tt --email-tela atalhos (a tecla ? do aerc) deveria abrir a tela: $(telas)"
tt --email-tela atalhos; sleep 1; [[ $(telas) == '1: ' ]] || falhou "tt --email-tela de novo deveria fechar: $(telas)"
passou 'telas do tt (contas, atalhos) abrem como janelas da sessão oculta; trocam entre si, o mesmo botão fecha, uma ação do aerc fecha e age'

# 2c) binds da sessão oculta: ? e F2 viram telas do tt (não abas do aerc) e F3–F10 têm ação por contexto
mkdir -p ~/.config/aerc
printf '[messages]\n<Enter> = :view<Enter>\nq = :quit<Enter>\n? = :term %s/.local/bin/tt --email-atalhos<Enter>\n<F2> = :term %s/.local/bin/tt --email-contas-ui<Enter>\n[view]\n? = :term %s/.local/bin/tt --email-atalhos<Enter>\n' "$HOME" "$HOME" "$HOME" >~/.config/aerc/binds.conf
tmux kill-session -t =_tt-email
bash -c "source <(sed -n '/^EMAIL_SESSAO=/,/^# ─── Cadastro e gerência de contas de e-mail/p' '$TT' | sed '\$d'); email_sessao 'aerc' largo" || falhou 'email_sessao com binds'
bo=~/.cache/tt-aerc-binds-oculto.conf
grep -q "^? = :exec $HOME/.local/bin/tt --email-tela atalhos<Enter>$" "$bo" || falhou "? deveria abrir a tela de atalhos do tt: $(cat "$bo")"
grep -q "^<F2> = :exec $HOME/.local/bin/tt --email-tela contas<Enter>$" "$bo" || falhou "F2 deveria abrir a tela de contas do tt"
grep -q ':term' "$bo" && falhou 'ainda há :term nos binds da sessão oculta'
grep -q '^q = :exec tmux detach-client<Enter>$' "$bo" || falhou 'q deveria desanexar'
awk '/^\[messages\]/{s="m"} /^\[view\]/{s="v"} /^<F3> = :view<Enter>$/{f[s]++} /^<F9> = :choose -o y .Apagar esta mensagem. delete-message<Enter>$/{d[s]++} END{exit !(f["m"]==1 && !f["v"] && d["m"]==1 && d["v"]==1)}' "$bo" || falhou "F3 só na lista, F9 na lista e na leitura: $(grep -n '^<F\|^\[' "$bo")"
[[ $(tmux show -qv -t =_tt-email: @tt_email_binds) == 3:* ]] || falhou "sessão deveria marcar a versão dos binds (versão:soma do binds.conf): $(tmux show -qv -t =_tt-email: @tt_email_binds)"
passou 'binds da sessão oculta: ? e F2 abrem as telas do tt; F3–F10 ligados por contexto; versão marcada'

# 2d) sessão oculta de antes (sem a versão dos binds) é recriada ao abrir — os botões mandam F3–F10
tmux set -qu -t =_tt-email: @tt_email_binds
bash -c "source <(sed -n '/^EMAIL_SESSAO=/,/^# ─── Cadastro e gerência de contas de e-mail/p' '$TT' | sed '\$d'); email_sessao 'aerc' largo" || falhou 'email_sessao recriar'
[[ $(tmux show -qv -t =_tt-email: @tt_email_binds) == 3:* ]] || falhou 'sessão com binds antigos deveria ser recriada com a versão nova'
# binds.conf mudou (ex.: conta Gmail cadastrada → binds por conta): a sessão também é recriada
echo '# mudou' >>~/.config/aerc/binds.conf
antes=$(tmux show -qv -t =_tt-email: @tt_email_binds)
bash -c "source <(sed -n '/^EMAIL_SESSAO=/,/^# ─── Cadastro e gerência de contas de e-mail/p' '$TT' | sed '\$d'); email_sessao 'aerc' largo" || falhou 'email_sessao após mudança'
[[ $(tmux show -qv -t =_tt-email: @tt_email_binds) != "$antes" ]] || falhou 'binds.conf mudado deveria recriar a sessão (soma nova)'
passou 'sessão oculta com binds antigos ou binds.conf mudado é recriada'

# 2e) linha de status do aerc fica só com o estado; as dicas antigas do tt são migradas, valor do dono fica
printf '[statusline]\ncolumn-right={{.TrayInfo}}  ? atalhos · F2 contas · Ctrl+r redesenha · q fecha\n' >~/.config/aerc/aerc.conf
bash -c "source <(sed -n '/^AERC_BINDS_INI=/,/^remover_aerc() {/p' '$TT' | sed '\$d'); DIR_TT='$TT_DIR'; conf() { :; }; aerc_tema_suportado() { return 1; }; configurar_aerc"
grep -q '^column-right={{.TrayInfo}}$' ~/.config/aerc/aerc.conf || falhou "dica antiga (longa) deveria virar só o estado: $(grep column-right ~/.config/aerc/aerc.conf)"
printf '[statusline]\ncolumn-right={{.TrayInfo}}  ? atalhos · q fecha\n' >~/.config/aerc/aerc.conf
bash -c "source <(sed -n '/^AERC_BINDS_INI=/,/^remover_aerc() {/p' '$TT' | sed '\$d'); DIR_TT='$TT_DIR'; conf() { :; }; aerc_tema_suportado() { return 1; }; configurar_aerc"
grep -q '^column-right={{.TrayInfo}}$' ~/.config/aerc/aerc.conf || falhou 'dica antiga (curta) deveria virar só o estado'
printf '[statusline]\ncolumn-right=%%s meu\n' >~/.config/aerc/aerc.conf
bash -c "source <(sed -n '/^AERC_BINDS_INI=/,/^remover_aerc() {/p' '$TT' | sed '\$d'); DIR_TT='$TT_DIR'; conf() { :; }; aerc_tema_suportado() { return 1; }; configurar_aerc"
grep -q '^column-right=%s meu$' ~/.config/aerc/aerc.conf || falhou 'valor do dono na linha de status deveria ficar'
passou 'linha de status do aerc: só o estado (TrayInfo); dicas antigas do tt migradas; valor do dono preservado'

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
