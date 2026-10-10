# Novidades do tt-terminais

Uma seção por versão, da mais nova para a mais velha. `tt --novidades` mostra o que saiu desde a última
vez que você olhou; `tt --novidades --todas` mostra tudo. Também no menu administrar → 📰 Novidades do tt.

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
- Corrigido: depois de instalar o plugin XOAUTH2, o Gmail e o Career (contas com senha de aplicativo)
  falhavam com "Invalid credentials" — o plugin agora só vale para contas OAuth (a Alumni).

## v1.5.266 · 09/10/2026
- Novo: esta tela de novidades. O tt avisa na faixa (📰) quando atualiza; o clique abre aqui.
- O aviso dos agentes ("🤖 sessão · …") agora leva ao painel certo mesmo se a sessão foi renomeada depois.

## v1.5.264 · 09/10/2026
- Pendências de instalação: o plugin XOAUTH2 (contas Google com OAuth, como a Alumni) agora instala de
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
