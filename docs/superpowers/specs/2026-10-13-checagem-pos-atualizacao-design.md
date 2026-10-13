# Checagem pós-atualização (agente que confere e corrige o tt)

Data: 2026-10-13 · Versão alvo: **v1.14.0** (funcionalidade nova abre série: `MARCO` 1.14)

## Objetivo

Sempre que uma máquina instala uma versão nova do tt, um agente de IA, lançado pelo rotador (`ia-rot`),
confere se tudo o que foi definido para o ambiente está funcionando, confere que o que a versão nova
trouxe funciona de verdade, **corrige** o que estiver errado e deixa um relatório num lugar centralizado.
Quem usa o tt consegue entregar todos esses registros num pacote único (handoff) quando o mantenedor pedir.

Sucesso = depois de cada atualização, em cada máquina: um relatório da rodada, problemas locais corrigidos
sem intervenção, um aviso no 🔔 com o resumo, e `tt --checar-handoff` gerando um pacote sem segredos.

## Visão geral

Duas camadas:

1. **Coletor determinístico** `tt --checar [--tsv] [--corrigir-simples]`: sem IA, roda as checagens fixas e
   imprime uma linha por checagem: `id  estado(ok|aviso|falha)  resumo  evidência  correção-sugerida`.
   Barato, testável no `make test`, útil mesmo sem conta de IA livre.
2. **Agente** `tt --checar-agente [--de VERSÃO]`: monta o pedido (relatório do coletor + trecho do
   `NOVIDADES.md` entre a versão anterior e a atual + `checagens-tt.md` + regras locais + limites) e lança
   `ia-rot -p` numa sessão oculta `_tt-checagem`. O agente investiga, corrige e escreve o relatório.

## Gatilho

- O **vigia**, não o `instalar_aqui` (a instalação precisa ser rápida e roda fora do tmux).
- Marca `$ESTADO_DIR/checagem-versao` = última versão checada (mesmo modelo de `novidades_avisar`).
  Versão instalada mais nova que a marca → dispara uma vez; a marca só avança quando a rodada termina
  (com ou sem agente).
- Máquina recém-instalada (sem marca): grava a marca e não dispara (igual às novidades).
- Sem conta livre (`ia-rot` sai 2): grava o relatório do coletor, tenta de novo na volta seguinte do
  vigia, até 3 tentativas (contador em `checagem-tentativas`); depois disso fecha a rodada só com o coletor.
- Trava `$RT/tt-checagem-UID.trava` (mkdir): uma rodada por vez.
- `checagem_auto=0` no config desliga o disparo automático; o verbo manual continua.
- Manual: `tt --checar-agente` a qualquer hora; item 🩺 no menu administrar (checar agora / gerar handoff /
  ver último relatório).

## Regras versionadas

- `checagens-tt.md` (novo, no pacote e em `ARQUIVOS_FONTE`): a lista de checagens e regras que o agente
  reforça. Cresce a cada regra nova; cada item diz o que conferir, como provar e como corrigir.
- `checagem-prompt.md` (novo, no pacote): o modelo do pedido ao agente (limites de autonomia, formato do
  relatório, onde gravar).
- `~/.config/tt/checagens.md` (opcional, local): regras só desta máquina, somadas ao pedido.

## Checagens iniciais

| id | o que confere | correção |
|---|---|---|
| `vigia` | pidfile aponta para processo vivo; última volta recente no `tt-vigia.log`; sem erro repetido | religar o vigia |
| `atualizacao` | instalada = publicada; sem 3 falhas de sonda; `rapido/` presente | `--garantir-atualizacao`, `--rapido gerar` |
| `separacao` | pacote em `~/.local/share/tt` = `ARQUIVOS_PACOTE` (sem arquivo do usuário); perfil sem código; no clone, `--repo-checar` limpo | reinstalar pacote, `--repo-checar --corrigir` |
| `email` | por conta: espelho existe se `sync_local=1`; última rodada em dia; sem `.erro`/`.espera` longa; causa por `email_erro_dica` | `--email-mbsync-migrar`, `--email-regerar`, pendência certa; OAuth vencido → aviso com `--email-autorizar CONTA` pronto |
| `tarefas` | `--tarefas-sync status` sem erro e com troca recente | `--tarefas-sync agora` |
| `malha` | todas alcançáveis, sem ilha | `--reparar` quando for chave |
| `agentes` | `AGENTS.md` único com links certos; regras e skill instaladas | `--reforcar-agentes` |
| `pendencias` | nenhuma essencial faltando | `--pedir-sudo --sim` (só se `sudo -n` funciona; senão aviso) |
| `hora` | desvio < 60 s | `--hora --sincronizar` |
| `sessoes-ia` | nenhuma máquina parada há > 1 dia | `--sessoes-ia agora` |
| `novidades` | (só o agente) cada item do trecho novo do `NOVIDADES.md` testado na prática | conforme o item |

