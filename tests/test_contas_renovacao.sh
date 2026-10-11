#!/usr/bin/env bash
# Renovar token abre o Claude antes da conversa: precisa do mesmo ambiente dos sub-agentes,
# inclusive quando há várias contas vencidas. Agente falso, HOME isolado, sem rede/tmux.
source "$(dirname "$0")/lib.sh"; isolar
sed -n '/^token_vencido() {/,/^}/p; /^renovar_tokens() {/,/^}/p' "$RAIZ/ia-conta" >"$T/renovar.sh"
source "$T/renovar.sh"
BASE=$HOME/principal
pasta_claude() { printf '%s/%s\n' "$HOME" "$1"; }
for c in principal perfil; do
  mkdir -p "$HOME/$c"
  printf '{"claudeAiOauth":{"expiresAt":0}}\n' >"$HOME/$c/.credentials.json"
done
CLAUDE_BIN=$T/claude
cat >"$CLAUDE_BIN" <<'EOF'
#!/usr/bin/env bash
[[ $* == '-p --no-session-persistence' ]] || exit 20
c=${CLAUDE_CONFIG_DIR##*/}; c=${c:-principal}
printf '%s|%s\n' "${CLAUDE_CODE_SUBAGENT_MODEL_FORCE-ausente}" "${CLAUDE_CODE_DISABLE_EXPLORE_INHERIT_CAP-ausente}" >"$HOME/$c/ambiente"
exit 1 # renovar sem prompt sai com erro; renovar_tokens deve esperar e tolerar isso
EOF
chmod +x "$CLAUDE_BIN"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SUBAGENT_MODEL_FORCE CLAUDE_CODE_DISABLE_EXPLORE_INHERIT_CAP
renovar_tokens principal perfil codex kiro
for c in principal perfil; do
  [[ $(cat "$HOME/$c/ambiente") == '1|1' ]] || falhou "renovação de $c não aplicou padrões"
done
passou 'renovação de principal e perfil aplica as variáveis; outros provedores são pulados'
export CLAUDE_CODE_SUBAGENT_MODEL_FORCE='' CLAUDE_CODE_DISABLE_EXPLORE_INHERIT_CAP=custom
renovar_tokens principal perfil
for c in principal perfil; do
  [[ $(cat "$HOME/$c/ambiente") == '|custom' ]] || falhou "renovação de $c sobrescreveu escolha do dono"
done
passou 'renovação preserva valores explícitos, inclusive vazios'
rm "$HOME/perfil/ambiente"
printf '{"claudeAiOauth":{"expiresAt":4102444800000}}\n' >"$HOME/perfil/.credentials.json"
renovar_tokens perfil
[[ ! -e $HOME/perfil/ambiente ]] || falhou 'token válido foi renovado'
passou 'token ainda válido não inicia Claude'
