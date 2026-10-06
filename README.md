# tt — central de terminais

O nomeador automático usa o `~/.local/bin/claude-rot`, quando instalado com suporte
a `--claude-only`, para alternar entre contas Claude com Haiku, sem ferramentas.
Sem rotator, usa o Claude local. Falhas de execução, limites e respostas fora do
formato de nome são rejeitados, inclusive quando vêm de outra máquina; o nome
existente é preservado. O título da conversa continua sendo usado sem consulta
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
  rolagem), ☰ central, ┃/━ dividir, ⋯ menu do painel, ⇅ arquivos, 📧 e-mail (abre o cliente de
  terminal numa subjanela, como a central; `aerc` por padrão, configurável), ⤢ caber nesta tela (quando duas
  telas de tamanhos diferentes usam a mesma sessão). Botão direito também abre os menus.
- **Uma sessão, vários aparelhos**: a janela tem o tamanho do aparelho que você está usando: tecla,
  toque ou clique, foco na janela, girar o celular ou abrir o teclado passam a sessão para ele na
  hora, e o outro toma de volta assim que for usado. Quem só está olhando vê ⤢ na barra (um toque
  encaixa nele). A janela nunca fica presa num tamanho fixo.
- **Copiar e colar iguais em todo lugar**: arrastar copia (também sobre o Claude Code, o Codex e
  sessões de outra máquina), duplo clique copia a palavra, triplo a linha, sempre com o aviso
  "📋 copiado (N caracteres)"; a cópia vai para a área de transferência do aparelho em uso (PC,
  Windows/WSL ou celular via mosh). Colar: Ctrl+Shift+V, botão do meio ou ⋯ → 📋 Colar; no
  celular, ⋯ → 📋 Copiar o texto da tela. Shift+arrastar continua sendo a seleção do terminal.
- **Painéis com outras sessões**: `^v` ao lado, `^o` embaixo, `^p` troca — inclusive sessões de
  outra máquina. Uma sessão de outra máquina vista daqui vira uma "ponte"; trocar de sessão pela
  barra de lá troca a sua tela de verdade (sem ponte dentro de ponte).
- **Arquivos entre máquinas**: navegador de pastas (→ entra, ← sobe, Tab marca, ⏎ confirma), escolha
  da máquina e da pasta (a de cada sessão de lá aparece como opção). Nunca sobrescreve: conflito
  vira `nome (2)`. Quem recebe vê um aviso na tela. Rodam em segundo plano: a barra
  mostra "⇅ N em andamento" e avisa ao terminar; ⇅ → Acompanhar mostra progresso, velocidade e
  cancela (cópia cancelada ou interrompida não deixa nada pela metade).
- **⚙ tmux**: janelas, layouts, digitar em todos os painéis, histórico, mouse, atalhos, editar e
  recarregar a configuração, desanexar telas.
- **Nomes automáticos**: sessões genéricas ganham nome pelo assunto (título do Claude Code, ou o
  Claude Haiku lendo a tela, se o `claude` estiver instalado).

## Requisitos

bash, git, tmux ≥ 3.4, fzf ≥ 0.60, python3, ssh, tar (GNU) e `rg` (testes e busca rápida).
Opcionais: tailscale, mosh (celular), pv (barra de progresso nas cópias), claude (nomes automáticos).

macOS: bash ≥ 4 e as demais dependências pelo Homebrew (`brew install bash tmux fzf ripgrep`). Como o
ssh não interativo do macOS (zsh) não carrega o Homebrew, a instalação acrescenta ao `~/.zshenv` um
bloco entre marcadores que põe `~/.local/bin`, `/opt/homebrew/bin` e `/usr/local/bin` no PATH, e todo
comando que o tt manda para outra máquina já leva esse PATH. Não é preciso `setopt NO_EQUALS`.

## Instalação

    git clone https://github.com/helio-nogueira-cardoso/tt-terminais.git && cd tt-terminais
    ./tt --instalar [nome-desta-máquina]

Ou, instalando automaticamente as dependências que faltarem:

    ./instalar.sh [nome-desta-máquina]

O instalador detecta apt, dnf, pacman, apk, Homebrew e Termux/pkg, instala tudo em uma única etapa,
traduz nomes de pacotes entre as distribuições e verifica novamente os comandos antes de instalar o
tt. Em Linux, pode ser necessário informar a senha do `sudo` uma vez.

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


Tudo isso também está no menu de máquinas (clique no nome da máquina na barra). Configuração:

    ~/.config/tt/config     nome=<como esta máquina aparece>   repo=<clone de origem, se houver>
                            recebidos=<pasta onde chegam os arquivos> (padrão: ~/Recebidos; no
                            WSL, Downloads\\Recebidos do Windows)
                            claude_flags=<opções extras do claude nos botões CL, CLC e CLR>
                            claude_env=<variáveis para o claude nesses botões, ex.: IS_SANDBOX=1>
                            email=<cliente de e-mail do botão 📧; padrão aerc. A conta e as
                            credenciais ficam na config do próprio cliente, nunca aqui>
    ~/.config/tt/maquinas   host  usuario  nome  [oculta]  (uma máquina por linha)

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
  código); Google e outros pelo navegador. Precisa do ID de um app OAuth (para a Microsoft há a opção do ID
  público do Thunderbird). O token de renovação fica em `~/.secrets` e o aerc renova o acesso sozinho.

