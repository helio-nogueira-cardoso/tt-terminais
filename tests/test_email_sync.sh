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
export PATH="$T/bin:/usr/bin:/bin"
# TT_MBSYNC aponta para um executável inexistente: simula a máquina sem mbsync mesmo onde ele está
# em /usr/bin (o Dell tem; só tirar do PATH não bastava).
echo 'SENHA_X' | TT_MBSYNC=/nonexistent/mbsync "$TT" --email-adicionar nome=SemMbsync endereco=a@x.com provedor=gmail auth=senha sync_local=1 --senha-stdin >/dev/null 2>&1 \
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
grep -q '^Timeout 60$' "$rc" || falhou '.mbsyncrc sem Timeout 60 (o Gmail trava mais que os 20 s padrão)'
grep -q '^PassCmd "cat .*aerc-local.txt"$' "$rc" || falhou ".mbsyncrc PassCmd não aponta para o arquivo de senha: $(grep PassCmd "$rc")"
grep -q '^Channel local-inbox$' "$rc" || falhou '.mbsyncrc sem o canal do INBOX'
grep -q '^Channel local-pastas$' "$rc" && grep -q '^Patterns \* !INBOX$' "$rc" || falhou ".mbsyncrc sem o canal das outras pastas (sem rótulos conhecidos ainda): $(grep Patterns "$rc")"
grep -q '^Group local$' "$rc" && grep -q '^Channels local-inbox local-pastas$' "$rc" || falhou '.mbsyncrc sem o grupo da volta completa'
grep -q 'Channel local-arquivo' "$rc" && falhou 'sem pasta_todos conhecida não pode haver canal de arquivo'
grep -q "Path $HOME/.cache/tt/maildir/local/" "$rc" || falhou '.mbsyncrc sem Path do maildir'
grep -q 'SENHA_SYNC' "$rc" && falhou 'SENHA vazou para o .mbsyncrc'
[[ $(stat -c %a "$rc") == 600 ]] || falhou ".mbsyncrc deveria ser 600 (é $(stat -c %a "$rc"))"
passou '.mbsyncrc: Host/User/PassCmd/Path corretos, canais INBOX + pastas + grupo, sem segredo em claro, 600'

# Com as pastas especiais do Gmail descobertas: os rótulos saem do canal de pastas e o "Todos os
# e-mails" vira um canal próprio, limitado (MaxMessages) — é o que fazia a volta nunca terminar.
printf 'pasta_todos=[Gmail]/Todos os e-mails\npasta_importantes=[Gmail]/Importantes\npasta_estrela=[Gmail]/Com estrela\n' >>"$HOME/.config/tt/email/local.conf"
"$TT" --email-regerar Local >/dev/null || falhou 'regerar com pastas especiais'
grep -q '^Patterns \* !INBOX "!\[Gmail\]/Todos os e-mails" "!\[Gmail\]/Importantes" "!\[Gmail\]/Com estrela"$' "$rc" || falhou "pastas-rótulo deveriam sair do canal de pastas: $(grep Patterns "$rc")"
grep -q '^Channel local-arquivo$' "$rc" && grep -q '^Far ":local-remote:\[Gmail\]/Todos os e-mails"$' "$rc" || falhou 'canal do arquivo (Todos os e-mails) ausente ou sem aspas'
grep -q '^MaxMessages 500$' "$rc" && grep -q '^ExpireUnread yes$' "$rc" || falhou 'canal do arquivo sem MaxMessages/ExpireUnread'
grep -q '^Channels local-inbox local-pastas local-arquivo$' "$rc" || falhou 'grupo não inclui o canal do arquivo'
# o mbsync de verdade aceita a sintaxe (lê o arquivo; falha só na rede, não no parse)
if [[ -x /usr/bin/mbsync ]]; then
  saida=$(timeout 10 env HOME="$HOME" /usr/bin/mbsync -c "$rc" -l local 2>&1 || true)
  grep -qi 'line [0-9]*\|unknown\|syntax\|parse' <<<"$saida" && falhou "mbsync de verdade não aceitou o .mbsyncrc: $saida"
fi
passou 'Gmail: rótulos fora do espelho, arquivo limitado a 500 e sintaxe aceita pelo mbsync'

# OAuth2: PassCmd usa o email-tt.py oauth-token (sem gravar token no rc)
"$TT" --email-adicionar nome=LocalOA endereco=oa@empresa.com provedor=microsoft auth=oauth oauth_client_id=cid sync_local=1 >/dev/null || falhou 'cadastro oauth com sync_local'
rcoa=$(RC localoa)
grep -q 'PassCmd "python3 .*email-tt.py oauth-token .*localoa.conf"' "$rcoa" || falhou "oauth: PassCmd não usa oauth-token: $(grep PassCmd "$rcoa")"
grep -q '^AuthMechs XOAUTH2$' "$rcoa" || falhou 'oauth: faltou AuthMechs XOAUTH2'
passou 'OAuth2: PassCmd via email-tt.py oauth-token e AuthMechs XOAUTH2'

