# Novidades do tt-terminais

Uma seção por versão, da mais nova para a mais velha. `tt --novidades` mostra o que saiu desde a última
vez que você olhou; `tt --novidades --todas` mostra tudo. Também no menu administrar → 📰 Novidades do tt.

## v1.15.1 · 13/10/2026
- **📈 Seta da variação não cobre mais o número.** Nas cotações do letreiro, o ▲/▼ vinha colado no percentual (`▲0,5%`), e muita fonte desenha esses triângulos de borda a borda da célula, ou até além dela: a seta ficava em cima do algarismo, às vezes por cima dele. Agora há um espaço entre os dois (`▲ 0,5%`). Variação zero passa a aparecer como `= 0,0%`: com o espaço, o `•` antigo se confundiria com o separador entre os itens. Quem usa `{seta}` e `{pct}` num modelo próprio continua montando do seu jeito.

## v1.15.0 · 13/10/2026
- **☑ Selecionar tudo no e-mail.** Um botão novo (ou `Ctrl+a` na lista) seleciona todas as mensagens da pasta aberta; com uma busca ou o filtro de não lidas ligado, só as encontradas. Daí ✕ Apagar, ▤ Arquivar e 📁 Mover agem em todas de uma vez. De novo, desmarca.
- **⚡ E-mail em lote, para milhares.** O botão ⚡ (ou botão direito no 📧 → Em lote, ou `tt --email-lote`) escolhe a conta, a pasta e uma busca (`todas`, `nao-lidas`, `de:loja@x.com`, `assunto:"fatura"`, `antes:2024-01-01`, `maior:5m`; no Gmail também a busca do próprio Gmail, `gmail:"older_than:1y"`), mostra quantas mensagens são e uma amostra, e apaga, arquiva, move ou marca como lidas **direto no servidor**, em blocos, com progresso.
  - Só as mensagens contadas entram: o que chegar durante a operação fica.
  - Apagar de vez, ou mexer em 1000 ou mais, pede que você digite o número de mensagens.
  - O espelho local acompanha sozinho em seguida.
- **✕ Apagar funciona em toda conta.** Antes, só o Gmail tinha o apagar ajustado. Agora toda conta com lixeira manda o apagado para ela, e dá para recuperar; na lixeira e no spam, apagar é de vez. Numa conta sem lixeira, a pergunta diz que apaga de vez.
- **📥 Tarefa mandada por e-mail não se perde mais em quem acabou de instalar.** Se a pessoa ainda não tinha autorizado nenhum remetente, o tt dela nem lia os e-mails `[tt]`. E, quando ela autorizava alguém depois, os que tinham mais de 1 dia eram dados como vistos. Agora o e-mail fica à espera, chega um aviso no 🔔 ("Tarefa por e-mail de … aguardando sua autorização") e, ao autorizar (`tt --demanda-autorizar EMAIL`), ela entra na aba Entrada.
- **🩺 A checagem confere a caixa de entrada de tarefas.** O `tt --checar` e o agente de cada atualização olham todo o caminho: conta com espelho local, sync em dia, e-mails `[tt]` esperando autorização e remetentes ignorados por falha de autenticação. O agente nunca autoriza um remetente sozinho: diz quem está esperando e o comando.
- **🩺 O tt confere os comandos do e-mail.** `tt --email-conferir` (menu do 📧 → 🩺, e também a checagem que roda a cada atualização) acusa e conserta o caso em que apagar não funcionava. A lixeira da conta pode ser desconhecida (no Gmail, o ✕ só arquivava), pode faltar no espelho local, ou os comandos da conta podem estar desatualizados. Para consertar, o tt descobre a lixeira no servidor (em qualquer idioma), traz a pasta para o espelho e refaz os comandos.

## v1.14.0 · 13/10/2026
- **🩺 Cada atualização agora se confere sozinha, e o que estiver errado é corrigido.** Quando uma máquina instala uma versão nova do tt, o vigia lança um agente de IA pelo rotador (a conta com mais folga). Ele confere o vigia, a atualização, a separação entre o pacote e a sua configuração, o espelho de cada conta de e-mail, o sync das tarefas, a malha, as regras dos agentes, as pendências, a hora e as conversas das IAs. Também testa na prática o que a versão nova trouxe e **corrige o que for desta máquina**, guardando cópia do que mexer na sua configuração. O que depende de você (login vencido, sudo com senha) vem com o comando pronto.
  - Defeito no código do tt: na máquina de desenvolvimento, o agente deixa a correção num commit pronto (sem publicar); nas outras, cria uma tarefa com o diagnóstico.
  - No fim chega um aviso no 🔔 com o resumo (ok, aviso, falha, corrigido); o clique abre o relatório.
  - `checagem_auto=0` no config desliga. Sem conta de IA livre, tenta de novo em 30 min, até 3 vezes; no celular ou sem agente, fica o relatório da conferência sem IA.
- **`tt --checar`** confere tudo isso na hora, sem IA, e diz a correção de cada item. **`tt --checar-agente`** abre uma rodada com o agente quando você quiser; **`tt --checar-ver`** mostra o último relatório. Também no menu administrar → 🩺.
- **Tudo num lugar só:** `~/.local/state/tt/checagens/` tem o `historico.log` (uma linha por rodada) e uma pasta por rodada com o relatório, o que o agente recebeu e a saída dele (ficam as últimas 20).
- **📦 Pacote para entregar: `tt --checar-handoff`.** Quando quem mantém o tt pedir, gere um `.tar.gz` (na pasta de recebidos) com as rodadas, o fim dos logs do tt e o estado atual. Senhas, tokens e chaves são mascarados, e-mails viram `f***@dominio`, e nada de `~/.secrets` entra. O comando lista o que foi no pacote para você conferir antes de enviar.

