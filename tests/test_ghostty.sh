#!/usr/bin/env bash
# Ghostty, o terminal padrão do tt: pendência só onde cabe (macOS e Linux com tela), que adiar não cala; bloco de
# configuração no TOPO do arquivo (o que o dono escreve abaixo vence), idempotente e preservando o resto; o
# ~/.bashrc abre o tt numa janela do Ghostty; o tmux liga os recursos do xterm-ghostty.
source "$(dirname "$0")/lib.sh"; isolar
export TT_GHOSTTY_BIN=$T/ghostty-ausente # não herdar o Ghostty real, inclusive /snap/bin
B=$T/bin; mkdir -p "$B"
carrega() { source <(sed -n '/^mac_ghostty_conf() {/,/^}/p;/^GHOSTTY_INI=/,/^# tt --ghostty/p' "$TT"); }

# 1) Configuração: bloco no topo, idempotente, o que o dono escreveu fica (abaixo do bloco).
(
  carrega
  c=$(mac_ghostty_conf)
  [[ $c == "$HOME/.config/ghostty/config.ghostty" || $(uname -s) == Darwin ]] || falhou "arquivo padrão inesperado: $c"
  mkdir -p "${c%/*}"; printf 'font-size = 15\n' >"$c"
  ghostty_configurar forcar; ghostty_configurar forcar
  [[ $(head -1 "$c") == "$GHOSTTY_INI" ]] || falhou 'bloco do tt não está no topo'
  [[ $(grep -cxF "$GHOSTTY_INI" "$c") == 1 ]] || falhou 'bloco duplicado (não idempotente)'
  [[ $(tail -1 "$c") == 'font-size = 15' ]] || falhou 'ajuste do dono sumiu ou não ficou abaixo do bloco'
  grep -qx 'theme = Catppuccin Mocha' "$c" && grep -qx 'macos-option-as-alt = left' "$c" && grep -qx 'shell-integration-features = ssh-env,ssh-terminfo' "$c" || falhou 'bloco sem tema, Option ou ssh'
  rm -f "$c"; ghostty_configurar   # sem Ghostty instalado (e sem forcar) não cria nada
  [[ ! -e $c ]] || falhou 'criou configuração sem o Ghostty instalado'
  # Arquivo antigo (config, sem .ghostty) é o que vale se existir.
  printf 'x = 1\n' >"${c%/*}/config"; [[ $(mac_ghostty_conf) == "${c%/*}/config" || $(uname -s) == Darwin ]] || falhou 'não usou o arquivo config existente'
)
passou 'configuração: bloco do tt no topo, idempotente, ajustes do dono preservados; nada sem o Ghostty'

# 2) Pendência: só onde cabe; Linux com snap = passo de administrador; sem snap = manual; instalado = ok; adiar não cala.
est() { env "$@" PATH="$B:$PATH" TT_PEND_SEM_GHOSTTY= "$TT" --pendencias --tsv 2>/dev/null | awk -F'\t' '$1 == "ghostty" { print $2 }'; }
[[ $(est TT_GHOSTTY_CABE=0) == na ]] || falhou 'Ghostty pedido onde não cabe (WSL/Termux/sem tela)'
printf '#!/bin/sh\nexit 0\n' >"$B/snap"; chmod +x "$B/snap"
if [[ $(uname -s) != Darwin ]]; then
  [[ $(est TT_GHOSTTY_CABE=1 TT_GHOSTTY_BIN=/nao/existe) == falta ]] || falhou 'Linux com tela e snap: Ghostty deveria faltar'
  grep -q 'P_ADM=1; P_ADM_CMD="sudo snap install ghostty --classic"' "$TT" || falhou 'com snap a instalação deveria ser o passo de administrador do snap'
  rm -f "$B/snap"
  [[ $(env PATH="$B:$TT_PATH_BASE" TT_PEND_SEM_GHOSTTY= TT_GHOSTTY_CABE=1 TT_GHOSTTY_BIN=/nao/existe "$TT" --pendencias --tsv 2>/dev/null | awk -F'\t' '$1 == "ghostty" { print $2 }') =~ ^(manual|falta)$ ]] || falhou 'sem snap a pendência sumiu'
fi
printf '#!/bin/sh\n:\n' >"$B/ghostty-falso"; chmod +x "$B/ghostty-falso"
[[ $(est TT_GHOSTTY_CABE=1 TT_GHOSTTY_BIN="$B/ghostty-falso") == ok ]] || falhou 'Ghostty instalado não fecha a pendência'
grep -q '^PEND_SEMPRE=.* ghostty ' "$TT" || falhou 'pendência do Ghostty aceita "nunca"'
passou 'pendência: só onde cabe; snap pelo administrador, manual sem snap, ok instalado; "nunca" não vale'

# 3) Janela do Ghostty entra no tt; as outras regras do ~/.bashrc seguem iguais.
bl=$(sed -n '/^bashrc_bloco() {/,/^BLOCO$/p' "$TT")
grep -q '( -z ${TERM_PROGRAM:-} || ${TERM_PROGRAM:-} == ghostty )' <<<"$bl" && grep -q '|| ${TERM_PROGRAM:-} == ghostty ) ]]' <<<"$bl" || falhou 'bashrc não abre o tt numa janela do Ghostty'
grep -q -- '-z ${SSH_CONNECTION:-}' <<<"$bl" && grep -q -- '-z ${TERMINAL_EMULATOR:-}' <<<"$bl" || falhou 'bashrc perdeu as exclusões (ssh, IDE)'
passou 'bashrc: janela do Ghostty abre no tt, exclusões de ssh e IDE preservadas'

# 4) tmux: recursos do xterm-ghostty sem perder os anteriores.
f=$(grep '^set -s terminal-features' "$TT_DIR/tmux.conf")
grep -q 'xterm-ghostty:RGB:extkeys:usstyle:overline:strikethrough' <<<"$f" && grep -q 'xterm-256color:RGB:extkeys' <<<"$f" && grep -q 'xterm\*:sync:hyperlinks' <<<"$f" || falhou "terminal-features sem o Ghostty ou sem os de antes: $f"
passou 'tmux: cores reais, teclas estendidas e sublinhados no Ghostty; recursos anteriores intactos'

# 5) Larguras: os 9 emojis de mão e de pessoa sem seletor ocupam 1 coluna, como no Ghostty (o tmux dava 2 e a linha
#    andava para a esquerda no terminal); com o seletor de emoji seguem 2. Medido no tmux com o tmux.conf do tt.
if tmux -V | awk '{v=$2+0; exit !(v >= 3.5)}'; then
  tmux -f /dev/null new -d -s larg -x 40 -y 5 'sleep 60' 2>/dev/null || falhou 'tmux de teste não subiu'
  grep '^set -sq codepoint-widths' "$TT_DIR/tmux.conf" >"$T/larg.conf" && tmux source-file "$T/larg.conf"
  for par in "☝ 1" "🕵 1" "🖐 1" "☝️ 2" "🖐️ 2" "👍 2"; do
    set -- $par
    tmux respawn-pane -k -t larg "printf '%s' '$1'; sleep 30"
    x=; for _ in $(seq 1 20); do sleep 0.05; x=$(tmux display -p -t larg '#{cursor_x}'); [[ $x != 0 ]] && break; done
    [[ $x == "$2" ]] || falhou "$1 ocupa $x colunas no tmux com o tmux.conf do tt, não $2"
  done
  tmux kill-session -t larg
  passou 'tmux: ☝ ✌ 🕵 🖐 sem seletor com 1 coluna (como o Ghostty), com o seletor 2'
fi
