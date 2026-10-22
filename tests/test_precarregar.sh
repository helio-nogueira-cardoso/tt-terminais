#!/usr/bin/env bash
# tt-teste: sozinho
# Heurística + SSH/PTY/tmux reais em duas casas e sockets isolados. Nenhuma rede real.
source "$(dirname "$0")/lib.sh"; isolar
python3 "$RAIZ/tests/test_precarregar_modelo.py"
export TT_PRECARREGAR=1
export TT_TEST_PRE_REMOTE=$T/remota
mkdir -p "$T/bin" "$TT_TEST_PRE_REMOTE/home/.config/tt" "$TT_TEST_PRE_REMOTE/home/.local/bin" "$TT_TEST_PRE_REMOTE/home/.local/share" "$TT_TEST_PRE_REMOTE/tmux" "$TT_TEST_PRE_REMOTE/rt" "$HOME/.local/bin"
ln -s "$RAIZ/tests/precarregar_ssh.py" "$T/bin/ssh"
# Sem helper nem tt novo no destino: o protocolo é transitório, só em memória.
ln -s "$T/pkg/tt" "$HOME/.local/bin/tt"
export PATH="$T/bin:$PATH"
ln -s /usr/bin/false "$T/bin/tailscale"
ln -s /usr/bin/false "$T/bin/pmset"
printf 'nome=remota\nprecarregar=off\n' >"$TT_TEST_PRE_REMOTE/home/.config/tt/config"
printf 'dest usuario remota\n' >"$XDG_CONFIG_HOME/tt/maquinas"
R() { env -u TMUX TMUX_TMPDIR="$TT_TEST_PRE_REMOTE/tmux" tmux "$@"; }
limpar_pre() {
  local st=$?
  "$TT" --precarregar off >/dev/null 2>&1 || true
  R kill-server 2>/dev/null || true
  (exit "$st")
  limpar_isolado
}
trap 'st=$?; set +e; (exit "$st"); limpar_pre' EXIT
R -f /dev/null new-session -d -s primeira 'sleep 600'
R new-session -d -s segunda 'sleep 600'
R set-option -t primeira @tt_session_id aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
R set-option -t segunda @tt_session_id bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
printf 'remota\tprimeira\taaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nremota\tsegunda\tbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n' >"$XDG_CONFIG_HOME/tt/fixadas"
tmux -f /dev/null new-session -d -s origem 'sleep 600'
fora new -d -s pc -x 120 -y 35 "env -u TMUX TERM=xterm-256color TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t origem"
fora new -d -s outro -x 90 -y 25 "env -u TMUX TERM=xterm-256color TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t origem"
espera() {
  local n=0
  until "$@"; do
    ((n+=1))
    if ((n >= 100)); then
      "$TT" --precarregar status || true
      tmux list-clients -F '#{client_name}|#{client_pid}|#{client_created}|#{client_activity}|#{client_termname}|#{session_name}'
      tmux list-panes -a -F '#{session_name} #{pane_dead} #{pane_current_command}'
      while read -r p; do tmux capture-pane -p -J -t "$p"; done < <(tmux list-panes -a -F '#{pane_id}')
      falhou "espera: $*"
    fi
    sleep .1
  done
}
clientes() { [[ $(tmux list-clients -F '#{client_name}' | wc -l) == 2 ]]; }
espera clientes
cliente=$(tmux list-clients -F '#{client_width} #{client_name}' | awk '$1==120 {print $2}')
outro=$(tmux list-clients -F '#{client_width} #{client_name}' | awk '$1==90 {print $2}')
export TMUX=$(tmux display-message -p '#{socket_path},#{pid},0')
pre_estado() { "$TT" --precarregar json; }
prontas() { pre_estado | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(not any(p["state"]=="ready" for p in d.get("pontes",[])))'; }
"$TT" --precarregar-evento evento
espera prontas
pre_estado | python3 -c 'import json,sys; assert json.load(sys.stdin)["historico_eventos"]==0' || falhou 'preparação contaminou histórico'
if "$TT" --listar-leve | grep -q 'tt-pre-'; then falhou 'transporte especulativo apareceu no seletor'; fi
[[ $(R list-clients | wc -l) == 0 ]] || falhou 'pré-carregamento anexou usuário fantasma'
[[ $(tmux list-clients -F '#{session_name}' | sort -u) == origem ]] || falhou 'pré-carregamento trocou tela sem clique'
passou 'conexões preparadas sem anexar cliente nem trocar a tela'

# Nome muda depois de preparar: identidade persiste.
R rename-session -t primeira renomeada
# CLI interna usa a mesma entrada de navegação da barra, com identidade explícita.
TT_SO_CARREGAR=1 source "$TT"
EU=$TT
fixada_chave_em chave remota primeira aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
"$TT" --ir-fixada "$cliente" "fx$chave"
trocou() { [[ $(tmux list-clients -F '#{client_name} #{session_name}' | awk -v c="$cliente" '$1==c {print $2}') == tt-pre-* ]]; }
espera trocou
grep -q 'via=precarregar' "$HOME/.cache/tt-troca.log" || falhou 'troca preparada sem trilha de diagnóstico'
[[ $(tmux list-clients -F '#{client_name} #{session_name}' | awk -v c="$outro" '$1==c {print $2}') == origem ]] || falhou 'arrastou outra tela'
[[ $(R list-clients -F '#{session_name}') == renomeada ]] || falhou 'não usou identidade ao renomear'
passou 'clique promove a ponte correta sem arrastar outra tela; renomeação preservada'

# Voltar ao caminho legado não pode adotar um terminal ainda esperando bilhete.
legada=$(criar_ponte usuario@dest segunda "$outro")
[[ $legada != tt-pre-* ]] || falhou 'ponte legada adotou transporte em espera'
tmux kill-session -t "=$legada"
passou 'caminho legado não reaproveita ponte em espera'

# Uma resposta lenta não ganha de um clique local posterior.
printf 'lenta usuario lenta\noffline usuario offline\n' >>"$XDG_CONFIG_HOME/tt/maquinas"
precarregar_trocar "$outro" usuario@lenta segunda bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
(set +e; TT_CLIENTE=$outro ir_para . origem)
sleep 2
[[ $(tmux list-clients -F '#{client_name} #{session_name}' | awk -v c="$outro" '$1==c {print $2}') == origem ]] || falhou 'clique cancelado trocou tela tarde'
[[ $(R list-clients -F '#{session_name}') == renomeada ]] || falhou 'cancelamento deixou cliente remoto'
passou 'clique local cancela navegação remota lenta, sem usuário fantasma'

# Dois cliques remotos: somente o último pode vencer, mesmo com respostas fora de ordem.
precarregar_trocar "$outro" usuario@lenta segunda bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
precarregar_trocar "$outro" usuario@dest primeira aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
ultimo_clique() { [[ $(tmux list-clients -F '#{client_name} #{session_name}' | awk -v c="$outro" '$1==c {print $2}') == tt-pre-* ]]; }
espera ultimo_clique
ponte_outro=$(tmux list-clients -F '#{client_name} #{session_name}' | awk -v c="$outro" '$1==c {print $2}')
sleep 2
[[ $(R list-clients -F '#{session_name}' | sort -u) == renomeada ]] || falhou 'resposta antiga ganhou do clique novo'
(set +e; TT_CLIENTE=$outro ir_para . origem)
tmux kill-session -t "=$ponte_outro"
passou 'dois cliques remotos concorrentes respeitam o último destino'

# Máquina sem rede: conserva a tela e aplica espera progressiva.
precarregar_trocar "$outro" usuario@offline segunda bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
falha_rede() { pre_estado | python3 -c 'import json,sys; sys.exit(json.load(sys.stdin).get("metricas",{}).get("falhas",0)<1)'; }
espera falha_rede
[[ $(tmux list-clients -F '#{client_name} #{session_name}' | awk -v c="$outro" '$1==c {print $2}') == origem ]] || falhou 'rede caída mudou tela'
passou 'falha de rede preserva a tela'

# Sessão removida e recriada com MESMO nome não herda um bilhete de outra identidade.
R kill-session -t segunda
R new-session -d -s segunda 'sleep 600'
R set-option -t segunda @tt_session_id cccccccccccccccccccccccccccccccc
precarregar_trocar "$outro" usuario@dest segunda bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
sleep 3
[[ $(R list-clients -F '#{session_name}') == renomeada ]] || falhou 'abriu sessão reciclada'
passou 'identidade removida não abre sessão nova de mesmo nome'
precarregar_trocar "$outro" usuario@dest segunda cccccccccccccccccccccccccccccccc
espera ultimo_clique
[[ $(R list-clients -F '#{session_name}' | sort -u) == $'renomeada\nsegunda' ]] || falhou 'clique explícito na identidade nova não abriu'
pre_estado | python3 -c 'import json,sys; d=json.load(sys.stdin); s=d["troca_ms"]; a=[v["clique_ms"] for v in s if v["preparada"]]; b=[v["clique_ms"] for v in s if not v["preparada"]]; assert a and b and min(a+b)>=0; print("telemetria: preparada %d ms; sob demanda %d ms" % (a[0], b[-1]))'
passou 'destino novo sob demanda e destino preparado têm confirmação e telemetria'
# A tela de controle usa as mesmas operações da CLI (não depende de fzf nem rede).
tmux new-session -d -s controle "$(q "$TT" --precarregar-ui)"
controle_visivel() { tmux capture-pane -p -t '=controle:' | grep -q 'automático'; }
espera controle_visivel
tmux send-keys -t '=controle:' e
eco() { grep -q '^precarregar=economico$' "$XDG_CONFIG_HOME/tt/config"; }
espera eco
tmux send-keys -t '=controle:' q
controle_fechado() { ! tmux has-session -t '=controle' 2>/dev/null; }
espera controle_fechado
"$TT" --precarregar status | grep -q 'econômico' || falhou 'status legível não mostra modo'
passou 'painel de controle e CLI mostram e alteram o mesmo modo'
clientes_remotos=$(R list-clients -F '#{session_name}' | sort)
precarregar_cmd off >/dev/null
[[ $(R list-clients -F '#{session_name}' | sort) == "$clientes_remotos" ]] || falhou 'desligar matou ponte em uso'
passou 'desligar descarta apenas especulação e preserva a sessão em uso'
