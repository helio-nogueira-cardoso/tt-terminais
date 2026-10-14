#!/usr/bin/env bash
# Roda do mouse nos chips da barra (tt --rolar, ligado no tmux.conf em WheelUp/DownStatus):
#  - "sessão ▾": a seguinte/anterior desta máquina, na ordem do tmux, dando a volta, sem pontes nem ocultas;
#  - rajada (vários eventos de uma rolagem) anda um passo só;
#  - "máquina ▾": a máquina seguinte na ordem da central, na primeira sessão da lista de lá (por ponte); a que
#    não responde é pulada e lembrada; voltando a esta máquina, a primeira sessão daqui;
#  - vista por ponte: a máquina de lá pede à da tela (tt --rolar-ponte), que troca o aparelho dela.
# Sem rede: o ssh é falso e roda o comando "na outra máquina" aqui mesmo, com outra HOME.
source "$(dirname "$0")/lib.sh"; isolar
O() { fora "$@"; }
B=$T/fb; mkdir -p "$B"
ORIG=$HOME D=$T/dest
mkdir -p "$D/.local/bin" "$D/.config/tt"; ln -s "$TT" "$D/.local/bin/tt"
mkdir -p "$ORIG/.local/bin"; ln -s "$TT" "$ORIG/.local/bin/tt"
cat >"$B/ssh" <<'EOF'
#!/usr/bin/env bash
cmd=${*: -1}; host=""
for a in "$@"; do case $a in *@*-host) host=${a#*@} ;; esac; done
printf '%s %s\n' "$host" "$cmd" >>"$SSH_LOG"
case $host in
  lento-host) sleep 20; exit 255 ;;
  destino-host) H=$DEST ;;
  origem-host) H=$ORIG ;;
  *) exit 255 ;;
esac
exec env HOME="$H" XDG_CONFIG_HOME="$H/.config" TT_RT="$H/rt" bash -c "$cmd"
EOF
chmod +x "$B/ssh"
export PATH=$B:$PATH SSH_LOG=$T/ssh.log DEST=$D ORIG TT_T_ROLAR=1
mkdir -p "$D/rt"
printf 'lento-host helio lenta\ndestino-host helio outra\n' >"$XDG_CONFIG_HOME/tt/maquinas"
printf 'nome=outra\n' >"$D/.config/tt/config"
printf 'origem-host helio teste\n' >"$D/.config/tt/maquinas"

grep -q 'WheelUpStatus .*mouse_status_range},maquina.*mouse_status_range},sessao.*tt --rolar .* -1 .*previous-window' "$RAIZ/tmux.conf" &&
  grep -q 'WheelDownStatus .*tt --rolar .* +1 .*next-window' "$RAIZ/tmux.conf" ||
  falhou 'tmux.conf: a roda em máquina/sessão não chama tt --rolar (ou perdeu o padrão do tmux no resto da barra)'
passou 'tmux.conf: roda em "máquina ▾"/"sessão ▾" vai ao tt; no resto da barra, janela anterior/seguinte'

for s in bb aa cc _oculta; do tmux new -d -s "$s" 'sleep 600'; done
tmux new -d -s zz-ponte 'sleep 600'; tmux set -t =zz-ponte: @ponte x
anexar tela 100 20 aa; sleep 0.8
c=$(tmux list-clients -F '#{client_name}' | head -1)
[[ -n $c ]] || falhou 'cliente de teste não anexou'
sessao_de() { tmux list-clients -F '#{client_name} #{session_name}' | awk -v c="$1" '$1 == c { print $2; exit }'; }
atual() { sessao_de "$c"; }
rolar() { TT_ROLAR_FOLGA=${FOLGA:-0} "$TT" --rolar "$@" "$c"; }

rolar sessao +1;        [[ $(atual) == bb ]] || falhou "aa +1 deveria ir a bb: $(atual)"
rolar 'user|sessao' +1; [[ $(atual) == cc ]] || falhou "bb +1 deveria ir a cc: $(atual)"
rolar sessao +1;        [[ $(atual) == aa ]] || falhou "cc +1 deveria dar a volta em aa (sem _oculta nem a ponte): $(atual)"
rolar sessao -1;        [[ $(atual) == cc ]] || falhou "aa -1 deveria dar a volta em cc: $(atual)"
passou 'sessão: a seguinte/anterior na ordem do tmux, dando a volta, sem pontes nem sessões ocultas'

