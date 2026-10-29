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
passou() { echo "  ok $*"; }   # o que foi observado nos casos 26-29, para a saída crua mostrar o estado e não só o veredito
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
# 20) falha fechada: se a pendência não puder ser gravada (aqui, um diretório com o nome do temporário), a vazia é ACEITA em vez de recusada sem
# bloqueio: a lista daqui iguala a das outras e a propagação leva a lista nova, sem nada antigo
local_com 100 3; mkdir "$CF.recusada.novo"
receber 200 "$D/vazia"
[[ $(n "$CF") == 0 && $(ver) == 200 && ! -e $CF.recusada ]] || falhou "pendência não gravável: a lista não foi igualada (n=$(n "$CF") v=$(ver) pend=$([[ -e $CF.recusada ]] && echo sim || echo nao))"
grep -q 'VAZIA aceita: nao deu para gravar a pendencia' "$LOG" || falhou "sem rastro da recusa que não pôde ser gravada: $(cat "$LOG" 2>/dev/null)"
propagar
[[ $(envios 2) == 2 && $(listas_enviadas) == "0 0 " ]] || falhou "depois da falha de gravação saiu estado antigo: $(listas_enviadas)"
rmdir "$CF.recusada.novo"

# 21) morrer (SIGKILL) logo depois de gravar a pendência, no primeiro log da recusa, deixa a pendência: a propagação segue bloqueada
local_com 100 3
{ env -u SSH_CLIENT HOME="$D/home" XDG_CONFIG_HOME="$D/home/.config" TT_MACHINE=m1 TT_SO_CARREGAR=1 \
    bash -c 'source "$1"; fixadas_log() { kill -9 $$; }; receber_fixadas 200' _ "$ROOT/tt" </dev/null >/dev/null 2>&1; } 2>/dev/null || true
[[ $(cat "$CF.recusada" 2>/dev/null) == 200 && $(n "$CF") == 3 && $(ver) == 100 ]] || falhou "a morte depois de gravar perdeu a pendência (pend=$(cat "$CF.recusada" 2>/dev/null) n=$(n "$CF") v=$(ver))"
rmdir "$CF.trava" 2>/dev/null   # a trava ficou com o processo que morreu (sai sozinha em 20 s)
echo 999 >"$CF.v"; propagar
nada_enviado || falhou "propagou depois da morte com a pendência gravada: $(ls "$CAP")"
# 22) a pendência guarda a MAIOR versão recusada: 100 → recusa 300 → recusa 200 mantém 300; uma lista 250 é aceita mas não limpa; 350 limpa
local_com 100 3; receber 300 "$D/vazia"; receber 200 "$D/vazia"
[[ $(cat "$CF.recusada" 2>/dev/null) == 300 ]] || falhou "recusa menor rebaixou a pendência (pend=$(cat "$CF.recusada" 2>/dev/null))"
receber 250 "$D/uma"
[[ $(n "$CF") == 1 && $(ver) == 250 && $(cat "$CF.recusada" 2>/dev/null) == 300 ]] || falhou "a 250 limpou a pendência 300 (n=$(n "$CF") v=$(ver) pend=$(cat "$CF.recusada" 2>/dev/null))"
echo 999 >"$CF.v"; propagar
nada_enviado || falhou "propagou com a recusa 300 ainda sem reconciliar: $(ls "$CAP")"
echo 250 >"$CF.v"; receber 350 "$D/tres"
[[ ! -e $CF.recusada ]] || falhou "a 350 (acima da maior recusada) não limpou a pendência"

