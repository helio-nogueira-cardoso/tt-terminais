#!/usr/bin/env bash
# Dois logins seguidos da mesma conta: o 2º mata a sessão do 1º (a última do tmux isolado `-L tt-login`), o que derruba
# o servidor, e no tmux 3.6 o new-session logo em seguida falhava com "server exited unexpectedly" (27 vezes em 30,
# medido no book). O ia-login repete até o servidor novo subir. O tmux falso reproduz a corrida: falha o 1º new-session
# depois do kill-session.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
mkdir -p "$HOME/.claude" "$HOME/.local/bin" "$T/falso"
real=$(command -v tmux)
cat >"$HOME/.local/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "https://exemplo.invalid/oauth/authorize?code=true"; sleep 120
EOF
chmod +x "$HOME/.local/bin/claude"
cat >"$T/falso/tmux" <<EOF
#!/usr/bin/env bash
# tmux 3.6 de mentira: o primeiro new-session depois de um kill-session morre com o servidor
for a in "\$@"; do
  [[ \$a == kill-session ]] && : >"$T/matou"
  if [[ \$a == new-session && -e $T/matou ]]; then
    rm -f "$T/matou"; echo 'server exited unexpectedly' >&2; : >"$T/falhou-uma-vez"; exit 1
  fi
done
exec "$real" "\$@"
EOF
chmod +x "$T/falso/tmux"
export PATH=$T/falso:$PATH

s=$(ia-login --iniciar claude principal a@x.com 2>"$T/err") || falhou "1º login não iniciou: $(cat "$T/err")"
[[ $s == login-claude-principal ]] || falhou "nome da sessão: $s"
s=$(ia-login --iniciar claude principal a@x.com 2>"$T/err") || falhou "2º login (com a corrida do tmux) não iniciou: $(cat "$T/err")"
[[ -e $T/falhou-uma-vez ]] || falhou 'o tmux falso não simulou a corrida (teste inválido)'
tmux -L tt-login has-session -t '=login-claude-principal' 2>/dev/null || falhou 'a sessão do 2º login não existe'
passou '2º login seguido da mesma conta repete o new-session quando o tmux ainda está derrubando o servidor'
tmux -L tt-login kill-server 2>/dev/null || true
echo "TODOS OS TESTES PASSARAM"
