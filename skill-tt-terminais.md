---
name: tt-terminais
description: Referência completa do tt-terminais (central de terminais em Bash+tmux) para IAs operarem e evoluírem o projeto. Use ao trabalhar no repositório tt-terminais, ao diagnosticar a central/barra/sessões/fixadas/tarefas/e-mail/sync entre máquinas, ou ao usar os verbos `tt --...` por linha de comando. Cobre todos os verbos CLI, os ranges da barra e o roteamento de clique, os arquivos de perfil/estado/cache/pacote, o vigia e seus temporizadores, a sincronização por ssh e git, identidade de máquina/sessão/fixada, e-mail (aerc), celular/Termux, testes e as convenções de desenvolvimento.
---

# tt-terminais — central de terminais multi-máquina (Bash + tmux)

O `tt` é um único script Bash (`set -u`, arrays associativos) que oferece um menu único para todas
as sessões tmux de todas as máquinas do usuário (ligadas por ssh/Tailscale), com central, barra
clicável, fixadas, tarefas, transferência de arquivos, e-mail, nomeação automática de sessões e
sincronização de estado entre máquinas. A versão é o número de commits da `main`
(`git rev-list --count HEAD`, com `+dev` quando há mudança não gravada).

Esta skill descreve o comportamento REAL extraído do código. Trate tudo como mapa de navegação:
confirme no código antes de alterar contrato.

## Arquitetura em uma olhada

- `tt` — script principal: dispatch de verbos, central/seletor, barra e cliques, vigia, sync,
  identidade, e-mail, botões, empacotamento. O dispatch é um grande `case "${1:-}" in` no fim.
- `tmux.conf` — binds de teclado/mouse (prefixo `Ctrl+B`), hooks de tmux e roteamento de clique
  para o `tt`. No fim, `source-file -q ~/.config/tt/tmux.conf` carrega o perfil local.
- `tema-tmux.conf` — define a barra (`status-left`, `status-right`, `status-format[1]`) e os
  `range=user|...`, mais o padrão visual Catppuccin Mocha.
- `tema-terminal.sh`, `tema-agentes.sh`, `memoria-agentes.sh` — paleta do terminal, tema dos
  agentes de IA instalados, memória compartilhada dos agentes.
- `email-tt.py` — utilitário de e-mail (só stdlib: descoberta de provedor, OAuth2, teste, pastas,
  filtro HTML). Roda inclusive no Termux.
- `nomeador-local.py` — modelo local (llama.cpp) opcional para nomear sessões.
- `ia-conta`, `ia-rot`, `ia-login`, `contas-uso.py`, `skill-rodizio-de-contas.md` — rotação de
  contas de IA (ver a skill `rodizio-de-contas`).
- `atalhos-padrao`, `atalhos-padrao-mobile` — atalhos de barra padrão (desktop e Termux).
- `termux/celular.sh` — provisiona um celular do zero (Termux + Debian proot).
- `tests/` — suíte de regressão; `Makefile` → `make test`.

### Três lugares, três papéis (nunca os misture)

| Lugar | Variável | Papel | Quem escreve |
|---|---|---|---|
| `~/.local/share/tt/` | `$DIR_TT` (`TT_DIR`) | pacote geral, trocado inteiro a cada instalação | só o instalador |
| `~/.config/tt/` | `$CONF_DIR` (`XDG_CONFIG_HOME`) | perfil: escolhas do usuário | você e os menus do tt |
| `~/.local/state/tt/` | `$ESTADO_DIR` (`XDG_STATE_HOME`) | estado gerado pelo tt | o tt |
| `~/.cache/`, `/run/user/UID` | `$RT` (`TT_RT`) | cache e runtime descartáveis | o tt |

Código de aplicação nunca mora no perfil; escolhas do usuário nunca são sobrescritas pela
instalação; o pacote pode ser reinstalado sem perder nada do usuário.

## Verbos de linha de comando

Forma: `tt --verbo [args]`. Agrupados por área. Verbos marcados "(interno)" são usados pela própria
barra/fzf/vigia; os de usuário são os mais úteis no dia a dia.