# 23) queda entre gravar fixadas.v e remover a pendência: a reexecução idêntica da lista aplicada limpa se a versão daqui alcança a recusada, e não limpa
# se a pendência é maior que a versão daqui
local_com 250 1; cp "$CF" "$D/aplicada"; echo 200 >"$CF.recusada"   # estado pós-queda: lista e versão 250 gravadas, pendência 200 ficou
receber 250 "$D/aplicada"
[[ ! -e $CF.recusada ]] || falhou "a reexecução idêntica não limpou a pendência 200 com a versão daqui em 250"
local_com 250 1; cp "$CF" "$D/aplicada"; echo 300 >"$CF.recusada"
receber 250 "$D/aplicada"
[[ $(cat "$CF.recusada" 2>/dev/null) == 300 ]] || falhou "a reexecução limpou uma pendência (300) maior que a versão daqui (250)"
echo 999 >"$CF.v"; propagar
nada_enviado || falhou "propagou com a pendência 300 aberta: $(ls "$CAP")"

# 24) uma edição local (versão acima da recusada) não limpa a pendência, nem com lista velha nem com a mesma versão e outro conteúdo
local_com 100 3; receber 200 "$D/vazia"
echo 999 >"$CF.v"
receber 150 "$D/uma"
[[ $(cat "$CF.recusada" 2>/dev/null) == 200 ]] || falhou "edição local + lista velha limparam a pendência (pend=$(cat "$CF.recusada" 2>/dev/null))"
receber 999 "$D/uma"   # mesma versão que a daqui, conteúdo diferente (daqui 3 linhas, recebida 1)
[[ $(cat "$CF.recusada" 2>/dev/null) == 200 && $(n "$CF") == 3 ]] || falhou "versão igual com conteúdo diferente limpou a pendência ou mexeu na lista"
propagar
nada_enviado || falhou "propagou com a pendência 200 aberta depois de edição local: $(ls "$CAP")"
# 25) sequência do Pedro Estevão: local 100 → recusa 300 → alteração local (999) → recebe a lista 250 → propaga: a recusa 300 continua e nada sai
local_com 100 3; receber 300 "$D/vazia"
echo 999 >"$CF.v"   # alteração local: a versão sobe para 999, sem aceitar nada remoto
receber 250 "$D/uma"
[[ $(cat "$CF.recusada" 2>/dev/null) == 300 && $(n "$CF") == 3 && $(ver) == 999 ]] || falhou "a 250 após a alteração local mexeu na pendência, na lista ou na versão (pend=$(cat "$CF.recusada" 2>/dev/null) n=$(n "$CF") v=$(ver))"
propagar
nada_enviado || falhou "propagou depois da alteração local + lista 250 com a recusa 300 aberta: $(ls "$CAP")"
# 26) o envio já iniciado antes da recusa (caso 19) chega a um destino atrasado (v50, 1 fixada) DEPOIS da recusa daqui: o destino aceita a v100, porque
# o envio foi decidido antes da v200 existir aqui (ordem válida), e quando a vazia v200 chegar a ele (pelo puxar_fixadas do vigia) também é recusada. O que se afirma é o estado final:
# nenhuma fixada some em nenhuma das duas máquinas e as duas ficam bloqueadas, sem que o destino fique com a v100 em silêncio
local_com 100 3
DST=$D/dest; mkdir -p "$DST/home/.config/tt"; printf 'nome=m2\n' >"$DST/home/.config/tt/config"; CFD=$DST/home/.config/tt/fixadas
printf 'm2\told\tidold\n' >"$CFD"; echo 50 >"$CFD.v"; rm -f "$CFD.prev" "$CFD.recusada"
propagar ATRASO=1
receber 200 "$D/vazia"
[[ $(envios 2) == 2 ]] || falhou "os envios iniciados antes da recusa não terminaram (chegaram $(envios 0))"
env_dest() { env -u SSH_CLIENT HOME="$DST/home" XDG_CONFIG_HOME="$DST/home/.config" TT_MACHINE=m2 TT_SO_CARREGAR=1 bash -c 'source "$1"; receber_fixadas "$2"' _ "$ROOT/tt" "$@"; }
env_dest 100 <"$(ls "$CAP"/envio.* | grep -v '\.cmd$' | head -1)" >/dev/null 2>&1
[[ $(n "$CFD") == 3 && $(cat "$CFD.v") == 100 ]] || falhou "o destino atrasado não recebeu o envio já decidido (n=$(n "$CFD") v=$(cat "$CFD.v" 2>/dev/null))"
# A v200 vazia vem de uma TERCEIRA máquina (m3) e chega ao destino pelo caminho real da volta: o vigia roda "tt --puxar-fixadas" ao iniciar e a cada 5 min;
# ele pergunta a versão de cada máquina por ssh, lê a lista da mais nova e entrega ao receber_fixadas por pipe. O ssh de mentira lê os ARQUIVOS das
# máquinas declaradas: m1 = a origem montada acima ($D/home: v100, 3 fixadas, pendência 200) e m3 = $M3 (vazia, v200); INDISP lista as que não respondem.
M3=$D/m3home; mkdir -p "$M3/.config/tt" "$D/sshpull"; : >"$M3/.config/tt/fixadas"; echo 200 >"$M3/.config/tt/fixadas.v"
cat >"$D/sshpull/ssh" <<'EOS'
#!/usr/bin/env bash
a=("$@"); host=${a[${#a[@]}-2]}; cmd=${a[${#a[@]}-1]}
[[ ,${INDISP:-}, == *",$host,"* ]] && exit 255
case $host in m1) h=$HOME_M1 ;; m3) h=$HOME_M3 ;; *) exit 255 ;; esac
case $cmd in
  *fixadas.v*) cat "$h/.config/tt/fixadas.v" 2>/dev/null || echo 0 ;;
  *) cat "$h/.config/tt/fixadas" 2>/dev/null ;;
