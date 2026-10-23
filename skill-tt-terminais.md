---
name: tt-terminais
description: Referência completa do tt-terminais (central de terminais em Bash+tmux) para IAs operarem e evoluírem o projeto. Use ao trabalhar no repositório tt-terminais, ao diagnosticar a central/barra/sessões/fixadas/tarefas/e-mail/sync entre máquinas, ao TRABALHAR COM AS TAREFAS DO USUÁRIO (códigos e apelidos, registrar o que fez na descrição com `tt --tarefa-log`, atualizar, concluir, compartilhar por e-mail), ou ao usar os verbos `tt --...` por linha de comando. Cobre todos os verbos CLI, os ranges da barra e o roteamento de clique, os arquivos de perfil/estado/cache/pacote, o vigia e seus temporizadores, a sincronização por ssh e git, identidade de máquina/sessão/fixada, e-mail (aerc, contas e ENVIO sem tela com `tt --email-enviar`), celular/Termux, testes e as convenções de desenvolvimento. Use também quando o agente precisar AVISAR o usuário (pedir algo, dar retorno, avisar que uma rodada importante acabou): `tt --notificar-daqui` só notifica se ele não estiver olhando para a sessão, e o clique leva de volta a ela. E para pôr perguntas do AI-DLC no painel de tarefas, onde o usuário responde (`aidlc-tt`). E quando o agente precisar ENVIAR UM E-MAIL por uma conta do usuário (`tt --email-enviar`, campos `--para --assunto --corpo --anexo`, `--ensaio` antes). E quando o agente precisar de um terminal interativo (sudo, ssh, prompts, instaladores): `tt --pty`.
---

# tt-terminais — central de terminais multi-máquina (Bash + tmux)

O `tt` é um único script Bash (`set -u`, arrays associativos) que oferece um menu único para todas
as sessões tmux de todas as máquinas do usuário (ligadas por ssh/Tailscale), com central, barra
clicável, fixadas, tarefas, transferência de arquivos, e-mail, nomeação automática de sessões e
sincronização de estado entre máquinas. A **ordem** das versões (o que a propagação e o vigia comparam)
é o número de commits da `main` (`git rev-list --count HEAD`, `+dev` com mudança não gravada), o 1º campo do `VERSAO`. O
**rótulo para humanos** é hierárquico `MAIOR.MENOR.PATCH` (4º campo do `VERSAO`, mostrado como `v1.7.3`): o arquivo `MARCO`
(`1.7`) diz a série e o PATCH conta os commits depois do que mudou o `MARCO`; **quando um número da esquerda sobe, os da
direita zeram** (1.6.12 → 1.7.0). Funcionalidade nova abre série nova: edite o `MARCO` no commit que a entrega (MENOR; quebra de
compatibilidade = MAIOR, ex. `2.0`); correção e ajuste só somam PATCH. Os títulos do `NOVIDADES.md` usam o rótulo (`## v1.7.0`).

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
- `email-tt.py` — utilitário de e-mail (só stdlib; roda inclusive no Termux): descoberta de provedor
  (`descobrir`), OAuth2 (`oauth-autorizar`, `oauth-token`), testes (`testar`, `graph-testar`), envio (`enviar`,
  o do `tt --email-enviar`; `graph-sendmail`, o sendmail do aerc nas contas Graph), Microsoft Graph (`graph-sync`,
  `graph-classificar`), pastas e lixeira (`pastas`, `lixeira`), lote (`lote-pastas`, `lote-contar`, `lote-agir`),
  leitura (`html`, `linkify`, `imagens`, `baixar-imagem`, `cabecalhos`), contatos (`contatos-indexar`) e demandas
  (`demanda`). A lista com argumentos está no cabeçalho do próprio arquivo (`python3 email-tt.py` sem argumentos).
- `nomeador-local.py` — modelo local (llama.cpp) opcional para nomear sessões.
- `ia-conta`, `ia-rot`, `ia-login`, `contas-uso.py`, `skill-rodizio-de-contas.md` — rotação de
  contas de IA (ver a skill `rodizio-de-contas`).
- `atalhos-padrao`, `atalhos-padrao-mobile` — atalhos de barra padrão (desktop e Termux).
- `telas-agentes.py`, `telas-agentes.conf` — as telas dos agentes (confiar na pasta, atualização, termos, permissão…) e o
  que a voz faz com cada uma: responder sozinha a rotina e a pasta autorizada, perguntar a decisão.
- `voz`, `voz-audio.py`, `voz-windows.ps1` — o 🎤: conversa por voz com o tt (cérebro, regras e ações no `voz`; gravar,
  escolher o motor, transcrever, falar e a janela no `voz-audio.py`; o microfone do Windows no WSL pelo `.ps1`). No celular, `termux/bin/voz` roda o `voz` da raiz pelo bash do Termux.
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
- `tt --atualizacao-estado` — instalada × publicada, vigia vivo, última sonda, fonte e motivo das falhas (estado em
  `~/.local/state/tt/atualizacao`; 3 falhas seguidas = aviso 🔔). `tt --sondar-atualizacao` (vigia, a cada `TT_T_SONDA`=300 s,
  900 no Termux) = `git ls-remote`; só busca/instala quando o SHA publicado mudou; decisão por ancestralidade
  (`atu_relacao`: igual/atras/frente/divergente). Busca completa a cada `TT_T_ATUALIZACAO`=21600 s.
- `tt --repo-checar [--corrigir]` — no clone de desenvolvimento, o que trava a atualização; `--corrigir` move acréscimos
  locais do `.gitignore` para `.git/info/exclude`. `tt --atualizar` lá faz rebase dos commits locais; conflito → ramo `local/<data>`.
- `tt --versao` — versão instalada ("N hash data").
- `tt --demanda-autorizar EMAIL [etiqueta] [auth|relaxado|segredo|aberto] [segredo]` / `--demanda-remover EMAIL` /
  `--demandas` / `--demandas-pendentes` / `--demandas-processar [conta]` / `--demanda-aprovar ID` /
  `--demanda-recusar ID` / `--demandas-ui` — demandas por e-mail: e-mail de remetente autorizado (cadastro
  `~/.config/tt/demandas`, propagado por `--receber-demandas`/`--propagar-demandas`/`--puxar-demandas`) com `[tt] título @prazo !prio
  #tag` no assunto vira tarefa PENDENTE (estado novo no arquivo de tarefas) após o sync da conta; só vale com
  autenticação do provedor (padrão), modo relaxado (não exige auth; aceita auth ausente ou fail explícito), segredo ou modo aberto; aba Entrada do painel aprova/recusa.
- `tt --flutuante [status|on|off|alternar]` — painel de tarefas flutuante: com `painel_flutuante=1` e tmux
  3.8+ (detecta `new-pane -O -C -K`), `--tarefas`/📋 abrem um painel modal da janela que fecha ao clicar
  fora; desligado (padrão) ou sem suporte, é o popup de sempre. Item 🪟 no menu ⋯ do painel.
- `tt --hora [--sincronizar|agora]` — hora confiável: mostra o relógio da máquina, o desvio medido contra
  a internet (Cloudflare/Google/Apple, mediana; cache em `$RT/tt-hora`, válido por 12 h) e a hora que o tt
  usa nas tarefas e na barra; `--sincronizar` mede agora; `agora` imprime o epoch confiável. Config
  `hora_sync=0` desliga, `hora_urls=` troca os endpoints. Desvio ≥ 60 s: `@barra_hora` mostra a hora corrigida.
- `tt --vigia-garantir` — religa o vigia parado (confere no máximo a cada 30 s; cada clique na barra e o gancho `client-attached` chamam). `TT_SEM_VIGIA_AUTO=1` desliga (os testes). Salto de relógio entre duas voltas do vigia (sleep): a malha espera `TT_POS_WAKE` s (90); `TT_FOLGA_WAKE` (30) é a folga sobre 3 voltas que conta como salto.
- `tt --checar [--tsv]` — checagem desta máquina sem IA (vigia, atualização, separação pacote × perfil × clone, e-mail,
  tarefas, malha, agentes, pendências, hora, conversas das IAs): `id estado(ok|aviso|falha) resumo correção`; sai 1 com falha.
  `tt --checar-agente [--de VERSÃO] [--so-coletor]` abre uma rodada: com conta livre, `ia-rot -p … --dangerously-skip-permissions`
  na sessão oculta `_tt-checagem` com o pedido `checagem-prompt.md` (coletor + trecho do `NOVIDADES.md` + `checagens-tt.md` +
  `~/.config/tt/checagens.md` + limites); o agente corrige o que é desta máquina e escreve `relatorio.md` (3ª linha
  `RESUMO: ok= aviso= falha= corrigido=`); `--checar-fechar` (interno) grava `historico.log`, poda (`TT_CHECAGEM_MANTER`=20) e
  avisa no 🔔 (ação `checagem:RODADA`). Saída 2 = sem conta livre (nada criado), 3 = sem agente, 4 = já rodando.
  `tt --checar-ver [RODADA]`, `tt --checar-handoff [ARQ]` (tar.gz mascarado: rodadas sem `backup/`, fim dos logs, estado; nunca
  `~/.secrets`). Vigia: `--checar-auto` a cada 300 s (versão instalada > `checagens/versao-checada`; instalação nova só marca;
  sem conta repete a cada `TT_CHECAGEM_REPETIR`=1800 s até 3 vezes; `checagem_auto=0` desliga). `TT_IA_ROT` troca o rotador (`-` = nenhum; testes).
  Teste: `tests/test_checagem.sh`.
- `tt --novidades [--todas]` — a tela de novidades (novo = seções ACIMA do título guardado em `~/.local/state/tt/novidades-visto`, que é o do título mais novo visto, não o rótulo instalado: o rótulo anda com commits sem entrada e quem publica ao mesmo tempo; estado antigo, que não é título, cai na comparação numérica; o aviso `novidades_avisar` leva o código `novidades-v<título mais novo>`) (`NOVIDADES.md` formatado por `novidades_fmt`: negrito, código,
  subitens, quebra na largura até 100 colunas); `tt --novidades-fmt LARGURA` (interno) formata o Markdown do stdin.
- `tt --help` (`-h`, `ajuda`) — os verbos do dia a dia, a versão e onde está o resto. Uma opção
  desconhecida (`tt --xyz`) sai com código 2 e aponta para a ajuda (não abre a central).
- `tt --pacote` (interno) — emite o tar do pacote no stdout.
- `tt --aidlc [raiz]` — bootstrap AI-DLC no projeto (idempotente).

### Máquinas, cadastro, diagnóstico
- **macOS:** instalação e vigia (a cada 300 s) chamam `--tailscale-ws-garantir`: Node com WebSocket nativo,
  tailscaled e três LaunchDaemons conferidos, sem reinício quando saudáveis. `--tailscale-ws garantir|ativar|status|testar|desativar`
  usa `tailscale-ws.py`; grava estado/log em `$ESTADO_DIR/tailscale-ws/`. Só `sudo -n`, sem login automático;
  bridge pronto antes do proxy, rollback se falhar, opções do daemon preservadas. Linux/Termux não agem.
  `TT_TAILSCALE_WS_AUTO=0` suspende; testes (`TT_MAC_AUTO=0`, `TT_RT` ou HOME isolado) não tocam no sistema.
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
- **Sessão `_nome` = oculta**: nome começando com `_` (`_tt-email`, `_tt-vigia`) fica fora da central, do seletor,
  do mestre de obras, da renomeação do vigia e de toda poda (`[[ -n $ponte || $s == _* ]] && continue` em cada laço
  de `list-sessions`). Ponte (`@ponte`) é outra coisa: sessão que mostra uma sessão de outra máquina.
- **Janelas flutuantes**: todo `tmux display-popup` do código do tt cai em `popup_janela` (o wrapper `tmux()` do `tt` o
  intercepta; strings de menu, rodadas por outro shell, usam `$EU --popup …`, mesmas opções). Com `painel_flutuante=1`
  e `new-pane -O -C -K` vira painel modal (fecha ao clicar fora), com `TT_CLIENTE`/`TT_EM_JANELA=1` no ambiente
  (`em_popup` os reconhece). `popup_fixo` = display-popup que não deve fechar com um clique perdido (pendências,
  navegador). Tela nova: use `tmux display-popup` normalmente; para ser fixa use `popup_fixo`.
- **tmux certo**: um cliente 3.5a não conversa com servidor 3.6/3.8. `tmux_alinhar` (início do `tt`) acha o binário
  do servidor por `$TMUX` → `/proc/PID/exe` e, se o PATH acha outro arquivo, define a função `tmux` e `TT_TMUX_BIN`
  (exportado; `exec`, strings de popup e os `.py` usam). Script novo que chama tmux fora do `tt` deve fazer o mesmo
  (`ia-rot` e `links-tt.py` fazem); comando remoto leva `$PATH_REMOTO` na frente.
- Internos do fzf/central: `--lista-tudo`, `--lista-rapida-central`, `--atualizar-uma-vez`,
  `--seletor`, `--seletor-em`, `--lista-seletor`, `--lista-rapida`, `--pos-atual`,
  `--cabecalho`, `--cabecalho-seletor`, `--clique`, `--clique-direito`, `--clique-linha`,
  `--clique-seletor`, `--clique-cabecalho`, `--previa`, `--previa-em`, `--fechar`, `--fechar-em`,
  `--fechar-vazias`, `--bordas`, `--ajustar`, `--guarda-tamanho`, `--ciclo`, `--descongelar`,
  `--focar`, `--soltar`, `--ponte`, `--ir-ponte`, `--malha`, `--malha-completar`, `--malha-lista`, `--malha-vigia`, `--estado-maquina`, `--adotar`, `--janela`, `--listar`,
  `--listar-leve`, `--atualizar-info`, `--pastas-sessoes`, `--pasta-de`,
  `--menu-painel`, `--menu-tmux`, `--menu-sessao`, `--menu-maquinas`, `--menu-admin`,
  `--menu-arquivos`, `--menu-atalhos`, `--menu-popup-ui`, `--avisar`.

### Pré-carregamento de sessões
- `tt --precarregar [status|json|auto|economico|off]`: estado legível, diagnóstico JSON ou modo local.
  Administrar → ⚡ abre `--precarregar-ui` (`a`/`e`/`d`, `q`/Esc). Desligar mantém pontes em uso.
- `precarregar-tt.py`: coordenador por socket tmux/pacote; prioridade de fixadas/esquerda + recência,
  frequência, alternância e foco no fzf (300 ms). 3 candidatos/tela, 6 no total, duas preparações em paralelo;
  econômico/Termux/bateria ≤20%: 1/tela, 2 total; bateria <10%: sem especulação. Ajustes locais
  `precarregar`, `precarregar_total`, `precarregar_por_tela`; `TT_PRECARREGAR=0` desliga nos testes.
- `precarregar_remoto.py`: protocolo stdlib enviado em memória pelo SSH, sem instalação no destino.
  Espera bilhete de uso único, sem anexar usuário ao tmux. Clique valida ID estável + servidor/sessão e
  primeira tela antes de trocar apenas o cliente correto. Pedidos anteriores são cancelados; sleep,
  renomeação, sessão substituída, rede caída e cliente desconectado não provocam troca tardia.
- **Voltar a uma ponte viva é local:** a entrada curta da fixada faz RPC Unix e confere tty/PID/nascimento,
  dono, identidade, bilhete, PID do transporte e `@tt_pre_viva`. Sem SSH por retorno; também recupera a ponte após
  reinício do coordenador. A fixada local com ID estável usa a mesma entrada. Transporte encerrado limpa a marca,
  mesmo se o pane continua no prompt. Pressionar troca; soltar não repete. O coordenador já aberto também ativa a preparada ou prepara sob demanda. Sem coordenador/atendimento, reexecuta o comando
  original; resposta perdida nunca duplica. `TT_COMPLETO=1`/arquivo `trace` conservam o fluxo completo. Vigia em
  segundo plano. Ponte antiga sem marca viva precisa de uma abertura completa após atualizar.
- **Clique de dentro da ponte:** a fixada pede à origem antes de resolver o destino por SSH, levando o ID.
  Também ao escolher outra sessão da mesma máquina remota: não retargeta uma ponte identificada por dentro.
  `--ir-ponte P M S [ID]` usa entrada curta no coordenador aberto, escolhe apenas o cliente que vê P e respeita
  `TT_PRAZO`. Recusa da origem preserva a ponte do cache; a ida pela rede à origem continua necessária.
- **Empresa vendo o Mac:** `TT_PRE_TOKEN` no cliente de transporte habilita envelope no TTY, retirado por
  `NavigationStream` antes de desenhar e encaminhado ao RPC da origem, sem SSH adicional por clique. A origem
  continua controlando a troca; não retargetar a ponte por dentro. `@tt_pre_relay=1` indica a capacidade;
  transporte antigo é renovado na primeira troca. Cliques no Mac incrementam `encaminhadas_fluxo`; as trocas
  ficam nas métricas da empresa. Fragmentação, duplicação/expiração, teclado e resize têm teste com dois PTYs.
  Encaminhador frio é iniciado pelo clique e não encerra só por não ter tela física; não faz prefetch de aninhados.
- **Terminal de outro dono (Tailscale SSH: pty do root, 620):** o bilhete deixa um porteiro (`start_doorman`) com o
  terminal aberto, socket `/tmp/tt-pre-relay-UID/<token16>`; só envelopes daquela ponte; sai com o cliente tmux.
  `relay_nested`: terminal direto → porteiro (`encaminhadas_porteiro`) → SSH de volta (`falhas_encaminhamento`).
- **Mestra do ssh meio morta segura pipes** (mux entrega o stdout à mestra; os keepalives só a derrubam em ~45 s):
  nada de `communicate()`/`$(ssh …)` esperando o fim do pipe. Python: `execute()`/`finish()` leem até o processo
  terminar. Bash: `ssh_pedir VAR PRAZO DESTINO COMANDO [PRAZO_MESTRA]` (saída em arquivo; mestra com prazo curto,
  depois `-O stop` e conexão própria). Coordenador grava `vivo` a cada volta; cliente sem resposta de coordenador
  parado há 5 s o encerra (`coordinator_stuck`) e segue pelo caminho antigo (pedido vencido não vira troca tardia).
  Testes: `tests/test_ssh_mestra_presa.sh`, classe `SemTravar` em `tests/test_precarregar_fluxo_modelo.py`.
  Bilhete: 3 = sessão não existe (sai do histórico se tem ID: `forget`), 5 = tmux de lá lento (passageiro).
  `erros.log` do coordenador: voltas do laço > 2 s (fase a fase) e coordenadores encerrados como travados.
- **Identidade:** `@tt_session_id` é UUID persistente de 32 hex, atribuído uma vez sob trava e checagem de colisão.
  Nome só na descoberta inicial de legado sem ID. Havendo ID, não aceitar fallback por nome em clique, cache,
  reconciliação ou reconexão; exclusão/recriação é outra sessão. ID duplicado/ausente é recusa, nunca desempate
  por nome. `$N`/servidor são endereços de execução, conferidos junto ao UUID. Teste: `test_sessoes_identidade.sh`.
- Primeiro uso continua validando destino e primeiro quadro via rede. Sondagens: 10 ms no início do pedido,
  50 ms na espera lenta, 500 ms ocioso. JSON: `reutilizada`/`local`, contadores `reutilizadas`/`locais`;
  `clique_ms` mede pedido Python→troca, sem partida do chamador, pintura final ou SSH de volta à origem.
- Pontes `tt-pre-*` têm `@ponte`, `@tt_pre_owner`, `@tt_pre_token`, `@tt_pre_estado=espera|ativa`.
  `criar_ponte` e `fechar_pontes_ociosas` ignoram as de espera (gerenciadas pelo coordenador).
  Histórico privado em `~/.local/state/tt/precarregamento/`, 500 transições/7 dias; não sincroniza conteúdo.
  Runtime `/tmp/tt-pre-UID-HASH` modo 700 (Termux: no TMPDIR privado). Status sem tmux informa que aguarda sessão.
  Internos: `--precarregar-evento`, `--precarregar-ponte`,
  `--precarregar-remoto`, `--precarregar-confirmar`. Ganchos tmux `[22]`, vigia e mudança de fixadas
  acordam o coordenador. CLI/barra/central e pedidos vindos de pontes convergem na máquina da tela.
  Testes `test_precarregar.sh` e `test_precarregar_modelo.py`.

