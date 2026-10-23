# tt — central de terminais

O nomeador automático de abas usa, nesta ordem, o [nomeador local](#nomeador-local-de-abas) (um
modelo open source leve rodando na própria máquina, se instalado), o Haiku pelo rotator (`claude-rot`,
ver [Contas de IA](#contas-de-ia), com `--claude-only`, sem ferramentas) ou outra máquina do tt.
Falhas de execução, limites e respostas fora do formato de nome são rejeitados, inclusive quando vêm de
outra máquina; o nome existente é preservado. O título da conversa continua sendo usado sem consulta
ao modelo quando disponível.

Um menu só para todas as sessões tmux de todas as suas máquinas: entre, crie, divida, busque e
mande arquivos de uma para outra, pelo teclado, mouse ou toque (celular com Termux + mosh).

As máquinas se enxergam por ssh. Com [Tailscale](https://tailscale.com), fica automático: o `tt`
encontra as máquinas da sua rede, sabe quais estão ligadas e usa o Tailscale SSH.

## O que faz

- **Central** (`tt`, `Ctrl+B s` ou ☰ na barra): sessões de todas as máquinas, com prévia ao vivo;
  busca em nome, título da conversa do Claude Code e conteúdo da tela (a prévia pula para o
  trecho achado); filtro por máquina; cada painel de cada sessão; janelas vazias agrupadas, com
  "fechar todas".
- **Barra clicável**: `máquina ▾` (máquinas, versões, cadastro), `sessão ▾` (seletor rápido com
  rolagem), ☰ central, ┃/━ dividir, ⋯ menu do painel (enviar/trazer arquivos, acompanhar transferências), 📧 e-mail (abre o cliente de
  terminal numa subjanela, como a central; `aerc` por padrão, configurável), ⤢ caber nesta tela (quando duas
  telas de tamanhos diferentes usam a mesma sessão). Botão direito também abre os menus. A **roda do
  mouse** sobre `máquina ▾` troca de máquina (vai à primeira sessão da lista de lá; máquina que não
  responde é pulada) e sobre `sessão ▾` troca de sessão nesta máquina (veja [Roda nos chips](#roda-nos-chips)).
- **Uma sessão, vários aparelhos**: a janela tem o tamanho do aparelho que você está usando: tecla,
  toque ou clique, foco na janela, girar o celular ou abrir o teclado passam a sessão para ele na
  hora, e o outro toma de volta assim que for usado. Quem só está olhando vê ⤢ na barra (um toque
  encaixa nele). A janela nunca fica presa num tamanho fixo.
- **Copiar e colar iguais em todo lugar**: segure **Ctrl** para copiar com o mouse —
  arrastar copia a seleção (também sobre o Claude Code, o Codex e sessões de outra máquina), duplo clique
  a palavra, triplo a linha; sem a tecla, arrastar e clicar vão ao programa e nada é copiado (sem cópias
  por acidente poluindo o histórico). Sempre com o aviso
  "📋 copiado (N caracteres)"; a cópia vai para a área de transferência do aparelho em uso (PC,
  Windows/WSL ou celular via mosh). O que a tela partiu em linhas — um endereço, caminho ou código
  longo quebrado na borda, com recuo ou borda na linha de baixo, como no Claude Code — volta a ser
  uma coisa só na cópia; quebras de verdade ficam. Colar: Ctrl+Shift+V, botão do meio ou
  ⋯ → 📋 Colar; no celular, ⋯ → 📋 Copiar o texto da tela. Shift+arrastar continua sendo a seleção
  do terminal (essa não passa pelo tt).
- **Links clicáveis em qualquer painel**: clique num endereço (http/https) abre a mesma escolha de
  navegador do e-mail (veja "Links: escolha do navegador"), com a URL inteira mesmo quando ela está
  quebrada em várias linhas; Ctrl + duplo clique copia o link inteiro; Ctrl+B u (ou ⋯ → 🔗 Links da tela)
  lista os links do painel e do histórico. Vale também sobre programas que usam o mouse (Claude
  Code, aerc): fora de um link, o clique continua indo para eles.
- **Painéis com outras sessões**: `^v` ao lado, `^o` embaixo, `^p` troca — inclusive sessões de
  outra máquina. Uma sessão de outra máquina vista daqui vira uma "ponte"; trocar de sessão pela
  barra de lá troca a sua tela de verdade (sem ponte dentro de ponte).
- **Arquivos entre máquinas**: navegador de pastas (→ entra, ← sobe, Tab marca, ⏎ confirma), escolha
  da máquina e da pasta (a de cada sessão de lá aparece como opção). Nunca sobrescreve: conflito
  vira `nome (2)`. Quem recebe vê um aviso na tela. Rodam em segundo plano: a barra
  mostra o andamento ("⇅ 62% 14M/s") e avisa ao terminar. As entradas ficam no menu do painel (⋯):
  enviar, trazer, o caminho copiado, recebidos recentes e acompanhar. Antes de começar, um resumo
  (itens, tamanho, conflitos, espaço livre) pede ⏎; ⏎ também repete a última rota. A tela de
  acompanhar tem seleção por ↑↓ e rolagem; `c` cancela (pergunta passando de 50 %), `l` mostra o
  log, `r` tenta de novo, `o` abre o destino, `x` limpa as terminadas. Falhas dizem a causa
  provável (sem espaço, sem permissão, máquina inalcançável). Ao fim, contagem e tamanho são
  conferidos nas duas pontas (`TT_CONFERIR=1` confere por sha256). Um arquivo único grande
  (≥ 100 MB, `TT_RETOMAR_MIN`) é retomável: se a conexão cair, a parte fica no destino e `r`
  continua dali.
- **⚙ tmux**: janelas, layouts, digitar em todos os painéis, histórico, mouse, atalhos, editar e
  recarregar a configuração, desanexar telas.
- **Nomes automáticos**: sessões genéricas ganham nome pelo assunto (título do Claude Code, ou o
  Claude Haiku lendo a tela, se o `claude` estiver instalado).


## Snapshots do estado (histórico e restaurar)

Funcionalidade **ativável** (`tt --snapshots on`; desligada de fábrica). Ligada, o tt grava um snapshot do estado **desta máquina**
a cada mudança que você faz: sessão ou aba criada, fechada ou renomeada, painel dividido, troca do agente de IA de um painel e
mudança nas fixadas. Fica guardado até **50** (o mais antigo sai), cada um com data e hora, o motivo ("aba criada: site") e o que
tem dentro:

- as sessões e abas na ordem, com layout, pasta e programa de cada painel;
- o agente de IA de cada painel (Claude, Codex ou Kiro): o código da conversa e a conta;
- as fixadas, na ordem.

Rajadas viram um snapshot só (`TT_SNAP_ESPERA`, 4 s) e estado igual ao último não grava de novo. A troca de agente num painel não tem
gancho no tmux; o vigia a percebe a cada volta.

`tt --snapshots` (também `Ctrl+B S` e menu administrar → 📸) abre a lista com data e hora e a prévia da árvore de cada um; ⏎ restaura. **O modo é
perguntado a cada vez**: *aditivo* (padrão: recria só o que falta e não fecha nada do que está aberto; as fixadas que faltam voltam) ou
*substituir* (deixa igual ao snapshot: fecha o que não está nele, menos a sessão em uso e as ocultas, e as fixadas ficam como estavam;
pede "sim"). Antes de restaurar o tt grava o estado de agora, então a restauração também se desfaz.

**Cada agente de IA é retomado na mesma conversa**, do jeito da máquina e sempre sem pedir permissões (`ia-conta retomar`):

| Agente | Comando |
|---|---|
| Claude | `claude --dangerously-skip-permissions --resume CÓDIGO` (na conta do snapshot, ou na principal se ela não existe aqui) |
| Codex | `codex resume CÓDIGO --dangerously-bypass-approvals-and-sandbox` |
| Kiro | `kiro-cli chat --v3 --trust-all-tools --resume-id CÓDIGO` |

Linux, macOS e WSL chamam o `ia-conta` direto; no Termux o comando entra no Debian do proot (`proot-distro login debian --shared-tmp -- bash -lc …`),
onde os agentes vivem, e na pasta de dentro do proot; como root, o `ia-conta` liga `IS_SANDBOX=1` sozinho. Se a conversa não está nesta máquina
(as conversas sincronizam entre elas, mas pode não ter chegado), abre uma sessão **nova** do mesmo agente, também sem pedir permissões, com aviso.

`tt --snapshots [on|off|status]`, `tt --snapshots-listar`, `tt --snapshot-ver ID`, `tt --snapshot-restaurar ID [aditivo|substituir]`,
`tt --snapshot-agora`. Arquivos: `~/.local/state/tt/snapshots/*.json` (`TT_SNAP_DIR`; teto `TT_SNAP_MAX`=50). Teste: `tests/test_snapshots.sh`.

## Busca na conversa inteira

A busca da central (`tt`, `Ctrl+B s`) sempre achou texto no nome, na máquina, na pasta, no título do Claude e no **fim da tela**
(150 linhas, 2500 caracteres). Agora ela tem um 3º escopo, **conversa**: `^e` (ou clique no cabeçalho) alterna
`tudo → nomes → conversa`. No escopo conversa a lista vem de um índice de texto completo (SQLite FTS5, só biblioteca padrão):

- a **conversa inteira** do agente de IA de cada painel (Claude, Codex, Kiro, lida pelo `sessoes-ia.py`);
- o **scrollback inteiro** do tmux de cada painel (não só a janela de 150 linhas);
- sem acento nem maiúscula (`autenticacao` acha "Autenticação"), várias palavras em qualquer ordem, prefixo (`autent`),
  `"frase exata"` entre aspas e `!palavra` para excluir; o melhor resultado vem primeiro, com um pedaço do trecho ao lado do nome;
- as outras máquinas respondem ao mesmo tempo (ssh em paralelo); a prévia mostra as últimas ocorrências, com contexto e destaque.

O vigia reindexa a cada `TT_T_BUSCA` s (180; 0 desliga) só o que mudou (assinatura `mtime:tamanho` da conversa; scrollback pelo
tamanho do histórico e o fim da tela) e esquece painel e conversa que sumiram. Índice em `~/.cache/tt/busca.db`
(`TT_BUSCA_DB`; teto de `TT_BUSCA_MAX_KB`=16384 KB por fonte). `busca_conversa=0` no config, `tt --busca off` ou o menu administrar → 🔎 desliga.

`tt --busca [estado|agora|on|off|consultar TEXTO]`; `tt --busca-consulta TEXTO` (o que as outras máquinas respondem). O mesmo índice guarda também as **conversas antigas** de todas as contas (`tt --busca-conversas TEXTO`; veja a voz, abaixo).
Teste: `tests/test_busca_conversa.sh`.

## Atalhos no Mac

No macOS alguns atalhos do tt mudam, porque o sistema ou o terminal se metem no caminho. `tt --mac atalhos` mostra a tabela e
`tt --mac status` diz o que está ligado no terminal em uso.

| No tt (Linux) | No Mac | Por quê |
|---|---|---|
| `Ctrl+B …` | `Control+B …` | igual |
| Ctrl+arrastar, duplo e triplo clique (copiar) | Option+arrastar, duplo e triplo clique | o macOS transforma Ctrl+clique em botão direito |
| Ctrl+clique num link | Option+clique (ou `Ctrl+B u`) | idem |
| Alt+… | Option+… | o Option só vira Meta se o terminal for configurado |
| Ctrl+Shift+V (colar) | Cmd+V | colar do próprio terminal |
| `Ctrl+B F1`…`F10` | `Ctrl+B g 1`…`0` | sem a tecla fn, F1–F10 viram brilho e volume (`g`, depois 1 a 9 e 0) |
| `Ctrl+B [`, `v`, `y` | igual | copia sem mouse |

`tt --mac ativar` liga o Option como Meta: no **Terminal.app** grava `useOptionAsMetaKey` no perfil padrão (com cópia em
`~/.config/tt/backup`; vale em janelas novas) e no **Ghostty** acrescenta `macos-option-as-alt = true` ao config. No iTerm2
(Profiles › Keys › Left Option key = Esc+) e no WezTerm o `tt --mac status` só orienta. Para forçar o terminal:
`TT_MAC_TERMINAL=terminal|ghostty|iterm|wezterm`. Teste: `tests/test_mac_atalhos.sh`.

## Requisitos

bash, git, tmux ≥ 3.4, fzf ≥ 0.60, python3, ssh, tar (GNU) e `rg` (testes e busca rápida).
Opcionais: tailscale, mosh (celular), pv (barra de progresso nas cópias), claude (nomes automáticos).

`tt --pendencias` mostra, para a máquina em que você está, tudo isso e mais o que os recursos pedem (aerc,
mbsync, w3m, vim, Chrome, Carbonyl, bibliotecas, clipboard, notificações…), o que está pronto e o que falta;
o [modal de pendências](#pendências-de-instalação-) instala o que faltar.

Plataformas: Linux (Debian, Ubuntu e derivados, incluindo WSL; Fedora/RHEL; openSUSE; Arch; Alpine; Void),
macOS (Homebrew), Termux no Android, Linux (Debian) dentro do proot do Termux e FreeBSD, OpenBSD e NetBSD.
Os navegadores baixados (Chrome e Carbonyl) são binários glibc x86_64: só entram em Linux x86_64 com glibc.

macOS: bash ≥ 4 e as demais dependências pelo Homebrew (`brew install bash tmux fzf ripgrep`). O `./instalar.sh` instala também as ferramentas GNU (coreutils, gnu-sed, gnu-tar, findutils, grep, gawk, util-linux) e um Python novo; o tt as põe na frente do PATH só dos processos dele. Como o
ssh não interativo do macOS (zsh) não carrega o Homebrew, a instalação acrescenta ao `~/.zshenv` um
bloco entre marcadores que põe `~/.local/bin`, `/opt/homebrew/bin` e `/usr/local/bin` no PATH, e todo
comando que o tt manda para outra máquina já leva esse PATH. A instalação também garante Node.js e Tailscale
e ativa automaticamente o fallback WebSocket local versionado do Tailscale (`tt --tailscale-ws status` para conferir).
Não é preciso `setopt NO_EQUALS`.

## Instalação

    git clone https://github.com/helio-nogueira-cardoso/tt-terminais.git && cd tt-terminais
    ./tt --instalar [nome-desta-máquina]

Ou, instalando automaticamente as dependências que faltarem:

    ./instalar.sh [nome-desta-máquina]

O instalador detecta o gerenciador de pacotes (apt, dnf/yum, zypper, pacman, apk, xbps, Homebrew, pkg do
Termux ou do FreeBSD, pkg_add, pkgin) pela família da distro, instala tudo em uma única etapa, traduz os
nomes de pacote entre as distribuições (tabela conferida em cada uma) e verifica novamente os comandos antes
de instalar o tt. Usa `sudo`, `doas` ou `su` conforme houver (e nada no root, no Homebrew e no Termux); se
um pacote não existir na sua distro, os outros continuam. Em Linux, pode ser necessário informar a senha
uma vez. No macOS com o bash 3.2 de fábrica, instala o bash atual pelo Homebrew e recomeça com ele.
Quem não tem `bash` (Alpine e Void mínimos) instala-o antes: `apk add bash`, `xbps-install bash`.

Isso põe o tt em `~/.local/share/tt/`, liga `~/.local/bin/tt` a ele, faz o `~/.tmux.conf` carregar o
`tmux.conf` do tt (o antigo fica em `~/.tmux.conf.antes-tt`) e **configura o `~/.bashrc`** para cada
janela de terminal abrir já dentro do tmux e aparecer na central. O bloco é acrescentado ao fim,
entre marcadores, uma única vez (backup em `~/.bashrc.antes-tt`). Ajustes só daquela máquina vão no
perfil, em `~/.config/tt/tmux.conf` (veja abaixo).

### Onde fica cada coisa

O tt separa o que é geral do que é seu, para dar para compartilhar, atualizar e versionar cada parte
sem misturar:

| Lugar | Papel | Quem escreve |
|---|---|---|
| `~/.local/share/tt/` | **pacote** geral, igual para qualquer usuário; trocado inteiro a cada instalação | só o instalador |
| `~/.config/tt/` | **perfil**: só escolhas suas (veja a lista abaixo) | você e os menus do tt |
| `~/.local/state/tt/` | **estado** que o tt gera sozinho: memória dos agentes, avisos, perfil do celular aplicado | o tt |
| `~/.cache/`, `/run/user/UID` | caches e travas, descartáveis | o tt |

Arquivos do perfil (todos opcionais, exceto `config`):

    config             nome desta máquina e opções (recebidos=, claude_flags=, tela_destino=, …)
    maquinas           máquinas cadastradas: host usuario rótulo
    atalhos            atalhos da barra além dos padrões (mesmo ID substitui; emoji - desativa)
    fixadas            sessões fixadas (sincronizada entre as máquinas)
    tmux.conf          ajustes de tmux só seus, carregados depois do tmux.conf do pacote
    termux.properties  barra de teclas do Termux própria (o celular.sh usa esta no lugar da geral)
    AI-DLC.md          política AI-DLC própria, no lugar da do pacote

Por isso o perfil pode virar um repositório git privado seu (ou ser copiado para outra máquina) sem
levar código junto, e o pacote pode ser atualizado ou reinstalado sem perder nada seu. O
`~/.tmux.conf` e o `~/.bashrc` só ganham os pontos de ligação (uma linha `source-file` e um bloco
entre marcadores).

### AI-DLC para qualquer motor

Toda instalação do tt também disponibiliza uma política neutra (`AI-DLC.md` do pacote, ou a sua em
`~/.config/tt/AI-DLC.md`, se existir) e expõe seu caminho em `TT_AIDLC_POLICY`. Quando um agente identificar o
início de uma tarefa em qualquer projeto — pequeno, grande, greenfield ou brownfield — ele deve
preparar a estrutura local antes de editar código:

    tt --aidlc [raiz-do-projeto]

O comando é idempotente, detecta os motores de IA instalados e chama o adaptador AI-DLC de cada um.
Em brownfield, preserva a configuração existente e não usa `--force`. A convenção comum fica no
`AI-DLC.md` do projeto; adaptadores específicos podem coexistir, mas não substituem essa fonte
neutra. Se o runtime `aidlc` ainda não estiver instalado, o comando deixa um marcador `.aidlc/`
e informa o que falta, sem fingir que o workflow foi configurado.

### Cores iguais em todas as máquinas

O pacote inclui a paleta **Catppuccin Mocha** em `tema-terminal.sh`: ela configura as 16 cores ANSI, o fundo
e o texto do terminal ao abrir um shell, e o `tmux`/`fzf` usam a mesma paleta. Windows Terminal,
GNOME Terminal/VTE e Termux aceitam essa configuração; terminais que não aceitam as sequências de
cor simplesmente a ignoram. Para mudar o padrão, edite esse arquivo e as cores do `tema-tmux.conf` no
clone de origem, faça commit e rode `tt --sincronizar`. Todas as máquinas cadastradas recebem o
mesmo pacote; `tt --atualizar --todas` faz o mesmo a partir da versão publicada.

### Padrão visual completo

O tt fixa texto, fundo, paleta ANSI, barras, bordas e popups no tmux, além das cores do
terminal externo. Reaplica o padrão ao conectar, sincronizar e a cada cinco minutos;
clientes aninhados e pontes também recebem a paleta. Todos os clientes conectados são
redesenhados, incluindo o atual, sem encerrar sessões ou processos. Sessões desanexadas
herdam o padrão e são desenhadas ao conectar. Desvios locais de texto, fundo e paleta dos
painéis são removidos nessa reaplicação.

    tt --reforcar-padrao aplica os temas dos agentes e redesenha todos os clientes
    tt --redesenhar    reforça o padrão visual e redesenha todos os clientes desta máquina
    tt --tema-agentes  reaplica as preferências visuais dos agentes instalados

Os atalhos da barra aplicam o padrão completo antes de iniciar o programa. O Codex guarda
as cores padrão do terminal ao iniciar; corrigir o terminal e redesenhar o tmux não limpa
esse cache. Se uma conversa antiga continuar com blocos claros, use `/quit` e
`codex resume <id-da-conversa>` para retomá-la com as cores novas, sem perder o histórico.
O tt não encerra agentes automaticamente para fazer essa atualização.

Os agentes já abertos podem precisar de reabertura para ler sua configuração novamente;
o redesenho do tmux não obriga o agente a reler preferências nem substitui cores RGB que
ele próprio desenha. A sincronização distribui o mesmo padrão às máquinas cadastradas.

### Temas dos agentes

Junto com a paleta do terminal, a sincronização aplica `tema-agentes.sh` somente aos agentes que
já existem na máquina: Claude fica no modo escuro e herda a paleta ANSI Mocha; Codex recebe
`tui.theme = "catppuccin-mocha"`; e Kiro recebe `Catppuccin Mocha`. O script altera apenas as
chaves visuais, é idempotente e nunca copia tokens, MCPs, permissões ou outras preferências entre
máquinas. Se um dos agentes for instalado depois, a verificação roda em toda nova janela de
terminal e a cada cinco minutos enquanto o tt estiver ativo.

Fica de fora do tmux: terminais de IDE, sessões SSH e shells não interativos. Para abrir uma janela
sem tmux: `NOTMUX=1 bash`.

    tt --configurar-bashrc    põe o bloco no ~/.bashrc (já feito pelo --instalar)
    tt --remover-bashrc       tira o bloco
    TT_SEM_BASHRC=1 ./tt --instalar    instala sem mexer no ~/.bashrc

### Testes

Os testes de regressão ficam em `tests/`. Para executá-los:

    tests/test_fixadas.sh

## Máquinas

    tt --cadastrar [host [usuario [nome]]]   testa o ssh, instala o tt lá e cadastra as duas
                                             máquinas uma na outra (sem host: lista as do Tailscale)
    tt --descadastrar [nome]                 tira do menu (aqui e lá); opcionalmente desinstala lá
    tt --ocultar-maquina [nome]              esconde só neste menu, preservando a configuração
    tt --mostrar-maquina [nome]              restaura uma máquina ocultada
    tt --sincronizar [nome…]                 instala esta versão aqui e nas cadastradas
    tt --diagnosticar [nome]                 por que uma (ou todas) não conecta, camada por camada
    tt --saude                               painel rápido: verde conecta, vermelho online sem acesso
    tt --reparar [nome]                      reautoriza a chave desta máquina usando outra como ponte
    tt --versao                              versão instalada ("N hash data")

### Quando uma máquina para de conectar

Uma máquina pode estar ligada no Tailscale e mesmo assim recusar o acesso: a rota existe,
mas falta a chave no `authorized_keys` de lá, ou a policy do tailnet não libera aquele
usuário. `tt --diagnosticar` separa as camadas (desligada, sem rota, porta fechada, precisa
aprovar no navegador, policy nega, sem chave, timeout) e diz qual é o caso. `tt --reparar`
resolve o caso mais comum, "sem chave": procura outra máquina cadastrada que ainda acesse a
que quebrou e, por ela como ponte, reautoriza a chave desta máquina, sem precisar de senha.
O `--cadastrar` já deixa a chave autorizada no destino, para o acesso direto não depender de
configuração manual.

Os menus e a barra pulam as máquinas que o Tailscale dá como desligadas. Só a marca "Online" dele não basta: ela é a
visão do servidor de coordenação e às vezes oscila com a máquina de pé e o ssh funcionando. A máquina sai da lista só
quando o Tailscale a dá como fora, não há tráfego recente com ela e ela foi vista pela última vez há mais de 5 min
(`TT_TS_TOLERANCIA`, em segundos). E o clique para ir a uma sessão dela (uma fixada, uma ponte) tenta o ssh assim mesmo:
se ela responder, vai; senão, avisa que ela não respondeu.


Tudo isso também está no menu de máquinas (clique no nome da máquina na barra). Configuração:

    ~/.config/tt/config     nome=<como esta máquina aparece>   repo=<clone de origem, se houver>
                            recebidos=<pasta onde chegam os arquivos> (padrão: ~/Recebidos; no
                            WSL, Downloads\\Recebidos do Windows)
                            claude_flags=<opções extras do claude nos botões CL, CLC e CLR>
                            claude_env=<variáveis para o claude nesses botões, ex.: IS_SANDBOX=1>
                            email=<cliente de e-mail do botão 📧; padrão aerc. A conta e as
                            credenciais ficam na config do próprio cliente, nunca aqui>
                            email_padrao=<conta do tt --email-enviar sem --conta (slug, nome ou
                            endereço)>
    ~/.config/tt/maquinas   host  usuario  nome  [oculta]  (uma máquina por linha)

## Figma: skill e recuperação de login

A [skill figma-cota](skills/figma-cota/SKILL.md) e seu script estão versionados neste clone.
Recebe links de frames, consulta o cache REST e reserva MCP para detalhes. A referência
[acesso e autenticação](skills/figma-cota/references/acesso-autenticacao.md) explica o erro de
callback local do Kiro, o login Organização por dispositivo e a validação separada do OAuth Figma.
A instalação e o reforço periódico do tt distribuem a skill completa para Claude, Codex e Kiro,
inclusive nos proots já provisionados do celular. A fonte compartilhada fica em
`~/.agents/skills/figma-cota/`; somente os quatro arquivos do pacote são atualizados, preservando
recursos locais. O reforço compara o conteúdo antes de gravar e não configura MCP nem copia credenciais.
Testes isolados: `tests/test_figma_cota.sh` e `tests/test_figma_instalacao.sh`; também fazem parte de `make test`.

## Contas de IA

O tt instala um seletor e um rotator de contas para os agentes de linha de comando: `ia-conta` e
`ia-rot` (os nomes antigos `claude-conta` e `claude-rot` continuam valendo). Contas: a principal do
Claude (`~/.claude`), as do `ia-conta`, o Codex e o Kiro. A ordem não é fixa: vai da conta com mais
**folga** agora para a com menos. A folga olha todas as janelas e quando cada uma reinicia: na de 5 h,
o que sobra (90% usada que reinicia em 10 min quase não pesa); na semanal e no mês do Kiro, o que
sobra em relação ao tempo até o reinício (20% livres com 6 dias pela frente é pouco, os mesmos 20% a
3 h do reinício são "use ou perde"). Vale a janela mais apertada; conta com alguma janela a 95% ou
mais fica de fora.

**Modelo padrão.** Quando o modelo padrão do Claude (o `model` do `~/.claude/settings.json`, ou
`--model`/`ANTHROPIC_MODEL`) tem cota semanal própria, como o Fable, as contas com essa cota livre vêm
primeiro, e a cota dele pesa na folga delas. As outras contas do Claude, o Codex e o Kiro ficam para
depois, na ordem da folga. Assim os atalhos e as passagens abrem o agente no modelo padrão enquanto
alguma conta ainda o roda; o `ia-conta listar` mostra a cota (`fable 41%`). Na rotação sem tela, a
conta que responde que o modelo exige créditos de uso passa a vez sem ser bloqueada.
`CLAUDE_ROT_MODELO` troca o modelo considerado (vazio desliga). O Claude aberto pelo `ia-conta` e pelo
`ia-rot` também roda os sub-agentes no modelo do agente que os chama
(`CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` e `CLAUDE_CODE_DISABLE_EXPLORE_INHERIT_CAP=1`; definir uma delas
antes, mesmo vazia, mantém a sua).

    ia-conta abrir                   # a IA com mais folga agora, interativa e sem pedir permissões
    ia-conta abrir --retomar ID      # idem, continuando a conversa ID se a escolhida for do Claude
    ia-conta abrir --conta NOME      # abre a conta dada (principal, um perfil, codex, kiro), sem o rotador
    ia-conta abrir --listar-contas   # as contas que dá para abrir aqui, com o uso conhecido (o menu dos atalhos)
    ia-rot --melhor                  # só diz qual seria: conta, pico e uso (sai 2 se nenhuma livre)
    ia-conta codex                   # abre o Codex (ia-conta kiro: o chat do Kiro), com os argumentos dados

    ia-conta adicionar trabalho      # login uma vez; cria o atalho claude-trabalho
    ia-conta listar                  # todas as contas, com e-mail, estado e USO da janela
    ia-conta renomear trabalho emp   # pasta, atalho, estado do rotator e botão da barra
    ia-conta remover emp             # guarda em ~/.local/share/claude-contas.removidas
    ia-conta uso --eu                # uso da conta desta sessão (saída 0 ok, 3 aviso, 4 passar)

    ia-conta cadastro                # contas de todas as máquinas: provedor, apelido, e-mail, nome aqui

**Cadastro comum:** uma conta é o par **(provedor, e-mail)** — `claude`, `codex` ou `kiro` — e o
apelido é só um rótulo. O `listar` (que tem a coluna PROVEDOR) registra as contas desta máquina num
cadastro igual em todas (`~/.config/tt/contas-ia`, enviado a cada mudança e conferido pelo vigia a
cada 30 min) e, depois da tabela, mostra as contas do Claude do cadastro que faltam aqui (o Claude é
o único com vários perfis por máquina) e apelidos locais diferentes, que são opcionais. A credencial
não é copiada: cada máquina faz o próprio login, porque duas com a mesma cópia se derrubariam quando o
token renovasse. `ia-conta cadastro nomear <apelido|e-mail|provedor:e-mail> <novo>` muda o apelido e
`ia-conta cadastro esquecer <…>` tira a conta do cadastro. Duas contas locais com o mesmo par (a
principal e um perfil logados no mesmo e-mail) são a mesma janela de uso: o `ia-rot` bloqueia as duas
juntas e nunca passa a tarefa de uma para a outra.
No macOS o Claude Code guarda a credencial no Keychain (serviço `Claude Code-credentials`, com
`-<8 hex do sha256 da pasta>` nos perfis), não no `.credentials.json`: o `ia-conta` e o `ia-login` consultam
só a existência dela no `login.keychain` (sem ler o segredo; funciona por ssh).

**Logar o que falta, de um lugar só:** `ia-login` pergunta a cada máquina do tt o que falta (contas do
Claude do cadastro que ela não tem, perfis sem credencial, Codex/Kiro instalados e deslogados),
mostra o plano e faz os logins um por um, cada um num tmux isolado na máquina certa (`tmux -L
tt-login`, longe das suas abas). Para cada um ele mostra o link (copiado para a área de
transferência; QR code se houver `qrencode`), no Claude recebe o código que a página dá e o entrega
(a página já abre com o e-mail esperado), no Codex/Kiro mostra o código do dispositivo e espera a
aprovação; no fim confere o e-mail que entrou e avisa se não é o esperado. Antes do plano ele junta
o cadastro de todas as máquinas e entrega o completo a cada uma (não há comando separado de
sincronizar: fora isso, cada mudança já é enviada na hora e o vigia confere a cada 30 min).
`ia-login --plano` só mostra o que falta. Kiro de organização: os argumentos do login (`--license`, `--identity-provider`,
`--region`) vão em `kiro_login=` no `~/.config/tt/config` da máquina. No celular, as contas ficam dentro do proot-distro: o tt
espelha o pacote no proot que já tem `/root/.local/share/tt` (links, skill, cadastro do Termux), e o
`ia-login` do Termux pergunta ao proot o que falta e roda lá os logins.

**Logar sem abrir link nem colar código (pelo celular).** O `ia-login` conversa com cada máquina por poucos verbos
(`--iniciar`, `--tela`, `--codigo`, `--enter`, `--conferir`, `--encerrar`, `--faltas`, `--principal-faltas`; ver o
cabeçalho do script), e isso permite que um agente de IA faça o ciclo inteiro por você: com o celular montado pelo tt
(controle rápido da tela) e o navegador dele logado na conta, ele abre o link no celular, anda pelo login do site e do
Google, toca em "Autorizar" (depois de conferir o "Conectado como …" da página), lê o código e o entrega ao alvo — uma
máquina por vez, menos de um minuto cada. Senha, verificação em duas etapas, CAPTCHA e outra conta o param e chamam
você. A receita completa, com uma função de bash pronta, as armadilhas e o que foi (e o que não foi) exercitado em
aparelho real está na skill `celular-android` (seção 14); `tests/test_login_pelo_celular.sh` roda essa função, extraída
da própria skill, contra um celular e um alvo simulados (26 execuções, 19 verificações). Dois logins seguidos da mesma conta no tmux 3.6
falhavam com "server exited unexpectedly"; o `ia-login` agora repete o `new-session`.

**Trocar a principal:** a principal é a credencial de `~/.claude` (o `claude` puro e a primeira da rotação);
os perfis são as outras. `ia-login --principal trabalho` (apelido do cadastro) ou `ia-login --principal
conta@exemplo.com` faz a principal de todas as máquinas passar para essa conta: o plano mostra "trocar (hoje:
outro@…)" onde for outra, pula as que já são e, para cada uma, abre o login num tmux isolado, mostra o link, recebe o
código e confere o e-mail. `ia-login --principal CONTA --plano [máquina…]` só mostra. Numa máquina só, `ia-conta
adicionar principal [--email E]`. O login novo grava por cima do antigo (os perfis não mudam) e a troca **recusa**
com um Claude aberto na principal. Uma máquina cujo `ia-login` é mais velho aparece como "sem suporte"
(rode `tt --sincronizar` nela). Tirar uma conta de todas as máquinas: `ia-conta cadastro esquecer <conta>`, `ia-conta
remover <perfil> --sim` em cada uma e, se ela era a principal, `ia-login --principal` para outra conta antes. Lembre-se de
que o logout local **não revoga** o token: ele vale no servidor até ser revogado em claude.ai (ou pelo administrador da
organização). O passo a passo completo (principal, cadastro e o tombstone `-` que deve ficar, perfis, credenciais,
atalhos, proot do celular) está na skill `rodizio-de-contas`, seção "Tirar uma conta de todas as máquinas".

A coluna **USO** mostra a janela de 5 h e a semanal do Claude e do Codex (`5h 23% · 7d 65%`) e os
créditos do mês do Kiro (o mesmo do `/usage`). O horário entre parênteses é quando a janela volta.
Os tokens do Claude vencidos são renovados pelo próprio Claude, que sai antes de gastar qualquer uso;
`listar --rapido` pula essa renovação e usa o último valor conhecido, marcado com `~`. Contas com
sessão aberta não são renomeadas nem removidas, porque o Claude aberto perderia a credencial.

O `ia-rot` roda um agente headless (`ia-rot -p "…"`, mesmos argumentos do `claude`) na primeira
conta com login e janela livre. Antes de tentar uma conta, ele consulta o uso, com cache de 5 min:
a partir de `CLAUDE_ROT_LIMITE` (95%) a conta fica para o fim e, em 100%, sai da rotação até a
janela virar. `ia-rot --status` mostra o mesmo em TSV.

**Passagem de tarefa:** `ia-rot --passar ARQUIVO [--yolo]` abre a próxima conta ou agente livre
(nunca a conta desta sessão) mandando ler `ARQUIVO` e continuar. No tmux, abre numa janela nova da
mesma aba; fora dele, roda em segundo plano com a saída em `ARQUIVO.saida`. A skill
**rodizio-de-contas**, instalada para o Claude, o Codex e o Kiro de cada máquina, ensina os agentes
a consultar o próprio uso em tarefas longas e, perto do limite, a escrever a passagem em
`~/.local/state/tt/passagens/` e chamar o `--passar`.

### Conversas das IAs iguais em todas as máquinas

As conversas do **Claude Code**, do **Codex** e do **Kiro CLI** são as mesmas em todas as máquinas do
tt: o `/resume` do Claude, o `codex resume` e o `kiro-cli chat --resume` de qualquer máquina, em
qualquer conta, acham a conversa que começou em outra. Entre as contas de uma máquina já era assim (o
`ia-conta` liga `projects`, `sessions` e o histórico de cada conta ao `~/.claude`); o tt leva isso de
uma máquina para as outras. Vem **ligado**: o vigia troca as conversas com cada máquina cadastrada a
cada 30 min (`TT_T_SESSOES_IA`, em segundos; 0 desliga o automático).

    tt --sessoes-ia              # estado: conversas daqui por IA e a última troca com cada máquina
    tt --sessoes-ia agora [rót]  # troca agora (com todas, ou só com as dadas)
    tt --sessoes-ia off | on     # desliga/religa nesta máquina (desligada, ela nem manda nem recebe)

Também no menu administrar → 🧠. O que vai: no Claude, as transcrições de `~/.claude/projects` (com
subagentes e resultados de ferramentas; a `memory/` de cada projeto fica em cada máquina); no Codex,
`~/.codex/sessions` mais a linha da conversa no banco (`state_*.sqlite`, que o `codex resume` lista) e o
nome dela; no Kiro, `~/.kiro/sessions/cli`. No celular, o Claude e o Codex de dentro do proot. Credenciais
e configurações não vão.

**A home é traduzida.** A pasta do projeto do Claude e o `cwd` das conversas dizem onde ela foi aberta;
o tt troca a home de uma máquina pela da outra (`/home/ana` ↔ `/home/asilva` ↔ `/root` do
proot), e a ida e a volta dão os mesmos bytes. O resto do caminho é igual: `~/projetos/x` aqui aparece
em `~/projetos/x` lá.

**Quem recebe decide**, conversa por conversa: falta → grava; transcrição que só cresceu do outro lado →
fica a mais longa; continuada nas duas máquinas → fica a mais nova e a outra vai para
`~/.local/state/tt/sessoes-ia/conflitos/` (nada se perde); conversa mexida há menos de 2 min
(`TT_SESSOES_QUIETO`) está em uso e fica para a próxima volta. Máquina com tt antigo, desligada ou fora
da rede é pulada. `sessoes_ia_excluir=` no config tira conversas por padrão glob sobre
`provedor/chave` (a chave do Claude começa por `@H` para a home: `claude/@H-tt-mesh/*` tira o enxame).

## Contas de e-mail

**Botão direito no 📧** → Contas (também ⚙ administrar → Contas de e-mail, `F2` dentro do e-mail ou
`tt --email-contas`); sem nenhuma conta, o próprio 📧 abre o cadastro: uma lista com cada conta
(provedor, autenticação, servidor). **⏎** abre as ações da conta (🔌 testar conexão, ✏ editar,
🔑 autorizar de novo, 🗑 descadastrar); **^n** cadastra, **^t** testa, **^d** descadastra.

O cadastro pergunta o provedor e já preenche servidores, portas e segurança: Gmail, Outlook /
Hotmail / Microsoft 365, Yahoo, iCloud, Fastmail, Zoho, Proton (via Bridge) ou **outro** — aí os
servidores são descobertos pelo domínio do endereço (base pública do Thunderbird). Formas de entrar:

- **senha / senha de app** — lida sem aparecer na tela, guardada em `~/.secrets/aerc-<conta>.txt` (600);
- **comando externo** — `pass`, `secret-tool`, Bitwarden etc.: a senha nem chega ao disco;
- **OAuth2 / SSO** — Microsoft pelo código no aparelho (abre-se o link em qualquer aparelho e digita-se o
  código) e leitura pelo Microsoft Graph; Google e outros pelo navegador. Gmail e Microsoft funcionam de
  fábrica; outros provedores pedem o ID de um app OAuth. O token de renovação fica em `~/.secrets`.

Em **ajustar** (ou ✏ editar): servidores IMAP/SMTP, portas, segurança (TLS, STARTTLS ou nenhuma, só
para localhost), usuário de login diferente do endereço, nome de exibição e pasta inicial.

Cada conta tem um arquivo sem segredos em `~/.config/tt/email/<conta>.conf`; o `accounts.conf` do
aerc é gerado entre marcadores `# >>> tt e-mail: <conta> >>>` — blocos escritos à mão ficam intactos, e as
contas do cadastro antigo são importadas sozinhas. Pela linha de comando:

    tt --email-adicionar nome=Pessoal endereco=eu@gmail.com provedor=gmail auth=senha --senha-stdin
    tt --email-adicionar nome=X endereco=eu@x.com imap_host=mail.x.com imap_porta=143 imap_seg=starttls \
       smtp_host=mail.x.com smtp_porta=587 smtp_seg=starttls auth=comando 'cred_cmd=pass email/x'
    tt --email-listar | --email-testar NOME | --email-autorizar NOME | --email-remover NOME

**Levar a conta às outras máquinas.** Credencial nunca viaja em sincronização automática: a conta só
vai quando você manda. Ao fim do cadastro guiado (com a conta já testada) o tt pergunta *Propagar esta
conta para as máquinas da rede (notebook, celular)? (S/n)*; na tela da conta (`F2` → a conta → **⇪ Propagar
para as máquinas da rede…**) há um seletor de máquinas (todas marcadas, Tab desmarca, ⏎ envia); e pela
linha de comando:

    tt --email-propagar Pessoal                  # todas as máquinas cadastradas e acessíveis agora
    tt --email-propagar Pessoal notebook celular # só essas
    tt --email-propagar Pessoal --sobrescrever   # substitui a conta que já existir lá
    tt --email-adicionar … propagar=1 --senha-stdin    # (ou propagar=notebook,celular) já manda ao cadastrar

Vai por ssh direto (o mesmo canal do tt), pelo stdin, sem arquivo intermediário: a configuração da
conta e o que houver de segredo dela em `~/.secrets` (senha de app, token de renovação do OAuth2,
client_secret). Antes de mandar o segredo o tt confere que o tt de lá já sabe receber — um tt antigo
não recebe nada (a mensagem pede `tt --atualizar`). Na chegada tudo é conferido antes de gravar (pacote
estranho, conta sem senha ou nome que colide com um bloco escrito à mão: recusado sem resíduo); os
segredos ficam com permissão 600, o bloco do aerc e o `.mbsyncrc` são regerados lá, e uma conta com
sync local chega **desligada** numa máquina sem `mbsync` (com aviso, em vez de fingir). Conta que já
existe lá fica como está, a não ser com `--sobrescrever` (no terminal, o tt pergunta). Conta OAuth2
ainda não autorizada aqui não é propagada. O aerc aberto na outra máquina vê a conta ao reabrir.

### O leitor de e-mail (aerc)

O tt deixa o aerc pronto em toda máquina (só acrescenta o que você não configurou; o que já estiver no
`aerc.conf` fica): tema **Catppuccin Mocha** igual ao do tt, pastas em árvore com a **contagem de não
lidas** (e as abas das contas também, `Trabalho (3)`), conversas agrupadas em fios, datas curtas e em
português (`08/10/26`, hoje `15:04`, este ano `02/01`), **ícones de estado** na lista (● nova · ○ não
lida · 📎 anexo · ★ estrela · ↩ respondida · ↪ encaminhada · ✎ rascunho), **prévia da mensagem**
selecionada (embaixo da lista, com a largura toda; em tela muito larga, ≥ 180 colunas, ao lado; em tela
estreita não há prévia; o que fica 3 s na prévia é marcado como lido) e e-mails em **HTML legíveis**
mesmo sem `w3m` (usa `lynx` ou o conversor do próprio tt, com os links numerados no fim).

**Tudo clicável.** No rodapé do popup há uma **barra de botões**: 📖 Abrir · + Nova · ↩ Responder ·
↩↩ Todos · ↪ Encaminhar · ▤ Arquivar · ✕ Apagar · 📁 Pasta · ☑ Tudo · ⚡ Em lote · ✉ Não lidas · 🧹 Lixeira · ⟳ Sincronizar ·
👤 Contas · ? Atalhos (em tela estreita, só os ícones; os rótulos entram conforme cabem, os dos ícones
menos óbvios primeiro); cada botão faz o mesmo que a tecla. **Esc fecha**: na mensagem aberta, volta à
lista; na lista, limpa o filtro ou a busca, se houver, e senão esconde o e-mail (o `q` também esconde).
**✉ Não lidas** (ou `F`) mostra só as não lidas da pasta aberta, em cada conta; de novo, ou Esc, mostra
todas. **☑ Tudo** (ou `Ctrl+a`) seleciona todas as mensagens da pasta aberta (com busca ou filtro ativo, só as
encontradas) e então ✕, ▤ e 📁 agem em todas; de novo, desmarca. **⚡ Em lote** (ou botão direito no 📧, ou
`tt --email-lote [CONTA] [--pasta P] [--busca B] [--acao apagar|mover|arquivar|lidas|nao-lidas] [--destino D]
[--de-vez] [--sim]`) é para milhares: escolhe a conta, a pasta e uma busca (`todas`, `nao-lidas`, `de:…`, `assunto:…`,
`antes:AAAA-MM-DD`, `maior:5m`, no Gmail também `gmail:"…"`), mostra quantas são e uma amostra, e age **direto no
servidor**, em blocos de 500 e só nas que foram contadas; de vez, ou 1000 ou mais, só digitando o número. O espelho
local acompanha depois. **Apagar sempre vai para a lixeira da conta** (a pasta que o servidor marca como lixeira), em
qualquer provedor; na lixeira e no spam apaga de vez; numa conta sem lixeira a pergunta diz que apaga de vez.
`tt --email-conferir [CONTA…] [--corrigir]` (e o `tt --checar`) confere se os comandos de cada conta têm para onde
mandar a mensagem e conserta: descobre a lixeira no servidor, traz a pasta para o espelho e regera os comandos.
**🧹 Lixeira** (ou botão direito no 📧 → *Esvaziar a lixeira*, ou `tt --email-lixeira [CONTA…]
[--sim]`) mostra quantas mensagens há na lixeira de cada conta e, depois de você confirmar, **apaga de
vez** as da conta escolhida (ou de todas), direto no servidor — a pasta que ele marca como lixeira,
nunca outra; o espelho local acompanha na rodada do sync que começa em seguida. **⟳ Sincronizar** (ou `Ctrl+s`, ou
botão direito no 📧 → *Sincronizar agora*, ou `tt --email-sync-agora`) consulta a caixa de entrada de
todas as contas **agora**, sem esperar a vez do vigia nem a pausa que ele faz depois de um erro — para
quando você está esperando um código com validade. As contas vão em paralelo; se a volta completa
estiver no meio, ela é interrompida (o vigia a refaz depois) para a caixa de entrada vir já. O botão
mostra *consultando…* e depois *✓ 2 novos* (ou *nada novo*), a mensagem aparece na tela e, se chegou
algo, o aviso de e-mail novo diz de quem é. **Os botões valem de qualquer lugar**: contas, atalhos e lixeira
são telas do tt que abrem por cima do aerc (a barra continua embaixo) e se fecham com Esc, `q` ou o
mesmo botão de novo; abrir uma com a outra aberta troca; e um botão do aerc (abrir, responder,
apagar…) com uma tela dessas na frente primeiro a fecha e depois age. Com uma mensagem sendo escrita
ou um terminal na frente, os botões do aerc não injetam letras no que está sendo digitado (eles vão por
teclas de função que só agem na lista e na leitura). A linha de status do aerc mostra só o estado
(conta, conexão, sincronização); as dicas de teclas saíram, porque os botões já dizem tudo.
**Duplo clique** numa mensagem abre; um clique numa **aba** troca de conta, numa **pasta** abre a
pasta, e a roda rola. Atalhos, na lista e na leitura:

| Tecla | Ação | Tecla | Ação |
|---|---|---|---|
| ⏎ | abrir | Esc / `q` | fechar (a mensagem / o e-mail; Esc limpa antes o filtro ou a busca) |
| `u` | lido ↔ não lido | `*` | estrela (importante) |
| `rr` / `Rr` | responder a todos / responder | `f` | encaminhar |
| `a` | arquivar | `d` / `D` | apagar (com confirmação / direto) |
| `M` | mover para pasta (Tab completa) | `Y` | copiar para pasta |
| `F` / ✉ | só não lidas (de novo, ou Esc, volta) | `/` | buscar |
| `m` | escrever | `J` / `K` | próxima / anterior pasta |
| `v` / espaço | selecionar várias (as ações valem para todas) | `?` | tela de atalhos, em português, com um ícone por assunto |
| Ctrl+j / Ctrl+k | escolher anexo (na mensagem) | `O` / `S` | abrir / salvar o anexo |
| `E` | **enviar os anexos para a pasta de recebidos de uma máquina do tt** (seletor visual) | `F2` | contas de e-mail |
| `i` | **imagens do e-mail** (anexadas, embutidas e da web): lista e abre no visualizador de imagens; as da web só são baixadas se você escolher | | |

E-mails com versão HTML abrem nela, pelo `w3m` (tabelas, cores, links), na largura da janela. Em tela
estreita (lado a lado, celular) o 📧 abre o aerc sem a barra de pastas (`J`/`K` trocam de pasta).
**Botão direito no 📧**: abrir, sincronizar agora, contas (cadastrar, descadastrar, testar), nova conta, atalhos e o estado do sync local.

**Apagar e arquivar certos no Gmail.** No IMAP do Gmail as pastas são rótulos: tirar uma mensagem
da Caixa de entrada (o que um "delete" comum faz, direto ou pelo espelho local) só a **arquiva** — ela
continua em *Todos os e-mails*. Por isso, nas contas Gmail do tt, `d` (e o botão ✕) pergunta e **manda
para a Lixeira** de verdade (`D` sem perguntar), `a` (e ▤) **arquiva** tirando da Caixa de entrada,
sem subir cópia nenhuma, e dentro da *Lixeira* e do *Spam* `d`/`D` **apagam de vez**. As outras contas
seguem com o comportamento de fábrica (lá apagar apaga). Isso vale na lista, na leitura e nos
botões; o tt escreve essas regras no `binds.conf` por conta (`[messages:account=…]`) a cada cadastro.

### Escrever e-mails

`m` (ou o botão **+ Nova**), `Rr`/`rr` responder, `f` encaminhar. Os campos (Para, Cc, Assunto) vêm
primeiro; Tab, Ctrl+j e Ctrl+k passam de um a outro. No **Para**, ao digitar aparecem os
**destinatários** com quem você já trocou e-mail (nome ou endereço, sem distinguir maiúsculas): o tt
indexa remetentes e destinatários de todas as mensagens espelhadas (`~/.cache/tt/email-contatos.tsv`,
refeito a cada volta completa do sync; os seus próprios endereços e os automáticos, tipo *noreply*,
ficam de fora) e, antes deles, os contatos que você escrever à mão em `~/.config/tt/email/contatos.tsv`
(`endereço<TAB>nome`, um por linha).

O corpo abre no **editor padronizado do tt**: o `vim` com a configuração bonita do tt mais o jeito de
e-mail — quebra em **72 colunas com format=flowed** (o aerc envia `text/plain; format=flowed`, e quem
lê reflui o texto à largura dele, no celular inclusive), **ortografia em português e inglês** (`z=`
sugere a correção da palavra; o dicionário de português baixa sozinho uma vez, 2,6 MB), sem números
de linha, começando a escrever acima da citação. `Ctrl+S` salva e vai para a **revisão**: `y` envia,
`n` descarta, `p` adia (vira rascunho), `e` volta a editar, `v` mostra como vai ficar, `a` abre o
**seletor de anexos** (os arquivos da pasta de recebidos e da sua pasta, os mais recentes primeiro;
Tab marca vários), `A` pede o caminho e `d` tira um anexo. Se `VISUAL`/`EDITOR` estiverem definidos,
valem eles (o `nano` ganha a largura 72; outros ficam como estão). Antes de enviar, o aerc **avisa**
se o assunto está vazio ou se o texto fala em anexo (*anexo, anexa, anexei, attach…*) e não há nenhum.

Cada conta pode ter uma **assinatura** (`F2` → a conta → **✎ Assinatura**, que abre o editor; uma
linha já no cadastro; `tt --email-assinatura CONTA` ou `--email-adicionar … assinatura="…"` pela
linha de comando); fica em `~/.config/tt/email/<conta>.assinatura`, entra no bloco do aerc como
`signature-file` (uma `signature-cmd`/`signature-file` sua nas linhas extras tem prioridade) e viaja
junto na propagação da conta.

### Enviar pela linha de comando (sem tela)

`tt --email-enviar` manda um e-mail por qualquer conta cadastrada, sem abrir o aerc: serve para scripts,
agentes de IA e para mandar um arquivo rápido. O tt escolhe o caminho pela conta: **SMTP** (senha, senha
por comando ou OAuth2/XOAUTH2) ou, nas contas Microsoft lidas pelo Graph, a **API do Outlook** (o app do
Outlook Mobile, padrão do tt, só tem permissão de envio nela). Acentos, HTML e anexos funcionam nos dois.

    tt --email-enviar --conta Pessoal --para ana@x.com,bia@y.com --cc chefe@x.com \
       --assunto "Relatório de outubro" --corpo "Segue o relatório." --anexo ~/relatorio.pdf
    echo "corpo vindo de um programa" | tt --email-enviar --conta trabalho --para eu@x.com --assunto Aviso
    tt --email-enviar --conta Pessoal --para eu@x.com --assunto Teste --corpo oi --ensaio   # só mostra
    tt --email-enviar --conta Trabalho --para netto@x.com --tarefa kito47  # árvore completa da tarefa
    tt --email-enviar --tarefas-ui  # escolhe várias, ensaia cada e-mail e pede confirmação

`--tarefa ID` pode repetir-se: cada tarefa principal vira um e-mail próprio, com assunto `[tt] … ~CÓDIGO`, descrição,
prazo/prioridade/tags, IDs, estados e descrições das subtarefas e rodapé do protocolo de atualização. Os atributos próprios das filhas
(prazo/hora, prioridade, repetição e etiquetas) também viajam. O diário privado `⟡` de mães e filhas não é enviado.
Use apelido, código ou prefixo aceito pelos verbos de tarefas; subtarefa isolada é recusada (envie a mãe). O envio direto usa
a mesma conta/transporte SMTP ou Outlook deste utilitário; `--ensaio` mostra sem enviar. No menu do 📋, **📨 Enviar tarefas
diretamente…** abre a seleção, permite escolher a conta, mostra o ensaio de cada mensagem e só transmite após confirmação explícita. O compositor
`tt --tarefas-email` continua disponível para revisar/editar manualmente antes de enviar.

O menu do 📧 também oferece **Enviar tarefas**, **Tarefas recebidas / Entrada** e **Remetentes autorizados**. O menu ⋯ de uma tarefa
oferece envio direto daquela tarefa. No receptor, um remetente autorizado cria uma demanda pendente na Entrada: aprovar cria a tarefa com
os mesmos IDs; reenviar gera uma proposta de atualização, com revisão dos conflitos, inclusive nas descrições das subtarefas.

O lote é validado antes do primeiro envio, tarefas repetidas são deduplicadas e a base registra a versão efetivamente enviada. Se a rede
falhar no meio, o utilitário informa quantas mensagens já saíram e em qual tarefa parou. Há limites explícitos de 1 MB de corpo e 1000
subtarefas/remoções por tarefa; excedê-los dá erro, sem cortar dados. O Outlook/Graph recebe o corpo completo, em páginas menores, preservando
acentos, identidade e autenticação da mensagem. As mensagens continuam legíveis por versões antigas; os atributos ricos das filhas exigem tt 2.6+.

Os campos têm nome em português, como no resto do tt, e aceitam o equivalente em inglês:

| Campo | Opção | Apelido em inglês | Vira o cabeçalho |
|---|---|---|---|
| conta que envia | `--conta CONTA` (slug, nome ou endereço; também `--de`) | `--account`, `--from` | `From` (nome de exibição + endereço da conta) |
| destinatários | `--para END[,END…]` (repetível) | `--to` | `To` |
| cópia | `--cc END[,END…]` | `--cc` | `Cc` |
| cópia oculta | `--cco END[,END…]` | `--bcc` | (só no envelope; nunca nos cabeçalhos) |
| assunto | `--assunto TEXTO` (obrigatório; `""` manda sem assunto) | `--subject` | `Subject` |
| corpo (texto) | `--corpo TEXTO`, `--corpo-arquivo ARQ` ou o stdin | `--body`, `--body-file` | parte `text/plain` |
| corpo (HTML) | `--html TEXTO` ou `--html-arquivo ARQ` (junto com o texto) | `--html-file` | parte `text/html` |
| anexo | `--anexo ARQ` (repetível) | `--attach` | anexo com o nome do arquivo |
| responder para | `--responder-para END` | `--reply-to` | `Reply-To` |
| em resposta a | `--em-resposta-a MESSAGE-ID` | `--in-reply-to` | `In-Reply-To` e `References` |
| sem assinatura | `--sem-assinatura` | `--no-signature` | (a assinatura da conta entra por padrão) |
| só mostrar | `--ensaio` | `--dry-run` | nada é enviado |

Sem `--conta`, vale a chave `email_padrao=` da configuração (`~/.config/tt/config`) ou a única conta
cadastrada; com várias e sem padrão, o tt para e lista as contas. A cópia nos **enviados** fica com o
provedor no Gmail, na Microsoft e no caminho da API do Outlook; nos outros, o tt grava a cópia pelo IMAP na
pasta de enviados da conta. No fim imprime `✓ enviado … · Message-ID: <…>`. Código de saída: 0 enviado,
1 falhou (servidor, login, rede; a mensagem diz por quê), 2 uso errado (conta, destinatário, assunto ou
anexo faltando, opção desconhecida). No caminho da API do Outlook os anexos somam no máximo 3 MB e a
resposta não se encadeia na conversa (a API não aceita `In-Reply-To`).

### Consulta mais rápida

Por padrão o aerc guarda os cabeçalhos em disco (`cache-headers`, em `~/.cache/aerc`): abrir uma pasta
deixa de rebaixar tudo pela rede a cada vez, o que acelera caixas grandes ou conexões lentas sem
depender de nada além do próprio aerc.

Para quem precisa de mais, cada conta pode manter um **espelho local completo** (opt-in, desligado por
padrão), com o [`mbsync`](https://isync.sourceforge.io/) (pacote `isync`): o aerc passa a ler de um
`maildir` em `~/.cache/tt/maildir/<conta>` (abertura instantânea, busca local, leitura offline do que
já baixou), e o envio continua online (SMTP, ou a API do Outlook nas contas Graph). As marcas (lido, arquivado, apagado) e as mensagens
novas sobem e descem no próximo sync. Ligue pela interface (`F2` → a conta → **🔄 Sync local**;
sem o `mbsync`, o modal de pendências oferece instalá-lo), por `tt --email-sync-local CONTA 1`
(`0` desliga; desligar volta ao IMAP direto sem apagar nada), ou já no cadastro:

    tt --email-adicionar nome=Pessoal endereco=eu@gmail.com provedor=gmail auth=senha sync_local=1 --senha-stdin

O tt gera um `~/.config/tt/mbsync/<conta>.mbsyncrc` sem segredo (a senha vem por `PassCmd`: o arquivo
de senha, o seu comando externo, ou, no OAuth2, um token renovado na hora), em três canais: o
**INBOX** sozinho (leva segundos), as **outras pastas**, e o **arquivo** do Gmail ("Todos os e-mails",
destino do arquivar) limitado às últimas 500 mensagens no espelho (`TT_EMAIL_ARQUIVO_MAX`; o servidor
segue com tudo). As pastas-rótulo do Gmail (*Importantes*, *Com estrela*) ficam fora: são visões do que
já está nas outras, e baixá-las duplicava o espelho e fazia a volta completa nunca terminar. O vigia
sincroniza em segundo plano: o INBOX a cada `TT_EMAIL_SYNC` segundos (padrão 120; `0` desliga) e a
volta completa a cada `TT_EMAIL_SYNC_COMPLETO` (padrão 1800), com teto `TT_EMAIL_SYNC_TETO` (600 s).
Como as mesmas contas costumam estar em vários aparelhos, e o Gmail atrasa as respostas de quem o
procura demais, o vigia pega leve: sem terminal em uso na máquina nos últimos 10 min, o INBOX vai a
cada `TT_EMAIL_SYNC_OCIOSO` (padrão 300); a volta completa não se repete a cada reinício do vigia
(só quando a última registrada já passou do prazo); e depois de um erro a conta espera 2×, 4×… o
intervalo (até 15 min) antes de tentar de novo, voltando ao normal no primeiro sucesso — `tt
--email-sync` à mão não espera. O `.mbsyncrc` leva `Timeout 60` (no padrão de 20 s o login lento do
Gmail estourava), inclusive nos gerados antes, na próxima atualização.
`tt --email-sync [conta]` força o INBOX agora, `--completo` força tudo, e `tt --email-sync-estado`
mostra, por conta, a última rodada de cada tipo (há quanto tempo, duração, ok ou o erro que o mbsync
deu). Contas já cadastradas migram para os canais na próxima atualização, sem baixar nada de novo.
Sem o `mbsync` instalado o cadastro com `sync_local=1` é recusado, em vez de fingir que ligou. Contas
sem o flag seguem lendo direto do servidor (IMAP) com o cache de cabeçalhos acima.

**E-mail que chega fica visível.** Nas contas com espelho local, o botão **📧** da barra mostra as
**não lidas** do INBOX (lidas do próprio espelho, sem processo na barra), fica **âmbar com ⏳** quando
o sync de alguma conta só atrasou (uma ou duas falhas passageiras, como o Gmail lento) e **vermelho
com ⚠** quando o problema persiste (3 falhas seguidas, mais de 10 min sem o INBOX sincronizar, senha
recusada — esta já na primeira) ou o sync parou; botão direito no 📧 → *Sync local: estado das
rodadas* mostra o detalhe. Depois de cada rodada do INBOX, os e-mails que **chegaram** viram um aviso
na tela dos terminais abertos e na notificação do sistema, com remetente e assunto (até 3; o resto
"e mais N") — sem repetir, e sem avisar a caixa inteira na primeira rodada. `email_aviso=0` no
`~/.config/tt/config` desliga o aviso. Contas só IMAP (sem espelho) não entram na contagem nem no aviso.
**Clicar no aviso** (na faixa ou na central de notificações) abre o leitor **na mensagem nova**, não
como ele ficou: vai à conta do aviso, à caixa de entrada, e foca a não lida mais recente (na tela
estreita, sem prévia, já a abre) — por comandos ao aerc, sem teclas cegas: uma mensagem sendo escrita
fica na aba dela. O aviso fica marcado como lido na central. `tt --email-ir-novo CONTA` faz o mesmo
pela linha de comando.

Gmail com OAuth2 funciona **de fábrica**: sem informar `client_id`, o cadastro usa o app
"Desktop" do próprio tt no Google (num app instalado o client_secret não é confidencial — o
fluxo nativo do Google assume isso, e rclone e Thunderbird embutem os deles). Quem preferir o
próprio app continua passando `oauth_client_id=`.

Microsoft (Outlook, Hotmail, Microsoft 365) com OAuth2 também: sem `client_id`, o padrão é o app público
**Outlook Mobile** e o escopo `https://graph.microsoft.com/.default`, que a Microsoft preautoriza para
esse app de primeira parte e devolve os escopos de e-mail que a conta pode usar. Isso evita a tela de
aprovação administrativa do app de terceiros em muitos tenants corporativos. `oauth_client_id=thunderbird`
usa o ID público do Thunderbird (IMAP/SMTP), e `oauth_client_id=tt` volta ao app próprio do tt; para
esses modos, informe os escopos de IMAP/SMTP correspondentes.

### Pendências de instalação 📦

Tudo o que o tt pode precisar fica num **catálogo único**, e `tt --pendencias` mostra o estado de cada
item nesta máquina (✓ pronto, ✗ falta, ! o tt não resolve sozinho, – não se aplica). Entram:

| Grupo | Itens |
|---|---|
| Essencial | ferramentas básicas (bash, tmux, fzf, python3, ssh, tar, rg, git, curl); **fzf atual** (o do sistema é velho: baixa o oficial para `~/.local/share/tt-bin`, que passa na frente no PATH do tt); tmux antigo (só orienta) |
| E-mail | aerc, mbsync (isync), **isync com SASL** (compilado na sua pasta quando o do sistema não tem LibSASL, como no Termux), plugin XOAUTH2 do SASL, w3m, vim, dicionário de português |
| Navegadores | **Google Chrome** e **Carbonyl** (baixados para `~/.local/share/tt-navegadores`, sem sudo) e as bibliotecas do sistema que eles pedem (as ~25 que o `ldd` acusa, mais GTK, Vulkan e fontes) |
| Conforto | clipboard (wl-clipboard/xclip), notificações (notify-send), xdg-utils, Termux:API, pv, mosh, nomeador local |

Cada item é **essencial** (o tt degrada sem ele), **recurso** (de uma função que você usa) ou **opcional**;
o vigia só avisa dos dois primeiros, e o menu administrar → 📦 mostra tudo. O que precisa de
administrador vai num **modal único** (`tt --pedir-sudo`, ou `--pedir-sudo ID…` para escolher) com quatro
respostas: **[i] instalar agora**, **[s] selecionar** (decide item a item), **[m] mais tarde** (pergunta de
novo em 1 dia) e **[n] não instalar** (nunca mais avisa daquilo). Para scripts e agentes,
`tt --pedir-sudo --sim` aceita tudo sem perguntar nem precisar de terminal.

O vigia confere as pendências ao iniciar e a cada 6 h e põe **um** aviso na faixa (📦 N pendências de
instalação…, que dura 6 h e só volta depois de 12 h); clicar abre o modal. O menu do 📧 também oferece
instalar o que falta para o e-mail, e o erro do sync de e-mail (`tt --email-sync-estado`) aponta a
pendência que o resolve. Quem disse "não" não é incomodado de novo, mas pode mudar de ideia: **menu
administrar → 📦 Pendências de instalação…** reavalia todas, inclusive as recusadas de vez (`TT_PEND_TODAS=1
tt --pedir-sudo`); **📋 Estado de tudo** mostra o catálogo.

Como a instalação é robusta: o gerenciador é escolhido pela família da distro e o privilégio por `sudo` >
`doas` > `su` (nenhum no root, no Homebrew e no Termux; sem nenhum, o tt mostra o comando para o
administrador rodar); tudo vai em **uma** chamada, sem perguntas (`DEBIAN_FRONTEND`, espera da trava do
dpkg) e, se ela falhar, o tt atualiza o índice e repete, e depois tenta **um pacote por vez**, para um nome
inexistente na sua distro não derrubar os outros; senha errada para na primeira tentativa. No Debian 13 e
no Ubuntu 24.04 o nome `…t64` é escolhido sozinho; no proot do Termux o apt roda com
`APT::Sandbox::User=root`. Depois o tt **confere** cada item (✓/✗); o que falhou espera 7 dias para
voltar a avisar, e o registro de cada tentativa fica em `~/.cache/tt/pendencias.log`. Downloads têm
tentativas, espaço livre checado antes, sha256 conferido e nunca deixam arquivo pela metade. Uma
instalação por vez (trava).

**Contas Google com login OAuth** (`auth=oauth`, como uma conta de ex-aluno) só sincronizam com o
plugin XOAUTH2 do Cyrus SASL, que quase nenhuma distribuição empacota. A pendência `email-xoauth2`
instala só o compilador e os cabeçalhos do SASL com o gerenciador do sistema (apt, dnf, zypper, pacman,
apk, xbps, brew, pkg) e o tt baixa o código (cyrus-sasl-xoauth2, MIT, 4 arquivos C), confere o sha256, compila em ~1 s e
deixa `libxoauth2.so` em `~/.local/share/tt-sasl2` — sem tocar no sistema. O `mbsync` a enxerga por
`SASL_PATH`, que o tt define só nas rodadas de sync (a lista padrão do sistema continua na frente).
Se o próprio `mbsync` foi empacotado sem LibSASL (é o caso do Termux), a pendência `isync-sasl` compila o
isync 1.5.1 com SASL em `~/.local/share/tt-isync` (sha256 conferido; só o compilador, o `make`, o `perl` e
os cabeçalhos vêm do gerenciador), e o tt passa a usar esse `mbsync`. O `instalar.sh` da primeira
instalação já traz o resto de uma vez, em qualquer gerenciador; o plugin XOAUTH2 é oferecido pelo modal
assim que existe uma conta OAuth com sync local.

## Tarefas

Uma lista de afazeres que acompanha você em todas as máquinas. O botão 📋 na 2ª linha da barra
(ou `Ctrl+B t`) abre o painel deslizando pela direita; `esc` fecha. O botão mostra quantas estão
abertas e fica vermelho (⚠ N) quando alguma vence hoje ou já venceu. Dentro do painel, `?` mostra
este mesmo "Como usar" (ou `tt --tarefas-ajuda` no terminal).

**Criar.** Digite no campo *buscar ou criar* e tecle ⏎: se nenhuma tarefa tiver esse texto, aparece
**+ criar tarefa** e o ⏎ cria. Também pelo botão **+ Nova** (ou `Ctrl+N`), que pede o título e,
opcionalmente, a descrição. No título dá para dizer, em qualquer ponto (tudo opcional):

| no título | vira | exemplos |
|---|---|---|
| `@…` | prazo (o dia todo) | `@hoje` `@amanha` `@seg` … `@dom` `@25/12` `@25/12/2027` |
| `@… 14h` | prazo com horário | `@sex 14h` `@amanha às 9h30` `@14:30` (só a hora: hoje, ou amanhã se já passou) |
| `!…` | prioridade | `!alta` `!media` |
| `*…` | repetir | `*diaria` `*semanal` `*mensal` (ou `*d` `*w` `*m`) |
| `#…` | etiqueta | `#casa` (a busca também acha por `#casa`) |

Ex.: `Reunião com a Ana @sex 14h !alta`. Na criação (**+ Nova**, ^n), **Ctrl+E** abre o editor
do tt: a 1ª linha é o título e o resto vira a descrição (colar texto com várias linhas também
vale). Concluir uma tarefa que repete avança o
prazo (mantendo a hora) e ela continua aberta. `@25/12` sem ano é a próxima vez que esse dia chega.

**Editar.** **✎ Editar** (`F2`, ou ⋯ menu → *✎ Editar…*) reabre o título da tarefa com os marcadores
que ela tem — `Reunião com a Ana @10/10 14h !alta *semanal #casa` — para mudar o texto e trocar,
tirar ou acrescentar marcadores; ⏎ grava relendo a frase como na criação. Tirar um marcador tira o
atributo: sem `@` a tarefa fica sem prazo, sem `!` sem prioridade, sem `*` deixa de repetir, sem `#`
sem etiquetas (o prazo volta como `@DD/MM`, ou `@DD/MM/AAAA` quando atrasado ou no ano que vem, com
a hora quando houver). A descrição não é marcador e fica como está; `Ctrl+E` abre o editor com a
frase em cima e a descrição embaixo, e o que voltar do editor vale — descrição inclusive, apagada se
você a apagar. Numa subtarefa só o texto muda (como na criação dela). ⏎ vazio, ou a frase igual,
cancela.

**Descrição.** Para não poluir a lista, a descrição tem visão própria: a tarefa que tem descrição
mostra só um **≡** no fim da linha. Abra a tarefa (▾) e tecle `Ctrl+/` (ou **⋯ menu** → *Ver a
descrição*) para ver o cartão da tarefa embaixo: título, prazo, prioridade, repetição, etiquetas, a descrição
inteira e as subtarefas; `Ctrl+/` fecha. **✎ Descrição** (`Ctrl+E`) edita no editor do tt (o vim com a
configuração do tt: `Ctrl+S` salva e sai, `:q!` cancela; `VISUAL`/`EDITOR` escolhem outro). Apagar
todo o texto tira a descrição.

**Subtarefas.** **↳ Subtarefa** (`Ctrl+S`) cria. A tarefa só é concluída quando **todas** as
subtarefas estiverem feitas: antes disso, ⏎, duplo clique, ✓ Feita, o menu e `tt --tarefa-ok` não
concluem — o painel avisa o que falta (linha ⚠ no topo) e abre a tarefa. Concluir a última subtarefa
**não** conclui a tarefa (você decide quando). Reabrir uma subtarefa, ou criar uma nova, numa tarefa
já feita reabre a tarefa. Numa tarefa que repete, concluir avança o prazo e **reabre as subtarefas**
(o checklist volta no próximo ciclo).

**Desfazer uma conclusão.** Uma tarefa que repete não fica marcada: concluir avança o prazo. Por isso
o painel avisa no topo (`✓ Ciclo feito · próximo: 14/11 · ^z desfaz`) e a linha mostra **✓ ciclo
feito** por 24 h. Concluiu um ciclo a mais? `Ctrl+Z`, **↶ Desfazer a última conclusão** no menu da
tarefa ou `tt --tarefa-desfazer ID` voltam o prazo um ciclo e devolvem a feitas as subtarefas que
aquele ciclo reabriu (as criadas depois ficam abertas). Dá para voltar até 3 ciclos. O cartão da
tarefa (`^/`) mostra quantos ciclos já foram feitos. Numa tarefa que não repete, desfazer reabre a
tarefa feita.

**Arquivo (histórico).** Em vez de só apagar, as tarefas feitas podem ser **arquivadas**: saem da
lista, da agenda e das contas, mas ficam guardadas. `Ctrl+L` (ou, no botão direito do 📋, *Arquivar ou
apagar as tarefas feitas…*) pergunta o que fazer com as feitas: **▤ Arquivar** (o padrão, ⏎) guarda
no histórico; **✕ Apagar de vez** some sem histórico; *Cancelar* não faz nada. Para uma tarefa
sozinha, aberta ou feita: menu ⋯ → **▤ Arquivar**. A tarefa vai com as subtarefas; subtarefa não se
arquiva sozinha, e a subtarefa feita de uma tarefa ainda aberta fica (é o checklist dela). A aba
**Arquivo** mostra o histórico, do arquivado mais recente ao mais antigo, com a data, e a busca vale
lá dentro; abra uma tarefa arquivada e clique em **↩ restaurar** (ou menu ⋯ → *Restaurar*) para ela
voltar à lista como estava, com as subtarefas — ou em **✕ apagar de vez**. O arquivo fica no próprio
`~/.config/tt/tarefas` (estado `arquivada`, com a data) e sincroniza com as outras máquinas como as
tarefas: arquivar e restaurar valem em todas, e uma cópia antiga noutra máquina não desfaz. Milhares
de arquivadas não pesam na lista do dia a dia.

**Prazo, horário e agenda.** O horário é opcional: sem ele o prazo vale o dia todo. **◷ Prazo**
(`Ctrl+D`) abre o calendário dizendo de qual tarefa é o prazo: clique no dia e, se quiser, num horário
(ou digite `1430`, `9h`, `18:15`); **✓ Definir prazo** grava (⏎ ou duplo clique no dia também; *sem
prazo* tira). Embaixo aparece o que já está marcado naquele dia. Com horário, a tarefa vence na hora
e o tt avisa 10 minutos antes (notificação do sistema e mensagem nos terminais abertos;
`TT_TAREFAS_ANTECEDENCIA` muda os minutos). A aba **Agenda** lista o que tem prazo, agrupado por dia e
pela hora (atrasadas no topo); clicar no título de um dia abre o calendário nele. **▦ Calendário**
(`Ctrl+T`) — e o clique no relógio da barra — abre a agenda do mês: dias com tarefas marcados com •,
as tarefas do dia escolhido (um clique marca feita) e **+ Nova tarefa** naquele dia e horário.

**Mouse** — tudo é clicável:

- **clique** numa tarefa **com subtarefas** abre/fecha os detalhes (o triângulo vira ▸ fechada / ▾
  aberta): as subtarefas e, à direita, um **⋯ menu** discreto que abre o menu da tarefa. Tarefa
  sem subtarefas não tem triângulo nem o que abrir (o clique só a seleciona); o menu dela fica no
  botão direito, em **⋯ Mais** ou em `Ctrl+O` (descrição, subtarefa, prazo, prioridade, repetir,
  mover, arquivar, apagar);
- **duplo clique** marca/desmarca como feita (☐ → ☑); numa subtarefa basta um clique;
- **botão direito** abre o menu da tarefa: feita, editar, descrição, subtarefa, prazo e horário,
  prioridade (alta/média/sem) e repetição (não/dia/semana/mês) como escolhas, subir/descer e apagar;
- no topo, as **abas** (Hoje · Abertas · Feitas · Agenda · Todas · Arquivo, cada uma com o contador),
  **▦ Calendário** e os **botões** (+ Nova, ✓ Feita, ✎ Editar, ↳ Subtarefa, ✎ Descrição, ◷ Prazo, ! Prioridade,
  ↻ Repetir, ↑ ↓, ✕ Apagar, ⋯ Mais, ? Ajuda), que agem na tarefa em foco;
- o calendário é todo clicável: dias, ‹ › (ou a roda do mouse) para o mês, *hoje*, os horários,
  *Definir prazo* / *+ Nova tarefa*, *sem prazo*, *cancelar* e, na agenda, as tarefas do dia.

**Teclado:** `⏎` feita/aberta · `→`/`espaço` abre · `←` fecha · `Tab` próxima aba · `Ctrl+N` nova ·
`Ctrl+S` subtarefa · `Ctrl+E` descrição · `Ctrl+D` prazo · `Ctrl+T` calendário · `Ctrl+P`
prioridade · `Ctrl+R` repetir · `Ctrl+K`/`Ctrl+J` sobe/desce · `Ctrl+X` apaga · `Ctrl+L` arquiva ou
apaga as feitas · `Ctrl+O` mais ações · `F2` edita · `Ctrl+/` descrição (cartão) · `?` ajuda · `esc` volta, limpa a
busca ou fecha. Apagar sempre pede confirmação. No calendário: setas mudam o dia, `<` `>`
o mês, `t` hoje, dígitos digitam a hora, `d` volta ao dia todo, `x` sem prazo, `esc` sai.

**Símbolos:** ☐ aberta · ☑ feita · ● vermelho/amarelo prioridade alta/média · ◷ prazo, com a hora
quando houver (vermelho quando venceu) · ↻ repete · ━━━ 1/2 subtarefas feitas · ≡ tem descrição ·
`#tag` · no calendário, • = dia com tarefas.

**Linha de comando:** `tt --tarefa-add-natural "texto @amanha !alta"`, `tt --tarefa-add "texto"`,
`tt --tarefa-ok ID`, `tt --tarefa-abrir ID`, `tt --tarefa-rm ID`, `tt --tarefa-editar ID "texto @prazo !prio *rep #tag"`
(relê a frase como na criação; marcador ausente tira o atributo; linhas além da 1ª substituem a
descrição), `tt --tarefa-frase ID` (a frase atual, pronta para editar), `tt --tarefa-renomear ID "texto"` (só o texto, sem ler marcadores),
`tt --tarefa-limpar` (apaga as feitas de vez), `tt --tarefas-arquivar-feitas`, `tt --tarefa-arquivar ID`,
`tt --tarefa-restaurar ID`, `tt --tarefas-arquivadas` (o histórico em texto), `tt --tarefas` (fora do
tmux, lista em texto).

As tarefas ficam em `~/.config/tt/tarefas` e vão para as outras máquinas sozinhas. A junção é por
tarefa (a alteração mais recente vence; apagar nunca "ressuscita").

### Sincronização das tarefas (P2P, repositório git, os dois)

Menu ⋯ da barra → **🔄 Sincronização das tarefas** (ou botão direito no 📋 → 🔄, ou
`tt --tarefas-sync`). Vale para esta máquina; cada uma escolhe o seu modo:

| Modo | O que faz |
|---|---|
| **P2P** (padrão) | direto entre as máquinas cadastradas, por ssh, como as fixadas |
| **Ambos** | P2P e um repositório git seu, que guarda o histórico de todas as mudanças |
| **Git** | só pelo repositório |
| **Desligada** | esta máquina não envia nem busca |

O endereço do repositório (de preferência privado) é conferido antes de gravar; a credencial fica no
git e no ssh da máquina. A tela mostra a última troca com o repositório ou o motivo da falha, e uma
falha que dure mais de 1 h vira um aviso na faixa (uma vez, até voltar a funcionar). Basta uma máquina
com o repositório: no modo **Ambos** ela leva ao repositório também o que chegou das outras por P2P.

    tt --tarefas-sync                      # estado: modo, repositório, última troca
    tt --tarefas-sync ambos git@github.com:voce/tt-tarefas.git
    tt --tarefas-sync agora                # sincroniza já
    tt --tarefas-sync p2p                  # volta ao padrão (o endereço fica guardado)

O clone fica em `~/.local/state/tt/tarefas-git` e é só cache: a cada volta ele é realinhado ao
repositório, o que chegou entra na lista local, a lista vai para o repositório e, se outra máquina
enviou no meio, a volta se refaz. Uma máquina que ficou sem rede retoma sozinha, sem perder nada.

## Perguntas do AI-DLC nas tarefas

O `aidlc-tt` (instalado em `~/.local/bin`) põe as perguntas de um estágio do AI-DLC na descrição de uma
tarefa: você abre a tarefa, `Ctrl+E`, escreve cada resposta depois do seu `[Answer]:` e salva. Depois o
agente colhe as respostas para o arquivo de perguntas e segue.

    aidlc-tt publicar requirements-questions.md ID   # ID da tarefa ou subtarefa
    aidlc-tt estado   requirements-questions.md      # o que falta
    aidlc-tt colher   requirements-questions.md      # grava no .md; conclui a tarefa quando tudo estiver respondido

A descrição anterior da tarefa fica no topo como anotação. Respostas iguais ou complementares se juntam;
diferentes entre o tt e o arquivo aparecem como conflito, sem sobrescrever nada.

## Faixa de notificações

Uma linha a mais na barra, colada abaixo das fixadas e sem réguas — as faixas (janelas, fixadas e esta) se
distinguem só pelo fundo, levemente diferente em cada uma, e a única folga é a margem vazia no topo; fundo
azul-acinzentado suave em toda a largura: `📧 (N) · 📋 N · ‹avisos passando› · Qui, 08/10/2026 | 13:16 · v1.5.223`.
Os avisos — e-mail que chegou, lembrete de prazo, o que vier por `tt --notificar "texto" [segundos] [destino]`
— aparecem no slot por ~10 s, **piscando devagar** em negrito, e depois vivem só na central do 🔔
(negrito até serem abertos; abrir pelo clique/⏎ marca como lido). O conteúdo do slot fica sempre
entre `│  …  │`, com o mesmo respiro mínimo em qualquer largura
— passam ali por alguns minutos e expiram sozinhos. O clique abre o DESTINO do aviso mais
recente (📧 vai para o e-mail, 📋 para as tarefas); botão direito/`tt --notifs` abre o histórico,
onde ⏎ abre o destino de cada um (↗). `tt --notificar "texto" [segundos] [email|tarefas|calendario|cmd:...]`.
A **central do 🔔** tem, no alto, abas de filtro clicáveis (**Todas · Não lidas · Lidas** e, quando há avisos
delas, **Agentes · E-mail · Tarefas**) e uma barra de botões como a do e-mail: **↗ Abrir**, **◐ Lida/não lida**,
**✓ Ler todas**, **✕ Apagar** e **🧹 Limpar lidas** (pergunta antes; a exclusão vale em todas as máquinas). Em
tela estreita os botões ficam com rótulo curto e depois só com o ícone, e as abas de origem viram 🤖 📧 📋 —
nada passa da janela. Um aviso por linha; o selecionado fica destacado (é nele que os botões agem) e a prévia
embaixo mostra o texto inteiro e o que o ⏎ faz. Teclado: ⏎ abre, Espaço lida/não lida, Tab/Shift+Tab trocam a aba, `^u` não lidas,
`^a` todas, `^d`/Del apaga, `^r` limpa as lidas, `^l` lê todas, Esc/q fecham.
O 🔔 é um só em todas as máquinas, e o mesmo evento aparece nele uma vez, mesmo quando cada máquina o percebe
sozinha: o e-mail que chega numa conta espelhada em três máquinas, o lembrete de uma tarefa, a demanda por
e-mail, o "tt atualizado". Cada aviso leva a identidade do evento (no e-mail, a de cada mensagem); a máquina que
chega depois não cria outro, e cópias criadas ao mesmo tempo viram uma na sincronização. A notificação do
sistema (a do celular, a da área de trabalho) continua saindo em cada aparelho.
Agentes de IA (e scripts) num painel do tt avisam com `tt --notificar-daqui "texto" [segundos] [--sempre]`:
o aviso só sai se você não estiver olhando para a janela de onde ele veio (o tt vê o foco pelo tmux). Ele
vai para o **🔔** (o contador na barra e a central; não pisca no miolo da faixa), fica no contador até você
abri-lo (⏎ na central leva direto àquela sessão e àquele painel) ou marcar tudo como lido (✓ Ler todas, `^l`), e vale 24 h.
Com a faixa, a linha das fixadas fica 100% para as fixadas, e o 📧 e o relógio saem da 1ª linha.
Sem aviso novo, o slot mostra o **🔔** (sempre visível; é a porta do histórico) e, se você ativar
um **letreiro** (ligado de fábrica; `indicadores=` escolhe as fontes e `indicadores=0` desliga) rolando com as infos (dólar via
AwesomeAPI, frases, e notícias G1 + BBC World por RSS — tudo sem chave, com cache; a rede roda no
vigia, nunca no letreiro). Com aviso OU transferência ativa, o letreiro cede a vez (transferências aparecem aqui, com o
andamento ao vivo — nada cobre as linhas de cima).

**Terminal interativo para agentes (`tt --pty`).** O Bash de uma IA não tem tty, então `sudo`, `ssh`, `vim` e instaladores
ficavam fora de alcance. `tt --pty abrir|enviar|tecla|ler|esperar|entrar|fechar|listar` dá a ela uma sessão tmux (`ia-pty-NOME`)
que ela digita e lê; você entra nela com `tt --pty entrar` para digitar a senha, que o agente nunca vê. Igual no Linux e no macOS.

O miolo da faixa é desenhado por um processo leve por terminal (`letreiro-tt.py`, que o tmux liga à
barra como `#()` e encerra quando o terminal sai): ele só lê arquivos e imprime uma linha quando o
conteúdo muda, e o tmux redesenha então **só a barra**, no máximo uma vez por segundo — em vez da
tela inteira. Foi isso que acabou com o flicker e o cursor dançando: qualquer opção gravada no tmux
(até uma `@opção`) redesenha a tela inteira de todos os terminais, e o letreiro antigo gravava uma a
cada passo. O slot ocupa exatamente a largura que sobra entre as pontas da linha (o tmux mede as duas
com `#{w:}` e passa ao processo) e some se não houver lugar. Quem olha por uma ponte (outra máquina,
por ssh) vê o letreiro rolar como os demais — sem redesenho de tela inteira o custo é só a barra
(`ticker_ponte=parado` o congela). Tudo configurável no `~/.config/tt/config`:
`ticker_rolagem=continua|paginas` (padrão `continua`: desliza `1/ticker_veloc` colunas por segundo —
padrão 1/`ticker_fps` → uma coluna por quadro, 6/s; `ticker_veloc=0.5` dá 2/s, `1` dá 1/s; `paginas` troca em
blocos a cada `ticker_veloc=` s — padrão 6), `ticker_fps=1..20` (quadros por segundo, padrão 6; o teto é 20 porque cada quadro além do primeiro custa um processo `bash` por cliente. O menor passo de um terminal é 1 coluna: subir o fps com a mesma velocidade só repete redesenhos, o ganho é rolar mais depressa, com `ticker_veloc` ajustando: o tmux só
redesenha a barra 1 vez/s por `#()`, mas guarda a última linha de cada um — o pintor imprime um quadro
novo a cada 1/fps s e fps−1 gatilhos de linha vazia, defasados, provocam os redesenhos entre os
segundos; custo ≈ 2 KB por quadro e ~12 MB o pintor (python) e ~4 MB cada gatilho (`gatilho-tt.sh`, só builtins do bash): 1 pintor + 5 gatilhos ≈ 32 MB por terminal; `1` volta
ao passo de 1 s), `aviso_pisca=1`
(alternância do aviso a cada segundo; padrão estático em negrito), `indicadores=` e `indicador_nome=URL ;; …` (o formato antigo, migrado sem perda: veja
**Letreiro: fontes (APIs)** abaixo, com as fontes configuráveis, o painel e o catálogo). `faixa_notif=0` no `~/.config/tt/config` desliga e devolve o layout de 3 linhas (padrão: ligada;
desligada no Termux, onde a tela é baixa). `tt --ticker-quadro [largura]` imprime o que o letreiro
mostraria agora; `tt --ticker-fontes` atualiza as fontes.

## Letreiro: fontes (APIs)

O letreiro da faixa de notificações rola informações de **fontes**, e cada fonte é um objeto configurável:
um arquivo `~/.config/tt/letreiro/NOME.conf` (perfil seu, nunca sobrescrito pela instalação) que você cria
**pela tela** (menu ⋯ → 📰 Letreiro), **pelo comando** (`tt --letreiro-add`) ou **à mão** — os três dão
exatamente a mesma fonte e a mesma linha. Quem busca, extrai, formata e guarda o cache é o
`letreiro-fontes.py`, chamado pelo vigia a cada volta; quem **desenha** é o `letreiro-tt.py` de cada
terminal, que só **lê arquivos** em `~/.cache/tt-ticker/`: a rede nunca está dentro do desenho, e uma falha
de rede nunca trava nem apaga o letreiro (o último valor segue na faixa, marcado como velho depois de um
tempo).

### O que valia até a v277 (e continua valendo)

- Três fontes nativas no código: **dólar** (AwesomeAPI, TTL 600 s; `💵 dólar R$ 5,123 ▲ 0,5%`), **frases**
  (lista embutida de 6, uma sorteada por TTL de 600 s) e **notícias** (RSS do g1 e da BBC World, 2 manchetes
  de cada, TTL 900 s). O config só ligava/desligava por `indicadores=dolar,frases,noticias`
  (`indicadores=0` desliga tudo) e `indicador_NOME=URL ;; rótulo ;; caminho.no.json ;; ttl ;; Header: @arquivo`
  criava fontes próprias (só GET; só JSON ou texto cru com o caminho `-`; um valor por fonte; valor cortado em
  60 e linha em 90 caracteres; sem formatação, sem cor, sem teste, sem diagnóstico, sem propagação, erro de
  rede em silêncio). Os ajustes globais eram `ticker_rolagem` (continua/paginas), `ticker_veloc`, `ticker_fps`
  (1 a 20) e `ticker_ponte`.
- **Nada disso quebra.** As linhas `indicador_NOME=` e o `indicadores=` são migrados sem perda para arquivos
  (`tt --letreiro-migrar`; roda sozinho na primeira atualização): o antigo corte em 60/90 caracteres
  não é levado (o letreiro não corta entradas), o header `@arquivo` continua apontando para `~/.secrets`, e um header com segredo **literal**
  tem o valor movido para `~/.secrets/letreiro-NOME` (modo 600) e sai da linha do config. As linhas antigas
  ficam no config (sem perda); depois de migrada, vale o arquivo. Se você editar `indicadores=` depois, a
  lista nova é reaplicada. `tt --ticker-fontes` e `tt --ticker-quadro` seguem funcionando.
- Única diferença visível: o texto sai pelo mesmo motor das demais fontes, então a variação do dólar usa a
  vírgula do pt-BR (`▲ 0,5%`, antes `▲0.5%`) e uma variação que arredonda para zero fica neutra (`= 0,0%`).
  A seta vem separada do número por um espaço: ▲/▼ têm largura ambígua e muita fonte os desenha de borda a
  borda da célula (ou além), colados ou por cima do algarismo.

### Arquivo da fonte

`~/.config/tt/letreiro/NOME.conf` — `chave=valor`, uma por linha (`#` comenta; repita a linha nos campos de
lista; valores com espaços nas pontas vão entre aspas: `prefixo=">> "`). `versao=1` marca o formato. As
fontes nativas (`dolar`, `frases`, `noticias`) vivem no código: um `NOME.conf` com o mesmo nome só **sobrepõe
as chaves que traz** (a definição de fábrica não é congelada no seu arquivo; `chave=` vazio desfaz um padrão).
`escopo=global` propaga a fonte pela rede; `~/.config/tt/letreiro/local/NOME.conf` sobrescreve chaves só
desta máquina.

**Identidade**

| campo | valor | padrão | o que faz |
|---|---|---|---|
| `rotulo` | texto | — | texto que rotula o valor (ex.: dólar) |
| `icone` | texto | — | ícone/emoji do item (ex.: 💵) |
| `descricao` | texto | — | descrição livre |
| `ativa` | 1/0 | `1` | 1 = entra na roda |
| `ordem` | inteiro 0–9999 | `100` | posição na roda (menor primeiro) |
| `peso` | inteiro 1–9 | `1` | quantas vezes aparece por volta |
| `tags` | texto | — | etiquetas separadas por vírgula |
| `escopo` | local/global | `local` | global = propagada pela rede (a mudança mais nova vence) |
| `perfil` | todos/desktop/celular | `todos` | só nas máquinas deste perfil |
| `maquinas` | texto | — | só nestas máquinas (nomes separados por vírgula; !nome exclui) |

**Origem e requisição**

| campo | valor | padrão | o que faz |
|---|---|---|---|
| `origem` | rede/lista/tt | `rede` | rede = HTTP; lista = itens fixos do arquivo; tt = dado do próprio tt |
| `dado` | texto | — | origem=tt: tarefas-atrasadas \| emails-nao-lidos |
| `item` | lista (repete a linha) | — | origem=lista: um item por linha (sorteia entre eles) |
| `url` | texto | — | endereço https (aceita {data} {moeda} {segredo} e var.NOME=) |
| `metodo` | GET/POST | `GET` | método HTTP |
| `header` | lista (repete a linha) | — | cabeçalho extra 'Nome: valor' (valor secreto: @arquivo) |
| `query` | lista (repete a linha) | — | parâmetro de query 'nome=valor' (repetível) |
| `corpo` | texto | — | corpo do POST (aceita {variáveis}) |
| `timeout` | número 1–60 | `10` | segundos por tentativa |
| `tentativas` | inteiro 1–5 | `2` | tentativas por atualização |
| `espera` | número 0–60 | `2` | espera entre tentativas (dobra a cada uma) |
| `user_agent` | texto | — | User-Agent (padrão do tt) |
| `tls_verificar` | 1/0 | `1` | 0 = não verificar o certificado TLS (evite) |
| `proxy` | texto | — | proxy http://host:porta (opcional) |
| `permitir_http` | 1/0 | `0` | 1 = aceita http:// (sem criptografia; evite) |
| `tamanho_max` | inteiro 1024–8388608 | `1048576` | bytes máximos da resposta |

**Autenticação**

| campo | valor | padrão | o que faz |
|---|---|---|---|
| `auth` | nenhuma/header/query/bearer/basic | `nenhuma` | como enviar o segredo |
| `auth_nome` | texto | — | nome do header ou do parâmetro (auth=header\|query) |
| `segredo` | texto | — | @arquivo em ~/.secrets (basic: usuario:senha) |

**Resposta**

| campo | valor | padrão | o que faz |
|---|---|---|---|
| `formato` | json/xml/rss/atom/csv/texto/regex | `json` | formato da resposta |
| `caminho` | texto | — | o que extrair: JSONPath simples, XPath, coluna, regex ou linha |
| `itens` | inteiro 1–20 | `1` | quantos itens tirar da resposta |
| `de` | inicio/fim | `inicio` | tirar os itens do início ou do fim da resposta |
| `csv_sep` | texto | `,` | separador do CSV |
| `csv_cabecalho` | auto/1/0 | `auto` | CSV com linha de cabeçalho |
| `codificacao` | texto | `utf-8` | codificação do texto (utf-8, latin-1…) |

**Transformação**

| campo | valor | padrão | o que faz |
|---|---|---|---|
| `decimais` | inteiro 0–8 | — | casas decimais (vazio = como veio) |
| `separador` | pt/en | — | pt = 1.234,56; en = 1,234.56 (vazio = como veio); vale também para os campos extras que são número decimal (`{max}` 30.2 → 30,2) |
| `entrada` | auto/pt/en | `auto` | como o número chega na resposta |
| `milhar` | 1/0 | `1` | separador de milhar ao formatar |
| `moeda` | texto | — | prefixo do valor (R$, US$…) |
| `escala` | nenhuma/mil/mi/bi | `nenhuma` | divide o valor e põe o sufixo |
| `arredondar` | normal/cima/baixo/truncar | `normal` | como arredondar |
| `variacao` | texto | — | caminho da variação % na resposta, ou 'calculada' (contra o valor anterior) |
| `var_base` | texto | — | caminho do valor de referência: variação = (valor-base)/base |
| `var_decimais` | inteiro 0–4 | `1` | casas da variação |
| `setas` | 1/0 | `1` | ▲/▼ na variação (0 = +/-) |
| `traduzir` | lista (repete a linha) | — | troca de texto fixo 'origem>destino' |
| `valor_max` | inteiro 0–400 | `0` | corta o valor bruto em N caracteres (0 = não corta) |

**Exibição**

| campo | valor | padrão | o que faz |
|---|---|---|---|
| `modelo` | texto | `{icone} {rotulo} {valor} {var}` | modelo do item: {icone} {rotulo} {valor} {var} {seta} {pct}… |
| `truncar` | inteiro 0–400 | `0` | largura máxima do item em células (`0` = não corta, o padrão: o letreiro rola, não corta) |
| `prefixo` | texto | — | texto antes do item |
| `sufixo` | texto | — | texto depois do item |
| `cor` | 1/0 | `1` | cor por sinal (alta verde, baixa vermelha) |
| `se_faltar` | esconder/ultimo/erro | `ultimo` | sem dado novo: esconde, mostra o último (marcado) ou o erro |
| `cache_max` | inteiro 0–100000 | `360` | minutos de cache aceitos sem marca (0 = sem limite) |

**Agenda e cache**

| campo | valor | padrão | o que faz |
|---|---|---|---|
| `ttl` | inteiro 10–604800 | `600` | segundos entre atualizações |
| `dias` | texto | — | dias em que atualiza (seg-sex, sab,dom…) |
| `horas` | texto | — | horas em que atualiza (10-18, 9:30-12,14-17:45) |
| `so_com_cliente` | 1/0 | `0` | 1 = só atualiza com um terminal tmux em uso |
| `limite_hora` | inteiro 0–3600 | `0` | máximo de requisições por hora (0 = sem limite) |
| `alerta_falhas` | inteiro 0–100 | `5` | avisa na central de notificações após N falhas seguidas (0 = nunca) |

**Condições**

| campo | valor | padrão | o que faz |
|---|---|---|---|
| `condicao` | lista (repete a linha) | — | mostra só se: valor>N · var>N · abs>N · cruza N · contem T · mudou |
| `mostrar_dias` | texto | — | dias em que o item aparece |
| `mostrar_horas` | texto | — | horas em que o item aparece |

**Clique**

| campo | valor | padrão | o que faz |
|---|---|---|---|
| `clique` | nada/url/painel/copiar | `nada` | o que o clique no item faz |
| `clique_alvo` | texto | — | url (aceita {link} {valor}…) \| painel (tarefas, email, calendario, notificacoes, letreiro) \| texto a copiar |

**Controle (gerenciados pelo tt)**

| campo | valor | padrão | o que faz |
|---|---|---|---|
| `versao` | inteiro | `1` | versão do formato do arquivo |
| `mudada` | inteiro | `0` | hora da última mudança (a mais nova vence ao propagar) |

Variáveis em `url`, `query`, `corpo`, `modelo`, `rotulo`, `caminho` e `clique_alvo`: `{data}` `{hoje}`
`{ontem}` `{amanha}` `{data_br}` `{ano}` `{mes}` `{dia}` `{hora}` `{epoch}`, as suas (`var.moeda=USD` →
`{moeda}`), os campos extras (`campo.link=.//item/link` → `{link}`) e, em `url`/`header`/`query`/`corpo`,
`{segredo}`. No `modelo`: `{icone}` `{rotulo}` `{valor}` `{var}` `{seta}` `{pct}` `{nome}` `{hora}` `{data}`.
Um campo extra chamado `campo.dia` formata valores ISO `AAAA-MM-DD` como `DD/MM/AAAA (Dia)` em português
(por exemplo, `13/10/2026 (Ter)`); valores que não sejam datas ISO permanecem como vieram.

O pacote inclui `letreiro-padrao.json`, que liga por padrão as fontes de fábrica ativas do perfil tt e fixa
a previsão do tempo em **Ribeirão Preto (SP)**, inclusive a previsão diária de sete dias. As escolhas que já
existem no perfil local prevalecem. O painel de ajustes oferece ritmos prontos e personalizados: na rolagem,
0,1–5 segundos por coluna; em páginas, 1–60 segundos por bloco.

Caminhos de extração: **json** `a.b`, `a.b[0]`, `a[-1]`, `a[*].x` (todos), `a[0:3]`, `$.a.b`,
`['chave com ponto']` e filtros `itens[?data>={hoje}].nome`; **xml/rss/atom** XPath simples (`.//item/title`,
`channel/item/link`, `.//item/@id`, namespaces ignorados; `rss`/`atom` sem caminho pegam os títulos); **csv**
a coluna pelo nome ou pelo número (`csv_sep`, `csv_cabecalho`); **texto** vazio (as linhas), `linha:N`;
**regex** o 1º grupo. `itens=N` tira N achados do início ou do fim (`de=fim`). Se o caminho não existe, o erro
diz onde parou e quais chaves havia ali.

Condições (`condicao=`, repetível, todas valem juntas): `valor>N`, `valor<=N`, `var>N`, `abs>N` (variação
absoluta), `cruza N` (alerta de 1 h quando o valor cruza o limite), `contem TEXTO`, `nao_contem TEXTO`,
`mudou`. Janelas: `dias=seg-sex` e `horas=10-18` (das 10:00 às 17:59; `9:30-12,14-17:45`; `22-6` atravessa a
meia-noite) valem para **atualizar**; `mostrar_dias`/`mostrar_horas` para **exibir**. O fuso é o da máquina
ou `ticker_fuso`.

### Exemplos

```
# ~/.config/tt/letreiro/bitcoin.conf — cotação com variação, alerta de 2% e clique que abre o gráfico
url=https://economia.awesomeapi.com.br/json/last/BTC-BRL
caminho=BTCBRL.bid
variacao=BTCBRL.pctChange
icone=₿
rotulo=bitcoin
moeda=R$
decimais=0
separador=pt
ttl=300
condicao=abs>2
clique=url
clique_alvo=https://www.google.com/finance/quote/BTC-BRL

# ~/.config/tt/letreiro/ci.conf — API com chave: o valor fica em ~/.secrets/github-token (modo 600)
url=https://api.github.com/repos/{repo}/actions/runs?status=in_progress&per_page=1
var.repo=dono/projeto
auth=bearer
segredo=@github-token
caminho=total_count
modelo={icone} CI: {valor} em andamento
icone=⚙
```

### Segredos

O segredo **sempre** mora em `~/.secrets/ARQUIVO` (modo 600) e a fonte só o referencia por `@ARQUIVO`
(`auth=bearer|basic|header|query` + `segredo=@ARQUIVO`; `basic` lê `usuario:senha`). `tt --letreiro-segredo
NOME` grava o arquivo sem mostrar o valor; o assistente também pergunta. Credencial **literal** em `header`,
`query` ou na URL é recusada ao salvar, e o valor lido nunca aparece em tela, `testar`, log, cache (se a
API ecoar a chave, o trecho vira `***`), exportação ou propagação — o pacote leva só `segredo=@nome`, e na
outra máquina você cria o arquivo de segredo dela.

### Segurança

Só **https** (`http://` exige `permitir_http=1` e avisa). Destinos locais e de rede privada são bloqueados —
`localhost`, 127.x, 10.x, 172.16–31.x, 192.168.x, 169.254.x (nuvem), 100.64.x (Tailscale), `::1`, endereços
IPv4-mapeados, `*.local`/`*.internal` e qualquer nome que **resolva** para um deles (o IP validado é o usado
na conexão, sem segunda resolução) — também a cada redirecionamento (até 3; https→http é recusado e
credenciais não seguem para outro servidor). Limites: `timeout`, `tentativas` com espera que dobra,
`tamanho_max` (resposta e descompressão), XML com `DOCTYPE`/`ENTITY` recusado, certificado TLS verificado
(`tls_verificar=0` avisa). O texto vindo da rede é **dado não confiável**: antes de chegar à faixa perde
sequências de escape de terminal (CSI, OSC…), controles, controles de direção do Unicode e o `#` que abriria
`#[`, `#(` ou `#{` do tmux; o desenhista ainda dobra todo `#` e filtra de novo o que lê do cache. Um clique
só abre `http(s)`.

### Diagnóstico

Por fonte (`tt --letreiro-listar`, e o painel): estado (ok · velha · erro · desligada · fora · aguardando),
última atualização, HTTP, latência, falhas seguidas e último erro. Depois de um erro a fonte espera 60 s,
120 s, 240 s… (até 1 h) antes de tentar de novo; após `alerta_falhas` (5) falhas seguidas há **um** aviso na
central de notificações 🔔 (clique abre o painel). `tt --letreiro-testar NOME` mostra cada etapa (pedido,
resposta, extração, resultado) sem gravar nada (`--gravar` também atualiza o cache) e `tt --letreiro-log
[NOME] [N]` lê o log rotativo `~/.cache/tt-letreiro.log` (256 KB, mais um `.1`). O estado fica em
`~/.cache/tt-ticker/NOME.meta`.

### Propagação e sobrescrita por máquina

`escopo=global` leva a fonte às outras máquinas como o cadastro de demandas: a mudança mais nova vence
(`mudada`), uma remoção vira lápide que nenhum pacote mais velho ressuscita, e o vigia puxa a cada 30 min
(`tt --puxar-letreiro`; cadastrar/editar/remover já empurra na hora por ssh). Só o texto do `.conf` viaja, só
fontes globais, só se passarem na mesma validação (sem credencial literal, sem destino privado, sem chave
desconhecida). `tt --letreiro-editar NOME --local ativa=0` (ou "só nesta máquina" no painel) guarda a
escolha em `letreiro/local/` — uma fonte global desligada só aqui, por exemplo — e nada disso é propagado.
`perfil=celular|desktop` e `maquinas=nome,!outro` escolhem onde a fonte vale.

### Ajustes globais (por máquina, no `~/.config/tt/config`)

`ticker_ligado` (interruptor), `ticker_rolagem` (`continua`/`paginas`), `ticker_veloc`, `ticker_fps`,
`ticker_separador` (entre itens), `ticker_ordem` (`sequencial` pelo campo `ordem` — `manual` é o nome antigo —, `aleatoria`: mistura as ENTRADAS de todas as
fontes, não só a ordem delas; estável dentro da hora e sem pular quando uma fonte atualiza; ou `peso`; no painel, `^o` alterna
sequencial ⇄ aleatória),
`ticker_largura` (máximo de células), `ticker_pausa`, `ticker_cor`, `ticker_economia`, `ticker_bateria_min`,
`ticker_ponte`, `ticker_idioma`, `ticker_fuso`. `tt --letreiro-ajustes` lista; `tt --letreiro-ajuste CHAVE
VALOR` grava (vazio volta ao padrão); a tela tem o mesmo (⚙ Ajustes globais). `peso=N` na fonte é quantas
vezes ela aparece por volta, espalhadas. **Clique no letreiro**: roda a ação do item sob o mouse (`url`,
`copiar`, `painel`) e, num item sem ação, pausa/continua (`ticker_pausa=nunca` desliga); o tmux não avisa
quando o mouse só passa por cima, então a pausa é por clique. **Modo economia** (`ticker_economia=auto`
liga no celular): não atualiza com a bateria abaixo de `ticker_bateria_min` sem carregar nem sem nenhum
terminal em uso (e a bateria baixa congela o letreiro em páginas).

### Painel e comandos

Menu ⋯ → **📰 Letreiro** (ou o aviso de falhas): lista com o estado de cada fonte. ⏎ ou duplo clique/botão
direito abrem as ações; teclas: `^n` nova (assistente: cola a URL, o tt busca, mostra a resposta formatada,
você escolhe o campo no fzf e define rótulo, TTL e modelo, vê o **teste ao vivo** e só então salva), `F2`
editar (formulário de todos os campos, com `^t` testar e `^s` salvar), `^t` testar, `^a` liga/desliga, `^d`
duplicar, `^k`/`^j` subir/descer na roda, `^l` log, `^x` remover (de fábrica: tirar da lista), `Tab` vista (todas · na roda · disponíveis), `^o` ordem (sequencial ⇄ aleatória), `^g` ajustes, `^b` catálogo, `^p`
pré-visualizar na faixa, `^r` atualizar, `esc` fecha.

| comando | faz |
|---|---|
| `tt --letreiro-listar [--tsv] [--todas\|--ativas\|--inativas] [--categoria C]` | fontes com estado, atualização, latência e erro (padrão: as ligadas, as suas e as de fábrica que você mexeu) |
| `tt --letreiro-add NOME url=… caminho=… [chave=valor…] [--testar]` · `--catalogo ID [var=valor…]` | cria (valida antes); sem argumentos num terminal, o assistente |
| `tt --letreiro-editar NOME [chave=valor…] [--local]` | altera (`-chave` remove); sem pares, o formulário |
| `tt --letreiro-rm NOME [--sim]` · `--letreiro-duplicar A B` · `--letreiro-ativar/--letreiro-desativar NOME [--local]` · `--letreiro-mover NOME +1\|-1\|inicio\|fim\|N` | gerenciam |
| `tt --letreiro-testar NOME [--cor] [--gravar]` | busca ao vivo e mostra cada etapa |
| `tt --letreiro-log [NOME] [N]` | log rotativo |
| `tt --letreiro-exportar [NOME…]` · `--letreiro-importar ARQ [--sobrescrever]` | pacote de texto (sem segredos) |
| `tt --letreiro-catalogo [ID [var=valor…]]` | catálogo: liga uma de fábrica (traz de volta a que você tirou) ou cria a partir de um modelo |
| `tt --letreiro-restaurar NOME` | fonte de fábrica: apaga o que você mudou e mantém na lista |
| `tt --letreiro-segredo NOME` · `--letreiro-ajustes` · `--letreiro-ajuste CHAVE VALOR` · `--letreiro-migrar` | segredos, ajustes, migração |
| `tt --letreiro-ui` | o painel |

### Catálogo de fábrica (156 fontes prontas, desligadas)

O pacote leva o `letreiro-catalogo.json` com **156 fontes já definidas e validadas na rede real**. Todas vêm
**desligadas**: aparecem na lista do painel (por categoria), mas **não buscam nada na rede** até você ligar.
As únicas ligadas de fábrica continuam sendo `dolar`, `frases` e `noticias`. No painel (menu ⋯ → 📰 Letreiro):

- **Tab** (ou a linha `⇄ Vista`) alterna o que a lista mostra: *todas*, só as *na roda* ou só as *disponíveis*;
  digitar filtra por nome, categoria ou descrição (`status`, `bolsa`, `rss`…).
- **`^a`** (ou ⏎ → *Ativar*) liga e a fonte sobe para a seção *Na roda*; **`^t`** testa ao vivo sem ligar; a
  prévia mostra *como aparece*, com um exemplo validado.
- **`F2`** (⏎ → *Configurar*) abre o formulário de todos os campos; o arquivo `~/.config/tt/letreiro/NOME.conf`
  guarda **só o que você mudou** (o resto continua vindo do pacote e acompanha as atualizações do tt).
  Quase todas as de clima usam `var.lat`, `var.lon` e `var.cidade`: troque para o seu lugar.
- **`^x`** (⏎ → *Tirar da lista*) esconde uma de fábrica; **📚 Catálogo** (`^b`) ou `tt --letreiro-catalogo NOME`
  traz de volta e liga. ⏎ → *↺ Voltar ao padrão de fábrica* apaga o que você mudou e mantém na lista.
- **Adicionar**: `^n` (assistente), os **modelos** abaixo (perguntam o que falta) ou `⧉ Duplicar` uma de fábrica
  para ajustar à vontade (a cópia é sua).

Pela linha de comando: `tt --letreiro-listar [--todas|--ativas|--inativas] [--categoria C]`,
`tt --letreiro-ativar NOME`, `--letreiro-desativar`, `--letreiro-editar NOME ttl=300`, `--letreiro-rm NOME`
(de fábrica: tira da lista), `--letreiro-restaurar NOME`, `--letreiro-catalogo [NOME|MODELO [var=valor…]]`.

Cada fonte foi rodada ao vivo no dia da validação (coluna *como aparece*) e a suíte confere TODAS contra a resposta
real guardada em `tests/letreiro-amostras/` — sem rede — além de exigir https, destino público, nenhum segredo e
`ativa=0`. Para revalidar na rede de verdade (quando uma API mudar) ou incluir uma fonte nova:
`tests/letreiro_catalogo_rede.py [--gravar] [NOME…]` (ferramenta de manutenção, fora da suíte). Algumas usam
endpoints **não oficiais** (Yahoo Finance, Mega-Sena) e podem mudar sem aviso; o limite do GitHub sem token é 60
consultas/h por rede (as fontes `*-ultimo` consultam de 6 em 6 h).

**💱 Moedas** (11)

| fonte | o que mostra | como aparece |
|---|---|---|
| `dolar-australiano` | Dólar australiano em reais | 🇦🇺 dólar aus. R$ 3,482 ▼ 0,3% |
| `dolar-canadense` | Dólar canadense em reais | 🇨🇦 dólar can. R$ 3,498 ▼ 0,8% |
| `dolar-turismo` | Dólar turismo em reais | 🧳 dólar turismo R$ 4,953 ▼ 0,5% |
| `euro` | Euro em reais (AwesomeAPI, sem chave) | 💶 euro R$ 5,583 ▼ 0,8% |
| `euro-dolar` | Euro em dólares | 💱 euro/dólar US$ 1,1201 ▼ 0,1% |
| `franco-suico` | Franco suíço em reais | 🇨🇭 franco suíço R$ 6,004 ▼ 0,5% |
| `iene` | Iene japonês em reais | 💴 iene R$ 0,0314 ▼ 1,0% |
| `libra` | Libra esterlina em reais | 💷 libra R$ 6,593 ▼ 0,5% |
| `ouro-onca` | Ouro: onça troy em reais | 🥇 ouro (onça) R$ 20.917 ▲ 0,6% |
| `peso-argentino` | Peso argentino em reais | 🇦🇷 peso arg. R$ 0,0032 ▼ 0,2% |
| `yuan` | Yuan chinês em reais | 🇨🇳 yuan R$ 0,745 ▼ 0,5% |

**₿ Criptomoedas** (11)

| fonte | o que mostra | como aparece |
|---|---|---|
| `bitcoin` | Bitcoin em reais (AwesomeAPI, sem chave) | ₿ bitcoin R$ 420.217 ▲ 0,8% |
| `bitcoin-bloco` | Altura do último bloco do Bitcoin (mempool.space, sem chave) | 🧱 bloco BTC 970.972 |
| `bitcoin-taxa` | Taxa de rede do Bitcoin para confirmar logo (mempool.space, sem chave) | ⛏ taxa BTC 2 sat/vB |
| `bitcoin-usd` | Bitcoin em dólares (Coinbase, sem chave) | ₿ BTC US$ 83.632 |
| `dogecoin` | Dogecoin em reais | 🐕 dogecoin R$ 0,436 ▲ 0,5% |
| `ethereum` | Ethereum em reais | Ξ ethereum R$ 12.741 ▲ 1,0% |
| `ethereum-usd` | Ethereum em dólares (Coinbase, sem chave) | Ξ ETH US$ 2.533 |
| `litecoin` | Litecoin em reais | Ł litecoin R$ 323,60 ▲ 0,4% |
| `medo-ganancia` | Índice de medo e ganância das criptomoedas (alternative.me, sem chave) | 😨 medo/ganância 61 (Greed) |
| `solana` | Solana em reais | ◎ solana R$ 562,30 ▲ 1,6% |
| `xrp` | XRP em reais | ✕ XRP R$ 7,073 ▲ 0,3% |

**🏦 Juros, inflação e economia (Banco Central)** (13)

| fonte | o que mostra | como aparece |
|---|---|---|
| `cdi` | CDI anualizado (BCB, série 4389) | 🏦 CDI 13,65% a.a. |
| `desemprego` | Taxa de desocupação — PNAD Contínua (BCB, série 24369) | 👷 desocupação 5,3% |
| `dolar-ptax` | Dólar PTAX de venda (BCB, série 1) | 💵 PTAX dólar R$ 4,9892 |
| `euro-ptax` | Euro PTAX de venda (BCB, série 21619) | 💶 PTAX euro R$ 5,5844 |
| `igpm` | IGP-M, variação mensal (BCB, série 189) | 📈 IGP-M 1,57% no mês |
| `inpc` | INPC, variação mensal (BCB, série 188) | 📈 INPC 0,82% no mês |
| `ipca` | IPCA, variação mensal (BCB, série 433) | 📈 IPCA 0,82% no mês |
| `ipca-12m` | IPCA acumulado em 12 meses (BCB, série 13522) | 📈 IPCA 12m 4,58% |
| `ipca-15` | IPCA-15, variação mensal (BCB, série 7478) | 📈 IPCA-15 0,70% no mês |
| `poupanca` | Rendimento mensal da poupança (BCB, série 195) | 🐖 poupança 0,6218% no mês |
| `reservas` | Reservas internacionais em milhões de dólares (BCB, série 13621) | 🏛 reservas 362.367 mi US$ |
| `selic` | Meta da taxa Selic ao ano (BCB, série 432) | 🏦 Selic 13,75% a.a. |
| `tr` | Taxa Referencial (BCB, série 226) | 💹 TR 0,1212% no mês |

**📊 Bolsas e commodities** (13)

| fonte | o que mostra | como aparece |
|---|---|---|
| `dow-jones` | Dow Jones em pontos (Yahoo Finance, endpoint não oficial) | 🇺🇸 Dow Jones 51.655 ▲ 0,8% |
| `ibovespa` | Ibovespa em pontos; só atualiza no pregão (Yahoo Finance, endpoint não oficial) | 📊 Ibovespa 209.067 ▲ 1,4% |
| `itub4` | Itaú Unibanco PN em reais (Yahoo Finance, endpoint não oficial) | 🏦 ITUB4 R$ 50,47 ▲ 2,3% |
| `nasdaq` | Nasdaq Composite em pontos (Yahoo Finance, endpoint não oficial) | 🇺🇸 Nasdaq 27.366 ▲ 0,6% |
| `nikkei` | Nikkei 225 em pontos (Yahoo Finance, endpoint não oficial) | 🇯🇵 Nikkei 69.031 = 0,0% |
| `ouro-futuro` | Ouro, futuro em dólares por onça (Yahoo Finance, endpoint não oficial) | 🥇 ouro US$ 4.216,30 = 0,0% |
| `petr4` | Petrobras PN em reais (Yahoo Finance, endpoint não oficial) | 🛢 PETR4 R$ 56,00 ▲ 0,9% |
| `petroleo-brent` | Petróleo Brent, futuro em dólares (Yahoo Finance, endpoint não oficial) | 🛢 Brent US$ 104,72 = 0,0% |
| `petroleo-wti` | Petróleo WTI, futuro em dólares (Yahoo Finance, endpoint não oficial) | 🛢 WTI US$ 91,85 = 0,0% |
| `prata-futuro` | Prata, futuro em dólares por onça (Yahoo Finance, endpoint não oficial) | 🥈 prata US$ 61,05 = 0,0% |
| `sp500` | S&P 500 em pontos (Yahoo Finance, endpoint não oficial) | 🇺🇸 S&P 500 7.812 ▲ 0,6% |
| `vale3` | Vale ON em reais (Yahoo Finance, endpoint não oficial) | ⛏ VALE3 R$ 67,90 ▲ 0,4% |
| `vix` | Índice de volatilidade VIX (Yahoo Finance, endpoint não oficial) | 😱 VIX 14,84 ▼ 3,7% |

**🌤 Tempo e clima** (14)

| fonte | o que mostra | como aparece |
|---|---|---|
| `clima-chuva` | Chuva neste momento (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🌧 Ribeirão Preto 0,0 mm |
| `clima-max-min` | Máxima e mínima de hoje (graus inteiros) (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🌡 Ribeirão Preto 30°C/19°C |
| `clima-nascer-do-sol` | Hora do nascer do sol (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🌅 Ribeirão Preto nasce 05:42 |
| `clima-pm25` | Partículas finas PM2,5 (µg/m³) (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🌫 Ribeirão Preto 76 µg/m³ |
| `clima-por-do-sol` | Hora do pôr do sol (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🌇 Ribeirão Preto põe 18:13 |
| `clima-prob-chuva` | Probabilidade de chuva hoje (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | ☔ Ribeirão Preto 66% |
| `clima-qualidade-ar` | Qualidade do ar (índice AQI dos EUA: até 50 boa, 100 moderada) (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 😷 Ribeirão Preto AQI 96 |
| `clima-rp-7dias` | Previsão diária para os próximos sete dias em Ribeirão Preto (Open-Meteo, sem chave; datas em formato brasileiro) | Ribeirão Preto 12/10/2026 (Seg): 30,2°C/19,8°C · chuva 66% |
| `clima-sensacao` | Sensação térmica agora (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🥵 Ribeirão Preto 22,1°C |
| `clima-temperatura` | Temperatura agora (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🌡 Ribeirão Preto 20,3°C |
| `clima-tempo` | Condição do tempo agora (código WMO traduzido) (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | ⛅ Ribeirão Preto: nublado |
| `clima-umidade` | Umidade relativa do ar agora (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 💧 Ribeirão Preto 89% |
| `clima-uv` | Índice UV máximo de hoje (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 😎 Ribeirão Preto UV 8 |
| `clima-vento` | Velocidade do vento agora (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🌬 Ribeirão Preto 9 km/h |

**🚀 Espaço e Terra** (5)

| fonte | o que mostra | como aparece |
|---|---|---|
| `iss-posicao` | Onde a Estação Espacial Internacional está agora (latitude, longitude; wheretheiss.at, sem chave) | 🛰 ISS -30.86°, 101.30° |
| `proximo-lancamento` | Próximo lançamento de foguete no mundo (The Space Devs, sem chave; 15 consultas/h) | 🚀 Falcon 9 Block 5 \| Starlink Group 15-25 (13/10/2026 (Ter)) |
| `sismo-recente` | Maior sismo recente (magnitude 4,5+ nas últimas 24 h; USGS, sem chave); some se não houve | 🌋 M 5.5 - 123 km W of Neiafu, Tonga |
| `tempestade-geomagnetica` | Índice Kp de atividade geomagnética (NOAA SWPC, sem chave): 5+ é tempestade | 🧲 Kp 2,3 |
| `vento-solar` | Velocidade do vento solar (NOAA SWPC, sem chave) | ☀ vento solar 535 km/s |

**🇧🇷 Brasil** (3)

| fonte | o que mostra | como aparece |
|---|---|---|
| `feriados` | Próximo feriado nacional (BrasilAPI, sem chave; data em formato brasileiro) | 📅 Feriado Nossa Senhora Aparecida — 12/10/2026 (Seg) |
| `ibge-noticias` | Notícias do IBGE (API de serviços do IBGE, sem chave) | 📈 IBGE: Acervo bibliográfico de Pedro Geiger é doado à Biblioteca do IBGE |
| `megasena` | Último concurso da Mega-Sena (API aberta não oficial; sem chave) | 🍀 Mega-Sena 3068: 07-10-39-40-43-57 |

**📰 Notícias do Brasil** (16)

| fonte | o que mostra | como aparece |
|---|---|---|
| `agencia-brasil` | Manchetes: Agência Brasil (feed RSS, sem chave) | 🇧🇷 Agência Brasil: Henrique Marques leva ouro, o 2º do Brasil em Grand Prix de taekwond |
| `camara-noticias` | Manchetes: Câmara (feed RSS, sem chave) | 🏛 Câmara: Projeto pune empresas que atrasarem pagamento de médicos |
| `cnn-brasil` | Manchetes: CNN Brasil (feed RSS, sem chave) | 📺 CNN Brasil: China impõe sanções a ministros de Paraguai e Belize por laços com Taiwan |
| `estadao` | Manchetes: Estadão (feed RSS, sem chave) | 📰 Estadão: ‘Não poderia ter acontecido’, diz idosa que teve prótese implantada no joelho errado |
| `exame` | Manchetes: Exame (feed RSS, sem chave) | 💼 Exame: Como células de defesa encontram seu caminho pelo corpo? Estudo revela mecanismo |
| `folha` | Manchetes: Folha (feed RSS, sem chave) | 📰 Folha: Estudo aponta cinco estratégias para reduzir hesitação vacinal |
| `folha-mercado` | Manchetes: Folha Mercado (feed RSS, sem chave) | 💼 Folha Mercado: Consumo deixa de ser motor do PIB e deve ter menor crescimento desde pandemia |
| `g1-ciencia` | Manchetes: G1 Ciência (feed RSS, sem chave) | 🔬 G1 Ciência: 'Ciência Aberta': centro que abriga o Sirius recebe público para apresentar curiosidades e atrações da ciência |
| `g1-economia` | Manchetes: G1 Economia (feed RSS, sem chave) | 💼 G1 Economia: Mega-Sena pode pagar R$ 150 milhões nesta terça (13); veja os 10 maiores prêmios da loteria |
| `g1-mundo` | Manchetes: G1 Mundo (feed RSS, sem chave) | 🌎 G1 Mundo: A nova onda de protestos de jovens do movimento das 'baratas' na Índia em imagens |
| `g1-politica` | Manchetes: G1 Política (feed RSS, sem chave) | 🏛 G1 Política: Nem todo eleitor que deixa de votar é desinteressado pela política, diz pesquisador |
| `g1-tecnologia` | Manchetes: G1 Tecnologia (feed RSS, sem chave) | 💻 G1 Tecnologia: Bill Gates considera ciberataques o principal risco atual da IA: 'Teremos muitas surpresas desagradáveis' |
| `ge-esportes` | Manchetes: ge (feed RSS, sem chave) | ⚽ ge: Análise: Singapura tem show de Verstappen e dá chance para Antonelli ser campeão em Austin |
| `infomoney` | Manchetes: InfoMoney (feed RSS, sem chave) | 💼 InfoMoney: Flamengo e Fluminense protestam contra MP das Bets; torcedores estendem faixa |
| `poder360` | Manchetes: Poder360 (feed RSS, sem chave) | 📰 Poder360: Homem rasga bandeira dos EUA em ato pró-Lula na Paulista |
| `senado-noticias` | Manchetes: Senado (feed RSS, sem chave) | 🏛 Senado: Áudio: Senado homenageia os 45 anos da Associação do Senhor Jesus |

**🌍 Notícias do mundo** (7)

| fonte | o que mostra | como aparece |
|---|---|---|
| `al-jazeera` | Manchetes: Al Jazeera (feed RSS, sem chave) | 🌍 Al Jazeera: China sanctions Paraguay, Belize ministers over Taiwan ties |
| `bbc-brasil` | Manchetes: BBC Brasil (feed RSS, sem chave) | 🌍 BBC Brasil: Corredor Andes-Atlântico: o que se sabe sobre o ambicioso projeto dos EUA para acessar recursos estratégicos da Argentina (e competir com a China) |
| `bbc-mundo` | Manchetes: BBC World (feed RSS, sem chave) | 🌍 BBC World: Trump's 'energy ceasefire' claim welcomed by Zelensky but Russia silent |
| `dw-brasil` | Manchetes: DW Brasil (feed RSS, sem chave) | 🌍 DW Brasil: "Sem anistia!": Milhares vão às ruas em defesa da democracia |
| `guardian` | Manchetes: Guardian (feed RSS, sem chave) | 🌍 Guardian: Controversial vaccine trial touted by RFK Jr gets go-ahead in Guinea-Bissau |
| `npr` | Manchetes: NPR (feed RSS, sem chave) | 🎙 NPR: Tropical Storm Rachel downgraded as high winds and rain turn inward |
| `nyt-mundo` | Manchetes: NYT World (feed RSS, sem chave) | 🗽 NYT World: Saudi Arabia Has Few Options as Houthis Aim at Heart of Its Ambitions |

**💻 Tecnologia** (18)

| fonte | o que mostra | como aparece |
|---|---|---|
| `ars-technica` | Manchetes: Ars Technica (feed RSS, sem chave) | 💻 Ars Technica: Review: 4-hour Musk documentary feels like two different films |
| `bbc-tech` | Manchetes: BBC Tech (feed RSS, sem chave) | 💻 BBC Tech: AI is less regulated than milk, says Microsoft president |
| `canaltech` | Manchetes: Canaltech (feed RSS, sem chave) | 💻 Canaltech: 6 filmes que prometeram muito e floparam na estreia nos cinemas |
| `debian-seguranca` | Avisos de segurança do Debian (feed RDF, sem chave) | 🛡 Debian DSA: DSA-6552-1 vips - security update |
| `go-blog` | Manchetes: Go Blog (feed ATOM, sem chave) | 🐹 Go Blog: Arch-specific SIMD in Go |
| `hacker-news` | Manchetes: Hacker News (feed RSS, sem chave) | 🟧 Hacker News: Type-safe HTML templating in Zig |
| `lobsters` | Manchetes: Lobsters (feed RSS, sem chave) | 🦞 Lobsters: I'm sorry, but you still have to think |
| `lwn` | Manchetes: LWN (feed RSS, sem chave) | 🐧 LWN: Kernel prepatch 7.3-rc7 |
| `nyt-tech` | Manchetes: NYT Tech (feed RSS, sem chave) | 💻 NYT Tech: Inside Mark Zuckerberg’s Decision to Pull the Trigger on Meta’s A.I. Agent |
| `olhar-digital` | Manchetes: Olhar Digital (feed RSS, sem chave) | 💻 Olhar Digital: Carregador portátil pega fogo em voo e força pouso de emergência na Índia |
| `phoronix` | Manchetes: Phoronix (feed RSS, sem chave) | 🐧 Phoronix: Linus Torvalds Working On A Hefty Linux Kernel Improvement With Claude Code |
| `rust-blog` | Manchetes: Rust Blog (feed ATOM, sem chave) | 🦀 Rust Blog: Demoting i686 Windows targets to std-only |
| `techcrunch` | Manchetes: TechCrunch (feed RSS, sem chave) | 💻 TechCrunch: The founder’s guide to TechCrunch Disrupt 2026: Everything you need to know |
| `tecmundo` | Manchetes: Tecmundo (feed RSS, sem chave) | 💻 Tecmundo: Valor Mortis, Enshrouded, Castlevania Belmonts Curse e mais! Veja os lançamentos de games da semana |
| `tecnoblog` | Manchetes: Tecnoblog (feed RSS, sem chave) | 💻 Tecnoblog: TV TCL C7L 65” registra o menor preço desde lançamento em oferta no Magalu |
| `the-verge` | Manchetes: The Verge (feed ATOM, sem chave) | 💻 The Verge: A college in Illinois tried to cancel its Flock contact and it refused |
| `ubuntu-seguranca` | Avisos de segurança do Ubuntu (feed RSS, sem chave) | 🛡 Ubuntu USN: USN-8911-1: Linux kernel (OEM) vulnerabilities |
| `wired` | Manchetes: Wired (feed RSS, sem chave) | 💻 Wired: I Made Terrible Games With Google’s AI Playground |

**🔬 Ciência** (4)

| fonte | o que mostra | como aparece |
|---|---|---|
| `bbc-ciencia` | Manchetes: BBC Science (feed RSS, sem chave) | 🔬 BBC Science: 'Prepare for the unthinkable' warning over autumn flooding |
| `nasa` | Manchetes: NASA (feed RSS, sem chave) | 🚀 NASA: APOD: 2026 October 12 – Jupiter and the Moons |
| `quanta` | Manchetes: Quanta (feed RSS, sem chave) | 🔬 Quanta: How Does Life Unfold? A Landscape Metaphor Comes Into Its Own. |
| `science-daily` | Manchetes: ScienceDaily (feed RSS, sem chave) | 🔬 ScienceDaily: NASA astronauts splash down after 100 million miles in space |

**🛠 Versões e ferramentas** (13)

| fonte | o que mostra | como aparece |
|---|---|---|
| `chrome-estavel` | Chrome estável para Linux (Google, sem chave) | 🌐 Chrome 155.0.8059.39 |
| `claude-code-ultimo` | Última versão do Claude Code (npm, sem chave) | 🤖 Claude Code 2.1.296 |
| `debian-estavel` | Última versão estável do Debian (endoflife.date, sem chave) | 🌀 Debian 13.7 |
| `firefox-ultimo` | Última versão do Firefox (Mozilla, sem chave) | 🦊 Firefox 157.0.1 |
| `go-ultimo` | Última versão do Go (go.dev, sem chave) | 🐹 go1.27.2 |
| `kernel-linux` | Última versão estável do kernel Linux (kernel.org, sem chave) | 🐧 Linux 7.2.10 |
| `nodejs-ultimo` | Última versão do Node.js (endoflife.date, sem chave) | 🟩 Node.js 26.11.1 |
| `python-ultimo` | Última versão do Python (endoflife.date, sem chave) | 🐍 Python 3.15.0 |
| `rust-ultimo` | Última versão do Rust (GitHub, sem chave; 60 consultas/h por rede) | 🦀 Rust 1.99.0 |
| `tmux-ultimo` | Última versão do tmux (GitHub, sem chave; 60 consultas/h por rede) | 🪟 tmux 3.8 |
| `ubuntu-lts` | Última versão LTS do Ubuntu (endoflife.date, sem chave) | 🟠 Ubuntu LTS 26.04.1 |
| `vim-ultimo` | Última versão do Vim (GitHub, sem chave; 60 consultas/h por rede) | 📝 Vim v9.2.1176 |
| `vscode-ultimo` | Última versão do VS Code (Microsoft, sem chave) | 🆚 VS Code 1.141.0 |

**🛰 Status de serviços** (16)

| fonte | o que mostra | como aparece |
|---|---|---|
| `status-atlassian` | Estado de Atlassian (página de status Statuspage) | 🛰 Atlassian: tudo operando |
| `status-claude` | Estado de Claude (página de status Statuspage) | 🛰 Claude: serviço parcialmente degradado |
| `status-cloudflare` | Estado de Cloudflare (página de status Statuspage) | 🛰 Cloudflare: queda parcial |
| `status-digitalocean` | Estado de DigitalOcean (página de status Statuspage) | 🛰 DigitalOcean: tudo operando |
| `status-discord` | Estado de Discord (página de status Statuspage) | 🛰 Discord: tudo operando |
| `status-dropbox` | Estado de Dropbox (página de status Statuspage) | 🛰 Dropbox: tudo operando |
| `status-flyio` | Estado de Fly.io (página de status Statuspage) | 🛰 Fly.io: tudo operando |
| `status-github` | Estado de GitHub (página de status Statuspage) | 🛰 GitHub: tudo operando |
| `status-netlify` | Estado de Netlify (página de status Statuspage) | 🛰 Netlify: tudo operando |
| `status-npm` | Estado de npm (página de status Statuspage) | 🛰 npm: tudo operando |
| `status-openai` | Estado de OpenAI (página de status Statuspage) | 🛰 OpenAI: sistema parcialmente degradado |
| `status-pypi` | Estado de Python/PyPI (página de status Statuspage) | 🛰 Python/PyPI: tudo operando |
| `status-reddit` | Estado de Reddit (página de status Statuspage) | 🛰 Reddit: tudo operando |
| `status-twilio` | Estado de Twilio (página de status Statuspage) | 🛰 Twilio: serviço parcialmente degradado |
| `status-vercel` | Estado de Vercel (página de status Statuspage) | 🛰 Vercel: tudo operando |
| `status-zoom` | Estado de Zoom (página de status Statuspage) | 🛰 Zoom: tudo operando |

**✨ Curiosidades e frases** (10)

| fonte | o que mostra | como aparece |
|---|---|---|
| `conselho` | Um conselho aleatório em inglês (Advice Slip, sem chave) | 💡 Vinegar is a powerful cleaning agent. |
| `fato-aleatorio` | Um fato aleatório em inglês (uselessfacts, sem chave) | 🧠 Tigers not only have striped fur, they have striped skin! |
| `fato-gato` | Um fato sobre gatos em inglês (catfact.ninja, sem chave) | 🐈 If they have ample water, cats can tolerate temperatures up to 133 °F. |
| `frase-zen` | Uma frase inspiradora em inglês (ZenQuotes, sem chave; no máx. 5 consultas/30 s) | 💭 “It's not what we do once in a while that shapes our lives, but what we do consistently.” — Tony Robbins |
| `hoje-na-historia` | Um fato histórico que aconteceu neste dia (Wikipédia em português, sem chave) | 🕰 2019: O tufão Hagibis atinge o Japão, matando ao menos 70 pessoas, causando graves inundações e forçando a evacuação de um milhão de pessoas. |
| `piada-ingles` | Uma piada curta em inglês (Official Joke API, sem chave) | 😄 What did one ocean say to the other ocean? — Nothing, they just waved. |
| `versiculo` | Um versículo bíblico aleatório (bible-api.com, sem chave) | 📖 For it is written, “I will destroy the wisdom of the wise, I will bring the discernment of the discerning to nothing.” (1 Corinthians 1:19) |
| `wikipedia-aleatoria` | Um verbete aleatório da Wikipédia em português (sem chave) | 📚 Nykvarn (comuna): comuna da Suécia |
| `xkcd` | Título da tirinha mais recente do xkcd (feed RSS, sem chave) | 🎨 xkcd: Dogcatcher |
| `zen-do-github` | Um princípio zen do GitHub (api.github.com/zen, sem chave) | 🧘 Non-blocking is better than blocking. |

**🌐 Rede** (1)

| fonte | o que mostra | como aparece |
|---|---|---|
| `ip-publico` | O seu endereço IP público (api.ipify.org, sem chave) — aparece na faixa, cuidado ao compartilhar a tela | 🌐 IP 203.0.113.7 |

**📋 Do próprio tt** (2)

| fonte | o que mostra | como aparece |
|---|---|---|
| `emails-nao-lidos` | Quantos e-mails não lidos há no espelho local (do próprio tt; some quando zera) | (só aparece quando há algo para avisar) |
| `tarefas-atrasadas` | Quantas tarefas estão atrasadas (do próprio tt; some quando zera) | (só aparece quando há algo para avisar) |

**Modelos** (`tt --letreiro-catalogo MODELO …`: perguntam o que falta e criam uma fonte **sua**):

| modelo | o que cria | pergunta |
|---|---|---|
| `cotacao` | Cotação de uma moeda ou criptomoeda (AwesomeAPI: USD-BRL, EUR-BRL, BTC-BRL, ETH-USD…) | `par` |
| `acao` | Cotação de uma ação, índice ou commodity (Yahoo Finance: PETR4.SA, ^GSPC, GC=F…) | `simbolo` |
| `bcb-serie` | Qualquer série do Banco Central (SGS): informe o número da série | `serie`, `nome` |
| `github-release` | Última versão publicada de um repositório do GitHub | `repo` |
| `github-estrelas` | Estrelas de um repositório do GitHub | `repo` |
| `npm-pacote` | Última versão de um pacote do npm | `pacote` |
| `pypi-pacote` | Última versão de um pacote do PyPI | `pacote` |
| `fim-de-vida` | Última versão de um produto e quando acaba o suporte (endoflife.date: python, nodejs, ubuntu, debian, postgresql…) | `produto` |
| `clima` | Temperatura agora no lugar que você escolher (Open-Meteo, sem chave) | `lat`, `lon`, `cidade` |
| `rss` | Manchetes de qualquer feed RSS/Atom (informe o endereço) | `feed` |
| `status` | Status de qualquer serviço que use página Statuspage (informe o domínio) | `pagina`, `servico` |
| `ci-github` | Execuções de CI em andamento num repositório (GitHub Actions) | `repo` |

Testes: `tests/test_letreiro_catalogo.sh` (o catálogo de fábrica contra respostas reais guardadas, sem rede, e o painel), `tests/test_letreiro_fontes.sh` (módulo contra um servidor HTTP/HTTPS de mentira em 127.0.0.1, sem
a rede real, mais um tmux isolado para o clique, o painel e o assistente) e `tests/test_letreiro.sh` (o
desenho). `tests/INTERACTIONS.md` guarda a matriz de interação.

## Sessões fixadas

Uma segunda linha na barra com as sessões que você usa sempre (desta ou de outras máquinas): um
toque vai direto para ela ao pressionar, e o ✕ ao lado desafixa; botão direito num item: ir, desafixar e
mover (um passo, para o início ou para o fim), e **≡ Todas as fixadas**, que abre o popup com a lista
completa. Cada item mostra o **conteúdo primeiro**: o nome da sessão; uma sessão de outra máquina
ganha antes um **selo colorido de uma letra** (`E tt-mesh-logincheck`, `D asd`), com a mesma letra e
cor no popup e no menu de máquinas — o nome da máquina não ocupa mais a faixa. A faixa acompanha a
**largura de cada janela**, ao vivo: monitor, notebook e celular veem cada um a sua versão, e
redimensionar redesenha na hora. Quando falta espaço, nada rola: os rótulos **encolhem por estágios**
— abreviados **por palavras** (`tt-mesh-logincheck` → `tt-mesh-logi`, sem cortar o fim às cegas), e
dois nomes nunca ficam iguais —, depois o ✕ sai (desafixe pelo popup ou pelo botão direito). Há um
**piso de legibilidade**: os nomes não encolhem abaixo de 16 colunas; quando nem assim tudo cabe, os
excedentes viram um chip **`+N ▾`** (que abre o mesmo popup, com os nomes inteiros e a máquina por
extenso) e os visíveis continuam confortáveis — a sessão em uso de cada janela nunca some da faixa. A **roda do
mouse** em cima do chip gira as fixadas: para cima, as escondidas no chip giram junto com a última visível ao lado
dele (a próxima escondida aparece; a que estava ali vai para o fim do chip); para baixo, todas giram uma casa (a
primeira vai para o fim). O **botão direito** no chip agrupa as fixadas por máquina: as de uma mesma máquina ficam
lado a lado, as máquinas na ordem em que aparecem e, dentro de cada uma, a ordem de antes (no popup, `^g`; na linha
de comando, `tt --fixadas-agrupar`; a roda, `tt --fixadas-girar cima|baixo`). No popup: `⏎` vai para a sessão, `^x`
desafixa e `^k`/`^j` (ou alt-↑/↓) **reordenam ao vivo** — o item acompanha o cursor e, ao fechar, a barra e as outras
máquinas recebem a ordem nova. Para fixar a sessão em uso: o pino ao lado do nome dela na barra (📍 = não fixada, um
clique fixa; 📌 = fixada, um clique desafixa). Também: menu da sessão (botão direito em
"sessão ▾") → "📌 Fixar na barra", `^f` no seletor, ou `tt --fixar [máquina:]sessão`. A lista é a mesma em todas as máquinas (cada mudança é copiada
para as cadastradas; quem estava desligada puxa a mais nova sozinha ao voltar, em até 5 min), então
as fixadas continuam lá ao entrar numa sessão de outra máquina. A faixa permanece visível mesmo
vazia, marcada por `📌`. Cada fixada também carrega uma
identidade persistente da sessão, independente do nome exibido; por isso renomear uma sessão não
quebra o clique, inclusive quando a troca atravessa máquinas. A linha
só ganha itens quando há fixadas. O vigia dá nome semântico às sessões (inclusive fixadas), e o item da barra
acompanha o novo nome:

- **primeiro nome**: uma aba de nome genérico (`janela-N`, `atalho-N`…) ganha nome 1 minuto
  depois da primeira interação (`TT_T_PRIMEIRO`, em segundos); se a tela ainda não mostrar do que
  se trata, tenta de novo 1 minuto depois da interação seguinte;
- **renomeações seguintes**: por pontos. Cada pedido novo vale 3 (`TT_PESO_PEDIDO`) e cada minuto
  com uso vale 1; com 10 pontos (`TT_PONTOS_RENOMEAR`) e pelo menos 5 min desde o último nome
  (`TT_T_RENOMEAR`, em segundos), o nomeador sugere o nome novo. Pedido é uma mensagem digitada na
  conversa do Claude ou, nas outras abas, tecla/toque de verdade (saída na tela não conta). Sem
  pedido novo o assunto não mudou e o Haiku nem é chamado, por mais que a tela mude (um agente
  trabalhando sozinho no mesmo pedido). Mudar de pasta também renomeia. Nas abas do Claude o
  primeiro nome é o título da conversa (sem custo); as revisões leem os últimos pedidos e a tela,
  e o nome acompanha a tarefa atual. Se o título da conversa mudar, a aba o segue.

O comando `^a`/“Nomear todas” faz isso sequencialmente nesta máquina e em todas as máquinas
cadastradas que estiverem acessíveis.

## Nomeador local de abas

Para não depender de conta nem de rede para nomear as abas, o tt pode rodar um modelo open source
leve na própria máquina: o [llama.cpp](https://github.com/ggml-org/llama.cpp) (MIT) com o Qwen3
(Apache-2.0). Nada vai para fora da máquina, e a janela de uso das contas de IA fica para o trabalho.

    tt --nomeador-local instalar     # baixa uma vez, com confirmação do sha256 (ou: menu ⋯ → 🧠 Nomeador de abas)
    tt --nomeador-local estado       # instalado, modelo, memória e modelo sugerido
    tt --nomeador-local remover      # apaga motor e modelo
    tt --nomeador auto               # auto | local | claude | nenhum (nomeador= no config)

- **Modelo pela memória:** Qwen3 4B Instruct (2,5 GB; nomes no nível do Haiku) com 8 GB de RAM ou mais;
  Qwen3 1.7B (1,1 GB) entre 3 e 8 GB e no celular; abaixo de 3 GB, nada. O `instalar.sh` pergunta no
  fim se quer instalar; nunca baixa sem confirmação.
- **Onde fica:** `~/.local/share/tt-nomeador` (fora do pacote do tt). O motor é o binário oficial do
  llama.cpp em versão fixa (Linux x64/arm64, WSL, macOS); no Termux vem do `pkg install llama-cpp`.
  Motor e modelo têm o sha256 conferido antes de usar; um download interrompido continua de onde parou.
- **Sem nada residente:** o servidor sobe a cada nome (≈1 s com o modelo no cache de disco), responde
  e é derrubado; só um por vez na máquina. Cada nome leva de ~5 a ~30 s de CPU, conforme a máquina e a
  carga; o vigia faz isso em segundo plano.
- **Formato garantido:** uma gramática prende a saída em 1 a 3 palavras minúsculas com hífen, e o tt
  ainda valida o nome. A entrada é curta: pasta, título, os 4 últimos pedidos e as linhas finais da tela.
- **Modos:** `auto` (padrão) usa o local se instalado e cai no Haiku/outra máquina se ele falhar;
  `local` só o modelo local (a tela nunca sai da máquina); `claude` só o Haiku; `nenhum` usa o nome da pasta.

## Memória local dos agentes

Toda instalação do tt mantém um repositório local em `~/.local/state/tt/ai-memory` (fora do pacote,
para sobreviver às atualizações; a pasta antiga, `~/.local/share/tt/ai-memory`, é migrada sozinha). Ele é
atualizado ao entrar no tt e periodicamente pelo vigia, detectando Claude, Codex, Kiro e outros
processos visíveis nas sessões tmux. O índice (`index.json`), os agentes instalados e os metadados
das sessões ficam separados dos textos duradouros (`memory.md` e `decisions.md`). Nenhum token,
cookie, credencial ou transcript completo é copiado para esse repositório.

Para forçar uma atualização: `tt --memoria-agentes`. Para mudar o local em uma máquina específica,
use `TT_AI_MEMORY_DIR=/caminho/da/memoria`.

Se uma sessão fixada de outra máquina foi fechada, ou a máquina caiu, o tt avisa e conserva a tela
atual. Se a conexão cair depois de entrar, a ponte fica aberta mostrando a falha; `Enter` tenta de
novo e `Ctrl+B d` volta, sem fechar a janela do terminal.

## Fechar telas e popups

Uma regra só, em qualquer máquina:

| Tela | Como fecha |
|---|---|
| Listas com fzf (central, fixadas, links, contas, atalhos) | `Esc` (ou `Ctrl+C`); `q` também onde não há busca (central, atalhos) |
| Painel de tarefas e agenda | `Esc` volta/fecha (`q` digitaria na busca) |
| Mensagens (sync local, resultado de cadastro, erros do e-mail, "pasta padrão") | **qualquer tecla**, `Esc` inclusive |
| Perguntas de uma linha (nome, usuário, pasta) | `Enter` confirma; `Ctrl+C` cancela |
| Navegador interno (Carbonyl) | `Ctrl+Q` ou `Ctrl+C` (a página consome `Esc` e `q`) |
| E-mail (aerc) | `:quit`, `q` nas telas de contas/atalhos, ou o botão 📧 |

Pedir uma tela do tt (clique na faixa, `tt --notif-abrir`) com o popup do e-mail na frente solta o
popup do e-mail (a sessão oculta segue viva) e abre a tela pedida em seguida — nada fica preso por baixo.

## Novidades do tt

`tt --novidades` (menu administrar → 📰 Novidades do tt) mostra, num popup com rolagem, o que mudou desde a
última versão que você viu; `--todas` mostra tudo. O texto vem de `NOVIDADES.md` (uma seção por versão,
escrita para quem usa o tt), formatado para o terminal: **negrito** e `código` com estilo, subitens com
recuo e o texto quebrado na largura da janela (até 100 colunas). Quando o tt atualiza, o vigia põe **um** aviso 📰 na faixa; clicar abre a
tela. Máquina recém-instalada não recebe o aviso. Quem publica uma versão acrescenta a seção dela em
`NOVIDADES.md` no mesmo commit.

## Checagem pós-atualização

Cada máquina, ao instalar uma versão nova, se confere: o vigia (`--checar-auto`) lança um agente de IA pelo
rotador (`ia-rot -p … --dangerously-skip-permissions`, a conta com mais folga) na sessão oculta `_tt-checagem`.
O agente recebe o resultado do coletor, o trecho novo do `NOVIDADES.md` e as regras de `checagens-tt.md` (mais
`~/.config/tt/checagens.md`, regras só desta máquina). Ele corrige o que é desta máquina, com cópia em `backup/` do que mexer no
perfil, e testa o que a versão trouxe. Defeito no código vira commit pronto sem push, na máquina de
desenvolvimento, ou tarefa no tt, nas outras. O relatório chega pelo 🔔. Instalação nova só marca a versão;
`checagem_auto=0` desliga; sem conta livre, tenta de novo a cada 30 min, até 3 vezes, e fecha só com o coletor.

- `tt --checar [--tsv]`: o coletor, sem IA. Uma linha por item, com estado (ok/aviso/falha) e correção; sai 1 com falha.
- `tt --checar-agente [--de VERSÃO] [--so-coletor]`, `tt --checar-ver [RODADA]`: rodada à mão e último relatório (menu administrar → 🩺).
- Registro centralizado em `~/.local/state/tt/checagens/`: `historico.log` e uma pasta por rodada (`relatorio.md`,
  `coletor.tsv`, `prompt.md`, `saida.log`, `backup/`); ficam as últimas 20.
- `tt --checar-handoff [ARQ]`: `.tar.gz` para entregar a quem mantém o tt (rodadas, fim dos logs, estado atual),
  com senhas, tokens e chaves mascarados, e-mails como `f***@dominio` e nada de `~/.secrets`.

## Demandas por e-mail

Quem você autorizar pode mandar tarefas para a sua rede do tt **por e-mail**. O e-mail cai na caixa de uma
conta com sync local (`sync_local=1`), o tt reconhece o formato e cria uma **demanda pendente** que só vira
tarefa quando você aprova.

- **Autorizar um remetente:** menu **⋯ do painel → ✉ Demandas por e-mail** (tela com prompts) ou
  `tt --demanda-autorizar EMAIL [etiqueta] [auth|relaxado|segredo|aberto] [segredo]`; `tt --demanda-remover EMAIL`;
  `tt --demandas` lista os remetentes e as pendentes. O cadastro (`~/.config/tt/demandas`, modo 600) é
  propagado às outras máquinas como o das contas de IA: vale a mudança mais nova (`--receber-demandas`,
  `--propagar-demandas`, `--puxar-demandas`; o vigia puxa a cada 30 min). A **etiqueta** é posta em toda
  demanda desse remetente como etiqueta local reservada: `netto` vira `#_netto`. Etiquetas iniciadas por `_`
  não podem ser criadas manualmente nem recebidas de outro usuário, e nunca seguem no e-mail de devolução
  (nem nos dados de comparação). As demais etiquetas viajam normalmente. A edição e a revisão preservam
  as etiquetas locais. Na atualização, etiquetas antigas são migradas somente em tarefas cuja origem
  corresponde ao remetente cadastrado, inclusive arquivadas; a migração é idempotente e guarda backup local.
- **Formato do e-mail:** assunto `[tt] título @sex 14h !alta *semanal #tag [~CÓDIGO]` — a mesma sintaxe de
  `tt --tarefa-add-natural`; com `~CÓDIGO` o e-mail cria/atualiza **aquela** tarefa (ver a seção de códigos acima). No corpo, linhas `- texto` (ou `* texto`) viram **subtarefas** e o resto vira a
  **descrição**; citação (`>`) e assinatura (`-- `) são ignoradas.
- **Segurança:** o `From` é forjável, então o padrão (`auth`) só aceita se o **provedor que recebeu**
  autenticou o remetente — `dmarc=pass`, ou `dkim=pass`/`spf=pass` alinhado ao domínio do `From`, lido do
  cabeçalho `Authentication-Results` **de cima** (o que o servidor final põe; o de baixo pode ser forjado).
  `relaxado`: para um endereço que você já autorizou, não exige `Authentication-Results` e aceita inclusive `fail` explícito; como o `From` pode ser falsificado, use apenas com remetentes confiáveis. `segredo`: o assunto leva `[tt:SEGREDO]`. `aberto`: sem checagem — só onde forjar não importa. Mensagem
  ignorada por falta de autenticação fica em `~/.local/state/tt/email-sync/<conta>.demandas.log` e gera um
  aviso. O texto do e-mail é dado não confiável: nunca é executado (e um agente que ler a tarefa deve tratá-lo
  como dado).
- **Fluxo:** depois de cada sync de uma conta, as mensagens ainda não vistas dos remetentes autorizados viram
  tarefas no estado **pendente** (mesmo arquivo das tarefas: sincroniza entre as máquinas e não aparece nas
  listas normais). Aviso na faixa (o clique abre o painel já na aba **Entrada**) e um chip **📥 N** na barra. Na
  Entrada, cada demanda aparece aberta com as subtarefas e as linhas **✓ aprovar** (vira tarefa aberta, com as
  subtarefas) e **✕ recusar** (lápide); `tt --demanda-aprovar ID` / `--demanda-recusar ID` fazem o mesmo.
- **Sem duplicar nem ressuscitar:** o id da tarefa sai do `Message-ID` e o horário dela é o da mensagem. Várias
  máquinas que sincronizam a mesma caixa criam a MESMA tarefa (o merge por id deduplica); aprovar ou recusar grava
  a hora de agora, que vence qualquer recriação tardia. A 1ª vez numa caixa só olha o que chegou nas últimas 24 h.
- Testes: `tests/test_demandas.sh`.

## Malha de máquinas (sem ilhas)

Todas as máquinas cadastradas se conhecem e se alcançam, sem você fazer nada além do primeiro `--cadastrar`:

- **Completa:** cada máquina publica o que sabe (`tt --malha-lista`) e aprende com as outras as que lhe faltam; quem aprende
  uma máquina se apresenta a ela. Roda no vigia a cada 15 min (`TT_T_MALHA`, segundos) e ao final do `--cadastrar`.
- **Coerente:** o rótulo é o que a máquina anuncia (`nome=` no config; sem `nome=` explícito o seu rótulo não é mexido).
  Descadastrar vale em todas (`~/.config/tt/maquinas-estado`, o registro mais recente vence) e a troca de listas não a ressuscita.
- **Inter-acessível:** só entra o que se prova (par da tailnet, o ssh entra e o nome de lá confere). A máquina se apresenta pelo
  IP que a outra vê; porta 8022 (sshd do Termux) vai para o `~/.ssh/config`; endereço que falha é trocado por outro que as demais
  usam, inclusive o IP da tailnet que quem tem o Tailscale anuncia (o celular sem o MagicDNS não resolve os nomes); máquina
  nova para esta entra pelo nome ou, se o nome não conecta daqui, por esse IP; chave faltando é reparada por uma máquina que
  já acessa o destino.
- **Sem fricção:** nada é perguntado. Se uma ilha persistir por 2 voltas, a barra avisa.

`tt --malha` completa e mostra quem alcança quem (`ok`, `○` desligada, `✗` ilha); sai com o número de conexões quebradas.
Desligada no Tailscale de quem pergunta é `○` em todas as linhas, mesmo na de uma máquina que não sabe disso (o Termux).
Rastros: `~/.cache/tt-malha.log`. Testes: `tests/test_malha.sh`.

**sshd garantido (v1.15.2):** `sshd_garantir` (vigia a cada 300 s por `--sshd-garantir --vigia`, só com outras máquinas
cadastradas; `tt --sshd-garantir` na hora; `sshd_garantir=0` desliga): algo escutando na 22 (8022 no Termux) → nada; com
`sudo -n`, `systemctl enable --now ssh` (ou `service ssh start` sem systemd); senão `sshd_usuario`, um sshd sem root na
8022 (só chave, `UsePAM no`, chave de host e config em `~/.local/state/tt/sshd/`, log `garantir.log`); sem o programa,
pendência essencial `sshd` (openssh-server). A `--malha-lista` anuncia a porta real (`sshd_porta`) e o conserto da malha,
com `porta-fechada`, tenta a 8022 no mesmo host (`malha_provar` grava o `~/.ssh/config`). O `tt --checar` tem a linha
`sshd`. Testes trocam as portas: `TT_SSHD_PORTA`, `TT_SSHD_PORTA_SISTEMA`, `TT_SSHD_SEM_SUDO` (`tests/test_sshd_malha.sh`).

## Código e apelido das tarefas, registro de trabalho e compartilhamento

Toda tarefa e subtarefa tem um **código** único (o id: 12 hex, igual em todas as máquinas) e um **apelido** curto e falável
derivado dele (ex.: `kito47`). Assim você, a IA e outra pessoa falam da mesma tarefa sem ambiguidade.

- **Onde aparece:** na própria lista do painel — o **apelido** vem antes do título de toda tarefa (`▸ ☐ kito47 Preparar apresentação`)
  e as subtarefas mostram a posição (`☐ .2 slide dois` = `kito47.2` **hoje**); em painel largo (80+ colunas) o **código** completo
  fecha a linha da tarefa e o **apelido estável** da subtarefa (`ruzi83` → `kito47.ruzi83`) fecha a dela. Também no cartão da tarefa (`^/`), no topo do menu ⋯ e em `tt --tarefas`. A busca do painel acha pelo apelido ou pelo código.
  `tt --tarefa-codigo [ID]` mostra apelido, código, texto e a referência estável (`MÃE.APELIDO` numa subtarefa).
- **Como usar:** todo verbo que recebe um ID (`--tarefa-ok`, `--tarefa-editar`, `--tarefa-sub-add`, `--tarefa-rm`, `--demanda-aprovar`…)
  aceita o apelido, o código, um prefixo do código (4+ caracteres), `MÃE.APELIDO-DA-SUB` (`kito47.ruzi83`, estável) e `MÃE.N`
  (`kito47.2` = a 2ª subtarefa **de hoje**: posição, desliza quando outras entram ou saem). Ambíguo: lista as candidatas.
- **Registro de trabalho:** `tt --tarefa-log ID "o que fez" --inicio 2026-10-10T15:10:00-03:00 --fim 2026-10-10T15:52:00-03:00 --como "…" --modelo M --esforco E --tokens-ent N --tokens-sai N` acrescenta
  à descrição um bloco com o instante de gravação em UTC e o intervalo RFC 3339 com fuso explícito, além do que foi feito, sessão, tokens e estimativas em USD/BRL.
  O código persistente da sessão tmux é registrado; `tt --session-resolve CÓDIGO` localiza a sessão pelo código mesmo após renomeá-la, para recuperar seu contexto enquanto ela existir. O custo usa `--usd`/`--brl` explícitos ou a tabela
  `~/.config/tt/precos` (`modelo<TAB>USD/Mtok entrada<TAB>USD/Mtok saída`) × `cotacao_brl` (padrão 5,50).
  `tt --tarefa-historico ID` lista os registros da tarefa e das subtarefas com o total. Os blocos aparecem em cinza no cartão.
- **Compartilhar por e-mail (upsert em três vias):** menu ⋯ da tarefa → **✉ Enviar por e-mail…** (ou `tt --tarefa-email ID DESTINO --abrir`,
  ou no menu do 📋 para várias de uma vez, `tt --tarefas-email DESTINO ID…`) abre **um e-mail por tarefa já preenchido** no compositor do tt
  (aerc): assunto `[tt] título … ~CÓDIGO`, corpo com a descrição (sem o diário de trabalho ⟡, que nunca viaja) e as subtarefas
  `- [CÓDIGO] [x] texto`, e depois da assinatura `tt:2 estado=… removidas=…` (um tt antigo ignora). Quem recebe (remetente autorizado, ver
  Demandas por e-mail): código desconhecido → nasce pendente **com o mesmo código**; código que já existe → **atualização** (↻) na aba Entrada,
  comparada em **três vias** (a sua tarefa × o e-mail × a última versão que os dois viram): o que só o e-mail mudou entra, o que só você mudou
  fica, o que os dois mudaram é **conflito** e nada é gravado até você decidir. **⇄ revisar mudanças** abre a tela de revisão (vim, clicável): por
  campo e por subtarefa, *Aceitar recebida · Manter minha · Ficar com as duas · Editar…*, mais *Aceitar tudo recebido* e *Manter tudo meu*;
  `Ctrl+S` aplica, `Q` cancela. Na Entrada também há *aprovar todas as que não têm conflito* e *recusar todas*. Estado da tarefa, concluir,
  reabrir, remover e acrescentar subtarefa viajam. Tarefa removida nunca ressuscita; código de subtarefa que já é de outra coisa vira subtarefa
  nova com código daqui. Em texto: `tt --demanda-diff ID`; `tt --demanda-aprovar [--recebida|--minha] ID` (sai 4 se houver conflito sem escolha).
- **Reforço nas IAs (AGENTS.md único):** as instruções globais de todas as IAs moram num arquivo só, `~/.agents/AGENTS.md`: o seu
  texto e, num bloco gerenciado, as regras acima (`agentes-regras-tt.md`). O vigia (a cada ~5 min) e cada instalação/atualização
  impõem isso no Claude (todas as contas), Codex e Kiro de cada máquina, inclusive nos proots do celular: o `CLAUDE.md` de cada conta
  do Claude e o `AGENTS.md` do Codex viram link para a fonte, o Kiro recebe uma cópia gerada (`steering/agentes.md`), e o Claude passa
  a ler o `AGENTS.md` de projeto mesmo onde há `CLAUDE.md`. Texto escrito à mão num desses arquivos vai para a fonte (cópia do
  original em `~/.local/state/tt/agentes-backup/`), e travas abandonadas das contas do Claude são apagadas. `tt --reforcar-agentes`
  faz na hora.
- Testes: `tests/test_tarefas_codigo.sh`, `tests/test_agentes_md.sh`.

## Janelas flutuantes (clicar fora fecha)

As telas do tt (central, seletor ☰, menus, painel de tarefas, agenda, notificações, fixadas, e-mail, transferências…)
abrem num `display-popup`, que é modal e **engole o clique fora dele** (medido no tmux 3.5a: nem dispara bind de mouse
nem fecha). O tmux 3.8 trouxe o painel modal (`new-pane -O -C`): um floating pane que fecha ao clicar fora. O tt usa
esse painel para **todas** as suas telas quando você liga, e só onde o tmux sabe (detecção pela capacidade do
`new-pane`, não pelo número da versão).

- **Liga/desliga:** menu **⋯ do painel → 🪟 Janelas flutuantes (clicar fora fecha)** (alterna e diz o estado), ou
  `tt --flutuante [status|on|off|alternar]`. Vem **desligado**: as telas seguem como popup, só na tela que clicou.
  Valor em `painel_flutuante=1` no `~/.config/tt/config` (por máquina, porque depende do tmux dela).
- **Como funciona:** todo `tmux display-popup` do código do tt passa por `popup_janela`, que recebe as mesmas
  opções e, ligado, abre o painel modal com a mesma caixa (largura/altura com a borda, `-x`, `-y S` encostado na
  barra, centralizado por padrão), o título na borda e o comando com `TT_CLIENTE` e `TT_EM_JANELA=1`. Os comandos
  de menu, que rodam em outro shell, chamam `tt --popup` com as mesmas opções do `display-popup`.
- **Diferenças do popup:** o painel é da **janela**, não do cliente — todo aparelho que olha a janela (o PC e o
  celular pela mesma sessão, por exemplo) o vê abrir e fechar. A borda `rounded` vira `single`. **Aberto, a barra de
  status fica inerte** (o tmux bloqueia o clique nela), então o botão que abriu não fecha a janela.
- **Fechar:** clique na janela fora do painel, `Esc` (ou o `q` da tela), ou escolher o item. Em tela estreita
  (menos de 80 colunas, o celular) a maioria das telas ocupa a janela inteira e não sobra "fora" para clicar: use
  `Esc`. Se um aparelho cair com uma janela aberta, ela fica na janela até alguém clicar fora ou apertar `Esc`.
- **O que continua popup:** o modal das **pendências** (apt/sudo no meio da instalação) e o **navegador**, para um
  clique perdido não interromper uma instalação nem fechar uma página. Também cai no popup de sempre quando a janela
  já tem um modal (o painel de tarefas aberto) ou é pequena demais.
- O painel de tarefas, que já era assim, segue tendo o toggle: `tt --tarefas` de novo o fecha.
- Sem tmux 3.8 (hoje a maioria das distribuições traz 3.5/3.6), ligar não quebra nada: o rótulo avisa
  "precisa ser 3.8+" e tudo abre como popup. A opção é por máquina e **vale assim que o tmux dela passa a 3.8**: uma
  máquina que já tinha `painel_flutuante=1` de antes muda de popup para janela flutuante no dia da atualização.
- O painel flutuante não conta como divisão da janela para a barrinha de título dos painéis (`tt --bordas`): com
  um flutuante aberto a borda mostra só o título dele (`pane-border-status top-floating`).
- Testes: `tests/test_janelas_flutuantes.sh` e `tests/test_flutuante.sh` (a parte com o painel real exige um tmux
  3.8; aponte `TT_TMUX_38` para o binário se o do sistema for mais velho).

## Versões de tmux misturadas

O tt compila o tmux 3.8 por conta própria quando a máquina tem um mais velho (pendência 📦), então é comum haver
dois tmux na mesma máquina: o do sistema (3.5/3.6) e o do tt (`~/.local/share/tt-tmux`, com links em
`~/.local/bin` e `~/.local/share/tt-bin`). Medido com 3.5a, 3.6b e 3.8:

| servidor ↓ / cliente → | 3.5a | 3.6b | 3.8 |
|---|---|---|---|
| 3.5a | ok | ok | ok |
| 3.6b | **falha** | ok | ok |
| 3.8 | **falha** | ok | ok |

Só um cliente **mais velho que o servidor** (hoje, o 3.5a) falha: `server exited unexpectedly`. Por isso, dentro do
tmux o tt chama o **binário do próprio servidor** (`$TMUX` = socket,PID,sessão → `/proc/PID/exe`), mesmo que o PATH
do painel ache outro, e o passa em `TT_TMUX_BIN`; o `ia-rot`, os auxiliares em python e os comandos de popup fazem o
mesmo. Fora do tmux (cron, ssh) o tt usa o PATH dele, com `~/.local/bin` e `tt-bin` na frente. Seus próprios
comandos `tmux` num painel seguem o PATH do seu shell: se aparecer `server exited unexpectedly`, ponha
`~/.local/bin` antes de `/usr/bin` no PATH. Teste: `tests/test_tmux_versoes.sh` (acha sozinho um par velho/novo;
aponte `TT_TMUX_VELHO` e `TT_TMUX_NOVO` para testar outro).

## Hora confiável

O relógio de uma máquina deriva (WSL depois de hibernar, celular sem bateria) e o tt decide coisas com
ele: prazo vencido, "hoje", lembretes, a ordem das edições no merge das tarefas e a data/hora da
barra. Por isso o vigia mede, a cada 6 h (`TT_T_HORA`; de 15 em 15 min enquanto não houver medida), o
desvio do relógio contra a internet — cabeçalho `Date` de Cloudflare, Google e Apple, pela mediana, e
só vale se duas fontes concordarem (uma fonte sozinha vale até 1 dia de desvio) — e usa
**relógio da máquina + desvio**. Sem rede, sem endpoint, sem Python ou com medida de mais de 12 h, vale o
relógio da máquina: ele é só a reserva.

- `tt --hora` mostra o relógio, o desvio e a hora que o tt está usando; `tt --hora --sincronizar` mede
  agora; `tt --hora agora` imprime o epoch confiável (para scripts).
- Com desvio de 60 s ou mais, a hora da barra deixa de ser o `%H:%M` do tmux (relógio da máquina) e passa a
  ser a corrigida (`@barra_hora`, renovada pelo vigia a cada volta); com desvio menor nada muda.
- `hora_sync=0` no `~/.config/tt/config` desliga a medição; `hora_urls=` troca a lista (separada por
  espaços). A medição usa HTTPS: com o relógio da máquina errado por semanas o certificado falha e fica o
  relógio dela (de propósito: um HTTP forjável não deve mexer nos seus prazos).
- Testes: `tests/test_hora.sh` (servidores falsos com o relógio adiantado).

## Fechar sessões

Na central e no seletor, cada sessão tem, alinhados à direita, o pino (📍 fixar / 📌 desafixar —
liga e desliga a sessão na barra de fixadas) e o ✕ (os painéis só têm o ✕). Um toque no ✕
vira "fechar? ✕"; o segundo fecha. Tocar em qualquer outro ponto da linha abre a sessão (e cancela
a confirmação). Pelo teclado: `^x` fecha a selecionada. (A coluna do clique é lida por uma camada
fina em Python entre o terminal e o fzf; sem python3, a lista funciona sem o ✕.)

O vigia de cada máquina também fecha sozinho as **sessões paradas**: sem tecla, toque, anexo nem
saída na tela há N minutos (menu do painel → "⏱ Sessões paradas", ou `tt --definir-paradas N`,
que vale para todas as máquinas; padrão 30, 0 desliga) e sem nada rodando, nem em segundo plano.
Shells interativos ociosos aninhados (um `bash -l` aberto para recarregar o PATH) e o invólucro do
`proot-distro login` não contam como programa; um agente aberto, um `sleep &` ou um `sh -c` contam.
Sessões abertas em alguma tela, fixadas e pontes nunca são fechadas assim.

**Sessões ocultas:** uma sessão cujo nome começa com `_` (`_tt-email`, `_tt-vigia`…) é infraestrutura e fica fora
da central, do seletor, do mestre de obras, da renomeação do vigia e de toda poda (vazias, expiradas, paradas). É
a convenção para manter uma sessão viva sem ela aparecer: `tmux new-session -d -s _minha 'sleep infinity'`.

## Arquivos

    tt --enviar                          navega a partir da pasta atual; escolhe máquina e pasta
    tt --enviar a.pdf fotos/ trabalho    envia para a pasta de recebidos de "trabalho"
    tt --enviar a.pdf trabalho:~/docs    envia para essa pasta
    ... | tt --enviar --stdin NOME [máq]  o que vier no pipe vira o arquivo NOME no destino
    tt --trazer                          escolhe máquina, pasta e arquivos de lá → pasta atual
    tt --trazer trabalho:~/x.log [pasta] traz direto
    tt --pasta-padrao                    escolhe (navegando) onde chegam os arquivos nesta máquina
    tt --pasta-padrao trabalho:~/docs    define a pasta padrão de outra máquina

Cada máquina tem sua pasta padrão de recebidos: `~/Recebidos`; no WSL, `Downloads\Recebidos` do
Windows; no Termux, `Download/Recebidos` do Android. Dá para mudar por ⋯ painel → ⚙ tmux… → Administrar ("Pasta padrão de recebidos…"),
pela lista de destinos ao enviar ("⚙ mudar a pasta padrão de …") ou com `tt --pasta-padrao`. Os
arquivos chegam com a data de chegada, e o destino mostra onde a pasta aparece (Explorer, só no
WSL, app de arquivos do Android).

O navegador também transfere **pastas inteiras**, com todas as subpastas e arquivos: navegue até a
pasta que quer enviar ou trazer, aperte `Tab` para marcá-la e `Enter` para confirmar. Pela linha de
comando, basta passar a pasta normalmente: `tt --enviar projeto empresa:~/Recebidos` ou
`tt --trazer empresa:~/projeto .`. Se já existir uma pasta com o mesmo nome no destino, ela chega
como `projeto (2)`; nada é sobrescrito.

Na central: `^s` envia para a pasta da sessão escolhida; `^g` traz de lá para a pasta do painel.

## Botões inteligentes

Botões (ou teclas) que olham o estado e seguem o fluxo. Cada um manda `Ctrl+B F1…F10`, e o tmux
chama `tt --botao <ação>`:

| Botão | Tecla | O que faz |
|---|---|---|
| `CL` | F1 | Claude Code com conversa nova na pasta atual, sempre numa sessão nova |
| `CLC` | F2 | continua a última conversa (`--continue`) na pasta atual: vai para a sessão do Claude que já existe ali, cria uma se não houver, e volta para a anterior se você já está nela |
| `CLR` | F3 | abre o seletor de conversas (`--resume`) numa sessão nova |
| `DBN` | F4 | Debian (proot-distro, no Termux) na pasta atual, com a mesma lógica do `CLC` |
| `TL` | F5 | liga ou desliga o túnel da tela remota (`tela_destino=usuario@host` em `~/.config/tt/config`; opcionais `tela_porta` e `tela_url`) |
| `X` | F6 | fecha o painel, a janela ou a sessão se estiver vazia (shell parado); se há algo rodando, só desanexa |
| `ANT` | F7 | volta para a sessão anterior |
| `DV` | F8 | divide o painel pelo lado maior |
| `ZM` | F9 | zoom do painel |
| `JN` | F10 | janela nova na pasta atual |

O `CL` e o `DBN` usam o `claude` local; no Termux, o do Debian (`proot-distro`). No Termux, copie
[`termux/termux.properties`](termux/termux.properties) para `~/.termux/termux.properties` e rode
`termux-reload-settings` para ter os botões na barra de teclas extras.

## Atalhos de comandos

A barra também mostra um emoji por comando em `atalhos-padrao`, versionado junto com o tt. O padrão
são quatro botões, iguais no PC e no celular:

- 🚀 **ia-nova** abre a IA com mais folga de uso **agora** (`ia-conta abrir`, veja [Contas de IA](#contas-de-ia)),
  já sem pedir permissões, numa sessão nova e muda para ela;
- 👇 **ia-aqui** faz o mesmo no lugar do que roda no painel atual (fecha o agente que estiver nele, ou parte do
  shell), na mesma pasta. Se ali havia uma conversa do Claude e a escolhida também é do Claude, a
  conversa continua (`{retomar}` vira `--retomar ID`); Codex e Kiro abrem uma sessão nova;
- ⏩ **ia-seguir** passa a conversa de IA do painel (Claude, Codex ou Kiro) para outra IA, escolhida pelo
  rotador (em geral porque a conta da atual está ficando sem créditos): acha a conversa e o código dela,
  encerra o agente e abre a nova IA ali mesmo, com um pedido para ler a conversa inteira e seguir o trabalho
  de onde parou. Veja [Seguir a conversa com outra IA](#seguir-a-conversa-com-outra-ia);
- 🎤 **voz** abre a conversa por voz com o tt (também `Ctrl+B v`), numa janela flutuante encostada na barra. Veja
  [Conversar com o tt pela voz](#conversar-com-o-tt-pela-voz).

Um comando que começa com `@aqui ` roda no painel atual em vez de numa sessão nova; um que começa com
`@seguir ` é o da ⏩ (o resto do comando abre a nova IA, com `{prompt}` no lugar do arquivo do pedido); um que
começa com `@janela ` roda numa janela flutuante sobre a tela, na pasta do painel, e ela fecha quando o comando
termina (um clique fora não a fecha: a tela de baixo continua visível). No
celular os três entram no Debian (`proot-distro login debian --shared-tmp -- bash -lc '…'`) e põem eles
mesmos o `~/.local/bin` de lá no PATH, sem depender do `~/.bashrc` do Debian. O que é próprio do celular
fica no comando do perfil (`atalhos-padrao-mobile`), não no tt: o menu de contas e a ⏩ usam o próprio comando
do atalho e por isso funcionam lá do mesmo jeito.

Cada máquina pode sobrescrever, desativar ou acrescentar atalhos em `~/.config/tt/atalhos`, no mesmo
formato `emoji<TAB>id<TAB>comando<TAB>cor-de-fundo<TAB>menu` (a cor, em hexadecimal como `#cba6f7`, e o
menu são opcionais). A segunda coluna é o ID estável: uma linha local com o mesmo ID substitui a padrão; emoji
`-` desativa; um ID novo acrescenta:

    👾	kiro-v3	kiro-cli chat --v3
    -	codex
    🧪	meu-teste	ssh servidor

### Menu do botão direito

O clique num atalho faz sempre a mesma coisa. Com a 5ª coluna preenchida, o **botão direito** abre um menu
com outros jeitos de rodar o mesmo atalho (sem ela, o botão direito só mostra o comando, como antes). Os
itens vão separados por ` ;; ` e podem ser fixos ou dinâmicos:

| Item | O que vira no menu |
| --- | --- |
| `@contas` | uma opção por conta de IA desta máquina, com o uso de cada uma; o comando roda com `{conta}` = `--conta NOME` (sem o rotador). As contas saem do próprio comando, com `{conta}` = `--listar-contas`, então valem as do ambiente em que o atalho roda (no celular, as do Debian) |
| `@maquinas` | uma opção por máquina do tt: o atalho de mesmo ID roda numa sessão nova da máquina escolhida (com o perfil de atalhos dela) e a tela vai para lá; na ⏩, a conversa segue lá |
| `Rótulo=comando` | opção fixa (o comando segue as regras do atalho: `@aqui`, `{retomar}`, `{conta}`) |
| `-` | separador |

Clicado direto (ou pelo primeiro item do menu), `{conta}` some e o rotador escolhe. Os padrões: 🚀 e 👇 com
`@contas`, ⏩ com `@maquinas`. A lista de contas fica guardada (o menu abre na hora) e se renova em segundo
plano a cada 2 min de uso.

Para editar sem abrir
o arquivo: menu ⋯ do painel → **✏ Atalhos da barra** (⏎ edita emoji, comando, menu e cor; ^n novo; ^x
exclui ou desativa um padrão; ^r volta ao padrão). O arquivo continua editável à mão. Os botões “lado” e “baixo” ficam disponíveis no menu de
painel, mas não ocupam mais a barra.

As contas não ganham mais um botão cada: os atalhos escolhem entre todas, e o menu do botão direito deixa
escolher uma. O arquivo versionado pode ser alterado no repositório para que novos atalhos padrão cheguem a
todas as máquinas.

## Conversar com o tt pela voz

O 🎤 da barra (ou `Ctrl+B v`) abre uma janela de conversa: você fala, o tt mostra o que entendeu, age e responde
falando. Funciona no Linux, no macOS e no Windows (pelo WSL); no celular o Tasker ouve e fala (guia na skill
`celular-android`, seção 15) e a janela mostra a conversa. O que dá para pedir é o mesmo do celular: máquinas e
status, escolher e ler sessões, falar com um agente (escolher a sessão já a libera; "bloquear sessão" a solta), abrir
uma IA nova como o 🚀 ("abra uma sessão nova na empresa com o codex para revisar o bimo": pelo rodízio de contas, ou a
IA ou a conta que você disser, já com o 1º pedido), trocar a IA do painel como o 👇, passar a conversa como a ⏩, ler as
tarefas e as subtarefas, o uso das contas. Frases curtas ("máquinas", "status", "dois", "encerrar") vão direto às
regras; o resto vai ao **cérebro**, um Claude (o Sonnet, pelo rodízio de contas) que entende a frase solta e escolhe
as ações. Na janela ele roda nesta máquina, sem configurar nada (`voz --cerebro "pc local"` escolhe outro lugar;
`voz --cerebro -` deixa só as regras; `voz --cerebro-modelo haiku|sonnet|opus` troca o modelo: medido com frases reais,
o Sonnet acerta as ambíguas que o Haiku errava, por ~1 s a mais). A janela mantém esse Claude aberto a conversa toda
(stream-json, a conta escolhida pelo rodízio ao abrir): cada volta leva ~1,5 s, contra ~7 s de um Claude que parte do
zero; enquanto ele abre, ou se cair, vale o caminho de sempre.

**As sessões de todas as máquinas:** a janela guarda um índice de todas elas (agente, título, se está trabalhando ou
parada), renovado a cada 30 s em segundo plano, e o cérebro escolhe por ele: "vá para a sessão que revisa o bimo" acha
a sessão em qualquer máquina, pelo nome ou pelo título. "Panorama", "resumo de todas as sessões" ou "o que está
acontecendo nas sessões" leem todas de uma vez (todas as máquinas ao mesmo tempo, `voz --panorama [MÁQUINA]`) e
resumem o que cada uma faz, primeiro as que esperam por você. `voz --indice-local [N]` é o índice desta máquina.

Na janela: **Espaço** encerra a frase na hora (sem esperar o silêncio) ou pula a fala; **t** digita uma frase (no
escritório, ou sem microfone); **n** passa ao microfone seguinte (e o tt lembra dele); **c** abre as opções; **m** liga
e desliga a voz; **Esc** fecha. A janela tem até 96 colunas e quase a altura toda da tela, e a conversa rola: a roda
do mouse, as setas, **PgUp**/**PgDn** e **Home**/**End**; rolada para cima, ela não pula quando chega texto (embaixo
aparece quantas linhas novas há; **End** volta). Sem o reconhecimento de voz instalado, a janela oferece instalar ali
mesmo, em segundo plano (sem sudo: sem o `python3-venv`, o pip vem pelo `get-pip.py`), segue digitando e passa a ouvir
quando termina; um erro de segundo plano vai a `~/.cache/tt-voz/erros.log`, nunca à tela. Duas vezes sem ouvir nada, ou "encerrar", também fecham. O botão direito do 🎤 tem "Só
digitando", "Opções: modelos, microfone e som", "Testar o microfone e a voz" e "Instalar a voz neural".

**A voz é do aparelho onde você está:** o 🎤 clicado numa ponte (vendo esta máquina de outra) abre a janela na máquina
de origem, com o microfone e o som dela, já com a sessão que estava na tela como alvo. Perguntas sobre o estado de uma
sessão ("o que ela está fazendo?") respondem na hora, pela tela de agora; depois de mandar um pedido, a janela espera uns
30 s e, se o agente segue trabalhando, avisa sozinha quando ele terminar. Numa ponte, a leitura e o texto vão à sessão de
verdade da outra máquina.

**As telas que o agente mostra antes de conversar** (e no meio do trabalho) a voz não lê para você à toa. Na sessão que
ela abriu (o 🚀 pela voz, o 👇 e o ⏩), o tt responde sozinho o que é rotina: pular a atualização, aceitar os termos sem
ceder as conversas para treino, o tema, o "Enter para continuar", o aviso do modo sem permissões que o próprio 🚀 pediu,
o login que já deu certo. "Confiar nesta pasta" ele só responde sozinho se a pasta está na **sua lista**
(`~/.config/tt-voz/pastas`: uma por linha, `[MÁQUINA:]PASTA`, com `PASTA/**` valendo as subpastas; `voz --pastas add
'~/Projetos/**'`, `voz --pastas rm …`, `voz --pastas`); fora dela, a voz pergunta e "sempre" põe a pasta na lista. O que
pede senha, credencial (login, chave de API), algo destrutivo (apagar, sobrescrever, `rm -rf`, `drop table`), uma
permissão nova de execução (rodar um comando, editar, servidor MCP, "não perguntar de novo", acesso total) ou dinheiro
(créditos) a voz **nunca** responde: lê a pergunta e as opções e espera você dizer o número, sim, não ou sempre. Senha
ela nem lê: você digita no terminal. Pergunta que ela não conhece também é sua. Tudo o que foi respondido sozinho fica em
`~/.local/state/tt-voz/aprovacoes.log`. Quem reconhece as telas é o catálogo `telas-agentes.conf` (Claude, Codex, Kiro,
Gemini e blocos para qualquer agente), que você estende em `~/.config/tt/telas-agentes.conf`: um bloco com o mesmo `[id]`
troca o do pacote (por exemplo, para ouvir o aviso do modo sem permissões, `classe = decisao`), `classe = -` desliga.
As decisões vêm sempre antes das rotinas, e a opção que "não pergunta de novo", "sempre", "todas" ou apaga nunca é
escolhida sozinha, mesmo que um bloco peça.

**Esperar e acompanhar:** "espere um minuto e depois confira a sessão" (ou "daqui a 30 segundos leia a resposta",
"espere 10 minutos e resuma a sessão site", "me chama em 5 minutos") agenda e deixa você livre; na hora, a voz confere
e fala sozinha o resultado, ou a pergunta que exige decisão. "Me avise quando ele terminar" e "acompanhe a sessão até
concluir" vigiam a sessão (até 2 h): a voz fala quando ela terminar ou pedir uma decisão sua, e responde sozinha a
rotina. "O que você está esperando?" lista; "cancele a espera" ou "pare de acompanhar" cancela. No celular, o daemon faz
o mesmo e responde pelo canal do pedido (o Tasker ou o bot do Telegram).

**Modo retorno (a voz chama você):** "modo retorno" (ou "me chama quando elas terminarem", "pode ir que eu espero") fecha
o microfone: a janela mostra quem está em aberto (`⏸ retorno: site há 3min`) e, quando uma sessão a que você pediu algo
responde, pede uma decisão sua ou fecha, toca um aviso curto, fala o resultado (ou a pergunta com as opções) e abre o
microfone para a sua resposta; em silêncio, volta a esperar. Espaço fala com ela, `t` digita, `r` sai do modo. "Modo
retorno por 5 minutos" põe um prazo: se nada chamar nesse tempo, a voz chama assim mesmo, com um resumo do que cada
sessão fez desde o seu pedido (o cérebro compara a tela de agora com a da hora do pedido); cada retorno zera a contagem.
No modo, o pedido a um agente não espera ouvindo ("Te chamo quando responder"); sem nada em aberto, a voz sai do modo
sozinha. "Ligar o retorno automático" faz cada pedido já entrar nele. Nas sessões abertas pela voz, o Claude e o Codex
avisam na hora quando terminam ou pedem algo, com a última mensagem deles: o `ia-conta` passa o gancho `Stop` e
`Notification` ao Claude (`--settings`) e o `notify` ao Codex (`-c`), só nessas sessões e sem mudar a sua configuração;
Kiro, Gemini e outros são conferidos pela tela (todas as sessões de uma máquina numa ida, a cada 10 s).
O daemon do celular também confere o retorno e seu prazo, mesmo sem outra espera em andamento;
a resposta segue pelo Tasker ou Telegram conforme o canal do pedido.

**A interface do tt pela voz:** "fixar esta sessão" (ou "fixe a sessão site"), "desafixar a sessão X", "quais são as
fixadas", "mova a fixada X para o início" (fim, esquerda, direita, posição 3) e "agrupe as fixadas"; "nova tarefa comprar
pão para amanhã às 14 horas" (vira `@amanha 14h`; "urgente" no fim vira `!alta`), "adicione a subtarefa X na tarefa Y",
"conclua a tarefa X", "reabra a tarefa X", "mude o prazo da tarefa X para sexta", "tire o prazo da tarefa X", "qual o
apelido da tarefa X", "apague a tarefa X" (pede o sim); "ler as notificações" (as não lidas), "marque as notificações
como lidas", "limpe as notificações" (as lidas, pede o sim); "o que está no letreiro", "pause o letreiro", "continue o
letreiro".

Os outros controles seguem a máquina escolhida na voz:

- "Esconda a barra das fixadas" e "mostre a barra das fixadas" mudam a altura da barra e preservam as sessões fixadas.
- "Não perturbe por dez minutos", "ligue o não perturbe" e "desligue o não perturbe" controlam os avisos do aparelho e as mensagens sobrepostas do tmux. O histórico e o contador do sino continuam disponíveis. Sem duração, fica ligado até desligar.
- "Mude a mensagem do letreiro para Reunião às 14h" substitui uma mensagem local e preserva as outras fontes. O texto é tratado como texto, inclusive quando contém pontuação.
- "Renomeie esta sessão para Revisão da sprint" ou "renomeie a sessão site para Portal" mantém o alvo da voz, fixadas, esperas e retornos associados à sessão.
- "Abra o e-mail", "abra transferências" e "abra o calendário" usam o terminal conectado à sessão escolhida. "Contas de e-mail", "estado do e-mail", "ver transferências" e "ler calendário" respondem pela voz.
- "Troque a conta para career" pede confirmação, pois interrompe o agente da sessão escolhida. "Trocar conta" lista as contas disponíveis. A confirmação perde validade se a sessão ou o painel for substituído.

Pelo terminal, os mesmos controles estão em `tt --fixadas-faixa on|off|status`, `tt --nao-perturbe on|off|SEGUNDOS|status`,
`tt --letreiro-mensagem "TEXTO"` e `tt --renomear SESSÃO "NOME"`. O menu Administrar também alterna a barra das fixadas e o não perturbe.

**Fechar sessões e a limpeza:** "feche a sessão X" pergunta antes ("diga sim para fechar"); se é a sessão escolhida, ou
se o agente dela está trabalhando, pergunta duas vezes. "Limpeza" (ou "quais sessões posso fechar", "limpe as sessões
do dell") olha todas as sessões das máquinas: quem está olhando, fixada, papel no tt, texto não enviado, uso recente,
agente esperando sua resposta, outro programa aberto ficam; terminal sem programa parado há mais de 1 h e agente parado
há mais de 4 h são sugeridos, cada um com o motivo ("velha, no dell: terminal sem programa, parado há 2 dias"). Depois:
"fechar" fecha todas da lista (conferindo antes que ninguém voltou a usar), "tira a dois" deixa uma de fora, "cancelar"
não fecha nada.

**As opções** (tecla **c**, ou `voz --opcoes`) escolhem o modelo do cérebro (1 Haiku, 2 Sonnet, 3 Opus), o da
transcrição (a automático, ou b–f um fixo: tiny, base, small, medium, turbo, com o que esta máquina mediu de cada um), o
microfone (n), a sensibilidade do microfone (g), a saída de som (s) e a voz (v, com um exemplo). **l** abre a escolha da
máquina de transcrição: digite o número e Enter (0 volta ao automático; Esc cancela). Ao voltar à conversa, o motor é
trocado; se a máquina não responder, o anterior continua e a janela avisa. A escolha fica guardada em `~/.config/tt-voz`
e vale também na máquina que transcreve.

**A sensibilidade** diz a partir de que nível o som conta como fala: normal (350, o padrão), alta (180), máxima (100) ou
baixa (600, para sala barulhenta); em sala com ruído, o limite sobe sozinho acima do ruído. Um headset com filtro de
ruído próprio (o BlackShark, por exemplo) entrega a voz baixa: use a alta ou a máxima (**g** nas opções, ou
`voz --limiar alta`). Quando ouve um som que durou mas ficou abaixo do limite, a janela diz o nível e como aumentar.

**O microfone** é escolhido pelo tipo: o headset (ou um microfone dedicado) antes do USB e do Bluetooth, depois a
webcam, por último o embutido; os que não entregam áudio (o conector de fone vazio, um filtro sem sinal) ficam de fora.
`voz --microfone "blackshark, headset"` fixa a preferência. No Windows (WSL), o tt grava direto do microfone escolhido
(`voz-windows.ps1`), sem mudar o padrão do Windows, que continua sendo o das chamadas.

**A voz** é gerada no motor (aqui, ou na máquina que transcreve) e sai no mesmo aparelho do microfone (o headset ouve
e fala; o microfone embutido, o alto-falante embutido); sem par, a saída de melhor nota. Vozes: **Piper Faber** (a
padrão; neural e offline), **Francisca**, **Antônio** e **Thalita** (as neurais da Microsoft, as do Edge: quase humanas,
mas online, e o texto falado vai ao serviço dela) e **a do sistema** (a do Windows, o `say` do macOS, o `spd-say`). Nas
opções (**c**), **v** passa à seguinte e fala um exemplo; `voz --voz piper:pt_BR-faber-medium|edge:pt-BR-FranciscaNeural|
sistema` fixa. A fala vai frase a frase (a primeira toca enquanto a seguinte é gerada). No Windows a saída padrão costuma ser o alto-falante ou a P2 e o headset é só o de
chamadas: o tt toca direto no aparelho escolhido. `voz --saida "nome"` fixa a saída.

**A transcrição** é escolhida pela medida. Cada máquina com o Whisper mede, na instalação, cada jeito que tem (o
modelo × a CPU ou a GPU NVIDIA) com frases de referência, em tempo e em erro. Ao abrir, a janela pergunta a todas as
suas máquinas ao mesmo tempo e fica com a de menor custo (o tempo, a carga de agora e a rede, mais o erro), deixando de
fora as desligadas sem esperá-las de novo por 10 min. O tempo de cada frase de verdade corrige a escolha seguinte, e
se a escolhida ficar lenta no meio da conversa a janela passa para a próxima sozinha. Exemplo: o notebook com uma
GeForce MX250 transcreve uma frase em 0,9 s na GPU (2,6 s na CPU), e um computador sem o Whisper usa essa GPU pela
rede em ~0,9 s.

| | Gravar (o fim da frase é o silêncio) | Transcrever | Falar |
| --- | --- | --- | --- |
| Linux | as fontes do PulseAudio/PipeWire pela escolha acima; sem elas, `pw-record`/`arecord` e o microfone direto pelo ALSA | o de menor custo: aqui (CPU ou GPU) ou noutra máquina | Piper (voz pt-BR), ou `spd-say`/`espeak` |
| macOS | as entradas do Core Audio, pelo `sox` (`brew install sox`) ou pelo `ffmpeg` | o de menor custo (aqui só a CPU) | `say` com a voz Luciana |
| WSL | o microfone do Windows escolhido, direto (ou o padrão, pelo WSLg) | o de menor custo (em geral noutra máquina, sem pesar no disco do Windows) | a voz pt-BR do Windows (Maria) |
| Celular | Tasker | Google (no Tasker) | Tasker |

- `voz --instalar-audio` cria `~/.local/share/tt-voz/venv` com o faster-whisper e o Piper (e, com GPU NVIDIA, as
  bibliotecas CUDA, ~2 GB), baixa a voz pt-BR do Piper e os modelos e mede. `voz --medir` mede de novo (a janela também
  mede sozinha, em segundo plano, quando um pacote, um modelo ou a GPU mudou).
- `voz --audio` mostra os microfones, as medições, a GPU e o ranking dos lugares de transcrição.
- `voz --transcrever "local pc"` limita onde transcrever; `voz --modelo base|small|medium|large-v3-turbo` fixa o modelo;
  `voz --fala piper|say|windows|spd|espeak|nenhum` escolhe a voz.
- `voz --audio-teste` grava uma frase, mostra o nível, transcreve e repete o que ouviu.
- Para esconder o botão nesta máquina: a linha `-	voz` em `~/.config/tt/atalhos`.

### Seguir a conversa com outra IA

A ⏩ acha a conversa do agente que roda no painel: a do Claude pelo registro do processo, a do Kiro pela trava
que ele grava com o pid, a do Codex pela pasta e pela hora (a conversa daquela pasta mexida depois que o agente
começou; havendo mais de uma, a que tem mais linhas da tela do painel). Painel sem agente não muda nada.

- **Nesta máquina** (o clique): a conversa vai em Markdown para `~/.cache/tt/conversas/CÓDIGO.md`, o pedido para
  `~/.cache/tt/seguir/`, e a nova IA abre no mesmo painel e na mesma pasta, já com os dois.
- **Noutra máquina** (botão direito → ⏩ Seguir em …): a máquina escolhida abre a nova IA numa sessão nova, com o
  ⏩ do perfil dela, buscando antes a conversa na de origem pela rede do tt; só depois que ela abriu o agente
  daqui fecha (o painel fica num shell dizendo onde a conversa seguiu) e a tela vai para lá. O pedido diz qual é
  a máquina de origem e como entrar nela (`ssh`), porque os arquivos do trabalho continuam lá.

`tt --conversa-ia CÓDIGO [--de MÁQUINA] [--salvar]` imprime (ou salva) qualquer conversa do Claude, do Codex ou do
Kiro desta máquina ou de outra: as falas inteiras, cada ferramenta com os argumentos e o que ela devolveu cortado em
1500 caracteres, sem os pensamentos nem as mensagens internas do agente.

### Roda nos chips

A roda do mouse (ou o arrasto, no celular) sobre os dois primeiros chips da barra:

- `máquina ▾`: vai à máquina seguinte (para baixo) ou anterior (para cima), na ordem do cabeçalho da central
  (esta primeiro, depois as cadastradas e ligadas), dando a volta, na primeira sessão da lista de lá (a de uso
  mais recente); sem nenhuma, cria uma. Máquina que não responde em ~3 s é pulada com aviso, e por 1 min a
  roda nem tenta de novo. Vendo outra máquina por ponte, quem troca é a máquina da tela, na ordem dela.
- `sessão ▾`: a sessão seguinte ou anterior desta máquina, na ordem do `Ctrl+B (`/`)` (por nome), sem pontes
  nem sessões ocultas, dando a volta.

Uma rolagem longa manda vários eventos: a roda anda um passo por vez (o resto da rajada cai). No resto da
barra, a roda continua com o padrão do tmux (janela anterior/seguinte). `TT_T_ROLAR` (s) muda a espera por
uma máquina e `TT_ROLAR_FOLGA` (ms), a folga entre passos.

### Voz com autonomia: planos, temas, conversas antigas e sessões que conversam (2.1)

- **Autonomia.** O que você não disser (máquina, IA, pasta, sessão) o cérebro decide e segue, sem perguntar nem bloquear: "quero trabalhar na
  conciliação do bimo" escolhe ou abre a sessão certa, manda o pedido já escrito com contexto e conta numa frase o que escolheu. Só pergunta
  quando a dúvida muda o resultado e errar sai caro.
- **Planos compostos, um ok só.** Um pedido grande vira todas as ações num turno: ler, resumir, fixar, desafixar, abrir, enviar… rodam direto. O
  que destrói (fechar sessão, apagar tarefa, apagar avisos lidos, juntar sessões) o tt junta numa **fila** e faz **uma** pergunta com tudo
  ("Vou fazer isto: 1, fechar a sessão a. 2, juntar as abas de b na c…"); você diz **sim** (executa tudo, em ordem), **tira o 2** ou **tira a b**
  (tira um item), ou **não** (limpa). Nada da fila roda antes do sim, e sessão `_*` nunca entra. Frase com dois pedidos ("apaga a tarefa X **e**
  fecha a sessão Y") vai ao cérebro, não a uma regra simples que faria só a primeira metade.
- **Temas.** "Resuma por tema": lê todas as sessões, agrupa por assunto e fala cada grupo; os grupos ficam guardados e você age sobre eles
  ("fixa as do deploy, fecha as do site"), o que vira ações por sessão no mesmo plano.
- **Juntar sessões.** `juntar_sessoes` leva as abas das origens para a sessão que fica (`tmux move-window`, mesma máquina); as origens fecham
  ao ficar sem abas e a fixada órfã sai da barra. Entra na fila do plano.
- **Conversas antigas, de qualquer conta, em qualquer máquina.** "Aquela conversa sobre conciliação bancária": o `busca-tt.py` indexa **todas**
  as conversas em disco (Claude, Codex e Kiro; todas as contas; dentro do proot do Termux também), das últimas `TT_BUSCA_DIAS` (120), mais novas
  primeiro, num orçamento de `TT_BUSCA_ORCAMENTO` s por volta do vigia (60), só o que mudou. A voz procura em todas as máquinas ao mesmo tempo,
  lê as melhores e **retoma** a escolhida: onde ela mora, na mesma conversa, sem pedir permissões (`ia-conta retomar`); noutra máquina, abre ali
  uma IA que lê a conversa e segue de onde parou. `tt --busca-conversas TEXTO` faz a mesma busca na linha de comando.
- **Sessões que conversam.** "Peça à sessão backend para validar o que a site fez": `voz --sessao-falar ORIGEM DESTINO "mensagem" [RODADAS]`
  (`tt --sessao-falar`; ORIGEM e DESTINO = `máquina:sessão`; `-` = a voz) entrega a mensagem ao agente de destino, espera a resposta e a devolve à
  origem; com RODADAS (1 a 6) segue indo e voltando. Mesma máquina ou máquinas diferentes. Se o destino demora mais que
  `VOZ_CONVERSA_ESPERA` (60 s), a voz deixa a conversa acompanhando e avisa quando ele responder.
- Teste: `tests/test_voz_plano.sh`; avaliação manual do modelo de verdade, sem executar nada: `tests/avaliar_cerebro.sh`.

## Atalhos da central

    ⏎ entrar   ^n nova   ^r renomear   ^x fechar   ^t soltar painel   ^a nomear todas
    ^v ao lado   ^o embaixo   ^p trocar painel   ^s enviar   ^g trazer
    ^f filtrar por máquina   ^e busca (tudo / só nomes)   ⚙ tmux…   🖥 máquinas…   esc sair

As palavras do cabeçalho são clicáveis.

Sessões com nome genérico (`janela-N`, `claude-N`) ganham nome sozinhas conforme o uso: o título
da conversa, se for o Claude, ou um nome curto que o Haiku tira da tela. O tt acha sozinho onde o
Claude guarda as conversas e qual `claude` usar, inclusive no Termux, com o Claude dentro do Debian
(`proot-distro`). Um nome que você der à mão (`^r`, Ctrl+B N) nunca é trocado.

## Links: escolha do navegador

Clique num link em qualquer painel, Enter (ou `ESC M`) num link no leitor de e-mail, ⏎ no link do
cadastro de conta OAuth e Ctrl+B u abrem o mesmo seletor com as opções disponíveis (mais "📋 Só copiar o link"):

- **Chromium interno**: no Linux/WSL, Google Chrome estável extraído do .deb oficial sem sudo; no macOS, usa Google Chrome (app universal) ou um Chromium compatível com a arquitetura do Mac, pelo LaunchServices e em perfil próprio do tt (`~/.local/share/tt-navegadores/perfil-chrome-macos`). A URL segue a máquina da tela que originou o clique. Se o app não existir ou falhar, avisa e copia o link — nunca troca silenciosamente para Safari/navegador padrão;
- **Carbonyl embutido**: Chromium que desenha no terminal, num popup do tmux (Ctrl+Q ou Ctrl+C fecha). É um build
  de 2023 sem atualizações: use para ler, não para logins sensíveis;
- **Navegador padrão do sistema**: `xdg-open` (ou `open` via LaunchServices no macOS); no WSL abre o navegador do Windows.

No Linux/WSL e no macOS, o Chrome interno e o navegador do sistema abrem na máquina da tela em que você clicou,
não na da sessão: vendo pelo book-hl uma sessão (ou o e-mail) do PC, o link abre no book-hl. O tt de lá
descobre isso pela ponte (`TT_PONTE`, ou `TT_ORIGEM` no cliente do popup do e-mail) e manda
`tt --abrir-aqui QUAL URL` por ssh para a máquina da tela; se ela não confirmar, avisa sem abrir em outra máquina.
No macOS, o Chromium usa `open -n` e perfil exclusivo: o link chega mesmo com o Chrome já aberto.
O Carbonyl e o "só copiar" seguem no próprio terminal.

No Linux/WSL, os dois primeiros são baixados sob demanda para `~/.local/share/tt-navegadores`, sem sudo, e só são
instalados se o sha256 do pacote bater (o do Chrome, com o índice do repositório do Google; o do Carbonyl, com o fixado no `tt`). Esses builds são x86_64; no Termux ficam ocultos. No macOS, o seletor oferece o Chromium interno quando encontra Google Chrome.app ou Chromium.app em `/Applications` ou `~/Applications`; usa o app nativo compatível já instalado, sem baixar binário Linux.
Em Linux/WSL, máquina nova (`instalar.sh`) e máquina atualizada (`tt --sincronizar`, `tt --atualizar`) já deixam os dois prontos em segundo plano: baixam o Carbonyl e, havendo ambiente gráfico, o Chrome (o que já está instalado é pulado; o log fica em `~/.cache/tt/navegadores.log`). Se faltar `curl`/`unzip` (ou as bibliotecas do sistema que os navegadores pedem), eles entram nas [pendências de instalação](#pendências-de-instalação-): o vigia avisa (📦) e o modal instala com o `sudo` pedindo a senha ali, sem o tt vê-la; quem disse "não" a um deles não tem o download em segundo plano. A escolha mais recente aparece marcada. Para pular o seletor, ponha `navegador=chromium|carbonyl|sistema`
no `~/.config/tt/config` (o padrão é `perguntar`). O navegador sobe pelo servidor do tmux, fora do
isolamento de rede do leitor de e-mail.

Como o link é achado na tela: o tmux entrega ao `links-tt.py` a linha e a coluna do clique (e o
hyperlink OSC 8 sob o mouse, se o programa mandou um). Ele junta a linha clicada com as vizinhas
quando o que chega na borda direita continua, sem espaço, no começo da linha de baixo — seja a
quebra do próprio terminal, seja a de um programa que recua a continuação (Claude Code) ou a desenha
dentro de uma caixa. Um endereço curto que só termina na borda não gruda no texto da linha de baixo.
O clique (simples ou com Ctrl) espera o tempo de um duplo clique antes de abrir (Ctrl + duplo clique copia, e o
arrasto, que só com Ctrl copia, cancela a abertura). No Windows Terminal, o Ctrl+clique numa linha que ele mesmo reconhece como URL é
tratado por ele, que só enxerga aquela linha: prefira o clique simples. Hyperlinks OSC 8 chegam
inteiros ao terminal de fora (recurso `hyperlinks` do tmux), então nesses o Ctrl+clique do próprio
terminal também pega a URL toda, inclusive dentro de popups.

No cadastro de conta com OAuth, a espera pela autorização é um menu (↑/↓, roda ou clique escolhem,
⏎ ou a letra confirma, Esc cancela) que continua esperando o navegador enquanto você usa: pelo
navegador (Google), 🌐 abrir o endereço de autorização (seletor), 📋 copiar o endereço inteiro e
📥 colar o endereço de volta quando o navegador está em outro aparelho (ou só colar com Ctrl+Shift+V
no menu); pelo código no aparelho (Microsoft), abrir o endereço e copiar o código. O endereço também
vem como hyperlink. As perguntas s/N e o "Enter volta" do cadastro aceitam as setas sem escrever
`^[[A` na tela.

## Atualizar

    tt --atualizar           instala a versão mais nova publicada no GitHub nesta máquina
    tt --atualizar --todas   … e nas máquinas cadastradas

O vigia consulta a fonte publicada a cada 30 min e instala automaticamente uma versão superior
nesta máquina; sem rede, mantém o tt em funcionamento e tenta de novo no ciclo seguinte. (Quem
publica já instala nas máquinas ligadas com `tt --sincronizar`; a consulta só cobre a que estava
desligada na hora.) `TT_T_ATUALIZACAO=0` força a consulta em cada volta do vigia (útil para teste);
`TT_T_ATUALIZACAO=300` volta aos 5 min. O menu de máquinas
continua oferecendo "⟳ Atualizar do GitHub". Para seguir um fork, ponha `fonte=<url do repositório>` no
`~/.config/tt/config`.

## Montar um celular do zero

Num Termux recém-instalado (F-Droid ou GitHub; Termux:Boot e Termux:API da mesma origem), um
comando deixa o celular no padrão do tt: pacotes, barra de teclas com os botões, sshd na porta 8022
só por chave, início automático no boot, Debian (`proot-distro`) com o Claude Code e o tt instalado:

    curl -fsSL https://raw.githubusercontent.com/helio-nogueira-cardoso/tt-terminais/main/termux/celular.sh | bash

Ele clona o repositório em `~/tt-terminais` e roda `termux/celular.sh` de lá. Depois:

    termux/celular.sh verificar           o que está pronto e o que falta (não muda nada)
    termux/celular.sh conectar eu@meu-pc  chaves dos dois lados, porta 8022 no ~/.ssh/config do PC e cadastro no tt
    termux/celular.sh android             ajustes do Android (processos fantasmas, bateria) via adb ou Shizuku
    termux/celular.sh adb                 adb do próprio aparelho, Shizuku e Tasker (voltam sozinhos depois do reboot)
    termux/celular.sh voz                 opcional: conversar com o tt pela voz, no celular e no carro (guia na skill celular-android, seção 15)
    termux/celular.sh --nome cel --chaves-github USUARIO --sem-claude   opções da instalação

Tudo é idempotente: depois de um `git pull`, rodar de novo aplica só o que mudou (a versão do perfil
fica em `~/.local/state/tt/celular`). Arquivos que seriam trocados ganham cópia `*.antes-celular`, e
`claude_flags`/`claude_env` só entram no config se ainda não existirem. Uma barra de teclas própria
(com botões pessoais, por exemplo) vai em `~/.config/tt/termux.properties` e tem prioridade sobre a
geral. `CELULAR_SIMULAR=1` mostra
os comandos sem executar.

**Agentes de IA no celular.** O tt instala nos agentes (no PC e no Debian do celular) a skill
`celular-android`: as camadas (Android, Termux, Debian no proot), como chegar ao aparelho, onde rodar
cada comando, o shell do sistema sem root (adb do próprio aparelho em `127.0.0.1` e Shizuku), por que o
Tasker religa a depuração sem fio depois do reboot, por que o Wi-Fi só é preciso uma vez por boot e
como operar a tela (screencap, uiautomator, input, am start) e o controle rápido (servidor de shell e acessibilidade
com `uid shell` dentro do aparelho, consultado em ~40 ms por uma porta local, com tela virtual, lotes, ponte e
log do Tasker, sem depender de Wi-Fi depois do primeiro boot). Ela traz também a receita de usar o navegador do celular
para **logar as outras máquinas** (acima, em "Logar sem abrir link nem colar código"). O passo a passo para gente está
em `termux/ANDROID-ADB.md`.

## Celular / tela pequena

Em telas com menos de 80 colunas ou 30 linhas (celular), a central abre em tela cheia, com
cabeçalho compacto (toque em "?" para todos os atalhos) e prévia escondida (toque em "prévia" ou
^/). O seletor rápido (toque no nome da sessão na barra) é o jeito mais prático de trocar de sessão
pelo toque.

Os popups de tamanho fixo (fixadas `+N ▾`, 🔔 notificações, renomear, nova tarefa, abrir link,
pendências) encolhem até caber na tela: o tmux recusa popup maior que a tela, e num celular com 63
colunas o toque não fazia nada.

## Pré-carregamento inteligente de sessões

O tt prepara passivamente conexões para prováveis próximos destinos remotos. As fixadas ganham
prioridade, especialmente as mais à esquerda, mas isso é só parte da decisão: recência, frequência,
alternância com a sessão atual e foco por pelo menos 300 ms no seletor também contam. Sessões locais
já trocam diretamente, sem transporte extra. O histórico registra apenas transições reais de tela,
não conteúdo de conversas nem preparações, com até 500 eventos dos últimos sete dias, só nesta máquina.

A preparação autentica o SSH e confere a identidade, mas **não anexa um cliente ao tmux remoto**:
não cria presença humana, não redimensiona a sessão e não recebe saída dos programas. No clique,
um bilhete de uso único libera a anexação. Só depois da confirmação do destino e da primeira tela
o cliente de origem troca. Renomear preserva a identidade; apagar e recriar com o mesmo nome não.
Um novo clique cancela o anterior. Outra tela anexada à mesma sessão continua independente.

Ao **voltar a uma ponte já ativada**, a troca reaproveita sua conexão e sua tela prontas.
Confere localmente o cliente (tty, PID e nascimento), a identidade do destino, o bilhete,
o processo do transporte e a marca de conexão viva. Não abre SSH para resolver novamente o
nome nem para perguntar se a mesma sessão existe. A saída do transporte limpa a marca viva;
um terminal parado no prompt de reconexão não conta como ponte pronta. Um reinício do
coordenador recupera essas marcas, preservando o dono de cada tela. A fixada local também
troca pelo caminho curto quando tem identidade estável.

O clique numa fixada usa um pedido Unix local antes de carregar o núcleo Bash.
O coordenador já aberto também ativa uma ponte preparada ou prepara o destino sob demanda.
Se não houver coordenador ou o pedido não puder ser atendido ali, continua pelo comando original; uma resposta perdida
não repete uma ação já enviada. Pressionar faz a troca e soltar não inicia outra. O vigia é
conferido em segundo plano, sem segurar a troca. `TT_COMPLETO=1` ou o arquivo de diagnóstico
`~/.config/tt/trace` conservam o caminho completo. Preparações novas continuam exigindo
identidade remota e primeiro quadro: **a primeira abertura ainda depende da rede**. As
verificações de ativação usam 10 ms no início e 50 ms enquanto a rede demora, somente com
pedido pendente; a espera ociosa continua em 500 ms. Após atualizar, uma ponte de versão
antiga sem a marca viva precisa ser aberta pelo fluxo completo uma vez para ganhar o reuso.

Padrão: até **3 candidatos por tela e 6 no total**, com duas preparações simultâneas em segundo plano,
margem contra trocas excessivas, validade de 150 s e espera progressiva após falhas. Cliques reais
têm prioridade sobre esse trabalho especulativo. Termux, modo econômico ou bateria ≤20% sem carregar:
até 2 candidatos no total, 1 por tela; abaixo de 10%, sem especulação. Tela sem atividade há 10 min
deixa de preparar. Suspender/retomar cancela pedidos antigos e dá 5 s para a rede recuperar.

Em **Administrar → ⚡ Pré-carregamento**, `a` liga o automático, `e` o econômico, `d` desliga e `q`/Esc volta.
Também: `tt --precarregar status` mostra o estado, os motivos e a última duração; `json` fornece métricas
e amostras de preparação/troca para diagnóstico (`reutilizada` distingue uma volta, `local` a sessão desta máquina);
`auto`, `economico` e `off` escolhem o modo. `clique_ms` começa no pedido Python, até o comando de troca:
não inclui a partida do chamador, o desenho final do terminal ou um SSH da máquina remota até a origem.
`~/.config/tt/config` aceita `precarregar_total=6` e `precarregar_por_tela=3` (tetos 12 e 6).
Desligar descarta só transportes especulativos: não derruba uma sessão em uso.

O coordenador Python é único por socket tmux/pacote, com socket Unix privado e pontes por identidade
do cliente (tty, PID e nascimento). A ponte usa conexão SSH própria; só a confirmação usa o multiplexador do tt. O protocolo remoto é pequeno,
só stdlib, executado em memória via SSH: basta Python 3 e tmux, sem instalar arquivos ou exigir uma
versão nova do tt no destino. Não usa servidor TCP nem serviço novo do sistema. Estado local em
`~/.local/state/tt/precarregamento/`; runtime privado em `/tmp/tt-pre-UID-HASH/`
(no Termux, na pasta temporária privada do Android). Sem servidor tmux, o status informa que
aguarda uma sessão; não abre um servidor nem cria sessões só para consultar.
`TT_PRECARREGAR=0` impede preparação automática (usado pelos testes isolados).

## Partida rápida

O `tt` é um script só, de ~850 KB, e cada clique na barra, tecla num painel ou recarga do fzf chama um `tt`
novo: ler o arquivo inteiro custava de 60 a 90 ms antes de qualquer trabalho. Como o bash lê um script
comando a comando, um desvio no topo do arquivo evita o resto: a instalação gera `~/.local/share/tt/rapido/`
com um núcleo (o código de topo, na mesma ordem, e cada função trocada por uma linha que carrega o corpo na
primeira chamada) e um arquivo por função. Cada invocação lê só o núcleo (~160 KB) e as poucas funções que
usa: em média ~100 ms a menos por invocação, com a mesma saída.

O núcleo só passa a valer depois de conferido: cada corpo, lido sozinho, dá a mesma definição que o tt
inteiro, e o núcleo carregado dá as mesmas funções e variáveis de topo. Um corpo que falte faz carregar
todos; um `tt` editado depois da instalação, ou `TT_COMPLETO=1`, roda o arquivo inteiro; processos longos (o
vigia) carregam tudo de uma vez, para uma instalação no meio não misturar versões. `tt --rapido` mostra o
estado, `tt --rapido gerar` refaz e `tt --rapido remover` desliga. Teste: `tests/test_partida_rapida.sh`.

## Desempenho do clique

Entre o clique e a ação há um `tt` que parte, idas ao servidor do tmux (que atende um pedido por vez, atrás
dos redesenhos dos painéis) e, muitas vezes, a barra recalculada. O que o tt faz para a resposta vir rápida:

- **A barra numa ida só.** Todo `set-option` redesenha a tela inteira de todos os clientes; a barra gravava cada
  segmento que mudou num pedido separado. Agora tudo vai junto, num redesenho só, e os segmentos que dependem de
  outros (tarefas e versão medem o canto da faixa das fixadas) são calculados uma vez.
- **Comando ausente não custa mais nada no WSL.** O PATH do WSL inclui as pastas do Windows, e perguntar por um
  comando que não existe (o `termux-open-url`, que decide se a faixa de avisos aparece) custava ~35 ms, 8 vezes
  a cada atualização da barra. As pastas do Linux continuam conferidas a cada pergunta; a resposta das pastas do
  Windows fica guardada por 10 min (`TT_CMD_WIN_VALE`, em segundos).
- **Menos processos por clique.** Hora, configuração, versão, chaves das fixadas, contas de e-mail e avisos
  passaram a ser lidos pelo próprio bash, sem `date`, `cat`, `awk`, `sha256sum` ou `basename` a cada vez; a
  partida de cada `tt` caiu de ~20 para ~13 ms.
- **O painel de tarefas não espera a barra.** Marcar, editar ou criar uma tarefa no painel (e na agenda)
  recarrega a lista na hora; a barra é atualizada em segundo plano, juntando pedidos seguidos e terminando
  sempre no estado final. Pela linha de comando (`tt --tarefa-ok` etc.) continua tudo síncrono.
- **Clique dentro de um painel.** Antes de procurar um link com python (~30 ms), o tmux confere em ~2 ms se há
  `http` ou `://` na tela (ou um hiperlink sob o mouse); sem nenhum, o clique vai direto ao programa.
- **Janelas flutuantes sem rajada de processos.** Abrir ou fechar uma janela disparava 3 ou 4 `tt --bordas`
  ao mesmo tempo; agora só o primeiro trabalha.

Medido aqui (WSL, com um painel redesenhando a tela sem parar): 📌 fixar de ~710 para ~260 ms; marcar uma
tarefa no painel de ~790 para ~195 ms; atualizar a barra de ~580 para ~150 ms; abrir a central de ~480 para
~200 ms; clique num painel sem link de ~50 para ~14 ms.

Para investigar uma lentidão: `touch ~/.config/tt/trace` grava cada linha executada nos cliques, com hora, em
`~/.cache/tt-trace.log` (`rm ~/.config/tt/trace` desliga). O log interno do servidor tmux (ligado com
`kill -USR2` no servidor) dobra o custo de cada comando do tmux: deixe-o ligado só enquanto depura. Teste das
garantias acima: `tests/test_desempenho.sh`.

## Desenvolvimento

### Testes e AI-DLC

A versão exibida é `v1.MINOR.PATCH` (o PATCH é o contador interno de publicação, que continua
sendo o que as máquinas comparam para decidir quem é mais novo; o MINOR sobe à mão em marcos).

Rode `make test` (ou `tests/run.sh`) antes de publicar mudanças. A suíte usa configuração e
runtime temporários para testar fluxos de CLI sem tocar nas máquinas cadastradas, além de validar
os bindings do tmux num servidor isolado. Para auditar uma instalação, use
`TT_DIR=~/.local/share/tt tests/run.sh`.

Os testes rodam em paralelo: `TT_TESTES_J` testes ao mesmo tempo (padrão: o número de CPUs, até 8;
`TT_TESTES_J=1` roda em fila), cada um com o seu tmux sentinela, a fila começando pelos mais demorados da
última rodada (`~/.cache/tt-testes/duracoes`). Um teste que mede tempo leva a marca `# tt-teste: sozinho` e
roda no fim, sem disputar a máquina. `TT_TESTES='letreiro|listar'` roda só os testes cujo nome casa (as
checagens estáticas rodam sempre); `TT_TESTE_TEMPO_MAX` (1800 s) encerra um teste preso. Nenhum teste alcança
a tela gráfica de quem roda a suíte (`sem_tela_real` no `tests/lib.sh`): nada de área de transferência real.

O projeto segue a política [`AI-DLC.md`](AI-DLC.md); o protocolo de trabalho para agentes está em
[`AGENTS.md`](AGENTS.md), e a cobertura esperada de mouse, toque, teclado, menus e CLI está na
[`tests/INTERACTIONS.md`](tests/INTERACTIONS.md).

O clone é a origem: edite, faça commit e rode `tt --sincronizar`. A versão tem dois números: a **ordem** de atualização
é o número de commits (`+dev` quando há mudanças não gravadas) e o **rótulo** é hierárquico `MAIOR.MENOR.PATCH` (ex.: `v1.7.3`). O
arquivo `MARCO` na raiz (`1.7`) diz a série e o PATCH conta os commits desde que ele mudou; ao subir um número da esquerda os da
direita **zeram** (1.6.12 → 1.7.0). Funcionalidade nova: edite o `MARCO` no commit que a entrega; correção: só soma PATCH.
Testes: `tests/test_versao.sh`. Máquinas com versão mais velha aparecem com ⚠ no menu de máquinas, que oferece atualizar; máquinas com versão mais velha aparecem com ⚠ no menu
de máquinas, que oferece atualizar.

A instalação se protege de versões erradas, venha de `--sincronizar`, `--atualizar` ou `--cadastrar`:

- não rebaixa: uma máquina com versão mais nova é mantida, e uma com o mesmo número mas outro commit
  (clone divergente) também — `TT_FORCAR=1 tt --sincronizar` volta de propósito a uma versão anterior;
- o pacote precisa ter todos os arquivos (`tt`, `tmux.conf`, `tema-terminal.sh`, `tema-agentes.sh`,
  `README.md`) e passar no `bash -n`; senão nada é trocado;
- `--sincronizar` recusa rodar de um clone atrasado em relação ao GitHub (faça `git pull --rebase`).

`tema-terminal.sh` é carregado com `source` pelo `~/.bashrc`: nele, nunca use `exit` fora de uma
função — encerraria o shell que o carregou (a sessão do tmux fecharia na hora).

## Licença

MIT — veja [LICENSE](LICENSE).
