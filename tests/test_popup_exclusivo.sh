#!/usr/bin/env bash
# O e-mail e a central não podem ocupar o mesmo cliente ao mesmo tempo.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$(dirname "$0")/lib.sh"; isolar
RT=$TT_RT
source <(sed -n '/^popup_exclusivo_reservar()/,/^popup_exclusivo_liberar()/p' "$ROOT/tt")
popup_exclusivo_reservar email cliente || { echo 'FALHOU: primeira reserva recusada' >&2; exit 1; }
reserva=$POPUP_EXCLUSIVO
if popup_exclusivo_reservar notificacoes cliente; then echo 'FALHOU: notificações abriram sobre e-mail' >&2; exit 1; fi
popup_exclusivo_liberar "$reserva"
popup_exclusivo_reservar notificacoes cliente || { echo 'FALHOU: central não abriu depois que e-mail fechou' >&2; exit 1; }
reserva=$POPUP_EXCLUSIVO
if popup_exclusivo_reservar email cliente; then echo 'FALHOU: e-mail abriu sobre notificações' >&2; exit 1; fi
popup_exclusivo_liberar "$reserva"
echo 'ok: e-mail e central de notificações são mutuamente exclusivos por cliente'
