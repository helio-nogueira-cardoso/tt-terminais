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

# Microsoft continua com o app do Thunderbird; o padrão do Gmail não interfere.
"$TT" --email-adicionar nome=Ms endereco=m@empresa.com provedor=microsoft auth=oauth oauth_client_id=9e5f94bc-e8a4-4e73-b8be-63364c29d753 >/dev/null || falhou 'cadastro microsoft oauth'
[[ -e $HOME/.secrets/aerc-ms.client_secret ]] && falhou 'segredo do Gmail gravado numa conta Microsoft'
passou 'padrão do Gmail não vaza para outros provedores'

echo 'ok: app OAuth do tt para Gmail (de fábrica, seguro, sem segredo no .conf)'
