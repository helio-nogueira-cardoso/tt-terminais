#!/usr/bin/env bash
# Ordem do letreiro: sequencial (uma fonte depois da outra) ou aleatória, que MISTURA as entradas de todas as fontes
# (não só a ordem delas). A mistura é estável: o mesmo instante dá a mesma roda, e quando uma fonte atualiza as
# entradas das outras ficam onde estavam (o letreiro não pula no meio da rolagem). No painel: linha "🔀 Ordem",
# tecla ^o e `tt --letreiro-ordem-ciclar` alternam sequencial ⇄ aleatória.
source "$(dirname "$0")/lib.sh"; isolar
D="$T/pkg/letreiro-tt.py"
CACHE="$HOME/.cache/tt-ticker"; mkdir -p "$CACHE"

# três fontes de três linhas cada, escritas direto no cache que o desenhista lê
for f in a b c; do printf '%s1\n%s2\n%s3\n' "${f^^}" "${f^^}" "${f^^}" >"$CACHE/$f"; done
cat >"$CACHE/_roda.json" <<'J'
{"itens":[{"nome":"a","peso":1,"cache_max":0,"se_faltar":"ultimo"},{"nome":"b","peso":1,"cache_max":0,"se_faltar":"ultimo"},{"nome":"c","peso":1,"cache_max":0,"se_faltar":"ultimo"}]}
J

roda() { # ORDEM [INSTANTE] → a roda como "A1 B2 …" (separador " • " trocado por espaço)
  python3 -I - "$D" "${1:-}" "${2:-1790000000}" <<'PY'
import importlib.util, sys
sp = importlib.util.spec_from_file_location("lt", sys.argv[1]); lt = importlib.util.module_from_spec(sp); sp.loader.exec_module(lt)
cfg = {"ticker_ordem": sys.argv[2]} if sys.argv[2] else {}
r = lt.montar_roda(cfg, float(sys.argv[3]))
print(" ".join("".join(c for c, _e in r.cel[i:f]) for i, f, _n, _l in r.segs))
PY
}
SEQ='A1 A2 A3 B1 B2 B3 C1 C2 C3'

# 1) sequencial (padrão) e "manual", o nome antigo, saem na ordem das fontes
[[ $(roda) == "$SEQ" ]] || falhou "padrão deveria ser sequencial: $(roda)"
[[ $(roda sequencial) == "$SEQ" ]] || falhou "sequencial: $(roda sequencial)"
[[ $(roda manual) == "$SEQ" ]] || falhou "manual (nome antigo) deveria seguir sequencial: $(roda manual)"
passou 'sequencial é o padrão; "manual" (nome antigo) continua valendo'

# 2) aleatória: as mesmas 9 entradas, misturadas ENTRE as fontes (não 3 blocos inteiros trocados de lugar)
mistura_ok() { # roda → 0 se alguma fonte aparece quebrada em pedaços
  python3 -I -c '
import sys
t = sys.argv[1].split()
fontes = [x[0] for x in t]
blocos = sum(1 for i, f in enumerate(fontes) if i == 0 or fontes[i - 1] != f)
sys.exit(0 if blocos > 3 else 1)' "$1"
}
achou=0
for h in 0 1 2 3 4 5 6 7; do   # cada hora sorteia uma ordem; em alguma delas as fontes têm de estar intercaladas
  a=$(roda aleatoria $((1790000000 + h * 3600)))
  [[ $(tr ' ' '\n' <<<"$a" | sort | paste -sd' ') == "$SEQ" ]] || falhou "aleatória perdeu ou repetiu entradas: $a"
  mistura_ok "$a" && achou=$((achou + 1))
done
((achou >= 6)) || falhou "aleatória deveria intercalar as fontes na maioria das horas (intercalou em $achou de 8)"
passou "aleatória: as mesmas entradas, misturadas entre as fontes ($achou de 8 horas intercaladas)"

# 3) estável: o mesmo instante dá a mesma roda; a hora seguinte, outra
[[ $(roda aleatoria 1790000000) == $(roda aleatoria 1790000100) ]] || falhou 'dois instantes da mesma hora deveriam dar a mesma roda'
[[ $(roda aleatoria 1790000000) != $(roda aleatoria 1790003600) ]] || falhou 'a hora seguinte deveria sortear outra ordem'
passou 'aleatória: estável dentro da hora, outra ordem na hora seguinte'

# 4) uma fonte atualiza: as entradas das outras não mudam de lugar (nada de pulo na rolagem)
antes=$(roda aleatoria | tr ' ' '\n' | grep -v '^B')
printf 'B1\nB2\nB3\nB4\nB5\n' >"$CACHE/b"
depois=$(roda aleatoria | tr ' ' '\n' | grep -v '^B')
[[ $antes == "$depois" ]] || falhou "a atualização da fonte b mexeu na ordem das outras: $antes // $depois"
[[ $(roda aleatoria | tr ' ' '\n' | grep -c '^B') == 5 ]] || falhou 'as 5 entradas novas da fonte b deveriam aparecer'
passou 'aleatória: atualizar uma fonte não muda a ordem das entradas das outras'

# 5) o painel: ⏎/^o alternam sequencial ⇄ aleatória, gravando ticker_ordem no config desta máquina
"$T/pkg/tt" --letreiro-lista 2>/dev/null | grep '^@ord' | grep -q 'Ordem: sequencial' || falhou 'a linha da ordem deveria dizer sequencial'
"$T/pkg/tt" --letreiro-ordem-ciclar
grep -q '^ticker_ordem=aleatoria$' "$XDG_CONFIG_HOME/tt/config" || falhou 'ciclar deveria gravar ticker_ordem=aleatoria'
"$T/pkg/tt" --letreiro-lista 2>/dev/null | grep '^@ord' | grep -q 'Ordem: aleatória' || falhou 'a linha da ordem deveria dizer aleatória'
"$T/pkg/tt" --letreiro-ordem-ciclar
grep -q '^ticker_ordem=' "$XDG_CONFIG_HOME/tt/config" && falhou 'voltar ao sequencial deveria apagar a chave (padrão)'
[[ $("$T/pkg/tt" --letreiro-acao enter @ord) == *letreiro-ordem-ciclar* ]] || falhou '⏎ na linha da ordem deveria alternar'
[[ $("$T/pkg/tt" --letreiro-acao ordem x) == *letreiro-ordem-ciclar* ]] || falhou '^o deveria alternar'
grep -q 'ctrl-o:transform(\$a ordem' "$RAIZ/tt" || falhou '^o não está ligado no fzf do painel'
printf 'ticker_ordem=peso\n' >>"$XDG_CONFIG_HOME/tt/config"
"$T/pkg/tt" --letreiro-ordem-ciclar
grep -q '^ticker_ordem=' "$XDG_CONFIG_HOME/tt/config" && falhou 'de "peso" o ciclar deveria voltar ao sequencial'
passou 'painel: linha 🔀 Ordem, ⏎ e ^o alternam sequencial ⇄ aleatória (peso volta ao sequencial)'
