# Recuperação de telas e integridade de anexos

Revisão de 23–24/10/2026. Registro da demanda: **fube34**, código `1cf21ff1ed29`.

## Quando uma conexão falha

O quadro remoto antigo é substituído por uma tela local. Ela informa o motivo e oferece:

| Entrada | Resultado |
| --- | --- |
| `R` ou Enter; clique em Reconectar | Uma nova tentativa, com prazo próprio |
| `V`, `Q`, Esc ou Ctrl+C; clique em Central | Abre a central local |
| `N`; clique em Nova sessão | Cria uma sessão no destino e conecta a ela |
| `Ctrl+B`, depois Esc | Escape local, inclusive durante uma tentativa de conexão |
| Menu ⋯ do painel → Recuperar tela | A mesma recuperação do atalho |
| `tt --recuperar-tela CLIENTE` | A mesma recuperação pela CLI; CLIENTE é o tty do cliente tmux |

Não é necessário apertar Enter para limpar o quadro corrompido. A tela de recuperação desliga
o eco, normaliza os modos do terminal e consome setas, pacotes de mouse e colagens delimitadas
sem imprimi-los ou transformá-los em comandos. O tamanho acompanha o terminal.

Uma tentativa tem **20 segundos**, contando a resolução da identidade da sessão, SSH e chegada
da primeira saída após o marcador do destino. Quando o destino está mudo, há até três
retentativas de resolução, com esperas de 2, 4 e 8 segundos, dentro desse mesmo prazo;
Esc e Ctrl+B Esc continuam disponíveis durante toda a espera. `TT_T_RECONEXAO` permite ajustar esse prazo entre
mais de zero e 120 segundos. O prazo deixa de valer após a conexão: uma sessão ociosa pode ficar
aberta indefinidamente. Banners anteriores ao marcador não liberam a digitação.

Esc cancela a tentativa e mostra a recuperação. Ctrl+B Esc cancela e abre a central diretamente.
Fechar a central volta à tela de recuperação. Depois das retentativas limitadas, a reconexão depende de escolha explícita; não há laço
infinito contra uma máquina indisponível. A criação por N também é supervisionada e limpa
toda a identidade antiga da ponte antes de conectar. Se a criação perder a resposta ou for
cancelada, confira a central: a sessão pode já existir no destino. O tt não repete a criação
automaticamente.

O escape fecha a superfície modal que ocupa aquela tela e cancela o pedido de navegação pendente.
As sessões tmux de trabalho e o processo do aerc são preservados. A central usa o funcionamento
local do tt; a recuperação não espera uma consulta SSH antes de abri-la.

### Limites e atualização

O atalho depende de o servidor tmux local estar respondendo. Ele não recupera um processo do
emulador de terminal ou um servidor tmux inteiramente travado. Nessas situações, um terminal
separado ainda é necessário para diagnosticar o processo.

Uma ponte já em execução mantém o código Bash que carregou. A instalação recarrega o atalho e
os ganchos sem matar as sessões; a nova espera da ponte passa a valer quando seu processo for
iniciado novamente. A ponte pré-carregada, depois de uma desconexão, também entra nessa espera.
Não é necessário reiniciar o Mac para carregar os novos atalhos.
Vistas de e-mail abertas antes da atualização recebem a identificação de dono ao serem fechadas
e reabertas; a guarda de ciclos também atende as vistas antigas.

## Por que o e-mail podia mostrar a própria janela

O e-mail persistente roda na sessão oculta `_tt-email`. A janela sobreposta contém outro cliente
tmux anexado a ela. Se esse cliente passar a mostrar a sessão que contém a própria janela, surge
uma recursão de desenho e tamanho.

As proteções são complementares:

1. Cada vista nova do e-mail identifica seu dono por **tty e PID**. Navegação do tt, barra e
   botões que trocam de sessão agem nessa tela externa. Um tty reutilizado por outro processo
   não passa na validação.
2. Uma troca nativa que contorne o tt aciona o gancho do tmux: primeiro `ignore-size`, depois
   retorno para `_tt-email`. Enquanto isso a vista não pode reduzir sucessivamente a janela.
3. O helper verifica a sessão daquele cliente com `list-clients`, via `do_cliente`. O parâmetro
   `-c` de `display-message` sozinho não define o contexto dos formatos de sessão. Nos tmux que
   não completam a troca dentro do gancho, o helper tenta o comando externo; se falhar, desanexa
   somente a vista. Não registra um retorno fictício nem encerra o aerc.
4. A detecção de ciclos gerais percorre a relação pai/filho dos processos. Um shell entre o
   painel e o cliente tmux não esconde a relação. Ao impedir um ciclo, só a vista solicitante sai.

A partida do aerc também tem uma checagem limitada: durante até dois segundos, uma sessão recém
criada que ainda aparece como `env`, `bash`, `sh` ou `zsh` pode completar o início. Um aerc já
aberto é reconhecido imediatamente. Isso evita recriações por confundir o lançador com um
cliente que terminou.

## Salvar e retomar anexos

