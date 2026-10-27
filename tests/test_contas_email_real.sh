#!/usr/bin/env bash
# O e-mail de cada pasta do Claude é o que o próprio Claude grava no arquivo de configuração (oauthAccount do
# .claude.json; ~/.claude.json na principal; o .config.json antigo, se houver), não o cache .account-email: um /login
# de dentro do Claude troca a conta sem passar pelo ia-conta (27/10/2026: seis perfis em duas contas). O listar avisa o
# perfil na conta errada com o conserto, o ia-rot conta a mesma conta uma vez só (--status, --exceto, limite, --passar),
# e o ia-login enxerga e refaz o login do perfil errado sem tirar conta nenhuma da máquina.
# Sem rede: o Claude é falso e o "auth status" dele lê o .claude.json, como o de verdade.
source "$(dirname "$0")/lib.sh"
isolar
B=$HOME/.local/bin R=$HOME/.local/share/claude-contas C=$XDG_CONFIG_HOME/tt/contas-ia
mkdir -p "$B" "$HOME/.claude" "$HOME/.cache" "$R"
cat >"$B/claude" <<'EOF'
#!/usr/bin/env bash
d=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
f=${CLAUDE_CONFIG_DIR:+$CLAUDE_CONFIG_DIR/.claude.json}; f=${f:-$HOME/.claude.json}
[[ -s $d/.config.json ]] && f=$d/.config.json
if [[ $1 == auth && $2 == status ]]; then
  echo "${CLAUDE_CONFIG_DIR:-principal}" >>"$HOME/auth.log"
  e=$(sed -n 's/.*"emailAddress": *"\([^"]*\)".*/\1/p' "$f" 2>/dev/null | head -n 1)
  [[ -s $d/.credentials.json && -n $e ]] && printf '{\n  "loggedIn": true,\n  "email": "%s"\n}\n' "$e"; exit 0
fi
if [[ $1 == auth && $2 == login ]]; then
  echo 'Opening browser to sign in…'
  echo "If the browser didn't open, visit: https://claude.com/cai/oauth/authorize?code=true&client_id=x&state=$RANDOM"
  read -r -p 'Paste code here if prompted > ' cod
  case $cod in
    certo-*) echo '{"claudeAiOauth":{"accessToken":"t","expiresAt":0}}' >"$d/.credentials.json"
             printf '{\n  "oauthAccount": {\n    "emailAddress": "%s"\n  }\n}\n' "${cod#certo-}" >"$f"
             echo 'Login successful.'; exit 0 ;;
    *) echo 'OAuth error: Invalid code'; exit 1 ;;
  esac
fi
printf '%s\t%s\n' "${CLAUDE_CONFIG_DIR:-principal}" "$*" >>"$HOME/claude.log"
[[ -f $d/limite-falso ]] && { echo "You've hit your limit · resets 5pm"; exit 1; }
[[ $* == *--no-session-persistence ]] && exit 1
for a; do :; done; echo "resposta de ${CLAUDE_CONFIG_DIR##*/}: $a"
EOF
chmod +x "$B/claude"
export PATH=$B:$PATH IA_LOGIN_SEM_COPIAR=1 CLAUDE_ROT_USO=0
instalar_isolado

cred='{"claudeAiOauth":{"accessToken":"t","expiresAt":0}}'
conf() { printf '{\n  "numStartups": 3,\n  "oauthAccount": {\n    "accountUuid": "u",\n    "emailAddress": "%s",\n    "organizationName": "Org"\n  }\n}\n' "$1"; }
# principal e itau na mesma conta (o itau tem o cache de antes do /login); devs e career na mesma; solo só com o cache;
# legado com o .config.json antigo, que o Claude prefere ao .claude.json.
echo "$cred" >"$HOME/.claude/.credentials.json"; conf helio@x.com >"$HOME/.claude.json"
for c in itau devs career solo legado; do mkdir -p "$R/$c"; echo "$cred" >"$R/$c/.credentials.json"; done
conf helio@x.com >"$R/itau/.claude.json"; echo banco@x.com >"$R/itau/.account-email"
conf devs@x.com >"$R/devs/.claude.json"
conf devs@x.com >"$R/career/.claude.json"; echo career@x.com >"$R/career/.account-email"
echo solo@x.com >"$R/solo/.account-email"
conf velho@x.com >"$R/legado/.claude.json"; conf legado@x.com >"$R/legado/.config.json"
agora=$(date +%s)
printf 'claude\thelio@x.com\tprincipal\t%s\nclaude\tbanco@x.com\titau\t%s\nclaude\tdevs@x.com\tdevs\t%s\nclaude\tcareer@x.com\tcareer\t%s\nclaude\tsolo@x.com\tsolo\t%s\nclaude\tlegado@x.com\tlegado\t%s\n' \
  "$agora" "$agora" "$agora" "$agora" "$agora" "$agora" >"$C"