# --email-sync roda o mbsync só das contas com flag: por padrão só o INBOX; --completo, o grupo
: >"$T/mbsync.calls"
"$TT" --email-sync >/dev/null 2>&1
[[ $(grep -c . "$T/mbsync.calls") == 2 ]] || falhou "--email-sync deveria chamar mbsync 2x (contas com flag), chamou $(grep -c . "$T/mbsync.calls")"
grep -q ' local-inbox$' "$T/mbsync.calls" || falhou "--email-sync (padrão) deveria sincronizar só o INBOX: $(cat "$T/mbsync.calls")"
grep -qw online "$T/mbsync.calls" && falhou '--email-sync sincronizou conta sem flag'
: >"$T/mbsync.calls"; "$TT" --email-sync Local --completo >/dev/null 2>&1
grep -q ' local$' "$T/mbsync.calls" || falhou "--email-sync --completo deveria rodar o grupo: $(cat "$T/mbsync.calls")"
# registro do estado: última rodada por modo, e --email-sync-estado conta a história
E=$HOME/.local/state/tt/email-sync
[[ -f $E/local ]] && grep -q '^inbox	' "$E/local" && grep -q '^completo	' "$E/local" || falhou "estado do sync não registrou as rodadas: $(cat "$E/local" 2>/dev/null)"
est=$("$TT" --email-sync-estado)
grep -q 'Local (local)' <<<"$est" && grep -q 'inbox .*ok' <<<"$est" && grep -q 'completo .*ok' <<<"$est" || falhou "--email-sync-estado: $est"
[[ $("$TT" --email-sync-estado curto | grep '^local	') == $'local\tok' ]] || falhou "estado curto deveria ser ok: $("$TT" --email-sync-estado curto)"
# erro e tempo esgotado ficam registrados, com o que o mbsync disse
printf '#!/bin/sh\necho "IMAP error: login failed" >&2\nexit 1\n' >"$T/bin/mbsync"; chmod +x "$T/bin/mbsync"
"$TT" --email-sync Local >/dev/null 2>&1
grep -q 'login failed' "$E/local.erro" || falhou 'erro do mbsync não ficou registrado'
grep -q '✗ erro 1' <<<"$("$TT" --email-sync-estado)" && grep -q 'login failed' <<<"$("$TT" --email-sync-estado)" || falhou 'estado não mostra o erro'
[[ $("$TT" --email-sync-estado curto | grep '^local	') == $'local\terro' ]] || falhou 'estado curto deveria ser erro'
printf '#!/bin/sh\necho "$@" >>"%s/mbsync.calls"\nexit 0\n' "$T" >"$T/bin/mbsync"; chmod +x "$T/bin/mbsync"
"$TT" --email-sync Local >/dev/null 2>&1; [[ -e $E/local.erro ]] && falhou 'rodada boa deveria limpar o erro'
passou '--email-sync: INBOX por padrão, --completo roda o grupo, estado e erro registrados'

# migração: .mbsyncrc antigo (canal único, Patterns *) vira canais + grupo, sem tocar no maildir
printf 'IMAPAccount local\nHost imap.gmail.com\nChannel local\nFar :local-remote:\nNear :local-local:\nPatterns *\n' >"$rc"
mkdir -p "$(MD local)/INBOX/cur"; touch "$(MD local)/INBOX/.mbsyncstate"
TT_EMAIL_SEM_REDE=1 "$TT" --email-mbsync-migrar >/dev/null || falhou 'migrar'
grep -q '^Group local$' "$rc" && grep -q '^Channel local-inbox$' "$rc" || falhou 'migração não regravou o .mbsyncrc antigo'
[[ -f $(MD local)/INBOX/.mbsyncstate ]] || falhou 'migração mexeu no estado do maildir'
TT_EMAIL_SEM_REDE=1 "$TT" --email-mbsync-migrar >/dev/null; grep -c '^Group local$' "$rc" | grep -qx 1 || falhou 'migração não é idempotente'
# e o sync com um rc antigo (sem canal -inbox) ainda funciona (roda o canal único)
printf 'IMAPAccount local\nChannel local\nPatterns *\n' >"$rc"; : >"$T/mbsync.calls"
"$TT" --email-sync Local >/dev/null 2>&1; grep -q ' local$' "$T/mbsync.calls" || falhou "rc antigo: deveria rodar o canal único: $(cat "$T/mbsync.calls")"
"$TT" --email-regerar Local >/dev/null
passou 'migração do .mbsyncrc antigo (idempotente, sem tocar no maildir); rc antigo ainda sincroniza'

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
TT_MBSYNC=/nonexistent/mbsync "$TT" --email-sync-local Online 1 >/dev/null 2>&1 && falhou 'ligou sync local sem mbsync instalado'
grep -q '^sync_local=' "$HOME/.config/tt/email/online.conf" && falhou 'recusa por falta de mbsync gravou o flag'
passou 'liga/desliga pós-cadastro: maildir+mbsyncrc ao ligar, volta limpa ao desligar, sem mbsync recusa'

echo 'ok: sync local opcional (mbsync + maildir) — opt-in por conta, sem segredo em claro, remoção limpa'
