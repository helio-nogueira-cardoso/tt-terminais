#!/usr/bin/env bash
# Cursor piscando: todo set-option (até de opção @) redesenha a tela inteira de todos os clientes.
# Em regime, nada pode gravar opções periodicamente; a barra não roda processos.
source "$(dirname "$0")/lib.sh"; isolar
grep -q '#(' "$T/pkg/tmux.conf" "$T/pkg/tema-tmux.conf" && falhou 'barra roda processos (#())'
iv=$(awk '/^set -g status-interval/ { print $4 }' "$T/pkg/tmux.conf" "$T/pkg/tema-tmux.conf" | tail -1)
((iv == 0 || iv >= 15)) || falhou "status-interval curto demais: $iv"
passou "barra sem processos, intervalo $iv s"
# Exceção única e deliberada: o miolo da faixa vive em @barra_notifs como UM #() persistente por cliente
# (letreiro-tt.py fluxo), que só lê arquivos e imprime — o tmux redesenha então só a barra, no máximo
# 1 vez/s. Nada do tt grava opção por passo do letreiro nem força refresh-client -S em regime (um
# refresh recria os #() de cada cliente).
grep -qE 'subprocess|os\.system|popen|os\.exec' "$T/pkg/letreiro-tt.py" && falhou 'letreiro-tt.py lança processos (deveria só ler arquivos e imprimir)'
rg -q 'tmux set -g @barra_ticker|tmux set -g @barra_aviso|refresh-client -S' "$T/pkg/tt" && falhou 'tt grava @barra_ticker/@barra_aviso ou força refresh-client -S (redesenho completo / letreiro reiniciado)'
passou 'letreiro por #() persistente: sem set-option por passo, sem refresh forçado'

mkdir -p "$T/shim"; cat >"$T/shim/tmux" <<SH
#!/usr/bin/env bash
case \$1 in set|set-option|source-file) echo "\$*" >>"$T/escritas" ;; esac
exec $(command -v tmux) "\$@"
SH
chmod +x "$T/shim/tmux"
tmux -f "$T/pkg/tmux.conf" new -d -s a -x 100 -y 30 'sleep 900' 2>/dev/null; tmux new -d -s b 'bash --norc'; sleep 2
"$TT" --reforcar-padrao
: >"$T/escritas"; PATH=$T/shim:$PATH "$TT" --reforcar-padrao
[[ ! -s $T/escritas ]] || falhou "reforçar o padrão sem desvio gravou: $(head -c 200 "$T/escritas")"
tmux set -t =b: status-style bg=red
: >"$T/escritas"; PATH=$T/shim:$PATH "$TT" --reforcar-padrao
[[ $(wc -l <"$T/escritas") == 1 && -z $(tmux show -qv -t =b: status-style) ]] || falhou 'desvio não corrigido numa gravação só'
passou 'reforçar o padrão é idempotente (0 gravações sem desvio; 1 com desvio)'

tmux new -d -s c 'while :; do echo x; sleep 1; done'
TT_PAUSA=2 TT_T_PRIMEIRO=999 TT_PONTOS_RENOMEAR=999999 PATH=$T/shim:$PATH "$TT" --vigia >/dev/null 2>&1 &
sleep 8; : >"$T/escritas"; sleep 12
grep -v '@barra_\|^set -g status 2' "$T/escritas" | grep -q . && falhou "vigia em regime grava opções: $(head -3 "$T/escritas")"
passou 'vigia em regime não grava opções (nenhum redesenho completo periódico)'
