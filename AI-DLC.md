<!-- tt-managed: AI-DLC bootstrap policy; do not edit the copy in ~/.config/tt manually. -->
# Política AI-DLC do tt

Esta política é independente do motor de IA. Ela vale para Claude, Codex, Kiro,
Copilot, Cursor, OpenCode e qualquer outro agente que esteja trabalhando dentro
de um terminal gerenciado pelo `tt`.

Quando identificar que uma tarefa está começando dentro de um projeto — pequeno
ou grande, greenfield ou brownfield — o agente deve, antes de alterar código:

1. descobrir a raiz do projeto;
2. executar `tt --aidlc <raiz-do-projeto>`;
3. ler o estado e as instruções AI-DLC locais que o bootstrap configurar;
4. continuar o trabalho pelo workflow adequado ao escopo.

Não pule o bootstrap por considerar a tarefa pequena. O escopo pode ser mínimo,
mas a estrutura local, o registro de decisões e a possibilidade de retomada
devem existir desde o início.

Em projetos brownfield, preserve arquivos, hooks, configurações, plugins,
credenciais e workflows existentes. O bootstrap é idempotente e deve adicionar
somente o que estiver faltando. Se houver conflito ou uma configuração protegida,
pare para revisar e não use `--force` automaticamente.

O arquivo é uma convenção neutra, não uma instrução exclusiva de um cliente.
Cada motor pode manter seus próprios adaptadores, mas todos devem reutilizar o
mesmo projeto AI-DLC local e a mesma fonte de verdade.
