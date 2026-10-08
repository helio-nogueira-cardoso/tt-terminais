---
name: tt-terminais
description: Referência completa do tt-terminais (central de terminais em Bash+tmux) para IAs operarem e evoluírem o projeto. Use ao trabalhar no repositório tt-terminais, ao diagnosticar a central/barra/sessões/fixadas/tarefas/e-mail/sync entre máquinas, ou ao usar os verbos `tt --...` por linha de comando. Cobre todos os verbos CLI, os ranges da barra e o roteamento de clique, os arquivos de perfil/estado/cache/pacote, o vigia e seus temporizadores, a sincronização por ssh e git, identidade de máquina/sessão/fixada, e-mail (aerc), celular/Termux, testes e as convenções de desenvolvimento.
---

# tt-terminais — central de terminais multi-máquina (Bash + tmux)

O `tt` é um único script Bash (`set -u`, arrays associativos) que oferece um menu único para todas
as sessões tmux de todas as máquinas do usuário (ligadas por ssh/Tailscale), com central, barra
clicável, fixadas, tarefas, transferência de arquivos, e-mail, nomeação automática de sessões e
sincronização de estado entre máquinas. A versão é o número de commits da `main`
(`git rev-list --count HEAD`, com `+dev` quando há mudança não gravada).

Esta skill descreve o comportamento REAL extraído do código. Trate tudo como mapa de navegação:
confirme no código antes de alterar contrato.

## Arquitetura em uma olhada

- `tt` — script principal: dispatch de verbos, central/seletor, barra e cliques, vigia, sync,
  identidade, e-mail, botões, empacotamento. O dispatch é um grande `case "${1:-}" in` no fim.
- `tmux.conf` — binds de teclado/mouse (prefixo `Ctrl+B`), hooks de tmux e roteamento de clique
  para o `tt`. No fim, `source-file -q ~/.config/tt/tmux.conf` carrega o perfil local.
- `tema-tmux.conf` — define a barra (`status-left`, `status-right`, `status-format[1]`) e os
  `range=user|...`, mais o padrão visual Catppuccin Mocha.
- `tema-terminal.sh`, `tema-agentes.sh`, `memoria-agentes.sh` — paleta do terminal, tema dos
  agentes de IA instalados, memória compartilhada dos agentes.
- `email-tt.py` — utilitário de e-mail (só stdlib: descoberta de provedor, OAuth2, teste, pastas,
  filtro HTML). Roda inclusive no Termux.
- `nomeador-local.py` — modelo local (llama.cpp) opcional para nomear sessões.
- `ia-conta`, `ia-rot`, `ia-login`, `contas-uso.py`, `skill-rodizio-de-contas.md` — rotação de
  contas de IA (ver a skill `rodizio-de-contas`).
- `atalhos-padrao`, `atalhos-padrao-mobile` — atalhos de barra padrão (desktop e Termux).
- `termux/celular.sh` — provisiona um celular do zero (Termux + Debian proot).
- `tests/` — suíte de regressão; `Makefile` → `make test`.

### Três lugares, três papéis (nunca os misture)

| Lugar | Variável | Papel | Quem escreve |
|---|---|---|---|
| `~/.local/share/tt/` | `$DIR_TT` (`TT_DIR`) | pacote geral, trocado inteiro a cada instalação | só o instalador |
| `~/.config/tt/` | `$CONF_DIR` (`XDG_CONFIG_HOME`) | perfil: escolhas do usuário | você e os menus do tt |
| `~/.local/state/tt/` | `$ESTADO_DIR` (`XDG_STATE_HOME`) | estado gerado pelo tt | o tt |
| `~/.cache/`, `/run/user/UID` | `$RT` (`TT_RT`) | cache e runtime descartáveis | o tt |

Código de aplicação nunca mora no perfil; escolhas do usuário nunca são sobrescritas pela
instalação; o pacote pode ser reinstalado sem perder nada do usuário.

## Verbos de linha de comando

Forma: `tt --verbo [args]`. Agrupados por área. Verbos marcados "(interno)" são usados pela própria
barra/fzf/vigia; os de usuário são os mais úteis no dia a dia.

### Instalação, pacote, atualização
- `tt --instalar [nome]` — primeira instalação a partir do clone; grava `repo=` no config,
  configura o `~/.bashrc` (salvo `TT_SEM_BASHRC=1`).
- `tt --instalar-aqui` — instala/atualiza o pacote nesta máquina.
- `tt --desinstalar-aqui` — remove a instalação local.
- `tt --configurar-bashrc` / `tt --remover-bashrc` — liga/desliga abrir no tmux via `~/.bashrc`.
- `tt --sincronizar [nome...]` — (na máquina de dev, a do `repo=`) instala esta versão aqui e nas
  cadastradas. Recusa rodar de clone atrasado em relação ao GitHub; nunca rebaixa.
- `tt --atualizar [--todas]` — instala a versão publicada mais nova nesta máquina (e nas cadastradas).
- `tt --verificar-atualizacao` / `tt --garantir-atualizacao` — checa / força estar na última.
- `tt --versao` — versão instalada ("N hash data").
- `tt --help` (`-h`, `ajuda`) — os verbos do dia a dia, a versão e onde está o resto. Uma opção
  desconhecida (`tt --xyz`) sai com código 2 e aponta para a ajuda (não abre a central).
- `tt --pacote` (interno) — emite o tar do pacote no stdout.
- `tt --aidlc [raiz]` — bootstrap AI-DLC no projeto (idempotente).

### Máquinas, cadastro, diagnóstico
- `tt --cadastrar [host [usuario [nome]]]` — testa ssh, instala o tt lá, cadastra as duas máquinas
  uma na outra. Sem host, lista as do Tailscale.
- `tt --descadastrar [nome]` — tira do menu (aqui e lá); opcional desinstalar lá.
- `tt --ocultar-maquina nome` / `tt --mostrar-maquina nome` — esconde/restaura no menu sem perder
  `host usuario rotulo` (4ª coluna `oculta`).
- `tt --maquinas` — lista "usuario@host rotulo" das acessíveis.
- `tt --candidatas` — Linux online na tailnet ainda não cadastrados.
- `tt --diagnosticar [nome]` — por que não conecta, camada por camada (desligada, sem rota, porta,
  precisa aprovar, policy nega, sem chave, timeout).
- `tt --reparar [nome]` — reautoriza a chave desta máquina usando outra cadastrada como ponte.
- `tt --saude` — painel: verde conecta, vermelho online sem acesso.

### Sessões, central, seletor, painéis
- `tt` (sem args) ou `Ctrl+B s` — abre a central (todas as sessões de todas as máquinas).
- `tt --nova [nome]` — cria sessão solta; `tt --nova-e-ir nome` cria e entra.
- `tt --fixar [maquina:]sessao` — fixa (ver Fixadas).
- `tt --renomear [sessao]` — pergunta um nome; `tt --sugerir sessao` sugere; `tt --nomear-todas`
  nomeia as genéricas (`janela-N`, `claude-N`).
