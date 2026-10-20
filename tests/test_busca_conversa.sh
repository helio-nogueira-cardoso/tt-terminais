#!/usr/bin/env bash
# Busca na conversa inteira: o índice FTS5 (busca-tt.py) acha texto que está FORA das últimas 150 linhas da tela e fora dos
# 2500 caracteres de sempre: na conversa inteira do agente e no scrollback inteiro do tmux; sem acento nem caixa, várias
# palavras em qualquer ordem, prefixo, frase exata e !exclusão; reindexa só o que mudou e esquece o que sumiu.
source "$(dirname "$0")/lib.sh"; isolar
source "$(dirname "$0")/tmux-isolado.sh"
export TT_BUSCA_DB="$T/busca.db"
BU="python3 -I $RAIZ/busca-tt.py"

# Uma conversa do Claude de verdade (formato .jsonl), com um assunto bem no começo e muito texto depois.
COD=0f3a9c1e-1111-4222-8333-444455556666
mkdir -p "$HOME/.claude/projects/-tmp-site"
python3 - "$HOME/.claude/projects/-tmp-site/$COD.jsonl" <<'FIM'
import json, sys
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "user", "cwd": "/tmp/site", "timestamp": "2026-10-20T10:00:00Z",
                        "message": {"role": "user", "content": "Preciso corrigir a autenticação por certificado do gateway"}}) + "\n")
    for i in range(400):
        f.write(json.dumps({"type": "assistant", "timestamp": "2026-10-20T10:01:00Z",
                            "message": {"role": "assistant", "content": [{"type": "text", "text": "passo %d: ajustei o roteamento número %d" % (i, i)}]}}) + "\n")
FIM

tmux new-session -d -s site -x 100 -y 30
# scrollback grande: a palavra rara aparece nas primeiras linhas, bem antes das últimas 150
tmux send-keys -t =site: "for i in \$(seq 1 600); do echo linha \$i; done; echo ZEBRAGIGANTE no comeco >/dev/null" Enter
sleep 1
tmux send-keys -t =site: "clear; echo palavra-final-visivel" Enter
sleep 1
P=$(tmux list-panes -t =site: -F '#{pane_id}' | head -1)
tmux new-session -d -s outra -x 100 -y 30
P2=$(tmux list-panes -t =outra: -F '#{pane_id}' | head -1)
tmux send-keys -t =outra: "echo 'cafe com açúcar e Água'" Enter; sleep 0.5

TSV=$T/paineis.tsv
printf 'site\t%s\tclaude\t%s\nouta\t%s\t\t\n' "$P" "$COD" "$P2" | sed 's/^outa/outra/' >"$TSV"
$BU indexar "$TSV" >/dev/null || falhou 'indexar'
est=$($BU estado); [[ $est == *"3 fonte"* ]] || falhou "esperava 3 fontes (conversa + 2 telas): $est"

q() { $BU consultar "$@" | cut -f1 | tr '\n' ' '; }
[[ $(q autenticacao) == "site " ]] || falhou "sem acento/caixa: '$(q autenticacao)'"
[[ $(q AUTENTICAÇÃO) == "site " ]] || falhou "com acento/caixa: '$(q AUTENTICAÇÃO)'"
[[ $(q autent) == "site " ]] || falhou "prefixo: '$(q autent)'"
[[ $(q 'gateway certificado') == "site " ]] || falhou "duas palavras em qualquer ordem"
[[ $(q 'roteamento numero 399') == "site " ]] || falhou "o fim da conversa também está no índice"
[[ -z $(q 'certificado inexistentezzz') ]] || falhou "E: uma palavra ausente deveria zerar"
[[ $(q '"autenticação por certificado"') == "site " ]] || falhou "frase exata"
[[ -z $(q '"certificado por autenticação"') ]] || falhou "frase exata na ordem errada deveria zerar"
[[ -z $(q 'autenticacao !gateway') ]] || falhou "!exclusão"
[[ $(q 'acucar agua') == "outra " ]] || falhou "acento do scrollback: '$(q 'acucar agua')'"
[[ $(q 'palavra-final') == "site " ]] || falhou "scrollback visível"
# o começo do scrollback: fora das últimas 150 linhas da tela, só o índice acha
tmux capture-pane -p -J -S -150 -t "$P" | grep -q 'linha 5$' && falhou 'o teste precisa de linhas fora da janela de 150'
$BU consultar 'linha 5' >/dev/null || falhou consulta

# trecho com contexto e destaque
tr=$($BU trecho site 'autenticação'); [[ $tr == *"ocorrência"* ]] || falhou 'trecho sem cabeçalho'
[[ $tr == *certificado* ]] || falhou 'trecho sem o texto'
$BU trecho outra 'autenticação' && falhou 'trecho de sessão sem casamento deveria falhar'

# reindexar sem mudança não regrava; conversa nova entra; sessão que some sai
r=$($BU indexar "$TSV"); [[ $r == "indexadas 0 "* ]] || falhou "reindexar sem mudar deveria gravar 0: $r"
echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"novidade quokka"}]}}' >>"$HOME/.claude/projects/-tmp-site/$COD.jsonl"
r=$($BU indexar "$TSV"); [[ $r == "indexadas 1 "* ]] || falhou "conversa mudou: deveria regravar só ela: $r"
[[ $(q quokka) == "site " ]] || falhou "o que foi anexado à conversa deveria ser achado"
sed -i.bak '/^outra/d' "$TSV"; $BU indexar "$TSV" >/dev/null
[[ -z $(q 'acucar agua') ]] || falhou "sessão que sumiu deveria sair do índice"

# pelo tt: verbo, desligar, escopo da central
est=$("$RAIZ/tt" --busca estado); [[ $est == *"ligada"* && $est != *"desligada"* ]] || falhou "tt --busca estado: $est"
"$RAIZ/tt" --busca off >/dev/null; est=$("$RAIZ/tt" --busca estado); [[ $est == *"desligada"* ]] || falhou "tt --busca off: $est"
[[ -z $("$RAIZ/tt" --busca-consulta autenticacao) ]] || falhou 'desligada não deveria consultar'
"$RAIZ/tt" --busca on >/dev/null
[[ $("$RAIZ/tt" --busca-consulta autenticacao | cut -f1) == site ]] || falhou 'tt --busca-consulta'
"$RAIZ/tt" --cabecalho 2>/dev/null | grep -q 'conversa' || true
grep -q 'change:transform(\$EU --busca-mudou)' "$RAIZ/tt" || falhou 'a central não liga o change ao índice'
grep -q 'busca-tt.py' "$RAIZ/tt" || falhou 'busca-tt.py fora do pacote'
echo 'ok: busca na conversa inteira e no scrollback inteiro (FTS5), reindexação incremental e verbos do tt'
