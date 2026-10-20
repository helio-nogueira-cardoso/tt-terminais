# Interoperabilidade e diagnóstico da malha

Uma malha completa exige, em cada direção, descoberta do endereço, rota, porta SSH,
identidade autorizada e o ambiente remoto correto. Tailscale online não prova que o
sshd está acessível; um dispositivo offline não pode ser reparado remotamente. Teste
as duas direções com `tt --malha` e examine `tt --diagnosticar` em cada ponta.

## Incidente observado em 20/10/2026

No book-hl, o acesso ao S23 na porta 8022 chegou ao SSH, mas recebeu `Not allowed
at this time` e reset antes da autenticação. A configuração observada do servidor
incluía MaxStartups e PerSourcePenalties; esses mecanismos são hipóteses compatíveis,
não uma causa confirmada sem registros do servidor. Repetições agressivas podem
agravar o problema. Consulte os logs e os processos do sshd no celular, aguarde a
expiração de eventual bloqueio e valide novamente; não desative proteções às cegas.
O S23 também apresentou falha de resolução MagicDNS, enquanto o IP Tailscale
funcionou em testes entre outras pontas. O Mac estava offline no Tailscale, portanto
suas rotas não puderam ser validadas. O relógio do WSL apresentou divergência;
confirme o horário do Windows/WSL e a sincronização antes de investigar autenticação.

## Defeitos corrigidos

O socket de multiplexação SSH incluía usuário e host, mas não a porta: uma tentativa
na 8022 podia reutilizar uma conexão já aberta na 22. Agora `%C` identifica também a
porta e evita nomes de socket longos. Sockets antigos expiram conforme ControlPersist;
não é necessário encerrá-los. O diagnóstico reconhece IPs Tailscale e diferencia
recusa temporária do sshd, erro de DNS e conexão interrompida de porta recusada.
Essas correções eliminam ambiguidades observáveis; não substituem a correção de
DNS, rede, bloqueios do servidor ou disponibilidade da máquina.

No Termux, comandos remotos devem preservar `TMUX_TMPDIR=$PREFIX/var/run`: consultar
o tmux com outro diretório pode mostrar falsamente que não há sessões. O tt já
configura esse ambiente nos comandos remotos. Em macOS, mantenha Bash e ferramentas
do Homebrew acessíveis pelo PATH remoto. Use chaves e verificações de host SSH;
não copie credenciais nem reduza a proteção para fazer um teste passar.
