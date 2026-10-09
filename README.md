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
- **Copiar e colar iguais em todo lugar**: arrastar copia (também sobre o Claude Code, o Codex e
  sessões de outra máquina), duplo clique copia a palavra, triplo a linha, sempre com o aviso
  "📋 copiado (N caracteres)"; a cópia vai para a área de transferência do aparelho em uso (PC,
  Windows/WSL ou celular via mosh). O que a tela partiu em linhas — um endereço, caminho ou código
  longo quebrado na borda, com recuo ou borda na linha de baixo, como no Claude Code — volta a ser
  uma coisa só na cópia; quebras de verdade ficam. Colar: Ctrl+Shift+V, botão do meio ou
  ⋯ → 📋 Colar; no celular, ⋯ → 📋 Copiar o texto da tela. Shift+arrastar continua sendo a seleção
  do terminal (essa não passa pelo tt).
- **Links clicáveis em qualquer painel**: clique num endereço (http/https) abre a mesma escolha de
  navegador do e-mail (veja "Links: escolha do navegador"), com a URL inteira mesmo quando ela está
  quebrada em várias linhas; duplo clique copia o link inteiro; Ctrl+B u (ou ⋯ → 🔗 Links da tela)
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
conta para as máquinas da rede (dell, s23)? (S/n)*; na tela da conta (`F2` → a conta → **⇪ Propagar
para as máquinas da rede…**) há um seletor de máquinas (todas marcadas, Tab desmarca, ⏎ envia); e pela
linha de comando:

    tt --email-propagar Pessoal                  # todas as máquinas cadastradas e acessíveis agora
    tt --email-propagar Pessoal dell s23         # só essas
    tt --email-propagar Pessoal --sobrescrever   # substitui a conta que já existir lá
    tt --email-adicionar … propagar=1 --senha-stdin    # (ou propagar=dell,s23) já manda ao cadastrar

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
lidas** (e as abas das contas também, `Career (3)`), conversas agrupadas em fios, datas curtas e em
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

Tudo o que o tt quer instalar com administrador (curl/unzip dos navegadores de links, as
bibliotecas do sistema que o Chrome/Carbonyl baixados pedem, `isync` do sync local, `w3m` do
HTML) se junta num **modal único** (`tt --pedir-sudo`): instalar tudo,
selecionar o que aceitar, ou recusar (a recusa vale 7 dias, por item). O `instalar.sh` da primeira
instalação já traz tudo isso de uma vez, em qualquer gerenciador (apt, dnf, pacman, apk, brew, pkg).

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

- **clique** numa tarefa abre/fecha os detalhes (o triângulo vira ▸ fechada / ▾ aberta): as
  subtarefas e, à direita, um **⋯ menu** discreto que abre o menu da tarefa (descrição, subtarefa,
  prazo, prioridade, repetir, mover, arquivar, apagar);
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

As tarefas ficam em `~/.config/tt/tarefas` e vão para as outras máquinas sozinhas:
`tarefas_sync=p2p|git|ambos|off` no `~/.config/tt/config` (com `tarefas_repo=<url>` para usar um
repositório git seu). A junção é por tarefa (a alteração mais recente vence; apagar nunca
"ressuscita").

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
padrão 0,25 → 4 colunas/s, uma por quadro; `ticker_veloc=0.5` dá 2/s, `1` dá 1/s; `paginas` troca em
blocos a cada `ticker_veloc=` s — padrão 6), `ticker_fps=1..6` (quadros por segundo, padrão 4: o tmux só
redesenha a barra 1 vez/s por `#()`, mas guarda a última linha de cada um — o pintor imprime um quadro
novo a cada 1/fps s e fps−1 gatilhos de linha vazia, defasados, provocam os redesenhos entre os
segundos; custo ≈ 2 KB por quadro e ~12 MB por processo, 1 pintor + 3 gatilhos por terminal; `1` volta
ao passo de 1 s), `aviso_pisca=1`
(alternância do aviso a cada segundo; padrão estático em negrito), `indicadores=` (quais fontes passam; `0` desliga o letreiro, o slot segue
para avisos/transferências) e endpoints próprios: `indicador_nome=URL ;; rótulo ;; caminho.no.json
;; ttl ;; Header: @arquivo-em-secrets` (caminho `-` = texto cru; a chave de API pode vir de
`~/.secrets`, fora do config). `faixa_notif=0` no `~/.config/tt/config` desliga e devolve o layout de 3 linhas (padrão: ligada;
desligada no Termux, onde a tela é baixa). `tt --ticker-quadro [largura]` imprime o que o letreiro
mostraria agora; `tt --ticker-fontes` atualiza as fontes. Indicadores acopláveis (clima, cotações…) virão aqui.

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
Máquina nova (`instalar.sh`) e máquina atualizada (`tt --sincronizar`, `tt --atualizar`) já deixam os dois prontos em segundo plano: instalam `curl`/`unzip` (direto com root ou sudo sem senha; senão abre um modalzinho com o resumo e o comando exato, e o próprio `sudo` pede a senha ali, sem o tt vê-la; recusar silencia por 7 dias), baixam o Carbonyl e, havendo ambiente gráfico, o Chrome; o que já está instalado é pulado e o log fica em `~/.cache/tt/navegadores.log`. A escolha mais recente aparece marcada. Para pular o seletor, ponha `navegador=chromium|carbonyl|sistema`
no `~/.config/tt/config` (o padrão é `perguntar`). O navegador sobe pelo servidor do tmux, fora do
isolamento de rede do leitor de e-mail.

Como o link é achado na tela: o tmux entrega ao `links-tt.py` a linha e a coluna do clique (e o
hyperlink OSC 8 sob o mouse, se o programa mandou um). Ele junta a linha clicada com as vizinhas
quando o que chega na borda direita continua, sem espaço, no começo da linha de baixo — seja a
quebra do próprio terminal, seja a de um programa que recua a continuação (Claude Code) ou a desenha
dentro de uma caixa. Um endereço curto que só termina na borda não gruda no texto da linha de baixo.
O clique simples espera o tempo de um duplo clique antes de abrir (o duplo clique copia); Ctrl+clique
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

A versão exibida é `v1.MINOR.PATCH` (o PATCH é o contador interno de publicação, que continua
sendo o que as máquinas comparam para decidir quem é mais novo; o MINOR sobe à mão em marcos).

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