### Fixadas (2ª linha da barra)
- `tt --fixar [maquina:]sessao` — fixa/desafixa a sessão.
- `tt --fixadas` — lista as fixadas; `tt --barra-fixadas` (interno) formata a faixa.
- Internos: `--aplicar-fixadas`/`--barras` (liga a 2ª linha), `--ir-fixada`, `--mover-fixada`,
  `--notificar TEXTO [SEGUNDOS]` (aviso na faixa de notificações, 3ª linha; expira sozinho), `--notificar-daqui TEXTO [SEGUNDOS] [--sempre]` (aviso de agente pelo 🔔: só se o usuário não estiver olhando para a janela de onde veio; abrir o aviso leva à sessão e ao painel; `--notifs-lidas` marca todos como lidos; `--notifs-listar [todas|naolidas|lidas]` = `id<TAB>lida<TAB>quando<TAB>texto` em texto puro (a voz lê por ele); `--notifs-limpar-lidas` apaga as lidas e imprime quantas; ver "Agente avisa o usuário"), `--notifs` (a central do 🔔: abas Todas/Não lidas/Lidas/Agentes/E-mail/Tarefas e botões ↗ Abrir, ◐ Lida/não lida, ✓ Ler todas, ✕ Apagar, 🧹 Limpar lidas (confirma) no cabeçalho, com mapa de cliques; tudo passa pelo despachante `--notifs-acao EVENTO ID` (internos `--notifs-cabecalho`, `--notifs-lista-ui`, `--notifs-previa ID` = a prévia do aviso em foco; estado em `$RT/tt-notifs-ui-UID`; uma linha por aviso, a em foco destacada com `--highlight-line`; nada de processo por aviso no desenho: `notif_quando_em`, `notifs_ids_em`); teclas ⏎, Espaço, Tab/Shift+Tab, `^u`, `^a`, `^d`/Del, `^r`, `^l`, Esc/q; exclusões usam lápides sincronizadas entre máquinas; teste `tests/test_notifs_central.sh`; arquivo do aviso = `exp\ttexto\tação\tcanal[\tcódigo]`: o 5º campo, opcional, é o código do EVENTO (`notificar TEXTO SEG AÇÃO CANAL CÓDIGO`), igual em todas as máquinas: aviso com o mesmo código não é recriado, a sincronização deixa um só na rede (o de menor id; cópias ganham lápide; o lido passa) e a lápide de aviso apagado guarda `codigo=…`; usado pelo `novidades-v<versão>` e pelo lembrete de tarefa `lembrete-<id>|<dia ou prazo>`; código de LOTE `BASE#item,item,…` para o evento que cada máquina percebe sozinha, em hora e número diferentes (e-mail novo: `email-<slug>#<chave>,…`, chave = 12 hex do sha1 do Message-ID, de `email-tt.py cabecalhos`; demandas: `demandas-<slug>#`, `demandas-espera-<slug>#`, `demandas-ignoradas-<slug>#`): o aviso leva só os itens que a rede ainda não avisou (`notifs_itens_conhecidos BASE`, vigentes + lápides com código) e, depois de cada junção, `notifs_lotes_normalizar` apaga, do mais velho ao mais novo, o que não traz item novo (o lido de quem some passa aos mais velhos que ele cobria inteiros); a poda guarda o código na lápide; a notificação do SISTEMA (`notificar_aparelho`) continua sendo de cada aparelho que percebe o evento; leitores do arquivo leem o 5º campo à parte (`read -r exp txt acao canal _`); teste `tests/test_notifs_sync.sh`), chave `faixa_notif=0|1`. `--fixadas-popup [cliente]` (popup: ir/desafixar/reordenar ao vivo), `--mover-fixada-rel N ±1` e `--desafixar-n N` (índice 0-based do popup), `--alternar-fixada`, `--alternar-fixada-rotulo`,
  `--resolver-fixada`, `--fixadas-girar cima|baixo [cliente]` (a roda no chip), `--fixadas-agrupar [cliente]`
  (botão direito no chip, `^g` no popup). Sync: `--propagar-fixadas`, `--receber-fixadas [V]`, `--puxar-fixadas`,
  `--reconciliar-fixadas`, `--marcar-fixadas`.

### Tarefas (gerenciador simples)
- `tt --tarefas [cliente]` — abre o painel: slide-over ancorado à direita (no tmux) ou lista texto
  (fora dele). Também `Ctrl+B t`.
- `tt --tarefa-add "texto"` — adiciona; `tt --tarefa-ok ID` conclui; `tt --tarefa-desfazer ID` desfaz a última
  conclusão (recorrente: volta um ciclo; senão reabre; sai 1 se não há o que desfazer); `tt --tarefa-abrir ID` reabre;
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
- Código e apelido (cada tarefa/subtarefa): `tt --tarefa-codigo [ID]` imprime `apelido<TAB>código<TAB>texto<TAB>referência` (sem
  argumento, de todas as vivas). O **código** é o próprio id (12 hex; igual em toda máquina e em e-mails) e o
  **apelido** (`kito47`: CVCV + 2 dígitos) sai dele (`tarefa_slug`; não é guardado). Todo verbo `--tarefa-*` que recebe
  ID (`ok abrir rm arquivar restaurar editar frase renomear sub-add desc implementar ia-prompt email codigo log
  historico`) e `--demanda-aprovar/recusar` aceita apelido, código, prefixo do código (4+ hex) e `MÃE.N`
  (`kito47.2`); ambíguo lista as candidatas e sai 1; apelido/`MÃE.N` que não existe sai 1 (`tarefas_resolver`).
  Subtarefa também aceita `MÃE.APELIDO-DA-SUB` e `MÃE.PREFIXO-DO-CÓDIGO` (procurados só entre as filhas daquela mãe).
- Registro de trabalho: `tt --tarefa-log ID "o que fez" --inicio RFC3339 --fim RFC3339 [--como T] [--agente A] [--modelo M] [--esforco E]
  [--tokens-ent N --tokens-sai N | --tokens N] [--usd V] [--brl V] [--conta C] [--email E] [--sessao S] [--sessao-codigo ID] [--maquina M]` acrescenta
  um bloco com instante de gravação UTC e período RFC 3339 (ambos os limites têm fuso explícito), código estável da sessão tmux, tokens e custos estimados em USD e BRL; `tt --tarefa-historico ID` mostra os
  blocos da tarefa e das subtarefas e os totais. Ver a seção "Tarefas: código, apelido, registro e e-mail".
- E-mail de compartilhamento: `tt --tarefa-email ID [destinatário] [--abrir]` imprime Para/Assunto/corpo e um link `mailto:` (`--abrir` abre o e-mail pronto no compositor); `tt --tarefas-email DESTINO ID…` abre um por tarefa; `tt --tarefa-email-ui [ID…]` escolhe as tarefas no fzf (lembra o último destinatário; `TT_EMAIL_PARA` preenche); recebido: `tt --demanda-diff|--demanda-merge|--demanda-aprovar [--recebida|--minha] ID`, `--demandas-aprovar-limpas`, `--demandas-recusar-todas`.
- Conclusão (`tarefa_concluir`): mãe só conclui com todas as subtarefas feitas (senão imprime as
  que faltam e devolve 2; no painel vira a linha ⚠ `aviso=` do cabeçalho, mostrada uma vez; o
  `--tarefa-ok` sai 1 com a lista). A última subtarefa não conclui a mãe. Reabrir/criar subtarefa
  numa mãe feita reabre a mãe. Recorrente: avança o prazo (com `hora`) e reabre as subtarefas, e grava na
  meta `ant` (prazos anteriores, vírgula, até `TAREFAS_DESFAZER_MAX`=3), `antsub` (subtarefas reabertas neste
  ciclo), `ciclos` (total feito) e `feito` (epoch do último). `tarefa_desfazer` (`--tarefa-desfazer`, `^z`,
  menu ↶) desempilha um prazo, devolve `antsub` a feitas e desconta o ciclo; sem `ant`, reabre uma feita.
  A linha mostra `✓ ciclo feito` enquanto `feito` tiver menos de 24 h.
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
- `tt --tarefa-implementar ID [cliente]` — IA na tarefa: abre a sessão `impl-N` (pasta do painel ativo do cliente)
  com `ia-conta abrir --prompt-arquivo $RT/tt-impl-ID.md` (a IA de mais folga; Claude/Codex/Kiro recebem o texto como
  1º pedido) e leva o cliente até ela. O pedido (`--tarefa-ia-prompt ID`) traz título, prazo, descrição e as
  subtarefas com ids; a IA marca cada uma com `tt --tarefa-ok` e avisa com `--notificar-daqui`; não publica sem
  ordem. Subtarefa: só ela. Painel: botão ✦ IA, `^g`, ⋯ menu → 🤖 (o painel fecha ao abrir).
- Internos da UI: `--tarefas-ui`, `--tarefas-lista [busca]`, `--tarefas-cabecalho`,
  `--tarefa-acao EVENTO CHAVE` (despachante único: toda tecla, clique e botão do painel passa por
  ele e devolve as ações do fzf), `--tarefa-nova-prompt`, `--tarefa-sub-prompt`,
  `--tarefa-desc-prompt` (editor_tt; `--tarefa-desc-editor` é o nome antigo), `--tarefa-prazo-prompt`, `--tarefa-editar-prompt`
  (frase preenchida; Ctrl+E abre o editor com a descrição embaixo e, nesse caso, `tarefa_editar … --desc` faz a
  descrição que voltou valer, mesmo vazia; `--tarefa-renomear-prompt` é o nome antigo),
  `--tarefa-remover-prompt`, `--tarefa-limpar-prompt`, `--tarefa-add-ui`, `--tarefas-barra`. Sync:
  `--receber-tarefas`, `--tarefas-espelhar`, `--tarefas-puxar`.
- `tt --tarefas-sync [status|agora|p2p|git|ambos|off] [url]`: sincronização desta máquina. Sem
  argumento mostra modo, repositório e a última troca (ou o motivo da falha); `agora` sincroniza já;
  `git`/`ambos URL` confere o acesso (`git ls-remote`) antes de gravar `tarefas_repo` e sincroniza.
  `--tarefas-sync-ui` é a tela do menu ⋯ do painel → 🔄 (também no botão direito do 📋).
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
  cliques simples; os 400 ms (`TT_TAREFAS_DUPLO_MS`; 1500 no Android) contam do FIM do 1º clique
  (`tarefa_acao` renova a marca `clique=` do estado da UI depois de pronta a lista), não do começo: o fzf
  só entrega o 2º quando o 1º termina, e numa máquina carregada o tempo do tt passava da janela;
  botão direito = menu de ações. Não use `--id-nth` (o fzf perde o clique que
  chega durante a recarga) nem ligue `q` (impediria digitar tarefas com q).
- Teclado no painel: `⏎` alterna feita (ou cria o que foi digitado), `→`/`␣` abre, `←` fecha,
  `^n` nova, `^s` subtarefa, `^e` descrição, `^d` prazo, `^t` calendário, `^o` mais ações, `^p`
  prioridade, `^r` repetir, `^k`/`^j` move, `^x` apaga (confirma), `^l` limpa feitas (confirma), `F2`
  edita (= botão ✎ Editar e ⋯ menu → ✎ Editar: a frase com os marcadores volta para mexer), `Tab`
  troca a aba, `?`/`F1` ajuda, `esc` volta/limpa a busca/fecha.

### Letreiro da faixa: fontes (APIs)
O miolo da faixa de notificações (3ª linha) rola o texto de **fontes**; cada uma é `~/.config/tt/letreiro/NOME.conf`
(versao=1; as nativas `dolar`/`frases`/`noticias` vivem no código e o arquivo só sobrepõe chaves; `letreiro/local/NOME.conf`
sobrescreve só esta máquina). Quem busca/extrai/formata/guarda cache é `letreiro-fontes.py` (vigia → `ticker_atualizar_fontes`
→ `atualizar`); quem desenha é `letreiro-tt.py` (um `#()` por cliente), que SÓ lê `~/.cache/tt-ticker/` (`NOME` = linhas com
marcas de cor \x01–\x04, `NOME.itens` = alvos de clique, `NOME.meta` = estado/diagnóstico, `_roda.json` = fontes ativas
desta máquina em ordem, `_energia`), nunca a rede. Log rotativo `~/.cache/tt-letreiro.log`. Segredo só em `~/.secrets`
(`segredo=@arquivo`).
- `tt --letreiro-listar [--tsv]` · `--letreiro-add NOME chave=valor… [--testar]` / `--catalogo ID [var=valor…]` (sem args,
  num terminal: assistente) · `--letreiro-editar NOME [chave=valor… | -chave] [--local]` (sem pares: formulário) ·
  `--letreiro-rm NOME [--sim]` · `--letreiro-duplicar A B` · `--letreiro-ativar/--letreiro-desativar NOME [--local]` ·
  `--letreiro-mover NOME +1|-1|inicio|fim|N` · `--letreiro-testar NOME|--arquivo F [--cor] [--gravar]` ·
  `--letreiro-log [NOME] [N]` · `--letreiro-exportar [NOME…]` / `--letreiro-importar ARQ [--sobrescrever]` ·
  `--letreiro-catalogo [ID]` · `--letreiro-segredo NOME` · `--letreiro-ajustes` / `--letreiro-ajuste CHAVE [VALOR]`
  (`ticker_ligado`, `ticker_rolagem`, `ticker_veloc`, `ticker_fps`, `ticker_separador`, `ticker_ordem`, `ticker_largura`,
  `ticker_pausa`, `ticker_cor`, `ticker_economia`, `ticker_bateria_min`, `ticker_ponte`, `ticker_idioma`, `ticker_fuso`) ·
  `--letreiro-migrar` (indicador_NOME=/indicadores= → arquivos; idempotente, roda sozinho) · `--letreiro-ler` (a linha de
  agora, sem buscar na rede) · `--letreiro-pausa [sim|nao|alternar|estado]` (imprime pausado|rolando; a marca é
  `$RT/tt-letreiro-pausa`, e o `letreiro-tt.py` sem `/run/user` usa o `$TMPDIR`, como o tt) · `--ticker-fontes`,
  `--ticker-quadro [largura]` (antigos, valem).
- Painel: menu ⋯ → 📰 (`--letreiro-ui`; despachante único `--letreiro-acao EVENTO CHAVE`, formulário
  `--letreiro-form-evento`/`--letreiro-form-exec`, assistente `--letreiro-assistente`, `--letreiro-menu-fonte`,
  `--letreiro-catalogo-ui`, `--letreiro-ajustes-ui`, `--letreiro-previa`, `--letreiro-ordem-ciclar`). `ticker_ordem` =
  `sequencial` (`manual` é o nome antigo) | `aleatoria` (mistura as entradas de todas as fontes: o desenhista ordena cada entrada por
  um hash de hora+fonte+linha+volta, então atualizar uma fonte não move as outras) | `peso`; `^o` no painel alterna sequencial ⇄ aleatória.
  O letreiro NÃO corta entradas: `truncar` e `valor_max` valem 0 por padrão (só cortam se o usuário pedir). Clique no item da faixa = range `letreiro` →
  `letreiro_clique` (url | copiar | painel | pausa). Aviso de falhas seguidas: `--notificar … letreiro`.
- Sync: `--receber-letreiro` (stdin), `--letreiro-pacote` (stdout), `--propagar-letreiro`, `--puxar-letreiro`; só fontes
  `escopo=global`, a `mudada` mais nova vence, lápides em `letreiro/.removidas`, nunca segredo.
- Internos: `--letreiro-dado tarefas-atrasadas|emails-nao-lidos` (fontes `origem=tt`), `--letreiro-lista`,
  `--letreiro-previa-fonte`, `--letreiro-alternar`, `--letreiro-atualizar`. Ganchos de teste (só com
  `TT_LETREIRO_TESTE=1`): `TT_LETREIRO_HOSTS`, `TT_LETREIRO_REMAP`, `TT_LETREIRO_CA`, `TT_LETREIRO_CLIENTES`,
  `TT_LETREIRO_BATERIA`, `TT_AGORA`, `TT_PERFIL`, `TT_BIN`. Teste: `tests/test_letreiro_fontes.sh` (servidor de mentira
  `tests/servidor_falso.py`, nunca a rede real) e `tests/test_letreiro.sh`.

### Atalhos de barra
- `tt --editar-atalhos` — edita os atalhos locais. `--atalhos-barra`/`--atalhos-lista` (internos)
  formatam/listam a partir de `atalhos-padrao` + `~/.config/tt/atalhos` (override por ID; emoji `-`
  desativa). Linha: `emoji⇥id⇥comando⇥cor⇥menu` (cor vazia com menu sai `-` na lista: `read` com IFS=tab junta
  tabs). Padrões: 🚀 `ia-nova` (`ia-conta abrir {conta}`), 👇 `ia-aqui` (`@aqui ia-conta abrir {retomar} {conta}`),
  ⏩ `ia-seguir` (`@seguir ia-conta abrir {prompt}`); no celular, os mesmos dentro de `proot-distro login …`; 🎤 `voz`
  (`@janela voz --conversa`, também `Ctrl+B v` → `tt --clique voz` → `atalho_voz`, que usa o atalho `voz` do perfil).
- `@janela CMD` (`atalho_janela`): `popup_fixo` (display-popup de verdade: um clique fora não fecha) de até 80×16
  encostado na barra à direita (`-x R -y S`), na pasta do painel, com `bash -lc` e `~/.local/bin` + `$DIR_TT` no PATH;
  fecha quando o comando termina.
- Menu do botão direito (5ª coluna, itens separados por ` ;; `): `@contas` (o próprio comando com `{conta}` →
  `--listar-contas` dá `conta⇥provedor⇥rótulo⇥uso`; cada item roda com `--conta NOME`; lista guardada em
  `$RT/tt-atalho-contas-UID-<cksum>`), `@maquinas` (o atalho de mesmo ID roda numa sessão nova da máquina:
  `tt --atalho-sessao ID PASTA` lá, depois `ir_para`), `Rótulo=comando`, `-`. Internos: `tt --atalho-menu-itens ID
  CLIENTE PAINEL` (itens no formato do `menu_popup`), `tt --atalho-rodar ID CLIENTE PAINEL [conta=N|maquina=R|opcao=K]`.
  Sem a 5ª coluna, o botão direito só mostra o comando (`atalho_info`).
- ⏩ / `@seguir CMD` (`seguir_ia`): `agente_no_painel` (claude/codex/kiro-cli entre os descendentes do painel) →
  `conversa_do_painel` (Claude: `claude_info`; Codex/Kiro: `sessoes-ia.py achar`) → nesta máquina `seguir_abrir` respawna
  o painel com `tt --conversa-ia ID --de ORIGEM --salvar` + CMD (`{prompt}` = `--prompt-arquivo
  ~/.cache/tt/seguir/ID-data.md`); noutra, `ssh … tt --seguir-abrir ORIGEM PROVEDOR ID PASTA` abre uma sessão nova lá
  (com o `@seguir` do perfil de lá) e imprime o nome, o painel daqui é respawnado com um recado e a tela vai por `ir_para`.
- `tt --conversa-ia CÓDIGO [--de MÁQUINA] [--salvar]` — a conversa (Claude, Codex ou Kiro) em Markdown, para outra
  IA seguir o trabalho; `--salvar` grava em `~/.cache/tt/conversas/CÓDIGO.md`. Se você recebeu um pedido da ⏩,
  é com isto que se relê a conversa original.

### 🎤 Voz (`voz`, `voz-audio.py`, `voz-windows.ps1`)
- `voz --conversa [--digitar]` (o 🎤): no computador, `exec python3 voz-audio.py conversa` (só biblioteca padrão). Detecta
  fala e fim pelo nível (piso adaptativo, `VOZ_LIMIAR`, `VOZ_PAUSA`, `VOZ_ESPERA_FALA_S`), transcreve (`Transcritor`) e chama
  `voz --turno FRASE` com `VOZ_TELA_FD`: o `falar` do voz escreve `fala|aviso|fim<TAB>texto` nesse fd e a janela mostra e
  fala (`Falador`: Piper, `say`, voz do Windows por `powershell.exe` com o texto em base64, `spd-say`, `espeak`,
  `termux-tts-speak`). No celular com o Tasker ligado: `voz --abrir` + `voz-audio.py espelho` (mostra
  `~/.local/state/tt-voz/conversa.log`; digitar grava em `/sdcard/Tasker/voz/in`).
- Microfone (`candidatos_gravador` → `Mic`, `nota_microfone`): preferência (a tecla n lembra em `~/.cache/tt-voz/microfone`;
  `VOZ_MICROFONE` = `voz --microfone "nome, outro"`) > headset/microfone dedicado (+300) > USB/Bluetooth (+120) > webcam
  (+60) > embutido (−100); monitor e "stereo mix" fora. Linux: as fontes do `pactl list sources` (porta "not available"
  e monitores fora; `node.virtual` = filtro, só com sinal), depois os genéricos (`parecord`/`pw-record`/`arecord` padrão,
  `plughw:C,D` de cada placa, `sox`, `ffmpeg`), que só valem com sinal (`VOZ_SINAL_MIN`). macOS: `system_profiler
  SPAudioDataType -json` + `sox -t coreaudio NOME` (ou `ffmpeg -f avfoundation -i :NOME`). WSL: `voz-windows.ps1`
  (winmm waveIn + MMDevice; DLL compilada uma vez em `%TEMP%`) lista os microfones do Windows com o padrão e grava um
  direto (`gravar N`), sem mudar o padrão (o das chamadas); o `parecord` do WSLg grava só o padrão. O gravador fica aberto
  na conversa (`Fluxo`: thread que guarda os últimos 10 s; `frase()` descarta o que veio antes de ouvir, inclusive a voz
  do tt); o do Windows leva ~1,5–3 s para abrir. `Gravador.proximo()` = tecla n. Nível 0 exato na prova = microfone
  no mudo (`Gravador.mudo`): pulado mesmo sendo headset, listado em `pulados` (a janela avisa); `frase()` com tudo zero
  devolve "mudo".