- `tt --listar-tudo [--tsv|--para-ia]` — linhas do menu de todas as máquinas; `--para-ia` emite um
  TSV estável (contrato do "mestre de obras": máquina, sessão, anexada, ocioso, agente, rascunho,
  última linha etc.) para outra IA recomendar o que fechar.
- Internos do fzf/central: `--lista-tudo`, `--lista-rapida-central`, `--atualizar-uma-vez`,
  `--seletor`, `--seletor-em`, `--lista-seletor`, `--lista-rapida`, `--pos-atual`,
  `--cabecalho`, `--cabecalho-seletor`, `--clique`, `--clique-direito`, `--clique-linha`,
  `--clique-seletor`, `--clique-cabecalho`, `--previa`, `--previa-em`, `--fechar`, `--fechar-em`,
  `--fechar-vazias`, `--bordas`, `--ajustar`, `--guarda-tamanho`, `--ciclo`, `--descongelar`,
  `--focar`, `--soltar`, `--ponte`, `--ir-ponte`, `--adotar`, `--janela`, `--listar`,
  `--listar-leve`, `--atualizar-info`, `--pastas-sessoes`, `--pasta-de`,
  `--menu-painel`, `--menu-tmux`, `--menu-sessao`, `--menu-maquinas`, `--menu-admin`,
  `--menu-arquivos`, `--menu-atalhos`, `--menu-popup-ui`, `--avisar`.

### Fixadas (2ª linha da barra)
- `tt --fixar [maquina:]sessao` — fixa/desafixa a sessão.
- `tt --fixadas` — lista as fixadas; `tt --barra-fixadas` (interno) formata a faixa.
- Internos: `--aplicar-fixadas`/`--barras` (liga a 2ª linha), `--ir-fixada`, `--mover-fixada`,
  `--notificar TEXTO [SEGUNDOS]` (aviso na faixa de notificações, 3ª linha; expira sozinho), `--notifs` (histórico), chave `faixa_notif=0|1`. `--fixadas-popup [cliente]` (popup: ir/desafixar/reordenar ao vivo), `--mover-fixada-rel N ±1` e `--desafixar-n N` (índice 0-based do popup), `--alternar-fixada`, `--alternar-fixada-rotulo`,
  `--resolver-fixada`. Sync: `--propagar-fixadas`, `--receber-fixadas [V]`, `--puxar-fixadas`,
  `--reconciliar-fixadas`, `--marcar-fixadas`.

### Tarefas (gerenciador simples)
- `tt --tarefas [cliente]` — abre o painel: slide-over ancorado à direita (no tmux) ou lista texto
  (fora dele). Também `Ctrl+B t`.
- `tt --tarefa-add "texto"` — adiciona; `tt --tarefa-ok ID` conclui; `tt --tarefa-abrir ID` reabre;
  `tt --tarefa-rm ID` remove (lápide); `tt --tarefa-limpar` remove as feitas de vez;
  `tt --tarefas-arquivar-feitas`, `tt --tarefa-arquivar ID` (só de topo; leva as subtarefas),
  `tt --tarefa-restaurar ID`, `tt --tarefas-arquivadas` (histórico em texto).
- `tt --tarefa-add-natural "frase @sex 14h !alta *semanal #tag"` (multi-linha: 1ª linha é o título, o resto vira descrição) — cria lendo prazo
  (com horário opcional: `@sex 14h`, `@amanha às 9h30`, `@14:30`), prioridade, repetição, etiqueta e
  `tt --tarefa-editar ID "frase"` (relê a frase como na criação: texto, @prazo, !prio, *rep, #tag;
  marcador ausente tira o atributo; linhas além da 1ª substituem a descrição, senão ela fica;
  subtarefa: só o texto), `tt --tarefa-frase ID` (a frase atual: `tarefas_frase_de`, inversa de
  `tarefas_frase_ler`), `tt --tarefa-renomear ID "texto"` (só o texto); `tt --tarefas-ajuda` imprime o
  "Como usar" do painel. `tt --calendario [epoch]` é o seletor de prazo (imprime `EPOCH`, `EPOCH 1`
  com horário, `limpar` ou nada); `tt --calendario-agenda [dia]` é a agenda (relógio da barra).
- Conclusão (`tarefa_concluir`): mãe só conclui com todas as subtarefas feitas (senão imprime as
  que faltam e devolve 2; no painel vira a linha ⚠ `aviso=` do cabeçalho, mostrada uma vez; o
  `--tarefa-ok` sai 1 com a lista). A última subtarefa não conclui a mãe. Reabrir/criar subtarefa
  numa mãe feita reabre a mãe. Recorrente: avança o prazo (com `hora`) e reabre as subtarefas.
  `tarefa_limpar_feitas` só remove feitas de topo (cascata leva as subtarefas delas).
- Arquivo: estado `arquivada` no mesmo arquivo `tarefas`, meta `arq=EPOCH:a|f` (quando + estado de
  antes), via `tarefas_arquivo_mudar arquivar|restaurar --feitas|ID…` (uma passada de awk; mãe leva
  as subtarefas). `valida()` só aceita aberta/feita, então arquivadas ficam fora de lista, contas,
  agenda, calendário e lembrete; a aba `filtro=arquivo` (ARQ no awk) as mostra. Merge: rank
  removida > arquivada > feita > aberta no empate; `tarefas_compactar` só poda `removida`, então o
  histórico é permanente e sincroniza como as tarefas. `^l` = `tarefas_escolha` (a Arquivar padrão /
  x Apagar de vez / esc).
- Meta `hora=1`: o prazo tem horário (vence quando a hora passa; sem ela vale o dia todo, epoch às
  12:00). Lembrete (`--tarefas-lembrete`, a cada volta do vigia): com horário avisa
  `TT_TAREFAS_ANTECEDENCIA` (10) min antes, uma vez por prazo; sem horário, uma vez por dia. Avisa
  por notify-send/termux-notification e por `display-message` em cada cliente tmux.
- Internos da UI: `--tarefas-ui`, `--tarefas-lista [busca]`, `--tarefas-cabecalho`,
  `--tarefa-acao EVENTO CHAVE` (despachante único: toda tecla, clique e botão do painel passa por
  ele e devolve as ações do fzf), `--tarefa-nova-prompt`, `--tarefa-sub-prompt`,
  `--tarefa-desc-prompt` (editor_tt; `--tarefa-desc-editor` é o nome antigo), `--tarefa-prazo-prompt`, `--tarefa-editar-prompt`
  (frase preenchida; Ctrl+E abre o editor com a descrição embaixo e, nesse caso, `tarefa_editar … --desc` faz a
  descrição que voltou valer, mesmo vazia; `--tarefa-renomear-prompt` é o nome antigo),
  `--tarefa-remover-prompt`, `--tarefa-limpar-prompt`, `--tarefa-add-ui`, `--tarefas-barra`. Sync:
  `--receber-tarefas`, `--tarefas-espelhar`, `--tarefas-puxar`.
