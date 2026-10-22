#!/usr/bin/env bash
# Regressão (projeto tt, dell 18/10/2026): a conexão mestra do ssh (ControlMaster) para a empresa ficou meio morta:
# respondia ao keepalive, mas cada sessão nova saía 1 na hora, sem mensagem. O diagnóstico dava "falha não
# classificada", a mestra nunca caía (cada sondagem renovava os 12 h do ControlPersist), e o "aceita a conexão e não
# manda o banner" do sshd travado de lá também não tinha nome. Com um sshd de verdade numa porta alta: a mestra com a
# sessão quebrada por um ForceCommand, que só recusa a conexão dela; e um socket que escuta e nunca atende.
source "$(dirname "$0")/lib.sh"; isolar
sshd_bin=""; for b in /usr/sbin/sshd /usr/local/sbin/sshd /opt/homebrew/sbin/sshd; do [[ -x $b ]] && sshd_bin=$b; done
porta_livre() { python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'; }
mkdir -p "$T/bin" "$T/s"; chmod 700 "$T/s"
printf '#!/bin/sh\n[ "$1" = status ] && echo "{}"\nexit 0\n' >"$T/bin/tailscale"; chmod +x "$T/bin/tailscale"
export PATH="$T/bin:$PATH"
eval "$(sed -n '/^tailscale_alcanca() {/,/^}/p; /^diagnosticar_conexao() {/,/^}/p; /^explicar_diagnostico() {/,/^}/p; /^mtu_quebrada() {/,/^}/p' "$TT")"

# Sem mestra, e o ssh morto pelo timeout (124) sem dizer nada: é tempo esgotado, não "falha não classificada".
r=$(timeout() { shift; "$@"; }; ssh() { [[ " $* " == *" -O "* ]] && return 255; return 124; }; SSH_OPC=(); diagnosticar_conexao u@alvo)
[[ $r == timeout ]] || falhou "ssh morto pelo timeout, sem mensagem, deveria dar timeout, deu '$r'"
passou 'ssh morto pelo timeout sem mensagem: timeout'

[[ -n $sshd_bin ]] || { passou 'sem sshd neste sistema: as provas com um sshd de verdade ficam de fora'; exit 0; }
P=$(porta_livre); ssh-keygen -q -t ed25519 -N '' -f "$T/s/host"; ssh-keygen -q -t ed25519 -N '' -f "$T/s/cli"
cp "$T/s/cli.pub" "$T/s/ak"
# A conexão anotada em "quebrada" (a porta de origem da mestra) recebe toda sessão nova com saída 1 e sem mensagem.
cat >"$T/s/cmd" <<FIM
#!/bin/sh
c=\${SSH_CONNECTION#* }; c=\${c%% *}
[ -s "$T/s/quebrada" ] && [ "\$(cat "$T/s/quebrada")" = "\$c" ] && exit 1
exec /bin/sh -c "\$SSH_ORIGINAL_COMMAND"
FIM
chmod +x "$T/s/cmd"
cat >"$T/s/sshd_config" <<FIM
Port $P
ListenAddress 127.0.0.1
HostKey $T/s/host
PidFile $T/s/sshd.pid
AuthorizedKeysFile $T/s/ak
StrictModes no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
ForceCommand $T/s/cmd
FIM
"$sshd_bin" -f "$T/s/sshd_config" -E "$T/s/sshd.log" || falhou "o sshd de teste não subiu: $(cat "$T/s/sshd.log")"
printf 'Host *\n  IdentityFile %s\n  IdentitiesOnly yes\n  UserKnownHostsFile %s\n' "$T/s/cli" "$T/s/kh" >"$T/s/ssh_config"
SSH_OPC=(-F "$T/s/ssh_config" -o Port="$P" -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new
  -o ControlMaster=auto -o "ControlPath=$T/s/m" -o ControlPersist=60 -o ServerAliveInterval=15 -o ServerAliveCountMax=3)
D=$(id -un)@127.0.0.1
for i in 1 2 3 4 5 6 7 8 9 10; do timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$P" 2>/dev/null && break; sleep 0.2; done

# Uma sessão longa abre a mestra; depois, a conexão dela passa a recusar sessões novas.
ssh "${SSH_OPC[@]}" "$D" 'sleep 30' </dev/null >/dev/null 2>&1 & longa=$!
for i in $(seq 25); do ssh "${SSH_OPC[@]}" -O check "$D" >/dev/null 2>&1 && break; sleep 0.2; done
ssh "${SSH_OPC[@]}" -O check "$D" >/dev/null 2>&1 || falhou "a mestra de teste não abriu: $(tail -3 "$T/s/sshd.log")"
c=$(ssh "${SSH_OPC[@]}" "$D" 'echo $SSH_CONNECTION' </dev/null) || falhou 'a sessão pela mestra ainda boa falhou'
c=${c#* }; printf '%s\n' "${c%% *}" >"$T/s/quebrada"
if e=$(ssh "${SSH_OPC[@]}" "$D" true 2>&1 </dev/null) || [[ -n $e ]]; then falhou "a mestra quebrada deveria sair com erro e sem mensagem (como a da empresa): '$e'"; fi
r=$(diagnosticar_conexao "$D")
[[ $r == ok ]] || falhou "a máquina atende conexão nova; o diagnóstico deveria dar ok, deu '$r'"
! ssh "${SSH_OPC[@]}" -O check "$D" >/dev/null 2>&1 || falhou 'a mestra quebrada deveria ter parado de aceitar sessões (-O stop)'
kill -0 "$longa" 2>/dev/null || falhou 'a sessão que estava aberta na mestra quebrada não deveria cair'
ssh "${SSH_OPC[@]}" "$D" true </dev/null 2>/dev/null || falhou 'depois do diagnóstico, o ssh comum deveria voltar a funcionar (mestra nova)'
passou 'mestra meio morta (sessão nova sai 1, sem mensagem): o diagnóstico dá ok pela conexão nova, a mestra para e a sessão aberta segue'

# Mestra quebrada e a máquina sem atender ninguém: vale o erro da conexão nova; a mestra fica (não foi provado
# que ela é a quebrada).
c=$(ssh "${SSH_OPC[@]}" "$D" 'echo $SSH_CONNECTION' </dev/null); c=${c#* }; printf '%s\n' "${c%% *}" >"$T/s/quebrada"
kill "$(cat "$T/s/sshd.pid")"; sleep 0.3
r=$(diagnosticar_conexao "$D")
[[ $r == porta-fechada ]] || falhou "mestra quebrada e sshd parado: deveria dar porta-fechada (o erro da conexão nova), deu '$r'"
passou 'mestra quebrada e sshd parado: vale o erro da conexão nova (porta-fechada)'

# Aceita a conexão e nunca manda o "SSH-2.0-…" (o sshd da empresa travado): ssh-travado, sem mestra no caminho.
PM=$(porta_livre)
python3 -I -c 'import socket, sys, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(8)
time.sleep(60)' "$PM" "$T/mudo" &
for i in 1 2 3 4 5 6 7 8 9 10; do timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$PM" 2>/dev/null && break; sleep 0.2; done
SSH_OPC=(-F "$T/s/ssh_config" -o Port="$PM" -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=accept-new
  -o ControlMaster=auto -o "ControlPath=$T/s/mudo" -o ControlPersist=60)
r=$(diagnosticar_conexao "$D")
[[ $r == ssh-travado ]] || falhou "porta que aceita e não manda o banner deveria dar ssh-travado, deu '$r'"
[[ $(explicar_diagnostico ssh-travado) == *travado* ]] || falhou 'ssh-travado sem explicação própria'
passou 'porta que aceita e não manda o banner: ssh-travado, com explicação'
