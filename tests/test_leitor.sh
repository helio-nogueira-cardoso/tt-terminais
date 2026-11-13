#!/usr/bin/env bash
# Leitor rápido (tt --leitor, leitor-tt.py): uma palavra por vez, no mesmo lugar da tela.
# Cobre: extração de cada formato (txt em Latin-1, md, html, epub, docx, odt, fb2, rtf e pdf com um pdftotext falso:
# cabeçalho e número de página saem, hífen de fim de linha some); biblioteca (mesmo arquivo = mesmo código, posição,
# remover e acrescentar de novo); o quadro (letra de foco sempre na mesma coluna, letras grandes em cada traço,
# palavra que não cabe é partida, pontuação pede mais tempo); a tela num tmux isolado (teclado e toque nos botões,
# posição gravada ao pausar, ajustes, busca, marcador); a troca entre duas máquinas com um ssh falso (texto e
# original chegam, a posição mais nova vence nos dois sentidos, segunda volta não move nada, limite do original e
# --leitor-baixar, remoção que se espalha e não ressuscita, máquina desligada e tt antigo pulados) e um pacote
# adulterado (nome fora da pasta, original com outro conteúdo, texto que não é texto) que não grava nada.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
PY() { python3 -I "$TT_DIR/leitor-tt.py" "$@"; }
BIB=$HOME/.local/share/tt-leitor
F=$T/arquivos; mkdir -p "$F" "$T/bin"

# --- 1. Extração ---------------------------------------------------------------------------------
python3 -I - "$F" <<'PY'
import sys, zipfile, os
d = sys.argv[1]
open(d + "/latin.txt", "wb").write("Capítulo 1\n\nA ação começa aqui, numa linha que-\nbra no meio.\n\nSegundo parágrafo.\n".encode("latin-1"))
open(d + "/nota.md", "w").write("# Título da nota\n\nUm **texto** com [link](http://x.y) e `código`.\n\n## Parte dois\n\n- item um\n- item dois\n")
open(d + "/pagina.html", "w").write("<html><head><title>Página boa</title><style>p{color:red}</style></head><body><nav>menu</nav>"
                                    "<h1>Abertura</h1><p>Primeiro &amp; único.</p><script>alert(1)</script><h2>Depois</h2><p>Fim da página.</p></body></html>")
with zipfile.ZipFile(d + "/livro.epub", "w") as z:
    z.writestr("mimetype", "application/epub+zip")
    z.writestr("META-INF/container.xml", '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
               '<rootfile full-path="OEBPS/c.opf"/></rootfiles></container>')
    z.writestr("OEBPS/c.opf", '<package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata>'
               '<dc:title>O Livro de Teste</dc:title><dc:creator>Fulana de Tal</dc:creator></metadata><manifest>'
               '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
               '<item id="a" href="cap%201.xhtml" media-type="application/xhtml+xml"/><item id="b" href="t/cap2.xhtml" media-type="application/xhtml+xml"/>'
               '</manifest><spine><itemref idref="nav"/><itemref idref="a"/><itemref idref="b"/></spine></package>')
    z.writestr("OEBPS/nav.xhtml", "<html><body><nav><ol><li>sumário que não se lê</li></ol></nav></body></html>")
    z.writestr("OEBPS/cap 1.xhtml", "<html><body><h1>Um começo</h1><p>Era uma vez um epub.</p><p>Com dois parágrafos.</p></body></html>")
    z.writestr("OEBPS/t/cap2.xhtml", "<html><body><h2>Um fim</h2><p>E acabou.</p></body></html>")
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
with zipfile.ZipFile(d + "/doc.docx", "w") as z:
    z.writestr("word/document.xml", '<w:document %s><w:body><w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Seção do Word</w:t></w:r></w:p>'
               '<w:p><w:r><w:t>Texto </w:t></w:r><w:r><w:t>partido em runs.</w:t></w:r></w:p></w:body></w:document>' % W)
    z.writestr("docProps/core.xml", '<cp:coreProperties xmlns:cp="x" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Documento do Word</dc:title></cp:coreProperties>')
with zipfile.ZipFile(d + "/doc.odt", "w") as z:
    z.writestr("content.xml", '<office:document-content xmlns:office="o" xmlns:text="t"><office:body><office:text>'
               '<text:h>Título do Writer</text:h><text:p>Parágrafo do <text:span>Writer</text:span>.</text:p></office:text></office:body></office:document-content>')
open(d + "/conto.fb2", "w").write('<?xml version="1.0"?><FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0"><description><title-info>'
    '<book-title>Conto FB2</book-title></title-info></description><body><section><title><p>Parte única</p></title><p>Texto do conto.</p></section></body>'
    '<binary id="c">QUJD</binary></FictionBook>')