- Painel: um fzf com três modos (lista, ajuda, menu de ações de uma tarefa) guardados em
  `$RT/tt-tarefas-ui-UID` (`filtro=`, `modo=`, `exp=ID` por tarefa aberta, `clique=` para o duplo
  clique). Cada linha é `chave<TAB>desenho`: `ID`, `desc:ID`, `sub:ID`, `menu:ID`, `act:AÇÃO:ID`,
  `dia:N` (título de dia na Agenda), `criar`, `voltar` ou vazia. A lista é renderizada numa passada
  de awk (`TAREFAS_AWK`, LC_ALL=C, sem strftime; decodifica a descrição base64 no próprio awk; a
  descrição não entra na lista — só ≡ na linha e, com a tarefa aberta, a linha `desc:ID` que alterna a
  prévia, que é a visão da descrição: o cartão de `tarefa_preview`) —
  centenas de tarefas em ~0,1 s. Abas Hoje e Agenda (filtro `prazo` = abertas com prazo) agrupam por
  dia e ordenam pela hora.
- Calendário (`calendario_tui MODO`): datas por aritmética própria (`_cal_dias`/`_cal_civil`, sem
  `date` por célula), tela montada em linhas com regiões clicáveis registradas, redesenho sem
  limpar (não pisca), compacto quando a altura é < 32. `TT_CAL_TECLAS` roda sem tela (testes). O cabeçalho grava `$RT/tt-tarefas-mapa-UID`
  (linha, colunas, ação de cada aba/botão) e o clique consulta o mapa (FZF_CLICK_HEADER_*).
- Mouse no painel: clique numa tarefa abre/fecha (▸/▾); 2º clique na mesma linha em < 400 ms =
  duplo (marca feita) — detectado pelo tt, porque a recarga do 1º clique faz o fzf entregar dois
  cliques simples; botão direito = menu de ações. Não use `--id-nth` (o fzf perde o clique que
  chega durante a recarga) nem ligue `q` (impediria digitar tarefas com q).
- Teclado no painel: `⏎` alterna feita (ou cria o que foi digitado), `→`/`␣` abre, `←` fecha,
  `^n` nova, `^s` subtarefa, `^e` descrição, `^d` prazo, `^t` calendário, `^o` mais ações, `^p`
  prioridade, `^r` repetir, `^k`/`^j` move, `^x` apaga (confirma), `^l` limpa feitas (confirma), `F2`
  edita (= botão ✎ Editar e ⋯ menu → ✎ Editar: a frase com os marcadores volta para mexer), `Tab`
  troca a aba, `?`/`F1` ajuda, `esc` volta/limpa a busca/fecha.

### Atalhos de barra
- `tt --editar-atalhos` — edita os atalhos locais. `--atalhos-barra`/`--atalhos-lista` (internos)
  formatam/listam a partir de `atalhos-padrao` + `~/.config/tt/atalhos` (override por ID; emoji `-`
  desativa).

### Arquivos entre máquinas
- `tt --enviar [arquivo... [destino[:pasta]]]` — navega e envia; `tt --trazer [maquina:caminho [pasta]]`
  traz. `tt --pasta-padrao [maquina:pasta]` define a pasta de recebidos.
- Internos: `--receber`, `--transferir-fundo`, `--transferencias`, `--transferencias-barra`,
  `--empacotar`, `--tamanho`, `--listar-pasta[-em]`, `--previa-item[-em]`, `--resolver-pasta`,
  `--arq-acao`, `--cabecalho-arquivos`, `--abrir-pasta`, `--caminho-visivel`, `--pasta-recebidos`,
  `--conferir [--hash]`, `--destino-info`, `--confirmar-transferencia`, `--registrar-recebido`, `--recebidos`,
  `--info-arquivo`, `--parte-tamanho`, `--empacotar-de`, `--receber-parte` (cópia retomável de arquivo único ≥
  `TT_RETOMAR_MIN`, parte em `.tt-parte.<chave>` no destino), `--enviar --stdin NOME`,
  `--destinos`, `--definir-recebidos`, `--anexos-enviar` (anexos do aerc → recebidos de uma máquina).
  `--imagens` (tecla `i` do aerc: lista as imagens do e-mail cru em stdin e abre as escolhidas; as da
  web só são baixadas sob demanda, via `email-tt.py baixar-imagem`) e `--abrir-imagem ARQ` (opener `image/*`).
  `--email-adicionar provedor=gmail auth=oauth` sem client_id usa o app OAuth embutido do tt (EMAIL_GMAIL_ID; segredo montado em partes, gravado por conta em ~/.secrets). `--email-sync-local CONTA 0|1` (liga/desliga o espelho mbsync pós-cadastro; botão 🔄 em F2).
  `--pedir-sudo [id…]` (modal único das pendências de instalação com sudo: navegadores, email-sync,
  email-html; aceitar tudo / selecionar / recusar por 7 dias; pacotes por gerenciador, mbsync→isync).

### E-mail (aerc)
- `tt --email [cliente]` — abre o cliente de e-mail (default `aerc`) numa subjanela popup.
- `tt --email-contas` / `tt --email-conta` — gerenciador de contas; `tt --email-adicionar ...`
  cadastra por CLI; `tt --email-listar`.
- `tt --email-testar NOME`, `tt --email-autorizar NOME` (OAuth2), `tt --email-pastas NOME`,
  `tt --email-regerar NOME`, `tt --email-assumir NOME`, `tt --email-remover NOME`.
- `tt --email-propagar CONTA [máquina…] [--sobrescrever]` / `tt --email-receber SLUG [--sobrescrever|--sonda]`
  — leva a conta (`<slug>.conf` + segredos `aerc-<slug>.txt`/`.client_secret` de ~/.secrets) às outras
  máquinas por ssh direto (tar pelo stdin, sem arquivo intermediário), transacional e NUNCA automático:
  pergunta no fim do cadastro guiado, item ⇪ na tela da conta (F2 → conta; seletor
  `--email-propagar-ui CONTA`), ou `--email-adicionar … propagar=1|rótulos` (a chave não fica no .conf).
  Sonda o tt de lá (`--sonda` → `pronto existe=0|1 mbsync=0|1`) antes de mandar o segredo; tt antigo
  não recebe nada. Na chegada: só os 3 nomes de membro aceitos, validação, snapshot, segredos 600,
  `email_regerar`; sync_local=1 sem mbsync chega desligado com aviso; já existente só com --sobrescrever.