## v1.13.0 · 13/10/2026
- **⟳ Versão nova chega em até 5 minutos.** O vigia agora faz uma sonda leve a cada 5 min (15 no celular): pergunta ao GitHub só qual é a versão publicada, sem baixar nada, e busca e instala apenas quando ela mudou. Antes era um download completo a cada 30 min, e uma versão nova levava até meia hora para chegar. A busca completa continua de 6 em 6 h, por segurança.
- **Mais esperto para decidir o que é "mais novo".** O vigia compara pelo histórico: instala quando a versão publicada contém a instalada; não mexe numa máquina de desenvolvimento que está à frente; e não troca uma versão divergente de número maior (rebaixaria).
- **Por que não atualizou? `tt --atualizacao-estado`** mostra a versão instalada e a publicada, se o vigia está vivo, a última consulta, a fonte (avisa se o `fonte=` do config aponta para outro repositório) e, se estiver falhando, há quanto tempo e por quê (rede, git, pacote). Depois de 3 falhas seguidas chega um aviso no 🔔 com o motivo.
- **Commits locais não travam mais a máquina de desenvolvimento.** `tt --atualizar` num clone com commits que o publicado não tem reaplica esses commits sobre a versão publicada (rebase). Se der conflito, eles ficam guardados num ramo `local/<data>` e o clone segue o publicado: nada se perde. Arquivo versionado mudado e não gravado faz recusar, com a lista.
- **Configuração local separada do versionado.** Linhas acrescentadas só nesta máquina ao `.gitignore` do clone vão para `.git/info/exclude` (vale igual, não é versionado). `tt --repo-checar` explica o que no clone trava a atualização; `--corrigir` faz a separação.

## v1.12.2 · 13/10/2026
- **📰 Clique nas notícias do letreiro volta a abrir.** Quando o tmux trocava o processo que desenha o letreiro (ao mudar o tamanho da tela, trocar de sessão, abrir uma janela do tt…), o processo antigo, ao sair, apagava o mapa que o clique usa para saber qual item está sob o mouse. Daí em diante o clique não fazia nada até a tela mudar de tamanho de novo. Agora quem sai não apaga o mapa, e o letreiro o refaz se ele sumir.
- **As manchetes de fábrica (g1 e BBC) também abrem a matéria.** Só as fontes de notícias do catálogo tinham o link de cada item; clicar numa manchete da fonte `noticias` apenas pausava a faixa.
- **📋 Cópias chegam ao celular pelo mosh.** O tmux mandava cada cópia ao terminal com a seleção vazia (OSC 52 `52;;…`), e o mosh descarta esse formato: copiar no PC visto pelo Termux via mosh não chegava ao Android. Agora a cópia sai com a seleção `c`, que o mosh repassa e que o Windows Terminal, o Termux e o xterm também entendem. Vale para os terminais que se conectarem depois da atualização.
- **📰 Esta tela ficou mais legível.** **Negrito** e `código` aparecem com estilo, sem os asteriscos e as crases; subitens têm recuo; e o texto quebra na largura da janela, alinhado ao item (até 100 colunas, para a leitura não virar uma faixa).
- **✉ `tt --demanda-autorizar`** não repete mais a etiqueta na confirmação (saía "#vendasvendas" no lugar de "#vendas").

## v1.12.1 · 13/10/2026
- **📥 Tarefa enviada por e-mail antes de você autorizar o remetente não se perde mais.** O tt marcava como visto todo e-mail da caixa de entrada; um `[tt]` que chegava antes de o remetente estar autorizado nunca mais era lido. Agora ele fica à espera e vira demanda (aba Entrada) assim que o remetente é autorizado, aqui, pela tela de demandas ou vindo de outra máquina. O log da conta (`~/.local/state/tt/email-sync/<conta>.demandas.log`) diz "aguardando autorização de=…" com o comando para autorizar.
- **📥 Tarefa recebida por e-mail chega inteira.** A descrição era cortada em 8 mil caracteres (400 linhas) e o texto de cada subtarefa em 200; um handoff completo chegava pela metade. Não há mais corte.

## v1.12.0 · 13/10/2026
- **📦 Espelho local do e-mail agora é pendência obrigatória.** Toda conta de e-mail do tt sem espelho local (`sync_local`) vira uma pendência de instalação: "espelho local do e-mail (contas)". É do espelho que saem o aviso de e-mail novo, o contador do 📧 e os e-mails `[tt]` que viram tarefa (tarefas compartilhadas, demandas e atualizações); conta só IMAP não gera nada disso.
  - Aceitar instala o que falta (mbsync e, para conta Google/OAuth, o SASL e o plugin XOAUTH2 na sua pasta) e liga o espelho de cada conta; a primeira sincronização roda em segundo plano.
  - Dá para adiar, mas não para recusar de vez: "não instalar" vale como "mais tarde" e o tt pergunta de novo no dia seguinte (o 📦 do vigia avisa).
- **📧 "check-mail: no command specified" corrigido.** Numa conta com espelho local o aerc lê do disco, e o F11, o ⟳ e o abrir pelo aviso de e-mail novo mandavam `:check-mail` sem que a conta tivesse o comando que traz o INBOX. Agora toda conta espelhada tem `check-mail-cmd` (o `tt --email-sync` da conta, com até 120 s), e a atualização conserta sozinha as contas que já estavam espelhadas.

## v1.11.1 · 13/10/2026
- **🔔 Central de notificações mais limpa, com rolagem e botões certeiros.** Cada linha tinha fundo colorido e o aviso selecionado quase não aparecia (só um traço fino à esquerda): a roda do mouse movia uma seleção invisível, parecendo que não rolava, e os botões agiam num aviso que você não via. Agora só a etiqueta "● Não lida"/"✓ Lida" é colorida, e **o aviso selecionado fica destacado de ponta a ponta**; a roda anda pela lista e o clique numa linha mostra qual aviso os botões vão usar.
- **Um aviso por linha:** os longos não quebram mais em 2 ou 3 linhas; são cortados com "…", e **a prévia embaixo** mostra o aviso selecionado inteiro, quando chegou, de onde veio e o que o ⏎ faz (ex.: "abre o e-mail na mensagem nova"). O ↗ (tem destino) fica numa coluna antes do texto, sempre à vista.
- **Botões sem demora:** cada clique redesenhava a lista abrindo ~100 processos (`date` para cada data); com 30 avisos, uma ação levava ~170 ms, e muito mais com o tmux ocupado. Agora são ~40 ms.

