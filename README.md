# tt — central de terminais

Gerencia sessões tmux em várias máquinas (via Tailscale + ssh) num só menu, pelo teclado, mouse ou
toque (celular com Termux + mosh).

## O que faz

- **Central** (`tt`, `Ctrl+B s` ou botão ☰ na barra): todas as sessões de todas as máquinas, com
  prévia ao vivo, busca em nome/título do Claude/conteúdo da tela, filtro por máquina, painéis
  de cada sessão, janelas vazias agrupadas (e "fechar todas").
- **Barra clicável**: `máquina ▾` (menu de máquinas), `sessão ▾` (seletor rápido), ☰ central,
  ┃/━ dividir, ⋯ menu do painel, ⇅ arquivos, ⤢ caber nesta tela.
- **Painéis com outras sessões** (`^v`, `^o`, `^p`), inclusive de outras máquinas.
- **Arquivos entre máquinas**: navegador de pastas (→ entra, ← sobe, Tab marca, ⏎ confirma),
  sem sobrescrever (conflito vira `nome (2)`), aviso na tela de quem recebe.
- **⚙ tmux**: janelas, layouts, sincronizar digitação, histórico, mouse, atalhos, configuração.

## Instalação e máquinas

Cada máquina tem o tt em `~/.local/share/tt/` (`tt`, `tmux.conf`, `VERSAO`), com
`~/.local/bin/tt` apontando para lá e o `~/.tmux.conf` fazendo `source-file` do `tmux.conf` de lá
(ajustes só daquela máquina vão no `~/.tmux.conf`, depois do source-file).

    ~/.config/tt/config     nome=<como esta máquina aparece no menu>
    ~/.config/tt/maquinas   host  usuario  rótulo   (uma máquina cadastrada por linha)

Comandos:

    tt --cadastrar [host [usuario [rótulo]]]   testa o ssh, instala o tt lá e cadastra as duas
                                               máquinas uma na outra (também no menu de máquinas)
    tt --descadastrar [rótulo]                 tira do menu (aqui e lá); opcionalmente desinstala lá
    tt --sincronizar [rótulo…]                 instala esta versão aqui e nas cadastradas
    tt --versao                                versão instalada ("N hash data")

## Arquivos

    tt --enviar                         navega a partir da pasta atual, escolhe máquina e pasta
    tt --enviar a.pdf fotos/ empresa    envia para empresa:~/Recebidos
    tt --enviar a.pdf empresa:~/docs    envia para essa pasta
    tt --trazer                         escolhe máquina, pasta e arquivos de lá → pasta atual
    tt --trazer empresa:~/x.log [pasta] traz direto

Na central: `^s` envia para a pasta da sessão escolhida, `^g` traz de lá para a pasta do painel.

## Desenvolvimento

Este repositório é a fonte. Edite aqui, faça commit e rode `tt --sincronizar`: a versão é o número
de commits (`+dev` quando há mudanças não gravadas). Máquinas com versão mais velha aparecem com
⚠ no menu de máquinas, que oferece atualizar.
