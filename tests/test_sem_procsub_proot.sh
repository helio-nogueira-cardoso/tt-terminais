#!/usr/bin/env bash
# O proot do celular (proot-distro) liga /proc/self/fd em /dev/fd na hora de abrir o proot, então o /dev/fd de dentro é o
# do lançador, não o do processo: toda substituição de processo (< <(cmd), cat <(cmd)) falha com
# "/dev/fd/63: No such file or directory". As funções que o vigia, a barra e a malha chamam no s23 usam here-string
# (<<<"$(cmd)"), com guarda contra a linha vazia que a here-string cria quando a saída é vazia.
# (tarefa role69, 16/11/2026: tt --malha, --email-listar, --barra-fixadas, vigia)
source "$(dirname "$0")/lib.sh"; isolar

# 1) O tt inteiro não usa substituição de processo, salvo as exceções abaixo: comentário, regex de \<( e o clique do Python, e
#    o fzf da central (precisa começar a desenhar antes de a lista acabar; lá o proot não é usado).
sobras=$(grep -n '<(' "$TT" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -vE "rb'.x1b" | grep -vF '\<(' |
         grep -vF -- '--track --bind="load:transform($EU --atualizar-uma-vez)" < <(lista_rapida_central)' |
         grep -vE '# arquivo, não < <\(find -print0\)' || true)
[[ -z $sobras ]] || falhou "o tt voltou a usar substituição de processo (< <(...)): $(head -3 <<<"$sobras" | cut -c1-120)"

# 2) Sem outras máquinas (maquinas vazio) a here-string não cria uma volta com destino vazio.
export TT_SO_CARREGAR=1
saida=$(bash -c 'source "$1"; ecoa() { echo "CHAMOU[$1][$2]"; }; nas_maquinas ecoa' _ "$TT" 2>&1)
[[ -z $saida ]] || falhou "nas_maquinas chamou a função sem nenhuma máquina cadastrada: $saida"

# 3) Sem tarefa com prazo, o lembrete não avisa nada (chave vazia nunca vira aviso).
saida=$(bash -c 'source "$1"; tarefas_notificar() { echo "AVISOU[$*]"; }; tarefas_lembrete' _ "$TT" 2>&1)
[[ -z $saida ]] || falhou "tarefas_lembrete avisou sem tarefa: $saida"

# 4) Sem fixadas, a barra desenha só o marcador (nenhum item vazio).
unset TT_SO_CARREGAR
b=$("$TT" --barra-fixadas 2>/dev/null | sed 's/#\[[^]]*\]//g')
[[ $b == *'range'* || $b == *'✕'* ]] && falhou "barra das fixadas desenhou um item sem nenhuma fixada: $b"

# 5) E com fixadas continua desenhando (nome e ✕).
tmux -f /dev/null new -d -s alfa 'sleep 600'
"$TT" --fixar alfa >/dev/null
b=$("$TT" --barra-fixadas 2>/dev/null | sed 's/#\[[^]]*\]//g')
[[ $b == *alfa* && $b == *'✕'* ]] || falhou "barra das fixadas não desenhou a sessão fixada: $b"
passou
