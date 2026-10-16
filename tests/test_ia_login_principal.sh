#!/usr/bin/env bash
# ia-login --principal / ia-conta adicionar principal: trocar a conta PRINCIPAL (a de ~/.claude) por outro
# login, sem tocar nos perfis. Plano (trocar / já está / sem login), login de ponta a ponta num tmux isolado,
# conferência do e-mail, apelido do cadastro como alvo, e recusa com um Claude aberto na principal.
# O Claude é falso e imita as telas reais.
source "$(dirname "$0")/lib.sh"
isolar
B=$HOME/.local/bin R=$HOME/.local/share/claude-contas C=$XDG_CONFIG_HOME/tt/contas-ia
mkdir -p "$B" "$HOME/.claude" "$R/perfil"
cat >"$B/claude" <<'EOF'
#!/usr/bin/env bash
d=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
if [[ $1 == auth && $2 == status ]]; then
  [[ -s $d/.credentials.json ]] && printf '{\n  "email": "%s"\n}\n' "$(cat "$d/quem")"; exit 0
fi
if [[ $1 == auth && $2 == login ]]; then
  a="$*"; [[ $a == *"--email "* ]] && echo "${a##*--email }" >"$d/email-pedido"
  echo "dir-do-login: $d"
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
chmod +x "$B/claude"
export PATH=$B:$PATH IA_LOGIN_SEM_COPIAR=1
instalar_isolado

# Principal logada como antigo@x.com; o perfil tem outra conta e não pode mudar.
echo '{"claudeAiOauth":{"accessToken":"antigo"}}' >"$HOME/.claude/.credentials.json"; echo antigo@x.com >"$HOME/.claude/quem"
echo '{"claudeAiOauth":{"accessToken":"perfil"}}' >"$R/perfil/.credentials.json"; echo perfil@x.com >"$R/perfil/quem"; echo perfil@x.com >"$R/perfil/.account-email"
printf 'claude\tnovo@x.com\tnovo\t1\n' >"$C"

# 1) plano: a principal é outra conta → trocar; sem pedir nada ao usuário
out=$(ia-login --principal novo@x.com --plano)
grep -qE 'claude +principal +novo@x.com +trocar \(hoje: antigo@x.com\)' <<<"$out" || falhou "plano: $out"
[[ $(cat "$HOME/.claude/quem") == antigo@x.com ]] || falhou 'o plano mexeu na principal'
passou 'plano: principal de outra conta aparece como "trocar (hoje: …)" e nada é alterado'

# 2) apelido do cadastro resolve para o e-mail
out=$(ia-login --principal novo --plano)
grep -qE 'principal +novo@x.com +trocar' <<<"$out" || falhou "apelido do cadastro: $out"
ia-login --principal desconhecido --plano >/dev/null 2>&1 && falhou 'apelido fora do cadastro deveria falhar'
passou 'o alvo pode ser o apelido do cadastro; apelido desconhecido falha'

# 3) login de ponta a ponta: o código certo grava por cima da principal, o perfil fica intacto
saida=$(printf 's\ncerto-novo@x.com\n' | IA_LOGIN_ESPERA=10 ia-login --principal novo@x.com 2>&1) || falhou "login da principal: $saida"
grep -q 'https://claude.com/cai/oauth/authorize' <<<"$saida" || falhou "link não apareceu: $saida"
grep -q '✓ logado (novo@x.com)' <<<"$saida" || falhou "não logou: $saida"
[[ $(cat "$HOME/.claude/quem") == novo@x.com ]] || falhou "a principal não virou novo@x.com: $(cat "$HOME/.claude/quem")"
[[ $(cat "$HOME/.claude/email-pedido") == novo@x.com ]] || falhou 'o login não pediu --email'
[[ $(cat "$HOME/.claude/.account-email" 2>/dev/null) == novo@x.com ]] || falhou "cache do e-mail da principal: $(cat "$HOME/.claude/.account-email" 2>/dev/null)"
[[ $(cat "$R/perfil/quem") == perfil@x.com && $(cat "$R/perfil/.account-email") == perfil@x.com ]] || falhou 'o perfil foi alterado'
[[ ! -e $R/perfil/email-pedido ]] || falhou 'o login mexeu no perfil'
tmux -L tt-login list-sessions 2>/dev/null | grep -q login- && falhou 'sessão de login ficou aberta'
passou 'login da principal: link + código colado, e-mail conferido, cache atualizado, perfil intacto, sessão fechada'

# 4) já é a conta pedida: nada a fazer
out=$(ia-login --principal novo@x.com)
grep -q 'Nada a fazer: a principal de todas as máquinas já é novo@x.com' <<<"$out" || falhou "já estava na conta: $out"
passou 'principal que já é a conta pedida: nada a fazer'

