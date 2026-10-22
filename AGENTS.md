# tt-terminais · guia AI-DLC

Este é um projeto Bash/tmux orientado a interação. Uma mudança só está pronta quando o mesmo
resultado funciona pelos canais que o elemento expõe: CLI, teclado, mouse/toque, menu e barra.

## Ciclo obrigatório

1. Leia `AI-DLC.md` e `tests/INTERACTIONS.md` antes de alterar o comportamento.
2. Preserve configurações do usuário, sessões tmux e dados em `~/.config/tt/`.
3. Prefira um ambiente isolado (`HOME`, `XDG_CONFIG_HOME` e `TT_RT` temporários) para testes de
   fluxo; nunca use os arquivos ou socket tmux reais do usuário em um teste. Todo `tests/test_*.sh`
   se isola do tmux real: pelo `isolar()` do `tests/lib.sh` ou, sem ele, com
   `source "$(dirname "$0")/tmux-isolado.sh"` logo depois do seu `trap EXIT`. O `tests/run.sh`
   reprova teste sem isso e, com uma sentinela no tmux padrão, o teste que falar com ele.
4. Rode `tests/run.sh` após cada alteração de comportamento. Ele roda os testes em paralelo
   (`TT_TESTES_J`, padrão nº de CPUs até 8, também limitado pela RAM no Mac) e `TT_TESTES=regex` roda só alguns; um teste que mede tempo
   ou depende de tela sob carga leva a marca `# tt-teste: sozinho` e roda no fim, sem concorrência.
5. Para mudança em interface, atualize a matriz de `tests/INTERACTIONS.md` e acrescente ao menos
   uma verificação executável que cubra a rota modificada.

## Versão

O rótulo é `MAIOR.MENOR.PATCH` e **zera à direita quando sobe à esquerda**. O arquivo `MARCO` (ex.: `1.7`) é a série; o PATCH
são os commits depois do que o mudou. Entregou funcionalidade nova? Edite o `MARCO` (MENOR; quebra de compatibilidade: MAIOR) no
mesmo commit e dê ao título do `NOVIDADES.md` o rótulo novo (`## v1.8.0`). Correção ou ajuste: não mexa no `MARCO`. A ordem de
atualização entre máquinas continua sendo o nº de commits; não a troque. Teste: `tests/test_versao.sh`.

## Partida rápida

O tt instalado roda por um núcleo gerado na instalação (`rapido/`, ver README "Partida rápida"). Toda função
nova vai antes da linha `[[ -n ${TT_SO_CARREGAR:-} ]] && …` ("Fim das definições"); depois dela o gerador
recusa e a instalação fica sem partida rápida (`tests/test_partida_rapida.sh` acusa).

## Desempenho

O que roda por clique, tecla ou volta da barra não abre processo à toa (README "Desempenho do clique"):
`tem_cmd` em vez de `command -v` (no WSL, comando ausente custa ~35 ms), vários `set-option` num lote só
(`lote_add`: cada set redesenha todos os clientes), `atualizar_barras_pedir` depois de mudar um dado,
`printf -v`/`conf_em`/`read` no lugar de `date`/`$(conf)`/`cat`. `tests/test_desempenho.sh` guarda essas regras.

Nunca `wait` sem pids: guarde `$!` e chame `esperar "${pids[@]}"` (ou use `par`/`par_fim`). No bash 5.3, dentro
de um subshell com trabalho do shell de cima vivo, o `wait` sem pids gira a CPU para sempre
(`tests/test_esperar_subshell.sh`).

## Portabilidade: o tt roda em Linux **e** no macOS

Quase todo mundo que mexe aqui está numa máquina Linux, mas o dono também usa um Mac. Uma mudança que só funciona no Linux
está **quebrada**. No macOS: o shell padrão é o **zsh**; o `bash` do sistema é o **3.2**; `ps`, `sed`, `stat`, `date`, `pgrep`,
`script` são os do **BSD**; **não existe `/proc`**, `setsid`, `flock`, `getent`, `xdg-open` nem `notify-send`; o locale é
`en_US.UTF-8` (não há `C.UTF-8`); e `/var`, `/tmp` e `/etc` são links para `/private/…`. O `tt` já cuida de boa parte (põe as
ferramentas GNU do Homebrew na frente do PATH só dos processos dele, tem `flock` próprio, volta ao bash 5 sozinho), mas o código
novo precisa seguir estas regras:

1. **Nada de `/proc` direto.** Use `env_do_pid PID VAR`, `cwd_do_pid PID`, `cmdline_do_pid PID` (no `tt`/`voz`; `/proc` no Linux,
   `ps`/`lsof` no macOS). Em Python, siga `cwd_processo`/`inicio_processo` do `sessoes-ia.py`. Para "o processo está vivo?"
   use `kill -0 "$pid"`, não `[[ -d /proc/$pid ]]`. Se for mesmo só Linux, proteja (`[[ -r /proc/… ]]`) e dê um retorno.
