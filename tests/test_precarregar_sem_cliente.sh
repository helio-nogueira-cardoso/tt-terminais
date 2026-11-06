#!/usr/bin/env bash
# O evento do vigia (um por volta, 60 s) não pode subir um coordenador do pré-carregamento sem cliente tmux ativo:
# ele encerraria em 60 s e o evento seguinte subiria outro, um Python por minuto o dia todo (celular sem clientes; Mac
# com as telas paradas). Com um cliente anexado e ativo o coordenador sobe como sempre. tmux real e isolado, sem rede.
source "$(dirname "$0")/lib.sh"; isolar
export TT_PRECARREGAR=1
printf 'nome=local\n' >"$XDG_CONFIG_HOME/tt/config"
mkdir -p "$HOME/.cache"  # o coordenador registra o início aí e engole o erro se a pasta não existir
log=$HOME/.cache/tt-vigia.log
trap 'st=$?; set +e; (exit "$st"); "$TT" --precarregar off >/dev/null 2>&1; limpar_isolado' EXIT

inicios() { grep -c 'precarregador iniciado' "$log" 2>/dev/null || true; }
espera() { local n=0; until "$@"; do ((n+=1)); ((n >= 100)) && return 1; sleep .1; done; }

tmux -f /dev/null new-session -d -s origem "sleep 600"

# 1) servidor tmux no ar, nenhum cliente: o evento não sobe coordenador (nem uma vez, nem em rajada)
[[ -z $(tmux list-clients 2>/dev/null) ]] || falhou 'o cenário deveria começar sem cliente tmux'
for _ in 1 2 3; do "$TT" --precarregar-evento evento; done
sleep 1.5
n=$(inicios)
((n == 0)) || falhou "sem cliente ativo o evento subiu $n coordenador(es)"
pgrep -f "$T/pkg/precarregar-tt.py daemon" >/dev/null && falhou 'há um coordenador vivo sem nenhum cliente'
echo "ok: sem cliente tmux o evento não sobe coordenador"

# 2) um cliente anexado e ativo: o mesmo evento sobe o coordenador
fora new -d -s pc -x 120 -y 35 "env -u TMUX TERM=xterm-256color TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t origem"
espera bash -c '[[ -n $(tmux list-clients 2>/dev/null) ]]' || falhou 'o cliente não anexou'
"$TT" --precarregar-evento evento
espera bash -c "grep -q 'precarregador iniciado' '$log' 2>/dev/null" || falhou 'com cliente ativo o coordenador deveria subir'
n=$(inicios)
((n == 1)) || falhou "com cliente ativo deveria subir exatamente 1 coordenador; subiu $n"
echo "ok: com cliente ativo o evento sobe o coordenador (1)"

# 3) coordenador já vivo: eventos seguintes não sobem outro
for _ in 1 2 3; do "$TT" --precarregar-evento evento; done
sleep 1
n=$(inicios)
((n == 1)) || falhou "o coordenador vivo atendeu os eventos; não era para subir outro (inícios: $n)"
echo "ok: coordenador vivo atende os eventos seguintes"
echo "TODOS OS TESTES PASSARAM"
