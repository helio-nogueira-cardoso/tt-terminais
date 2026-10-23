#!/usr/bin/env bash
# tt-teste: sozinho (prazos de PTY e cancelamento, sem concorrência de testes gráficos)
source "$(dirname "$0")/lib.sh"; isolar
python3 "$RAIZ/tests/test_tela_recuperar.py" "$T/pkg/tela-recuperar.py" || falhou 'recuperação da tela'
grep -q 'bind Escape .*--recuperar-tela' "$T/pkg/tmux.conf" || falhou 'atalho local de escape ausente'
passou 'tela limpa, leitura sem eco, prazo até primeiro quadro, escape e sessão ociosa preservada'
