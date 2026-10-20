# Fallback WebSocket local do Tailscale (macOS)

Em redes corporativas com inspeção Netskope, o protocolo nativo do Tailscale pode falhar com `unexpected EOF`. O tt traz um fallback local que mantém o controle e o DERP dentro do proxy HTTP local e os converte para WebSocket sobre HTTPS.

## Ativar

Em instalações novas ou atualizações no macOS, o `tt` garante Node.js/Tailscale pelo Homebrew e ativa este
fallback automaticamente. A ativação manual continua disponível para reparar ou conferir uma máquina:

No Mac, com Node.js, Tailscale e `sudo` disponível:

```sh
tt --tailscale-ws ativar
```

O comando instala três LaunchDaemons locais: `127.0.0.1:18743` para controle, `127.0.0.1:80` para compatibilidade com bridges antigos e `127.0.0.1:18744` para proxy HTTP/DERP. O bridge só permite `controlplane.tailscale.com`, `login.tailscale.com` e hosts `derp*.tailscale.com`; ele escuta apenas em loopback.

O `tailscaled` recebe `HTTP_PROXY`, `HTTPS_PROXY`, `TS_DEBUG_USE_DERP_HTTP=true` e `TS_USE_CONTROL_DIAL_PLAN=false`. O plano de dados ainda pode usar UDP direto quando disponível; o fallback cobre principalmente controle e DERP.

## Verificar e desativar

```sh
tt --tailscale-ws status
tt --tailscale-ws testar
tt --saude
tt --tailscale-ws desativar
```

Durante a ativação, as CAs confiadas pelo macOS são exportadas para `~/.local/share/tt-tailscale-ws/system-ca.pem`, permitindo que o Node confie na inspeção Netskope. Nenhum auth key, token ou segredo é copiado para o pacote.
