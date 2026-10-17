# Checagens do tt

O que o agente de checagem (`tt --checar-agente`) confere em cada máquina depois de uma atualização. Cada item
diz o que conferir, como provar e como corrigir. O coletor (`tt --checar`) já faz a parte barata de cada um; o
agente vai além: descobre a causa, corrige e prova que ficou bom. Regra nova do ambiente entra aqui (no
repositório) e chega a todas as máquinas na próxima versão; regra só de uma máquina vai em `~/.config/tt/checagens.md`.

## 1. Vigia
- **Conferir:** o pid de `$RT/tt-vigia-$UID.pid` é um `tt --vigia` vivo, único, sem CPU alta; o fim de
  `~/.cache/tt-vigia.log` não repete o mesmo erro.
- **Corrigir:** parado → `tmux run-shell -b '~/.local/bin/tt --vigia'` (o vigia vive no servidor tmux do tt; sem
  tmux aberto, a sessão oculta `_tt-vigia` com `sleep infinity` o mantém). CPU alta → anotar o fim do log, matar o
  pid e religar. Erro repetido → investigar a função citada.

## 2. Atualização
- **Conferir:** `tt --atualizacao-estado` em dia, sem falhas seguidas; `~/.local/share/tt/rapido/nucleo.sh` existe.
- **Corrigir:** `tt --atualizar`; sem partida rápida → `TT_COMPLETO=1 ~/.local/bin/tt --rapido gerar`.

## 3. Separação: versionado × local
- **Regra:** `~/.local/share/tt` é o pacote, trocado inteiro a cada instalação (só o instalador escreve);
  `~/.config/tt` é o perfil (escolhas do usuário, nunca código); `~/.local/state/tt` é estado gerado; segredos só
  em `~/.secrets` (modo 600). No clone de desenvolvimento, configuração local não vai em arquivo versionado
  (`.git/info/exclude`, não o `.gitignore`).
- **Conferir:** o pacote tem todos os arquivos do `ARQUIVOS_PACOTE` e nada do usuário; o perfil não tem código;
  `~/.secrets` e os arquivos dentro dele com modo 600; no clone, `tt --repo-checar` limpo.
- **Corrigir:** pacote incompleto → reinstalar (`tt --atualizar`); arquivo do usuário no pacote → mover para o
  perfil; segredo com modo aberto → `chmod 600`; `.gitignore` com acréscimos locais → `tt --repo-checar --corrigir`.

## 4. E-mail
- **Conferir:** para cada conta (`tt --email-listar`), espelho local ligado (`sync_local=1`), última rodada em dia
  em `tt --email-sync-estado`, sem `.erro` nem espera longa em `~/.local/state/tt/email-sync/`; a volta completa (as
  outras pastas) também em dia: `<conta>.erro-completo` guarda a causa da última ruim.
- **Conferir também os comandos:** `tt --email-conferir` (✕ Apagar tem para onde mandar: lixeira conhecida, presente no
  espelho, comandos da conta no aerc). Corrigir: `tt --email-conferir CONTA --corrigir`.
- **Corrigir:** a dica do `--email-sync-estado` diz a pendência (`tt --pedir-sudo …`); mbsyncrc antigo →
  `tt --email-mbsync-migrar`; config gerada errada → `tt --email-regerar CONTA`; "far side box X cannot be opened
  anymore" = pasta que sumiu do servidor e ficou no espelho: confira que está vazia ou que as mensagens existem em outra
  pasta e mova-a de `~/.cache/tt/maildir/CONTA/` para o backup da rodada; depois `tt --email-sync CONTA --completo` e
  conferir de novo. OAuth vencido ou senha recusada exige o usuário: avisar com `tt --email-autorizar CONTA` pronto.

## 5. Tarefas
- **Conferir:** `tt --tarefas-sync status` sem erro e com troca recente.
- **Corrigir:** `tt --tarefas-sync agora`; erro de acesso ao repositório → conferir a URL e a chave, sem trocar o modo.

## 6. Malha
- **Conferir:** `tt --malha` sem ilha; `tt --saude` sem máquina vermelha.
- **Conferir também:** linha `sshd` do `tt --checar` (esta máquina aceita conexão na 22, ou na 8022 pelo sshd do usuário
  que o tt sobe); log em `~/.local/state/tt/sshd/garantir.log`.
