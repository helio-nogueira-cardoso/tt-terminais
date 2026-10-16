#!/usr/bin/env bash
# tt --pty: terminal interativo (tmux) para agentes. O agente abre uma sessão ia-pty-NOME, digita, lê a tela e espera por
# um texto, inclusive um prompt que pede entrada (como "Password:"), que só a pessoa responde. Linux e macOS.
source "$(dirname "$0")/lib.sh"; isolar
tt() { "$TT" "$@"; }
fail() { echo "FALHOU: $1" >&2; tmux kill-server 2>/dev/null; exit 1; }

[[ $(tt --pty abrir t1 "$T") == ia-pty-t1 ]] || fail "abrir deveria imprimir ia-pty-t1"
[[ $(tt --pty abrir t1) == ia-pty-t1 ]] || fail "abrir de novo deveria reaproveitar a sessão"
[[ $(tt --pty listar) == ia-pty-t1 ]] || fail "listar deveria mostrar só ia-pty-t1: $(tt --pty listar)"
echo "ok: abrir cria e reaproveita; listar"

tt --pty enviar t1 'echo oi-$((1+2))'
tt --pty esperar t1 '^oi-3$' 10 || fail "o resultado do comando não apareceu: $(tt --pty ler t1)"
tt --pty ler t1 | grep -q '^oi-3$' || fail "ler deveria mostrar oi-3"
echo "ok: enviar digita, esperar acha, ler mostra"

# entrada interativa: o agente vê o prompt e responde só o que lhe cabe (aqui um read comum, não senha)
tt --pty enviar t1 'printf "Continuar? "; read -r r; echo "resposta=$r"'
tt --pty esperar t1 '^Continuar\?' 10 || fail "o prompt não apareceu"
tt --pty enviar t1 sim
tt --pty esperar t1 'resposta=sim' 10 || fail "a resposta ao prompt não chegou: $(tt --pty ler t1)"
echo "ok: prompt interativo respondido"

tt --pty enviar t1 'sleep 60'
tt --pty tecla t1 C-c
tt --pty enviar t1 'echo livre'
tt --pty esperar t1 '^livre$' 10 || fail "C-c não interrompeu o sleep"
echo "ok: tecla C-c"

if tt --pty esperar t1 'nunca-aparece' 1; then fail "esperar deveria devolver 1 no tempo esgotado"; fi
if tt --pty ler nao-existe 2>/dev/null; then fail "ler de sessão inexistente deveria falhar"; fi
echo "ok: tempo esgotado e sessão inexistente devolvem erro"

tt --pty fechar t1
[[ -z $(tt --pty listar) ]] || fail "fechar deveria encerrar a sessão"
echo "ok: fechar"
tmux kill-server 2>/dev/null || true
