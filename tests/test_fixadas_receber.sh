#!/usr/bin/env bash
# Lista de fixadas recebida de outra máquina (receber_fixadas): uma lista VAZIA mais nova que apagaria 2+ fixadas de uma vez é
# recusada. O puxar_fixadas lê o arquivo remoto por ssh sem checar o retorno: um cat vazio (ssh que caiu, arquivo no meio da
# regravação) chegava como "lista vazia nova" e desafixava tudo daqui. Desafixar a ÚLTIMA continua valendo (1 → 0), e toda
# redução guarda a lista anterior em fixadas.prev e deixa rastro em ~/.cache/tt-fixadas.log.
# Candidato a causa do clique em fixada que leva a outra sessão ou a lugar nenhum: sem reprodução real do clique, este teste
# NÃO afirma que cobre o sintoma, só que a lista não some por uma leitura vazia.
# Também cobre um furo que já existia: sem SSH_CLIENT (o puxar_fixadas roda local) o set -u abortava receber_fixadas na primeira
# lista menor, deixando a lista antiga e a trava presa; o teste roda sem a variável de propósito.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
source "$(dirname "$0")/tmux-isolado.sh"
mkdir -p "$D/home/.config/tt" "$D/bin"
printf 'nome=m1\n' >"$D/home/.config/tt/config"
CF=$D/home/.config/tt/fixadas; LOG=$D/home/.cache/tt-fixadas.log
falhou() { echo "FALHOU: $*" >&2; exit 1; }
# tmux de mentira: sem servidor (o aplicar_fixadas volta cedo, sem tocar em nada)
printf '#!/usr/bin/env bash\nexit 1\n' >"$D/bin/tmux"; chmod +x "$D/bin/tmux"; export PATH="$D/bin:$PATH"
# receber V ARQUIVO [VAR=valor...]: roda receber_fixadas com a lista do ARQUIVO no stdin. SSH_CLIENT sai do ambiente (o puxar_fixadas roda
# local, sem ssh, e quem roda este teste pode estar numa sessao ssh): com set -u, ${SSH_CLIENT%% *} abortava a funcao nas reducoes.
receber() {
  local v=$1 arq=$2; shift 2
  env -u SSH_CLIENT HOME="$D/home" XDG_CONFIG_HOME="$D/home/.config" TT_MACHINE=m1 TT_SO_CARREGAR=1 "$@" \
    bash -c 'source "$1"; receber_fixadas "$2"' _ "$ROOT/tt" "$v" <"$arq" >/dev/null 2>&1
}
n() { local c; c=$(grep -vc '^[[:space:]]*$' "$1" 2>/dev/null); echo "${c:-0}"; }  # grep -c sai com 1 quando conta 0
ver() { cat "$CF.v" 2>/dev/null || echo 0; }
local_com() { # V N: lista local com N fixadas na versão V (e sem o .prev de um caso anterior)
  : >"$CF"; local i; for ((i = 1; i <= $2; i++)); do printf 'm1\ts%s\tid%s\n' "$i" "$i" >>"$CF"; done
  echo "$1" >"$CF.v"; rm -f "$CF.prev" "$CF.recusada" "$LOG" "$CAP"/envio.*
}
# ssh de mentira: guarda o comando remoto (envio.XXXX.cmd) e a lista que seguiria no stdin (envio.XXXX)
CAP=$D/cap; mkdir -p "$CAP"
printf '#!/usr/bin/env bash\n[[ -n ${ATRASO:-} ]] && sleep "$ATRASO"\nf=$(mktemp "$CAP/envio.XXXXXX"); printf "%%s\\n" "$*" >"$f.cmd"; cat >"$f"; exit 0\n' >"$D/bin/ssh"; chmod +x "$D/bin/ssh"
# propagar: roda propagar_fixadas em processo novo (vale como reinício) com dois destinos de mentira
propagar() { # [VAR=valor...]
  env -u SSH_CLIENT HOME="$D/home" XDG_CONFIG_HOME="$D/home/.config" TT_MACHINE=m1 TT_SO_CARREGAR=1 CAP="$CAP" "$@" \
    bash -c 'source "$1"; maquinas() { printf "dest1\tm2\ndest2\tm3\n"; }; propagar_fixadas' _ "$ROOT/tt" >/dev/null 2>&1
}
# propagar_gancho versao|maquinas: no ponto indicado da propagação, outro processo faria a recusa da vazia v200 e uma mudança local (a versão sobe
# para 999); aqui o gancho faz as duas coisas na hora, e a ordem fica exata
propagar_gancho() {
  env -u SSH_CLIENT HOME="$D/home" XDG_CONFIG_HOME="$D/home/.config" TT_MACHINE=m1 TT_SO_CARREGAR=1 CAP="$CAP" GANCHO="$1" \
    bash -c 'source "$1"
      gancho() { receber_fixadas 200 </dev/null; echo 999 >"$CONF_FIX.v"; }
      maquinas() { [[ $GANCHO == maquinas ]] && gancho; printf "dest1\tm2\ndest2\tm3\n"; }
      if [[ $GANCHO == versao ]]; then
        eval "orig_$(declare -f versao_fixadas)"
        versao_fixadas() { versao_fixadas() { orig_versao_fixadas; }; gancho; orig_versao_fixadas; }
      fi
      propagar_fixadas' _ "$ROOT/tt" >/dev/null 2>&1
}
envios() { # N: espera até 5 s pelos N envios do ssh falso e diz quantos chegaram
  local i c=0; for ((i = 0; i < 50; i++)); do c=$(ls "$CAP" 2>/dev/null | grep -vc '\.cmd$'); ((c >= $1)) && break; sleep 0.1; done; echo "$c"
}
nada_enviado() { sleep 1; [[ -z $(ls "$CAP") ]]; } # ausência não tem o que esperar: o ssh sairia em segundo plano, então dá 1 s antes de concluir
listas_enviadas() { local f; for f in "$CAP"/envio.*; do case $f in *.cmd) ;; *) n "$f" ;; esac; done | tr '\n' ' '; }
: >"$D/vazia"
printf 'm1\tnova\tidnova\n' >"$D/uma"
printf 'm1\ta\tida\nm1\tb\tidb\nm1\tc\tidc\n' >"$D/tres"

