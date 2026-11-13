# Os Doze Fatores

Adam Wiggins e colaboradores · tradução para o português do Brasil mantida pela comunidade

*The Twelve-Factor App* (12factor.net/pt_br): doze práticas para construir aplicações que rodam como serviço.
Texto do repositório github.com/heroku/12factor, distribuído sob a licença MIT (nota no fim). As figuras do
original não acompanham esta cópia.

## Introdução
Na era moderna, software é comumente entregue como um serviço: denominados *web apps*, ou *software-como-serviço*. A aplicação doze-fatores é uma metodologia para construir softwares-como-serviço que:

* Usam formatos **declarativos** para automatizar a configuração inicial, minimizar tempo e custo para novos desenvolvedores participarem do projeto;
* Tem um **contrato claro** com o sistema operacional que o suporta, oferecendo **portabilidade máxima** entre ambientes que o executem;
* São adequados para **implantação** em modernas **plataformas em nuvem**, evitando a necessidade por servidores e administração do sistema;
* **Minimizam a divergência** entre desenvolvimento e produção, permitindo a **implantação contínua** para máxima agilidade;
* E podem **escalar** sem significativas mudanças em ferramentas, arquiteturas, ou práticas de desenvolvimento.

A metodologia doze-fatores pode ser aplicada a aplicações escritas em qualquer linguagem de programação, e que utilizem qualquer combinação de serviços de suportes (banco de dados, filas, cache de memória, etc).

## Quem deve ler este documento?
Qualquer desenvolvedor que esta construindo aplicações que rodam como serviço. Engenheiros de Operações que implantam ou administram tais aplicações.

