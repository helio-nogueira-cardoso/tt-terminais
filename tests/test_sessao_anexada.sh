#!/usr/bin/env bash
# A janela do terminal nunca fecha sozinha: fechar_vazias pula sessão com cliente anexado
# (mesmo "vazia"), e o tmux.conf pede detach-on-destroy off.
source "$(dirname "$0")/lib.sh"; isolar
tmux -f /dev/null new -d -s viva 'sleep 300'; tmux new -d -s ociosa
anexar cli 80 24 ociosa; sleep 0.5
"$TT" --fechar-vazias >/dev/null 2>&1 || true
tmux has-session -t ociosa 2>/dev/null || falhou 'sessão anexada (embora vazia) foi morta — a aba do usuário fecharia'
grep -q 'detach-on-destroy off' "$TT_DIR/tmux.conf" || falhou 'tmux.conf sem detach-on-destroy off'
grep -q 'anexada > 0' "$TT" || falhou 'fechar_vazias sem a guarda de sessão anexada'
passou 'sessão com alguém olhando nunca é fechada; cliente nunca é desanexado à força'
echo 'ok: terminal não fecha sozinho'