esac
EOS
chmod +x "$D/sshpull/ssh"
dest_env() { env -u SSH_CLIENT HOME="$DST/home" XDG_CONFIG_HOME="$DST/home/.config" TT_MACHINE=m2 TT_SO_CARREGAR=1 HOME_M1="$D/home" HOME_M3="$M3" "$@"; }
puxar_dest() { # [MAQUINAS_FORA]
  dest_env INDISP="${1:-}" PATH="$D/sshpull:$PATH" bash -c 'source "$1"; maquinas() { printf "m1\tm1\nm3\tm3\n"; }; puxar_fixadas' _ "$ROOT/tt" >/dev/null 2>&1
}
propagar_dest() { dest_env CAP="$CAP" bash -c 'source "$1"; maquinas() { printf "p1\tm1\np3\tm3\n"; }; propagar_fixadas' _ "$ROOT/tt" >/dev/null 2>&1; }
# 26a) m3 responde: o destino lê a v200 vazia da m3, recusa e fica bloqueado como a origem (nada novo sai dele)
rm -f "$CAP"/envio.*
puxar_dest
[[ $(n "$CFD") == 3 && $(cat "$CFD.recusada" 2>/dev/null) == 200 && $(n "$CF") == 3 && $(cat "$CF.recusada" 2>/dev/null) == 200 ]] || falhou "26a: estado final: destino n=$(n "$CFD") pend=$(cat "$CFD.recusada" 2>/dev/null); origem n=$(n "$CF") pend=$(cat "$CF.recusada" 2>/dev/null)"
propagar_dest
nada_enviado || falhou "26a: o destino com a pendência 200 propagou: $(cat "$CAP"/envio.*.cmd 2>/dev/null)"
passou "26a (m3 no ar): m2 leu a v200 vazia da m3 e recusou: pendência=$(cat "$CFD.recusada") fixadas=$(n "$CFD"); nada propagou (envios=$(ls "$CAP" | grep -vc '\.cmd$'))"
# 26b) m3 fora do ar: o destino (v100, 3 fixadas) não viu a v200 e não tem como recusá-la. O bloqueio é LOCAL, de quem recebeu a v200 (a origem, por exemplo), e
# NÃO se estende ao destino: ele continua propagando a v100, que as máquinas que já têm a v200 ignoram (versão menor). Contrato registrado, não escondido.
rm -f "$CFD.recusada" "$CAP"/envio.*
puxar_dest m3
[[ ! -e $CFD.recusada && $(n "$CFD") == 3 && $(cat "$CFD.v") == 100 ]] || falhou "26b: com a m3 fora o destino mudou (n=$(n "$CFD") v=$(cat "$CFD.v" 2>/dev/null) pend=$([[ -e $CFD.recusada ]] && echo sim || echo nao))"
propagar_dest
[[ $(envios 2) == 2 && $(cat "$CAP"/envio.*.cmd | grep -c -- '--receber-fixadas 100$') == 2 ]] || falhou "26b: com a m3 fora o destino sem pendência deveria propagar a v100 (envios=$(envios 0); $(cat "$CAP"/envio.*.cmd 2>/dev/null))"
passou "26b (m3 fora): m2 sem pendência, v$(cat "$CFD.v"), fixadas=$(n "$CFD"); propagou aos 2 destinos (destino v<versão>): $(awk '{for (i = 1; i <= NF; i++) if ($i ~ /^p[0-9]+$/) d = $i; printf "%s v%s; ", d, $NF}' "$CAP"/envio.*.cmd)"