### Instalação, pacote, atualização
- `tt --instalar [nome]` — primeira instalação a partir do clone; grava `repo=` no config,
  configura o `~/.bashrc` (salvo `TT_SEM_BASHRC=1`).
- `tt --instalar-aqui` — instala/atualiza o pacote nesta máquina.
- `tt --desinstalar-aqui` — remove a instalação local.
- `tt --configurar-bashrc` / `tt --remover-bashrc` — liga/desliga abrir no tmux via `~/.bashrc`.
- `tt --sincronizar [nome...]` — (na máquina de dev, a do `repo=`) instala esta versão aqui e nas
  cadastradas. Recusa rodar de clone atrasado em relação ao GitHub; nunca rebaixa.
- `tt --atualizar [--todas]` — instala a versão publicada mais nova nesta máquina (e nas cadastradas).
- `tt --verificar-atualizacao` / `tt --garantir-atualizacao` — checa / força estar na última.
- `tt --versao` — versão instalada ("N hash data").
- `tt --pacote` (interno) — emite o tar do pacote no stdout.
- `tt --aidlc [raiz]` — bootstrap AI-DLC no projeto (idempotente).

### Máquinas, cadastro, diagnóstico
- `tt --cadastrar [host [usuario [nome]]]` — testa ssh, instala o tt lá, cadastra as duas máquinas
  uma na outra. Sem host, lista as do Tailscale.
- `tt --descadastrar [nome]` — tira do menu (aqui e lá); opcional desinstalar lá.
- `tt --ocultar-maquina nome` / `tt --mostrar-maquina nome` — esconde/restaura no menu sem perder
  `host usuario rotulo` (4ª coluna `oculta`).
- `tt --maquinas` — lista "usuario@host rotulo" das acessíveis.
- `tt --candidatas` — Linux online na tailnet ainda não cadastrados.
- `tt --diagnosticar [nome]` — por que não conecta, camada por camada (desligada, sem rota, porta,
  precisa aprovar, policy nega, sem chave, timeout).
- `tt --reparar [nome]` — reautoriza a chave desta máquina usando outra cadastrada como ponte.
- `tt --saude` — painel: verde conecta, vermelho online sem acesso.

### Sessões, central, seletor, painéis
- `tt` (sem args) ou `Ctrl+B s` — abre a central (todas as sessões de todas as máquinas).
- `tt --nova [nome]` — cria sessão solta; `tt --nova-e-ir nome` cria e entra.
- `tt --fixar [maquina:]sessao` — fixa (ver Fixadas).
- `tt --renomear [sessao]` — pergunta um nome; `tt --sugerir sessao` sugere; `tt --nomear-todas`
  nomeia as genéricas (`janela-N`, `claude-N`).
- `tt --listar-tudo [--tsv|--para-ia]` — linhas do menu de todas as máquinas; `--para-ia` emite um
  TSV estável (contrato do "mestre de obras": máquina, sessão, anexada, ocioso, agente, rascunho,
  última linha etc.) para outra IA recomendar o que fechar.
- Internos do fzf/central: `--lista-tudo`, `--lista-rapida-central`, `--atualizar-uma-vez`,
  `--seletor`, `--seletor-em`, `--lista-seletor`, `--lista-rapida`, `--pos-atual`,
  `--cabecalho`, `--cabecalho-seletor`, `--clique`, `--clique-direito`, `--clique-linha`,
  `--clique-seletor`, `--clique-cabecalho`, `--previa`, `--previa-em`, `--fechar`, `--fechar-em`,
  `--fechar-vazias`, `--bordas`, `--ajustar`, `--guarda-tamanho`, `--ciclo`, `--descongelar`,
  `--focar`, `--soltar`, `--ponte`, `--ir-ponte`, `--adotar`, `--janela`, `--listar`,
  `--listar-leve`, `--atualizar-info`, `--pastas-sessoes`, `--pasta-de`,
  `--menu-painel`, `--menu-tmux`, `--menu-sessao`, `--menu-maquinas`, `--menu-admin`,
  `--menu-arquivos`, `--menu-atalhos`, `--menu-popup-ui`, `--avisar`.