open(d + "/carta.rtf", "wb").write(rb"{\rtf1\ansi{\fonttbl{\f0 Arial;}}\f0 Ol\'e1, mundo.\par Segunda linha com \u231?edilha.\par}")
open(d + "/texto.pdf", "wb").write(b"%PDF-1.4 conteudo de mentira\n")
open(d + "/foto.bin", "wb").write(b"\x00\x01\x02\x03" * 50)
PY
cat >"$T/bin/pdftotext" <<'EOF'
#!/bin/sh
# pdftotext falso: 4 páginas, cabeçalho repetido, número no pé, palavra partida na margem e parágrafo que atravessa a página
printf 'Relatorio Anual\n\nA primeira pagina fala de um as-\nsunto comprido que continua\n\n1\n\f'
printf 'Relatorio Anual\n\nna pagina seguinte, sem ponto final antes.\n\n2\n\f'
printf 'Relatorio Anual\n\nOutro paragrafo inteiro.\n\n3\n\f'
printf 'Relatorio Anual\n\nUltima pagina.\n\n4\n\f'
EOF
chmod +x "$T/bin/pdftotext"; export PATH=$T/bin:$PATH

ex() { "$TT" --leitor-extrair "$F/$1"; }
s=$(ex latin.txt); [[ $s == *"A ação começa aqui, numa linha quebra no meio."* && $s == *"## Capítulo 1"* ]] || falhou "txt latin-1/hífen/capítulo: $s"
s=$(ex nota.md); [[ $s == *"## Título da nota"* && $s == *"Um texto com link e código."* && $s == *"## Parte dois"* && $s == *$'\nitem um\n'* ]] || falhou "md: $s"
s=$(ex pagina.html); [[ $s == "# Página boa"* && $s == *"Primeiro & único."* && $s == *"## Depois"* && $s != *alert* && $s != *menu* && $s != *color* ]] || falhou "html: $s"
s=$(ex livro.epub); [[ $s == "# O Livro de Teste — Fulana de Tal"* && $s == *"## Um começo"* && $s == *"Era uma vez um epub."* && $s == *"## Um fim"* && $s != *sumário* ]] || falhou "epub: $s"
s=$(ex doc.docx); [[ $s == "# Documento do Word"* && $s == *"## Seção do Word"* && $s == *"Texto partido em runs."* ]] || falhou "docx: $s"
s=$(ex doc.odt); [[ $s == *"## Título do Writer"* && $s == *"Parágrafo do Writer."* ]] || falhou "odt: $s"
s=$(ex conto.fb2); [[ $s == "# Conto FB2"* && $s == *"## Parte única"* && $s == *"Texto do conto."* && $s != *QUJD* ]] || falhou "fb2: $s"
s=$(ex carta.rtf); [[ $s == *"Olá, mundo."* && $s == *"Segunda linha com çedilha."* && $s != *Arial* ]] || falhou "rtf: $s"
s=$(ex texto.pdf)
[[ $s == *"A primeira pagina fala de um assunto comprido que continua na pagina seguinte, sem ponto final antes."* ]] || falhou "pdf: parágrafo entre páginas / hífen: $s"
[[ $s != *"Relatorio Anual"* && $s != *$'\n3\n'* && $s == *"Ultima pagina."* ]] || falhou "pdf: cabeçalho ou número de página ficou: $s"
if "$TT" --leitor-extrair "$F/foto.bin" >/dev/null 2>"$T/err"; then falhou 'binário aceito como texto'; fi
grep -q 'formato não reconhecido' "$T/err" || falhou "erro do binário: $(cat "$T/err")"
passou 'extração: txt (Latin-1), md, html, epub, docx, odt, fb2, rtf e pdf (cabeçalho, nº de página e hífen de margem saem); binário recusado'

