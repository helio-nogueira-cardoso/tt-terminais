# AI-DLC · tt-terminais

Este diretório estabelece o `tt-terminais` como projeto AI-DLC mesmo em ambientes onde o runtime
`aidlc` ainda não esteja instalado. A fonte de verdade é `AI-DLC.md`; as instruções operacionais
para agentes estão em `AGENTS.md`; a matriz de qualidade de interação está em
`tests/INTERACTIONS.md`.

## Porta de qualidade

Antes de integrar uma mudança de comportamento:

1. execute `tests/run.sh` (ou `make test` quando `make` estiver disponível);
2. atualize a matriz e acrescente uma verificação executável para cada canal de interação novo ou
   modificado;
3. preserve a compatibilidade das configurações e o isolamento dos testes;
4. registre no commit a natureza do contrato alterado (`fix`, `feat`, `test` ou `docs`).

Quando o runtime externo estiver instalado, rode `tt --aidlc .` novamente para complementar esta
estrutura com seus adaptadores. Ele não substitui nem remove estes arquivos do projeto.
