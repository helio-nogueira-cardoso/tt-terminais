#!/usr/bin/env bash
# Clique local visto por ponte: envia controle no PTY existente, não abre SSH nem muda o alvo por dentro.
source "$(dirname "$0")/lib.sh"; isolar
export TT_PRECARREGAR=1
printf 'nome=mac\nprecarregar=auto\n' >"$XDG_CONFIG_HOME/tt/config"
mkdir -p "$T/bin"
cat >"$T/bin/ssh" <<'EOF'
#!/bin/sh
echo indevido >>"$TT_TEST_SSH_LOG"
exit 99
EOF
chmod +x "$T/bin/ssh"
export PATH="$T/bin:$PATH" TT_TEST_SSH_LOG=$T/ssh.log
cat >"$T/cliente.py" <<'PY'
import importlib.util,json,os,pty,sys
from pathlib import Path
sys.path.insert(0,sys.argv[1])
spec=importlib.util.spec_from_file_location('pre',Path(sys.argv[1])/'precarregar-tt.py')
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
token,out,pidfile=sys.argv[2:]
pid,fd=pty.fork()
if pid==0:
 env=dict(os.environ,TERM='tmux-256color',TT_PRE_TOKEN=token,TT_PONTE='empresa|tt-pre-'+token[:16])
 os.execvpe('tmux',['tmux','-u','attach-session','-E','-t','=origem'],env)
Path(pidfile).write_text(str(pid))
def record(packet):
 with open(out,'a') as f: f.write(json.dumps(packet)+'\n')
stream=p.NavigationStream(token,record)
try:
 while True:
  data=os.read(fd,65536)
  if not data: break
  stream.feed(data)
except OSError: pass
finally:
 os.close(fd)
PY
tmux -f /dev/null new-session -d -s origem 'sleep 600'
tmux new-session -d -s destino 'sleep 600'
tmux set-option -t '=destino:' @tt_session_id bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
printf 'mac\tnome-antigo\tbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n' >"$XDG_CONFIG_HOME/tt/fixadas"
python3 "$T/cliente.py" "$RAIZ" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$T/a.jsonl" "$T/a.pid" &
python3 "$T/cliente.py" "$RAIZ" cccccccccccccccccccccccccccccccc "$T/c.jsonl" "$T/c.pid" &
for i in {1..150}; do
 [[ $(tmux list-clients -F '#{client_name}' 2>/dev/null | wc -l) == 2 ]] && break
 sleep .02
done
[[ $(tmux list-clients -F '#{client_name}' | wc -l) == 2 ]] || falhou 'clientes aninhados não anexaram'
c=$(tmux list-clients -F '#{client_pid} #{client_name}' | awk -v p="$(cat "$T/a.pid")" '$1==p {print $2}')
export TMUX=$(tmux display-message -p '#{socket_path},#{pid},0')
TT_SO_CARREGAR=1 source "$TT"; EU=$TT
fixada_chave_em k mac nome-antigo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
"$TT" --clique "fx$k" "$c" %0 '' 0 d
"$TT" --clique "fx$k" "$c" %0 '' 0 u
for i in {1..150}; do [[ -s $T/a.jsonl ]] && break; sleep .02; done
[[ -s $T/a.jsonl ]] || falhou 'clique local não usou o transporte existente'
python3 - "$T/a.jsonl" <<'PY'
import json,sys
rows=[json.loads(x) for x in open(sys.argv[1])]
assert len(rows)==1 and rows[0]['dest']=='mac' and rows[0]['id']=='b'*32,rows
PY
[[ ! -s $T/c.jsonl ]] || falhou 'encaminhou à outra tela'
[[ ! -e $T/ssh.log ]] || falhou 'abriu SSH para trocar sessão local'
[[ $(tmux list-clients -F '#{session_name}' | sort -u) == origem ]] || falhou 'retargetou ponte por dentro'
passou 'clique local dentro da ponte envia ID uma vez no PTY certo, sem SSH, sem trocar outra tela'