- Escrever (seção "Escrever e-mails" do tt; `configurar_aerc` põe em `[compose]`: `editor=tt --email-editor`,
  `format-flowed=true`, `empty-subject-warning=true`, `no-attachment-warning=^[^>]*(anex[oa]|anexei|attach)`,
  `address-book-cmd=tt --email-contatos %s`, `file-picker-cmd=tt --email-anexos-escolher %f`; binds
  `[compose::review]` a = `:attach -m` (seletor), A = `:attach<space>`): `tt --email-editor ARQ` =
  `editor_tt` + (se vim) `--cmd let g:tt_spelllang=… -S $DIR_TT/vimrc-tt-email` (`email_vimrc_garantir`:
  ft=mail, tw=72 fo+=w, spell, sem number, insert acima da citação; `TT_EMAIL_EDITOR_MOSTRAR=1` só
  imprime o comando); dicionário `~/.vim/spell/pt.utf-8.spl` por `email_vim_spell_garantir`
  (`TT_VIM_SPELL_URL`; baixa em 2º plano na instalação/1º uso; sem ele spelllang=en); `tt
  --email-contatos TEXTO` lê `~/.config/tt/email/contatos.tsv` (manual) + `~/.cache/tt/email-contatos.tsv`
  (índice `email-tt.py contatos-indexar --sem=próprios MAILDIR…`, refeito por `email_contatos_indexar`
  ao fim de cada sync completo ou em 2º plano se > 1 h); `tt --email-anexos-escolher ARQ` (fzf multi
  sobre recebidos + $HOME, sem terminal lê stdin); assinatura em `~/.config/tt/email/<slug>.assinatura`
  (`email_assinatura_editar`, `tt --email-assinatura CONTA`, `assinatura=` no --email-adicionar, pergunta
  no assistente, item g na tela da conta; `email_bloco` emite `signature-file` salvo se extra_* já tem
  `signature-`; entra no snapshot, no --email-remover e no pacote da propagação). Pendência de sudo
  `email-editor` (vim).
- Apagar/arquivar certos no Gmail (R6): `aerc_binds_gravar` (chamada por `configurar_aerc` e por
  `email_regerar`; copia o binds.conf de fábrica se faltar `<Enter> = :view`) põe no bloco do tt as
  seções de `email_binds_contas` (= `email_binds_contas_gerar d D a`): para cada conta de
  `email_contas_gmail` ("nome⇥lixeira⇥spam⇥todos", nomes relativos à pasta-mãe), `[messages|view:account=^Nome$]`
  d = `:choose … 'move <lixeira>'`, D = `:move <lixeira>`, a = `:delete` (tirar do INBOX = arquivar
  no Gmail, sem APPEND); `[…:folder=^<lixeira|spam>$]` d/D apagam de vez e `a =` (sem efeito), em
  `^<todos>$` só `a =`; nomes escapados por `re_escapar`. Na sessão oculta, `email_binds_botoes_contas`
  (= `… '<F9>' '' '<F8>'`) faz o mesmo para os botões ✕/▤. `@tt_email_binds` = `EMAIL_BINDS_VER:cksum(binds.conf)`:
  cadastro de conta recria a sessão oculta na próxima abertura. No `:choose` do aerc a resposta é a
  tecla + Enter. `email_remover_slug` apaga o .conf antes de regerar (as seções vêm da lista de .conf).
- `tt --email-ir-novo SLUG [cliente]` — abrir pelo aviso mostra a mensagem nova: o aviso de e-mail
  novo sai com a ação `email:SLUG` (notif_abrir → `email_ir_novo`): marca os avisos da conta como
  lidos (`<id>.lida` em $DIR_NOTIFS), fecha a tela do tt na frente e, pelo IPC do aerc (`email_ipc`:
  `aerc :comando`, socket `$XDG_RUNTIME_DIR/aerc.sock`, só com a sessão oculta rodando aerc; erro =
  linha `response:`), faz `:change-tab Nome` (global: vale com compose/terminal na frente) → `:cf
  INBOX` → `:select 0` → `:search -u` (foca a não lida mais recente; `:clear` depois desfaz, não
  usar) → `:view` só no modo estreito → `:check-mail`; sem sessão oculta, o salto espera o aerc
  subir em 2º plano e o popup abre como sempre (`botao_email`); `TT_EMAIL_SEM_POPUP=1` só nos
  testes. `--email-saltar-novo SLUG` é o salto sozinho. Nunca teclas cegas.
- `tt --email-sync-agora [cliente]` — ⟳ Sincronizar agora (botão `sync` de EMAIL_BOTOES com o estado
  em `@tt_email_sync`; `<C-s>` em [messages]/[view] do bloco do tt; item do menu do 📧): INBOX de
  todas as contas com espelho em paralelo (`email_sync_manual`: espera a trava até 20 s; se a volta
  completa a segura, marca `<slug>.interrompida` + `pkill` do mbsync dela e segue — a rodada
  derrubada fica no registro como `interrompida`, não erro; não respeita a espera do vigia), conta não
  lidas antes/depois (`email_nao_lidas_inbox`), retorno por display-message no cliente, "✓ N novos"
  no botão por 6 s, e F11 (`:check-mail`, só com o aerc na frente) para as contas só IMAP.
- `tt --email-sync [NOME] [--completo]` — espelha por mbsync as contas com `sync_local=1` (padrão só
  o INBOX; `--completo` o grupo inteiro); `tt --email-sync-estado [curto]` — última rodada por conta
  e modo (estado em `$ESTADO_DIR/email-sync/<slug>`, erro em `<slug>.erro`; `curto` = ok|nunca|atrasado|
  erro|parado por conta, para a barra — `email_sync_resumo`); `tt --email-mbsync-migrar` — regrava
  .mbsyncrc antigos (canal único, ou em canais sem `Timeout 60`) no formato de canais `<slug>-inbox`/`-pastas`/`-arquivo` + `Group <slug>` (a instalação
  chama). Pastas especiais `pasta_importantes`/`pasta_estrela` (marcas `\Important`/`\Flagged`)
  saem do espelho; `pasta_todos` vira o canal de arquivo com `MaxMessages`/`ExpireUnread`. Vigia:
  INBOX a cada `TT_EMAIL_SYNC` (120; `TT_EMAIL_SYNC_OCIOSO`=300 sem cliente tmux ativo há 10 min,
  gravado em `email-sync/.intervalo`), completo a cada `TT_EMAIL_SYNC_COMPLETO` (1800; ao iniciar só
  se `email_ultima_completa` já passou do prazo), teto `TT_EMAIL_SYNC_TETO` (600; INBOX 240). O vigia
  chama com `--vigia`, que respeita `<slug>.espera` (após erro: 2×, 4×… o intervalo, até 900 s;
  `<slug>.falhas` conta; sucesso zera); trava ocupada registra `pulada`. Depois de cada rodada `email_novos_avisar` (ids novos e não lidos em
  INBOX/new+cur vs. `email-sync/<slug>.vistas`; `email-tt.py cabecalho ARQ` dá "remetente<TAB>assunto"
  decodificados; `email_aviso=0` desliga) e `atualizar_barras`; `barra_email_fmt` (`tt --barra-email`)
  preenche `@barra_email` (não lidas do espelho; ⚠ vermelho se `--email-sync-estado curto` tem
  erro/parado, ⏳ âmbar se só atrasado), referenciada pelo range `email` do tema.
