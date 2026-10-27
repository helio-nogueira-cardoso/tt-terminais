# Novidades do tt-terminais

Uma seção por versão, da mais nova para a mais velha. `tt --novidades` mostra o que saiu desde a última
vez que você olhou; `tt --novidades --todas` mostra tudo. Também no menu administrar → 📰 Novidades do tt.

## v2.11.48 · 27/10/2026
- **📧 O que você envia já aparece em Enviados:** numa conta Microsoft com espelho local, o `tt --email-enviar` atualiza a pasta Enviados do espelho assim que o e-mail sai. Antes ele já estava no Outlook, mas só chegava ao aerc na sincronização completa, que pode levar até 2 horas.
- **Message-ID certo nas contas Microsoft:** o Outlook grava um Message-ID próprio e o tt mostrava o da mensagem que ele montou, que não servia para responder nem para achar o e-mail. Agora mostra o que está nos Itens Enviados; se a mensagem demorar a aparecer, diz isso em vez de mostrar um identificador que não existe.

## v2.11.10 · 24/10/2026
- **Saída de uma conexão presa:** Ctrl+B Esc e o menu ⋯ → Recuperar tela abrem a central local. Uma falha limpa o quadro antigo e oferece Reconectar ou Central, sem escrever sequências estranhas por cima da interface. A tentativa tem prazo e pode ser cancelada; a sessão de trabalho é preservada.
- **E-mail sem cascata:** navegar de dentro da janela age na tela que a abriu. Trocas nativas recebem proteção imediata de tamanho e retorno verificado; uma falha fecha só a vista, preservando o aerc. A partida do cliente no Mac também deixa de provocar recriações por confundir `env` com um aerc encerrado.
- **Anexos recuperáveis:** erro de gravação ou cancelamento preserva os arquivos e informa como retomar. Nomes repetidos não sobrescrevem arquivos existentes. E-mails anexados (`.eml`) enviados pela Microsoft deixam de ir vazios; imagens inline conservam seu vínculo com o corpo HTML. Guia completo: `docs/recuperacao-telas-anexos.md`.
- **Sessões internas pela voz:** um nome reservado não vira uma busca aproximada que acaba selecionando outra sessão de trabalho pelo título.

## v2.11.4 · 24/10/2026
- **📰 Letreiro sem emoji piscando no Ghostty:** com o letreiro andando uma coluna por quadro (o da ponte, que é o mais fluido), o Ghostty fazia piscar o emoji montado com mais de um código, como o 🏛️ do G1, da Câmara e do Senado, o 🌡️ do tempo e o 🛰. Agora o emoji desse tipo sai como o símbolo seguido de um espaço, que o Ghostty desenha firme e na mesma largura; tom de pele, emoji com ZWJ e keycap ficam só com o emoji de base. As bandeiras continuam as de verdade e são as únicas que ainda podem piscar: não existe bandeira de país feita de um código só.

## v2.11.1 · 24/10/2026
- **🧹 Esvaziar a lixeira nas contas Microsoft:** dava "AUTHENTICATE failed". A lixeira era sempre consultada pelo IMAP, e o acesso dessas contas é do Microsoft Graph, que a Microsoft não aceita no IMAP. Agora a contagem vem pelo Graph e o esvaziar apaga pela mesma API do Outlook que o tt já usa para enviar e marcar lida.

## v2.11.0 · 24/10/2026
- **📧 E-mail por eventos:** o servidor passa a avisar quando chega mensagem, e só então o tt sincroniza. Um processo leve por máquina deixa uma conexão IMAP IDLE aberta na caixa de entrada de cada conta com espelho local; e-mail novo, apagado ou lido em outro aparelho dispara a sincronização daquela conta em segundos. Antes, cada conta era consultada a cada 2 minutos por dois caminhos ao mesmo tempo (o vigia e o aerc); num Mac com sete contas eram cerca de 1.200 sincronizações por dia, quase todas para descobrir que nada tinha mudado.
- **Polling vira rede de segurança:** com o IDLE de pé, o vigia confere a caixa de entrada a cada 30 minutos e as demais pastas a cada 2 horas. Se a conexão cair ou o servidor não oferecer IDLE, a conta volta sozinha ao ritmo de antes. O 📧 não acusa "parado" por causa desse espaçamento.
- **O aerc deixa de ir ao servidor à toa:** o intervalo de 2 minutos dele continua (é o que faz a lista se atualizar sozinha), mas não abre conexão se a conta acabou de sincronizar ou se o IDLE dela está de pé. Antes ele ainda ignorava a espera que o tt faz depois de um erro.
- **Menos trabalho por rodada:** o aviso de e-mail novo só varre a caixa quando ela mudou, e a contagem de não lidas da barra só é refeita quando as pastas mudam.
- **Contas Microsoft (Graph) também por eventos:** o Graph não oferece IDLE, então o tt confere os contadores da caixa de entrada a cada minuto, numa consulta de poucos bytes, e sincroniza só quando eles mudam. A sincronização também ficou incremental: lista as mensagens sem o corpo e baixa o corpo só do que é novo ou mudou. Na conta da empresa, cada sincronização caiu de cerca de 500 requisições e 70 segundos para uma requisição e 0,2 segundo.
- **Mensagens que sumiam do espelho Microsoft no Mac:** os identificadores do Graph diferenciam maiúsculas de minúsculas, e o disco do Mac não. Duas mensagens com identificadores parecidos caíam no mesmo arquivo, e uma sobrescrevia a outra: na conta da empresa eram 37 de 500. Agora cada uma tem o seu arquivo; as afetadas são baixadas de novo uma vez.
- `TT_EMAIL_IDLE=0` desliga os eventos.

## v2.10.1 · 24/10/2026
- **⚙ Guarda dos serviços:** o loop de programa ausente às vezes passava despercebido. A cada volta ele fica de pé por um instante (antes de o programa faltar de novo) e, no systemd 254 ou mais novo, passa por um estado de espera que o tt não conhecia; pego num desses momentos, o `tt --checar` dizia que estava tudo bem. Agora o tt olha de novo antes de concluir, e um programa trocado com o serviço rodando continua fora da conta. O aviso de um programa que some de novo no mesmo dia passa a dizer quando ele sumiu desta vez, não da primeira.

## v2.10.0 · 23/10/2026
- **⚙ Guarda dos serviços do usuário:** um serviço do systemd que reinicia sem parar agora é percebido, explicado e tratado com critério. Antes, um serviço cujo programa sumiu ficava reiniciando a cada poucos segundos para sempre, sem nunca aparecer como falha: o ollama.service do Jiraops reiniciou 6611 vezes em 23 horas assim. O vigia confere a cada 5 minutos.
- **Programa ausente:** o serviço deixa de tentar enquanto o programa não existir, e o aviso diz qual programa, para onde apontava o link quebrado e desde quando. Quando o programa volta, o tt religa o serviço, confere que ele ficou de pé e então tira a guarda. Se o serviço não subir, ele fica parado (nada de loop com o programa quebrado) e só tenta de novo quando o programa mudar. Uma troca de versão que deixa o programa ausente por um instante não conta.
- **Falha repetida:** medida pela taxa de tentativas, nunca pelo total acumulado, e o serviço nunca é desligado: só ganha espera crescente entre as tentativas (systemd 254 ou mais novo) e um aviso. O episódio termina sozinho quando o serviço se normaliza, e a espera crescente sai junto. Um serviço que termina com sucesso de propósito, como um periódico, nunca é tocado.
- **Uma pergunta por episódio, no 🔔:** o aviso abre a decisão na máquina do serviço, mesmo vista de outra: instalar de novo (o tt já reinstala o Ollama sem administrador, numa pasta só dele, conferindo o pacote oficial e sem tocar nos modelos), ligar agora, desligar, deixar esperando ou tirar a guarda. Também em `tt --servicos`, no `tt --checar` e no `tt --saude`.

## v2.9.20 · 23/10/2026
- **Menos SSH à toa no pré-carregamento:** quando a outra máquina responde que a sessão com aquele ID não existe mais, ela sai do histórico de visitas e deixa de ser preparada. Antes, sessões já fechadas voltavam à fila a cada poucos segundos, e cada tentativa abria uma conexão SSH. Um tmux que apenas demorou a responder lá não apaga nada.
- **Trilha de diagnóstico do coordenador:** uma volta do laço acima de 2 s fica no `erros.log` do coordenador, com o tempo de cada fase, e o encerramento de um coordenador travado também fica registrado.

## v2.9.19 · 23/10/2026
- **Clique de dentro da ponte que não trocava a tela:** o coordenador de pontes congelava quando uma conexão mestra do SSH, meio morta, segurava a saída de um comando dele. A partir daí todo clique nas fixadas feito de dentro de uma ponte sumia sem aviso. Agora nenhuma leitura espera o fim da saída de um processo que já terminou. Se o coordenador parar de responder mesmo assim, ele é encerrado, um novo assume e o clique segue pelo caminho antigo, sem risco de troca dupla.
- **Terminal do Tailscale SSH:** quando a ponte entra pelo SSH do Tailscale, o terminal de lá pertence ao root e o tt não conseguia devolver o clique por ele. Agora um porteiro mínimo, que só repassa pedidos de navegação daquela ponte, segura o terminal enquanto a ponte existe. O clique volta pelo caminho rápido também nesse caso. O status do pré-carregamento conta à parte os cliques entregues pelo porteiro e os que precisaram do SSH de volta.
- **Pedido à máquina da tela em segundos, não em 45 s:** com a mestra do SSH travada, o pedido de troca esperava até os keepalives derrubarem a conexão. Agora a mestra tem um prazo curto. Sem resposta nesse prazo, ela é encerrada e o pedido segue por uma conexão própria. O mesmo vale para a consulta de sessão e de identidade antes de abrir uma ponte. A troca feita a pedido de uma ponte agora aparece em `~/.cache/tt-troca.log`.

## v2.9.16 · 23/10/2026
- **Sessões do Mac vistas pela empresa:** o clique na faixa das fixadas segue pela conexão que já exibe a ponte. Não abre outro comando SSH de volta à origem por clique; a origem continua validando a identidade e escolhendo apenas a tela correta. A primeira troca renova conexões de versões antigas.
- **ID preservado ao renomear:** atribuição de UUID uma única vez, protegida contra concorrência e colisão; o nome só descobre uma referência ainda sem identidade. Um ID conhecido não é substituído pelo nome em navegação, reconciliação ou reconexão. Sessão recriada com o mesmo nome recebe outro ID; identidade ambígua é recusada.


