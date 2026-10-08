#!/usr/bin/env bash
# Escolha do navegador para links (tt --abrir-link): chave navegador=, queda para o navegador do
# sistema sem terminal/tmux ou no Termux, e instalação sob demanda que recusa pacote com sha256 errado.
source "$(dirname "$0")/lib.sh"; isolar
B=$T/bin; mkdir -p "$B"
LOG=$T/xdg.log
printf '#!/bin/sh\necho "$1" >> %s\n' "$LOG" >"$B/xdg-open"; chmod +x "$B/xdg-open"
export PATH="$B:$PATH"
U=https://exemplo.com/muito/longo?a=1
cfg() { printf 'nome=teste\n%s\n' "$1" >"$XDG_CONFIG_HOME/tt/config"; }

# 1) navegador=sistema chama o abridor do sistema com a URL inteira.
cfg navegador=sistema; : >"$LOG"
"$TT" --abrir-link "$U" </dev/null; sleep 0.3
[[ $(cat "$LOG") == "$U" ]] || falhou "sistema não recebeu a URL inteira: '$(cat "$LOG")'"
passou "navegador=sistema: xdg-open recebe a URL inteira"

# 2) perguntar sem terminal e sem tmux: não trava, cai no navegador do sistema.
cfg navegador=perguntar; : >"$LOG"
timeout 10 "$TT" --abrir-link "$U" </dev/null; sleep 0.3
[[ $(cat "$LOG") == "$U" ]] || falhou "perguntar sem tty/tmux deveria cair no sistema: '$(cat "$LOG")'"
passou "perguntar sem terminal nem tmux: cai no navegador do sistema"

# 3) No Termux (termux-open-url presente) as opções gráficas não existem: mesmo com navegador=chromium usa o sistema.
printf '#!/bin/sh\nexit 0\n' >"$B/termux-open-url"; chmod +x "$B/termux-open-url"
cfg navegador=chromium; : >"$LOG"
"$TT" --abrir-link "$U" </dev/null; sleep 0.3
[[ $(cat "$LOG") == "$U" ]] || falhou "Termux deveria usar o sistema: '$(cat "$LOG")'"
rm -f "$B/termux-open-url"
passou "Termux: opções gráficas ocultas, usa o sistema"

# 4) .deb do Chrome com sha256 diferente do índice é recusado e nada é instalado.
mkdir -p "$T/repo/pool"; echo falso >"$T/repo/pool/chrome.deb"
printf 'Package: google-chrome-stable\nVersion: 1.0-1\nFilename: pool/chrome.deb\nSHA256: %064d\n' 0 >"$T/repo/Packages"
cfg navegador=chromium; : >"$LOG"
saida=$(TT_CHROME_INDICE="file://$T/repo/Packages" TT_CHROME_BASE="file://$T/repo" "$TT" --abrir-link "$U" </dev/null 2>&1)
grep -q 'sha256' <<<"$saida" || falhou "não avisou sha256 divergente: $saida"
[[ ! -e $HOME/.local/share/tt-navegadores/chrome ]] || falhou "instalou pacote com sha256 errado"
passou "instalação do Chrome recusa .deb com sha256 divergente do índice"

# 5) Caminho feliz: .deb válido (ar + data.tar.xz) com sha256 certo no índice instala sem dpkg-deb.
python3 -I - "$T/repo/pool/chrome.deb" <<'PY'
import sys, tarfile, io
def ar_membro(nome, dados):
    cab = "%-16s%-12s%-6s%-6s%-8s%-10s`\n" % (nome + "/", "0", "0", "0", "100644", len(dados))
    return cab.encode() + dados + (b"\n" if len(dados) % 2 else b"")
bio = io.BytesIO()
with tarfile.open(fileobj=bio, mode="w:xz") as t:
    d = b"#!/bin/sh\necho chrome\n"; ti = tarfile.TarInfo("./opt/google/chrome/chrome"); ti.size = len(d); ti.mode = 0o755
    t.addfile(ti, io.BytesIO(d))
open(sys.argv[1], "wb").write(b"!<arch>\n" + ar_membro("debian-binary", b"2.0\n") + ar_membro("data.tar.xz", bio.getvalue()))
PY
sha=$(sha256sum "$T/repo/pool/chrome.deb" | cut -d' ' -f1)
printf 'Package: google-chrome-stable\nVersion: 9.9-1\nFilename: pool/chrome.deb\nSHA256: %s\n' "$sha" >"$T/repo/Packages"
PATH="$B:/usr/bin:/bin" TT_CHROME_INDICE="file://$T/repo/Packages" TT_CHROME_BASE="file://$T/repo" "$TT" --abrir-link "$U" </dev/null >/dev/null 2>&1 || true
[[ -x $HOME/.local/share/tt-navegadores/chrome/opt/google/chrome/chrome && $(cat "$HOME/.local/share/tt-navegadores/chrome/versao") == 9.9-1 ]] ||
  falhou "não instalou o .deb válido (ou dependeu do dpkg-deb)"
passou "instalação do Chrome extrai o .deb com python3 e registra a versão"

echo "TODOS OS TESTES PASSARAM"
