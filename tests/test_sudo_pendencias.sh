#!/usr/bin/env bash
# Modal único de pendências: reúne tudo o que falta (ferramentas básicas, e-mail, bibliotecas do Chrome…),
# com instalar agora / selecionar / mais tarde / não instalar (nunca mais avisa); id explícito reabre mesmo
# recusado; --sim aceita tudo sem terminal; nomes de pacote por gerenciador (mbsync → isync); a instalação
# é conferida depois (o que não ficou pronto é dito, e não incomoda toda hora); uma instalação por vez.
source "$(dirname "$0")/lib.sh"; isolar
B=$T/bin; mkdir -p "$B" "$HOME/.config/tt/email"
# gerenciador de mentira: registra o que "instala" e esvazia as listas de faltas (como se tivesse instalado)
cat >"$B/apt-get" <<'EOF'
#!/bin/sh
case "$*" in *install*)
  [ -n "$APTFALHA" ] && { echo "E: Unable to locate package" >&2; exit 100; }
  echo "$*" >> "$SUDOLOG"
  [ -n "$TT_FINGE_FALTA_ARQ" ] && : > "$TT_FINGE_FALTA_ARQ"
  [ -n "$TT_FINGE_CHROME_LIBS_ARQ" ] && : > "$TT_FINGE_CHROME_LIBS_ARQ" ;;
