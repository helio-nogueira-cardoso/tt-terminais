#!/usr/bin/env bash
# ia-login: plano do que falta (conta do cadastro ausente, perfil sem credencial, nome ocupado, Codex
# deslogado) e os logins de ponta a ponta num tmux isolado: link + código colado (Claude), link +
# código de dispositivo com espera da aprovação (Codex), conferência do e-mail e limpeza das sessões.
# Claude e Codex falsos imitam as telas reais.
source "$(dirname "$0")/lib.sh"
isolar
B=$HOME/.local/bin R=$HOME/.local/share/claude-contas C=$XDG_CONFIG_HOME/tt/contas-ia
mkdir -p "$B" "$HOME/.claude" "$HOME/.codex" "$R"
cat >"$B/claude" <<'EOF'
#!/usr/bin/env bash
d=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
if [[ $1 == auth && $2 == status ]]; then
  [[ -s $d/.credentials.json ]] && printf '{\n  "email": "%s"\n}\n' "$(cat "$d/quem")"; exit 0
fi
if [[ $1 == auth && $2 == login ]]; then
  a="$*"; [[ $a == *"--email "* ]] && echo "${a##*--email }" >"$d/email-pedido"
  echo 'Opening browser to sign in…'
  echo "If the browser didn't open, visit: https://claude.com/cai/oauth/authorize?code=true&client_id=x&state=$RANDOM"
  read -r -p 'Paste code here if prompted > ' cod
  case $cod in
    certo*) echo '{"claudeAiOauth":{"accessToken":"t","expiresAt":0}}' >"$d/.credentials.json"; echo "${cod#certo-}" >"$d/quem"
            echo 'Login successful.'; exit 0 ;;
    *) echo 'OAuth error: Invalid code'; exit 1 ;;
  esac
fi
exit 0
EOF
cat >"$B/codex" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == login && ${2:-} == status ]]; then [[ -s $HOME/.codex/auth.json ]]; exit; fi
if [[ $1 == login && ${2:-} == --device-auth ]]; then
  printf 'Follow these steps to sign in with ChatGPT using device code authorization:\n'
  printf '1. Open this link in your browser and sign in to your account\n   https://auth.openai.com/codex/device\n'
  printf '2. Enter this one-time code (expires in 15 minutes)\n   ABCD-12345\n'
  until [[ -e $HOME/aprovado ]]; do sleep 0.2; done
  echo '{}' >"$HOME/.codex/auth.json"; echo 'Successfully logged in'; exit 0
fi
exit 0
EOF
chmod +x "$B/claude" "$B/codex"
export PATH=$B:$PATH IA_LOGIN_SEM_COPIAR=1 # sem mexer na área de transferência real
instalar_isolado
[[ -L $B/ia-login ]] || falhou 'instalação não ligou o ia-login'

# Cadastro: alfa falta aqui; beta é um perfil sem credencial; gama existe aqui com outro e-mail.
for c in beta gama; do mkdir -p "$R/$c"; done
echo '{"claudeAiOauth":{}}' >"$R/gama/.credentials.json"; echo 'outro@x.com' >"$R/gama/.account-email"
printf 'claude\ta@x.com\talfa\t1\nclaude\tb@x.com\tbeta\t1\nclaude\tg@x.com\tgama\t1\ncodex\tcx@x.com\tcx\t1\n' >"$C"

mkdir -p "$R/codex" # pasta estranha (ia-conta codex antigo): não é perfil do Claude
mkdir -p "$R/x.lock" "$R/nome com espaço" "$R/-invalida"
printf 'trava preservada\n' >"$R/x.lock/dono"
plano=$(ia-login --faltas | sort)
esperado=$(printf 'claude\talfa\ta@x.com\tfalta\nclaude\tbeta\tb@x.com\tsem login\nclaude\tgama\tg@x.com\tnome ocupado\ncodex\tcodex\tcx@x.com\tsem login\n' | sort)
[[ $plano == "$esperado" ]] || falhou "faltas: $plano"
out=$(ia-login --plano)
grep -Eq 'x\.lock|nome com espaço|-invalida' <<<"$out" && falhou "plano incluiu pasta auxiliar: $out"
[[ $(cat "$R/x.lock/dono") == 'trava preservada' ]] || falhou 'plano alterou trava'
passou 'faltas e plano ignoram pastas auxiliares e preservam a trava'
grep -qE '^teste +claude +gama +g@x.com +nome ocupado por outro e-mail' <<<"$out" || falhou "plano: $out"
passou 'faltas: conta do cadastro ausente, perfil sem credencial, nome ocupado e Codex deslogado'

