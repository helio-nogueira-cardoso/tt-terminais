#!/usr/bin/env bash
# Regressão: trap RETURN que cita uma variável local (a trava) ficava armado depois de a função voltar. Na
# partida rápida a função real roda dentro de um stub; quando o stub voltava, o trap disparava de novo sem a
# variável e o set -u derrubava o verbo ("trava: unbound variable"): tt --malha morria antes de mostrar a malha.
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
[[ -r $TT_DIR/rapido/nucleo.sh ]] || falhou 'a instalação não gerou a partida rápida'
mkdir -p "$T/bin"
printf '#!/usr/bin/env bash\necho "ssh: connect to host $2 port 22: Connection timed out" >&2\nexit 255\n' >"$T/bin/ssh"
printf '#!/usr/bin/env bash\necho indisponivel\n' >"$T/bin/tailscale"
chmod +x "$T/bin/ssh" "$T/bin/tailscale"
printf '# host usuario rotulo\nh-fora u fora\n' >"$HOME/.config/tt/maquinas"
saida=$(PATH="$T/bin:$PATH" "$TT" --malha 2>&1) || true
[[ $saida != *"unbound variable"* ]] || falhou "tt --malha (partida rápida) caiu no trap da trava: $saida"
saida=$(PATH="$T/bin:$PATH" TT_COMPLETO=1 "$TT" --malha 2>&1) || true
[[ $saida != *"unbound variable"* ]] || falhou "tt --malha (tt inteiro) caiu no trap da trava: $saida"
passou 'tt --malha não cai no trap RETURN da trava (partida rápida e tt inteiro)'

# Todo trap RETURN que cita variável precisa se desarmar ao disparar.
ruins=$(grep -nE "trap '[^']*\\\$[A-Za-z_][^']*' RETURN" "$T/pkg/tt" | grep -v 'trap - RETURN') || true
[[ -z $ruins ]] || falhou "trap RETURN com variável que não se desarma:
$ruins"
passou 'traps RETURN com variável se desarmam ao disparar'
