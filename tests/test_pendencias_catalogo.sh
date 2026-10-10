#!/usr/bin/env bash
# Catálogo de pendências: tudo o que o tt pode precisar, por plataforma (Linux x86_64 com GUI, Termux, proot,
# WSL, macOS, musl, ARM), e os instaladores da pasta do usuário: Chrome, Carbonyl (e as bibliotecas que
# pedem), fzf atual, isync com SASL. Tudo com fixtures locais (file://), sem rede e sem tocar no sistema.
source "$(dirname "$0")/lib.sh"; isolar
B=$T/bin; mkdir -p "$B" "$HOME/.config/tt/email"
cat >"$B/apt-get" <<'EOF'
#!/bin/sh
case "$*" in *install*)
  echo "$*" >> "$SUDOLOG"
  [ -n "$TT_FINGE_FALTA_ARQ" ] && : > "$TT_FINGE_FALTA_ARQ"
  [ -n "$LDDARQ" ] && : > "$LDDARQ" ;;
esac
exit 0
EOF
printf '#!/bin/sh\nexec "$@"\n' >"$B/sudo"
printf '#!/bin/sh\necho "  Candidate: 1.0"\n' >"$B/apt-cache"
# ldd/ldconfig/fc-list de mentira: o ldd só acusa o que está em $LDDARQ (o apt-get de mentira esvazia)
cat >"$B/ldd" <<'EOF'
#!/bin/sh
[ -s "$LDDARQ" ] && sed 's/$/ => not found/' "$LDDARQ"
exit 0
EOF
printf '#!/bin/sh\necho "	libgtk-3.so.0 (libc6,x86-64) => /usr/lib/libgtk-3.so.0"\necho "	libvulkan.so.1 (libc6,x86-64) => /usr/lib/libvulkan.so.1"\necho "	libudev.so.1 (libc6,x86-64) => /usr/lib/libudev.so.1"\n' >"$B/ldconfig"
printf '#!/bin/sh\necho "DejaVu Sans"\n' >"$B/fc-list"
for f in aerc vim w3m; do printf '#!/bin/sh\n:\n' >"$B/$f"; done
chmod +x "$B"/*
export SUDOLOG=$T/sudo.log FALTAS=$T/faltas LDDARQ=$T/ldd.txt TT_GERENCIADOR=apt-get TT_PRIV=sudo TT_SO=linux TT_ARCH=x86_64 TT_LIBC=glibc TT_AMBIENTE=nativo
: >"$FALTAS"; : >"$SUDOLOG"
ES=$HOME/.local/state/tt
tt() { PATH="$B:$PATH" TT_FINGE_FALTA_ARQ="$FALTAS" "$TT" "$@" 2>&1; }
estado() { tt --pendencias --tsv | awk -F'\t' -v i="$1" '$1 == i { print $2 }'; }
limpar() { rm -f "$ES"/sudo-recusado-* "$ES"/navegadores-sudo-recusado "$ES"/pendencias-avisadas; rm -rf "$ES/pendencias.trava"; }

# 1) Todos os itens do catálogo respondem, com nome próprio (não o id) e estado válido.
tsv=$(tt --pendencias --tsv)
ids=(nucleo fzf-novo tmux-antigo email-aerc email-sync isync-sasl email-xoauth2 email-html email-editor email-spell chrome carbonyl chrome-libs clipboard notificacoes xdg-utils termux-api pv mosh nomeador-local)
for i in "${ids[@]}"; do
  l=$(awk -F'\t' -v i="$i" '$1 == i' <<<"$tsv"); [[ -n $l ]] || falhou "item $i ausente do catálogo"
  [[ $(cut -f2 <<<"$l") =~ ^(na|ok|falta|manual)$ ]] || falhou "estado inválido de $i: $l"
  [[ $(cut -f4 <<<"$l") != "$i" ]] || falhou "item $i sem nome amigável"
done
out=$(tt --pendencias); grep -q 'Pendências de instalação' <<<"$out" || falhou 'tt --pendencias sem a tela'
passou "catálogo: ${#ids[@]} itens, todos com nome e estado"

# 2) Aplicabilidade por plataforma.
tt_em() { local -a v=(); while [[ $1 != -- ]]; do v+=("$1"); shift; done; shift; env "${v[@]}" PATH="$B:$PATH" TT_FINGE_FALTA_ARQ="$FALTAS" "$TT" "$@" 2>&1; }
est_em() { local i=$1; shift; tt_em "$@" -- --pendencias --tsv | awk -F'\t' -v i="$i" '$1 == i { print $2 }'; }
# Linux nativo x86_64 glibc com tela: navegadores entram (falta baixar).
[[ $(est_em chrome TT_FORCAR_GUI=1 TT_PEND_SEM_NAVEGADORES=) == falta && $(est_em carbonyl TT_FORCAR_GUI=1 TT_PEND_SEM_NAVEGADORES=) == falta ]] || falhou 'Linux x86_64 com tela deveria pedir Chrome e Carbonyl'
# Termux, proot (ARM), macOS, musl, ARM: sem navegadores (binários glibc x86_64).
for cfg in "TT_AMBIENTE=termux TT_GERENCIADOR=pkg TT_ARCH=aarch64 TT_LIBC=bionic" "TT_AMBIENTE=proot TT_ARCH=aarch64" "TT_SO=macos TT_GERENCIADOR=brew" "TT_LIBC=musl TT_GERENCIADOR=apk" "TT_ARCH=aarch64"; do
  # shellcheck disable=SC2086
  [[ $(est_em chrome $cfg TT_FORCAR_GUI=1 TT_PEND_SEM_NAVEGADORES=) == na && $(est_em carbonyl $cfg TT_FORCAR_GUI=1 TT_PEND_SEM_NAVEGADORES=) == na ]] || falhou "navegadores não se aplicam em [$cfg]"
done
# Termux: Termux:API pede o pacote; WSL/macOS/Termux não pedem clipboard/notify-send/xdg-utils do Linux de mesa.
echo "termux-notification" >"$FALTAS"
[[ $(est_em termux-api TT_AMBIENTE=termux TT_GERENCIADOR=pkg TT_ARCH=aarch64 TT_LIBC=bionic) == falta ]] || falhou 'Termux:API deveria faltar no Termux'
[[ $(est_em termux-api) == na ]] || falhou 'Termux:API não se aplica fora do Termux'
: >"$FALTAS"
for amb in wsl termux proot; do
  for i in clipboard notificacoes xdg-utils; do
    [[ $(est_em $i TT_AMBIENTE=$amb TT_FORCAR_GUI=1) == na ]] || falhou "$i não deveria se aplicar em $amb"
  done
done
[[ $(est_em clipboard TT_SO=macos TT_GERENCIADOR=brew TT_FORCAR_GUI=1) == na ]] || falhou 'macOS tem pbcopy: sem clipboard do Linux'
passou 'aplicabilidade: navegadores só em Linux x86_64 glibc (não em Termux/proot/ARM/macOS/musl); Termux:API só no Termux; clipboard/notify/xdg só no Linux de mesa'

# 3) fzf atual: o do sistema é velho → baixa o oficial para ~/.local/share/tt-bin (sha256 conferido).
printf '#!/bin/sh\necho "0.29.0 (abc)"\n' >"$B/fzf"; chmod +x "$B/fzf"
mkdir -p "$T/fz"; printf '#!/bin/sh\necho "0.74.4 (novo)"\n' >"$T/fz/fzf"; chmod +x "$T/fz/fzf"; tar czf "$T/fzf.tgz" -C "$T/fz" fzf
sha=$(sha256sum "$T/fzf.tgz" | cut -d' ' -f1)
[[ $(estado fzf-novo) == falta ]] || falhou "fzf 0.29 deveria pedir o fzf atual: $(estado fzf-novo)"
out=$(tt_em TT_FZF_URL="file://$T/fzf.tgz" TT_FZF_SHA256=0000 -- --pedir-sudo --sim fzf-novo </dev/null) && falhou 'fzf com sha errado deveria falhar'
[[ ! -e $HOME/.local/share/tt-bin/fzf ]] || falhou 'fzf com sha errado foi instalado'
limpar
out=$(tt_em TT_FZF_URL="file://$T/fzf.tgz" TT_FZF_SHA256="$sha" -- --pedir-sudo --sim fzf-novo </dev/null) || falhou "instalar o fzf: $out"
[[ -x $HOME/.local/share/tt-bin/fzf ]] || falhou 'fzf não foi para ~/.local/share/tt-bin'
[[ $(estado fzf-novo) == na ]] || falhou "depois de instalar, o tt deveria usar o fzf novo (PATH): $(estado fzf-novo)"
rm -f "$B/fzf"; rm -rf "$HOME/.local/share/tt-bin"
passou 'fzf antigo → fzf oficial na pasta do usuário (sha256 conferido), que passa na frente no PATH do tt'

# 4) isync sem SASL: o mbsync daqui recusa OAuth → o tt compila um com SASL em ~/.local/share/tt-isync.
printf 'nome=X\nendereco=x@y.z\nauth=oauth\nsync_local=1\n' >"$HOME/.config/tt/email/x.conf"
cat >"$B/mbsync" <<'EOF'
#!/bin/sh
echo "Error: mbsync built without LibSASL; only AuthMech LOGIN is supported." >&2; exit 1
EOF
chmod +x "$B/mbsync"
echo "xoauth2" >"$FALTAS"   # o plugin é outro item; aqui interessa o isync
mkdir -p "$T/inc/sasl" "$T/inc/openssl"; : >"$T/inc/sasl/sasl.h"; : >"$T/inc/openssl/ssl.h"; : >"$T/inc/openssl/md5.h"; : >"$T/inc/zlib.h"
export TT_SASL_INCLUDE=$T/inc
[[ $(estado isync-sasl) == falta ]] || falhou "mbsync sem LibSASL deveria acusar isync-sasl: $(estado isync-sasl)"
mkdir -p "$T/is"; cat >"$T/is/configure" <<'EOF'
#!/bin/sh
for a; do case $a in --prefix=*) p=${a#--prefix=} ;; esac; done
echo "Using SASL"
printf 'all:\n\t@true\ninstall:\n\tmkdir -p %s/bin && printf "#!/bin/sh\\nexit 0\\n" > %s/bin/mbsync && chmod +x %s/bin/mbsync\n' "$p" "$p" "$p" > Makefile
EOF
chmod +x "$T/is/configure"; tar czf "$T/isync.tgz" -C "$T/is" .
isha=$(sha256sum "$T/isync.tgz" | cut -d' ' -f1)
out=$(tt_em TT_ISYNC_URL="file://$T/isync.tgz" TT_ISYNC_SHA256="$isha" -- --pedir-sudo --sim isync-sasl </dev/null) || falhou "compilar o isync com SASL: $out"
[[ -x $HOME/.local/share/tt-isync/bin/mbsync ]] || falhou 'mbsync com SASL não ficou em tt-isync'
[[ $(estado isync-sasl) == ok ]] || falhou "depois de compilar, o isync-sasl deveria estar ok: $(estado isync-sasl)"
grep -q 'isync com SASL' <<<"$out" || falhou "saída sem o nome do item: $out"
rm -rf "$HOME/.local/share/tt-isync" "$B/mbsync"; : >"$FALTAS"
passou 'isync sem LibSASL: detectado por sonda sem rede e substituído por um build com SASL na pasta do usuário'

# 5) A dica no erro do sync: quando o erro é falta de SASL/plugin, diz qual pendência resolve.
mkdir -p "$ES/email-sync"; printf 'Error: mbsync built without LibSASL; only AuthMech LOGIN is supported.\n' >"$ES/email-sync/x.erro"
printf '#!/bin/sh\necho "Error: mbsync built without LibSASL" >&2; exit 1\n' >"$B/mbsync"; chmod +x "$B/mbsync"
out=$(tt --email-sync-estado); grep -q 'tt --pedir-sudo isync-sasl' <<<"$out" || falhou "erro de SASL sem dica da pendência: $out"
printf 'IMAP error: selected SASL mechanism(s) not available;\n   selected: XOAUTH2\n' >"$ES/email-sync/x.erro"
rm -f "$B/mbsync"; printf '#!/bin/sh\nexit 0\n' >"$B/mbsync"; chmod +x "$B/mbsync"
out=$(TT_FINGE_FALTA_ARQ="$FALTAS" PATH="$B:$PATH" TT_FINGE_FALTA=xoauth2 "$TT" --email-sync-estado 2>&1); grep -q 'tt --pedir-sudo email-xoauth2' <<<"$out" || falhou "erro de plugin sem dica da pendência: $out"
rm -f "$B/mbsync" "$ES/email-sync/x.erro"
passou 'erro do sync por falta de SASL/plugin aponta a pendência que resolve'

# 6) Navegadores de verdade (fixtures): Chrome e Carbonyl baixados, conferidos, extraídos; as bibliotecas que
#    o ldd acusa são instaladas na sequência; o resultado é conferido.
python3 - "$T" <<'PY'
import io, tarfile, zipfile, hashlib, os, sys
T = sys.argv[1]
def ar(arquivos):
    out = b"!<arch>\n"
    for nome, dados in arquivos:
        cab = ("%-16s%-12d%-6d%-6d%-8s%-10d`\n" % (nome + "/", 0, 0, 0, "100644", len(dados))).encode()
        out += cab + dados + (b"\n" if len(dados) % 2 else b"")
    return out
def targz(membros):
    b = io.BytesIO()
    with tarfile.open(fileobj=b, mode="w:gz") as t:
        for nome, dados, modo in membros:
            ti = tarfile.TarInfo(nome); ti.size = len(dados); ti.mode = modo; t.addfile(ti, io.BytesIO(dados))
    return b.getvalue()
chrome = b"#!/bin/sh\necho 'Google Chrome de teste'\n"
deb = ar([("debian-binary", b"2.0\n"), ("control.tar.gz", targz([])), ("data.tar.gz", targz([("./opt/google/chrome/chrome", chrome, 0o755)]))])
os.makedirs(T + "/idx/pool", exist_ok=True)
open(T + "/idx/pool/chrome.deb", "wb").write(deb)
sha = hashlib.sha256(deb).hexdigest()
open(T + "/idx/Packages", "w").write("Package: google-chrome-stable\nVersion: 9.9.9-1\nFilename: pool/chrome.deb\nSHA256: %s\n\n" % sha)
zi = zipfile.ZipInfo("carbonyl-0.0.3/carbonyl"); zi.external_attr = 0o755 << 16
with zipfile.ZipFile(T + "/carbonyl.zip", "w") as z: z.writestr(zi, "#!/bin/sh\necho 'Carbonyl de teste'\n")
open(T + "/carbonyl.sha", "w").write(hashlib.sha256(open(T + "/carbonyl.zip", "rb").read()).hexdigest())
PY
NAV=(TT_FORCAR_GUI=1 TT_PEND_SEM_NAVEGADORES= TT_CHROME_INDICE="file://$T/idx/Packages" TT_CHROME_BASE="file://$T/idx" TT_CARBONYL_URL="file://$T/carbonyl.zip" TT_CARBONYL_SHA256="$(cat "$T/carbonyl.sha")")
printf 'libnss3.so\nlibasound.so.2\n' >"$LDDARQ"; : >"$SUDOLOG"; limpar
out=$(tt_em "${NAV[@]}" -- --pedir-sudo --sim chrome carbonyl </dev/null) || falhou "instalar os navegadores: $out"
D=$HOME/.local/share/tt-navegadores
[[ -x $D/chrome/opt/google/chrome/chrome && -x $D/carbonyl/carbonyl-0.0.3/carbonyl ]] || falhou "navegadores não foram extraídos: $out"
[[ $(cat "$D/chrome/versao") == 9.9.9-1 ]] || falhou 'versão do Chrome não registrada'
grep -q 'install libnss3 libasound2$' "$SUDOLOG" || falhou "as bibliotecas que o ldd acusou não foram instaladas: $(cat "$SUDOLOG")"
[[ $(tt_em "${NAV[@]}" -- --pendencias --tsv | awk -F'\t' '$1 ~ /^(chrome|carbonyl|chrome-libs)$/ { print $2 }' | sort -u) == ok ]] || falhou 'depois de instalar, os três deveriam estar ok'
ls -A "$D" | grep -E '\.deb\.|\.zip\.|^\.dl\.' && falhou 'sobraram temporários do download'
passou 'Chrome e Carbonyl: baixados, sha256 conferido, extraídos; bibliotecas do ldd instaladas; tudo ok no catálogo'

# 6b) Sem rede/índice: falha dita, nada pela metade, e o aviso espera.
rm -rf "$D"; limpar
out=$(tt_em "${NAV[@]}" TT_CHROME_INDICE="file://$T/nao-existe" -- --pedir-sudo --sim chrome </dev/null) && falhou 'sem índice do Chrome deveria falhar'
[[ ! -e $D/chrome ]] || falhou 'download que falhou deixou pasta do Chrome'
grep -q '✗' <<<"$out" || falhou "falha sem ✗: $out"
passou 'Chrome sem índice: falha dita, nada pela metade'

# 6c) O download em segundo plano (instalação/atualização) pega o que falta, respeita "não" e não abre modal.
rm -rf "$D"; limpar; mkdir -p "$ES"; echo nunca >"$ES/sudo-recusado-carbonyl"
tt_em "${NAV[@]}" -- --garantir-navegadores >/dev/null
[[ -x $D/chrome/opt/google/chrome/chrome ]] || falhou 'o segundo plano deveria baixar o Chrome'
[[ ! -e $D/carbonyl ]] || falhou 'quem disse "não" ao Carbonyl não pode ter o download em segundo plano'
rm -rf "$D"; limpar; date +%s >"$ES/navegadores-sudo-recusado"   # recusa antiga, de quando era uma pendência só
tt_em "${NAV[@]}" -- --garantir-navegadores >/dev/null
[[ ! -e $D/chrome && ! -e $D/carbonyl ]] || falhou 'a recusa antiga (navegadores-sudo-recusado) deveria valer para os dois'
passou 'segundo plano: baixa o que falta, respeita o "não" por navegador e a recusa antiga'

# 7) nomeador local escolhido e não instalado entra no catálogo.
limpar; printf 'nomeador=local\n' >>"$HOME/.config/tt/config"
[[ $(estado nomeador-local) == falta ]] || falhou 'nomeador=local sem modelo deveria acusar'
passou 'nomeador local escolhido e ainda não baixado aparece como pendência'

# 8) tmux antigo: o tt não instala sozinho, mas diz o que fazer.
out=$(TT_FINGE_TMUX_VERSAO=3.0 tt --pendencias); grep -q 'tmux atual' <<<"$out" && grep -q 'atualize o tmux' <<<"$out" || falhou "tmux antigo sem orientação: $out"
[[ $(TT_FINGE_TMUX_VERSAO=3.0 estado tmux-antigo) == manual ]] || [[ $(TT_FINGE_TMUX_VERSAO=3.0 tt --pendencias --tsv | awk -F'\t' '$1=="tmux-antigo"{print $2}') == manual ]] || falhou 'tmux antigo deveria ser "manual"'
passou 'tmux antigo: pendência manual, com a orientação'

echo "TODOS OS TESTES PASSARAM"
