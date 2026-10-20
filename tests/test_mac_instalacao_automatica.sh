#!/usr/bin/env bash
# A instalação do Mac garante as dependências do fallback e aciona as configurações padrão.
source "$(dirname "$0")/lib.sh"; isolar

grep -q 'mac_configurar_padrao || return 1' "$RAIZ/tt" || falhou 'instalar_aqui não aplica a configuração automática do Mac'
grep -q 'TT_TAILSCALE_WS_AUTO' "$RAIZ/tt" || falhou 'a configuração automática não tem chave de escape explícita'
grep -q 'macos_ws=(node tailscale)' "$RAIZ/instalar.sh" || falhou 'instalar.sh não garante Node/Tailscale no macOS'

out=$(bash -c 'source "$1"; pk_resolver brew node tailscale; printf "%s\n" "${PK_PACOTES[*]}"' _ "$T/pkg/pacotes-tt.sh")
[[ $out == 'node tailscale' ]] || falhou "Homebrew não resolveu Node/Tailscale: $out"

# Exercita as mesmas funções chamadas pela instalação e pelo vigia. O bridge é
# substituído antes de retirar TT_RT; nenhum comando administrativo é executado.
TT_SO_CARREGAR=1 source "$TT"
tailscale_ws() { printf '%s\n' "$1" >>"$T/chamadas-ws"; return "${WS_RC:-0}"; }
mac_terminal() { echo iterm; }
(
  unset TT_RT
  export TT_MAC_AUTO=1 TT_TAILSCALE_WS_AUTO=1
  uname() { echo Linux; }
  tailscale_ws_garantir
  [[ ! -e $T/chamadas-ws ]] || falhou 'Linux acionou WebSocket do Mac'
  uname() { echo Darwin; }
  tailscale_ws_garantir || falhou 'vigia não garantiu WebSocket no Mac'
  [[ $(wc -l <"$T/chamadas-ws") -eq 1 ]] || falhou 'garantia não chegou ao bridge'
  TT_TAILSCALE_WS_AUTO=0 tailscale_ws_garantir
  TT_MAC_AUTO=0 tailscale_ws_garantir
  TT_RT="$T/rt" tailscale_ws_garantir
  [[ $(wc -l <"$T/chamadas-ws") -eq 1 ]] || falhou 'escape/isolamento não foi respeitado'
  mac_configurar_padrao >"$T/mac-saida"
  [[ $(wc -l <"$T/chamadas-ws") -eq 2 ]] || falhou 'instalação não garantiu WebSocket'
  WS_RC=1 mac_configurar_padrao >"$T/mac-saida" || falhou 'pendência de WebSocket bloqueou instalação do tt'
  grep -q 'WebSocket pendente' "$T/mac-saida" || falhou 'falha não virou pendência explícita'
)

echo 'ok: instalação Mac ativa atalhos e fallback WebSocket do Tailscale automaticamente'