## v1.11.0 · 13/10/2026
- **🔔 Central de notificações com botões de verdade.** A linha de atalhos `⟦^u Não lidas⟧ ⟦^a Todas⟧ …` saía cortada para fora da janela e parte dela não funcionava (o filtro de não lidas não filtrava). No lugar dela, o alto da central agora tem:
  - **abas de filtro clicáveis**, com a contagem: **Todas · Não lidas · Lidas** e, quando houver avisos delas, **Agentes · E-mail · Tarefas**;
  - **uma barra de botões** no estilo da do e-mail: **↗ Abrir**, **◐ Lida/não lida**, **✓ Ler todas**, **✕ Apagar** e **🧹 Limpar lidas** (este pergunta antes, no próprio alto da central, e a exclusão vale em todas as máquinas).
- **Cabe em qualquer tela:** sem espaço, os botões ficam com rótulo curto e depois só com o ícone, e as abas de Agentes/E-mail/Tarefas viram 🤖 📧 📋. No celular de 63 colunas tudo cabe numa linha.
- **Teclado igual aos botões:** ⏎ abre, Espaço marca lida/não lida, Tab/Shift+Tab trocam a aba, `^u` não lidas, `^a` todas, `^d`/Del apaga, `^r` limpa as lidas, `^l` lê todas, Esc/q fecham. Cada ação mostra um retorno curto no alto (ex.: "✓ 3 notificações marcadas como lidas"). Um aviso sem destino não fecha mais a central ao ser aberto: fica marcado como lido.

## v1.10.11 · 12/10/2026
- **📦 A pendência "tmux 3.8" fecha depois de instalada.** O `tt` conferia a versão pelo tmux do PATH, que acompanha o servidor em execução (ainda o 3.6 até reiniciar); então, mesmo com o 3.8 já compilado na sua pasta, a pendência continuava aparecendo e a instalação terminava com "ainda falta". Agora ele também olha o 3.8 compilado em `~/.local/share/tt-tmux`: se está lá, a pendência some. O 3.8 vale a partir do próximo servidor tmux, como sempre.

## v1.10.10 · 12/10/2026
- **🌐 Link abre na máquina em que você clicou.** Vendo pelo book-hl uma sessão do PC (ou o e-mail do PC), escolher "Navegador padrão do sistema" ou o Chrome interno abria o navegador no PC, longe da sua tela. Agora o tt percebe pela ponte de onde vem a tela e abre lá; se aquela máquina não responder, abre onde está, como antes. Carbonyl e "só copiar" continuam no próprio terminal.

## v1.10.9 · 12/10/2026
- **🔧 O vigia não fica mais preso girando a CPU.** No bash 5.3 (PC e book-hl), um `wait` sem pids dentro de um subshell gira a 100% de CPU para sempre quando o shell de cima tem um trabalho em 2º plano ainda vivo. O vigia caía nisso ao procurar sessões vazias e parava de trabalhar (fechar sessões, sincronizar, atualizar) por horas, com um núcleo inteiro ocupado. Agora cada espera aguarda só os processos que ela mesma lançou.

## v1.10.8 · 12/10/2026
- **⚡ Cliques bem mais rápidos, sem mudar o que eles fazem.** Medido no WSL com um painel redesenhando a tela sem parar: 📌 fixar de ~710 para ~260 ms; marcar uma tarefa no painel de ~790 para ~195 ms; atualizar a barra de ~580 para ~150 ms; abrir a central de ~480 para ~200 ms; um clique dentro de um painel sem link chega ao programa em ~14 ms (eram ~50).
- **A barra numa ida só ao tmux:** cada segmento que mudava era gravado num pedido separado, e cada um redesenhava a tela inteira de todos os clientes. Agora vai tudo junto, num redesenho só.
- **WSL sem a demora dos comandos ausentes:** o PATH do WSL inclui as pastas do Windows, e perguntar por um comando que não existe custava ~35 ms; a barra fazia isso 8 vezes a cada atualização. As pastas do Linux seguem conferidas na hora; a resposta das do Windows fica guardada por 10 min.
- **O painel de tarefas e a agenda não esperam a barra:** marcar, criar ou editar recarrega a lista na hora, e a barra se atualiza logo depois, em segundo plano, sempre terminando no estado certo. Pela linha de comando continua como antes.
- **Clique dentro de um painel sem link vai direto ao programa:** antes de procurar um link (um python de ~30 ms a cada clique), o tmux confere se há algum endereço na tela.
- **Menos processos em todo clique:** a partida de cada `tt` caiu de ~20 para ~13 ms; hora, configuração, versão, chaves das fixadas, contas de e-mail e avisos são lidos pelo próprio bash; menus montam os itens medindo a tela uma vez; uma fixada de outra máquina abre com uma ida por ssh a menos; abrir ou fechar uma janela flutuante não dispara mais 3 ou 4 processos ao mesmo tempo.

## v1.10.7 · 12/10/2026
- **Envio para a pasta pessoal pede confirmação de propósito:** se o destino é a pasta pessoal e não a de Recebidos, a confirmação avisa e só o `s` envia (⏎ não basta). Evita o arquivo "concluído" que não aparece em Recebidos.

## v1.10.2 · 12/10/2026
- **Central de notificações mais clara e prática:** fundo âmbar e “● Não lida” identificam avisos pendentes; fundo azulado e “✓ Lida” identificam os abertos. `^u` filtra as não lidas, `^a` limpa o filtro, `^d` apaga a selecionada e `^r` apaga todas as lidas. As exclusões propagam lápides pela rede para não ressuscitarem em outra máquina.

## v1.10.1 · 12/10/2026
- **Sininho igual em todas as máquinas:** avisos e marcas de leitura se propagam por P2P; o contador mostra todos os avisos vigentes não lidos, não só os recém-chegados ou os avisos de agentes. Máquinas que ficaram offline convergem quando voltam.
- **E-mail e central de notificações não se empilham:** uma reserva por cliente bloqueia a abertura de uma segunda central ou do e-mail sobre ela. A abertura direta do Carbonyl deixou de ser confundida com um seletor temporário; ao fechá-lo, o foco volta ao e-mail.
- **Samsung Internet no seletor do Android:** o tt direciona links ao pacote Samsung Internet no S23, sem depender do navegador padrão.
- **Aviso de agente abre a máquina de origem:** a ação sincronizada leva à sessão da máquina onde o aviso nasceu.