: >"$HOME/auth.log"
out=$(ia-conta listar --rapido)
grep -qE '^itau +claude +helio@x.com ' <<<"$out" && grep -qE '^career +claude +devs@x.com ' <<<"$out" ||
  falhou "listar com o e-mail do cache, não o do Claude: $out"
grep -qE '^solo +claude +solo@x.com ' <<<"$out" || falhou "sem oauthAccount, vale o cache: $out"
grep -qE '^legado +claude +legado@x.com ' <<<"$out" || falhou ".config.json antigo não venceu o .claude.json: $out"
[[ $(cat "$R/itau/.account-email") == helio@x.com && $(cat "$R/career/.account-email") == devs@x.com ]] ||
  falhou "cache velho não foi regravado: $(cat "$R/itau/.account-email" "$R/career/.account-email")"
[[ -s $HOME/auth.log ]] && falhou "listar chamou o auth status com o e-mail no arquivo: $(cat "$HOME/auth.log")"
passou 'listar: o e-mail é o do oauthAccount do Claude (o .config.json antigo vence); o cache velho é regravado; sem CLI'

grep -q 'Perfis logados numa conta que não é a do cadastro' <<<"$out" || falhou "sem o aviso de conta errada: $out"
grep -q 'itau  está em helio@x.com (a mesma conta de principal), mas no cadastro é banco@x.com' <<<"$out" &&
  grep -q '→ ia-conta adicionar itau --email banco@x.com  (abra o link numa janela anônima' <<<"$out" ||
  falhou "aviso do itau: $out"
grep -q 'career  está em devs@x.com (a mesma conta de devs), mas no cadastro é career@x.com' <<<"$out" &&
  grep -q '→ ia-conta adicionar career --email career@x.com' <<<"$out" || falhou "aviso do career: $out"
grep -qE 'renomear (itau|career)' <<<"$out" && falhou "dica de renomear para perfil na conta errada: $out"
grep -q 'faltam aqui' <<<"$out" && falhou "conta errada também listada como falta: $out"
grep -q '^  helio@x.com  principal, itau$' <<<"$out" && grep -q '^  devs@x.com  career, devs$' <<<"$out" ||
  falhou "resumo da mesma conta em mais de uma pasta: $out"
[[ $(grep -c $'^claude\t' "$C") == 6 ]] || falhou "cadastro ganhou linhas com a conta errada: $(cat "$C")"
passou 'listar: perfil na conta errada vira aviso com ia-conta adicionar --email (sem renomear); mesma conta resumida'

# Perfil sem apelido próprio no cadastro, na conta de outra pasta (o trabalho de 27/10): renomear para o apelido dela
# não dá certo; a dica é remover ou logar na conta certa.
mkdir -p "$R/trab"; echo "$cred" >"$R/trab/.credentials.json"; conf devs@x.com >"$R/trab/.claude.json"
out=$(ia-conta listar --rapido)
grep -q 'trab  é a mesma conta de devs (devs@x.com)  → ia-conta remover trab, ou logue-o na conta certa' <<<"$out" ||
  falhou "perfil repetido: $out"
grep -q 'renomear trab' <<<"$out" && falhou "dica de renomear para o apelido de outra pasta: $out"
grep -q $'^trab\tmesma-conta\tde devs' <<<"$(ia-rot --claude-only --status)" || falhou 'trab fora do mesma-conta'
mv "$R/trab" "$T/trab-fora"
passou 'listar: perfil repetido sem apelido próprio pede remover ou relogar, não renomear'

st=$(ia-rot --claude-only --status)
grep -q $'^itau\tmesma-conta\tde principal (helio@x.com)' <<<"$st" && grep -q $'^career\tmesma-conta\tde devs (devs@x.com)' <<<"$st" ||
  falhou "status sem mesma-conta: $st"
