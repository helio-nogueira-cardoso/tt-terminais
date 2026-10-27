#!/usr/bin/env bash
# macOS: o Claude Code guarda a credencial no Keychain, não no .credentials.json. O ia-conta e o ia-login
# reconhecem o login por lá (serviço "Claude Code-credentials[-<8 hex do sha256 da pasta>]", consultado pelo
# caminho do login.keychain, como funciona por ssh) e não cobram login de quem já tem. Nome que não é conta
# (ia-conta rodar) não deixa pasta de perfil vazia. uname e security são falsos.
source "$(dirname "$0")/lib.sh"
isolar
B=$HOME/.local/bin R=$HOME/.local/share/claude-contas
mkdir -p "$B" "$HOME/.claude" "$R" "$HOME/.cache"
cat >"$B/claude" <<'EOF'
#!/usr/bin/env bash
[[ $1 == auth ]] && exit 1 # por ssh o Claude não lê o Keychain: o e-mail vem do cache
echo "rodou ${CLAUDE_CONFIG_DIR:-principal}"
EOF
chmod +x "$B/claude"
export PATH=$B:$PATH
instalar_isolado

# Keychain falso: só responde com o caminho do login.keychain (sem ele, como por ssh, não acha nada).
F=$T/falsos; mkdir -p "$F"
printf '#!/bin/sh\necho Darwin\n' >"$F/uname"
cat >"$F/security" <<'EOF'
#!/usr/bin/env bash
[[ $1 == find-generic-password && $2 == -s ]] || exit 1
[[ ${4:-} == "$HOME/Library/Keychains/login.keychain-db" ]] || exit 44
grep -qxF -- "$3" "$HOME/keychain" 2>/dev/null || exit 44
EOF
chmod +x "$F/uname" "$F/security"
h() { python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:8])' "$1"; }
for c in mac1 mac2; do mkdir -p "$R/$c"; echo "$c@x.com" >"$R/$c/.account-email"; done
printf 'Claude Code-credentials\nClaude Code-credentials-%s\n' "$(h "$R/mac1")" >"$HOME/keychain"
echo 'p@x.com' >"$HOME/.claude/.account-email"
printf 'claude\tmac1@x.com\tmac1\t1\nclaude\tmac2@x.com\tmac2\t1\n' >"$XDG_CONFIG_HOME/tt/contas-ia"

# No Linux o Keychain não conta: mac1 segue sem login.
out=$(ia-conta listar --rapido)
grep -Eq '^mac1 .*sem login' <<<"$out" || falhou "Linux: mac1 deveria estar sem login: $out"
status=$(CLAUDE_ROT_USO=0 ia-rot --claude-only --status)
grep -q $'^mac1\tdeslogada\t' <<<"$status" || falhou 'rotador Linux aceitou Keychain do macOS'

export PATH=$F:$PATH
out=$(ia-conta listar --rapido)
grep -Eq '^principal .*p@x\.com' <<<"$out" || falhou "principal no Keychain não apareceu conectada: $out"
grep -Eq '^mac1 .*mac1@x\.com' <<<"$out" || falhou "mac1 no Keychain não apareceu conectada: $out"
grep -Eq '^mac1 .*sem login' <<<"$out" && falhou "mac1 no Keychain dado como sem login: $out"
grep -Eq '^mac2 .*sem login' <<<"$out" || falhou "mac2 sem credencial deveria estar sem login: $out"
faltas=$(ia-login --faltas)
[[ $faltas == $'claude\tmac2\tmac2@x.com\tsem login' ]] || falhou "faltas: $faltas"
[[ $(ia-conta mac1 2>&1) == "rodou $R/mac1" ]] || falhou 'conta do Keychain não abriu'
ia-conta mac2 >/dev/null 2>&1 && falhou 'conta sem login abriu'
passou 'macOS: login no Keychain conta como conectado (listar, faltas, abrir); sem credencial segue cobrado'

# O rotador deve usar a mesma detecção, inclusive sem sessão gráfica/por ssh. Não lê segredos.
status=$(CLAUDE_ROT_USO=0 ia-rot --claude-only --status)
grep -q $'^mac1\tdisponivel\t' <<<"$status" || falhou "rotador recusou login do Keychain: $status"
grep -q $'^mac2\tdeslogada\t' <<<"$status" || falhou 'rotador aceitou perfil sem credencial'
melhor=$(CLAUDE_ROT_USO=0 ia-rot --claude-only --melhor --exceto principal)
[[ ${melhor%%$'\t'*} == mac1 ]] || falhou "rotador não escolheu perfil do Keychain: $melhor"
resp=$(CLAUDE_ROT_USO=0 ia-rot --claude-only --exceto principal -p 'oi' </dev/null)
[[ $resp == "rodou $R/mac1" ]] || falhou 'rotação sem tela não abriu perfil do Keychain'
passou 'rotador: status, seleção e execução sem tela reconhecem o Keychain e recusam conta sem login'

# Cache de janela encerrada não prova uso atual zero nem derruba bloqueio recente.
rm -f "$HOME/.cache/claude-rot.current"
agora=$(date +%s)
cat >"$HOME/.cache/claude-rot.uso.json" <<EOF
{"mac1":{"alvo":"$R/mac1","quando":$((agora - 86400)),"janelas":[["5h",10,$((agora - 3600))]],"modelos":[["fable",0,$((agora - 3600))]]}}
EOF
status=$(ia-rot --claude-only --status)
grep -q $'^mac1\tdisponivel\tuso desconhecido (cache vencido)' <<<"$status" || falhou "cache antigo virou uso atual: $status"
printf 'mac1\t%s\t%s\n' "$((agora + 3600))" "$agora" >"$HOME/.cache/claude-rot.state"
status=$(ia-rot --claude-only --status)
grep -q $'^mac1\tesgotada\t' <<<"$status" || falhou 'cache vencido removeu bloqueio por limite'
ia-rot --claude-only --melhor --exceto principal >/dev/null 2>&1 && falhou 'seleção ignorou limite vigente'
passou 'cache vencido é desconhecido e preserva o bloqueio recente por limite'

for n in rodar naoexiste; do
  ia-conta "$n" >/dev/null 2>&1 && falhou "ia-conta $n deveria falhar"
  [[ -e $R/$n ]] && falhou "ia-conta $n deixou a pasta de perfil $R/$n"
done
grep -q "não é uma conta" <<<"$(ia-conta rodar 2>&1)" || falhou 'ia-conta rodar sem a mensagem de nome reservado'
ia-conta entrar rodar </dev/null >/dev/null 2>&1 && falhou 'entrar aceitou o nome reservado rodar'
[[ -e $R/rodar ]] && falhou 'entrar rodar criou pasta'
passou 'nome que não é conta (rodar, desconhecido) não cria pasta de perfil vazia'