## v1.10.0 · 12/10/2026
- **⚡ Partida rápida: cada clique, tecla e recarga ficou cerca de 100 ms mais rápido.** O `tt` tem ~850 KB, e o bash lia o arquivo inteiro (de 60 a 90 ms) toda vez que a barra, um menu ou um painel o chamava. Agora a instalação gera um núcleo (~160 KB) e as funções são lidas na primeira vez em que são usadas: `tt --versao` caiu de 138 para 37 ms; a lista e o cabeçalho das tarefas, de 157 e 220 para 67 e 97 ms. A saída é a mesma, e o núcleo só passa a valer depois de conferido contra o arquivo inteiro; qualquer diferença, o tt segue lendo o arquivo todo, como sempre. `tt --rapido` mostra o estado (`gerar`, `remover`); `TT_COMPLETO=1` desliga.
- **AGENTS.md único para todas as IAs:** as instruções globais (as suas e as regras do tt) moram num arquivo só, `~/.agents/AGENTS.md`. O tt impõe isso sozinho a cada instalação e a cada ~5 min: o `CLAUDE.md` de cada conta do Claude e o `AGENTS.md` do Codex viram link para ele, o Kiro recebe uma cópia gerada (`steering/agentes.md`), e o que você tinha escrito em cada um foi juntado lá, sem repetir parágrafo (o original fica em `~/.local/state/tt/agentes-backup/`). Para mudar uma instrução global, edite `~/.agents/AGENTS.md`.
- **Claude lê o AGENTS.md dos projetos sempre:** nas contas extras do `ia-conta`, o `~/.claude/CLAUDE.md` fazia o Claude ignorar o `AGENTS.md` de qualquer projeto dentro de `~` e carregar as regras do tt duas vezes. Agora o tt liga a opção `claude-md-and-agents-md` do Claude, e as regras chegam uma vez só.
- **Travas abandonadas das contas do Claude são apagadas:** o tt gravava arquivos dentro de `claude-contas/<conta>.lock` como se fosse uma conta, e isso mantinha a trava com cara de nova.
- **`ia-conta codex` e `ia-conta kiro` abrem o Codex e o Kiro** (com os argumentos dados), em vez de responder "não é conta do Claude".
- **E-mail e menus abertos por cima não dão mais nome à sessão:** com as janelas flutuantes ligadas, o e-mail, os menus, as tarefas e a própria central abrem como um painel por cima da sessão, e o tmux passa a tratá-lo como o painel ativo dela: o nomeador lia a tela do e-mail e dava à sessão o assunto de um e-mail. Agora o nomeador, a lista e a prévia da central e o mestre de obras olham a sessão de baixo, e o vigia não renomeia uma sessão enquanto há uma janela do tt aberta por cima dela.
- **Painel de tarefas mais ágil:** cada tecla chamava o tt três vezes (a ação, a lista e o cabeçalho); agora a ação já entrega a lista e o cabeçalho prontos e o painel só os lê: por tecla, de ~450 ms (antes da partida rápida) para ~60 ms. Quando o resultado depende de algo que acontece depois (um editor aberto, uma busca em curso), segue como antes.
- **A central aparece na hora:** ao abrir, ela mostra a última lista desta máquina se as sessões e os painéis ainda são os mesmos (uma pergunta ao tmux confere) e atualiza em seguida; aqui, de 1,1–1,3 s para 0,14–0,2 s até a lista aparecer.
- **Central mais rápida:** a lista de sessões de cada máquina pergunta ao tmux uma vez, em vez de cerca de cinco vezes por painel, e lê as telas em paralelo. O servidor do tmux atende um pedido por vez, atrás dos redesenhos dos painéis: com uma IA despejando a tela, a lista daqui caiu de 2,6–20 s para 2,2–4,3 s. O vigia (uma consulta por volta para todas as sessões), a barra (24 → 9 consultas) e o mestre de obras seguem o mesmo princípio.
- **Todas as máquinas ao mesmo tempo:** puxar fixadas, tarefas, contas, demandas e fontes do letreiro, a malha, `tt --sincronizar` e `tt --saude` falam com todas as máquinas juntas: o tempo é o da mais lenta, não a soma.
- **Rótulo de painel com `|`** aparecia cortado na central; agora sai inteiro.

## v1.9.4 · 12/10/2026
- **Painel de e-mail sem cascata:** cliques repetidos ou simultâneos não abrem popups aninhados nem anexos duplicados à sessão do aerc.
- **Aviso abre a mensagem:** o clique agora confere a caixa ainda na lista, localiza a não lida e abre a mensagem em qualquer largura. Isso evita enviar `:check-mail` ao leitor, onde o aerc rejeitava o comando.

## v1.9.3 · 12/10/2026
- **Temperaturas com vírgula e °C:** a previsão de 7 dias de Ribeirão Preto mostra `30,2°C/19,8°C` (antes `30.2°/19.8°`) e a máxima/mínima de hoje, `30°C/19°C`. Os campos extras de uma fonte que são número decimal seguem o `separador` dela (`pt` = vírgula); sem separador, ficam como vieram.

## v1.9.2 · 12/10/2026
- **Testes não mandam mais notificações ao seu PC:** cada rodada da suíte disparava uns 27 avisos de mentira nas notificações do sistema ("🤖 agente · precisa de você", "📧 Um: 1 e-mail novo", "📋 Pagar aluguel"), que não apareciam no 🔔 porque cada teste grava num lugar temporário. Agora os testes usam um `notify-send` mudo e a suíte reprova quem tentar o de verdade. Os avisos reais dos agentes continuam indo ao 🔔 e às notificações do sistema.

