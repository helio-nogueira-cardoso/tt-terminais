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
  telas de tamanhos diferentes usam a mesma sessão). Botão direito também abre os menus.
- **Uma sessão, vários aparelhos**: a janela tem o tamanho do aparelho que você está usando: tecla,
  toque ou clique, foco na janela, girar o celular ou abrir o teclado passam a sessão para ele na
  hora, e o outro toma de volta assim que for usado. Quem só está olhando vê ⤢ na barra (um toque
  encaixa nele). A janela nunca fica presa num tamanho fixo.
- **Copiar e colar iguais em todo lugar**: **Alt**+arrastar copia (também sobre o Claude Code, o Codex e
  sessões de outra máquina), Alt+duplo clique copia a palavra, Alt+triplo a linha; sem Alt, arrastar e
  clicar vão ao programa e nada é copiado (sem cópias por acidente). Sempre com o aviso
  "📋 copiado (N caracteres)"; a cópia vai para a área de transferência do aparelho em uso (PC,
  Windows/WSL ou celular via mosh). O que a tela partiu em linhas — um endereço, caminho ou código
  longo quebrado na borda, com recuo ou borda na linha de baixo, como no Claude Code — volta a ser
  uma coisa só na cópia; quebras de verdade ficam. Colar: Ctrl+Shift+V, botão do meio ou
  ⋯ → 📋 Colar; no celular, ⋯ → 📋 Copiar o texto da tela. Shift+arrastar continua sendo a seleção
  do terminal (essa não passa pelo tt).
- **Links clicáveis em qualquer painel**: clique num endereço (http/https) abre a mesma escolha de
  navegador do e-mail (veja "Links: escolha do navegador"), com a URL inteira mesmo quando ela está
  quebrada em várias linhas; Alt+duplo clique copia o link inteiro; Ctrl+B u (ou ⋯ → 🔗 Links da tela)
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

## Requisitos

bash, git, tmux ≥ 3.4, fzf ≥ 0.60, python3, ssh, tar (GNU) e `rg` (testes e busca rápida).
Opcionais: tailscale, mosh (celular), pv (barra de progresso nas cópias), claude (nomes automáticos).

