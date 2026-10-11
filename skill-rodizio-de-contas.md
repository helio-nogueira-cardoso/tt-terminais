---
name: rodizio-de-contas
description: Use em tarefas longas ou quando aparecer aviso de limite de uso ("approaching usage limit", "you've hit your limit", "5-hour limit", créditos acabando) — consulta quanto a sua conta de IA já gastou da janela (ia-conta uso --eu) e, perto do fim, grava uma passagem de tarefa e passa o trabalho para a próxima conta ou agente livre (ia-rot --passar), que continua de onde você parou. Também cobre, quando o usuário pedir: trocar a conta PRINCIPAL (a de ~/.claude) de todas as máquinas do tt (ia-login --principal), logar contas que faltam e tirar (expurgar) uma conta de IA de todas as máquinas, inclusive fazendo o login pelo navegador do celular.
---

# Rodízio de contas: consultar o uso e passar a tarefa adiante

Esta máquina tem várias contas de IA numa rotação (contas do Claude, depois Codex, depois Kiro),
gerenciadas pelo tt-terminais:

- `ia-conta` (também `claude-conta`): seletor de contas e consulta de uso.
- `ia-rot` (também `claude-rot`): rotator; escolhe, entre as contas com login e janela livre, a de mais folga de uso agora (5 h, semana e mês, pelo tempo até reiniciar). Se o modelo padrão do Claude tem cota própria (o Fable), as contas que ainda o rodam vêm primeiro.
- Sub-agentes rodam no modelo do agente que os chama: não peça outro modelo ao chamar um sub-agente (o tt liga `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`, que ignora o pedido).

O uso é por conta, somado entre todas as sessões que usam a mesma conta. Por isso ele pode subir
mesmo quando você trabalha pouco.

## Quando consultar

- No começo de uma tarefa que vai levar mais que alguns minutos.
- Depois de cada etapa grande (um commit, uma bateria de testes, uma investigação concluída).
- Em tarefa longa, pelo menos a cada ~30 min de trabalho.
- Sempre que o próprio CLI avisar que o limite está perto.

```bash
ia-conta uso --eu        # Claude: detecta a conta pela sessão
ia-conta uso codex       # se você é o Codex
ia-conta uso kiro        # se você é o Kiro
```

A saída é `conta<TAB>pico%<TAB>situação<TAB>detalhe`. O pico é o maior percentual entre as janelas
(5 h e semanal no Claude e no Codex; créditos do mês no Kiro). O código de saída já diz o que fazer:

| saída | situação       | o que fazer                                                          |
|-------|----------------|----------------------------------------------------------------------|
| 0     | `ok`           | siga trabalhando                                                     |
| 3     | `aviso` (≥85%) | feche a etapa atual, mantenha a passagem de tarefa pronta            |
| 4     | `passar` (≥95%)| pare num ponto consistente e passe a tarefa agora                    |
| 2     | `desconhecido` | sem dado (sem rede ou conta sem login); consulte de novo mais tarde  |

Se `--eu` disser que não sabe a conta, passe o nome dela (`ia-conta listar` mostra todas).

## Como passar a tarefa

1. Pare num ponto consistente: nada pela metade num arquivo, testes rodados, trabalho salvo
   (commit num branch, se o projeto usa git e isso for o costume do projeto).
2. Escreva a passagem num arquivo novo, em
   `~/.local/state/tt/passagens/<AAAAMMDD-HHMMSS>-<assunto>.md`, com tudo o que a próxima IA
   precisa, sem depender da sua conversa (ela não vai ver a conversa):

   ```markdown
   # Passagem: <assunto>
   - De: <sua conta/agente>   Quando: <data e hora>   Pasta: <caminho absoluto>
   ## Pedido original do usuário
   <as palavras do usuário, literais, inclusive restrições e autorizações dadas>
   ## Feito até agora
   <o que já foi feito e verificado; commits, arquivos alterados, comandos que funcionaram>
   ## Estado atual
   <o que está pela metade, o que está quebrado, o que não foi verificado>
   ## Próximo passo
   <a próxima ação concreta, e as seguintes até o fim da tarefa>
   ## Cuidados
   <o que NÃO fazer, decisões já tomadas com o usuário, armadilhas encontradas>
   ```

3. Passe a vez, da pasta onde a tarefa acontece:

   ```bash
   ia-rot --passar ~/.local/state/tt/passagens/<arquivo>.md [--yolo] [--de <conta>]
   ```

   - `--yolo`: use se você mesmo roda sem pedir permissões (Claude com
     `--dangerously-skip-permissions`/bypass, Codex sem sandbox, Kiro com `--trust-all-tools`); a
     próxima IA recebe o mesmo nível.
   - `--de`: só quando a conta não é detectada sozinha (Codex: `--de codex`; Kiro: `--de kiro`).
   - Dentro do tmux, a próxima IA abre numa janela nova da mesma aba, já lendo a passagem. Fora do
     tmux, ela roda em segundo plano e a saída vai para `<arquivo>.md.saida`.
   - Saída 2 = nenhuma outra conta livre agora; a mensagem diz quando a primeira volta. Nesse caso,
     avise o usuário, deixe a passagem pronta e diga o caminho dela.

