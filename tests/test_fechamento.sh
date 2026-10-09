#!/usr/bin/env bash
# Fechamento uniforme: mensagens fecham com QUALQUER tecla (Esc inclusive), sem deixar ^[ na tela.
source "$(dirname "$0")/lib.sh"
isolar
corpo=$(sed -n '/^email_pausa()/p' "$RAIZ/tt")
[[ -n $corpo ]] || falhou "email_pausa não encontrada"
for tecla in '\033' '\n' 'x' '\033[A'; do
  saida=$(python3 - "$corpo" "$tecla" <<'PY'
import os, pty, sys, time, select
corpo, tecla = sys.argv[1], sys.argv[2].encode().decode("unicode_escape").encode()
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", "-c", corpo + "\nemail_pausa 'fecha com qualquer tecla'; echo FIM"])
time.sleep(0.4); os.write(fd, tecla)
out = b""; fim = time.time() + 3
while time.time() < fim:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try: d = os.read(fd, 4096)
        except OSError: break
        if not d: break
        out += d
        if b"FIM" in out: break
print("ok" if b"FIM" in out and b"^[" not in out else "falhou: %r" % out)
PY
)
  [[ $saida == ok ]] || falhou "tecla [$tecla] não fechou a pausa limpo: $saida"
done
passou 'Esc, Enter, letra e seta fecham a pausa das mensagens sem sobras na tela'
grep -q 'detach-client -s "=\$EMAIL_SESSAO"' "$RAIZ/tt" || falhou 'notif_abrir deveria soltar o popup do e-mail'
passou 'abrir tela do tt com o e-mail na frente solta o popup do e-mail'
echo "TODOS OS TESTES PASSARAM"
