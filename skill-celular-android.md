---
name: celular-android
description: Como um agente de IA opera um celular Android montado com o tt-terminais, sem root. Cobre as camadas (Android, Termux com tmux/sshd/tt, Debian no proot-distro onde rodam os agentes), como chegar ao aparelho pela rede, onde rodar cada comando, como ganhar o shell do sistema (adb do próprio aparelho em 127.0.0.1, Shizuku/rish), por que o Tasker religa tudo depois do reboot, por que o Wi-Fi só é preciso uma vez por boot, e como operar a tela (screencap, uiautomator, input, am start). Use quando precisar mexer num celular Android de um usuário do tt, rodar algo no Termux ou no Debian dele, usar permissões do sistema, abrir app ou link na frente, recuperar o Shizuku ou entender uma falha do adb/Shizuku/Tasker.
---

# Celular Android pelo tt-terminais

Vale para qualquer Android 11+ sem root montado com `termux/celular.sh` (do repositório do tt). O
guia de montagem para gente está em `termux/ANDROID-ADB.md`; esta skill é o mapa para o agente. Nos
exemplos, `<celular>` é o rótulo do aparelho no tt (`tt --maquinas` mostra rótulo e `usuario@host`).

## As camadas

| Camada | O que é | Como se chega | Privilégio |
|---|---|---|---|
| Android | o sistema | shell do sistema: adb local ou Shizuku (abaixo) | `uid shell` (o do `adb shell`) |
| Termux | app com um Linux próprio (bionic, `$PREFIX`) | ssh na porta 8022, pela tailnet | usuário do app (`u0_aNNN`) |
| tmux do Termux | o servidor de sessões do celular | central do tt (`tt`), ponte, `ssh <dest> tmux …` | o do Termux |
| Debian (proot-distro) | Linux com glibc dentro do Termux | `proot-distro login debian --shared-tmp --work-dir "$PWD"` (atalho `dbn`) | root falso (proot) |

- Os agentes (Claude Code, Codex, Kiro) rodam no **Debian**, porque precisam de glibc. A instalação do
  tt espelha o pacote em `/root/.local/share/tt` do proot e põe lá as skills e os links `ia-*`.
- O proot vê a home do Termux no mesmo caminho e, com `--shared-tmp`, o mesmo `/tmp`. Ele **não** tem
  o privilégio do Android: comando de sistema (`settings`, `pm`, `input`, `cmd`…) sai do Termux.
- Root no proot: o Claude Code só aceita `--dangerously-skip-permissions` com `IS_SANDBOX=1`, e o
  socket de mensagens precisa de caminho explícito (o proot não mapeia uid). Os atalhos `cl`, `clc` e
  `clr` do Termux já fazem isso.
- O proot do Android não tem `/dev/fd` (evite `<(…)` em scripts que rodam lá) nem `iconv`.

## Chegar ao aparelho

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
- Para um agente trabalhar **dentro** do celular (melhor que operar de longe quando o assunto é o
  próprio aparelho), abra uma sessão lá com o agente e um pedido; o roteiro está na skill
  `tt-terminais`, seção "Agente lança agente em outra máquina".

## Shell do sistema sem root

Duas portas para o mesmo privilégio (`uid shell`):

| Porta | Como nasce | Depende de Wi-Fi? | Até quando |
|---|---|---|---|
| adb local | o adb do Termux pareado **uma vez** com a depuração sem fio do próprio aparelho (`adb-local parear PORTA CÓDIGO`) | a depuração sem fio sim; `127.0.0.1:5555`, aberto depois com `adb-local tcpip`, não | 5555 até o próximo reboot |
| Shizuku | servidor iniciado com `uid shell` pelo adb, pela biblioteca do próprio app (`libshizuku.so`) | não, depois de iniciado | até o próximo reboot |

- Teste antes de agir: `tt-rish --ok` (Shizuku) e `adb-local status` (adb). Prefira
  `tt-rish -c 'comando'`: não depende de adb nem de Wi-Fi.
