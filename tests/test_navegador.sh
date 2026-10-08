#!/usr/bin/env bash
# Escolha do navegador para links (tt --abrir-link): chave navegador=, queda para o navegador do
# sistema sem terminal/tmux ou no Termux, e instalação sob demanda que recusa pacote com sha256 errado.
source "$(dirname "$0")/lib.sh"; isolar
B=$T/bin; mkdir -p "$B"
LOG=$T/xdg.log
printf '#!/bin/sh\necho "$1" >> %s\n' "$LOG" >"$B/xdg-open"; chmod +x "$B/xdg-open"
export PATH="$B:$PATH"
U=https://exemplo.com/muito/longo?a=1
cfg() { printf 'nome=teste\n%s\n' "$1" >"$XDG_CONFIG_HOME/tt/config"; }

# 1) navegador=sistema chama o abridor do sistema com a URL inteira.
cfg navegador=sistema; : >"$LOG"
"$TT" --abrir-link "$U" </dev/null; sleep 0.3
[[ $(cat "$LOG") == "$U" ]] || falhou "sistema não recebeu a URL inteira: '$(cat "$LOG")'"
passou "navegador=sistema: xdg-open recebe a URL inteira"

# 2) perguntar sem terminal e sem tmux: não trava, cai no navegador do sistema.
cfg navegador=perguntar; : >"$LOG"
timeout 10 "$TT" --abrir-link "$U" </dev/null; sleep 0.3
[[ $(cat "$LOG") == "$U" ]] || falhou "perguntar sem tty/tmux deveria cair no sistema: '$(cat "$LOG")'"
passou "perguntar sem terminal nem tmux: cai no navegador do sistema"

# 3) No Termux (termux-open-url presente) as opções gráficas não existem: mesmo com navegador=chromium usa o sistema.
printf '#!/bin/sh\nexit 0\n' >"$B/termux-open-url"; chmod +x "$B/termux-open-url"
cfg navegador=chromium; : >"$LOG"
"$TT" --abrir-link "$U" </dev/null; sleep 0.3
[[ $(cat "$LOG") == "$U" ]] || falhou "Termux deveria usar o sistema: '$(cat "$LOG")'"
rm -f "$B/termux-open-url"
passou "Termux: opções gráficas ocultas, usa o sistema"

# 4) Pacote com sha256 errado é recusado e nada é instalado.
echo falso >"$T/falso.txt"; (cd "$T" && zip -q falso.zip falso.txt)
cfg navegador=chromium; : >"$LOG"
saida=$(TT_CHROMIUM_URL="file://$T/falso.zip" "$TT" --abrir-link "$U" </dev/null 2>&1)
grep -q 'sha256' <<<"$saida" || falhou "não avisou sha256 divergente: $saida"
[[ ! -e $HOME/.local/share/tt-navegadores/chromium ]] || falhou "instalou pacote com sha256 errado"
passou "instalação recusa pacote com sha256 divergente"

echo "TODOS OS TESTES PASSARAM"