# 1) vazia mais nova contra 3 locais: recusada (lista, versão e trava intactas, rastro no log, sem .prev)
local_com 100 3; receber 200 "$D/vazia"
[[ $(n "$CF") == 3 ]] || falhou "vazia nova apagou as 3 locais: $(cat "$CF")"
[[ $(ver) == 100 ]] || falhou "a versão mudou na recusa: $(ver)"
grep -q 'VAZIA recusada' "$LOG" || falhou "sem rastro da recusa: $(cat "$LOG" 2>/dev/null)"
[[ ! -d $CF.trava ]] || falhou "a recusa deixou a trava"
[[ ! -e $CF.prev ]] || falhou "a recusa não deveria gravar .prev"
[[ -z $(ls "$D/home/.config/tt" | grep -v -e '^config$' -e '^fixadas' ) ]] || falhou "sobrou arquivo temporário: $(ls "$D/home/.config/tt")"

# 2) vazia mais nova contra 2 locais: ainda recusada (o limite é 2+)
local_com 100 2; receber 200 "$D/vazia"
[[ $(n "$CF") == 2 && $(ver) == 100 ]] || falhou "vazia nova contra 2 locais não foi recusada"

# 3) vazia mais nova contra 1 local: aceita (desafixar a última é legítimo)
local_com 100 1; receber 200 "$D/vazia"
[[ $(n "$CF") == 0 && $(ver) == 200 ]] || falhou "desafixar a última foi recusado (n=$(n "$CF") v=$(ver))"

# 4) lista menor e não vazia: aceita, guarda a anterior em .prev e deixa rastro
local_com 100 3; receber 200 "$D/uma"
[[ $(n "$CF") == 1 && $(ver) == 200 ]] || falhou "lista menor não foi aceita (n=$(n "$CF") v=$(ver))"
[[ $(n "$CF.prev") == 3 ]] || falhou "o .prev não guardou as 3 anteriores: $(cat "$CF.prev" 2>/dev/null)"
grep -q 'tem 1 fixada(s) e a daqui tinha 3' "$LOG" || falhou "sem rastro da redução: $(cat "$LOG" 2>/dev/null)"

# 5) lista maior: aceita sem tocar no .prev
local_com 100 1; receber 200 "$D/tres"
[[ $(n "$CF") == 3 && $(ver) == 200 && ! -e $CF.prev ]] || falhou "lista maior (n=$(n "$CF") v=$(ver) prev=$([[ -e $CF.prev ]] && echo sim || echo nao))"

