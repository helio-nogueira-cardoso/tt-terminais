#!/usr/bin/env bash
# Toda máquina da malha aceita conexão: sem sshd escutando, o tt sobe sozinho um sshd do usuário (sem root, só
# chave, chave de host própria em ~/.local/state/tt/sshd/), o vigia o religa, o tt --checar acusa quando não há,
# a malha anuncia a porta real, e fora da malha (sem outras máquinas) nada é aberto. Portas altas de teste no
# lugar da 22 e da 8022 (TT_SSHD_PORTA_SISTEMA, TT_SSHD_PORTA) e sem sudo (TT_SSHD_SEM_SUDO).
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
sshd_bin=""; for b in /usr/sbin/sshd /usr/local/sbin/sshd; do [[ -x $b ]] && sshd_bin=$b; done
porta_livre() { python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'; }
export TT_SSHD_SEM_SUDO=1 TT_SSHD_PORTA_SISTEMA=$(porta_livre) TT_SSHD_PORTA=$(porta_livre)
ES=$HOME/.local/state/tt
parar() { [[ -s $ES/sshd/sshd.pid ]] && kill "$(cat "$ES/sshd/sshd.pid")" 2>/dev/null; return 0; }
trap 'parar; limpar_isolado' EXIT

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

# sshd_garantir=0 desliga.
parar; sleep 0.5; echo sshd_garantir=0 >>"$XDG_CONFIG_HOME/tt/config"
"$TT" --sshd-garantir --vigia
timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TT_SSHD_PORTA" 2>/dev/null && falhou 'sshd_garantir=0 deveria desligar'
passou 'sshd_garantir=0 desliga'
