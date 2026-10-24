#!/usr/bin/env bash
# Conta do Microsoft Graph (graph=1; o espelho é refeito do servidor: o INBOX e, na volta completa, as pastas padrão):
#  - sem token nesta máquina, o sync não vai à rede: o .erro diz para autorizar e o vigia espera antes de tentar de novo;
#  - o erro de uma rodada ruim fica sem o token ("Bearer …"), e a rodada boa limpa erro e espera; a volta completa
#    pede o modo completo ao graph-sync e guarda/apaga o próprio erro, como a do mbsync;
#  - o --checar conta as voltas completas ruins (sem o token) e a linha da lixeira diz o que o Graph faz;
#  - o --email-sync-estado mostra a volta completa; o --email-conferir --corrigir não procura a lixeira pelo IMAP;
#  - conta com classificar=1: a classificação no servidor roda antes do espelho, e só com token (sem ele não vai à rede);
#  - graph_token (email-tt.py): sem token diz que falta autorizar, a recusa traz a causa da Microsoft e o refresh
#    token devolvido na renovação fica guardado.
source "$(dirname "$0")/lib.sh"; isolar
PY=$(command -v python3)
mkdir -p "$T/bin" "$HOME/.secrets" "$XDG_CONFIG_HOME/tt/email"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"
# python3 de mentira só para o graph-sync e o pastas (o resto vai ao de verdade): registra a chamada e devolve
# o que o teste deixou em $T/py.erro e $T/py.rc
cat >"$T/bin/python3" <<EOF
#!/bin/sh
case "\$2" in
  graph-sync|pastas) echo "\$2 \$6" >>"$T/py.chamadas"; cat "$T/py.erro" >&2 2>/dev/null; exit \$(cat "$T/py.rc" 2>/dev/null || echo 0) ;;
  graph-classificar) echo "\$2" >>"$T/py.chamadas"; echo classificadas=0; exit 0 ;;
esac
exec "$PY" "\$@"
EOF
chmod +x "$T/bin/python3"
export PATH="$T/bin:$TT_PATH_BASE"
export _TT_PATH_ORIGEM=$PATH # o bootstrap do Mac não deve esconder o python falso
ES=$HOME/.local/state/tt/email-sync
printf 'nome=Trabalho\nendereco=eu@empresa.com\nprovedor=microsoft\nauth=oauth\ngraph=1\nimap_host=outlook.office365.com\noauth_client_id=cid\noauth_token_endpoint=https://login.exemplo/token\nsync_local=1\nclassificar=1\n' \
  >"$XDG_CONFIG_HOME/tt/email/trab.conf"

# --- Sem token: nada de rede, o .erro manda autorizar, e o vigia espera ----------------------------------------
"$TT" --email-sync trab   # (calado e sempre 0: o aerc e o tmux o chamam)
[[ ! -e $T/py.chamadas ]] || falhou "sem token, o graph-sync e a classificação não deveriam rodar: $(cat "$T/py.chamadas")"
grep -q 'ainda não autorizada.*tt --email-autorizar trab' "$ES/trab.erro" && [[ $(tail -1 "$ES/trab") == inbox*$'\t'1 ]] || falhou "o .erro deveria mandar autorizar: $(cat "$ES/trab.erro" 2>/dev/null)"
[[ -s $ES/trab.espera ]] || falhou 'depois da falha a conta deveria esperar'
n=$(wc -l <"$ES/trab")
"$TT" --email-sync trab --vigia
[[ $(wc -l <"$ES/trab") == "$n" ]] || falhou 'o vigia não respeitou a espera da conta Graph'
passou 'Graph sem token: sem rede, o erro manda autorizar e o vigia espera'