# 5) Claude aberto na principal: recusa e não toca na credencial. (argv[0] "claude", sem CLAUDE_CONFIG_DIR)
echo antigo@x.com >"$HOME/.claude/quem"; rm -f "$HOME/.claude/.account-email"
( unset CLAUDE_CONFIG_DIR; eval "$(exec_como claude sleep 40)" ) & aberto=$!
sleep 0.5
msg=$(ia-conta adicionar principal --email novo@x.com 2>&1) && falhou 'adicionar principal deveria recusar com Claude aberto'
grep -q 'a principal está aberta agora' <<<"$msg" || falhou "mensagem da recusa: $msg"
saida=$(printf 's\ncerto-novo@x.com\n' | IA_LOGIN_ESPERA=10 ia-login --principal novo@x.com 2>&1) && falhou "o login deveria falhar com Claude aberto: $saida"
grep -q 'a principal está aberta agora' <<<"$saida" || falhou "o login não explicou a recusa: $saida"
grep -q 'a principal continua em antigo@x.com' <<<"$saida" && grep -q '✗ teste claude principal' <<<"$saida" || falhou "a recusa deveria contar como falha: $saida"
[[ $(cat "$HOME/.claude/quem") == antigo@x.com ]] || falhou 'a credencial mudou apesar da recusa'
# um Claude de perfil (CLAUDE_CONFIG_DIR) aberto não impede
kill "$aberto" 2>/dev/null; wait "$aberto" 2>/dev/null || true
( export CLAUDE_CONFIG_DIR=$R/perfil; eval "$(exec_como claude sleep 40)" ) & perfil_aberto=$!
sleep 0.5
saida=$(printf 's\ncerto-novo@x.com\n' | IA_LOGIN_ESPERA=10 ia-login --principal novo@x.com 2>&1) || falhou "um Claude de perfil aberto não deveria impedir: $saida"
kill "$perfil_aberto" 2>/dev/null; wait "$perfil_aberto" 2>/dev/null || true
[[ $(cat "$HOME/.claude/quem") == novo@x.com ]] || falhou 'a principal não trocou com só um perfil aberto'
passou 'Claude aberto na principal impede a troca; Claude de perfil aberto não'

# 6) interoperabilidade: uma máquina com o ia-login de antes do --principal (via ssh) não pode abrir o plano completo
#    nem passar por "pronta": aparece como "sem suporte". Ssh falso que roda o comando num HOME com o ia-login antigo.
mkdir -p "$T/velho/bin" "$T/velho/home"
cat >"$T/velho/bin/ia-login" <<'EOF2'
#!/usr/bin/env bash
# ia-login de antes do --principal: ajuda sem a linha nova; qualquer argumento desconhecido vira "máquina" e abre o plano
case ${1:-} in
  -h | --help | ajuda) echo '# ia-login velho' ;;
  *) echo "PLANO COMPLETO DO VELHO (nunca deveria rodar)" >>"$HOME/velho-rodou"; echo 'Perguntando às máquinas o que falta…' ;;
esac
EOF2
chmod +x "$T/velho/bin/ia-login"
cat >"$B/ssh" <<EOF2
#!/usr/bin/env bash
# ssh falso: o último argumento é o comando remoto; roda aqui com o ia-login velho na frente do PATH
cmd=\${!#}
HOME=$T/velho/home PATH=$T/velho/bin:\$PATH bash -c "\$cmd"
EOF2
chmod +x "$B/ssh"
printf 'maq-velha usuario velha\n' >"$XDG_CONFIG_HOME/tt/maquinas"
echo antigo@x.com >"$HOME/.claude/quem"; rm -f "$HOME/.claude/.account-email"
out=$(ia-login --principal novo@x.com --plano 2>&1)
grep -qE 'velha +- +- +- +sem suporte' <<<"$out" || grep -qE 'velha .*sem suporte' <<<"$out" || falhou "máquina com ia-login velho deveria aparecer como sem suporte: $out"
[[ ! -e $T/velho/home/velho-rodou ]] || falhou 'o ia-login velho rodou o plano completo por causa do argumento novo'
grep -qE 'teste +claude +principal +novo@x.com +trocar' <<<"$out" || falhou "a máquina local deveria continuar no plano: $out"
passou 'máquina com ia-login antigo: "sem suporte", sem rodar o plano completo de lá; a local segue no plano'

# 7) o ssh frio falha na 1ª tentativa (celular de tela apagada): a 2ª resolve e a máquina entra no plano
rm -f "$T/velho/home/velho-rodou" "$T/ssh-tentativas"
cat >"$B/ssh" <<EOF2
#!/usr/bin/env bash
n=\$(cat "$T/ssh-tentativas" 2>/dev/null || echo 0); echo \$((n + 1)) >"$T/ssh-tentativas"
((n < 1)) && exit 255
cmd=\${!#}
HOME=$T/velho/home PATH=$T/velho/bin:\$PATH bash -c "\$cmd"
EOF2
chmod +x "$B/ssh"
out=$(ia-login --principal novo@x.com --plano 2>&1)
grep -qE 'velha .*sem suporte' <<<"$out" || falhou "a 2ª tentativa deveria responder (sem suporte, o ia-login de lá é o velho): $out"
grep -q 'sem resposta' <<<"$out" && falhou "o ssh frio não pode virar 'sem resposta' na 1ª falha: $out"
[[ $(cat "$T/ssh-tentativas") == 2 ]] || falhou "esperava 2 tentativas de ssh, houve $(cat "$T/ssh-tentativas")"
passou 'ssh frio: a 2ª tentativa responde e a máquina não vira "sem resposta"'
echo "TODOS OS TESTES PASSARAM"
