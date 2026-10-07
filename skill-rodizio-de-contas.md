---
name: rodizio-de-contas
description: Use em tarefas longas ou quando aparecer aviso de limite de uso ("approaching usage limit", "you've hit your limit", "5-hour limit", créditos acabando) — consulta quanto a sua conta de IA já gastou da janela (ia-conta uso --eu) e, perto do fim, grava uma passagem de tarefa e passa o trabalho para a próxima conta ou agente livre (ia-rot --passar), que continua de onde você parou.
---

# Rodízio de contas: consultar o uso e passar a tarefa adiante

Esta máquina tem várias contas de IA numa rotação (contas do Claude, depois Codex, depois Kiro),
gerenciadas pelo tt-terminais:

- `ia-conta` (também `claude-conta`): seletor de contas e consulta de uso.
- `ia-rot` (também `claude-rot`): rotator; escolhe, entre as contas com login e janela livre, a de mais folga de uso agora (5 h, semana e mês, pelo tempo até reiniciar).

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