# --- 2. Biblioteca -------------------------------------------------------------------------------
python3 -I - "$F/conto.txt" <<'PY'
import sys
pal = ["Capítulo", "1", "\n\n"]
pal += "A leitura rápida mostra uma palavra de cada vez, sempre no mesmo lugar. Os olhos ficam parados; extraordinariamente, o cérebro acompanha.".split()
pal += ["\n\n"] + ("palavra " * 300).split() + ["fim."]
pal += ["\n\n", "Capítulo", "2", "\n\n"] + ("outra " * 100).split() + ["acabou."]
open(sys.argv[1], "w").write(" ".join(pal).replace(" \n\n ", "\n\n"))
PY
r=$("$TT" --leitor-add "$F/conto.txt"); ID=${r%%$'\t'*}
[[ $ID =~ ^[0-9a-f]{12}$ && $r == *$'\tconto\tnovo' ]] || falhou "acrescentar: $r"
[[ $ID == "$(sha256sum "$F/conto.txt" | cut -c1-12)" ]] || falhou 'código não é o sha256 do arquivo'
[[ -s $BIB/livros/$ID/texto.json.gz && -s $BIB/livros/$ID/original.txt ]] || falhou 'faltou o texto ou o original na biblioteca'
cmp -s "$F/conto.txt" "$BIB/livros/$ID/original.txt" || falhou 'o original guardado não é o arquivo'
[[ $("$TT" --leitor-add "$F/conto.txt") == *$'\tjá estava' ]] || falhou 'o mesmo arquivo virou outro livro'
IFS=$'\t' read -r l_id l_pct l_pos l_pal l_tit _ <<<"$("$TT" --leitor-listar --tsv)"
[[ $l_id == "$ID" && $l_pct == 0 && $l_pos == 0 && $l_pal == 427 && $l_tit == conto ]] || falhou "listar --tsv: $l_id $l_pct $l_pos $l_pal $l_tit"
[[ $("$TT" --leitor-posicao "$ID" 50% | cut -f1,2) == $'213\t427' ]] || falhou 'posição em %'
[[ $("$TT" --leitor-posicao "${ID:0:5}" | cut -f1) == 213 && $("$TT" --leitor-posicao conto | cut -f1) == 213 ]] || falhou 'prefixo do código / pedaço do título'
[[ $("$TT" --leitor-listar) == *"$ID"*" 49%"*conto* ]] || falhou "listar: $("$TT" --leitor-listar)"
"$TT" --leitor-rm "$ID" >/dev/null; [[ ! -e $BIB/livros/$ID && $(cat "$BIB/lapides.json") == *"$ID"* ]] || falhou 'remover não deixou lápide'
[[ $("$TT" --leitor-listar) == Nenhum* ]] || falhou 'removido ainda listado'
[[ $("$TT" --leitor-add "$F/conto.txt") == *$'\tnovo' && $(cat "$BIB/lapides.json") != *"$ID"* ]] || falhou 'acrescentar de novo não venceu a lápide'
printf 'Texto que veio pelo stdin.\nSegunda linha.\n' | "$TT" --leitor-add - >"$T/stdin.out"
[[ $(cut -f2 "$T/stdin.out") == "Texto que veio pelo stdin." ]] || falhou "stdin: $(cat "$T/stdin.out")"
"$TT" --leitor-rm "$(cut -f1 "$T/stdin.out")" >/dev/null
passou 'biblioteca: código = sha256, mesmo arquivo = mesmo livro, posição (nº, %, prefixo, título), remover e acrescentar de novo, stdin'

# --- 3. O quadro: foco fixo, letras grandes, palavra partida, tempos ------------------------------
campo() { python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d[sys.argv[1]])' "$1"; }
conferir_foco() { # pos → a letra de foco da palavra está na coluna do foco (texto do terminal)
  PY quadro "$ID" --pos "$1" --largura 80 --altura 20 tamanho=1 guia=0 --json | python3 -I -c '
import json, sys
d = json.load(sys.stdin); p = d["texto"]; col = d["foco"]
linha = next(l for l in d["linhas"][1:] if p in l)
i0 = linha.index(p)
n = len(p.rstrip(".,;:!?"))
k = 0 if n <= 1 else 1 if n <= 5 else 2 if n <= 9 else 3 if n <= 13 else 4
assert i0 + k == col, (p, i0, k, col)
print(col)'
}
c1=$(conferir_foco 2); c2=$(conferir_foco 3); c3=$(conferir_foco 19); c4=$(conferir_foco 5)
[[ $c1 == "$c2" && $c2 == "$c3" && $c3 == "$c4" && $c1 == 28 ]] || falhou "a letra de foco mudou de coluna: $c1 $c2 $c3 $c4"
[[ $(PY quadro "$ID" --pos 3 --largura 80 --altura 20 tamanho=1 foco_pos=centro --json | campo foco) == 40 ]] || falhou 'foco no centro'
passou 'foco: a letra em que o olho pousa fica na mesma coluna (à esquerda do centro, ou no centro)'

q=$(PY quadro "$ID" --pos 3 --largura 100 --altura 30 tamanho=6 traco=fino)
[[ $q == *█* && $q == *▛* && $q == *┬* && $q == *┴* ]] || falhou "letras grandes (fino) ou linhas de foco: $q"
coluna() { python3 -I -c 'import sys; l = next(x for x in sys.stdin.read().split("\n") if sys.argv[1] in x); print(l.index(sys.argv[1]))' "$1"; } # em caracteres
col_guia=$(coluna '┬' <<<"$q")
[[ $col_guia == $(PY quadro "$ID" --pos 3 --largura 100 --altura 30 tamanho=6 --json | campo foco) ]] || falhou "marca da linha de foco fora da coluna do foco ($col_guia)"
[[ $(PY quadro "$ID" --pos 3 --largura 100 --altura 30 tamanho=6 traco=pontos) == *[⠁-⣿]* ]] || falhou 'traço pontilhado sem braille'
qb=$(PY quadro "$ID" --pos 3 --largura 100 --altura 30 tamanho=6 traco=blocos); [[ $qb == *▀* && $qb == *▄* && $qb != *▛* ]] || falhou 'traço em blocos'
[[ $(PY quadro "$ID" --pos 3 --largura 100 --altura 30 tamanho=6 traco=cheio) != *[▀▄▛]* ]] || falhou 'traço cheio com meio bloco'
a=$(PY quadro "$ID" --pos 3 --largura 100 --altura 30 fonte=sans); b=$(PY quadro "$ID" --pos 3 --largura 100 --altura 30 fonte=serif)
c=$(PY quadro "$ID" --pos 3 --largura 100 --altura 30 fonte=sans estilo=itálico); d=$(PY quadro "$ID" --pos 3 --largura 100 --altura 30 fonte=sans tamanho=10)
[[ $a != "$b" && $a != "$c" && $a != "$d" ]] || falhou 'fonte, estilo ou tamanho não mudaram o desenho'
[[ $(grep -c '[█▛▜▙▟▌▐▀▄]' <<<"$d") -gt $(grep -c '[█▛▜▙▟▌▐▀▄]' <<<"$a") ]] || falhou 'tamanho 10 não ficou mais alto que o 6'
[[ $(PY fontes | wc -l) -ge 6 ]] || falhou 'atlas com menos de 6 famílias'
passou 'letras grandes: quatro traços, fonte, estilo e tamanho mudam o desenho; a marca das linhas de foco fica na coluna do foco'

