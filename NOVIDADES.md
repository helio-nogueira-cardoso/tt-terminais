# Novidades do tt-terminais

Uma seção por versão, da mais nova para a mais velha. `tt --novidades` mostra o que saiu desde a última
vez que você olhou; `tt --novidades --todas` mostra tudo. Também no menu administrar → 📰 Novidades do tt.

## v1.8.2 · 11/10/2026
- **"Clicar fora fecha" agora vale para as outras telas do tt**, não só para o painel de tarefas: central, seletor ☰,
  menus, agenda, notificações, fixadas, transferências, cópias, e-mail, atalhos… Com o interruptor ligado (menu ⋯ do
  painel → 🪟 **Janelas flutuantes**, `tt --flutuante`) e tmux 3.8+, toda tela que era `display-popup` abre como painel
  modal com o título na borda, fecha ao clicar na janela fora dela (ou `Esc`) e devolve o controle a quem a chamou. O
  modal das **pendências** (apt/sudo) e o **navegador** continuam popup, para um clique perdido não os derrubar. Em
  celular/tela estreita a maioria ocupa a janela toda: lá fecha com `Esc`. Desligado ou em tmux antigo nada muda.
  Quem já tinha o interruptor ligado passa a ter isso assim que o tmux da máquina chega ao 3.8.
- `ia-login --principal` tenta duas vezes falar com cada máquina antes de dar "sem resposta" (o celular de tela apagada
  perdia a primeira conexão fria).

## v1.8.1 · 11/10/2026
- **Versões de tmux misturadas deixam de quebrar o tt.** Medido com o 3.5a, 3.6b e 3.8: um cliente tmux 3.5a **não
  conversa** com um servidor 3.6 ou 3.8 (`server exited unexpectedly`); os outros pares funcionam. Num painel cujo
  PATH acha o tmux do sistema (o Debian trixie traz o 3.5a em `/usr/bin`), as listagens saíam vazias e os comandos falhavam em
  silêncio. Agora, dentro do tmux, o tt usa o binário do próprio servidor (achado por `$TMUX` → `/proc/PID/exe`, sem
  subprocesso quando o PATH já acerta) e o repassa em `TT_TMUX_BIN` ao `ia-rot --passar`, aos auxiliares em python,
  aos popups do e-mail e ao `exec`. A consulta ssh do menu de máquinas também usa o PATH do tt: com o servidor no 3.8
  ela contava 0 sessões.
- **Sessões `_nome` ficam ocultas de verdade**: antes só as marcadas como ponte (`@ponte`) saíam das listagens, então
  uma sessão `_tt-vigia` criada à mão aparecia na central e no seletor, ganhava nome do vigia e entrava na poda de
  vazias e paradas. Agora qualquer sessão que comece com `_` fica fora da central, do seletor, do mestre de obras, da
  renomeação e da poda.
- **O painel flutuante não conta como divisão da janela**: com o painel de tarefas aberto (tmux 3.8) a barrinha de título
  dos painéis ligava e o painel de baixo perdia uma linha (o Claude redesenhava a tela a cada abrir e fechar). O botão
  de sair também só considera painéis divididos.
- **Trocar a conta principal de uma máquina, rápido**: `ia-login --principal CONTA|E-MAIL` troca a principal (a de
  `~/.claude`, a do `claude` puro) de todas as máquinas do tt de uma vez; pula as que já estão nela, mostra o link e
  recebe o código como nos outros logins e confere o e-mail que entrou. Numa máquina só: `ia-conta adicionar principal
  [--email E]`. O login novo grava por cima do antigo e os perfis não mudam; com um Claude aberto na principal o tt
  **recusa** (ele guardaria o token antigo na memória e regravaria por cima do novo). Máquina com o `ia-login` de antes
  aparece como "sem suporte" no plano, sem abrir nada lá.

## v1.8.0 · 10/10/2026
- **Apelido e código das tarefas agora aparecem na lista do painel**, para você se referir a elas sem abrir nada: o apelido
  (`kito47`) vem antes do título de toda tarefa, as subtarefas mostram o número (`.2` = `kito47.2`) e, em painel largo (80+ colunas),
  o código completo fecha a linha. A busca do painel também acha pelo apelido ou pelo código. Os comandos seguem aceitando os dois.

