#!/usr/bin/env bash
# Integridade de anexos: falha parcial/disco cheio, colisão, retomada, .eml e imagens inline.
source "$(dirname "$0")/lib.sh"; isolar
python3 "$RAIZ/tests/test_anexos_integridade.py" "$T/pkg/email-tt.py" || falhou 'integridade dos anexos'
passou 'anexos preservados em falhas; EML e imagens inline mantêm conteúdo'

# Fluxo do tt: retomar pelo caminho anunciado, sem consumir stdin ao descobrir a tela.
fn() { TT_SO_CARREGAR=1 bash -c 'source "$1"; shift; dest_da_tela() { :; }; "$@"' _ "$TT" "$@"; }
base=$HOME/.cache/tt-anexos
mkdir -p "$base/salvar"
printf 'conteudo' >"$base/salvar/arquivo.pdf"
printf 'bloqueio' >"$T/nao-e-pasta"
if printf '%s\n' "$T/nao-e-pasta" | fn anexo_salvar >"$T/falha.log" 2>&1; then falhou 'falha de gravação retornou sucesso'; fi
lote=$(find "$base" -type d -name arquivos)
[[ -n $lote && $(cat "$lote/arquivo.pdf") == conteudo ]] || falhou 'anexo desapareceu na falha'
grep -q -- '--anexo-salvar' "$T/falha.log" || falhou 'não explicou como retomar'
printf '%s\n' "$T/recebidos" | fn anexo_salvar "$lote" || falhou 'retomada falhou'
[[ $(cat "$T/recebidos/arquivo.pdf") == conteudo && ! -e $lote ]] || falhou 'retomada perdeu conteúdo ou não retirou lote vazio'
mkdir -p "$T/pasta-arbitraria"
fn anexo_salvar "$T/pasta-arbitraria" >/dev/null 2>&1 && falhou 'aceitou retomar pasta arbitrária'
passou 'falha de destino devolve erro e retomada explícita conserva o conteúdo'

mkdir -p "$base/atual" "$T/bin"
printf 'oculto' >"$base/atual/.anexo.txt"
printf '#!/bin/sh\nexit 130\n' >"$T/bin/fzf"; chmod +x "$T/bin/fzf"
PATH="$T/bin:$PATH" fn anexos_enviar >"$T/cancelar.log" 2>&1 && falhou 'cancelamento retornou sucesso'
lote=$(find "$base" -type d -name arquivos)
[[ $(cat "$lote/.anexo.txt") == oculto ]] || falhou 'cancelar apagou o anexo'
mkdir -p "$base/atual"; printf 'outro' >"$base/atual/outro.pdf"
outro=$(fn anexos_lote atual)
[[ $outro != "$lote" && -f $outro/outro.pdf && -f $lote/.anexo.txt ]] || falhou 'lotes colidiram'
passou 'cancelar seleção preserva anexos ocultos; lotes simultâneos têm nomes distintos'
