#!/usr/bin/env bash
# E-mail: domínio próprio hospedado na Microsoft 365 é reconhecido pelo MX (DNS falso, sem a base do
# Thunderbird) e o assistente cadastra a conta com OAuth2 e o ID do Thunderbird; o client_id do
# OAuth não é mais exigido antes de ser perguntado (antes: "Falta o ID do app OAuth" em toda conta OAuth).
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"; export PATH=$T/bin:$PATH
mkdir -p "$HOME/.config/aerc" "$HOME/.secrets"

# Servidor DNS falso: MX de blue.test → Microsoft; MX de outro.test → servidor próprio.
cat >"$T/dns.py" <<'PY'
import socket, struct, sys
MX = {"blue.test": "blue-test.mail.protection.outlook.com", "outro.test": "mx.outro.test"}
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(("127.0.0.1", 0))
print(s.getsockname()[1], flush=True); sys.stdout.close()
def rotulos(n): return b"".join(bytes([len(r)]) + r.encode() for r in n.split(".")) + b"\0"
while True:
    d, a = s.recvfrom(512)
    i, partes = 12, []
    while d[i]: partes.append(d[i+1:i+1+d[i]].decode()); i += 1 + d[i]
    q = d[12:i+5]; alvo = MX.get(".".join(partes))
    resp = struct.pack(">HHHHHH", struct.unpack(">H", d[:2])[0], 0x8180, 1, 1 if alvo else 0, 0, 0) + q
    if alvo:
        rd = struct.pack(">H", 10) + rotulos(alvo)
        resp += b"\xc0\x0c" + struct.pack(">HHIH", 15, 1, 60, len(rd)) + rd
    s.sendto(resp, a)
PY
python3 "$T/dns.py" >"$T/porta" </dev/null 2>/dev/null & DNS_PID=$!
trap 'kill $DNS_PID 2>/dev/null' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s $T/porta ]] && break; sleep 0.2; done
export TT_EMAIL_DNS=127.0.0.1:$(cat "$T/porta") TT_EMAIL_ISPDB=http://127.0.0.1:1/ TT_EMAIL_SEM_REDE=1
# Sem rede de verdade: a autorização no fim do assistente falha na hora em vez de falar com a Microsoft.
export https_proxy=http://127.0.0.1:1 HTTPS_PROXY=http://127.0.0.1:1

r=$(python3 "$TT_DIR/email-tt.py" descobrir blue.test)
grep -qx 'provedor=microsoft' <<<"$r" || falhou "MX da Microsoft não reconhecido: $r"
r=$(python3 "$TT_DIR/email-tt.py" descobrir outro.test)
grep -q '^provedor=' <<<"$r" && falhou "MX próprio virou provedor: $r"
grep -qx 'imap_host=imap.outro.test' <<<"$r" || falhou "palpite imap.<domínio> sumiu: $r"
passou 'descoberta pelo MX: Microsoft 365 reconhecida; servidor próprio cai no palpite'

# "Outro" com domínio da Microsoft: vira provedor microsoft, mas preserva a escolha explícita por senha.
printf 'outro\neu@blue.test\nBlue\nsenha\nSENHA_BLUE\nSENHA_BLUE\n' | "$TT" --email-conta-nova-ui >"$T/saida" 2>&1
c=$HOME/.config/tt/email/blue.conf
[[ -f $c ]] || falhou "assistente não gravou a conta: $(tail -3 "$T/saida")"
for l in provedor=microsoft auth=senha imap_host=outlook.office365.com smtp_host=smtp.office365.com smtp_porta=587 smtp_seg=starttls; do
  grep -qx "$l" "$c" || falhou "conta Blue sem $l"
done
grep -q '^oauth_client_id=' "$c" && falhou 'descoberta sobrescreveu a escolha por senha'
[[ $(cat "$HOME/.secrets/aerc-blue.txt") == SENHA_BLUE ]] || falhou 'senha escolhida não foi preservada'
passou 'assistente: descoberta Microsoft preserva a autenticação escolhida pelo usuário'

# Provedor Microsoft escolhido direto, OAuth2, client_id em branco = Thunderbird.
printf 'microsoft\neu@m.test\nM365\noauth\n\n' | "$TT" --email-conta-nova-ui >"$T/saida" 2>&1
mc=$HOME/.config/tt/email/m365.conf
grep -qx 'oauth_client_id=9e5f94bc-e8a4-4e73-b8be-63364c29d753' "$mc" 2>/dev/null ||
  falhou "conta Microsoft com OAuth2 não foi gravada: $(tail -3 "$T/saida")"
grep -qx 'auth=oauth' "$mc" || falhou 'conta Microsoft não ficou com auth=oauth'
grep -q 'Falta o ID' "$T/saida" && falhou 'assistente ainda exige o client_id antes de perguntá-lo'
passou 'assistente: OAuth2 da Microsoft não para em "Falta o ID do app OAuth"'