## v1.7.9 · 10/10/2026
- Pendências 📦: quando a compilação do tmux 3.8 falha, a tela e o `pendencias.log` dizem em que etapa (download,
  configure ou make) e por quê; antes o log dizia só "rc=1" e o motivo sumia com o modal. E "ainda faltam
  ferramentas" passa a dizer quais (por exemplo "yacc (bison)") em vez do nome interno do grupo.

## v1.7.8 · 10/10/2026
- Corrigido: a pendência 📦 **tmux 3.8** não compilava em nenhuma máquina. O código do tmux 3.8 precisa do `bison`
  (yacc) para compilar, e o tt não o pedia: o `configure` parava em "yacc not found". Agora o bison entra junto com
  as outras ferramentas de compilação (no Termux também, sem administrador). Testado com o tmux 3.8 de verdade: o
  executável novo conversa com o servidor tmux que já está aberto, então nada muda nas sessões até você reabrir.

## v1.7.4 · 10/10/2026
- Pendências de instalação 📦: se a janela do modal fechar no meio da instalação, o `apt` termina o que começou em vez
  de morrer pela metade (o que podia deixar o dpkg travado), e o motivo do fechamento fica em
  `~/.cache/tt/pendencias.log` (SIGHUP, SIGTERM, Ctrl+C), junto com o fim da instalação. Antes o modal sumia sem
  deixar rastro.

## v1.7.2 · 10/10/2026
- Conversas das IAs: a troca vai em lotes de 100 conversas. Na primeira troca com o celular a rede caiu no meio
  (1,3 GB pelo relay) e o pacote inteiro se perdia; agora cada lote entregue já vale e a volta seguinte
  continua do que faltou. Sobras de uma recepção interrompida são limpas sozinhas.

## v1.7.1 · 10/10/2026
- Novo diagnóstico de lentidão ao trocar de sessão: crie o arquivo `~/.config/tt/trace` (`touch`) e os cliques
  e trocas passam a gravar cada linha executada, com a hora, em `~/.cache/tt-trace.log` (zera acima de 5 MB).
  Apague o arquivo para desligar. Vem desligado.

## v1.7.0 · 10/10/2026
- A numeração das versões agora é hierárquica: `MAIOR.MENOR.PATCH`, e quando um número da esquerda sobe os da direita voltam a zero
  (esta é a 1.7.0, depois da 1.6.277). Antes o último número só crescia (era a contagem de commits). O que decide qual versão é
  mais nova entre as máquinas não mudou.
- Toda tarefa e subtarefa ganhou um **código** único (igual em todas as máquinas) e um **apelido** curto, como `kito47`, para
  você e a IA falarem da mesma tarefa. Aparecem só no cartão da tarefa, no menu ⋯ e em `tt --tarefas`, sem encher a lista.
  Os comandos aceitam apelido, código ou `kito47.2` (a 2ª subtarefa).
- Compartilhar tarefa por e-mail agora atualiza em vez de duplicar: `tt --tarefa-email ID` gera o e-mail com o código; quem
  recebe cria a tarefa com o mesmo código, ou, se já a tem, vê uma proposta de atualização (↻) na aba Entrada e aprova ou recusa.
- Novo registro de trabalho: `tt --tarefa-log` anota na descrição o que a sessão fez, quando, como, qual agente/modelo/esforço,
  máquina, conta, tokens e custo estimado em reais; `tt --tarefa-historico` mostra tudo com o total.
- O vigia (e cada atualização) reforça a skill `tt-terminais` e as regras de tarefas em todas as IAs de todas as máquinas
  (Claude, Codex e Kiro, inclusive no celular).

## v1.6.280 · 10/10/2026
- **Copiar com o mouse agora exige segurar Alt**, em qualquer painel: Alt+arrastar copia, Alt+duplo clique copia
  a palavra (ou o link inteiro), Alt+triplo clique copia a linha. Sem Alt, arrastar e clicar vão ao programa
  (ou ao modo cópia) e nada é copiado, para não gerar cópias por acidente. Shift+arrastar continua sendo a
  seleção do próprio terminal. Ctrl+clique num link segue abrindo o link.

## v1.6.279 · 10/10/2026
- Nova skill para os agentes de IA, `celular-android`: como operar um celular Android montado com o tt
  (Termux, Debian no proot, shell do sistema sem root pelo adb do próprio aparelho ou pelo Shizuku, o
  Tasker religando tudo depois do reboot, o Wi-Fi que só é preciso uma vez por boot e as receitas de
  tela). O tt a instala sozinho nos agentes do PC e do Debian do celular.