# --- Com token: o erro sai sem o token; a rodada boa limpa erro, espera e a volta completa de antes ---------------
printf 'rt' >"$HOME/.secrets/aerc-trab.txt"; chmod 600 "$HOME/.secrets/aerc-trab.txt"
echo '✗ HTTP Error 401: Unauthorized (Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.c2VncmVkbw.assinatura)' >"$T/py.erro"; echo 1 >"$T/py.rc"
"$TT" --email-sync trab
grep -q 'Bearer \[omitido\]' "$ES/trab.erro" || falhou "o .erro deveria guardar a causa sem o token: $(cat "$ES/trab.erro")"
grep -q 'eyJ0eXAi\|c2VncmVkbw' "$ES/trab.erro" && falhou 'o token ficou no .erro'
agora=$(date +%s)
"$TT" --email-sync trab --completo
grep -q 'Bearer \[omitido\]' "$ES/trab.erro-completo" || falhou "a volta completa ruim deveria guardar o erro dela, sem o token: $(cat "$ES/trab.erro-completo" 2>/dev/null)"
[[ $(tail -1 "$ES/trab") == completo*$'\t'1 ]] || falhou "a volta completa não ficou registrada: $(tail -1 "$ES/trab")"
: >"$T/py.erro"; echo 0 >"$T/py.rc"; rm -f "$T/py.chamadas"
"$TT" --email-sync trab
for x in erro espera falhas; do [[ -e $ES/trab.$x ]] && falhou "a rodada boa deveria apagar o .$x"; done
[[ -e $ES/trab.erro-completo ]] || falhou 'a rodada do INBOX não apaga o erro da volta completa'
grep -qx 'graph-sync inbox' "$T/py.chamadas" || falhou "o INBOX deveria pedir o modo inbox: $(cat "$T/py.chamadas")"
[[ $(head -1 "$T/py.chamadas") == graph-classificar ]] || falhou "com classificar=1 e token, a classificação deveria rodar antes do espelho: $(cat "$T/py.chamadas")"
"$TT" --email-sync trab --completo
grep -qx 'graph-sync completo' "$T/py.chamadas" || falhou "--completo deveria pedir o modo completo: $(cat "$T/py.chamadas")"
[[ -e $ES/trab.erro-completo ]] && falhou 'a volta completa boa deveria apagar o .erro-completo'
passou 'Graph: erro sem o token, rodada boa limpa erro e espera, a volta completa pede o modo completo e cuida do próprio erro'

# --- --checar, --email-sync-estado e --email-conferir ------------------------------------------------------------
printf 'completo\t%s\t%s\t1\ncompleto\t%s\t%s\t1\n' $((agora-60)) $((agora-59)) $((agora-30)) $((agora-29)) >>"$ES/trab"
echo "IMAP command 'AUTHENTICATE XOAUTH2 dXNlcj1ldUBlbXByZXNhLmNvbQFhdXRoPUJlYXJlciBzZWdyZWRv' returned an error" >"$ES/trab.erro-completo"
saida=$("$TT" --checar --tsv) || true
l=$(grep '^email:trab' <<<"$saida")
[[ $l == $'email:trab\taviso\t'*'falhou 2 vezes'*'XOAUTH2 [omitido]'* ]] || falhou "as voltas completas ruins contam, sem o token: $l"
l=$(grep '^email-cmd:trab' <<<"$saida")
[[ $l == $'email-cmd:trab\taviso\t'*'Microsoft Graph'*'Outlook'* ]] || falhou "a linha da lixeira deveria dizer o que o Graph faz: $l"
grep -q 'dXNlcj1ldUBl' <<<"$saida" && falhou 'o token apareceu no --checar'
est=$("$TT" --email-sync-estado)
grep -q 'completo  há .*erro 1' <<<"$est" || falhou "--email-sync-estado da conta Graph deveria mostrar a volta completa: $est"
rm -f "$T/py.chamadas"
TT_EMAIL_SEM_REDE='' "$TT" --email-conferir trab --corrigir >/dev/null 2>&1 || true
[[ ! -e $T/py.chamadas ]] || falhou "o --corrigir procurou a lixeira pelo IMAP: $(cat "$T/py.chamadas")"
# o erro de uma versão antiga, gravado com o token, também sai limpo no --checar
echo "IMAP command 'AUTHENTICATE XOAUTH2 dXNlcj1ldUBlbXByZXNhLmNvbQFhdXRoPUJlYXJlciBzZWdyZWRv' returned an error" >"$ES/trab.erro"
printf 'inbox\t%s\t%s\t1\ninbox\t%s\t%s\t1\ninbox\t%s\t%s\t1\n' $((agora-20)) $((agora-19)) $((agora-10)) $((agora-9)) $((agora-5)) $((agora-4)) >>"$ES/trab"
saida=$("$TT" --checar --tsv) || true
l=$(grep '^email:trab' <<<"$saida")
[[ $l == $'email:trab\tfalha\t'*'XOAUTH2 [omitido]'* ]] || falhou "erro antigo deveria aparecer sem o token: $l"
passou 'Graph no --checar (volta completa sem o token, lixeira explicada), no estado e no --corrigir'

