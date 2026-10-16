# Escolha da máquina de transcrição

Escopo: incremento da voz existente, fluxo express. O usuário pediu seleção manual e troca da máquina durante a conversa, mantendo a seleção automática disponível.

Decisões: reutilizar `transcrever` e a CLI existente; submenu `l` com números, Enter e cancelamento; `0` restaura todas as candidatas; preservar o motor atual se a abertura do novo falhar. Fechamento do transcritor também encerra alternativas carregadas em segundo plano.

Validação: teste com motores remotos simulados, seleção da máquina mais lenta, cancelamento, retorno ao automático, troca em conversa e máquina indisponível; teste do painel real no tmux isolado; suíte completa antes da publicação.

Bootstrap: executado `tt --aidlc`; adaptador Codex detectou AGENTS.md legado. Revisado e preservado o guia existente conforme README desta pasta, sem forçar substituição. Scaffolding genérico gerado pelo adaptador Claude foi guardado fora da árvore de código.