- `tt --email-atalhos` — tela de atalhos do aerc em português.
- Popup do e-mail: `email_sessao` cria a sessão oculta `_tt-email` e `email_sessao_botoes` liga nela
  uma linha de status própria com a barra de botões (`email_barra_fmt`, ranges `user|em_<ação>`,
  lista `EMAIL_BOTOES` = ação|ícone|rótulo|tecla); o clique chega por `MouseDown1Status → tt --clique`
  e `em_*)` em `clique()` chama `email_botao_acao`. Funciona de qualquer lugar: contas e atalhos são
  **telas do tt** (`email_tela atalhos|contas`, `tt --email-tela`) = janelas da própria sessão oculta
  com `@tt_email_tela`, barra visível; o mesmo botão de novo (ou q/Esc) fecha, abrir outra troca, e
  as ações do aerc fecham antes a tela da frente (`email_tela_fechar`) e mandam uma **tecla de
  função** (F3 abrir … F10 pasta; `send-keys -t =_tt-email:`), nunca letras — os binds da sessão
  oculta (`~/.cache/tt-aerc-binds-oculto.conf`, gerados em `email_sessao`: `email_binds_botoes` por
  contexto `[messages]`/`[view]`; `?`/F2 reescritos de `:term` para `:exec tt --email-tela …`) só agem
  na lista e na leitura, então com compose/terminal na frente nada é digitado. `EMAIL_BINDS_VER`
  marca a sessão (`@tt_email_binds`); sessão com binds antigos é recriada. A linha de status do
  aerc fica só com `{{.TrayInfo}}` (dicas antigas do tt migradas). Duplo clique no painel da sessão
  `_tt-email` = Enter (abre), via `if -F` no `DoubleClick1Pane` do tmux.conf.
  `configurar_aerc` também põe ícones (`icon-*`), `tab-title-account` com não lidas, datas numéricas,
  `message-list-split horizontal 14` + `auto-mark-read-split` (cópias em ~/.cache: tela < 100 sem split e sem sidebar, modo estreito; ≥ 180 `vertical 70`, modo amplo).

### Nomeador de abas
- `tt --nomeador [auto|local|claude|nenhum]` — define a fonte do nome automático.
- `tt --nomeador-local [estado|instalar|remover]` — modelo local llama.cpp.
- `tt --nomear-texto` (interno, lê stdin), `--nomeador-ui`, `--sugerir`, `--renomear`,
  `--nomear-todas[-local]`.

### Botões inteligentes (teclado F1–F10 / barra de teclas do Termux)
`tt --botao ACAO cliente painel pasta`. Mapeamento (tmux.conf): F1→`cl`, F2→`clc`, F3→`clr`,
F4→`dbn`, F5→`tela`, F6→`sair`, F7→`ant`, F8→`zm`, F9→`jn`, F10→`dv`.
- `cl` Claude conversa nova; `clc` continua a última na pasta; `clr` seletor de conversas; `dbn`
  Debian (proot, Termux); `tela` liga/desliga o túnel de tela remota (`tela_destino=`); `sair` fecha
  painel/janela/sessão se vazia, senão desanexa; `ant` sessão anterior; `zm` zoom; `jn` janela nova;
  `dv` divide pelo lado maior.

### Vigia, sync, tema
- `tt --vigia` (interno) — loop em segundo plano (ver abaixo).
- `tt --reforcar-padrao`, `tt --redesenhar`, `tt --tema-agentes`, `tt --tema-clientes`,
  `tt --memoria-agentes`, `tt --copiar-tela`.
- `tt --fechar-paradas`, `tt --definir-paradas N` (0 desliga), `tt --config-paradas`,
  `tt --encerrar-duplicados`.

### Área de transferência e contas de IA
- `tt --copiar`/`--copiar-buffer`/`--copiado` (clipboard Wayland/X/clip.exe + OSC 52);
  `--propagar-copia`/`--receber-copia`/`--copias` (histórico entre máquinas). `tt --copiar --tela
  LARGURA SX SY EX EY RETANGULO CLIENTE` (copy-pipe do tmux.conf, opção `@tt_copiar`) religa o que a
  tela partiu na borda (`links-tt.py desquebrar`).
- Links: `links-tt.py clique|copiar` (chamados pelo tmux.conf no clique/duplo clique; 0 = havia
  link), `tt --link-abrir ID CLIENTE PAINEL URL`, `tt --link-copiar CLIENTE URL`,
  `tt --links-tela CLIENTE PAINEL` (Ctrl+B u), `tt --abrir-link URL` (seletor de navegador).
- `tt --conta-propagar [nome] [alvos...]` / `tt --conta-receber [nome]` — move os arquivos próprios
  da conta Claude de forma transacional. `--receber-contas-ia`/`--propagar-contas-ia`/
  `--puxar-contas-ia` sincronizam o cadastro `contas-ia`. `--registrar`/`--desregistrar`/
  `--session-id` cuidam de registro e identidade de sessão.

## Barra: ranges e roteamento de clique

Contrato (AGENTS.md): cada `#[range=user|X]` desenhado precisa de uma rota em `clique()` (esquerdo/
toque) ou `clique_direito()` (botão direito). `tests/run.sh` verifica a lista de rotas.

Ranges e destino:

| range | onde | clique esquerdo | botão direito |
|---|---|---|---|
| `maquina` | status-left | `menu_maquinas` | `menu_admin` |
| `sessao` | status-left | `seletor_em` | `menu_sessao` |
| `fixar` | status-left (📌/📍) | `fixar_atual` | — |
| `ajustar` | status-right (⤢, condicional) | `ajustar` | — |
| `tt` | status-right (☰) | central (`display-popup`) | — |
| `painel` | status-right (⋯) | `menu_painel` | — |
| `email` | status-right (📧) | `botao_email` | `menu_email` |
| `tarefas` | 2ª linha, à direita (📋 N) | `abrir_tarefas` | `menu_tarefas` |
| `fx<chave>` | faixa de fixadas | `ir_fixada` | `menu_fixada` |
| `fxx<chave>` | faixa de fixadas (✕) | `desafixar_item` | `desafixar_item` |
| `fixmais` | chip `+N ▾` da faixa de fixadas | `fixadas_popup` | — |
| `at<N>` | atalhos | `atalho_executar` | `atalho_info` (tooltip, sem executar) |
| `transferencias` | status-right (⇅ N) | popup `--transferencias` | — |
| `copias` | `Ctrl+B y` | popup `--copias` | — |

Ordem na barra principal: `email` < relógio `%H:%M` (exigido pelos testes). A 2ª linha
(`status-format[1]`) tem `@barra_fixadas` à esquerda e `@barra_tarefas` + `@barra_versao` à direita.
`@barra_fixadas` é uma cadeia `#{?#{e|>=:#{client_width},LIM},#{E:@fxsK},…}`: cada versão (estágios
confortáveis 28/20/16 com ✕ e 16 sem ✕ — piso de legibilidade 16; depois `@fxoK_N` = N itens no piso +
`+N ▾`; 12/8/6 só com um item) fica em opções pequenas
(`@fxK_I` por item) gravadas de uma vez por `source-file` (a faixa inteira estourava o limite de um
comando tmux), e o tmux escolhe por cliente pela largura — redimensionar redesenha sem processo. No
estouro, o último lugar é `#{?#{==:#{session_name},…}}`: a sessão em uso de cada cliente. Rótulo:
`fixada_abrev` (por palavras, números inteiros; senão começo…última palavra; memo FX_ABREV) e
desempate de iguais; máquina remota = selo `fixadas_selos` (letra estável sobre todas as cadastradas,
cor pela ordem do cadastro), também em `fixadas_ui_lista` e `menu_maquinas`. `TT_FIX_LARGURA` força
uma largura (testes), `TT_FIX_VISIVEIS` é teto de itens; o carimbo `#{?,hash,}` muda a cadeia quando
um item muda, para a barra redesenhar.