## v1.9.1 · 12/10/2026
- **Atalhos de IA do celular sem "código 127":** 🚀 e 👇 no Termux terminavam com `atalho terminou com código 127` quando o `~/.bashrc` do Debian (proot) perdia a linha que põe `~/.local/bin` no PATH. Agora os atalhos, o botão do Claude e os atalhos `cl`/`clc`/`clr` do Termux levam esse PATH no próprio comando. Quem tem os atalhos personalizados em `~/.config/tt/atalhos` com o comando antigo pode trocá-lo pelo novo de `atalhos-padrao-mobile`.
- **`~/.bashrc` preservado:** quando faltava o marcador de fim do bloco do tt, a instalação apagava tudo o que vinha depois do bloco. Agora ela reconhece o fim do bloco e recoloca o marcador (com cópia em `~/.bashrc.antes-tt`) ou, sem reconhecer, não mexe. Também mantém as permissões do arquivo e não troca um `~/.bashrc` que seja link (dotfiles) por um arquivo comum.
- **`termux/celular.sh`:** a linha do PATH do Debian voltava a faltar sem aviso (a busca confundia o bloco do tt com ela); o `verificar` agora avisa quando ela falta.

## v1.9.0 · 12/10/2026
- **E-mail: Esc fecha.** Na mensagem aberta, Esc volta à lista; na lista, limpa o filtro ou a busca, se houver, e senão esconde o e-mail (ele segue conectado; o `q` continua valendo). O título do popup agora diz "Esc fecha".
- **✉ Não lidas:** botão novo no rodapé do e-mail que mostra só as não lidas da pasta aberta, em cada conta. Clicar de novo, ou Esc, volta a mostrar todas (é o mesmo que a tecla `F`).
- **🧹 Esvaziar a lixeira:** botão novo no rodapé do e-mail, item no menu do 📧 (botão direito) e `tt --email-lixeira [CONTA…] [--sim]`. Mostra quantas mensagens há na lixeira de cada conta e, depois de você confirmar, apaga de vez as da conta escolhida (ou de todas) direto no servidor: só a pasta que ele marca como lixeira, nunca outra. O espelho local acompanha na rodada de sync que começa em seguida.
- **Ajuda do e-mail com ícones:** a tela de atalhos (?) ganhou um ícone por assunto (📖 Ler, 📂 Organizar, 💬 Responder, 🔍 Encontrar, 📎 Anexos…), os botões ao lado das teclas e as colunas alinhadas mesmo com emoji.
- **Rodapé do e-mail cabe na tela:** os rótulos dos botões entram conforme a largura (os dos ícones menos óbvios primeiro), em vez de a barra passar da borda e esconder os últimos botões.

## v1.8.24 · 12/10/2026
- **Ctrl copia com o mouse, como o Alt:** Ctrl+arrastar copia a seleção, Ctrl+duplo clique a palavra (num link, o link inteiro) e Ctrl+triplo clique a linha. O tmux 3.8 trazia de fábrica Ctrl+arrastar = desenhar um painel flutuante (a "subjanela" que aparecia onde se arrastava); o tt desliga isso. Ctrl+arrastar a partir de um link copia e não abre o link: o Ctrl+clique num link agora espera o tempo de um duplo clique antes de abrir, como o clique simples. Sem Alt ou Ctrl, arrastar continua indo ao programa, e Shift+arrastar continua sendo a seleção do próprio terminal.
- **Botão do meio cola a cópia certa:** depois de copiar algo que a tela tinha partido em linhas (um endereço longo, por exemplo), o botão do meio colava a cópia anterior; agora cola a que você acabou de fazer, já religada.

## v1.8.23 · 12/10/2026
- **Datas completas em português:** previsões, feriados e lançamentos exibem `DD/MM/AAAA (Dia)`.
- **Títulos legíveis:** o primeiro caractere alfabético de cada item fica em maiúscula depois dos ícones, por exemplo `g1` → `G1` e `feriado` → `Feriado`.

## v1.8.22 · 12/10/2026
- **Letreiro pronto ao instalar:** as 48 fontes atualmente ativas viram padrão de fábrica; Ribeirão Preto é a localidade padrão, com previsão para sete dias e datas em `DD/MM/AAAA (Dia)`.
- **Ajustes do painel:** nomes mais claros e ritmos de velocidade prontos, com limites de 0,1–5 s por coluna ou 1–60 s por página.

## v1.8.21 · 12/10/2026
- **Letreiro sem cortes:** nenhuma entrada é mais cortada no meio. Antes, o catálogo e as notícias embutidas cortavam o título em 90 a 200 caracteres (`valor_max`/`truncar`); agora `truncar` vale `0` (não corta) e o catálogo não define corte nenhum. Quem quiser limitar uma fonte ainda pode pôr `truncar=N`.
- **Clima de Ribeirão Preto:** as 13 fontes de clima do catálogo e o modelo "clima" trazem Ribeirão Preto como lugar padrão (antes, São Paulo). Os exemplos do catálogo foram regravados com a resposta real.
- **Letreiro: ordem sequencial ou aleatória:** o painel do letreiro ganhou a linha **🔀 Ordem** (⏎, clique ou `^o`) que alterna entre *sequencial* (uma fonte depois da outra) e *aleatória*, que agora mistura as **entradas** de todas as fontes, não só a ordem delas. A mistura muda a cada hora e não pula quando uma fonte atualiza. `manual`, o nome antigo, segue valendo como sequencial.

## v1.8.20 · 12/10/2026
- **Título dos popups sem códigos estranhos:** a tela do letreiro (e qualquer popup com emoji no título, como 📤 enviar) mostrava `\360\237\223\260` antes do nome quando o tmux rodava sem locale UTF-8. O texto agora chega inteiro.

## v1.8.19 · 12/10/2026
- **Avisos de agentes pelo sininho 🔔:** `tt --notificar-daqui` não pisca mais no miolo da faixa de notificações. O aviso entra no contador do 🔔 (que o mantém, de qualquer idade, até você abri-lo) e na central; ⏎ no aviso leva à sessão e ao painel do agente e `^l` marca todos como lidos (`tt --notifs-lidas`). Vale 24 h por padrão. Os demais avisos (e-mail, lembretes de tarefas) seguem piscando na faixa como antes.

