#!/usr/bin/env bash
# Token de dono (dono-tt.py, `tt --dono`) e a biblioteca padrão gerenciada por ele (biblioteca-padrao.json assinado).
# Cobre: assinar e verificar (adulterado, outra chave e sem assinatura não passam); o catálogo que junta o pacote e o
# manifesto do dono (entrada nova, troca, `remover`; manifesto sem assinatura, adulterado, file:// ou mais velho que o
# já aceito é ignorado); só o dono mexe (sem a chave, add/rm/publicar recusam); add recusa texto sem https, sem licença
# ou sem fonte; publicar assina, grava, comita e empurra para o remoto, subindo a versão; rm tira do padrão sem apagar.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
command -v ssh-keygen >/dev/null || { passou 'dono: sem ssh-keygen aqui (pulado)'; exit 0; }
export TT_DONO_TESTE=1
K=$T/chaves; mkdir -p "$K"
ssh-keygen -q -t ed25519 -N '' -C teste -f "$K/dono" && ssh-keygen -q -t ed25519 -N '' -C outro -f "$K/outro"
pub=$(awk '{print $1" "$2}' "$K/dono.pub")
printf 'dono namespaces="tt-dono" %s\n' "$pub" >"$K/allowed"
export TT_DONO_CHAVES=$K/allowed TT_DONO_CHAVE=$K/dono
D() { python3 -I "$TT_DIR/dono-tt.py" "$@"; }

# --- 1. assinar e verificar ---
printf 'conteudo\n' >"$T/a.txt"
D assinar "$T/a.txt" >/dev/null || falhou 'assinar com a chave do dono'
D verificar "$T/a.txt" >/dev/null || falhou 'a assinatura do dono deveria conferir'
printf 'conteudo adulterado\n' >"$T/b.txt"; cp "$T/a.txt.sig" "$T/b.txt.sig"
D verificar "$T/b.txt" >/dev/null 2>&1 && falhou 'arquivo adulterado passou na verificação'
cp "$T/a.txt" "$T/c.txt"; TT_DONO_CHAVE=$K/outro D assinar "$T/c.txt" >/dev/null 2>&1 && falhou 'assinar com chave que não é do dono deveria falhar (não está em dono-chaves)'
ssh-keygen -q -Y sign -f "$K/outro" -n tt-dono "$T/c.txt" 2>/dev/null
D verificar "$T/c.txt" >/dev/null 2>&1 && falhou 'assinatura de outra chave passou'
D verificar "$T/nao-existe.txt" >/dev/null 2>&1 && falhou 'sem arquivo/assinatura deveria falhar'
chmod 644 "$K/dono"; D assinar "$T/a.txt" >/dev/null 2>&1 && falhou 'chave com permissão aberta deveria ser recusada'; chmod 600 "$K/dono"
passou 'dono: assinar e verificar; adulterado, outra chave e sem assinatura não passam'