- Saída de som (`escolher_saida`): VOZ_SAIDA / a escolhida com s (`~/.cache/tt-voz/saida`) > o mesmo aparelho do
  microfone (`nucleo()` tira o tipo: "Headphones (BlackShark…)" e "BlackShark… (Windows)" → "blackshark…"; "MacBook Pro
  Microphone/Speakers" → "macbook pro") > a de melhor nota (a de comunicação do Windows +150) > a padrão. WSL:
  `FalaWindows` = `voz-windows.ps1 falar` num processo só (lista as saídas e "--"; stdin "D n", "F base64", "P"; responde
  "fim"; System.Speech pt-BR → waveOut no aparelho). Linux: `saidas_pulse()` (sem porta "not available") → `paplay
  --device=`. macOS: `say -a ID` (`say -a ?`).
- Opções (`painel_opcoes`: tecla c da janela; `voz --opcoes` = `voz-audio.py opcoes`): 1–3 cérebro (grava
  `cerebro-modelo`; Sonnet = sem arquivo), a–f transcrição (grava `modelo`; automático = sem arquivo; recarrega o
  `Transcritor`), l máquina de transcrição (número + Enter; 0 automática, Esc cancela; grava `transcrever`; troca ao
  voltar à conversa, falha mantém o motor anterior com aviso), n microfone, g sensibilidade (`SENSIBILIDADES`: normal
  350, alta 180, máxima 100, baixa 600; grava `limiar` = `voz --limiar` → `VOZ_LIMIAR`, nome ou número; normal = sem
  arquivo), s saída, v voz (grava `voz`; Piper Faber = sem arquivo; fala um exemplo). `ssh_cmd` leva `VOZ_MODELO=` à
  máquina que transcreve.
- Janela (`Tela`/`Teclado`): `Tela.abrir()` = tela alternativa + mouse SGR (1000/1006), histórico (`itens`, `linhas`
  requebradas no SIGWINCH), `desloc` (0 = acompanha o fim), `rolar(n|"inicio"|"fim")`, estado com "↑ rolada"/"↓ N
  novas · End volta"; sem `abrir()` (teste do microfone) escreve rolando. `Teclado(tela)._consumir` entende a roda
  (`\e[<64/65;…M`), setas, PgUp/PgDn (`\e[5~`/`\e[6~`), Home/End e manda à tela; Esc sozinho espera `TT_ESC_SEQ`.
  `@janela` (tt `atalho_janela`): até 96 colunas, altura `cliente − 6` (até 60). Erro de thread → `_erro_thread` →
  `~/.cache/tt-voz/erros.log`; `_aquecer_piper` engole a falta do Piper. Sem reconhecimento e sem faster-whisper aqui,
  `_oferecer_instalar` (s/n; "n" vale 7 dias em `~/.cache/tt-voz/instalar-recusado`) roda `voz-audio.py instalar` em 2º
  plano (`VOZ_INSTALAR_CMD` nos testes; passo a passo em `~/.cache/tt-voz/instalar.log`) e, pronto, `som_pronto` faz a
  conversa passar a ouvir. `instalar()` sem o `python3-venv`: `venv --without-pip` + `get-pip.py` (`VOZ_GET_PIP`).
- Detector (`Gravador.frase`): fala = 3 quadros de 30 ms acima de max(2,6 × piso, `limiar_minimo()`). Guarda em
  `quase`/`limiar_quase` o maior nível que durou 3 quadros sem virar fala; no silêncio (ou Espaço sem fala) com
  `quase` ≥ 30% do limiar, a janela avisa uma vez por conversa (`_aviso_fraco`) como aumentar a sensibilidade.
- Vozes neurais (`VOZES_NEURAIS`; `VOZ_VOZ` = `voz --voz`): `piper:NOME` (Piper, offline; `~/.local/share/tt-voz/piper`)
  e `edge:NOME` (as da Microsoft pelo `edge-tts`, online; MP3 → WAV pelo PyAV, `mp3_para_wav`). O motor responde
  `{"op":"tts_wav","texto","voz"}` com `{"n":N}` + N bytes de WAV (`Canal.pedir(binario=True)`). `Falador._fonte`: este
  computador, se o venv dele gera a voz (`vozes_de`), senão o canal da máquina que transcreve (`fornecedor`;
  `capacidade()` informa `vozes`). `pedacos()`: a 1ª frase sozinha, as outras até 220 letras; a seguinte é gerada enquanto
  a atual toca. Toca: WSL `FalaWindows.tocar` ("T base64" → waveOut no aparelho); Linux `paplay --device`; macOS
  `afplay`. Sem a voz em lugar nenhum, ou se a 1ª frase falha, vale a do sistema.
- Motor: `voz-audio.py servidor` (no Python com os pacotes; `voz --motor` o acha para outra máquina por ssh): linhas JSON
  `{"op":"stt","n":N,"dica":…}` + N bytes de WAV 16 kHz, `{"op":"tts",…}`, `{"op":"carregar","stt":true}` (responde
  `escolha`); `com_libs_cuda` recomeça o processo com as bibliotecas CUDA do pip no `LD_LIBRARY_PATH`. `Motor` usa
  `escolha_local`; GPU que falha no aquecimento cai na CPU e marca `gpu_falhou` nas medições.
- Escolha: `voz-audio.py medir` (no fim do `voz --instalar-audio`; `voz --medir`; sozinho em segundo plano ao fechar a
  janela se a assinatura mudou) diz as `FRASES_TESTE` com o Piper (+ ruído de microfone a −15 dB), transcreve com cada
  `combinacoes()` (CPU: tiny/base/small; GPU: os que cabem em 70% da VRAM, int8 → int8_float16 → float32) e grava tempo e
  erro por palavra em `~/.local/share/tt-voz/medicoes.json` com a `assinatura` (pacotes, modelos baixados, GPUs).
  `custo = tempo + PESO_ERRO (4) × erro_efetivo` (metade medido, metade o típico do modelo: a voz sintética é fácil).
  `voz --motor-info` = `capacidade()` (JSON: núcleos, carga, GPUs, escolha). A janela (`escolher`) pergunta a todos os
  lugares ao mesmo tempo (ssh com o ControlPath do tt, ConnectTimeout 3; espera no máximo 1,5 s depois da 1ª resposta
  útil); ssh que não conecta (código 255) fica de fora por 10 min (`~/.cache/tt-voz/sondas.json`); estimativa = histórico
  real (`desempenho.json`, média móvel por lugar|modelo|dispositivo) ou medição × carga atual + 0,15 s de rede. Depois de
  duas frases 1,6 vez mais lentas que o previsto para o seguinte, abre o seguinte em paralelo e troca.
- Estado e espera (`voz`): `real_de MAQ SESSÃO` resolve uma ponte (`@ponte`) para a sessão que o cliente dela mostra na
  outra máquina (`voz --cliente-ponte "origem|ponte"` lá, pelo `TT_PONTE` no environ do cliente; senão `@ponte_alvo`);
  ler e mandar texto vão lá. `cerebro_prompt` leva a tela de agora da sessão escolhida (`limpar_tela`: sem `CHROME`;
  `ocupado`, `ha_quanto`), e a regra manda responder estado/contexto pela tela, sem "ler". `ler_agora` não espera
  (trabalhando → `pendente_marcar`); `aguardar` (depois de `enviar`) espera até `VOZ_ESPERA`=15 voltas de 2 s, com
  `descarregar` (fala o que a volta já juntou) antes. A janela confere o `pendente` a cada ~6 s enquanto você não fala
  (`voz --pendente-pronto`: duas telas iguais sem "trabalhando") e fala a resposta (`voz --turno-pendente`).
- Aparelho de origem: `atalho_janela` com comando `voz …` num cliente que é ponte (`origem_ponte`) pede à máquina de
  origem `tt --janela-ponte PONTE CMD MÁQUINA SESSÃO` (`janela_ponte`: o cliente que olha a ponte, `voz --alvo`, e a
  janela lá); falhou, abre aqui com um aviso.
- Cérebro: `cerebro_regras` (fixas) + `cerebro_contexto FRASE` (estado, tela da sessão escolhida, índice, conversa);
  `cerebro_chamar CONTEXTO` usa o Claude aberto da janela (`VOZ_CEREBRO_SOCK`: socket Unix servido por `CerebroVivo` no
  `voz-audio.py`; manda só o contexto) e, sem resposta, `ia-rot -p --model $(cerebro_modelo) --no-session-persistence`
  com regras + contexto. `voz --cerebro-vivo` (a janela o abre ao começar; `VOZ_CEREBRO_VIVO=0` desliga;
  `VOZ_CEREBRO_VIVO_CMD` nos testes) = no 1º lugar do cérebro (aqui, ou `ssh … voz --cerebro-vivo-aqui MODELO`, só se o
  voz de lá o tem), `cerebro_vivo_aqui`: conta de `ia-rot --claude-only --melhor` (principal = sem `CLAUDE_CONFIG_DIR`,
  senão `~/.local/share/claude-contas/CONTA`), `claude -p --input-format stream-json --output-format stream-json
  --verbose --tools "" --no-session-persistence --system-prompt-file ~/.local/state/tt-voz/cerebro-regras.md`. Aquece
  com uma volta, recomeça depois de `VOLTAS` (20) ou de um erro (`is_error`, tempo esgotado); ~1,5 s por volta (contra
  ~7 s). Padrão `sonnet` (medido em 16/10/2026: acerta as frases ambíguas que o Haiku errava por ~1 s a mais);
  `voz --cerebro-modelo haiku|sonnet|opus`. Ações: `panorama` (MÁQUINA opcional), `nova_sessao` com `texto` (o 1º
  pedido, mandado quando o agente abre), `opcao` (número, sim, nao, sempre), `esperar` (`segundos`, `depois`),
  `acompanhar`, `cancelar_espera`, `esperas`, `fixar`, `desafixar`, `fixadas`, `mover_fixada` (`posicao`),
  `agrupar_fixadas`, `tarefa_nova` (texto com marcadores), `subtarefa`, `concluir_tarefa`, `reabrir_tarefa`,
  `apelido_tarefa`, `prazo_tarefa` (`prazo`), `apagar_tarefa`, `notificacoes`, `notificacoes_lidas`,
  `limpar_notificacoes`, `letreiro` (`tecla` ler|pausar|continuar), `fechar_sessao`, `limpeza`. As destrutivas confirmam
  pelas regras (o cérebro não confirma).
- Telas dos agentes (`telas-agentes.py` + o catálogo `telas-agentes.conf`, estendido por `~/.config/tt/telas-agentes.conf`:
  blocos `[id]` com `agente`, `classe` rotina|pasta|decisao|-, `tela` (regex), `opcao`/`evitar`/`tecla`, `motivo`; o mesmo id
  troca o do pacote). `telas-agentes.py decidir --pastas ARQ --maquina M --casa DIR… [--cwd]` lê a tela VISÍVEL (o
  histórico guarda menus já respondidos) e imprime `decisão classe id ação marcada tipo pasta pergunta opções motivo`
  (decisão nada|auto|perguntar; tipo menu|sn|enter|senha; menu = o último com cursor ❯ › ▶, numerado ou não; lista do
  agente sem cursor não vale). Ordem: senha na última linha (trava do código) → todos os `decisao` → rotina/pasta na ordem;
  a opção escolhida sozinha nunca casa `NUNCA` (não pergunte de novo, sempre, todas, acesso total, apagar…); `tecla` só
  em tela que pede só Enter. `pasta` = sozinho só se a pasta (da tela, ou a do painel) está em `~/.config/tt-voz/pastas`
  (`[MÁQUINA:]PASTA`, `/**` = subpastas, `*`, `..` barrado; `casas_de M` traz o `$HOME` de lá e a `/root` do proot).
  `validar`, `catalogo`, `pasta-ok`. No `voz`: `tela_tratar MAQ SESSÃO TELA abertura|trabalho [PASTA] auto|voz|perguntar`
  (0 nada, 1 perguntou, 2 respondeu; `voz` = sozinho só se `@tt_voz`=1, a opção de sessão que o 🚀/👇/⏩ pela voz gravam);
  `destravar` (abertura) e `resposta_ou_pergunta` (depois de `aguardar`, `ler_agora`, pendente, agenda) o usam; a pergunta
  fica em `pergunta` (`opcao|sn|enter:MAQ:SESSÃO`) + `pergunta.info` (classe, id, pasta, origem) e `responder_pergunta`
  (número, sim, nao, sempre, enter) responde e segue (`destravar` e o 1º pedido guardado em `pedido-SESSÃO`, ou
  `aguardar`); senha: a voz manda digitar no terminal. Registro: `~/.local/state/tt-voz/aprovacoes.log` (sozinha|você).
  `voz --pastas [add|rm [MÁQUINA:]PASTA]`. Teste: `tests/test_telas_agentes.sh`.
- Confirmação (`confirmar_pedir ETAPAS P1 P2 AÇÃO ARGS…`, só ações de `CONFIRMAVEIS`): grava `confirmar`, `pergunta` =
  confirmar; "sim" (`confirmar sim`) faz, com ETAPAS=2 pergunta P2 antes; "não" desiste (5 min de validade).
- Agenda e acompanhamento (o que a voz fala sozinha): `esperar SEG ler|resumir|avisar [NOME]` grava `agenda` (`quando
  depois máquina sessão N canal`); `duracao_de` lê "um minuto e meio", "30 segundos", "vinte e cinco minutos"; até 6 h;
  vencida há mais de `VOZ_AGENDA_VALIDADE` (900 s) cai calada. `acompanhar [NOME]` grava `acompanhar` (até
  `VOZ_ACOMPANHAR_MAX`=7200 s; tira o `pendente` da mesma sessão) e `acompanhar_estado` diz sumiu/trabalhando/pergunta/
  pergunta-dita/terminou (mexeu e parada em duas olhadas)/parada. `voz --fundo-pronto` (0 = há o que falar: agenda
  vencida, acompanhada com novidade, pendente pronto) e `voz --turno-fundo` (fala, cada um pelo `CANAL` do pedido); a
  janela confere a cada ~6 s ouvindo e digitando; o daemon do celular a cada `VOZ_T_FUNDO` (6 s), inclusive
  quando só o modo retorno está ativo. A condição do daemon precisa incluir `retorno`: sem isso, callbacks
  e prazos ficavam parados até surgir outra espera. `tests/test_voz_daemon_retorno.sh` cobre retorno e prazo
  pelos canais Tasker e Telegram, com transportes falsos e sem fala duplicada. `esperas`,
  `cancelar_espera` (agenda, acompanhamentos, pendente e o modo retorno), `voz --esperas`.
- Modo retorno (`modo_retorno [SEG]`, frases "modo retorno (por N)", "me chama quando elas terminarem", "pode ir que eu
  espero"; `retorno_sair`, `retorno_auto sim|nao` = `~/.config/tt-voz/retorno-auto`; CLI `voz --retorno [SEG|sair|auto X]`;
  cérebro `retorno` (`segundos`), `sair_retorno`, `retorno_auto` (`tecla`)). Estado em `~/.local/state/tt-voz`: `retorno`
  (`início prazo último-contato canal`), `chamadas` (uma por sessão: `máquina sessão pedido-em retornou-em
  assinatura-no-pedido assinatura-da-última-olhada pergunta-dita foto pedido`; em aberto = pedido > retornou; a foto é a
  tela de antes do pedido, em `fotos/`), `retorno.fila` (`tipo máquina sessão arquivo`) e `eventos.visto-MÁQUINA`.
  `enviar` grava a chamada antes de mandar e, no modo, não chama `aguardar`; `resposta_ou_pergunta` e o acompanhar marcam
  `chamada_retornou` (sem fala dupla); `responder_pergunta` no modo reabre a chamada. `retorno_novidade` (dentro do
  `fundo_pronto`): os eventos de cada máquina das chamadas (uma ida: `awk` desde o `eventos.visto`), a conferência de
  reserva a cada `VOZ_RETORNO_POLL` (10 s; `telas_lote`: as telas visíveis das sessões em aberto de uma máquina numa ida;
  terminou = parada, igual em duas olhadas e diferente da do pedido; decisão pelo `tela_decidir`; sumiu) e o prazo.
  `turno_retorno` (dentro do `turno_fundo`): respostas (a mensagem do evento pelo `resumo`, senão a tela), sessões que
  fecharam, o resumo do prazo (`retorno_resumo_prazo`: o cérebro com o pedido e o `retorno_delta` = o que apareceu depois
  da foto; sem cérebro, o estado) e a pergunta por último (uma por vez); sem nada em aberto, sai do modo. `voz
  --retorno-pronto` = 1ª linha `retorno_status` + saída do `fundo_pronto`. Janela: `aguardar_retorno` (microfone fechado
  com `Gravador.pausar`, confere a cada `VOZ_T_RETORNO` = 3 s; Espaço/t/r/Esc), `Falador.plim` (som curto; `VOZ_PLIM=0`
  desliga), `retomar` reabre o mesmo microfone enquanto a voz fala e a sua vez (`sua_vez`) em silêncio volta a esperar.
- Ganchos dos agentes (as sessões da voz): `ia-conta` (`voz_eventos`: `TT_VOZ_EVENTOS=1`, que o 🚀 passa, ou `@tt_voz`=1 da
  sessão do `$TMUX_PANE`, que o 👇/⏩ gravam antes de abrir) passa ao Claude `--settings` com `Stop` → `voz --evento
  terminou claude` e `Notification` → `voz --evento pergunta claude`, e ao Codex `-c notify=[voz,--evento,terminou,codex]`;
  nada no `settings.json`/`config.toml` do usuário. `voz --evento TIPO AGENTE [JSON]` (`evento_gravar`) roda na máquina da
  sessão, não imprime nada, ignora sessão sem `@tt_voz` e o `idle_prompt`/`auth_success`, guarda a última mensagem
  (`last_assistant_message` do stdin do Claude, `last-assistant-message` do argumento do Codex) em `eventos.d/ID.txt` e
  acrescenta `ID sessão tipo agente arquivo` em `eventos` (ID = `EPOCHREALTIME`; poda em 300 linhas). O monitor-silence do
  tmux não serve: avisa o 1º silêncio e só rearma quando alguém olha a janela.
- Interface do tt pela voz: fixadas (`fixar_voz fixar|desafixar`, `fixadas_ler`, `mover_fixada_voz NOME
  inicio|fim|esquerda|direita|N` = `tt --mover-fixada`, `tt --fixadas-agrupar`); tarefas (`tarefa_nova` com `frase_natural`:
  "para amanhã às 14 horas" → `@amanha 14h`, "urgente" → `!alta`; `subtarefa_nova`, `tarefa_fazer
  concluir|reabrir|apelido|apagar` (apagar confirma), `tarefa_prazo` = `--tarefa-frase` sem o @prazo + o novo →
  `--tarefa-editar`; `tarefa_achar NOME [sub]`); notificações (`tt --notifs-listar`, `--notifs-lidas`,
  `--notifs-limpar-lidas` com confirmação); letreiro (`tt --letreiro-ler`, `tt --letreiro-pausa sim|nao`). Texto com
  acento vem da frase original (`cru_sufixo`, `cru_trecho`).
- Controles da etapa 2: `controle_interface_voz` chama o tt na máquina escolhida com argumentos literais.
  Os controles exigem destino cadastrado (`EM_EXIGIR_DESTINO`): máquina removida não vira ação local.
  `barra_fixadas` (`tecla=mostrar|esconder|estado`), `nao_perturbe` (`tecla=ligar|desligar|estado`, `segundos` opcional),
  `mensagem_letreiro` (`texto`), `renomear_sessao` (`sessao` opcional, `texto` novo), `email` (`abrir|contas|estado`),
  `transferencias` (`abrir|ler`), `calendario` (`abrir|ler`) e `trocar_conta` (`ia` = conta) são ações do cérebro e das regras.
  Reescreva antes de tirar verbos como “mostre”: nesse caso ele significa tornar a faixa visível.
  `--fixadas-faixa` persiste `fixadas_faixa=0|1`, ajusta status para 2–4 linhas e mantém os cadastros. Com a faixa
  de notificações desligada, os chips de tarefas/versão passam para a linha das janelas quando as fixadas estão ocultas.
  `--nao-perturbe` usa estado local em `nao-perturbe` (on ou epoch de término, até 86400 s); a expiração é conferida
  com relógio do Bash. Silencia `notificar_aparelho`, incluindo sobreposição de terminal; histórico e sino permanecem.
  `--letreiro-mensagem` cria/edita a fonte local `voz-mensagem` (lista), substitui seu item e atualiza só essa fonte.
  A CLI `--renomear S N` usa o mesmo `renomear` manual; a voz acompanha a mudança no alvo, permissões, pendente,
  chamadas, agenda, acompanhamentos e fila de retorno. `--interface-abrir TIPO CLIENTE` reutiliza e-mail/calendário/popup
  de transferências; a voz escolhe um cliente anexado à sessão, sem cair no terminal de outra sessão.
  `trocar_conta_voz` valida a conta e guarda servidor/sessão/painel; confirma pelo mecanismo existente (fila do plano
  para ações do cérebro), revalida a identidade e a conta, e chama o atalho `ia-aqui` via `trocar_ia`.
  Testes: `tests/test_interface_controles.sh` e `tests/test_voz_interface.sh`.
- Fechar e limpeza: `fechar_sessao [NOME]` confirma (2 vezes se é a escolhida ou está trabalhando; sessão `_*` nunca) e
  `fechar_uma` usa `tt --fechar . SESSÃO` lá (solta a fixada). `limpeza [MÁQUINA]`: `tt --listar-tudo --tsv` de todas ao
  mesmo tempo → `LIMPEZA_AWK` (manter: escolhida, acompanhada, anexada, fixada, papel ≠ atalho, rascunho, ocioso < 120 s,
  agente com a última linha em "?", outro programa; fechar: shell parado ≥ `VOZ_LIMPEZA_SHELL` 3600 s, agente parado ≥
  `VOZ_LIMPEZA_AGENTE` 14400 s, com o motivo) → `limpeza.analise` e `limpeza` (até `VOZ_LIMPEZA_MAX` 8, as mais paradas);
  `pergunta` = limpeza: "fechar" (`limpeza_fechar`, que pula a que voltou a ser usada há < `VOZ_LIMPEZA_RECENTE` s),
  "tira a N" (`limpeza_tirar`), "cancelar". Teste: `tests/test_voz_acoes.sh`.
- Liberação: escolher (lista, número, nome, cérebro, sessão nova, próxima/anterior) grava em `permitidas` (`liberar`);
  `enviar`, Enter/cancelar, 👇 e ⏩ só pedem a sessão escolhida; "bloquear sessão" tira da lista e solta a escolha.
- Índice (`indice_local [N]` = `voz --indice-local`: uma ida ao tmux, sem ocultas nem pontes; agente e título do
  `tt --listar-tudo --para-ia`; estado por `ocupado`/`ha_quanto`; N linhas limpas, sem a caixa de digitar ❯/›/> com
  espaço comum ou não separável); `indice_todas [N] [MÁQUINA]` (todas ao mesmo tempo; lá só se o voz de lá tem o
  verbo; `VOZ_T_INDICE`=8 s); `voz --indice-atualizar` grava `~/.local/state/tt-voz/indice` (a janela, a cada
  `VOZ_T_INDICE_JANELA`=30 s); `indice_lista` (até 60 s, senão refaz) alimenta `sessao_em_todas` (escolher pelo nome
  ou título em qualquer máquina) e o contexto do cérebro. `panorama` = `indice_todas 20` → `cerebro_chamar "PANORAMA…"`
  (uma frase por sessão); sem o cérebro, o estado de cada uma.
- Regras (`reescrever`): `RE_NOVA`/`RE_NOVA_VERBO` ("abra uma nova sessão em M com X" → `nova sessao …`; "abrir a sessão
  X" sem nova/uma e sem em/no/na/com é escolher); "máquina + sessões" só em frase de até 6 palavras sem
  `RE_PEDIDO`; `RE_PANORAMA`/`RE_PANORAMA2`; "ir para a sessão X" = `sessao X`; "ir para X" que não é máquina procura
  a sessão. `em` aceita `EM_TEMPO`; o ssh do voz usa o ControlPath do tt (`~/.cache/tt-ssh-%r@%h`, 12 h).
- Configuração em `~/.config/tt-voz/`: `cerebro` (`-` = desligado; sem o arquivo, a janela usa `local` se houver
  `ia-rot`), `cerebro-modelo`, `transcrever`, `fala`, `modelo`, `microfone`, `permitidas`. `voz --instalar-audio` = venv
  `~/.local/share/tt-voz/venv` (faster-whisper, piper-tts; com GPU NVIDIA, `nvidia-cublas-cu12` e `nvidia-cudnn-cu12`,
  ~2 GB) + voz `pt_BR-faber-medium` + os modelos small e base + `medir`. `voz --audio` mostra microfones, medições, GPU e
  o ranking dos lugares; `voz --audio-teste` grava, transcreve e repete.
- Testes: `tests/test_voz.sh` (regras, cérebro, ações, daemon do celular), `tests/test_voz_acoes.sh` (esperar,
  acompanhar, pergunta no meio do trabalho, fixadas, tarefas, notificações, letreiro, fechar, limpeza),
  `tests/test_voz_retorno.sh` (ganchos, modo retorno, prazo, reserva, decisão, frases, janela),
  `tests/test_telas_agentes.sh` (o catálogo e a trava) e `tests/test_voz_tela.sh` (canal da janela,
  sistemas com `VOZ_SISTEMA=Darwin|WSL|Linux`, microfones com `pactl`/PowerShell falsos, medições e escolha com ssh
  falso e `VOZ_MOTOR_FALSO`, gravação, janela num tmux isolado, `@janela`, instalação).

### 🎤 Voz 2.1: autonomia, planos de um ok, temas, conversas antigas e sessões que conversam
- **Regras do cérebro** (`cerebro_regras`): bloco AUTONOMIA (o que o usuário não disse, o cérebro decide e conta em UMA frase; só pergunta se errar sai
  caro; nunca "posso fazer?") e PLANO (todas as ações em ordem no mesmo turno; nunca confirmar por fala). Ações novas: `temas`, `juntar_sessoes`
  (`origem` = lista), `achar_conversa` (`consulta`), `retomar_conversa` (`numero`, `maquina`, `texto`), `falar_com_sessao` (`origem` = `máquina:sessão`,
  `maquina`+`sessao` = destino, `texto`, `rodadas`), `plano_tirar` (`nome`). `CEREBRO_PY` achata cada ação em colunas fixas (as 3 últimas: origem,
  rodadas, consulta).
- **Plano de um ok:** durante o laço do `cerebro()`, `PLANO_LOTE=1`; `fechar_sessao`, `tarefa_fazer apagar`, `notificacoes_limpar` e `juntar_sessoes`
  chamam `lote_add DESCRIÇÃO AÇÃO ARGS…` (arquivo `$ST/lote`, campos 0x1F) em vez de `confirmar_pedir`. No fim do turno, `plano_perguntar` faz UMA
  pergunta e grava `pergunta`=plano; `plano_resposta sim|nao|tirar X` (rotas `plano sim|nao|tirar` em `reescrever`/`comando`) executa só ações de
  `PLANO_ACOES` (`fechar_sessao_ja tarefa_apagar_ja notifs_limpar_ja unir_ja`), em ordem. Fila sem aprovação em 5 min é descartada no próximo turno.
  `simples()` manda ao cérebro a frase com conjunção + outro verbo de ação (`COMPOSTO_RE`).
- **Juntar:** `unir_ja` = `tmux move-window -a -d -s =origem:N -t =destino:{end}` por aba; a origem some sozinha; a fixada órfã é desafixada.
- **Temas:** `temas_analisar` pede ao cérebro `grupos` (nome → `máquina:sessão`), guarda em `$ST/temas` (30 min) e o contexto traz "temas da última análise".
- **Conversas antigas:** `busca-tt.py conversas-indexar [--dias 120] [--orcamento 60]` (todas as conversas em disco: `todas(".claude"|".codex"|".kiro")` do
  `sessoes-ia.py`, inclusive proot; extração em processo com `exportar_*`; chave `hist:PROV:ID`, tabela `hist`, fonte `historico`, fora das consultas por
  sessão; só o que mudou; esquece o que saiu do disco) e `conversas-consultar TEXTO [N]` (`pontuação, provedor, código, quando, pasta, título, trecho`).
  O vigia roda após o `indexar` normal (`busca_indexar`). `tt --busca-conversas`. Voz: `conversa_achar` (todas as máquinas em paralelo, guarda
  `$ST/conversas`) e `conversa_retomar` (`ia-conta retomar` onde a conversa mora; noutra máquina, `tt --conversa-ia ID --de M --salvar` + `ia-conta abrir
  --prompt-arquivo`). Env: `TT_BUSCA_DIAS`, `TT_BUSCA_ORCAMENTO`, `TT_BUSCA_MAX_CONVERSA_MB`.
- **Sessões que conversam:** `conversa_entre ORIGEM_M ORIGEM_S DEST_M DEST_S TEXTO [RODADAS]` (`voz --sessao-falar`, `tt --sessao-falar`): `mandar_para` digita com o
  prefixo "[Mensagem da sessão 'X' (M)]", `esperar_resposta_longa` (`VOZ_CONVERSA_ESPERA`=60 s), `extrair` a resposta e a entrega à origem; sem origem, a voz
  lê a resposta. Teste: `tests/test_voz_plano.sh`; avaliação manual com o modelo de verdade (sem executar nada): `tests/avaliar_cerebro.sh`.

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
  Anexos seguem a MÁQUINA DA TELA (a de onde se está; ponte = `TT_PONTE`, popup do e-mail aberto de uma ponte = `TT_ORIGEM`;
  `dest_da_tela`, a mesma regra dos links): `--abrir-anexo ARQ` (opener de `application/*`, `text/*`, `audio/*`, `video/*`;
  `--abrir-imagem` passa por ele) manda o arquivo por ssh para `--abrir-recebido NOME` de lá (guarda em
  `~/.cache/tt-anexos/abertos` e abre no programa padrão, `abrir_arquivo_local`); sem resposta, abre aqui. A tecla `S`
  do aerc salva o anexo escolhido em `~/.cache/tt-anexos/salvar` e chama `--anexo-salvar`: pela ponte, vai para a pasta
  de recebidos da máquina da tela (`transferir`); aqui, pergunta a pasta (sem sobrescrever: "nome (2)"). No `E`, o
  seletor de máquina começa pela da tela (`escolher_maquina TÍTULO [exceto] [preferida]`). Teste
  `tests/test_anexos_maquina_da_tela.sh`.
  `--email-adicionar provedor=gmail auth=oauth` sem client_id usa o app OAuth embutido do tt (EMAIL_GMAIL_ID; segredo montado em partes, gravado por conta em ~/.secrets). `--email-sync-local CONTA 0|1` (liga/desliga o espelho mbsync pós-cadastro; botão 🔄 em F2).
  Pendências de instalação: ver a seção "Pendências de instalação" abaixo (`--pendencias`, `--pedir-sudo`).

### Pendências de instalação (📦)
Catálogo único do que o tt pode precisar, por máquina. A camada de plataforma vive em `pacotes-tt.sh` (também
usada pelo `instalar.sh`; só funções `pk_*`, carregada sob demanda por `pacotes_lib`); o catálogo, o modal
e os instaladores da pasta do usuário ficam no `tt`.
- `tt --pendencias [--tsv]` — estado de TODOS os itens (✓ ok · ✗ falta · ! manual · – não se aplica) com a
  plataforma (`pk_resumo`: "Ubuntu 24.04 · WSL · x86_64 · apt-get · sudo"); `--tsv` = `id estado nível rótulo detalhe`.
- `tt --pedir-sudo [--sim] [id…]` — o modal (`pedir_sudo_pendencias`): lista as pendências, mostra o comando
  exato e oferece [i] instalar [s] selecionar [m] mais tarde (1 dia) [n] nunca. Com ids, ignora recusas e
  níveis; `--sim` aceita tudo sem terminal. `TT_PEND_TODAS=1` (menu administrar → 📦) inclui opcionais e recusadas.
  `--pendencias-avisar` (vigia, a cada 6 h): UM aviso de essencial/recurso (dura 6 h, repete após 12 h).
- `sudo-sem-senha` (recurso; só enquanto `sudo -n true` falha; fora do Termux e do root): passo de administrador que não é
  pacote (`P_ADM=1`, `P_ADM_CMD` = o texto que o modal mostra em "Configuração do sistema"); `pend_instalar` roda
  `sudo_sem_senha_ativar`: regra `USUÁRIO ALL=(ALL) NOPASSWD: ALL` em `$(sudoers_arquivo)` (`/etc/sudoers.d/tt-sem-senha-USUÁRIO`,
  sem ponto no nome), conferida por `sudo visudo -cf`, gravada por `sudo install -m 0440 -o root -g root`. Testes:
  `TT_SUDO_BIN`, `TT_SUDOERS_DIR`; o `tests/lib.sh` esconde o item (`TT_PEND_SEM_SUDO_SEM_SENHA=1`); `tests/test_sudo_sem_senha.sh`.
- Itens (`PEND_IDS`): `nucleo` `fzf-novo` `tmux-antigo` (manual) `email-aerc` `email-sync` `isync-sasl` `email-xoauth2` `email-espelho`
  `email-html` `email-editor` `email-spell` `chrome` `carbonyl` `chrome-libs` `clipboard` `notificacoes` `xdg-utils`
  `termux-api` `pv` `mosh` `nomeador-local`. `pend_avaliar ID` preenche `P_APLICA P_NIVEL P_SYS P_USR P_MANUAL
  P_ROTULO P_MOTIVO P_TAM` (P_SYS = o que o gerenciador instala; P_USR=1 = há passo sem administrador). Nível:
  essencial · recurso · opcional (o vigia ignora opcional e manual).
- Plataforma (`pacotes-tt.sh`): `pk_so` `pk_arch` `pk_ambiente` (termux|proot|wsl|nativo) `pk_libc`
  `pk_gerenciador` (apt-get dnf yum zypper pacman apk xbps brew pkg pkg-bsd pkg_add pkgin; a família da
  distro decide quando há vários) `pk_privilegio` (nenhum|sudo|doas|su|indisponivel). Nomes de pacote:
  tabela `PK_TABELA` (lógico → nome por gerenciador; conferida em repositórios reais) e `PK_TABELA_LIBS`
  (sonames do Chrome/Carbonyl); `pend_resolver GER item…` → `PK_PACOTES`/`PK_SEM_PACOTE`; apt escolhe `…t64`.
- Instalação robusta: `pk_instalar GER PRIV pacote…` = um lote; se falhar, atualiza o índice e repete; depois
  um a um (nome inexistente não derruba os outros); `PK_OK`/`PK_FALHOS`/`PK_MOTIVO` (permissao|rede|
  indice_ou_nome); senha errada para na hora; `pk_baixar URL DEST [sha] [MB]` (tentativas, espaço, sha256,
  atômico). `pend_instalar` confere ✓/✗ no fim e adia 7 dias o que falhou; log em `~/.cache/tt/pendencias.log`;
  trava `$ESTADO_DIR/pendencias.trava`.
- Passos da pasta do usuário: `navegador_instalar` (Chrome: `.deb` extraído com python3; Carbonyl: zip),
  `xoauth2_construir` (`~/.local/share/tt-sasl2`), `isync_sasl_construir` (`~/.local/share/tt-isync`; `mbsync_bin`
  prefere esse), `fzf_instalar` (`~/.local/share/tt-bin`, na frente do PATH do tt), `email_vim_spell_garantir`.
- Ganchos de teste: `TT_GERENCIADOR TT_PRIV TT_SO TT_ARCH TT_AMBIENTE TT_LIBC TT_OS_RELEASE TT_PK_LOG`,
  `TT_FINGE_FALTA` / `TT_FINGE_FALTA_ARQ` (comandos tratados como ausentes; o arquivo é esvaziado por um
  gerenciador de mentira), `TT_FINGE_CHROME_LIBS[_ARQ]`, `TT_FINGE_FZF_VERSAO`, `TT_FINGE_TMUX_VERSAO`,
  `TT_PEND_SEM_NAVEGADORES` (esconde Chrome/Carbonyl do catálogo; o `tests/lib.sh` o define),
  `TT_FZF_URL/SHA256`, `TT_ISYNC_URL/SHA256`, `TT_XOAUTH2_URL/SHA256`, `TT_CARBONYL_URL/SHA256`, `TT_CHROME_INDICE/BASE`.
- `email-espelho` (PEND_SEMPRE, sem "nunca": recusa vira "mais tarde", volta em 1 dia): conta IMAP sem `sync_local=1`;
  aceitar roda `email_espelho_ligar` (SASL/XOAUTH2 se OAuth + `email_sync_local_definir CONTA 1`). Aviso de e-mail novo,
  contador do 📧 e demandas `[tt]` só leem o espelho.
- Erros do sync de e-mail que uma pendência resolve (`email_erro_dica`): "built without LibSASL" →
  `isync-sasl email-xoauth2`; "SASL mechanism(s) not available" → `email-xoauth2`.

### E-mail (aerc)
- `tt --email [cliente]` — abre o cliente de e-mail (default `aerc`) numa subjanela popup.
- `tt --email-contas` / `tt --email-conta` — gerenciador de contas (a tela é `tt --email-contas-ui`; o
  cadastro guiado, `tt --email-conta-nova-ui`); `tt --email-adicionar chave=valor… [--senha-stdin]` cadastra por
  CLI (chaves em `EMAIL_CHAVES`; `provedor=gmail|microsoft|yahoo|icloud|fastmail|zoho|proton|outro`,
  `auth=senha|comando|oauth`); `tt --email-listar` (TSV: slug, nome, endereço, provedor, auth, IMAP).
- **Enviar sem tela:** `tt --email-enviar` (seção "Enviar e-mail pela linha de comando" abaixo). O aerc
  envia pelo `outgoing` de cada conta: `smtps|smtp[+xoauth2]://…` (SMTP) ou, nas contas Graph,
  `email-tt.py graph-sendmail CONF DEST…` (API REST do Outlook; mesmo conversor do `--email-enviar`).
- **Microsoft pelo Graph** (`provedor=microsoft auth=oauth graph=1`, padrão do cadastro Microsoft): o
  app OAuth padrão é o do Outlook Mobile (`EMAIL_OUTLOOK_MOBILE_ID`; apelidos em
  `oauth_client_id=`: `outlook` = esse, `thunderbird` = `EMAIL_THUNDERBIRD_ID` (IMAP/SMTP), `tt` = `EMAIL_MICROSOFT_ID`), escopo `offline_access https://graph.microsoft.com/.default`. Leitura: `email-tt.py
  graph-sync CONF BASE` espelha no maildir (por isso conta Graph tem `sync_local=1`; `tt --email-graph-migrar`
  liga isso nas antigas); `classificar=1` organiza o INBOX no servidor (`graph-classificar`, precisa de
  Mail.ReadWrite). Envio: API REST do Outlook (`/api/v2.0/me/sendmail`, token do recurso
  `outlook.office.com`), porque o Mail.Send desse app existe no recurso do Outlook e não no do Graph.
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
  ao fim de cada sync completo ou em 2º plano se > 1 h; refazer na hora: `tt --email-contatos-indexar`); `tt --email-anexos-escolher ARQ` (fzf multi
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
  usar) → `:check-mail` ainda na lista → `:select 0` → `:search -u` → `:view` em qualquer largura;
  popups duplicados são bloqueados enquanto um já está aberto; sem sessão oculta, o salto espera o aerc
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
  e modo (estado em `$ESTADO_DIR/email-sync/<slug>`, erro em `<slug>.erro`, o da última volta completa ruim em `<slug>.erro-completo`; `curto` = ok|nunca|atrasado|
  erro|parado por conta, para a barra — `email_sync_resumo`); `tt --email-mbsync-migrar` — regrava
  .mbsyncrc antigos (canal único, ou em canais sem `Timeout 60`) no formato de canais `<slug>-inbox`/`-pastas`/`-arquivo` + `Group <slug>` (a instalação
  chama). Pastas especiais `pasta_importantes`/`pasta_estrela` (marcas `\Important`/`\Flagged`)
  saem do espelho; `pasta_todos` vira o canal de arquivo com `MaxMessages`/`ExpireUnread`. Vigia:
  INBOX a cada `TT_EMAIL_SYNC` (120; `TT_EMAIL_SYNC_OCIOSO`=300 sem cliente tmux ativo há 10 min,
  gravado em `email-sync/.intervalo`), completo a cada `TT_EMAIL_SYNC_COMPLETO` (1800; ao iniciar só
  se `email_ultima_completa` já passou do prazo), teto `TT_EMAIL_SYNC_TETO` (600; INBOX 240). O vigia
  chama com `--vigia`, que respeita `<slug>.espera` (após erro: 2×, 4×… o intervalo, até 900 s;
  `<slug>.falhas` conta; sucesso zera); trava ocupada registra `pulada`. Depois de cada rodada `email_novos_avisar` (ids novos e não lidos em
  INBOX/new+cur vs. `email-sync/<slug>.vistas`; `email-tt.py cabecalhos ARQ…` dá "chave<TAB>remetente<TAB>assunto"
  decodificados, chave = 12 hex do sha1 do Message-ID; o aviso do 🔔 é de lote `email-<slug>#chave,…` e leva só as que a rede
  não avisou, a notificação do sistema leva todas; `email_aviso=0` desliga) e `atualizar_barras`; `barra_email_fmt` (`tt --barra-email`)
  preenche `@barra_email` (não lidas do espelho; ⚠ vermelho se `--email-sync-estado curto` tem
  erro/parado, ⏳ âmbar se só atrasado), referenciada pelo range `email` do tema.
- Filtros do leitor (`aerc_filtros_basicos`, `aerc_filtro_texto`): a seção `[filters]` do `aerc.conf` SUBSTITUI a lista de fábrica do aerc; só com `text/html` o corpo
  `text/plain` aparecia como anexo ("No filter configured for this mimetype"). `configurar_aerc` e `aerc_reparar_se_preciso` (ao abrir o 📧) acrescentam, só se
  faltarem, `text/plain=wrap -w 100 | colorize | python3 email-tt.py linkify`, `text/calendar=calendar`, `message/delivery-status|rfc822=colorize` e `.headers=colorize`
  (filtro do dono fica). Teste: `tests/test_aerc_texto_plano.sh`.
- `tt --email-atalhos` — tela de atalhos do aerc em português (um ícone por assunto: `EMAIL_ATALHOS_ICONES`).
- `tt --email-esc` (Esc na lista da sessão oculta: limpa filtro/busca — "| filter"/"| search" na linha de status do
  aerc — ou desanexa o popup), `tt --email-naolidas` (botão ✉: `:filter -u` ↔ `:clear`), `tt --email-lixeira
  [CONTA…|--todas] [--sim]` (🧹: `email-tt.py lixeira CONF [--esvaziar]` conta/apaga de vez a pasta \Trash pelo IMAP;
  pergunta antes; sem terminal e sem --sim só mostra) e `tt --email-lixeira-ui` (a tela do botão 🧹 e do menu do 📧).
- `tt --email-tudo` (botão ☑ e `Ctrl+a` na lista: `:mark -a` ↔ `:unmark -a` pelo IPC; estado em `@tt_email_tudo` da sessão
  oculta). `tt --email-lote [CONTA] [--pasta P] [--busca B] [--acao apagar|mover|arquivar|lidas|nao-lidas] [--destino D]
  [--de-vez] [--sim] [--tela]` (botão ⚡, menu do 📧): `email-tt.py lote-contar CONF PASTA BUSCA --salvar ARQ` (SEARCH; termos
  `todas nao-lidas lidas com-estrela de: para: cc: assunto: texto: antes: desde: maior: menor: gmail:`; grava UIDVALIDITY e os
  UIDs) → `lote-agir CONF ARQ AÇÃO` (só os UIDs contados, blocos de 500, `progresso=` no stderr; MOVE ou COPY+STORE+UID
  EXPUNGE; apagar = \Trash, de vez na lixeira/spam ou com `--de-vez` fora do Gmail; arquivar = tirar da pasta no Gmail,
  \Archive nos outros; UIDVALIDITY mudada recusa). Sem terminal exige `--sim`; de vez ou ≥ 1000 confirma digitando o número.
- Apagar em toda conta: `email_contas_lixeira` (nome␟lixeira␟spam␟todos␟gmail) → `email_binds_contas_gerar`: com lixeira,
  d/D/✕ movem para ela (a = `:delete` só no Gmail); na lixeira/spam apagam de vez; sem lixeira (fora do Gmail), d pergunta
  "Apagar de vez (esta conta não tem lixeira)". `tt --email-conferir [CONTA…] [--corrigir]` (`email_cmds_estado`: lixeira
  conhecida, pasta dela no espelho, seção da conta nos binds; `email_cmds_corrigir`: `email_detectar_pastas`, cria a pasta da
  lixeira no maildir, `email_regerar` e `email_sync CONTA lixeira`, só o canal dela); o `tt --checar` tem `email-cmd:CONTA`.
  Autoconserto: `email_mbsyncrc_migrar` (instalação) regrava rc sem a marca `# tt-mbsyncrc 2` e conserta os comandos; o
  `email_sync` completo bom confere e conserta de novo. Testes: `tests/test_email_lote.sh`, `tests/test_email_espelho_grande.sh`.
- Caixa grande: o canal `<slug>-inbox` tem `MaxMessages EMAIL_INBOX_MAX` (5000, `TT_EMAIL_INBOX_MAX`) + `ExpireUnread yes` (só
  poda o espelho); `<slug>-lixeira` (pasta_lixeira) é canal próprio, fora do `Patterns` das pastas e primeiro no `Group`.
  Erro `OVERQUOTA`/`bandwidth limits` do Gmail: `<slug>.espera` de `TT_EMAIL_ESPERA_COTA` (7200 s) e dica no `--email-sync-estado`.
- Demandas sem nenhum remetente autorizado: `demandas_processar_conta` roda sempre (não depende de `demandas_ativas`); e-mail
  `[tt]` de quem não está autorizado vai para `<conta>.demandas.espera` e avisa ("aguardando sua autorização"). O `tt --checar`
  tem a linha `demandas` (sem conta espelhada, à espera, ignorado por autenticação nos últimos 7 dias, ou pronta com N
  autorizados e M na Entrada). O agente de checagem nunca autoriza remetente.
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
  marca a sessão (`@tt_email_binds` = versão:soma do binds.conf:`email_pastas_soma`); binds antigos ou pasta nova
  no espelho recriam a sessão, mas pasta nova não derruba sessão anexada (fica para a próxima abertura). A linha de status do
  aerc fica só com `{{.TrayInfo}}` (dicas antigas do tt migradas). Duplo clique no painel da sessão
  `_tt-email` = Enter (abre), via `if -F` no `DoubleClick1Pane` do tmux.conf.
  `configurar_aerc` também põe ícones (`icon-*`), `tab-title-account` com não lidas, datas numéricas,
  `message-list-split horizontal 14` + `auto-mark-read-split` (cópias em ~/.cache: tela < 100 sem split e sem sidebar, modo estreito; ≥ 180 `vertical 70`, modo amplo).

### Nomeador de abas
- `tt --nomeador [auto|local|claude|nenhum]` — define a fonte do nome automático.
- `tt --nomeador-local [estado|instalar|remover]` — modelo local llama.cpp.
- `tt --nomear-texto` (interno, lê stdin), `--nomeador-ui`, `--sugerir`, `--renomear`,
  `--nomear-todas[-local]`.

### Snapshots do estado (`snapshots-tt.py`)
- Ativável: `snapshots=1` (`tt --snapshots on|off|status`; sem argumento abre a tela, também `Ctrl+B S` — rota `snapshots` do `clique()` — e menu administrar → 📸; na tela, ⏎ liga quando desligada, `^o` desliga, `^n` grava agora). Ganchos do tmux `[20]` em
  `session-created/closed/renamed`, `after-new-window`, `window-unlinked`, `window-renamed` (`set-hook -gw`) e `after-split-window` chamam
  `tt --snapshot-evento TIPO`; `marcar_fixadas` também; o vigia chama `--snapshot-vigiar` (troca de agente: compara `painel:provedor:pid`).
  `snapshot_evento` anota o motivo e agenda UMA gravação em `TT_SNAP_ESPERA`=4 s; `snapshot_capturar` coleta (uma ida ao tmux; `conversa_do_painel`
  por painel em paralelo; pasta do agente pelo `cwd_do_pid`, no Termux sem o prefixo `installed-rootfs/<distro>`) e `snapshots-tt.py gravar` dedupa por
  assinatura e poda em `TT_SNAP_MAX`=50 (`~/.local/state/tt/snapshots/<ns>.json`, `TT_SNAP_DIR`). Dados entre o tt e o python usam 0x1F (o `read` com
  IFS=tab junta campos vazios). Sessão `_*`, ponte (`@ponte`) e painel flutuante ficam fora.
- Restaurar: `snapshot_restaurar ID aditivo|substituir [sessão-em-uso]` (a tela sempre pergunta o modo; substituir pede "sim"); grava antes um snapshot
  "antes de restaurar" (marca `$RT/tt-snap-UID.restaurando` pausa os eventos), recria sessões/abas/painéis na ordem com o layout, as fixadas (aditivo
  acrescenta; substituir copia), e escreve em cada painel de agente `snapshot_cmd_agente` = `ia-conta retomar PROVEDOR CÓDIGO [--conta C]` (Termux:
  `proot-distro login debian --shared-tmp -- bash -lc 'cd PASTA; …'`). `ia-conta retomar`: claude `--dangerously-skip-permissions --resume`, codex
  `resume ID --dangerously-bypass-approvals-and-sandbox`, kiro `--v3 --trust-all-tools --resume-id`; sem a conversa aqui (`sessoes-ia.py existe`), sessão
  nova do mesmo agente. Arquivo novo do pacote: `snapshots-tt.py`. Teste: `tests/test_snapshots.sh`.

### Busca na conversa inteira (`busca-tt.py`)
- Escopo **conversa** da central (`^e`: tudo → nomes → conversa): índice SQLite FTS5 (`~/.cache/tt/busca.db`, `TT_BUSCA_DB`) da conversa
  inteira do agente de cada painel (`conversa_do_painel` + `sessoes-ia.py exportar`) e do scrollback inteiro do tmux. `busca_indexar`
  (vigia a cada `TT_T_BUSCA`=180 s; `--busca-indexar`) monta o TSV `sessão painel provedor código` numa ida ao tmux e o
  `busca-tt.py indexar` relê só o que mudou (assinatura `mtime:tamanho` / histórico+fim da tela) e esquece o que sumiu.
  `busca-tt.py consultar|trecho|estado`; texto = palavras E, sem acento/caixa, prefixo, `"frase"`, `!exclui`. Na central o fzf fica
  `--disabled` e `change:transform` (`--busca-mudou`) manda `reload(--listar-busca {q})`, que consulta esta máquina e as outras
  (`--busca-consulta` por ssh, `TT_T_BUSCA_REMOTA`=5 s) e filtra as listas guardadas. `busca_conversa=0`/`tt --busca off` desliga.
  Arquivo novo do pacote: `busca-tt.py` em `ARQUIVOS_FONTE`. Teste: `tests/test_busca_conversa.sh`.

### Atalhos no Mac (`tt --mac`)
- `tt --mac [status|ativar|atalhos]`: no macOS Ctrl+clique vira botão direito, Ctrl+Shift+V não existe (Cmd+V) e F1–F10 pedem fn.
  O `tmux.conf` liga `M-MouseDown1Pane`/`M-SecondClick1Pane` como o Ctrl (Option+clique abre link), a tabela `tt-botoes`
  (`Ctrl+B g 1…9,0` = F1…F10) e `y`/Enter para copiar no modo de cópia. `ativar` liga o Option como Meta: Terminal.app
  (`useOptionAsMetaKey` do perfil padrão, via `defaults import`, com cópia em `~/.config/tt/backup`) e Ghostty
  (`macos-option-as-alt = true`); iTerm2/WezTerm só orientam. `TT_MAC_TERMINAL` força o terminal. Teste: `tests/test_mac_atalhos.sh`.

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
- `tt --guarda-aninhado CLIENTE [voltou]` (gancho `client-session-changed` do tmux.conf, só para clientes aninhados, TERM
  `tmux*`/`screen*`): `[0]` o cliente do e-mail (último a sair da `_tt-email`) volta por `run-shell -b "/proc/#{pid}/exe
  switch-client …"` (um switch-client direto no gancho o tmux ignora) e o tt só registra; `[1]` outra vista aninhada que
  passou a mostrar a sessão que a contém (`alcanca`) é desanexada com aviso. Teste: `tests/test_guarda_aninhado.sh`.
- `tt --fechar-paradas`, `tt --definir-paradas N` (0 desliga), `tt --config-paradas`,
  `tt --encerrar-duplicados`.

### Conversas das IAs entre as máquinas (`sessoes-ia.py`)
- `tt --sessoes-ia [status|on|off|agora [rótulo…]]` — estado (conversas daqui por IA, última troca com
  cada máquina em `$ESTADO_DIR/sessoes-ia/maquinas/<rótulo>`), liga/desliga (`sessoes_ia_sync=0|1`, ligado
  de fábrica; desligada a máquina nem manda nem recebe) e troca agora. Menu administrar → 🧠.
- `tt --sessoes-ia-sync [rótulo…]` — para cada máquina: inventário de lá (`--sessoes-ia-inventario`),
  `sessoes-ia.py pedir` decide o que trazer (`--sessoes-ia-empacotar` lá → `aplicar` aqui) e depois o que
  levar (`empacotar` aqui → `--sessoes-ia-aplicar` lá). Trava `$RT/tt-sessoes-ia-$UID.trava`; log do vigia
  em `~/.cache/tt-sessoes-ia.log`; vigia a cada `TT_T_SESSOES_IA` (1800; 0 desliga), 1ª volta 5 min após
  iniciar. tt antigo/desligado/fora da rede: `pulada`.
- `sessoes-ia.py` (stdlib): provedores Claude (`~/.claude/projects`, recursivo, sem `memory/`; `.jsonl`
  = anexa, resto = inteiro), Codex (`sessions/**/rollout-*.jsonl` + linha de `threads` em `state_N.sqlite`
  pelas colunas em comum + `session_index.jsonl`) e Kiro (`sessions/cli/<uuid>.{json,jsonl,history}`,
  grupo, vence o maior `updated_at`). No Termux, acha o do proot (`rootfs/root/.X`, home `/root`) quando o
  da home não tem a subpasta. Forma canônica: home no `"cwd"` (inclusive `file://`) → `@@TT_HOME@@`,
  pasta do projeto do Claude `enc(home)…` → `@H…`, `rollout_path` do Codex → `@@TT_CODEX@@`; hash sha1 da
  forma canônica com cache em `~/.cache/tt/sessoes-ia-hash.json`. Unidade mexida há menos de
  `TT_SESSOES_QUIETO` (120 s) fica fora do inventário e não é trocada no destino. Mescla no destino:
  falta → grava (600, mtime de origem); a daqui contém a outra → mantém; a de lá contém a daqui → troca;
  divergiu → a de mtime maior, a perdedora em `$ESTADO_DIR/sessoes-ia/conflitos/<prov>/<data>/`.
  `TT_SESSOES_EXCLUIR` (= `sessoes_ia_excluir=` do config) são globs sobre `provedor/chave`.
  Novo provedor = nova classe em `PROVEDORES` (descobrir, unidades, chave/rel).
- `sessoes-ia.py achar --provedor P --pid PID [--pids …] [--tela ARQ]` (a conversa de um agente em execução: Claude
  `sessions/<pid>.json`, Kiro `<uuid>.lock` com o pid, Codex a da mesma pasta mexida desde o início do processo,
  desempatada pelas linhas da tela) e `sessoes-ia.py exportar CÓDIGO [--max-resultado N]` (Markdown; base do
  `tt --conversa-ia`). Procuram em todas as pastas do agente (home e cada proot).

### Área de transferência e contas de IA
- `tt --copiar`/`--copiar-buffer`/`--copiado` (clipboard Wayland/X/clip.exe + OSC 52; o `tmux.conf` fixa a
  seleção `c` no `Ms` dos `xterm*` com `terminal-overrides[20]`: o tmux manda `52;;…` e o mosh 1.4 só repassa
  `52;c;…` — `tests/test_copia_osc52.sh`);
  `--propagar-copia`/`--receber-copia`/`--copias` (histórico entre máquinas). `tt --copiar --tela
  LARGURA SX SY EX EY RETANGULO CLIENTE` (copy-pipe do tmux.conf, opção `@tt_copiar`) religa o que a
  tela partiu na borda (`links-tt.py desquebrar`).
- Links: `links-tt.py clique|copiar` (chamados pelo tmux.conf no clique/duplo clique; 0 = havia
  link), `tt --link-abrir ID CLIENTE PAINEL URL`, `tt --link-copiar CLIENTE URL`,
  `tt --links-tela CLIENTE PAINEL` (Ctrl+B u), `tt --abrir-link URL` (seletor de navegador), `tt --abrir-aqui sistema|chromium URL` (abre nesta máquina; a máquina da sessão manda por ssh para a máquina da tela clicada; falha de conexão nunca redireciona para outra máquina).
- `tt --conta-propagar [nome] [alvos...]` / `tt --conta-receber [nome]` — move os arquivos próprios
  da conta Claude de forma transacional. `--receber-contas-ia`/`--propagar-contas-ia`/
  `--puxar-contas-ia` sincronizam o cadastro `contas-ia`. `--registrar`/`--desregistrar`/
  `--session-id` cuidam de registro e identidade de sessão.
- `ia-login` (login centralizado das contas de IA: plano por máquina e cada login num tmux isolado `-L tt-login`):
  para pessoas, `ia-login [máquina…]`, `--plano` e `--principal CONTA|E-MAIL [--plano]`. Os verbos que ele usa entre
  máquinas, por ssh, e que um agente pode dirigir à mão: `--faltas`, `--principal-faltas E`, `--iniciar PROVEDOR CONTA
  [E-MAIL]` (imprime a sessão `login-PROVEDOR-CONTA`), `--tela S`, `--codigo S TEXTO`, `--enter S`, `--conferir
  PROVEDOR CONTA` (o e-mail logado), `--encerrar S`. Para logar sem o dono copiar link nem colar código, o agente usa o
  navegador do celular: skill `celular-android`, seção 14 (função `login_pelo_celular`). O `--iniciar` repete o
  `new-session` se o tmux ainda derruba o servidor da sessão anterior (corrida do tmux 3.6).

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
| `letreiro` | 3ª linha, miolo (texto do letreiro; desenhado pelo `letreiro-tt.py`) | `letreiro_clique` (ação do item sob o mouse ou pausa) | — |
| `fx<chave>` | faixa de fixadas | `ir_fixada` | `menu_fixada` |
| `fxx<chave>` | faixa de fixadas (✕) | `desafixar_item` | `desafixar_item` |
| `fixmais` | chip `+N ▾` da faixa de fixadas | `fixadas_popup` | `fixadas_agrupar` (as de uma máquina lado a lado); a roda: `tt --rolar fixmais ±1` → `fixadas_girar` |
| `at<N>` | atalhos | `atalho_executar` | `atalho_menu` (menu da 5ª coluna; sem ela, `atalho_info`: tooltip, sem executar) |
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
um item muda, para a barra redesenhar. `@fx_mapa` ("LIM:VISÍVEIS …" na ordem das versões; vale a 1ª que cabe) diz,
por cliente (`fixadas_visiveis`), quantos itens vêm antes do chip: a roda no chip (`WheelUp/DownStatus` com range
`fixmais` → `tt --rolar fixmais ∓1` → `fixadas_girar CLIENTE cima|baixo`, um passo por vez com `rolar_vez`) gira, para
cima, as escondidas com a última visível (`mover_fixada VIS N`) e, para baixo, todas (`mover_fixada 1 N`). Botão
direito no chip e `^g` no popup = `fixadas_agrupar` (`tt --fixadas-agrupar`: as de uma máquina lado a lado, máquinas
na ordem da 1ª aparição, estável; sem mudança não grava nem propaga).

Binds de teclado (prefixo `Ctrl+B`): `s` central, `t` tarefas, `|` split horizontal, `-` split
vertical, `c` janela nova, `r` recarrega config, `m` menu do painel, `y` histórico de cópias, `N`
renomear sessão, `F1..F10` botões. Mouse: Ctrl + arrastar/duplo/triplo clique copiam (sem modificador vão ao programa; o Ctrl+arrastar = painel flutuante do tmux 3.8 fica desligado); botão do meio cola;
`MouseDown/Up1Status*` → `--clique` (o 6º argumento é o evento, `d` ao pressionar e `u` ao soltar: o 📌 `fixar` ignora o `u`; sem ele, CLI e testes, age sempre); `MouseUp3Status*` → `--clique-direito`; `WheelUp/DownStatus` em `maquina`/`sessao` →
`tt --rolar RANGE ±1 CLIENTE` (`rolar_sessao`: ordem do tmux, sem pontes/ocultas; `rolar_maquina_cliente`: ordem de
`rotulos`, 1ª sessão do `--listar-leve` de lá, pula quem não responde em `TT_T_ROLAR` s e lembra 60 s; de uma ponte,
pede à máquina da tela `tt --rolar-ponte PONTE RÓTULO ±1`; um passo por vez, `TT_ROLAR_FOLGA` ms entre eles), no
resto da barra `previous-window`/`next-window`;
`MouseUp3Pane`/`MouseDown3Border` → `--menu-painel`.

Popup de tamanho fixo passa por `dim_popup CLIENTE L A` (encolhe até a tela do cliente: o tmux
recusa popup maior que a tela e o clique morria em silêncio no celular de 63 colunas); popup grande
usa `tam_popup`. Nenhum `display-popup` com `-w N`/`-h N` literal (tests/test_popups_tela.sh). Chamado
de fora (CLI), o `display-popup` só volta quando o popup fecha: nos testes, rode em segundo plano.

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
  - `email_padrao` — conta (slug, nome ou endereço) do `tt --email-enviar` sem `--conta`.
  - `tela_destino`, `tela_porta`, `tela_url` — túnel do botão `tela` (F5).
  - `tarefas_sync` — `p2p` (default) | `git` | `ambos` | `off` (menu ⋯ → 🔄 ou `--tarefas-sync`).
  - `tarefas_repo` — URL de um repositório git pessoal para sincronizar tarefas (conferido antes de gravar).
- `maquinas` — `host  usuario  rotulo [oculta]` por linha (`host -` = formato antigo sem usuário).
- `atalhos` — atalhos locais da barra (override de `atalhos-padrao` por ID; emoji `-` desativa).
- `fixadas` (+ `.v` versão em ns, `.trava` lock) — `maquina\tsessao\tchave`.
- `letreiro/NOME.conf` (+ `local/NOME.conf`, `.removidas`, `.migrado`) — fontes do letreiro (sem segredo; ver "Letreiro da faixa").
- `tarefas` (+ `.v`, `.trava`) — `id\testado\tcriada\tmudada\ttexto[\tmeta]`, estado = `aberta|feita|removida` (+ `arquivada`, `pendente`); meta (pares `chave=valor` separados por `|`, na ordem de `tarefas_meta_set`): desc prazo hora prio rep ant antsub ciclos feito tags pai ord arq de upd scod sest colide iest rem v2 base.
- `precos` — `modelo\tUSD/Mtok entrada\tUSD/Mtok saída` (custo estimado do `--tarefa-log`); `cotacao_brl=` no `config` (padrão 5.50).
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
de tarefas; só cache) e `tarefas-git.ok` (epoch da última troca boa), `tarefas-git.erro` (desde,
última, motivo), `tarefas-git.trava`/`.pendente` (uma volta por vez) e `.avisado`.