## v1.8.17 · 11/10/2026
- `tt --session-resolve CÓDIGO` localiza a sessão tmux pelo identificador persistente, inclusive depois de renomeá-la, para reanexar e recuperar seu contexto enquanto ela existir.

## v1.8.16 · 11/10/2026
- **Registro de tarefas mais completo:** cada trecho exige início e fim em RFC 3339 com fuso explícito; registra o código persistente da sessão tmux, tokens usados e custos estimados em USD e R$. O histórico soma tokens e as duas moedas.
- **Caracteres corretos na revisão de atualizações:** o editor do tt força UTF-8, inclusive quando a máquina usa locale ASCII.

## v1.8.15 · 11/10/2026
- Letreiro com fontes (APIs) configuráveis: menu ⋯ → 📰 Letreiro. Cada fonte (dólar, notícias, uma API
  sua…) vira um arquivo `~/.config/tt/letreiro/NOME.conf` e você cria, testa ao vivo e edita pela tela —
  cola a URL, o tt busca e mostra a resposta, você escolhe o campo no fzf — ou por `tt --letreiro-add`,
  `--letreiro-editar`, `--letreiro-testar`, `--letreiro-log`, `--letreiro-exportar/--letreiro-importar`.
  Suporta JSON (caminho, `[*]`, filtros), XML, RSS/Atom, CSV, texto e regex; GET e POST; autenticação
  Bearer, Basic, header e query com o segredo só em `~/.secrets`; casas decimais, pt/en, escala, moeda,
  variação com ▲▼ e cor; modelo do item, truncar, prefixo/sufixo; janela de dias e horas, cota por hora,
  condições (só se variar mais de X%, só se cruzar um limite), perfil/máquinas e modo economia no celular.
- **156 fontes prontas já no pacote, todas desligadas** (`letreiro-catalogo.json`), cada uma validada na rede real:
  moedas e criptomoedas, juros e inflação do Banco Central (Selic, CDI, IPCA, IGP-M, TR, poupança, PTAX…), bolsas e
  commodities (Ibovespa, S&P 500, Nasdaq, PETR4, ouro, Brent…), tempo e clima por lugar (temperatura, chuva, UV, nascer
  e pôr do sol, qualidade do ar), espaço e Terra (sismos, tempestade geomagnética, ISS, próximo lançamento), Brasil
  (feriados, Mega-Sena, IBGE), 46 feeds de notícias, tecnologia e ciência (g1, Folha, BBC, Guardian, Hacker News, LWN…), versões
  (kernel, Python, Node, Go, Rust, tmux, Vim, Claude Code, Chrome, Firefox, Ubuntu LTS…), status de 16 serviços,
  frases e curiosidades. Nada busca na rede até você ligar. No painel: **Tab** alterna a vista (todas · na roda ·
  disponíveis), **`^a`** liga/desliga, a prévia mostra *como aparece* com um exemplo, **F2** configura (o arquivo guarda
  só o que você mudou), **`^x`** tira da lista e o **📚 Catálogo** traz de volta, ↺ volta ao padrão de fábrica. Além
  disso, 12 **modelos** que perguntam o que falta: par de moedas, ação ou índice (Yahoo), série do Banco Central,
  versão de um repositório do GitHub, estrelas, pacote do npm ou do PyPI, fim de suporte (endoflife.date), clima de
  qualquer lugar, feed RSS qualquer, status de qualquer serviço, CI do GitHub.
- Corrigido: uma variável com `dono/nome` (como `{repo}`) virava `dono%2Fnome` na URL e o GitHub respondia 404; o modelo
  de CI do GitHub nunca funcionava.
- Segurança: só https; destinos locais e de rede privada bloqueados (também nos redirecionamentos); o texto
  vindo da rede perde escapes de terminal e a sintaxe de formatação do tmux; o segredo nunca aparece em
  tela, log, cache, exportação ou propagação.
- Diagnóstico por fonte (estado, última atualização, HTTP, latência, falhas seguidas, espera crescente após
  erro, aviso na central após 5 falhas seguidas, log rotativo) e propagação das fontes globais entre as
  máquinas (a mudança mais nova vence, com sobrescrita por máquina). Clique no letreiro: abre a URL do
  item, copia, abre um painel do tt ou pausa/continua. Ajustes novos: separador, ordem (manual, aleatória
  ou por peso), largura máxima, interruptor por máquina. As linhas antigas `indicador_NOME=` são migradas
  sem perda; `tt --ticker-fontes` e `tt --ticker-quadro` seguem iguais. Detalhes no README, seção
  "Letreiro: fontes (APIs)".

## v1.8.14 · 11/10/2026
- **Emoji aparecendo como `__` nas telas abertas dentro de uma janela flutuante/popup** (e-mail e atalhos do e-mail, pontes). O
  cliente tmux lançado dentro da janela decide se o terminal é UTF-8 pelo ambiente dele (`LC_ALL`/`LC_CTYPE`/`LANG`); sem locale
  UTF-8 o tmux desenha um `_` por célula no lugar de cada caractere (📋 vira `__`, ✓ vira `_`). Agora todo cliente aninhado
  (e-mail em popup ou painel flutuante, ponte local e ponte por ssh) é lançado com `tmux -u`, que não depende do ambiente da
  janela. `tests/test_cliente_aninhado_utf8.sh` reproduz o `_` sem o `-u` e prova a correção.

## v1.8.13 · 11/10/2026
- **Acentos corretos nas novidades:** a tela agora informa ao `less` que as notas são UTF-8, mesmo em terminais
  com locale POSIX/ASCII (como o Debian do Termux sem locale configurado). Acentos e símbolos deixam de aparecer
  como sequências entre sinais de menor e maior.

