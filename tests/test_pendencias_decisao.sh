#!/usr/bin/env bash
# Pendências de instalação: mais tarde (volta em 1 dia), não instalar (nunca mais avisa), reavaliar
# pelo menu (TT_PEND_TODAS), plugin XOAUTH2 compilado na pasta do usuário e o aviso do vigia.
source "$(dirname "$0")/lib.sh"; isolar
B=$T/bin; mkdir -p "$B" "$HOME/.config/tt/email"
printf '#!/bin/sh\n:\n' >"$B/apt-get"; chmod +x "$B/apt-get"
printf '#!/bin/sh\necho "$@" >> %s/sudo.log\n' "$T" >"$B/sudo"; chmod +x "$B/sudo"
printf 'nome=X\nendereco=x@y.z\nauth=oauth\nsync_local=1\n' >"$HOME/.config/tt/email/x.conf"
ES=$HOME/.local/state/tt
FALTA="curl unzip mbsync w3m vim xoauth2 xoauth2-build cc gcc"
roda() { PATH="$B:$PATH" TT_TTY="$T/resposta" TT_FINGE_FALTA="$FALTA" TT_SASL_INCLUDE="$T/inc" "$TT" --pedir-sudo "$@" 2>&1; }
limpar() { rm -f "$ES"/sudo-recusado-* "$ES"/navegadores-sudo-recusado "$ES"/pendencias-avisadas; }

# 1) O XOAUTH2 entra na lista com conta OAuth + sync local, com os pacotes de compilação.
printf m >"$T/resposta"; saida=$(roda) || true
grep -q 'plugin XOAUTH2' <<<"$saida" || grep -q 'compilador + cabeçalhos do SASL' <<<"$saida" || falhou "xoauth2 não apareceu: $saida"
grep -q 'gcc libc6-dev libsasl2-dev' <<<"$saida" || falhou "pacotes de compilação ausentes do comando: $saida"
passou 'conta OAuth com sync local gera a pendência do plugin XOAUTH2 (compilador + cabeçalhos do SASL)'

# 2) Mais tarde: não pergunta agora, volta depois de 1 dia.
v=$(cat "$ES/sudo-recusado-email-xoauth2"); [[ $v =~ ^[0-9]+$ ]] || falhou "mais tarde deveria gravar uma hora: [$v]"
grep -q 'Nada pendente' <<<"$(roda)" || falhou 'adiado voltou na hora'
for f in "$ES"/sudo-recusado-* "$ES"/navegadores-sudo-recusado; do echo $(( $(cat "$f") - 90000 )) >"$f"; done
grep -q 'bibliotecas\|mbsync\|XOAUTH2\|SASL' <<<"$(printf m >"$T/resposta"; roda)" || falhou 'adiado não voltou depois de 1 dia'
passou 'mais tarde: some agora e volta depois de 1 dia'

# 3) Não instalar: nunca mais avisa, nem depois de dias; o menu (TT_PEND_TODAS) reabre tudo.
limpar; printf n >"$T/resposta"; roda >/dev/null || true
[[ $(cat "$ES/sudo-recusado-email-xoauth2") == nunca ]] || falhou 'não instalar deveria gravar "nunca"'
grep -q 'Nada pendente' <<<"$(roda)" || falhou 'depois do "não instalar" voltou a perguntar'
printf n >"$T/resposta"; saida=$(TT_PEND_TODAS=1 roda) || true
grep -q 'XOAUTH2\|SASL' <<<"$saida" || falhou "reavaliar pelo menu não reabriu o que foi recusado: $saida"
passou 'não instalar: nunca mais avisa; reavaliar pelo menu reabre tudo'

# 4) Aviso do vigia: um aviso com ação pendencias; sem repetir; nada se foi "nunca".
limpar; rm -rf "$ES/notifs"
PATH="$B:$PATH" TT_FINGE_FALTA="$FALTA" "$TT" --pendencias-avisar
n=$(grep -l 'pendencias$' "$ES"/notifs/* 2>/dev/null | wc -l); ((n == 1)) || falhou "esperava 1 aviso com ação pendencias, vi $n"
PATH="$B:$PATH" TT_FINGE_FALTA="$FALTA" "$TT" --pendencias-avisar
n=$(ls "$ES"/notifs | wc -l); ((n == 1)) || falhou "avisou de novo o mesmo conjunto ($n)"
passou 'vigia: um aviso por conjunto de pendências, a cada 24 h no máximo'
limpar; rm -rf "$ES/notifs"; printf n >"$T/resposta"; roda >/dev/null || true
PATH="$B:$PATH" TT_FINGE_FALTA="$FALTA" "$TT" --pendencias-avisar
[[ -z $(ls "$ES/notifs" 2>/dev/null) ]] || falhou 'avisou do que o usuário mandou não instalar'
passou 'vigia não avisa do que foi recusado de vez'

# 5) Instalar: apt roda, depois o tt compila o plugin na pasta do usuário (cc e curl de mentira).
limpar; mkdir -p "$T/inc/sasl" "$T/fonte"; : >"$T/inc/sasl/sasl.h"
for f in xoauth2_str xoauth2_init xoauth2_server xoauth2_client; do echo "int $f;" >"$T/fonte/$f.c"; done
tar czf "$T/x.tgz" -C "$T/fonte" .
cat >"$B/cc" <<'CC'
#!/bin/sh
while [ $# -gt 0 ]; do [ "$1" = -o ] && o=$2; shift; done
echo plugin >"$o"
CC
chmod +x "$B/cc"
FAL="curl unzip mbsync w3m vim xoauth2-build"   # cc existe (o de mentira); só o pacote "falta"
printf i >"$T/resposta"; : >"$T/sudo.log"
sha=$(sha256sum "$T/x.tgz" | cut -d' ' -f1)
PATH="$B:$PATH" TT_TTY="$T/resposta" TT_FINGE_FALTA="$FAL" TT_SASL_INCLUDE="$T/inc" TT_XOAUTH2_URL="file://$T/x.tgz" TT_XOAUTH2_SHA256="$sha" \
  "$TT" --pedir-sudo email-xoauth2 >"$T/saida.txt" 2>&1 || { cat "$T/saida.txt"; falhou 'instalar o xoauth2 deveria sair com sucesso'; }
grep -q 'gcc libc6-dev libsasl2-dev' "$T/sudo.log" || falhou "sudo não instalou o compilador: $(cat "$T/sudo.log")"
[[ -s $HOME/.local/share/tt-sasl2/libxoauth2.so ]] || { cat "$T/saida.txt"; falhou 'plugin não foi construído na pasta do usuário'; }
# sha errado → recusa e não instala
rm -rf "$HOME/.local/share/tt-sasl2"
PATH="$B:$PATH" TT_TTY="$T/resposta" TT_FINGE_FALTA="$FAL" TT_SASL_INCLUDE="$T/inc" TT_XOAUTH2_URL="file://$T/x.tgz" TT_XOAUTH2_SHA256=0000 \
  "$TT" --pedir-sudo email-xoauth2 >/dev/null 2>&1 && falhou 'sha256 errado deveria falhar'
[[ ! -e $HOME/.local/share/tt-sasl2/libxoauth2.so ]] || falhou 'plugin com sha errado foi instalado'
passou 'instalar: sudo para o compilador, depois o plugin é compilado na pasta do usuário (sha256 conferido)'
echo "TODOS OS TESTES PASSARAM"
