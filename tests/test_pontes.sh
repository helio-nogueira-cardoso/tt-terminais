#!/usr/bin/env bash
# Teste focado do saneamento de pontes orfas (v136). Usa um servidor tmux isolado (-L) e
# substitui as sondas remotas por stubs, para validar a logica de fechar_pontes_ociosas sem rede.
set -u
SOCK="tt-test-$$"
TM() { tmux -L "$SOCK" "$@"; }
limpar() { TM kill-server 2>/dev/null; }
trap limpar EXIT

falhas=0
ok()   { echo "  ok: $1"; }
erro() { echo "  ERRO: $1"; falhas=$((falhas+1)); }

# Estado controlado pelos testes:
#   REMOTO_VIVO: lista de "dest|sessao" que "existem" no destino
#   DESTINO_MUDO: lista de dest que NAO respondem (rede caida)
REMOTO_VIVO=""
DESTINO_MUDO=""

sessao_remota_existe() { case " $REMOTO_VIVO " in *" $1|$2 "*) return 0;; *) return 1;; esac; }
alcanca_destino()      { [[ -n $1 && $1 != : ]] || return 1; case " $DESTINO_MUDO " in *" $1 "*) return 1;; *) return 0;; esac; }

# Mesmo corpo da funcao do tt, com tmux -> TM (servidor isolado).
fechar_pontes_ociosas() {
  local agora=$1 limite=${TT_T_PONTE:-1800} s anexada ult dest alvo rs
  while IFS='|' read -r s anexada ult dest alvo; do
    [[ $s == _tt-* ]] && continue
    if ((anexada == 0 && ult > 0 && agora - ult >= limite)); then
      TM kill-session -t "=$s" 2>/dev/null
      continue
    fi
    [[ -n $alvo && $alvo == *"|"* ]] || continue
    rs=${alvo#*|}
    if ! sessao_remota_existe "$dest" "$rs" && alcanca_destino "$dest"; then
      TM kill-session -t "=$s" 2>/dev/null
    fi
  done < <(TM list-sessions -F '#{session_name}|#{session_attached}|#{?session_last_attached,#{session_last_attached},#{session_created}}|#{@ponte}|#{@ponte_alvo}' -f '#{@ponte}' 2>/dev/null)
  return 0
}

cria_ponte() { # nome dest alvo
  TM new-session -d -s "$1" "sleep 600"
  TM set-option -t "=$1:" @ponte "$2"
  TM set-option -t "=$1:" @ponte_alvo "$3"
}
existe() { TM has-session -t "=$1" 2>/dev/null; }

# --- Cenario -----------------------------------------------------------------
TM new-session -d -s real-local "sleep 600"          # sessao normal (sem @ponte): nunca tocar
cria_ponte ponte-viva   destX "destX|viva"            # alvo existe -> preservar
cria_ponte ponte-morta  destX "destX|sumiu"           # alvo nao existe, destino responde -> matar
cria_ponte ponte-muda   destY "destY|qualquer"        # destino mudo -> preservar (transitorio)

REMOTO_VIVO="destX|viva"
DESTINO_MUDO="destY"

AGORA=$(date +%s)
TT_T_PONTE=1800 fechar_pontes_ociosas "$AGORA"

echo "== resultados =="
existe real-local  && ok "sessao local preservada"        || erro "sessao local sumiu (NAO devia)"
existe ponte-viva  && ok "ponte com alvo vivo preservada" || erro "ponte-viva foi morta (NAO devia)"
existe ponte-morta && erro "ponte-morta sobreviveu (devia ser encerrada)" || ok "ponte orfa encerrada"
existe ponte-muda  && ok "ponte com destino mudo preservada" || erro "ponte-muda morta (destino mudo e transitorio)"

echo
if ((falhas==0)); then echo "TODOS OS TESTES PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit $falhas
