#!/usr/bin/env bash
# App OAuth do tt para Gmail: conta gmail auth=oauth sem client_id ganha o app embutido
# (client_id no .conf e client_secret em ~/.secrets, 600); quem traz o próprio client_id
# não é tocado (sem arquivo de segredo do tt); o segredo nunca vai para o .conf.
source "$(dirname "$0")/lib.sh"; isolar

"$TT" --email-adicionar nome=Padrao endereco=eu@gmail.com provedor=gmail auth=oauth >/dev/null ||
  falhou 'cadastro gmail oauth sem client_id deveria funcionar de fábrica'
conf=$HOME/.config/tt/email/padrao.conf
grep -q '^oauth_client_id=.*\.apps\.googleusercontent\.com$' "$conf" || falhou 'client_id do tt não entrou no .conf'
grep -q '^oauth_token_endpoint=https://oauth2.googleapis.com/token$' "$conf" || falhou 'endpoints do Google ausentes'
seg=$HOME/.secrets/aerc-padrao.client_secret
[[ -s $seg ]] || falhou 'client_secret do app do tt não foi gravado'
[[ $(stat -c %a "$seg") == 600 ]] || falhou "client_secret deveria ser 600 (é $(stat -c %a "$seg"))"
grep -q '^GOCSPX-' "$seg" || falhou 'client_secret sem o formato esperado'
grep -q 'GOCSPX' "$conf" && falhou 'o segredo vazou para o .conf'
passou 'gmail oauth de fábrica: app do tt no .conf e segredo em ~/.secrets (600), fora do .conf'

"$TT" --email-adicionar nome=Proprio endereco=p@gmail.com provedor=gmail auth=oauth \
  oauth_client_id=meu.apps.googleusercontent.com >/dev/null || falhou 'cadastro com client próprio'
grep -q '^oauth_client_id=meu.apps.googleusercontent.com$' "$HOME/.config/tt/email/proprio.conf" ||
  falhou 'client próprio foi sobrescrito pelo padrão'
[[ -e $HOME/.secrets/aerc-proprio.client_secret ]] && falhou 'segredo do tt gravado para client próprio'
passou 'client_id próprio é respeitado, sem segredo do tt'

# Microsoft sem client_id: o padrão é Outlook Mobile + Microsoft Graph; "thunderbird" segue disponível.
"$TT" --email-adicionar nome=MsOut endereco=t@empresa.com provedor=microsoft auth=oauth >/dev/null || falhou 'cadastro microsoft oauth sem client_id'
c=$HOME/.config/tt/email/msout.conf
grep -qx 'oauth_client_id=27922004-5251-4030-b22d-91ecd9a37ea4' "$c" || falhou "Microsoft sem client_id deveria usar Outlook Mobile: $(grep oauth_client_id "$c")"
grep -qx 'graph=1' "$c" || falhou 'Microsoft padrão deveria usar Graph'
grep -qx 'oauth_scope=offline_access https://graph.microsoft.com/.default' "$c" || falhou 'escopo Graph ausente'
[[ -e $HOME/.secrets/aerc-msout.client_secret ]] && falhou 'app da Microsoft é cliente público: nada de segredo'
"$TT" --email-adicionar nome=MsTb endereco=b@empresa.com provedor=microsoft auth=oauth oauth_client_id=thunderbird >/dev/null || falhou 'cadastro microsoft oauth thunderbird'
grep -qx 'oauth_client_id=9e5f94bc-e8a4-4e73-b8be-63364c29d753' "$HOME/.config/tt/email/mstb.conf" || falhou '"thunderbird" deveria virar o ID público do Thunderbird'
"$TT" --email-adicionar nome=MsTt endereco=t@empresa.com provedor=microsoft auth=oauth oauth_client_id=tt >/dev/null || falhou 'cadastro microsoft oauth tt'
grep -qx 'oauth_client_id=fa7042a4-7b4f-4148-833b-ceb8ce1b8808' "$HOME/.config/tt/email/mstt.conf" || falhou '"tt" deveria virar o ID do app do tt (EMAIL_MICROSOFT_ID)'
passou 'Microsoft: app do tt de fábrica, "thunderbird" e "tt" ainda disponíveis'

# Microsoft com o app do Thunderbird informado à mão; o padrão do Gmail não interfere.
"$TT" --email-adicionar nome=Ms endereco=m@empresa.com provedor=microsoft auth=oauth oauth_client_id=9e5f94bc-e8a4-4e73-b8be-63364c29d753 >/dev/null || falhou 'cadastro microsoft oauth'
[[ -e $HOME/.secrets/aerc-ms.client_secret ]] && falhou 'segredo do Gmail gravado numa conta Microsoft'
passou 'padrão do Gmail não vaza para outros provedores'

echo 'ok: app OAuth do tt para Gmail (de fábrica, seguro, sem segredo no .conf)'