# "extraordinariamente," (pos 19) não cabe em 26 colunas com letra grande: encolhe e, sem caber, é partida em pedaços
[[ $(PY quadro "$ID" --pos 19 --largura 26 --altura 20 tamanho=8 --json | campo texto) == extr- ]] || falhou 'palavra longa não foi partida'
[[ $(PY quadro "$ID" --pos 19 --largura 120 --altura 30 tamanho=6 --json | campo texto) == "extraordinariamente," ]] || falhou 'palavra que cabe foi partida'
e_simples=$(PY quadro "$ID" --pos 5 --json | campo espera); e_virgula=$(PY quadro "$ID" --pos 10 --json | campo espera); e_ponto=$(PY quadro "$ID" --pos 14 --json | campo espera)
python3 -I -c 'import sys; a, b, c = map(float, sys.argv[1:]); assert abs(a - 0.2) < 0.001 and a < b < c, (a, b, c)' "$e_simples" "$e_virgula" "$e_ponto" || falhou "tempos: $e_simples $e_virgula $e_ponto"
[[ $(PY quadro "$ID" --pos 5 ppm=600 --json | campo espera) == 0.1 ]] || falhou 'o dobro da velocidade não deu a metade do tempo'
[[ $(PY quadro "$ID" --pos 6 grupo=3 tamanho=1 --json | campo texto) == "uma palavra de" ]] || falhou 'três palavras por vez'
[[ $(PY quadro "$ID" --pos 12 grupo=3 tamanho=1 --json | campo texto) == "no mesmo lugar." ]] || falhou 'o grupo passou do fim da frase'
passou 'palavra que não cabe é partida; vírgula e ponto pedem mais tempo; velocidade e palavras por vez'

# --- 4. A tela, num tmux isolado ------------------------------------------------------------------
X() { tmux -f /dev/null "$@"; }
tela() { X capture-pane -p -t lt; }
espera_tela() { # padrão(egrep) [segundos]
  local i
  for ((i = 0; i < ${2:-10} * 10; i++)); do tela 2>/dev/null | grep -Eq -- "$1" && return 0; sleep 0.1; done
  echo "--- tela ---"; tela || true; falhou "a tela não mostrou: $1"
}
"$TT" --leitor-posicao "$ID" 0 >/dev/null
X new-session -d -s lt -x 100 -y 30 "TT_LEITOR_CORES=256 '$TT' --leitor --tela; echo SAIU=\$?; exec sleep 600"
espera_tela 'Leitor rápido.*1 livro'; espera_tela '▌ conto'
X send-keys -t lt Enter; espera_tela '‖ pausado · 300 ppm'; espera_tela '0% · 1 de 427'
X send-keys -t lt Up; espera_tela 'pausado · 325 ppm'
X send-keys -t lt Space; espera_tela '▶ 325 ppm'; espera_tela '‖ pausar'
espera_tela ' [0-9]+% · ([2-9][0-9]|[1-9][0-9]{2}) de 427' 15   # andou pelo menos umas 20 palavras
X send-keys -t lt Space; espera_tela '‖ pausado'
p1=$("$TT" --leitor-posicao "$ID" | cut -f1); ((p1 >= 15 && p1 < 420)) || falhou "pausar não gravou a posição ($p1)"
espera_tela '(A leitura rápida mostra uma palavra|(palavra ){5})'   # pausado, mostra o trecho do texto em volta
X send-keys -t lt /; espera_tela 'buscar:'; X send-keys -t lt -l 'cerebro'; X send-keys -t lt Enter; espera_tela '“cerebro” em 4%'
X send-keys -t lt b; espera_tela 'marcado: Os olhos ficam parados'
grep -q '"nome": "Os olhos ficam parados' "$BIB/livros/$ID/estado.json" || falhou 'marcador não foi gravado'
X send-keys -t lt o; espera_tela '┌─ ajustes'; espera_tela 'Tamanho da letra .* 6 linhas'
X send-keys -t lt Down Down Left; espera_tela 'Tamanho da letra .* 5 linhas'
X send-keys -t lt Escape; espera_tela '▶ tocar'
grep -q '"tamanho": 5' "$XDG_CONFIG_HOME/tt/leitor.json" && grep -q '"ppm": 325' "$XDG_CONFIG_HOME/tt/leitor.json" || falhou 'preferências não foram gravadas'
X send-keys -t lt i; espera_tela '┌─ índice'; espera_tela '75%  Capítulo 2'; X send-keys -t lt Down Enter; espera_tela 'conto  ·  Capítulo 2'
# toque no botão "‹ 5s": volta 5 segundos de leitura (o toque chega como a sequência de mouse do terminal)
antes=$(tela | grep -Eo '[0-9]+ de 427' | cut -d' ' -f1)
lin=$(tela | grep -n '‹ 5s' | cut -d: -f1); col=$(($(tela | coluna '‹ 5s') + 2))
X send-keys -t lt -l $'\033[<0;'"$col;$lin"'M'; X send-keys -t lt -l $'\033[<0;'"$col;$lin"'m'
espera_tela "‖ pausado"; sleep 0.3
depois=$(tela | grep -Eo '[0-9]+ de 427' | cut -d' ' -f1); ((depois < antes)) || falhou "toque no botão de voltar não voltou ($antes → $depois)"
X send-keys -t lt '?'; espera_tela '┌─ ajuda'; X send-keys -t lt x
X send-keys -t lt q; espera_tela 'Leitor rápido.*1 livro'; espera_tela "lido agora"
X send-keys -t lt q; espera_tela 'SAIU=0'
[[ $("$TT" --leitor-posicao "$ID" | cut -f1) == $((depois - 1)) ]] || falhou "sair não gravou a posição ($("$TT" --leitor-posicao "$ID" | cut -f1) × $((depois - 1)))"
X kill-session -t lt
passou 'tela: abre, toca, pausa e grava a posição; velocidade, busca sem acento, marcador, ajustes, índice, toque no botão, ajuda, sair'

