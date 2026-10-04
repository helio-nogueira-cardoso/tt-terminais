#!/usr/bin/env bash
# Interface real (tmux.conf instalado, cliente anexado): copiar sobre app que captura o mouse,
# central que fecha rápido no Esc mesmo com máquina lenta, pino 📍/📌 e ✕ das fixadas.
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
echo copia_entre_maquinas=0 >>"$XDG_CONFIG_HOME/tt/config"
cat >"$T/app.sh" <<'APP'
printf '\033[?1000h\033[?1002h\033[?1006h'; clear; echo "linha um"; echo "copiar isto ç"; stty -echo raw; cat >/dev/null
APP
tmux -f "$HOME/.tmux.conf" new -d -s app -x 100 -y 20 "bash $T/app.sh" 2>/dev/null
anexar v 100 22 app; sleep 2
[[ $(tmux display -p -t '=app:' '#{mouse_any_flag}') == 1 ]] || falhou 'app de teste não capturou o mouse'
fora send -t v -l $'\e[<0;1;2M\e[<32;8;2M\e[<32;20;2M\e[<0;20;2m'; sleep 1.5
[[ $(tmux show-buffer 2>/dev/null) == "copiar isto"* ]] || falhou "arrastar sobre app com mouse não copiou: '$(tmux show-buffer 2>/dev/null)'"
[[ -n $(ls "$HOME/.cache/tt-copias" 2>/dev/null) ]] || falhou 'cópia não entrou no histórico'
passou 'arrastar copia mesmo sobre app que captura o mouse, e entra no histórico'

# Central com uma máquina que não responde: o Esc fecha o quadro na hora.
printf '192.0.2.1 ninguem lenta\n' >"$XDG_CONFIG_HOME/tt/maquinas"
c=$(tmux list-clients -F '#{client_name}' | head -1)
aberto() { fora capture-pane -p -t v | grep -c '╭'; }
for espera in 0.3 1.5; do
  tmux display-popup -c "$c" -E -w 90% -h 80% "TT_CLIENTE='$c' $TT" & sleep "$espera"
  [[ $(aberto) -ge 1 ]] || falhou 'central não abriu'
  fora send -t v Escape; t0=$(date +%s%N)
  while (( $(aberto) > 0 )); do sleep 0.05; (( ($(date +%s%N) - t0) / 1000000 > 3000 )) && break; done
  ms=$(( ($(date +%s%N) - t0) / 1000000 ))
  (( ms < 1000 )) || falhou "central com máquina lenta levou ${ms} ms para fechar (Esc após ${espera}s)"
  wait 2>/dev/null || true
done
passou "Esc fecha a central em menos de 1 s mesmo com máquina sem resposta"
: >"$XDG_CONFIG_HOME/tt/maquinas"

# Pino da barra (mesma rota do clique) e ✕ da faixa.
tmux run-shell "$TT --clique 'user|fixar' '$c' '' '' 10"; sleep 1
grep -q $'^teste\tapp\t' "$XDG_CONFIG_HOME/tt/fixadas" || falhou '📍 não fixou a sessão atual'
[[ $(tmux show -qv -t '=app:' @tt_fixada) == 1 ]] || falhou 'marca @tt_fixada não acesa'
k=$(tmux show -gqv @barra_fixadas | grep -o 'range=user|fxx[0-9a-f]*' | head -1 | cut -d'|' -f2)
[[ -n $k ]] || falhou 'faixa não tem o ✕ da fixada'
tmux run-shell "$TT --clique 'user|$k' '$c' '' '' 10"; sleep 1
grep -q $'^teste\tapp' "$XDG_CONFIG_HOME/tt/fixadas" && falhou '✕ não desafixou'
[[ -z $(tmux show -qv -t '=app:' @tt_fixada) ]] || falhou 'marca @tt_fixada ficou acesa'
passou 'pino 📍 fixa a sessão atual, ✕ da faixa desafixa, marca acompanha'