`S` no aerc continua salvando o anexo selecionado. O tt primeiro separa a entrada em um lote
exclusivo, em `~/.cache/tt-anexos/pendente-XXXXXXXX/arquivos`. Arquivos ocultos e nomes com espaços,
acentos ou quebras de linha são conservados. Lotes diferentes não dependem do segundo do relógio.

Para um destino local, cada arquivo passa por cópia completa, flush e confirmação antes de a
origem ser removida. O nome é publicado sem substituir um arquivo ou link já existente; colisões
ganham ` (2)`, ` (3)` etc. Em sistemas com hardlinks, a publicação do temporário é atômica.
Em FAT/exFAT e compartilhamentos sem hardlinks, há criação exclusiva e cópia confirmada: o nome
pode aparecer enquanto a cópia termina, mas a origem continua preservada até a conclusão.

Disco cheio, permissão recusada, destino inválido, origem alterada durante a cópia ou cancelamento
deixam os anexos não concluídos no lote. Só diretórios vazios são retirados. A saída mostra o
caminho e um comando pronto para retomar:

```sh
tt --anexo-salvar ~/.cache/tt-anexos/pendente-XXXXXXXX/arquivos
```

Esse comando aceita somente lotes próprios do tt, sem diretórios arbitrários ou links simbólicos.
Na retomada, os arquivos já concluídos não são copiados novamente. Um desligamento exatamente
entre a publicação e a retirada da origem pode deixar as duas cópias; nesse caso a prioridade é
preservar o conteúdo, e a retomada pode produzir um nome numerado.

Na transferência para outra máquina, a tarefa de cópia continua em segundo plano e seu andamento
aparece na barra. Iniciar a tarefa não comprova entrega. O lote local permanece disponível, e não
há exclusão automática apenas pela idade. Confira o resultado da transferência antes de remover
manualmente um lote já entregue. Cancelar a seleção de anexos ou de máquina também preserva o lote.

## Conteúdo enviado por e-mail

O caminho Microsoft converte a mensagem MIME para o corpo da API. Um anexo `message/rfc822`
é uma árvore de mensagem, e `get_payload(decode=True)` pode retornar `None`. Tratar esse retorno
como bytes vazios enviava um `.eml` vazio. Agora a mensagem anexada é serializada integralmente,
com cabeçalhos, corpo e seus próprios anexos; seus bytes entram no limite de tamanho existente.

O envio pela CLI constrói `.eml` como mensagem MIME, sem a codificação base64 inválida nesse
tipo. Imagens relacionadas ao HTML conservam `Content-ID` e a marca inline; a alternativa de
texto não vira um anexo extra. Multipart anexado sem formato suportado e `message/rfc822` com
codificação de transporte inválida produzem erro explícito antes do envio, em vez de anexos vazios.

Esta correção não remove o limite de tamanho da API Microsoft nem acrescenta upload de anexos
grandes. Nenhuma mensagem real precisa ser enviada para executar os testes.

## Arquitetura e diagnóstico

Uma regressão adicional da suíte revelou que a voz normalizava `_interna` para `interna` antes
de recusar sessões reservadas. A busca por título podia então encontrar uma sessão de trabalho
cujo título padrão era um hostname terminado em `.internal`. `sessao_resolver` agora recusa o
nome reservado antes da normalização. `test_voz_plano.sh` fixa esse título na fixture para
verificar a proteção em qualquer máquina, sem depender do hostname de quem executa o teste.

- `tela-recuperar.py`: terminal local sem eco, leitura das ações, PTY exclusivo por tentativa,
  propagação de tamanho e encerramento somente do grupo de processos daquela tentativa.
- `ponte_tentar`, `ponte`, `ponte_esperar`: resolução de identidade, transporte e estado de falha.
- `recuperar_tela`: escape local; valida PID e token de `@tt_tentativa` antes de cancelar o supervisor.
- `cliente_de_fora`, `contem_cliente`, `arestas_paineis`, `guarda_aninhado`: dono e prevenção de ciclos.
- `anexos_lote`, `anexo_salvar`, `anexos_enviar`: separação e retomada dos lotes.
- `email-tt.py`: publicação local, conversão MIME e anexos Microsoft.

No Mac, a restauração do terminal usa `TCSANOW` e limpeza da fila de entrada: esperar a saída
escoar com `TCSAFLUSH` pode prender a própria saída quando o PTY está sem leitor. O EOF do PTY
também pode anteceder brevemente o estado de saída do filho; a coleta tem espera limitada.
As escritas também são não bloqueantes: prazo e sinal de cancelamento continuam sendo verificados
quando a saída não é consumida ou quando o transporte deixa de ler a digitação. Até a tentativa de
redesenhar o terminal na saída tem prazo, para a limpeza não virar outro bloqueio.

No tmux 3.5a, o controle 0x1f em saída formatada vira a sequência literal `\037`.
As leituras novas de id/início/UUID, pid/terminal e painel/modal/supervisor usam `|`,
que preserva os campos vazios e não ocorre nesses valores restritos. O tmux 3.6 e o 3.8
não exibiram essa diferença; os testes no Dell 3.5a cobrem a compatibilidade mais antiga.

