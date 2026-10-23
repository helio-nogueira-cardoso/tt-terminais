#!/usr/bin/env bash
# tt-teste: sozinho (atalho e popup reais; transporte simulado, sem rede)
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
fn() { TT_SO_CARREGAR=1 bash -c 'source "$1"; shift; menu_popup() { cat; }; "$@"' _ "$TT" "$@"; }
espera() { local n; for ((n=0; n<100; n++)); do "$@" && return 0; sleep .05; done; return 1; }
cat >"$T/transporte" <<'EOF'
#!/bin/sh
exec sleep 600
EOF
chmod +x "$T/transporte"
cat >"$T/ponte" <<EOF
#!/usr/bin/env bash
TT_SO_CARREGAR=1 source "$TT"
EU="$T/transporte"
ponte destino simulada ponte
EOF
chmod +x "$T/ponte"
tmux -f "$HOME/.tmux.conf" new-session -d -s ponte -x 120 -y 36 "$T/ponte"
tmux new-session -d -s preservada 'sleep 600'
anexar tela 120 36 ponte
tentativa() { [[ -n $(tmux show-options -pqv -t =ponte: @tt_tentativa) ]]; }
espera tentativa || falhou 'supervisor não registrou a tentativa'
supervisor=$(tmux show-options -pqv -t =ponte: @tt_tentativa); supervisor=${supervisor%%|*}
c=$(tmux list-clients -t =ponte -F '#{client_name}' | head -1)
[[ -n $c ]] || falhou 'cliente não anexou'
central() { fora capture-pane -p -t tela | grep -q 'Recuperar tela'; }
fora send-keys -t tela C-b Escape
espera central || falhou 'Ctrl+B Esc não abriu central local'
encerrou() { ! kill -0 "$supervisor" 2>/dev/null; }
espera encerrou || falhou 'escape deixou tentativa de conexão viva'
tmux has-session -t =ponte && tmux has-session -t =preservada || falhou 'escape encerrou sessão de trabalho'
tmux display-popup -C -c "$c"
recuperou() { tmux capture-pane -p -t =ponte: | grep -q 'Tentativa cancelada'; }
espera recuperou || falhou 'fechar central não voltou à tela de recuperação'
passou 'Ctrl+B Esc cancela transporte e abre central sem derrubar sessões'

tmux run-shell -b "$TT --recuperar-tela '$c'"
espera central || falhou 'CLI não abriu a mesma central'
tmux display-popup -C -c "$c"
fn menu_painel "$c" "$(tmux display -p -t =ponte: '#{pane_id}')" >"$T/menu"
grep -q -- '--recuperar-tela' "$T/menu" || falhou 'menu não oferece a mesma ação'
passou 'CLI e menu alcançam a mesma recuperação local'

# Agora o --ponte completo, inclusive o --ponte-tentar carregado pelo núcleo instalado.
# O "SSH" executa o comando em outro HOME/socket, sem rede nem instalação remota.
export TT_TEST_PRE_REMOTE=$T/remota
mkdir -p "$T/bin" "$TT_TEST_PRE_REMOTE/home/.config/tt" "$TT_TEST_PRE_REMOTE/home/.local/bin" \
  "$TT_TEST_PRE_REMOTE/tmux" "$TT_TEST_PRE_REMOTE/rt"
ln -s "$RAIZ/tests/precarregar_ssh.py" "$T/bin/ssh"
export PATH="$T/bin:$PATH"
printf 'nome=remota\nprecarregar=off\n' >"$TT_TEST_PRE_REMOTE/home/.config/tt/config"
"$TT" --ponte-tentar usuario@destino renomeavel integrada 'token;invalido' && falhou 'aceitou marcador inválido'
[[ ! -e $TT_TEST_PRE_REMOTE/ssh.log ]] || falhou 'marcador inválido chegou ao transporte'
R() { env -u TMUX TMUX_TMPDIR="$TT_TEST_PRE_REMOTE/tmux" tmux "$@"; }
trap 'teste_status=$?; set +e; R kill-server 2>/dev/null; (exit "$teste_status"); limpar_isolado' EXIT
R -f /dev/null new-session -d -s renomeavel "bash -c 'echo REMOTA_INTEGRADA; while read -r linha; do echo DIGITADO:\"\$linha\"; done'"
tmux new-session -d -s integrada -e "PATH=$PATH" -e "TT_TEST_PRE_REMOTE=$TT_TEST_PRE_REMOTE" -e TT_T_RECONEXAO=5 \
  "$TT --ponte usuario@destino renomeavel integrada"
