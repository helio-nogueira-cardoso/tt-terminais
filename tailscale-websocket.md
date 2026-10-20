# Fallback WebSocket local do Tailscale (macOS)

Em redes corporativas com inspeção Netskope, o protocolo nativo do Tailscale pode falhar com `unexpected EOF`. O tt traz um fallback local que mantém o controle e o DERP dentro do proxy HTTP local e os converte para WebSocket sobre HTTPS.

## Ativar

Em instalações novas ou atualizações no macOS, o `tt` garante Node.js com WebSocket nativo e o `tailscaled`
pelo Homebrew (Intel e Apple Silicon), e ativa este fallback automaticamente. O vigia reforça a garantia
ao iniciar e a cada cinco minutos. Em Linux e Termux a rotina não faz nada.

`tt --tailscale-ws garantir` é a mesma operação idempotente da instalação e do vigia: compara arquivos,
confere os serviços e consulta `/tt-health` nos três listeners. Só recarrega o que mudou ou caiu.
Os arquivos são instalados atomicamente, os argumentos e opções existentes do `tailscaled` são preservados,
e os bridges ficam prontos antes de apontar o daemon ao proxy. Falha de carregamento restaura o estado anterior.
Ao atualizar o bridge ou as CAs, reconecta o daemon uma vez para descartar tentativas antigas malsucedidas.

As chamadas administrativas usam `sudo -n`. Sem privilégio, Homebrew ou dependência disponível, fica uma
pendência em `~/.local/state/tt/tailscale-ws/estado` e `ultima.log`, visível também em `tt --checar`.
A instalação do tt continua e o vigia tenta novamente; nunca pede senha nem inicia login do Tailscale.
A instalação requer o daemon standalone `tailscaled`; a extensão da aplicação gráfica não é administrada pelo tt.

A ativação manual continua disponível para reparar ou conferir uma máquina:

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

O bridge e as CAs públicas do System Keychain são instalados em `/Library/Application Support/tt-tailscale-ws/`,
com propriedade de root. O backup de um plist anterior sem proxy fica nessa pasta como `tailscaled.antes-ws.plist`.
Os logs ficam em `~/.local/state/tt/tailscale-ws/`. Nenhum auth key, token ou segredo é copiado para o pacote.

`desativar` tira apenas as variáveis do fallback e preserva o restante do serviço; não restaura backups antigos
contaminados pelo próprio proxy. O próximo reforço volta a ativá-lo. `TT_TAILSCALE_WS_AUTO=0` no ambiente do
instalador/vigia suspende o reforço explicitamente. `TT_MAC_AUTO=0`, `TT_RT` isolado ou HOME temporário protegem testes.
