#!/usr/bin/env bash
# tt_largura mede como o tmux: a barra, a faixa de fixadas, a barra do e-mail e o mapa de clique dos cabeçalhos usam
# essa conta para saber onde cada coisa cai. Ela errava nos dois sentidos (⚡ ⏳ ☰ ✅ contavam 1, 🖥 🗑 🕰 contavam 2,
# ZWJ, tom de pele e acento decomposto somavam colunas) e o toque podia cair no botão vizinho. Cada amostra é
# impressa num painel do tmux (com o tmux.conf do tt: ☝ e companhia valem 1) e a coluna do cursor tem de bater.
source "$(dirname "$0")/lib.sh"; isolar
tmux -V | awk '{v=$2+0; exit !(v >= 3.6)}' || { passou 'tmux < 3.6: sem agrupamento de grafemas, nada a medir'; exit 0; }
source <(sed -n '/^tt_largura() {/,/^}/p' "$TT")
TT_UTF8=$(locale -a 2>/dev/null | grep -i -m1 -E '^(C|en_US)\.utf-?8$'); TT_UTF8=${TT_UTF8:-en_US.UTF-8}
amostras=(
  'ab' '📋 ab' '☰ terminais' '⚡ Em lote' '📧 (430) ⏳' '✅ ok' '⭐' '❌' '♿' '⌚'
  '🖥 máquinas' '🗑' '🕰2022' '🌡' '⚙ tmux' '⚙️ tmux' '✏️ Atalhos' '✉ x' '☑ Tudo' '↩ Responder'
  '❤️' '❤' '⚠️ aviso' '👍🏽' '👨‍👩‍👧' '🏃‍♀️' '👩‍💻' '🇧🇷 Brasil' '1️⃣' '🏳️‍🌈'
  "$(printf 'e\xcc\x81')" '日本語' '한국어' 'ＡＢ' '☝ mão' '✌️' '🕵 x' '🇦🇷 Peso arg.' 'x▸ y ✕' '🔀 Ordem'
)
tmux -f /dev/null new -d -s m -x 80 -y 5 'sleep 120' 2>/dev/null || falhou 'tmux de teste não subiu'
grep '^set -sq codepoint-widths' "$TT_DIR/tmux.conf" >"$T/larg.conf" && tmux source-file "$T/larg.conf"
erros=()
for s in "${amostras[@]}"; do
  printf '%s' "$s" >"$T/amostra"
  tmux respawn-pane -k -t m "cat '$T/amostra'; sleep 30"
  x=; for _ in $(seq 1 30); do sleep 0.05; x=$(tmux display -p -t m '#{cursor_x}'); [[ $x != 0 ]] && break; done
  tt_largura "$s"
  [[ $W == "$x" ]] || erros+=("[$s] tt=$W tmux=$x")
done
tmux kill-server 2>/dev/null
((${#erros[@]} == 0)) || falhou "tt_largura diferente do tmux: ${erros[*]}"
passou "tt_largura igual ao tmux em ${#amostras[@]} amostras (emoji de texto e de figura, ZWJ, tom de pele, bandeira, keycap, CJK)"