- `adb-local conectar` acha a porta da depuração sem fio (ela muda a cada vez: varre 30000 a 50000)
  e guarda o endereço que funcionou em `~/.local/state/tt/adb-serial`. Endereço sempre `127.0.0.1`:
  o IP da tailnet não serve para o adb.
- Saída longa do `rish` pode chegar fora de ordem: mande o comando gravar em `/sdcard/…` e leia o
  arquivo depois.

## Depois de um reboot: o papel do Tasker

No reboot tudo cai: o Shizuku (sem root ele não sobrevive), o `127.0.0.1:5555` e a depuração sem fio.
Para religar, alguém precisa ligar a depuração sem fio, e isso é um ajuste protegido
(`settings put global adb_wifi_enabled 1` exige `WRITE_SECURE_SETTINGS`). O Termux sozinho não tem
esse direito, e quem o teria (adb, Shizuku) está justamente fora do ar. O Tasker quebra o círculo:
ele recebe `WRITE_SECURE_SETTINGS` **uma vez**, pelo adb
(`pm grant net.dinglisch.android.taskerm android.permission.WRITE_SECURE_SETTINGS`, feito pelo
`android-ajustes.sh`), e a permissão sobrevive a reboot e a desligar o modo dev.

O projeto `termux/tasker/tt-celular.prj.xml` traz quatro perfis:

| Perfil | Gatilho | O que faz |
|---|---|---|
| `tt: abrir no boot` | o aparelho ligou | liga o modo dev e o adb, espera, abre o Termux (Termux:Boot sobe sshd, cron e tmux) e volta à tela inicial |
| `tt: ligar modo dev` | intent `tt.MODO_DEV_ON` | liga o modo dev e a **depuração sem fio** |
| `tt: desligar modo dev` | intent `tt.MODO_DEV_OFF` | desliga depuração sem fio, adb e modo dev (o Shizuku cai junto) |
| `tt: estado do Wi-Fi` | Wi-Fi conectado / caiu | grava `1 <ms>` / `0 <ms>` em `/sdcard/Tasker/estado/wifi` |

As intents saem do Termux sem privilégio nenhum: `am broadcast -a tt.MODO_DEV_ON`.

A cadeia, sem tocar na tela:

1. O aparelho liga; o Tasker liga o modo dev e abre o Termux; o Termux:Boot sobe sshd, cron e tmux.
2. Ao conectar num Wi-Fi já autorizado para a depuração sem fio, o Tasker grava `1 <ms>`.
3. O `shizuku-vigia` (cron, a cada 2 min) vê "Shizuku fora + Wi-Fi novo" e roda `shizuku-ligar`.
4. `shizuku-ligar`: intent para o Tasker ligar a depuração sem fio, `adb-local conectar` (já
   pareado), inicia o Shizuku pela `libshizuku.so` do app e abre `127.0.0.1:5555`.
5. Pronto: Shizuku e adb local ficam de pé até o próximo reboot.

O vigia tenta **uma vez por conexão Wi-Fi**: numa rede nova o Android pergunta se permite a depuração
sem fio nela, e insistir só enche a tela de diálogos. Sem o Tasker, o vigia sabe do Wi-Fi pelo
`termux-wifi-connectioninfo` (Termux:API), mas a depuração sem fio volta a ser ligada à mão. O
`~/.config/tt/shizuku-ok` (opcional, executável) roda a cada volta do vigia com o Shizuku de pé: é
onde o usuário põe serviços próprios que dependem dele.

## O Wi-Fi só é preciso uma vez por boot

A depuração sem fio do Android só funciona com Wi-Fi conectado, e é ela que dá o primeiro adb depois
de um reboot. Daí em diante o Wi-Fi pode cair: o Shizuku é um processo que já está rodando, e o
`127.0.0.1:5555` é o adbd escutando no loopback, que não depende de rede nenhuma. Só um novo reboot
pede outra conexão Wi-Fi (numa rede já autorizada).

