# tt — central de terminais

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
  rolagem), ☰ central, ┃/━ dividir, ⋯ menu do painel, ⇅ arquivos, ⤢ caber nesta tela (quando duas
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

bash, tmux ≥ 3.4, fzf ≥ 0.60, python3, ssh, tar (GNU). Opcionais: tailscale, mosh (celular), pv
(barra de progresso nas cópias), claude (nomes automáticos).

## Instalação

    git clone https://github.com/helio-nogueira-cardoso/tt-terminais.git && cd tt-terminais
    ./tt --instalar [nome-desta-máquina]

Ou, instalando também as dependências que faltarem (apt) em um passo só:

    ./instalar.sh [nome-desta-máquina]

Isso põe o tt em `~/.local/share/tt/`, liga `~/.local/bin/tt` a ele, faz o `~/.tmux.conf` carregar o
`tmux.conf` do tt (o antigo fica em `~/.tmux.conf.antes-tt`) e **configura o `~/.bashrc`** para cada
janela de terminal abrir já dentro do tmux e aparecer na central. O bloco é acrescentado ao fim,
entre marcadores, uma única vez (backup em `~/.bashrc.antes-tt`). Ajustes só daquela máquina vão no
`~/.tmux.conf`, depois da linha `source-file`.

### Cores iguais em todas as máquinas

O pacote inclui a paleta **Catppuccin Mocha** em `tema-terminal.sh`: ela configura as 16 cores ANSI, o fundo
e o texto do terminal ao abrir um shell, e o `tmux`/`fzf` usam a mesma paleta. Windows Terminal,
GNOME Terminal/VTE e Termux aceitam essa configuração; terminais que não aceitam as sequências de
cor simplesmente a ignoram. Para mudar o padrão, edite esse arquivo e as cores do `tmux.conf` no
clone de origem, faça commit e rode `tt --sincronizar`. Todas as máquinas cadastradas recebem o
mesmo pacote; `tt --atualizar --todas` faz o mesmo a partir da versão publicada.

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

## Máquinas

    tt --cadastrar [host [usuario [nome]]]   testa o ssh, instala o tt lá e cadastra as duas
                                             máquinas uma na outra (sem host: lista as do Tailscale)
    tt --descadastrar [nome]                 tira do menu (aqui e lá); opcionalmente desinstala lá
    tt --sincronizar [nome…]                 instala esta versão aqui e nas cadastradas
    tt --versao                              versão instalada ("N hash data")

Tudo isso também está no menu de máquinas (clique no nome da máquina na barra). Configuração:

    ~/.config/tt/config     nome=<como esta máquina aparece>   repo=<clone de origem, se houver>
                            recebidos=<pasta onde chegam os arquivos> (padrão: ~/Recebidos; no
                            WSL, Downloads\\Recebidos do Windows)
                            claude_flags=<opções extras do claude nos botões CL, CLC e CLR>
                            claude_env=<variáveis para o claude nesses botões, ex.: IS_SANDBOX=1>
    ~/.config/tt/maquinas   host  usuario  nome     (uma máquina por linha; "host -" esconde)

## Sessões fixadas

Uma segunda linha na barra com as sessões que você usa sempre (desta ou de outras máquinas): um
clique vai direto para ela; botão direito num item: ir, desafixar, mover para os lados. Para fixar:
menu da sessão (botão direito em "sessão ▾") → "📌 Fixar na barra", `^f` no seletor, ou
`tt --fixar [máquina:]sessão`. A lista é a mesma em todas as máquinas (cada mudança é copiada
para as cadastradas; quem estava desligada puxa a mais nova sozinha ao voltar, em até 5 min), então
as fixadas continuam lá ao entrar numa sessão de outra máquina. A linha
só aparece quando há alguma fixada. O vigia dá nome semântico às sessões (inclusive fixadas), e o item da barra
acompanha o novo nome:

- **primeiro nome**: uma aba de nome genérico (`janela-N`, `atalho-N`…) ganha nome 1 minuto
  depois da primeira interação (`TT_T_PRIMEIRO`, em segundos); se a tela ainda não mostrar do que
  se trata, tenta de novo 1 minuto depois da interação seguinte;
- **renomeações seguintes**: depois de 3 interações (`TT_INTERACOES_RENOMEAR`), ao mudar de pasta
  ou na revisão periódica. Sessões do Claude seguem o título da conversa.

O comando `^a`/“Nomear todas” faz isso sequencialmente nesta máquina e em todas as máquinas
cadastradas que estiverem acessíveis.

## Memória local dos agentes

Toda instalação do tt mantém um repositório local em `~/.local/share/tt/ai-memory`. Ele é
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

O tt consulta o GitHub a cada 12 h e avisa na tela quando sai versão nova; o menu de máquinas
oferece "⟳ Atualizar do GitHub". Para seguir um fork, ponha `fonte=<url do repositório>` no
`~/.config/tt/config`.

## Celular / tela pequena

Em telas com menos de 80 colunas ou 30 linhas (celular), a central abre em tela cheia, com
cabeçalho compacto (toque em "?" para todos os atalhos) e prévia escondida (toque em "prévia" ou
^/). O seletor rápido (toque no nome da sessão na barra) é o jeito mais prático de trocar de sessão
pelo toque.

## Desenvolvimento

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
