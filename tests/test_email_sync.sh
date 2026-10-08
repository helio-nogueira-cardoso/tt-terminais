#!/usr/bin/env bash
# Sync local opcional por conta (sync_local=1, mbsync/isync + maildir):
#  - conta com sync_local=1 gera source=maildir:// no accounts.conf e NÃO escreve source-cred-cmd;
#  - gera ~/.config/tt/mbsync/<slug>.mbsyncrc com Host/User/PassCmd corretos e SEM segredo em claro;
#  - PassCmd aponta para o arquivo de senha (auth=senha) ou para o email-tt.py oauth-token (oauth);
#  - conta sem o flag continua com source=imaps:// e source-cred-cmd (comportamento atual intacto);
#  - cadastrar com sync_local=1 sem mbsync instalado é RECUSADO (não finge que ligou);
#  - remover a conta apaga o .mbsyncrc e o maildir;
#  - --email-sync roda o mbsync só das contas com o flag.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"
A=$HOME/.config/aerc/accounts.conf
RC() { echo "$HOME/.config/tt/mbsync/$1.mbsyncrc"; }
MD() { echo "$HOME/.cache/tt/maildir/$1"; }

# --- Sem mbsync instalado: sync_local=1 é recusado -----------------------------------------------
export PATH="$T/bin:/usr/bin:/bin"   # sem mbsync aqui
echo 'SENHA_X' | "$TT" --email-adicionar nome=SemMbsync endereco=a@x.com provedor=gmail auth=senha sync_local=1 --senha-stdin >/dev/null 2>&1 \
  && falhou 'aceitou sync_local=1 sem mbsync instalado'
[[ -e $HOME/.config/tt/email/semmbsync.conf ]] && falhou 'conta recusada deixou resíduo .conf'
passou 'sync_local=1 sem mbsync instalado é recusado, sem resíduo'

# --- Com mbsync (stub) instalado -----------------------------------------------------------------
printf '#!/bin/sh\necho "$@" >>"%s/mbsync.calls"\nexit 0\n' "$T" >"$T/bin/mbsync"; chmod +x "$T/bin/mbsync"

echo 'SENHA_SYNC' | "$TT" --email-adicionar nome=Local endereco=eu@gmail.com provedor=gmail auth=senha sync_local=1 --senha-stdin >/dev/null || falhou 'cadastro com sync_local'
"$TT" --email-adicionar nome=Online endereco=on@gmail.com provedor=gmail auth=comando 'cred_cmd=pass x' >/dev/null || falhou 'cadastro conta online (sem flag)'

# conta com flag: maildir e sem credencial no bloco
grep -q "^source *= maildir://$HOME/.cache/tt/maildir/local$" "$A" || falhou "conta sync_local não usa maildir: $(grep -A1 '\[Local\]' "$A")"
awk '/^\[Local\]$/{f=1} f&&/^source-cred-cmd/{print "ACHOU"} /^\[Online\]$/{f=0}' "$A" | grep -q ACHOU && falhou 'bloco maildir não deve ter source-cred-cmd'
grep -q '^outgoing *= smtps://eu%40gmail.com@smtp.gmail.com:465$' "$A" || falhou 'envio da conta sync_local deve seguir SMTP online'
# conta sem flag: segue imaps:// com cred-cmd (comportamento atual intacto)
grep -q '^source *= imaps://on%40gmail.com@imap.gmail.com:993$' "$A" || falhou 'conta sem flag deixou de usar imaps://'
passou 'sync_local=1 → maildir sem cred-cmd e SMTP online; conta sem flag intacta (imaps://)'

# .mbsyncrc gerado, correto e sem segredo em claro
rc=$(RC local)
[[ -f $rc ]] || falhou '.mbsyncrc não foi gerado'
grep -q '^Host imap.gmail.com$' "$rc" || falhou '.mbsyncrc sem Host correto'
grep -q '^User eu@gmail.com$' "$rc" || falhou '.mbsyncrc sem User correto'
grep -q '^PassCmd "cat .*aerc-local.txt"$' "$rc" || falhou ".mbsyncrc PassCmd não aponta para o arquivo de senha: $(grep PassCmd "$rc")"
grep -q '^Channel local$' "$rc" || falhou '.mbsyncrc sem Channel'
grep -q "Path $HOME/.cache/tt/maildir/local/" "$rc" || falhou '.mbsyncrc sem Path do maildir'
grep -q 'SENHA_SYNC' "$rc" && falhou 'SENHA vazou para o .mbsyncrc'
[[ $(stat -c %a "$rc") == 600 ]] || falhou ".mbsyncrc deveria ser 600 (é $(stat -c %a "$rc"))"
passou '.mbsyncrc: Host/User/PassCmd/Channel/Path corretos, sem segredo em claro, 600'

