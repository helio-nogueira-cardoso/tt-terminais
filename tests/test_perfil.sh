#!/usr/bin/env bash
# Pacote × perfil × estado: a instalação troca o pacote inteiro sem levar nada do usuário; dados
# que versões antigas gravavam no pacote ou no perfil migram para ~/.local/state/tt.
source "$(dirname "$0")/lib.sh"; isolar
pkg=$HOME/.local/share/tt state=$HOME/.local/state/tt
# Instalação "antiga": memória dos agentes dentro do pacote, avisado= e cópia gerenciada no perfil.
mkdir -p "$pkg/ai-memory"; echo 'fato importante' >"$pkg/ai-memory/memory.md"; echo '1 velho x' >"$pkg/VERSAO"
printf 'nome=teste\navisado=7\nrecebidos=~/R\n' >"$XDG_CONFIG_HOME/tt/config"
printf '<!-- tt-managed: x -->\nvelha\n' >"$XDG_CONFIG_HOME/tt/AI-DLC.md"
: >"$HOME/.bashrc"
"$T/pkg/tt" --configurar-bashrc >/dev/null 2>&1 || falhou 'bloco do bashrc'
instalar_isolado

grep -qx 'fato importante' "$state/ai-memory/memory.md" 2>/dev/null || falhou 'memória dos agentes perdida na atualização'
[[ -e $pkg/ai-memory ]] && falhou 'memória dos agentes continua dentro do pacote'
grep -q '^avisado=' "$XDG_CONFIG_HOME/tt/config" && falhou 'avisado= (estado) ficou no perfil'
grep -qx 'recebidos=~/R' "$XDG_CONFIG_HOME/tt/config" || falhou 'instalação mexeu numa escolha do usuário'
[[ -e $XDG_CONFIG_HOME/tt/AI-DLC.md ]] && falhou 'cópia gerenciada da política ficou no perfil'
pol=$(bash -c 'source ~/.bashrc >/dev/null 2>&1; echo "$TT_AIDLC_POLICY"' </dev/null)
[[ $pol == "$pkg/AI-DLC.md" ]] || falhou "TT_AIDLC_POLICY não aponta para o pacote: $pol"
passou 'perfil: atualização migra memória/avisado para o estado e não toca nas escolhas'

# Reinstalar de novo (pacote trocado inteiro) mantém a memória; política do usuário prevalece.
echo 'minha política' >"$XDG_CONFIG_HOME/tt/AI-DLC.md"
echo "1000 outro 2099-01-02" >"$T/pkg/VERSAO"; TT_DIR=$pkg "$T/pkg/tt" --instalar-aqui >/dev/null 2>&1
grep -qx 'fato importante' "$state/ai-memory/memory.md" || falhou 'memória perdida na segunda instalação'
grep -qx 'minha política' "$XDG_CONFIG_HOME/tt/AI-DLC.md" || falhou 'política do usuário foi apagada'
pol=$(bash -c 'source ~/.bashrc >/dev/null 2>&1; echo "$TT_AIDLC_POLICY"' </dev/null)
[[ $pol == "$XDG_CONFIG_HOME/tt/AI-DLC.md" ]] || falhou "política do perfil não prevaleceu: $pol"
passou 'perfil: reinstalação preserva memória e a política própria do usuário'

# tmux.conf do perfil é carregado depois do pacote; sem ele, nada quebra.
s=$T/perfil.sock
tmux -S "$s" -f "$pkg/tmux.conf" new -d -s p 'sleep 30' || falhou 'tmux.conf sem perfil não carrega'
tmux -S "$s" kill-server; for _ in $(seq 50); do tmux -S "$s" has-session 2>/dev/null || break; sleep 0.1; done; rm -f "$s"
echo 'set -g @perfil_ok sim' >"$XDG_CONFIG_HOME/tt/tmux.conf"
tmux -S "$s" -f "$pkg/tmux.conf" new -d -s p 'sleep 30'
[[ $(tmux -S "$s" show -gv @perfil_ok 2>/dev/null) == sim ]] || falhou 'tmux.conf do perfil não foi carregado'
tmux -S "$s" kill-server
passou 'perfil: ~/.config/tt/tmux.conf carregado depois do pacote'
