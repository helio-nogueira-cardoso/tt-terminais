#!/usr/bin/env bash
# Redesenhos por eventos: saída sincronizada ligada; reinstalar a mesma versão não recarrega nada;
# o vigia não renomeia pontes nem troca o nome de uma sessão já nomeada antes de TT_T_RENOMEAR.
# tt-teste: sozinho
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
tmux -f "$HOME/.tmux.conf" new -d -s s -x 100 -y 30 'bash --norc' 2>/dev/null
anexar x 100 32 s; sleep 1.5
tmux list-clients -F '#{client_termfeatures}' | grep -q sync || falhou 'cliente sem saída sincronizada (modo 2026)'
passou 'saída sincronizada ativa: redesenhos chegam em bloco, sem o cursor correr pela tela'

mkdir -p "$T/shim"; cat >"$T/shim/tmux" <<SH
#!/usr/bin/env bash
[[ \${1:-} == -u ]] && shift   # o tt chama tmux -u (2.12.1)
case \$1 in set|set-option|source-file|refresh-client) echo "\$*" >>"$T/escritas" ;; esac
exec $(command -v tmux) "\$@"
SH
chmod +x "$T/shim/tmux"
: >"$T/escritas"; TT_DIR=$HOME/.local/share/tt PATH=$T/shim:$PATH "$T/pkg/tt" --instalar-aqui >/dev/null 2>&1
[[ ! -s $T/escritas ]] || falhou "reinstalar a mesma versão recarregou/redesenhou: $(head -c 150 "$T/escritas")"
passou 'reinstalar a mesma versão não recarrega nem redesenha'

# Sessão de shell com uso, já nomeada há pouco: o vigia não troca o nome. Ponte: nunca.
tmux new -d -s janela-1 'bash --norc'; tmux new -d -s ja-nomeada 'bash --norc'; tmux new -d -s ponte-y 'bash --norc'; tmux set -t =ponte-y: @ponte x
# O tmux.conf instalado sobe o próprio vigia: para o teste controlar o dele (claude falso, prazos curtos).
kill "$(cat "$TT_RT"/tt-vigia-*.pid 2>/dev/null)" 2>/dev/null || true; rm -f "$TT_RT"/tt-vigia-*.pid; sleep 0.5
# A instalação fornece claude-rot: substituir só o claude do PATH não intercepta essa rota.
# O nomeador falso não consulta contas nem depende de credenciais desta máquina.
rm -f "$HOME/.local/bin/claude-rot" # link do pacote isolado; o falso fica em arquivo próprio
printf '#!/bin/sh\ncat >/dev/null; echo chamado >>"%s"; echo nome-novo\n' "$T/nomeador-chamado" >"$HOME/.local/bin/claude-rot"
chmod +x "$HOME/.local/bin/claude-rot"
printf 'nomeador=claude\n' >>"$XDG_CONFIG_HOME/tt/config"
TT_PAUSA=1 TT_T_PRIMEIRO=2 TT_PONTOS_RENOMEAR=1 TT_T_RENOMEAR=3600 "$TT" --vigia >"$T/vigia-saida" 2>&1 &
sleep 3
for i in {1..30}; do
  tmux has-session -t =nome-novo 2>/dev/null && break
  for s in janela-1 ja-nomeada ponte-y; do tmux send -t "=$s:" "echo $i" Enter; done
  sleep 1
done
tmux has-session -t =ja-nomeada 2>/dev/null || falhou 'sessão já nomeada foi renomeada antes do prazo'
tmux has-session -t =ponte-y 2>/dev/null || falhou 'ponte foi renomeada pelo vigia'
[[ -s $T/nomeador-chamado ]] && tmux has-session -t =nome-novo 2>/dev/null || {
  cat "$T/vigia-saida" "$HOME/.cache/tt-vigia.log" 2>/dev/null || true
  falhou 'nomeador falso não foi usado (teste sem efeito)'
}
passou 'vigia: sem renomear pontes nem trocar nome recente (menos redesenhos, nome estável)'