# --- 5. Entre duas máquinas (ssh falso: a outra é um segundo HOME) ---------------------------------
D=$T/dest; mkdir -p "$D/.local/bin" "$D/.config/tt"; ln -s "$TT" "$D/.local/bin/tt"
export DEST=$D SSH_LOG=$T/ssh.log
cat >"$HOME/.local/bin/ssh" <<'EOF'
#!/usr/bin/env bash
cmd=${*: -1}
printf '%s\n' "$cmd" >>"$SSH_LOG"
case ${MODO_SSH:-} in
  antigo) cat >/dev/null 2>&1 </dev/null; echo "tt: opção desconhecida: ${cmd##* } (tt --help mostra as principais)" >&2; exit 2 ;;
esac
exec env HOME="$DEST" XDG_CONFIG_HOME="$DEST/.config" TT_MAQUINA= bash -c "$cmd"
EOF
chmod +x "$HOME/.local/bin/ssh"
printf 'destino-host helio outra\n' >"$XDG_CONFIG_HOME/tt/maquinas"
printf 'nome=outra\n' >"$D/.config/tt/config"
LA() { env HOME="$D" XDG_CONFIG_HOME="$D/.config" "$TT" "$@"; }
export TT_LEITOR_SEM_FUNDO=1 # a troca roda só quando o teste chama (a de segundo plano disputaria a trava)
BIB_D=$D/.local/share/tt-leitor

"$TT" --leitor-posicao "$ID" 40 >/dev/null
s=$("$TT" --leitor-sync)
[[ $s == *"outra        ok"*"levado: livros=0 textos=1 originais=1 recusados=0"* && $s == *"1 de 1 máquinas em dia"* ]] || falhou "1ª troca: $s"
cmp -s "$BIB/livros/$ID/original.txt" "$BIB_D/livros/$ID/original.txt" && cmp -s "$BIB/livros/$ID/texto.json.gz" "$BIB_D/livros/$ID/texto.json.gz" || falhou 'texto ou original não chegou igual'
[[ $(LA --leitor-posicao "$ID" | cut -f1,4) == $'40\tteste' ]] || falhou "posição não chegou lá: $(LA --leitor-posicao "$ID")"
grep -q 'Os olhos ficam parados' "$BIB_D/livros/$ID/estado.json" || falhou 'marcador não chegou lá'
[[ $("$TT" --leitor-sync) == *"0 arquivos trazidos, 0 levados"* ]] || falhou '2ª troca moveu arquivo de novo'
passou 'troca: texto, original, posição e marcador chegam à outra máquina; a 2ª volta não move nada'

sleep 0.05; LA --leitor-posicao "$ID" 200 >/dev/null
"$TT" --leitor-sync >/dev/null
[[ $("$TT" --leitor-posicao "$ID" | cut -f1,4) == $'200\toutra' ]] || falhou "a posição mais nova de lá não veio: $("$TT" --leitor-posicao "$ID")"
sleep 0.05; "$TT" --leitor-posicao "$ID" 90 >/dev/null; "$TT" --leitor-sync >/dev/null
[[ $(LA --leitor-posicao "$ID" | cut -f1,4) == $'90\tteste' ]] || falhou 'a posição mais nova daqui não foi'
# a mais velha nunca desfaz a mais nova: lá fica com um estado antigo forjado e a troca devolve o novo
python3 -I - "$BIB_D/livros/$ID/estado.json" <<'PY'
import json, sys
e = json.load(open(sys.argv[1])); e["pos"], e["mudada"] = 7, e["mudada"] - 100000
json.dump(e, open(sys.argv[1], "w"))
PY
"$TT" --leitor-sync >/dev/null
[[ $("$TT" --leitor-posicao "$ID" | cut -f1) == 90 && $(LA --leitor-posicao "$ID" | cut -f1) == 90 ]] || falhou 'estado antigo desfez o novo'
passou 'posição: a mais nova vence nos dois sentidos e a antiga não a desfaz'

