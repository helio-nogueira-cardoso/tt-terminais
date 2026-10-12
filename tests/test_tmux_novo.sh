#!/usr/bin/env bash
# Pendência "tmux 3.8": o tt compila o tmux oficial na pasta do usuário (DIR_TMUX), liga o executável na frente do
# PATH do tt e em ~/.local/bin, confere o sha256 e NÃO toca no servidor tmux que já roda. Fixtures locais (file://),
# sem rede, sem compilador de verdade e sem tocar no sistema. O configure de mentira exige um yacc, como o real
# ('configure: error: "yacc not found"'), e só há yacc depois que o apt de mentira recebe o bison.
source "$(dirname "$0")/lib.sh"; isolar
unset TT_FINGE_TMUX_VERSAO   # aqui o tmux é o de mentira de $B (3.6), não o fingido pelo lib.sh
B=$T/bin; mkdir -p "$B" "$HOME/.config/tt"
cat >"$B/apt-get" <<'X'
#!/bin/sh
case "$*" in *install*) echo "$*" >> "$SUDOLOG"; [ -n "$TT_FINGE_FALTA_ARQ" ] && : > "$TT_FINGE_FALTA_ARQ"
  case " $* " in *" bison "*) printf '#!/bin/sh\n:\n' > "$FAKEBIN/bison"; chmod +x "$FAKEBIN/bison" ;; esac ;; esac