### Cache e runtime
`~/.cache/tt-vigia.log`, `tt-ticker/` (cache das fontes do letreiro), `tt-letreiro.log`, `tt-github-versao`, `tt-anexos/`, `tt/maildir/<slug>` (sync local);
`$RT` (`/run/user/UID` ou `TT_RT`): pidfile e estado do vigia, lock de clique, cache de máquinas,
ControlPath do ssh, transferências em andamento.

### Pacote `~/.local/share/tt/`
`ARQUIVOS_FONTE` (lista no `tt`): `tt email-tt.py links-tt.py letreiro-tt.py letreiro-fontes.py letreiro-catalogo.json letreiro-padrao.json gatilho-tt.sh tmux.conf
tema-tmux.conf tema-terminal.sh tema-agentes.sh memoria-agentes.sh atalhos-padrao atalhos-padrao-mobile
README.md AI-DLC.md ia-conta ia-rot ia-login contas-uso.py skill-rodizio-de-contas.md nomeador-local.py
skill-tt-terminais.md skill-celular-android.md agentes-regras-tt.md aidlc-tt NOVIDADES.md pacotes-tt.sh sessoes-ia.py
tarefas-merge.py tarefas-merge.vim checagens-tt.md checagem-prompt.md voz voz-audio.py voz-windows.ps1 telas-agentes.py telas-agentes.conf` (a
lista dos testes, em `tests/lib.sh` e `tests/test_repo_em_dia.sh`, acompanha). `ARQUIVOS_PACOTE` = `ARQUIVOS_FONTE` + `VERSAO`.
`skills/figma-cota/{SKILL.md,scripts/figma_rest.py,scripts/figma_oauth_retorno.py,references/acesso-autenticacao.md}`
também faz parte da lista (`ARQUIVOS_SKILL_FIGMA`). Caminhos relativos são preservados ao montar,
completar e espelhar o pacote no proot. Arquivo novo do pacote PRECISA entrar em `ARQUIVOS_FONTE`, senão a autoatualização instala um pacote
incompleto.