- As skills e os guias ficaram genéricos: exemplos com nomes neutros no lugar de máquinas, contas e
  pastas de uma pessoa, para qualquer um reaproveitar.

## v1.6.278 · 10/10/2026
- Sincronização das tarefas com menu: ⋯ da barra → 🔄 (ou botão direito no 📋 → 🔄, ou
  `tt --tarefas-sync`). Escolha P2P (padrão), **Ambos** (P2P e um repositório git seu, com o histórico
  de todas as mudanças), só git ou desligada; o endereço é conferido antes de gravar, e a tela mostra a
  última troca ou o motivo da falha. Uma falha que dure mais de 1 h avisa na faixa.
- O modo git das tarefas funciona de verdade: o primeiro envio a um repositório vazio levava um arquivo
  vazio; uma máquina que ficava sem rede enquanto outra enviava parava de trocar para sempre, sem
  avisar; e tarefa vinda por P2P só chegava ao repositório depois de uma mudança local. Agora a volta se
  refaz sozinha, sem perder nada.
- No celular, tocar no `+N ▾` das fixadas, no 🔔 e em itens como renomear e nova tarefa não fazia nada:
  esses popups tinham largura fixa maior que a tela (63 colunas) e o tmux recusava. Agora encolhem até
  caber.

## v1.6.277 · 10/10/2026
- Novo: as conversas do Claude Code, do Codex e do Kiro CLI ficam iguais em todas as suas máquinas. O
  `/resume` do Claude (e o `codex resume`, e o `kiro-cli chat --resume`) de qualquer máquina, em qualquer
  conta, acha a conversa que começou em outra, na pasta equivalente: a home é traduzida
  (por exemplo `/home/ana` ↔ `/home/asilva` ↔ o `/root` do Debian do celular). Vem ligado; o vigia troca as
  conversas a cada 30 min. `tt --sessoes-ia` mostra o estado, `tt --sessoes-ia agora` troca na hora e
  `tt --sessoes-ia off` desliga nesta máquina. Também no menu administrar → 🧠.
- Nada se perde: conversa continuada em duas máquinas fica com a versão mais nova nas duas, e a outra é
  guardada em `~/.local/state/tt/sessoes-ia/conflitos/`. Conversa aberta agora espera a próxima volta.
- Os testes do tt não falam mais com o seu tmux: rodar a suíte numa máquina em uso não mostra mais avisos
  de teste por cima da barra (como o "✓ 2 itens de A → …" que cobriu a faixa de notificações).
- Marco v1.6: esta versão fecha o pacote que trouxe as pendências de instalação multiplataforma (com o tmux
  3.8), as demandas por e-mail e a aba Entrada, o botão de IA nas tarefas, o painel de tarefas novo e
  flutuante, a hora confiável, o Carbonyl de volta numa subjanela e, agora, as conversas das IAs em todas
  as máquinas.

## v1.5.275 · 10/10/2026
- O chip 📥 da barra (demandas por e-mail esperando aprovação) agora abre o painel de tarefas direto na aba
  **Entrada**, onde você aprova ou recusa. Antes ele abria o painel no filtro de sempre e a Entrada ficava
  escondida em outra aba. Se você aprovar ou recusar tudo, o painel não abre mais numa Entrada vazia.
- Corrigido: em contas de e-mail novas, ou de pouco volume, as demandas por e-mail nunca eram processadas
  (o arquivo de mensagens já vistas nascia vazio e o filtro não deixava passar nada).
- Nova pendência de instalação 📦 **tmux 3.8**: o painel de tarefas flutuante (clicar fora fecha) e outros
  recursos pedem o tmux 3.8, e os pacotes do Debian/Ubuntu ficam no 3.5/3.6. O tt baixa o código oficial
  (confere o sha256), compila na sua pasta e liga o executável — sem tocar no sistema, só com o administrador
  para as ferramentas de compilação. As sessões abertas não são tocadas: o 3.8 vale no próximo servidor tmux
  (depois de fechar todas as sessões ou reiniciar). O vigia avisa enquanto o tmux estiver abaixo do 3.8.