# livro acrescentado lá chega aqui; com limite 0 só o texto vem, e --leitor-baixar traz o original
printf 'leitor_original_max_mb=0\n' >>"$XDG_CONFIG_HOME/tt/config"
r=$(LA --leitor-add "$F/livro.epub"); ID2=${r%%$'\t'*}
"$TT" --leitor-sync >/dev/null
[[ -s $BIB/livros/$ID2/texto.json.gz && ! -e $BIB/livros/$ID2/original.epub ]] || falhou 'o livro de lá não veio em texto (ou o original veio apesar do limite 0)'
[[ $("$TT" --leitor-listar) == *"O Livro de Teste"* && $("$TT" --leitor-estado) == *"$ID2"*"arquivo em: outra"* ]] || falhou "estado sem dizer onde está o original: $("$TT" --leitor-estado)"
[[ $(PY quadro "$ID2" --pos 2 tamanho=1 --json | campo texto) == Era ]] || falhou 'o livro que veio só em texto não abre'
"$TT" --leitor-baixar "$ID2" >/dev/null; cmp -s "$F/livro.epub" "$BIB/livros/$ID2/original.epub" || falhou '--leitor-baixar não trouxe o original'
sed -i.bak '/leitor_original_max_mb/d' "$XDG_CONFIG_HOME/tt/config"
passou 'livro acrescentado na outra máquina chega; limite do original respeitado; --leitor-baixar traz assim mesmo'

"$TT" --leitor-rm "$ID2" >/dev/null; "$TT" --leitor-sync >/dev/null
[[ ! -e $BIB_D/livros/$ID2 && $(cat "$BIB_D/lapides.json") == *"$ID2"* ]] || falhou 'a remoção não chegou à outra máquina'
"$TT" --leitor-sync >/dev/null; [[ ! -e $BIB/livros/$ID2 && $("$TT" --leitor-listar) != *"O Livro de Teste"* ]] || falhou 'livro removido ressuscitou'
passou 'remoção se espalha e o livro não ressuscita'

printf 'leitor_sync=0\n' >>"$D/.config/tt/config"
[[ $("$TT" --leitor-sync) == *"outra        pulada"*"0 de 1 máquinas em dia"* ]] || falhou 'máquina com a troca desligada não foi pulada'
sed -i.bak '/leitor_sync/d' "$D/.config/tt/config"
[[ $(MODO_SSH=antigo "$TT" --leitor-sync) == *"outra        pulada"* ]] || falhou 'tt antigo não foi pulado'
printf 'leitor_sync=0\n' >>"$XDG_CONFIG_HOME/tt/config"
[[ $("$TT" --leitor-sync) == *"desligada nesta máquina"* ]] || falhou 'leitor_sync=0 aqui'
sed -i.bak '/leitor_sync/d' "$XDG_CONFIG_HOME/tt/config"
passou 'máquina desligada (lá e aqui) e tt antigo: pulados, sem erro'

# --- 6. Pacote adulterado ---------------------------------------------------------------------------
python3 -I - "$T/ruim.tar" "$ID" <<'PY'
import gzip, io, json, sys, tarfile, time
saida, lid = sys.argv[1:]
falso = "0123456789ab"
def por(tar, nome, dados):
    i = tarfile.TarInfo(nome); i.size = len(dados); i.mtime = int(time.time()); tar.addfile(i, io.BytesIO(dados))
meta = {"id": falso, "titulo": "Falso", "bytes": 5, "palavras": 2, "adicionada": int(time.time() * 1000), "texto_sha": "0" * 16, "original": "original.txt"}
with tarfile.open(saida, "w") as tar:
    por(tar, "../../fora.txt", b"escapou")
    por(tar, falso + "/../../fora2.txt", b"escapou")
    por(tar, falso + "/meta.json", json.dumps(meta).encode())
    por(tar, falso + "/original", b"nao e o arquivo do codigo")
    por(tar, falso + "/texto.json.gz", gzip.compress(json.dumps({"capitulos": [{"paragrafos": ["texto trocado"]}]}).encode()))
    por(tar, lid + "/original", b"sem meta antes")