## O vigia (`tt --vigia`)

Loop em segundo plano, instância única por pidfile em `$RT`. Log em `~/.cache/tt-vigia.log` (cortado
a 1500 linhas ao passar de 3000). Ao iniciar, `faxina_vigia` remove restos: estado de vigias de
servidores tmux mortos, sidecars de menu e marcas de tema com mais de um dia, temporários de gravações
atômicas (`fixadas.XXXXXX` etc.) com mais de uma hora. A cada volta: `atualizar_barras`. Em intervalos:
- Info das máquinas (sessões e versão, para o menu de máquinas) a cada `TT_T_INFO` s (300).
- Fixadas/tarefas a cada 300 s: `--puxar-fixadas`, `--reconciliar-fixadas`, `--tarefas-puxar`; na
  mesma volta, a sonda por ssh das pontes órfãs (o fechamento por ociosidade é local e roda sempre).
  A sonda acha o alvo pelo **id da sessão** (+ start_time do servidor), não pelo nome, porque o vigia renomeia sessões; só encerra a ponte quando o destino responde, o id e o nome sumiram e isso se repete em 2 voltas. Todo encerramento de ponte fica em `~/.cache/tt-vigia.log`; toda troca de sessão do tt, em `~/.cache/tt-troca.log`.
- Contas de IA a cada 1800 s: `--puxar-contas-ia`; junto, `--puxar-demandas` e `--puxar-letreiro` (fontes globais do letreiro).
- Fontes do letreiro: toda volta, `ticker_atualizar_fontes` (= `letreiro-fontes.py atualizar`: migra o que for antigo, respeita TTL, janela,
  cota, espera após erro e modo economia, e recompila `_roda.json`); desligado com `ticker_ligado=0`.
