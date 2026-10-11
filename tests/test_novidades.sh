#!/usr/bin/env bash
# Novidades do tt: mostra só o que saiu depois da última versão vista, --todas mostra tudo, o vigia
# avisa uma vez por versão nova (sem avisar máquina recém-instalada), e o clique no aviso do agente
# vai ao painel mesmo com a sessão renomeada.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado; TT=$HOME/.local/bin/tt
ES=$HOME/.local/state/tt
cat >"$TT_DIR/NOVIDADES.md" <<'N'
# Novidades
## v1.7.2 · 01/01/2099
- coisa nova C — atualização com ação
## v1.7.1 · 01/01/2099
- coisa nova B
## v1.7.0 · 01/01/2099
- coisa velha A
## v1.5.3 · 01/01/2099
- coisa legada Z
N
echo "312 teste 2099-01-01 1.7.2" >"$TT_DIR/VERSAO"
echo 1.7.0 >"$(mkdir -p "$ES"; echo "$ES/novidades-visto")"
saida=$("$TT" --novidades)
grep -q 'coisa nova C' <<<"$saida" && grep -q 'coisa nova B' <<<"$saida" || falhou "faltou novidade: $saida"
grep -q 'coisa velha A' <<<"$saida" && falhou 'mostrou o que já foi visto'
[[ $(cat "$ES/novidades-visto") == 1.7.2 ]] || falhou 'não marcou como visto'
passou 'mostra só o que saiu depois da última versão vista, e marca como visto'
saida=$("$TT" --novidades --todas); grep -q 'coisa velha A' <<<"$saida" || falhou '--todas deveria mostrar tudo'
passou '--todas mostra tudo'

# Vigia: versão nova → um aviso (ação novidades); repetido na mesma versão → nada.
rm -rf "$ES/notifs" "$ES/novidades-avisada"; echo 1.7.0 >"$ES/novidades-visto"
"$TT" --novidades-avisar; "$TT" --novidades-avisar
n=$(grep -l 'novidades$' "$ES"/notifs/* 2>/dev/null | wc -l); ((n == 1)) || falhou "esperava 1 aviso, vi $n"
# Máquina recém-instalada (sem registro do que foi visto): não avisa.
rm -rf "$ES/notifs" "$ES/novidades-avisada" "$ES/novidades-visto"; "$TT" --novidades-avisar
[[ -z $(ls "$ES/notifs" 2>/dev/null) ]] || falhou 'avisou numa máquina recém-instalada'
[[ $(cat "$ES/novidades-visto") == 1.7.2 ]] || falhou 'recém-instalada deveria marcar a versão atual'
passou 'vigia avisa uma vez por versão nova; instalação nova não é incomodada'

# Estado antigo (só o nº de commits) vale como 1.6.N: não reabre o que já passou, mas mostra a série nova.
echo 999 >"$ES/novidades-visto"; saida=$("$TT" --novidades)
grep -q 'coisa nova C' <<<"$saida" && ! grep -q 'coisa legada Z' <<<"$saida" || falhou "estado numérico antigo: $saida"
passou 'estado antigo (nº de commits) é lido como 1.6.N'

# Clique do agente: vale o nome ATUAL da sessão do painel.
tmux -f /dev/null new -d -s antigo -x 120 -y 30 'sleep 300'; tmux new -d -s outra 'sleep 300'
anexar cli 120 30 outra; sleep 1.2
c=$(tmux list-clients -F "#{client_name}" | head -1); p=$(tmux list-panes -t antigo -F '#{pane_id}')
tmux rename-session -t antigo novo
TMUX="$(tmux display -p "#{socket_path}"),1,0" "$TT" --notif-abrir "sessao:antigo|$p" "$c"; sleep 0.7
[[ $(tmux list-clients -F '#{client_session}' | head -1) == novo ]] || falhou "não foi à sessão renomeada: $(tmux list-clients -F '#{client_session}')"
passou 'o clique do aviso do agente acha a sessão renomeada pelo id do painel'
# Num terminal a tela SEGURA o texto (antes o less saía sozinho com pouco texto e o popup piscava).
res=$(python3 - "$TT" <<'PY'
import os, pty, sys, time, select
tt = sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"; os.environ["LINES"] = "40"; os.environ["COLUMNS"] = "100"
    # Reproduz Debian sem locale configurado (POSIX/ASCII), como no proot do S23.
    os.environ["LANG"] = "C"; os.environ["LC_ALL"] = "C"
    os.environ.pop("LC_CTYPE", None); os.environ.pop("LESSCHARSET", None)
    os.execvp(tt, [tt, "--novidades", "--todas"])
out = b""; t0 = time.time()
while time.time() - t0 < 2.5:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try: out += os.read(fd, 4096)
        except OSError: break
done, _ = os.waitpid(pid, os.WNOHANG)
vivo = done == 0
if vivo:
    os.write(fd, b"q")
    time.sleep(0.6); done, _ = os.waitpid(pid, os.WNOHANG)
utf8 = "atualização com ação".encode() in out
print("SEGUROU_UTF8" if vivo and done and utf8 else "PISCOU" if not vivo else "NAO-FECHOU-NO-Q" if not done else "UTF8-ESCAPOU")
PY
)
[[ $res == SEGUROU_UTF8 ]] || falhou "tela de novidades em locale ASCII: $res"
passou 'tela de novidades fica aberta e mostra UTF-8 mesmo sem locale UTF-8'
echo "TODOS OS TESTES PASSARAM"