### Fixadas (2ª linha da barra)
- `tt --fixar [maquina:]sessao` — fixa/desafixa a sessão.
- `tt --fixadas` — lista as fixadas; `tt --barra-fixadas` (interno) formata a faixa.
- Internos: `--aplicar-fixadas`/`--barras` (liga a 2ª linha), `--ir-fixada`, `--mover-fixada`,
  `--fixada-scroll [next|prev]`, `--alternar-fixada`, `--alternar-fixada-rotulo`,
  `--resolver-fixada`. Sync: `--propagar-fixadas`, `--receber-fixadas [V]`, `--puxar-fixadas`,
  `--reconciliar-fixadas`, `--marcar-fixadas`.

### Tarefas (gerenciador simples)
- `tt --tarefas [cliente]` — abre o painel: slide-over ancorado à direita (no tmux) ou lista texto
  (fora dele). Também `Ctrl+B t`.
- `tt --tarefa-add "texto"` — adiciona; `tt --tarefa-ok ID` conclui; `tt --tarefa-abrir ID` reabre;
  `tt --tarefa-rm ID` remove (lápide); `tt --tarefa-limpar` remove as feitas.
- Internos da UI: `--tarefas-ui`, `--tarefas-lista`, `--tarefa-toggle`, `--tarefa-nova-prompt`,
  `--tarefa-remover-prompt`, `--tarefa-add-ui`, `--tarefas-barra`. Sync: `--receber-tarefas`,
  `--tarefas-espelhar`, `--tarefas-puxar`.
- Dentro do painel: `enter` alterna feita/aberta, `ctrl-n` cria, `ctrl-x` remove com confirmação,
  `ctrl-l` limpa as feitas, `esc`/`q` fecha.

### Atalhos de barra
- `tt --editar-atalhos` — edita os atalhos locais. `--atalhos-barra`/`--atalhos-lista` (internos)
  formatam/listam a partir de `atalhos-padrao` + `~/.config/tt/atalhos` (override por ID; emoji `-`
  desativa).

### Arquivos entre máquinas
- `tt --enviar [arquivo... [destino[:pasta]]]` — navega e envia; `tt --trazer [maquina:caminho [pasta]]`
  traz. `tt --pasta-padrao [maquina:pasta]` define a pasta de recebidos.
- Internos: `--receber`, `--transferir-fundo`, `--transferencias`, `--transferencias-barra`,
  `--empacotar`, `--tamanho`, `--listar-pasta[-em]`, `--previa-item[-em]`, `--resolver-pasta`,
  `--arq-acao`, `--cabecalho-arquivos`, `--abrir-pasta`, `--caminho-visivel`, `--pasta-recebidos`,
  `--destinos`, `--definir-recebidos`, `--anexos-enviar` (anexos do aerc → recebidos de uma máquina).

### E-mail (aerc)
- `tt --email [cliente]` — abre o cliente de e-mail (default `aerc`) numa subjanela popup.
- `tt --email-contas` / `tt --email-conta` — gerenciador de contas; `tt --email-adicionar ...`
  cadastra por CLI; `tt --email-listar`.
- `tt --email-testar NOME`, `tt --email-autorizar NOME` (OAuth2), `tt --email-pastas NOME`,
  `tt --email-regerar NOME`, `tt --email-assumir NOME`, `tt --email-remover NOME`.
- `tt --email-sync [NOME]` — espelha por mbsync as contas com `sync_local=1`.
- `tt --email-atalhos` — tela de atalhos do aerc em português.

### Nomeador de abas
- `tt --nomeador [auto|local|claude|nenhum]` — define a fonte do nome automático.
- `tt --nomeador-local [estado|instalar|remover]` — modelo local llama.cpp.
- `tt --nomear-texto` (interno, lê stdin), `--nomeador-ui`, `--sugerir`, `--renomear`,
  `--nomear-todas[-local]`.

