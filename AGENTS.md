# tt-terminais · guia AI-DLC

Este é um projeto Bash/tmux orientado a interação. Uma mudança só está pronta quando o mesmo
resultado funciona pelos canais que o elemento expõe: CLI, teclado, mouse/toque, menu e barra.

## Ciclo obrigatório

1. Leia `AI-DLC.md` e `tests/INTERACTIONS.md` antes de alterar o comportamento.
2. Preserve configurações do usuário, sessões tmux e dados em `~/.config/tt/`.
3. Prefira um ambiente isolado (`HOME`, `XDG_CONFIG_HOME` e `TT_RT` temporários) para testes de
   fluxo; nunca use os arquivos ou socket tmux reais do usuário em um teste.
4. Rode `tests/run.sh` após cada alteração de comportamento.
5. Para mudança em interface, atualize a matriz de `tests/INTERACTIONS.md` e acrescente ao menos
   uma verificação executável que cubra a rota modificada.

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
