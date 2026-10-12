#!/usr/bin/env bash
# AGENTS.md único: ~/.agents/AGENTS.md é a fonte das instruções globais de todas as IAs. O reforço
# (tt --reforcar-agentes, o mesmo do vigia) migra o texto que cada IA tinha para a fonte, liga Claude
# (principal e perfis) e Codex a ela por link relativo, gera a cópia do Kiro, faz o Claude ler o
# AGENTS.md de projeto também onde há CLAUDE.md, apaga travas abandonadas e volta a impor tudo isso
# quando alguém mexe — sem ressuscitar o que o usuário apagou da fonte.
source "$(dirname "$0")/lib.sh"; isolar
tt() { "$TT" "$@"; }
fail() { echo "FALHOU: $1" >&2; exit 1; }
F=$HOME/.agents/AGENTS.md P=$HOME/.local/share/claude-contas K=$HOME/.kiro/steering/agentes.md
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.kiro/steering" "$P/trabalho" "$P/trabalho.lock" "$P/nova.lock"
printf 'minhas regras\n\n@WORKFLOW.md\n' >"$HOME/.claude/CLAUDE.md"
printf 'regra do codex\n\nminhas regras\n' >"$HOME/.codex/AGENTS.md"
printf -- '---\ninclusion: always\n---\nregra antiga do kiro\n' >"$HOME/.kiro/steering/tt-terminais.md"
printf '{"theme": "dark", "pluginConfigs": {"cc-plugin-agents-md@builtin": {"options": {"instructionFiles": "claude-md"}}}}\n' >"$HOME/.claude/settings.json"
ln -s "$HOME/.claude/settings.json" "$P/trabalho/settings.json"
touch -d '-1 hour' "$P/trabalho.lock"

tt --reforcar-agentes

# 1) migração: o texto de cada IA vai para a fonte uma vez, antes do bloco do tt; import relativo corrigido
[[ $(head -1 "$F") == 'minhas regras' ]] || fail "texto do usuário deveria abrir a fonte: $(head -3 "$F")"
[[ $(grep -c '^minhas regras$' "$F") == 1 ]] || fail "parágrafo repetido em duas IAs entrou duas vezes"
grep -qx '@~/.claude/WORKFLOW.md' "$F" || fail "import relativo do Claude deveria apontar para ~/.claude"
grep -qx 'regra do codex' "$F" && grep -qx 'regra antiga do kiro' "$F" || fail "texto do Codex/Kiro não foi para a fonte"
[[ $(grep -c 'regras-tt BEGIN' "$F") == 1 ]] && grep -q 'tt --tarefa-log' "$F" || fail "bloco do tt ausente ou repetido na fonte"
(( $(grep -n 'regra do codex' "$F" | cut -d: -f1) < $(grep -n 'regras-tt BEGIN' "$F" | cut -d: -f1) )) || fail "texto absorvido deveria ficar antes do bloco"
ls -A "$HOME/.local/state/tt/agentes-backup/" | grep -q '^.claude%CLAUDE.md\.' || fail "sem cópia de segurança do CLAUDE.md antigo"
echo "ok: migração para ~/.agents/AGENTS.md (sem repetir parágrafo, import corrigido, cópia de segurança)"

# 2) links relativos (valem também de dentro do proot) e cópia do Kiro
[[ $(readlink "$HOME/.claude/CLAUDE.md") == ../.agents/AGENTS.md ]] || fail "Claude: $(readlink "$HOME/.claude/CLAUDE.md")"
[[ $(readlink "$HOME/.codex/AGENTS.md") == ../.agents/AGENTS.md ]] || fail "Codex: $(readlink "$HOME/.codex/AGENTS.md")"
[[ $(readlink "$P/trabalho/CLAUDE.md") == ../../../../.agents/AGENTS.md ]] || fail "perfil: $(readlink "$P/trabalho/CLAUDE.md")"
[[ -e $HOME/.kiro/steering/tt-terminais.md ]] && fail "steering antigo do Kiro deveria sair"
[[ $(head -1 "$K") == --- ]] && grep -q 'inclusion: always' "$K" && grep -qx 'regra do codex' "$K" && grep -q 'tt --tarefa-log' "$K" || fail "cópia do Kiro incompleta"
echo "ok: Claude (principal e perfil) e Codex por link relativo; Kiro com cópia gerada"