# Logins: alfa entra certo, beta erra o código, codex é aprovado alguns segundos depois.
(sleep 4; until tmux -L tt-login has-session -t '=login-codex-codex' 2>/dev/null; do sleep 0.3; done; sleep 2; touch "$HOME/aprovado") &
aprova=$!
set +e
saida=$(printf 's\ncerto-a@x.com\nerrado\n' | IA_LOGIN_ESPERA=10 ia-login 2>&1); rc=$?
set -e
wait $aprova 2>/dev/null || true
grep -q 'https://claude.com/cai/oauth/authorize' <<<"$saida" || falhou "link do Claude não apareceu: $saida"
grep -q '✓ logado (a@x.com)' <<<"$saida" || falhou "alfa não logou: $saida"
[[ -s $R/alfa/.credentials.json ]] || falhou "alfa sem credencial: $(ls -la $R/alfa)"; [[ $(cat "$R/alfa/email-pedido" 2>/dev/null) == a@x.com ]] || falhou "sem --email: $(cat "$R/alfa/email-pedido" 2>&1)"
grep -q 'Invalid code' <<<"$saida" && grep -q 'o login saiu com 1' <<<"$saida" && grep -q '✗ teste claude beta' <<<"$saida" || falhou "código errado não foi relatado: $saida"
grep -q 'Código: ABCD-12345' <<<"$saida" && grep -q 'https://auth.openai.com/codex/device' <<<"$saida" || falhou "fluxo do Codex: $saida"
grep -q '✓ teste codex codex' <<<"$saida" || falhou "codex não logou: $saida"
grep -q 'Resumo: 2 de 3' <<<"$saida" && [[ $rc != 0 ]] || falhou "resumo/saída: rc=$rc $saida"
tmux -L tt-login list-sessions 2>/dev/null | grep -q login- && falhou 'sessões de login ficaram abertas'
passou 'logins: link + código colado (Claude), aprovação por dispositivo (Codex), erro relatado, sessões fechadas'

# E-mail diferente do esperado é avisado.
rm -f "$R/beta/quem"
set +e
saida=$(printf 's\ncerto-outra@x.com\n' | IA_LOGIN_ESPERA=10 ia-login 2>&1)
set -e
grep -q '⚠ logou em outra@x.com, mas o esperado era b@x.com' <<<"$saida" || falhou "e-mail trocado não avisado: $saida"
passou 'login em conta diferente da esperada é avisado'

# Conta já logada: --iniciar recusa (o codex login derruba a credencial existente ao começar).
ia-login --iniciar codex codex '' 2>"$T/err" && falhou 'iniciou login do Codex já logado'
grep -q 'já está logada' "$T/err" || falhou "recusa: $(cat "$T/err")"
ia-login --iniciar claude alfa a@x.com 2>/dev/null && falhou 'iniciou login de perfil já logado'
tmux -L tt-login list-sessions 2>/dev/null | grep -q login- && falhou 'abriu sessão de login para conta logada'
passou 'conta já logada nunca recebe login por cima'

# Perfil sem e-mail esperado: a coluna sai "-" (campo vazio deslocava as colunas do plano).
mkdir -p "$R/delta"
grep -q $'^claude\tdelta\t-\tsem login$' <(ia-login --faltas) || falhou "e-mail vazio: $(ia-login --faltas)"
ia-login --plano >"$T/plano"; grep -qE "^teste +claude +delta +- +sem login *$" "$T/plano" || falhou "plano com e-mail vazio: $(grep delta "$T/plano" | cat -A)"
ia-conta codex --version 2>/dev/null && falhou 'ia-conta codex rodou como perfil'
[[ -e $R/kiro ]] && falhou 'criou pasta de perfil kiro'
ia-conta kiro 2>/dev/null || true; [[ -e $R/kiro ]] && falhou 'ia-conta kiro criou pasta de perfil'
passou 'e-mail vazio não desloca colunas; codex/kiro não viram perfil do Claude'

# Antes do plano, o ia-login junta os cadastros e entrega o completo a cada máquina: uma que ficou sem
# rede (cópia velha) não deixa a conta nova de fora do plano. ssh falso = outra máquina noutro HOME.
R2=$T/remota
mkdir -p "$R2/.config/tt" "$R2/.local/bin" "$R2/.claude"; printf 'nome=remota\n' >"$R2/.config/tt/config"
HOME=$R2 XDG_CONFIG_HOME=$R2/.config TT_DIR=$R2/.local/share/tt "$T/pkg/tt" --instalar-aqui >/dev/null 2>&1 || falhou 'instalação da remota'
cp "$B/claude" "$R2/.local/bin/claude"
cat >"$B/ssh" <<EOS
#!/usr/bin/env bash
while [[ \$1 == -* ]]; do case \$1 in -o|-p) shift 2 ;; *) shift ;; esac; done
shift # destino
exec env HOME=$R2 XDG_CONFIG_HOME=$R2/.config TT_DIR=$R2/.local/share/tt bash -c "\$*"
EOS
chmod +x "$B/ssh"
printf 'host-remota usuario remota\n' >"$XDG_CONFIG_HOME/tt/maquinas"
agora=$(date +%s)
printf 'claude\tnova@x.com\tnova\t%s\n' "$agora" >>"$C"                       # só aqui
printf 'claude\tso-la@x.com\tsola\t%s\n' "$agora" >"$R2/.config/tt/contas-ia"   # só lá
out=$(ia-login --plano)
grep -q $'^claude\tnova@x.com\tnova\t' "$R2/.config/tt/contas-ia" || falhou "remota não recebeu o cadastro: $(cat "$R2/.config/tt/contas-ia")"
grep -q $'^claude\tso-la@x.com\tsola\t' "$C" || falhou "não puxou o cadastro da remota: $(cat "$C")"
grep -qE '^remota +claude +nova +nova@x.com +falta' <<<"$out" || falhou "plano da remota sem a conta nova: $out"
grep -qE '^teste +claude +sola +so-la@x.com +falta' <<<"$out" || falhou "plano daqui sem a conta da remota: $out"
passou 'ia-login sincroniza o cadastro (puxa e entrega) antes do plano'
