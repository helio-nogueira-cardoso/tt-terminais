#!/usr/bin/env bash
# Renovar token abre o Claude antes da conversa: precisa do mesmo ambiente dos sub-agentes,
# inclusive quando há várias contas vencidas. Agente falso, HOME isolado, sem rede/tmux.
source "$(dirname "$0")/lib.sh"; isolar
sed -n '/^servico_chaves() {/,/^}/p; /^token_vencido() {/,/^}/p; /^validade_vencida() {/,/^}/p; /^renovar_tokens() {/,/^}/p' \
  "$RAIZ/ia-conta" >"$T/renovar.sh"
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

# macOS: o login vive no Chaves (o .credentials.json ali pode ser sobra antiga). uname e security são falsos;
# o security só responde pelo caminho do login.keychain, e -w devolve a credencial guardada em $HOME/chaves/.
F=$T/falsos; mkdir -p "$F" "$HOME/chaves" "$HOME/Library/Keychains"
: >"$HOME/Library/Keychains/login.keychain-db"
printf '#!/bin/sh\necho Darwin\n' >"$F/uname"
cat >"$F/security" <<'EOS'
#!/usr/bin/env bash
[[ $1 == find-generic-password && $2 == -s ]] || exit 1
f=$HOME/chaves/$3; [[ -s $f ]] || exit 44
if [[ $4 == -w ]]; then [[ $5 == "$HOME/Library/Keychains/login.keychain-db" ]] || exit 44; cat "$f"
else [[ $4 == "$HOME/Library/Keychains/login.keychain-db" ]] || exit 44; fi
EOS
chmod +x "$F/uname" "$F/security"
h() { python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:8])' "$1"; }
mkdir -p "$HOME/chaveiro"
printf '{"claudeAiOauth":{"expiresAt":0}}\n' >"$HOME/chaves/Claude Code-credentials-$(h "$HOME/chaveiro")"
printf '{"claudeAiOauth":{"expiresAt":4102444800000}}\n' >"$HOME/chaves/Claude Code-credentials" # a principal, sem sufixo
printf '{"claudeAiOauth":{"expiresAt":0}}\n' >"$HOME/principal/.credentials.json" # sobra vencida
rm -f "$HOME"/*/ambiente
PATH=$F:$PATH renovar_tokens chaveiro principal
[[ -e $HOME/chaveiro/ambiente ]] || falhou 'macOS: token vencido no Chaves não foi renovado'
[[ ! -e $HOME/principal/ambiente ]] || falhou 'macOS: sobra vencida no arquivo renovou quem está válido no Chaves'
passou 'macOS: a validade vem do Chaves, não da sobra do .credentials.json'

# O contas-uso.py lê o token do Chaves (antes só o arquivo: no Mac, uso sempre "último valor conhecido").
PATH=$F:$PATH python3 -I - "$RAIZ/contas-uso.py" "$HOME" <<'PY' || falhou 'contas-uso.py não leu a credencial do Chaves'
import importlib.util, json, pathlib, sys
spec = importlib.util.spec_from_file_location("uso", sys.argv[1]); uso = importlib.util.module_from_spec(spec)
spec.loader.exec_module(uso)
casa = pathlib.Path(sys.argv[2])
assert uso.credencial_claude(str(casa / "chaveiro")) == {"expiresAt": 0}
(casa / ".claude").mkdir(exist_ok=True)
(casa / ".claude/.credentials.json").write_text(json.dumps({"claudeAiOauth": {"expiresAt": 0}}))  # sobra vencida
assert uso.credencial_claude(str(casa / ".claude")) == {"expiresAt": 4102444800000}  # Chaves antes do arquivo
(casa / "perfil").mkdir(exist_ok=True)
(casa / "perfil/.credentials.json").write_text(json.dumps({"claudeAiOauth": {"expiresAt": 7}}))
assert uso.credencial_claude(str(casa / "perfil")) == {"expiresAt": 7}  # sem item no Chaves: o arquivo
(casa / "Library/Keychains/login.keychain-db").unlink()
assert uso.credencial_claude(str(casa / ".claude")) == {"expiresAt": 0}  # sem Chaves (Linux): o arquivo
PY
passou 'uso: credencial do Chaves no macOS, arquivo como reserva e no Linux'
