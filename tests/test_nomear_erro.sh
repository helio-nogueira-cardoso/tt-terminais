#!/usr/bin/env bash
# Falhas do gerador nunca viram nomes; o mesmo contrato vale para resposta remota.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$HOME/.local/bin"
cat >"$HOME/.local/bin/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' "$TT_TEST_RESPOSTA"
exit "$TT_TEST_STATUS"
EOF
chmod +x "$HOME/.local/bin/claude"
export TT_TEST_STATUS=1 TT_TEST_RESPOSTA="You've hit your limit · resets 3pm"
if resultado=$("$TT" --nomear-texto <<<'Pasta: projeto'); then
  falhou "aceitou limite como nome: $resultado"
fi
[[ -z $resultado ]] || falhou 'falha expôs resposta como nome'
export TT_TEST_RESPOSTA='nome-aparentemente-valido'
if "$TT" --nomear-texto <<<'Pasta: projeto'; then falhou 'ignorou exit code do Claude'; fi
export TT_TEST_STATUS=0
for TT_TEST_RESPOSTA in "You've hit your limit · resets 3pm" 'you-ve-hit' 'api-error' $'aviso\nnome-valido' ''; do
  export TT_TEST_RESPOSTA
  if "$TT" --nomear-texto <<<'Pasta: projeto'; then falhou "aceitou saída inválida: $TT_TEST_RESPOSTA"; fi
done
for TT_TEST_RESPOSTA in 'corrigir-terminal' 'ação-terminal' 'vazio'; do
  export TT_TEST_RESPOSTA
  resultado=$("$TT" --nomear-texto <<<'Pasta: projeto') || falhou 'recusou nome válido'
  [[ -n $resultado ]] || falhou 'nome válido vazio'
done
passou 'gerador rejeita falha, limite e texto livre; aceita nome válido'

# Extração das funções para simular um servidor remoto antigo (que ainda devolve erros).
sed -n '/^sugerir_nome() {/,/^}/p; /^validar_nome_sugerido() {/,/^}/p; /^sem_acento() {/,/^}/p; /^limpar() {/,/^}/p; /^slug() {/,/^}/p' "$TT" >"$T/funcoes.sh"
(
  source "$T/funcoes.sh"
  claude_na_sessao() { :; }
  encurtar() { echo "$1"; }
  tmux() { case "$*" in *pane_current_path*) echo /projeto ;; *pane_current_command*) echo bash ;; *) echo 'trabalho na tela' ;; esac; }
  nomear_texto() { cat >/dev/null; return 1; }
  maquinas() { echo 'teste@remoto remoto'; }
  timeout() { shift; "$@"; }
  ssh() { cat >/dev/null; echo "You've hit your limit"; }
  SSH_OPC=() TT_REMOTO=tt
  if resultado=$(sugerir_nome sessao revisar); then falhou "aceitou erro remoto: $resultado"; fi
  ssh() { cat >/dev/null; echo corrigir-terminal; }
  [[ $(sugerir_nome sessao revisar) == corrigir-terminal ]] || falhou 'recusou nome remoto válido'
)
passou 'sugestão remota também valida a resposta antes do slug'

# O rotator recebe o prompt inteiro como argumento para repeti-lo em todas as contas.
cat >"$HOME/.local/bin/claude-rot" <<'EOF'
#!/usr/bin/env bash
[[ $1 == --claude-only ]] || exit 20
[[ $* == *'--model haiku'* && $* == *'--no-session-persistence'* ]] || exit 21
while (($#)); do
  if [[ $1 == --tools ]]; then [[ $2 == '' ]] || exit 22; fi
  if [[ $1 == --system-prompt ]]; then [[ $2 == *'Você nomeia sessões'* ]] || exit 23; fi
  ultimo=$1; shift
done
[[ $ultimo == $'Pasta: teste\nPedido: arrumar abas' ]] || exit 24
echo rotacao-terminal
EOF
chmod +x "$HOME/.local/bin/claude-rot"
[[ $("$TT" --nomear-texto <<<$'Pasta: teste\nPedido: arrumar abas') == rotacao-terminal ]] || falhou 'rotator não recebeu o contrato de nomeação'
passou 'rotator: Haiku, sem ferramentas, apenas Claude e prompt reutilizável'
