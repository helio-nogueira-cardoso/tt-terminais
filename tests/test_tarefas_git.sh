#!/usr/bin/env bash
# Sincronização das tarefas por um repositório git pessoal (tarefas_sync=git|ambos), com duas máquinas
# isoladas (A e B, cada uma com o seu HOME) e um repositório git local (file://) no lugar do GitHub.
# Cobre: 1º envio num repositório vazio; troca nos dois sentidos; clone antigo divergente (envio que
# não chegou) se recupera sem perder nada; envio recusado porque a outra máquina enviou no meio refaz a
# volta; mudança feita durante uma volta não espera o vigia; tarefa vinda por P2P vai ao repositório na
# volta do vigia; lápide velha não volta do repositório; falha de acesso fica no estado e avisa uma vez;
# o verbo --tarefas-sync confere o endereço antes de gravar; a tela do menu ⋯ → 🔄 (tmux isolado).
# Nada sai da pasta do teste: HOME, config, estado, tmux e repositório são temporários.
source "$(dirname "$0")/lib.sh"; isolar
command -v git >/dev/null || { echo "pulado: sem git"; exit 0; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1   # o git do usuário (hooks, assinatura) fica de fora

R=$T/remoto.git; git init -q --bare -b main "$R"
ln -s "$R" "$T/atalho-b.git"   # B chega ao repositório por um atalho: apagar o atalho = B sem rede
maq() { # nome url
  mkdir -p "$T/$1/.config/tt" "$T/$1/rt"
  printf 'nome=%s\nhora_sync=0\ntarefas_sync=git\ntarefas_repo=%s\n' "$1" "$2" >"$T/$1/.config/tt/config"
  : >"$T/$1/.config/tt/maquinas"
}
maq A "file://$R"; maq B "file://$T/atalho-b.git"
em() { local n=$1; shift; env HOME="$T/$n" XDG_CONFIG_HOME="$T/$n/.config" TT_RT="$T/$n/rt" "$TT" "$@"; }
# As mudanças sincronizam em segundo plano; espera todas terminarem antes de conferir.
# Duas leituras vazias seguidas: entre um processo que termina e o filho que ele dispara há uma fresta.
esperar() { local i livre=0; for ((i = 0; i < 120; i++)); do
    if pgrep -f "$T/pkg/tt" >/dev/null; then livre=0; else ((++livre >= 2)) && return 0; fi; sleep 0.25; done; falhou "sincronia em 2º plano não terminou"; }
no_repo() { git -C "$R" show main:tarefas 2>/dev/null | cut -f5; }
local_de() { awk -F'\t' '$2 != "removida" { print $5 }' "$T/$1/.config/tt/tarefas" 2>/dev/null; }
tem() { grep -qxF -- "$2" <<<"$1"; }
clone_de() { echo "$T/$1/.local/state/tt/tarefas-git"; }
linha() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$3" "$4"; }   # id estado epoch texto

# 1) O 1º envio num repositório vazio leva as tarefas (antes gravava um arquivo vazio).
em A --tarefa-add "t1 de A" >/dev/null; esperar
tem "$(no_repo)" "t1 de A" || falhou "o 1º envio num repositório vazio não levou a tarefa: '$(no_repo)'"
passou "1º envio num repositório vazio leva as tarefas"

# 2) Troca nos dois sentidos.
em B --tarefas-puxar
tem "$(local_de B)" "t1 de A" || falhou "B não recebeu a tarefa de A pelo repositório"
em B --tarefa-add "t2 de B" >/dev/null; esperar
em A --tarefas-puxar
tem "$(local_de A)" "t2 de B" || falhou "A não recebeu a tarefa de B pelo repositório"
passou "troca nos dois sentidos pelo repositório"

# 3) Clone antigo divergente (um envio que não chegou, como deixava a versão anterior) se recupera:
#    nada se perde e as duas máquinas voltam a trocar.
agora=$(date +%s)
cb=$(clone_de B)
linha aaaaaaaaaaa3 aberta "$agora" "t3 que não chegou" >>"$cb/tarefas"
git -C "$cb" -c user.name=t -c user.email=t@t commit -qam "envio que não chegou"
em A --tarefa-add "t4 de A" >/dev/null; esperar
em B --tarefas-puxar; em A --tarefas-puxar
tem "$(local_de B)" "t4 de A" || falhou "B com clone divergente não recebeu a tarefa nova de A"
tem "$(local_de A)" "t3 que não chegou" || falhou "a tarefa do envio que não chegou se perdeu"
[[ $(git -C "$cb" rev-parse HEAD) == $(git -C "$R" rev-parse main) ]] || falhou "o clone de B não voltou a acompanhar o repositório"
passou "clone divergente se recupera sem perder nada"

# 4) Envio recusado porque a outra máquina enviou no meio: refaz a volta e leva as duas mudanças.
ganchoA="env HOME=$T/A XDG_CONFIG_HOME=$T/A/.config TT_RT=$T/A/rt TT_TESTE_ANTES_DO_PUSH= $TT --tarefa-add 't5 de A no meio' >/dev/null"
gancho="[[ -e $T/gancho.feito ]] || { : >$T/gancho.feito; $ganchoA; for i in \$(seq 80); do git -C $R show main:tarefas 2>/dev/null | grep -q 't5 de A' && break; sleep 0.25; done; }"
TT_TESTE_ANTES_DO_PUSH=$gancho em B --tarefa-add "t6 de B" >/dev/null; esperar
[[ -e $T/gancho.feito ]] || falhou "o gancho de teste não rodou antes do envio"
tem "$(no_repo)" "t5 de A no meio" && tem "$(no_repo)" "t6 de B" ||
  falhou "envio recusado não refez a volta: repositório tem '$(no_repo | tr '\n' '|')'"
passou "envio recusado refaz a volta e leva as duas mudanças"

# 5) Mudança feita durante uma volta não espera o vigia: quem chega com a trava ocupada marca, e a
#    volta em andamento repete.
sed -i 's/^tarefas_sync=.*/tarefas_sync=off/' "$T/B/.config/tt/config"
em B --tarefa-add "t7a de B" >/dev/null
sed -i 's/^tarefas_sync=.*/tarefas_sync=git/' "$T/B/.config/tt/config"
TT_TESTE_ANTES_DO_PUSH='sleep 2' em B --tarefas-sync agora >/dev/null &
for i in $(seq 40); do [[ -d $T/B/.local/state/tt/tarefas-git.trava ]] && break; sleep 0.1; done
em B --tarefa-add "t7b de B durante a volta" >/dev/null
wait; esperar
tem "$(no_repo)" "t7a de B" || falhou "a volta em andamento não levou a tarefa dela"
tem "$(no_repo)" "t7b de B durante a volta" || falhou "a mudança feita durante a volta ficou para depois"
[[ ! -e $T/B/.local/state/tt/tarefas-git.pendente && ! -e $T/B/.local/state/tt/tarefas-git.trava ]] || falhou "sobrou trava ou marca de pendência"
passou "mudança durante uma volta entra na mesma volta"

# 6) Tarefa que chegou por P2P vai ao repositório na volta do vigia (antes, só com mudança local).
linha bbbbbbbbbbb8 aberta "$agora" "t8 vinda por P2P" | em A --receber-tarefas
em A --tarefas-puxar
tem "$(no_repo)" "t8 vinda por P2P" || falhou "tarefa vinda por P2P não foi ao repositório na volta do vigia"
passou "tarefa vinda por P2P vai ao repositório na volta do vigia"

# 7) Lápide velha (removida há mais que a validade) não volta do repositório nem vai para ele.
velho=$((agora - 40 * 86400))
linha ccccccccccc9 removida "$velho" "t9 apagada há 40 dias" | em A --receber-tarefas
em A --tarefas-puxar; em B --tarefas-puxar
git -C "$R" show main:tarefas | grep -q '^ccccccccccc9' && falhou "lápide velha foi para o repositório"
grep -q '^ccccccccccc9' "$T/A/.config/tt/tarefas" "$T/B/.config/tt/tarefas" && falhou "lápide velha voltou para a lista local"
passou "lápide velha não volta do repositório"

# 8) Sem acesso: o estado mostra a falha (sem travar nada), avisa uma vez; voltando, mostra ✓.
rm "$T/atalho-b.git"
saida=$(TT_TAREFAS_GIT_AVISO=0 em B --tarefas-sync agora)
grep -q '⚠ falhou' <<<"$saida" && grep -q 'sem acesso ao repositório' <<<"$saida" || falhou "o estado não mostrou a falha de acesso: $saida"
TT_TAREFAS_GIT_AVISO=0 em B --tarefas-sync agora >/dev/null
avisos=$(cat "$T"/B/.local/state/tt/notifs/* 2>/dev/null | grep -c 'repositório git não sincroniza' || true)
[[ $avisos == 1 ]] || falhou "a falha deveria avisar uma vez só na faixa (avisos: $avisos)"
grep -q 'tarefas-sync$' "$T"/B/.local/state/tt/notifs/* || falhou "o aviso deveria abrir a tela da sincronia (ação tarefas-sync)"
grep -qF 'tarefas-sync) eval "$(popup_tt' "$TT" || falhou "a ação tarefas-sync do aviso não tem rota no notif_abrir"
em B --tarefa-add "t10 de B sem rede" >/dev/null; esperar
grep -qxF "t10 de B sem rede" <(local_de B) || falhou "sem rede, a tarefa nova deveria ficar na lista local"
ln -s "$R" "$T/atalho-b.git"
em B --tarefas-sync agora >/dev/null; esperar   # uma sincronia lenta de antes da rede voltar não pode reescrever o erro depois
saida=$(em B --tarefas-sync agora)
grep -q 'última troca: Hoje' <<<"$saida" && grep -q '✓' <<<"$saida" || falhou "voltando a rede, o estado deveria mostrar a troca ✓: $saida"
tem "$(no_repo)" "t10 de B sem rede" || falhou "a tarefa feita sem rede não foi ao repositório quando a rede voltou"
[[ -e $T/B/.local/state/tt/tarefas-git.erro ]] && falhou "o erro antigo deveria sumir depois de uma troca boa"
passou "falha de acesso aparece no estado e avisa uma vez; voltando a rede, segue sem perder nada"

# 9) Verbo: o endereço é conferido antes de gravar; modo inválido é recusado.
rc=0; saida=$(em A --tarefas-sync ambos "file://$T/nao-existe.git" 2>&1) || rc=$?
[[ $rc == 1 ]] && grep -q 'não consegui acessar' <<<"$saida" || falhou "endereço inacessível deveria ser recusado (rc=$rc): $saida"
grep -qxF "tarefas_repo=file://$R" "$T/A/.config/tt/config" && grep -qxF 'tarefas_sync=git' "$T/A/.config/tt/config" ||
  falhou "endereço recusado não pode mudar o config: $(cat "$T/A/.config/tt/config")"
em A --tarefas-sync p2p >/dev/null
[[ $(grep -c '^tarefas_sync=' "$T/A/.config/tt/config") == 1 ]] && grep -qxF 'tarefas_sync=p2p' "$T/A/.config/tt/config" ||
  falhou "mudar o modo deveria gravar uma linha só"
rc=0; em A --tarefas-sync xyz >/dev/null 2>&1 || rc=$?
[[ $rc == 2 ]] || falhou "modo inválido deveria sair com 2 (rc=$rc)"
saida=$(em A --tarefas-sync)
grep -q '^modo: P2P' <<<"$saida" && grep -q "^repositório: file://$R" <<<"$saida" || falhou "estado do verbo sem modo/repositório: $saida"
rc=0; saida=$(em A --tarefas-sync ambos 2>&1) || rc=$?
[[ $rc == 0 ]] && grep -q 'última troca: Hoje' <<<"$saida" || falhou "ambos com o endereço já gravado deveria sincronizar (rc=$rc): $saida"
passou "verbo --tarefas-sync confere o endereço, grava uma linha e recusa modo inválido"

# 10) Menu: ⋯ do painel e botão direito no 📋 levam à tela; a tela não trava sem terminal.
grep -qF '🔄 Sincronização das tarefas: $(tarefas_sync_rotulo)…' "$TT" || falhou "menu ⋯ do painel sem o item 🔄"
grep -qF '🔄 Sincronização: $(tarefas_sync_rotulo)…' "$TT" || falhou "botão direito do 📋 sem o item 🔄"
grep -Fq -- '--tarefas-sync-ui) tarefas_sync_ui' "$TT" || falhou "rota --tarefas-sync-ui ausente"
setsid -w timeout 10 env HOME="$T/A" XDG_CONFIG_HOME="$T/A/.config" TT_RT="$T/A/rt" "$TT" --tarefas-sync-ui </dev/null >/dev/null 2>&1 ||
  falhou "a tela da sincronia travou ou falhou sem terminal"
passou "menu ⋯ e botão direito do 📋 têm o item; a tela abre"

# 11) A tela de verdade (tmux isolado): escolhe o endereço, confere, liga "ambos" e sincroniza.
command -v fzf >/dev/null || { echo "pulado: sem fzf para a tela"; echo "TODOS OS TESTES PASSARAM"; exit 0; }
maq C ""; sed -i '/^tarefas_repo=/d; s/^tarefas_sync=.*/tarefas_sync=p2p/' "$T/C/.config/tt/config"
tmux -f /dev/null new -d -s ui -x 63 -y 30 "env HOME=$T/C XDG_CONFIG_HOME=$T/C/.config TT_RT=$T/C/rt $TT --tarefas-sync-ui; sleep 30"
tela() { tmux capture-pane -p -t ui; }
ver() { local i; for ((i = 0; i < 40; i++)); do tela | grep -q -- "$1" && return 0; sleep 0.25; done; falhou "a tela não mostrou '$1': $(tela)"; }
ver 'Sincronização das tarefas desta máquina'; ver '✓ P2P'
for i in 1 2 3 4 5; do tmux send-keys -t ui Down; done; sleep 0.3   # p2p ambos git off - [e]
tmux send-keys -t ui Enter; ver 'Endereço:'
tmux send-keys -t ui "file://$R" Enter; ver 'acesso conferido'
tmux send-keys -t ui q; ver 'Sincronização das tarefas desta máquina'; ver 'repositório: file://'; sleep 0.5
tmux send-keys -t ui Down; sleep 0.3; tmux send-keys -t ui Enter; ver 'última troca: Hoje'   # 2º item: "Ambos"
grep -qxF 'tarefas_sync=ambos' "$T/C/.config/tt/config" || falhou "a tela não gravou o modo ambos: $(cat "$T/C/.config/tt/config")"
tem "$(local_de C)" "t1 de A" || falhou "ligado pela tela, C não recebeu as tarefas do repositório"
tmux kill-session -t ui
passou "tela 🔄 (63 colunas): endereço conferido, ambos ligado, tarefas recebidas"

echo "TODOS OS TESTES PASSARAM"
