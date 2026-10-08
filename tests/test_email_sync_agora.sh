#!/usr/bin/env bash
# ⟳ Sincronizar agora: consulta o INBOX das contas com espelho já, sem esperar o vigia — botão na
# barra do popup (range em_sync, com o estado em @tt_email_sync), Ctrl+s no aerc, item no menu do
# 📧 e tt --email-sync-agora [cliente]; contas em paralelo; conta o que chegou; se a volta completa
# está segurando a trava, derruba o mbsync dela e consulta; sem espelho, só pede ao aerc para
# conferir (F11 = :check-mail). mbsync falso que "baixa" uma mensagem a cada rodada do INBOX.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"
# mbsync falso: "--version" responde; rodada do INBOX de uma conta põe uma mensagem nova em new/
cat >"$T/bin/mbsync" <<'EOF'
#!/usr/bin/env bash
[[ $1 == --version ]] && { echo "isync 1.4.4"; exit 0; }
rc=$2; alvo=$3; slug=${alvo%-inbox}
md=$(sed -n 's/^Path \(.*\)\/$/\1/p' "$rc")
[[ -n ${MBSYNC_LENTO:-} ]] && sleep "$MBSYNC_LENTO"
n=$(date +%s%N)
printf 'From: a@x\nSubject: chegou %s\n\ncorpo\n' "$n" >"$md/INBOX/new/$n"
echo "$alvo" >>"${MBSYNC_LOG:-/dev/null}"
exit 0
EOF
chmod +x "$T/bin/mbsync"; export PATH=$T/bin:$PATH MBSYNC_LOG=$T/mbsync.log
tt() { "$TT" "$@"; }

# 1) sem conta com espelho: avisa e não falha
echo 'S' | tt --email-adicionar nome=Direta endereco=d@gmail.com provedor=gmail auth=senha --senha-stdin >/dev/null || falhou 'cadastro direta'
out=$(tt --email-sync-agora) || falhou "sem espelho deveria dar certo: $out"
grep -q 'nenhuma conta com espelho' <<<"$out" || falhou "sem espelho: $out"
passou 'sem conta com espelho: avisa que o aerc lê direto (nada a sincronizar)'

# 2) duas contas com espelho: consulta as duas agora, conta o que chegou, com retorno
echo 'S' | tt --email-adicionar nome=Um endereco=um@gmail.com provedor=gmail auth=senha sync_local=1 --senha-stdin >/dev/null || falhou 'cadastro um'
echo 'S' | tt --email-adicionar nome=Dois endereco=dois@gmail.com provedor=gmail auth=senha sync_local=1 --senha-stdin >/dev/null || falhou 'cadastro dois'
for s in um dois; do mkdir -p "$HOME/.cache/tt/maildir/$s/INBOX/new" "$HOME/.cache/tt/maildir/$s/INBOX/cur"; done
out=$(tt --email-sync-agora) || falhou "sincronizar agora falhou: $out"
grep -q '✓ caixa de entrada atualizada: 2 novos' <<<"$out" || falhou "deveria contar 2 novos (um por conta): $out"
[[ $(grep -c -- '-inbox$' "$MBSYNC_LOG") == 2 ]] || falhou "deveria rodar só o INBOX das duas contas: $(cat "$MBSYNC_LOG")"
grep -q $'^inbox\t' "$HOME/.local/state/tt/email-sync/um" || falhou 'a rodada manual deveria ficar registrada como inbox'
passou 'sincronizar agora: INBOX das contas com espelho, em paralelo, e "N novos" no retorno'