exit 0
X
printf '#!/bin/sh\nexec "$@"\n' >"$B/sudo"
printf '#!/bin/sh\necho "tmux 3.6"\n' >"$B/tmux"
for c in cc pkg-config; do printf '#!/bin/sh\n:\n' >"$B/$c"; done   # o bison só nasce quando o apt o recebe
# make de mentira: só o "install" faz algo (roda o instalar.sh que o configure de mentira deixou)
printf '#!/bin/sh\ncase "$*" in *install*) sh ./instalar.sh ;; esac\nexit 0\n' >"$B/make"
cp "$B/make" "$B/gmake"   # o tt prefere o gmake: um gmake de verdade no PATH pularia o make de mentira
chmod +x "$B"/*
export SUDOLOG=$T/sudo.log FALTAS=$T/faltas FAKEBIN=$B TT_GERENCIADOR=apt-get TT_PRIV=sudo TT_SO=linux TT_ARCH=x86_64 TT_LIBC=glibc TT_AMBIENTE=nativo
: >"$FALTAS"; : >"$SUDOLOG"
mkdir -p "$T/inc/event2"; : >"$T/inc/event2/event.h"; : >"$T/inc/ncurses.h"; export TT_SASL_INCLUDE=$T/inc
tt_em() { local -a v=(); while [[ $1 != -- ]]; do v+=("$1"); shift; done; shift; env "${v[@]}" PATH="$B:$PATH" TT_FINGE_FALTA_ARQ="$FALTAS" "$TT" "$@" 2>&1; }
estado() { tt_em "${@:2}" -- --pendencias --tsv | awk -F'\t' -v i="$1" '$1 == i { print $2 }'; }

# código "oficial" de mentira: configure + instalar.sh que cria PREFIX/bin/tmux dizendo "tmux 3.8"
mkdir -p "$T/src"; cat >"$T/src/configure" <<'X'
#!/bin/sh
[ -x "$FAKEBIN/bison" ] || { echo 'configure: error: "yacc not found"'; exit 1; }   # como o real
for a; do case $a in --prefix=*) p=${a#--prefix=} ;; esac; done
printf 'mkdir -p %s/bin && printf "#!/bin/sh\\necho tmux 3.8\\n" > %s/bin/tmux && chmod +x %s/bin/tmux\n' "$p" "$p" "$p" > instalar.sh
X
chmod +x "$T/src/configure"; tar czf "$T/tmux.tgz" -C "$T/src" .
sha=$(sha256sum "$T/tmux.tgz" | cut -d' ' -f1)

# 1) tmux 3.6, nada de build instalado: pendência "falta" e pede o grupo de compilação ao gerenciador
[[ $(estado tmux-novo) == na ]] && falhou "tmux 3.6 deveria acusar o tmux-novo"
echo "tmux-build" >"$FALTAS"
[[ $(estado tmux-novo) == falta ]] || falhou "tmux 3.6 sem dependências deveria ser 'falta': $(estado tmux-novo)"
passou "tmux 3.6 vira pendência (rótulo e motivo próprios)"
lista=$(tt_em -- --pendencias); grep -q 'tmux 3.8' <<<"$lista" || falhou "a lista de pendências deveria nomear o tmux 3.8"

# 2) instalar: o gerenciador traz o que falta para compilar e o tt compila na pasta do usuário
out=$(tt_em TT_TMUX_URL="file://$T/tmux.tgz" TT_TMUX_SHA256="$sha" -- --pedir-sudo --sim tmux-novo </dev/null) || falhou "instalar o tmux 3.8: $out"
grep -q 'libevent-dev' "$SUDOLOG" && grep -q 'libncurses-dev' "$SUDOLOG" || falhou "o apt deveria receber libevent-dev e libncurses-dev: $(cat "$SUDOLOG")"
grep -qw 'bison' "$SUDOLOG" || falhou "o apt deveria receber o bison (o configure do tmux 3.8 para sem yacc): $(cat "$SUDOLOG")"
[[ $("$HOME/.local/share/tt-tmux/bin/tmux" -V) == "tmux 3.8" ]] || falhou "o tmux compilado não ficou em tt-tmux: $out"
[[ -L $HOME/.local/share/tt-bin/tmux && -L $HOME/.local/bin/tmux ]] || falhou "o executável deveria ser ligado em tt-bin e ~/.local/bin"
grep -q 'servidor tmux' <<<"$out" || falhou "a saída deveria avisar que o servidor atual não foi tocado: $out"
passou "compila na pasta do usuário, liga o executável e avisa que as sessões abertas não foram tocadas"
# 2b) o tmux do PATH segue o servidor em execução (3.6) mesmo com o 3.8 já compilado: a pendência tem de fechar
[[ $(estado tmux-novo) == na ]] || falhou "com o 3.8 compilado em tt-tmux a pendência deveria fechar: $(estado tmux-novo)"
passou "3.8 compilado fecha a pendência mesmo com o servidor ainda no 3.6"

# 3) já tem o 3.8 (ou mais novo): nada a fazer; 3.2 é assunto do tmux-antigo (manual), não deste
[[ $(estado tmux-novo TT_FINGE_TMUX_VERSAO=3.8) == na ]] || falhou "com tmux 3.8 a pendência não se aplica"
[[ $(estado tmux-novo TT_FINGE_TMUX_VERSAO=3.9) == na ]] || falhou "com tmux 3.9 a pendência não se aplica"
[[ $(estado tmux-novo TT_FINGE_TMUX_VERSAO=3.2) == na ]] || falhou "com tmux 3.2 quem cuida é o tmux-antigo"
passou "3.8+ e 3.2 ficam fora"

# 4) sha256 errado: não instala nada e não deixa lixo
rm -rf "$HOME/.local/share/tt-tmux" "$HOME/.local/share/tt-bin/tmux" "$HOME/.local/bin/tmux"; echo "" >"$FALTAS"
out=$(tt_em TT_TMUX_URL="file://$T/tmux.tgz" TT_TMUX_SHA256=0000 -- --pedir-sudo --sim tmux-novo </dev/null) && falhou "sha256 errado não pode dar certo: $out"
[[ -e $HOME/.local/share/tt-tmux ]] && falhou "falha na compilação não pode deixar tt-tmux pela metade"
grep -q 'tmux 3.8: download, sha256 ou extração falhou' "$HOME/.cache/tt/pendencias.log" ||
  falhou "o motivo da falha deveria ficar no pendencias.log: $(tail -3 "$HOME/.cache/tt/pendencias.log")"
[[ -e $HOME/.local/bin/tmux ]] && falhou "falha não pode ligar o executável"
passou "sha256 errado: nada instalado e nada pela metade"
# 5) o gerenciador diz que instalou, mas o yacc continua faltando (pacote quebrado, PATH): o tt nem tenta
#    compilar, diz o que falta pelo nome (antes: "(tmux-build)") e deixa o motivo no pendencias.log
rm -f "$B/bison" "$HOME/.local/share/tt-bin/tmux" "$HOME/.local/bin/tmux"; : >"$HOME/.cache/tt/pendencias.log"
out=$(tt_em TT_FINGE_FALTA="yacc bison byacc" TT_TMUX_URL="file://$T/tmux.tgz" TT_TMUX_SHA256="$sha" -- --pedir-sudo --sim tmux-novo </dev/null) &&
  falhou "sem yacc a compilação não pode dar certo: $out"
grep -q 'ainda faltam ferramentas (yacc (bison))' <<<"$out" || falhou "a saída deveria dizer que falta o yacc: $out"
grep -q 'tmux 3.8: ainda faltam ferramentas (yacc (bison))' "$HOME/.cache/tt/pendencias.log" ||
  falhou "o motivo deveria ficar no pendencias.log: $(cat "$HOME/.cache/tt/pendencias.log")"
[[ -e $HOME/.local/share/tt-tmux ]] && falhou "sem yacc nada pode ficar instalado"
passou "sem yacc: a mensagem e o pendencias.log dizem o que falta"
echo "TODOS OS TESTES PASSARAM"