### Botões inteligentes (teclado F1–F10 / barra de teclas do Termux)
`tt --botao ACAO cliente painel pasta`. Mapeamento (tmux.conf): F1→`cl`, F2→`clc`, F3→`clr`,
F4→`dbn`, F5→`tela`, F6→`sair`, F7→`ant`, F8→`zm`, F9→`jn`, F10→`dv`.
- `cl` Claude conversa nova; `clc` continua a última na pasta; `clr` seletor de conversas; `dbn`
  Debian (proot, Termux); `tela` liga/desliga o túnel de tela remota (`tela_destino=`); `sair` fecha
  painel/janela/sessão se vazia, senão desanexa; `ant` sessão anterior; `zm` zoom; `jn` janela nova;
  `dv` divide pelo lado maior.

### Vigia, sync, tema
- `tt --vigia` (interno) — loop em segundo plano (ver abaixo).
- `tt --reforcar-padrao`, `tt --redesenhar`, `tt --tema-agentes`, `tt --tema-clientes`,
  `tt --memoria-agentes`, `tt --copiar-tela`.
- `tt --fechar-paradas`, `tt --definir-paradas N` (0 desliga), `tt --config-paradas`,
  `tt --encerrar-duplicados`.

### Área de transferência e contas de IA
- `tt --copiar`/`--copiar-buffer`/`--copiado` (clipboard Wayland/X/clip.exe + OSC 52);
  `--propagar-copia`/`--receber-copia`/`--copias` (histórico entre máquinas).
- `tt --conta-propagar [nome] [alvos...]` / `tt --conta-receber [nome]` — move os arquivos próprios
  da conta Claude de forma transacional. `--receber-contas-ia`/`--propagar-contas-ia`/
  `--puxar-contas-ia` sincronizam o cadastro `contas-ia`. `--registrar`/`--desregistrar`/
  `--session-id` cuidam de registro e identidade de sessão.

## Barra: ranges e roteamento de clique

Contrato (AGENTS.md): cada `#[range=user|X]` desenhado precisa de uma rota em `clique()` (esquerdo/
toque) ou `clique_direito()` (botão direito). `tests/run.sh` verifica a lista de rotas.

Ranges e destino:

| range | onde | clique esquerdo | botão direito |
|---|---|---|---|
| `maquina` | status-left | `menu_maquinas` | `menu_admin` |
| `sessao` | status-left | `seletor_em` | `menu_sessao` |
| `fixar` | status-left (📌/📍) | `fixar_atual` | — |
| `ajustar` | status-right (⤢, condicional) | `ajustar` | — |
| `tt` | status-right (☰) | central (`display-popup`) | — |
| `painel` | status-right (⋯) | `menu_painel` | — |
| `arquivos` | status-right (⇅) | `menu_arquivos` | — |
| `email` | status-right (📧) | `botao_email` | `menu_email` |
| `tarefas` | 2ª linha, à direita (📋 N) | `abrir_tarefas` | `menu_tarefas` |
| `fx<chave>` | faixa de fixadas | `ir_fixada` | `menu_fixada` |
| `fxx<chave>` | faixa de fixadas (✕) | `desafixar_item` | `desafixar_item` |
| `fixprev`/`fixnext` | faixa de fixadas (‹ ›) | `fixada_scroll` | — |
| `at<N>` | atalhos | `atalho_executar` | `atalho_info` (tooltip, sem executar) |
| `transferencias` | status-right (⇅ N) | popup `--transferencias` | — |
| `copias` | `Ctrl+B y` | popup `--copias` | — |

Ordem na barra principal: `arquivos` < `email` < relógio `%H:%M` (exigido pelos testes). A 2ª linha
(`status-format[1]`) tem `@barra_fixadas` à esquerda e `@barra_tarefas` + `@barra_versao` à direita.

Binds de teclado (prefixo `Ctrl+B`): `s` central, `t` tarefas, `|` split horizontal, `-` split
vertical, `c` janela nova, `r` recarrega config, `m` menu do painel, `y` histórico de cópias, `N`
renomear sessão, `F1..F10` botões. Mouse: arrastar/duplo/triplo clique copiam; botão do meio cola;
`MouseDown/Up1Status*` → `--clique`; `MouseUp3Status*` → `--clique-direito`;
`MouseUp3Pane`/`MouseDown3Border` → `--menu-painel`.

