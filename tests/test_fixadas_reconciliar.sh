#!/usr/bin/env bash
# Fixada local só some quando o tmux respondeu e a ausência se confirmou (ou foi fechada pelo tt);
# tmux fora do ar nunca remove nada, e toda remoção deixa rastro em ~/.cache/tt-fixadas.log.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
source "$(dirname "$0")/tmux-isolado.sh"
mkdir -p "$D/home/.config/tt" "$D/cache"
printf 'nome=m1\n' >"$D/home/.config/tt/config"
LOG=$D/home/.cache/tt-fixadas.log
falhou() { echo "FALHOU: $*" >&2; exit 1; }
rodar() { # [VAR=1] -> reconcilia com o tmux atual do teste
  env HOME="$D/home" XDG_CONFIG_HOME="$D/home/.config" TT_MACHINE=m1 TT_SO_CARREGAR=1 "$@" \
    bash -c 'source "$1"; reconciliar_fixadas' _ "$ROOT/tt" >/dev/null 2>&1
}
n() { grep -c . "$D/home/.config/tt/fixadas" 2>/dev/null || echo 0; }

# tmux de mentira: sessões em $D/sessoes ("nome<TAB>id"); com $D/fora existindo, é um servidor fora do ar.
mkdir -p "$D/bin"
cat >"$D/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
[[ -e $TT_T_DIR/fora ]] && { echo "no server running" >&2; exit 1; }
[[ ${1:-} == -u ]] && shift   # o wrapper do tt passa -u (UTF-8) antes do comando, como o tmux de verdade aceita
case ${1:-} in
  list-sessions) while IFS=$'\t' read -r n i; do printf '%s\t%s\n' "$n" "$i"; done <"$TT_T_DIR/sessoes" ;;
  has-session) n=${3#=}; cut -f1 "$TT_T_DIR/sessoes" | grep -qxF "$n" ;;
  show-options) n=${@: -2:1}; n=${n#=}; n=${n%:}; awk -F'\t' -v n="$n" '$1==n{print $2}' "$TT_T_DIR/sessoes" ;;
  *) exit 0 ;;
esac
TMUX
chmod +x "$D/bin/tmux"; export TT_T_DIR=$D PATH="$D/bin:$PATH"
printf 'viva\tidviva\n' >"$D/sessoes"; id=idviva
printf 'm1\tviva\t%s\nm1\tfechada\tidfechada\n' "$id" >"$D/home/.config/tt/fixadas"

# 1) 1ª conferência: a ausente é preservada (aguarda confirmar)
rodar; [[ $(n) == 2 ]] || falhou "1ª conferência removeu: $(cat "$D/home/.config/tt/fixadas")"
grep -q 'preservada m1:fechada' "$LOG" || falhou "sem rastro de preservação"
# 2) 2ª conferência seguida: remove, com rastro
rodar; [[ $(n) == 1 ]] || falhou "2ª conferência não removeu"
grep -q 'removida m1:fechada' "$LOG" || falhou "sem rastro de remoção"
grep -q 'm1.viva' "$D/home/.config/tt/fixadas" || falhou "perdeu a viva"

# 3) fechar pelo tt (imediato) remove já na 1ª
printf 'm1\tviva\t%s\nm1\toutra\tidoutra\n' "$id" >"$D/home/.config/tt/fixadas"
rodar TT_RECONC_IMEDIATO=1; [[ $(n) == 1 ]] || falhou "imediato não removeu"

# 4) tmux fora do ar: nunca remove, nem na 2ª, nem no modo imediato
printf 'm1\tviva\t%s\nm1\toutra\tidoutra\n' "$id" >"$D/home/.config/tt/fixadas"
: >"$D/fora"
rodar; rodar; rodar TT_RECONC_IMEDIATO=1
[[ $(n) == 2 ]] || falhou "removeu com o tmux fora do ar"
grep -q 'tmux sem resposta' "$LOG" || falhou "sem rastro do tmux fora do ar"
echo ok
