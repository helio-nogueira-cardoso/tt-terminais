#!/usr/bin/env bash
# Regressão (projeto tt): par alcançável SÓ por relay (DERP). O `tailscale ping` sai com erro quando não há
# conexão direta ("direct connection not established"), mesmo com pong; o diagnóstico tomava isso por "sem rota" e
# a malha acusava uma ilha que não existia. Usa um tailscale falso; sem rede.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"
cat >"$T/bin/tailscale" <<'TS'
#!/usr/bin/env bash
case $1 in
  status) printf '{"Peer":{"a":{"HostName":"alvo","DNSName":"alvo.tail.ts.net.","TailscaleIPs":["100.1.1.1"],"Online":true}}}\n' ;;
  ping)
    case ${TS_MODO:-derp} in
      derp) echo "pong from alvo (100.1.1.1) via DERP(sao) in 30ms"; echo "direct connection not established"; exit 1 ;;
      direto) echo "pong from alvo (100.1.1.1) via 1.2.3.4:41641 in 5ms"; exit 0 ;;
      mudo) echo "no reply"; exit 1 ;;
    esac ;;
esac
TS
chmod +x "$T/bin/tailscale"
export PATH="$T/bin:$PATH"
eval "$(sed -n '/^tailscale_alcanca() {/,/^}/p; /^diagnosticar_conexao() {/,/^}/p; /^mtu_quebrada() {/,/^}/p' "$TT")"
# ping falso: PING_MODO=mtu, só o pequeno (-s 1000) volta; senão nenhum (o diagnóstico não acusa MTU sem o pequeno)
ping() { [[ ${PING_MODO:-} == mtu && " $* " == *" -s 1000 "* ]]; }
uname() { echo Linux; }
SSH_OPC=()
ssh() { return 0; }   # a autenticação não é o assunto aqui
sleep() { :; }
timeout() { shift; "$@"; }
r=$(TS_MODO=derp diagnosticar_conexao u@alvo);   [[ $r == ok ]] || falhou "par só por DERP deveria dar ok, deu '$r'"
r=$(TS_MODO=direto diagnosticar_conexao u@alvo); [[ $r == ok ]] || falhou "par direto deveria dar ok, deu '$r'"
passou 'par alcançável só por relay (DERP) ou direto: ok (não é ilha)'
r=$(TS_MODO=mudo diagnosticar_conexao u@alvo);   [[ $r == sem-rota ]] || falhou "sem nenhum pong deveria dar sem-rota, deu '$r'"
passou 'nenhum pong: sem-rota'
r=$(TS_MODO=mudo diagnosticar_conexao u@100.1.1.1); [[ $r == sem-rota ]] || falhou "IP Tailscale sem pong deveria dar sem-rota, deu '$r'"
passou 'endereço IP também identifica o par Tailscale'
ssh() { echo "${SSH_ERRO:-}" >&2; return 255; }
r=$(SSH_ERRO='Not allowed at this time' diagnosticar_conexao u@desconhecido); [[ $r == ssh-limitado ]] || falhou "recusa temporária: '$r'"
r=$(SSH_ERRO='Could not resolve hostname host' diagnosticar_conexao u@desconhecido); [[ $r == dns ]] || falhou "falha DNS: '$r'"
r=$(SSH_ERRO='Connection reset by peer port 22' diagnosticar_conexao u@desconhecido); [[ $r == conexao-interrompida ]] || falhou "reset não é porta fechada: '$r'"
passou 'recusa temporária SSH e erro DNS têm diagnósticos distintos'
r=$(SSH_ERRO='ssh: connect to host h port 22: No route to host' diagnosticar_conexao u@desconhecido); [[ $r == sem-rota ]] || falhou "sem rota: '$r'"
passou 'No route to host é sem-rota (não "falha não classificada")'
# Rota com MTU menor que o túnel (WSL com eth0 em 1280): o ping pequeno passa, o de 1280 some; o ssh para no KEX e
# o sshd de lá reseta (castigo) ou o timeout mata o ssh calado.
r=$(PING_MODO=mtu SSH_ERRO='kex_exchange_identification: read: Connection reset by peer' diagnosticar_conexao u@desconhecido)
[[ $r == mtu ]] || falhou "reset com o ping grande sumindo deveria dar mtu, deu '$r'"
r=$(PING_MODO=mtu SSH_ERRO='Connection timed out' diagnosticar_conexao u@desconhecido); [[ $r == mtu ]] || falhou "timeout + MTU: '$r'"
r=$(PING_MODO=nenhum SSH_ERRO='Connection timed out' diagnosticar_conexao u@desconhecido); [[ $r == timeout ]] || falhou "timeout sem ping nenhum: '$r'"
uname() { echo Darwin; }
r=$(PING_MODO=mtu SSH_ERRO='Connection reset by peer' diagnosticar_conexao u@desconhecido); [[ $r == conexao-interrompida ]] || falhou "fora do Linux não sonda o MTU: '$r'"
passou 'ping pequeno passa e o do tamanho do túnel não: mtu (só no Linux)'
