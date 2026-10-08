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
    ln = tarfile.TarInfo("./etc/cron.daily/google-chrome"); ln.type = tarfile.SYMTYPE; ln.linkname = "/opt/google/chrome/cron/google-chrome"; t.addfile(ln)
open(sys.argv[1], "wb").write(b"!<arch>\n" + ar_membro("debian-binary", b"2.0\n") + ar_membro("data.tar.xz", bio.getvalue()))
PY
sha=$(sha256sum "$T/repo/pool/chrome.deb" | cut -d' ' -f1)
printf 'Package: google-chrome-stable\nVersion: 9.9-1\nFilename: pool/chrome.deb\nSHA256: %s\n' "$sha" >"$T/repo/Packages"
PATH="$B:/usr/bin:/bin" TT_CHROME_INDICE="file://$T/repo/Packages" TT_CHROME_BASE="file://$T/repo" "$TT" --abrir-link "$U" </dev/null >/dev/null 2>&1 || true
[[ -x $HOME/.local/share/tt-navegadores/chrome/opt/google/chrome/chrome && $(cat "$HOME/.local/share/tt-navegadores/chrome/versao") == 9.9-1 ]] ||
  falhou "não instalou o .deb válido (ou dependeu do dpkg-deb)"
passou "instalação do Chrome extrai o .deb com python3 e registra a versão"

# 6) tt --garantir-navegadores (usado em máquina nova e em atualização): instala o Chrome sem clique, uma vez.
rm -rf "$HOME/.local/share/tt-navegadores"
saida=$(PATH="$B:/usr/bin:/bin" TT_FORCAR_GUI=1 TT_CARBONYL_URL="file://$T/falso.zip" TT_CHROME_INDICE="file://$T/repo/Packages" TT_CHROME_BASE="file://$T/repo" "$TT" --garantir-navegadores 2>&1)
[[ -x $HOME/.local/share/tt-navegadores/chrome/opt/google/chrome/chrome ]] || falhou "garantir-navegadores não instalou o Chrome: $saida"
[[ ! -d $HOME/.local/share/tt-navegadores.lock ]] || falhou "travou: lock não liberado"
passou "garantir-navegadores pré-instala o Chrome e libera o lock"

# 7) Sem ambiente gráfico o Chrome é pulado (servidor sem tela não baixa 150 MB à toa).
rm -rf "$HOME/.local/share/tt-navegadores"
if [[ ! -d /mnt/wslg && -z ${DISPLAY:-} && -z ${WAYLAND_DISPLAY:-} && ! -d /tmp/.X11-unix ]]; then
  PATH="$B:/usr/bin:/bin" TT_CARBONYL_URL="file://$T/falso.zip" TT_CHROME_INDICE="file://$T/repo/Packages" TT_CHROME_BASE="file://$T/repo" "$TT" --garantir-navegadores >/dev/null 2>&1
  [[ ! -e $HOME/.local/share/tt-navegadores/chrome ]] || falhou "baixou o Chrome sem ambiente gráfico"
  passou "sem ambiente gráfico: Chrome pulado"
fi

# 8) A instalação/atualização dispara a pré-instalação (máquina nova e já instalada).
grep -q 'garantir_navegadores_em_segundo_plano; echo "$(conf nome): $(versao) (já instalada)"' "$RAIZ/tt" &&
  grep -B2 'echo "$(conf nome): $(versao)"$' "$RAIZ/tt" | grep -q garantir_navegadores_em_segundo_plano ||
  falhou "instalar_aqui não dispara a pré-instalação nos dois caminhos"
passou "instalar_aqui dispara a pré-instalação (já instalada e instalação nova)"

# 9) Modal do sudo: mostra as pendências e o comando; recusar não roda sudo e grava a recusa.
printf '#!/bin/sh\n:\n' >"$B/apt-get"; chmod +x "$B/apt-get"
printf '#!/bin/sh\necho "$@" >> %s/sudo.log\n' "$T" >"$B/sudo"; chmod +x "$B/sudo"
printf r >"$T/resposta"; : >"$T/sudo.log"
rc=0; saida=$(PATH="$B:$PATH" TT_TTY="$T/resposta" TT_FINGE_FALTA="curl unzip" "$TT" --pedir-sudo 2>&1) || rc=$?
(( rc != 0 )) || falhou "recusa deveria sair com erro"
grep -q 'sudo apt-get install -y curl unzip' <<<"$saida" || falhou "resumo sem o comando exato: $saida"
grep -q 'não a vê' <<<"$saida" || falhou "resumo não explica quem pede a senha: $saida"
[[ ! -s $T/sudo.log ]] || falhou "rodou sudo apesar da recusa"
[[ -s $HOME/.local/state/tt/navegadores-sudo-recusado ]] || falhou "recusa não foi gravada"
saida=$(PATH="$B:$PATH" TT_TTY="$T/resposta" TT_FINGE_FALTA="curl unzip" "$TT" --pedir-sudo 2>&1)
grep -q 'Nada pendente' <<<"$saida" || falhou "recusado há pouco deveria dar 'Nada pendente': $saida"
passou "modal do sudo: resumo com o comando exato; recusa não roda sudo e é lembrada por 7 dias"

# 10) Aceitar tudo roda exatamente o comando mostrado, com sudo (que pede a senha ele mesmo).
rm -f "$HOME/.local/state/tt/navegadores-sudo-recusado"
printf a >"$T/resposta"; : >"$T/sudo.log"
PATH="$B:$PATH" TT_TTY="$T/resposta" TT_FINGE_FALTA="curl unzip" "$TT" --pedir-sudo >/dev/null 2>&1 || falhou "aceite deveria sair com sucesso"
[[ $(cat "$T/sudo.log") == "apt-get install -y curl unzip" ]] || falhou "sudo rodou outra coisa: '$(cat "$T/sudo.log")'"
passou "modal do sudo: aceitar tudo roda sudo apt-get install -y com os pacotes do resumo"

echo "TODOS OS TESTES PASSARAM"