## Autonomia do agente

- Corrige direto, sem perguntar, tudo o que for **desta máquina**: config, estado e serviços do tt.
- Antes de alterar qualquer arquivo em `~/.config/tt`, guarda cópia em `checagens/<rodada>/backup/`;
  o relatório diz como desfazer.
- sudo só se `sudo -n true` funciona; senão registra e avisa.
- Bug no código do tt:
  - na máquina de desenvolvimento (a do `repo=`): worktree a partir do `origin/main`, correção,
    `make test`, commit pronto **sem push**, aviso no 🔔;
  - nas outras máquinas (inclusive de outros usuários): tarefa no tt com o diagnóstico, que também vai no handoff.
- Nunca: imprimir ou copiar segredo; publicar (push, `--sincronizar`, `--email-propagar`); apagar dado do
  usuário sem backup; mexer em credenciais das IAs.
- Execução: Claude com `--dangerously-skip-permissions` (headless, ninguém responderia a uma pergunta);
  os limites acima vão no pedido. O `ia-rot -p … --dangerously-skip-permissions` já repassa a opção ao Claude
  e a traduz para o Codex (`--dangerously-bypass-approvals-and-sandbox`); o Kiro roda `--no-interactive`.
- Celular/máquina sem agente: só o coletor + aviso.

## Log centralizado

Um lugar só: `~/.local/state/tt/checagens/`

- `historico.log`: uma linha por rodada (`quando máquina de→para agente conta ok aviso falha corrigido`).
- `<versão>-<data>/relatorio.md`: checagens, evidências, o que o agente fez e por quê, como desfazer,
  o que ficou pendente.
- `<versão>-<data>/coletor.tsv`, `saida.log` (saída bruta do agente), `prompt.md`, `backup/`.
- Retenção: últimas 20 rodadas.
- Fim da rodada: `tt --notificar-daqui` (ou `--notificar` sem tmux) com o resumo
  (`🩺 v1.14.0: 9 ok · 1 corrigido · 1 falha`), clique abre o relatório.

## Handoff

`tt --checar-handoff [arquivo]` gera um `.tar.gz` (padrão `tt-handoff-<máquina>-<data>.tar.gz` na pasta de
recebidos) com:

- `checagens/` (histórico + últimas rodadas, sem `backup/`);
- fim dos logs: `tt-vigia.log`, `tt-malha.log`, `tt-letreiro.log`, `tt/pendencias.log`, erros de
  `email-sync/`, `tarefas-git.erro`;
- saída de `--versao`, `--atualizacao-estado`, `--pendencias --tsv`, `pk_resumo` e um `--checar` feito na hora;
- `LEIA-ME.md` com o índice.

Higiene:

- Nunca entra `~/.secrets`, `accounts.conf`, `.mbsyncrc`, credenciais de IA.
- Máscara antes de empacotar: tokens, senhas, `refresh_token`, `Authorization:`, padrões de chave;
  e-mails viram `f***@dominio`.
- Mostra o que entrou e o tamanho antes de terminar.
- Envio: `tt --enviar` (se na malha do mantenedor), anexo de e-mail, ou item 🩺 → abrir pasta.

## Testes

- `tests/test_checagem.sh` (isolado):
  - coletor: cada checagem em ok/aviso/falha com estado fabricado (vigia morto, `.erro` de e-mail,
    pacote com arquivo a mais, desvio de hora);
  - gatilho: versão nova dispara uma vez; máquina nova não dispara; `checagem_auto=0` não dispara;
    sem conta livre → 3 tentativas e fecha;
  - agente: `ia-rot` falso grava o pedido; confere que o pedido traz o trecho certo do `NOVIDADES.md`
    e os limites;
  - log: histórico, retenção de 20;
  - handoff: segredos plantados não aparecem no tar; e-mail mascarado; `~/.secrets` ausente do pacote.
- Rota do item 🩺 no menu administrar em `tests/INTERACTIONS.md`.
- Funções novas antes da guarda da partida rápida; arquivos novos em `ARQUIVOS_FONTE` e nas listas dos testes.

## Fora do escopo

- Disparar a checagem em outras máquinas a partir de uma (cada uma se checa ao atualizar).
- Receber handoffs automaticamente (o mantenedor recebe o arquivo e lê).