# 3) volta completa segurando a trava: a manual derruba o mbsync dela e consulta mesmo assim
lock=$HOME/.config/tt/mbsync/um.lock; rc=$HOME/.config/tt/mbsync/um.mbsyncrc
printf 'completo\t%s\n' "$(date +%s)" >"$HOME/.local/state/tt/email-sync/um.andamento"
flock "$lock" bash -c "exec -a 'mbsync -c $rc um' sleep 300" &
sleep 0.5
pgrep -f "mbsync -c $rc um" >/dev/null || falhou 'a completa falsa não está rodando'
: >"$MBSYNC_LOG"
ini=$(date +%s); out=$(tt --email-sync-agora) || falhou "com a completa na frente: $out"
(( $(date +%s) - ini < 90 )) || falhou 'demorou demais com a completa na frente'
pgrep -f "mbsync -c $rc um" >/dev/null && falhou 'a completa falsa deveria ter sido derrubada'
grep -q '^um-inbox$' "$MBSYNC_LOG" || falhou "o INBOX da conta travada deveria ter sido consultado: $(cat "$MBSYNC_LOG")"
grep -q '✓ caixa de entrada atualizada' <<<"$out" || falhou "retorno com a completa na frente: $out"
rm -f "$HOME/.local/state/tt/email-sync/um.andamento"
passou 'volta completa segurando a trava: derrubada, e o INBOX é consultado'

# 4) retorno na tela do cliente e no botão (@tt_email_sync), binds Ctrl+s/F11, item do menu, botão na barra
tmux -f /dev/null new -d -s base -x 150 -y 40 'sleep 600'
tmux new-session -d -s _tt-email -x 150 -y 40 'sleep 600'
tmux set -q -t =_tt-email: @ponte email
out=$(tt --email-sync-agora base 2>&1) || falhou "com cliente: $out"
[[ $(tmux show -qv -t =_tt-email: @tt_email_sync) == '✓ 2 novos' ]] || falhou "botão deveria mostrar o resultado: '$(tmux show -qv -t =_tt-email: @tt_email_sync)'"
fmt=$(bash -c "source <(sed -n '/^EMAIL_SESSAO=/,/^# ─── Cadastro e gerência de contas de e-mail/p' '$TT' | sed '\$d'); email_barra_fmt")
grep -q 'range=user|em_sync.*⟳.*@tt_email_sync' <<<"$fmt" || falhou "barra sem o botão ⟳ com estado: $fmt"
bo=$(bash -c "source <(sed -n '/^EMAIL_SESSAO=/,/^# ─── Cadastro e gerência de contas de e-mail/p' '$TT' | sed '\$d'); email_binds_botoes messages")
grep -q '^<F11> = :check-mail<Enter>$' <<<"$bo" || falhou 'F11 (:check-mail) ausente dos binds da sessão oculta'
B=$HOME/.config/aerc/binds.conf
sed -n '/# >>> tt (saída rápida/,$p' "$B" | sed -n '/^\[messages\]/,/^\[view\]/p' | grep -q "^<C-s> = :exec $HOME/.local/bin/tt --email-sync-agora<Enter>$" || falhou 'Ctrl+s na lista ausente'
sed -n '/# >>> tt (saída rápida/,$p' "$B" | sed -n '/^\[view\]/,/^\[compose/p' | grep -q "^<C-s> = :exec $HOME/.local/bin/tt --email-sync-agora<Enter>$" || falhou 'Ctrl+s na leitura ausente'
grep -q 'Sincronizar agora.*--email-sync-agora' "$TT" || falhou 'item do menu do 📧 ausente'
grep -q "'sync|⟳|Sincronizar|'" "$TT" || falhou 'botão ⟳ ausente de EMAIL_BOTOES'
# clique no botão: rota em_sync chama a consulta (em segundo plano) — a marca aparece
tmux set -qu -t =_tt-email: @tt_email_sync; : >"$MBSYNC_LOG"
tt --clique em_sync base '' "$HOME" 0; sleep 3
grep -q -- '-inbox$' "$MBSYNC_LOG" || falhou "clique em ⟳ deveria consultar: $(cat "$MBSYNC_LOG")"
passou 'retorno no cliente e no botão ⟳ (estado), Ctrl+s/F11 nos binds, item no menu, clique em ⟳ consulta'

echo 'ok: ⟳ sincronizar agora — consulta imediata com retorno, por botão, tecla, menu e CLI'
