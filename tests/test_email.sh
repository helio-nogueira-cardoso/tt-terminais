#!/usr/bin/env bash
# E-mail: provedores, segurança/portas → URLs do aerc, segredos fora do accounts.conf (600),
# importação de conta antiga, conta manual intacta, assistente sem terminal, remoção, teste de
# conexão com erro legível e OAuth2 (código no aparelho) contra um servidor de autorização falso.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"; export PATH=$T/bin:$PATH
A=$HOME/.config/aerc/accounts.conf
mkdir -p "$HOME/.config/aerc" "$HOME/.secrets"
printf '\n[Antiga]\nsource        = imaps://a%%40gmail.com@imap.gmail.com:993\nsource-cred-cmd = cat ~/.secrets/aerc-antiga.txt\nfrom          = a@gmail.com\n\n[Manual]\nsource = imaps://m@x.com@mail.x.com:993\n' >"$A"
printf 'SEGREDO_ANTIGO' >"$HOME/.secrets/aerc-antiga.txt"

echo 'SENHA_FICT_1' | "$TT" --email-adicionar nome=Pessoal endereco=eu@gmail.com provedor=gmail auth=senha --senha-stdin >/dev/null || falhou 'cadastro gmail'
"$TT" --email-adicionar nome=Trabalho endereco=eu@empresa.com provedor=microsoft auth=oauth oauth_client_id=id-ficticio >/dev/null || falhou 'cadastro microsoft'
echo 'BRIDGE_FICT' | "$TT" --email-adicionar nome=Proton endereco=eu@proton.me provedor=proton auth=senha --senha-stdin >/dev/null || falhou 'cadastro proton'
"$TT" --email-adicionar nome=Custom endereco=eu@x.com.br imap_host=mail.x.com.br imap_porta=143 imap_seg=starttls \
  smtp_host=mail.x.com.br smtp_porta=587 smtp_seg=starttls usuario=login-x auth=comando 'cred_cmd=pass email/x' >/dev/null || falhou 'cadastro manual'
grep -q '^source *= imaps://eu%40gmail.com@imap.gmail.com:993$' "$A" || falhou 'gmail: URL IMAP'
grep -q '^outgoing *= smtps://eu%40gmail.com@smtp.gmail.com:465$' "$A" || falhou 'gmail: URL SMTP'
grep -q '^source *= imaps+xoauth2://eu%40empresa.com@outlook.office365.com:993?token_endpoint=.*client_id=id-ficticio' "$A" || falhou 'microsoft: URL OAuth2'
grep -q '^outgoing *= smtp+xoauth2://eu%40empresa.com@smtp.office365.com:587?' "$A" || falhou 'microsoft: SMTP STARTTLS + OAuth2'
grep -q '^source *= imap+insecure://eu%40proton.me@127.0.0.1:1143$' "$A" || falhou 'proton: bridge sem TLS'
grep -q '^source *= imap://login-x@mail.x.com.br:143$' "$A" || falhou 'manual: STARTTLS e usuário próprio'
grep -q '^source-cred-cmd *= pass email/x$' "$A" || falhou 'manual: comando externo'
passou 'provedores e configuração avançada geram as URLs certas do aerc (TLS/STARTTLS/nenhuma, OAuth2, usuário)'

grep -q 'SENHA_FICT_1\|BRIDGE_FICT\|SEGREDO_ANTIGO' "$A" && falhou 'segredo vazou para o accounts.conf'
[[ $(stat -c %a "$HOME/.secrets/aerc-pessoal.txt") == 600 ]] || falhou 'senha não está com permissão 600'
[[ $(cat "$HOME/.secrets/aerc-pessoal.txt") == SENHA_FICT_1 ]] || falhou 'senha não gravada'
passou 'segredos só em ~/.secrets (600), nunca no accounts.conf'

l=$("$TT" --email-listar)
grep -q $'^antiga\tAntiga\ta@gmail.com\tgmail' <<<"$l" || falhou "conta antiga não importada: $l"
[[ $(grep -c '^\[Antiga\]$' "$A") == 1 && $(grep -c '^\[Manual\]$' "$A") == 1 ]] || falhou 'importação duplicou ou apagou blocos'
passou 'conta do cadastro antigo vira gerenciada; bloco escrito à mão fica intacto'

echo x | "$TT" --email-adicionar nome=Pessoal endereco=b@gmail.com provedor=gmail auth=senha --senha-stdin >/dev/null && falhou 'aceitou nome repetido'
echo x | "$TT" --email-adicionar 'nome=pessoal!' endereco=c@gmail.com provedor=gmail auth=senha --senha-stdin >/dev/null && falhou 'aceitou identificador colidente'
[[ $(cat "$HOME/.secrets/aerc-pessoal.txt") == SENHA_FICT_1 ]] || falhou 'colisão sobrescreveu a senha'
echo x | "$TT" --email-adicionar 'nome=Tra[balho]' endereco=t@gmail.com provedor=gmail auth=senha --senha-stdin >/dev/null && falhou 'aceitou [ ] no nome'
"$TT" --email-adicionar nome=Ruim endereco=r@x.com imap_host=h imap_porta=abc imap_seg=tls smtp_host=h smtp_porta=1 smtp_seg=tls auth=comando cred_cmd=x >/dev/null && falhou 'aceitou porta inválida'
passou 'validação: nome repetido, identificador colidente, [ ] e porta inválida recusados'

# Assistente sem terminal: provedor, endereço, nome, autenticação, senha, senha.
printf 'yahoo\neu@yahoo.com\nYahoo\nsenha\nSENHA_Y\nSENHA_Y\n' | "$TT" --email-conta-nova-ui >/dev/null 2>&1
grep -q '^source *= imaps://eu%40yahoo.com@imap.mail.yahoo.com:993$' "$A" || falhou 'assistente: conta Yahoo não foi gravada'
[[ $(cat "$HOME/.secrets/aerc-yahoo.txt" 2>/dev/null) == SENHA_Y ]] || falhou 'assistente: senha não gravada'
passou 'assistente guiado cadastra conta (provedor → endereço → nome → autenticação → senha)'

