#!/usr/bin/env bash
# Regressão (projeto tt): a ponte pré-carregada de outra máquina ficou presa em "Não consegui confirmar a
# identidade do destino. Enter para tentar novamente." com a sessão existindo lá. Destino mudo (rede/SSH)
# agora tenta sozinho (2, 4 e 8 s) antes de pedir a escolha: Enter tenta de novo, n abre uma sessão nova
# na máquina de lá, q volta. A escolha ignora eventos de foco (ESC[I/ESC[O) e o que chegou antes.
# Usa as funções REAIS do tt (extraídas), com resolver, ssh, sleep, read e tmux simulados; sem rede.
set -u
source "$(dirname "$0")/tmux-isolado.sh"   # antes dos stubs abaixo, que valem por cima
TT="$(cd "$(dirname "$0")/.." && pwd)/tt"
HOME=$(mktemp -d); export HOME
falhas=0
ok()   { echo "  ok: $1"; }
erro() { echo "  ERRO: $1"; falhas=$((falhas+1)); }

for f in ler_escolha ponte_nova_janela ponte; do
  eval "$(sed -n "/^$f() {/,/^}/p" "$TT")"
  [[ $(type -t "$f") == function ]] || { echo "não extraí $f"; exit 1; }
done

LOG=$HOME/chamadas; : >"$LOG"
FILA=$HOME/fila     # retornos do resolver_remota, um por linha (0, 1 ou 2); a subshell não guarda estado
RESP=""             # o que o usuário digita no aviso
FIM=""              # 1: a entrada acabou (EOF) no aviso
resolver_remota() {
  local r
  r=$(sed -n 1p "$FILA" 2>/dev/null); [[ -n $r ]] || r=$(tail -n1 "$FILA")
  sed -i 1d "$FILA" 2>/dev/null
  echo "resolver $r" >>"$LOG"
  [[ $r == 0 ]] && echo '$17|1792792741|graph-email-tt'
  return "$r"
}
sleep() { echo "sleep $1" >>"$LOG"; }
read() {
  case "$*" in
    "-r -t 0.05 -n 64 _le_x") return 1 ;;                        # drenagem: nada na fila
    "-r _le_r") echo "AVISO" >>"$LOG"; [[ -n $FIM ]] && return 1
                printf -v _le_r '%s' "$RESP"; return 0 ;;
    *) builtin read "$@" ;;
  esac
}
stty() { :; }
timeout() { shift; "$@"; }
clear() { :; }
rotulo_de() { echo macbook-pro; }
ponte_registrar() { :; }
log_ponte() { :; }
ssh() {
  echo "ssh" >>"$LOG"
  case "$*" in *--nova*) echo sessao-nova ;; esac
  return 0
}
tmux() {
  case $1 in
    kill-session) echo "kill-session" >>"$LOG" ;;
    set-option) echo "set-option $*" >>"$LOG" ;;
  esac
  return 0
}
MAQUINA=dell; PATH_REMOTO=''; SSH_OPC_TELA=(); SSH_OPC=(); TT_REMOTO=tt; EU=/bin/true
q() { printf '%q' "$1"; }

# 1) destino mudo duas vezes e depois responde; a 3ª resposta (sessão sumiu depois do attach) encerra a ponte
printf '%s\n' 2 2 0 1 1 >"$FILA"; : >"$LOG"; FIM=1
ponte macbook-pro@x graph-email-tt tt-pre-teste >/dev/null 2>&1
grep -q '^sleep 2$' "$LOG" && grep -q '^sleep 4$' "$LOG" && ok "espera crescente de 2 e 4 s antes de confirmar" || erro "esperas erradas: $(tr '\n' ' ' <"$LOG")"
grep -q '^AVISO$' "$LOG" && erro "mostrou o aviso quando o destino voltou a responder" || ok "sem aviso enquanto as tentativas automáticas resolvem"
grep -q '^kill-session$' "$LOG" && ok "ponte encerrada quando a sessão sumiu de verdade" || erro "ponte não encerrou"

# 2) destino mudo o tempo todo: 3 tentativas automáticas (2, 4, 8 s), depois o aviso; Enter tenta de novo
printf '%s\n' 2 2 2 2 2 2 2 2 2 2 2 2 >"$FILA"; : >"$LOG"; RESP=""; FIM=1
ponte macbook-pro@x graph-email-tt tt-pre-teste >/dev/null 2>&1
[[ $(grep -c '^sleep' "$LOG") == 3 ]] && grep -q '^sleep 8$' "$LOG" && ok "três tentativas automáticas (2, 4, 8 s)" || erro "tentativas: $(tr '\n' ' ' <"$LOG")"
[[ $(grep -c '^AVISO$' "$LOG") == 1 ]] && ok "depois mostra o aviso, uma vez" || erro "aviso mostrado $(grep -c '^AVISO$' "$LOG") vezes"
grep -q 'nova janela' "$LOG" && erro "ação n disparou sem ser escolhida" || ok "sem ação extra quando a entrada acaba"

# 3) escolha n: cria a sessão nova lá e troca a ponte para ela (exec do tt com o nome novo)
printf '%s\n' 2 2 2 >"$FILA"; : >"$LOG"; RESP="n"; FIM=""; EU=/bin/echo
saida=$(ponte macbook-pro@x graph-email-tt tt-pre-teste 2>&1)
grep -q -- '--ponte macbook-pro@x sessao-nova tt-pre-teste' <<<"$saida" && ok "n: ponte passa para a sessão nova criada lá" || erro "n não trocou para a sessão nova: $saida"
grep -q 'set-option -u' "$LOG" && ok "identidade antiga removida da ponte" || erro "identidade antiga ficou na ponte"
EU=/bin/true

# 4) escolha com eventos de foco e espaços: ESC[O e ESC[I saem da resposta; q volta sem tocar em nada
RESP=$'\e[O q\e[I'; FIM=""
ler_escolha escolha_teste; [[ $escolha_teste == " q" ]] && ok "eventos de foco saem da resposta" || erro "resposta com lixo: [$escolha_teste]"

echo "$([[ $falhas == 0 ]] && echo 'ok: retentativa e escolha da ponte' || echo "$falhas falha(s)")"
[[ $falhas == 0 ]]