# 3) travas: a abandonada sai, a viva fica intocada; nenhuma vira perfil
[[ -e $P/trabalho.lock ]] && fail "trava abandonada deveria ser apagada"
[[ -d $P/nova.lock && -z $(ls -A "$P/nova.lock") ]] || fail "trava viva deveria ficar vazia e intocada"
echo "ok: travas abandonadas apagadas, vivas intocadas"

# 4) Claude: AGENTS.md de projeto sempre, por cima de outro valor; o resto do settings fica
python3 - "$HOME/.claude/settings.json" <<'PY' || fail "settings.json do Claude"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["theme"] == "dark", d
for n in ("cc-plugin-agents-md@builtin", "agents-md@builtin"):
    assert d["pluginConfigs"][n]["options"]["instructionFiles"] == "claude-md-and-agents-md", d
PY
[[ -L $P/trabalho/settings.json ]] || fail "settings.json do perfil deveria continuar link"
echo "ok: Claude lê o AGENTS.md de projeto (instructionFiles imposto, resto preservado)"

# 5) idempotente
a=$(cksum <"$F")$(cksum <"$K"); tt --reforcar-agentes
[[ $(cksum <"$F")$(cksum <"$K") == "$a" ]] || fail "2ª volta não pode mudar nada"
echo "ok: idempotente"

# 6) normaliza de novo quando alguém mexe, sem ressuscitar o que o usuário apagou
printf 'regra nova do pacote\n' >>"$T/pkg/agentes-regras-tt.md"
printf '\nescrita pelo link\n' >>"$HOME/.claude/CLAUDE.md" # vai direto para a fonte
rm -f "$HOME/.codex/AGENTS.md"; { printf 'regra solta no codex\n\n'; cat "$F"; } >"$HOME/.codex/AGENTS.md" # ferramenta trocou o link por arquivo
printf '\nregra escrita no kiro\n' >>"$K"
sed -i '/^regra antiga do kiro$/d' "$F" # o usuário apagou da fonte
tt --reforcar-agentes
grep -q 'regra nova do pacote' "$F" && [[ $(grep -c 'regras-tt BEGIN' "$F") == 1 ]] || fail "bloco deveria ser atualizado no lugar"
grep -qx 'escrita pelo link' "$F" && grep -qx 'regra solta no codex' "$F" && grep -qx 'regra escrita no kiro' "$F" || fail "edições fora da fonte não chegaram nela"
[[ $(grep -c '^regra do codex$' "$F") == 1 ]] || fail "arquivo que era cópia da fonte duplicou parágrafos"
grep -qx 'regra antiga do kiro' "$F" && fail "parágrafo apagado da fonte voltou"
[[ $(readlink "$HOME/.codex/AGENTS.md") == ../.agents/AGENTS.md ]] || fail "link do Codex deveria voltar"
grep -q 'regra nova do pacote' "$K" && [[ $(grep -c '^regra escrita no kiro$' "$K") == 1 ]] || fail "cópia do Kiro deveria ser regerada da fonte"
echo "ok: reforço normaliza de novo (link, cópia do Kiro, bloco) sem perder nem ressuscitar texto"

# 7) override do Codex não esconde a fonte; a fonte já sendo link (dotfiles) recebe a escrita no destino
printf 'regra do override\n' >"$HOME/.codex/AGENTS.override.md"
mkdir -p "$HOME/dotfiles"; mv "$F" "$HOME/dotfiles/AGENTS.md"; ln -s ../dotfiles/AGENTS.md "$F"
tt --reforcar-agentes
[[ -e $HOME/.codex/AGENTS.override.md ]] && fail "override do Codex deveria ir para a fonte"
[[ -L $F ]] && grep -qx 'regra do override' "$HOME/dotfiles/AGENTS.md" || fail "fonte por link deveria continuar link e receber o texto"
echo "ok: override do Codex absorvido; fonte que é link continua link"
