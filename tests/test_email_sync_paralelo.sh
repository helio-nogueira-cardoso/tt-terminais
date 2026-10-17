#!/usr/bin/env bash
# --email-sync (todas as contas): uma conta lenta não segura as outras. O mbsync de mentira da conta "lenta"
# demora 4 s; a "rapida" tem de aparecer no registro de sync enquanto a lenta ainda roda, e as duas terminam.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"
export PATH="$T/bin:$TT_PATH_BASE"
printf '#!/bin/sh\ncase "$3" in lenta*) sleep 4 ;; esac\nexit 0\n' >"$T/bin/mbsync"; chmod +x "$T/bin/mbsync"
for n in Lenta Rapida; do
  echo SENHA | "$TT" --email-adicionar "nome=$n" "endereco=$n@gmail.com" provedor=gmail auth=senha sync_local=1 --senha-stdin >/dev/null || falhou "cadastro $n"
done
ES=$HOME/.local/state/tt/email-sync
"$TT" --email-sync >/dev/null 2>&1 &
pid=$!
for _ in $(seq 1 30); do [[ -s $ES/rapida ]] && break; sleep 0.1; done
[[ -s $ES/rapida && ! -s $ES/lenta ]] || falhou "a rapida deveria terminar antes da lenta (rapida=$(cat "$ES/rapida" 2>/dev/null) lenta=$(cat "$ES/lenta" 2>/dev/null))"
wait "$pid"
[[ -s $ES/lenta ]] || falhou 'a lenta não terminou'
passou 'email-sync: as contas rodam em paralelo (a lenta não atrasa a rápida) e as duas terminam'
