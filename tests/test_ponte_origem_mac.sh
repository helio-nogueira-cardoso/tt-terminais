#!/usr/bin/env bash
# Vendo uma máquina de outra (ponte), o clique numa sessão pede à máquina de origem que troque a tela (--ir-ponte). Em
# 17/10/2026, do Mac vendo o Dell: (1) o Tailscale SSH do macOS devolve sempre 0, então o "não" de lá chegava como "sim"
# e o Dell nem abria a ponte daqui; (2) numa rede travada o ssh ficou preso ~2 min sem aviso e os seis cliques chegaram
# juntos ao Mac, trocando a tela seis vezes. Agora vale o "tt-ok" impresso lá, o pedido tem prazo (TT_T_PONTE) com aviso
# na tela, e o pedido atrasado (TT_PRAZO vencido) não troca nada.
# ssh e tmux falsos: o ssh roda o comando "de lá" aqui mesmo e sai sempre 0, como o do Mac.
source "$(dirname "$0")/lib.sh"; isolar
B=$T/bin; mkdir -p "$B"
cat >"$B/tailscale" <<'FIM'
#!/bin/sh
echo '{}'
FIM
cat >"$B/ssh" <<'FIM'
#!/usr/bin/env bash
args=("$@"); i=0
while ((i < ${#args[@]})); do case ${args[i]} in -o) i=$((i + 2)) ;; -*) i=$((i + 1)) ;; *) break ;; esac; done
cmd=${args[*]:i+1}
printf '%s\n' "$cmd" >>"$T/ssh.log"
[[ -e $T/ssh-trava ]] && sleep 30 >/dev/null 2>&1
# o tt "de lá" é um falso que anota e sai com o código de $T/remoto-rc
TT_FALSO_REMOTO=1 bash -c "${cmd//\~\/.local\/bin\/tt/$T/remoto-tt}" >/dev/null 2>&1 &&
  [[ $cmd == *'&& echo tt-ok'* ]] && echo tt-ok
exit 0 # o Tailscale SSH do macOS: sempre 0
FIM
cat >"$B/remoto-tt" <<'FIM'
#!/usr/bin/env bash
printf 'prazo=%s %s\n' "${TT_PRAZO:-}" "$*" >>"$T/remoto.log"
exit "$(cat "$T/remoto-rc" 2>/dev/null || echo 0)"
FIM
mv "$B/remoto-tt" "$T/remoto-tt"
cat >"$B/tmux" <<'FIM'
#!/usr/bin/env bash
printf '%s %s\n' "${TT_FALSO_REMOTO:+[lá]}" "$*" >>"$T/tmux.log"
case ${1:-} in
  has-session) [[ -n ${TT_FALSO_REMOTO:-} ]] && exit "$(cat "$T/remoto-sessao" 2>/dev/null || echo 0)"; exit 1 ;;
  list-clients) if [[ $* == *client_activity* ]]; then echo '100 cliente'; else printf 'cliente\t%s\n' "$(cat "$T/pid")"; fi ;;
esac
exit 0
FIM
chmod +x "$B"/* "$T/remoto-tt"
export T PATH="$B:$TT_PATH_BASE"
printf 'ho u maq-o\n' >"$XDG_CONFIG_HOME/tt/maquinas"

# a tela é uma ponte vinda da maq-o (o cliente tem TT_PONTE no ambiente)
env TT_PONTE='maq-o|ponte-o' sleep 120 &
echo $! >"$T/pid"
trap 'kill "$(cat "$T/pid")" 2>/dev/null' EXIT
clicar() { # na sessão sessao-x da maq-o, vista daqui
  rm -f "$T/ssh.log" "$T/tmux.log" "$T/remoto.log" "$TT_RT"/tt-maquinas-*
  TMUX=tmux-teste TMUX_PANE=%1 TT_SO_CARREGAR=1 bash -c 'source "$1"; TT_CLIENTE=cliente ir_para u@ho sessao-x' _ "$TT"
}
locais() { grep -v '^\[lá\]' "$T/tmux.log" 2>/dev/null; }

# --- a origem troca a tela: nada mais acontece aqui
echo 0 >"$T/remoto-rc"; clicar
grep -q -- "--ir-ponte ponte-o maq-o sessao-x" "$T/remoto.log" || falhou "a origem não recebeu o pedido: $(cat "$T/remoto.log" 2>/dev/null)"
p=$(sed -n 's/^prazo=\([0-9]*\) .*/\1/p' "$T/remoto.log"); agora=$(date +%s)
[[ $p =~ ^[0-9]+$ ]] && ((p > agora && p <= agora + 16)) || falhou "o pedido sem prazo (TT_PRAZO=$p, agora $agora)"
locais | grep -q 'new-session\|switch-client' && falhou "a origem trocou; aqui não pode abrir ponte: $(locais)"

# --- a origem diz que não (o ssh do Mac devolve 0 assim mesmo): abre a ponte daqui
echo 1 >"$T/remoto-rc"; clicar
locais | grep -q 'new-session -d -s maq-o-sessao-x' && locais | grep -q 'switch-client -c cliente -t =maq-o-sessao-x' ||
  falhou "com o não da origem (código 0 pelo ssh), deveria abrir a ponte daqui: $(locais)"

# --- e a sessão que não existe lá também não passa por existente pelo código 0
echo 1 >"$T/remoto-sessao"; clicar || true
locais | grep -q 'não existe mais ou está inacessível' || falhou "sessão que não existe lá: $(locais)"
locais | grep -q 'new-session' && falhou 'abriu ponte para uma sessão que não existe lá'
rm -f "$T/remoto-sessao"
passou 'ponte vinda do Mac: vale o "tt-ok" de lá, não o código de saída do ssh (sempre 0 no Tailscale SSH do macOS)'

# --- a origem não responde (rede travada): avisa que espera, desiste no prazo, não troca nada
echo 0 >"$T/remoto-rc"; touch "$T/ssh-trava"
a=$(date +%s); TT_T_PONTE=3 clicar || true; dt=$(($(date +%s) - a))
rm -f "$T/ssh-trava"
((dt <= 6)) || falhou "o clique ficou preso ${dt}s (prazo de 3 s)"
grep -q 'esperando maq-o (a máquina desta tela) responder' "$T/tmux.log" || falhou "sem o aviso de espera: $(locais)"
grep -q 'maq-o (a máquina desta tela) não respondeu; a tela não trocou' "$T/tmux.log" || falhou "sem o aviso de desistência: $(locais)"
locais | grep -q 'new-session\|switch-client' && falhou "sem resposta da origem, a tela não pode trocar: $(locais)"
passou 'origem que não responde: aviso de espera, desistência no prazo, nenhuma troca'

# --- do lado de lá: o pedido que chega depois do prazo não troca a tela; no prazo, troca
eu=$(TT_SO_CARREGAR=1 bash -c 'source "$1"; echo "$MAQUINA"' _ "$TT")
rm -f "$T/tmux.log"
TMUX=tmux-teste TT_PRAZO=$(($(date +%s) - 1)) "$TT" --ir-ponte ponte-o "$eu" sessao-x || true
[[ ! -s $T/tmux.log ]] || falhou "pedido atrasado mexeu no tmux: $(cat "$T/tmux.log")"
TMUX=tmux-teste TT_PRAZO=$(($(date +%s) + 30)) TT_FALSO_REMOTO=1 "$TT" --ir-ponte ponte-o "$eu" sessao-x
grep -q 'switch-client -c cliente -t =sessao-x' "$T/tmux.log" || falhou "pedido no prazo deveria trocar: $(cat "$T/tmux.log")"
passou 'ir-ponte: pedido que chega depois do prazo (rede travada) não troca a tela; no prazo, troca'