Em **ajustar** (ou ✏ editar): servidores IMAP/SMTP, portas, segurança (TLS, STARTTLS ou nenhuma, só
para localhost), usuário de login diferente do endereço, nome de exibição e pasta inicial.

Cada conta tem um arquivo sem segredos em `~/.config/tt/email/<conta>.conf`; o `accounts.conf` do
aerc é gerado entre marcadores `# >>> tt e-mail: <conta> >>>` — blocos escritos à mão ficam intactos, e as
contas do cadastro antigo são importadas sozinhas. Pela linha de comando:

    tt --email-adicionar nome=Pessoal endereco=eu@gmail.com provedor=gmail auth=senha --senha-stdin
    tt --email-adicionar nome=X endereco=eu@x.com imap_host=mail.x.com imap_porta=143 imap_seg=starttls \
       smtp_host=mail.x.com smtp_porta=587 smtp_seg=starttls auth=comando 'cred_cmd=pass email/x'
    tt --email-listar | --email-testar NOME | --email-autorizar NOME | --email-remover NOME

### O leitor de e-mail (aerc)

O tt deixa o aerc pronto em toda máquina (só acrescenta o que você não configurou; o que já estiver no
`aerc.conf` fica): tema **Catppuccin Mocha** igual ao do tt, pastas em árvore com a **contagem de não
lidas**, conversas agrupadas em fios, datas curtas e e-mails em **HTML legíveis** mesmo sem `w3m`
(usa `lynx` ou o conversor do próprio tt, com os links numerados no fim). Atalhos, na lista e na leitura:

| Tecla | Ação | Tecla | Ação |
|---|---|---|---|
| ⏎ | abrir | `q` | fechar (a mensagem / o e-mail) |
| `u` | lido ↔ não lido | `*` | estrela (importante) |
| `rr` / `Rr` | responder a todos / responder | `f` | encaminhar |
| `a` | arquivar | `d` / `D` | apagar (com confirmação / direto) |
| `M` | mover para pasta (Tab completa) | `Y` | copiar para pasta |
| `F` | só não lidos (Esc volta) | `/` | buscar |
| `m` | escrever | `J` / `K` | próxima / anterior pasta |
| `v` / espaço | selecionar várias (as ações valem para todas) | `?` | tela de atalhos, em português |
| Ctrl+j / Ctrl+k | escolher anexo (na mensagem) | `O` / `S` | abrir / salvar o anexo |
| `E` | **enviar os anexos para a pasta de recebidos de uma máquina do tt** (seletor visual) | `F2` | contas de e-mail |

E-mails com versão HTML abrem nela, pelo `w3m` (tabelas, cores, links), na largura da janela. Em tela
estreita (lado a lado, celular) o 📧 abre o aerc sem a barra de pastas (`J`/`K` trocam de pasta).
**Botão direito no 📧**: abrir, contas (cadastrar, descadastrar, testar), nova conta e atalhos.

## Sessões fixadas

