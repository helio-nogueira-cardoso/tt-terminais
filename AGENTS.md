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
   (`TT_TESTES_J`, padrão nº de CPUs até 8) e `TT_TESTES=regex` roda só alguns; um teste que mede tempo
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