## v2.9.12 · 23/10/2026
- **📧 Um aerc só:** abrir o e-mail numa tela de outra largura (o celular depois do Mac, uma ponte) reaproveita o aerc que já está aberto e só ajusta a prévia e a barra de pastas, sem reconectar as contas. Antes, cada troca de largura abria um aerc novo. O antigo ficava vivo sem tela, porque o aerc ignora o sinal que o tmux manda ao fechar a sessão. Num Mac de 8 GB chegaram a se acumular 59 instâncias em três dias, com mais de cem visualizadores pendurados. Quando a sessão precisa mesmo ser recriada (conta ou pasta nova), o aerc antigo é encerrado. Os que sobraram de versões anteriores são encerrados na próxima abertura.
- **Salto para a mensagem nova no Mac:** o tt procurava o socket do aerc em `/run/user`, que não existe no macOS. Agora procura em `~/Library/Application Support`, e o clique no aviso de e-mail novo vai direto à mensagem também no Mac.
- **Testes sem restos:** a suíte guarda tudo o que cria numa pasta da rodada e a varre ao sair, inclusive quando é interrompida ou quando um teste estoura o tempo. Antes, servidores tmux e agentes falsos de rodadas interrompidas ficavam vivos por dias.

## v2.9.7 · 23/10/2026
- **Voltar à ponte mais rápido:** clicar numa fixada já conectada reaproveita a tela e a conexão, sem resolver e conferir o destino novamente por SSH. A entrada curta também volta à fixada local. Cada troca continua conferindo a identidade e o dono da tela. Cliques feitos dentro da ponte vão primeiro à máquina da tela, sem uma consulta extra ao destino, inclusive ao trocar entre sessões da mesma máquina remota.
- **Cache preservado no reinício:** o coordenador recupera pontes vivas. Um transporte encerrado, mesmo com prompt de reconexão aberto, não é tratado como tela pronta. A primeira abertura continua confirmando o destino remoto; as verificações de ativação agora esperam menos entre rodadas.

## v2.9.0 · 23/10/2026
- **Mais controles pela voz:** esconder e mostrar a barra das fixadas, ligar o não perturbe com prazo, mudar a mensagem do letreiro e renomear sessões. Fixadas, histórico de avisos e acompanhamentos ficam preservados.
- **E-mail, transferências e calendário:** a voz abre os painéis no terminal conectado à sessão escolhida e lê contas, estado da sincronização, transferências e tarefas com prazo.
- **Trocar a conta da IA:** diga o nome da conta e confirme antes de interromper o agente. A confirmação é recusada se a sessão tiver sido substituída. Os novos controles também têm ajuda falada; barra e não perturbe estão no menu Administrar e na CLI.

## v2.8.10 · 23/10/2026
- **Retorno da voz no celular:** o daemon verifica respostas e prazos do modo retorno mesmo sem outra espera ativa. O aviso segue pelo Tasker ou pelo Telegram conforme o canal do pedido.

## v2.8.9 · 22/10/2026
- **🔄 Passagem de tarefa no Mac:** o `ia-rot --passar` rodado por SSH ou fora do Claude não morre mais com "CLAUDE_CONFIG_DIR: unbound variable"; sem essa variável a conta da sessão só fica desconhecida. As datas também deixaram de depender do `date` do Linux: no Mac aparecia "date: illegal option -- d" e sumia a hora em que a primeira conta volta. A hora do reset lida na mensagem de limite ("try again at…", "resets 3pm") agora é entendida no Mac também.

## v2.8.8 · 22/10/2026
- **🖥 Ghostty sem linhas duplicadas:** a tela não rola mais sozinha de vez em quando, com linhas repetidas e barras deslocadas até o redesenho seguinte. A causa era o letreiro, que recortava o texto caractere a caractere e partia ao meio as bandeiras das cotações (🇦🇷 🇺🇸 🇨🇳) quando passavam pela borda. Meia bandeira ocupa 1 coluna para o tmux e 2 para o Ghostty, e a coluna a mais na última linha da tela fazia o terminal rolar. Agora o recorte anda de grafema em grafema: bandeira, emoji com tom de pele, sequência com ZWJ e keycap ficam inteiros, e a largura de cada um é a que o tmux e o Ghostty medem igual (conferido nos dois, caractere a caractere).
- **Ícones que não invadem o texto:** símbolos como 🕰 ⏱ ✏ ⚙ ✉ ❤ aparecem no letreiro e nos menus na forma de emoji, com 2 colunas. Na forma de texto, o Ghostty os desenhava com a fonte de emoji por cima da letra seguinte ("🕰2022", "⚙tmux…"). No menu ⋯ do painel o texto dos itens voltou a ficar alinhado. Na saída dos programas, ☝ ✌ ✍ ⛹ 🏋 🏌 🕴 🕵 🖐 sem seletor passam a ocupar 1 coluna no tmux, como no Ghostty: antes o tmux dava 2 e o resto da linha (até um popup por cima) andava para a esquerda.
- **Medida de largura igual à do tmux:** a conta que o tt usa para montar a barra, as fixadas, a barra do e-mail e o mapa de clique dos cabeçalhos errava em vários emojis: ⚡ ⏳ ☰ ✅ ⭐ valiam 1, 🖥 🗑 🕰 valiam 2, e ZWJ, tom de pele e acento decomposto somavam colunas a mais. Agora ela bate com o tmux em todas as amostras, e um toque perto de um desses ícones não cai mais no botão vizinho. No painel do letreiro, ⚙ Ajustes, 👁 Pré-visualizar e ⇄ Vista voltaram ao alinhamento dos outros itens.
- **Letreiro dez vezes mais leve:** o quadro caiu de cerca de 65 ms para 6 ms. A roda só é remontada quando muda uma fonte, a configuração ou o minuto, e a checagem do Termux é feita uma vez por processo; no WSL ela varria o PATH do Windows a cada quadro. Com 8 quadros por segundo, cada terminal gastava metade de um núcleo só no letreiro.

## v2.8.7 · 22/10/2026
- **Salvar anexos com destino informado no WSL:** a descoberta da pasta de recebidos não consome mais a entrada que informa onde salvar. Arquivos existentes continuam preservados.
- **Clique cancelado não reabre o link:** a intenção é registrada antes da captura do painel e conferida depois dela. Duplo clique, arrasto ou um clique mais novo continuam cancelando uma abertura cuja leitura demorou.
- **Mouse da central após ação lenta:** ao retomar de uma ação que pausou o fzf, o tt religa o mouse. O pino continua respondendo ao segundo clique mesmo quando a gravação aguardou a trava.
- **Consulta de e-mail sem trava herdada:** ao concluir a rodada, a trava é liberada mesmo se um aviso deixou filhos em segundo plano. A consulta seguinte não é pulada por esses filhos; o fallback de flock do Mac respeita liberação e leitura compartilhada.
- **Runtime explícito respeitado:** `TT_RT` é criado quando necessário; caminho inválido informa erro, sem cair silenciosamente no temporário compartilhado.
- **Testes isolados no Mac e WSL:** processos simulados funcionam também com sleep multicall, a seleção do e-mail espera o aerc iniciar e o clipboard fica restrito aos substitutos de teste. O teste da faixa usa um quadro estável; a transferência de fontes para testes evita metadados do macOS.

## v2.8.6 · 22/10/2026
- **🔌 Ponte fechada não deixa cliente preso na outra máquina:** a ponte e o painel remoto passam a abrir uma conexão ssh própria, em vez de um canal da conexão compartilhada. No Tailscale SSH, fechar um canal dessa conexão não encerrava o tmux do outro lado, que ficava preso horas animando a barra para ninguém (eram 9 no PC da empresa). Agora fechar a ponte fecha a conexão, e o cliente de lá sai junto. Abrir uma ponte nova custa uns 0,1 a 0,3 s a mais; a pré-carregada já vem conectada. Os comandos rápidos seguem na conexão compartilhada.

## v2.8.3 · 22/10/2026
- **⚡ Pré-carregamento sem pontes esquecidas:** um coordenador só por servidor tmux. Antes, no Mac, o mesmo servidor chegava por dois caminhos (/tmp e /private/tmp, e duas pastas temporárias), abria dois coordenadores e cada um preparava as suas pontes, passando do limite de 6. Sessões em espera deixadas por um coordenador que já morreu são recolhidas. Para a mesma sessão remota fica uma ponte ativada só: as cópias que ninguém está vendo fecham, e a sessão da outra máquina não é tocada. O `tt --precarregar status` volta a achar o coordenador também por ssh.

## v2.8.2 · 22/10/2026
- **📰 Letreiro mais leve:** quando a velocidade do letreiro é mais lenta que uma coluna por quadro, o tt deixa de redesenhar a barra nos quadros em que nada muda. Exemplo: 20 quadros por segundo com o texto andando 2 colunas por segundo viram 2 quadros, com a mesma tela, no mesmo instante, em todos os clientes. Menos processos por terminal e menos tráfego nas pontes. Dica: para o texto deslizar contínuo, use uma coluna por quadro (por exemplo, velocidade 0,125 s com 8 quadros por segundo).

## v2.8.1 · 22/10/2026
- **🖥 Ghostty, o terminal padrão do tt:** onde cabe (Mac e Linux com área de trabalho), o tt passa a recomendar o Ghostty como pendência de instalação, que dá para adiar mas não para recusar de vez: no Mac pelo Homebrew, no Linux pelo snap. Com o Ghostty presente, o tt o deixa configurado: tema Catppuccin Mocha, Option esquerdo como Alt (o direito segue digitando símbolos), terminfo e variáveis levados no ssh e janela que fecha sem perguntar (a sessão continua no tmux). Seus ajustes ficam abaixo do bloco do tt e prevalecem. Janelas do Ghostty abrem direto no tt, e o tmux liga nele cores reais, teclas estendidas e sublinhado colorido. `tt --ghostty` mostra o estado. Os outros terminais seguem como antes.