# --- 2. catálogo = pacote + manifesto assinado ---
AM=$T/am; mkdir -p "$AM"
cat >"$AM/leitor-amostras.json" <<EOF
{"amostras": [
 {"chave": "base-a", "titulo": "Base A", "autor": "X", "url": "https://exemplo.invalid/a.pdf", "mb": 1, "licenca": "dp", "fonte": "https://exemplo.invalid/"},
 {"chave": "base-b", "titulo": "Base B", "autor": "X", "url": "https://exemplo.invalid/b.pdf", "mb": 1, "licenca": "dp", "fonte": "https://exemplo.invalid/"}
]}
EOF
MAN=$AM/biblioteca-padrao.json
manifesto() { # versão  JSON-das-amostras  JSON-do-remover
  printf '{"tipo":"biblioteca-padrao","versao":%s,"emitido":"2026-11-16T00:00:00Z","amostras":%s,"remover":%s}\n' "$1" "$2" "$3" >"$MAN"
  rm -f "$MAN.sig"; D assinar "$MAN" >/dev/null || falhou 'assinar o manifesto'
}
LST() { env TT_LEITOR_DIR="$AM/bib" TT_LEITOR_AMOSTRAS=1 TT_LEITOR_AMOSTRAS_CATALOGO="$AM/leitor-amostras.json" TT_LEITOR_MANIFESTO="$MAN" "$TT" --leitor-amostras "$@"; }
s=$(LST); [[ $s == *base-a* && $s == *base-b* ]] || falhou "catálogo do pacote sem manifesto: $s"
manifesto 1 '[{"chave":"dono-c","titulo":"Dono C","autor":"Y","url":"https://exemplo.invalid/c.pdf","mb":1,"licenca":"dp","fonte":"https://exemplo.invalid/"},{"chave":"base-a","titulo":"Base A nova","url":"https://exemplo.invalid/a2.pdf","mb":1,"licenca":"dp","fonte":"https://exemplo.invalid/"}]' '["base-b"]'
s=$(LST); [[ $s == *dono-c* && $s == *"Base A nova"* && $s != *base-b* ]] || falhou "manifesto do dono não entrou (nova, troca, remover): $s"
est=$(LST estado 2>&1 || true); [[ $est == *"manifesto do dono: v1"* ]] || falhou "estado não mostra o manifesto: $est"
# adulterado: o texto muda, a assinatura é a de antes
sed -i 's/Dono C/Dono C adulterado/' "$MAN"
s=$(LST); [[ $s != *dono-c* && $s == *base-b* ]] || falhou "manifesto adulterado não deveria valer: $s"
est=$(LST estado 2>&1 || true); [[ $est == *IGNORADO* ]] || falhou 'estado deveria dizer que o manifesto foi ignorado'
# sem assinatura
manifesto 1 '[{"chave":"dono-c","titulo":"Dono C","url":"https://exemplo.invalid/c.pdf","mb":1,"licenca":"dp","fonte":"https://exemplo.invalid/"}]' '[]'; rm -f "$MAN.sig"
[[ $(LST) != *dono-c* ]] || falhou 'manifesto sem assinatura valeu'
# file:// e arquivo do pacote não vêm do dono
manifesto 1 '[{"chave":"dono-d","titulo":"D","url":"file:///etc/passwd","mb":1,"licenca":"dp","fonte":"https://exemplo.invalid/"},{"chave":"dono-e","titulo":"E","arquivo":"x.md","licenca":"dp","fonte":"https://exemplo.invalid/"},{"chave":"dono-f","titulo":"F","url":"https://exemplo.invalid/f.pdf","mb":1,"fonte":"https://exemplo.invalid/"}]' '[]'
s=$(LST); [[ $s != *dono-d* && $s != *dono-e* && $s != *dono-f* ]] || falhou "entrada do dono sem https, com arquivo ou sem licença valeu: $s"
# mais velho que o já aceito: ignorado
manifesto 5 '[{"chave":"dono-c","titulo":"Dono C","url":"https://exemplo.invalid/c.pdf","mb":1,"licenca":"dp","fonte":"https://exemplo.invalid/"}]' '[]'
env TT_LEITOR_DIR="$AM/bib" TT_LEITOR_AMOSTRAS=1 TT_LEITOR_AMOSTRAS_CATALOGO="$AM/leitor-amostras.json" TT_LEITOR_MANIFESTO="$MAN" "$TT" --leitor-amostras garantir --quieto >/dev/null 2>&1 || true
grep -q '"manifesto_versao": 5' "$AM/bib/amostras.json" || falhou "garantir não guardou a versão aceita do manifesto: $(cat "$AM/bib/amostras.json")"
manifesto 3 '[{"chave":"dono-g","titulo":"G","url":"https://exemplo.invalid/g.pdf","mb":1,"licenca":"dp","fonte":"https://exemplo.invalid/"}]' '[]'
s=$(LST); [[ $s != *dono-g* ]] || falhou 'manifesto de versão menor que a aceita voltou atrás'
passou 'dono: o catálogo junta pacote e manifesto assinado; adulterado, sem assinatura, file://, sem licença e versão velha são ignorados'