Contrato de toque: fixadas e o ✕ agem no **MouseDown** (a barra pode redesenhar entre pressionar e
soltar); menus agem no **MouseUp**. Um atalho de teclado deve ter a mesma ação observável do botão.

## Arquivos de perfil, estado e cache

### Perfil `~/.config/tt/`
- `config` — `chave=valor` (lido por `conf()`, pega a última ocorrência). Chaves conhecidas:
  - `nome` — nome desta máquina no menu.
  - `repo` — clone de origem (usado por `--sincronizar`).
  - `fonte` — URL do repositório para `--atualizar` (seguir um fork).
  - `recebidos` — pasta onde chegam arquivos (default `~/Recebidos`; no WSL, `Downloads\Recebidos`).
  - `email` — binário do cliente de e-mail (default `aerc`).
  - `tela_destino`, `tela_porta`, `tela_url` — túnel do botão `tela` (F5).
  - `tarefas_sync` — `p2p` (default) | `git` | `ambos` | `off`.
  - `tarefas_repo` — URL de um repositório git pessoal para sincronizar tarefas.
- `maquinas` — `host  usuario  rotulo [oculta]` por linha (`host -` = formato antigo sem usuário).
- `atalhos` — atalhos locais da barra (override de `atalhos-padrao` por ID; emoji `-` desativa).
- `fixadas` (+ `.v` versão em ns, `.trava` lock) — `maquina\tsessao\tchave`.
- `tarefas` (+ `.v`, `.trava`) — `id\testado\tcriada\tmudada\ttexto`, estado = `aberta|feita|removida`.
- `contas-ia` — `provedor\temail\tapelido\thora` (cadastro comum das contas de IA).
- `tmux.conf` — ajustes de tmux só desta máquina (carregado depois do pacote).
- `termux.properties` — barra de teclas própria do Termux.
- `email/<slug>.conf` — config por conta (sem segredo). `mbsync/<slug>.mbsyncrc` — sync local.
- `AI-DLC.md` — política AI-DLC própria (se existir, substitui a do pacote).

### Segredos `~/.secrets/` (modo 600)
`aerc-<slug>.txt` (senha de app ou refresh token OAuth2), `aerc-<slug>.client_secret`. Nunca são
impressos, copiados entre máquinas, nem vão para o `accounts.conf`.

### Estado `~/.local/state/tt/`
Memória de agentes (`ai-memory`), estado do celular, avisos, `tarefas-git/` (clone do repo pessoal
de tarefas).

### Cache e runtime
`~/.cache/tt-vigia.log`, `tt-github-versao`, `tt-anexos/`, `tt/maildir/<slug>` (sync local);
`$RT` (`/run/user/UID` ou `TT_RT`): pidfile e estado do vigia, lock de clique, cache de máquinas,
ControlPath do ssh, transferências em andamento.

### Pacote `~/.local/share/tt/`
`ARQUIVOS_FONTE` (lista no `tt`): `tt email-tt.py tmux.conf tema-tmux.conf tema-terminal.sh
tema-agentes.sh memoria-agentes.sh atalhos-padrao atalhos-padrao-mobile README.md AI-DLC.md
ia-conta ia-rot ia-login contas-uso.py skill-rodizio-de-contas.md nomeador-local.py
skill-tt-terminais.md`. `ARQUIVOS_PACOTE` = `ARQUIVOS_FONTE` + `VERSAO`. Mudança que acrescenta um
arquivo ao pacote PRECISA entrar em `ARQUIVOS_FONTE`, senão a autoatualização instala um pacote
incompleto.

## O vigia (`tt --vigia`)

Loop em segundo plano, instância única por pidfile em `$RT`. Log em `~/.cache/tt-vigia.log`. A cada
volta: `atualizar_barras`; atualiza info das máquinas. Em intervalos:
- Fixadas/tarefas a cada 300 s: `--puxar-fixadas`, `--reconciliar-fixadas`, `--tarefas-puxar`.
- Contas de IA a cada 1800 s: `--puxar-contas-ia`.
- E-mail (sync local) a cada `TT_EMAIL_SYNC` s (default 180; 0 desliga): `--email-sync`.
- Padrão visual + memória a cada 300 s: `--reforcar-padrao`, `--memoria-agentes`.
- Atualização a cada `TT_T_ATUALIZACAO` s: `--garantir-atualizacao`.
- Toda volta: fecha sessões paradas, pontes ociosas, Claude duplicados, janelas vazias abandonadas.
- Nomeação automática por sessão (título do Claude; primeiro nome; revisão por pontos).