## v2.8.0 · 22/10/2026
- **Skills do Figma completas e reforçadas:** a instalação e o vigia distribuem instruções, scripts REST/cache, auxiliar de retorno OAuth e referência detalhada para Claude, Codex e Kiro, inclusive em proots já provisionados. Links e recursos locais ficam preservados; só arquivos diferentes são regravados.
- **Acesso Figma entre navegador e WSL documentado e testado:** entrada por URL do frame, cache antes de MCP e retorno manual entregue ao Kiro original sem Claude. A referência distingue login do Kiro, OAuth do Figma e token REST, explica a validade de 30 s do código e registra o ensaio Mac → WSL e o reinício autenticado. A distribuição não copia credenciais nem configura MCP automaticamente.

## v2.7.3 · 22/10/2026
- **📧 Abas do aerc sem depender do Alt:** os números sozinhos também trocam de aba na lista e na mensagem aberta: 1 … 9 vão direto à conta e 0 lista todas as abas. Funcionam em qualquer terminal, inclusive no Mac sem Option como Meta e no celular, onde o Alt é difícil de alcançar. Alt+número continua valendo.


## v2.7.2 · 22/10/2026
- **📧 Abas do aerc sempre alcançáveis:** o aerc desenha a barra a partir da primeira aba e não rola, então com muitas contas e mensagens abertas as do fim sumiam. Agora a aba atual fica sempre na ponta esquerda: Ctrl+n / Ctrl+p giram a barra como um carrossel, e a mensagem que você abre vem para a frente. Alt+1 … Alt+9 vão direto à conta (na ordem das contas) e Alt+0 lista todas as abas, contas e mensagens, com busca pelo nome. As abas também ficaram distintas e mais curtas: ▣ conta, ✉ mensagem (assunto em até 20 letras), ✎ mensagem sendo escrita.
## v2.7.1 · 22/10/2026
- **Pré-carregamento no Android:** o coordenador usa a pasta temporária privada do Termux quando `/tmp` não é gravável, mantendo o isolamento. Sem servidor tmux ativo, o status mostra que aguarda uma sessão, sem erro e sem abrir sessões por conta própria.

## v2.7.0 · 22/10/2026
- **Próximas sessões preparadas por tela:** conexões SSH ficam prontas sem anexar ao tmux remoto. Fixadas mais à esquerda têm prioridade, combinada com uso recente/frequente, alternância entre sessões e foco estabilizado no seletor. Só o clique ativa a sessão, com identidade e primeira tela confirmadas; um pedido antigo não ganha de outro clique. Cada tela tem suas pontes; rede caída ou sessão substituída preservam a tela atual.
- **Recursos limitados e controle local:** até 3 candidatos por tela e 6 no total, duas preparações simultâneas, expiração e espera progressiva após falhas. Modo econômico e bateria baixa reduzem o orçamento; suspensão cancela pedidos antigos. Menu Administrar → ⚡ Pré-carregamento e `tt --precarregar status|json|auto|economico|off`. Desligar preserva pontes em uso. O protocolo roda em memória no destino, sem exigir atualizar todas as máquinas juntas.

## v2.6.2 · 22/10/2026
- **📧 Fim do aviso vermelho do aerc nas contas Graph:** o espelho do Outlook deixou de apagar e refazer a pasta a cada sync. Cada mensagem mantém o mesmo arquivo; só a marca de lida e o conteúdo mudam quando o servidor muda, e sai só o que sumiu dele. Acaba o `could not read previous flags … key …`, as marcas do aerc (sinalizada, respondida) ficam e o sync não regrava o que não mudou.

## v2.6.1 · 22/10/2026
- **📧 Lida no aerc vale no Outlook (contas Graph):** marcar uma mensagem como lida ou não lida no aerc chega ao servidor no próximo sync, antes de a pasta ser refeita. Antes a marcação sumia na volta seguinte e a mensagem reaparecia como não lida. Vai pela API REST do Outlook (no Graph o app padrão do tt só lê); sem permissão, avisa e a marcação fica só no cliente. A primeira volta depois de atualizar só registra o estado, sem enviar nada.

## v2.6.0 · 22/10/2026
- **Etiquetas de recebimento locais:** remetentes usam `#_nome`; o prefixo `_` é reservado e não pode ser criado manualmente. Essas etiquetas não viajam no e-mail e ficam preservadas ao receber atualizações. Tarefas antigas identificadas pelo remetente migram com backup.
- **Cópia só com Ctrl:** Alt não autoriza copiar. O arraste reinicia a seleção por caractere, sem herdar palavra/linha anterior nem expandir ao soltar. Soltar Ctrl antes do mouse não copia; os atalhos explícitos de teclado continuam funcionando.
- **Links no aparelho certo:** Chromium e navegador do sistema seguem a origem do clique, inclusive no Mac. Falha remota não abre em outra máquina. Chrome do Mac recebe a URL mesmo já aberto, com perfil separado do tt.
- **Correções das checagens consolidadas:** malha distingue máquinas desligadas, respeita ocultas e evita rajadas de SSH; demandas recusadas são reavaliadas quando o cadastro muda; avisos resolvidos não persistem. Busca preserva históricos e UTF-8; snapshots identificam a conversa retomada; voz não perde passos remotos. Erros de e-mail ocultam tokens, Graph renova credenciais e respeita espera após falhas. Testes isolados deixam de mascarar erros.
- **📨 Envio e recebimento de tarefas integrados:** menus do 📧, do 📋 e da tarefa oferecem envio com seleção de conta, destinatários, prévia e confirmação. `tt --email-enviar --tarefa ID` envia uma mensagem por tarefa, com IDs, estados, descrições, prazos, prioridades e etiquetas de mães e filhas. O lote é validado inteiro, sem duplicar tarefas repetidas. Atualizações chegam à Entrada para aprovação e revisão de conflitos por campo; o diário privado não viaja.
- **📧 Outlook recebe o conteúdo completo:** o espelho Graph passa a guardar o corpo inteiro em UTF-8 e a identidade original da mensagem, com paginação. Descrições longas e subtarefas deixam de depender da prévia resumida do e-mail.

## v2.5.3 · 21/10/2026
- **🍎 Contas de IA no Mac não aparecem mais como "sem login" por engano:** no macOS o Claude Code guarda a credencial no Keychain, não no
  `.credentials.json`. O `ia-conta listar`, a abertura da conta e o `ia-login --faltas` passam a reconhecer o login por lá (também por ssh), então
  o `ia-login` deixa de cobrar logins de contas que já estão conectadas.
- **Nome que não é conta não deixa perfil vazio:** `ia-conta rodar` (ou um nome que não existe) agora só avisa, sem criar a pasta de perfil
  que o `ia-login` depois cobrava como login pendente.

## v2.5.2 · 21/10/2026
- **📨 Modo relaxado libera as demandas de remetentes autorizados:** aceita mesmo quando o Graph entrega autenticação como `fail`, além dos casos sem cabeçalho. Necessário para mensagens legítimas do Felipe que o tenant reporta como não autenticadas.

## v2.5.1 · 21/10/2026
- **📨 Demandas por e-mail com autenticação ausente:** novo modo `relaxado`, que aceita mensagens quando o provedor não expõe `Authentication-Results`, mas continua recusando falhas explícitas. Na atualização, os remetentes já cadastrados em `auth` migram automaticamente uma única vez; novos cadastros mantêm a escolha de modo. Isso libera o e-mail do Felipe que estava sendo ignorado.

## v2.5.0 · 21/10/2026
- **✉️ Enviar e-mail sem abrir tela:** `tt --email-enviar --conta CONTA --para END --assunto "…" --corpo "…"` manda por qualquer conta do tt, seja
  qual for o provedor e a forma de entrar (SMTP com senha, senha por comando ou OAuth; contas Microsoft pelo Graph saem pela API do Outlook). Aceita
  `--cc`, `--cco`, `--anexo` (repetível), `--html`, corpo pelo stdin ou `--corpo-arquivo`, `--responder-para` e `--em-resposta-a`; `--ensaio` mostra a
  mensagem sem enviar. Os campos têm nome em português e aceitam o equivalente em inglês (`--to`, `--subject`, `--body`, `--attach`…). Sem `--conta`,
  vale `email_padrao=` da configuração. Feito para scripts e agentes de IA (que devem mostrar o ensaio e confirmar antes de mandar a terceiros).
- **📤 Enviar pelo aerc numa conta Microsoft (Graph) voltou a funcionar:** o envio falhava sempre (erro interno) e, quando passasse, perderia anexos e HTML.
  Agora usa o mesmo conversor do `--email-enviar`: HTML, anexos, Cco e Responder-para chegam.
- **🧩 Tarefas: uma linha estragada não trava mais todas as máquinas:** um arquivo de tarefas truncado, juntado a outro, grudava duas tarefas numa linha, e a
  sincronização repetia o texto dela a cada volta até passar de 9 MB e prender os merges em todas as máquinas. O merge agora descarta linha malformada, só
  aceita `chave=valor` nos metadados (e limpa o lixo que já estiver lá), nunca concatena arquivos sem quebra de linha e cada gravação usa temporário próprio.
- **🔑 `oauth_client_id=tt`** em conta Microsoft volta a significar o app do tt, como prometido na v2.2.0 (antes ia literalmente "tt" como ID).
- **📚 Skill revisada:** seção nova "Enviar e-mail pela linha de comando", modo Graph documentado, verbos de e-mail que faltavam, e um teste que reprova verbo
  citado na skill que não exista no tt (e verbo de e-mail sem documentação).

## v2.4.7 · 21/10/2026
- **📨 E-mail no Maildir e no Graph:** atualização automática da lista a cada 2 minutos e verificação preservada nas demandas Graph, inclusive reavaliação das mensagens cujo cabeçalho de autenticação chega depois.

## v2.4.6 · 21/10/2026
- **📨 E-mail novo aparece sem atualização manual:** contas que usam Maildir agora mandam o aerc sincronizar e atualizar a lista a cada 2 minutos. A migração corrige contas já cadastradas; se o aerc estiver aberto, a configuração é carregada na próxima abertura, sem fechar um popup ativo.

## v2.4.5 · 21/10/2026
- **📨 Demandas por e-mail no Graph:** o espelho preserva `Authentication-Results` e mantém mensagens `[tt]` aguardando quando os cabeçalhos ainda não chegaram; elas são reavaliadas no próximo sync, sem relaxar a autenticação.

## v2.4.4 · 21/10/2026
- **🕸️ Máquina sozinha não é ilha:** com nenhuma outra máquina cadastrada, `tt --malha` acusava "1 conexão quebrada" (a própria máquina "não respondeu") e o vigia
  avisava uma ilha que não existe. Agora diz "sem outras máquinas cadastradas" e a malha sai completa.
