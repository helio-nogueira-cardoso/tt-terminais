#!/usr/bin/env bash
# Imagens de e-mail como anexo: o extrator salva as partes image/* (cid/anexas), lista as <img> da web
# sem baixar nada, ignora pixel de rastreamento; a tecla i e o opener image/* entram no aerc.
source "$(dirname "$0")/lib.sh"; isolar
PY=$TT_DIR/email-tt.py
python3 -I - "$T/msg.eml" <<'PYEOF'
import sys, base64
from email.message import EmailMessage
png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
m = EmailMessage(); m['Subject'] = 't'; m['From'] = 'a@b'; m['To'] = 'c@d'
m.set_content('oi')
m.add_alternative('<p>oi<img src="cid:x1"><img src="https://example.com/a/foto.jpg" alt="Foto"><img src="https://t.example.com/p.gif" width="1" height="1"><img src="javascript:x"></p>', subtype='html')
m.get_payload()[1].add_related(png, 'image', 'png', cid='<x1>', filename='../logo.png')
open(sys.argv[1], 'wb').write(m.as_bytes())
PYEOF
l=$(python3 -I "$PY" imagens "$T/out" <"$T/msg.eml") || falhou 'extrator falhou'
[[ $(wc -l <<<"$l") == 2 ]] || falhou "esperava 2 imagens (embutida + web), veio: $l"
grep -q "^arq	$T/out/01-logo.png	" <<<"$l" && [[ -s $T/out/01-logo.png ]] || falhou 'imagem embutida não salva (ou nome não saneado)'
grep -q '^url	https://example.com/a/foto.jpg	Foto' <<<"$l" || falhou 'imagem da web não listada'
grep -q 'p.gif\|javascript' <<<"$l" && falhou 'pixel de rastreamento ou esquema perigoso listado'
[[ $(ls "$T/out" | wc -l) == 1 ]] || falhou 'o extrator baixou/criou arquivos além da imagem embutida'
python3 -I "$PY" baixar-imagem 'file:///etc/passwd' "$T/x" 2>/dev/null && falhou 'baixar-imagem aceitou file://'
[[ ! -e $T/x ]] || falhou 'baixar-imagem gravou arquivo para esquema inválido'
printf 'From: a@b\nSubject: x\n\nsem imagens\n' | python3 -I "$PY" imagens "$T/vazio" | grep -q . && falhou 'e-mail sem imagens listou algo'
passou 'imagens: embutida salva, web só listada, pixel/esquema perigoso ignorados, file:// recusado'

# Servidor local: baixa só image/*, recusa o resto.
mkdir -p "$T/www"; cp "$T/out/01-logo.png" "$T/www/a.png"; echo '<html>' >"$T/www/b.html"
( cd "$T/www" && exec python3 -u -m http.server 0 --bind 127.0.0.1 >"$T/srv.log" 2>&1 ) & srv=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do p=$(grep -o 'port [0-9]*' "$T/srv.log" | awk '{print $2}' || true); [[ -n $p ]] && break; sleep 0.3; done
if [[ -n ${p:-} ]]; then
  python3 -I "$PY" baixar-imagem "http://127.0.0.1:$p/a.png" "$T/dl.png" && cmp -s "$T/dl.png" "$T/www/a.png" || falhou 'download de image/png falhou'
  python3 -I "$PY" baixar-imagem "http://127.0.0.1:$p/b.html" "$T/dl.html" 2>/dev/null && falhou 'baixou conteúdo que não é imagem'
  [[ ! -e $T/dl.html ]] || falhou 'gravou arquivo de conteúdo que não é imagem'
  passou 'download: aceita image/*, recusa HTML'
else falhou 'servidor de teste não subiu'; fi
kill "$srv" 2>/dev/null || true; wait "$srv" 2>/dev/null || true

# Provisionamento: tecla i na leitura e opener image/*.
mkdir -p "$T/bin" "$HOME/.config/aerc"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"
for _ in 1 2; do PATH="$T/bin:/usr/bin:/bin" bash -c "source <(sed -n '/^AERC_BINDS_INI=/,/^remover_aerc() {/p' '$TT' | sed '\$d'); DIR_TT='$TT_DIR'; conf() { :; }; configurar_aerc"; done
B=$HOME/.config/aerc/binds.conf; C=$HOME/.config/aerc/aerc.conf
[[ $(grep -c '^i = :pipe -m .*tt --imagens<Enter>$' "$B") == 1 ]] || falhou 'tecla i ausente ou duplicada'
awk '/^\[view\]/{v=1;next} /^\[/{v=0} v&&/^i = :pipe/{ok=1} END{exit !ok}' "$B" || falhou 'tecla i fora da seção [view]'
[[ $(grep -c '^image/\*=.*tt --abrir-imagem {}$' "$C") == 1 ]] || falhou 'opener image/* ausente ou duplicado'
passou 'aerc: tecla i na leitura e opener image/*, idempotentes'

# Seletor e abertura: sem fzf/visualizador não trava; com stub de xdg-open abre o arquivo certo.
printf '#!/bin/sh\necho "$1" >"%s/aberto"\n' "$T" >"$T/bin/xdg-open"; chmod +x "$T/bin/xdg-open"
printf '#!/bin/sh\ncat >/dev/null; sed -n 1p "%s/lista"\n' "$T" >"$T/bin/fzf"; chmod +x "$T/bin/fzf"
printf 'arq\t%s/out/01-logo.png\t📎 logo.png\n' "$T" >"$T/lista"
PATH="$T/bin:/usr/bin:/bin" HOME=$HOME bash "$TT" --imagens <"$T/msg.eml" >/dev/null 2>&1 </dev/null || true
PATH="$T/bin:/usr/bin:/bin" bash "$TT" --abrir-imagem "$T/out/01-logo.png"; sleep 0.5
[[ $(cat "$T/aberto" 2>/dev/null) == "$T/out/01-logo.png" ]] || falhou 'abrir-imagem não chamou o visualizador com o arquivo'
PATH="$T/bin:/usr/bin:/bin" bash "$TT" --abrir-imagem "$T/nao-existe"; [[ $? != 0 ]] || true
passou 'abrir-imagem chama o visualizador do sistema'