# OAuth2: PassCmd usa o email-tt.py oauth-token (sem gravar token no rc)
"$TT" --email-adicionar nome=LocalOA endereco=oa@empresa.com provedor=microsoft auth=oauth oauth_client_id=cid sync_local=1 >/dev/null || falhou 'cadastro oauth com sync_local'
rcoa=$(RC localoa)
grep -q 'PassCmd "python3 .*email-tt.py oauth-token .*localoa.conf"' "$rcoa" || falhou "oauth: PassCmd não usa oauth-token: $(grep PassCmd "$rcoa")"
grep -q '^AuthMechs XOAUTH2$' "$rcoa" || falhou 'oauth: faltou AuthMechs XOAUTH2'
passou 'OAuth2: PassCmd via email-tt.py oauth-token e AuthMechs XOAUTH2'

# --email-sync roda o mbsync só das contas com flag
: >"$T/mbsync.calls"
"$TT" --email-sync >/dev/null 2>&1
[[ $(grep -c . "$T/mbsync.calls") == 2 ]] || falhou "--email-sync deveria chamar mbsync 2x (contas com flag), chamou $(grep -c . "$T/mbsync.calls")"
grep -qw local "$T/mbsync.calls" || falhou '--email-sync não sincronizou a conta local'
grep -qw online "$T/mbsync.calls" && falhou '--email-sync sincronizou conta sem flag'
passou '--email-sync espelha só as contas com sync_local=1'

# remover apaga .mbsyncrc e maildir
mkdir -p "$(MD local)/INBOX/cur"
"$TT" --email-remover Local >/dev/null || falhou 'remover conta local'
[[ -e $rc ]] && falhou 'remover não apagou o .mbsyncrc'
[[ -d $(MD local) ]] && falhou 'remover não apagou o maildir'
grep -q '^\[Local\]$' "$A" && falhou 'remover não tirou o bloco do accounts.conf'
passou 'remover a conta apaga bloco, .mbsyncrc e maildir'

# --- Liga/desliga depois do cadastro (o botão 🔄 da tela de contas chama isto) -------------------
"$TT" --email-sync-local Online 1 >/dev/null || falhou 'ligar sync local numa conta existente'
grep -q "^source *= maildir://$HOME/.cache/tt/maildir/online$" "$A" || falhou 'ligar não trocou a conta para maildir'
[[ -f $(RC online) ]] || falhou 'ligar não gerou o .mbsyncrc'
grep -q '^sync_local=1$' "$HOME/.config/tt/email/online.conf" || falhou 'ligar não gravou o flag no .conf'
"$TT" --email-sync-local Online 0 >/dev/null || falhou 'desligar sync local'
grep -q '^source *= imaps://on%40gmail.com@imap.gmail.com:993$' "$A" || falhou 'desligar não voltou a imaps://'
awk '/^\[Online\]$/{f=1} f&&/^source-cred-cmd/{print "ACHOU"} f&&/^$/{f=0}' "$A" | grep -q ACHOU || falhou 'desligar não devolveu o source-cred-cmd'
[[ ! -e $(RC online) ]] || falhou 'desligar não removeu o .mbsyncrc'
grep -q '^sync_local=' "$HOME/.config/tt/email/online.conf" && falhou 'desligar deixou o flag no .conf'
PATH="/usr/bin:/bin" "$TT" --email-sync-local Online 1 >/dev/null 2>&1 && falhou 'ligou sync local sem mbsync instalado'
grep -q '^sync_local=' "$HOME/.config/tt/email/online.conf" && falhou 'recusa por falta de mbsync gravou o flag'
passou 'liga/desliga pós-cadastro: maildir+mbsyncrc ao ligar, volta limpa ao desligar, sem mbsync recusa'

echo 'ok: sync local opcional (mbsync + maildir) — opt-in por conta, sem segredo em claro, remoção limpa'