PY
r=$(PY aplicar <"$T/ruim.tar")
[[ $r == "livros=0 textos=0 originais=0 recusados=5" ]] || falhou "pacote adulterado: $r"
[[ ! -e $T/fora.txt && ! -e $HOME/fora.txt && ! -e $BIB/fora2.txt && -z $(find "$T" -name 'fora*.txt') ]] || falhou 'o pacote escreveu fora da pasta do livro'
[[ ! -e $BIB/livros/0123456789ab && $("$TT" --leitor-listar) != *Falso* ]] || falhou 'o livro falso entrou na biblioteca'
cmp -s "$F/conto.txt" "$BIB/livros/$ID/original.txt" || falhou 'o original verdadeiro foi trocado'
passou 'pacote adulterado: nada fora da pasta, original só com o sha256 do código, texto só o que a meta descreve'

# --- 7. Leitura na faixa: as palavras passam no lugar do letreiro ------------------------------------
# O motor escreve o roteiro; o letreiro-tt.py (o pintor da faixa) desenha a palavra da vez e os controles e, enquanto
# a leitura estiver ligada, não mostra letreiro nem aviso. Os controles respondem por `tt --leitor-ctl` e pelo clique.
LT() { python3 -I "$TT_DIR/letreiro-tt.py" "$@"; }
BARRA=$HOME/.cache/tt-leitor/barra
limpar_motor() { "$TT" --leitor-parar >/dev/null 2>&1 || true; }
trap 'limpar_motor; limpar_isolado' EXIT
mkdir -p "$HOME/.cache/tt-ticker"; printf 'LETREIRO-DE-TESTE\n' >"$HOME/.cache/tt-ticker/frases"
printf 'indicadores=frases\nfaixa_notif=1\n' >>"$XDG_CONFIG_HOME/tt/config"
[[ $(LT quadro 160) == *LETREIRO-DE-TESTE* ]] || falhou "sem leitura, o letreiro deveria aparecer: $(LT quadro 160)"
"$TT" --leitor-posicao "$ID" 2 >/dev/null
"$TT" --leitor-barra "$ID" --pausado || falhou '--leitor-barra não ligou o motor'
[[ -s $BARRA/roteiro.json && -p $BARRA/ctl ]] && kill -0 "$(cat "$BARRA/pid")" || falhou 'motor sem roteiro, fifo ou processo'
q=$(LT quadro 160)
[[ $q == *'range=user|letreiro'* && $q == *'#[fg=#a6adc8,bold]#[fg=#f38ba8]A#[fg=#a6adc8]'* && $q == *' ▶ '* && $q == *' ✕ '* && $q == *'325'* ]] || falhou "faixa pausada: $q"
[[ $q != *LETREIRO-DE-TESTE* ]] || falhou 'o letreiro apareceu junto com a leitura'
"$TT" --notificar 'AVISO-FRESCO' 60 >/dev/null 2>&1
[[ $(LT quadro 160) != *AVISO-FRESCO* ]] || falhou 'aviso fresco tomou a faixa da leitura'
# a coluna da letra de foco é a mesma para qualquer palavra
foco_col() { LT quadro 160 | python3 -I -c 'import re,sys; l = sys.stdin.read(); i = l.index("#[fg=#f38ba8]"); print(len(re.sub(r"#\[[^\]]*\]", "", l[:i])))'; }
c_a=$(foco_col); "$TT" --leitor-ctl palavra+; sleep 0.3; c_b=$(foco_col); "$TT" --leitor-ctl ir 19; sleep 0.3; c_c=$(foco_col)
[[ $c_a == "$c_b" && $c_b == "$c_c" ]] || falhou "a letra de foco mudou de coluna na faixa: $c_a $c_b $c_c"
[[ $(LT quadro 160) == *extr*a*ordinariamente,* ]] || falhou "ir 19 não mostrou a palavra: $(LT quadro 160)"
"$TT" --leitor-ctl ppm+; sleep 0.3
[[ $(LT quadro 160) == *'350 palavras por minuto'* ]] || falhou 'aviso da velocidade'
grep -q '"ppm": 350' "$XDG_CONFIG_HOME/tt/leitor.json" || grep -q '"ppm": 3[0-9]*' "$XDG_CONFIG_HOME/tt/leitor.json" || falhou 'velocidade não gravada'
# estreita: os controles vão saindo e a palavra fica; sem lugar, o miolo some
q=$(LT quadro 100); [[ $q == *' ▶ '* && $q != *' « '* ]] || falhou "faixa média deveria ter só os controles do meio: $q"
[[ -z $(LT quadro 60) ]] || falhou 'faixa sem lugar deveria ficar vazia'
# tocar: a palavra anda na hora marcada pelo roteiro e a posição é gravada ao pausar
"$TT" --leitor-ctl ir 25; "$TT" --leitor-ctl tocar; sleep 0.3
[[ $(LT quadro 160) == *' ‖ '* && $(LT quadro 160) == *'#[fg=#cdd6f4,bold]'* ]] || falhou "faixa tocando: $(LT quadro 160)"
python3 -I - "$BARRA/roteiro.json" <<'PY' || falhou 'roteiro fora da grade de quadros'
import json, sys
d = json.load(open(sys.argv[1])); fps = d["fps"]; ts = [p[0] for p in d["palavras"]]
assert d["tocando"] and len(ts) > 20 and ts == sorted(ts), ts[:5]
assert all(abs(t * fps - round(t * fps)) < 1e-6 for t in ts), "hora fora da grade"
assert all(b - a >= 1 / fps - 1e-9 for a, b in zip(ts, ts[1:])), "palavra com menos de um quadro"
PY
sleep 2.2; "$TT" --leitor-ctl pausar; sleep 0.3
p_b=$("$TT" --leitor-posicao "$ID" | cut -f1); ((p_b >= 30 && p_b <= 45)) || falhou "em ~2,5 s a 350 ppm deveria andar umas 12 palavras a partir da 25 (ficou em $p_b)"
"$TT" --leitor-ctl curto-; sleep 0.3; "$TT" --leitor-ctl pausar; sleep 0.2
# clique: o pintor grava onde está cada controle; o clique devolve a ação daquele ponto
LT fluxo /dev/null $$ 54 160 10 20 >/dev/null 2>&1 & pintor=$!
for _ in {1..40}; do [[ -s $TT_RT/tt-letreiro-$$.geo ]] && grep -q '"leitor"' "$TT_RT/tt-letreiro-$$.geo" && break; sleep 0.1; done
kill "$pintor" 2>/dev/null || true
x_de() { python3 -I -c 'import json,sys; g = json.load(open(sys.argv[1])); z = next(z for z in g["leitor"] if z[2] == sys.argv[2]); print(g["esq"] + 5 + z[0] + 1)' "$TT_RT/tt-letreiro-$$.geo" "$1"; }
[[ $(LT clique $$ "$(x_de parar)") == $'leitor\tparar' && $(LT clique $$ "$(x_de curto-)") == $'leitor\tcurto-' && $(LT clique $$ "$(x_de ppm+)") == $'leitor\tppm+' ]] || falhou 'clique nos controles da faixa'
rm -f "$TT_RT/tt-letreiro-$$.geo"
# a tela da biblioteca, com faixa: ⏎ manda o texto para a faixa e fecha
"$TT" --leitor-parar; [[ ! -e $BARRA/roteiro.json && ! -e $BARRA/pid ]] || falhou '--leitor-parar deixou o motor'
[[ $(LT quadro 160) == *AVISO-FRESCO* || $(LT quadro 160) == *LETREIRO-DE-TESTE* ]] || falhou "parar não devolveu a faixa: $(LT quadro 160)"
X new-session -d -s lf -x 100 -y 30 "'$TT' --leitor; echo SAIU=\$?; exec sleep 600"
tela() { X capture-pane -p -t lf; }
espera_tela '⏎ ler na faixa'; X send-keys -t lf Enter; espera_tela 'SAIU=0'
[[ -s $BARRA/roteiro.json ]] && grep -q '"tocando": true' "$BARRA/roteiro.json" || falhou '⏎ na biblioteca não pôs a leitura na faixa'
[[ $(X list-keys -T tt-leitor 2>/dev/null | wc -l) -ge 16 ]] || true
"$TT" --leitor-ctl pausar; "$TT" --leitor-parar; X kill-session -t lf
if "$TT" --leitor-ctl tocar 2>"$T/err"; then falhou 'ctl sem leitura deveria falhar'; fi
grep -q 'nenhuma leitura na faixa' "$T/err" || falhou 'mensagem do ctl sem leitura'
grep -q '^    leitor) # leitura na faixa' "$TT_DIR/tt" && grep -q '^bind -T tt-leitor Space run-shell -b "~/.local/bin/tt --leitor-ctl alternar" \\; switch-client -T tt-leitor' "$TT_DIR/tmux.conf" || falhou 'clique do letreiro ou tabela de teclas do leitor'
passou 'faixa: a leitura toma o lugar do letreiro (nem aviso entra), foco em coluna fixa, controles por ctl e clique, grade de quadros, ⏎ da biblioteca, parar devolve a faixa'

# --- 8. Contratos com o tt ---------------------------------------------------------------------------
[[ $("$TT" --help) == *"tt --leitor [ARQ|ID|-]"*"Menu: Enter entra"* ]] || falhou 'tt --help sem o leitor (ou a ajuda perdeu o fim)'
grep -q "^bind L run-shell -b \"~/.local/bin/tt --clique leitor " "$TT_DIR/tmux.conf" || falhou 'Ctrl+B L sem bind'
grep -q '^    leitor) leitor_tecla ' "$TT_DIR/tt" || falhou 'rota leitor do clique()'
grep -q $'^L\t📖 Leitor rápido' "$TT_DIR/tt" || falhou 'item do menu do painel'
[[ -s $TT_DIR/leitor-tt.py && -s $TT_DIR/leitor-fontes.bin ]] || falhou 'o pacote instalado não traz o leitor e o atlas'
[[ $("$TT" --leitor-popup-cmd-teste 2>&1 || true) == *"opção desconhecida"* ]] || falhou 'verbo inexistente não foi recusado'
passou 'contratos: ajuda, Ctrl+B L, rota do clique, item do menu ⋯ e arquivos do pacote'