- **⚙️ Partida rápida gerada com o bash certo:** o `tt` gerava o núcleo da partida rápida com o `bash` do PATH, que no Mac pode ser o 3.2 do sistema; passa a usar o próprio bash que o executa.

## v2.4.0 · 21/10/2026
- **🤖 Organização automática das contas Graph:** com `classificar=1` na conta, a cada sync o tt mantém o INBOX arrumado movendo cada mensagem para a pasta da categoria (@ Ação, Automações, Códigos, Segurança, Notificações, Newsletters) por regra de remetente/assunto; o que não casa fica no INBOX. É server-side (vale em todo cliente) e só roda em conta com token de escrita (Mail.ReadWrite).

## v2.3.2 · 21/10/2026
- **🛡️ A atualização não destrói mais o pacote quando duas acontecem juntas:** o vigia que se atualiza sozinho e um `--atualizar`/`--sincronizar` chamado de fora
  trocavam o pacote ao mesmo tempo, apagavam a cópia um do outro e deixavam o `tt` sem arquivos (a `empresa` ficou com ele quebrado por alguns minutos). A troca agora é
  uma por vez (trava com retomada se o processo morrer), quem espera confere de novo, e uma instalação mais velha nunca sobrescreve uma mais nova.

## v2.3.0 · 21/10/2026
- **🗂️ Pastas e maildir de verdade nas contas Microsoft (Graph):** o espelho virou um maildir válido (cur/new/tmp) que o cliente abre — antes só criava `new/` e a caixa aparecia vazia. E a volta completa passa a trazer, além do INBOX, as pastas padrão **Enviados, Lixeira, Rascunhos, Spam e Arquivo** (sem elas não dá para apagar certo nem ver o enviado). Cada pasta é refeita do servidor a cada sync, sem acumular duplicata.

## v2.2.0 · 21/10/2026
- **📧 Outlook, Hotmail e Microsoft 365 entram com menos atrito:** sem `client_id`, o cadastro agora usa o app público **Outlook Mobile** e lê o e-mail pelo
  **Microsoft Graph** (escopo `https://graph.microsoft.com/.default`, que a Microsoft já preautoriza para esse app e devolve os escopos de e-mail que a conta
  pode usar). Isso evita, em muitos tenants corporativos, a tela de aprovação do administrador que o app de terceiros exigia. `oauth_client_id=thunderbird`
  (IMAP/SMTP) e `oauth_client_id=tt` (o app próprio do tt) continuam valendo.

## v2.1.2 · 21/10/2026
- **🩺 O vigia não trava mais quando a pasta de onde foi lançado some:** ele herdava o diretório de quem o lançou. Apagada essa pasta (um worktree, uma
  pasta temporária), toda sonda de atualização falhava com "getcwd: impossível acessar os diretórios pais" e era acusada como "rede": um Mac ficou 16 sondas
  seguidas sem se atualizar. Agora o vigia vai para a pasta pessoal ao começar, e quem o religa já o lança de lá.

## v2.1.0 · 21/10/2026
- **🎤 A voz decide sozinha e faz planos:** o que você não disser (máquina, IA, sessão) ela escolhe e conta em uma frase. Pedidos grandes viram
  vários passos de uma vez: o que não apaga nada roda direto, e o que fecha, apaga ou junta vira **uma pergunta só** com tudo ("sim" faz tudo,
  "tira o 2" tira um item, "não" cancela). "Apaga a tarefa X e fecha a sessão Y" agora faz as duas coisas.
- **🧩 Temas e juntar:** "resuma por tema" agrupa as sessões abertas por assunto e você age sobre o grupo ("fecha as do deploy"); "junta as abas
  de a e b na c" leva as abas para uma sessão só.
- **🕰️ Conversas antigas de qualquer conta:** "aquela conversa sobre conciliação" procura em todas as máquinas, em todas as conversas do Claude,
  do Codex e do Kiro (não só as abertas), e reabre a escolhida **na mesma conversa**, sem pedir permissões. `tt --busca-conversas TEXTO`.
- **💬 Sessões que conversam:** "peça à sessão backend para validar o que a site fez" entrega a mensagem ao agente de lá, espera a resposta e a
  devolve, na mesma máquina ou em máquinas diferentes (`tt --sessao-falar`).

## v2.0.14 · 21/10/2026
- **🌐 Chromium nativo no Mac:** “Chromium interno” agora abre Google Chrome/Chromium.app pelo LaunchServices,
  com perfil próprio do tt, inclusive quando a sessão está em ponte para outra máquina. Se o app falhar,
  o tt avisa e copia o link; não troca silenciosamente para Safari.

## v2.0.13 · 21/10/2026
- **📰 As novidades voltam a aparecer:** a tela de novidades e o aviso na faixa não mostravam as seções novas. O rótulo da versão sai da
  contagem de commits e anda com commits que não têm texto aqui, então os títulos ficavam abaixo do rótulo instalado e nada contava como
  novo (a tela mostrava só "as 3 mais recentes" e o aviso nunca saía). Agora vale a **ordem do arquivo**: novo é o que está acima do último
  título que você viu, e o aviso sai uma vez por título novo, mesmo que o rótulo ande com outros commits.

## v2.0.9 · 20/10/2026
- **📧 E-mail em texto simples volta a abrir no aerc:** o corpo de uma mensagem só texto (sem HTML) aparecia como se fosse um anexo
  ("No filter configured for this mimetype ('text/plain') — Open using the system handler / Save to file"), enquanto o HTML aparecia bem. A
  seção `[filters]` que o tt escrevia só tinha `text/html` e apagava os filtros de fábrica do aerc. Agora o tt acrescenta os que faltam
  (`text/plain` com quebra na largura do terminal, cores e links clicáveis; `text/calendar`, `message/*`, `.headers`), no cadastro e no reparo que
  roda ao abrir o 📧 (quem já tem o `aerc.conf` antigo é consertado sozinho, e o aerc reinicia uma vez). Um filtro seu continua como está.

## v2.0.8 · 20/10/2026
- **Caminhos pela interface para o que a 2.0.0 trouxe:** `Ctrl+B S` abre os 📸 snapshots; a tela dos snapshots agora liga e desliga a
  funcionalidade (desligada, oferece ligar com ⏎; `^o` desliga, `^n` grava agora); o menu administrar ganhou **🔎 Busca na conversa
  inteira** (liga/desliga) e, no macOS, **🍎 Atalhos no Mac** (estado do Option, tabela Linux → Mac e ativar). Antes só dava pela linha de comando.

## v2.0.4 · 20/10/2026
- **WebSocket reforçado no Mac:** a instalação e o vigia garantem os três serviços e conferem seus listeners.
  Corrigido o caminho dos LaunchDaemons; repetir a garantia não reinicia serviços saudáveis. Falha restaura a
  configuração anterior e aparece no diagnóstico, sem prompt de senha. Linux/Termux e ambientes de teste ficam isolados.

## v2.0.0 · 20/10/2026
Começa o ciclo 2.x.
- **🍎 Tailscale WebSocket automático no Mac:** a instalação e as atualizações agora garantem Node.js/Tailscale,
  aplicam os atalhos padrão do macOS e ativam o fallback WebSocket local versionado, de forma idempotente.
- **📸 Snapshots do estado (ativável):** `tt --snapshots on` grava, a cada aba, sessão, agente de IA ou fixada que muda, um snapshot do
  estado da máquina (abas e painéis na ordem, o agente de IA de cada painel com a conversa e a conta, as fixadas na ordem), até 50, com
  data e hora. `tt --snapshots` (ou administrar → 📸) lista, mostra a árvore e restaura, perguntando o modo a cada vez (aditivo: só recria o
  que falta; substituir: deixa igual). A restauração **retoma cada agente na mesma conversa**, do jeito de cada máquina (Linux, Mac, WSL ou o
  Debian do proot no Termux) e sempre sem pedir permissões: `claude --dangerously-skip-permissions --resume`, `codex resume … --dangerously-bypass-approvals-and-sandbox`,
  `kiro-cli chat --v3 --trust-all-tools --resume-id` (novo `ia-conta retomar`). Antes de restaurar, grava o estado de agora.
- **📋 O chip de tarefas atrasadas mantém o tamanho da fila:** com 2 atrasadas entre 23 abertas aparece `2 (23)`, não só `2`.

## v1.32.0 · 20/10/2026
- **🔎 Busca na conversa inteira:** a central ganhou o escopo **conversa** (`^e`: tudo → nomes → conversa) que procura na conversa
  inteira do agente de cada painel (Claude, Codex, Kiro) e no scrollback inteiro do tmux, não só nas últimas 150 linhas da tela.
  Sem acento nem maiúscula, várias palavras em qualquer ordem, prefixo, `"frase exata"` e `!exclusão`; as outras máquinas
  respondem juntas, o melhor resultado vem primeiro e a prévia pula para o trecho. Índice SQLite FTS5 atualizado pelo vigia só
  com o que mudou. `tt --busca [estado|agora|on|off]`.

## v1.31.0 · 20/10/2026
- **🍎 Atalhos no Mac:** no macOS Ctrl+clique vira botão direito, Ctrl+Shift+V não existe e F1–F10 pedem fn. Agora Option+clique,
  arrastar, duplo e triplo clique fazem o que o Ctrl faz (copiar e abrir link), `Ctrl+B g 1`…`0` chamam os botões F1–F10,
  `Ctrl+B [` copia sem mouse (`v` marca, `y` ou Enter copia) e Cmd+V cola. `tt --mac atalhos` mostra a tabela e `tt --mac ativar`
  liga o Option como Meta no Terminal.app e no Ghostty (`tt --mac status` confere; iTerm2 e WezTerm só orientam).

## v1.30.0 · 20/10/2026
- **🍎 Fallback WebSocket local do Tailscale:** `tt --tailscale-ws ativar` instala o bridge restrito a loopback e os LaunchDaemons para controle/DERP em redes corporativas com Netskope; `status`, `testar` e `desativar` completam a operação. Detalhes em `tailscale-websocket.md`.

## v1.29.1 · 18/10/2026
- **📌 fixa de verdade.** O 📌/📍 da barra alterna e agia duas vezes num toque lento (apertar e soltar com mais de 0,5 s, um
  clique firme no trackpad ou o toque do celular): fixava e desafixava e a sessão ficava como estava. Agora ele age só ao
  pressionar; o soltar é ignorado.