## v1.8.12 · 11/10/2026
- **Tarefa por e-mail em três vias.** Antes, aprovar uma atualização sobrescrevia em silêncio tudo o que você tinha mudado
  (prazo, prioridade, etiquetas, até a descrição). Agora o tt compara a sua tarefa × o e-mail × a última versão que os dois
  viram: o que só o e-mail mudou entra, o que só você mudou fica, e o que os dois mudaram é **conflito** (nada é gravado até
  você decidir). Na aba Entrada: **⇄ revisar mudanças** abre uma tela única (vim, clicável, também no celular): por campo e por
  subtarefa, *Aceitar recebida · Manter minha · Ficar com as duas · Editar…*, mais *Aceitar tudo recebido* e *Manter tudo meu*;
  a descrição mostra só as linhas que diferem. ✓ aprovar com conflito abre a revisão; há *aprovar todas as que não têm
  conflito* e *recusar todas*. Na linha de comando: `tt --demanda-diff ID`, `--demanda-merge ID`,
  `--demanda-aprovar [--recebida|--minha] ID` (sai 4 se ficou conflito sem escolha).
- **O e-mail diz a verdade.** O estado da tarefa, concluir, **reabrir**, **remover** e acrescentar subtarefa agora viajam (antes
  a mãe concluída continuava aberta do outro lado, `[x]` só valia em atualização e reabrir/remover não chegavam). O rodapé
  `tt:2 …` fica depois da assinatura, então um tt antigo continua entendendo o e-mail. O **diário de trabalho (⟡) não vai mais
  no e-mail**: ele levava máquina, sessão, tokens, custo e o **e-mail da conta** de quem trabalhou.
- **Menos ruído:** reenvio sem diferença, proposta velha que chega depois da nova e e-mails repetidos são descartados sozinhos;
  a mais nova do mesmo remetente substitui as pendentes dele.
- **✉ Enviar por e-mail**: menu ⋯ da tarefa (e menu do 📋, para várias, com Tab) abre **um e-mail por tarefa já preenchido**
  (Para, assunto `[tt] … ~código`, subtarefas com código) no compositor do tt. `tt --tarefa-email ID DESTINO --abrir`,
  `tt --tarefas-email DESTINO ID…`; `TT_EMAIL_MAILTO_CMD` troca o compositor. Sem onde abrir, imprime o texto e o link.
- **Subtarefa com identidade estável.** `kito47.2` é a **posição** (muda quando outras entram, saem ou trocam de lugar); agora
  toda subtarefa tem referência estável `MÃE.APELIDO` (`kito47.ruzi83`), mostrada em `tt --tarefas` e na 4ª coluna de `--tarefa-codigo`
  (a 1ª continua sendo só o apelido). O painel, o cartão e a linha de comando passam a ordenar as filhas do mesmo jeito (antes divergiam
  quando duas tinham a mesma ordem). Os verbos que alteram dizem em qual item agiram quando você não deu o código inteiro, e
  avisam se foi por posição. O pedido que a IA recebe e as regras das IAs mandam usar apelido/código, nunca posição.
  Subtarefa de subtarefa é recusada (ficava órfã e invisível). O código novo nunca repete um que existe.
- **Segurança do upsert.** Um e-mail de tarefa nova que citava códigos de subtarefa que você já tem **tomava** a subtarefa de
  outra tarefa, **ressuscitava** a removida e, ao recusar, a apagava. Agora o código só vale se estiver livre; se já é de outra
  coisa, a subtarefa entra nova, com código daqui. `~código` que aponta para uma subtarefa vira demanda nova.

## v1.8.11 · 11/10/2026
- **Corrigido: par alcançável só por relay (DERP) aparecia como ilha ("sem rota").** O `tailscale ping` sai com erro quando não
  consegue conexão direta, mesmo com `pong`; o diagnóstico (`tt --diagnosticar`, `tt --malha`, vigia) usava o código de saída e
  acusava uma ilha que não existia (visto entre o book e o celular, com `pong` em 30 ms por DERP). Agora vale qualquer `pong`,
  direto ou por relay, com uma segunda tentativa mais folgada antes de acusar. `tests/test_diagnostico_derp.sh`.

## v1.8.10 · 11/10/2026
- **O código das tarefas e subtarefas aparece no painel real.** O limite caiu de 80 para 60 colunas (`COLS >= 60`): o painel do celular
  tem 64 colunas (72 com terminal largo) e antes o código quase nunca aparecia. Abaixo de 60 segue só o apelido; o código está sempre
  no preview (`⌗ apelido · código`). Linhas mais longas quebram na largura (o fzf já usa `--wrap`), nada é cortado.
- **`ticker_fps` vai até 20** (antes 10; padrão continua 6, nada muda para quem não configurou). O teto existe porque cada quadro além
  do primeiro custa um gatilho (um processo `bash` por cliente) e tirá-lo não é seguro. Observação: o menor passo de um terminal é 1
  coluna, então subir o fps com a mesma velocidade só repete redesenhos; o ganho é rolar mais depressa (ajuste com `ticker_veloc`).
- Testes: `tests/test_ticker_fps_teto.sh` e o painel de 64 colunas em `tests/test_tarefas_codigo_visivel.sh`.

## v1.8.9 · 11/10/2026
- **Cada subtarefa mostra o próprio apelido e, discretamente, o código.** Na lista do painel a subtarefa era só `.2`; agora é
  `.2 gore21 texto` (o apelido é o mesmo de `tt --tarefa-codigo kito47.2`), em qualquer largura. O código completo (12 hex) fecha a
  linha em painel largo (80+ colunas), como nas tarefas de topo, e o preview da tarefa lista cada subtarefa com `⌗ apelido · código`,
  então o código de tarefa e subtarefas está sempre a um passo, sem poluir a lista.

## v1.8.8 · 11/10/2026
- O diagnóstico de conexão (`tt --diagnosticar`, `tt --malha`) não acusa mais "sem rota" por um único ping lento: tenta de novo, com
  mais folga, antes de declarar a rota perdida. Era um falso alarme quando o par acabava de acordar ou estava sob carga (visto no
  celular e no WSL do book logo depois de ligar).