### Variáveis de ajuste (defaults)
`TT_T_PRIMEIRO`=60, `TT_T_RENOMEAR`=300, `TT_T_GENERICO`=300, `TT_T_PASTA`=120, `TT_T_REVISAO`=1800,
`TT_PAUSA`=60, `TT_T_ATUALIZACAO`=300 (0 = toda volta), `TT_PESO_PEDIDO`=3, `TT_PONTOS_RENOMEAR`=10,
`TT_EMAIL_SYNC`=180, `TT_FIX_VISIVEIS`=8, `TT_TAREFAS_LAPIDE_DIAS`=30. Flags: `TT_FORCAR` (pula
proteção de downgrade), `TT_SEM_BASHRC` (instala sem mexer no `~/.bashrc`), `NOTMUX=1 bash` (abre
terminal sem tmux), `TT_AI_MEMORY_DIR` (dir da memória de agentes), `TT_GIT_NAME`/`TT_GIT_EMAIL`
(commit do repo de tarefas), `TT_MACHINE`/`TT_DIR`/`TT_RT`.

## Sincronização entre máquinas

Protocolo comum: itera `maquinas` e roda `ssh "${SSH_OPC[@]}" dest "$TT_REMOTO --receber-*"`.
`SSH_OPC` = BatchMode, ConnectTimeout 4, StrictHostKeyChecking accept-new, ControlMaster/Persist
(socket em `~/.cache/tt-ssh-%r@%h`, 12 h), keepalive. `TT_REMOTO` força o PATH (homebrew/local) e
chama `~/.local/bin/tt`. `dest_de ROTULO` resolve `.` (local) ou `usuario@host`.

- **Fixadas**: versão em `.v` (ns da última mudança); `receber_fixadas` só aceita versão mais nova
  (uma máquina atrasada nunca desfaz mudança nova); `puxar_fixadas` busca a maior entre todas. Lock
  por `mkdir` atômico.
- **Tarefas**: modos `p2p` (ssh como fixadas), `git` (repo pessoal `tarefas_repo`), `ambos`, `off`.
  O merge é **por tarefa**: por `id`, vence o maior `mudada`; empate favorece `removida` > `feita`
  > `aberta` (remoção vira lápide e nunca ressuscita). P2P e git interoperam sem perder tarefa.
  Modo git: clone depth 1 em `$ESTADO_DIR/tarefas-git`, pull `--ff-only`, merge por tarefa no
  arquivo do repo, commit (`TT_GIT_NAME/EMAIL`), push. Credencial fica no git/ssh do usuário.
- **Contas de IA**: cadastro `contas-ia` sincroniza por par (provedor,email), mudança mais nova
  vence. As credenciais NÃO são copiadas (cada máquina faz o próprio login; copiar derrubaria a
  outra na renovação do token).

## Identidade

- Máquina: `TT_MACHINE` > `nome=` (config) > `hostname -s`; normalizada com `_`→`-` onde a barra/IA
  a exibem.
- Sessão: opção tmux `@tt_session_id`; se vazia, gera `sha256(maquina\0sessao\0pid\0ns)` (32 hex) e
  grava — não muda num rename.
- Fixada: `fixada_chave` = `sha256(maquina\tsessao)` cortado em 12 hex (o argumento `range=user|X`
  do tmux tem limite de 15 bytes). O clique resolve a sessão pelo `@tt_session_id` para sobreviver a
  renomeações durante o sync.

## E-mail (resumo)

