#!/usr/bin/env bash
# Notificações do sistema que os testes disparam (notify-send, termux-notification) nunca chegam à tela de
# quem roda a suíte. Em 12/10/2026 uma suíte mandava 27 avisos de mentira ao GNOME do Hélio ("🤖 agente ·
# precisa de você", "📧 Um: 1 e-mail novo", "📋 Pagar aluguel"), que ele via no PC e não achava no 🔔 (cada
# teste grava o aviso no estado temporário dele). Cada comando que EXISTE aqui ganha, na frente do PATH, um
# substituto que não faz nada; quem não existe continua ausente (o tt decide pela presença: pendências do
# Termux, "sem notificador"). Teste que quer conferir o aviso põe o próprio notify-send em $T/bin antes do PATH.
# Uso: sem_notificacao_real PASTA   (o lib.sh e o tmux-isolado.sh já chamam)
sem_notificacao_real() {
  local dir=$1/sem-notificacao-real c
  mkdir -p "$dir"
  for c in notify-send termux-notification; do
    [[ -e $dir/$c ]] && continue
    command -v "$c" >/dev/null 2>&1 || continue
    printf '#!/bin/sh\nexit 0\n' >"$dir/$c"; chmod +x "$dir/$c"
  done
  case ":$PATH:" in *":$dir:"*) ;; *) PATH="$dir:$PATH"; export PATH ;; esac
}
