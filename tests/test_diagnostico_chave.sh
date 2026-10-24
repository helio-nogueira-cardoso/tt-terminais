#!/usr/bin/env bash
# Chave SSH trocada no destino (máquina reinstalada) vira o rótulo chave-trocada, com a orientação, e não "falha não
# classificada". Usa um ssh falso que imprime o aviso do OpenSSH. Isola HOME/XDG; ssh é falso.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"
cat >"$T/bin/ssh" <<'SH'
#!/bin/sh
echo "@@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@@" >&2
echo "Host key verification failed." >&2
exit 255
SH
chmod +x "$T/bin/ssh"
export PATH="$T/bin:$TT_PATH_BASE"
est=$(TT_SO_CARREGAR=1 bash -c 'source "$1"; diagnosticar_conexao helio@maquina.exemplo' _ "$TT")
[[ $est == chave-trocada ]] || falhou "chave trocada deveria ser chave-trocada, veio: $est"
TT_SO_CARREGAR=1 bash -c 'source "$1"; explicar_diagnostico chave-trocada' _ "$TT" | grep -q "ssh-keygen -R" || falhou "a mensagem de chave trocada deveria orientar o ssh-keygen -R"
passou 'chave SSH trocada: rótulo chave-trocada com a orientação'