Binds de teclado (prefixo `Ctrl+B`): `s` central, `t` tarefas, `|` split horizontal, `-` split
vertical, `c` janela nova, `r` recarrega config, `m` menu do painel, `y` histórico de cópias, `N`
renomear sessão, `F1..F10` botões. Mouse: arrastar/duplo/triplo clique copiam; botão do meio cola;
`MouseDown/Up1Status*` → `--clique`; `MouseUp3Status*` → `--clique-direito`;
`MouseUp3Pane`/`MouseDown3Border` → `--menu-painel`.

Contrato de toque: fixadas e o ✕ agem no **MouseDown** (a barra pode redesenhar entre pressionar e
soltar); menus agem no **MouseUp**. Um atalho de teclado deve ter a mesma ação observável do botão.

## Arquivos de perfil, estado e cache

### Perfil `~/.config/tt/`
- `config` — `chave=valor` (lido por `conf()`, pega a última ocorrência). Chaves conhecidas:
  - `nome` — nome desta máquina no menu.
  - `repo` — clone de origem (usado por `--sincronizar`).
  - `fonte` — URL do repositório para `--atualizar` (seguir um fork).
  - `recebidos` — pasta onde chegam arquivos (default `~/Recebidos`; no WSL, `Downloads\Recebidos`).
  - `email` — binário do cliente de e-mail (default `aerc`).
  - `tela_destino`, `tela_porta`, `tela_url` — túnel do botão `tela` (F5).
  - `tarefas_sync` — `p2p` (default) | `git` | `ambos` | `off`.
  - `tarefas_repo` — URL de um repositório git pessoal para sincronizar tarefas.
- `maquinas` — `host  usuario  rotulo [oculta]` por linha (`host -` = formato antigo sem usuário).
- `atalhos` — atalhos locais da barra (override de `atalhos-padrao` por ID; emoji `-` desativa).
- `fixadas` (+ `.v` versão em ns, `.trava` lock) — `maquina\tsessao\tchave`.
- `tarefas` (+ `.v`, `.trava`) — `id\testado\tcriada\tmudada\ttexto`, estado = `aberta|feita|removida`.
- `contas-ia` — `provedor\temail\tapelido\thora` (cadastro comum das contas de IA).
- `tmux.conf` — ajustes de tmux só desta máquina (carregado depois do pacote).
- `termux.properties` — barra de teclas própria do Termux.
- `email/<slug>.conf` — config por conta (sem segredo). `mbsync/<slug>.mbsyncrc` — sync local.
- `AI-DLC.md` — política AI-DLC própria (se existir, substitui a do pacote).

### Segredos `~/.secrets/` (modo 600)
`aerc-<slug>.txt` (senha de app ou refresh token OAuth2), `aerc-<slug>.client_secret`. Nunca são
impressos, copiados entre máquinas, nem vão para o `accounts.conf`.

### Estado `~/.local/state/tt/`
Memória de agentes (`ai-memory`), estado do celular, avisos, `tarefas-git/` (clone do repo pessoal
de tarefas).

### Cache e runtime
`~/.cache/tt-vigia.log`, `tt-github-versao`, `tt-anexos/`, `tt/maildir/<slug>` (sync local);
`$RT` (`/run/user/UID` ou `TT_RT`): pidfile e estado do vigia, lock de clique, cache de máquinas,
ControlPath do ssh, transferências em andamento.

### Pacote `~/.local/share/tt/`
`ARQUIVOS_FONTE` (lista no `tt`): `tt email-tt.py tmux.conf tema-tmux.conf tema-terminal.sh
tema-agentes.sh memoria-agentes.sh atalhos-padrao atalhos-padrao-mobile README.md AI-DLC.md
ia-conta ia-rot ia-login contas-uso.py skill-rodizio-de-contas.md nomeador-local.py
skill-tt-terminais.md`. `ARQUIVOS_PACOTE` = `ARQUIVOS_FONTE` + `VERSAO`. Mudança que acrescenta um
arquivo ao pacote PRECISA entrar em `ARQUIVOS_FONTE`, senão a autoatualização instala um pacote
incompleto.

## O vigia (`tt --vigia`)

Loop em segundo plano, instância única por pidfile em `$RT`. Log em `~/.cache/tt-vigia.log` (cortado
a 1500 linhas ao passar de 3000). Ao iniciar, `faxina_vigia` remove restos: estado de vigias de
servidores tmux mortos, sidecars de menu e marcas de tema com mais de um dia, temporários de gravações
atômicas (`fixadas.XXXXXX` etc.) com mais de uma hora. A cada volta: `atualizar_barras`. Em intervalos:
- Info das máquinas (sessões e versão, para o menu de máquinas) a cada `TT_T_INFO` s (300).
- Fixadas/tarefas a cada 300 s: `--puxar-fixadas`, `--reconciliar-fixadas`, `--tarefas-puxar`; na
  mesma volta, a sonda por ssh das pontes órfãs (o fechamento por ociosidade é local e roda sempre).
- Contas de IA a cada 1800 s: `--puxar-contas-ia`.
- E-mail (sync local) a cada `TT_EMAIL_SYNC` s (default 120; 300 ocioso; 0 desliga): `--email-sync --vigia`.
- Padrão visual + memória a cada 300 s: `--reforcar-padrao`, `--memoria-agentes`.
- Atualização a cada `TT_T_ATUALIZACAO` s: `--garantir-atualizacao`.
- Toda volta: fecha sessões paradas, pontes ociosas, Claude duplicados, janelas vazias abandonadas.
- Nomeação automática por sessão (título do Claude; primeiro nome; revisão por pontos).

### Variáveis de ajuste (defaults)
`TT_T_PRIMEIRO`=60, `TT_T_RENOMEAR`=300, `TT_T_PASTA`=120, `TT_T_REVISAO`=1800, `TT_T_INFO`=300,
`TT_T_PONTE`=1800, `TT_PAUSA`=60, `TT_T_ATUALIZACAO`=1800 (0 = toda volta), `TT_PESO_PEDIDO`=3, `TT_PONTOS_RENOMEAR`=10,
`TT_EMAIL_SYNC`=180, `TT_FIX_VISIVEIS`=8, `TT_TAREFAS_LAPIDE_DIAS`=30. Flags: `TT_FORCAR` (pula
proteção de downgrade), `TT_SEM_BASHRC` (instala sem mexer no `~/.bashrc`), `NOTMUX=1 bash` (abre
terminal sem tmux), `TT_AI_MEMORY_DIR` (dir da memória de agentes), `TT_GIT_NAME`/`TT_GIT_EMAIL`
(commit do repo de tarefas), `TT_MACHINE`/`TT_DIR`/`TT_RT`.

