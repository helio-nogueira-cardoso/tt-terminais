#!/usr/bin/env bash
# Caixa grande no espelho (o caso de um INBOX de ~68 mil mensagens): sem limite, a 1ª volta do INBOX nunca
# cabia nos 240 s, recomeçava a cada poucos minutos e estourava a cota do Gmail (OVERQUOTA); a lixeira vinha
# depois do INBOX, nunca chegava ao espelho, e o ✕ Apagar não tinha para onde mover. Confere: INBOX limitado
# (MaxMessages), lixeira num canal próprio e primeiro, migração automática dos rc antigos que já conserta os
# comandos, conserto que só sincroniza a lixeira, espera longa no OVERQUOTA e autoconserto depois da volta
# completa. Isola HOME/XDG; mbsync falso (o de verdade só confere a sintaxe, sem rede).
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"
cat >"$T/bin/mbsync" <<MB
#!/bin/sh
echo "\$@" >>"$T/mbsync.calls"
[ -n "\$MBSYNC_ERR" ] && echo "\$MBSYNC_ERR" >&2
exit \${MBSYNC_RC:-0}
MB
chmod +x "$T/bin"/*
export PATH="$T/bin:$TT_PATH_BASE" TT_EMAIL_SEM_REDE=1
echo 'SENHA' | "$TT" --email-adicionar nome=Felipe endereco=f@gmail.com provedor=gmail auth=senha sync_local=1 --senha-stdin >/dev/null || falhou 'cadastro'
CONF=$HOME/.config/tt/email/felipe.conf RC=$HOME/.config/tt/mbsync/felipe.mbsyncrc E=$HOME/.local/state/tt/email-sync
MD=$HOME/.cache/tt/maildir/felipe
printf 'pasta_todos=[Gmail]/Todos os e-mails\npasta_lixeira=[Gmail]/Lixeira\npasta_importantes=[Gmail]/Importantes\npasta_estrela=[Gmail]/Com estrela\n' >>"$CONF"
"$TT" --email-regerar felipe >/dev/null 2>&1 || falhou 'regerar'

# 1) o rc novo: marca do formato, INBOX limitado, lixeira com canal próprio e primeiro no grupo
grep -qx '# tt-mbsyncrc 2 .*' "$RC" || falhou "rc sem a marca do formato: $(head -1 "$RC")"
awk '/^Channel felipe-inbox$/ { c = 1 } c && /^MaxMessages 5000$/ { m = 1 } c && /^ExpireUnread yes$/ { x = 1 } c && /^$/ { c = 0 } END { exit !(m && x) }' "$RC" ||
  falhou "canal do INBOX sem MaxMessages 5000/ExpireUnread: $(sed -n '/^Channel felipe-inbox$/,/^$/p' "$RC")"
grep -q '^Channel felipe-lixeira$' "$RC" && grep -q '^Far ":felipe-remote:\[Gmail\]/Lixeira"$' "$RC" || falhou 'canal da lixeira ausente'
grep -q '^Channels felipe-lixeira felipe-inbox felipe-pastas felipe-arquivo$' "$RC" || falhou "a lixeira deveria vir primeiro no grupo: $(grep '^Channels' "$RC")"
grep -q '^Patterns .*"!\[Gmail\]/Lixeira"' "$RC" || falhou "a lixeira não pode estar em dois canais: $(grep Patterns "$RC")"
TT_EMAIL_INBOX_MAX=800 "$TT" --email-regerar felipe >/dev/null 2>&1
grep -q '^MaxMessages 800$' "$RC" || falhou 'TT_EMAIL_INBOX_MAX deveria trocar o limite'
"$TT" --email-regerar felipe >/dev/null 2>&1
if [[ -x /usr/bin/mbsync ]]; then
  saida=$(timeout 10 env HOME="$HOME" /usr/bin/mbsync -c "$RC" -l felipe 2>&1 || true)
  grep -qi 'line [0-9]*\|unknown\|syntax\|parse' <<<"$saida" && falhou "mbsync de verdade não aceitou o rc: $saida"
fi
passou 'rc: INBOX limitado no espelho, lixeira num canal próprio e primeiro no grupo, sintaxe aceita pelo mbsync'

# 2) migração na atualização: rc do formato anterior (grupo + Timeout, sem a marca) é regravado, sem tocar no
#    maildir, e a lixeira que faltava no espelho já nasce (o ✕ Apagar volta a funcionar sem esperar a rede)
sed -i '1d; /^MaxMessages 5000$/d' "$RC"
mkdir -p "$MD/INBOX/cur"; touch "$MD/INBOX/.mbsyncstate"; rm -rf "${MD:?}/[Gmail]"
grep -q 'não existe no espelho' <<<"$("$TT" --email-conferir felipe 2>&1)" || falhou 'antes: a lixeira fora do espelho deveria ser acusada'
"$TT" --email-mbsync-migrar >/dev/null || falhou 'migrar'
grep -qx '# tt-mbsyncrc 2 .*' "$RC" && grep -q '^MaxMessages 5000$' "$RC" || falhou 'a migração não regravou o rc do formato anterior'
[[ -f $MD/INBOX/.mbsyncstate ]] || falhou 'a migração mexeu no estado do maildir'
[[ -d $MD/[Gmail]/Lixeira/cur ]] || falhou 'a migração deveria criar a lixeira no espelho'
grep -q '✓ felipe' <<<"$("$TT" --email-conferir felipe 2>&1)" || falhou "depois da migração: $("$TT" --email-conferir felipe 2>&1)"
cp "$RC" "$T/rc.antes"; "$TT" --email-mbsync-migrar >/dev/null; cmp -s "$RC" "$T/rc.antes" || falhou 'a migração não é idempotente'
passou 'migração automática: rc antigo regravado, maildir intacto, lixeira criada e comandos ok (idempotente)'

# 3) --corrigir sincroniza só a lixeira (não a volta inteira, que numa caixa grande não terminava)
rm -rf "${MD:?}/[Gmail]"; : >"$T/mbsync.calls"
TT_EMAIL_SEM_REDE= "$TT" --email-conferir felipe --corrigir >/dev/null 2>&1 || falhou "corrigir: $("$TT" --email-conferir felipe 2>&1)"
grep -q ' felipe-lixeira$' "$T/mbsync.calls" || falhou "o conserto deveria rodar o canal da lixeira: $(cat "$T/mbsync.calls")"
grep -q ' felipe$\| felipe-inbox$' "$T/mbsync.calls" && falhou "o conserto não deveria rodar a volta inteira nem o INBOX: $(cat "$T/mbsync.calls")"
[[ -d $MD/[Gmail]/Lixeira/cur ]] || falhou 'o conserto deveria criar a lixeira no espelho'
passou 'conserto: cria a lixeira no espelho e sincroniza só o canal dela'

# 4) OVERQUOTA do Gmail: o vigia espera 2 h (não 4 min) e o estado explica
rm -f "$E"/felipe "$E"/felipe.*
MBSYNC_RC=1 MBSYNC_ERR='IMAP error: unexpected BYE response: [OVERQUOTA] Account exceeded command or bandwidth limits.' \
  "$TT" --email-sync felipe >/dev/null 2>&1
esp=$(cat "$E/felipe.espera" 2>/dev/null); agora=$(date +%s)
[[ -n $esp ]] && ((esp - agora >= 7100 && esp - agora <= 7201)) || falhou "OVERQUOTA deveria esperar 2 h: $((${esp:-0} - agora)) s"
grep -q 'limitou a conta' <<<"$("$TT" --email-sync-estado)" || falhou "estado sem a explicação da cota: $("$TT" --email-sync-estado)"
: >"$T/mbsync.calls"; "$TT" --email-sync --vigia >/dev/null 2>&1
[[ ! -s $T/mbsync.calls ]] || falhou "o vigia não respeitou a espera da cota: $(cat "$T/mbsync.calls")"
"$TT" --email-sync felipe >/dev/null 2>&1; [[ ! -e $E/felipe.espera ]] || falhou 'rodada boa deveria zerar a espera'
passou 'OVERQUOTA: o vigia espera 2 h, o estado explica; à mão sincroniza; sucesso zera'

# 5) depois de uma volta completa boa, os comandos se conferem e se consertam sozinhos
rm -rf "${MD:?}/[Gmail]"
"$TT" --email-sync felipe --completo >/dev/null 2>&1
[[ -d $MD/[Gmail]/Lixeira/cur ]] || falhou 'a volta completa deveria repor a lixeira que sumiu do espelho'
grep -q '✓ felipe' <<<"$("$TT" --email-conferir felipe 2>&1)" || falhou "depois da volta completa: $("$TT" --email-conferir felipe 2>&1)"
passou 'autoconserto: depois da volta completa a lixeira volta ao espelho e os comandos ficam ok'
