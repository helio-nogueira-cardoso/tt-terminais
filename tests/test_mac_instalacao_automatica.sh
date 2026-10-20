#!/usr/bin/env bash
# A instalação do Mac garante as dependências do fallback e aciona as configurações padrão.
source "$(dirname "$0")/lib.sh"; isolar

grep -q 'mac_configurar_padrao || return 1' "$RAIZ/tt" || falhou 'instalar_aqui não aplica a configuração automática do Mac'
grep -q 'TT_TAILSCALE_WS_AUTO' "$RAIZ/tt" || falhou 'a configuração automática não tem chave de escape explícita'
grep -q 'macos_ws=(node tailscale)' "$RAIZ/instalar.sh" || falhou 'instalar.sh não garante Node/Tailscale no macOS'

out=$(bash -c 'source "$1"; pk_resolver brew node tailscale; printf "%s\n" "${PK_PACOTES[*]}"' _ "$T/pkg/pacotes-tt.sh")
[[ $out == 'node tailscale' ]] || falhou "Homebrew não resolveu Node/Tailscale: $out"

echo 'ok: instalação Mac ativa atalhos e fallback WebSocket do Tailscale automaticamente'