# 27) interrupção REAL (SIGKILL) com tmux de verdade: o que se confere é o estado das sessões (@tt_fixada, o 📌), não um arquivo-marcador.
# A pendência só sai DEPOIS de a lista ser aplicada às sessões; morrer antes de aplicar ou antes de remover deixa a pendência (propagação bloqueada)
# e a reexecução idêntica aplica e remove. Sessões: "nova" está na lista recebida; "velha" estava fixada e sai dela.
RP=${PATH#"$D/bin:"}   # o PATH sem o tmux de mentira: aqui o tmux é o isolado do tmux-isolado.sh
rtmux() { PATH=$RP tmux "$@"; }
marca() { rtmux show-options -qv -t "=$1:" @tt_fixada 2>/dev/null; }
rtmux -f /dev/null new -d -s nova 'sleep 600'; rtmux new -d -s velha 'sleep 600'
estado_antigo() { rtmux set -q -u -t =nova: @tt_fixada; rtmux set -q -t =velha: @tt_fixada 1; }
com_tmux() { # CÓDIGO_DO_BASH [V]: roda receber_fixadas V (250) com a lista $LISTA ("uma"), tmux de verdade, depois de CÓDIGO (funções trocadas)
  env -u SSH_CLIENT HOME="$D/home" XDG_CONFIG_HOME="$D/home/.config" TT_MACHINE=m1 TT_SO_CARREGAR=1 PATH="$RP" \
    bash -c 'source "$1"; eval "$2"; receber_fixadas "$3"' _ "$ROOT/tt" "$1" "${2:-250}" <"${LISTA:-$D/uma}" >/dev/null 2>&1
}
# 27a) morre ANTES de aplicar
local_com 100 3; estado_antigo
receber 200 "$D/vazia"
{ com_tmux 'aplicar_fixadas() { kill -9 $$; }'; } 2>/dev/null || true
rmdir "$CF.trava" 2>/dev/null
[[ $(n "$CF") == 1 && $(ver) == 250 && $(cat "$CF.recusada" 2>/dev/null) == 200 && -z $(marca nova) && $(marca velha) == 1 ]] || falhou "27a: estado depois da morte antes de aplicar (n=$(n "$CF") v=$(ver) pend=$(cat "$CF.recusada" 2>/dev/null) nova=[$(marca nova)] velha=[$(marca velha)])"
propagar
nada_enviado || falhou "27a: propagou com a pendência 200 aberta: $(ls "$CAP")"
com_tmux ''
[[ ! -e $CF.recusada && $(marca nova) == 1 && -z $(marca velha) ]] || falhou "27a: a reexecução idêntica não aplicou e limpou (pend=$([[ -e $CF.recusada ]] && echo sim || echo nao) nova=[$(marca nova)] velha=[$(marca velha)])"
passou "27a (SIGKILL antes de aplicar): a pendência ficou e bloqueou o envio; a reexecução aplicou e removeu: nova=[$(marca nova)] velha=[$(marca velha)] pendência=$([[ -e $CF.recusada ]] && echo sim || echo nao)"
# 27b) morre DEPOIS de aplicar e ANTES de remover a pendência
local_com 100 3; estado_antigo
receber 200 "$D/vazia"
{ com_tmux 'rm() { [[ "$*" == *.recusada ]] && kill -9 $$; command rm "$@"; }'; } 2>/dev/null || true
rmdir "$CF.trava" 2>/dev/null
[[ $(cat "$CF.recusada" 2>/dev/null) == 200 && $(marca nova) == 1 && -z $(marca velha) ]] || falhou "27b: estado depois da morte antes de remover (pend=$(cat "$CF.recusada" 2>/dev/null) nova=[$(marca nova)] velha=[$(marca velha)])"
propagar
nada_enviado || falhou "27b: propagou com a pendência 200 aberta: $(ls "$CAP")"
com_tmux ''
[[ ! -e $CF.recusada && $(marca nova) == 1 && -z $(marca velha) ]] || falhou "27b: a reexecução não removeu a pendência (nova=[$(marca nova)] velha=[$(marca velha)])"
passou "27b (SIGKILL entre aplicar e remover): a pendência ficou e bloqueou o envio; a reexecução a removeu: nova=[$(marca nova)] velha=[$(marca velha)] pendência=$([[ -e $CF.recusada ]] && echo sim || echo nao)"
# 27c) a reexecução idêntica SEM pendência não reaplica nada
estado_antigo; com_tmux ''
[[ $(marca velha) == 1 && -z $(marca nova) ]] || falhou "27c: a reexecução idêntica sem pendência reaplicou a lista (nova=[$(marca nova)] velha=[$(marca velha)])"
passou "27c (reexecução sem pendência): não reaplicou: nova=[$(marca nova)] velha=[$(marca velha)]"
# 27d) uma recusa nova (v300) que chega entre a aplicação e a remoção troca a pendência por 300: a remoção que esperava a 200 não a apaga
local_com 100 3; estado_antigo
receber 200 "$D/vazia"
LISTA=$D/tres com_tmux 'aplicar_fixadas() { receber_fixadas 300 </dev/null; }'
[[ $(cat "$CF.recusada" 2>/dev/null) == 300 && $(n "$CF") == 3 ]] || falhou "27d: a remoção da pendência 200 apagou a recusa 300 que chegou no meio (pend=$(cat "$CF.recusada" 2>/dev/null) n=$(n "$CF"))"
propagar
nada_enviado || falhou "27d: propagou com a recusa 300 aberta: $(ls "$CAP")"
passou "27d (recusa v300 no meio da aplicação): pendência=$(cat "$CF.recusada") fixadas=$(n "$CF"); nada propagou"
# 28) duas aplicações ao mesmo tempo: a A leu a lista antiga e demora para gravar as marcas (o gancho dorme no primeiro lote_add); no meio chega a lista nova e a
# B aplica tudo. A lista antiga não pode terminar por último e deixar "velha" fixada com a lista nova já em vigor
rtmux set -q -u -t =nova: @tt_fixada; rtmux set -q -u -t =velha: @tt_fixada
local_com 300 1; printf 'm1\tvelha\tidvelha\n' >"$CF"
env -u SSH_CLIENT HOME="$D/home" XDG_CONFIG_HOME="$D/home/.config" TT_MACHINE=m1 TT_SO_CARREGAR=1 PATH="$RP" \
  bash -c 'source "$1"; eval "orig_$(declare -f lote_add)"; lote_add() { sleep 2; orig_lote_add "$@"; }; aplicar_fixadas' _ "$ROOT/tt" </dev/null >/dev/null 2>&1 &
sleep 0.7   # a A já leu a lista antiga e está dormindo
printf 'm1\tnova\tidnova\n' >"$CF"; echo 301 >"$CF.v"
env -u SSH_CLIENT HOME="$D/home" XDG_CONFIG_HOME="$D/home/.config" TT_MACHINE=m1 TT_SO_CARREGAR=1 PATH="$RP" \
  bash -c 'source "$1"; aplicar_fixadas' _ "$ROOT/tt" </dev/null >/dev/null 2>&1
wait
[[ $(marca nova) == 1 && -z $(marca velha) ]] || falhou "28: a aplicação com a lista antiga terminou por último (nova=[$(marca nova)] velha=[$(marca velha)])"
passou "28 (duas aplicações ao mesmo tempo): a lista nova venceu: nova=[$(marca nova)] velha=[$(marca velha)]"
# 29) duas listas ACEITAS disputando as mesmas sessões, com a pendência da recusa no meio: a mais nova é o estado final. A primeira (v250: só "velha") é aceita e
# demora para gravar as marcas (gancho no primeiro lote_add); a segunda (v260: só "nova") chega no meio e aplica tudo. Depois, um replay da v260 não muda nada
rtmux set -q -u -t =nova: @tt_fixada; rtmux set -q -u -t =velha: @tt_fixada
local_com 100 3; receber 200 "$D/vazia"
printf 'm1\tvelha\tidvelha\n' >"$D/so_velha"
env -u SSH_CLIENT HOME="$D/home" XDG_CONFIG_HOME="$D/home/.config" TT_MACHINE=m1 TT_SO_CARREGAR=1 PATH="$RP" \
  bash -c 'source "$1"; eval "orig_$(declare -f lote_add)"; lote_add() { sleep 2; orig_lote_add "$@"; }; receber_fixadas 250' _ "$ROOT/tt" <"$D/so_velha" >/dev/null 2>&1 &
sleep 0.7   # a primeira já gravou a lista v250 e está dormindo antes de gravar as marcas
com_tmux '' 260
wait
[[ $(marca nova) == 1 && -z $(marca velha) && $(ver) == 260 && $(n "$CF") == 1 && ! -e $CF.recusada ]] || falhou "29: a lista mais nova não é o estado final (nova=[$(marca nova)] velha=[$(marca velha)] v=$(ver) n=$(n "$CF") pend=$([[ -e $CF.recusada ]] && echo sim || echo nao))"
com_tmux '' 260
[[ $(marca nova) == 1 && -z $(marca velha) && $(ver) == 260 ]] || falhou "29: o replay da v260 mudou o estado (nova=[$(marca nova)] velha=[$(marca velha)] v=$(ver))"
passou "29 (duas listas aceitas v250/v260 na mesma sessão, replay da v260): estado final nova=[$(marca nova)] velha=[$(marca velha)] versão=$(ver) fixadas=$(n "$CF")"
# 30) sem locale UTF-8 (cron/systemd/launchd): o \x1f dos -F tem de sobreviver (tmux -u no wrapper); sem isso a lista "nova__" não casa e nada é aplicado
rtmux set -q -u -t =nova: @tt_fixada; rtmux set -q -u -t =velha: @tt_fixada
local_com 100 3; receber 200 "$D/vazia"
LC_ALL=C LANG=C com_tmux '' 260
[[ $(marca nova) == 1 && -z $(marca velha) ]] || falhou "30: sem locale UTF-8 a lista não foi aplicada (nova=[$(marca nova)] velha=[$(marca velha)])"
passou "30 (LC_ALL=C, sem locale UTF-8): nova=[$(marca nova)] velha=[$(marca velha)]"
echo "ok: test_fixadas_receber"