## v1.8.7 · 11/10/2026
- **Malha de máquinas sem ilhas.** O cadastro (`--cadastrar`) ligava só duas máquinas: com a C cadastrada só na A, B e C não se
  conheciam e nenhuma sessão de B alcançava as de C (nem por ponte, que também depende de a origem conhecer o alvo). Agora toda
  máquina publica o que sabe e aprende o que lhe falta com as outras, sozinha (vigia a cada 15 min, e ao cadastrar), e a malha é:
  **completa** (todas se conhecem e se apresentam uma à outra), **coerente** (o rótulo é o que a própria máquina anuncia em `nome=`;
  descadastrar vale em todas e a troca de listas não ressuscita, o registro mais recente vence),
  **inter-acessível** (só se aceita o que se prova: par da tailnet, ssh entra, o nome de lá confere; o endereço com que cada uma se
  apresenta é o IP que a outra vê, não o "localhost" do Termux; sshd do Termux na 8022 vai para o `~/.ssh/config`; endereço que
  não conecta é trocado por outro que as demais usam; chave faltando é reparada por uma ponte) e **sem fricção** (nenhuma pergunta;
  só avisa na barra se uma ilha persistir 2 voltas). `tt --malha` completa e mostra quem alcança quem; rastros em `~/.cache/tt-malha.log`.
  Corrigido junto: `--cadastrar` feito do celular gravava `localhost` como o endereço dele nas outras máquinas.
- Testes: `tests/test_malha.sh` (4 máquinas simuladas) e a ponte anexada em `tests/test_ponte_renomeada.sh`; o `test_pontes.sh`,
  que validava uma cópia velha da função, foi removido.
## v1.8.6 · 11/10/2026
- **Logar as outras máquinas pelo navegador do celular, sem copiar link nem colar código** (documentação + teste).
  A skill `celular-android` ganhou a seção 14 com a receita completa e uma função de bash pronta, `login_pelo_celular`:
  abre o link de login no navegador do celular, anda pelo login do site e do Google, toca em "Autorizar" (conferindo o
  "Conectado como …" da página), lê o código, o entrega ao `ia-login` do alvo e confere o e-mail que entrou. Para senha,
  verificação em duas etapas, CAPTCHA ou outra conta ela para e chama o dono. Validada de ponta a ponta num celular e num
  alvo reais (48 s, sem intervenção) e, em 26 execuções simuladas, pelo novo `tests/test_login_pelo_celular.sh`, que extrai a função
  do próprio markdown e a roda contra um celular e um alvo simulados (o código de login nunca pode vazar para a saída).
  O mesmo ciclo está resumido no README, no `termux/ANDROID-ADB.md` e na skill `tt-terminais`.
- **Corrigido: dois logins seguidos da mesma conta falhavam com "server exited unexpectedly".** No tmux 3.6, matar a
  última sessão do tmux isolado dos logins (`-L tt-login`) derruba o servidor e o `new-session` seguinte bate nele ainda
  morrendo (27 falhas em 30, medido). A sessão de um login anterior dura 15 min, então bastava repetir o login da mesma
  conta nesse prazo. O `ia-login --iniciar` agora repete até o servidor novo subir (`tests/test_ia_login_corrida.sh`).
- Documentado o que faltava para quem automatiza a tela do celular: o `click`/`tap` por acessibilidade não aciona botão
  de página web (só `input tap` avulso), elemento com limites de altura zero está abaixo da dobra, a janela do navegador
  só aparece no dump ~3 s depois do `abrir`, e o Termux pode voltar à frente entre duas chamadas (seções 8, 9 e 11).
- A skill `rodizio-de-contas` passou a ensinar a **tirar uma conta de todas as máquinas** (trocar a principal antes,
  esquecer no cadastro mantendo o tombstone `-`, remover perfis, conferir credenciais e atalhos, e lembrar o dono de
  revogar o token, que o logout local não revoga) e a restauração do login que a troca da principal derruba.

## v1.8.5 · 11/10/2026
- **Sessões do Termux voltam a aparecer por ssh**: o comando remoto do tt passa `TMUX_TMPDIR=$PREFIX/var/run`
  (onde mora o servidor tmux do Termux). Antes, o ssh sem login não lia o `profile.d` e o tmux olhava
  `$PREFIX/tmp`, dizendo "não existe ou está inacessível" para sessões vivas (ponte, abrir, listar).
- **Tarefas iguais em todas as máquinas**: quando duas versões da mesma tarefa empatam em `mudada` e
  estado, o merge junta as chaves de meta (`pai`, `ord`, `desc`…) em vez de cada máquina guardar a sua.
  Antes o painel mostrava contagens diferentes (26 × 19) com os mesmos dados.

## v1.8.4 · 11/10/2026
- **Proteção adicional para sessões internas**: o nomeador recusa sugerir nomes para sessões `_nome`,
  e a função de renomeação também bloqueia mudanças automáticas nessas sessões, mesmo quando chamada
  fora do vigia. Isso impede a repetição de `_tt-vigia` virar `esperando-inicio` por esses caminhos.
  Renomeações manuais explícitas continuam permitidas. Teste de regressão preserva o processo interno
  e verifica que sessões comuns continuam recebendo nomes.
- A renovação de token pelo `ia-conta` aplica as mesmas variáveis de sub-agentes da conversa normal,
  preservando valores definidos pelo usuário, inclusive vazios. Corrige a falha da suíte nesse caminho.

## v1.8.3 · 11/10/2026
- **Corrigido: ser jogado de uma sessão de outra máquina para outra qualquer "sem motivo".** A causa: o vigia renomeia
  sessões sozinho; a ponte guardava o nome antigo do alvo, a sonda de pontes órfãs (a cada 5 min) não o achava lá,
  tomava a ponte por morta, matava-a com você dentro e o tmux (`detach-on-destroy off`) te levava a outra sessão.
  Agora a ponte acha a sessão de lá pelo **id** (junto do start_time do servidor, que muda se ele reiniciar), nunca
  pelo nome; conecta por esse id e segue o nome novo. Uma ponte só é encerrada quando o destino responde, o id e o nome
  sumiram e isso se repete em 2 sondagens seguidas; sem resposta de rede, nada é concluído. Ponte antiga ainda
  anexada e sem id nunca é morta pela sonda.
- Rastros: toda ponte que o tt encerra grava o motivo em `~/.cache/tt-vigia.log`, e toda troca de sessão do tt grava
  `~/.cache/tt-troca.log` (cliente, de onde para onde, quem chamou, se veio de ssh). Testes: `tests/test_ponte_renomeada.sh`.

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
