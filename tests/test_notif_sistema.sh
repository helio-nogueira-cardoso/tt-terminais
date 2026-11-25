#!/usr/bin/env bash
# Notificação do sistema por máquina (notif_sistema=0|1, tt --notif-sistema, menu Administrar → 🖥):
#  - ligada por padrão: notificar_aparelho chama o notificador do sistema;
#  - desligada: nem notify-send nem termux-notification, com ou sem a faixa; o aviso fica no 🔔 e, sem a faixa,
#    a mensagem nos terminais continua;
#  - o menu mostra o estado e roda a mesma ação da CLI; valor inválido não mexe no config;
#  - não depende do não perturbe nem mexe nele.
source "$(dirname "$0")/lib.sh"; isolar

mkdir -p "$T/bin"; export AVISOS_TESTE=$T/avisos TELA_TESTE=$T/tela
for cmd in notify-send termux-notification; do
  printf '#!/usr/bin/env bash\nprintf "%s\\n" >>"$AVISOS_TESTE"\n' "$cmd" >"$T/bin/$cmd"; chmod +x "$T/bin/$cmd"
done
export PATH="$T/bin:$PATH"
CONF=$HOME/.config/tt/config
printf 'faixa_notif=1\n' >>"$CONF"

# Chama uma função do tt já carregado; o tmux de mentira registra a mensagem que iria à tela de um terminal.
tt_fn() {
  TT_COMPLETO=1 TT_SO_CARREGAR=1 bash -c '
    source "$0"
    tmux() { case "$1 ${2:-}" in "list-clients "*) echo cliente-teste ;; "display-message -c") printf "tela\n" >>"$TELA_TESTE" ;; esac; return 0; }
    "$@"' "$TT" "$@"
}
conta() { [[ -e $1 ]] && wc -l <"$1" | tr -d ' ' || echo 0; }

# 1) padrão: ligada
"$TT" --notif-sistema status | grep -q 'ligada' || falhou 'padrão deveria ser ligada'
tt_fn notificar_aparelho titulo corpo
(($(conta "$AVISOS_TESTE") >= 1)) || falhou 'ligada (padrão) não chamou o notificador do sistema'
passou 'ligada por padrão: o aviso vai ao sistema'

# 2) desligada, com a faixa: nada no sistema, o aviso fica no 🔔
"$TT" --notif-sistema off | grep -q 'desligada' || falhou 'off não respondeu desligada'
grep -qx 'notif_sistema=0' "$CONF" || falhou "off não gravou notif_sistema=0: $(cat "$CONF")"
antes=$(conta "$AVISOS_TESTE")
tt_fn tarefas_notificar '📋 Teste' 'aviso só no tt' '' '' 600 ''
[[ $(conta "$AVISOS_TESTE") == "$antes" ]] || falhou 'desligada deixou passar aviso ao sistema (com a faixa)'
"$TT" --notifs-listar | grep -q 'aviso só no tt' || falhou 'desligada tirou o aviso do 🔔'
passou 'desligada com a faixa: nada no sistema, aviso preservado no 🔔'

# 3) desligada, sem a faixa: nada no sistema, a mensagem nos terminais continua
sed -i.bak 's/^faixa_notif=1$/faixa_notif=0/' "$CONF"
tela=$(conta "$TELA_TESTE")
tt_fn notificar_aparelho titulo corpo || falhou 'sem a faixa, com terminal aberto, deveria dar certo'
[[ $(conta "$AVISOS_TESTE") == "$antes" ]] || falhou 'desligada deixou passar aviso ao sistema (sem a faixa)'
(($(conta "$TELA_TESTE") == tela + 1)) || falhou "sem a faixa, a mensagem nos terminais sumiu (tela=$(conta "$TELA_TESTE"))"
sed -i.bak 's/^faixa_notif=0$/faixa_notif=1/' "$CONF"
passou 'desligada sem a faixa: nada no sistema, a mensagem nos terminais continua'

# 4) valor inválido não mexe no config; alternar volta a ligar
cp "$CONF" "$T/conf.antes"
rc=0; "$TT" --notif-sistema talvez >/dev/null 2>&1 || rc=$?
((rc == 2)) || falhou "valor inválido deveria sair 2 (saiu $rc)"
cmp -s "$CONF" "$T/conf.antes" || falhou 'valor inválido alterou o config'
"$TT" --notif-sistema alternar | grep -q 'ligada' || falhou 'alternar não religou'
tt_fn notificar_aparelho titulo corpo
(($(conta "$AVISOS_TESTE") > antes)) || falhou 'religada não voltou a avisar o sistema'
passou 'valor inválido recusado; alternar religa'

# 5) menu Administrar: rótulo com o estado e a mesma ação da CLI
menu=$(TT_COMPLETO=1 TT_SO_CARREGAR=1 bash -c '
  source "$0"
  maquinas() { :; }; versao_github() { echo 0; }; tam_popup_fixar() { :; }
  menu_popup() { cat; }
  menu_admin terminal-teste
' "$TT")
IFS=$'\t' read -r _ rotulo acao <<<"$(awk -F'\t' '$1 == "N"' <<<"$menu")"
[[ $rotulo == *'Notificação do sistema'*ligada* && $acao == *' --notif-sistema alternar' ]] || falhou "menu: $rotulo / $acao"
bash -c "$acao" >/dev/null
"$TT" --notif-sistema status | grep -q 'desligada' || falhou 'a ação do menu não alternou'
menu=$(TT_COMPLETO=1 TT_SO_CARREGAR=1 bash -c '
  source "$0"
  maquinas() { :; }; versao_github() { echo 0; }; tam_popup_fixar() { :; }
  menu_popup() { cat; }
  menu_admin terminal-teste
' "$TT")
awk -F'\t' '$1 == "N"' <<<"$menu" | grep -q 'desligada, só no tt' || falhou 'o rótulo do menu não mostrou desligada'
passou 'menu Administrar: rótulo com o estado e a mesma ação da CLI'

# 6) independente do não perturbe
"$TT" --nao-perturbe status | grep -q 'desligado' || falhou 'mexer na notificação do sistema ligou o não perturbe'
"$TT" --nao-perturbe on >/dev/null; "$TT" --notif-sistema on >/dev/null
"$TT" --notif-sistema status | grep -q 'ligada' || falhou 'não perturbe mudou a chave da notificação do sistema'
antes=$(conta "$AVISOS_TESTE"); tt_fn notificar_aparelho titulo corpo
[[ $(conta "$AVISOS_TESTE") == "$antes" ]] || falhou 'com o não perturbe ligado, o aviso ainda foi ao sistema'
"$TT" --nao-perturbe off >/dev/null
passou 'independente do não perturbe'
