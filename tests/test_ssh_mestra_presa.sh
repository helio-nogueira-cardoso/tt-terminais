#!/usr/bin/env bash
# Mestra do ssh meio morta (23/10/2026): no modo mux o cliente entrega o próprio stdout à mestra. Ela aceitava o canal e
# não o abria lá; o timeout matava o cliente, mas a mestra seguia com o pipe e o $(ssh …) do clique de dentro de uma
# ponte esperava até os keepalives a derrubarem (47 s, sem trocar a tela). O ssh_pedir grava a saída num arquivo (só o
# processo é esperado) e, havendo mestra, dá a ela um prazo curto antes de repetir por conexão própria.
# ssh falso: "-O check" diz se há mestra ($T/mestra); a ida pela mestra segue $T/modo; a conexão própria responde.
source "$(dirname "$0")/lib.sh"; isolar
B=$T/bin; mkdir -p "$B"
cat >"$B/ssh" <<'FIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$T/ssh.log"
case " $* " in
  *" -O check "*) [[ -e $T/check-trava ]] && sleep 5; [[ -e $T/mestra ]]; exit ;;
  *" -O stop "*) rm -f "$T/mestra"; echo stop >>"$T/stop.log"; exit 0 ;;
esac
ini() { [[ ${!#} == 'echo tt-ini; '* ]] && echo tt-ini; } # o canal abriu lá e o shell de lá começou o comando
if [[ " $* " == *" ControlPath=none "* ]]; then ini "$@"; echo resposta-nova; exit 0; fi
case $(cat "$T/modo") in
  ok) ini "$@"; echo resposta ;;
  lento) ini "$@"; sleep 3; echo resposta ;;                               # canal aberto, a origem só demora
  neto) ini "$@"; echo resposta; sleep 20 & echo $! >>"$T/netos" ;;       # respondeu; a mestra segue com o pipe
  presa) sleep 20 & echo $! >>"$T/netos"; sleep 20 ;;                     # o canal nem abre: mestra meio morta
  recusa) exit 255 ;;                                                     # a mestra recusa o canal
esac
FIM
chmod +x "$B/ssh"
trap 'kill $(cat "$T/netos" 2>/dev/null) 2>/dev/null' EXIT
export T PATH="$B:$TT_PATH_BASE"

pedir() { # prazo [prazo_mestra] -> "rc saída" em $T/r, segundos em $dt
  rm -f "$T/ssh.log" "$T/stop.log"
  local a=$EPOCHREALTIME
  TT_SO_CARREGAR=1 "$BASH" -c 'source "$1"; ssh_pedir r "$2" u@lá "comando" ${3:+"$3"}; echo "$? $r" >"$T/r"' _ "$TT" "$@"
  dt=$(awk -v a="$a" -v b="$EPOCHREALTIME" 'BEGIN { printf "%d", (b - a) * 10 }') # décimos de segundo
}

touch "$T/mestra"; echo ok >"$T/modo"; pedir 6 2
[[ $(cat "$T/r") == "0 resposta" ]] || falhou "mestra boa: $(cat "$T/r")"
[[ ! -e $T/stop.log ]] || falhou 'mestra boa foi encerrada'
passou 'mestra boa: responde pela mestra, sem encerrá-la'

echo neto >"$T/modo"; pedir 6 2
[[ $(cat "$T/r") == "0 resposta" ]] || falhou "resposta com o pipe preso: $(cat "$T/r")"
((dt < 15)) || falhou "esperou o pipe que a mestra segura: $((dt / 10)) s"
passou 'resposta com a mestra segurando o pipe volta na hora (só o processo é esperado)'

echo presa >"$T/modo"; pedir 6 2
[[ $(cat "$T/r") == "0 resposta-nova" ]] || falhou "mestra presa: $(cat "$T/r")"
((dt < 40)) || falhou "mestra presa levou $((dt / 10)) s (prazo dela: 2 s)"
[[ -e $T/stop.log ]] || falhou 'mestra presa não foi encerrada'
grep -q 'ControlPath=none' "$T/ssh.log" || falhou 'não repetiu por conexão própria'
passou 'mestra presa: encerrada no prazo dela e a ida se repete por conexão própria'

touch "$T/mestra"; echo recusa >"$T/modo"; pedir 6 2
[[ $(cat "$T/r") == "0 resposta-nova" ]] || falhou "mestra que recusa: $(cat "$T/r")"
passou 'mestra que recusa o canal (255): repete por conexão própria'

# A origem só demora (o canal abriu): o prazo curto da mestra não corta, e nada roda duas vezes lá.
touch "$T/mestra"; echo lento >"$T/modo"; pedir 6 2
[[ $(cat "$T/r") == "0 resposta" ]] || falhou "origem lenta: $(cat "$T/r")"
((dt >= 28 && dt < 55)) || falhou "origem lenta levou $((dt / 10)) s (resposta em 3 s)"
[[ ! -e $T/stop.log ]] || falhou 'mestra boa encerrada porque a origem demorou'
grep -q 'ControlPath=none' "$T/ssh.log" && falhou 'repetiu um comando que já rodava lá'
passou 'origem lenta com o canal aberto: espera o prazo inteiro, sem repetir o comando'

# Mestra que nem responde ao controle local: a ida já sai por conexão própria.
touch "$T/mestra" "$T/check-trava"; echo presa >"$T/modo"; pedir 6 2
rm -f "$T/check-trava"
[[ $(cat "$T/r") == "0 resposta-nova" ]] || falhou "controle da mestra travado: $(cat "$T/r")"
((dt < 30)) || falhou "controle da mestra travado levou $((dt / 10)) s"
passou 'mestra travada até no controle local: vai direto por conexão própria'

# Sem mestra, a ida abre a própria conexão: tem o prazo inteiro (rede lenta não é mestra quebrada) e não repete.
rm -f "$T/mestra"; echo presa >"$T/modo"; pedir 3 1
[[ $(cat "$T/r") == "124 " ]] || falhou "sem mestra: $(cat "$T/r")"
((dt >= 28)) || falhou "sem mestra cortou o prazo: $((dt / 10)) s de 3"
((dt < 60)) || falhou "sem mestra passou do prazo: $((dt / 10)) s de 3"
grep -q 'ControlPath=none' "$T/ssh.log" && falhou 'sem mestra repetiu a ida'
passou 'sem mestra: o prazo inteiro, uma ida só, 124 no fim'