- **📌 numa sessão de ponte fixa a sessão real.** Estando numa ponte (`dell-checkin`), o pino ia para a ponte local, que o
  vigia encerra por ociosidade e o reconciliador então apagava da lista. Agora vale para a sessão da outra máquina
  (`dell:checkin`), e o pino da ponte acende quando ela está fixada.
- **Vigia que morre é religado.** Se o vigia parasse (morto de fora, servidor tmux trocado), ninguém o religava e nada
  sincronizava (e-mail, fixadas, malha, atualização). Cada clique na barra e cada cliente que se anexa conferem (no máximo a
  cada 30 s) e o religam; `tt --vigia-garantir` faz isso na hora. `TT_SEM_VIGIA_AUTO=1` desliga.
- **A malha espera a rede subir depois de um sleep.** Num Mac que dorme, o vigia acorda em janelas de poucos segundos e
  acusava "ilha" (sem rota) com a rede ainda subindo. Se o relógio dá um salto entre duas voltas, a malha só é conferida
  `TT_POS_WAKE` s depois (90 por padrão).

## v1.29.0 · 17/10/2026
- **🎤 Modo retorno: a voz fecha o microfone e as sessões chamam você.** Diga "modo retorno" (ou "me chama quando elas
  terminarem", "pode ir que eu espero"): a janela para de ouvir e mostra quem está em aberto ("⏸ retorno: site há
  3min"). Quando uma sessão a que você pediu algo responde, pede uma decisão sua ou fecha, a voz toca um aviso curto, fala
  (o resultado, ou a pergunta com as opções) e abre o microfone para a sua resposta; em silêncio, volta a esperar.
  Espaço fala com ela, `t` digita, `r` sai do modo.
- **Com prazo:** "modo retorno por 5 minutos" (ou "pode ir que eu espero no máximo 5 minutos"). Se nada chamar nesse
  tempo, a voz chama mesmo assim, com um resumo do que cada sessão fez **desde o seu pedido** (não a tela inteira) e se
  ainda trabalha; cada retorno zera a contagem. Sem nenhum pedido em aberto, ela sai do modo sozinha.
- **No modo, o pedido não espera ouvindo:** "Enviado para site. Te chamo quando responder." e o microfone fecha de novo.
  Respondida uma decisão, a sessão volta a ser esperada. "Ligar o retorno automático" faz cada pedido já entrar no modo.
- **Avisos na hora, sem ficar olhando a tela:** nas sessões abertas pela voz (🚀, 👇, ⏩) o Claude e o Codex avisam quando
  terminam a vez ou pedem algo (o gancho `Stop`/`Notification` do Claude e o `notify` do Codex, passados só a essas
  sessões pela linha de comando; o seu `settings.json` e o seu `config.toml` não mudam), já com a última mensagem do
  agente, que é o que a voz fala. Kiro, Gemini e outros: a voz confere a tela de todas as sessões de uma máquina numa ida só.
- "Sair do modo retorno", "cancele a espera" e "o que você está esperando?" valem também para o modo. `voz --retorno
  [SEGUNDOS|sair|auto sim|nao]`, e o cérebro entende as ações `retorno`, `sair_retorno` e `retorno_auto`.

## v1.28.15 · 17/10/2026
- **Vigia no celular e no Mac:** a sincronização das contas de e-mail em paralelo (v1.28.10) esperava as contas com um
  `wait` sem lista, o que no bash 5.3 (Termux e Mac) já deixou o vigia preso a 100% de CPU. Agora espera só as contas
  que ela mesma começou.

## v1.28.14 · 17/10/2026
- **Ponte vinda do Mac: o clique numa sessão não se perde mais.** Vendo outra máquina pelo Mac, o clique numa sessão pede ao
  Mac que troque a tela. O Tailscale SSH do macOS responde sempre "deu certo" (código de saída 0); quando o Mac não
  conseguia, o tt achava que tinha ido e não fazia nada. Agora vale a resposta escrita de lá, e se o Mac diz que não, a
  ponte abre daqui. O mesmo vale para a roda no chip da máquina, para o 🎤 aberto pela ponte e para conferir se a sessão
  de lá existe.
- **Rede lenta até a máquina da tela:** depois de 1,5 s sem resposta aparece "⟳ esperando … responder"; em 10 s
  (`TT_T_PONTE`) o tt desiste com "não respondeu; a tela não trocou". O pedido que chegar lá depois disso não faz nada:
  antes, cliques presos numa rede travada chegavam todos juntos minutos depois e trocavam a tela várias vezes.

## v1.28.0 · 17/10/2026
- **🎤 A voz não lê mais as telas de abertura dos agentes.** Na sessão que ela abre (o 🚀 pela voz, o 👇 e o ⏩), o tt
  responde sozinho o que é rotina, no Claude, no Codex, no Kiro ou em outro agente: pular a atualização, aceitar os termos
  sem ceder as conversas para treino, o tema, o "Enter para continuar", o aviso do modo sem permissões que o próprio 🚀
  pediu, o login que já deu certo. A voz fala só o resultado do agente e as perguntas que são suas.
- **Segurança:** "confiar nesta pasta" só vai sozinho se a pasta está na sua lista (`voz --pastas add '~/Projetos/**'`;
  quando a voz pergunta, "sempre" põe a pasta na lista). Senha, login ou chave, algo destrutivo (apagar, sobrescrever,
  `rm -rf`), permissão nova de execução (rodar comando, editar, servidor MCP, "não perguntar de novo") e créditos a voz
  nunca aprova: lê a pergunta e as opções e espera o seu número, sim ou não. Senha ela manda você digitar no terminal. O que
  foi respondido sozinho fica em `~/.local/state/tt-voz/aprovacoes.log`.
- **Catálogo das telas, fácil de estender:** `telas-agentes.conf`, um bloco por tela de cada agente; os seus vão em
  `~/.config/tt/telas-agentes.conf` (um bloco com o mesmo nome troca o do pacote; `classe = -` desliga).
- **⏱ "Espere um minuto e depois confira a sessão".** A voz agenda (segundos, minutos, "um minuto e meio", até 6 h), fica
  livre para outros pedidos e, na hora, confere e fala sozinha o resultado (ou resume, ou só avisa). "Me avise quando ele
  terminar" e "acompanhe a sessão" vigiam até concluir e falam também quando ela pedir uma decisão. "O que você está
  esperando?" lista; "cancele a espera" cancela. No celular, o mesmo, pelo Tasker ou pelo bot.
- **🧭 A interface do tt pela voz.** Fixadas: fixar, desafixar, listar, mover (início, fim, esquerda, direita, posição) e
  agrupar. Tarefas: criar ("nova tarefa comprar pão para amanhã às 14 horas"), subtarefa, concluir, reabrir, prazo, tirar
  o prazo, apelido e apagar (com o seu sim). Notificações: ler as não lidas, marcar como lidas, limpar as lidas (com o sim).
  Letreiro: ler, pausar, continuar.
- **🧹 Fechar sessões e limpeza.** "Feche a sessão X" pede o seu sim; se é a escolhida ou se está trabalhando, pede duas
  vezes. "Limpeza" olha todas as sessões de todas as máquinas e sugere as paradas, cada uma com o motivo ("terminal sem
  programa, parado há 2 dias"; "Claude parado há 5 horas; por último: …"); as que estão em uso, fixadas, com alguém
  olhando, com texto não enviado ou com o agente esperando a sua resposta ficam. "Fechar" fecha a lista, "tira a dois"
  deixa uma de fora, "cancelar" não fecha nada.
- **Pela linha de comando:** `tt --notifs-listar`, `tt --notifs-limpar-lidas`, `tt --letreiro-ler`,
  `tt --letreiro-pausa sim|nao`. No macOS, a marca de pausa do letreiro passa a ficar na mesma pasta temporária que o tt
  usa (antes ia para `/run/user`, que lá não existe).

## v1.27.5 · 16/10/2026
- **🖥️ Terminal interativo para agentes (`tt --pty`).** Um agente de IA não tem tty: `sudo`, `ssh`, `vim` e instaladores ficavam fora
  de alcance. Agora ele abre uma sessão tmux própria (`ia-pty-NOME`), digita, lê a tela e espera por um texto; você entra nela
  (`tt --pty entrar`) para digitar o que o agente não deve ver, como a senha. Funciona igual no Linux e no macOS e entra nas regras
  que todos os agentes recebem.
- **🍎 O e-mail (aerc) não abria no macOS.** O aerc só procura estilos e configuração em `~/Library/Preferences/aerc` no macOS, e o tt grava
  tudo em `~/.config/aerc`: o aerc morria ao abrir com "Can't find styleset tt-catppuccin" e o tt avisava "o aerc fechou sozinho". A sessão
  oculta do e-mail agora roda com `XDG_CONFIG_HOME` apontando para `~/.config` (igual no Linux).
- **🍎 "Sudo sem senha" no macOS.** O passo gravava a regra com `install -g root`, mas o macOS não tem grupo `root` (é `wheel`): falhava e
  o tt culpava a senha ("senha errada?"). Agora usa o grupo real do root e a mensagem de erro é mais precisa.


## v1.27.4 · 16/10/2026
- **🔒 E-mail OAuth e uso das contas de IA em redes com inspeção de TLS.** O Python 3.13+ rejeita, no modo estrito de X.509, a CA de
  inspeção de redes corporativas (Netskope e afins) que o sistema já confia mas que não declara `keyUsage`: a renovação do token do
  Gmail OAuth e a consulta de uso das contas falhavam com "CA cert does not include key usage extension". O `email-tt.py` e o
  `contas-uso.py` passam a usar um contexto TLS sem só esse critério estrito; a cadeia, o nome do servidor e a data seguem verificados.

## v1.27.3 · 16/10/2026
- **🍎 Janelas soltas no macOS e testes isolados.** O tt acha as janelas de terminal soltas (fora do tmux) também no macOS e passou a
  ter `TT_SEM_SOLTOS=1`, que os testes ligam para que as janelas abertas na máquina de quem roda a suíte não apareçam nas listagens
  (o `test_listar_lote` reprovava só por isso).

## v1.27.2 · 16/10/2026
- **📌 Fixada de outra máquina que dizia "desligada" sem estar.** Às vezes o clique numa fixada de outra máquina dizia
  "máquina não cadastrada ou desligada" e não ia; depois de vários cliques, ia. O tt confiava na marca "Online" do
  Tailscale, que oscila com a máquina de pé e o ssh funcionando (a empresa viu o Dell "desligado" por mais de um minuto
  com o túnel aberto). Agora a máquina só sai da lista quando o Tailscale a dá como fora, sem tráfego recente e vista
  pela última vez há mais de 5 min. E o clique para ir a uma sessão dela (fixada, ponte) tenta o ssh assim mesmo: vai, se
  ela responder; senão avisa que ela não respondeu.

## v1.27.0 · 16/10/2026
- **🍎 O tt agora roda no macOS (Homebrew), de ponta a ponta.** `./instalar.sh` instala o que o sistema não tem (bash 5, tmux,
  fzf, ripgrep, as ferramentas GNU — coreutils, sed, tar, findutils, grep, gawk, util-linux — e um Python novo) e o `tt` põe
  essas versões na frente do PATH **só dos processos dele**; a janela nova volta ao PATH de origem, então o `ls`, o `sed` e o
  `grep` dos seus painéis seguem os do sistema.
- **Janela nova do Terminal.app/iTerm abre direto no tt** (o `~/.zshrc` ganha um bloco). O `env bash` do macOS achava o
  bash 3.2 e o tt quebrava na sintaxe: agora o tt e os auxiliares (`ia-conta`, `ia-login`, `ia-rot`, `voz`, o gatilho do
  letreiro) se reexecutam no bash do Homebrew, e o bloco do zsh nunca fecha a janela se não houver bash 4+.
- **Correções que só aparecem no Mac:** o e-mail ✉ abre no zsh (o `=_tt-email` sem aspas virava "comando não encontrado");
  pontes vindas de outra máquina (você vendo o Mac pelo `dell`) são reconhecidas sem `/proc`, então links e atalhos abrem
  na tela certa; o letreiro anima a 6 quadros/s (rodava a 1); janelas de terminal soltas e agentes (Claude, Codex, Kiro) são
  achados pelo `ps`/`lsof`; as contas de IA em uso (`ia-conta`) são vistas por `ps eww`; `/var` e `/private/var` são a mesma
  pasta para casar conversa e painel; o título dos popups com emoji sai inteiro (o macOS não tem `C.UTF-8`); `flock` portátil.
- **🛡 Guardião de portabilidade para os agentes.** Nova seção "Portabilidade" no `AGENTS.md`, no bloco de regras que o tt
  instala em todos os agentes de todas as máquinas e na skill; e o `tests/test_portabilidade.sh` reprova código novo que
  reintroduz o que só funciona no Linux (`/proc` direto, `=alvo` sem aspas, `$variável` em `if-shell`, script bash 4+ sem
  guarda, `C.UTF-8`, `exec -a` em teste…). A suíte inteira passa no macOS: `tests/run.sh` põe sozinho o que precisa no PATH
  e há um `script(1)` sobre pty em `tests/macos-bin`.

## v1.26.0 · 16/10/2026
- **📌 A roda no chip `+N ▾` das fixadas:** para cima, as abas escondidas giram junto com a última visível ao lado do
  chip (a próxima escondida aparece); para baixo, todas as abas giram uma casa.
- **📌 Botão direito no chip:** agrupa as fixadas por máquina, com as sessões de uma mesma máquina lado a lado (as
  máquinas na ordem em que aparecem; dentro de cada uma, a ordem de antes). No popup das fixadas, `^g`.

## v1.25.0 · 16/10/2026
- **🎤 Escolher a sessão já a libera.** Acabou o "diga sim para liberar": escolheu (pelo número, pelo nome, pelo
  cérebro, ou abrindo uma nova), pode falar com ela. "Bloquear sessão" a solta.
- **🎤 Sessão nova pelo rodízio:** "abra uma sessão nova na empresa" abre o agente da conta com mais folga naquela
  máquina (antes, lia a lista de sessões). Com a IA ("com o codex") e com um pedido ("para revisar o bimo"), que vai
  assim que ele abre.
- **🎤 As sessões de todas as máquinas:** a janela guarda um índice delas (agente, título, trabalhando ou parada) e
  acha a sessão pelo nome ou pelo assunto em qualquer máquina. "Panorama" ou "resumo de todas as sessões" lê todas ao
  mesmo tempo e resume o que cada uma faz, em segundos (antes, uma por uma, minutos). Frase longa que só cita a máquina
  não vira mais "sessões da empresa": vai ao cérebro.
- **🎤 Respostas mais rápidas:** o Claude do cérebro fica aberto enquanto a janela está aberta, e cada volta leva
  ~1,5 s (eram ~7 s). As conexões com as outras máquinas são as do tt, já abertas.
- **🎤 Janela maior e com rolagem:** um pouco mais larga e quase da altura da tela; a roda do mouse, as setas,
  PgUp/PgDn e Home/End rolam a conversa, e ela não pula quando chega texto com você lendo lá em cima.
- **🎤 Primeira vez numa máquina:** nada de traceback na tela. Sem o reconhecimento de voz instalado, a janela oferece
  instalar ali mesmo, em segundo plano (também sem o `python3-venv`, sem sudo), e passa a ouvir quando termina.

## v1.24.2 · 16/10/2026
- **⌨ Seta não vira Esc com a máquina ocupada.** As telas que leem tecla por tecla (transferências, confirmações e
  escolhas das tarefas, calendário, a espera do login OAuth do e-mail) davam 30 a 50 ms para o resto de uma seta
  chegar depois do ESC. Com a máquina carregada, ou por ssh e mosh, ele chega depois: a seta virava Esc e a tela
  fechava. Agora a espera é de 0,3 s (`TT_ESC_SEQ` muda). Um Esc sozinho continua fechando, só um pouco depois.
- **🖱 Duplo clique nas tarefas com a máquina ocupada.** Os 400 ms do duplo clique contavam do começo do 1º clique, e
  o tempo que o próprio tt leva para recarregar a lista entrava na conta: com a máquina carregada, dois cliques rápidos
  viravam dois simples. Agora contam do fim do 1º clique.

## v1.24.1 · 16/10/2026
- **🎤 Sensibilidade do microfone.** Um headset com filtro de ruído próprio (o BlackShark, por exemplo) entrega a voz
  baixa, e o tt respondia "não ouvi" mesmo com você falando. Nas opções (`c`), `g` troca a sensibilidade: normal,
  alta, máxima ou baixa. A escolha fica guardada; pela linha de comando, `voz --limiar alta`.
- Quando ouve um som que durou mas não chegou a contar como fala, a janela diz isso uma vez, com o nível, e mostra como
  aumentar a sensibilidade, em vez de só "não ouvi".

## v1.24.0 · 16/10/2026
- **🎤 Você escolhe onde transcrever.** Nas opções (`c`), aperte `l`: esta máquina, uma das outras cadastradas ou
  automática. Digite o número e Enter; Esc cancela. A escolha fica guardada e o motor troca ao voltar à conversa, sem
  fechar o 🎤. Se a máquina escolhida falhar, o motor anterior continua e a janela explica o problema.
- A escolha também está em `voz --opcoes`. Pela linha de comando: `voz --transcrever local`, `voz --transcrever NOME`
  ou `voz --transcrever auto`.

## v1.23.1 · 16/10/2026
- **🎤 Microfone no mudo é percebido.** Um headset no mudo (o botão dele) entrega silêncio absoluto, e o 🎤 ficava
  "ouvindo" esse microfone sem nunca ouvir você. Agora o tt passa para o microfone seguinte e avisa na janela ("o
  BlackShark não manda som nenhum: está no mudo?"); no meio da conversa, se o microfone emudece, a janela avisa igual
  (c e depois n troca o microfone).
- **🎤 A tecla v das opções não troca mais para a voz do sistema sem querer** quando as vozes neurais ainda não estão
  disponíveis (a máquina que transcreve não respondeu): ela diz que nenhuma voz neural está disponível agora.

## v1.23.0 · 16/10/2026
- **🎤 Sem travar ao perguntar o estado de uma sessão.** "Qual o estado dessa sessão?" esperava o agente terminar
  (até 2,5 min, em silêncio). Agora o cérebro recebe a tela de agora da sessão e responde na hora: o que o agente está
  fazendo, se está trabalhando e há quanto tempo. Depois de mandar um pedido ao agente, a janela espera no máximo uns 30 s;
  se ele segue trabalhando, ela diz "eu aviso quando terminar" e volta a ouvir, e quando ele termina, fala a resposta
  sozinha. O que já estava pronto para dizer sai antes de qualquer espera.
- **🎤 Nas sessões que mostram outra máquina (pontes),** a leitura e o texto vão à sessão de verdade de lá, a que a
  ponte está mostrando agora: sem as barras do tt e o rodapé do agente lidos como resposta ("Update installed",
  "Crunched for…").
- **🎤 A voz é do aparelho onde você clica.** O 🎤 clicado numa ponte (vendo esta máquina de outra) abre a janela na
  máquina de origem, com o microfone e o som dela, já com a sessão que estava na tela como alvo da conversa.

## v1.22.0 · 16/10/2026
- **🎤 Vozes neurais: a resposta deixa de soar robótica.** A voz passa a ser gerada no motor (nesta máquina ou na
  que transcreve, por exemplo o computador com GPU) e tocada no aparelho do microfone. A padrão é a **Piper Faber**,
  neural e offline. Também dá para escolher as vozes neurais da Microsoft (**Francisca**, **Antônio** e **Thalita**,
  as mesmas do Edge), que soam quase humanas, mas são online: o texto falado vai para o serviço da Microsoft. A da
  versão anterior continua como "a do sistema".
  - Nas opções da janela (**c**), **v** passa à voz seguinte e já fala um exemplo, para você escolher pelo ouvido. A
    escolha fica guardada (`voz --voz`).
  - A fala vai frase a frase: a primeira toca enquanto a seguinte é gerada.
  - O `voz --instalar-audio` também instala o `edge-tts`.

## v1.21.1 · 16/10/2026
- **📧 Microsoft com o app do próprio tt.** Conta Outlook, Hotmail ou Microsoft 365 com OAuth2 agora entra de
  fábrica pelo app "tt-terminais" do tt na Microsoft, como já acontecia com o Gmail. A tela de consentimento
  mostra o nome do tt, não o do Thunderbird. Conta pessoal entra com um aviso de publicador não verificado;
  numa empresa, o administrador costuma precisar aprovar o app. Quem precisar do ID do Thunderbird (às vezes já
  aprovado no tenant da empresa) digita `thunderbird` no lugar do client_id. Contas já cadastradas continuam
  com o app que usavam.

## v1.21.0 · 16/10/2026
- **🎤 A voz sai no aparelho do microfone.** O tt falava na saída padrão do sistema. No Windows ela costuma ser o
  alto-falante ou a saída P2, e o headset é só o padrão de chamadas: a resposta ia para onde ninguém ouvia, e a janela
  ficava "falando" em silêncio. Agora a fala sai no mesmo aparelho do microfone escolhido (o BlackShark ouve e fala),
  sem mudar os padrões do Windows; sem par, vai a saída de melhor nota (fone antes de alto-falante). Vale no WSL (a
  voz do Windows num processo só, que abre uma vez), no Linux (PulseAudio/PipeWire) e no macOS (`say -a`).
- **🎤 Opções na interface.** Na janela, **c** abre as opções: o modelo do cérebro (1 Haiku, 2 Sonnet, 3 Opus), o da
  transcrição (automático ou um fixo, com o que esta máquina mediu de cada um), o microfone (n) e a saída de som (s).
  A escolha fica guardada. Fora da conversa: botão direito do 🎤 → "Opções: modelos, microfone e som" (`voz --opcoes`).
  `voz --saida "nome"` fixa a saída.

## v1.20.0 · 16/10/2026
- **🎤 O tt escolhe sozinho o melhor jeito de ouvir e de transcrever, em cada máquina.**
  - **O microfone pelo tipo:** o headset (ou um microfone dedicado) antes do USB e do Bluetooth, depois a webcam, por
    último o embutido; o que não entrega áudio fica de fora. No Windows (WSL), o tt grava direto do microfone escolhido,
    sem mudar o padrão do Windows (o das chamadas). Na janela, **n** passa ao microfone seguinte, e o tt lembra da
    escolha; `voz --microfone "nome"` fixa uma preferência.
  - **A transcrição pela medida:** cada máquina com o Whisper mede cada jeito que tem (o modelo × a CPU ou a GPU NVIDIA)
    em tempo e em erro, e a janela pergunta a todas as suas máquinas ao mesmo tempo e fica com a de menor custo, contando
    a carga de agora e a rede. As desligadas ficam de fora sem esperar; o tempo de cada frase corrige a próxima escolha, e
    se a escolhida ficar lenta no meio da conversa a janela passa para outra sozinha. Com GPU NVIDIA, o
    `voz --instalar-audio` põe as bibliotecas CUDA (num notebook com GeForce MX250: 0,9 s por frase, contra 2,6 s na CPU).
  - **O cérebro passa a ser o Sonnet:** medido com frases reais, ele acerta as ambíguas que o Haiku errava (escolher a
    sessão citada e pedir para liberar, perguntar qual sessão, não agir sobre uma frase mal transcrita), por ~1 s a mais.
    `voz --cerebro-modelo haiku` volta ao mais rápido.
  - `voz --audio` mostra os microfones, as medições, a GPU e o ranking; `voz --medir` mede de novo.

## v1.19.1 · 16/10/2026
- **🎤 Voz no celular sempre atualizada.** O `voz` do celular rodava a cópia do clone usado na instalação
  (`~/tt-terminais`), que não se atualiza sozinho: o daemon do Tasker ficava sem os consertos novos. Agora ele roda o
  `voz` do tt instalado, que acompanha cada versão publicada.

## v1.19.0 · 16/10/2026
- **🎤 Conversar com o tt pela voz, também no computador.** Um botão novo na barra, o 🎤 (ou `Ctrl+B v`), abre uma
  janela de conversa: você fala, ela mostra o que entendeu, o tt age e responde falando. Vale no Linux, no macOS e no
  Windows pelo WSL; no celular, o Tasker continua ouvindo e falando, e a janela mostra a conversa. O que dá para pedir
  é o mesmo do celular: máquinas e status, sessões, falar com um agente (só nas sessões que você liberou), abrir uma IA
  como o 🚀, trocar a do painel como o 👇, passar a conversa como a ⏩, tarefas e subtarefas, o uso das contas. O
  cérebro (um Claude rápido) já vem ligado na janela, nesta máquina.
  - Na janela: **Espaço** encerra a frase ou pula a fala, **t** digita (no escritório ou sem microfone), **m** tira a
    voz, **Esc** fecha. O botão direito do 🎤 tem "Só digitando", "Testar o microfone e a voz" e "Instalar a voz neural".
  - Cada sistema usa o que tem: no Linux grava pelo servidor de som e, se ele perdeu a placa, direto pelo microfone; no
    macOS, `sox` ou `ffmpeg` e a voz Luciana do `say`; no WSL, o som do WSLg e a voz pt-BR do Windows. A transcrição é o
    Whisper: aqui, com `voz --instalar-audio` (instala também a voz neural Piper), ou numa máquina sua que o tenha, por
    ssh, sem instalar nada. `voz --audio` diz o que esta máquina usa. Guia: README, "Conversar com o tt pela voz".
  - Atalho da barra com `@janela CMD`: roda o comando numa janela flutuante, em vez de numa sessão nova.

## v1.18.5 · 16/10/2026
- **🎙 Voz: consertos no celular.** "contas", o 🚀 por voz ("nova sessão com o codex") e as contas que o cérebro conhece
  agora vêm do Linux do proot, onde o tt instala as contas de IA do celular (o `ia-conta` do Termux não as via: dizia
  "principal, desconhecido" e não achava o codex). Na leitura das tarefas, "14 de 11 subtarefas" saía de uma data
  (`14/11`) ou do título (`BIMO-989/990`): agora conta só a barra de progresso; na agenda (hoje, com prazo) diz o dia
  do grupo e a hora, sem ler "12:00 pese74". O `ia-rot -p` com o pedido pelo stdin (o cérebro) entrega o mesmo pedido à
  próxima conta quando a primeira bate no limite (antes ia vazio e a volta caía nas regras).
- **🎙 Voz: tarefas abertas, de hoje ou com prazo.** Pelo cérebro, "quais tarefas eu tenho para hoje" e "o que tem prazo"
  leem a lista certa, numa aba própria das tarefas (o filtro do painel não muda), e o prazo é lido inteiro ("prazo venceu
  ontem 14:00") (veio na v1.18.1 e na v1.18.2).


## v1.18.4 · 16/10/2026
- **🔔 E-mail novo, lembrete de tarefa e demanda por e-mail chegam uma vez só.** Cada máquina que espelha uma conta
  percebia o mesmo e-mail e criava o seu aviso, e o 🔔 mostrava um por máquina (três "📧 1 e-mail novo" iguais). O
  mesmo acontecia com os lembretes 📋 e as demandas 📥. Agora cada aviso leva a identidade do evento (no e-mail, a de
  cada mensagem): a máquina que chega depois só avisa o que nenhuma outra avisou, e cópias criadas ao mesmo tempo
  viram uma na sincronização. A notificação do sistema (a do celular, a da área de trabalho) continua saindo em
  cada aparelho.

## v1.18.3 · 16/10/2026
- **🧩 aidlc-tt não cai por causa de outra tarefa.** `aidlc-tt publicar/colher/estado` lê todas as tarefas para achar a
  ligada ao arquivo de perguntas; uma descrição de OUTRA tarefa com o base64 truncado ou sem o `=` do fim derrubava o
  comando com "Incorrect padding". Agora a descrição sem `=` é lida e a corrompida é ignorada.

## v1.18.0 · 16/10/2026
- **🧠 Voz com cérebro (opcional).** `voz --cerebro "pc local"` faz um Claude rápido entender frases soltas ("como anda o
  claude da empresa?", "abre um codex no pc", "lê as três últimas respostas") e agir no tt; comandos curtos continuam
  instantâneos. Por voz também dá para abrir sessões como o 🚀 (com a IA ou a conta que você disser, já passando pelas
  perguntas de abertura como "confiar nesta pasta" e "pular atualização"), trocar a IA da sessão como o 👇, passar a
  conversa adiante como o ⏩ e ouvir uma tarefa com as subtarefas que faltam. Guia: skill `celular-android`, seção 15.

## v1.17.0 · 15/10/2026
- **🎙 Falar com o tt pela voz, no celular e no carro (opcional, só no celular).** `termux/celular.sh voz` liga uma
  conversa por voz com o tt: listar máquinas, ver o status, trocar de máquina e de sessão, ler tarefas e o uso das contas
  de IA, e conversar com um agente indo e voltando. Fora do carro, o celular ouve pelo microfone e responde falando; no
  Android Auto, um bot seu do Telegram manda "pronto" quando o carro conecta, e você responde falando na tela do carro.
  Diga "ajuda" para saber como usar. Texto livre só vai a sessões que você liberou. Quem não ativa não vê nenhuma
  mudança. Guia: skill `celular-android`, seção 15.

## v1.16.2 · 14/10/2026
- **↶ Desfazer a conclusão de uma tarefa que repete.** Concluir uma tarefa recorrente não a deixa marcada: o prazo avança para o próximo ciclo. Era fácil clicar de novo achando que não tinha pegado, e não havia volta. Agora:
  - ao concluir, o topo do painel avisa `✓ Ciclo feito · próximo: 14/11 · ^z desfaz`, e a linha mostra **✓ ciclo feito** por 24 h;
  - `Ctrl+Z`, **↶ Desfazer a última conclusão** no menu da tarefa (com a data para onde o prazo volta) ou `tt --tarefa-desfazer ID` voltam um ciclo por vez, até 3, e devolvem a feitas as subtarefas que aquele ciclo reabriu;
  - o cartão da tarefa (`^/`) mostra quantos ciclos já foram feitos;
  - numa tarefa que não repete, desfazer reabre a tarefa feita.

## v1.16.0 · 14/10/2026
- **🖱 Roda do mouse nos chips da barra.** Sobre o chip azul da máquina, a roda troca de máquina: para baixo a seguinte, para cima a anterior, na ordem do cabeçalho da central, dando a volta. Você cai na primeira sessão da lista de lá (a de uso mais recente) e, se não houver nenhuma, uma nova é criada. Máquina que não responde em uns 3 s é pulada com aviso, e por 1 minuto a roda nem tenta de novo. Sobre o chip da sessão, a roda passa pelas sessões desta máquina, na ordem do `Ctrl+B (` e `)`, sem pontes nem sessões ocultas. Uma rolagem longa anda um passo por vez. Vendo outra máquina pela ponte, a troca acontece na máquina da tela, na ordem dela. No resto da barra, a roda faz o de sempre (janela anterior/seguinte).
- **☰ Menu no botão direito dos atalhos.** O clique no atalho continua igual. O botão direito agora pode abrir um menu com outros jeitos de rodar o mesmo atalho, configurável na 5ª coluna do atalho (também pelo ✏ editor de atalhos), com opções fixas (`Rótulo=comando`) ou dinâmicas:
  - **@contas**: no 🚀 e no 👇, uma opção por conta de IA cadastrada no `ia-conta`, com o uso de cada uma, para abrir uma conta específica em vez de deixar o rotador escolher. A lista sai do próprio comando do atalho, então no celular vêm as contas do Debian;
  - **@maquinas**: o mesmo atalho noutra máquina, numa sessão nova de lá, e a tela vai junto.
  Atalho sem menu continua mostrando o comando no botão direito, como antes.
- **⏩ Seguir a conversa com outra IA (atalho novo).** No painel com uma conversa de IA (Claude, Codex ou Kiro), a ⏩ acha a conversa e o código dela, encerra aquela IA e abre outra pelo rotador (em geral uma conta com mais créditos), com o pedido para ler a conversa inteira e seguir integralmente o trabalho de onde parou. O clique segue nesta máquina, no mesmo painel. No botão direito, escolha outra máquina: ela abre a nova IA numa sessão de lá, busca a conversa na máquina de origem pela rede do tt, e só então a IA daqui fecha e a tela vai para lá. O pedido diz qual é a máquina de origem e como entrar nela, porque os arquivos do trabalho continuam lá.
- **📜 `tt --conversa-ia CÓDIGO`** mostra qualquer conversa do Claude, do Codex ou do Kiro em texto legível (as falas inteiras e as ferramentas com o que devolveram, resumido), desta máquina ou de outra (`--de MÁQUINA`). Com `--salvar`, grava em `~/.cache/tt/conversas/`.
- **📌 Dois toques rápidos no pino ou no ✕ da central não a fecham mais.** O 2º toque rápido (fixar e logo desafixar, ou pedir a confirmação do ✕ e confirmar) era tomado como duplo clique, que abria a sessão e fechava a central. Agora são dois toques, na central e no seletor de sessões.
- **🤖 `ia-conta abrir --conta NOME`** abre uma conta específica, sem passar pelo rotador. `ia-conta abrir --listar-contas` lista as contas que dá para abrir na máquina, com o último uso conhecido.

## v1.15.7 · 13/10/2026
- **📎 Anexos abrem e são salvos na máquina onde você está.** Vendo pela ponte o e-mail de outra máquina (por exemplo, o do PC pelo notebook ou pelo celular), o anexo abria e era salvo na máquina do e-mail, longe da sua tela. Agora segue a mesma regra dos links:
  - **O** (abrir) leva o arquivo para a máquina da tela e abre nela, no programa padrão (PDF, planilha, áudio, vídeo, imagem; a tecla **i** das imagens também). Se ela não responder, abre na máquina do e-mail, como antes.
  - **S** (salvar) manda o anexo para a pasta de recebidos da máquina da tela. Usando o e-mail na própria máquina, pergunta a pasta, começando pela de recebidos, e não sobrescreve: um arquivo repetido chega como "nome (2)".
  - **E** (enviar) abre o seletor de máquina já com a da tela em primeiro, marcada "(onde você está)".

## v1.15.6 · 13/10/2026
- **📰 "tt atualizado" chega uma vez só, não uma por máquina.** Cada máquina que se atualizava criava o seu aviso de novidades, e quem tem 4 máquinas via 4 avisos iguais no 🔔. Agora o aviso leva um código da versão, igual em todas: a rede guarda um só, ler numa máquina vale para todas, e o aviso apagado não volta quando outra máquina se atualiza depois.
- **🕸 Celular sem o DNS do Tailscale volta a alcançar as outras máquinas.** Quando o Android não resolve os nomes da tailnet, a malha agora religa pelo IP da tailnet, que as máquinas com Tailscale passam a anunciar. Trocar uma máquina para um IP também não apaga mais do cadastro as outras guardadas por IP.
- **🕸 Celular sem o DNS do Tailscale reaprende a máquina que perdeu do cadastro.** A malha só tentava o nome de uma máquina nova para ele, e o nome não resolve no celular: uma máquina que saiu do cadastro dele (como a apagada pelo IP cortado, consertado no item acima) não voltava mais. Agora, se o nome não conecta, ela é aprendida pelo IP da tailnet que as outras anunciam.
- **🕸 Máquina desligada não é ilha.** Desligada no Tailscale, ela aparece `○` em todas as linhas do `tt --malha`, inclusive na do celular, que não tem como saber disso. Antes, o aviso de ilha ficava tocando enquanto ela estivesse desligada.
- **🕸 Sem ilha falsa quando o `tt --malha` roda junto com o vigia.** As duas rodadas usavam a mesma pasta de respostas, e uma apagava a da outra: aparecia "não respondeu ao diagnóstico" para uma máquina que estava bem, e duas voltas assim viravam o aviso de ilha.
- **🩺 A checagem vê a volta completa do e-mail.** Se o sync das outras pastas (fora o INBOX) falhar seguidas vezes, o `tt --checar` avisa e mostra a causa. Uma pasta que sumiu do servidor e ficou no espelho fazia toda volta completa falhar sem aviso.
- **🩺 Sem falso "atualização pendente" logo depois de atualizar.** A checagem comparava com a versão publicada vista antes da instalação.
- **📧 E-mail aberto em outra tela não fecha por causa de pasta nova.** Desde a v1.15.5, pasta nova no espelho (uma etiqueta criada no Gmail, por exemplo) fazia o clique no 📧 de outra tela fechar o e-mail que estava aberto, inclusive uma resposta pela metade. Agora o e-mail só é reaberto quando não está aberto em nenhuma tela.
- **🔐 O pedido do "sudo sem senha" não se diz mais "sem administrador".** O modal listava o passo também em "Baixado/compilado na sua pasta (sem administrador)", mas ele grava uma regra do sistema com o `sudo`: agora aparece só em "Configuração do sistema", com o comando exato.

## v1.15.5 · 13/10/2026
- **🗑 Apagar funciona logo depois do conserto, sem reabrir o e-mail.** O aerc que já estava aberto não enxergava uma pasta criada depois dele (a lixeira que o 🩺 conserto acabou de trazer): o ✕ Apagar continuava com "could not move message … no such file", mesmo com o conserto dizendo ok. Agora, quando aparece pasta nova no espelho, o e-mail é reaberto sozinho na próxima vez que você clica no 📧.

## v1.15.4 · 13/10/2026
- **🗑 Apagar funciona até em caixa gigante, e se conserta sozinho.** Com um INBOX de dezenas de milhares de mensagens, o espelho local nunca terminava a primeira volta, recomeçava a cada poucos minutos e acabava estourando a cota diária do Gmail ("OVERQUOTA"). A lixeira só vinha depois, então nunca chegava, e o ✕ Apagar não tinha para onde mandar. Agora:
  - O espelho guarda só as últimas 5000 mensagens do INBOX (`TT_EMAIL_INBOX_MAX` muda). As outras continuam no servidor, e o ⚡ Em lote age nelas.
  - A lixeira tem um sincronismo só dela, que roda antes de tudo. O 🩺 conserto cria a lixeira no espelho na hora (o apagar volta a funcionar mesmo sem rede ou com a cota estourada) e sincroniza só ela.
  - Quando o Gmail responde que a cota acabou, o tt espera 2 horas antes de tentar de novo, em vez de insistir a cada poucos minutos, e o `tt --email-sync-estado` explica o que houve.
  - Nada a fazer: ao atualizar, cada conta é regravada no formato novo e os comandos de apagar se conferem e se consertam sozinhos; depois de cada sincronização completa, de novo.
- **⚡ Busca com acento no e-mail em lote.** `assunto:"solicitação"` dava sempre "este servidor não aceita busca com acento". Agora funciona no Gmail.
- **🕸 `tt --malha` não cai mais** com "trava: unbound variable" antes de mostrar quem alcança quem.

## v1.15.3 · 13/10/2026
- **🔐 "sudo sem senha" virou pendência.** Enquanto o `sudo` desta máquina pedir senha, o 📦 oferece ativá-lo. Ao aceitar, você digita a senha uma última vez e o tt grava uma regra em `/etc/sudoers.d/` (conferida pelo `visudo` antes de entrar, modo 0440). Daí em diante o tt e os agentes ligam o ssh do sistema, instalam pendências e corrigem a máquina sem pedir senha. O modal mostra o comando exato. Para desfazer: `sudo rm /etc/sudoers.d/tt-sem-senha-<seu usuário>`.

## v1.15.2 · 13/10/2026
- **🔌 Nenhuma máquina vira ilha por falta de ssh.** Se nada atende na porta do ssh (o caso de um WSL, que não liga o servidor ssh quando o Windows sobe), o tt resolve sozinho, sem esperar ninguém: com `sudo` sem senha, liga o ssh do sistema; senão, sobe **um ssh do próprio usuário na porta 8022, sem root**, que só aceita chave. As outras máquinas já tentam a 8022 quando a 22 não responde e passam a usá-la sozinhas.
  - O vigia confere a cada 5 minutos e religa se cair. Faltando o programa (openssh-server), vira pendência essencial no 📦.
  - Só vale para máquina que tem outras cadastradas (fora da malha, nenhuma porta é aberta). `sshd_garantir=0` no config desliga; `tt --sshd-garantir` faz na hora. O `tt --checar` passa a ter a linha `sshd`.
- **📧 O e-mail não se abre mais dentro de si até cair.** Com as janelas flutuantes, uma tecla do tt digitada dentro do e-mail (a central, a sessão anterior, as teclas de sessão do tmux) levava o e-mail à sua própria sessão, e a tela se desenhava dentro de si mesma até o tmux fechar. Agora o e-mail volta para o lugar dele na hora, e qualquer outra janela que passasse a mostrar a si mesma é fechada com um aviso.
- **🩺 Pacote de handoff mais limpo:** a linha da plataforma não cola mais no kernel, e os arquivos temporários do sync de e-mail ficam de fora.

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
