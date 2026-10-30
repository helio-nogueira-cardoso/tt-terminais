#!/usr/bin/env bash
# .credentials.json com os tokens zerados (o Claude os apaga quando o refresh falha: "OAuth session expired and could not be
# refreshed") não é login. Na empresa, em 30/10/2026, o perfil itau ficou assim: o ia-login dizia "Nada a fazer", o ia-conta
# listava "última do rot" e o ia-rot continuava escolhendo a conta, então todo tick do mesh falhava com rc=1.
source "$(dirname "$0")/lib.sh"
isolar
B=$HOME/.local/bin R=$HOME/.local/share/claude-contas C=$XDG_CONFIG_HOME/tt/contas-ia
mkdir -p "$B" "$HOME/.claude" "$R"
printf '#!/usr/bin/env bash\nexit 0\n' >"$B/claude"; chmod +x "$B/claude"
export PATH=$B:$PATH IA_LOGIN_SEM_COPIAR=1
instalar_isolado
[[ -L $B/ia-login ]] || falhou 'instalação não ligou o ia-login'

for c in zerado vivo legado; do mkdir -p "$R/$c"; echo "${c:0:1}@x.com" >"$R/$c/.account-email"; done
# o arquivo como o Claude o deixa depois do refresh que falhou (compacto, uma linha)
printf '%s\n' '{"claudeAiOauth":{"accessToken":"","refreshToken":"","expiresAt":0,"scopes":["user:inference"],"subscriptionType":"pro"}}' >"$R/zerado/.credentials.json"
printf '%s\n' '{"claudeAiOauth":{"accessToken":"t","refreshToken":"r","expiresAt":4102444800000}}' >"$R/vivo/.credentials.json"
printf '%s\n' '{"claudeAiOauth":{}}' >"$R/legado/.credentials.json" # sem os campos de token: vale como antes
printf 'claude\tz@x.com\tzerado\t1\nclaude\tv@x.com\tvivo\t1\nclaude\tl@x.com\tlegado\t1\n' >"$C"

# ia-login: só o zerado entra no plano, como "sem login" (com o e-mail que o cadastro dá ao apelido)
plano=$(ia-login --faltas | sort)
[[ $plano == $'claude\tzerado\tz@x.com\tsem login' ]] || falhou "faltas: $plano"
passou 'ia-login: perfil com tokens zerados vira "sem login"; o vivo e o legado (sem campos) seguem logados'

# ia-conta: lista o perfil como "sem login" e manda refazer (adicionar), em vez de "conectada"
out=$(ia-conta listar 2>&1)
grep -E '^zerado' <<<"$out" | grep -q 'sem login' || falhou "ia-conta listar não marcou o zerado como sem login: $out"
grep -E '^zerado' <<<"$out" | grep -q 'conectada' && falhou "ia-conta listar chamou o zerado de conectada: $out"
grep -q 'ia-conta adicionar zerado' <<<"$out" || falhou "ia-conta listar não mandou refazer o login do zerado: $out"
grep -E '^vivo' <<<"$out" | grep -q 'conectada' && grep -E '^legado' <<<"$out" | grep -q 'conectada' || falhou "vivo e legado deveriam seguir conectadas: $out"
passou 'ia-conta: perfil com tokens zerados aparece "sem login" e o vivo e o legado seguem conectados'

# ia-rot: marca como deslogada, para o rodízio não escolher a conta (era o que derrubava o tick)
out=$(ia-rot --status 2>&1 || true)
grep -E '^zerado' <<<"$out" | grep -q 'deslogada' || falhou "ia-rot --status não marcou o zerado como deslogada: $out"
grep -E '^vivo' <<<"$out" | grep -q 'deslogada' && falhou "ia-rot --status marcou o vivo como deslogada: $out"
grep -E '^legado' <<<"$out" | grep -q 'deslogada' && falhou "ia-rot --status marcou o legado como deslogada: $out"
passou 'ia-rot: perfil com tokens zerados fica deslogada e o rodízio não o escolhe'
