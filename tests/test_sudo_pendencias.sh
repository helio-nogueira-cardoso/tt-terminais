#!/usr/bin/env bash
# Modal único de pendências sudo: reúne tudo o que falta (navegadores, sync local, w3m), com
# instalar agora / selecionar / mais tarde / não instalar (nunca mais avisa); id explícito reabre mesmo
# recusado; nomes de pacote por gerenciador (mbsync → isync).
source "$(dirname "$0")/lib.sh"; isolar
B=$T/bin; mkdir -p "$B" "$HOME/.config/tt/email"
printf '#!/bin/sh\n:\n' >"$B/apt-get"; chmod +x "$B/apt-get"
printf '#!/bin/sh\necho "$@" >> %s/sudo.log\n' "$T" >"$B/sudo"; chmod +x "$B/sudo"
printf 'nome=X\nendereco=x@y.z\n' >"$HOME/.config/tt/email/x.conf" # com conta, mbsync/w3m entram
FALTA="curl unzip mbsync w3m"
roda() { PATH="$B:$PATH" TT_TTY="$T/resposta" TT_FINGE_FALTA="$FALTA" "$TT" --pedir-sudo "$@" 2>&1; }

# 1) Tudo pendente aparece junto, num comando só, com os nomes de pacote certos.
printf r >"$T/resposta"; : >"$T/sudo.log"
saida=$(roda) || true
grep -q 'curl unzip' <<<"$saida" && grep -q 'mbsync' <<<"$saida" && grep -q 'w3m' <<<"$saida" ||
  falhou "modal não reuniu as três pendências: $saida"
grep -q 'sudo apt-get install -y curl unzip isync w3m' <<<"$saida" || falhou "comando agregado errado: $saida"
[[ ! -s $T/sudo.log ]] || falhou 'recusar rodou sudo'
[[ -s $HOME/.local/state/tt/navegadores-sudo-recusado && -s $HOME/.local/state/tt/sudo-recusado-email-sync \
   && -s $HOME/.local/state/tt/sudo-recusado-email-html ]] || falhou 'recusa não foi gravada por item'
grep -q 'Nada pendente' <<<"$(roda)" || falhou 'recusado há pouco voltou a ser oferecido'
passou 'pendências reunidas num comando só (isync pelo mbsync); recusa por item, lembrada (n = nunca mais avisar)'

# 2) Id explícito reabre mesmo recusado (o usuário pediu pela interface) e instala só aquilo.
printf a >"$T/resposta"; : >"$T/sudo.log"
roda email-sync >/dev/null || falhou 'aceitar id explícito deveria instalar'
[[ $(cat "$T/sudo.log") == "apt-get install -y isync" ]] || falhou "id explícito instalou outra coisa: $(cat "$T/sudo.log")"
passou 'id explícito ignora a recusa e instala só o pedido'

# 3) Selecionar: aceita o 1º item, recusa os demais; instala só o aceito.
rm -f "$HOME/.local/state/tt"/navegadores-sudo-recusado "$HOME/.local/state/tt"/sudo-recusado-*
printf ssnn >"$T/resposta"; : >"$T/sudo.log"
roda >/dev/null || falhou 'selecionar com um aceite deveria sair com sucesso'
[[ $(cat "$T/sudo.log") == "apt-get install -y curl unzip" ]] || falhou "selecionar instalou outra coisa: $(cat "$T/sudo.log")"
[[ ! -s $HOME/.local/state/tt/navegadores-sudo-recusado ]] || falhou 'item aceito foi marcado como recusado'
[[ -s $HOME/.local/state/tt/sudo-recusado-email-sync && -s $HOME/.local/state/tt/sudo-recusado-email-html ]] ||
  falhou 'itens não escolhidos não viraram recusa'
passou 'selecionar: instala só o aceito e grava recusa dos demais'

# 3b) Bibliotecas do Chrome/Carbonyl baixados também são pendência, com tradução por gerenciador.
rm -f "$HOME/.local/state/tt"/navegadores-sudo-recusado "$HOME/.local/state/tt"/sudo-recusado-*
printf a >"$T/resposta"; : >"$T/sudo.log"
PATH="$B:$PATH" TT_TTY="$T/resposta" TT_FINGE_CHROME_LIBS="libnss3 libnspr4" "$TT" --pedir-sudo chrome-libs >/dev/null ||
  falhou 'aceitar chrome-libs deveria instalar'
[[ $(cat "$T/sudo.log") == "apt-get install -y libnss3 libnspr4" ]] ||
  falhou "chrome-libs instalou outra coisa: $(cat "$T/sudo.log")"
saida=$(PATH="$B:$PATH" TT_TTY="$T/resposta" TT_FINGE_FALTA="$FALTA" TT_FINGE_CHROME_LIBS="libnss3" "$TT" --pedir-sudo 2>&1) || true
grep -q 'bibliotecas do sistema' <<<"$saida" || falhou "visão geral não listou as bibliotecas do Chrome: $saida"
passou 'bibliotecas do Chrome/Carbonyl entram no modal, com nomes de pacote do gerenciador'

# 4) Sem conta de e-mail, mbsync/w3m não são oferecidos.
rm -f "$HOME/.config/tt/email/x.conf" "$HOME/.local/state/tt"/navegadores-sudo-recusado "$HOME/.local/state/tt"/sudo-recusado-*
printf r >"$T/resposta"
saida=$(roda) || true
grep -q 'mbsync\|w3m' <<<"$saida" && falhou "sem conta de e-mail ofereceu mbsync/w3m: $saida"
passou 'sem conta de e-mail, só as pendências que fazem sentido aparecem'

echo 'ok: modal único de pendências sudo'
