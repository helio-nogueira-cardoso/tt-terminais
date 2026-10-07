#!/usr/bin/env bash
# Celular (Termux): os agentes rodam no proot-distro. A instalação espelha o pacote dentro do proot
# que já tem /root/.local/share/tt (links ia-*/claude-*, versão antiga guardada, skill, link para o
# cadastro do Termux) e não toca num proot sem ela; o Termux ganha só o ia-login, que pergunta ao proot.
source "$(dirname "$0")/lib.sh"
isolar
P=$T/com.termux/usr
RF=$P/var/lib/proot-distro/containers/debian/rootfs
OUTRO=$P/var/lib/proot-distro/containers/ubuntu/rootfs
mkdir -p "$RF/root/.local/share/tt" "$RF/root/.local/bin" "$RF/root/.claude" "$OUTRO/root/.claude"
printf '#!/bin/sh\n# claude-rot — roda um agente headless (antigo)\n' >"$RF/root/.local/bin/claude-rot"
printf '#!/bin/sh\n# meu script\n' >"$RF/root/.local/bin/claude-conta"
PREFIX=$P TT_DIR=$HOME/.local/share/tt "$T/pkg/tt" --instalar-aqui >/dev/null 2>&1 || falhou 'instalação no Termux'

for f in ia-conta ia-rot ia-login contas-uso.py tt VERSAO; do
  cmp -s "$T/pkg/$f" "$RF/root/.local/share/tt/$f" || falhou "proot sem $f do pacote"
done
for n in ia-conta ia-rot claude-rot ia-login; do
  [[ $(readlink "$RF/root/.local/bin/$n") == /root/.local/share/tt/* ]] || falhou "link $n no proot: $(readlink "$RF/root/.local/bin/$n")"
done
grep -q 'meu script' "$RF/root/.local/bin/claude-conta" || falhou 'script alheio no proot foi trocado'
grep -q 'antigo' "$RF/root/.local/bin/claude-rot.antes-tt" || falhou 'claude-rot antigo do proot não foi guardado'
grep -q '^name: rodizio-de-contas' "$RF/root/.claude/skills/rodizio-de-contas/SKILL.md" || falhou 'skill no proot'
[[ $(readlink "$RF/root/.config/tt/contas-ia") == "$XDG_CONFIG_HOME/tt/contas-ia" ]] || falhou 'cadastro do proot não aponta para o do Termux'
[[ -e $OUTRO/root/.local || -e $OUTRO/root/.claude/skills ]] && falhou 'mexeu num proot sem tt'
[[ -L $HOME/.local/bin/ia-login ]] || falhou 'Termux sem ia-login'
[[ -e $HOME/.local/bin/ia-conta || -e $HOME/.local/bin/claude-rot ]] && falhou 'Termux ganhou ia-conta/claude-rot (os agentes ficam no proot)'
passou 'Termux: pacote espelhado no proot com tt, links, skill e cadastro; proot sem tt e Termux intocados'

# ia-login no Termux pergunta ao proot (proot-distro falso registra a chamada).
mkdir -p "$T/fb"
printf '#!/bin/sh\necho "proot $*"\n' >"$T/fb/proot-distro"; chmod +x "$T/fb/proot-distro"
out=$(PREFIX=$P PATH=$T/fb:/usr/bin:/bin "$HOME/.local/bin/ia-login" --faltas)
[[ $out == "proot login debian -- env HOME=/root PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin ia-login --faltas" ]] ||
  falhou "ia-login não delegou ao proot: $out"
passou 'ia-login no Termux delega o --faltas ao proot que tem o tt'