# 6) vazia com versão igual ou menor: ignorada como sempre (nem aceita nem recusada com rastro)
local_com 100 3; receber 100 "$D/vazia"; receber 50 "$D/vazia"
[[ $(n "$CF") == 3 && $(ver) == 100 ]] || falhou "versão velha mexeu na lista"
! grep -q 'VAZIA' "$LOG" 2>/dev/null || falhou "versão velha não deveria entrar na recusa"

# 7) depois de recusar uma vazia, a próxima lista não vazia e mais nova ainda é aceita
local_com 100 3; receber 200 "$D/vazia"; receber 300 "$D/uma"
[[ $(n "$CF") == 1 && $(ver) == 300 ]] || falhou "a recusa travou as listas seguintes (n=$(n "$CF") v=$(ver))"

# 8) sem ssh a funcao nao aborta (set -u): a lista menor foi aplicada e a trava saiu (era o furo do caso 4 no tt anterior)
[[ ! -d $CF.trava ]] || falhou "ficou a trava depois de aplicar lista menor sem SSH_CLIENT"
# 9) com SSH_CLIENT (a chamada por ssh de outra maquina), a origem vai ao rastro
local_com 100 3; receber 200 "$D/vazia" SSH_CLIENT="9.9.9.9 51234 22"
grep -q 'VAZIA recusada.*origem 9.9.9.9' "$LOG" || falhou "o rastro nao traz a origem do ssh: $(cat "$LOG" 2>/dev/null)"
[[ $(n "$CF") == 3 && $(ver) == 100 ]] || falhou "vazia nova chegando por ssh apagou as locais (n=$(n "$CF") v=$(ver))"

# 10) versão velha ou igual e desafixar a última não deixam pendência; a recusa deixa (a versão recusada)
local_com 100 3; receber 100 "$D/vazia"; receber 50 "$D/vazia"
[[ ! -e $CF.recusada ]] || falhou "versão velha criou pendência"
local_com 100 1; receber 200 "$D/vazia"
[[ ! -e $CF.recusada ]] || falhou "desafixar a última criou pendência"
local_com 100 3; receber 200 "$D/vazia"
[[ $(cat "$CF.recusada" 2>/dev/null) == 200 ]] || falhou "a recusa não gravou a pendência (v200): $(ls "$D/home/.config/tt")"

# 11) com a recusa pendente, uma mudança local (a versão sobe) NÃO envia a lista velha a nenhum destino, mesmo em outro processo
echo 999 >"$CF.v"
propagar
nada_enviado || falhou "propagou com recusa pendente: $(ls "$CAP")"
grep -q 'propagacao bloqueada: recusa pendente (v200)' "$LOG" || falhou "sem rastro do bloqueio: $(cat "$LOG" 2>/dev/null)"
[[ $(n "$CF") == 3 ]] || falhou "o bloqueio mexeu na lista daqui"

# 12) saída manual (fixadas e fixadas.v para o lado): a vazia v200 é aceita, a pendência some e só então se propaga, sem nada antigo
local_com 100 3; receber 200 "$D/vazia"
mkdir -p "$D/bk"; mv "$CF" "$CF.v" "$D/bk/"
receber 200 "$D/vazia"
[[ $(n "$CF") == 0 && $(ver) == 200 && ! -e $CF.recusada ]] || falhou "saída manual (n=$(n "$CF") v=$(ver) pend=$([[ -e $CF.recusada ]] && echo sim || echo nao))"
propagar
[[ $(envios 2) == 2 ]] || falhou "depois da saída manual deveria enviar aos 2 destinos (enviou $(envios 0))"
[[ $(listas_enviadas) == "0 0 " ]] || falhou "a saída manual republicou fixadas antigas: $(listas_enviadas)"
cat "$CAP"/envio.*.cmd | grep -c -- '--receber-fixadas 200$' | grep -qx 2 || falhou "versão enviada diferente de 200: $(cat "$CAP"/envio.*.cmd)"
[[ $(n "$D/bk/fixadas") == 3 && $(cat "$D/bk/fixadas.v") == 100 ]] || falhou "o backup mudou"