Os eventos de conexão e guarda ficam em `~/.cache/tt-vigia.log` pela função `log_ponte` e pelas
guardas. Para identificar as vistas, sem depender do contexto de `display-message`:

```sh
tmux list-clients -F '#{client_name} #{client_pid} #{session_name} #{client_termname} #{client_flags}'
tmux list-panes -a -F '#{session_name} #{pane_id} #{pane_pid} #{@tt_tentativa}'
tmux show-hooks -g
```

Nunca execute testes contra o socket ou as contas do usuário. A suíte cria HOME, runtime, sockets,
contas fictícias, arquivos e transportes isolados. Para reproduzir a cobertura principal:

```sh
TT_TESTES='^(test_tela_recuperar|test_recuperar_tela|test_email_recursao|test_anexos_integridade|test_email_aerc_unico|test_email_sessao|test_email_enviar|test_email_graph_envio|test_portabilidade)\.sh$' tests/run.sh
tests/run.sh
```

| Teste | Evidência |
| --- | --- |
| `test_tela_recuperar` | PTYs reais; eco, limpeza, mouse, Esc fragmentado, colagem, prazo, inatividade e término do filho |
| `test_ponte_retentativa` | Rede que volta, limite de tentativas, alvo ausente e criação explícita sem repetir resultado incerto |
| `test_recuperar_tela` | Ponte simulada; Ctrl+B Esc, CLI e menu; central local e sessões preservadas |
| `test_email_recursao` | Modal real quando disponível; navegação pela tela dona, troca nativa, tamanho, PID reciclado e shell intermediário |
| `test_anexos_integridade` | Falha parcial, ENOSPC, retomada, colisões, nomes especiais, links, origem alterada, destino sem hardlinks, `.eml` e inline |
| `test_email_aerc_unico` / `test_email_sessao` | Reuso da sessão, processo e layout; abertura real com conta Maildir fictícia |
| `test_email_enviar` / `test_email_graph_envio` | Rotas de envio existentes, sem destinatários reais |
| `test_portabilidade` | Regras macOS/Linux e comandos que não podem depender de `/proc`, Bash 3.2 ou ferramentas GNU fora do ambiente preparado |

O histórico da tarefa registra as rodadas efetivamente executadas e seus resultados. No Mac de
origem, a auditoria e os logs estão em `~/.local/state/tt/revisao-estabilidade/20261023-154544/`.

## Validação da entrega de 24/10/2026

A primeira suíte ampla executou **204 scripts em 2.121 segundos** no Mac. Houve cinco falhas:
preparação do aerc simulado, pacote/manifestos das fixtures, resolução de sessão pela voz e
histórico da cópia. As correções e a reexecução dos dez testes envolvidos passaram; a cópia
passou na reexecução isolada, sem alteração no seu comportamento. A suíte ampla inicial não
é apresentada como uma execução integral verde da revisão final.

Depois da integração com as mudanças publicadas em 24/10, foram conferidos novamente o envio
SMTP/Graph, anexos, eventos do e-mail, retentativas, voz, pacote, versão, partida rápida,
proteção do e-mail, transporte e portabilidade. A comparação de identidade no teste de nova
sessão considera o número da sessão **e o início do servidor**, pois um tmux recém-iniciado
pode reutilizar o mesmo número. A tecla N é testada depois do desenho da recuperação, sem
confundir a imagem antiga que reaparece brevemente ao fechar um popup com um leitor pronto.

As últimas rodadas no **macOS / tmux 3.8** e no **Linux / tmux 3.5a** passaram. Há ainda provas
anteriores no Linux com tmux 3.6. O helper tem 12 testes com PTYs; o módulo de anexos tem nove
testes de integridade e MIME, além das rotas de salvar/retomar/cancelar exercitadas pelo shell.
Nenhum desses testes usa conta de e-mail, socket tmux ou sessão de trabalho do usuário.

Evidências na pasta de auditoria acima:

| Arquivo | Conteúdo |
| --- | --- |
| `suite-completa.log`, `retestes-finais.log` | Rodada ampla inicial e correções conferidas |
| `integracao-upstream.log` | Sete testes de anexos, envio, eventos, retentativas e portabilidade |
| `integracao-telas.log`, `integracao-final.log` | Telas, voz, pacote, versão, partida rápida e ajuste da identidade no teste |
| `mac-compatibilidade.log`, `mac-entrega.log` | Verificações finais no Mac |
| `linux-final.log`, `linux-compatibilidade.log`, `linux-entrega.log` | Diagnóstico do tmux 3.5a e verificações finais aprovadas |

O registro `tt --tarefa-historico fube34` informa o commit entregue, instalação e sincronização.
As cópias de segurança guardam o pacote de programa, sem incluir credenciais ou substituir
configurações. Para reverter uma entrega publicada, reverta o commit e gere uma versão nova:
a proteção de atualização do tt recusa simplesmente instalar um número de versão mais antigo.
