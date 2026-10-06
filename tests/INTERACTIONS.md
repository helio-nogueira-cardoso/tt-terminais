# Matriz de interações

| Elemento | Canais | Cenários mínimos |
| --- | --- | --- |
| Máquina | barra, botão direito, CLI | abrir seletor; administrar; ocultar e restaurar sem perder `host usuário rótulo` |
| Sessão | barra, seletor, teclado | abrir; renomear; fechar com confirmação; tratar sessão inexistente |
| Fixada | toque, clique direito, ✕ | ir no pressionar; menu; desafixar; redraw entre pressionar e soltar; toque de ponta a ponta no 📍 (fixa) e bem em cima do ✕ (desafixa) |
| Painel | mouse, botão direito, `Ctrl+B m` | menu; copiar; colar; dividir; maximizar; fechar |
| Barra principal | toque, mouse, teclado | central, arquivos, e-mail, painel, ajustes, transferências e atalhos customizados |
| E-mail | botão 📧, teclado/CLI `--email` | abre o cliente numa subjanela (popup) sobre a tela; ao sair volta à tela de baixo; sem sessão nem shell órfão; o tt garante no aerc o mouse ligado e a saída rápida (Q) em toda máquina, sem tocar nas contas |
| Contas de e-mail | menu administrar, CLI `--email-contas` / `--email-adicionar` / `--email-listar` / `--email-testar` / `--email-autorizar` / `--email-remover` | lista navegável (⏎ ações, ^n nova, ^t testar, ^d descadastrar); provedores prontos e "outro" com descoberta pelo domínio; autenticação por senha, comando externo ou OAuth2/SSO (código no aparelho ou navegador); avançado: servidores, portas, TLS/STARTTLS/nenhuma, usuário; segredos só em `~/.secrets` (600); o tt só mexe nos blocos com marcadores e importa as contas antigas; recusa nome repetido, slug colidente, `[ ]` e porta inválida (tests/test_email.sh) |
| Leitor de e-mail (aerc) | instalação (`configurar_aerc`), teclado no aerc | tema Catppuccin, pastas em árvore com não lidas, fios, HTML legível sem w3m; atalhos u (lido), * (estrela), f (encaminhar), M/Y (mover/copiar para pasta), F (só não lidos), a, d; só acrescenta opções ausentes; o aerc real abre com a configuração (tests/test_aerc.sh) |
| Contas de IA | CLI `ia-conta` / `ia-rot` (apelidos `claude-conta` / `claude-rot`), skill rodizio-de-contas | instalação liga os 4 nomes ao pacote, guarda versão antiga em `.antes-tt`, preserva script alheio e põe a skill no Claude/Codex/Kiro presentes; listar com coluna USO (cache `~`, desconhecido `?`); `uso --eu` com saída 0/3/4/2; renomear leva pasta, atalho, cache e botão; recusa nome existente, reservado e conta aberta; remover guarda a pasta; rotator pula conta cheia pelo uso; `--passar` abre a próxima conta em janela nova da mesma aba lendo a passagem (tests/test_contas_ia.sh) |
| Botões F1–F10 | teclado/Termux | cada `bind F*` chama o respectivo `tt --botao` |
| Central e seletor | mouse, toque, teclado | abrir linha; pino; ✕; busca; troca de máquina; prévia ligada/desligada |
| Mouse fzf | SGR/PTY | pressão, soltura, arrasto, modificadores e sequência de bytes fragmentada |
| Nome automático | vigia, CLI `--nomear-texto` | primeiro nome pelo título do Claude; com o título parado, revisa pelos pedidos recentes; segue título novo; pontos (pedido 3, minuto de uso 1); sem pedido novo não chama o Haiku; erro/limite local ou remoto nunca vira nome; rotator usa apenas contas Claude, Haiku sem ferramentas (tests/test_nomear_erro.sh) |
| Sessão parada | vigia, CLI | fecha só sem uso e sem programa; shell aninhado ocioso e proot ocioso não seguram; anexada, fixada e ponte ficam |
| Atualização | vigia, CLI | sem rede não bloqueia; versão maior instala; nunca rebaixa |

`tests/run.sh` cobre hoje os contratos estruturais, o tmux isolado, a ponte SGR e o fluxo isolado
de máquinas. Ao adicionar uma interação, acrescente aqui o cenário e o teste correspondente.
