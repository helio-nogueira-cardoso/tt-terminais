#!/usr/bin/env bash
# O tema dos agentes não pode criar nem trocar o settings.json de um perfil do Claude. No Mac (20/10) o perfil ainda sem o
# link ganhou um arquivo {"theme": "dark"} e o ia-conta passou a recusar abrir as quatro contas ("já tem 'settings.json'
# próprio"). Sem arquivo: o ia-conta cria o link. Link: segue link (o principal já recebe o tema). Arquivo próprio: só o tema.
source "$(dirname "$0")/lib.sh"; isolar
C="$HOME/.local/share/claude-contas"
mkdir -p "$HOME/.claude" "$HOME/dotfiles" "$C/semarquivo" "$C/comlink" "$C/proprio" "$T/bin"
printf '{"theme": "light", "hooks": {}}\n' >"$HOME/dotfiles/claude-settings.json"
ln -s "$HOME/dotfiles/claude-settings.json" "$HOME/.claude/settings.json"
ln -s "$HOME/.claude/settings.json" "$C/comlink/settings.json"
printf '{"theme": "light", "x": 1}\n' >"$C/proprio/settings.json"

PATH="$T/bin:$TT_PATH_BASE" bash "$T/pkg/tema-agentes.sh" >/dev/null 2>&1 || falhou "tema-agentes.sh saiu com erro"

[[ ! -e $C/semarquivo/settings.json && ! -L $C/semarquivo/settings.json ]] ||
  falhou "perfil sem settings.json ganhou um arquivo (o ia-conta não consegue mais criar o link)"
[[ -L $C/comlink/settings.json && $C/comlink/settings.json -ef $HOME/.claude/settings.json ]] ||
  falhou "o link do perfil para o settings.json principal virou arquivo"
[[ -L $HOME/.claude/settings.json && $HOME/.claude/settings.json -ef $HOME/dotfiles/claude-settings.json ]] ||
  falhou "o settings.json principal, que é link para os dotfiles, virou arquivo"
python3 - "$HOME/dotfiles/claude-settings.json" "$C/proprio/settings.json" <<'PY' || falhou "o tema não chegou onde devia ou levou outras chaves junto"
import json, sys
base, proprio = (json.load(open(p)) for p in sys.argv[1:])
assert base == {"theme": "dark", "hooks": {}}, base
assert proprio == {"theme": "dark", "x": 1}, proprio
PY
[[ -f $C/proprio/settings.json && ! -L $C/proprio/settings.json ]] || falhou "o arquivo próprio do perfil deixou de ser arquivo"
passou "tema dos agentes: perfil sem settings.json fica sem, links ficam links, arquivo próprio recebe só o tema"