## Sincronização entre máquinas

Protocolo comum: itera `maquinas` e roda `ssh "${SSH_OPC[@]}" dest "$TT_REMOTO --receber-*"`.
`SSH_OPC` = BatchMode, ConnectTimeout 4, StrictHostKeyChecking accept-new, ControlMaster/Persist
(socket em `~/.cache/tt-ssh-%r@%h`, 12 h), keepalive. `TT_REMOTO` força o PATH (homebrew/local) e
chama `~/.local/bin/tt`. `dest_de ROTULO` resolve `.` (local) ou `usuario@host`.

- **Fixadas**: versão em `.v` (ns da última mudança); `receber_fixadas` só aceita versão mais nova
  (uma máquina atrasada nunca desfaz mudança nova); `puxar_fixadas` busca a maior entre todas. Lock
  por `mkdir` atômico.
- **Tarefas**: modos `p2p` (ssh como fixadas), `git` (repo pessoal `tarefas_repo`), `ambos`, `off`.
  O merge é **por tarefa**: por `id`, vence o maior `mudada`; empate favorece `removida` > `feita`
  > `aberta` (remoção vira lápide e nunca ressuscita). P2P e git interoperam sem perder tarefa.
  Modo git: clone depth 1 em `$ESTADO_DIR/tarefas-git`, pull `--ff-only`, merge por tarefa no
  arquivo do repo, commit (`TT_GIT_NAME/EMAIL`), push. Credencial fica no git/ssh do usuário.
- **Contas de IA**: cadastro `contas-ia` sincroniza por par (provedor,email), mudança mais nova
  vence. As credenciais NÃO são copiadas (cada máquina faz o próprio login; copiar derrubaria a
  outra na renovação do token).

## Identidade

- Máquina: `TT_MACHINE` > `nome=` (config) > `hostname -s`; normalizada com `_`→`-` onde a barra/IA
  a exibem.
- Sessão: opção tmux `@tt_session_id`; se vazia, gera `sha256(maquina\0sessao\0pid\0ns)` (32 hex) e
  grava — não muda num rename.
- Fixada: `fixada_chave` = `sha256(maquina\tsessao)` cortado em 12 hex (o argumento `range=user|X`
  do tmux tem limite de 15 bytes). O clique resolve a sessão pelo `@tt_session_id` para sobreviver a
  renomeações durante o sync.

## E-mail (resumo)

Cliente configurável (`email=`, default `aerc`), aberto numa subjanela `display-popup` (não cria
sessão de trabalho; roda numa sessão oculta `_tt-email` fora da central/seletor/vigia). Contas em
`~/.config/tt/email/<slug>.conf` (sem segredo); segredos em `~/.secrets` (600). O `accounts.conf` do
aerc é gerado entre marcadores `# >>> tt e-mail: <slug> >>>` (blocos à mão ficam intactos).
`email-tt.py` descobre provedor (autoconfig/MX, detecta Microsoft 365 e Google), faz OAuth2 (código
no aparelho ou navegador), testa IMAP/SMTP, lista pastas e converte HTML — sempre sem imprimir
senha/refresh token. Sync local opcional (`sync_local=1`) por mbsync em `~/.cache/tt/maildir/<slug>`;
envio continua SMTP online.

## Celular / Termux

`termux/celular.sh` provisiona um aparelho do zero: pacotes do Termux, sshd por chave na porta 8022,
boot automático, Debian via proot-distro com o Claude, e o tt. Subcomandos: `verificar`,
`conectar eu@pc`, `android`, opções `--nome`, `--chaves-github`, `--sem-claude`. É idempotente
(`*.antes-celular` como backup). O proot do Android não tem `/dev/fd` (evite `<(...)`) nem `iconv`
(por isso a remoção de acentos é feita em Python). Perfil de atalhos: `atalhos-padrao-mobile`.

## Testes e desenvolvimento

- `make test` → `tests/run.sh`. `make test-installed` roda contra `~/.local/share/tt`.
- Cada `tests/test_*.sh` roda isolado em `HOME`/`XDG_CONFIG_HOME`/`TT_RT` temporários e um socket
  tmux próprio — **nunca** toque o tmux/arquivos reais do usuário num teste.
- `run.sh` faz: testes de comportamento, asserts estáticos (`bash -n`, Python da ponte de mouse,
  vigia exige versão publicada, etc.), tmux isolado, e o **contrato de rotas** (cada `range=user|X`
  tem `X)` em `clique()`), botões 📧/📋 (range + rota + verbo + posição), guardrails de segredo do
  e-mail, binds de mouse/status e teclas F1–F10.
- Ciclo obrigatório (AGENTS.md) ao mudar comportamento: ler `AI-DLC.md` e `tests/INTERACTIONS.md`;
  preservar config/sessões/dados; testar isolado; rodar `tests/run.sh`; para interface, atualizar a
  matriz em `INTERACTIONS.md` e acrescentar ao menos uma verificação executável da rota.
- Uma mudança só está pronta quando o mesmo resultado funciona por todos os canais do elemento:
  CLI, teclado, mouse/toque, menu e barra.
- Mudança que acrescenta arquivo ao pacote deve entrar em `ARQUIVOS_FONTE` no `tt`.

## Requisitos

Núcleo: bash, tmux ≥ 3.4, fzf ≥ 0.60, python3, ssh, tar (GNU), rg. Opcionais: tailscale (descoberta
e estado online das máquinas), mosh (celular), pv (barra de progresso), claude (botões cl/clc/clr e
nomeador), aerc (e-mail), mbsync/isync (sync local), git (sync de tarefas por repo). macOS: bash ≥ 4
pelo Homebrew; comandos remotos levam o PATH do Homebrew (o instalador acrescenta um bloco ao
`~/.zshenv`).

## Agente lança agente em outra máquina

Caso de uso: uma IA rodando numa máquina precisa de ajuda numa tarefa que só faz sentido em
OUTRA máquina (ex.: depurar algo no celular). Em vez de operar a outra máquina por controle
remoto de tela, ela **lança um agente lá**, que roda no ambiente nativo daquela máquina e devolve
o resultado. Para o agente remoto é muito mais fácil atuar localmente (ele tem o shell, os
binários e os dispositivos da máquina dele) do que o agente de origem tentar tudo por cima da rede.

Importante: o tt **não** tem um verbo único `tt --spawn-agente`. O que existe são primitivas que se
compõem. A conexão ssh já vem pronta e autenticada (Tailscale + `SSH_OPC`, multiplexada 12 h), e os
agentes já estão instalados em cada máquina (`ia-conta`/`ia-rot`/`claude`/`codex`/`kiro`). O caminho
suportado é: **ssh + `tmux new-session` com o agente como comando** (o mesmo padrão que
`atalho_executar` usa localmente, só que disparado por ssh).