- E-mail (sync local) a cada `TT_EMAIL_SYNC` s (default 120; 300 ocioso; 0 desliga): `--email-sync --vigia`.
- Padrão visual + memória a cada 300 s: `--reforcar-padrao`, `--memoria-agentes`.
- Atualização: sonda leve a cada `TT_T_SONDA` s (300; 900 no Termux) com `--sondar-atualizacao` e busca completa a cada `TT_T_ATUALIZACAO` s (21600) com `--garantir-atualizacao`.
- Hora confiável a cada `TT_T_HORA` s (21600; 15 min enquanto não houver medida): `--hora --sincronizar`.
- A cada 300 s (e ao iniciar): `--checar-auto` — versão nova instalada → um agente confere e corrige o tt (ver `tt --checar`).
- A cada 300 s (junto de `--reforcar-padrao`): `reforcar_agentes` — skill `tt-terminais`, regras `agentes-regras-tt.md` e `aidlc-tt` em todas as IAs (também na instalação).
- O vigia faz `cd "$HOME"` ao começar (`vigiar`) e `vigia_garantir` o lança com `tmux run-shell -b -c "$HOME"`: ele vive dias e herda o diretório de quem o lançou; se esse diretório é apagado (worktree, pasta temporária), todo git falhava com `getcwd` e a sonda acusava "rede" (`tests/test_vigia_cwd.sh`).
- Toda volta: fecha sessões paradas, pontes ociosas, Claude duplicados, janelas vazias abandonadas.
- Nomeação automática por sessão (título do Claude; primeiro nome; revisão por pontos).

### Variáveis de ajuste (defaults)
`TT_T_PRIMEIRO`=60, `TT_T_RENOMEAR`=300, `TT_T_PASTA`=120, `TT_T_REVISAO`=1800, `TT_T_INFO`=300,
`TT_T_PONTE`=1800, `TT_PAUSA`=60, `TT_T_ATUALIZACAO`=21600 (0 = toda volta), `TT_T_SONDA`=300, `TT_PESO_PEDIDO`=3, `TT_PONTOS_RENOMEAR`=10,
`TT_EMAIL_SYNC`=180, `TT_FIX_VISIVEIS`=8, `TT_TAREFAS_LAPIDE_DIAS`=30. Flags: `TT_FORCAR` (pula
proteção de downgrade), `TT_SEM_BASHRC` (instala sem mexer no `~/.bashrc`), `NOTMUX=1 bash` (abre
terminal sem tmux), `TT_AI_MEMORY_DIR` (dir da memória de agentes), `TT_GIT_NAME`/`TT_GIT_EMAIL`
(commit do repo de tarefas), `TT_MACHINE`/`TT_DIR`/`TT_RT`.

## Sincronização entre máquinas

Protocolo comum: para cada máquina de `maquinas`, `ssh "${SSH_OPC[@]}" dest "$TT_REMOTO --receber-*"`. As
máquinas vão ao mesmo tempo: enviar (`propagar_*`) dispara em 2º plano; puxar (`puxar_*`, `demandas_puxar`,
`letreiro_puxar`), a malha, o `--sincronizar` e o `--saude` usam `nas_maquinas FUNÇÃO` (saída na ordem das
máquinas, o total leva o tempo da mais lenta); `reconciliar_fixadas` consulta as remotas todas de uma vez.
`SSH_OPC` = BatchMode, ConnectTimeout 4, StrictHostKeyChecking accept-new, ControlMaster/Persist
(socket em `~/.cache/tt-ssh-%r@%h`, 12 h), keepalive. `TT_REMOTO` força o PATH (homebrew/local) e
chama `~/.local/bin/tt`. `dest_de ROTULO` resolve `.` (local) ou `usuario@host` pela lista de `maquinas` (cache de 20 s
de `maquinas_agora`): fica de fora a que o Tailscale dá como desligada **de verdade** (Online falso, sem `Active` e
`LastSeen` há mais de `TT_TS_TOLERANCIA` s, padrão 300; só o Online oscila com a máquina de pé). `dest_ir ROTULO` é o
dos cliques que vão a uma máquina (fixada, ponte, origem da tela, atalho/⏩ noutra máquina): cadastrada mas fora da lista,
devolve o host assim mesmo (`maquinas_agora todas`) e sai 2, e quem chama diz "não respondeu" se o ssh falhar.

- **Fixadas**: versão em `.v` (ns da última mudança); `receber_fixadas` só aceita versão mais nova
  (uma máquina atrasada nunca desfaz mudança nova); `puxar_fixadas` busca a maior entre todas. Lock
  por `mkdir` atômico.
- **Tarefas**: modos `p2p` (ssh como fixadas), `git` (repo pessoal `tarefas_repo`), `ambos`, `off`.
  O merge é **por tarefa**: por `id`, vence o maior `mudada`; empate favorece `removida` > `feita`
  > `aberta` (remoção vira lápide e nunca ressuscita). P2P e git interoperam sem perder tarefa.
  Linha malformada não entra no merge (estado fora de `aberta|feita|arquivada|removida|pendente`, `criada`/`mudada`
  não numéricos) e o meta só leva pares `chave=valor` (o lixo é limpo a cada merge). As fontes são passadas como
  arquivos ao `tarefas_merge`, nunca concatenadas com `cat` (`tarefas_linhas` garante a quebra no fim), e cada
  gravação usa temporário próprio (`mktemp`). Incidente de 21/10/2026: arquivo truncado sem quebra + `cat` grudou duas
  tarefas, o texto caiu no meta e crescia a cada merge (9 MB, merges presos em todas as máquinas). Teste:
  `tests/test_tarefas_linha_colada.sh`.
  Modo git (`tarefas_git_sincronizar` → `tarefas_git_volta`): o clone depth 1 em
  `$ESTADO_DIR/tarefas-git` é cache. Cada volta busca com refspec explícito (o clone de repo vazio
  nasce sem nenhum), realinha (`checkout -f -B` no remoto; repo vazio recomeça o ramo), junta na lista
  local o arquivo do repo e o que o clone tinha sem enviar, grava a junção (sem lápide velha) e envia;
  push recusado refaz a volta (até 3). Trava `mkdir` + marca `.pendente`: quem chega com uma volta em
  andamento só marca e ela repete. O vigia também envia (P2P recebido vai ao repo). Git sem hooks/
  assinatura do usuário, `GIT_TERMINAL_PROMPT=0`, ssh `BatchMode`; commit `TT_GIT_NAME/EMAIL`.
  Falha > `TT_TAREFAS_GIT_AVISO` s (3600) avisa na faixa uma vez (ação `tarefas-sync`). Gancho de
  teste `TT_TESTE_ANTES_DO_PUSH` (eval antes do push).
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

### Enviar e-mail pela linha de comando (`tt --email-enviar`)
Envia por qualquer conta do tt, sem abrir tela, independentemente do provedor e da autenticação; a
montagem e o envio são do `email-tt.py enviar CONF OPÇÕES…` (o `tt` resolve a conta e, com `--tarefa`, prepara o compartilhamento).

    tt --email-enviar [--conta CONTA] --para END[,END…] [--cc END…] [--cco END…] --assunto TEXTO
       [--corpo TEXTO | --corpo-arquivo ARQ | corpo no stdin] [--html TEXTO | --html-arquivo ARQ]
       [--anexo ARQ]… [--responder-para END] [--em-resposta-a MESSAGE-ID] [--sem-assinatura] [--ensaio]

- **Nomes dos campos** (canônicos em português; os apelidos em inglês valem igual, também na forma `--opção=valor`):

  | Campo | Opção | Apelido | Cabeçalho |
  |---|---|---|---|
  | conta | `--conta` (ou `--de`): slug, nome ou endereço | `--account`, `--from` | `From` = `nome_exibicao` + `endereco` |
  | destinatário | `--para` (vírgulas e/ou repetida) | `--to` | `To` |
  | cópia | `--cc` | `--cc` | `Cc` |
  | cópia oculta | `--cco` | `--bcc` | só no envelope (SMTP) / `BccRecipients` (Outlook) |
  | assunto | `--assunto` (obrigatório; `""` = sem assunto) | `--subject` | `Subject` |
  | corpo | `--corpo`, `--corpo-arquivo`, ou o stdin | `--body`, `--body-file` | `text/plain` (UTF-8) |
  | corpo HTML | `--html`, `--html-arquivo` (alternativa ao texto) | `--html-file` | `text/html` |
  | anexo | `--anexo` (repetível) | `--attach`, `--attachment` | anexo com o nome do arquivo |
  | responder para | `--responder-para` | `--reply-to` | `Reply-To` |
  | em resposta a | `--em-resposta-a` (com ou sem `<>`) | `--in-reply-to` | `In-Reply-To` + `References` |
  | assinatura | entra a de `~/.config/tt/email/<slug>.assinatura`; `--sem-assinatura` tira | `--no-signature` | depois de `-- ` |
  | ensaio | `--ensaio`: imprime a mensagem (cabeçalhos, corpo, anexos) e não envia | `--dry-run` | — |

- **Conta:** `--conta` resolve por slug, `nome=` ou `endereco=` (sem diferença de caixa); sem ela, a chave
  `email_padrao=` do `config`, ou a única conta; ambígua → rc 2 com a lista.
- **Caminho** (`email-tt.py`): conta Graph (`provedor=microsoft graph=1`) → `outlook_json` + `outlook_postar`
  (API REST do Outlook; `TT_EMAIL_OUTLOOK_API` troca a base, só nos testes; anexos até 3 MB no total; a API não
  aceita `In-Reply-To`, então resposta não se encadeia lá). Demais → `smtp_enviar` (TLS, STARTTLS ou nenhuma;
  `credencial`: senha de `~/.secrets/aerc-<slug>.txt`, `cred_cmd` ou XOAUTH2 com token renovado). Cópia nos
  enviados: Gmail, Microsoft e Outlook guardam sozinhos; os outros recebem APPEND IMAP em `pasta_enviados`
  (falha aqui só avisa: o e-mail já saiu).
- **Saída:** `✓ enviado de A para B, C por SMTP host|Outlook (API REST) · Message-ID: <…>`; rc 0 enviado, 1
  falhou (`✗ não enviado: motivo`), 2 uso errado (conta, destinatário, assunto, arquivo, opção). `--ajuda` mostra o uso.
- **Agente de IA:** o verbo envia na hora, sem perguntar. Antes de mandar a terceiros, mostre ao usuário o
  `--ensaio` e confirme; entre as contas do próprio usuário, só com o pedido dele. Nunca ponha senha, token ou
  segredo no corpo. Para compartilhar tarefas pelo transporte configurado, use `--tarefa ID` (repetível; também `--task`):
  assunto e corpo são gerados no formato `[tt] … ~CÓDIGO`, uma mensagem por tarefa. Não combine com assunto/corpo/HTML próprios.
- **Fluxo visual:** menus do 📧 e do 📋 → 📨 Enviar tarefas, ou menu ⋯ da tarefa → 📨 Enviar pela conta do tt;
  `tt --email-enviar --tarefas-ui [--tarefa ID]` seleciona tarefas, conta, destinatários e pede confirmação após a prévia.
  `--ensaio` nunca transmite nem muda a base. O lote inteiro é validado antes do primeiro envio e IDs repetidos são deduplicados.
  Falha de transporte interrompe o lote e informa quantas mensagens já saíram; não reenviar o lote inteiro automaticamente.
- Testes: `tests/test_email_enviar.sh` (servidor SMTP e API do Outlook falsos; campos, apelidos, Cco, HTML,
  anexo, resposta, stdin, conta, ensaio, erros e o `graph-sendmail` do aerc).

## E-mail (resumo)

Cliente configurável (`email=`, default `aerc`), aberto numa subjanela `display-popup` (não cria
sessão de trabalho; roda numa sessão oculta `_tt-email` fora da central/seletor/vigia). Contas em
`~/.config/tt/email/<slug>.conf` (sem segredo); segredos em `~/.secrets` (600). O `accounts.conf` do
aerc é gerado entre marcadores `# >>> tt e-mail: <slug> >>>` (blocos à mão ficam intactos).
`email-tt.py` descobre provedor (autoconfig/MX, detecta Microsoft 365 e Google), faz OAuth2 (código
no aparelho ou navegador), testa IMAP/SMTP, lista pastas, converte HTML e envia (`tt --email-enviar`) —
sempre sem imprimir senha/refresh token. Sync local opcional (`sync_local=1`) por mbsync em
`~/.cache/tt/maildir/<slug>` (contas Graph: `graph-sync`). Envio online: SMTP, ou a API REST do Outlook nas
contas Graph.

## Celular / Termux

`termux/celular.sh` provisiona um aparelho do zero: pacotes do Termux, sshd por chave na porta 8022,
boot automático, Debian via proot-distro com o Claude, e o tt. Subcomandos: `verificar`,
`conectar eu@pc`, `android`, opções `--nome`, `--chaves-github`, `--sem-claude`. É idempotente
(`*.antes-celular` como backup). O proot do Android não tem `/dev/fd` (evite `<(...)`) nem `iconv`
(por isso a remoção de acentos é feita em Python). Perfil de atalhos: `atalhos-padrao-mobile`.

Os agentes do celular rodam no Debian do proot (glibc); o shell do sistema Android (`uid shell`) vem do
adb do próprio aparelho (`adb-local`, `127.0.0.1:5555`) ou do Shizuku (`tt-rish`), e o Tasker religa a
depuração sem fio depois do reboot. Tudo isso, com receitas de tela (screencap, uiautomator, input,
am start), está na skill **`celular-android`**, instalada pelo tt nos agentes (no PC e no proot).
O jeito rápido de operar a tela (servidor `uid shell` local consultado em ~40 ms, tela virtual, lotes, mapa de
telas), o Tasker como ponte e como log, as armadilhas aprendidas, os hábitos e o diagnóstico e como dispensar o Wi-Fi
depois do primeiro boot estão na mesma skill. Também está lá a receita que usa o **navegador do celular como navegador
das outras máquinas do usuário** (logar ou trocar a conta de IA de uma máquina sem o dono copiar link nem colar código:
`ia-login` + controle rápido, com uma função de bash testada em `tests/test_login_pelo_celular.sh`).

## Portabilidade (Linux e macOS)

O tt roda no Linux (Debian/Ubuntu/WSL/Termux…) **e** no macOS (Homebrew). Ao desenvolver, não assuma Linux: o macOS tem zsh como
shell padrão, bash 3.2 no sistema, ferramentas BSD e não tem `/proc`, `setsid`, `getent`, `xdg-open`, `notify-send` nem
`C.UTF-8`. As regras completas (e os auxiliares `env_do_pid`, `cwd_do_pid`, `cmdline_do_pid`, `$TT_UTF8`, `tt --e-ponte`) estão
na seção "Portabilidade" do `AGENTS.md`; o guardião é `tests/test_portabilidade.sh`. No macOS o tt põe as ferramentas GNU do
Homebrew (coreutils, gnu-sed, gnu-tar, findutils, grep, gawk, util-linux) na frente do PATH só dos processos dele, e a janela nova
volta ao PATH de origem (`_TT_PATH_ORIGEM`).

## Testes e desenvolvimento

- `make test` → `tests/run.sh`. `make test-installed` roda contra `~/.local/share/tt`.
- Cada `tests/test_*.sh` roda isolado em `HOME`/`XDG_CONFIG_HOME`/`TT_RT` temporários e um socket
  tmux próprio — **nunca** toque o tmux/arquivos reais do usuário num teste. Sem o `isolar()` do
  `lib.sh`, o teste faz `source "$(dirname "$0")/tmux-isolado.sh"` logo depois do `trap EXIT` dele
  (tira `TMUX`/`TMUX_PANE`, `TMUX_TMPDIR` temporário, soma a limpeza ao trap). O `run.sh` roda a suíte
  com um tmux padrão próprio e um servidor sentinela: teste que manda comando a ele (no uso real seria
  o tmux do usuário: o `avisar` do tt faz display-message em todos os clientes) ou o derruba é
  reprovado, e teste sem um dos dois `source` também.
