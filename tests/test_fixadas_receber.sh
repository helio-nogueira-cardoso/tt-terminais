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
  echo "$1" >"$CF.v"; rm -f "$CF.prev" "$LOG"
}
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
echo "ok: test_fixadas_receber"
