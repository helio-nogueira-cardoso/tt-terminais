#!/usr/bin/env bash
# Sync de e-mail por eventos (v2.11): o check-mail do aerc deixa de ir ao servidor quando a conta acabou de
# sincronizar ou o IDLE dela está de pé (--se-preciso); com o IDLE de pé, o vigia espaça o INBOX e a volta
# completa (rede de segurança) e a conta não vira "parado"; o evento do IDLE (--evento) sempre sincroniza, mas
# respeita a espera depois de um erro; o aviso de novos só varre o INBOX quando new/ ou cur/ mudou; a contagem
# da barra é reaproveitada enquanto as pastas não mudam; e o email-tt.py idle, contra um servidor IMAP falso,
# grava o batimento e chama "tt --email-sync CONTA --evento" quando chega mensagem. Isola HOME/XDG; mbsync falso.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"
cat >"$T/bin/mbsync" <<MB
#!/bin/sh
echo "\$@" >>"$T/mbsync.calls"
if [ -n "\$MBSYNC_NOVA" ]; then
  d="$HOME/.cache/tt/maildir/local/INBOX/new"; mkdir -p "\$d"
  printf 'From: a@b.c\nSubject: oi\nMessage-ID: <\$MBSYNC_NOVA@x>\n\ncorpo\n' >"\$d/\$MBSYNC_NOVA.local"
