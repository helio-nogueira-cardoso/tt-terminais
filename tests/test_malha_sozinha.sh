#!/usr/bin/env bash
# Máquina sozinha na malha (nenhuma outra cadastrada): o diagnóstico local não tem par a listar e vazio é o certo. `tt --malha` acusava
# "1 conexão quebrada" (a própria máquina "não respondeu") e o vigia avisava uma ilha que não existe.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
rm -f "$HOME/.config/tt/maquinas" 2>/dev/null; : >"$XDG_CONFIG_HOME/tt/maquinas" 2>/dev/null || true
rc=0; saida=$("$TT" --malha 2>&1) || rc=$?
[[ $rc == 0 ]] || falhou "sozinha na malha, tt --malha deveria sair 0 (saiu $rc): $saida"
[[ $saida == *"sem outras máquinas cadastradas"* ]] || falhou "faltou a explicação (sem outras máquinas cadastradas): $saida"
[[ $saida == *"Malha completa"* && $saida != *"quebrada(s)"* ]] || falhou "acusou conexão quebrada numa máquina sozinha: $saida"
passou 'malha: máquina sozinha não é ilha (sai 0, explica e não acusa conexão quebrada)'
