#!/usr/bin/env bash
# Links de e-mail clicáveis: o pós-filtro linkify (email-tt.py) envolve [N] e as URLs da seção
# References em hyperlinks OSC 8, com a URL do escape SEM códigos ANSI (senão o terminal recebe uma
# URL corrompida e o clique cai em "wrong link"). Tolera a saída já colorida pelo filtro colorize
# e reconstrói a URL inteira mesmo quando ela quebraria em várias linhas na tela.
source "$(dirname "$0")/lib.sh"; isolar
PY="$TT_DIR/email-tt.py"

e=$'\033'

# 1) Entrada típica do w3m: corpo com [1]/[2] e seção References.
entrada=$'Veja [1]este e [2]outro.\n\nReferences:\n\n[1] https://ex.com/muito/longo?a=1&b=2\n[2] https://o.com/y\n'
saida=$(printf '%s' "$entrada" | python3 "$PY" linkify)
grep -qF "${e}]8;;https://ex.com/muito/longo?a=1&b=2${e}\\" <<<"$saida" || falhou "URL completa não virou hyperlink OSC 8: $(cat -v <<<"$saida")"
grep -qF "${e}]8;;https://o.com/y${e}\\" <<<"$saida" || falhou "segunda URL não virou hyperlink OSC 8"
passou "linkify envolve [N] e References em OSC 8 com a URL inteira"

# 2) Saída já colorida (colorize antes): a URL dentro do OSC 8 não pode conter ANSI.
col=$'Veja '"$e"'[33m[1]'"$e"'[0mste.\n\n'"$e"'[1;34mReferences:'"$e"'[0m\n\n[1] '"$e"'[4;33mhttps://ex.com/x'"$e"'[0m\n'
saida=$(printf '%b' "$col" | python3 "$PY" linkify)
alvo=$(printf '%s' "$saida" | sed -n 's/.*'"$e"']8;;\(https[^'"$e"']*\).*/\1/p' | head -1)
[[ $alvo == "https://ex.com/x" ]] || falhou "URL do OSC 8 veio corrompida por ANSI: '$(cat -v <<<"$alvo")'"
passou "linkify limpa ANSI de dentro da URL do OSC 8 (robusto após colorize)"

# 3) Sem References: devolve o texto intacto (idempotente, não inventa link).
plano=$'Mensagem simples sem links.\n'
[[ $(printf '%s' "$plano" | python3 "$PY" linkify; printf x) == "${plano}x" ]] || falhou "linkify alterou texto sem links"
passou "linkify não altera mensagem sem links"

# 4) Conversor próprio do tt também lista a URL (para o linkify completar depois).
html=$(printf '<p>Veja <a href="https://ex.com/z">isto</a>.</p>' | python3 "$PY" html)
grep -qF 'https://ex.com/z' <<<"$html" || falhou "conversor html não listou a URL"
passou "conversor html lista a URL na seção de referências"