fi
exit \${MBSYNC_RC:-0}
MB
chmod +x "$T/bin"/*
export PATH="$T/bin:$TT_PATH_BASE" TT_EMAIL_IDLE=0
echo 'SENHA' | "$TT" --email-adicionar nome=Local endereco=eu@gmail.com provedor=gmail auth=senha sync_local=1 --senha-stdin >/dev/null || falhou 'cadastro'
E=$HOME/.local/state/tt/email-sync; A=$HOME/.config/aerc/accounts.conf
linha() { printf '%s\t%s\t%s\t%s\n' "$@" >>"$E/local"; }
zera() { mkdir -p "$E"; rm -f "$E"/local "$E"/local.* "$T/mbsync.calls"; : >"$T/mbsync.calls"; }
chamadas() { local n; n=$(wc -l <"$T/mbsync.calls" 2>/dev/null) || n=0; echo $((n)); }
idle_ok() { printf '%s\tok\n' "$(date +%s)" >"$E/local.idle"; }
curto() { "$TT" --email-sync-estado curto | awk -F'\t' '$1 == "local" { print $2 }'; }

# 1) o check-mail do aerc leva --se-preciso; bloco antigo (sem ele) é regravado pela migração
grep -q -- '--email-sync local --se-preciso$' "$A" || falhou "bloco do aerc sem --se-preciso: $(grep check-mail-cmd "$A")"
sed -i 's/ --se-preciso$//' "$A"
(cd / && TT_COMPLETO=1 TT_SO_CARREGAR=1 TT_EMAIL_SEM_REDE=1 bash -c 'source "$1"; email_checkmail_migrar' _ "$TT") >/dev/null 2>&1
grep -q -- '--email-sync local --se-preciso$' "$A" || falhou "bloco antigo do aerc não ganhou o --se-preciso: $(grep check-mail-cmd "$A")"
passou 'o check-mail do aerc chama o sync com --se-preciso'

# 2) --se-preciso: pula se a conta sincronizou há pouco ou o IDLE está de pé; senão vai ao servidor
zera; agora=$(date +%s); linha inbox $((agora - 40)) $((agora - 30)) 0
"$TT" --email-sync local --se-preciso >/dev/null 2>&1
[[ $(chamadas) == 0 ]] || falhou "aerc foi ao servidor 30 s depois de um sync bom: $(cat "$T/mbsync.calls")"
zera; linha inbox $((agora - 400)) $((agora - 390)) 0
"$TT" --email-sync local --se-preciso >/dev/null 2>&1
[[ $(chamadas) == 1 ]] || falhou "aerc sem sync recente nem IDLE deveria sincronizar: $(chamadas)"
zera; linha inbox $((agora - 400)) $((agora - 390)) 0; idle_ok
"$TT" --email-sync local --se-preciso >/dev/null 2>&1
[[ $(chamadas) == 0 ]] || falhou 'aerc foi ao servidor com o IDLE de pé'
passou '--se-preciso não abre a rede logo depois de um sync nem com o IDLE de pé'

# 3) vigia com o IDLE de pé: INBOX só a cada 30 min, completa a cada 2 h; IDLE velho ou com erro = ritmo normal
zera; agora=$(date +%s); linha inbox $((agora - 700)) $((agora - 690)) 0; linha completo $((agora - 3000)) $((agora - 2990)) 0; idle_ok
"$TT" --email-sync local --vigia >/dev/null 2>&1
"$TT" --email-sync local --completo --vigia >/dev/null 2>&1
[[ $(chamadas) == 0 ]] || falhou "vigia sincronizou com o IDLE de pé e rodadas recentes: $(cat "$T/mbsync.calls")"
zera; linha inbox $((agora - 2000)) $((agora - 1990)) 0; linha completo $((agora - 8000)) $((agora - 7990)) 0; idle_ok
"$TT" --email-sync local --vigia >/dev/null 2>&1
"$TT" --email-sync local --completo --vigia >/dev/null 2>&1
[[ $(chamadas) == 2 ]] || falhou "rede de segurança (INBOX > 30 min, completa > 2 h) não rodou: $(chamadas)"
zera; linha inbox $((agora - 700)) $((agora - 690)) 0; printf '%s\tok\n' $((agora - 600)) >"$E/local.idle"
"$TT" --email-sync local --vigia >/dev/null 2>&1
[[ $(chamadas) == 1 ]] || falhou 'IDLE sem batimento há 10 min deveria devolver o ritmo normal'
zera; linha inbox $((agora - 700)) $((agora - 690)) 0; printf '%s\terro\tsem rede\n' "$agora" >"$E/local.idle"
"$TT" --email-sync local --vigia >/dev/null 2>&1
[[ $(chamadas) == 1 ]] || falhou 'IDLE com erro deveria devolver o ritmo normal'
passou 'com o IDLE de pé o vigia vira rede de segurança; IDLE velho ou com erro volta ao ritmo normal'

# 4) --evento sincroniza mesmo logo depois de um sync, mas respeita a espera depois de um erro
zera; agora=$(date +%s); linha inbox $((agora - 20)) $((agora - 10)) 0; idle_ok
"$TT" --email-sync local --evento >/dev/null 2>&1
[[ $(chamadas) == 1 ]] || falhou "o evento do IDLE não sincronizou: $(chamadas)"
zera; echo $((agora + 300)) >"$E/local.espera"
"$TT" --email-sync local --evento >/dev/null 2>&1
[[ $(chamadas) == 0 ]] || falhou 'evento ignorou a espera depois de um erro'
passou '--evento sincroniza na hora e respeita a espera depois de um erro'

# 5) estado: IDLE de pé com o INBOX espaçado de propósito não é "parado"
zera; agora=$(date +%s); linha inbox $((agora - 1500)) $((agora - 1490)) 0
[[ $(curto) == parado ]] || falhou "sem IDLE, 25 min sem rodada deveria ser parado: $(curto)"
idle_ok
[[ $(curto) == ok ]] || falhou "com o IDLE de pé, o espaçamento proposital não é parado: $(curto)"
passou 'a conta com o IDLE de pé não aparece como parada'

# 6) aviso de novos: só varre quando o INBOX mudou
zera; rm -f "$E/local.vistas"; mkdir -p "$HOME/.cache/tt/maildir/local/INBOX/new" "$HOME/.cache/tt/maildir/local/INBOX/cur" "$HOME/.cache/tt/maildir/local/INBOX/tmp"
"$TT" --email-sync local >/dev/null 2>&1      # 1ª rodada: só memoriza
[[ -f $E/local.vistas ]] || falhou '1ª rodada não memorizou as vistas'
echo MARCA >>"$E/local.vistas"
"$TT" --email-sync local >/dev/null 2>&1      # nada mudou: o aviso não roda (a marca fica)
grep -qx MARCA "$E/local.vistas" || falhou 'aviso varreu o INBOX sem nenhuma mudança'
MBSYNC_NOVA=n1 "$TT" --email-sync local >/dev/null 2>&1   # chegou mensagem: roda e regrava
grep -qx MARCA "$E/local.vistas" && falhou 'aviso não rodou com mensagem nova'
grep -q '^n1' "$E/local.vistas" || falhou "mensagem nova não entrou nas vistas: $(cat "$E/local.vistas")"
passou 'o aviso de novos só varre o INBOX quando new/ ou cur/ mudou'

# 7) contagem da barra: reaproveitada enquanto as pastas não mudam; refeita quando mudam
b1=$("$TT" --barra-email); [[ $b1 == *'(1)'* ]] || falhou "barra deveria contar 1 não lida: $b1"
[[ -s $E/.naolidas ]] || falhou 'contagem da barra sem cache'
c=$(cut -f2 "$E/.naolidas"); printf '%s\t%s\n' "$(cut -f1 "$E/.naolidas")" 7 >"$E/.naolidas"
[[ $("$TT" --barra-email) == *'(7)'* ]] || falhou 'barra não usou a contagem em cache com as pastas iguais'
sleep 0.05; MBSYNC_NOVA=n2 "$TT" --email-sync local >/dev/null 2>&1
[[ $("$TT" --barra-email) == *'(2)'* ]] || falhou "barra não recontou depois de chegar mensagem: $("$TT" --barra-email)"
[[ $c == 1 ]] || falhou "cache gravou contagem errada: $c"
passou 'a contagem da barra só é refeita quando new/ ou cur/ muda'

# 8) email-tt.py idle contra um servidor IMAP falso: batimento ok, evento chama o tt, parada grava erro
PORTA_ARQ="$T/porta"
python3 -I - "$PORTA_ARQ" >"$T/imap.log" 2>&1 <<'PY' &
import socket, sys, threading, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", 0)); s.listen(5)
open(sys.argv[1], "w").write(str(s.getsockname()[1]))
def atender(c):
    f = c.makefile("rb"); c.sendall(b"* OK [CAPABILITY IMAP4rev1 IDLE] falso\r\n")
    while True:
        l = f.readline()
        if not l: return
        partes = l.decode().split()
        if l.strip() == b"DONE":
            c.sendall(etiqueta + b" OK IDLE terminado\r\n"); continue
        tag, cmd = partes[0], partes[1].upper()
        if cmd == "CAPABILITY": c.sendall(b"* CAPABILITY IMAP4rev1 IDLE\r\n" + tag.encode() + b" OK feito\r\n")
        elif cmd == "LOGIN": c.sendall(tag.encode() + b" OK [CAPABILITY IMAP4rev1 IDLE] logado\r\n")
        elif cmd in ("SELECT", "EXAMINE"): c.sendall(b"* 4 EXISTS\r\n* 0 RECENT\r\n" + tag.encode() + b" OK [READ-ONLY] ok\r\n")
        elif cmd == "IDLE":
            etiqueta = tag.encode(); c.sendall(b"+ idling\r\n")
            def chega():
                time.sleep(1.5); c.sendall(b"* 5 EXISTS\r\n")
            threading.Thread(target=chega, daemon=True).start()
        elif cmd == "LOGOUT": c.sendall(b"* BYE\r\n" + tag.encode() + b" OK feito\r\n"); return
        else: c.sendall(tag.encode() + b" OK feito\r\n")
while True:
    c, _ = s.accept(); threading.Thread(target=atender, args=(c,), daemon=True).start()
PY
srv=$!
for _ in $(seq 50); do [[ -s $PORTA_ARQ ]] && break; sleep 0.1; done
[[ -s $PORTA_ARQ ]] || falhou "servidor IMAP falso não subiu: $(cat "$T/imap.log")"
CD="$T/contas"; ES="$T/estado"; mkdir -p "$CD" "$ES" "$HOME/.secrets"
printf 'nome=Falsa\nendereco=f@x.y\nusuario=f@x.y\nprovedor=outro\nauth=senha\nimap_host=127.0.0.1\nimap_porta=%s\nimap_seg=nenhuma\nsync_local=1\n' "$(cat "$PORTA_ARQ")" >"$CD/falsa.conf"
printf 'graph=1\nprovedor=microsoft\nsync_local=1\nimap_host=x\n' >"$CD/graph.conf"
echo segredo >"$HOME/.secrets/aerc-falsa.txt"; chmod 600 "$HOME/.secrets/aerc-falsa.txt"
printf '#!/bin/sh\necho "$@" >>"%s"\n' "$T/tt.calls" >"$T/bin/tt-falso"; chmod +x "$T/bin/tt-falso"
python3 -I "${TT%/*}/email-tt.py" idle "$T/bin/tt-falso" "$CD" "$ES" >"$T/idle.log" 2>&1 &
idle=$!; echo "$idle" >"$ES/.idle.pid"
for _ in $(seq 100); do grep -q 'falsa --evento' "$T/tt.calls" 2>/dev/null && break; sleep 0.1; done
grep -qx -- '--email-sync falsa --evento' "$T/tt.calls" 2>/dev/null || { kill $idle $srv 2>/dev/null; falhou "IDLE não chamou o tt no evento: $(cat "$T/idle.log")"; }
[[ $(cut -f2 "$ES/falsa.idle") == ok ]] || { kill $idle $srv 2>/dev/null; falhou "batimento não está ok: $(cat "$ES/falsa.idle")"; }
[[ -s $ES/.idle.vivo && ! -e $ES/graph.idle ]] || { kill $idle $srv 2>/dev/null; falhou 'conta do Graph não pode entrar no IDLE (ou faltou o batimento geral)'; }
grep -q segredo "$T/idle.log" && { kill $idle $srv 2>/dev/null; falhou 'o log do IDLE mostrou o segredo'; }
kill "$idle"; for _ in $(seq 50); do kill -0 "$idle" 2>/dev/null || break; sleep 0.1; done
kill "$srv" 2>/dev/null
[[ $(cut -f2 "$ES/falsa.idle") == erro ]] || falhou "parado, o IDLE deveria deixar o batimento em erro: $(cat "$ES/falsa.idle")"
passou 'email-tt.py idle: batimento ok, chama --evento quando chega mensagem, e marca erro ao parar'

# 9) Graph: sync incremental (corpo só das novas) e eventos pelos contadores do INBOX (graph_get falso)
python3 -I - "${TT%/*}/email-tt.py" "$T/graph" >"$T/graph.log" 2>&1 <<'PY' || falhou "Graph: $(cat "$T/graph.log")"
import importlib.util, os, sys, threading, time
sp = importlib.util.spec_from_file_location("e", sys.argv[1]); e = importlib.util.module_from_spec(sp); sp.loader.exec_module(e)
base = sys.argv[2]; os.makedirs(base, exist_ok=True)
caixa = {"m1": False, "m2": True}; chamadas = []
def falso(c, caminho):
    chamadas.append(caminho)
    if caminho.startswith("/me/mailFolders/inbox/messages?"):
        return {"value": [{"id": i, "isRead": l, "lastModifiedDateTime": "t"} for i, l in caixa.items()]}
    if caminho.startswith("/me/messages/"):
        i = caminho.split("/")[3].split("?")[0]
        return {"id": i, "subject": "assunto " + i, "from": {"emailAddress": {"name": "A", "address": "a@b.c"}},
                "isRead": caixa[i], "body": {"contentType": "text", "content": "corpo " + i}, "internetMessageId": f"<{i}@x>"}
    if caminho.startswith("/me/mailFolders/inbox?"):
        return {"totalItemCount": len(caixa), "unreadItemCount": sum(not l for l in caixa.values())}
    raise AssertionError(caminho)
e.graph_get = falso; e.graph_devolver_lidos = lambda c, m: {}
corpos = lambda: [x for x in chamadas if x.startswith("/me/messages/")]
arqs = lambda: sorted(os.listdir(os.path.join(base, "INBOX", "new")) + os.listdir(os.path.join(base, "INBOX", "cur")))
e.graph_sync({"_slug": "g"}, base, 500)
assert len(corpos()) == 2, chamadas
assert arqs() == ["m1", "m2:2,S"], arqs()
chamadas.clear(); e.graph_sync({"_slug": "g"}, base, 500)
assert corpos() == [] and len(chamadas) == 1, chamadas            # nada novo: uma listagem leve, nenhum corpo
caixa["m1"] = True; chamadas.clear(); e.graph_sync({"_slug": "g"}, base, 500)
assert corpos() == [] and arqs() == ["m1:2,S", "m2:2,S"], (chamadas, arqs())   # lida em outro aparelho: só renomeia
caixa["m3"] = False; del caixa["m2"]; chamadas.clear(); e.graph_sync({"_slug": "g"}, base, 500)
assert corpos() == ["/me/messages/m3?$select=" + e.GRAPH_CAMPOS] and arqs() == ["m1:2,S", "m3"], (chamadas, arqs())
print("ok: graph_sync incremental")
# ids iguais a menos de maiúsculas (comum no Graph): dois arquivos, cada um com o seu conteúdo, em qualquer disco
base2 = base + "-caixa"; caixa.clear(); caixa.update({"XAb": False, "XaB": False})
def conteudo():
    out = {}
    for sub in ("new", "cur"):
        d = os.path.join(base2, "INBOX", sub)
        for a in os.listdir(d):
            out[a] = [l for l in open(os.path.join(d, a)) if l.startswith("Subject:")][0].strip()
    return out
chamadas.clear(); e.graph_sync({"_slug": "g"}, base2, 500)
assert sorted(conteudo().values()) == ["Subject: assunto XAb", "Subject: assunto XaB"], conteudo()
chamadas.clear(); e.graph_sync({"_slug": "g"}, base2, 500)
assert corpos() == [], chamadas                                   # estável: nada a refazer na 2ª volta
del caixa["XAb"]; chamadas.clear(); e.graph_sync({"_slug": "g"}, base2, 500)
assert list(conteudo().values()) == ["Subject: assunto XaB"], conteudo()   # a que ficou não some com a outra
print("ok: ids que só diferem em maiúsculas")
# eventos: contadores mudam → um disparo; parados → nenhum
d = os.path.join(base, "estado"); os.makedirs(d, exist_ok=True)
conf = os.path.join(base, "g.conf"); open(conf, "w").write("provedor=microsoft\ngraph=1\nauth=oauth\n")
e.ler_arquivo = lambda p: "token"
e.GRAPH_EVENTOS_CADA = 0.2; e.IDLE_ENTRE = 0
t = e._GraphConta(os.path.join(base, "tt"), conf, d)
disparos = []; t._talvez_disparar_orig = t._talvez_disparar
def disparar():
    if t.pendente:
        disparos.append(time.time()); t.pendente = 0.0
t._talvez_disparar = disparar
t.start(); time.sleep(0.7)
assert disparos == [], disparos
caixa["m4"] = False; time.sleep(0.7)
assert len(disparos) == 1, disparos
assert open(os.path.join(d, "g.idle")).read().split("\t")[1].strip() == "ok"
t.parar.set(); t.join(2)
print("ok: eventos do Graph pelos contadores")
PY
grep -q 'ok: eventos do Graph' "$T/graph.log" || falhou "Graph: $(cat "$T/graph.log")"
passou 'Graph: corpo só das novas, lida em outro aparelho só renomeia, ids que só diferem em maiúsculas não se sobrescrevem, e os contadores disparam o evento'