- Notificação do sistema também nunca sai de um teste: os dois isoladores põem na frente do PATH um
  `notify-send`/`termux-notification` mudo (`tests/sem-notificacao-real.sh`; só para os comandos que existem
  na máquina) e o `run.sh` põe uma sentinela por teste que reprova o teste que ainda chegar ao de verdade. Teste que
  quer conferir o aviso põe o próprio stub em `$T/bin`. O `notify-send` dos AGENTES (`--notificar-daqui`)
  vai ao 🔔 e ao sistema no uso normal (regra do usuário; `test_notificar_daqui` item 9). O não perturbe ligado
  explicitamente pelo usuário silencia o aparelho, preservando o aviso no 🔔.
- Paralelo: `TT_TESTES_J` testes ao mesmo tempo (padrão nº de CPUs, até 8; no Mac, no máximo um por 4 GB de RAM;
  `1` = em fila; valor explícito prevalece), cada um com a sua
  sentinela (`TMUX_TMPDIR` próprio); fila pelos mais demorados (`~/.cache/tt-testes/duracoes`); a saída de cada
  teste sai inteira quando ele termina. Teste que mede tempo ou depende de tela/teclas sob carga leva
  `# tt-teste: sozinho` (roda no fim, um por vez). `TT_TESTES=regex` filtra; `TT_TESTE_TEMPO_MAX` (1800 s).
  `tmux-isolado.sh` também dá `TT_RT` próprio; `isolar()`/`tmux-isolado.sh` deixam a tela gráfica real
  inalcançável (`sem_tela_real`: `XDG_RUNTIME_DIR` do teste, `WAYLAND_DISPLAY`/`DISPLAY` existentes com valor
  morto — o tt acha o compositor sozinho e escrevia na área de transferência de verdade). Ao paralelizar, não
  use `pkill`/`kill` por padrão amplo (ex.: `tests/run.sh`): pega a suíte dos outros.
  Rode uma suíte por máquina: `sozinho` sequencia testes dentro de uma rodada, sem coordenar duas rodadas
  independentes. Outra suíte ou teste gráfico simultâneo invalida essa reserva de CPU. Confira carga e swap
  antes de atribuir falhas de prazo ao produto; no Mac de 8 GB o padrão passa a ser dois testes paralelos.
- `TT_RT` explícito é criado ao iniciar; caminho inválido encerra com erro. Ao simular outra
  máquina mudando HOME, mantenha o runtime dentro da pasta isolada, inclusive nos comandos SSH.
- Clipboard de teste: os dois isoladores interceptam `clip.exe`, inclusive no Mac. O receptor
  `tests/clipboard-isolado.py` recebe UTF-16LE e só encaminha UTF-8 para substitutos dentro da
  pasta isolada (por exemplo, `$T/bin/wl-copy`); sem substituto, grava no próprio ambiente.
  Isso impede que o caminho absoluto do clipboard do WSL alcance o Windows real.
- Processos simulados: use `exec_como`/`nomear_script`. Renomear o executável sleep pode quebrar
  applets uutils/BusyBox. Para sleep no Linux, `exec_como` usa um processo ocioso com nome explícito;
  no Mac preserva o nome do executável. Espere o processo ou a tela ficar pronto antes de enviar
  teclas; use sinais observáveis em vez de pausas fixas. Teste: `tests/test_ambiente_isolado.sh`.
- Mouse da central: transforms demorados fazem o fzf pausar o terminal; nas versões 0.67 e
  0.74.5, a retomada parcial não religa os modos 1000/1002/1006. `fzf_repor_mouse` os repõe no
  tty dos callbacks da central, sem imprimir escapes na CLI. `test_central_pino.sh` segura a
  trava por 3 s e verifica o próximo clique, além do toque duplo.
- Sync de e-mail: avisos e demandas podem criar filhos que herdam o fd da trava. Depois do
  processamento protegido, `flock -u 9` libera a trava antes de fechar o descritor; fechar só
  no pai não basta. Regressões: `test_email_aviso.sh` mantém um filho vivo e exige a rodada
  seguinte; `test_flock_portavel.sh` confere o fallback sem flock nativo, inclusive -u e -s.
- Reabertura do e-mail: `test_email_sessao.sh` exige a mesma sessão, painel e processo do aerc,
  além de medir a resposta (menos de 1,5 s no Linux e 2,5 s no Mac). A identidade preservada
  verifica o reaproveitamento; pequenas variações de agendamento não significam reinício.
- Nomeação simulada: instalação e reforço podem criar `~/.local/bin/claude-rot`, escolhido antes
  do `claude` no PATH. Substitua também essa rota por um arquivo próprio no HOME isolado, escolha
  `nomeador=claude` e espere o resultado; nunca deixe o teste depender de contas autenticadas.
  Cenários: `tests/test_redesenho_eventos.sh` e `tests/test_vigia_claude.sh`.
- Fonte para testes em outra máquina: grave o branch local e transfira com `git archive HEAD`.
  O tar do macOS pode levar `._*` (AppleDouble) e invalidar amostras/documentação. Não trate
  esses artefatos de transporte como falhas do catálogo.
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
- **A troca do pacote é uma por vez** (`instalar_travar`/`instalar_destravar`, `$DIR_TT.trava`, mkdir atômico; dono morto ou 10 min = retomada; `TT_INSTALAR_TRAVA_TENTATIVAS`): a troca usa `$DIR_TT.novo`/`.velho` e duas ao mesmo tempo (vigia que se atualiza + `--atualizar` por ssh) deixavam `~/.local/share/tt` sem pacote. Depois da trava reconfere (mesmo pacote: nada a fazer; versão mais nova instalada: não rebaixa). Não dispare `--atualizar --todas` enquanto os vigias das máquinas podem estar se atualizando: espere-os (`publicar.sh` agora espera). Teste: `tests/test_instalacao_concorrente.sh`.
- Tecla lida byte a byte numa tela própria (`read -rsn1`): o resto de uma seta ou clique depois do ESC espera
  `-t "${TT_ESC_SEQ:-0.3}"`, nunca 30–50 ms. Sob carga, ssh ou mosh o resto chega depois, e a seta virava Esc (a tela
  de transferências fechava). O `email-tt.py` usa o mesmo prazo (`ESC_SEQ`) e espera também o `\e[` pela metade;
  `tests/test_transferencias.sh` (2b) e `tests/test_email_oauth_menu.sh` mandam a seta partida.
- Teste que lança trabalho em segundo plano (transferência por `setsid`) espera ele acabar antes da etapa seguinte:
  o que o trabalho faz depois cai no registro da outra etapa (`espera_transferencias` em
  `tests/test_anexos_maquina_da_tela.sh`). Etapa que confere comportamento, e não tempo, não depende de janela
  curta (o duplo clique de `tests/test_tarefas_subtarefas.sh` 3 usa `TT_TAREFAS_DUPLO_MS=5000`; o tempo fica na 3b).

### Desempenho: o servidor do tmux é o gargalo
O servidor do tmux é uma linha só e atende um pedido por vez, atrás dos redesenhos dos painéis: uma IA que
redesenha a tela inteira a cada token (um Codex chegou a 134 KB/s) deixa cada ida ao tmux custando de dezenas
a centenas de ms. Regras do código:
- **Uma ida para todos, nunca uma por sessão/painel.** `list-sessions`/`list-panes -a`/`list-windows -a` com
  separador 0x1F (`$'…\x1f…'`: não é espaço, campo vazio não desloca colunas no `read`; `|` quebrava rótulos).
  Várias opções de uma vez: `display-message -p '#{@a}␟#{@b}'` (devolve o valor literal). Dois comandos na
  mesma ida: `tmux cmd1 \; cmd2`. `PAINEIS_FMT` (listar), `paineis_base`, `atualizar_barras`.
- **O que sobra, em paralelo:** `par`/`par_fim` (teto `TT_PARALELO`, padrão 8): N idas juntas esperam a fila
  uma vez. Máquinas: `nas_maquinas FUNÇÃO` (todas ao mesmo tempo; saída na ordem delas, stderr à parte).
- **Painel de trabalho:** `=sessão:` é o painel ATIVO — com uma janela do tt aberta por cima (e-mail, menus,
  tarefas, central: painéis flutuantes do tmux 3.8 com `painel_flutuante=1`), é ela. Quem lê "a sessão"
  (tela, pasta, programa, Claude) usa `painel_base SESSÃO` ou `paineis_base` (todas, uma ida; campo
  `sobreposta`); flutuantes ficam fora de listas e da detecção de vazias, e o vigia não decide nome com uma
  janela do tt por cima. `tests/test_painel_flutuante_sessao.sh` (precisa de tmux 3.8: `TT_TMUX_38`).
- **Opções em lote:** todo `set-option` (até de `@opção`) redesenha a tela inteira de todos os clientes. Vários
  sets numa ida são um pedido e um redesenho: `lote=(); lote_add lote set -g @a 1; lote_add lote set -g @b 2;
  tmux "${lote[@]}"` (`lote_add` segue a regra do tmux para argumento que termina em `;`). `atualizar_barras`
  grava tudo o que mudou num lote só (eram até 17 sets, cada um com seu redesenho); `aplicar_fixadas` e
  `criar_ponte` também.
- **Comando existe? `tem_cmd NOME`**, não `command -v`, em tudo que roda por clique, barra ou aviso. No WSL o
  PATH herda as pastas do Windows (`/mnt/c/…`) e cada comando AUSENTE custava ~35 ms (60 a 80 sob carga); a
  barra perguntava pelo `termux-open-url` 8 vezes por volta. As pastas do Linux, funções e builtins são
  conferidas sempre (é o `command -v` sem as pastas montadas); só a resposta das pastas do Windows fica
  guardada, `TT_CMD_WIN_VALE` s (600), em `$RT/tt-cmd-UID/`, e cada processo lembra o que já perguntou (o vigia
  esquece a cada volta). Para a resposta exata na hora (pendências, instalação), `command -v`.
- **Sem processo onde o bash resolve:** cada processo custa de 1 a 5 ms (dezenas sob carga) e um clique rodava
  dezenas. Hora: `printf -v agora '%(%s)T' -1` e `tt_fmt_epoch` (formata pelo `printf` do bash); µs:
  `${EPOCHREALTIME/[.,]/}`; config: `conf_em VAR chave` (sem subshell); arquivo pequeno: `read`, não `cat`;
  chave das fixadas: `fixada_chave_em VAR máquina sessão id` (o sha256 fica guardado em
  `$RT/tt-fixadas-chaves-UID`); `estado`, `maquinas` (idade do cache pelo carimbo `.t`), `soltos` (`/proc` direto)
  e `fixadas_selos` já são assim. Menus com muitos itens medem o cliente uma vez (`tam_popup_fixar`).
- **Barra depois de mudar um dado:** `atualizar_barras_pedir`. Na linha de comando (e nos testes) é o
  `atualizar_barras` síncrono de sempre; nas telas que recarregam a própria lista (painel de tarefas, histórico
  de avisos, agenda: `TT_BARRA_FUNDO=1`) vai para `atualizar_barras_fundo`, uma volta por vez em 2º plano em
  que pedidos seguidos se juntam e a última volta começa depois do último pedido (trava
  `$RT/tt-barras-UID.trava`, pedido `.pedido`).
- **Ganchos em rajada:** abrir ou fechar uma janela flutuante dispara 3 ou 4 ganchos do tmux; com
  `tt --bordas gancho` só o primeiro trabalha (marca `$RT/tt-bordas-UID.pend`). `tt --bordas` direto continua
  síncrono.
- **Clique dentro de um painel:** antes do `links-tt.py` (~30 ms de python por clique), o `tmux.conf` confere em
  ~2 ms se há `http` ou `://` nas mesmas linhas que ele leria (ou um hiperlink sob o mouse); sem isso não há
  link possível e o clique vai direto ao programa. Usa o tmux do próprio servidor (`/proc/#{pid}/exe`).
- Medir: `touch ~/.config/tt/trace` grava cada linha executada nos cliques, com hora, em
  `~/.cache/tt-trace.log` (`rm` desliga). O log interno do servidor tmux (SIGUSR2) dobra o custo de cada
  comando: só para depurar. Teste das garantias acima: `tests/test_desempenho.sh`.

### Partida rápida (rapido/)
- O bash lê um script comando a comando: o desvio no topo do `tt` (antes do `set -u`) faz `source
  $DIR_TT/rapido/nucleo.sh` e `exit` quando o `tt` executado é o instalado (`$0 -ef $DIR_TT/tt`), o núcleo
  existe e não é mais velho que ele, e `TT_COMPLETO` está vazio. O núcleo é o código de topo do `tt` na mesma
  ordem, com cada função de várias linhas (definida uma vez só, na coluna 0) trocada por um stub
  `f() { _tt_f f || return; f "$@"; }`; `_tt_f` lê `rapido/f/f.sh` (o texto original, com os comentários de
  cima) e, sem ele, `todas.sh`. No desvio, o caminho do tt (`EU`) já é o do pacote (sem o `readlink` de cada
  partida); o código de topo não abre subshell (`conf_em`, `printf -v`): a partida fica em ~13 ms. Processos longos (`--vigia`, `--transferir-fundo`, `--email-sync`,
  `--sessoes-ia-sync`, `--ticker-loop`, `--malha-vigia`, `--instalar-aqui`) carregam `todas.sh` de uma vez.
- `gerar_rapido PASTA` (na instalação, na pasta nova antes da troca; `tt --rapido gerar`) divide e confere:
  cada corpo lido sozinho == `declare -f` do tt inteiro carregado com `TT_SO_CARREGAR=1` (para na guarda
  "Fim das definições"); núcleo carregado == mesmas funções (`declare -F`) e variáveis de topo (`declare -p`,
  menos as voláteis). Qualquer diferença: não instala `rapido/`.
- **Regras para editar o `tt`:** toda função nova vai ANTES da guarda `[[ -n ${TT_SO_CARREGAR:-} ]] && …`
  (depois dela o gerador recusa e o tt fica sem partida rápida; `tests/test_partida_rapida.sh` acusa). Função
  definida duas vezes fica inteira no núcleo (sem ganho). Não dependa de `BASH_SOURCE`/`LINENO` do arquivo
  `tt`, nem de `FUNCNAME[1]` na 1ª chamada (o stub aparece na pilha).

## Requisitos

Núcleo: bash, tmux ≥ 3.4, fzf ≥ 0.60, python3, ssh, tar (GNU), rg. Opcionais: tailscale (descoberta
e estado online das máquinas), mosh (celular), pv (barra de progresso), claude (botões cl/clc/clr e
nomeador), aerc (e-mail), mbsync/isync (sync local), git (sync de tarefas por repo). macOS: bash ≥ 4
pelo Homebrew; comandos remotos levam o PATH do Homebrew (o instalador acrescenta um bloco ao
`~/.zshenv`).

## Tarefas: código, apelido, registro e e-mail

Como uma IA (ou pessoa) trabalha com as tarefas do tt. Vale para Claude, Codex e Kiro, em qualquer máquina: o vigia
reinjeta esta skill e as regras curtas (`agentes-regras-tt.md`) em todas as IAs (ver "Reforço pelo vigia").

### 1. Falar de uma tarefa: código e apelido
- **Código** = id da tarefa (12 hex). Único por construção (hash de máquina, hora em ns e pid), igual em todas as máquinas
  e nos e-mails; é ele que decide se "é a mesma tarefa". **Apelido** = forma curta e falável derivada do código
  (`kito47`; 562 500 combinações; o mesmo em toda máquina; se dois colidirem, o verbo lista as candidatas e pede o código).
- Subtarefa também tem código e apelido próprios (`tt --tarefa-codigo` mostra a referência estável `MÃE.apelido` na 4ª coluna, ex.:
  `kito47.ruzi83`). `MÃE.N` (ex.: `kito47.2`) é a **posição** da subtarefa entre as filhas vivas de hoje (ordem: `ord`,
  hora de criação, código — a mesma no painel, no cartão e na linha de comando) e **desliza** quando outra entra, sai ou
  muda de lugar: serve para olhar, nunca para alterar de forma automática. Os verbos que alteram imprimem em stderr
  `→ kito47.ruzi83 «texto» (subtarefa de «mãe»)` quando o alvo não foi dado pelo código inteiro (por posição, avisam).
  Só tarefa de topo tem subtarefa (`--tarefa-sub-add` numa subtarefa é recusado). O código é sorteado uma vez na criação
  (nunca derivado do conteúdo) e não repete um existente. O apelido tem 562 500 valores (8 primeiros hex), compartilhados com
  as tarefas: pode repetir (100 itens ≈ 0,8%; 500 ≈ 19%); repetido entre irmãs ou globalmente, o resolvedor lista as
  candidatas e pede o código.
- Onde aparecem: na lista do painel (apelido antes do título; `.N` nas subtarefas; código inteiro no fim da linha em painel largo,
  80+ colunas; a busca acha por eles), no cartão da tarefa (`^/`), topo do menu ⋯ da tarefa, `tt --tarefas` (texto),
  `tt --tarefa-codigo`. O usuário pode dizer só "a kito47"; resolva com `tt --tarefa-codigo kito47`.
- Ao falar com o usuário, cite sempre o apelido (e o título); em scripts e e-mails use o código inteiro.

### 2. Trabalhar numa tarefa (fluxo)
1. Localize: `tt --tarefas` (lista com apelidos) ou `tt --tarefa-codigo APELIDO`.
2. Leia o pedido: `tt --tarefa-ia-prompt ID` (título, prazo, descrição, subtarefas com ids).
3. Faça o trabalho; a cada marco, **registre** (seção 3); conclua cada subtarefa com `tt --tarefa-ok ID` e, por fim, a mãe
   (ela só conclui com todas as subtarefas feitas; a última subtarefa não conclui a mãe sozinha).
4. Precisa de algo do usuário: `tt --notificar-daqui "…" [--sempre]`. Perguntas do AI-DLC: `aidlc-tt publicar` na descrição.
5. Atualizar sem estragar: `tt --tarefa-editar ID "frase"` relê a frase como na criação (marcador ausente tira o atributo!);
   só o texto: `tt --tarefa-renomear`; prazo/prioridade/repetição pelos botões/verbos próprios; **nunca** sobrescreva a descrição
   com `tt --tarefa-desc` sem antes ler e preservar o que havia (use `--tarefa-log` para acrescentar).
6. Não publique, faça push nem instale em outras máquinas sem o dono pedir.

### 3. Registrar o que foi feito (`tt --tarefa-log`)
Cada registro vira um bloco no fim da descrição da tarefa/subtarefa, em cinza discreto no cartão:
```
⟡ 2026-10-10T18:52:00Z · kito47
  fez: Implementei o login
  como: editei tt, rodei os testes no Termux
  por: claude · claude-sonnet-5-5 · esforço high · sessão impl-3 [código abcd1234] · máquina notebook
  período: 2026-10-10T15:10:00-03:00 → 2026-10-10T15:52:00-03:00
  conta: trabalho <voce@exemplo.com>
  uso: 12300 tokens (10000 ent · 2300 sai) · ≈ US$ 0,0900 · ≈ R$ 0,45
```
- **Sai sozinho:** quando, apelido, máquina (`nome=` do tt), sessão tmux (`$TMUX_PANE`), agente (`CLAUDECODE`, `CODEX_*`, `KIRO_*`),
  conta (`IA_CONTA` ou o perfil de `CLAUDE_CONFIG_DIR`) e e-mail (cadastro `contas-ia`). Modelo, esforço e tokens só o agente
  sabe: **informe** (`--modelo`, `--esforco`, `--tokens-ent/--tokens-sai`). `TT_LOG_MODELO`/`TT_LOG_ESFORCO` são padrões.
- **Custos** (estimativas): `--usd V` e `--brl V` aceitam valores explícitos. Sem eles, calcula pela tabela `~/.config/tt/precos`
  (`modelo<TAB>USD por Mtok entrada<TAB>USD por Mtok saída`) e `cotacao_brl=` do config (padrão 5.50). Sem preço do modelo, não inventa valor.
  A tabela de preços e a cotação são do usuário: mantenha-as atualizadas.
- **Sessão e período:** dentro do tmux, o código persistente da sessão é coletado automaticamente e identifica a sessão após renomear; com `--sessao-codigo` pode ser informado manualmente.
  `tt --session-resolve CÓDIGO` informa máquina e nome atual da sessão no servidor tmux local, para você reanexar e recuperar o contexto enquanto ela existir.
  `--inicio` e `--fim` são obrigatórios e devem ser RFC 3339 com fuso (`Z` ou `±HH:MM`); o tt recusa fuso ausente e início posterior ao fim.
- **Quando registrar:** um registro por marco (subtarefa concluída, decisão, bloqueio), não por comando. Texto curto e objetivo no
  "fez"; o "como" diz o método/arquivos/testes. Não ponha segredos nem tokens de acesso.
- **Ler:** `tt --tarefa-historico ID` (tarefa + subtarefas, com totais de tokens, USD e R$).
- O log só acrescenta (preserva `aidlc:` e as notas do dono). Testes: `tests/test_tarefas_codigo.sh`.