- **Corrigir:** `tt --diagnosticar MÁQUINA`; chave → `tt --reparar MÁQUINA`; porta fechada nesta máquina →
  `tt --sshd-garantir` (sem o programa: `tt --pedir-sudo sshd`). Máquina desligada não é defeito. Nome que não resolve
  só numa máquina (o celular sem o MagicDNS): a malha religa pelo IP da tailnet que as outras anunciam.
- **Conferir também:** linha `tailscale` do `tt --checar`. `aviso` = sem falar com o servidor de coordenação (filtro de rede
  da empresa; o nó segue vivo pelo cache); `falha` = deslogado/parado. Não reinicie o `tailscaled` na rede com filtro: o
  registro falha e a máquina fica deslogada. Troque para uma rede sem filtro e rode `sudo tailscale up --ssh --hostname=NOME`.

## 7. Agentes
- **Conferir:** `~/.agents/AGENTS.md` tem o bloco `tt-managed:regras-tt`; `CLAUDE.md` dos perfis e `AGENTS.md` do
  Codex são links para ele; a skill `tt-terminais` está instalada.
- **Corrigir:** `tt --reforcar-agentes`.

## 8. Pendências de instalação
- **Conferir:** `tt --pendencias --tsv` sem item essencial ou de recurso faltando.
- **Corrigir:** `tt --pedir-sudo --sim ID…` só se `sudo -n true` funciona; senão, registrar e avisar o usuário.
  A pendência `sudo-sem-senha` é decisão do usuário (ele digita a senha no modal): nunca tente ativá-la por outro caminho.

## 9. Hora
- **Conferir:** `tt --hora` com desvio abaixo de 60 s.
- **Corrigir:** `tt --hora --sincronizar`; relógio do sistema errado é do usuário (avisar).

## 10. Conversas das IAs
- **Conferir:** `tt --sessoes-ia status` sem máquina sem troca boa há mais de 2 dias (estando ela ligada).
- **Corrigir:** `tt --sessoes-ia agora`; ver `~/.cache/tt-sessoes-ia.log`.

## 11. Caixa de entrada de tarefas (tarefas por e-mail)
- **O caminho:** alguém manda uma tarefa (`tt --tarefa-email`, assunto `[tt] … ~CÓDIGO`) → o e-mail chega ao INBOX de
  uma conta com espelho local → o sync roda `demandas_processar_conta` → remetente autorizado (`tt --demandas`) e
  autenticado (SPF/DKIM, ou segredo/aberto) → tarefa PENDENTE na aba Entrada (`tt --demandas-pendentes`).
- **Conferir:** `tt --checar` (linha `demandas`); existe conta com espelho local e o sync dela está em dia; o log
  `~/.local/state/tt/email-sync/<conta>.demandas.log` (criada, aguardando autorização, ignorada e o motivo);
  `<conta>.demandas.espera` (e-mails `[tt]` de quem ainda não foi autorizado); o e-mail chegou mesmo ao INBOX do
  espelho (`grep -l '^Subject: \[tt\]' ~/.cache/tt/maildir/<conta>/INBOX/{new,cur}/*`), e não ao spam.
- **Corrigir:** espelho desligado → `tt --pedir-sudo email-espelho`; sync parado → item 4; processar de novo →
  `tt --demandas-processar CONTA`. **Autorizar um remetente é decisão do usuário (segurança): nunca autorize sozinho.**
  Diga no relatório quem está esperando e o comando (`tt --demanda-autorizar EMAIL`), e avise com `--notificar-daqui`.
  Remetente ignorado por autenticação: explique o motivo do log e a opção de segredo, sem aplicá-la.

## 12. O que a versão trouxe
- **Conferir:** cada item do trecho novo do `NOVIDADES.md` funciona nesta máquina: rode o verbo citado, confira o
  arquivo ou o comportamento descrito. Item que depende de tela ou de outra máquina: confira o que der e diga o que
  não deu para provar.
- **Corrigir:** configuração local errada → corrigir; defeito do código → ver "Bug no código" no pedido.