rolar sessao +1; FOLGA=3000 rolar sessao +1; FOLGA=3000 rolar sessao +1
[[ $(atual) == aa ]] || falhou "rajada deveria andar um passo só (cc → aa): $(atual)"
passou 'sessão: uma rajada de eventos da roda anda um passo só'

# Máquina: daqui (teste) para a seguinte. A lenta não responde em TT_T_ROLAR s: pulada; a outra lista as sessões
# (o mesmo tmux, com a HOME de lá) e a tela vai por ponte para a primeira da lista de lá.
tmux send -t =bb: '' # bb vira a de atividade mais recente
sleep 1.1; tmux new -d -s recente 'echo oi; sleep 600'; sleep 0.5
t0=$SECONDS
rolar maquina +1
s=$(atual); alvo=$(tmux show -qv -t "=$s:" @ponte_alvo)
[[ $alvo == helio@destino-host\|recente ]] || falhou "máquina +1 deveria ir à 1ª sessão da outra (recente) por ponte: sessão=$s alvo=$alvo; ssh: $(cat "$SSH_LOG")"
((SECONDS - t0 <= 6)) || falhou "a máquina que não responde segurou a rolagem por $((SECONDS - t0)) s"
grep -q '^lento-host ' "$SSH_LOG" || falhou 'a lenta nem foi tentada'
passou "máquina: a lenta é pulada em ~${TT_T_ROLAR} s e a tela vai à primeira sessão da seguinte (ponte $s)"

# A lenta fica lembrada: a próxima passada nem tenta (direto, sem esperar). Da outra para trás: lenta (pulada) → esta.
: >"$SSH_LOG"
TT_ROLAR_FOLGA=0 "$TT" --rolar-ponte "$s" outra -1
s2=$(atual)
[[ -z $(tmux show -qv -t "=$s2:" @ponte) && $s2 != _* ]] || falhou "voltando a esta máquina, deveria cair numa sessão daqui: $s2"
[[ $s2 == recente ]] || falhou "esta máquina: deveria ir à primeira sessão da lista (recente): $s2"
grep -q '^lento-host ' "$SSH_LOG" && falhou 'a lenta foi tentada de novo logo depois de falhar'
passou 'máquina: a que falhou há pouco é pulada sem esperar; de volta aqui, a primeira sessão da lista'

# Vista por ponte: o cliente c2 "está na outra máquina" (TT_PONTE=teste|pp no ambiente, como o ssh da ponte) e o
# aparelho de verdade (c3) está na ponte pp daqui. A roda na barra da outra pede a troca à daqui (rolar-ponte), que
# leva c3 (não c2) à máquina seguinte à outra: dando a volta, esta.
tmux new -d -s pp 'sleep 600'; tmux set -t =pp: @ponte helio@destino-host
O new -d -s c3 -x 90 -y 20 "env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t pp"
O new -d -s c2 -x 80 -y 20 "env -u TMUX TT_PONTE='teste|pp' TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t aa"; sleep 0.8
c2=$(tmux list-clients -F '#{client_width} #{client_name}' | awk '$1 == 80 { print $2 }')
c3=$(tmux list-clients -F '#{client_width} #{client_name}' | awk '$1 == 90 { print $2 }')
: >"$SSH_LOG"
HOME=$D XDG_CONFIG_HOME=$D/.config TT_RT=$D/rt TT_ROLAR_FOLGA=0 "$TT" --rolar maquina +1 "$c2"
grep -q '^origem-host .*--rolar-ponte pp outra 1' "$SSH_LOG" || falhou "a outra máquina não pediu a troca à da tela: $(cat "$SSH_LOG")"
[[ $(sessao_de "$c3") == recente ]] || falhou "o aparelho na ponte deveria ir a esta máquina (recente): $(sessao_de "$c3")"
[[ $(sessao_de "$c2") == aa ]] ||
  falhou "o cliente da ponte (o ssh) foi trocado em vez do aparelho: c2=$c2 c3=$c3; $(tmux list-clients -F '#{client_width} #{client_name} #{session_name}' | tr '\n' ' ')"
passou 'ponte: a roda na barra da outra máquina troca o aparelho da tela, na ordem de máquinas da tela'
