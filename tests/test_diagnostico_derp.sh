#!/usr/bin/env bash
# Regressão (projeto tt): par alcançável SÓ por relay (DERP). O `tailscale ping` sai com erro quando não há
# conexão direta ("direct connection not established"), mesmo com pong; o diagnóstico tomava isso por "sem rota" e
# a malha acusava uma ilha que não existia. Usa um tailscale falso; sem rede.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"
cat >"$T/bin/tailscale" <<'TS'
#!/usr/bin/env bash
case $1 in
  status) printf '{"Peer":{"a":{"HostName":"alvo","DNSName":"alvo.tail.ts.net.","Online":true}}}\n' ;;
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
eval "$(sed -n '/^tailscale_alcanca() {/,/^}/p; /^diagnosticar_conexao() {/,/^}/p' "$TT")"
SSH_OPC=()
ssh() { return 0; }   # a autenticação não é o assunto aqui
sleep() { :; }
timeout() { shift; "$@"; }
r=$(TS_MODO=derp diagnosticar_conexao u@alvo);   [[ $r == ok ]] || falhou "par só por DERP deveria dar ok, deu '$r'"
r=$(TS_MODO=direto diagnosticar_conexao u@alvo); [[ $r == ok ]] || falhou "par direto deveria dar ok, deu '$r'"
passou 'par alcançável só por relay (DERP) ou direto: ok (não é ilha)'
r=$(TS_MODO=mudo diagnosticar_conexao u@alvo);   [[ $r == sem-rota ]] || falhou "sem nenhum pong deveria dar sem-rota, deu '$r'"
passou 'nenhum pong: sem-rota'
