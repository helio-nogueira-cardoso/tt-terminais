#!/usr/bin/env bash
# Indexador de contatos: uma indexação por vez. Contas sincronizando em paralelo terminam juntas e cada uma
# disparava a sua (4 de uma vez, minutos cada, saturando o celular). Com a trava ocupada, a chamada sai sem rodar.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"
# email-tt.py de mentira no pacote isolado: conta as indexações (a única chamada que importa aqui)
cat >"$TT_DIR/email-tt.py" <<FIM
import sys
if "contatos-indexar" in sys.argv: open("$T/chamadas", "a").write("x\n")
FIM
export PATH=$T/bin:$PATH
echo 'S' | "$TT" --email-adicionar nome=Pessoal endereco=eu@gmail.com provedor=gmail auth=senha --senha-stdin >/dev/null || falhou 'cadastro'
mkdir -p "$HOME/.cache/tt/maildir/pessoal/INBOX/cur"
lock=$HOME/.cache/tt/email-contatos.tsv.lock
"$TT" --email-contatos-indexar || falhou 'indexar sem trava'
[[ $(wc -l <"$T/chamadas" 2>/dev/null) == 1 ]] || falhou "sem trava, deveria indexar uma vez: $(cat "$T/chamadas" 2>/dev/null)"
( flock 8; sleep 4 ) 8>"$lock" & seg=$!
sleep 1
"$TT" --email-contatos-indexar || falhou 'indexar com trava ocupada deveria sair com 0'
[[ $(wc -l <"$T/chamadas") == 1 ]] || falhou "com a trava ocupada, não deveria indexar de novo: $(cat "$T/chamadas")"
wait "$seg"
"$TT" --email-contatos-indexar || falhou 'indexar depois de soltar a trava'
[[ $(wc -l <"$T/chamadas") == 2 ]] || falhou "solta a trava, deveria indexar de novo: $(cat "$T/chamadas")"
passou 'indexador de contatos: uma por vez (trava ocupada pula; solta, volta a indexar)'
