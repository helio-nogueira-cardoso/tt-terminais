# Voz versátil: sessões, panorama, latência e janela

Escopo: incremento da voz (fluxo express), pedido em 16/10/2026 depois de uma conversa real pelo 🎤 na empresa.

Pedidos:
- abrir sessões novas pelo rotador ("Abra uma nova sessão em empresa" listava as sessões);
- navegar entre as sessões de forma mais inteligente (por nome, título ou assunto, em qualquer máquina);
- ver o conteúdo das sessões de forma eficiente ("resumo de todas as sessões" levou 2 min, sessão por sessão, com texto cru);
- menos latência (cada volta do cérebro levava ~7–10 s; o `ia-rot --melhor` com o cache vencido, até 40 s);
- sem "diga sim para liberar": escolher a sessão já libera;
- janela do 🎤 um pouco mais larga, bem mais alta, com rolagem.

Medições (16/10): `claude -p` sonnet a cada volta ~6,9 s na empresa; processo persistente com
`--input-format stream-json`: 1ª volta ~1,9 s, as seguintes 1,4–1,6 s (haiku 0,9 s). ssh novo 0,75 s; com o
ControlPath do tt, 0,35 s. `tt --listar-tudo --para-ia` 0,3 s.

Decisões:
- Liberação: escolher (lista, nome, número, cérebro, sessão nova) grava em `permitidas`; `enviar`/teclas/trocar/passar
  só exigem a sessão escolhida. "bloquear sessão" tira a sessão da lista e solta a escolha.
- Regras: a reescrita "máquina + sessões" só vale para frase curta (até 6 palavras) sem verbo de criar/resumir;
  "abrir/abra/criar/crie (uma) (nova) sessão (em M) (com X)" é `nova sessao em M com X`. Sessão citada pelo nome que
  não existe na máquina atual é procurada nas outras.
- Índice: `voz --indice-local [N]` (na máquina; uma ida ao tmux para a lista, sem pontes nem ocultas) dá, por sessão,
  agente, título, estado e as N últimas linhas da tela limpas; `indice_todas` junta todas as máquinas em paralelo
  (cache de 30 s em `~/.local/state/tt-voz/indice`, renovado em 2º plano depois de cada volta). O contexto do
  cérebro leva o índice compacto (sem linhas de tela); a ação `panorama` coleta com 20 linhas por sessão e pede o
  resumo numa 2ª volta do cérebro.
- Cérebro persistente: a janela abre `voz --cerebro-vivo` (conta por `ia-rot --claude-only --melhor`, em 2º plano;
  `claude -p --input-format stream-json --output-format stream-json --tools "" --no-session-persistence
  --system-prompt-file`) e o serve por um socket Unix (`VOZ_CEREBRO_SOCK`); o `voz --turno` usa o socket e, sem ele
  (ou se falhar), o caminho de sempre (`ia-rot -p`). Recomeça depois de 20 voltas. Regras no system prompt; cada
  volta manda só o contexto e a frase.
- ssh do `voz` com o ControlMaster/ControlPath do tt (`~/.cache/tt-ssh-%r@%h`).
- Janela: `@janela` até 100 colunas e quase a altura toda da tela (`altura − 6`, até 60). A tela da janela guarda
  o histórico e desenha por cima (tela alternativa): roda do mouse, PgUp/PgDn, Home/End; rolada para cima, não pula
  para o fim quando chega texto (o estado mostra quantas linhas novas há embaixo).

Validação: testes do `voz` (regras, liberação, índice com tmux isolado, panorama e cérebro vivo com um Claude falso
em stream-json), da janela (rolagem por roda e PgUp, sem pular com texto novo) e do `@janela` (tamanho); suíte
completa antes de publicar.