Com o shell do sistema o agente também mexe no Wi-Fi: `cmd wifi status`,
`cmd wifi set-wifi-enabled enabled`, `cmd wifi connect-network <rede> wpa2 <senha>` (a ajuda completa
em `cmd wifi help`). Serve, por exemplo, para religar o Wi-Fi e preparar um novo pareamento ou um
novo `shizuku-ligar` enquanto o Shizuku ou o 5555 ainda estão de pé. Desligar Wi-Fi, adb ou modo dev
pode cortar o único canal: pergunte antes.

## Operar a tela

Pelo shell do sistema (`tt-rish -c '…'` ou `adb -s 127.0.0.1:5555 shell '…'`):

| Para | Comando |
|---|---|
| saber o app da frente (confira **antes** de tocar: a pessoa pode estar usando outro app) | `dumpsys window \| grep -E 'mCurrentFocus\|mFocusedApp'` |
| ver a tela | `screencap -p /sdcard/Download/tela.png` e traga o arquivo (`tt --trazer`) |
| achar elementos | `uiautomator dump /sdcard/Download/ui.xml` (texto, id e `bounds` de cada elemento; toque no centro) |
| tocar, arrastar, digitar | `input tap X Y`, `input swipe X1 Y1 X2 Y2 300`, `input text 'palavra'` (espaço vira `%s`) |
| teclas | `input keyevent KEYCODE_BACK`, `KEYCODE_HOME`, `KEYCODE_ENTER`; `111` (Esc) fecha painéis, mas pode descartar o que estava sendo editado |
| abrir link num navegador, na frente | `am start -a android.intent.action.VIEW -n <pacote>/<atividade> -f 0x10000000 -d '<url>'` |

- Vindo do app Termux, `termux-open-url` e `am start` nem sempre trazem o app para a frente (o Android
  barra atividade iniciada em segundo plano). Pelo `uid shell` funciona.
- Nunca digite senha nem código com `input text`: peça para a pessoa digitar.
- Retorno de login (OAuth) para `http://127.0.0.1:PORTA` aberto no navegador do celular chega a um
  processo de outra máquina por túnel reverso: `ssh -N -R 127.0.0.1:P:127.0.0.1:P <dest>`, rodado na
  máquina onde o processo escuta. Navegador de texto (Carbonyl) é recusado no login do Google.

## Regras

- Pergunte antes de: `shizuku-desligar`, desligar Wi-Fi/adb/modo dev, desinstalar app, mudar ajuste
  que não foi pedido. Derrubar o Shizuku tira o acesso de todos os agentes.
- Confira o app da frente antes de qualquer `input`.
- Nada de segredo em comando que fica em log ou na tela (token, senha, código).
- Teste em ambiente isolado (HOME, config e tmux temporários) quando o teste mexe em estado do tt:
  um `tt --fixar` de teste no HOME de verdade vai para a barra de todas as máquinas.

## Diagnóstico

```bash
tt-rish --ok && echo shizuku ok            # Shizuku
adb-local status                           # adb local e o endereço guardado
cat /sdcard/Tasker/estado/wifi             # o que o Tasker viu do Wi-Fi ("1 <ms>" conectado)
crontab -l | grep shizuku-vigia            # vigia no cron
tail ~/.local/state/tt/shizuku.log         # o que o vigia e o shizuku-ligar fizeram
termux/celular.sh verificar                # o que está montado e o que falta (no clone do tt)
```

Pegadinhas: o código de pareamento some quando a tela de pareamento fecha (use tela dividida); no
Android 14+ o `rish_shizuku.dex` precisa ser só leitura (`chmod 400`); o Shizuku pode cair logo depois
do `adb tcpip` (o adbd reinicia) e o `shizuku-ligar` o sobe de novo pelo 5555.
