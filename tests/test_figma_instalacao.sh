#!/usr/bin/env bash
# Reforço distribui a skill inteira, preserva arquivos locais/links e funciona dentro do proot.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.kiro/skills" "$HOME/.agents/skills/figma-cota"
printf 'nota local\n' >"$HOME/.agents/skills/figma-cota/nota-local.txt"
ln -s "$HOME/.agents/skills/figma-cota" "$HOME/.kiro/skills/figma-cota"
"$TT" --reforcar-agentes
for destino in "$HOME/.agents" "$HOME/.claude" "$HOME/.codex" "$HOME/.kiro"; do
  for rel in SKILL.md scripts/figma_rest.py scripts/figma_oauth_retorno.py references/acesso-autenticacao.md; do
    cmp -s "$TT_DIR/skills/figma-cota/$rel" "$destino/skills/figma-cota/$rel" || falhou "recurso ausente/diferente: $destino $rel"
  done
done
[[ -L $HOME/.kiro/skills/figma-cota && -f $HOME/.agents/skills/figma-cota/nota-local.txt ]] || falhou 'perdeu link/nota local'
[[ ! -e $HOME/.cursor && ! -e $HOME/.secrets/figma.txt && ! -e $HOME/.kiro/settings/mcp.json ]] || falhou 'criou agente, segredo ou MCP sem pedido'
passou 'fonte compartilhada e três agentes recebem skill, scripts e referência; links/notas e autenticação preservados'

# Dano no recurso gerenciado é reparado; um recurso já igual nem chega ao cp (não renova mtime).
f=$HOME/.claude/skills/figma-cota/scripts/figma_rest.py
cp "$f" "$T/referencia"; touch -r "$f" "$T/mtime"
printf 'desatualizado\n' >"$HOME/.codex/skills/figma-cota/references/acesso-autenticacao.md"
"$TT" --reforcar-agentes
cmp -s "$f" "$T/referencia" && [[ ! $f -nt $T/mtime && ! $T/mtime -nt $f ]] || falhou 'reescreveu recurso igual'
cmp -s "$TT_DIR/skills/figma-cota/references/acesso-autenticacao.md" "$HOME/.codex/skills/figma-cota/references/acesso-autenticacao.md" || falhou 'não reparou recurso desatualizado'
passou 'reforço repara recurso alterado e não regrava os que já conferem'

# O tt antigo entrega um pacote sem os recursos novos: completar_pacote precisa criar os pais.
TT_SO_CARREGAR=1 source "$TT"
mkdir -p "$T/incompleto"; cp "$TT" "$T/incompleto/tt"
DIR_FONTE=$TT_DIR completar_pacote "$T/incompleto"
for f in "${ARQUIVOS_SKILL_FIGMA[@]}"; do
  cmp -s "$TT_DIR/$f" "$T/incompleto/$f" || falhou "completar pacote perdeu caminho: $f"
done
passou 'pacote de atualizador antigo ganha recursos aninhados completos'

# O tar de um clone de desenvolvimento mantém os caminhos; o tt instalado também o retransmite.
repo=$T/clone; cp -R "$T/pkg" "$repo"; mkdir "$repo/.git"
REPO_TT=$repo pacote >"$T/pacote.tar"
mkdir "$T/extraido"; tar -C "$T/extraido" -xf "$T/pacote.tar"
for f in "${ARQUIVOS_SKILL_FIGMA[@]}"; do
  cmp -s "$TT_DIR/$f" "$T/extraido/$f" || falhou "tar perdeu recurso: $f"
done
passou 'pacote do clone inclui os recursos sem achatar seus caminhos'

# Reforço em rootfs existente: copia as fontes ao pacote e aos agentes, sem entrar em proot novo.
export PREFIX=$T/termux
r=$PREFIX/var/lib/proot-distro/containers/debian/rootfs/root
mkdir -p "$r/.local/share/tt" "$r/.kiro" "$PREFIX/var/lib/proot-distro/containers/novo/rootfs/root"
reforcar_agentes || falhou "reforço do proot falhou"
for f in "${ARQUIVOS_SKILL_FIGMA[@]}"; do
  cmp -s "$TT_DIR/$f" "$r/.local/share/tt/$f" || falhou "proot perdeu fonte: $f"
done
cmp -s "$TT_DIR/skills/figma-cota/scripts/figma_oauth_retorno.py" "$r/.kiro/skills/figma-cota/scripts/figma_oauth_retorno.py" || falhou 'Kiro do proot sem auxiliar'
[[ ! -e $PREFIX/var/lib/proot-distro/containers/novo/rootfs/root/.agents ]] || falhou 'tocou proot sem tt'
passou 'reforço chega ao proot já provisionado, sem criar instalação em outro rootfs'