esac
exit 0
EOF
printf '#!/bin/sh\nexec "$@"\n' >"$B/sudo"
printf '#!/bin/sh\necho "  Candidate: 1.0"\n' >"$B/apt-cache"
for f in aerc vim; do printf '#!/bin/sh\n:\n' >"$B/$f"; done   # presentes: só o que o teste manda faltar falta
chmod +x "$B"/*
printf 'nome=X\nendereco=x@y.z\n' >"$HOME/.config/tt/email/x.conf" # com conta, mbsync/w3m entram
export SUDOLOG=$T/sudo.log FALTAS=$T/faltas TT_GERENCIADOR=apt-get TT_PRIV=sudo TT_SO=linux TT_AMBIENTE=nativo
ES=$HOME/.local/state/tt
roda() { PATH="$B:$PATH" TT_TTY="$T/resposta" TT_FINGE_FALTA_ARQ="$FALTAS" "$TT" --pedir-sudo "$@" 2>&1; }
limpar() { rm -f "$ES"/sudo-recusado-* "$ES"/navegadores-sudo-recusado "$ES"/pendencias-avisadas; rm -rf "$ES/pendencias.trava"; }

# 1) Tudo pendente aparece junto, num comando só, com os nomes de pacote certos; recusar não roda nada.
echo "curl mbsync w3m" >"$FALTAS"; printf r >"$T/resposta"; : >"$SUDOLOG"
saida=$(roda) || true
grep -q 'ferramentas básicas' <<<"$saida" && grep -q 'mbsync (isync)' <<<"$saida" && grep -q 'w3m' <<<"$saida" ||
  falhou "modal não reuniu as três pendências: $saida"
grep -q 'sudo apt-get install -y curl isync w3m' <<<"$saida" || falhou "comando agregado errado: $saida"
grep -q 'Debian\|Linux\|·' <<<"$saida" || falhou 'o modal deveria dizer qual é a plataforma'
[[ ! -s $SUDOLOG ]] || falhou 'recusar rodou o gerenciador'
[[ -s $ES/sudo-recusado-nucleo && -s $ES/sudo-recusado-email-sync && -s $ES/sudo-recusado-email-html ]] || falhou 'recusa não foi gravada por item'
grep -q 'Nada pendente' <<<"$(roda)" || falhou 'recusado há pouco voltou a ser oferecido'
passou 'pendências reunidas num comando só (isync pelo mbsync); recusa por item, lembrada (n = nunca mais avisar)'

# 2) Id explícito reabre mesmo recusado (o usuário pediu pela interface) e instala só aquilo.
printf a >"$T/resposta"; : >"$SUDOLOG"
roda email-sync >/dev/null || falhou 'aceitar id explícito deveria instalar'
grep -q 'install curl\|install.* curl' "$SUDOLOG" && falhou "id explícito instalou outra coisa: $(cat "$SUDOLOG")"
grep -q 'install isync$' "$SUDOLOG" || falhou "id explícito não instalou o isync: $(cat "$SUDOLOG")"
passou 'id explícito ignora a recusa e instala só o pedido'

# 3) Selecionar: aceita o 1º item, recusa os demais; instala só o aceito.
limpar; echo "curl mbsync w3m" >"$FALTAS"; printf ssnn >"$T/resposta"; : >"$SUDOLOG"
roda >/dev/null || falhou 'selecionar com um aceite deveria sair com sucesso'
grep -q 'install curl$' "$SUDOLOG" || falhou "selecionar instalou outra coisa: $(cat "$SUDOLOG")"
[[ ! -s $ES/sudo-recusado-nucleo ]] || falhou 'item aceito foi marcado como recusado'
[[ $(cat "$ES/sudo-recusado-email-sync") == nunca && $(cat "$ES/sudo-recusado-email-html") == nunca ]] || falhou 'itens recusados com n deveriam virar "nunca"'
passou 'selecionar: instala só o aceito e grava a resposta dos demais'

# 4) Bibliotecas do Chrome/Carbonyl entram, com tradução por gerenciador; a instalação é conferida.
limpar; : >"$FALTAS"; echo "libnss3.so libnspr4.so" >"$T/libs"; printf a >"$T/resposta"; : >"$SUDOLOG"
saida=$(TT_FINGE_CHROME_LIBS_ARQ="$T/libs" roda chrome-libs) || falhou "aceitar chrome-libs deveria instalar: $saida"
grep -q 'install libnss3 libnspr4$' "$SUDOLOG" || falhou "chrome-libs instalou outra coisa: $(cat "$SUDOLOG")"
grep -q '✓' <<<"$saida" || falhou "a conferência final deveria marcar ✓: $saida"
echo "libnss3.so" >"$T/libs"; limpar
saida=$(TT_FINGE_CHROME_LIBS_ARQ="$T/libs" roda) || true
grep -q 'bibliotecas do Chrome e do Carbonyl' <<<"$saida" || falhou "visão geral não listou as bibliotecas do Chrome: $saida"
passou 'bibliotecas do Chrome/Carbonyl entram no modal, com nomes de pacote do gerenciador, e a instalação é conferida'

# 5) Sem conta de e-mail, mbsync/w3m não são oferecidos.
limpar; rm -f "$HOME/.config/tt/email/x.conf"; echo "mbsync w3m" >"$FALTAS"; printf r >"$T/resposta"
saida=$(roda) || true
grep -q 'mbsync\|w3m' <<<"$saida" && falhou "sem conta de e-mail ofereceu mbsync/w3m: $saida"
printf 'nome=X\nendereco=x@y.z\n' >"$HOME/.config/tt/email/x.conf"
passou 'sem conta de e-mail, só as pendências que fazem sentido aparecem'

# 6) --sim: instala tudo sem perguntar nem precisar de terminal; sai 0 e confere.
limpar; echo "curl mbsync w3m" >"$FALTAS"; : >"$SUDOLOG"
saida=$(PATH="$B:$PATH" TT_FINGE_FALTA_ARQ="$FALTAS" setsid "$TT" --pedir-sudo --sim 2>&1 </dev/null) || falhou "--sim deveria sair com sucesso: $saida"
grep -q 'install curl isync w3m$' "$SUDOLOG" || falhou "--sim não instalou tudo: $(cat "$SUDOLOG")"
grep -q 'Pronto' <<<"$saida" || falhou "--sim sem mensagem final: $saida"
grep -q 'Nada pendente' <<<"$(roda)" || falhou 'depois do --sim ainda há pendência'
passou '--sim: instala tudo sem perguntar, sem terminal, e confere'

# 7) Falha na instalação: é dita, o aviso espera 7 dias, e o id explícito reabre.
limpar; echo "w3m" >"$FALTAS"; printf a >"$T/resposta"
saida=$(APTFALHA=1 roda) && falhou 'instalação que falhou deveria sair com erro'
grep -q '✗' <<<"$saida" || falhou "falha sem ✗: $saida"
grep -q 'Detalhes em' <<<"$saida" || falhou "falha sem apontar o log: $saida"
[[ -s $ES/sudo-recusado-email-html ]] || falhou 'o que falhou não deveria voltar a incomodar na hora'
grep -q 'Nada pendente' <<<"$(roda)" || falhou 'o que falhou deveria esperar uma semana'
printf a >"$T/resposta"; : >"$SUDOLOG"; roda email-html >/dev/null || falhou 'id explícito deveria reabrir o que falhou'
passou 'falha: dita com ✗ e o log, espera 7 dias, reaberta pelo id'

# 8) Sem sudo/doas/su e sem ser root: explica o que rodar como administrador, sem tentar.
limpar; echo "w3m" >"$FALTAS"; printf a >"$T/resposta"; : >"$SUDOLOG"
saida=$(TT_PRIV=indisponivel roda) && falhou 'sem privilégio deveria sair com erro'
grep -q 'Não achei sudo' <<<"$saida" && grep -q 'apt-get install -y w3m' <<<"$saida" || falhou "sem privilégio não explicou: $saida"
[[ ! -s $SUDOLOG ]] || falhou 'sem privilégio não pode tentar instalar'
passou 'sem sudo/doas/su: mostra o comando para o administrador e não tenta'

# 9) Uma instalação por vez.
limpar; echo "w3m" >"$FALTAS"; printf a >"$T/resposta"; mkdir -p "$ES/pendencias.trava"
saida=$(roda) && falhou 'com outra instalação em andamento deveria recusar'
grep -q 'andamento' <<<"$saida" || falhou "trava sem mensagem: $saida"
rmdir "$ES/pendencias.trava"
passou 'uma instalação por vez (trava)'

# 10) Sem pendências, num terminal: a tela segura a mensagem "tudo em ordem" em vez de piscar e fechar.
limpar; : >"$FALTAS"; rm -f "$HOME/.config/tt/email"/*.conf
saida=$(python3 - "$TT" "$T" "$B" "$FALTAS" <<'PY'
import os, pty, sys, time, select
tt, T, B, F = sys.argv[1:5]
pid, fd = pty.fork()
if pid == 0:
    env = dict(os.environ, PATH=B + ":" + os.environ["PATH"], TT_FINGE_FALTA_ARQ=F, TT_TTY="/dev/tty")
    os.execvpe(tt, [tt, "--pedir-sudo"], env)
out = b""; t0 = time.time(); vivo_apos = None
while time.time() - t0 < 4:
    r, _, _ = select.select([fd], [], [], 0.3)
    if r:
        try: d = os.read(fd, 4096)
        except OSError: break
        if not d: break
        out += d
    try:
        done, _ = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError: done = pid
    if done: vivo_apos = False; break
if vivo_apos is None: os.write(fd, b"x"); vivo_apos = True
print("SEGUROU" if vivo_apos and "Tudo em ordem".encode() in out else "FECHOU/SEM MENSAGEM: %r" % out[-200:])
PY
)
[[ $saida == SEGUROU ]] || falhou "$saida"
passou 'sem pendências a tela segura "tudo em ordem" até uma tecla'
echo 'ok: modal único de pendências'
