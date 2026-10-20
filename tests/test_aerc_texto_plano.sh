#!/usr/bin/env bash
# E-mail em texto simples no aerc: com a seção [filters] só com text/html o aerc mostrava "No filter configured for this mimetype
# ('text/plain')" e tratava o CORPO como um anexo (Open using the system handler / Save to file), enquanto o HTML aparecia bem.
# O tt acrescenta os filtros de fábrica que faltam (text/plain, text/calendar, message/*, .headers) no cadastro e no reparo ao abrir,
# sem tocar num filtro que o dono escolheu.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$HOME/.config/aerc" "$T/bin"
conf=$HOME/.config/aerc/aerc.conf
printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"; export PATH="$T/bin:$PATH"

# roda funções do tt (o pacote copiado por isolar) sem executar nenhum verbo
tt_fn() { (cd / && TT_COMPLETO=1 TT_SO_CARREGAR=1 bash -c 'source "$1/tt"; shift; "$@"' _ "$TT_DIR" "$@"); }
filtro() { sed -n '/^\[filters\]/,/^\[/p' "$conf" | grep -E "^[[:space:]]*$1[[:space:]]*=" | tail -1 | sed "s|^$1[[:space:]]*=[[:space:]]*||"; }

# 1) a configuração que o tt escrevia até a 2.0.1: só text/html
printf '[filters]\ntext/html=! html\n[messages]\nq = :quit<Enter>\n' >"$conf"
tt_fn aerc_filtros_basicos "$conf" || falhou 'deveria ter acrescentado os filtros que faltam'
[[ $(filtro 'text/plain') == *"wrap -w 100"*colorize*linkify* ]] || falhou "text/plain sem wrap | colorize | linkify: $(filtro 'text/plain')"
[[ $(filtro 'text/calendar') == calendar ]] || falhou 'text/calendar'
[[ $(filtro 'message/rfc822') == colorize && $(filtro 'message/delivery-status') == colorize ]] || falhou 'message/*'
[[ $(filtro '\.headers') == colorize ]] || falhou ".headers: $(filtro '\.headers')"
[[ $(filtro 'text/html') == '! html' ]] || falhou 'não pode mexer no filtro HTML'
grep -q '^q = :quit<Enter>$' "$conf" || falhou 'mexeu em outra seção'

# 2) idempotente: segunda vez não muda nada (e avisa que não mudou)
antes=$(cksum <"$conf")
tt_fn aerc_filtros_basicos "$conf" && falhou 'segunda vez não deveria mudar'
[[ $(cksum <"$conf") == "$antes" ]] || falhou 'segunda vez gravou diferente'
[[ $(grep -c '^text/plain=' "$conf") == 1 ]] || falhou 'text/plain duplicado'

# 3) o filtro que o dono escolheu fica
printf '[filters]\ntext/html=! html\ntext/plain=cat\n' >"$conf"
tt_fn aerc_filtros_basicos "$conf" >/dev/null
[[ $(filtro 'text/plain') == cat ]] || falhou "filtro do dono foi trocado: $(filtro 'text/plain')"

# 4) o reparo ao abrir o e-mail conserta (e manda reiniciar o aerc: sai 0) e depois fica quieto (sai 1)
printf '[filters]\ntext/html=! html -o extbrowser=x -o keymap_file=y\n' >"$conf"
tt_fn aerc_reparar_se_preciso 2>/dev/null; rc=$?
[[ $(filtro 'text/plain') == *colorize* ]] || falhou "o reparo não pôs o text/plain (rc=$rc)"
[[ $rc == 0 ]] || falhou "o reparo deveria avisar que mudou (rc=$rc)"
tt_fn aerc_reparar_se_preciso 2>/dev/null && falhou 'reparo repetido não deveria pedir reinício'

# 5) o filtro de verdade: linha comprida é quebrada e o endereço é colorido (só se o aerc estiver instalado com os filtros)
W=""; for c in /opt/homebrew/opt/aerc/libexec/aerc/filters/wrap /usr/libexec/aerc/filters/wrap /usr/lib/aerc/filters/wrap /usr/local/libexec/aerc/filters/wrap; do [[ -x $c ]] && { W=$c; break; }; done
if [[ -n $W ]]; then
  d=${W%/wrap}; linha=$(printf 'palavra %.0s' $(seq 1 40))
  saida=$(printf '%s\n' "$linha" | "$d/wrap" -w 100 | "$d/colorize")
  (($(wc -l <<<"$saida") >= 3)) || falhou "wrap não quebrou a linha comprida em 100 colunas"
fi
echo 'ok: texto simples no aerc: filtros que faltam acrescentados (cadastro e reparo), idempotente, filtro do dono preservado'
