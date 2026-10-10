---
name: celular-android
description: Como um agente de IA opera um celular Android montado com o tt-terminais, sem root. Cobre as camadas (Android, Termux com tmux/sshd/tt, Debian no proot-distro onde rodam os agentes), como chegar ao aparelho pela rede, onde rodar cada comando, o shell do sistema sem root (adb do próprio aparelho em 127.0.0.1, Shizuku/rish), o que o tt traz pronto, por que o Tasker religa tudo depois do reboot, por que o Wi-Fi só é preciso uma vez por boot, como operar a tela (do jeito simples e do jeito rápido, com um servidor de shell e acessibilidade em uid shell consultado em ~40 ms, tela virtual, lotes, mapa de telas), o Tasker como ponte e como log, e as armadilhas aprendidas. Use quando precisar mexer num celular Android de um usuário do tt, rodar algo no Termux ou no Debian dele, usar permissões do sistema, operar a tela sem atrapalhar quem usa o aparelho, abrir app ou link na frente, recuperar o Shizuku, diagnosticar o Tasker ou um botão físico, ou montar um controle rápido do aparelho.
---

# Celular Android pelo tt-terminais

Vale para qualquer Android 11+ sem root montado com `termux/celular.sh` (do repositório do tt). O passo
a passo para gente está em `termux/ANDROID-ADB.md`; esta skill é o mapa para o agente.

Convenções dos exemplos: `<celular>` é o rótulo do aparelho no tt (`tt --maquinas` mostra rótulo e
`usuario@host`); `cel` é o nome de exemplo do cliente do controle rápido (seção 9), que cada instalação
batiza do seu jeito.

## 1. As camadas

| Camada | O que é | Como se chega | Privilégio |
|---|---|---|---|
| Android | o sistema | shell do sistema: adb local ou Shizuku (seção 4) | `uid shell` (2000, o do `adb shell`) |
| Termux | app com um Linux próprio (bionic, `$PREFIX`) | ssh na porta 8022, pela tailnet | usuário do app (`u0_aNNN`) |
| tmux do Termux | o servidor de sessões do celular | central do tt (`tt`), ponte, `ssh <dest> tmux …` | o do Termux |
| Debian (proot-distro) | Linux com glibc dentro do Termux | `proot-distro login debian --shared-tmp --work-dir "$PWD"` (atalho `dbn`) | root falso (proot) |

- Os agentes (Claude Code, Codex, Kiro) rodam no **Debian**, porque precisam de glibc. A instalação do
  tt espelha o pacote em `/root/.local/share/tt` do proot e põe lá as skills e os links `ia-*`.
- A conversa com o agente acontece na tela do Termux do próprio celular. Isso pesa nas regras da tela
  (seção 12): o que for mandado ao Termux na frente cai na sessão do agente.
- O proot vê a home do Termux no mesmo caminho e, com `--shared-tmp`, o mesmo `/tmp`. Ele **não** tem
  o privilégio do Android: comando de sistema (`settings`, `pm`, `input`, `cmd`…) vai pelo shell do
  sistema (seção 4), que funciona a partir do Termux e também de dentro do proot.
- Root no proot: o Claude Code só aceita `--dangerously-skip-permissions` com `IS_SANDBOX=1`, e o
  socket de mensagens precisa de caminho explícito (o proot não mapeia uid). Os atalhos `cl`, `clc` e
  `clr` do Termux já fazem isso.
- O proot não tem `/dev/fd` (nada de `<(…)`) nem `iconv`, roda em UTC (exporte `TZ` para bater com o
  Tasker e o logcat) e cada processo externo custa uns 30 ms (prefira builtins do bash em laços).

## 2. Chegar ao aparelho

```bash
dest=$(tt --maquinas | awk '$2=="<celular>"{print $1}')
ssh "$dest" 'PATH="$HOME/.local/bin:$PATH"; tt --listar-tudo --para-ia'   # sessões e agentes de lá
```

- O sshd do Termux sobe sozinho no boot (Termux:Boot) e ignora o nome de usuário: vale a chave.
- Comando remoto não lê o `.bashrc`: comece com `PATH="$HOME/.local/bin:$PATH"` (lá ficam `tt`,
  `adb-local`, `tt-rish`, `shizuku-ligar`…).