# 13) reversão: devolver o backup volta ao estado inicial e a vazia v200 é recusada de novo, com a pendência e o bloqueio
mv -f "$D/bk/fixadas" "$CF"; mv -f "$D/bk/fixadas.v" "$CF.v"; rm -f "$CAP"/envio.*
receber 200 "$D/vazia"
[[ $(n "$CF") == 3 && $(ver) == 100 && $(cat "$CF.recusada" 2>/dev/null) == 200 ]] || falhou "reversão (n=$(n "$CF") v=$(ver))"
propagar
nada_enviado || falhou "propagou depois da reversão: $(ls "$CAP")"

# 14) recuperação por lista nova não vazia: aceita, a pendência some e a propagação volta (com a lista recebida, 1 linha)
local_com 100 3; receber 200 "$D/vazia"; receber 300 "$D/uma"
[[ $(n "$CF") == 1 && $(ver) == 300 && ! -e $CF.recusada ]] || falhou "lista nova não limpou a pendência (n=$(n "$CF") v=$(ver))"
propagar
[[ $(envios 2) == 2 && $(listas_enviadas) == "1 1 " ]] || falhou "propagação não voltou: $(listas_enviadas)"

# 15) sem pendência (desafixar a última aceito) a propagação segue normal: 2 destinos, lista vazia, a versão aceita
local_com 100 1; receber 200 "$D/vazia"
propagar
[[ $(envios 2) == 2 && $(listas_enviadas) == "0 0 " ]] || falhou "propagação normal quebrou: $(listas_enviadas)"
# 16) uma lista intermediária (mais nova que a daqui, mais velha que a recusada) é aceita, mas NÃO limpa a pendência; versão velha também não
local_com 100 3; receber 200 "$D/vazia"; receber 50 "$D/uma"
[[ $(cat "$CF.recusada" 2>/dev/null) == 200 && $(n "$CF") == 3 ]] || falhou "versão velha mexeu na pendência ou na lista"
receber 150 "$D/uma"
[[ $(n "$CF") == 1 && $(ver) == 150 && $(cat "$CF.recusada" 2>/dev/null) == 200 ]] || falhou "a intermediária limpou a pendência (n=$(n "$CF") v=$(ver) pend=$(cat "$CF.recusada" 2>/dev/null))"
echo 999 >"$CF.v"; propagar
nada_enviado || falhou "propagou com a pendência ainda aberta depois de uma intermediária: $(ls "$CAP")"
echo 150 >"$CF.v"; receber 300 "$D/uma"
[[ ! -e $CF.recusada && $(ver) == 300 ]] || falhou "a lista tão nova quanto a recusada não limpou a pendência"

# 17) ordem exata, recusa + mudança local ANTES da leitura da versão: a versão lida é a de depois e a pendência já existe, então não envia (dois destinos)
local_com 100 3
propagar_gancho versao
[[ $(cat "$CF.recusada" 2>/dev/null) == 200 ]] || falhou "o gancho não recusou (pend=$(cat "$CF.recusada" 2>/dev/null))"
nada_enviado || falhou "enviou a lista velha com a versão nova (recusa antes da leitura da versão): $(cat "$CAP"/envio.*.cmd 2>/dev/null)"

# 18) recusa + mudança local NO MEIO da volta dos destinos: nenhum dos dois recebe
local_com 100 3
propagar_gancho maquinas
[[ $(cat "$CF.recusada" 2>/dev/null) == 200 ]] || falhou "o gancho não recusou"
nada_enviado || falhou "enviou depois da recusa, no meio da volta: $(cat "$CAP"/envio.*.cmd 2>/dev/null)"

# 19) envio já iniciado antes da recusa que termina depois dela: leva a versão de antes (100, menor que a recusada 200) e a lista de antes,
# então as máquinas que já têm a v200 o ignoram; e nenhum envio novo sai depois
local_com 100 3
propagar ATRASO=1
receber 200 "$D/vazia"; echo 999 >"$CF.v"
[[ $(envios 2) == 2 ]] || falhou "os 2 envios já iniciados deveriam terminar (chegaram $(envios 0))"
[[ $(cat "$CAP"/envio.*.cmd | grep -c -- '--receber-fixadas 100$') == 2 && $(listas_enviadas) == "3 3 " ]] || falhou "envio iniciado antes da recusa com versão/lista inesperada: $(cat "$CAP"/envio.*.cmd) / $(listas_enviadas)"
propagar; sleep 1
[[ $(envios 0) == 2 ]] || falhou "saiu envio novo depois da recusa (agora $(envios 0))"
echo "ok: test_fixadas_receber"