`tt --pendencias` mostra, para a máquina em que você está, tudo isso e mais o que os recursos pedem (aerc,
mbsync, w3m, vim, Chrome, Carbonyl, bibliotecas, clipboard, notificações…), o que está pronto e o que falta;
o [modal de pendências](#pendências-de-instalação-) instala o que faltar.

Plataformas: Linux (Debian, Ubuntu e derivados, incluindo WSL; Fedora/RHEL; openSUSE; Arch; Alpine; Void),
macOS (Homebrew), Termux no Android, Linux (Debian) dentro do proot do Termux e FreeBSD, OpenBSD e NetBSD.
Os navegadores baixados (Chrome e Carbonyl) são binários glibc x86_64: só entram em Linux x86_64 com glibc.

macOS: bash ≥ 4 e as demais dependências pelo Homebrew (`brew install bash tmux fzf ripgrep`). Como o
ssh não interativo do macOS (zsh) não carrega o Homebrew, a instalação acrescenta ao `~/.zshenv` um
bloco entre marcadores que põe `~/.local/bin`, `/opt/homebrew/bin` e `/usr/local/bin` no PATH, e todo
comando que o tt manda para outra máquina já leva esse PATH. Não é preciso `setopt NO_EQUALS`.

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


Tudo isso também está no menu de máquinas (clique no nome da máquina na barra). Configuração:

    ~/.config/tt/config     nome=<como esta máquina aparece>   repo=<clone de origem, se houver>
                            recebidos=<pasta onde chegam os arquivos> (padrão: ~/Recebidos; no
                            WSL, Downloads\\Recebidos do Windows)
                            claude_flags=<opções extras do claude nos botões CL, CLC e CLR>
                            claude_env=<variáveis para o claude nesses botões, ex.: IS_SANDBOX=1>
                            email=<cliente de e-mail do botão 📧; padrão aerc. A conta e as
                            credenciais ficam na config do próprio cliente, nunca aqui>
    ~/.config/tt/maquinas   host  usuario  nome  [oculta]  (uma máquina por linha)

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
    ia-rot --melhor                  # só diz qual seria: conta, pico e uso (sai 2 se nenhuma livre)

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
↩↩ Todos · ↪ Encaminhar · ▤ Arquivar · ✕ Apagar · 📁 Pasta · ⟳ Sincronizar · 👤 Contas · ? Atalhos (em
tela estreita, só os ícones); cada botão faz o mesmo que a tecla. **⟳ Sincronizar** (ou `Ctrl+s`, ou
botão direito no 📧 → *Sincronizar agora*, ou `tt --email-sync-agora`) consulta a caixa de entrada de
todas as contas **agora**, sem esperar a vez do vigia nem a pausa que ele faz depois de um erro — para
quando você está esperando um código com validade. As contas vão em paralelo; se a volta completa
estiver no meio, ela é interrompida (o vigia a refaz depois) para a caixa de entrada vir já. O botão
mostra *consultando…* e depois *✓ 2 novos* (ou *nada novo*), a mensagem aparece na tela e, se chegou
algo, o aviso de e-mail novo diz de quem é. **Os botões valem de qualquer lugar**: contas e atalhos
são telas do tt que abrem por cima do aerc (a barra continua embaixo) e se fecham com `q`, Esc ou o
mesmo botão de novo; abrir uma com a outra aberta troca; e um botão do aerc (abrir, responder,
apagar…) com uma tela dessas na frente primeiro a fecha e depois age. Com uma mensagem sendo escrita
ou um terminal na frente, os botões do aerc não injetam letras no que está sendo digitado (eles vão por
teclas de função que só agem na lista e na leitura). A linha de status do aerc mostra só o estado
(conta, conexão, sincronização); as dicas de teclas saíram, porque os botões já dizem tudo.
**Duplo clique** numa mensagem abre; um clique numa **aba** troca de conta, numa **pasta** abre a
pasta, e a roda rola. Atalhos, na lista e na leitura:

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

### Consulta mais rápida

Por padrão o aerc guarda os cabeçalhos em disco (`cache-headers`, em `~/.cache/aerc`): abrir uma pasta
deixa de rebaixar tudo pela rede a cada vez, o que acelera caixas grandes ou conexões lentas sem
depender de nada além do próprio aerc.

Para quem precisa de mais, cada conta pode manter um **espelho local completo** (opt-in, desligado por
padrão), com o [`mbsync`](https://isync.sourceforge.io/) (pacote `isync`): o aerc passa a ler de um
`maildir` em `~/.cache/tt/maildir/<conta>` (abertura instantânea, busca local, leitura offline do que
já baixou), e o envio continua pelo SMTP normal. As marcas (lido, arquivado, apagado) e as mensagens
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
Agentes de IA (e scripts) num painel do tt avisam com `tt --notificar-daqui "texto" [segundos] [--sempre]`:
o aviso só sai se você não estiver olhando para a janela de onde ele veio (o tt vê o foco pelo tmux), e o
clique leva direto àquela sessão e àquele painel.
Com a faixa, a linha das fixadas fica 100% para as fixadas, e o 📧 e o relógio saem da 1ª linha.
Sem aviso novo, o slot mostra o **🔔** (sempre visível; é a porta do histórico) e, se você ativar
um **letreiro** (ligado de fábrica; `indicadores=` escolhe as fontes e `indicadores=0` desliga) rolando com as infos (dólar via
AwesomeAPI, frases, e notícias G1 + BBC World por RSS — tudo sem chave, com cache; a rede roda no
vigia, nunca no letreiro). Com aviso OU transferência ativa, o letreiro cede a vez (transferências aparecem aqui, com o
andamento ao vivo — nada cobre as linhas de cima).

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

- Três fontes nativas no código: **dólar** (AwesomeAPI, TTL 600 s; `💵 dólar R$ 5,123 ▲0,5%`), **frases**
  (lista embutida de 6, uma sorteada por TTL de 600 s) e **notícias** (RSS do g1 e da BBC World, 2 manchetes
  de cada, TTL 900 s). O config só ligava/desligava por `indicadores=dolar,frases,noticias`
  (`indicadores=0` desliga tudo) e `indicador_NOME=URL ;; rótulo ;; caminho.no.json ;; ttl ;; Header: @arquivo`
  criava fontes próprias (só GET; só JSON ou texto cru com o caminho `-`; um valor por fonte; valor cortado em
  60 e linha em 90 caracteres; sem formatação, sem cor, sem teste, sem diagnóstico, sem propagação, erro de
  rede em silêncio). Os ajustes globais eram `ticker_rolagem` (continua/paginas), `ticker_veloc`, `ticker_fps`
  (1 a 20) e `ticker_ponte`.
- **Nada disso quebra.** As linhas `indicador_NOME=` e o `indicadores=` são migrados sem perda para arquivos
  (`tt --letreiro-migrar`; roda sozinho na primeira atualização): o corte em 60/90 vira `valor_max=60` e
  `truncar=90`, o header `@arquivo` continua apontando para `~/.secrets`, e um header com segredo **literal**
  tem o valor movido para `~/.secrets/letreiro-NOME` (modo 600) e sai da linha do config. As linhas antigas
  ficam no config (sem perda); depois de migrada, vale o arquivo. Se você editar `indicadores=` depois, a
  lista nova é reaplicada. `tt --ticker-fontes` e `tt --ticker-quadro` seguem funcionando.
- Única diferença visível: o texto sai pelo mesmo motor das demais fontes, então a variação do dólar usa a
  vírgula do pt-BR (`▲0,5%`, antes `▲0.5%`) e uma variação que arredonda para zero fica neutra (`•0,0%`).

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
| `separador` | pt/en | — | pt = 1.234,56; en = 1,234.56 (vazio = como veio) |
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
| `truncar` | inteiro 10–400 | `90` | largura máxima do item (células) |
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
`ticker_separador` (entre itens), `ticker_ordem` (`manual` pelo campo `ordem`, `aleatoria`, `peso`),
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
duplicar, `^k`/`^j` subir/descer na roda, `^l` log, `^x` remover (de fábrica: tirar da lista), `Tab` vista (todas · na roda · disponíveis), `^g` ajustes, `^b` catálogo, `^p`
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
| `dolar-australiano` | Dólar australiano em reais | 🇦🇺 dólar aus. R$ 3,482 ▼0,3% |
| `dolar-canadense` | Dólar canadense em reais | 🇨🇦 dólar can. R$ 3,498 ▼0,8% |
| `dolar-turismo` | Dólar turismo em reais | 🧳 dólar turismo R$ 4,953 ▼0,5% |
| `euro` | Euro em reais (AwesomeAPI, sem chave) | 💶 euro R$ 5,583 ▼0,8% |
| `euro-dolar` | Euro em dólares | 💱 euro/dólar US$ 1,1201 ▼0,1% |
| `franco-suico` | Franco suíço em reais | 🇨🇭 franco suíço R$ 6,004 ▼0,5% |
| `iene` | Iene japonês em reais | 💴 iene R$ 0,0314 ▼1,0% |
| `libra` | Libra esterlina em reais | 💷 libra R$ 6,593 ▼0,5% |
| `ouro-onca` | Ouro: onça troy em reais | 🥇 ouro (onça) R$ 20.917 ▲0,6% |
| `peso-argentino` | Peso argentino em reais | 🇦🇷 peso arg. R$ 0,0032 ▼0,2% |
| `yuan` | Yuan chinês em reais | 🇨🇳 yuan R$ 0,745 ▼0,5% |

**₿ Criptomoedas** (11)

| fonte | o que mostra | como aparece |
|---|---|---|
| `bitcoin` | Bitcoin em reais (AwesomeAPI, sem chave) | ₿ bitcoin R$ 420.217 ▲0,8% |
| `bitcoin-bloco` | Altura do último bloco do Bitcoin (mempool.space, sem chave) | 🧱 bloco BTC 970.972 |
| `bitcoin-taxa` | Taxa de rede do Bitcoin para confirmar logo (mempool.space, sem chave) | ⛏ taxa BTC 2 sat/vB |
| `bitcoin-usd` | Bitcoin em dólares (Coinbase, sem chave) | ₿ BTC US$ 83.632 |
| `dogecoin` | Dogecoin em reais | 🐕 dogecoin R$ 0,436 ▲0,5% |
| `ethereum` | Ethereum em reais | Ξ ethereum R$ 12.741 ▲1,0% |
| `ethereum-usd` | Ethereum em dólares (Coinbase, sem chave) | Ξ ETH US$ 2.533 |
| `litecoin` | Litecoin em reais | Ł litecoin R$ 323,60 ▲0,4% |
| `medo-ganancia` | Índice de medo e ganância das criptomoedas (alternative.me, sem chave) | 😨 medo/ganância 61 (Greed) |
| `solana` | Solana em reais | ◎ solana R$ 562,30 ▲1,6% |
| `xrp` | XRP em reais | ✕ XRP R$ 7,073 ▲0,3% |

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
| `dow-jones` | Dow Jones em pontos (Yahoo Finance, endpoint não oficial) | 🇺🇸 Dow Jones 51.655 ▲0,8% |
| `ibovespa` | Ibovespa em pontos; só atualiza no pregão (Yahoo Finance, endpoint não oficial) | 📊 Ibovespa 209.067 ▲1,4% |
| `itub4` | Itaú Unibanco PN em reais (Yahoo Finance, endpoint não oficial) | 🏦 ITUB4 R$ 50,47 ▲2,3% |
| `nasdaq` | Nasdaq Composite em pontos (Yahoo Finance, endpoint não oficial) | 🇺🇸 Nasdaq 27.366 ▲0,6% |
| `nikkei` | Nikkei 225 em pontos (Yahoo Finance, endpoint não oficial) | 🇯🇵 Nikkei 69.031 •0,0% |
| `ouro-futuro` | Ouro, futuro em dólares por onça (Yahoo Finance, endpoint não oficial) | 🥇 ouro US$ 4.216,30 •0,0% |
| `petr4` | Petrobras PN em reais (Yahoo Finance, endpoint não oficial) | 🛢 PETR4 R$ 56,00 ▲0,9% |
| `petroleo-brent` | Petróleo Brent, futuro em dólares (Yahoo Finance, endpoint não oficial) | 🛢 Brent US$ 104,72 •0,0% |
| `petroleo-wti` | Petróleo WTI, futuro em dólares (Yahoo Finance, endpoint não oficial) | 🛢 WTI US$ 91,85 •0,0% |
| `prata-futuro` | Prata, futuro em dólares por onça (Yahoo Finance, endpoint não oficial) | 🥈 prata US$ 61,05 •0,0% |
| `sp500` | S&P 500 em pontos (Yahoo Finance, endpoint não oficial) | 🇺🇸 S&P 500 7.812 ▲0,6% |
| `vale3` | Vale ON em reais (Yahoo Finance, endpoint não oficial) | ⛏ VALE3 R$ 67,90 ▲0,4% |
| `vix` | Índice de volatilidade VIX (Yahoo Finance, endpoint não oficial) | 😱 VIX 14,84 ▼3,7% |

**🌤 Tempo e clima** (13)

| fonte | o que mostra | como aparece |
|---|---|---|
| `clima-chuva` | Chuva neste momento (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🌧 São Paulo 0,4 mm |
| `clima-max-min` | Máxima e mínima de hoje (graus inteiros) (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🌡 São Paulo 25°/17° |
| `clima-nascer-do-sol` | Hora do nascer do sol (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🌅 São Paulo nasce 05:37 |
| `clima-pm25` | Partículas finas PM2,5 (µg/m³) (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🌫 São Paulo 16 µg/m³ |
| `clima-por-do-sol` | Hora do pôr do sol (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🌇 São Paulo põe 18:09 |
| `clima-prob-chuva` | Probabilidade de chuva hoje (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | ☔ São Paulo 100% |
| `clima-qualidade-ar` | Qualidade do ar (índice AQI dos EUA: até 50 boa, 100 moderada) (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 😷 São Paulo AQI 140 |
| `clima-sensacao` | Sensação térmica agora (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🥵 São Paulo 20,9°C |
| `clima-temperatura` | Temperatura agora (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🌡 São Paulo 19,6°C |
| `clima-tempo` | Condição do tempo agora (código WMO traduzido) (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | ⛅ São Paulo: pancadas fracas |
| `clima-umidade` | Umidade relativa do ar agora (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 💧 São Paulo 90% |
| `clima-uv` | Índice UV máximo de hoje (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 😎 São Paulo UV 7 |
| `clima-vento` | Velocidade do vento agora (Open-Meteo, sem chave; mude var.lat/var.lon/var.cidade para o seu lugar) | 🌬 São Paulo 10 km/h |

**🚀 Espaço e Terra** (5)

| fonte | o que mostra | como aparece |
|---|---|---|
| `iss-posicao` | Onde a Estação Espacial Internacional está agora (latitude, longitude; wheretheiss.at, sem chave) | 🛰 ISS -30.86°, 101.30° |
| `proximo-lancamento` | Próximo lançamento de foguete no mundo (The Space Devs, sem chave; 15 consultas/h) | 🚀 Falcon 9 Block 5 ¦ Starlink Group 15-25 (2026-10-12) |
| `sismo-recente` | Maior sismo recente (magnitude 4,5+ nas últimas 24 h; USGS, sem chave); some se não houve | 🌋 M 4.7 - 156 km ESE of Neiafu, Tonga |
| `tempestade-geomagnetica` | Índice Kp de atividade geomagnética (NOAA SWPC, sem chave): 5+ é tempestade | 🧲 Kp 2,3 |
| `vento-solar` | Velocidade do vento solar (NOAA SWPC, sem chave) | ☀ vento solar 535 km/s |

**🇧🇷 Brasil** (3)

| fonte | o que mostra | como aparece |
|---|---|---|
| `feriados` | Próximo feriado nacional (BrasilAPI, sem chave) | 📅 feriado Nossa Senhora Aparecida (2026-10-12) |
| `ibge-noticias` | Notícias do IBGE (API de serviços do IBGE, sem chave) | 📈 IBGE: Acervo bibliográfico de Pedro Geiger é doado à Biblioteca do IBGE |
| `megasena` | Último concurso da Mega-Sena (API aberta não oficial; sem chave) | 🍀 Mega-Sena 3068: 07-10-39-40-43-57 |

**📰 Notícias do Brasil** (16)

| fonte | o que mostra | como aparece |
|---|---|---|
| `agencia-brasil` | Manchetes: Agência Brasil (feed RSS, sem chave) | 🇧🇷 Agência Brasil: Interpretação é a base da prova de Linguagens do Enem; veja dicas |
| `camara-noticias` | Manchetes: Câmara (feed RSS, sem chave) | 🏛 Câmara: Projeto pune empresas que atrasarem pagamento de médicos |
| `cnn-brasil` | Manchetes: CNN Brasil (feed RSS, sem chave) | 📺 CNN Brasil: Chefe do Deutsche Bank vê eleições na Alemanha como risco para investidores |
| `estadao` | Manchetes: Estadão (feed RSS, sem chave) | 📰 Estadão: Ex-militar russo condenado à prisão perpétua é preso em Salvador |
| `exame` | Manchetes: Exame (feed RSS, sem chave) | 💼 Exame: Ciberataques são o principal risco imediato da IA, afirma Bill Gates |
| `folha` | Manchetes: Folha (feed RSS, sem chave) | 📰 Folha: Slayyyter faz show contido, marcado por aperto e calor no Zig Festival, em São Paulo |
| `folha-mercado` | Manchetes: Folha Mercado (feed RSS, sem chave) | 💼 Folha Mercado: Lula diz que votação do fim da 6x1 antes do segundo turno já está acordada com Alcolumbre |
| `g1-ciencia` | Manchetes: g1 Ciência (feed RSS, sem chave) | 🔬 g1 Ciência: 'Ciência Aberta': centro que abriga o Sirius recebe público para apresentar curiosidades e atrações da ciência |
| `g1-economia` | Manchetes: g1 Economia (feed RSS, sem chave) | 💼 g1 Economia: Mega-Sena acumula, e prêmio vai a R$ 150 milhões; veja os números sorteados |
| `g1-mundo` | Manchetes: g1 Mundo (feed RSS, sem chave) | 🌎 g1 Mundo: Aeroportos da Arábia Saudita voltam a ser bombardeados; Houthis reivindicam ataques |
| `g1-politica` | Manchetes: g1 Política (feed RSS, sem chave) | 🏛 g1 Política: Corregedor do TSE suspende preliminarmente decisão de Nunes Marques e libera canal 'Exército do Lula'; decisão |
| `g1-tecnologia` | Manchetes: g1 Tecnologia (feed RSS, sem chave) | 💻 g1 Tecnologia: IA ameaça aumentar desigualdades de gênero no mercado de trabalho, diz relatório |
| `ge-esportes` | Manchetes: ge (feed RSS, sem chave) | ⚽ ge: Ferroviária x Inter de Limeira - Campeonato Brasileiro Série C 2026 - globoesporte.com |
| `infomoney` | Manchetes: InfoMoney (feed RSS, sem chave) | 💼 InfoMoney: EUA ameaçam bloquear armas para Ucrânia devido a ataques a refinarias, diz FT |
| `poder360` | Manchetes: Poder360 (feed RSS, sem chave) | 📰 Poder360: Messias diz que Senado aprovará fim da 6 X 1 e pede votos para Lula |
| `senado-noticias` | Manchetes: Senado (feed RSS, sem chave) | 🏛 Senado: Áudio: Senado homenageia os 45 anos da Associação do Senhor Jesus |

**🌍 Notícias do mundo** (7)

| fonte | o que mostra | como aparece |
|---|---|---|
| `al-jazeera` | Manchetes: Al Jazeera (feed RSS, sem chave) | 🌍 Al Jazeera: Republican senator says Trump diesel agreement with Russia may be illegal |
| `bbc-brasil` | Manchetes: BBC Brasil (feed RSS, sem chave) | 🌍 BBC Brasil: Corredor Andes-Atlântico: o que se sabe sobre o ambicioso projeto dos EUA para acessar recursos estratégicos d |
| `bbc-mundo` | Manchetes: BBC World (feed RSS, sem chave) | 🌍 BBC World: Saudi capital airport hit by second Houthi strike in two days |
| `dw-brasil` | Manchetes: DW Brasil (feed RSS, sem chave) | 🌍 DW Brasil: "Sem anistia!": Milhares vão às ruas em defesa da democracia |
| `guardian` | Manchetes: Guardian (feed RSS, sem chave) | 🌍 Guardian: Controversial vaccine trial touted by RFK Jr gets go-ahead in Guinea-Bissau |
| `npr` | Manchetes: NPR (feed RSS, sem chave) | 🎙 NPR: Pope Leo XIV to undergo lung surgery this week |
| `nyt-mundo` | Manchetes: NYT World (feed RSS, sem chave) | 🗽 NYT World: Saudi Arabia Has Few Options as Houthis Aim at Heart of Its Ambitions |

**💻 Tecnologia** (18)

| fonte | o que mostra | como aparece |
|---|---|---|
| `ars-technica` | Manchetes: Ars Technica (feed RSS, sem chave) | 💻 Ars Technica: Prime Video unveils Blade Runner 2099 full trailer at NYCC |
| `bbc-tech` | Manchetes: BBC Tech (feed RSS, sem chave) | 💻 BBC Tech: King warns malicious online actors are evolving tactics |
| `canaltech` | Manchetes: Canaltech (feed RSS, sem chave) | 💻 Canaltech: Deixar TV ligada para o pet dormir gasta muita energia? Fizemos as contas |
| `debian-seguranca` | Avisos de segurança do Debian (feed RDF, sem chave) | 🛡 Debian DSA: DSA-6552-1 vips - security update |
| `go-blog` | Manchetes: Go Blog (feed ATOM, sem chave) | 🐹 Go Blog: Arch-specific SIMD in Go |
| `hacker-news` | Manchetes: Hacker News (feed RSS, sem chave) | 🟧 Hacker News: Chapter 1 of Ways of Seeing by John Berger |
| `lobsters` | Manchetes: Lobsters (feed RSS, sem chave) | 🦞 Lobsters: What's Wrong with GitHub |
| `lwn` | Manchetes: LWN (feed RSS, sem chave) | 🐧 LWN: Stable kernels 7.2.10 and 6.18.56 |
| `nyt-tech` | Manchetes: NYT Tech (feed RSS, sem chave) | 💻 NYT Tech: Inside Mark Zuckerberg’s Decision to Pull the Trigger on Meta’s A.I. Agent |
| `olhar-digital` | Manchetes: Olhar Digital (feed RSS, sem chave) | 💻 Olhar Digital: Economize na hora de imprimir: veja uma seleção de impressoras em promoção na Amazon |
| `phoronix` | Manchetes: Phoronix (feed RSS, sem chave) | 🐧 Phoronix: Linux Landing Kernel Workaround For AMD TLBI Erratum #1718 |
| `rust-blog` | Manchetes: Rust Blog (feed ATOM, sem chave) | 🦀 Rust Blog: Demoting i686 Windows targets to std-only |
| `techcrunch` | Manchetes: TechCrunch (feed RSS, sem chave) | 💻 TechCrunch: 48 hours to TechCrunch Disrupt 2026 — hear directly from the people building what’s next |
| `tecmundo` | Manchetes: Tecmundo (feed RSS, sem chave) | 💻 Tecmundo: Cyberleek vaza gameplay de GTA 6 com Lucia nua e ameaça liberar build completa do jogo |
| `tecnoblog` | Manchetes: Tecnoblog (feed RSS, sem chave) | 💻 Tecnoblog: TV TCL C7L 65” registra o menor preço desde lançamento em oferta no Magalu |
| `the-verge` | Manchetes: The Verge (feed ATOM, sem chave) | 💻 The Verge: Silicon Valley is falling in line with Trump’s attempt to rename AI |
| `ubuntu-seguranca` | Avisos de segurança do Ubuntu (feed RSS, sem chave) | 🛡 Ubuntu USN: USN-8911-1: Linux kernel (OEM) vulnerabilities |
| `wired` | Manchetes: Wired (feed RSS, sem chave) | 💻 Wired: I Made Terrible Games With Google’s AI Playground |

**🔬 Ciência** (4)

| fonte | o que mostra | como aparece |
|---|---|---|
| `bbc-ciencia` | Manchetes: BBC Science (feed RSS, sem chave) | 🔬 BBC Science: Orangutans released back into Borneo forest after devastating fires |
| `nasa` | Manchetes: NASA (feed RSS, sem chave) | 🚀 NASA: APOD: 2026 October 11 – Ice Fishing for Cosmic Neutrinos |
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
| `fato-aleatorio` | Um fato aleatório em inglês (uselessfacts, sem chave) | 🧠 In the great fire of London in 1666 half of London was burnt down but only 6 people were injured. |
| `fato-gato` | Um fato sobre gatos em inglês (catfact.ninja, sem chave) | 🐈 The oldest cat on record was Crème Puff from Austin, Texas, who lived from 1967 to August 6, 2005, three days after her 38th birthday. A cat typically can live |
| `frase-zen` | Uma frase inspiradora em inglês (ZenQuotes, sem chave; no máx. 5 consultas/30 s) | 💭 “He who knows how to wait need make no concessions.” — Sigmund Freud |
| `hoje-na-historia` | Um fato histórico que aconteceu neste dia (Wikipédia em português, sem chave) | 🕰 2018: A missão Soyuz MS-10, transportando uma tripulação destinada à Estação Espacial Internacional, é abortada pouco depois do lançamento; a trip |
| `piada-ingles` | Uma piada curta em inglês (Official Joke API, sem chave) | 😄 Why did Sweden start painting barcodes on the sides of their battleships? — So they could Scandinavian. |
| `versiculo` | Um versículo bíblico aleatório (bible-api.com, sem chave) | 📖 Moses stretched out his hand toward the sky, and there was a thick darkness in all the land of Egypt for three days. (Exodus 10:22) |
| `wikipedia-aleatoria` | Um verbete aleatório da Wikipédia em português (sem chave) | 📚 Li Xiaoxia: mesa-tenista chinesa |
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
extenso) e os visíveis continuam confortáveis — a sessão em uso de cada janela nunca some da faixa. No popup: `⏎` vai para a sessão, `^x` desafixa e `^k`/`^j`
(ou alt-↑/↓) **reordenam ao vivo** — o item acompanha o cursor e, ao fechar, a barra e as outras
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
escrita para quem usa o tt). Quando o tt atualiza, o vigia põe **um** aviso 📰 na faixa; clicar abre a
tela. Máquina recém-instalada não recebe o aviso. Quem publica uma versão acrescenta a seção dela em
`NOVIDADES.md` no mesmo commit.

## Demandas por e-mail

Quem você autorizar pode mandar tarefas para a sua rede do tt **por e-mail**. O e-mail cai na caixa de uma
conta com sync local (`sync_local=1`), o tt reconhece o formato e cria uma **demanda pendente** que só vira
tarefa quando você aprova.

- **Autorizar um remetente:** menu **⋯ do painel → ✉ Demandas por e-mail** (tela com prompts) ou
  `tt --demanda-autorizar EMAIL [etiqueta] [auth|segredo|aberto] [segredo]`; `tt --demanda-remover EMAIL`;
  `tt --demandas` lista os remetentes e as pendentes. O cadastro (`~/.config/tt/demandas`, modo 600) é
  propagado às outras máquinas como o das contas de IA: vale a mudança mais nova (`--receber-demandas`,
  `--propagar-demandas`, `--puxar-demandas`; o vigia puxa a cada 30 min). A **etiqueta** é posta em toda
  demanda desse remetente.
- **Formato do e-mail:** assunto `[tt] título @sex 14h !alta *semanal #tag [~CÓDIGO]` — a mesma sintaxe de
  `tt --tarefa-add-natural`; com `~CÓDIGO` o e-mail cria/atualiza **aquela** tarefa (ver a seção de códigos acima). No corpo, linhas `- texto` (ou `* texto`) viram **subtarefas** e o resto vira a
  **descrição**; citação (`>`) e assinatura (`-- `) são ignoradas.
- **Segurança:** o `From` é forjável, então o padrão (`auth`) só aceita se o **provedor que recebeu**
  autenticou o remetente — `dmarc=pass`, ou `dkim=pass`/`spf=pass` alinhado ao domínio do `From`, lido do
  cabeçalho `Authentication-Results` **de cima** (o que o servidor final põe; o de baixo pode ser forjado).
  `segredo`: o assunto leva `[tt:SEGREDO]`. `aberto`: sem checagem — só onde forjar não importa. Mensagem
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
  usam; chave faltando é reparada por uma máquina que já acessa o destino.
- **Sem fricção:** nada é perguntado. Se uma ilha persistir por 2 voltas, a barra avisa.

`tt --malha` completa e mostra quem alcança quem (`ok`, `○` desligada, `✗` ilha); sai com o número de conexões quebradas.
Rastros: `~/.cache/tt-malha.log`. Testes: `tests/test_malha.sh`.

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
- **Reforço nas IAs:** o vigia (a cada ~5 min) e cada instalação/atualização gravam a skill `tt-terminais` e as regras acima
  (`agentes-regras-tt.md`, bloco gerenciado) no Claude (todas as contas), Codex e Kiro de cada máquina, inclusive nos proots do celular.
  `tt --reforcar-agentes` faz na hora. O que está fora do bloco nunca é tocado.
- Testes: `tests/test_tarefas_codigo.sh`.

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
são dois botões, iguais no PC e no celular, que abrem a IA com mais folga de uso **agora** (`ia-conta
abrir`, veja [Contas de IA](#contas-de-ia)) já sem pedir permissões:

- 🚀 **ia-nova** abre numa sessão nova e muda para ela;
- 👇 **ia-aqui** troca o que roda no painel atual (fecha o agente que estiver nele, ou parte do
  shell), na mesma pasta. Se ali havia uma conversa do Claude e a escolhida também é do Claude, a
  conversa continua (`{retomar}` vira `--retomar ID`); Codex e Kiro abrem uma sessão nova.

Um comando que começa com `@aqui ` roda no painel atual em vez de numa sessão nova. No celular os
dois entram no Debian (`proot-distro login debian --shared-tmp -- bash -lc '…'`).

Cada máquina pode sobrescrever, desativar ou acrescentar atalhos em `~/.config/tt/atalhos`, no mesmo
formato `emoji<TAB>id<TAB>comando<TAB>cor-de-fundo` (a quarta coluna é opcional, em hexadecimal,
como `#cba6f7`). A segunda coluna é o ID estável: uma linha local com o mesmo ID substitui a padrão; emoji
`-` desativa; um ID novo acrescenta:

    👾	kiro-v3	kiro-cli chat --v3
    -	codex
    🧪	meu-teste	ssh servidor

Para editar sem abrir
o arquivo: menu ⋯ do painel → **✏ Atalhos da barra** (⏎ edita emoji, comando e cor; ^n novo; ^x
exclui ou desativa um padrão; ^r volta ao padrão). O arquivo continua editável à mão. Os botões “lado” e “baixo” ficam disponíveis no menu de
painel, mas não ocupam mais a barra.

As contas não ganham mais um botão cada: os dois atalhos escolhem entre todas. O arquivo versionado
pode ser alterado no repositório para que novos atalhos padrão cheguem a todas as máquinas.

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
cadastro de conta OAuth e Ctrl+B u abrem o mesmo seletor com três opções (mais "📋 Só copiar o link"):

- **Google Chrome interno**: o estável, extraído do .deb oficial sem sudo, janela gráfica (WSLg ou X11); atualiza sozinho, no máximo uma vez por dia. Acha a tela mesmo numa sessão do tmux que perdeu o `DISPLAY` (anexada por ssh ou mosh); se ainda assim não abrir, avisa o motivo, abre no navegador do sistema e guarda o erro em `~/.cache/tt/chrome.log`;
- **Carbonyl embutido**: Chromium que desenha no terminal, num popup do tmux (Ctrl+Q ou Ctrl+C fecha). É um build
  de 2023 sem atualizações: use para ler, não para logins sensíveis;
- **Navegador padrão do sistema**: `xdg-open`, que no WSL abre o do Windows.

Os dois primeiros são baixados sob demanda para `~/.local/share/tt-navegadores`, sem sudo, e só são
instalados se o sha256 do pacote bater (o do Chrome, com o índice do repositório do Google; o do Carbonyl, com o fixado no `tt`). Só x86_64; no Termux ficam ocultos.
Máquina nova (`instalar.sh`) e máquina atualizada (`tt --sincronizar`, `tt --atualizar`) já deixam os dois prontos em segundo plano: baixam o Carbonyl e, havendo ambiente gráfico, o Chrome (o que já está instalado é pulado; o log fica em `~/.cache/tt/navegadores.log`). Se faltar `curl`/`unzip` (ou as bibliotecas do sistema que os navegadores pedem), eles entram nas [pendências de instalação](#pendências-de-instalação-): o vigia avisa (📦) e o modal instala com o `sudo` pedindo a senha ali, sem o tt vê-la; quem disse "não" a um deles não tem o download em segundo plano. A escolha mais recente aparece marcada. Para pular o seletor, ponha `navegador=chromium|carbonyl|sistema`
no `~/.config/tt/config` (o padrão é `perguntar`). O navegador sobe pelo servidor do tmux, fora do
isolamento de rede do leitor de e-mail.

Como o link é achado na tela: o tmux entrega ao `links-tt.py` a linha e a coluna do clique (e o
hyperlink OSC 8 sob o mouse, se o programa mandou um). Ele junta a linha clicada com as vizinhas
quando o que chega na borda direita continua, sem espaço, no começo da linha de baixo — seja a
quebra do próprio terminal, seja a de um programa que recua a continuação (Claude Code) ou a desenha
dentro de uma caixa. Um endereço curto que só termina na borda não gruda no texto da linha de baixo.
O clique simples espera o tempo de um duplo clique antes de abrir (o Alt+duplo clique copia); Ctrl+clique
abre na hora. No Windows Terminal, o Ctrl+clique numa linha que ele mesmo reconhece como URL é
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

## Desenvolvimento

### Testes e AI-DLC

A versão exibida é `v1.MINOR.PATCH` (o PATCH é o contador interno de publicação, que continua
sendo o que as máquinas comparam para decidir quem é mais novo; o MINOR sobe à mão em marcos).

Rode `make test` (ou `tests/run.sh`) antes de publicar mudanças. A suíte usa configuração e
runtime temporários para testar fluxos de CLI sem tocar nas máquinas cadastradas, além de validar
os bindings do tmux num servidor isolado. Para auditar uma instalação, use
`TT_DIR=~/.local/share/tt tests/run.sh`.

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