tmux switch-client -c "$c" -t =integrada
mostra() { fora capture-pane -p -t tela | grep -q "$1"; }
espera mostra REMOTA_INTEGRADA || falhou 'ponte completa não chegou ao primeiro quadro'
fora send-keys -t tela 'conteudo-integrado' Enter
espera mostra 'DIGITADO:conteudo-integrado' || falhou 'teclas não chegaram ao destino após o marcador'
id_remoto=$(tmux show-options -qv -t =integrada: @ponte_id)
srv_remoto=$(tmux show-options -qv -t =integrada: @ponte_srv)
[[ $id_remoto == '$'* ]] || falhou 'identidade remota não foi guardada'
R rename-session -t =renomeavel renomeada
rc=$(R list-clients -F '#{client_name}' | head -1)
R detach-client -t "$rc"
espera mostra Reconectar || falhou 'desconexão não apresentou recuperação'
fora send-keys -t tela Enter
espera mostra REMOTA_INTEGRADA || falhou 'reconexão perdeu a sessão renomeada'
[[ $(tmux show-options -qv -t =integrada: @ponte_id) == "$id_remoto" ]] || falhou 'reconexão mudou de identidade'
R kill-session -t =renomeada
espera mostra Reconectar || falhou 'fim da sessão não apresentou saída local'
fora send-keys -t tela Enter
espera mostra 'não existe mais' || falhou 'alvo ausente não foi confirmado com saída recuperável'
passou 'ponte instalada recebe teclas, reconecta por identidade após renomeação e oferece saída para alvo ausente'

# N também atravessa a CLI instalada e o supervisor, com um tt remoto mínimo.
cat >"$TT_TEST_PRE_REMOTE/home/.local/bin/tt" <<'EOF'
#!/usr/bin/env bash
[[ $1 == --nova ]] || exit 2
tmux new-session -d -s nova-integrada "bash -c 'echo NOVA_INTEGRADA; while read -r linha; do echo NOVA:\"\$linha\"; done'" || exit
echo nova-integrada
EOF
chmod +x "$TT_TEST_PRE_REMOTE/home/.local/bin/tt"
tmux set-option -t =integrada: @ponte_uuid aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
tmux set-option -t =integrada: @tt_pre_id aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
# A espera já desenhou o erro do alvo ausente. Não digitar por cima do quadro antigo
# que reaparece por um instante ao fechar um popup, antes de o leitor voltar.
fora send-keys -t tela n
espera mostra NOVA_INTEGRADA || falhou 'N não criou e mostrou a nova sessão remota'
novo_id=$(tmux show-options -qv -t =integrada: @ponte_id)
novo_srv=$(tmux show-options -qv -t =integrada: @ponte_srv)
# A última sessão anterior terminou: outro servidor pode reutilizar $0; vale id + início.
[[ -n $novo_id && "$novo_id|$novo_srv" != "$id_remoto|$srv_remoto" ]] || falhou 'N manteve a identidade da sessão antiga'
[[ $(tmux show-options -qv -t =integrada: @ponte_alvo) == 'usuario@destino|nova-integrada' ]] || falhou 'N guardou o alvo antigo'
[[ -z $(tmux show-options -qv -t =integrada: @ponte_uuid) && -z $(tmux show-options -qv -t =integrada: @tt_pre_id) ]] || falhou 'UUID antigo sobreviveu à criação'
fora send-keys -t tela conteudo-novo Enter
espera mostra 'NOVA:conteudo-novo' || falhou 'nova sessão não recebe digitação'
rc=$(R list-clients -F '#{client_name}' | head -1)
R detach-client -t "$rc"
espera mostra Reconectar || falhou 'nova sessão não apresentou recuperação ao desconectar'
espera mostra 'Conexão com.*nova-integrada' || falhou 'recuperação mostra nome antigo após N'
fora send-keys -t tela Enter
espera mostra NOVA_INTEGRADA || falhou 'reconexão da nova sessão voltou ao alvo antigo'
[[ $(R list-sessions -F '#{session_name}' | wc -l) == 1 ]] || falhou 'reconexão criou outra sessão'
passou 'N cria uma sessão sob supervisão; reconectar preserva o novo alvo sem duplicar criação'
rc=$(R list-clients -F '#{client_name}' | head -1)
R detach-client -t "$rc"
espera mostra Reconectar || falhou 'nova desconexão não apresentou recuperação'
fora send-keys -t tela v
espera central || falhou 'V não abriu central a partir de falha real da ponte'
tmux display-popup -C -c "$c"
passou 'V abre a central local após desconexão real'
