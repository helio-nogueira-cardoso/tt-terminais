#!/usr/bin/env bash
# ia-login --consistencia: o mapa conta↔e-mail tem de ser o mesmo em todas as máquinas. Acusa (1) conta mapeada logada com
# outro e-mail, (2) a mesma conta com e-mails diferentes entre máquinas, (3) o mesmo e-mail com nomes diferentes entre
# máquinas. A principal fica fora (não segue conta esperada). O Claude é falso.
# tt-teste: sozinho
source "$(dirname "$0")/lib.sh"
isolar
B=$HOME/.local/bin R=$HOME/.local/share/claude-contas C=$XDG_CONFIG_HOME/tt/contas-ia
mkdir -p "$B" "$HOME/.claude" "$R/alfa" "$R/beta"
printf '#!/usr/bin/env bash\nexit 0\n' >"$B/claude"; chmod +x "$B/claude"
export PATH=$B:$PATH
instalar_isolado

# análise pura
out=$(printf '(cadastro)\ta\tx@x\nmac\ta\tx@x\ndell\ta\tx@x\n' | ia-login --analisar-consistencia) || falhou "falso positivo: $out"
passou 'análise: mapa igual em todas as máquinas é consistente'

out=$(printf '(cadastro)\ta\tx@x\nmac\ta\ty@x\n' | ia-login --analisar-consistencia) && falhou 'regra 1 não acusou'
grep -q '^(1) mac: a conta a está logada com y@x, mas o cadastro mapeia x@x' <<<"$out" || falhou "regra 1: $out"
passou 'análise: conta mapeada logada com outro e-mail (1)'

out=$(printf 'mac\ta\tx@x\ndell\ta\ty@x\n' | ia-login --analisar-consistencia) && falhou 'regra 2 não acusou'
grep -q '^(2) a conta a tem e-mails diferentes entre máquinas' <<<"$out" || falhou "regra 2: $out"
passou 'análise: mesma conta com e-mails diferentes entre máquinas (2)'

out=$(printf 'mac\tb\tz@x\ndell\tc\tz@x\n' | ia-login --analisar-consistencia) && falhou 'regra 3 não acusou'
grep -q '^(3) o e-mail z@x tem nomes de conta diferentes entre máquinas' <<<"$out" || falhou "regra 3: $out"
passou 'análise: mesmo e-mail com nomes diferentes entre máquinas (3)'

# inventário: perfis logados, sem a principal
echo '{"claudeAiOauth":{"accessToken":"t"}}' >"$HOME/.claude/.credentials.json"
for p in alfa beta; do echo '{"claudeAiOauth":{"accessToken":"t"}}' >"$R/$p/.credentials.json"; echo "$p@x.com" >"$R/$p/.account-email"; done
mkdir -p "$R/semlogin"
out=$(ia-login --inventario)
[[ $out == $'alfa\talfa@x.com\nbeta\tbeta@x.com' ]] || falhou "inventário: $out"
passou 'inventário: lista os perfis logados com o e-mail, sem a principal nem perfis sem login'

ia-login --recursos | grep -qw inventario || falhou '--recursos não anuncia o inventário'
passou '--recursos anuncia o inventário'

# ponta a ponta nesta máquina: cadastro diz alfa=outro@x.com, mas o perfil está em alfa@x.com
printf 'claude\toutro@x.com\talfa\t1\n' >"$C"
out=$(IA_LOGIN_SEM_PUXAR=1 ia-login --consistencia) && falhou "não acusou: $out"
grep -q '(1) .*alfa.*alfa@x.com.*outro@x.com' <<<"$out" || falhou "ponta a ponta: $out"
printf 'claude\talfa@x.com\talfa\t1\n' >"$C"
IA_LOGIN_SEM_PUXAR=1 ia-login --consistencia >/dev/null || falhou 'cadastro certo deveria ser consistente'
passou '--consistencia: acusa e some quando o cadastro bate'