## v1.5.274 · 10/10/2026
- Painel de tarefas mais limpo: o topo agora tem duas linhas fixas. Na 1ª, as abas numa faixa só; na 2ª,
  as ações mais usadas (+ Nova, ↳ Sub, ✎ Editar, ◷ Prazo, ✦ IA) e, alinhados à direita, ▦ calendário,
  ? ajuda e ⋯ Mais, que reúne o resto (feita, descrição, prioridade, repetir, mover, apagar). Os atalhos
  de teclado não mudaram. Em tela estreita os botões encolhem para só o ícone em vez de quebrar.
- O triângulo ▸ volta a aparecer em toda tarefa, pela uniformidade. Sem subtarefa ele fica apagado e não
  abre nada.

## v1.5.273 · 10/10/2026
- O Carbonyl (navegador no terminal) volta a abrir numa subjanela, com 90% x 85% da tela, como os outros
  popups grandes. Desde 07/10 ele tomava a tela inteira. Em tela pequena (celular) continua em tela cheia.
## v1.5.271 · 10/10/2026
- Corrigido: no Debian do proot do Termux (o Linux de dentro do celular), a detecção da plataforma e a
  instalação de pacotes falhavam — o proot se anuncia como "PRoot-Distro" e não tem `/dev/fd`. Testado de
  verdade no celular: agora ele é reconhecido e o `apt` roda com a opção certa para o proot.

## v1.5.270 · 10/10/2026
- Pendências de instalação completas: `tt --pendencias` mostra, num lugar só, tudo o que o tt pode usar
  nesta máquina — ferramentas básicas, fzf, tmux, e-mail (aerc, mbsync, w3m, vim, dicionário, plugin XOAUTH2),
  Chrome, Carbonyl e as bibliotecas deles, clipboard, notificações, Termux:API, pv, mosh e o nomeador local —,
  com ✓/✗ e o que falta. Menu administrar → 📋 abre essa tela; 📦 instala o que faltar.
- Chrome e Carbonyl agora estão no mesmo modal 📦. Antes só 6 das ~25 bibliotecas que eles pedem eram
  reconhecidas: num Linux enxuto o tt dizia "tudo em ordem" e o navegador não abria. Agora todas são
  instaladas (testado num Debian vazio: os dois navegadores sobem).
- Funciona em Debian/Ubuntu/WSL, Fedora/RHEL, openSUSE, Arch, Alpine, Void, macOS (Homebrew), Termux, Debian
  no proot do Termux e FreeBSD/OpenBSD/NetBSD, no `instalar.sh` e no modal. Usa `sudo`, `doas` ou `su` (nenhum
  no root, no Homebrew e no Termux).
- Instalação mais robusta: se um pacote não existe na sua distro, os outros continuam; o índice vazio é
  atualizado sozinho; espera a trava do apt; no proot do Termux o apt não trava; senha errada para na
  primeira tentativa. Depois o tt confere cada item (✓/✗); o que falhar volta a avisar em 7 dias, e o
  registro fica em `~/.cache/tt/pendencias.log`. `tt --pedir-sudo --sim` instala tudo sem perguntar.
- Corrigido o 📧 vermelho ⚠ da conta Google com OAuth no Termux: o `mbsync` de lá não sabe SASL, então o
  tt compila um com SASL na sua pasta. O erro do sync agora aponta a pendência que o resolve, e o menu
  do 📧 oferece instalar o que falta.
- fzf antigo (Ubuntu LTS, Debian estável): o tt baixa o fzf oficial para a sua pasta, sem sudo.
- O aviso 📦 dura 6 h (era 1 h) e volta em 12 h, em vez de passar despercebido de noite.
- macOS: `instalar.sh` instala o bash atual pelo Homebrew e recomeça; a cópia (clipboard) usa o `pbcopy`.

## v1.5.269 · 10/10/2026
- Novo: demandas por e-mail. Cadastre remetentes autorizados (menu ⋯ do painel → ✉ Demandas por e-mail, ou
  `tt --demanda-autorizar EMAIL [etiqueta]`); o cadastro vale em todas as suas máquinas. Um e-mail deles com
  `[tt] título @sex 14h !alta #tag` no assunto vira uma demanda pendente (linhas `- texto` do corpo viram
  subtarefas, o resto vira a descrição) na nova aba **Entrada** do painel de tarefas — com um chip 📥 na
  barra e um aviso. ✓ aprova (vira tarefa aberta, com as subtarefas) e ✕ recusa. Por segurança só vale se o
  provedor do e-mail autenticou o remetente (dmarc/dkim/spf); por remetente dá para exigir um segredo no
  assunto (`[tt:segredo]`) ou aceitar sem checar. Vale para contas com sync local.

