# fefi09 — clique no Mac visto pela empresa; identidade imune a rename

Base: 6cfbced/v2.9.11. Worktree fix/pontes-fluxo-20261023. Pedido de Hélio em 23/10/2026:
a faixa de fixadas continuava lenta entre sessões do Mac visto pelo PC da empresa; exigiu também
identificação por ID único, independente do nome.

## Diagnóstico

O benchmark anterior chamava a troca na máquina da tela. O clique REAL é recebido pela barra
do Mac, onde o cliente é um tmux aninhado. A v2.9.11 o recusava no coordenador e enviava outro
comando SSH à empresa. Com as opções reais do tt (mestra existente), cinco comandos vazios
Mac→empresa custaram 273, 1549, 185, 323 e 307 ms. Isso não é uma medição do clique inteiro,
mas comprova o custo restante que o benchmark anterior não incluía.

## Correção de percurso

O helper remoto publica TT_PRE_TOKEN só no ambiente do cliente de transporte (-E protege a sessão).
O coordenador do Mac distingue clientes aninhados dos físicos: aninhados somente encaminham,
sem preparar SSH. Ele valida tty/PID/nascimento/sessão e capacidade, e escreve um envelope OSC
com UUID no TTY do cliente. O processo de transporte da empresa filtra esse envelope no stdout
do SSH antes do desenho e entrega ao RPC local. Não abre conexão/comando SSH adicional no retorno.
A empresa continua dona das decisões, do cancelamento, do primeiro quadro e da tela exata.
Não se retargeta a sessão remota por dentro, deixando metadados falsos no cache.

Filtro incremental: preserva bytes ordinários, rejeita capacidade alheia, versão inválida,
duplicação/ordem antiga/expiração e limita memória. Resposta incerta não duplica. Falta de
coordenador/modo off usa o comando legado NA ORIGEM; não mais um SSH de volta. O SSH mantém
stdin/PTY e SIGWINCH; stdout passa pelo filtro. Conexões antigas sem @tt_pre_relay=1 são
substituídas normalmente na primeira troca, preservando a tela até confirmação. Sem janela
física no Mac, o encaminhador permanece enquanto há clientes aninhados; a partida fria tenta
esse encaminhamento antes de SSH. Sem tela física, não sonda bateria nem faz prefetch.

## Contrato de identidade

@tt_session_id é UUID persistente de 32 hex; geração uma vez sob flock por socket canônico,
com conferência de colisão antes de gravar. O valor existente nunca é recalculado no rename.
A chave da faixa/cache é máquina+UUID. Nome só descobre legado sem ID. SID $N/start_time do
servidor são endereços de execução derivados e conferidos junto ao UUID, nunca outro nome.

Retirados fallbacks por nome com identidade conhecida em clique local, resolução remota,
reconciliação e reconexão. A reconciliação preserva o UUID em vez de reconsultar pelo rótulo
que pode ter mudado. UUID duplicado é recusa; ID ausente não se transfere à sessão homônima.
Troca local usa SID e guarda UUID no próprio tmux; attach remoto conhecido também tem guarda.
Ponte legada guarda @ponte_uuid e resolve-o antes de anexar/reconectar. Sem confirmação, não
anexa por nome. A sessão inicial sem ID ganha UUID antes da confirmação do protocolo.

Conferência somente leitura do perfil em uso: 4 fixadas locais, as 4 com ID; zero duplicados
e zero referências órfãs. Nenhuma delas foi alterada ou usada como bancada.

## Ensaios até o primeiro commit

- 37 unitários anteriores + 7 do fluxo: fragmentação em todos os limites/byte a byte,
  dados ordinários, capacidade errada, inválido/truncado, expiração, duplicação e perda de resposta;
  emissão em PTY real sem SSH e sem escrever em tty de geração reaproveitada.
- Cenário com duas casas, dois sockets e dois PTYs: empresa→Mac→callback da faixa→envelope→
  empresa→quadro visível. Sete cliques alternados, ambos alvos ativos: última mediana 114 ms,
  máximo 122 ms, zero SSH adicional. Cronômetro começa na chamada do despachante do clique
  no Mac, não no mouse físico; é ensaio isolado, sem a latência real do primeiro salto de entrada.
- O cenário renomeia o alvo com transporte ativo e UUID constante, mantém outro cliente
  independente e testa teclado e redimensionamento pelos dois PTYs. SSH falso aloca PTY
  separado como o SSH real; não confunde stdout pipe com terminal remoto.
- 24 criadores concorrentes recebem o mesmo UUID; rename/grupos, exclusão/recriação,
  reconciliação sem herdar pelo nome, ID ambíguo e colisão simulada estão cobertos.
- Bateria Mac com 17 testes (ponte/fixadas/UUID/portabilidade/partida/desempenho) passou.
  Os testes antigos que exigiam literalmente um if específico foram substituídos por
  comportamento real. O teste que esperava herdar nome após reinício mudou para recusar,
  conforme o contrato pedido por Hélio. A suíte ampla será registrada na descrição do tt.

Sem publicação/instalação desta revisão antes dos testes. S23 continua pendente (ruka03);
extras de voz d5e2257 preservados em outra worktree e fora desta entrega.