- Celular de tela apagada costuma sumir da rede ("offline, last seen" no `tailscale status`, ssh com
  tempo esgotado). É normal: tente mais tarde, sem laço insistente.
- Arquivos: `tt --trazer <celular>:~/arquivo .` e `tt --enviar arquivo <celular>`.
- Quando o assunto é o próprio aparelho, um agente trabalhando **dentro** dele rende mais do que operar
  de longe: abra uma sessão lá com o agente e o pedido (roteiro na skill `tt-terminais`, seção "Agente
  lança agente em outra máquina") e receba o resultado por arquivo.

## 3. Onde rodar cada coisa

| O quê | Onde | Observação |
|---|---|---|
| tmux, sshd, cron, tt, `adb` (android-tools), `termux-*` (Termux:API) | Termux | o cron e o Termux:Boot só enxergam o Termux |
| agentes de IA, apt, ferramentas de desenvolvimento | Debian (proot) | `dbn` abre um shell lá na pasta atual |
| comandos do sistema Android | shell do sistema (seção 4) | `tt-rish`, adb local ou o servidor rápido (seção 9) |

- Script do proot chamado do Termux nativo: o shebang `#!/bin/bash` não existe no Termux. Um lançador
  em `~/.local/bin` do Termux roda o script do proot com o bash do Termux apontando para o caminho dele
  no rootfs (`$PREFIX/var/lib/proot-distro/containers/debian/rootfs/…`). É o que permite a um agente
  que chegou por ssh no Termux usar as mesmas ferramentas do agente que roda no proot.
- O inverso também vale: de dentro do proot dá para executar o `app_process` do Android (o proot só o
  executa), e é assim que o `rish` funciona lá dentro (seção 4).

## 4. Shell do sistema sem root

Duas portas para o mesmo privilégio (`uid shell`):

| Porta | Como nasce | Depende de Wi-Fi? | Até quando |
|---|---|---|---|
| adb local | o adb do Termux pareado **uma vez** com a depuração sem fio do próprio aparelho (`adb-local parear PORTA CÓDIGO`) | a depuração sem fio sim; `127.0.0.1:5555`, aberto depois com `adb-local tcpip`, não | 5555 até o próximo reboot |
| Shizuku | servidor iniciado com `uid shell` pelo adb, pela biblioteca do próprio app (`libshizuku.so`) | não, depois de iniciado | até o próximo reboot |

- Teste antes de agir: `tt-rish --ok` (Shizuku) e `adb-local status` (adb). Prefira `tt-rish -c 'cmd'`:
  não depende de adb nem de Wi-Fi.
- `adb-local conectar` acha a porta da depuração sem fio (muda a cada vez: varre 30000 a 50000) e
  guarda o endereço que funcionou em `~/.local/state/tt/adb-serial`. Endereço sempre `127.0.0.1`: o IP
  da tailnet não serve para o adb.
- O `rish` exportado pelo app Shizuku é um script que chama o carregador Java; no proot o `getprop`
  dele falha e suja a saída. Chame o carregador direto:
  `RISH_APPLICATION_ID=com.termux /system/bin/app_process -Djava.class.path=<pasta>/rish_shizuku.dex /system/bin --nice-name=rish rikka.shizuku.shell.ShizukuShellLoader -c "<cmd>"`.
  No Android 14+ o `.dex` precisa ser só leitura (`chmod 400`).
- Custo e jeito do `rish -c`: sobe uma JVM a cada chamada (~1 s) e só volta quando todos os filhos da
  sessão saem; matar o `rish` mata a sessão. Para muitos gestos, use o servidor da seção 9.
- Saída longa do `rish` pode chegar fora de ordem: mande o comando gravar em `/sdcard/…` e leia depois.

## 5. O que o tt traz pronto

| Peça | Papel |
|---|---|
| `termux/celular.sh` | monta o aparelho (pacotes, sshd por chave, boot, Debian com o Claude, tt); `verificar`, `conectar`, `android`, `adb` |
| `termux/celular.sh adb` | passo a passo idempotente: ferramentas, pareamento do adb local, ajustes do Android, Shizuku, Tasker, vigia no cron |
| `termux/android-ajustes.sh` | roda no shell do sistema: desliga o "phantom process killer", tira Termux/Tailscale/Shizuku/Tasker da economia de bateria, Tailscale como VPN sempre ativa, `WRITE_SECURE_SETTINGS` para Tasker e Shizuku |
| `adb-local` | adb do Termux ligado ao próprio aparelho: `parear`, `conectar`, `tcpip`, `sh`, `status`, `off` |
| `tt-rish` | shell do sistema pelo Shizuku (`-c 'cmd'`, `--ok` testa) |
| `shizuku-ligar` / `shizuku-desligar` | sobe/derruba Shizuku e adb sem tocar na tela (ligar: intent ao Tasker, adb local, Shizuku, 5555) |
| `shizuku-vigia` (cron, 2 min) | Shizuku fora e Wi-Fi novo: roda `shizuku-ligar`, uma vez por conexão; Shizuku de pé: roda o gancho opcional `~/.config/tt/shizuku-ok` |
| `termux/tasker/tt-celular.prj.xml` | projeto do Tasker com 4 perfis (seção 6) |
| `termux/boot-tt` | Termux:Boot: wake lock, serviços (sshd, cron) e um tmux para o tt do celular aparecer nas outras máquinas |
| `termux/atalhos.sh` | `dbn` (shell no Debian), `cl`/`clc`/`clr` (Claude como root do proot), `clu` (atualiza) |

Estado e log em `~/.local/state/tt/` (`adb-serial`, `shizuku.log`). Os utilitários ficam em
`termux/bin/` e são ligados em `~/.local/bin` por symlink (seguem o `git pull` do clone).

## 6. Depois de um reboot: o papel do Tasker

No reboot tudo cai: o Shizuku (sem root ele não sobrevive), o `127.0.0.1:5555` e a depuração sem fio.
Religar exige ligar a depuração sem fio, que é um ajuste protegido (`settings put global
adb_wifi_enabled 1` pede `WRITE_SECURE_SETTINGS`). O Termux sozinho não tem esse direito, e quem o
teria (adb, Shizuku) está justamente fora do ar. O Tasker quebra o círculo: recebe
`WRITE_SECURE_SETTINGS` **uma vez**, pelo adb (`android-ajustes.sh`), e a permissão sobrevive a reboot e
a desligar o modo dev.

Os perfis do projeto do tt:

| Perfil | Gatilho | O que faz |
|---|---|---|
| `tt: abrir no boot` | o aparelho ligou | liga o modo dev e o adb, espera, abre o Termux e volta à tela inicial |
| `tt: ligar modo dev` | intent `tt.MODO_DEV_ON` | liga o modo dev e a **depuração sem fio** |
| `tt: desligar modo dev` | intent `tt.MODO_DEV_OFF` | desliga depuração sem fio, adb e modo dev (o Shizuku cai junto) |
| `tt: estado do Wi-Fi` | Wi-Fi conectado / caiu | grava `1 <ms>` / `0 <ms>` em `/sdcard/Tasker/estado/wifi` |

As intents saem do Termux sem privilégio: `am broadcast -a tt.MODO_DEV_ON`.

A cadeia, sem tocar na tela:

1. O aparelho liga; o Tasker liga o modo dev e abre o Termux; o Termux:Boot sobe sshd, cron e tmux.
2. Ao conectar num Wi-Fi já autorizado para a depuração sem fio, o Tasker grava `1 <ms>`.
3. O vigia (cron, a cada 2 min) vê "Shizuku fora + Wi-Fi novo" e roda o `shizuku-ligar`.
4. `shizuku-ligar`: intent para o Tasker ligar a depuração sem fio, `adb-local conectar` (já pareado),
   Shizuku pela `libshizuku.so` do app, `adb tcpip 5555` e conexão em `127.0.0.1:5555`.
5. Pronto: Shizuku e adb local ficam de pé até o próximo reboot.

O vigia tenta **uma vez por conexão Wi-Fi**: numa rede nova o Android pergunta se permite a depuração
sem fio nela, e insistir só enche a tela de diálogos. Sem o Tasker, o vigia sabe do Wi-Fi pelo
`termux-wifi-connectioninfo` (Termux:API), mas a depuração sem fio volta a ser ligada à mão.

Instalações com automações próprias podem ter um vigia próprio no lugar do `shizuku-vigia` (o passo
`adb` do `celular.sh` reconhece um `shizuku-guard` no cron e não acrescenta o dele). Em geral esse
vigia faz o mesmo e ainda mantém vivos o servidor da seção 9 e um coletor de log: veja `crontab -l`.

## 7. O Wi-Fi só é preciso uma vez por boot

A depuração sem fio só funciona com Wi-Fi conectado, e é ela que dá o primeiro adb depois de um
reboot. Daí em diante o Wi-Fi pode cair e o celular pode sair do alcance: o Shizuku é um processo que
já está rodando, o `127.0.0.1:5555` é o adbd escutando no loopback e o servidor da seção 9 conversa por
loopback. Tudo segue funcionando até o próximo reboot, ou até alguém desligar o modo dev (o que derruba
o Shizuku junto).

Com o shell do sistema o agente também mexe no Wi-Fi: `cmd wifi status`,
`cmd wifi set-wifi-enabled enabled`, `cmd wifi connect-network <rede> wpa2 <senha>` (ajuda completa em
`cmd wifi help`). Serve, por exemplo, para religar o Wi-Fi e preparar um novo pareamento ou um novo
`shizuku-ligar` enquanto o Shizuku ou o 5555 ainda estão de pé. Desligar Wi-Fi, adb ou modo dev pode
cortar o único canal: pergunte antes.

## 8. Operar a tela do jeito simples

Pelo shell do sistema (`tt-rish -c '…'` ou `adb -s 127.0.0.1:5555 shell '…'`). Funciona em qualquer
instalação; é lento para muitos gestos (seção 9).

| Para | Comando |
|---|---|
| saber o app da frente (confira **antes** de tocar) | `dumpsys window \| grep -E 'mCurrentFocus\|mFocusedApp'` |
| ver a tela | `screencap -p /sdcard/Download/tela.png` e traga o arquivo (`tt --trazer`) |
| achar elementos | `uiautomator dump /sdcard/Download/ui.xml` (texto, id e `bounds` de cada elemento; toque no centro) |
| tocar, arrastar, digitar | `input tap X Y`, `input swipe X1 Y1 X2 Y2 300`, `input text 'palavra'` (espaço vira `%s`) |
| teclas | `input keyevent KEYCODE_BACK`, `KEYCODE_HOME`, `KEYCODE_ENTER`; `111` (Esc) fecha painéis, mas pode descartar o que estava sendo editado |
| abrir link num navegador, na frente | `am start -a android.intent.action.VIEW -n <pacote>/<atividade> -f 0x10000000 -d '<url>'` |
| abrir um app | `am start -n <pacote>/<atividade>` ou `monkey -p <pacote> 1` |

- Vindo do app Termux, `termux-open-url` e `am start` nem sempre trazem o app para a frente (o Android
  barra atividade iniciada em segundo plano). Pelo `uid shell` funciona.
- `uiautomator dump` espera a tela ficar ociosa: com o Termux animando pode levar 10 s.
- Retorno de login (OAuth) para `http://127.0.0.1:PORTA` aberto no navegador do celular chega a um
  processo de outra máquina por túnel reverso: `ssh -N -R 127.0.0.1:P:127.0.0.1:P <dest>`, rodado na
  máquina onde o processo escuta. Navegador de texto (Carbonyl) é recusado no login do Google.

## 9. Controle rápido: um servidor de shell e tela com uid shell

O tt não traz este servidor; ele existe em instalações com um projeto de automações próprio e é o
jeito certo de operar a tela com frequência. Em vez de uma JVM por gesto (`rish -c`, ~1 s) e de
esperar o `uiautomator dump`, um processo de longa duração roda como `uid shell` e atende o agente por
uma porta local: cada chamada custa **~40 ms**, quase tudo o `fork` do proot.

### Como descobrir se a instalação tem um

- Leia a documentação do projeto de automações do usuário (`CLAUDE.md`, `AGENTS.md` ou `README` na
  home do Debian ou do Termux): ela dá o nome do cliente e os comandos.
- Procure no PATH do Termux e do proot um executável que responda a `help` com comandos de tela
  (`tela`, `ui`, `vd`, `ir`) e veja no `crontab -l` o vigia que o mantém vivo.
- Nos exemplos abaixo, o cliente se chama `cel`. Use o nome real da instalação.

### Como é montado

1. **Shizuku de pé** (seção 4): é ele que dá `uid shell` a um app (o Termux) sem Wi-Fi e sem adb.
2. **Servidor**: uma classe Java compilada para `.dex`, iniciada **uma vez** pelo carregador do `rish`
   como `uid shell`:
   `cp servidor.dex /data/local/tmp/ && chmod 444 /data/local/tmp/servidor.dex && TOKEN=… setsid app_process -cp /data/local/tmp/servidor.dex / Servidor PORTA </dev/null >/data/local/tmp/servidor.log 2>&1 &`.
   O `setsid` tira o servidor da sessão do `rish` (senão morre junto); o `rish` vai para o fundo e é
   encerrado assim que o servidor responde a um `ping`.
3. **Dentro do servidor**: um `UiAutomation` conectado (a árvore de acessibilidade de todas as
   janelas), uma thread com `Looper` (APIs como `DisplayManager` e `ImageReader` exigem), escuta em
   `127.0.0.1:PORTA` e **exige token**: qualquer app com permissão de internet alcança o loopback, e ali
   se executa shell como uid 2000. O `app_process` não tem fontes: `Paint.measureText`/`drawText`
   derrubam o processo (para marcar screenshots, desenhe sem texto ou componha fora).
4. **Cliente fino**: um script bash que usa só builtins e `/dev/tcp` (nada de `nc` ou `python`, que
   custariam processos no proot). Lê o token de um arquivo com permissão 600 (só o Termux e o proot
   leem), manda uma linha, imprime a resposta e transforma a última linha `@@rc N` no código de saída.
   Conexão recusada: sobe o servidor e repete. Servidor de versão antiga no ar: encerra e sobe o novo.
5. **Vigia no cron** (a cada 2 min): se o Shizuku responde, garante servidor e coletor de log vivos (um
   `ping` local, barato); se o Shizuku caiu e há Wi-Fi novo, religa como na seção 6.

### Protocolo

Uma linha por conexão; a resposta termina quando o servidor fecha:

    TOKEN [de DONO] [in PACOTE] comando [ ; comando … ]

- `de DONO`: quem pede (por exemplo o começo do id da sessão do agente); é o que a reserva usa.
- `in PACOTE`: recusa o comando se aquele app não estiver na frente (evita tocar no app errado).
- ` ; ` junta comandos num lote, executado de uma vez, que para no primeiro erro.
- As ações esperam a tela **assentar** por eventos de acessibilidade (~150 ms sem mudança), sem
  `waitForIdle` e sem `sleep` no chute.

| Grupo | Comandos do servidor |
|---|---|
| leitura | `ping` `top` (app da frente) `windows` `tela` `onde` `dump [all]` `find Q` `linhas [rolar N]` `valor Q` `quem` |
| ação | `click Q [n]` `long Q [n]` `t N` `tl N` `settext Q\|TEXTO` `tap X Y` `press X Y [ms]` `swipe X1 Y1 X2 Y2 [ms]` `key N` `back` `home` `abrir PACOTE/ATIVIDADE` `ir TELA` `volta TELA [n]` |
| espera | `wait Q [ms]` `gone Q [ms]` `assenta [ms]` |
| outros | `sh CMD` (última linha `@@rc N`) `shot ARQ [escala] [qualidade] [marcas]` `lock [min]` `unlock` `quit` |

Busca de elemento (`Q`): texto, descrição ou id, sem acento e sem caixa; `=Q` exige igualdade; prefixo
de papel opcional `btn:` `tab:` `item:` `menu:` `campo:` `chk:` `txt:`.

### O que isso dá ao agente

| Capacidade | Exemplo | Por que poupa tempo |
|---|---|---|
| shell do sistema | `cel sh 'cmd'` | sem JVM nova; sai com o código de retorno |
| tela como texto | `cel tela` | só os acionáveis do app da frente, numerados, sem barra de status e sem teclado |
| tocar pelo número | `cel t N` · `cel tl N` (longo) | sem coordenadas e sem screenshot |
| lote | `cel ui 'click A ; wait B ; back'` | uma rodada em vez de três; devolve a tela final |
| lista rolável como dados | `cel linhas [rolar N]` · `cel valor ROTULO` | TSV da maior lista da tela; o valor ao lado de um rótulo |
| telas com nome | `cel onde` · `cel ir NOME` | mapa de telas com rotas; confere cada tela do caminho |
| screenshot barato | `cel shot 0.4 --marcas` | JPEG reduzido com os mesmos números do `tela` |
| tela virtual | `cel vd on` … `cel vd off` | as ações vão para uma segunda tela invisível: a pessoa continua usando o celular |
| reserva | `cel lock` · `cel unlock` · `cel quem` | recusa comandos que tocam a tela se outra sessão a reservou |
| app da frente e volta | `cel top` · `cel termux` | confere antes de tocar; devolve a tela ao Termux no fim |

### Mapa de telas

Um arquivo de texto (no aparelho, onde o servidor lê; o cliente copia do projeto quando muda)
reconhece telas por condições e guarda rotas:

    tela NOME condições…        # todas precisam valer; vence a que tiver mais condições
      pkg=PACOTE                # app da frente
      janela=TEXTO              # a classe da última janela/atividade do app contém TEXTO
      tem=TEXTO                 # algum texto/descrição/id visível contém TEXTO ("_" = espaço)
      tem==TEXTO                # … é exatamente TEXTO

`onde` diz em que tela se está (`onde debug` mostra qual condição falhou); `ir NOME` segue a rota e
confere cada tela no caminho. Um documento ao lado, para gente, anota como chegar a cada tela e os
perigos (por exemplo, botões que apagam dados).

### Tela virtual

Uma segunda tela invisível (como o `scrcpy --new-display`). Ligada, `abrir`, `ir`, `tela`, `t`,
`linhas`, `valor` e `shot` agem nela, sem mexer no que a pessoa vê. Um app aberto nela (o Tasker, por
exemplo) passa para a tela principal quando a pessoa o abre. Desligar fecha os apps abertos nela;
reiniciar o servidor também a fecha.

### Montar um servidor desses

O caminho mínimo: uma classe Java que cria o `UiAutomation` por reflexão (API escondida:
`android.app.UiAutomationConnection` e o construtor `UiAutomation(Looper, IUiAutomationConnection)`,
numa `HandlerThread`), um `ServerSocket` em `127.0.0.1`, token obrigatório, o protocolo de uma linha
acima, espera por eventos de acessibilidade, `sh` com `@@rc`, e um cliente bash com `/dev/tcp`. Para o
`.dex`: `javac --release 11` contra o `android.jar` (mais stubs das classes escondidas) e o `D8` do R8
(`--min-api 26`). Suba pelo carregador do `rish` com `setsid` e ponha um vigia no cron. Mudou o código:
recompile e reinicie o servidor.

## 10. O Tasker como ponte e como memória

O Tasker faz o que o shell não pode e deixa rastro legível:

- **Entrada sem tela.** Perfis de evento recebem intents do Termux, por exemplo uma para rodar uma
  tarefa pelo nome (com argumentos) e outra para exportar variáveis globais pedidas para um arquivo
  JSON em `/sdcard/Tasker/estado/`. Um cliente as dispara com `am broadcast -a …` e lê o arquivo.
- **Ajustes protegidos.** Com `WRITE_SECURE_SETTINGS`, liga e desliga modo dev e depuração sem fio por
  intent (seção 6).
- **Log de eventos.** Cada tarefa grava uma linha JSON num arquivo (ex.: `/sdcard/Tasker/log/eventos.jsonl`)
  e o Run Log do Tasker vai para um arquivo rotacionado. Um coletor de `logcat` filtrado (Tasker,
  Bluetooth, Shizuku, início de atividades) grava num arquivo próprio. O logcat do aparelho guarda só
  alguns minutos: o histórico vem do coletor. É assim que se responde "o que aconteceu às 11:40" sem
  abrir a tela.
- **Fonte de verdade.** As automações nascem de um gerador (script que produz o `.prj.xml`), nunca do XML
  editado à mão: gerar, importar (o Tasker faz 3 perguntas ao importar; entre a 1ª e a 2ª há alguns
  segundos de "obtendo permissões"), testar sem tela (rodar a tarefa por intent) e conferir no log.
- **Estado do Wi-Fi.** O perfil da seção 6 é o dado que o vigia usa.
- **Inventário.** Vale manter um documento gerado com o catálogo do aparelho (apps e atividades,
  aparelhos Bluetooth, perfis e globais do Tasker, atalhos) para não redescobrir tudo a cada sessão.

## 11. Armadilhas aprendidas

Tasker:

- Extras de intent viram variáveis locais, que precisam de **3 ou mais letras** (`id`, `p1` não chegam).
- Uma variável calculada num JavaScriptlet nem sempre chega à condição de uma ação seguinte: para
  disparar outra tarefa a partir de uma decisão do JS, chame `performTask()` dentro do próprio JS.
- `performTask(…)` pode não entregar o parâmetro 1 à tarefa chamada: grave uma global antes de chamar.
- "Executar Shell" pelo Shizuku **não passa por um shell**: nada de `|`, `;`, `>`; chame um programa.
- Ação que pode falhar e não deve abortar a tarefa: marque "continuar após erro".
- Eventos de Bluetooth chegam várias vezes por conexão: use uma trava de tempo (ex.: 60 s) para agir
  uma vez só.
- Tocar na aba VARS já selecionada abre um menu com "Limpar tudo", que apaga todas as globais.
- O Run Log só registra com o interruptor dele ligado.

proot, Shizuku e `app_process`:

- `rish -c`: uma JVM por chamada; só volta quando os filhos da sessão saem; matá-lo mata a sessão.
- `uiautomator dump` espera a tela ociosa; com o Termux animando, até 10 s.
- `app_process` sem fontes: `Paint.measureText`/`drawText` derrubam o processo.
- `pkill -f PADRÃO` acerta o próprio comando que contém o padrão (e derruba a sua conexão ssh se o
  padrão estiver no script remoto). Monte o padrão para não aparecer literal, ou use o PID.

Botões físicos e Termux:

- Tecla simulada (`input keyevent`) **não passa** pelo filtro de acessibilidade nem pelo caminho do
  botão físico: não prova que um botão funciona. Diagnostique com `getevent -lt` (o hardware),
  `logcat | grep interceptKeyTq` (o sistema recebeu) e `Delivering key to` (quem recebeu).
- Com o Termux na frente, `volume-keys = virtual` (padrão) transforma os botões de volume em teclas
  do terminal. Para que mudem o volume: `volume-keys = volume` em `~/.termux/termux.properties` e
  `termux-reload-settings`.

## 12. Hábitos e regras

- **Leia antes de tocar**: variáveis do Tasker, log, listas e `dumpsys` não mexem na tela. Só use a
  tela quando não houver outro jeito, e de preferência a virtual.
- **Na tela real**: confira o app da frente, use `in PACOTE` nos comandos e **volte ao Termux** ao
  terminar ou ao precisar de resposta (a conversa com o agente acontece nele). A pessoa pode estar
  usando o aparelho, inclusive dirigindo.
- **Nunca mande voltar ou teclas com o Termux na frente**: vão para a sessão do agente.
- **Lote e espera** em vez de uma chamada por gesto e `sleep` no chute.
- **Pergunte antes** de `shizuku-desligar`, desligar Wi-Fi/adb/modo dev, desinstalar app ou mudar
  ajuste que não foi pedido. Derrubar o Shizuku tira o acesso de todos os agentes.
- **Segredos**: nunca digite senha ou código com `input text`; peça para a pessoa digitar. Automação que
  desbloqueia o aparelho ou lê códigos de verificação guarda um segredo poderoso: só com pedido
  explícito do dono, num arquivo 600 fora do Git, e dizendo a ele como remover.
- **Testes**: teste que mexe em estado do tt roda com HOME, config e tmux temporários. Um
  `tt --fixar` de teste no HOME de verdade vai para a barra de todas as máquinas.

## 13. Diagnóstico

```bash
tt-rish --ok && echo shizuku ok            # Shizuku
adb-local status                           # adb local e o endereço guardado
cat /sdcard/Tasker/estado/wifi             # o que o Tasker viu do Wi-Fi ("1 <ms>" conectado)
crontab -l                                 # vigia (o do tt ou o próprio) e outros serviços
tail ~/.local/state/tt/shizuku.log         # o que o vigia e o shizuku-ligar fizeram
termux/celular.sh verificar                # o que está montado e o que falta (no clone do tt)
```

Com o servidor da seção 9: `cel quem` (reserva), `cel onde debug` (por que uma tela não foi
reconhecida), o log do servidor em `/data/local/tmp/` e o log de eventos do Tasker.

Pegadinhas da montagem: o código de pareamento some quando a tela de pareamento fecha (use tela
dividida ou janela pop-up); no Android 14+ o `rish_shizuku.dex` precisa ser só leitura; o Shizuku pode
cair logo depois do `adb tcpip` (o adbd reinicia) e o `shizuku-ligar` o sobe de novo pelo 5555.
