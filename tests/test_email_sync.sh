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
export PATH="$T/bin:$TT_PATH_BASE"
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
"$TT" --email-adicionar nome=LocalOA endereco=oa@empresa.com provedor=microsoft auth=oauth oauth_client_id=cid graph=0 sync_local=1 >/dev/null || falhou 'cadastro oauth com sync_local'
rcoa=$(RC localoa)
grep -q 'PassCmd "python3 .*email-tt.py oauth-token .*localoa.conf"' "$rcoa" || falhou "oauth: PassCmd não usa oauth-token: $(grep PassCmd "$rcoa")"
grep -q '^AuthMechs XOAUTH2$' "$rcoa" || falhou 'oauth: faltou AuthMechs XOAUTH2'
passou 'OAuth2: PassCmd via email-tt.py oauth-token e AuthMechs XOAUTH2'

# Graph (graph=1): a volta completa espelha INBOX + pastas padrão como maildir válido (cur/new/tmp),
# refeitas do servidor a cada sync; o modo inbox traz só o INBOX. Sem rede: stub do graph_get.
python3 - "$(dirname "$0")/../email-tt.py" "$T/graphmd" <<'PY' || falhou 'graph_sync (completo/inbox) não espelhou as pastas certas'
import importlib.util, os, sys, shutil
spec = importlib.util.spec_from_file_location("emailtt", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
base = sys.argv[2]
consultas = []
def graph_get(c, caminho):
    consultas.append(caminho)
    return {"value": [
    {"id": "A" + caminho, "subject": "a", "from": {"emailAddress": {"name": "N", "address": "n@x"}}, "isRead": True},
    {"id": "B" + caminho, "subject": "b", "from": {"emailAddress": {"name": "M", "address": "m@x"}}, "isRead": False,
     "internetMessageHeaders": [
         {"name": "Authentication-Results", "value": "mx.example; dkim=pass header.i=@x"},
         {"name": "Authentication-Results", "value": "forged; dmarc=fail"},
         {"name": "X-Private-Test", "value": "not copied"},
     ]},
]}
m.graph_get = graph_get

# (o graph_sync lista leve e busca a mensagem completa de cada nova: o falso acha pelo id visto na listagem)
_lista = m.graph_get; _vistas = {}; detalhes = []
def _com_detalhe(c, caminho):
    import urllib.parse
    if caminho.startswith("/me/messages/"):
        detalhes.append(caminho)
        return _vistas[urllib.parse.unquote(caminho.split("/")[3].split("?")[0])]
    r = _lista(c, caminho)
    for x in r.get("value", []):
        _vistas[x["id"]] = x
    return r
m.graph_get = _com_detalhe
m.graph_sync({"_slug": "g"}, base, 50, True)   # completo
for p in ("INBOX", "Enviados", "Lixeira", "Rascunhos", "Spam", "Arquivo"):
    for sub in ("cur", "new", "tmp"):
        assert os.path.isdir(os.path.join(base, p, sub)), "faltou %s/%s" % (p, sub)
    n = len(os.listdir(os.path.join(base, p, "cur"))) + len(os.listdir(os.path.join(base, p, "new")))
    assert n == 2, "%s: esperava 2 msgs, achou %d" % (p, n)
    # Message IDs replace slash and colon before becoming maildir filenames.
    b = next(os.path.join(base, p, "new", f) for f in os.listdir(os.path.join(base, p, "new")) if f.startswith("B"))
    raw = open(b, encoding="utf-8").read()
    assert "Authentication-Results: mx.example; dkim=pass header.i=@x" in raw, "faltou preservar Authentication-Results"
    assert "Authentication-Results: forged; dmarc=fail" in raw, "a ordem dos resultados não foi preservada"
    assert "X-Private-Test" not in raw, "cabeçalho não necessário foi copiado"
assert detalhes and all("internetMessageHeaders" in q for q in detalhes), "Graph não pediu internetMessageHeaders"
shutil.rmtree(base)
m.graph_sync({"_slug": "g"}, base, 50, False)  # inbox só
assert os.path.isdir(os.path.join(base, "INBOX")), "inbox-só não criou INBOX"
assert not os.path.exists(os.path.join(base, "Enviados")), "inbox-só não devia criar Enviados"
PY
passou 'Graph: completo espelha INBOX+Enviados+Lixeira+Rascunhos+Spam+Arquivo (cur/new/tmp); inbox-só traz só o INBOX'

# Cabeçalhos preservados não criam autenticação sintética. CR/LF não injeta cabeçalhos.
python3 - "$(dirname "$0")/../email-tt.py" "$T/graphmd2" <<'PY' || falhou 'graph_sync: tradução do AuthAs=Internal ou assunto/nome numa linha'
import importlib.util, os, sys, glob
spec = importlib.util.spec_from_file_location("emailtt", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
base = sys.argv[2]
ar_ms = {"name": "Authentication-Results", "value": "mx.microsoft.com 1; dkim=none (message not signed) header.d=none;dmarc=none action=none header.from=empresa.com.br;"}
def h(n, v): return {"name": n, "value": v}
m.graph_get = lambda c, caminho: {"value": [
    {"id": "INT", "subject": "[tt] interno", "from": {"emailAddress": {"name": "Colega", "address": "colega@Empresa.com.br"}}, "isRead": False, "body": {"content": "", "contentType": "text"},
     "internetMessageHeaders": [ar_ms, h("X-MS-Exchange-Organization-MessageDirectionality", "Originating"),
                                h("X-MS-Exchange-Organization-AuthAs", "Internal"), h("X-MS-Exchange-Organization-AuthMechanism", "04")]},
    {"id": "XT", "subject": "[tt] de fora", "from": {"emailAddress": {"name": "Fora", "address": "x@empresa.com.br"}}, "isRead": False, "body": {"content": "", "contentType": "text"},
     "internetMessageHeaders": [ar_ms, h("X-MS-Exchange-Organization-MessageDirectionality", "Incoming"),
                                h("X-MS-Exchange-Organization-AuthAs", "Anonymous"), h("X-MS-Exchange-CrossTenant-AuthAs", "Internal")]},
    {"id": "INJ", "subject": "[tt] a\nAuthentication-Results: x; dmarc=pass", "from": {"emailAddress": {"name": "N\r\nX-Falso: 1", "address": "n@empresa.com.br"}}, "isRead": False, "body": {"content": "", "contentType": "text"}},
]}

# (o graph_sync lista leve e busca a mensagem completa de cada nova: o falso acha pelo id visto na listagem)
_lista = m.graph_get; _vistas = {}; detalhes = []
def _com_detalhe(c, caminho):
    import urllib.parse
    if caminho.startswith("/me/messages/"):
        detalhes.append(caminho)
        return _vistas[urllib.parse.unquote(caminho.split("/")[3].split("?")[0])]
    r = _lista(c, caminho)
    for x in r.get("value", []):
        _vistas[x["id"]] = x
    return r
m.graph_get = _com_detalhe
m.graph_sync({"_slug": "g"}, base, 50, False)
def ler(i): return open(glob.glob(os.path.join(base, "INBOX", "new", i))[0], encoding="utf-8").read()
def veredito(i):
    import contextlib, io
    o = io.StringIO()
    with contextlib.redirect_stdout(o):
        m.demanda(glob.glob(os.path.join(base, "INBOX", "new", i))[0])
    return o.getvalue().split("\t")[3]
r = ler("INT")
assert "tt-graph" not in r, 'não sintetizar uma prova de autenticação'
assert "header.from=empresa.com.br;" in r, "o resultado do provedor é preservado"
assert veredito("INT") == "fail", "sem prova do provedor, use a autorização relaxada explícita"
r = ler("XT")
assert "tt-graph" not in r, "AuthAs Anonymous (o CrossTenant=Internal é de quem mandou) não pode virar tt-graph: " + r
assert veredito("XT") == "fail"
r = ler("INJ")
cab = r.split("\n\n", 1)[0].split("\n")
assert not any(l.startswith(("Authentication-Results", "X-Falso")) for l in cab), "quebra de linha virou cabeçalho: " + repr(cab)
assert "Subject: [tt] a Authentication-Results: x; dmarc=pass" in cab, repr(cab)
assert veredito("INJ") == "none"
PY
passou 'Graph: preserva veredito do provedor sem autenticação sintética nem injeção de cabeçalhos'

# Graph: a data vai como Date de e-mail (RFC 5322; em ISO o aerc deixava a coluna em branco e a demanda ficava com a hora
# do último sync, a do arquivo refeito) e o Message-ID é o de verdade (a identidade da demanda e do aviso de e-mail novo
# não muda quando o texto do espelho muda). Sem data nem Message-ID no Graph, nada é inventado.
python3 - "$(dirname "$0")/../email-tt.py" "$T/graphmd3" <<'PY' || falhou 'graph_sync: Date em RFC 5322 e Message-ID do Graph'
import importlib.util, os, sys, glob, contextlib, io, email.utils
spec = importlib.util.spec_from_file_location("emailtt", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
base = sys.argv[2]
consultas = []
def graph_get(c, caminho):
    consultas.append(caminho)
    return {"value": [
    {"id": "D1", "subject": "[tt] com data", "from": {"emailAddress": {"name": "C", "address": "c@x.com"}}, "isRead": False, "body": {"content": "", "contentType": "text"},
     "internetMessageId": "<abc.123@x.com>", "sentDateTime": "2026-10-21T18:21:05Z", "receivedDateTime": "2026-10-21T18:21:09Z"},
    {"id": "D2", "subject": "só recebida", "from": {"emailAddress": {"name": "C", "address": "c@x.com"}}, "isRead": False, "body": {"content": "", "contentType": "text"},
     "receivedDateTime": "2026-10-20T09:00:00.1234567Z"},
    {"id": "D3", "subject": "sem nada", "from": {"emailAddress": {"name": "C", "address": "c@x.com"}}, "isRead": False},
]}
m.graph_get = graph_get

# (o graph_sync lista leve e busca a mensagem completa de cada nova: o falso acha pelo id visto na listagem)
_lista = m.graph_get; _vistas = {}; detalhes = []
def _com_detalhe(c, caminho):
    import urllib.parse
    if caminho.startswith("/me/messages/"):
        detalhes.append(caminho)
        return _vistas[urllib.parse.unquote(caminho.split("/")[3].split("?")[0])]
    r = _lista(c, caminho)
    for x in r.get("value", []):
        _vistas[x["id"]] = x
    return r
m.graph_get = _com_detalhe
m.graph_sync({"_slug": "g"}, base, 50, False)
assert detalhes and all("internetMessageId" in q and "sentDateTime" in q for q in detalhes), detalhes
def arq(i): return glob.glob(os.path.join(base, "INBOX", "new", i))[0]
def cab(i): return dict(l.split(": ", 1) for l in open(arq(i), encoding="utf-8").read().split("\n\n", 1)[0].split("\n"))
h = cab("D1")
assert h["Date"] == "Wed, 21 Oct 2026 18:21:05 +0000", h      # a hora do envio, como no Date do IMAP
assert h["Message-ID"] == "<abc.123@x.com>", h
os.utime(arq("D1"), (2000000000, 2000000000))                   # o arquivo é refeito a cada volta: a hora dele não vale
o = io.StringIO()
with contextlib.redirect_stdout(o):
    m.demanda(arq("D1"))
de, mid, epoch = o.getvalue().split("\t")[:3]
assert mid == "abc.123@x.com", mid
assert int(epoch) == int(email.utils.parsedate_to_datetime("Wed, 21 Oct 2026 18:21:05 +0000").timestamp()), epoch
assert cab("D2")["Date"] == "Tue, 20 Oct 2026 09:00:00 +0000", cab("D2")
h = cab("D3")
assert h['Message-ID'].startswith('<graph-') and h.get("Date", "") == "", h
PY
passou 'Graph: Date em RFC 5322 (a do envio; a demanda fica com a data do e-mail) e o Message-ID do servidor; sem eles, nada inventado'

# Classificação automática: a regra manda cada caso para a categoria certa (sem rede)
python3 - "$(dirname "$0")/../email-tt.py" <<'PYC' || falhou 'classificar_email não mapeou as categorias esperadas'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("emailtt", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
casos = [
  ("x@accountprotection.microsoft.com", "Nova entrada detectada", "Segurança"),
  ("x@e.udemymail.com", "Login da Udemy: código de verificação", "Códigos"),
  ("x@investimentosblue.atlassian.net", "Fulano mencionou você em TU-1", "@ Ação"),
  ("x@investimentosblue.atlassian.net", "Novo comentário no quadro", "Notificações"),
  ("x@lumine.tv", "Oferta imperdível 50% OFF", "Newsletters"),
  ("noreply@build.com", "Failed pipeline for development", "Automações"),
  ("x@itau.com.br", "A fatura do seu cartão fechou", None),
  ("john@springframework.guru", "July Course Sale", "Newsletters"),
  ("service@paypal.com.br", "Status do seu pagamento mudou", "Notificações"),
  ("noreply@shop.app", "Sign in to Shop", "Códigos"),
  ("informativo@livrariatravessa.com.br", "Acontece em Ribeirão| Novembro", "Newsletters"),
  ("faturadigital@itau.com.br", "A fatura do seu cartão fechou", None),
  ("x@desconhecido.com", "assunto qualquer", None),
]
for frm, subj, esp in casos:
    got = m.classificar_email(frm, subj)
    assert got == esp, "%r / %r: esperava %r, deu %r" % (frm, subj, esp, got)
PYC
passou 'classificar_email: Códigos/Segurança/@ Ação/Notificações/Newsletters/Automações e resíduo no INBOX'


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
# o mbsync põe no erro o comando inteiro, e o "AUTHENTICATE XOAUTH2 …" leva o token: ele não fica no .erro
printf '#!/bin/sh\necho "IMAP command '"'"'AUTHENTICATE XOAUTH2 dXNlcj1ldUBnbWFpbC5jb20BYXV0aD1CZWFyZXIgeWEyOS5zZWdyZWRv'"'"' returned an error: AUTHENTICATE failed." >&2\nexit 1\n' >"$T/bin/mbsync"
"$TT" --email-sync Local >/dev/null 2>&1
grep -q "AUTHENTICATE XOAUTH2 \[omitido\]' returned an error" "$E/local.erro" || falhou "erro do XOAUTH2 deveria ficar sem o token: $(cat "$E/local.erro")"
grep -q 'dXNlcj1ldUBn' "$E/local.erro" "$E/local.erro-completo" 2>/dev/null && falhou 'o token ficou no .erro'
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

# Lida/não lida marcada no cliente volta ao Graph antes da reconstrução da pasta; primeira volta sem
# manifesto não devolve nada; sem permissão (403) a marcação fica local e o sync segue.
python3 - "$(dirname "$0")/../email-tt.py" "$T/graphlidos" <<'PY' || falhou 'graph_sync: lida/não lida do cliente não voltou ao Graph'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("emailtt", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
base = sys.argv[2]
servidor = {"A/1": False, "B:2": True, "C": False}
def graph_get(c, caminho):
    return {"value": [{"id": i, "subject": i, "from": {"emailAddress": {"address": "x@y"}}, "isRead": l}
                      for i, l in servidor.items()]}
patches, status = [], [200]
def outlook_marcar_lido(c, mid, lido):
    patches.append((mid, lido))
    if status[0] < 300:
        servidor[mid] = lido
    return status[0]
m.graph_get, m.outlook_marcar_lido = graph_get, outlook_marcar_lido

# (o graph_sync lista leve e busca a mensagem completa de cada nova: o falso acha pelo id visto na listagem)
_lista = m.graph_get; _vistas = {}; detalhes = []
def _com_detalhe(c, caminho):
    import urllib.parse
    if caminho.startswith("/me/messages/"):
        detalhes.append(caminho)
        return _vistas[urllib.parse.unquote(caminho.split("/")[3].split("?")[0])]
    r = _lista(c, caminho)
    for x in r.get("value", []):
        _vistas[x["id"]] = x
    return r
m.graph_get = _com_detalhe
inbox = os.path.join(base, "INBOX")
m.graph_sync({}, base, 50)
assert patches == [], "primeira volta não pode devolver nada ao servidor"
# o cliente lê A/1 (new/X → cur/X:2,S) e marca B:2 como não lida (cur/X:2,S → cur/X:2,)
os.rename(os.path.join(inbox, "new", "A_1"), os.path.join(inbox, "cur", "A_1:2,S"))
os.rename(os.path.join(inbox, "cur", "B_2:2,S"), os.path.join(inbox, "cur", "B_2:2,"))
m.graph_sync({}, base, 50)
assert dict(patches) == {"A/1": True, "B:2": False}, patches
assert servidor == {"A/1": True, "B:2": False, "C": False}, servidor
assert os.path.exists(os.path.join(inbox, "cur", "A_1:2,S")), "A/1 devia voltar lida"
assert os.path.exists(os.path.join(inbox, "cur", "B_2:2,")), "B:2 devia seguir não lida, no mesmo arquivo"
patches.clear(); m.graph_sync({}, base, 50)
assert patches == [], "sem mudança local não há PATCH: %r" % patches
# sem permissão de escrita: avisa, não quebra o sync e o arquivo volta como o servidor diz
status[0] = 403
os.rename(os.path.join(inbox, "new", "C"), os.path.join(inbox, "cur", "C:2,S"))
m.graph_sync({}, base, 50)
assert len(patches) == 1 and servidor["C"] is False, (patches, servidor)
assert os.path.exists(os.path.join(inbox, "cur", "C:2,")), "sem permissão, C segue não lida como no servidor"
PY
passou 'Graph: lida/não lida do cliente volta ao servidor (PATCH IsRead no Outlook REST); 1ª volta e sem mudança não enviam; 403 não quebra'

# Pasta atualizada no lugar: o nome do arquivo (a key do aerc) não muda entre syncs, flags do cliente
# (F, R) ficam, lida no servidor só liga o S, conteúdo novo é regravado no mesmo nome e o que sumiu sai.
python3 - "$(dirname "$0")/../email-tt.py" "$T/graphlugar" <<'PY' || falhou 'graph_sync: a pasta não foi atualizada no lugar'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("emailtt", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
base = sys.argv[2]; inbox = os.path.join(base, "INBOX")
servidor = {"A": {"isRead": False, "subject": "a"}, "B": {"isRead": True, "subject": "b"}, "C": {"isRead": False, "subject": "c"}}
m.graph_get = lambda c, caminho: {"value": [dict(v, id=i, **{"from": {"emailAddress": {"address": "x@y"}}}) for i, v in servidor.items()]}

# (o graph_sync lista leve e busca a mensagem completa de cada nova: o falso acha pelo id visto na listagem)
_lista = m.graph_get; _vistas = {}; detalhes = []
def _com_detalhe(c, caminho):
    import urllib.parse
    if caminho.startswith("/me/messages/"):
        detalhes.append(caminho)
        return _vistas[urllib.parse.unquote(caminho.split("/")[3].split("?")[0])]
    r = _lista(c, caminho)
    for x in r.get("value", []):
        _vistas[x["id"]] = x
    return r
m.graph_get = _com_detalhe
m.outlook_marcar_lido = lambda c, mid, lido: 200
def arquivos():
    return sorted(sub + "/" + a for sub in ("cur", "new") for a in os.listdir(os.path.join(inbox, sub)))
m.graph_sync({}, base, 50)
assert arquivos() == ["cur/B:2,S", "new/A", "new/C"], arquivos()
ino = {a: os.stat(os.path.join(inbox, a)).st_ino for a in arquivos()}
os.rename(os.path.join(inbox, "cur", "B:2,S"), os.path.join(inbox, "cur", "B:2,FRS"))  # aerc: sinalizada e respondida
os.rename(os.path.join(inbox, "new", "C"), os.path.join(inbox, "cur", "C:2,"))        # aerc viu, não leu
m.graph_sync({}, base, 50)
assert arquivos() == ["cur/B:2,FRS", "cur/C:2,", "new/A"], arquivos()
assert os.stat(os.path.join(inbox, "new", "A")).st_ino == ino["new/A"], "sem mudança, o arquivo não pode ser regravado"
servidor["A"]["isRead"] = True; servidor["B"]["subject"] = "b editado"; servidor["B"]["lastModifiedDateTime"] = "2026-10-24T00:00:00Z"; del servidor["C"]
m.graph_sync({}, base, 50)
assert arquivos() == ["cur/A:2,S", "cur/B:2,FRS"], arquivos()
assert "Subject: b editado" in open(os.path.join(inbox, "cur", "B:2,FRS"), encoding="utf-8").read(), "conteúdo novo no mesmo nome"
open(os.path.join(inbox, "new", "A"), "w").write("cópia velha")  # duplicata de outra versão
m.graph_sync({}, base, 50)
assert len([a for a in arquivos() if a.split("/")[1].startswith("A")]) == 1, arquivos()
PY
passou 'Graph: pasta atualizada no lugar (nome estável, flags do cliente preservadas, conteúdo regravado, sumida sai, duplicata some)'

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