grep -q $'^principal\tdisponivel' <<<"$st" && grep -q $'^devs\tdisponivel' <<<"$st" && grep -q $'^solo\tdisponivel' <<<"$st" ||
  falhou "status das contas que valem: $st"
set +e
ia-rot --claude-only --melhor --exceto principal --exceto devs --exceto solo --exceto legado >"$T/m" 2>&1; rc=$?
set -e
[[ $rc == 2 ]] || falhou "--exceto deixou a mesma conta noutra pasta (rc=$rc): $(cat "$T/m")"
passou 'ia-rot: --status mostra a repetida como mesma-conta; --exceto tira as pastas da mesma conta'

touch "$HOME/.claude/limite-falso"; : >"$HOME/claude.log"
(cd /tmp && ia-rot --claude-only --exceto devs --exceto solo --exceto legado -p oi </dev/null >/dev/null 2>&1) && falhou 'rotação devia esgotar'
grep -q '^principal' "$HOME/claude.log" || falhou "nem tentou a principal: $(cat "$HOME/claude.log")"
grep -q "$R/itau" "$HOME/claude.log" && falhou 'tentou o itau, mesma conta da principal que bateu o limite'
rm -f "$HOME/.claude/limite-falso"; : >"$HOME/.cache/claude-rot.state"
set +e
echo '# Passagem: teste' >"$T/passagem.md"
(cd /tmp && IA_CONTA=itau ia-rot --claude-only --exceto devs --exceto solo --exceto legado --sem-tmux --passar "$T/passagem.md" >"$T/p" 2>&1); rc=$?
set -e
[[ $rc == 2 ]] || falhou "passagem do itau foi para a mesma conta (rc=$rc): $(cat "$T/p")"
passou 'ia-rot: limite da principal bloqueia o itau (mesma conta pelo .claude.json); passagem não cai nela'

plano=$(ia-login --faltas | sort)
grep -q $'^claude\titau\tbanco@x.com\tconta errada (hoje: helio@x.com)$' <<<"$plano" &&
  grep -q $'^claude\tcareer\tcareer@x.com\tconta errada (hoje: devs@x.com)$' <<<"$plano" || falhou "faltas: $plano"
grep -qE $'\t(solo|legado|devs)\t' <<<"$plano" && falhou "faltas com conta certa: $plano"
out=$(ia-login --plano)
grep -qE '^teste +claude +itau +banco@x.com +conta errada \(hoje: helio@x.com\): o login refaz o perfil' <<<"$out" || falhou "plano: $out"
ia-login --iniciar claude devs devs@x.com 2>"$T/err" && falhou 'iniciou login por cima da conta certa'
ia-login --iniciar claude legado outro@x.com 2>/dev/null && falhou 'iniciou login por cima de conta que só existe ali'
grep -q 'já está logada' "$T/err" || falhou "recusa: $(cat "$T/err")"
tmux -L tt-login list-sessions 2>/dev/null | grep -q login- && falhou 'abriu sessão de login para conta logada'
passou 'ia-login: perfil na conta errada vira "conta errada"; --iniciar só refaz quando a conta de agora está repetida aqui'

set +e
saida=$(printf 's\ncerto-career@x.com\ncerto-banco@x.com\n' | IA_LOGIN_ESPERA=10 ia-login 2>&1); rc=$?
set -e
grep -q '✓ logado (career@x.com)' <<<"$saida" && grep -q '✓ logado (banco@x.com)' <<<"$saida" && [[ $rc == 0 ]] ||
  falhou "relogin dos perfis na conta errada (rc=$rc): $saida"
out=$(ia-conta listar --rapido)
grep -qE '^itau +claude +banco@x.com ' <<<"$out" && grep -qE '^career +claude +career@x.com ' <<<"$out" || falhou "depois do relogin: $out"
grep -q 'conta que não é a do cadastro' <<<"$out" && falhou "aviso ficou depois do relogin: $out"
grep -q $'^itau\tdisponivel' <<<"$(ia-rot --claude-only --status)" || falhou 'itau não voltou a contar como conta própria'
tmux -L tt-login list-sessions 2>/dev/null | grep -q login- && falhou 'sessões de login ficaram abertas'
passou 'ia-login refaz os perfis na conta certa; listar e ia-rot passam a ver as contas próprias'
