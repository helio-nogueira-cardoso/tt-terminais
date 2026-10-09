# Novidades do tt-terminais

Uma seção por versão, da mais nova para a mais velha. `tt --novidades` mostra o que saiu desde a última
vez que você olhou; `tt --novidades --todas` mostra tudo. Também no menu administrar → 📰 Novidades do tt.

## v1.5.265 · 09/10/2026
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