### 4. Compartilhar por e-mail = upsert pelo código, em três vias
- **Enviar:** `tt --email-enviar --para DESTINO --tarefa ID [--ensaio]` usa SMTP/Outlook; `--tarefas-ui` abre seleção e revisão.
  O compositor manual segue em menu ⋯ → ✉ (ou `tt --tarefa-email ID [destinatário] [--abrir]`, `tt --tarefas-email DESTINO ID…`, `tt --tarefa-email-ui`;
  `TT_EMAIL_MAILTO_CMD` troca o compositor). Ambos geram `Assunto: [tt] título @prazo !prio #tag ~CÓDIGO` e o corpo: descrição **sem os blocos `⟡` do diário** (conta, e-mail,
  máquina, tokens e custo não viajam), `- [CÓDIGO] [x]|[ ] texto` por subtarefa e, depois da assinatura `-- `, o rodapé do protocolo v2
  `tt:2 estado=aberta|feita removidas=COD,COD`. Um tt antigo ignora tudo depois da assinatura (continua válido para ele). Só tarefa de topo.
  Enviar grava a **base** (meta `base=`): a versão enviada.
- **Extensão rica v3:** conserva o rodapé v2 e acrescenta dados tipados de todas as subtarefas (descrição, prazo/hora, prioridade,
  repetição e etiquetas), com descrição principal exata. O diário é retirado de mães e filhas. O pacote acompanha o corpo legível;
  se alguém editar o corpo no compositor, passa a valer a leitura do texto. Limites explícitos: 1 MB no corpo e 1000 subtarefas/remoções,
  com erro antes de enviar (sem truncamento silencioso). O receptor valida IDs, tipos e atributos; a revisão em três vias inclui cada atributo
  das filhas, mantém o diário local e entende mensagens antigas. Graph guarda corpo completo em MIME UTF-8, Message-ID e autenticação do provedor.
- **Receber** (remetente autorizado, ver verbos de demandas; mesmas regras de segurança):
  - A etiqueta do remetente é local e reservada (`netto` → `#_netto`). O prefixo `_` é recusado na criação/edição
    manual e descartado em mensagens externas. Exportação e bases de comparação não levam essas etiquetas;
    aprovação de atualizações e edição preservam as locais. A instalação migra etiquetas antigas apenas quando
    `de=` identifica o remetente cadastrado (inclui arquivadas, com backup e sem alterar etiquetas manuais homônimas).
  - `~CÓDIGO` ausente → demanda nova como sempre (id do Message-ID; reenviar duas vezes cria duas — por isso o código).
  - código que **não existe** aqui (ou ainda é pendente) → nasce PENDENTE **com o mesmo código** (e subtarefas com os códigos do remetente,
    se livres); `[x]` e o estado da tarefa chegam como estavam; um e-mail mais novo do mesmo remetente substitui a pendente.
  - código que **existe** → **atualização** (↻) na Entrada, em **três vias** (`tarefas-merge.py`): `atual` × `recebida` × `base` (a última
    versão que os dois viram: gravada ao enviar e ao aplicar). Por campo (título, prazo, prioridade, repetição, etiquetas, descrição,
    situação) e por subtarefa (texto, situação, nova, removida): `igual` nada; `minha` só você mudou → fica; `entrada` só o e-mail mudou →
    entra; `conflito` os dois mudaram (ou não há base e diferem) → **ninguém grava até decidir**. Sem base (tarefa nunca trocada por e-mail)
    o que difere é conflito. E-mail legado (sem `tt:2`): `[x]` conclui, falta de `[x]` não reabre.
  - **Triagem ao chegar:** sem diferença em relação à tarefa, superada por uma mais nova do mesmo remetente, ou substituída pela nova → descartada
    sem aviso. Código de subtarefa que já é de outra coisa (ou removida) nunca é tomado: a subtarefa entra nova, com código daqui (`colide=`).
    `~CÓDIGO` que aponta para uma subtarefa daqui vira demanda nova. Código de tarefa **removida** → ignorado.
- **Decidir:** `tt --demanda-diff ID` (texto), `tt --demanda-merge ID` (tela única no vim: botões clicáveis + teclas `r m b e u A M Tab`,
  `Ctrl+S` aplica / `Q` cancela; sem vim, pergunta no terminal), `tt --demanda-aprovar [--recebida|--minha] ID` (sai **4** se houver conflito
  sem escolha e não grava nada), `--demandas-aprovar-limpas`, `--demandas-recusar-todas`. Na Entrada: ⇄ revisar mudanças, ✓ aprovar (com
  conflito abre a revisão), aprovar todas as sem conflito, recusar todas. Aprovar grava a base nova (a versão que chegou).
- E-mail `[tt]` de remetente ainda não autorizado vai para `<conta>.demandas.espera` (log: "aguardando autorização") e é
  relido quando o remetente passa a valer; o leitor (`email-tt.py demanda`) não corta descrição nem subtarefas.
- `tt --demandas-pendentes` mostra `[atualiza CÓDIGO]` nas propostas. Testes: `tests/test_tarefas_merge.sh`, `test_tarefas_enviar.sh`,
  `test_tarefas_identidade.sh`.

### 5. Reforço pelo vigia (como estas regras chegam às IAs)
- **AGENTS.md único:** `~/.agents/AGENTS.md` é a fonte das instruções globais de TODAS as IAs: o texto do usuário e, entre
  marcadores `<!-- tt-managed:regras-tt BEGIN … END -->`, `agentes-regras-tt.md` (só regravado se mudou). Para mudar uma instrução
  global sua, edite **a fonte**; nunca crie regra em `CLAUDE.md`/`AGENTS.md` de agente. `instalar_regras_agentes` é um normalizador
  sempre imposto:
  - `CLAUDE.md` de `~/.claude` e de cada perfil `~/.local/share/claude-contas/<perfil>` e `AGENTS.md` do Codex são **link relativo**
    para a fonte (vale de dentro do proot). O Claude deduplica pelo arquivo real: o perfil enxerga `~/.claude/CLAUDE.md` como
    CLAUDE.md de projeto do `$HOME` e mesmo assim lê a fonte uma vez só.
  - Kiro: `steering/agentes.md` é cópia gerada (`inclusion: always`; o Kiro ignora steering por link), com `soma:` no cabeçalho.
  - Texto escrito num desses arquivos fora do bloco (arquivo no lugar do link, cópia do Kiro editada, `AGENTS.override.md` do Codex,
    o antigo `steering/tt-terminais.md`) vai para a fonte, antes do bloco: só parágrafos que não estão nela nem no retrato da volta
    anterior (`~/.local/state/tt/agentes-fonte.anterior`, para o que foi apagado não voltar de uma cópia velha); `@caminho` relativo
    do Claude vira `@~/pasta/caminho`; cópia do original em `~/.local/state/tt/agentes-backup/`. Depois o link/cópia volta.
  - Claude lê o `AGENTS.md` de projeto também onde há `CLAUDE.md`: `pluginConfigs` de `cc-plugin-agents-md@builtin` e
    `agents-md@builtin` com `instructionFiles: "claude-md-and-agents-md"` no `settings.json` (imposto; o resto do JSON fica). Sem isso,
    nos perfis o `~/.claude/CLAUDE.md` (ancestral de todo projeto em `~`) desligava o `AGENTS.md` de projeto.
  - Travas `<perfil>.lock` paradas há mais de 10 min são apagadas (viva, o Claude a renova a cada poucos segundos); pasta que não
    tem nome de perfil não recebe nada. Só entra em IA que já existe.
  `instalar_ferramentas_agentes` também copia esta skill para `skills/tt-terminais/SKILL.md`,
  distribui os quatro recursos da `figma-cota` (fonte compartilhada e agentes) e liga o `aidlc-tt`. Testes:
  `tests/test_agentes_md.sh`.
- Quando roda: em **toda instalação/atualização** (`instalar_aqui`, que cada máquina faz sozinha ao ver versão nova) e **a cada ~5 min
  pelo vigia** (`reforcar_padrao` → `reforcar_agentes`), inclusive dentro dos proots do celular. `tt --reforcar-agentes` roda na hora.
- Para mudar uma regra: edite `agentes-regras-tt.md` (ou esta skill) no repositório, rode `make test` e publique; o vigia de cada
  máquina espalha a nova versão sozinho.

## Agente avisa o usuário

Um agente rodando num painel do tt avisa o usuário assim:

```bash
tt --notificar-daqui "XPerformance: 12/13 respostas colhidas, falta a Q6" # imprime "notificado" ou "vendo"
tt --notificar-daqui "Preciso da sua aprovação para o push" --sempre      # avisa mesmo se ele estiver olhando
```

- Quando usar: ao pedir algo que bloqueia o trabalho (aprovação, resposta, login), ao dar um retorno
  que ele espera, ao terminar uma rodada longa ou importante, ao falhar algo que exige ação dele.
  Não use para progresso miúdo; um aviso por marco.
- Foco: o `tt` olha os clientes tmux (`focus-events on`). Se algum cliente com foco mostra a sessão
  e a janela do agente (`$TMUX_PANE`), o usuário já está vendo: nada é enviado e sai `vendo`. Vale
  para vistas aninhadas (sessão aberta num painel do tt): o cliente de dentro só tem foco quando o
  painel de fora tem. Por isso o agente pode chamar sem medo de incomodar; o `tt` decide.
- Para onde vai: o **sininho 🔔** (texto `🤖 <sessão> · <texto>`): avisos e marcas de leitura sincronizam
  por P2P entre todas as máquinas cadastradas; o contador mostra todos os avisos vigentes ainda não lidos,
  de qualquer canal e idade. A união preserva a marca `.lida`, então uma cópia antiga não desfaz uma leitura.
  Criar/ler sincroniza logo; o vigia recupera máquinas que estavam offline. Até 30 avisos ativos ficam
  disponíveis; expiram conforme o tempo configurado (padrão 24 h). Mais a notificação do sistema onde houver
  (`notify-send`, Termux). Clicar no 🔔 abre a central; ⏎ num aviso de agente leva à máquina de origem e à
  sessão. Sem a faixa (`faixa_notif=0`, não há 🔔) segue o caminho antigo (tela dos clientes).
- Fora do tmux (sem `$TMUX_PANE`) vira um `tt --notificar` comum. Notificação de outra máquina
  fica na faixa daquela máquina.

## Figma e login do Kiro

A instalação e `tt --reforcar-agentes` distribuem a skill **figma-cota completa**: `SKILL.md`,
`scripts/figma_rest.py`, `scripts/figma_oauth_retorno.py` e `references/acesso-autenticacao.md`.
Fonte instalada: `~/.agents/skills/figma-cota/`, com cópias para os agentes existentes (Claude,
Codex e Kiro; perfis Claude compartilham skills). O vigia reforça a cada ~5 min, inclusive nos
proots que já têm tt. Compara antes de gravar, preserva links/arquivos extras e não replica credenciais.

Antes de consultar Figma, leia a skill. Receba o link do frame, resolva chave/nó e procure no cache
REST; MCP fica para o detalhe necessário. `uso` é contagem local, não saldo oficial. Nunca use
MCP para procurar páginas inteiras nem trate sonda de versão como gratuita (ela é Tier 1).

**Distinga os três fluxos de acesso:**
- Login do Kiro (Organização): em CLI 2.32.0, `kiro-cli login --use-device-flow` funcionou em
  `tt --pty`, evitando o callback local recusado. Isso não autentica o Figma.
- OAuth do MCP Figma: o Kiro mostra a URL nativa em `/mcp`. Mantenha a sessão aberta; URL de
  autorização não equivale a uma entrada nativa para colar o callback. Não use Claude como ponte.
- Token REST: usado só pelo script e pela conta autorizada, nunca impresso nem transportado pelo tt.

**Navegador fora do WSL:** `figma_oauth_retorno.py`, rodando no WSL, aceita a URL final em campo
oculto e a entrega ao receptor original, conferindo state/host/porta/caminho. Não troca token,
não segue redirect e não depende de outro modelo. Prepare a entrada antes de autorizar: o Figma
documenta apenas **30 s de validade do código após emissão**. Não passe códigos pelo chat nem
os registre em tarefas/Git. A tentativa pode aguardar minutos; a sessão autenticada é outra coisa.
O ensaio Mac → WSL confirmou o MCP carregado e, após reinício, carregamento em 2,46 s sem novo OAuth.
A entrega bem-sucedida foi imediata e assistida por observador temporário de clipboard; não
confunda isso com nova função nativa do Kiro. Detalhes e limites estão na referência da skill.

Teste de código/fluxo: `tests/test_figma_cota.sh`. Pacote, reparo, idempotência e proot:
`tests/test_figma_instalacao.sh`. Nenhum desses testes consome cota de leitura do Figma.

## Terminal interativo para agentes (`tt --pty`)

O Bash de um agente não tem tty (`tty` diz "not a tty"): `sudo`, `ssh`, `vim`, instaladores e qualquer "Password:" ficam fora de
alcance. `tt --pty` dá a ele um terminal de verdade, que é só uma sessão tmux `ia-pty-NOME` (igual no Linux e no macOS):

```bash
tt --pty abrir deploy [PASTA]         # cria (ou reaproveita) e imprime ia-pty-deploy
tt --pty enviar deploy 'sudo -v'      # digita o texto literal + Enter (--sem-enter para só digitar)
tt --pty esperar deploy 'assword' 20  # espera o egrep aparecer na tela: 0 achou, 1 acabou o tempo
tt --pty ler deploy 40                # a tela (últimas 40 linhas, sem linhas vazias no fim)
tt --pty tecla deploy C-c             # teclas do tmux (C-c, Enter, Up, y…)
tt --pty entrar deploy                # leva o CLIENTE do usuário à sessão (switch-client dentro do tmux; attach fora)
tt --pty fechar deploy                # encerra; tt --pty listar mostra as abertas
```

- NOME é opcional (`padrao`). A sessão aparece na central como as outras, e o usuário pode entrar a qualquer hora.
- **Senha: o agente nunca a digita.** Ao ver `Password:`: `tt --notificar-daqui "preciso da senha do sudo" --sempre` e pedir
  ao usuário `tt --pty entrar NOME`; ele digita e volta com Ctrl-b d. Depois o agente segue com `esperar`/`ler`.
  Para o sudo, a saída durável é a regra `NOPASSWD` da pendência `sudo-sem-senha` (`tt --pedir-sudo sudo-sem-senha`), criada
  uma vez por esse caminho. No macOS o sudo guarda o tíquete por terminal (`tty_tickets`): um `sudo -v` do usuário em outro
  terminal não vale para o do agente.
- `attach` de dentro do tmux dá "sessions should be nested with care": use `entrar` (que escolhe `switch-client`).
- Código: `pty_agente` no `tt`; teste `tests/test_pty_agentes.sh`.

## Perguntas do AI-DLC no painel de tarefas (`aidlc-tt`)

Em vez de mandar as perguntas de um estágio do AI-DLC por chat ou e-mail, publique a bateria na
descrição de uma tarefa (ou subtarefa) do tt; o usuário abre com `Ctrl+E`, responde e salva.

```bash
aidlc-tt publicar caminho/requirements-questions.md ID   # ID da tarefa/subtarefa (1ª coluna de tt --tarefas-lista)
aidlc-tt estado   caminho/requirements-questions.md      # o que falta, sem gravar
aidlc-tt colher   caminho/requirements-questions.md      # grava no .md e conclui a tarefa quando tudo estiver respondido
```

- Formato do `.md`: `## Question N`, opções `A) ...`, `Por quê: ...` opcional e `[Answer]:`.
- Na descrição: 1ª linha `aidlc: <caminho absoluto>` (a ligação); anotações livres no topo
  (a descrição anterior vira anotação, nada se perde); cada pergunta em `== QN · texto` com as
  opções e sua linha `[Answer]:` (resposta pode continuar nas linhas seguintes até uma em branco).
- `colher`: resposta só no tt vai ao `.md`; só no `.md` volta ao tt; complemento (um lado começa
  com o outro) vale o mais completo; diferentes de verdade aparecem como conflito e nada muda.
  Letra inexistente e `Other` sem texto não são gravados. Sem letra, grava como texto livre e avisa.
- Grava só pela CLI do tt (`--tarefa-desc-prompt` com um "editor" que copia o texto pronto);
  `TT=caminho` troca o executável (testes). Teste: `tests/test_aidlc_tt.sh`.
- Fluxo sugerido: publicar, `tt --notificar-daqui "Perguntas do AI-DLC prontas na tarefa X"`,
  esperar o usuário dizer que respondeu, `colher`, seguir o estágio.

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

1. **Descobrir a máquina alvo**: `tt --maquinas` (rótulo → `usuario@host`). Ex.: `usuario@celular-xyz  celular`.
2. **Lançar o agente lá, numa sessão tmux nomeada** (headless, destacada):
   ```bash
   # a partir de qualquer máquina do mesh, para o rótulo "celular":
   dest=$(tt --maquinas | awk '$2=="celular"{print $1}')
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
     `tt --trazer celular:~/resultado.md .` (tar+ssh, chega na pasta de recebidos; nunca sobrescreve).
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

Situação real: uma sessão Kiro CLI numa máquina precisava entender como o celular (rótulo `celular`) usa o
**Shizuku** para coordenar o **adb** numa depuração **sem Wi-Fi** (adb por USB/par local), e isso só
podia ser investigado de dentro do próprio aparelho — ainda por cima com o agente rodando dentro do
**Debian via proot**, que não enxerga o adb do Android diretamente. Em vez de tentar operar o celular
por ponte de tela, a sessão lançou um agente no celular para investigar localmente e relatar:

```bash
# 1) achar o celular no mesh
dest=$(tt --maquinas | awk '$2=="celular"{print $1}')

# 2) lançar um agente no celular, numa sessão nomeada, com o prompt da investigação.
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
#    ou puxe voce mesmo:  tt --trazer celular:~/resultado-adb.md .
```

Por que isto é melhor do que operar o celular remotamente: o agente no celular executa `rish`/
`shizuku`, `pm`, `adb` e inspeciona o lado Android **de dentro do aparelho**, com os privilegios que
o Shizuku concede, sem depender de o adb estar exposto na rede; e devolve so a conclusao (um arquivo)
pela conexao do mesh. O agente de origem continua livre para outra frente enquanto isso. O mapa
completo do aparelho (camadas, shell do sistema, Tasker, Wi-Fi, tela) está na skill `celular-android`.

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
- **Trocar a conta principal ou logar uma conta em várias máquinas**: `ia-login --principal CONTA --plano` e depois
  `ia-login --principal CONTA` (o dono abre o link e cola o código). Com um celular logado na conta e o pedido do dono,
  o agente faz o ciclo pelo navegador do celular (skill `celular-android`, seção 14). Prova: o plano diz "Nada a fazer".
- **Tirar uma conta de IA de todas as máquinas**: passo a passo na skill `rodizio-de-contas` ("Tirar uma conta de
  todas as máquinas"): trocar a principal antes, esquecer no cadastro (o tombstone `-` fica), remover os perfis,
  conferir credenciais e atalhos, e lembrar o dono de **revogar o token** em claude.ai (logout local não revoga).

## Malha de máquinas (sem ilhas)
`malha_completar` (vigia a cada `TT_T_MALHA`=900 s, e no fim do `cadastrar`): cada máquina lê `--malha-lista` das outras
(linhas `EU host usuário rótulo explícito porta`, `M host usuário rótulo` e `S estado epoch rótulo`), aprende as que faltam
(só as provadas: `tailnet_conhece` + `malha_provar`, que confere o `nome=` de lá e tenta a porta 8022), corrige rótulo de quem
anuncia `nome=` explícito, aplica estados (`estado_aplicar`, o epoch mais novo vence; `descadastrar` grava `removida` e propaga),
apresenta-se com o IP de origem que a outra vê (`meu_endereco_em`; nunca `meu_host`, que no Termux é "localhost") e tenta consertar
as que não conectam (endereço alternativo que as outras usam; `reparar` se for chave). `malha_estado` (`tt --malha`) mostra quem
alcança quem; `malha_vigia` avisa na barra se a ilha persistir 2 voltas. Rastros em `~/.cache/tt-malha.log`.

**sshd garantido (v1.15.2):** `sshd_garantir` (vigia a cada 300 s por `--sshd-garantir --vigia`, só com outras máquinas
cadastradas; `tt --sshd-garantir` na hora; `sshd_garantir=0` desliga): algo escutando na 22 (8022 no Termux) → nada; com
`sudo -n`, `systemctl enable --now ssh` (ou `service ssh start` sem systemd); senão `sshd_usuario`, um sshd sem root na
8022 (só chave, `UsePAM no`, chave de host e config em `~/.local/state/tt/sshd/`, log `garantir.log`); sem o programa,
pendência essencial `sshd` (openssh-server). A `--malha-lista` anuncia a porta real (`sshd_porta`) e o conserto da malha,
com `porta-fechada`, tenta a 8022 no mesmo host (`malha_provar` grava o `~/.ssh/config`). O `tt --checar` tem a linha
`sshd`. Testes trocam as portas: `TT_SSHD_PORTA`, `TT_SSHD_PORTA_SISTEMA`, `TT_SSHD_SEM_SUDO` (`tests/test_sshd_malha.sh`).
