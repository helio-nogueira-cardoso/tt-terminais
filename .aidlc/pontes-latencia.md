# Pontes: latência de retorno — mifa18 / 37b20671d2ec

Pedido de Hélio em 23/10/2026: preservar a estabilidade do cache e tornar a troca muito mais rápida.
Base publicada: d3c4203, v2.9.6. Trabalho isolado em fix/pontes-latencia-20261023.

## Causa e decisão

O coordenador devolvia handled=false para uma ponte já active. A fixada então resolvia novamente
sua identidade por SSH; entrar_remoto consultava o coordenador outra vez, verificava a sessão e
procurava uma ponte existente. O cache preservava o transporte, mas não encurtava essa volta.
A primeira ativação ainda aguardava rodadas de 200 ms para observar a confirmação/primeiro quadro.

O retorno agora confere localmente dono (tty + PID + nascimento), identidade estável, bilhete,
marca viva, PID do transporte e pane. A marca é limpa quando o SSH termina, mesmo com pane vivo
no prompt. O teste final no tmux também recusa a marca limpa/pane morto. A identidade da tela é
revalidada imediatamente antes da troca. Reinício recupera pontes com essas marcas; uma versão
antiga sem elas passa pela abertura completa uma vez, sem migração presumida de conexões.

A entrada da fixada instalada delega um RPC Unix antes de carregar o núcleo Bash. Não cria daemon,
não prepara SSH nem executa tarefas no caminho curto. Falta de cache/coordenador reexecuta o
comando original uma vez. Resposta incerta não duplica o clique. Soltar não navega novamente.
Fixada local com ID usa a mesma entrada; cliente aninhado continua no caminho de retorno à origem.
Vigia é conferido depois da resposta e no máximo a cada 30 s; trace/TT_COMPLETO preservam o Bash.

Primeira ativação mantém identidade remota e primeiro quadro. As sondagens passam a 10 ms nos
primeiros 250 ms de pedido e 50 ms na espera lenta, mantendo 500 ms ocioso. Não há rede simulada
como sucesso, não se publica screenshot antigo como confirmação e não se troca a sessão remota
anexada pela pessoa. A volta reaproveita a conexão existente: não comprova ida e volta nova de rede
por clique. Queda ainda não detectada pelo SSH fica sujeita ao keepalive existente (15 s × 3).

## Evidência até 10:56 (antes do commit final)

Mac, sete cliques alternando CLI e rota da barra, SSH falso executando protocolo real com PTY,
dois clientes tmux e HOME/sockets isolados. Cronômetro externo: início do comando até marcador
remoto aparecer no terminal externo, esperando primeiro o marcador de origem a cada volta.

- Base d3c4203 com apenas o mesmo benchmark: mediana 522 ms, máximo 538 ms.
- Revisão com entrada curta: mediana 133 ms, máximo 138 ms (cerca de 75% menos).
- Sete voltas sem novo SSH nem helper tt remoto; só a primeira conexão/ativação usa rede.
- Contador clique_ms começa no pedido Python e termina na troca; é menor que o cronômetro externo.
- A redução não é promessa de zero absoluto nem medição física do mouse/GPU/monitor.

Logs em ~/.local/state/tt/pontes-latencia-*.log. Base isolada em worktrees/pontes-latencia-base-20261023;
apenas o teste foi adaptado ali, com helper remoto temporário para viabilizar o legado. Não instalado.
A revisão passou 7 testes de regressão no Mac (pré-carregamento, portabilidade, partida rápida,
desempenho, toque nas fixadas, ponte vinda do Mac e versão), incluindo o protocolo real e testes
unitários. Ensaios de quadro visível, reinício, transporte encerrado, duas telas, rename, identidade
reciclada, cancelamento, rede sem resposta e modo off também passaram. A revisão final, com
checagem deferida do vigia e documentação, ainda será revalidada no Mac e no WSL antes da entrega.

Nenhuma sessão/ponte do usuário foi usada como bancada. Nenhum push, instalação remota ou acesso
físico ao S23. Os extras de voz d5e2257/v2.10.3 permanecem na sua worktree, separados desta correção.