"$TT" --email-remover Proton >/dev/null || falhou 'remover'
grep -q 'Proton' "$A" && falhou 'bloco do Proton ficou no accounts.conf'
[[ -e $HOME/.secrets/aerc-proton.txt ]] && falhou 'senha do Proton ficou em ~/.secrets'
"$TT" --email-remover NaoExiste >/dev/null && falhou 'remover conta inexistente deu sucesso'
passou 'descadastrar apaga o bloco e o segredo, só daquela conta'

"$TT" --email-adicionar nome=Falsa endereco=f@x.invalid imap_host=imap.nao.invalid imap_porta=993 imap_seg=tls \
  smtp_host=smtp.nao.invalid smtp_porta=587 smtp_seg=starttls auth=comando 'cred_cmd=echo x' >/dev/null
r=$("$TT" --email-testar Falsa) && falhou 'teste de servidor inexistente deu sucesso'
grep -q '✗ IMAP (receber): servidor não encontrado' <<<"$r" || falhou "mensagem de erro ruim: $r"
passou 'testar conexão: erro legível quando o servidor não existe'

# OAuth2 (código no aparelho) contra servidor falso: grava o refresh token (600) e renova o access token.
cat >"$T/oauth.py" <<'PY'
import http.server, json, sys, urllib.parse
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        d = urllib.parse.parse_qs(self.rfile.read(int(self.headers["Content-Length"])).decode())
        g = d.get("grant_type", [""])[0]
        if self.path == "/device": r = {"device_code": "DC", "user_code": "ABCD-1234", "verification_uri": "https://exemplo/aparelho", "interval": 1, "expires_in": 30}
        elif g.endswith("device_code"): r = {"refresh_token": "RT_FICT", "access_token": "AT_1"}
        elif g == "refresh_token": r = {"access_token": "AT_" + d["refresh_token"][0]}
        else: r = {"error": "invalid_grant"}
        b = json.dumps(r).encode(); self.send_response(200); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H); print(s.server_address[1], flush=True); s.serve_forever()
PY
python3 "$T/oauth.py" >"$T/porta" & sleep 1; P=$(cat "$T/porta")
"$TT" --email-adicionar nome=SSO endereco=eu@sso.test imap_host=imap.sso.test imap_porta=993 imap_seg=tls smtp_host=smtp.sso.test \
  smtp_porta=587 smtp_seg=starttls auth=oauth oauth_client_id=cid "oauth_device_endpoint=http://127.0.0.1:$P/device" \
  "oauth_token_endpoint=http://127.0.0.1:$P/token" "oauth_scope=mail" >/dev/null || falhou 'cadastro OAuth genérico'
r=$("$TT" --email-autorizar SSO </dev/null) || falhou "autorização falhou: $r"
grep -q 'ABCD-1234' <<<"$r" || falhou 'código para digitar não foi mostrado'
[[ $(cat "$HOME/.secrets/aerc-sso.txt") == RT_FICT && $(stat -c %a "$HOME/.secrets/aerc-sso.txt") == 600 ]] || falhou 'refresh token não gravado com 600'
[[ $(python3 "$TT_DIR/email-tt.py" oauth-token "$XDG_CONFIG_HOME/tt/email/sso.conf") == AT_RT_FICT ]] || falhou 'renovação do access token'
grep -q 'RT_FICT' "$A" && falhou 'refresh token vazou para o accounts.conf'
grep -q "^source *= imaps+xoauth2://eu%40sso.test@imap.sso.test:993?token_endpoint=http%3A%2F%2F127.0.0.1%3A$P%2Ftoken&client_id=cid&scope=mail$" "$A" || falhou 'URL OAuth genérica'
passou 'OAuth2/SSO: código no aparelho, token de renovação em ~/.secrets (600), renovação e URL do aerc'

# Conta escrita à mão (fora dos marcadores) aparece como manual e, assumida, gera bloco equivalente.
B=$T/manual; mkdir -p "$B/.config/aerc"
printf '# minha conta\n[Minha]\nsource        = imaps://m%%40x.com@imap.x.com:993\nsource-cred-cmd = cat ~/.secrets/minha-senha\noutgoing      = smtps://m%%40x.com@smtp.x.com:465\noutgoing-cred-cmd = cat ~/.secrets/minha-senha\nfrom          = Fulano de Tal <m@x.com>\ncopy-to       = "Enviados"\ndefault       = INBOX\n' >"$B/.config/aerc/accounts.conf"
l=$(HOME=$B XDG_CONFIG_HOME=$B/.config "$TT" --email-listar)
grep -q $'^!Minha\tMinha\t-\tmanual' <<<"$l" || falhou "conta manual não listada: $l"
HOME=$B XDG_CONFIG_HOME=$B/.config "$TT" --email-assumir Minha >/dev/null || falhou 'assumir conta manual'
ef() { grep -v '^#' "$1" | grep -v '^$' | sed 's/ *= */=/' | sort; }
diff <(ef "$B/.config/aerc/accounts.conf.antes-tt") <(ef "$B/.config/aerc/accounts.conf") >/dev/null || falhou 'conta assumida não ficou equivalente à original'
grep -q '^# >>> tt e-mail: minha >>>' "$B/.config/aerc/accounts.conf" || falhou 'conta assumida sem marcadores'
passou 'conta escrita à mão: listada como manual; assumida fica equivalente (comando de senha, copy-to, nome) e com cópia'