## Experiência
Os contribuidores deste documento estão diretamente envolvidos no desenvolvimento e implantação de centenas de aplicações, e indiretamente testemunhando o desenvolvimento, operação e escalada de centenas de milhares de aplicações através de seu trabalho na plataforma [Heroku](http://www.heroku.com/).

Este documento sintetiza toda nossa experiência e observação em uma variedade de aplicações que operam como software-como-serviço. Isto é a triangulação de práticas ideais ao desenvolvimento de software, com uma atenção particular a respeito das dinâmicas de crescimento orgânico de uma aplicação ao longo do tempo, a dinâmica de colaboração entre desenvolvedores trabalhando em uma base de código, e evitando os [custos de erosão de software](http://blog.heroku.com/archives/2011/6/28/the_new_heroku_4_erosion_resistance_explicit_contracts/)

Nossa motivação é aumentar a consciência de alguns problemas sistêmicos que temos visto no desenvolvimento de aplicações modernas, prover um vocabulário comum para discussão destes, e oferecer um amplo conjunto de soluções conceituais para esses problemas com a terminologia que os acompanha. O formato é inspirado nos livros de Martin Fowler *[Padrões de Arquitetura de Aplicações Enterprise](http://books.google.com/books/about/Patterns_of_enterprise_application_archi.html?id=FyWZt5DdvFkC)* e *[Refatorando](http://books.google.com/books/about/Refactoring.html?id=1MsETFPD3I0C)*.

## I. Base de Código
### Uma base de código com rastreamento utilizando controle de revisão, muitos deploys

Uma aplicação 12 fatores é sempre rastreada em um sistema de controle de versão, como [Git](http://git-scm.com/), [Mercurial](https://www.mercurial-scm.org/), ou [Subversion](http://subversion.apache.org/). Uma cópia da base de dados do rastreamento de revisões é conhecido como *repositório de código*, normalmente abreviado como *repositório* ou *repo*.

Uma *base de código* é um único repo (em um sistema de controle de versão centralizado como Subversion), ou uma série de repositórios que compartilham um registro raiz.


Existe sempre uma correlação um-para-um entre a base de código e a aplicação:

* Se existem várias bases de código, isto não é uma app -- é um sistema distribuído. Cada componente do sistema é uma app, e cada uma pode  individualmente ser compatível com os 12 fatores.
* Múltiplas apps compartilhando uma base de código é uma violação dos 12 fatores. A solução aqui é dividir o código compartilhado entre bibliotecas que podem ser incluídas através do [gerenciador de dependências](/dependencies).

Existe apenas uma base de código por aplicação, mas existirão vários deploys da mesma. Um *deploy* (ou implantação) é uma instância executando a aplicação. Isto é tipicamente um local de produção, e um ou mais locais de testes. Adicionalmente, todo desenvolvedor tem uma cópia da aplicação rodando em seu ambiente local de desenvolvimento, cada um desses pode ser qualificado como um deploy.

A base de código é a mesma através de todos os deploys, entretanto diferentes versões podem estar ativas em cada deploy. Por exemplo, um desenvolvedor tem alguns registros ainda não implantados no ambiente de teste, o ambiente de teste ainda tem registros não implantados em produção. Mas todos esses ambientes compartilham a mesma base de código, tornando-os identificáveis ​​como diferentes deploys do mesmo app.

## II. Dependências
### Declare e isole explicitamente as dependências

A maioria das linguagens de programação oferecem um sistema de pacotes para a distribuição de bibliotecas de apoio, como o [CPAN](http://www.cpan.org/) para Perl ou [Rubygems](http://rubygems.org/) para Ruby. Bibliotecas instaladas por meio de um sistema de pacotes podem ser instaladas em todo o sistema (conhecidas como "site packages") ou com escopo dentro do diretório contendo a aplicação (conhecidas como "vendoring" ou "building").

**Uma aplicação doze-fatores nunca confia na existência implícita de pacotes em todo o sistema.** Ela declara todas as dependências, completa e exatamente, por meio de um manifesto de *declaração de dependência*. Além disso, ela usa uma ferramenta de *isolamento de dependência* durante a execução para garantir que não há dependências implícitas "vazamento" a partir do sistema circundante. A completa e explícita especificação de dependências é aplicada de maneira uniforme tanto para produção quanto para desenvolvimento.

Por exemplo, [Bundler](https://bundler.io/) para Ruby oferece o formato de manifesto `Gemfile` para declaração de dependência e `bundle exec` para isolamento das mesmas. Em Python existem duas ferramentas separadas para estas etapas -- [Pip](http://www.pip-installer.org/en/latest/) é utilizado para declaração e [Virtualenv](http://www.virtualenv.org/en/latest/) para isolamento. Mesmo C tem [Autoconf](http://www.gnu.org/s/autoconf/) para declaração de dependência, e vinculação estática pode fornecer o isolamento. Não importa qual o conjunto de ferramentas, declaração de dependência e isolamento devem ser sempre usados juntos -- apenas um ou o outro não é suficiente para satisfazer doze-fatores.

Um dos beneficios da declaração de dependência explícita é que simplifica a configuração  da aplicação para novos desenvolvedores. O novo desenvolvedor pode verificar a base de código do aplicativo em sua máquina de desenvolvimento, exigindo apenas runtime da linguagem e gerenciador de dependência instalado como pré-requisitos. Eles serão capazes de configurar tudo o que é necessário para rodar o código da aplicação com um determinístico *comando de build*. Por exemplo, o comando de build para Ruby/Bundler é `bundle install`, enquanto que para Clojure/[Leiningen](https://github.com/technomancy/leiningen#readme) é `lein deps`.

Aplicações doze-fatores também não contam com a existência implícita de todas as ferramentas do sistema. Exemplos incluem executar algum comando externo como do ImageMagick ou `curl`. Embora possam existir essas ferramentas em muitos ou mesmo na maioria dos sistemas, não há garantia de que eles vão existir em todos os sistemas em que a aplicação pode rodar no futuro, ou se a versão encontrada em um futuro sistema será compatível com a aplicação. Se a aplicação precisa executar alguma ferramenta do sistema, essa ferramenta deve ser vendorizada na aplicação.

## III. Configurações
### Armazene as configurações no ambiente

A *configuração* de uma aplicação é tudo o que é provável variar entre [deploys](./codebase) (homologação, produção, ambientes de desenvolvimento, etc). Isto inclui:

* Recursos para a base de dados, Memcached, e outros [serviços de apoio](./backing-services)
* Credenciais para serviços externos como Amazon S3 ou Twitter
* Valores por deploy como o nome canônico do host para o deploy

Aplicações às vezes armazenam as configurações no código como constantes. Isto é uma violação da doze-fatores, a qual exige uma **estrita separação entre configuração e código**. Configuração varia substancialmente entre deploys, código não.

A prova de fogo para saber se uma aplicação tem todas as configurações corretamente consignadas fora do código é saber se a base de código poderia ter seu código aberto ao público a qualquer momento, sem comprometer as credenciais.

Note que esta definição de "configuração" **não** inclui configuração interna da aplicação, como `config/routes.rb` em Rails, ou como [módulos de códigos são conectados](http://docs.spring.io/spring/docs/current/spring-framework-reference/html/beans.html) em [Spring](http://spring.io/). Este tipo de configuração não varia entre deploys, e por isso é melhor que seja feito no código.

Outra abordagem para configuração é o uso de arquivos de configuração que não são versionados no controle de versão, como `config/database.yml` em Rails. Isto é uma grande melhoria sobre o uso de constantes que são versionadas no repositório do código, mas ainda tem pontos fracos: é fácil de colocar por engano um arquivo de configuração no repositório; há uma tendência para que os arquivos de configuração sejam espelhados em diferentes lugares e diferentes formatos, tornando-se difícil de ver e gerenciar todas as configurações em um só lugar. Além disso estes formatos tendem a ser específicos da linguagem ou framework.

**A aplicação doze-fatores armazena configuração em *variáveis de ambiente*** (muitas vezes abreviadas para *env vars* ou *env*). Env vars são fáceis de mudar entre deploys sem alterar qualquer código; ao contrário de arquivos de configuração, há pouca chance de serem colocados acidentalmente no repositório do código; e ao contrário dos arquivos de configuração personalizados, ou outros mecanismos de configuração como Propriedades do Sistema Java, eles são por padrão agnósticos a linguagem e ao SO.

Outro aspecto do gerenciamento de configuração é o agrupamento. Às vezes, as aplicações incluem a configuração em grupos nomeados (muitas vezes chamados de ambientes) que remetem a deploys específicos, tais como os ambientes `development`, `test`, e `production` em Rails. Este método não escala de forma limpa: quanto mais deploys da aplicação são criados, novos nomes de ambiente são necessários, tais como `staging` ou `qa`. A medida que o projeto cresce ainda mais, desenvolvedores podem adicionar seus próprios ambientes especiais como `joes-staging`, resultando em uma explosão combinatória de configurações que torna o gerenciamento de deploys da aplicação muito frágil.

Em uma aplicação doze-fatores, env vars são controles granulares, cada um totalmente ortogonal às outras env vars. Elas nunca são agrupadas como "environments", mas em vez disso são gerenciadas independentemente para cada deploy. Este é um modelo que escala sem problemas à medida que o app naturalmente se expande em muitos deploys durante seu ciclo de vida.

## IV. Serviços de Apoio
### Trate serviços de apoio como recursos anexados

Um *serviço de apoio* é qualquer serviço que o app consuma via rede como parte de sua operação normal. Exemplos incluem armazenamentos de dados (como [MySQL](http://dev.mysql.com/) ou [CouchDB](http://couchdb.apache.org/)), sistemas de mensagens/filas (tais como [RabbitMQ](http://www.rabbitmq.com/) ou [Beanstalkd](https://beanstalkd.github.io)), serviços SMTP para emails externos (tais como [Postfix](http://www.postfix.org/)), e sistemas de cache (tais como [Memcached](http://memcached.org/)).

Serviços de apoio como o banco de dados são tradicionalmente gerenciados pelos mesmos administradores de sistema do servidor de deploy de tempo de execução do app. Adicionalmente à esses serviços localmente gerenciados, o app pode ter serviços providos e gerenciados por terceiros. Exemplos incluem serviços SMTP (tais como [Postmark](http://postmarkapp.com/)), serviços de colheita de métricas (tais como [New Relic](http://newrelic.com/) ou [Loggly](http://www.loggly.com/)), serviços de ativos binários (tais como [Amazon S3](http://aws.amazon.com/s3/)), e até serviços de consumidores acessíveis via API (tais como [Twitter](http://dev.twitter.com/), [Google Maps](https://developers.google.com/maps/), ou [Last.fm](http://www.last.fm/api)).

**O código para um app doze-fatores não faz distinção entre serviços locais e de terceiros.** Para o app, ambos são recursos anexados, acessíveis via uma URL ou outro localizador/credenciais na [config](./config). Um [deploy](./codebase) do app doze-fatores deve ser capaz de trocar um banco de dados MySQL por um gerenciado por terceiros (tais como [Amazon RDS](http://aws.amazon.com/rds/)) sem realizar quaisquer mudanças no código do app. Da mesma forma, um servidor local SMTP poderia ser trocado por um serviço de terceiros (tais como Postmark) sem as mudanças em código. Em ambos os casos, apenas o identificador de recurso precisa mudar.

Cada serviço de apoio distinto é um *recurso*. Por exemplo, um banco MySQL é um recurso; dois bancos MySQL (usados para sharding na camada da aplicação) qualificam como dois recursos distintos. O app doze-fatores trata tais bancos como *recursos anexados*, o que indica seu baixo acoplamento ao deploy que ele está anexado.

<img src="/images/attached-resources.png" class="full" alt="Um deploy de produção anexado a quatro serviços de apoio." />

Recursos podem ser anexados e desanexados a deploys à vontade. Por exemplo, se o banco de dados do app não está funcionando corretamente devido a um problema de hardware, o administrador do app pode subir um novo servidor de banco de dados restaurado de um backup recente. O atual banco de produção pode ser desanexado, e o novo banco anexado -- tudo sem nenhuma mudança no código.

## V. Construa, lance, execute
### Separe estritamente os estágios de construção e execução

Uma [base de código](./codebase) é transformada num deploy (de não-desenvolvimento) através de três estágios:

* O *estágio de construção* é uma transformação que converte um repositório de código em um pacote executável conhecido como *construção*. Usando uma versão do código de um commit especificado pelo processo de desenvolvimento, o estágio de construção obtém e fornece [dependências](./dependencies) e compila binários e ativos.
* O *estágio de lançamento* pega a construção produzida pelo estágio de construção e a combina com a atual [configuração](./config) do deploy. O *lançamento* resultante contém tanto a construção quanto a configuração e está pronta para execução imediata no ambiente de execução.
* O *estágio de execução* roda o app no ambiente de execução, através do início de alguns dos [processos](./processes) do app com um determinado lançamento.


**O app doze-fatores usa separação estrita entre os estágios de construção, lançamento e execução.** Por exemplo, é impossível alterar código em tempo de execução, já que não há meios de se propagar tais mudanças de volta ao estágio de construção.

Ferramentas para deploy tipicamente oferecem ferramentas de gestão de lançamento, mais notadamente a habilidade de se reverter à um lançamento prévio. Por exemplo, a ferramenta de deploy [Capistrano](https://github.com/capistrano/capistrano/wiki) armazena lançamentos em um subdiretório chamado `releases`, onde o lançamento atual é um link simbólico para o diretório de lançamento atual. Seu comando `rollback` torna fácil reverter para um lançamento prévio.

Cada lançamento deve sempre ter um identificador de lançamento único, tal qual o timestamp do lançamento (como `2011-04-06-20:32:17`) ou um número incremental (como `v100`). Lançamentos são livro-razões onde apenas se acrescenta informações, ou seja, uma vez criado o lançamento não pode ser alterado. Qualquer mudança deve gerar um novo lançamento.

Construções são iniciadas pelos desenvolvedores do app sempre que novos códigos entram no deploy. A execução de um executável, todavia, pode acontecer automaticamente em casos como o reinício do servidor, ou um processo travado sendo reiniciado pelo gerenciador de processos. Assim, no estágio de execução deve haver quanto menos partes móveis quanto possível, já que problemas que previnem um app de rodar pode causá-lo a travar no meio da noite quando não há desenvolvedores por perto. O estágio de construção pode ser mais complexo, já que os erros estão sempre à vista do desenvolvedor que está cuidando do deploy.

## VI. Processos
### Execute a aplicação como um ou mais processos que não armazenam estado

A aplicação é executada em um ambiente de execução como um ou mais *processos*.

No caso mais simples, o código é um script autônomo, o ambiente de execução é o laptop local de um desenvolvedor com o runtime da linguagem instalado, e o processo é iniciado pela linha de comando (por exemplo, `python my_script`). Na outra extremidade do espectro, o deploy em produção de uma aplicação sofisticada pode utilizar vários [tipos de processos, instanciado em zero ou mais processos em andamento](./concurrency).

**Processos doze-fatores são stateless(não armazenam estado) e [share-nothing](http://en.wikipedia.org/wiki/Shared_nothing_architecture).** Quaisquer dados que precise persistir deve ser armazenado em um serviço de apoio stateful(que armazena o seu estado), tipicamente uma base de dados.

O espaço de memória ou sistema de arquivos do processo pode ser usado como um breve, cache de transação única. Por exemplo, o download de um arquivo grande, operando sobre ele, e armazenando os resultados da operação no banco de dados. A aplicação doze-fatores nunca assume que qualquer coisa cacheada na memória ou no disco estará disponível em uma futura solicitação ou job -- com muitos processos de cada tipo rodando, as chances são altas de que uma futura solicitação será servida por um processo diferente. Mesmo quando rodando em apenas um processo, um restart (desencadeado pelo deploy de um código, mudança de configuração, ou o ambiente de execução realocando o processo para uma localização física diferente) geralmente vai acabar com todo o estado local (por exemplo, memória e sistema de arquivos).

Empacotadores de assets (como [Jammit](http://documentcloud.github.io/jammit/) ou [django-compressor](http://django-compressor.readthedocs.org/)) usa o sistema de arquivos como um cache para assets compilados. Uma aplicação doze-fatores prefere fazer isto compilando durante a [fase de build](./build-release-run), tal como o [Rails asset pipeline](http://guides.rubyonrails.org/asset_pipeline.html), do que em tempo de execução.

Alguns sistemas web dependem de ["sessões persistentes"](http://en.wikipedia.org/wiki/Load_balancing_%28computing%29#Persistence) -- ou seja, fazem cache dos dados da sessão do usuário na memória do processo da aplicação, esperando futuras requisições do mesmo visitante para serem encaminhadas para o mesmo processo. Sessões persistentes são uma violação do doze-fatores e nunca devem ser utilizadas ou invocadas. Dados do estado da sessão são bons candidatos para um datastore que oferece tempo de expiração, tal como [Memcached](http://memcached.org/) ou [Redis](http://redis.io/).

## VII. Vínculo de Portas
### Exporte serviços via vínculo de portas

Apps web as vezes são executadas dentro de container de servidor web. Por exemplo, apps PHP podem rodar como um módulo dentro do [Apache HTTPD](http://httpd.apache.org/), ou apps Java podem rodar dentro do [Tomcat](http://tomcat.apache.org/).

**O aplicativo doze-fatores é completamente auto-contido** e não depende de injeções de tempo de execução de um servidor web em um ambiente de execução para criar um serviço que defronte a web. O app web **exporta o HTTP como um serviço através da vínculação a uma porta**, e escuta as requisições que chegam na mesma.

Num ambiente de desenvolvimento local, o desenvolvedor visita a URL de um serviço como `http://localhost:5000/` para acessar o serviço exportado pelo seu app. Num deploy, uma camada de roteamento manipula as requisições de rotas vindas de um hostname público para os processos web atrelados às portas.

Isso é tipicamente implementado usando [declaração de dependências](./dependencies) para adicionar uma biblioteca de servidor ao app, tal como [Tornado](http://www.tornadoweb.org/) para Python, [Thin](http://code.macournoyer.com/thin/) para Ruby, ou [Jetty](http://www.eclipse.org/jetty/) para Java e outra linguagens baseadas na JVM. Isso acontece completamente no *espaço do usuário*, isso é, dentro do código do app. O contrato com o ambiente de execução é vincular a uma porta para servir requisições.

HTTP não é o único serviço que pode ser exportado via vínculo de portas. Quase todos os tipos de software servidores podem rodar via um processo vinculado a uma porta e aguardar as requisições chegar. Exemplos incluem [ejabberd](http://www.ejabberd.im/) (comunicando via [XMPP](http://xmpp.org/)), e [Redis](http://redis.io/) (comunicando via [protocolo Redis](http://redis.io/topics/protocol)).

Note que a abordagem de vincular portas significa que um app pode se tornar o [serviço de apoio](./backing-services) para um outro app, provendo a URL do app de apoio como um identificador de recurso na [configuração](./config) para o app consumidor.

## VIII. Concorrência
### Escale através do processo modelo

Qualquer programa de computador, uma vez executado, está representado por um ou mais processos. Aplicações web têm tomado uma variedade de formas de processo de execução. Por exemplo, processos PHP rodam como processos filhos do Apache, iniciados sob demanda conforme necessário por volume de requisições. Processos Java tomam o caminho inverso, com a JVM proporcionando um processo uber maciço que reserva um grande bloco de recursos do sistema (CPU e memória) na inicialização, com concorrência gerenciada internamente via threads. Em ambos os casos, o(s) processo(os) em execução são apenas minimamente visível para os desenvolvedores da aplicação.


**Na aplicação doze-fatores, processos são cidadãos de primeira classe.**  Processos na aplicação doze-fatores utilizam fortes sugestões do modelo de processos UNIX para execução de serviços daemon, o desenvolvedor pode arquitetar a aplicação dele para lidar com diversas cargas de trabalho, atribuindo a cada tipo de trabalho a um *tipo de processo*. Por exemplo, solicitações HTTP podem ser manipuladas para um processo web, e tarefas background de longa duração podem ser manipuladas por um processo trabalhador.

Isto não exclui processos individuais da manipulação de sua própria multiplexação interna, por threads dentro do runtime da VM, ou o modelo async/evented encontrado em ferramentas como [EventMachine](https://github.com/eventmachine/eventmachine), [Twisted](http://twistedmatrix.com/trac/), ou [Node.js](http://nodejs.org/). Mas uma VM individual pode aumentar (escala vertical), de modo que a aplicação deve ser capaz de abranger processos em execução em várias máquinas físicas.

O modelo de processo realmente brilha quando chega a hora de escalar. O [compartilhar-nada, natureza horizontal particionada de um processo da aplicação doze-fatores](./processes) significa que a adição de mais simultaneidade é uma operação simples e de confiança. A matriz de tipos de processo e número de processos de cada tipo é conhecida como o *processo de formação*.

Processos de uma app doze-fatores [nunca deveriam daemonizar](http://dustin.github.com/2010/02/28/running-processes.html) ou escrever arquivos PID. Em vez disso, confiar no gerente de processo do sistema operacional (como [systemd](https://www.freedesktop.org/wiki/Software/systemd/), um gerenciador de processos distribuídos em uma plataforma de nuvem, ou uma ferramenta como [Foreman](http://blog.daviddollar.org/2011/05/06/introducing-foreman.html) em desenvolvimento) para gerenciar [fluxos de saída](./logs), responder a processos travados, e lidar com reinícios e desligamentos iniciados pelo usuário.

## IX. Descartabilidade
### Maximize robustez com inicialização rápida e desligamento gracioso

**Os [processos](./processos) de um app doze-fatores são *descartáveis*, significando que podem ser iniciados ou parados a qualquer momento.** Isso facilita o escalonamento elástico, rápido deploy de [código](./codebase) ou mudanças de [configuração](./config), e robustez de deploys de produção.

Processos devem empenhar-se em **minimizar o tempo de inicialização**. Idealmente, um processo leva alguns segundos do tempo que o comando de inicialização é executado até o ponto que ele estará pronto para receber requisições ou tarefas. Períodos curtos de inicialização provém mais agilidade para o processo de [release](./build-release-run) e de escalonamento; e ele adiciona robustez, pois o gestor de processos pode mais facilmente mover processos para outras máquinas físicas quando necessário.

Processos **desligam-se graciosamente quando recebem um sinal [SIGTERM](http://en.wikipedia.org/wiki/SIGTERM)** do seu gestor de processos. Para um processo web, desligamento gracioso é alcançado quando cessa de escutar à porta de serviço (consequentemente recusando quaisquer requisições novas), permitindo qualquer requisição em andamento terminar, e então desligando. Implícito neste modelo é que as requisições HTTP são curtas (não mais que alguns poucos segundos), ou no caso de um longo _polling_, o cliente deve ser capaz de transparentemente tentar se reconectar quando a conexão for perdida.

Para um processo de trabalho (worker), desligamento gracioso é alcançado retornando a tarefa atual para  fila de trabalho. Por exemplo, no [RabbitMQ](http://www.rabbitmq.com/) o trabalhador pode enviar um [`NACK`](http://www.rabbitmq.com/amqp-0-9-1-quickref.html#basic.nack); no [Beanstalkd](https://beanstalkd.github.io), a tarefa é retornada para a fila automaticamente sempre que um trabalhador se desconecta. Sistemas baseados em trava como o [Delayed Job](https://github.com/collectiveidea/delayed_job#readme) precisam se certificar de soltar a trava no registro da tarefa. Implícito neste modelo é que todas as tarefas são [reentrantes](http://en.wikipedia.org/wiki/Reentrant_%28subroutine%29), o que tipicamente é atingindo envolvendo os resultados numa transação, ou tornando a operação [idempotente](http://en.wikipedia.org/wiki/Idempotence).

Processos também devem ser **robustos contra morte súbida**, no caso de uma falha de hardware. Ao passo que isso é muito menos comum que um desligamento via `SIGTERM`, isso ainda pode acontecer. Uma abordagem recomendada é usar um backend de filas robusto, como o Beanstalkd, que retorna tarefas à fila quando clientes desconectam ou esgotam o tempo de resposta. De qualquer forma, um app doze-fatores é arquitetado para lidar com terminações não esperadas e não graciosas.  [Crash-only design](http://lwn.net/Articles/191059/) leva este conceito à sua [conclusão lógica](http://docs.couchdb.org/en/latest/intro/overview.html).

## X. Paridade entre desenvolvimento e produção
### Mantenha o desenvolvimento, homologação e produção o mais similares possível

Historicamente, houveram lacunas substanciais entre desenvolvimento (um desenvolvedor editando código num [deploy](./codebase) local do app) e produção (um deploy acessado pelos usuários finais). Essas lacunas se manifestam em três áreas:

* **A lacuna do tempo:** Um desenvolvedor pode trabalhar em código que demora dias, semanas ou até meses para ir para produção.
* **A lacuna de pessoal:** Desenvolvedores escrevem código, engenheiros de operação fazem o deploy dele.
* **A lacuna de ferramentas:** Desenvolvedores podem estar usando um conjunto como Nginx, SQLite, e OS X, enquanto o app em produção usa Apache, MySQL, e Linux.

**O App doze-fatores é projetado para [implantação contínua](http://avc.com/2011/02/continuous-deployment/) deixando a lacuna entre desenvolvimento e produção pequena.** Olhando às três lacunas descritas acima:

* Diminua a lacuna de tempo: um desenvolvedor pode escrever código e ter o deploy feito em horas ou até mesmo minutos depois.
* Diminua a lacuna de pessoal: desenvolvedores que escrevem código estão proximamente envolvidos em realizar o deploy e acompanhar seu comportamento em produção.
* Diminua a lacuna de ferramentas: mantenha desenvolvimento e produção o mais similares possível.

Resumindo o acima em uma tabela:

<table>
  <tr>
    <th></th>
    <th>App tradicional</th>
    <th>App doze-fatores</th>
  </tr>
  <tr>
    <th>Tempo entre deploys</th>
    <td>Semanas</td>
    <td>Horas</td>
  </tr>
  <tr>
    <th>Autores de código vs deployers</th>
    <td>Pessoas diferentes</td>
    <td>Mesmas pessoas</td>
  </tr>
  <tr>
    <th>Ambientes de desenvolvimento vs produção</th>
    <td>Divergente</td>
    <td>O mais similar possível</td>
  </tr>
</table>

[Serviços de apoio](./backing-services), como o banco de dados do app, sistema de filas, ou cache, são uma área onde paridade entre desenvolvimento e produção é importante. Muitas linguagens oferecem diferentes bibliotecas que simplificam o acesso ao serviço de apoio, incluindo *adaptadores* para os diferentes tipos de serviços. Alguns exemplos na tabela abaixo.

<table>
  <tr>
    <th>Tipo</th>
    <th>Linguagem</th>
    <th>Biblioteca</th>
    <th>Adaptadores</th>
  </tr>
  <tr>
    <td>Banco de dados</td>
    <td>Ruby/Rails</td>
    <td>ActiveRecord</td>
    <td>MySQL, PostgreSQL, SQLite</td>
  </tr>
  <tr>
    <td>Fila</td>
    <td>Python/Django</td>
    <td>Celery</td>
    <td>RabbitMQ, Beanstalkd, Redis</td>
  </tr>
  <tr>
    <td>Cache</td>
    <td>Ruby/Rails</td>
    <td>ActiveSupport::Cache</td>
    <td>Memory, sistema de arquivos, Memcached</td>
  </tr>
</table>

Desenvolvedores as vezes veem uma grande vantagem em usar um serviço de apoio leve em seus ambientes, enquanto um serviço de apoio mais sério e robusto seria usado em produção. Por exemplo, usando SQLite localmente e PostgreSQL em produção; ou memória de processo local para caching em desenvolvimento e Memcached em produção.

**O desenvolvedor doze-fatores resiste a tentação de usar diferentes serviços de apoio entre desenvolvimento e produção**, mesmo quando adaptadores teoricamente abstraem as diferenças dos serviços de apoio. Diferenças entre serviços de apoio significam que pequenas incompatibilidades aparecerão, fazendo com que código que funcionava e passava em desenvolvimento ou homologação, falhe em produção. Tais tipos de erros criam fricção que desincentivam deploy contínuo. O custo dessa fricção e do subsequente decaimento de deploy contínuo é extremamente alto quando considerado que vai acumular no tempo de vida da aplicação.

Serviços locais leves são menos tentadores que já foram um dia. Serviços de apoio modernos tais como Memcached, PostgreSQL, e RabbitMQ não são difíceis de instalar e rodam graças a sistemas modernos de empacotamento tais como [Homebrew](http://mxcl.github.com/homebrew/) e [apt-get](https://help.ubuntu.com/community/AptGet/Howto). Alternativamente, ferramentas de provisionamento declarativo tais como [Chef](http://www.opscode.com/chef/) e [Puppet](http://docs.puppetlabs.com/) combinado com ambientes virtuais leves como [Vagrant](http://vagrantup.com/) permitem desenvolvedores rodar ambientes locais que são bem próximos dos ambientes de produção. O custo de instalar e usar esses sistemas é baixo comparado ao benefício de ter a paridade entre desenvolvimento, produção e deploy contínuo.

Adaptadores para diferentes serviços de apoio ainda são úteis, pois eles fazem a portabilidade para novos serviços de apoio relativamente tranquilas. Mas todos os deploys do app (ambientes de desenvolvimento, homologação, produção) devem usar o mesmo tipo e versão de cada serviço de apoio.

## XI. Logs
### Trate logs como fluxos de eventos

*Logs* provém visibilidade no comportamento de um app em execução. Em ambientes de servidor eles são comumente escritos num arquivo em disco (um "logfile"); mas este é apenas um formato de saída.

Logs são o [fluxo](https://adam.herokuapp.com/past/2011/4/1/logs_are_streams_not_files/) de eventos agregados e ordenados por tempo coletados dos fluxos de saída de todos os processos em execução e serviços de apoio. Logs na sua forma crua são tipicamente um formato de texto com um evento por linha (apesar que pilhas de exceção podem ocupar várias linhas). Logs não tem começos ou términos fixos, mas fluem continuamente enquanto o app estiver operante.

**Um app doze-fatores nunca se preocupa com o roteamento ou armazenagem do seu fluxo de saída.** Ele não deve tentar escrever ou gerir arquivos de logs. No lugar, cada processo em execução escreve seu próprio fluxo de evento, sem buffer, para o `stdout`. Durante o desenvolvimento local, o desenvolvedor verá este fluxo no plano de frente do seu terminal para observar o comportamento do app.

Em deploys de homologação ou produção, cada fluxo dos processos serão capturados pelo ambiente de execução, colados com todos os demais fluxos do app, e direcionados para um ou mais destinos finais para visualização e arquivamento de longo prazo. Estes destinos de arquivamento não são visíveis ou configuráveis pelo app, e ao invés disso, são completamente geridos pelo ambiente de execução. Roteadores de log open source (tais como [Logplex](https://github.com/heroku/logplex) e [Fluentd](https://github.com/fluent/fluentd)) estão disponíveis para este propósito.

O fluxo de evento para um app pode ser direcionado para um arquivo, ou visto em tempo real via `tail` num terminal. Mais significativamente, o fluxo pode ser enviado para um sistema indexador e analisador tal como [Splunk](http://www.splunk.com/), ou um sistema mais genérico de _data warehousing_ como o [Hadoop/Hive](http://hive.apache.org/). Estes sistemas permitem grande poder e flexibilidade para observar o comportamento de um app durante o tempo, incluindo:

* Encontrando eventos específicos no passado.
* Gráficos em larga escala de tendências (como requisições por minuto)
* Notificações ativas de acordo com as heurísticas determinadas pelo usuário (como uma notificação quando a quantidade de erros por minuto exceder um certo limite).

## XII. Processos administrativos
### Rode tarefas de administração/gestão em processos pontuais

A [formação de processos](./concurrency) é o conjunto de processos que são usados para fazer as negociações regulares da app como ela é executada (tais como manipulação de requisições web). Separadamente, os desenvolvedores, muitas vezes desejam fazer tarefas pontuais de administração ou manutenção para a app, tais como:

* Executar migrações de base de dados (ex: `manage.py migrate` no Django, `rake db:migrate` no Rails).
* Executar um console (também conhecido como um [REPL](http://en.wikipedia.org/wiki/Read-eval-print_loop) shell) para rodar código arbitrário ou inspecionar os modelos da app ao vivo no banco de dados. A maioria das linguagens fornece um REPL para rodar o interpretador sem nenhum argumento (ex: `python` or `perl`) ou em alguns casos tem um comando separado (ex: `irb` para Ruby, `rails console` para Rails).
* Executar uma vez os scripts comitados no repositório da app (ex: `php scripts/fix_bad_records.php`).

Processos administrativos pontuais devem ser executados em um ambiente idêntico, como os [processos regulares de longa execução](./processes) da app. Eles rodam uma [versão](./build-release-run), usando a mesma [base de código](./codebase) e [configuração](./config) como qualquer processo executado com essa versão. Códigos de administração devem ser fornecidos com o código da aplicação para evitar problemas de sincronização.

A mesma técnica de [isolamento de dependência](./dependencies) deve ser usada em todos tipos de processos. Por exemplo, se o processo web Ruby usa o comando `bundle exec thin start`, então uma migração de base de dados deve usar `bundle exec rake db:migrate`. Da mesma forma, um programa Python usando Virtualenv deve usar `bin/python` fornecido para executar tanto o servidor web Tornado e qualquer processo `manage.py` de administração.

Doze-fatores favorecem fortemente linguagens que fornecem um shell REPL embutido, e que tornam mais fácil executar scripts pontuais. Em um deploy local, desenvolvedores invocam processos administrativos pontuais por um comando shell direto no diretório de checkout da app. Em um deploy de produção, desenvolvedores podem usar ssh ou outro mecanismo de execução de comandos remoto fornecido por aquele ambiente de execução do deploy para executar tal processo.

## Licença

Copyright (c) 2012 Adam Wiggins

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
