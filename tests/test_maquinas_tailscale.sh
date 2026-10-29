#!/usr/bin/env bash
# A marca Online do Tailscale é a visão do servidor de coordenação e oscila: em 16/10/2026 a empresa viu o Dell
# "desligado" por mais de um minuto com o túnel ssh de pé, e o clique numa fixada dele dizia "máquina não cadastrada
# ou desligada" sem nem tentar (cliques e mais cliques, até que ia). A lista de máquinas tolera a oscilação (tráfego
# recente, ou vista há pouco) e o clique numa máquina dada como desligada tenta o ssh assim mesmo.
# Tailscale, ssh e tmux falsos; nada de rede.
source "$(dirname "$0")/lib.sh"; isolar
B=$T/bin; mkdir -p "$B"
ha() { python3 -c 'import sys, time; print(time.strftime("%Y-%m-%dT%H:%M:%S.1Z", time.gmtime(time.time() - float(sys.argv[1]))))' "$1"; }
# o mesmo instante no fuso de Brasília, como o tailscale do Linux escreve ("…-03:00")
ha_br() { python3 -c 'import sys, time; print(time.strftime("%Y-%m-%dT%H:%M:%S.857788211-03:00", time.gmtime(time.time() - float(sys.argv[1]) - 10800)))' "$1"; }
cat >"$B/tailscale" <<'FIM'
#!/bin/sh
[ "$1" = status ] && cat "$TS_JSON"
FIM
cat >"$B/ssh" <<'FIM'
#!/usr/bin/env bash
# o destino é o 1º argumento que não é opção; com $T/ssh-falha, a conexão não sai (como uma máquina desligada)
args=("$@"); i=0
while ((i < ${#args[@]})); do case ${args[i]} in -o) i=$((i + 2)) ;; -*) i=$((i + 1)) ;; *) break ;; esac; done
printf '%s %s\n' "${args[i]}" "${args[*]:i+1}" >>"$T/ssh.log"
[[ -e $T/ssh-falha ]] && { echo "ssh: connect to host ${args[i]#*@} port 22: Connection timed out" >&2; exit 255; }
case "${args[*]:i+1}" in *--resolver-fixada*) printf 'sessao-x\tid-x\n' ;; esac
exit 0
FIM
cat >"$B/tmux" <<'FIM'
#!/usr/bin/env bash
[[ ${1:-} == -u ]] && shift   # o tt chama tmux -u (2.12.1)
printf '%s\n' "$*" >>"$T/tmux.log"
case ${1:-} in has-session) exit 1 ;; esac
exit 0
FIM
chmod +x "$B"/*
export T TS_JSON=$T/ts.json PATH="$B:$TT_PATH_BASE"

cat >"$XDG_CONFIG_HOME/tt/maquinas" <<'FIM'
# host usuário rótulo
ha u maq-a
hb u maq-b
hc u maq-c
hd u maq-d
he u maq-e
hf u maq-f
hg u maq-g
hh u maq-h
hi u maq-i
100.64.0.7 u maq-j
100.64.0.8 u maq-k
FIM
cat >"$TS_JSON" <<FIM
{"Peer": {
 "a": {"HostName": "ha", "DNSName": "ha.tail.ts.net.", "Online": true, "Active": true, "LastSeen": "0001-01-01T00:00:00Z"},
 "b": {"HostName": "hb", "DNSName": "hb.tail.ts.net.", "Online": false, "Active": false, "LastSeen": "$(ha 30)"},
 "c": {"HostName": "hc", "DNSName": "hc.tail.ts.net.", "Online": false, "Active": false, "LastSeen": "$(ha 86400)"},
 "d": {"HostName": "hd", "DNSName": "hd.tail.ts.net.", "Online": false, "Active": true, "LastSeen": "$(ha 86400)", "LastHandshake": "$(ha 5)"},
 "e": {"HostName": "he", "DNSName": "he.tail.ts.net.", "Online": false, "Active": false, "LastSeen": "0001-01-01T00:00:00Z"},
 "g": {"HostName": "hg", "DNSName": "hg.tail.ts.net.", "Online": false, "Active": true, "LastSeen": "$(ha 86400)", "LastHandshake": "0001-01-01T00:00:00Z"},
 "h": {"HostName": "hh", "DNSName": "hh.tail.ts.net.", "Online": false, "Active": false, "LastSeen": "$(ha_br 30)"},
 "i": {"HostName": "hi", "DNSName": "hi.tail.ts.net.", "Online": false, "Active": true, "LastSeen": "$(ha_br 900)", "LastHandshake": "$(ha_br 900)"},
 "j": {"HostName": "hj", "DNSName": "hj.tail.ts.net.", "TailscaleIPs": ["100.64.0.7"], "Online": false, "Active": true, "LastSeen": "$(ha 86400)"},
 "k": {"HostName": "hk", "DNSName": "hk.tail.ts.net.", "TailscaleIPs": ["100.64.0.8"], "Online": true, "Active": true, "LastSeen": "0001-01-01T00:00:00Z"}
}}
FIM
lista() { rm -f "$TT_RT"/tt-maquinas-*; "$TT" --maquinas | tr '\n' ' '; }
l=$(lista)
[[ $l == 'u@ha.tail.ts.net maq-a u@hb.tail.ts.net maq-b u@hd.tail.ts.net maq-d u@hf maq-f u@hh.tail.ts.net maq-h u@100.64.0.8 maq-k ' ]] ||
  falhou "lista de máquinas: '$l'"
l=$(TT_TS_TOLERANCIA=10 lista)
[[ $l == *maq-a* && $l != *maq-b* && $l == *maq-d* ]] || falhou "TT_TS_TOLERANCIA=10 deveria tirar a vista há 30 s: '$l'"
passou 'máquinas: a marca Online do Tailscale oscila; fica a que tem túnel respondendo ou foi vista há pouco, sai a desligada de verdade'
# Active só porque esta ponta (o vigia) segue mandando pacote, sem handshake (maq-g, fora há um dia) ou com o
# último há 15 min no fuso -03:00 (maq-i): desligadas. O fuso da maq-h (vista há 30 s) não a tira da lista.
l=$(lista)
[[ $l != *maq-g* && $l != *maq-i* && $l == *maq-h* ]] || falhou "Active sem túnel respondendo ou fuso -03:00: '$l'"
passou 'máquinas: Active sem handshake recente não é ligada; horário com fuso lido certo'
# cadastrada pelo IP da tailnet: desligada sai (maq-j), ligada fica com o IP (maq-k); "todas" traz as duas
l=$(rm -f "$TT_RT"/tt-maquinas-*; TT_SO_CARREGAR=1 bash -c 'source "$1"; maquinas_agora todas' _ "$TT" | tr '\n' ' ')
[[ $l == *'u@100.64.0.7 maq-j'* && $l == *'u@100.64.0.8 maq-k'* ]] || falhou "todas, com as cadastradas por IP: '$l'"
passou 'máquinas: a cadastrada pelo IP da tailnet também segue o estado do Tailscale'

# --- o clique numa fixada da maq-c (dada como desligada há um dia): tenta o ssh assim mesmo
printf 'maq-c\tsessao-x\tid-x\n' >"$XDG_CONFIG_HOME/tt/fixadas"
chave=$(TT_SO_CARREGAR=1 bash -c 'source "$1"; fixada_chave_em k maq-c sessao-x id-x; echo "$k"' _ "$TT")
[[ -n $chave ]] || falhou 'chave da fixada'
clicar() { rm -f "$T/ssh.log" "$T/tmux.log"; lista >/dev/null; TMUX=tmux-teste TMUX_PANE=%1 "$TT" --ir-fixada cliente "fx$chave"; }
touch "$T/ssh-falha"; clicar
grep -q '^u@hc.tail.ts.net .*--resolver-fixada' "$T/ssh.log" || falhou "o clique não tentou a maq-c: $(cat "$T/ssh.log" 2>/dev/null)"
grep -q 'tentando assim mesmo' "$T/tmux.log" || falhou "sem o aviso de que tenta: $(grep display "$T/tmux.log")"
grep -q 'maq-c não respondeu: o Tailscale a dá como desligada' "$T/tmux.log" || falhou "sem resposta, o aviso: $(grep display "$T/tmux.log")"
grep -q 'não cadastrada' "$T/tmux.log" && falhou 'cadastrada, não pode dizer "não cadastrada"'
grep -q 'switch-client' "$T/tmux.log" && falhou 'sem resposta, a tela não pode trocar'
rm -f "$T/ssh-falha"; clicar
grep -q 'new-session -d -s maq-c-sessao-x' "$T/tmux.log" && grep -q 'switch-client -c cliente -t =maq-c-sessao-x' "$T/tmux.log" ||
  falhou "respondendo, o clique deveria ir pela ponte: $(cat "$T/tmux.log")"
grep -q 'não respondeu' "$T/tmux.log" && falhou 'respondeu, não pode dizer que não'
# a que não está no cadastro continua recusada na hora, sem ssh
printf 'maq-z\tsessao-z\tid-z\n' >"$XDG_CONFIG_HOME/tt/fixadas"
chave=$(TT_SO_CARREGAR=1 bash -c 'source "$1"; fixada_chave_em k maq-z sessao-z id-z; echo "$k"' _ "$TT")
clicar
grep -q 'maq-z: máquina não cadastrada' "$T/tmux.log" && [[ ! -s $T/ssh.log ]] || falhou "não cadastrada: $(cat "$T/tmux.log") / $(cat "$T/ssh.log" 2>/dev/null)"
passou 'fixada de máquina dada como desligada: o clique tenta o ssh (e vai, se ela responde; senão diz que não respondeu)'
