#!/usr/bin/env bash
# Tela de transferências (⇅): causa da falha em português, rolagem com muitos trabalhos, seleção por
# setas, confirmação de cancelar passando de 50 %, "r" tenta de novo (com cópia real local), "x" limpa
# as terminadas, log inteiro com "l". Roda numa tmux isolada (socket próprio) com HOME/RT temporários.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); S=ttx$$
trap 'tmux -L $S kill-server 2>/dev/null; rm -rf "$T"' EXIT
fail(){ echo "FALHOU: $1" >&2; tmux -L $S capture-pane -p -t x 2>/dev/null | tail -30 >&2; exit 1; }
command -v tmux >/dev/null || { echo "sem tmux, pulei"; exit 0; }
mkdir -p "$T/home/.config/tt" "$T/rt" "$T/orig" "$T/dest"
printf 'nome=A\n' >"$T/home/.config/tt/config"
D="$T/rt/tt-transferencias-$(id -u)"; mkdir -p "$D"
E="env HOME=$T/home XDG_CONFIG_HOME=$T/home/.config XDG_STATE_HOME=$T/state TT_RT=$T/rt TT_MACHINE=A LANG=C.UTF-8 LC_ALL=C.UTF-8"
job(){ # id estado nome [log]
  printf '%s\n' "$2" >"$D/$1.status"; printf '%s\n' "$3" >"$D/$1.nomes"
  printf 'A\t/o\tA\t/d\n' >"$D/$1.info"; [[ -n ${4:-} ]] && printf '%s\n' "$4" >"$D/$1.log"; return 0; }
tela(){ tmux -L $S capture-pane -p -t x; }
espera(){ local i; for i in $(seq 1 40); do tela | grep -Fq -- "$1" && return 0; sleep 0.25; done; fail "tela não mostrou: $1"; }
abre(){ tmux -L $S kill-server 2>/dev/null || true
  tmux -L $S -f /dev/null new-session -d -x 100 -y 24 -s x "$E bash $TT --transferencias"; }