# --- 3. só o dono mexe; add valida; publicar assina, comita e empurra ---
R=$T/repo; REM=$T/remoto.git
git init -q --bare "$REM"; git init -q "$R"; git -C "$R" config user.email t@t; git -C "$R" config user.name t
echo x >"$R/x"; git -C "$R" add x; git -C "$R" commit -q -m inicio; git -C "$R" remote add origin "$REM"; git -C "$R" push -q origin HEAD:main 2>/dev/null; git -C "$R" branch -q -M main 2>/dev/null; git -C "$R" push -q -u origin main 2>/dev/null
cp "$TT_DIR/dono-chaves" "$T/chaves-reais" 2>/dev/null
export TT_REPO=$R XDG_STATE_HOME=$T/estado
BP() { env TT_LEITOR_AMOSTRAS_CATALOGO="$AM/leitor-amostras.json" "$TT" --dono biblioteca "$@"; }
TT_DONO_CHAVE=$K/nao-tenho BP add --url https://x.invalid/a.pdf --licenca dp --fonte https://x.invalid/ --titulo T --sem-testar >/dev/null 2>"$T/err" && falhou 'sem a chave do dono o add passou'
grep -q 'só o dono' "$T/err" || falhou "mensagem de quem não é o dono: $(cat "$T/err")"
BP add --url http://x.invalid/a.pdf --licenca dp --fonte https://x.invalid/ --titulo T --sem-testar >/dev/null 2>&1 && falhou 'http puro foi aceito no padrão'
BP add --url https://x.invalid/a.pdf --fonte https://x.invalid/ --titulo T --sem-testar >/dev/null 2>&1 && falhou 'texto sem licença foi aceito no padrão'
BP add --url https://x.invalid/a.pdf --licenca dp --titulo T --sem-testar >/dev/null 2>&1 && falhou 'texto sem fonte foi aceito no padrão'
BP add --url https://x.invalid/a.pdf --licenca dp --fonte https://x.invalid/ --sem-testar >/dev/null 2>&1 && falhou 'texto sem título foi aceito'
BP add --url https://x.invalid/livro.pdf --licenca "domínio público" --fonte https://x.invalid/ --titulo "Meu Livro Novo" --autor "Fulano" --sem-testar >/dev/null || falhou 'add válido'
BP lista | grep -q 'meu-livro-novo.*dono' || falhou "lista não mostra o rascunho: $(BP lista)"
BP publicar --sim >"$T/pub" 2>&1 || falhou "publicar: $(cat "$T/pub")"
[[ -s $R/biblioteca-padrao.json && -s $R/biblioteca-padrao.json.sig ]] || falhou 'publicar não gravou manifesto e assinatura'
D verificar "$R/biblioteca-padrao.json" >/dev/null || falhou 'o manifesto publicado não confere'
grep -q '"versao": 1' "$R/biblioteca-padrao.json" || falhou 'a primeira publicação deveria ser v1'
[[ $(git -C "$REM" log --oneline main 2>/dev/null | head -1) == *"padrão v1"* ]] || falhou "o push não chegou ao remoto: $(git -C "$REM" log --oneline main 2>&1 | head -2)"
BP rm base-b >/dev/null || falhou 'rm'
BP publicar --sim >/dev/null 2>&1 || falhou 'segunda publicação'
grep -q '"versao": 2' "$R/biblioteca-padrao.json" && grep -q '"base-b"' "$R/biblioteca-padrao.json" || falhou 'a v2 deveria retirar base-b do padrão'
BP publicar --sim >"$T/pub2" 2>&1; grep -q 'nada mudou' "$T/pub2" || falhou "publicar sem mudança deveria avisar: $(cat "$T/pub2")"
passou 'dono: só o dono mexe; add valida https, licença, fonte e título; publicar assina, comita e empurra; rm retira do padrão'
