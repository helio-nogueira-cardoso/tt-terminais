# Atalhos do celular (Termux), lidos pelo ~/.bashrc (linha "# tt-celular" de termux/celular.sh).
# O Debian (proot-distro) enxerga a home do Termux no mesmo caminho, então a pasta atual vale lá.

# dbn: shell no Debian na pasta atual (dbn <comando> executa um comando lá). O comando leva o
# ~/.local/bin (claude, ia-conta) no PATH mesmo que o ~/.bashrc do Debian tenha perdido a linha.
dbn() { local c; if (($#)); then c='PATH="$HOME/.local/bin:$PATH"; '$(printf '%q ' "$@"); else c='exec bash -l'; fi
  proot-distro login "${TT_DISTRO:-debian}" --shared-tmp --work-dir "$PWD" -- bash -lc "$c"; }

# cl: Claude Code na pasta atual; clc continua a última conversa; clr escolhe uma; clu atualiza.
# Root no proot: IS_SANDBOX=1 libera --dangerously-skip-permissions; o socket de mensagens vai
# num caminho explícito porque o proot não mapeia uid.
_cl() { dbn env IS_SANDBOX=1 claude --dangerously-skip-permissions --messaging-socket-path "$HOME/.claude/run/msg-$$.sock" "$@"; }
cl()  { _cl "$@"; }
clc() { _cl --continue "$@"; }
clr() { _cl --resume "$@"; }
clu() { dbn claude update; }
