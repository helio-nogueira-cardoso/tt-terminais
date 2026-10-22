#!/usr/bin/env bash
# tt-teste: sozinho (mede tempo/tela: roda sem outros testes disputando a máquina)
# Vigia: uma instância só, mesmo lançando várias juntas; quem perde o pidfile sai; sem tmux, sai.
source "$(dirname "$0")/lib.sh"; isolar
# Sem o letreiro: o "(ticker_atualizar_fontes &)" de cada volta é um subshell do vigia (mesmo "bash tt --vigia")
# que fica órfão (ppid 1) enquanto busca as fontes na rede; com a rede lenta ele passava dos 6 s e contava como
# um 2º vigia principal.
mkdir -p "$XDG_CONFIG_HOME/tt"; echo ticker_ligado=0 >>"$XDG_CONFIG_HOME/tt/config"
tmux -f /dev/null new -d -s s 'sleep 600'
vivos() { local n=0 p; for p in $(pgrep -f "$TT --vigia"); do [[ $(ps -o args= -p "$p") == "bash $TT --vigia" ]] && n=$((n+1)); done; echo $n; }
pid() { cat "$TT_RT/tt-vigia-$(id -u).pid" 2>/dev/null; }
for i in 1 2 3; do TT_PAUSA=2 "$TT" --vigia >/dev/null 2>&1 & done
sleep 3
[[ $(vivos) -le 2 ]] || true # subshells do vigia contam; o dono é o do pidfile
p=$(pid); [[ -n $p ]] && kill -0 "$p" 2>/dev/null || falhou 'nenhum vigia ficou com o pidfile'
sleep 3; n=0; for q in $(pgrep -f "$TT --vigia"); do [[ $(ps -o ppid= -p "$q" | tr -d ' ') == 1 || $(ps -o ppid= -p "$q" | tr -d ' ') == $$ ]] && n=$((n+1)); done
[[ $n -le 1 ]] || falhou "$n vigias principais rodando"
passou 'três vigias lançados juntos: fica um só'
echo 99999 >"$TT_RT/tt-vigia-$(id -u).pid"; sleep 5
kill -0 "$p" 2>/dev/null && falhou 'vigia que perdeu o pidfile continuou rodando'
passou 'vigia que perde o pidfile sai sozinho'
TT_PAUSA=1 "$TT" --vigia >/dev/null 2>&1 & v=$!; sleep 2; tmux kill-server; sleep 7
kill -0 "$v" 2>/dev/null && falhou 'vigia continuou sem servidor tmux'
passou 'sem servidor tmux, o vigia sai'