### Passo a passo

1. **Descobrir a máquina alvo**: `tt --maquinas` (rótulo → `usuario@host`). Ex.: `helio@s23-...  s23`.
2. **Lançar o agente lá, numa sessão tmux nomeada** (headless, destacada):
   ```bash
   # a partir de qualquer máquina do mesh, para o rótulo "s23":
   dest=$(tt --maquinas | awk '$2=="s23"{print $1}')
   ssh "$dest" 'PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH";
     tmux new-session -d -s ajuda-adb -c ~ \
       "ia-conta abrir -p \"<prompt da tarefa, com contexto e onde gravar o resultado>\"; exec bash"'
   ```
   - `ia-conta abrir` escolhe a conta de IA com mais folga de uso naquela máquina e abre sem pedir
     permissões; dá para trocar por `codex`/`kiro-cli chat`/`claude` conforme o motor desejado.
     No celular (Termux), o agente roda dentro do Debian via proot (atalho `dbn`/F4).
   - `tt --nova nome` cria uma sessão remota, mas **sem** comando — por isso o `tmux new-session`
     com o comando do agente é montado à mão.
   - A sessão fica com um shell ao fim (`exec bash`), então dá para entrar e ver como terminou.
3. **Acompanhar/operar o agente remoto** (opcional), por uma **ponte**: na central (`tt`), abra a
   sessão da outra máquina — o tt faz `ssh -t ... tmux attach -t =ajuda-adb` num painel local
   (`abrir_painel`/`ponte`/`ir_ponte`). Você vê e digita no agente de lá como se fosse local.
4. **Descobrir o que roda lá** (polling): `ssh "$dest" 'tt --listar-tudo --para-ia'` devolve o TSV
   das sessões daquela máquina (coluna `agente` indica claude/codex/kiro/… vivo no pane, `ultima_linha`
   mostra a última linha de conteúdo).
5. **Receber o resultado de volta**, opções reais:
   - **Arquivo** (melhor para resultado estruturado/grande): o agente remoto grava um arquivo e
     manda com `tt --enviar resultado.md <rótulo-de-origem>`, ou o chamador puxa com
     `tt --trazer s23:~/resultado.md .` (tar+ssh, chega na pasta de recebidos; nunca sobrescreve).
   - **Clipboard broadcast** (texto curto, ≤ 2 MB, best-effort): o agente remoto copia o texto e ele
     aparece no histórico de cópias de todas as máquinas (`tt --copias`). É broadcast, não endereçado.
   - **tt-mesh** (canal git append-only entre as sessões-chefe): só se as máquinas participam do
     enxame; é lento (timers de 10–60 min) e é o fluxo do enxame, não um RPC sob demanda.

### O que NÃO existe pronto (componha à mão)

- Nenhum verbo `tt --spawn-agente maquina "prompt"`: o `new-session` com comando remoto é ssh cru.
- `ia-rot --passar` (handoff da skill `rodizio-de-contas`) é **local**: passa a tarefa para outra
  CONTA/agente da mesma máquina, não cross-máquina. Para cross-máquina seria copiar o arquivo de
  passagem e rodar `ia-rot --passar` via ssh no destino, manualmente.
- `ai-memory` (`memoria-agentes.sh`) é local por máquina e não sincroniza entre máquinas; não é
  canal entre agentes de máquinas diferentes.
- `--listar-tudo --para-ia` é por máquina; para ver todas, faça um laço sobre `tt --maquinas`.

### Exemplo prático (celular: Shizuku + adb no Debian proot, fora do Wi-Fi)

Situação real: uma sessão Kiro CLI numa máquina precisava entender como o celular (`s23`) usa o
**Shizuku** para coordenar o **adb** numa depuração **sem Wi-Fi** (adb por USB/par local), e isso só
podia ser investigado de dentro do próprio aparelho — ainda por cima com o agente rodando dentro do
**Debian via proot**, que não enxerga o adb do Android diretamente. Em vez de tentar operar o celular
por ponte de tela, a sessão lançou um agente no `s23` para investigar localmente e relatar:

```bash
# 1) achar o celular no mesh
dest=$(tt --maquinas | awk '$2=="s23"{print $1}')

# 2) lançar um agente no s23, numa sessão nomeada, com o prompt da investigação.
#    No Termux o agente roda no Debian (proot); o prompt orienta a usar o Shizuku como
#    ponte de privilegio para o adb do Android, ja que o proot nao acessa o adb direto.
ssh "$dest" 'PATH="$HOME/.local/bin:$PATH";
  tmux new-session -d -s ajuda-adb -c ~ "ia-conta abrir -p \
    \"Investigue, nesta maquina (celular Android, Termux + Debian proot), como coordenar o adb \
      via Shizuku SEM Wi-Fi (USB/par local). O agente roda no proot e NAO ve o adb do Android \
      direto: descubra o caminho real (rish/shizuku no Termux chamando o adb do lado Android, \
      ou adb sobre a porta local do par) e descreva os comandos exatos. Grave o achado em \
      ~/resultado-adb.md e no fim rode: tt --enviar ~/resultado-adb.md <rotulo-de-origem>.\"; \
    exec bash"'

# 3) (opcional) acompanhar ao vivo pela central (ponte), ou fazer polling:
ssh "$dest" 'tt --listar-tudo --para-ia' | grep -i ajuda-adb

# 4) o resultado chega pela pasta de recebidos quando o agente remoto roda o tt --enviar do prompt;
#    ou puxe voce mesmo:  tt --trazer s23:~/resultado-adb.md .
```

Por que isto é melhor do que operar o celular remotamente: o agente no `s23` executa `rish`/
`shizuku`, `pm`, `adb` e inspeciona o lado Android **de dentro do aparelho**, com os privilegios que
o Shizuku concede, sem depender de o adb estar exposto na rede; e devolve so a conclusao (um arquivo)
pela conexao do mesh. O agente de origem continua livre para outra frente enquanto isso.

## Fluxos comuns (receitas)

- **Publicar uma mudança para todas as máquinas**: edite no clone de origem (`repo=`), rode
  `make test`, `git commit`, `git push` para a `main`, depois `tt --sincronizar` (ou deixe o vigia
  de cada máquina puxar a versão publicada em até 5 min).
- **Cadastrar uma máquina nova**: `tt --cadastrar` (sem host lista a tailnet); depois
  `tt --saude`/`tt --diagnosticar` se não conectar; `tt --reparar` resolve "sem chave".
- **Investigar a barra que não desenha**: o dado vive no perfil (`fixadas`, `tarefas`); a barra lê
  a opção tmux (`@barra_fixadas`, `@barra_tarefas`) recalculada por `atualizar_barras`. Se a opção
  ficou dessincronizada, force `atualizar_barras` / `--aplicar-fixadas` / `tt --barras`.
- **Nome de sessão não muda**: nome dado à mão nunca é trocado; o automático depende de pedidos e
  tempo (pontos). `tt --nomeador` escolhe a fonte; `tt --nomear-todas` força agora.
