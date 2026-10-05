# Matriz de interações

| Elemento | Canais | Cenários mínimos |
| --- | --- | --- |
| Máquina | barra, botão direito, CLI | abrir seletor; administrar; ocultar e restaurar sem perder `host usuário rótulo` |
| Sessão | barra, seletor, teclado | abrir; renomear; fechar com confirmação; tratar sessão inexistente |
| Fixada | toque, clique direito, ✕ | ir no pressionar; menu; desafixar; redraw entre pressionar e soltar; toque de ponta a ponta no 📍 (fixa) e bem em cima do ✕ (desafixa) |
| Painel | mouse, botão direito, `Ctrl+B m` | menu; copiar; colar; dividir; maximizar; fechar |
| Barra principal | toque, mouse, teclado | central, arquivos, e-mail, painel, ajustes, transferências e atalhos customizados |
| E-mail | botão 📧, teclado/CLI `--email` | abre o cliente numa subjanela (popup) sobre a tela; ao sair volta à tela de baixo; sem sessão nem shell órfão |
| Contas de e-mail | menu administrar, CLI `--email-contas` | cadastro guiado grava `[Nome]` no accounts.conf e a senha de app em `~/.secrets` (600), nunca no versionado; remover apaga bloco e credencial; nome duplicado é recusado |
| Botões F1–F10 | teclado/Termux | cada `bind F*` chama o respectivo `tt --botao` |
| Central e seletor | mouse, toque, teclado | abrir linha; pino; ✕; busca; troca de máquina; prévia ligada/desligada |
| Mouse fzf | SGR/PTY | pressão, soltura, arrasto, modificadores e sequência de bytes fragmentada |
| Nome automático | vigia | primeiro nome pelo título do Claude; com o título parado, revisa pelos pedidos recentes; segue título novo; pontos (pedido 3, minuto de uso 1); sem pedido novo não chama o Haiku |
| Sessão parada | vigia, CLI | fecha só sem uso e sem programa; shell aninhado ocioso e proot ocioso não seguram; anexada, fixada e ponte ficam |
| Atualização | vigia, CLI | sem rede não bloqueia; versão maior instala; nunca rebaixa |

`tests/run.sh` cobre hoje os contratos estruturais, o tmux isolado, a ponte SGR e o fluxo isolado
de máquinas. Ao adicionar uma interação, acrescente aqui o cenário e o teste correspondente.

