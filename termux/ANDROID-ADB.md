# adb, Shizuku e Tasker no próprio celular

Guia e handoff (para gente e para agentes de IA) do arranjo que dá ao Termux o shell do sistema
(`uid shell`, o mesmo do `adb shell`) sem PC, sem root e, depois do primeiro Wi-Fi, sem Wi-Fi —
inclusive depois de um reboot. Foi descoberto e testado num Galaxy S23 Ultra com Android 16, à base de
experimentos com agentes de IA; vale para Android 11+.

Comando único, passo a passo e idempotente (pode rodar de novo a qualquer momento):

    termux/celular.sh adb

## Para que serve

Com o shell do sistema o Termux pode, por script: desligar o "phantom process killer" (que mata as
abas do Termux em lote), tirar apps da economia de bateria, dar permissões especiais
(`WRITE_SECURE_SETTINGS`), ler ajustes do Android para backup, instalar/desativar apps, automatizar a
tela (`input`, `uiautomator`), entre outras coisas. Também permite que agentes de IA rodando no Termux
operem o celular.

## As peças

| Peça | Papel |
|---|---|
| Depuração sem fio (Android 11+) | o adbd do próprio aparelho; o Termux é **pareado uma vez** (`adb-local parear`) |
| `adb-local` | conecta o adb do Termux ao aparelho; a porta muda a cada vez, então ele varre 30000–50000 |
| `adb tcpip 5555` | abre também `127.0.0.1:5555`, que **não depende de Wi-Fi** — até o próximo reboot |
| Shizuku | servidor com permissão de shell que continua vivo sem adb; iniciado pela lib do próprio app |
| `tt-rish` | shell do sistema pelo Shizuku (`rish` exportado pelo app) — sem adb, sem Wi-Fi |
| Tasker + `WRITE_SECURE_SETTINGS` | liga modo dev, adb e depuração sem fio sozinho (o `settings` recusa isso vindo de apps comuns) |
| `termux/tasker/tt-celular.prj.xml` | 4 perfis: `tt: ligar/desligar modo dev` (intents `tt.MODO_DEV_ON/OFF`), `tt: abrir no boot`, `tt: estado do Wi-Fi` |
| `shizuku-ligar` / `shizuku-desligar` | sobe/derruba tudo sem tocar na tela |
| `shizuku-vigia` (cron, 2 min) | se o Shizuku caiu e há Wi-Fi, roda `shizuku-ligar` — uma vez por conexão Wi-Fi |

Os utilitários ficam em `termux/bin/` e são ligados em `~/.local/bin` por symlink (seguem o
`git pull`). Estado e log em `~/.local/state/tt/` (`adb-serial`, `shizuku.log`). Um hook opcional do
perfil, `~/.config/tt/shizuku-ok` (executável), roda a cada volta do vigia com o Shizuku de pé — é
onde ficam serviços pessoais que dependem dele.

## Ciclo de vida

**Uma vez só:** parear o Termux na depuração sem fio; `android-ajustes.sh` pelo adb (dá
`WRITE_SECURE_SETTINGS` ao Tasker e ao Shizuku, desliga o phantom killer, tira da economia de
bateria); exportar o `rish` do Shizuku; importar o projeto do Tasker; vigia no cron.

**Depois de um reboot** (sem tocar em nada):

1. O Tasker (`tt: abrir no boot`) liga modo dev e adb e abre o Termux; o Termux:Boot sobe sshd, cron
   e o tmux.
2. Ao conectar num Wi-Fi já autorizado, o `tt: estado do Wi-Fi` grava `1 <ms>` em
   `/sdcard/Tasker/estado/wifi`.
3. Em até 2 min o `shizuku-vigia` vê "Shizuku caído + Wi-Fi novo" e roda `shizuku-ligar`: intent
   para o Tasker ligar a depuração sem fio → varredura de portas → `adb connect` (já pareado) → inicia
   o Shizuku → `adb tcpip 5555`.
4. A partir daí o Wi-Fi pode cair: Shizuku e `127.0.0.1:5555` continuam até o próximo reboot.

Ou seja: depois de cada reboot basta **uma conexão Wi-Fi** (numa rede já autorizada para a
depuração sem fio).

## Pegadinhas aprendidas

- O código de pareamento some quando a tela de pareamento fecha: use tela dividida ou janela pop-up.
- Numa rede Wi-Fi nova o Android pergunta se permite a depuração sem fio nela; por isso o vigia tenta
  só uma vez por conexão (insistir enche a tela de diálogos).
- Android 14+: o `app_process` não carrega dex gravável — o `rish_shizuku.dex` fica com `chmod 400`.
- O Shizuku pode cair logo depois do `adb tcpip` (o adbd reinicia); o `shizuku-ligar` sobe de novo
  pelo 5555.
- `settings put global adb_wifi_enabled 1` vindo de um app precisa de `WRITE_SECURE_SETTINGS`; só o
  adb pode dar essa permissão (uma vez; sobrevive a reboot e a desligar o modo dev).
- O IP Tailscale do celular não serve para o adb; o adb local usa sempre `127.0.0.1`.
- Sem Tasker, o vigia usa o `termux-wifi-connectioninfo` (app Termux:API) para saber do Wi-Fi, mas
  depois de um reboot a depuração sem fio precisa ser ligada à mão.

## Para agentes de IA

- Teste antes de agir: `tt-rish --ok` (Shizuku), `adb-local status` (adb). Prefira `tt-rish -c '…'`:
  não depende de Wi-Fi.
- Nunca rode `shizuku-desligar` sem pedir: derruba o acesso de todos os agentes.
- Comandos de sistema úteis: `device_config`, `settings`, `cmd appops`, `dumpsys deviceidle`,
  `pm grant`, `input`, `uiautomator dump`.
- A saída do `rish` redirecionada pode chegar fora de ordem: para coletar muitos dados, mande o
  próprio comando gravar em `/sdcard/...` e leia o arquivo.
- Diagnóstico: `termux/celular.sh verificar` e `~/.local/state/tt/shizuku.log`.