# --- graph_token: autorizar, causa da recusa e refresh token novo guardado --------------------------------------
HOME=$HOME "$PY" -I - "$T/pkg/email-tt.py" "$HOME" <<'PY' || falhou 'graph_token (email-tt.py)'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("email_tt", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.SEGREDOS = os.path.join(sys.argv[2], "segredos-teste"); os.makedirs(m.SEGREDOS, exist_ok=True)
c = {"_slug": "g", "auth": "oauth", "graph": "1", "oauth_client_id": "cid", "oauth_token_endpoint": "https://x/token"}
arq = os.path.join(m.SEGREDOS, "aerc-g.txt")
try:
    m.graph_token(c); sys.exit("sem token deveria pedir autorização")
except RuntimeError as e:
    assert "autorizada" in str(e), e
open(arq, "w").write("rt-velho")
pedidos = []
m.post = lambda url, d: (pedidos.append(d), {"access_token": "at", "refresh_token": "rt-novo"})[1]
assert m.graph_token(c, "https://outlook.office.com/.default") == "at"
assert pedidos[-1]["refresh_token"] == "rt-velho" and pedidos[-1]["scope"] == "offline_access https://outlook.office.com/.default", pedidos
assert open(arq).read() == "rt-novo", "o refresh token novo não foi guardado"
assert oct(os.stat(arq).st_mode & 0o777) == "0o600"
m.post = lambda url, d: {"error": "invalid_grant", "error_description": "AADSTS700082: o refresh token venceu"}
try:
    m.graph_token(c); sys.exit("recusa deveria virar erro")
except RuntimeError as e:
    assert "AADSTS700082" in str(e), e
PY
passou 'graph_token: sem token pede autorização, a recusa traz a causa e o refresh token novo fica guardado (600)'

# Lixeira das contas Graph: o token é do Graph e o login IMAP com ele é recusado (AUTHENTICATE failed). Conta pelo
# Graph; esvazia pela API do Outlook e, sem permissão lá, pelo Graph; 404 (já apagada) conta; sem permissão em
# nenhum dos dois, para e diz como resolver. Sem rede: stubs.
python3 -I - "${TT%/*}/email-tt.py" >"$T/lix.log" 2>&1 <<'PY' || falhou "lixeira Graph: $(cat "$T/lix.log")"
import importlib.util, io, contextlib, sys
sp = importlib.util.spec_from_file_location("e", sys.argv[1]); e = importlib.util.module_from_spec(sp); sp.loader.exec_module(e)
lixo = ["a", "b", "c"]
def graph_get(c, caminho):
    if caminho.startswith("/me/mailFolders/deleteditems?"):
        return {"displayName": "Itens Excluídos", "totalItemCount": len(lixo)}
    if caminho.startswith("/me/mailFolders/deleteditems/messages?"):
        return {"value": [{"id": i} for i in lixo]}
    raise AssertionError(caminho)
e.graph_get = graph_get
e.imap_conectar = lambda c: (_ for _ in ()).throw(AssertionError("conta Graph não pode ir pelo IMAP"))
conta = {"provedor": "microsoft", "graph": "1", "auth": "oauth"}
def rodar(esvaziar):
    o = io.StringIO()
    with contextlib.redirect_stdout(o):
        assert e.lixeira(conta, esvaziar) == 0
    return dict(l.split("=", 1) for l in o.getvalue().splitlines() if "=" in l)
assert rodar(False) == {"pasta": "Itens Excluídos", "mensagens": "3"}
tentativas = []
def outlook(c, mid): tentativas.append(("outlook", mid)); return 403
def graph(c, mid):
    tentativas.append(("graph", mid))
    if mid == "b": return 404       # outro aparelho já tinha esvaziado
    lixo.remove(mid); return 204
e.outlook_apagar, e.graph_apagar = outlook, graph
r = rodar(True)
assert r["apagadas"] == "3" and r["restam"] == "1", r     # "b" ainda conta no stub: o servidor diria 0
assert tentativas == [("outlook", "a"), ("graph", "a"), ("graph", "b"), ("graph", "c")], tentativas
e.outlook_apagar = e.graph_apagar = lambda c, mid: 403
try:
    rodar(True); raise AssertionError("sem permissão deveria falhar")
except RuntimeError as x:
    assert "tt --email-autorizar" in str(x), x
print("ok")
PY
passou 'lixeira das contas Graph: conta e esvazia sem IMAP (Outlook, ou Graph sem permissão lá) e explica a falta de permissão'
