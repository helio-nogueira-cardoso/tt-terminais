#!/usr/bin/env bash
# tt-teste: sozinho (lança vigia e mede o diretório dele)
# O vigia vive dias e herdava o diretório de quem o lançou. Apagado esse diretório (um worktree, uma pasta temporária), todo git e todo
# subprocesso falhavam com "getcwd: impossível acessar os diretórios pais" e a sonda de atualização acusava "rede" para sempre:
# o Mac ficou 16 sondas seguidas sem atualizar. Agora o vigia vai para a pasta pessoal ao começar.
source "$(dirname "$0")/lib.sh"; isolar
tmux -f /dev/null new -d -s s 'sleep 600'
efemero=$T/efemero; mkdir -p "$efemero"
( cd "$efemero" && TT_PAUSA=2 exec "$TT" --vigia >/dev/null 2>&1 ) &
sleep 3
p=$(cat "$TT_RT/tt-vigia-$(id -u).pid" 2>/dev/null); [[ -n $p ]] && kill -0 "$p" 2>/dev/null || falhou 'o vigia não subiu'
rmdir "$efemero"                      # o diretório de onde ele foi lançado deixa de existir
sleep 1
cwd=$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'); [[ -z $cwd ]] && cwd=$(readlink "/proc/$p/cwd" 2>/dev/null || true)
real_home=$(cd "$HOME" && pwd -P)
[[ -d $cwd && ( $cwd == "$HOME" || $cwd == "$real_home" ) ]] || falhou "o vigia deveria estar na pasta pessoal, está em: ${cwd:-?}"
# e um git roda de dentro do processo dele (o que a sonda faz): o diretório de trabalho é utilizável
( cd "$cwd" && git --version >/dev/null && pwd >/dev/null ) || falhou 'o diretório do vigia não é utilizável'
kill "$p" 2>/dev/null
# quem religa o vigia (clique, gancho) também o manda para a pasta pessoal
grep -q 'tmux run-shell -b -c "\$HOME" "\$HOME/.local/bin/tt --vigia"' "$RAIZ/tt" || falhou 'vigia_garantir deveria usar run-shell -c "$HOME"'
[[ $(grep -c 'run-shell -b "\$HOME/.local/bin/tt --vigia"' "$RAIZ/tt") == 0 ]] || falhou 'sobrou um lançamento do vigia sem -c "$HOME"'
passou 'vigia lançado de um diretório que some continua numa pasta válida (pasta pessoal); quem o religa também o põe lá'