# 1) causa legível por tipo de erro
job 100 'erro — veja o log' 'a.zip' 'tar: write error: No space left on device'
job 101 'erro — veja o log' 'b.zip' 'ssh: connect to host x port 22: No route to host'
job 102 'erro — veja o log' 'c.zip' 'rsync: Permission denied (13)'
abre; espera 'sem espaço no destino'; tela | grep -Fq 'inalcançável' || fail 'causa: máquina inalcançável'
tela | grep -Fq 'sem permissão' || fail 'causa: permissão'
tmux -L $S send-keys -t x q; sleep 0.3
rm -f "$D"/*

# 2) muitos trabalhos: rolagem e contador "x–y de n"
for i in $(seq 1 12); do job "2$(printf '%02d' $i)" 'concluída' "arq$i.txt"; sleep 0.02; touch -d "-$((13 - i)) seconds" "$D/2$(printf '%02d' $i).status"; done
abre; espera 'de 12'
for i in $(seq 1 11); do tmux -L $S send-keys -t x Down; sleep 0.15; done
espera '▶12'; tela | grep -Fq 'arq1.txt' || fail 'a rolagem não mostrou o último trabalho'
tmux -L $S send-keys -t x q; sleep 0.3

# 3) x limpa as terminadas e preserva as em andamento
rm -f "$D"/*
job 300 'concluída' 'feita.txt'; job 301 'erro — veja o log' 'ruim.txt' 'x'
job 302 'transferindo 1G…' 'andando.iso'; sleep 600 & pidw=$!; printf '%s\n' "$pidw" >"$D/302.pid"
printf '1000 400 10\n' >"$D/302.prog"
abre; espera 'andando.iso'; tmux -L $S send-keys -t x x; sleep 1
[[ ! -f $D/300.status && ! -f $D/301.status && -f $D/302.status ]] || fail 'x deveria limpar só as terminadas'

# 4) cancelar abaixo de 50 % cancela direto; passando de 50 % pergunta
tmux -L $S send-keys -t x c; sleep 1; [[ $(cat "$D/302.status") == cancelada ]] || fail 'cancelar a 40% deveria cancelar direto'
sleep 600 & pidw=$!; printf '%s\n' "$pidw" >"$D/302.pid"
printf 'transferindo 1G…\n' >"$D/302.status"; printf '1000 800 10\n' >"$D/302.prog"; sleep 1
tmux -L $S send-keys -t x c; espera 'Cancelar mesmo'
tmux -L $S send-keys -t x n; sleep 1; [[ $(cat "$D/302.status") == transferindo* ]] || fail 'responder n deveria manter'
tmux -L $S send-keys -t x c; espera 'Cancelar mesmo'; tmux -L $S send-keys -t x s; sleep 1
[[ $(cat "$D/302.status") == cancelada ]] || fail 'responder s deveria cancelar'
kill "$pidw" 2>/dev/null || true; tmux -L $S send-keys -t x q; sleep 0.3
rm -f "$D"/*

# 5) r tenta de novo com cópia real (local→local): o trabalho antigo some e chega o arquivo
printf 'conteudo\n' >"$T/orig/dado.txt"
job 400 'erro — veja o log' 'dado.txt' 'x'
printf '%s\0' . "$T/orig" . "$T/dest" dado.txt >"$D/400.args"
abre; espera 'dado.txt'; tmux -L $S send-keys -t x r
for i in $(seq 1 40); do [[ -f $T/dest/dado.txt ]] && break; sleep 0.5; done
[[ -f $T/dest/dado.txt ]] || fail 'r não refez a cópia'
[[ ! -f $D/400.status ]] || fail 'r deveria apagar o trabalho antigo'
echo "ok — tela de transferências: causas, rolagem, x, confirmação de cancelar e r"

# 6) barra: andamento somado dos ativos (sem trabalho ativo, nada)
rm -f "$D"/*
sleep 600 & pidw=$!
job 500 'transferindo 1G…' 'a.iso'; printf '%s\n' "$pidw" >"$D/500.pid"; printf '1000 620 2097152\n' >"$D/500.prog"
b=$($E bash "$TT" --transferencias-barra)
grep -Fq '62%' <<<"$b" && grep -Fq '2.0M/s' <<<"$b" || { kill $pidw; fail "barra deveria mostrar 62% e 2.0M/s: $b"; }
kill $pidw 2>/dev/null || true; sleep 0.2
b=$($E bash "$TT" --transferencias-barra); [[ -z $b ]] || fail "barra sem ativos deveria ficar vazia: $b"
echo "ok — barra: andamento somado"

# 7) conferir / destino-info
rm -rf "$T/orig" "$T/dest"; mkdir -p "$T/orig/pasta/sub" "$T/dest"
printf 'aaaa' >"$T/orig/um.txt"; printf 'bbbbbb' >"$T/orig/pasta/sub/dois.txt"
r=$($E bash "$TT" --conferir "$T/orig" um.txt pasta); [[ $r == "2 10" ]] || fail "conferir deveria dar '2 10', deu '$r'"
h1=$($E bash "$TT" --conferir --hash "$T/orig" um.txt pasta); [[ ${#h1} == 64 ]] || fail "hash inválido: $h1"
printf 'x' >"$T/dest/um.txt"
r=$($E bash "$TT" --destino-info "$T/dest" um.txt pasta); read -r livre conf <<<"$r"
[[ $conf == 1 && $livre -gt 0 ]] || fail "destino-info deveria achar 1 conflito e espaço livre: $r"

# cópia local ponta a ponta: termina conferida (contagem/tamanho e, com TT_CONFERIR=1, sha256)
espera_fim(){ local i; for i in $(seq 1 60); do grep -Fq -- "$1" "$D"/*.log 2>/dev/null && return 0; sleep 0.5; done; fail "log não mostrou: $1"; }
rm -f "$D"/*; rm -rf "$T/dest"; mkdir -p "$T/dest"
$E TT_SEM_CONFIRMAR=1 bash "$TT" --enviar "$T/orig/um.txt" "$T/orig/pasta" "A:$T/dest" >/dev/null 2>&1
espera_fim 'Conferido (contagem e tamanho)'
[[ -f $T/dest/um.txt && -f $T/dest/pasta/sub/dois.txt ]] || fail 'a cópia local não chegou inteira'
rm -f "$D"/*; rm -rf "$T/dest"; mkdir -p "$T/dest"
$E TT_SEM_CONFIRMAR=1 TT_CONFERIR=1 bash "$TT" --enviar "$T/orig/um.txt" "A:$T/dest" >/dev/null 2>&1
espera_fim 'Conferido (sha256)'

# confirmação: mostra itens/tamanho/conflito; ⏎ aceita, Esc recusa
mkdir -p "$T/dest"; printf 'x' >"$T/dest/um.txt"
tmux -L $S kill-server 2>/dev/null || true
tmux -L $S -f /dev/null new-session -d -x 100 -y 24 -s x "$E bash $TT --confirmar-transferencia . $T/orig . $T/dest um.txt pasta; echo RC=\$?; sleep 30"
espera 'Confirmar a transferência'
tela | grep -Fq '2 itens' || fail 'confirmação deveria dizer 2 itens'
tela | grep -Fq '1 já existe lá' || fail 'confirmação deveria avisar do conflito'
tmux -L $S send-keys -t x Escape; espera 'RC=1'
tmux -L $S kill-server 2>/dev/null || true
tmux -L $S -f /dev/null new-session -d -x 100 -y 24 -s x "$E bash $TT --confirmar-transferencia . $T/orig . $T/dest um.txt; echo RC=\$?; sleep 30"
espera 'Confirmar a transferência'; tmux -L $S send-keys -t x Enter; espera 'RC=0'
echo "ok — conferência, confirmação e cópia local verificada"