4. Diga ao usuário, em uma ou duas frases, que passou a tarefa, para qual conta e onde está a
   passagem. Depois disso, pare: não continue editando os mesmos arquivos, porque a próxima IA já
   está trabalhando neles.

## Ao receber uma passagem

Leia o arquivo inteiro antes de agir. O pedido original e os cuidados valem como se o usuário os
tivesse dito a você. Confira o estado real (git status, testes) antes de seguir, porque a IA anterior
pode ter parado no meio de algo. Ao terminar, acrescente ao arquivo uma seção `## Resultado`.

## Trocar a conta principal (só quando o usuário pedir)

A "principal" é a credencial de `~/.claude` (o `claude` puro); os perfis (`claude-<nome>`) são as outras.
O usuário pode pedir que a principal passe a ser outra conta:

```bash
ia-login --principal CONTA|E-MAIL --plano      # o que mudaria, em todas as máquinas do tt
ia-login --principal CONTA|E-MAIL [máquina…]   # troca (o usuário abre o link e cola o código)
ia-conta adicionar principal [--email E]       # só esta máquina
```

Nunca copie `.credentials.json` entre contas ou máquinas: duas cópias do mesmo token se derrubam quando um deles
renova. A troca recusa com um Claude aberto na principal (ele regravaria a credencial antiga); feche essas sessões
antes, e avise o usuário se for uma que não é sua.

**Sem o usuário copiar link nem colar código**: se o celular dele tem um navegador logado na conta (e ele pediu o
login), faça o ciclo pelo navegador do celular com a função `login_pelo_celular` da skill `celular-android`
(seção 14): ela abre o link no celular, anda pelo login do site e do Google, toca em "Autorizar" depois de conferir
"Conectado como", lê o código e o entrega. Para senha, duas etapas, CAPTCHA ou outra conta ela para e chama o dono.
Rode com `ENSAIO=1` na primeira vez. Quem tem o celular em mãos pode também só pedir ao `ia-login` e fazer à mão.

A troca derruba o login que estava na principal: a conta que só existia ali some da máquina (o cadastro passa a
acusar "faltam aqui: …"); restaure com `ia-conta adicionar <apelido>` ou `ia-login <máquina>` se o usuário quiser.

## Tirar uma conta de todas as máquinas (só quando o usuário pedir)

Tirar uma conta (por exemplo, a de uma empresa que o usuário deixou) de todas as máquinas do tt:

1. **Era a principal em alguma máquina?** Troque antes (seção acima): `ia-login --principal OUTRA-CONTA`. O plano
   mostra em quais máquinas ela é a principal ("trocar (hoje: conta@…)"). `ia-conta remover` não remove a principal.
2. **Cadastro**: `ia-conta cadastro esquecer claude:conta@exemplo.com` grava uma linha `-` (tombstone) que o
   sincronismo propaga às máquinas. **Deixe a linha**: sem ela o cadastro de outra máquina ressuscita a conta.
3. **Perfis**: em cada máquina que tenha um perfil dela, `ia-conta remover PERFIL --sim` (recusa se há Claude aberto
   no perfil; ele fica guardado em `claude-contas.removidas/` com o comando de desfazer). Um processo longo que
   herdou `CLAUDE_CONFIG_DIR` do perfil (um agente de deploy, por exemplo) também impede: ache pelo ambiente
   (`/proc/PID/environ`) e encerre o PID exato.
4. **Conferir** em cada máquina (também no proot do celular, que é outro sistema de arquivos): perfis e atalhos
   `claude-<perfil>`, `~/.claude.json` e `~/.claude/.account-email`, o cadastro `~/.config/tt/contas-ia`, e
   `ia-login --principal OUTRA-CONTA --plano` ("Nada a fazer"). Menções em histórico de shell, sessões antigas do
   Codex e arquivos do mesh são registro histórico sem credencial: só apague com pedido do usuário.
5. **Revogar o token**: o logout local não revoga. O token continua válido no servidor até ser revogado em
   claude.ai (logado na conta) ou pelo administrador da organização. Só o dono faz: **lembre-o disso no fim**.
6. **Outros provedores são outras contas**: o Kiro e o Codex da mesma pessoa/organização têm login próprio; só mexa
   neles se o usuário pedir (ele pode querer manter o Kiro na conta da empresa).
