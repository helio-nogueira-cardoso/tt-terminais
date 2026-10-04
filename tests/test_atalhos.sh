#!/usr/bin/env bash
# Atalhos da barra: perfil de PC, perfil de celular (Termux), e personalização local por ID.
source "$(dirname "$0")/lib.sh"; isolar
ids() { "$TT" --atalhos-lista | cut -f2 | tr '\n' ' '; }

[[ $(ids) == "kiro-v3 claude-resume codex " ]] || falhou "padrão do PC deveria ter 3 atalhos: $(ids)"
"$TT" --atalhos-lista | grep -q $'\tclaude --dangerously-skip-permissions --resume\t' || falhou 'claude do PC sem --resume'
passou 'PC: 3 atalhos padrão (kiro, claude com --resume, codex)'

m=$(PREFIX=/data/data/com.termux/files/usr "$TT" --atalhos-lista)
grep -q 'proot-distro login debian' <<<"$m" || falhou 'celular: atalhos não entram no Debian (proot)'
grep -q 'IS_SANDBOX=1 claude --dangerously-skip-permissions' <<<"$m" || falhou 'celular: claude sem IS_SANDBOX como root'
grep -q $'\tcodex\t' <<<"$m" && falhou 'celular: atalho de codex sem codex instalado'
passou 'celular: perfil mobile (claude no Debian via proot, IS_SANDBOX)'

c=$XDG_CONFIG_HOME/tt/atalhos
printf '🔧\tcodex\tcodex --yolo\t#f38ba8\n-\tkiro-v3\t\t\n⚡\tmeu\thtop\t#a6e3a1\n' >"$c"
[[ $(ids) == "claude-resume codex meu " ]] || falhou "personalização: $(ids)"
"$TT" --atalhos-lista | grep -q $'^🔧\tcodex\tcodex --yolo' || falhou 'troca de um padrão pelo mesmo ID'
passou 'local: troca padrão pelo ID, "-" desativa, ID novo acrescenta no fim'

printf '🅰\tum\tls\t\n🅱\tdois\tls\t\n🅰\tum\tpwd\t\n' >"$c"
[[ $("$TT" --atalhos-lista | awk -F'\t' '$2 == "um"' | wc -l) == 1 ]] || falhou 'ID repetido aparece duas vezes'
"$TT" --atalhos-lista | grep -q $'\tum\tpwd' || falhou 'a última linha de um ID deveria valer'
passou 'ID repetido no arquivo local: vale a última, sem duplicar o botão'
