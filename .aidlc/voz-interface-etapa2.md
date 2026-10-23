# Interface pela voz, etapa 2

Tarefa: kane30.kapo27 (3d7fba42d951). Autorização para seguir após a publicação do retorno da voz, em 23/10/2026.

Escopo: visibilidade da faixa das fixadas, não perturbe, mensagem do letreiro, renomear sessão, e-mail,
transferências, calendário e conta da IA. Reutilizar as ações do tt e a confirmação existente.

Decisões:

- Controles seguem a máquina escolhida; interfaces precisam de um cliente anexado à sessão escolhida.
- Não perturbe é local, opcional e preserva histórico/contador. Duração em segundos ou até desligar.
- Mensagem local usa a fonte voz-mensagem, sem apagar as demais fontes e sem interpretar comandos.
- Renomeação manual mantém as referências da voz, incluindo as filas e prazos já existentes.
- Troca de conta guarda e revalida identidade do servidor/sessão/painel; usa a confirmação e o plano existentes.
- Não enviar e-mail nem executar transferência por inferência do comando de abrir a interface.

Validação: testes executáveis dos novos comandos, clientes tmux isolados, calendário real e transportes de IA
simulados; regressões de voz, barra, notificações e partida rápida; portabilidade no Mac e Linux/Termux.

Bootstrap AI-DLC executado. Integração Codex ambígua em AGENTS.md revisada e preservada, sem --force.
Scaffolding genérico e alterações automáticas próprias de .gitignore ficam fora da implementação.