## v1.5.268 · 10/10/2026
- Tarefas: só quem tem subtarefas mostra o triângulo (▸/▾) e abre ao clicar. Sem subtarefas não há o que
  abrir: o clique só seleciona, e o menu da tarefa segue no botão direito, em ⋯ Mais ou em `Ctrl+O`.
- Novo (opcional, vem desligado): painel de tarefas flutuante que fecha ao clicar fora. Precisa de tmux 3.8
  ou mais novo; liga em menu ⋯ do painel → 🪟 (ou `tt --flutuante on`). Ligado, o painel é da janela: todo
  aparelho que olha a janela o vê (o popup de hoje só aparece onde você clicou). Aberto, a barra de status
  fica inerte (o tmux bloqueia): feche clicando fora, com Esc ou com `tt --tarefas` de novo. Com tmux
  mais velho o toggle avisa e o painel segue como popup.
- Novo: hora confiável. O tt mede o desvio do relógio da máquina contra a internet (Cloudflare, Google e
  Apple; a cada 6 h, só o vigia) e usa relógio + desvio nas tarefas (prazo, "hoje", lembretes, ordem das
  edições) e na data/hora da barra. Sem rede ou sem medida, vale o relógio da máquina. `tt --hora` mostra
  o desvio; `tt --hora --sincronizar` mede agora; `hora_sync=0` no config desliga.
- Corrigido: tarefa que se repete (diária, semanal, mensal) avançava o prazo errado ao ser concluída — a
  semanal andava 14 horas em vez de 7 dias e a diária mudava a hora. Agora avança o período inteiro e
  mantém a hora.

## v1.5.267 · 09/10/2026
- Corrigido: a tela de novidades (📰) piscava e fechava; agora fica aberta até você apertar `q`.
- Pendências de instalação: quando está tudo em ordem, a tela diz "✓ Tudo em ordem" e espera uma tecla,
  em vez de piscar e fechar.
- Corrigido: depois de instalar o plugin XOAUTH2, contas Gmail com senha de aplicativo falhavam com
  "Invalid credentials": o plugin agora só vale para as contas OAuth.

## v1.5.266 · 09/10/2026
- Novo: esta tela de novidades. O tt avisa na faixa (📰) quando atualiza; o clique abre aqui.
- O aviso dos agentes ("🤖 sessão · …") agora leva ao painel certo mesmo se a sessão foi renomeada depois.

## v1.5.264 · 09/10/2026
- Pendências de instalação: o plugin XOAUTH2 (contas Google com OAuth) agora instala de
  verdade — o apt recebia os pacotes como um nome só.
- Se a instalação falhar, o modal espera uma tecla e deixa o erro na tela.

## v1.5.262 · 09/10/2026
- Pendências de instalação ganharam quatro respostas: instalar agora, selecionar, mais tarde (volta em
  1 dia) e não instalar (nunca mais avisa). O vigia põe um aviso 📦 na faixa; clicar abre o modal.
- Quem disse "não" pode mudar de ideia: menu administrar → 📦 Pendências de instalação.
- Conta Google com OAuth e sync local: o tt compila sozinho o plugin XOAUTH2 do SASL na sua pasta (só o
  compilador pede administrador). Resolve o 📧 vermelho ⚠ de contas assim.

## v1.5.259 · 09/10/2026
- A faixa das janelas tem cor própria (um tom acima da margem), então as quatro linhas se distinguem só
  pelo fundo.
- O letreiro roda a 6 quadros por segundo (até 10 com `ticker_fps`), uma coluna por quadro; os
  processos auxiliares ficaram bem mais leves (~4 MB cada em vez de ~12 MB).
- Fechar telas é igual em todo lugar: mensagens fecham com qualquer tecla (Esc inclusive); abrir uma tela
  do tt com o e-mail na frente solta o popup do e-mail em vez de deixá-lo preso por baixo. Tabela no
  README ("Fechar telas e popups").

## v1.5.257 · 09/10/2026
- A barra voltou a ser só fundo: sem réguas finas. Margem vazia no topo (onde caem as mensagens do tmux),
  janelas, fixadas e a faixa de notificações, coladas.
- A central de notificações diz o dia (Hoje, Ontem ou dd/mm) e os títulos dos popups não se repetem.