Uma segunda linha na barra com as sessões que você usa sempre (desta ou de outras máquinas): um
toque vai direto para ela ao pressionar, e o ✕ ao lado desafixa; botão direito num item: ir, desafixar, mover para
os lados. Para fixar a sessão em uso: o pino ao lado do nome dela na barra (📍 = não fixada, um
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
  (`TT_T_RENOMEAR`, em segundos), o Haiku sugere o nome novo. Pedido é uma mensagem digitada na
  conversa do Claude ou, nas outras abas, tecla/toque de verdade (saída na tela não conta). Sem
  pedido novo o assunto não mudou e o Haiku nem é chamado, por mais que a tela mude (um agente
  trabalhando sozinho no mesmo pedido). Mudar de pasta também renomeia. Nas abas do Claude o
  primeiro nome é o título da conversa (sem custo); as revisões leem os últimos pedidos e a tela,
  e o nome acompanha a tarefa atual. Se o título da conversa mudar, a aba o segue.

O comando `^a`/“Nomear todas” faz isso sequencialmente nesta máquina e em todas as máquinas
cadastradas que estiverem acessíveis.

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

## Arquivos

    tt --enviar                          navega a partir da pasta atual; escolhe máquina e pasta
    tt --enviar a.pdf fotos/ trabalho    envia para a pasta de recebidos de "trabalho"
    tt --enviar a.pdf trabalho:~/docs    envia para essa pasta
    tt --trazer                          escolhe máquina, pasta e arquivos de lá → pasta atual
    tt --trazer trabalho:~/x.log [pasta] traz direto
    tt --pasta-padrao                    escolhe (navegando) onde chegam os arquivos nesta máquina
    tt --pasta-padrao trabalho:~/docs    define a pasta padrão de outra máquina

Cada máquina tem sua pasta padrão de recebidos: `~/Recebidos`; no WSL, `Downloads\Recebidos` do
Windows; no Termux, `Download/Recebidos` do Android. Dá para mudar pelo ⇅ ("Mudar a pasta padrão…"),
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
usa 👻 para Kiro, 🦀 para Claude e ⚪ para Codex. Um toque
abre uma sessão nova na máquina atual e muda para ela. Os padrões incluem Kiro v3, Claude com
permissões liberadas e o fluxo de resume.

Cada máquina pode sobrescrever, desativar ou acrescentar atalhos em `~/.config/tt/atalhos`, no mesmo
formato `emoji<TAB>id<TAB>comando<TAB>cor-de-fundo` (a quarta coluna é opcional, em hexadecimal,
como `#cba6f7`). A segunda coluna é o ID estável: uma linha local com o mesmo ID substitui a padrão; emoji
`-` desativa; um ID novo acrescenta:

    👾	kiro-v3	kiro-cli chat --v3
    -	codex
    🧪	meu-teste	ssh servidor

Os padrões são três: 👻 Kiro, 🦀 Claude (retomando a conversa) e ⚪ Codex. Para editar sem abrir
o arquivo: menu ⋯ do painel → **✏ Atalhos da barra** (⏎ edita emoji, comando e cor; ^n novo; ^x
exclui ou desativa um padrão; ^r volta ao padrão). O arquivo continua editável à mão. Os botões “lado” e “baixo” ficam disponíveis no menu de
painel, mas não ocupam mais a barra.

As contas criadas por `claude-conta adicionar <nome>` aparecem automaticamente como `1️⃣`, `2️⃣`,
`3️⃣` etc.; as credenciais e os nomes dos perfis não entram no GitHub. O arquivo versionado pode ser
alterado no repositório para que novos atalhos padrão cheguem a todas as máquinas.

## Atalhos da central

    ⏎ entrar   ^n nova   ^r renomear   ^x fechar   ^t soltar painel   ^a nomear todas
    ^v ao lado   ^o embaixo   ^p trocar painel   ^s enviar   ^g trazer
    ^f filtrar por máquina   ^e busca (tudo / só nomes)   ⚙ tmux…   🖥 máquinas…   esc sair

As palavras do cabeçalho são clicáveis.

Sessões com nome genérico (`janela-N`, `claude-N`) ganham nome sozinhas conforme o uso: o título
da conversa, se for o Claude, ou um nome curto que o Haiku tira da tela. O tt acha sozinho onde o
Claude guarda as conversas e qual `claude` usar, inclusive no Termux, com o Claude dentro do Debian
(`proot-distro`). Um nome que você der à mão (`^r`, Ctrl+B N) nunca é trocado.

## Atualizar

    tt --atualizar           instala a versão mais nova publicada no GitHub nesta máquina
    tt --atualizar --todas   … e nas máquinas cadastradas

O vigia consulta a fonte publicada a cada 5 min e instala automaticamente uma versão superior
nesta máquina; sem rede, mantém o tt em funcionamento e tenta de novo no ciclo seguinte.
`TT_T_ATUALIZACAO=0` força a consulta em cada volta do vigia (útil para teste). O menu de máquinas
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
    termux/celular.sh --nome cel --chaves-github USUARIO --sem-claude   opções da instalação

Tudo é idempotente: depois de um `git pull`, rodar de novo aplica só o que mudou (a versão do perfil
fica em `~/.local/state/tt/celular`). Arquivos que seriam trocados ganham cópia `*.antes-celular`, e
`claude_flags`/`claude_env` só entram no config se ainda não existirem. Uma barra de teclas própria
(com botões pessoais, por exemplo) vai em `~/.config/tt/termux.properties` e tem prioridade sobre a
geral. `CELULAR_SIMULAR=1` mostra
os comandos sem executar.

## Celular / tela pequena

Em telas com menos de 80 colunas ou 30 linhas (celular), a central abre em tela cheia, com
cabeçalho compacto (toque em "?" para todos os atalhos) e prévia escondida (toque em "prévia" ou
^/). O seletor rápido (toque no nome da sessão na barra) é o jeito mais prático de trocar de sessão
pelo toque.

## Desenvolvimento

### Testes e AI-DLC

Rode `make test` (ou `tests/run.sh`) antes de publicar mudanças. A suíte usa configuração e
runtime temporários para testar fluxos de CLI sem tocar nas máquinas cadastradas, além de validar
os bindings do tmux num servidor isolado. Para auditar uma instalação, use
`TT_DIR=~/.local/share/tt tests/run.sh`.

O projeto segue a política [`AI-DLC.md`](AI-DLC.md); o protocolo de trabalho para agentes está em
[`AGENTS.md`](AGENTS.md), e a cobertura esperada de mouse, toque, teclado, menus e CLI está na
[`tests/INTERACTIONS.md`](tests/INTERACTIONS.md).

O clone é a origem: edite, faça commit e rode `tt --sincronizar`. A versão é o número de commits
(`+dev` quando há mudanças não gravadas); máquinas com versão mais velha aparecem com ⚠ no menu
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