Cliente configurável (`email=`, default `aerc`), aberto numa subjanela `display-popup` (não cria
sessão de trabalho; roda numa sessão oculta `_tt-email` fora da central/seletor/vigia). Contas em
`~/.config/tt/email/<slug>.conf` (sem segredo); segredos em `~/.secrets` (600). O `accounts.conf` do
aerc é gerado entre marcadores `# >>> tt e-mail: <slug> >>>` (blocos à mão ficam intactos).
`email-tt.py` descobre provedor (autoconfig/MX, detecta Microsoft 365 e Google), faz OAuth2 (código
no aparelho ou navegador), testa IMAP/SMTP, lista pastas e converte HTML — sempre sem imprimir
senha/refresh token. Sync local opcional (`sync_local=1`) por mbsync em `~/.cache/tt/maildir/<slug>`;
envio continua SMTP online.

## Celular / Termux

`termux/celular.sh` provisiona um aparelho do zero: pacotes do Termux, sshd por chave na porta 8022,
boot automático, Debian via proot-distro com o Claude, e o tt. Subcomandos: `verificar`,
`conectar eu@pc`, `android`, opções `--nome`, `--chaves-github`, `--sem-claude`. É idempotente
(`*.antes-celular` como backup). O proot do Android não tem `/dev/fd` (evite `<(...)`) nem `iconv`
(por isso a remoção de acentos é feita em Python). Perfil de atalhos: `atalhos-padrao-mobile`.

## Testes e desenvolvimento

- `make test` → `tests/run.sh`. `make test-installed` roda contra `~/.local/share/tt`.
- Cada `tests/test_*.sh` roda isolado em `HOME`/`XDG_CONFIG_HOME`/`TT_RT` temporários e um socket
  tmux próprio — **nunca** toque o tmux/arquivos reais do usuário num teste.
- `run.sh` faz: testes de comportamento, asserts estáticos (`bash -n`, Python da ponte de mouse,
  vigia exige versão publicada, etc.), tmux isolado, e o **contrato de rotas** (cada `range=user|X`
  tem `X)` em `clique()`), botões 📧/📋 (range + rota + verbo + posição), guardrails de segredo do
  e-mail, binds de mouse/status e teclas F1–F10.
- Ciclo obrigatório (AGENTS.md) ao mudar comportamento: ler `AI-DLC.md` e `tests/INTERACTIONS.md`;
  preservar config/sessões/dados; testar isolado; rodar `tests/run.sh`; para interface, atualizar a
  matriz em `INTERACTIONS.md` e acrescentar ao menos uma verificação executável da rota.
- Uma mudança só está pronta quando o mesmo resultado funciona por todos os canais do elemento:
  CLI, teclado, mouse/toque, menu e barra.
- Mudança que acrescenta arquivo ao pacote deve entrar em `ARQUIVOS_FONTE` no `tt`.

## Requisitos

Núcleo: bash, tmux ≥ 3.4, fzf ≥ 0.60, python3, ssh, tar (GNU), rg. Opcionais: tailscale (descoberta
e estado online das máquinas), mosh (celular), pv (barra de progresso), claude (botões cl/clc/clr e
nomeador), aerc (e-mail), mbsync/isync (sync local), git (sync de tarefas por repo). macOS: bash ≥ 4
pelo Homebrew; comandos remotos levam o PATH do Homebrew (o instalador acrescenta um bloco ao
`~/.zshenv`).

## Fluxos comuns (receitas)

- **Publicar uma mudança para todas as máquinas**: edite no clone de origem (`repo=`), rode
  `make test`, `git commit`, `git push` para a `main`, depois `tt --sincronizar` (ou deixe o vigia
  de cada máquina puxar a versão publicada em até 5 min).
- **Cadastrar uma máquina nova**: `tt --cadastrar` (sem host lista a tailnet); depois
  `tt --saude`/`tt --diagnosticar` se não conectar; `tt --reparar` resolve "sem chave".
- **Investigar a barra que não desenha**: o dado vive no perfil (`fixadas`, `tarefas`); a barra lê
  a opção tmux (`@barra_fixadas`, `@barra_tarefas`) recalculada por `atualizar_barras`. Se a opção
  ficou dessincronizada, force `atualizar_barras` / `--aplicar-fixadas` / `tt --barras`.
- **Nome de sessão não muda**: nome dado à mão nunca é trocado; o automático depende de pedidos e
  tempo (pontos). `tt --nomeador` escolhe a fonte; `tt --nomear-todas` força agora.
