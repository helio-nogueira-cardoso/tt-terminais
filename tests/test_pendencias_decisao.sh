#!/usr/bin/env bash
# Pendências de instalação: mais tarde (volta em 1 dia), não instalar (nunca mais avisa), reavaliar pelo
# menu (TT_PEND_TODAS), plugin XOAUTH2 compilado na pasta do usuário e o aviso do vigia (dura 6 h, não
# repete em 12 h, ignora opcionais e o que o tt não instala sozinho).
source "$(dirname "$0")/lib.sh"; isolar
B=$T/bin; mkdir -p "$B" "$HOME/.config/tt/email"
cat >"$B/apt-get" <<'EOF'
#!/bin/sh
case "$*" in *install*) echo "$*" >> "$SUDOLOG"; [ -n "$TT_FINGE_FALTA_ARQ" ] && : > "$TT_FINGE_FALTA_ARQ";; esac
exit 0
EOF
printf '#!/bin/sh\nexec "$@"\n' >"$B/sudo"
printf '#!/bin/sh\necho "  Candidate: 1.0"\n' >"$B/apt-cache"
for f in aerc vim; do printf '#!/bin/sh\n:\n' >"$B/$f"; done
chmod +x "$B"/*
printf 'nome=X\nendereco=x@y.z\nauth=oauth\nsync_local=1\n' >"$HOME/.config/tt/email/x.conf"
export SUDOLOG=$T/sudo.log FALTAS=$T/faltas TT_GERENCIADOR=apt-get TT_PRIV=sudo TT_SO=linux TT_AMBIENTE=nativo TT_SASL_INCLUDE="$T/inc"
mkdir -p "$T/inc/sasl" "$T/inc/openssl"; : >"$T/inc/sasl/sasl.h"; : >"$T/inc/openssl/md5.h"
ES=$HOME/.local/state/tt
FALTA="curl mbsync w3m xoauth2 xoauth2-build"
roda() { PATH="$B:$PATH" TT_TTY="$T/resposta" TT_FINGE_FALTA="$FALTA" "$TT" --pedir-sudo "$@" 2>&1; }
limpar() { rm -f "$ES"/sudo-recusado-* "$ES"/navegadores-sudo-recusado "$ES"/pendencias-avisadas; rm -rf "$ES/pendencias.trava"; }

# 1) O XOAUTH2 entra na lista com conta OAuth + sync local, com os pacotes de compilação.
printf m >"$T/resposta"; saida=$(roda) || true
grep -q 'plugin XOAUTH2 do SASL' <<<"$saida" || falhou "xoauth2 não apareceu: $saida"
grep -q 'gcc libc6-dev libsasl2-dev libssl-dev' <<<"$saida" || falhou "pacotes de compilação ausentes do comando: $saida"
grep -q 'Baixado/compilado na sua pasta' <<<"$saida" || falhou "o modal deveria separar o que só compila na pasta do usuário: $saida"
passou 'conta OAuth com sync local gera a pendência do plugin XOAUTH2 (compilador + cabeçalhos do SASL e do OpenSSL)'

# 2) Mais tarde: não pergunta agora, volta depois de 1 dia.
v=$(cat "$ES/sudo-recusado-email-xoauth2"); [[ $v =~ ^[0-9]+$ ]] || falhou "mais tarde deveria gravar uma hora: [$v]"
grep -q 'Nada pendente' <<<"$(roda)" || falhou 'adiado voltou na hora'
for f in "$ES"/sudo-recusado-*; do echo $(( $(cat "$f") - 90000 )) >"$f"; done
grep -q 'XOAUTH2\|mbsync\|ferramentas' <<<"$(printf m >"$T/resposta"; roda)" || falhou 'adiado não voltou depois de 1 dia'
passou 'mais tarde: some agora e volta depois de 1 dia'

# 3) Não instalar: nunca mais avisa, nem depois de dias; o menu (TT_PEND_TODAS) reabre tudo.
limpar; printf n >"$T/resposta"; roda >/dev/null || true
[[ $(cat "$ES/sudo-recusado-email-xoauth2") == nunca ]] || falhou 'não instalar deveria gravar "nunca"'
grep -q 'Nada pendente' <<<"$(roda)" || falhou 'depois do "não instalar" voltou a perguntar'
printf n >"$T/resposta"; saida=$(TT_PEND_TODAS=1 roda) || true
grep -q 'XOAUTH2' <<<"$saida" || falhou "reavaliar pelo menu não reabriu o que foi recusado: $saida"
passou 'não instalar: nunca mais avisa; reavaliar pelo menu reabre tudo'

# 4) Aviso do vigia: um aviso com ação pendencias, que dura 6 h; sem repetir em 12 h; nada se foi "nunca".
limpar; rm -rf "$ES/notifs"
PATH="$B:$PATH" TT_FINGE_FALTA="$FALTA" "$TT" --pendencias-avisar
n=$(grep -l 'pendencias$' "$ES"/notifs/* 2>/dev/null | wc -l); ((n == 1)) || falhou "esperava 1 aviso com ação pendencias, vi $n"
arq=$(grep -l 'pendencias$' "$ES"/notifs/* | head -1); exp=$(cut -f1 "$arq"); dura=$(( exp - $(date +%s) ))
(( dura > 20000 && dura <= 21600 )) || falhou "o aviso deveria durar 6 h (21600 s), durou $dura s"
PATH="$B:$PATH" TT_FINGE_FALTA="$FALTA" "$TT" --pendencias-avisar
n=$(ls "$ES"/notifs | wc -l); ((n == 1)) || falhou "avisou de novo o mesmo conjunto ($n)"
echo "$(cut -f1 "$ES/pendencias-avisadas")	$(( $(date +%s) - 50000 ))" >"$ES/pendencias-avisadas"   # passaram 13 h
PATH="$B:$PATH" TT_FINGE_FALTA="$FALTA" "$TT" --pendencias-avisar
n=$(ls "$ES"/notifs | grep -vc '\.lida$'); ((n == 2)) || falhou "depois de 12 h o aviso deveria voltar (vi $n)"
passou 'vigia: um aviso por conjunto, que dura 6 h e só volta depois de 12 h'
limpar; rm -rf "$ES/notifs"; printf n >"$T/resposta"; roda >/dev/null || true
PATH="$B:$PATH" TT_FINGE_FALTA="$FALTA" "$TT" --pendencias-avisar
[[ -z $(ls "$ES/notifs" 2>/dev/null) ]] || falhou 'avisou do que o usuário mandou não instalar'
passou 'vigia não avisa do que foi recusado de vez'

# 4b) Opcionais (pv, mosh…) e o que o tt não instala sozinho (tmux antigo) não geram aviso.
limpar; rm -rf "$ES/notifs"; rm -f "$HOME/.config/tt/email/x.conf"
PATH="$B:$PATH" TT_FINGE_FALTA="pv mosh notify-send" TT_FINGE_TMUX_VERSAO=3.0 "$TT" --pendencias-avisar
[[ -z $(ls "$ES/notifs" 2>/dev/null) ]] || falhou "avisou de opcional ou de pendência manual: $(cat "$ES"/notifs/* 2>/dev/null)"
printf 'nome=X\nendereco=x@y.z\nauth=oauth\nsync_local=1\n' >"$HOME/.config/tt/email/x.conf"
passou 'vigia ignora opcionais e pendências que o tt não resolve sozinho'

# 5) Instalar: o gerenciador roda, depois o tt compila o plugin na pasta do usuário (cc de mentira, tarball local).
limpar; mkdir -p "$T/fonte"
for f in xoauth2_str xoauth2_init xoauth2_server xoauth2_client; do echo "int $f;" >"$T/fonte/$f.c"; done
tar czf "$T/x.tgz" -C "$T/fonte" .
cat >"$B/cc" <<'CC'
#!/bin/sh
while [ $# -gt 0 ]; do [ "$1" = -o ] && o=$2; shift; done
echo plugin >"$o"
CC
chmod +x "$B/cc"
echo "xoauth2-build" >"$FALTAS"   # cc existe (o de mentira); só o pacote "falta" até o apt-get de mentira "instalar"
sha=$(sha256sum "$T/x.tgz" | cut -d' ' -f1)
printf i >"$T/resposta"; : >"$SUDOLOG"
PATH="$B:$PATH" TT_TTY="$T/resposta" TT_FINGE_FALTA_ARQ="$FALTAS" TT_XOAUTH2_URL="file://$T/x.tgz" TT_XOAUTH2_SHA256="$sha" \
  "$TT" --pedir-sudo email-xoauth2 >"$T/saida.txt" 2>&1 || { cat "$T/saida.txt"; falhou 'instalar o xoauth2 deveria sair com sucesso'; }
grep -q 'install gcc libc6-dev libsasl2-dev libssl-dev$' "$SUDOLOG" || falhou "o gerenciador não instalou o compilador: $(cat "$SUDOLOG")"
[[ -s $HOME/.local/share/tt-sasl2/libxoauth2.so ]] || { cat "$T/saida.txt"; falhou 'plugin não foi construído na pasta do usuário'; }
# sha errado → recusa e não instala
rm -rf "$HOME/.local/share/tt-sasl2"; echo "xoauth2-build" >"$FALTAS"; limpar
PATH="$B:$PATH" TT_TTY="$T/resposta" TT_FINGE_FALTA_ARQ="$FALTAS" TT_XOAUTH2_URL="file://$T/x.tgz" TT_XOAUTH2_SHA256=0000 \
  "$TT" --pedir-sudo email-xoauth2 >/dev/null 2>&1 && falhou 'sha256 errado deveria falhar'
[[ ! -e $HOME/.local/share/tt-sasl2/libxoauth2.so ]] || falhou 'plugin com sha errado foi instalado'
passou 'instalar: o gerenciador traz o compilador, depois o plugin é compilado na pasta do usuário (sha256 conferido)'

# 6) SASL_PATH (plugin XOAUTH2 do tt) só vai para conta OAuth: conta de senha não pode vê-lo, senão o
#    mbsync o escolhe e manda a senha como token (AUTHENTICATIONFAILED no Gmail).
mkdir -p "$HOME/.local/share/tt-sasl2" "$HOME/.config/tt/mbsync"; : >"$HOME/.local/share/tt-sasl2/libxoauth2.so"
printf 'nome=O\nendereco=o@y.z\nauth=oauth\nsync_local=1\n' >"$HOME/.config/tt/email/oa.conf"
printf 'nome=S\nendereco=s@y.z\nauth=comando\nsync_local=1\n' >"$HOME/.config/tt/email/se.conf"
printf '#!/bin/sh\necho "$SASL_PATH" > "%s/sasl-$3"\n' "$T" >"$B/mbsync"; chmod +x "$B/mbsync"
for sl in oa se; do printf 'Channel %s-inbox\n' "$sl" >"$HOME/.config/tt/mbsync/$sl.mbsyncrc"; done
for sl in oa se; do PATH="$B:$PATH" "$TT" --email-sync "$sl" >/dev/null 2>&1; done
grep -q 'tt-sasl2' "$T/sasl-oa-inbox" || falhou "conta OAuth não recebeu o SASL_PATH do tt: $(cat "$T/sasl-oa-inbox" 2>/dev/null)"
! grep -q 'tt-sasl2' "$T/sasl-se-inbox" || falhou "conta de senha recebeu o plugin XOAUTH2: $(cat "$T/sasl-se-inbox")"
passou 'SASL_PATH com o plugin do tt só vai para contas OAuth'

echo "TODOS OS TESTES PASSARAM"
