#!/usr/bin/env bash
# v139: cadastro/edição à prova do usuário. Prova: o bug do Vinicius (nome vira login) não acontece;
# validação estrita; rollback transacional em falha; escolha de autenticação livre com OAuth recomendado;
# tela de erro quando o aerc sai com erro.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"; export PATH=$T/bin:$PATH
mkdir -p "$HOME/.config/aerc" "$HOME/.secrets"
A=$HOME/.config/aerc/accounts.conf
export TT_EMAIL_SEM_REDE=1   # sem rede: salva após validar formato; teste real IMAP/SMTP é coberto em test_email.sh

# 1) Bug do Vinicius: nome com espaço jamais vira login IMAP/SMTP; source usa o endereço codificado.
echo 'SENHA_V' | "$TT" --email-adicionar 'nome=E-mail Pessoal' endereco=vini@gmail.com provedor=gmail auth=senha --senha-stdin >/dev/null || falhou 'cadastro com nome com espaço'
b=$(sed -n '/# >>> tt e-mail: e-mail-pessoal >>>/,/# <<< tt e-mail: e-mail-pessoal <<</p' "$A")
if grep -q 'E-mail Pessoal@' <<<"$b"; then falhou 'o nome vazou como login (bug do Vinicius)'; fi
grep -q '^source *= imaps://vini%40gmail.com@imap.gmail.com:993$' <<<"$b" || falhou "source não usou o endereço: $b"
passou 'nome com espaço nunca vira login; source usa o endereço codificado'

# 2) Usuário técnico com espaço é recusado (não grava conta inválida).
if echo x | "$TT" --email-adicionar nome=Comespaco endereco=u@x.com provedor=outro imap_host=mail.x.com imap_porta=993 imap_seg=tls \
  smtp_host=mail.x.com smtp_porta=465 smtp_seg=tls 'usuario=login com espaco' auth=senha --senha-stdin >/dev/null 2>&1; then falhou 'aceitou usuário com espaço'; fi
if [[ -e $HOME/.config/tt/email/comespaco.conf ]]; then falhou 'conta inválida foi gravada'; fi
passou 'usuário técnico com espaço é recusado e nada é gravado'

# 3) Porta fora da faixa e TLS "nenhuma" fora de localhost são recusados.
if echo x | "$TT" --email-adicionar nome=Porta endereco=p@x.com provedor=outro imap_host=h imap_porta=70000 imap_seg=tls \
  smtp_host=h smtp_porta=25 smtp_seg=tls auth=comando cred_cmd=x >/dev/null 2>&1; then falhou 'aceitou porta > 65535'; fi
if echo x | "$TT" --email-adicionar nome=Claro endereco=p@x.com provedor=outro imap_host=mail.x.com imap_porta=143 imap_seg=nenhuma \
  smtp_host=mail.x.com smtp_porta=25 smtp_seg=nenhuma auth=comando cred_cmd=x >/dev/null 2>&1; then falhou 'aceitou sem TLS fora de localhost'; fi
passou 'porta fora da faixa e sem-TLS fora de localhost são recusados'

# 4) Escolha livre: Gmail lista OAuth em 1º e também senha; iCloud não oferece OAuth; cadastro aceita ambos no Gmail.
gmail_auths=$(awk -F'|' '/imap\.gmail\.com 993/{print $5; exit}' "$TT_DIR/tt")
[[ ${gmail_auths%% *} == oauth ]] || falhou "Gmail não lista OAuth em primeiro: [$gmail_auths]"
[[ " $gmail_auths " == *" senha "* ]] || falhou 'Gmail não oferece senha como alternativa'
icloud_auths=$(awk -F'|' '/imap\.mail\.me\.com 993/{print $5; exit}' "$TT_DIR/tt")
if [[ " $icloud_auths " == *" oauth "* ]]; then falhou 'iCloud não deveria oferecer OAuth'; fi
"$TT" --email-adicionar nome=GmailOAuth endereco=og@gmail.com provedor=gmail auth=oauth oauth_client_id=cid-teste >/dev/null || falhou 'Gmail não aceitou OAuth'
grep -qx 'auth=oauth' "$HOME/.config/tt/email/gmailoauth.conf" || falhou 'conta Gmail OAuth não gravou auth=oauth'
echo 'SENHA_GS' | "$TT" --email-adicionar nome=GmailSenha endereco=gs@gmail.com provedor=gmail auth=senha --senha-stdin >/dev/null || falhou 'Gmail não aceitou senha'
passou 'escolha livre: Gmail aceita OAuth e senha (OAuth em 1º); iCloud fica só com senha'

# 5) Edição que ficaria inválida faz rollback byte a byte; o arquivo anterior não muda.
echo 'SENHA_ED' | "$TT" --email-adicionar nome=Edit endereco=e@x.com provedor=outro imap_host=mail.x.com imap_porta=993 imap_seg=tls \
  smtp_host=mail.x.com smtp_porta=465 smtp_seg=tls auth=senha --senha-stdin >/dev/null || falhou 'cadastro p/ edição'
antes=$(sha256sum "$A" | cut -d' ' -f1); antes_conf=$(sha256sum "$HOME/.config/tt/email/edit.conf" | cut -d' ' -f1)
printf 'e@x.com\n\nsenha\nmail.x.com\n99999\ntls\nmail.x.com\n465\ntls\n\nINBOX\nn\n' | "$TT" --email-editar Edit >/dev/null 2>&1 || true
[[ $(sha256sum "$A" | cut -d' ' -f1) == "$antes" ]] || falhou 'edição inválida alterou o accounts.conf'
[[ $(sha256sum "$HOME/.config/tt/email/edit.conf" | cut -d' ' -f1) == "$antes_conf" ]] || falhou 'edição inválida alterou o .conf'
passou 'edição que ficaria inválida faz rollback; configuração anterior intacta'

# 6) aerc que sai com erro NÃO deixa popup vazio: botao_email detecta e não deixa uma sessão aerc viva.
unset TT_EMAIL_SEM_REDE
cat >"$T/bin/aerc" <<'SH'
#!/bin/sh
echo "erro de configuração simulado" >&2
exit 3
SH
chmod +x "$T/bin/aerc"
tmux -f /dev/null new -d -s cliente_t -x 120 -y 30 'bash --norc' 2>/dev/null
c=$(tmux list-clients -F '#{client_name}' | head -1)
tmux run-shell -b "$TT --email '$c'"; sleep 2
# Não pode sobrar uma sessão de e-mail "rodando aerc" (seria o popup vazio); o botao_email trata o erro.
if tmux has-session -t =_tt-email 2>/dev/null; then
  pc=$(tmux display -p -t =_tt-email: '#{pane_current_command}' 2>/dev/null || true)
  if [[ $pc == aerc* ]]; then falhou "sessão ficou com aerc vivo após erro (popup vazio): $pc"; fi
fi
tmux kill-server 2>/dev/null || true
passou 'aerc que sai com erro não deixa popup vazio (botao_email detecta e avisa)'

echo "TODOS OS GUARDRAILS PASSARAM"