2. **Aspas em `=alvo` de tmux em string de comando.** O tmux roda comandos de painel/popup pelo zsh, e `=sessão` sem aspas vira
   "comando não encontrado". Em string use `-t $(q "=$sessao")`. (Chamada direta `tmux … -t "=$s"` no bash está certa.)
3. **`tmux.conf`: sem `$variável` dentro de `if-shell`/`run-shell`.** O tmux a expande (vazia) ao carregar; use `#{formato}`. Sem
   `/proc/#{pid}/exe` puro: o retorno é `tmux -S #{q:socket_path}`.
4. **Todo script bash executável que usa bash 4+** (`declare -A`, `mapfile`, `EPOCHREALTIME`, `{fd}`, `@(…)`) começa com a
   guarda `BASH_VERSINFO` (copie a do `ia-conta`): o `env bash` do macOS pode achar o 3.2. O `tt` e os auxiliares já têm.
5. **Locale UTF-8:** no `tt`, `$TT_UTF8`, nunca `C.UTF-8` literal.
6. **`letreiro-tt.py` não lança processos** (roda para sempre na barra). O que precisa de `ps`/`lsof` vem do shell, uma vez
   (`tt --e-ponte`).
7. **Comandos que mudam entre GNU e BSD:** dentro do `tt` as ferramentas GNU do Homebrew já estão na frente do PATH no macOS, mas
   scripts que rodam fora dele (instalador, testes, ganchos) não podem assumir `sed -i` sem sufixo, `stat -c`, `date -d`,
   `readlink -f`, `grep -P`, `pgrep -c` ou `xargs -r`, `paste -sd,` sem o `-` final (o BSD exige o arquivo: `paste -sd, -`); opção do `pgrep` vai **antes** do padrão (`pgrep -n -f padrão`).
   Coisa de Linux (notify-send, xdg-open, setsid) só atrás de um teste de existência, com alternativa (`open`, `osascript`).
8. **Caminhos:** compare pastas com `-ef` ou `realpath` (no macOS `/var/x` e `/private/var/x` são a mesma).

**Testes (têm que passar no macOS também).** Fingir o nome de um processo: `exec_como NOME cmd…` e `nomear_script ARQ NOME`
do `tests/lib.sh` (no macOS o tmux lê o nome do executável, não o `argv[0]`; `exec -a` não serve). Terminal falso com stdin por
pipe/FIFO: `script -qfc "cmd" arquivo` (o `tests/macos-bin/script` traduz para o macOS). PATH enxuto: `PATH="$T/bin:$TT_PATH_BASE"`,
não `…:/usr/bin:/bin`. Não dependa do que a máquina tem (`/var/lib/apt/lists`, `system_profiler`, o `tailscale`/`paplay` de
verdade): ponha um falso no PATH do teste. Espere pelo que importa (o texto na tela) em vez de `sleep` fixo.
`tests/test_portabilidade.sh` reprova o código que reintroduz estes padrões (tetos de `/proc`, `C.UTF-8`, `=alvo` sem aspas…);
**rode-o sempre**. Se ele reprovar, a mensagem diz o que usar. Subir um teto só com um retorno para o macOS e dito no commit.

Ao transferir uma revisão para testes em outra máquina, use `git archive HEAD` após gravar os arquivos
no branch local. Isso preserva somente as fontes versionadas e evita metadados AppleDouble (`._*`)
que o tar do macOS pode acrescentar. Metadados nas pastas de amostras invalidam o catálogo e a
checagem de documentação; não são falhas desses componentes.

## Contratos de interação

- Cada `#[range=user|…]` desenhado na barra precisa de uma rota correspondente em `clique()` ou
  `clique_direito()`.
- Uma ação de toque não pode depender do redraw entre pressionar e soltar. Fixadas e seu ✕ usam
  `MouseDown`; menus que precisam esperar a soltura usam `MouseUp` de propósito.
- Um atalho de teclado deve ter a mesma ação observável de seu botão equivalente.
- Mudanças destrutivas devem pedir confirmação; “ocultar” nunca pode apagar host, usuário ou rótulo.
- Falhas de rede, tmux ausente ou um pacote de mouse incompleto não podem fechar a interface ou
  direcionar uma ação para outro alvo.

## Entrega

Documente quais cenários foram testados e mantenha `make test` verde. Mudanças que alterem o
pacote também devem incluir os arquivos novos em `ARQUIVOS_FONTE` no `tt`.
