#!/usr/bin/env bash
# Toda máquina da malha aceita conexão: sem sshd escutando, o tt sobe sozinho um sshd do usuário (sem root, só
# chave, chave de host própria em ~/.local/state/tt/sshd/), o vigia o religa, o tt --checar acusa quando não há,
# a malha anuncia a porta real, e fora da malha (sem outras máquinas) nada é aberto. Portas altas de teste no
# lugar da 22 e da 8022 (TT_SSHD_PORTA_SISTEMA, TT_SSHD_PORTA) e sem sudo (TT_SSHD_SEM_SUDO).
source "$(dirname "$0")/lib.sh"; isolar
# Mesma descoberta e mesma ordem do sshd_bin() do tt: a fixture nao pode faltar quando o tt encontraria (e subiria) um sshd.
sshd_bin=""; for b in /usr/sbin/sshd /usr/local/sbin/sshd /opt/homebrew/sbin/sshd "${PREFIX:-/nonexistent}/bin/sshd" "$(command -v sshd 2>/dev/null)"; do
  [[ -n $b && -x $b ]] && { sshd_bin=$b; break; }
done
porta_livre() { python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'; }
porta_liberada() { python3 -I -c 'import socket,sys; s=socket.socket(); s.bind(("127.0.0.1", int(sys.argv[1]))); s.close()' "$1"; }
ES=$HOME/.local/state/tt
fixture_pid=
fixture_started=0
parar() { [[ -s $ES/sshd/sshd.pid ]] && kill "$(cat "$ES/sshd/sshd.pid")" 2>/dev/null; return 0; }
limpar_fixture() {
  local i
  [[ $fixture_started == 1 ]] || return 0
  if [[ -n $fixture_pid ]]; then kill "$fixture_pid" 2>/dev/null; wait "$fixture_pid" 2>/dev/null; fixture_pid=; fi
  for i in 1 2 3 4 5 6 7 8 9 10; do porta_liberada "$TT_SSHD_PORTA_SISTEMA" && return 0; sleep 0.1; done
  return 1
}
limpar_teste() { local st=$?; set +e; limpar_fixture || { echo 'FALHOU — a porta do fixture SSH continuou ocupada após a limpeza' >&2; st=1; }; parar; (exit "$st"); limpar_isolado; }
trap limpar_teste EXIT
# Sobe o sshd fixture (autenticavel, chave efemera) numa porta sorteada. Sortear e soltar deixa uma janela em que outro processo toma a porta:
# se o fixture nao ficar pronto, mata e repete com outra porta (ate 5 vezes). Sai 0 com TT_SSHD_PORTA_SISTEMA apontando para ele.
subir_fixture() {
  local tentativa porta pronto _
  fixture_dir=$HOME/.local/state/tt-fixture
  mkdir -p "$fixture_dir" "$ES/sshd" "$HOME/.ssh"; chmod 700 "$fixture_dir" "$ES/sshd" "$HOME/.ssh"
  ssh-keygen -q -t ed25519 -N '' -f "$fixture_dir/host_key"
  ssh-keygen -q -t ed25519 -N '' -f "$fixture_dir/client_key"
  cp "$fixture_dir/client_key.pub" "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
  for tentativa in 1 2 3 4 5; do
    porta=${TT_TEST_PORTA_FORCADA:-$(porta_livre)}; TT_TEST_PORTA_FORCADA=  # gancho de teste: 1a tentativa numa porta ja ocupada, para exercitar a repeticao
    cat >"$fixture_dir/sshd_config" <<FIM
Port $porta
ListenAddress 127.0.0.1
HostKey $fixture_dir/host_key
PidFile $fixture_dir/sshd.pid
AuthorizedKeysFile $HOME/.ssh/authorized_keys
StrictModes no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
PermitRootLogin no
Subsystem sftp internal-sftp
FIM
    export TT_SSHD_PORTA_SISTEMA=$porta
    "$sshd_bin" -D -e -f "$fixture_dir/sshd_config" -E "$fixture_dir/sshd.log" & fixture_pid=$!; fixture_started=1
    pronto=0
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      if ssh -i "$fixture_dir/client_key" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=1 -p "$porta" "$(id -un)@127.0.0.1" true >/dev/null 2>&1; then pronto=1; break; fi
      sleep 0.1
    done
    [[ $pronto == 1 ]] && return 0
    kill "$fixture_pid" 2>/dev/null; wait "$fixture_pid" 2>/dev/null; fixture_pid=; fixture_started=0
  done
  return 1
}
export TT_SSHD_SEM_SUDO=1
if [[ -n $sshd_bin ]]; then
  # Instalação também garante SSH fora da malha. Um serviço autenticável na porta de sistema isolada
  # mantém essa etapa fora do socket 22 real; depois ele sai e o teste exercita o sshd do usuário.
  subir_fixture || falhou 'o sshd fixture não ficou pronto para login por chave (5 portas tentadas)'
else
  export TT_SSHD_PORTA_SISTEMA=$(porta_livre)
fi
porta_tt=$(porta_livre)
while [[ $porta_tt == "$TT_SSHD_PORTA_SISTEMA" ]]; do porta_tt=$(porta_livre); done
export TT_SSHD_PORTA=$porta_tt
[[ ${TT_TEST_FALHAR_INSTALACAO:-0} != 1 ]] || falhou 'falha de instalação injetada para verificar limpeza do fixture'
instalar_isolado
if [[ -n $fixture_pid ]]; then limpar_fixture || falhou 'fixture SSH não liberou a porta após instalação'; fi

# Fora da malha: nada é aberto.
"$TT" --sshd-garantir --vigia
[[ -e $ES/sshd/sshd.pid ]] && falhou 'sem outras máquinas cadastradas, o vigia não deveria abrir porta'
grep -q '^sshd' <<<"$("$TT" --checar --tsv)" && falhou 'fora da malha, o tt --checar não deveria cobrar sshd'
passou 'fora da malha: nenhum sshd aberto, nada cobrado'

printf '100.64.0.9 alguem outra\n' >"$XDG_CONFIG_HOME/tt/maquinas"
if [[ -z $sshd_bin ]]; then
  grep -q $'^sshd\tfalha\t.*openssh-server' <<<"$("$TT" --checar --tsv)" || falhou 'sem o programa sshd, o tt --checar deveria apontar a pendência'
  "$TT" --pendencias --tsv | grep -q $'^sshd\t' || falhou 'pendência sshd ausente do catálogo'
  passou 'sem openssh-server: falha no checar e pendência sshd (este sistema não tem sshd; o resto do teste fica de fora)'
  exit 0
fi

# Na malha, sem nada escutando: o tt sobe o sshd do usuário na porta dele.
grep -q $'^sshd\tfalha\t' <<<"$("$TT" --checar --tsv)" || falhou 'sem sshd escutando, o tt --checar deveria acusar'
p=$("$TT" --sshd-garantir) || falhou "não subiu o sshd do usuário: $(cat "$ES"/sshd/*.log 2>/dev/null)"
[[ $p == "$TT_SSHD_PORTA" ]] || falhou "porta errada: $p"
timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TT_SSHD_PORTA" || falhou 'o sshd do usuário não está escutando'
grep -q '^PasswordAuthentication no$' "$ES/sshd/sshd_config" && grep -q '^UsePAM no$' "$ES/sshd/sshd_config" || falhou 'sshd do usuário deveria aceitar só chave'
[[ $(stat -c %a "$ES/sshd") == 700 && -s $ES/sshd/ssh_host_ed25519_key ]] || falhou 'pasta do sshd com permissão aberta ou sem chave de host'
grep -q $'^sshd\tok\t.*'"$TT_SSHD_PORTA" <<<"$("$TT" --checar --tsv)" || falhou 'com o sshd do usuário no ar, o checar deveria ficar ok'
grep -q "^EU	.*	$TT_SSHD_PORTA\$" <<<"$("$TT" --malha-lista)" || falhou "a malha deveria anunciar a porta real: $("$TT" --malha-lista | head -1)"
passou 'na malha: sobe o sshd do usuário (só chave, sem root), o checar fica ok e a malha anuncia a porta'

# Já de pé: garantir de novo não sobe outro; caiu: o vigia religa.
pid=$(cat "$ES/sshd/sshd.pid"); "$TT" --sshd-garantir >/dev/null
[[ $(cat "$ES/sshd/sshd.pid") == "$pid" ]] || falhou 'garantir com o sshd de pé não deveria subir outro'
parar; sleep 0.5
"$TT" --sshd-garantir --vigia
timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TT_SSHD_PORTA" || falhou 'o vigia deveria religar o sshd que caiu'
grep -q "sshd do usuário na porta $TT_SSHD_PORTA" "$ES/sshd/garantir.log" || falhou 'o religamento deveria ficar no log'
passou 'idempotente; o vigia religa o sshd que caiu e registra'

# Atualização (instalar-aqui) força o sshd da malha, mesmo com o pacote já instalado: sem esperar o vigia.
parar; sleep 0.5
"$TT" --instalar-aqui >/dev/null 2>&1 || falhou 'instalar-aqui com a malha deveria rodar'
timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TT_SSHD_PORTA" || falhou 'a instalação na malha deveria subir o sshd do usuário'
passou 'instalar-aqui na malha sobe o sshd sem esperar o vigia'

# Atualização sobe o sshd também fora da malha (sem outras máquinas cadastradas); o vigia não.
parar; sleep 0.5; rm -f "$XDG_CONFIG_HOME/tt/maquinas"; sed -i '/^sshd_garantir=0$/d' "$XDG_CONFIG_HOME/tt/config"
"$TT" --instalar-aqui >/dev/null 2>&1 || falhou 'instalar-aqui fora da malha deveria rodar'
timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TT_SSHD_PORTA" || falhou 'a atualização deveria subir o sshd mesmo fora da malha'
passou 'instalar-aqui fora da malha também sobe o sshd'

# sshd_garantir=0 desliga.
parar; sleep 0.5; echo sshd_garantir=0 >>"$XDG_CONFIG_HOME/tt/config"
"$TT" --sshd-garantir --vigia
timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TT_SSHD_PORTA" 2>/dev/null && falhou 'sshd_garantir=0 deveria desligar'
passou 'sshd_garantir=0 desliga'

# Saúde de verdade: a porta tem de responder com o banner SSH. Um socket que só aceita conexão não conta.
sed -i '/^sshd_garantir=0$/d' "$XDG_CONFIG_HOME/tt/config"
parar; sleep 0.5
python3 -I -c "
import socket, sys, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', $TT_SSHD_PORTA)); s.listen(5)
while True:
    c, _ = s.accept(); time.sleep(0.2); c.close()
" &
impostor=$!; sleep 0.5
"$TT" --sshd-garantir >/dev/null 2>&1 && falhou 'uma porta que não fala SSH não pode contar como sshd no ar'
kill "$impostor" 2>/dev/null; wait "$impostor" 2>/dev/null || true; sleep 0.3
passou 'porta sem banner SSH não conta como sshd funcionando'

# Instalação deixa a prova no log.
"$TT" --instalar-aqui >/dev/null 2>&1 || falhou 'instalar-aqui deveria rodar'
grep -q "instalação/atualização: sshd respondendo na porta $TT_SSHD_PORTA" "$ES/sshd/garantir.log" || falhou "o log deveria registrar a instalação: $(tail -2 "$ES/sshd/garantir.log")"
passou 'instalação registra no log que o sshd responde'

# O login de checagem usa uma chave temporária: depois do teste ela não pode ficar em authorized_keys.
"$TT" --sshd-garantir >/dev/null 2>&1
! grep -q 'tt-checagem-' "$HOME/.ssh/authorized_keys" 2>/dev/null || falhou 'a chave de checagem ficou em authorized_keys'
passou 'a chave de checagem sai de authorized_keys depois do teste'
