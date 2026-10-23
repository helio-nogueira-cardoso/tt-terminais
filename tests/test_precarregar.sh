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
R -f /dev/null new-session -d -s primeira "printf 'TT_TELA_PRIMEIRA\\n'; sleep 600"
R new-session -d -s segunda 'sleep 600'
R set-option -t primeira @tt_session_id aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
R set-option -t segunda @tt_session_id bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
printf 'remota\tprimeira\taaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nremota\tsegunda\tbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n' >"$XDG_CONFIG_HOME/tt/fixadas"
tmux -f /dev/null new-session -d -s origem "printf 'TT_TELA_ORIGEM\\n'; sleep 600"
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

# Mede a rota completa da barra até a tela pronta (SSH/PTY/tmux isolados).
# A versão anterior ainda exige o tt remoto para voltar a uma ponte já ativada.
ssh_antes=$(wc -l <"$TT_TEST_PRE_REMOTE/ssh.log")
ponte_cliente=$(tmux list-clients -F '#{client_name} #{session_name}' | awk -v c="$cliente" '$1==c {print $2}')
python3 - "$TT" "$cliente" "fx$chave" "$ponte_cliente" "fora-$$" <<'PY_BENCH'
import os, statistics, subprocess, sys, time
command, client, key, bridge, outer_socket = sys.argv[1:]
def screen():
    return subprocess.check_output(["tmux", "-L", outer_socket, "capture-pane", "-p", "-t", "=pc:"], text=True)
samples = []
for index in range(7):
    subprocess.run(["tmux", "switch-client", "-c", client, "-t", "=origem"], check=True)
    until = time.monotonic() + 4
    while "TT_TELA_ORIGEM" not in screen():
        if time.monotonic() > until:
            raise SystemExit("origem não apareceu na tela do terminal")
        time.sleep(.005)
    began = time.monotonic()
    args = ["--clique", "user|" + key, client, "%0", "", "0", "d"] if index % 2 else ["--ir-fixada", client, key]
    subprocess.run([command, *args], check=True)
    while time.monotonic() - began < 4:
        out = subprocess.check_output(["tmux", "list-clients", "-F", "#{client_name}\t#{session_name}"], text=True)
        if client + "\t" + bridge in out.splitlines() and "TT_TELA_PRIMEIRA" in screen():
            break
        time.sleep(.005)
    else:
        raise SystemExit("volta à ponte não trocou a tela")
    samples.append(round((time.monotonic() - began) * 1000))
print("latência de volta à ponte (7 cliques CLI→quadro no terminal): mediana=%d ms máximo=%d ms" % (statistics.median(samples), max(samples)))
PY_BENCH
[[ $(wc -l <"$TT_TEST_PRE_REMOTE/ssh.log") == "$ssh_antes" ]] || falhou 'volta à ponte abriu SSH de novo'
pre_estado | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["metricas"].get("reutilizadas",0)>=7; print("reuso no coordenador:", [s["clique_ms"] for s in d["troca_ms"] if s.get("reutilizada")])'
passou 'sete voltas à ponte pela barra sem helper remoto e sem SSH adicional'

# A mesma entrada curta volta à sessão local sem atrasar o clique com novo Bash/SSH.
tmux set-option -t '=origem:' @tt_session_id eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
printf '%s\torigem\teeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\n' "$MAQUINA" >>"$XDG_CONFIG_HOME/tt/fixadas"
fixada_chave_em chave_local "$MAQUINA" origem eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
"$TT" --ir-fixada "$cliente" "fx$chave_local"
[[ $(tmux list-clients -F '#{client_name} #{session_name}' | awk -v c="$cliente" '$1==c {print $2}') == origem ]] || falhou 'entrada curta não voltou à sessão local'
pre_estado | python3 -c 'import json,sys; assert json.load(sys.stdin)["troca_ms"][-1].get("local")'
"$TT" --ir-fixada "$cliente" "fx$chave"
passou 'voltar da ponte à fixada local usa identidade e cancela pedidos antigos'


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

# Reiniciar o coordenador não esquece o transporte que continua conectado.
precarregar_cmd off >/dev/null
precarregar_cmd auto >/dev/null
sleep .2
antes_clientes=$(R list-clients -F '#{client_pid}' | sort)
tmux switch-client -c "$cliente" -t '=origem'
"$TT" --ir-fixada "$cliente" "fx$chave"
[[ $(tmux list-clients -F '#{client_name} #{session_name}' | awk -v c="$cliente" '$1==c {print $2}') == "$ponte_cliente" ]] || falhou 'reinício perdeu ponte ativa'
[[ $(R list-clients -F '#{client_pid}' | sort) == "$antes_clientes" ]] || falhou 'reinício anexou usuário extra'
pre_estado | python3 -c 'import json,sys; assert json.load(sys.stdin)["troca_ms"][-1].get("reutilizada")'
passou 'reinício recupera a mesma ponte por identidade e dono, sem novo cliente remoto'

# Processo morto, mesmo com pane ainda vivo no prompt de reconectar, não é tela pronta.
pid_transporte=$(tmux show-options -qv -t "=$ponte_cliente:" @tt_pre_transport_pid)
kill "$pid_transporte"
transporte_encerrado() { [[ -z $(tmux show-options -qv -t "=$ponte_cliente:" @tt_pre_viva) ]]; }
espera transporte_encerrado
tmux switch-client -c "$cliente" -t '=origem'
"$TT" --ir-fixada "$cliente" "fx$chave"
nova_ponte() {
  local atual
  atual=$(tmux list-clients -F '#{client_name} #{session_name}' | awk -v c="$cliente" '$1==c {print $2}')
  [[ $atual == tt-pre-* && $atual != "$ponte_cliente" ]]
}
espera nova_ponte
passou 'transporte encerrado nunca é reutilizado como tela pronta'

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
