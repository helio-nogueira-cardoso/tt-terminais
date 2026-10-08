#!/usr/bin/env bash
# E-mail que chega fica visível: depois de cada rodada do INBOX o tt avisa (notificação do sistema e
# tela dos terminais) dos e-mails novos — remetente e assunto decodificados, até 3 e "e mais N" —,
# sem repetir, sem avisar a caixa inteira na primeira rodada, com o aerc movendo new/ → cur/ ou não,
# e email_aviso=0 desliga; o botão 📧 da barra mostra as não lidas do espelho e fica vermelho com ⚠
# quando o sync de alguma conta falha de forma persistente (âmbar ⏳ se só atrasou). Isola HOME/XDG; mbsync e notify-send são stubs.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"
export PATH="$T/bin:/usr/bin:/bin"
# notify-send é chamado como "notify-send -a tt TÍTULO CORPO": guarda "TÍTULO|CORPO"
printf '#!/bin/sh\nshift 2; printf "%%s|%%s\\n" "$1" "$2" >>"%s/notif.log"\n' "$T" >"$T/bin/notify-send"; chmod +x "$T/bin/notify-send"
# mbsync falso: "entrega" no INBOX do espelho os arquivos que estiverem em $T/chegando (um por rodada)
cat >"$T/bin/mbsync" <<MB
#!/bin/sh
md=$HOME/.cache/tt/maildir/local/INBOX; mkdir -p "\$md/new" "\$md/cur" "\$md/tmp"
for f in "$T"/chegando/*; do [ -e "\$f" ] && mv "\$f" "\$md/new/"; done
[ -n "\$MBSYNC_ERR" ] && echo "\$MBSYNC_ERR" >&2
exit \${MBSYNC_RC:-0}
MB
chmod +x "$T/bin/mbsync"; mkdir -p "$T/chegando"
MD=$HOME/.cache/tt/maildir/local/INBOX
msg() { # arquivo "De" "Assunto"
  printf 'From: %s\nTo: eu@gmail.com\nSubject: %s\nDate: Thu, 08 Oct 2026 10:00:00 -0300\nMessage-ID: <%s@x>\n\ncorpo\n' "$2" "$3" "$1" >"$T/chegando/$1"
}
notifs() { cat "$T/notif.log" 2>/dev/null; }

echo 'SENHA' | "$TT" --email-adicionar nome=Local endereco=eu@gmail.com provedor=gmail auth=senha sync_local=1 --senha-stdin >/dev/null || falhou 'cadastro'
mkdir -p "$MD/new" "$MD/cur" "$MD/tmp"
# caixa já com coisas antes do tt começar a observar: 2 não lidas e 1 lida
printf 'From: velho@x.com\nSubject: antigo\n\n.\n' >"$MD/new/1000.a.host"
printf 'From: velho@x.com\nSubject: antigo 2\n\n.\n' >"$MD/cur/1001.b.host:2,"
printf 'From: velho@x.com\nSubject: lido\n\n.\n' >"$MD/cur/1002.c.host:2,S"

# 1) primeira rodada: só memoriza, não avisa a caixa inteira
: >"$T/notif.log"; "$TT" --email-sync Local >/dev/null 2>&1
[[ -z $(notifs) ]] || falhou "primeira rodada não deveria avisar: $(notifs)"
passou 'primeira rodada só memoriza (não avisa a caixa inteira)'

# 2) chega 1: aviso com remetente (decodificado) e assunto; o aerc "abriu a pasta" (moveu para cur/, ainda não lida)
msg 2000.d.host '=?UTF-8?B?QW5hIFBhdWxh?= <ana@x.com>' '=?UTF-8?Q?Reuni=C3=A3o_de_sexta?='
"$TT" --email-sync Local >/dev/null 2>&1
grep -q '📧 Local: 1 e-mail novo|Ana Paula — Reunião de sexta' <<<"$(notifs)" || falhou "aviso do e-mail novo errado: $(notifs)"
mv "$MD/new/2000.d.host" "$MD/cur/2000.d.host:2,"
: >"$T/notif.log"; "$TT" --email-sync Local >/dev/null 2>&1
[[ -z $(notifs) ]] || falhou "não deveria repetir o aviso (mesmo com o arquivo movido para cur/): $(notifs)"
passou 'e-mail novo: um aviso só, com remetente e assunto decodificados; mover new/→cur/ não repete'

# 3) chegam 4 de uma vez: até 3 nomes e "e mais 1"
for i in 1 2 3 4; do msg "300$i.e.host" "Pessoa $i <p$i@x.com>" "Assunto $i"; done
: >"$T/notif.log"; "$TT" --email-sync Local >/dev/null 2>&1
grep -q '📧 Local: 4 e-mails novos|' <<<"$(notifs)" || falhou "4 novos: título errado: $(notifs)"
grep -q 'Pessoa 1 — Assunto 1 · Pessoa 2 — Assunto 2 · Pessoa 3 — Assunto 3 · e mais 1' <<<"$(notifs)" || falhou "4 novos: corpo errado: $(notifs)"
passou 'vários de uma vez: até 3 remetentes/assuntos e "e mais N"'

# 4) e-mail que chega já lido (ex.: lido no celular) não é "novo"; email_aviso=0 desliga
printf 'From: a@x.com\nSubject: ja lido\n\n.\n' >"$MD/cur/4000.f.host:2,S"
: >"$T/notif.log"; "$TT" --email-sync Local >/dev/null 2>&1
[[ -z $(notifs) ]] || falhou "mensagem já lida não deveria gerar aviso: $(notifs)"
echo 'email_aviso=0' >>"$XDG_CONFIG_HOME/tt/config"
msg 5000.g.host 'x@x.com' 'silencioso'
"$TT" --email-sync Local >/dev/null 2>&1
[[ -z $(notifs) ]] || falhou "email_aviso=0 deveria desligar o aviso: $(notifs)"
sed -i '/^email_aviso=/d' "$XDG_CONFIG_HOME/tt/config"
passou 'já lida não conta como nova; email_aviso=0 desliga'

# 5) botão 📧 da barra: não lidas do espelho (new/ + cur/ sem S), contagem limpa entre parênteses
b=$("$TT" --barra-email)
nl=$(( $(find "$MD/new" -type f | wc -l) + $(find "$MD/cur" -type f ! -name '*:2,*S*' | wc -l) ))
grep -qF "📧 ($nl)" <<<"$b" || falhou "barra deveria mostrar ($nl) não lidas: $b"
grep -q 'bg=#f9e2af' <<<"$b" || falhou "com não lidas o botão deveria ficar em destaque: $b"
grep -q ' email' <<<"$b" && falhou "o botão não leva mais a palavra 'email': $b"
grep -q '⚠' <<<"$b" && falhou "sem erro de sync não deveria ter ⚠: $b"
passou "botão 📧 mostra (não lidas) entre parênteses, sem rótulo"

# 6) sync com erro: uma falha passageira (Gmail lento) deixa o 📧 âmbar com ⏳; persistente (3 seguidas)
# ou senha recusada, vermelho com ⚠; rodada boa limpa
MBSYNC_RC=1 MBSYNC_ERR='Socket error on imap.gmail.com: timeout.' "$TT" --email-sync Local >/dev/null 2>&1
b=$("$TT" --barra-email)
grep -q '⏳' <<<"$b" && grep -q 'bg=#fab387' <<<"$b" || falhou "uma falha passageira deveria deixar o 📧 âmbar com ⏳: $b"
grep -q '⚠' <<<"$b" && falhou "uma falha passageira não deveria deixar vermelho: $b"
for i in 2 3; do MBSYNC_RC=1 MBSYNC_ERR='Socket error: timeout.' "$TT" --email-sync Local >/dev/null 2>&1; done
b=$("$TT" --barra-email)
grep -q '⚠' <<<"$b" && grep -q 'bg=#f38ba8' <<<"$b" || falhou "3 falhas seguidas deveriam deixar o 📧 vermelho com ⚠: $b"
"$TT" --email-sync Local >/dev/null 2>&1
grep -qE '⚠|⏳' <<<"$("$TT" --barra-email)" && falhou 'rodada boa deveria tirar o aviso'
MBSYNC_RC=1 MBSYNC_ERR='IMAP command AUTHENTICATE returned an error: NO [AUTHENTICATIONFAILED] Invalid credentials (Failure)' "$TT" --email-sync Local >/dev/null 2>&1
grep -q '⚠' <<<"$("$TT" --barra-email)" || falhou 'senha recusada deveria deixar vermelho já na 1ª falha'
"$TT" --email-sync Local >/dev/null 2>&1
# sem sync periódico (TT_EMAIL_SYNC=0) a conta nunca fica "parada"
[[ $(TT_EMAIL_SYNC=0 "$TT" --email-sync-estado curto | cut -f2) == ok ]] || falhou 'com TT_EMAIL_SYNC=0 não pode virar "parado"'
passou 'falha passageira deixa o 📧 âmbar ⏳; persistente ou senha recusada, vermelho ⚠; rodada boa limpa'

# 7) a barra de verdade (tmux isolado): @barra_email é recalculada e o tema a usa
tmux -f /dev/null new -d -s s1 'sleep 60'
"$TT" --barras >/dev/null 2>&1
grep -q '📧' <<<"$(tmux show -gqv @barra_email)" || falhou '@barra_email não foi preenchida por --barras'
grep -q '#{E:@barra_email}' "$RAIZ/tt" || falhou 'o tt não liga @barra_email na barra'
passou '@barra_email recalculada pelas barras e usada pelo tema'

echo 'ok: e-mail que chega fica visível (aviso com remetente/assunto, 📧 com não lidas e ⚠ no erro)'
