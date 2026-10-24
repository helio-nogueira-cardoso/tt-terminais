#!/usr/bin/env bash
# tt-teste: sozinho (painel/tela sob carga oscila: roda sem outros testes disputando a máquina)
# Fontes (APIs) do letreiro: cadastro em ~/.config/tt/letreiro/NOME.conf, migração das linhas antigas
# indicador_NOME=, atualização com TTL/janela/cota/espera, formatos (json, xml, rss/atom, csv, texto, regex),
# GET/POST e autenticação sem vazar segredo, transformação e exibição, condições, segurança (https, SSRF,
# sanitização), diagnóstico, comandos de linha e painel, propagação entre máquinas e o clique no letreiro.
# Tudo isolado: HOME, XDG_CONFIG_HOME e TT_RT temporários, servidor HTTP/HTTPS de mentira em 127.0.0.1 e um
# tmux próprio — NUNCA a rede real (TT_LETREIRO_TESTE=1 só libera o loopback) nem o tmux do usuário.
source "$(dirname "$0")/lib.sh"; isolar
tt() { "$TT" "$@"; }
L=$T/pkg/letreiro-fontes.py
D=$T/pkg/letreiro-tt.py
py() { python3 -I "$L" "$@"; }
igual() { [[ $1 == "$2" ]] || falhou "$3: esperava [$2], veio [$1]"; }
contem() { [[ $1 == *"$2"* ]] || falhou "$3: esperava conter [$2], veio [$1]"; }
nao_contem() { [[ $1 != *"$2"* ]] || falhou "$3: NÃO deveria conter [$2], veio [$1]"; }
cria() { py criar "$@" >/dev/null 2>"$T/err" || falhou "criar $1: $(cat "$T/err")"; }
atual() { py atualizar "$@" --forcar >/dev/null 2>&1 || true; }
cache() { tr -d '\001-\004' <"$HOME/.cache/tt-ticker/$1" 2>/dev/null || true; }
cru() { cat "$HOME/.cache/tt-ticker/$1" 2>/dev/null || true; }
meta() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2], ""))' "$HOME/.cache/tt-ticker/$1.meta" "$2" 2>/dev/null; }
roda_tmux() { # o letreiro inteiro (sem rolar) no formato do tmux, como o desenhista o pinta
  python3 -I - "$D" <<'PY2'
import importlib.util, sys, time
sp = importlib.util.spec_from_file_location("lt", sys.argv[1]); lt = importlib.util.module_from_spec(sp); sp.loader.exec_module(lt)
print(lt.janela_roda(lt.montar_roda(lt.ler_conf(), time.time()), 900, 0).rstrip())
PY2
}
hits() { local a b; a=$(curl -s "http://127.0.0.1:$PH/_hits?p=$1"); b=$(curl -sk "https://127.0.0.1:$PS/_hits?p=$1"); echo $((a + b)); }
ultimo() { local r; r=$(curl -sk "https://127.0.0.1:$PS/_ultimo?p=$1"); [[ $r == '{}' ]] && r=$(curl -s "http://127.0.0.1:$PH/_ultimo?p=$1"); echo "$r"; }
jq_() { python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); print(d.get(sys.argv[2]) if d.get(sys.argv[2]) is not None else "")' "$1" "$2"; }
zerar() { # estado limpo: sem fontes, natives desligadas (e sem rede real nem para elas)
  rm -rf "$HOME/.config/tt/letreiro" "$HOME/.cache/tt-ticker" "$HOME/.cache/tt-letreiro.log"* "$HOME/.secrets"
  printf 'nome=teste\nindicadores=0\n' >"$XDG_CONFIG_HOME/tt/config"
  mkdir -p "$HOME/.secrets"; chmod 700 "$HOME/.secrets"
}

# tmux e notify-send de mentira nas partes sem tmux: nenhum aviso vai à tela real
mkdir -p "$T/bin"
printf '#!/bin/sh\nexit 1\n' >"$T/bin/tmux"; chmod +x "$T/bin/tmux"
printf '#!/bin/sh\necho "$@" >>"%s/notif.log"\n' "$T" >"$T/bin/notify-send"; chmod +x "$T/bin/notify-send"
# tt de mentira para o que o módulo chama de volta (--notificar e --letreiro-dado)
cat >"$T/bin/tt-falso" <<EOF
#!/bin/sh
case "\$1" in
  --letreiro-dado) case "\$2" in tarefas-atrasadas) echo 3 ;; emails-nao-lidos) echo 0 ;; *) exit 2 ;; esac ;;
  *) echo "\$@" >>"$T/tt-chamado.log" ;;
esac
EOF
chmod +x "$T/bin/tt-falso"
export PATH="$T/bin:$PATH" TT_BIN="$T/bin/tt-falso"

# servidores de mentira: http (PH) e https (PS, certificado de x.example)
free_port() { python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
PH=$(free_port); PS=$(free_port)
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout "$T/chave.pem" -out "$T/cert.pem" -days 2 \
  -subj /CN=x.example -addext subjectAltName=DNS:x.example >/dev/null 2>&1 || falhou 'openssl não gerou o certificado de teste'
cp "$RAIZ/tests/servidor_falso.py" "$T/servidor_falso.py"   # o caminho em $T/ faz o isolar/limpar matar o servidor no fim
python3 "$T/servidor_falso.py" "$PH" >"$T/srv-http.log" 2>&1 &
python3 "$T/servidor_falso.py" "$PS" "$T/cert.pem" "$T/chave.pem" >"$T/srv-https.log" 2>&1 &
for _ in $(seq 1 50); do grep -q pronto "$T/srv-http.log" && grep -q pronto "$T/srv-https.log" && break; sleep 0.1; done
grep -q pronto "$T/srv-http.log" && grep -q pronto "$T/srv-https.log" || falhou "servidores de mentira não subiram: $(cat "$T/srv-http.log" "$T/srv-https.log")"
export TT_LETREIRO_TESTE=1 TT_LETREIRO_HOSTS="x.example=127.0.0.1" TT_LETREIRO_CA="$T/cert.pem" TT_LETREIRO_CLIENTES=1 TT_PERFIL=desktop TT_MACHINE=teste
H=https://x.example:$PS
U=http://127.0.0.1:$PH
export TT_LETREIRO_REMAP="https://economia.awesomeapi.com.br/json/last/USD-BRL=>$H/dolar;https://g1.globo.com/rss/g1/=>$H/rss;https://feeds.bbci.co.uk/news/world/rss.xml=>$H/rss-bbc"

# O pacote oferece o perfil atual como padrão, sem tocar no perfil real do usuário.
perfil=$(env -u TT_LETREIRO_TESTE -u TT_LETREIRO_SEM_PADRAO HOME="$T/perfil-home" XDG_CONFIG_HOME="$T/perfil-config" python3 -I "$L" listar --tsv)
contem "$perfil" $'clima-rp-7dias\t1' 'perfil de fábrica liga a previsão de Ribeirão Preto'
contem "$perfil" $'ibovespa\t1' 'perfil de fábrica liga fontes atualmente ativas'
contem "$perfil" 'Ribeirão Preto' 'perfil identifica a localidade do clima'

# ============================================================================================
# 1) O contrato de hoje (v277) continua valendo: as mesmas entradas dão as mesmas linhas
# ============================================================================================
mkdir -p "$HOME/.secrets"; chmod 700 "$HOME/.secrets"
printf 'segredo123' >"$HOME/.secrets/chave"; chmod 600 "$HOME/.secrets/chave"
cat >"$XDG_CONFIG_HOME/tt/config" <<EOF
nome=teste
indicadores=dolar,noticias,btc,txt,lst,sec
indicador_btc=$H/btc ;; ₿ ;; data.amount ;; 300
indicador_txt=$H/texto ;; ℹ ;; - ;; 120
indicador_lst=$H/lista ;; 📋 ;; a.1.x ;; 60
indicador_sec=$H/lista ;; 🔑 ;; a.0.x ;; 60 ;; X-Api-Key: @chave
EOF
# (antes de migrar, as linhas antigas já valem: o painel as mostra)
est=$(py listar --tsv | cut -f1,2,4 | tr '\t' ' ' | paste -sd, -)
contem "$est" 'btc 1 legado' 'linha antiga indicador_btc= aparece como fonte (legado) e ativa'
contem "$est" 'frases 0 nativa' 'frases fica fora porque indicadores= não a lista'
atual
igual "$(cache dolar)" '💵 dólar R$ 5,123 ▲ 0,5%' 'dólar: mesmo texto de antes (vírgula também na variação)'
igual "$(cache noticias)" $'📰 Manchete A do g1\n📰 Manchete B\n🌍 World one\n🌍 World two' 'notícias: g1 e BBC, 2 manchetes de cada, na mesma ordem'
igual "$(python3 -I -c 'import json,sys; print(" ".join(i["acao"] + ":" + i["alvo"] for i in json.load(open(sys.argv[1]))))' "$HOME/.cache/tt-ticker/noticias.itens")" \
  'url:https://exemplo.com/a url:https://exemplo.com/b bloqueado: bloqueado:' 'notícias de fábrica: o clique abre a matéria (link do item); manchete sem link não abre nada'
igual "$(cache btc)" '₿ 67890.12' 'indicador antigo com caminho JSON'
igual "$(cache txt)" 'ℹ primeira linha do texto' 'indicador antigo com caminho - (texto cru, 1ª linha)'
igual "$(cache lst)" '📋 um' 'indicador antigo com índice numérico no caminho (a.1.x)'
igual "$(cache sec)" '🔑 zero' 'indicador antigo com header @arquivo'
igual "$(jq_ "$(ultimo /lista)" key)" 'segredo123' 'o header com @arquivo chegou ao servidor com o valor de ~/.secrets'
igual "$(py linha)" '💵 dólar R$ 5,123 ▲ 0,5% • 📰 Manchete A do g1 • 📰 Manchete B • 🌍 World one • 🌍 World two • ₿ 67890.12 • ℹ primeira linha do texto • 📋 um • 🔑 zero' 'a linha do letreiro: itens unidos por " • " na ordem de indicadores='
[[ -e $HOME/.config/tt/letreiro/btc.conf && -e $HOME/.config/tt/letreiro/dolar.conf ]] || falhou 'a migração deveria ter criado os arquivos (btc.conf; dolar.conf com ativa/ordem)'
grep -q '^header=X-Api-Key: @chave' "$HOME/.config/tt/letreiro/sec.conf" || falhou 'migração sem perda: header @chave'
grep -qE '^(valor_max|truncar)=' "$HOME/.config/tt/letreiro/btc.conf" && falhou 'a migração não deve criar corte de tamanho (o letreiro não corta entradas)'
grep -q 'segredo123' "$HOME/.config/tt/letreiro"/*.conf && falhou 'segredo literal em arquivo de fonte'
grep -q '^indicador_btc=' "$XDG_CONFIG_HOME/tt/config" || falhou 'a migração não pode apagar a linha antiga do config (sem perda)'
n1=$(hits /btc); atual btc >/dev/null; py atualizar >/dev/null 2>&1; igual "$(hits /btc)" "$((n1 + 1))" 'sem --forcar o TTL (300 s) impede nova busca; --forcar busca'
msg=$(py migrar); igual "$msg" 'nada a migrar' 'a migração é idempotente'
passou 'contrato antigo: dólar, notícias, indicador_ (json, texto, índice, header @arquivo) e a linha " • " — migrados sem perda'

# indicadores= editado depois da migração volta a valer (a lista antiga nunca é ignorada em silêncio)
printf 'indicadores=btc,dolar\n' >>"$XDG_CONFIG_HOME/tt/config"
est=$(py listar --tsv | awk -F'\t' '{print $1":"$2":"$7}' | paste -sd' ')
contem "$est" 'btc:1:10' 'btc passa a ser o 1º (ordem 10)'; contem "$est" 'dolar:1:20' 'dolar o 2º'; contem "$est" 'noticias:0:' 'noticias saiu da lista: desligada'
py migrar >/dev/null; contem "$(grep -h '^ativa' "$HOME/.config/tt/letreiro/noticias.conf")" 'ativa=0' 'a nova lista foi gravada nos arquivos'
[[ $(py linha) == '₿ 67890.12 • 💵 dólar R$ 5,123 '* ]] || falhou "ordem nova na linha: $(py linha)"
passou 'indicadores= alterado à mão depois da migração é reaplicado'

# ============================================================================================
# 2) Formatos de resposta: json (caminhos), xml, rss/atom, csv, texto, regex — sempre N itens e erro claro
# ============================================================================================
zerar
cria j1 url="$H/lista" caminho='itens[*].nome' itens=3 modelo='{valor}' ativa=1
cria j2 url="$H/lista" caminho='$.itens[-1].v' modelo='último {valor}'
cria j3 url="$H/lista" caminho='itens[?d>={hoje}].nome' modelo='{valor}'
cria j4 url="$H/lista" caminho='a[0:2].x' itens=5 modelo='{valor}'
cria j5 url="$H/lista" caminho="['itens'][1]['nome']" modelo='{valor}'
cria j6 url="$H/lista" caminho='itens[*].nome' itens=3 campo.dia='itens[*].d' modelo='{dia}'
atual j1 j2 j3 j4 j5 j6
igual "$(cache j1)" $'a\nb\nc' 'json: [*] com itens=3'
igual "$(cache j2)" 'último 3' 'json: $.lista[-1]'
igual "$(TT_AGORA=$(date -d 2026-06-01 +%s) py atualizar j3 --forcar >/dev/null; cache j3)" 'b' 'json: filtro [?d>={hoje}] com a data de hoje (1º ano em diante) — pega o 1º futuro'
igual "$(cache j4)" $'zero\num' 'json: fatia [0:2] com chave sobre lista'
igual "$(cache j5)" 'b' "json: [\"chave\"] entre colchetes"
igual "$(cache j6)" $'01/01/2026 (Qui)\n31/12/2026 (Qui)\n01/06/2027 (Ter)' 'campo.dia: data ISO vira DD/MM/AAAA (dia da semana em português)'
err=$(py testar --arquivo <(printf 'url=%s/lista\ncaminho=itens[0].inexistente\n' "$H") 2>&1 || true)
contem "$err" 'nada em' 'json: caminho que não existe diz onde parou'
cria x1 url="$H/rss" formato=rss itens=2 modelo='{valor}'
cria x2 url="$H/atom" formato=atom itens=2 modelo='{valor}'
cria x3 url="$H/xml" formato=xml caminho='.//item/nome' itens=5 modelo='{valor}'
cria x4 url="$H/xml" formato=xml caminho='.//item/@id' itens=5 modelo='id {valor}'
cria x5 url="$H/rss" formato=rss caminho='.//item/description' itens=1 modelo='{valor}'
cria x6 url="$H/xml" formato=xml caminho='/dados/item/preco' itens=1 de=fim decimais=2 separador=en entrada=pt modelo='{valor}'
atual x1 x2 x3 x4 x5 x6
igual "$(cache x1)" $'Manchete A do g1\nManchete B' 'rss: títulos, 2 itens, espaços limpos'
igual "$(cache x2)" $'Entrada 1\nEntrada 2' 'atom: namespace ignorado, entry/title'
igual "$(cache x3)" $'Um\nDois' 'xml: XPath .//item/nome'
igual "$(cache x4)" $'id 1\nid 2' 'xml: atributo (/@id)'
igual "$(cache x5)" 'negrito resumo' 'rss: HTML do resumo vira texto'
igual "$(cache x6)" '20.00' 'xml: caminho absoluto, de=fim, número pt (20,00) → en com 2 casas'
cria c1 url="$H/csv" formato=csv caminho=valor itens=2 de=fim modelo='{valor}'
cria c2 url="$H/csv" formato=csv caminho=3 itens=1 modelo='{valor}' csv_cabecalho=1
cria c3 url="$H/csv-pv" formato=csv caminho=valor csv_sep=';' itens=1 decimais=1 separador=pt modelo='{valor}'
cria t1 url="$H/texto" formato=texto caminho='linha:2' modelo='{valor}'
cria t2 url="$H/texto" formato=texto itens=2 modelo='{valor}'
cria r1 url="$H/regex" formato=regex caminho='temperatura: ([0-9.]+) C' itens=2 modelo='{valor}°'
cria r2 url="$H/regex" formato=regex caminho='umidade: (?P<u>\d+)' modelo='{valor}%'
atual c1 c2 c3 t1 t2 r1 r2
igual "$(cache c1)" $'12.5\n15' 'csv: coluna pelo nome, de=fim (as 2 últimas)'
igual "$(cache c2)" 'alfa' 'csv: coluna pelo número (com cabeçalho)'
igual "$(cache c3)" '1.234,6' 'csv: separador ;, número pt-BR (1.234,56) com 1 casa'
igual "$(cache t1)" 'segunda' 'texto: linha:2'
igual "$(cache t2)" $'primeira linha do texto\nsegunda' 'texto: itens=2'
igual "$(cache r1)" $'21.3°\n25.0°' 'regex: grupo 1, 2 achados'
igual "$(cache r2)" '80%' 'regex: grupo nomeado'
err=$(py testar --arquivo <(printf 'url=%s/csv\nformato=csv\ncaminho=nao_existe\n' "$H") 2>&1 || true); contem "$err" 'colunas:' 'csv: coluna inexistente lista as colunas'
err=$(py testar --arquivo <(printf 'url=%s/lista\nformato=xml\n' "$H") 2>&1 || true); contem "$err" 'não é XML' 'xml: resposta que não é XML tem erro claro'
err=$(py testar --arquivo <(printf 'url=%s/texto\ncaminho=x\n' "$H") 2>&1 || true); contem "$err" 'não é JSON' 'json: resposta que não é JSON tem erro claro'
err=$(py testar --arquivo <(printf 'url=%s/regex\nformato=regex\ncaminho=zzz(\n' "$H") 2>&1 || true); contem "$err" 'regex' 'regex inválida é recusada com mensagem'
passou 'formatos: json (ponto, colchete, [*], [-1], fatia, filtro), xml (XPath, atributo), rss/atom, csv, texto, regex — N itens e erros claros'

# ============================================================================================
# 3) Métodos e autenticação: GET/POST, headers, query, corpo com variáveis, bearer, basic, header, query —
#    com o segredo SÓ em ~/.secrets (nunca no .conf, no cache, no log, na tela nem na propagação)
# ============================================================================================
zerar
SEG='ABC-token-9f3k'
printf '%s' "$SEG" >"$HOME/.secrets/api"; chmod 600 "$HOME/.secrets/api"
printf 'maria:senha-do-basic' >"$HOME/.secrets/basica"; chmod 600 "$HOME/.secrets/basica"
cria p1 url="$H/eco" metodo=POST corpo='{"dia":"{data}","moeda":"{moeda}"}' var.moeda=USD header='X-Extra: oi' query='a=1' query='b={moeda}' caminho=metodo modelo='{valor}' escopo=global
atual p1
u=$(ultimo /eco)
igual "$(jq_ "$u" metodo)" POST 'POST chegou como POST'
contem "$(jq_ "$u" corpo)" "\"dia\":\"$(date +%F)\"" 'corpo com {data}'; contem "$(jq_ "$u" corpo)" '"moeda":"USD"' 'corpo com var.moeda'
igual "$(jq_ "$u" ct)" 'application/json' 'Content-Type do POST com corpo JSON'
igual "$(jq_ "$u" extra)" oi 'header extra'
contem "$(jq_ "$u" path)" 'a=1' 'query fixa'; contem "$(jq_ "$u" path)" 'b=USD' 'query com variável'
contem "$(jq_ "$u" ua)" 'tt-letreiro' 'User-Agent do tt por padrão'
cria p2 url="$H/eco" auth=bearer segredo=@api caminho=auth modelo='{valor}'
cria p3 url="$H/eco" auth=basic segredo=@basica caminho=auth modelo='{valor}'
cria p4 url="$H/eco" auth=header auth_nome=X-Minha-Chave segredo=@api caminho=metodo modelo='{valor}'
cria p5 url="$H/eco" auth=query auth_nome=apikey segredo=@api caminho=full modelo='[{valor}]'
cria p6 url="$H/eco" auth=header segredo=@api caminho=key modelo='eco:{valor}'
for f in p2 p3 p4 p5 p6; do atual $f; done
igual "$(jq_ "$(ultimo /eco)" auth)" '' 'último pedido (p6, auth=header) não manda Authorization'
atual p2; igual "$(jq_ "$(ultimo /eco)" auth)" "Bearer $SEG" 'bearer: Authorization: Bearer <segredo>'
atual p3; igual "$(jq_ "$(ultimo /eco)" auth)" "Basic $(printf 'maria:senha-do-basic' | base64)" 'basic: usuario:senha em base64'
atual p4; igual "$(jq_ "$(ultimo /eco)" path)" '/eco' 'header: nada na URL'
atual p5; contem "$(jq_ "$(ultimo /eco)" path)" "apikey=$SEG" 'query: a chave vai como parâmetro'
atual p6; igual "$(jq_ "$(ultimo /eco)" key)" "$SEG" 'header sem auth_nome usa X-API-Key'
# o servidor ECOOU a chave (p5 e p6 extraem exatamente o campo que a contém): o tt a redige antes de pôr na faixa
nao_contem "$(cache p5)$(cache p6)" "$SEG" 'segredo refletido pela API não pode aparecer no cache/letreiro'
contem "$(cache p6)" '***' 'o trecho redigido vira ***'
# varredura: o segredo não está em NENHUM arquivo fora de ~/.secrets, nem no log, nem nas saídas de tela
for f in p1 p2 p3 p4 p5 p6; do py testar $f >>"$T/saidas.txt" 2>&1 || true; done
py listar >>"$T/saidas.txt"; py listar --tsv >>"$T/saidas.txt"; py exportar >>"$T/saidas.txt" 2>&1 || true; py pacote >>"$T/saidas.txt" 2>&1 || true
py ler p5 >>"$T/saidas.txt"; py log >>"$T/saidas.txt"
tt --letreiro-listar >>"$T/saidas.txt" 2>&1 || true
if grep -rIl --exclude-dir=.secrets -e "$SEG" -e 'senha-do-basic' "$HOME" "$T/saidas.txt" "$T/tt-chamado.log" 2>/dev/null | grep -q .; then
  falhou "segredo vazou: $(grep -rIl --exclude-dir=.secrets -e "$SEG" -e 'senha-do-basic' "$HOME" "$T/saidas.txt" 2>/dev/null | head -3 | tr '\n' ' ')"
fi
grep -q 'segredo @api lido de ~/.secrets' "$T/saidas.txt" || falhou 'testar deveria dizer que leu o segredo (sem mostrar o valor)'
passou 'segredo só em ~/.secrets: nada no .conf, no cache, no log, no pacote, no export nem nas telas — nem quando a API o ecoa'
# recusas: segredo/credencial literal, usuário na URL, segredo ausente, permissão frouxa
recusa() { local m=$1; shift; out=$(py criar zz "$@" 2>&1) && falhou "deveria recusar: $m"; contem "$out" "$m" "recusa de $m"; rm -f "$HOME/.config/tt/letreiro/zz.conf"; }
recusa credencial url="$H/x" header='Authorization: Bearer xyz'
recusa credencial url="$H/x" header='X-Api-Key: abc123'
recusa 'não pode ficar na URL' url="$H/x?apikey=abc123"
recusa 'referência @arquivo' url="$H/x" auth=bearer segredo=abc123
recusa 'precisa de segredo' url="$H/x" auth=bearer
recusa 'usuário/senha' url="https://u:p@x.example:$PS/x"
recusa 'credencial' url="$H/x" query='token=abc'
recusa 'nome de segredo inválido' url="$H/x" auth=bearer 'segredo=@../../etc/passwd'
cria ausente url="$H/eco" auth=bearer segredo=@nao-existe caminho=auth
out=$(py testar ausente 2>&1 || true); contem "$out" 'não encontrado' 'segredo ausente: erro claro'; nao_contem "$out" "$SEG" 'e sem valor'
printf 'x1' >"$HOME/.secrets/frouxa"; chmod 644 "$HOME/.secrets/frouxa"
cria frouxa url="$H/eco" auth=bearer segredo=@frouxa caminho=auth; contem "$(py testar frouxa 2>&1 || true)" 'chmod 600' 'segredo com permissão frouxa avisa'
passou 'recusas: credencial literal em header/query/URL, referência inválida, caminho fora de ~/.secrets, segredo ausente/frouxo'

# ============================================================================================
# 4) Transformação e exibição: casas, pt/en, escala, moeda, arredondar, variação (campo, base, calculada),
#    setas, cor por sinal, modelo, truncar, prefixo/sufixo, traduzir e o que mostrar sem dado
# ============================================================================================
zerar
v() { echo "$H/valor?v=$1&p=${2:-0}"; }
cria n1 url="$(v 1234567.891)" caminho=v decimais=2 separador=pt modelo='{valor}'
cria n2 url="$(v 1234567.891)" caminho=v decimais=2 separador=en modelo='{valor}'
cria n3 url="$(v 1234567.891)" caminho=v decimais=2 separador=pt milhar=0 modelo='{valor}'
cria n4 url="$(v 1234567.891)" caminho=v decimais=2 separador=pt escala=mi moeda='R$' modelo='{valor}'
cria n5 url="$(v 2.349)" caminho=v decimais=2 arredondar=truncar modelo='{valor}'
cria n6 url="$(v 2.341)" caminho=v decimais=2 arredondar=cima modelo='{valor}'
cria n7 url="$(v 2.349)" caminho=v decimais=2 arredondar=baixo modelo='{valor}'
cria n8 url="$(v 2.345)" caminho=v decimais=2 modelo='{valor}'
cria n9 url="$(v 1.234,56)" caminho=v decimais=1 separador=en entrada=pt modelo='{valor}'
cria n10 url="$(v Clear)" caminho=v traduzir='Clear>Limpo' modelo='{rotulo}:{valor}' rotulo=céu
cria n11 url="$(v 7)" caminho=v prefixo='">> "' sufixo='" <<"' truncar=12 modelo='{valor} coisa muito comprida'
LONGO=$(printf 'manchete-longa-%d-' $(seq 1 25))   # 400 caracteres: nenhum corte por padrão
cria n12 url="$(v "$LONGO")" caminho=v modelo='{icone} {valor}' icone=📰
cria n13 url="$(v "$LONGO")" caminho=v modelo='{valor}' truncar=30
cria n14 url="$(v 7 30.25)" caminho=v campo.t=p separador=pt modelo='{valor} máx {t}°'
cria n15 url="$(v 7 30.25)" caminho=v campo.t=p modelo='{valor} máx {t}°'
for f in n1 n2 n3 n4 n5 n6 n7 n8 n9 n10 n11 n12 n13 n14 n15; do atual $f; done
igual "$(cache n1)" '1.234.567,89' 'pt: milhar com ponto e vírgula decimal'
igual "$(cache n2)" '1,234,567.89' 'en'
igual "$(cache n3)" '1234567,89' 'milhar=0'
igual "$(cache n4)" 'R$ 1,23 mi' 'escala=mi + moeda'
igual "$(cache n5)" '2,34' 'arredondar=truncar'; igual "$(cache n6)" '2,35' 'arredondar=cima'; igual "$(cache n7)" '2,34' 'arredondar=baixo'; igual "$(cache n8)" '2,35' 'arredondar=normal (meio para cima)'
igual "$(cache n9)" '1,234.6' 'entrada=pt (1.234,56) → en com 1 casa'
igual "$(cache n10)" 'céu:Limpo' 'traduzir texto fixo'
igual "$(cache n11)" '>> 7 coi… <<' 'prefixo/sufixo (aspas guardam os espaços) e truncar em células (com …)'
igual "$(cache n12)" "📰 $LONGO" 'sem truncar/valor_max o item sai inteiro, por maior que seja (o letreiro rola, não corta)'
igual "$(cache n14)" '7 máx 30,25°' 'campo extra numérico segue o separador da fonte (pt: vírgula, com as casas que vieram)'
igual "$(cache n15)" '7 máx 30.25°' 'sem separador na fonte o campo extra fica como veio'
igual "$(cache n13)" "$(printf '%s' "$LONGO" | cut -c1-29)…" 'truncar=N continua cortando, mas só quando o usuário pede'
# variação: campo próprio, valor de referência, calculada contra o valor anterior; setas e cores
cria v1 url="$(v 100 -1.26)" caminho=v variacao=p modelo='{valor} {var}'
cria v2 url="$(v 100 2.04)" caminho=v variacao=p setas=0 modelo='{valor} {var}'
cria v3 url="$(v 100 0.01)" caminho=v variacao=p modelo='{valor} {var}'
cria v4 url="$H/valor?v=110&p=100" caminho=v var_base=p modelo='{valor} {var} {seta} {pct}'
cria v5 url="$H/contador" caminho=n variacao=calculada modelo='n={valor} {var}'
cria v6 url="$(v 100 3)" caminho=v variacao=p cor=0 modelo='{valor} {var}'
for f in v1 v2 v3 v4 v6; do atual $f; done
igual "$(cache v1)" '100 ▼ 1,3%' 'variação negativa: ▼ e vírgula'
igual "$(cache v2)" '100 +2,0%' 'setas=0: +2,0%'
igual "$(cache v3)" '100 = 0,0%' 'variação que arredonda a zero é neutra (=)'
igual "$(cache v4)" '110 ▲ 10,0% ▲ 10,0%' 'var_base: (110-100)/100; {seta} e {pct}'
[[ $(cru v1) == *$'\002'* && $(cru v3) == *$'\003'* && $(cru v2) == *$'\001'* ]] || falhou 'marcas de cor: baixa=\002, neutra=\003, alta=\001 no cache'
[[ $(cru v6) != *[$'\001\002\003\004']* ]] || falhou 'cor=0 não pode pôr marcas de cor'
atual v5; igual "$(cache v5)" 'n=1' 'variação calculada: 1ª leitura ainda sem referência'
atual v5; igual "$(cache v5)" 'n=2 ▲ 100,0%' 'variação calculada: (2-1)/1'
atual v5; igual "$(cache v5)" 'n=3 ▲ 50,0%' 'variação calculada: (3-2)/2'
# o desenhista pinta: alta verde, baixa vermelha; ticker_cor=0 desliga
q=$(roda_tmux)
contem "$q" '#[fg=#f38ba8]▼ 1,3%' 'faixa: baixa vermelha'; contem "$q" '#[fg=#a6e3a1]▲ 10,0%' 'faixa: alta verde'
printf 'ticker_cor=0\n' >>"$XDG_CONFIG_HOME/tt/config"; q=$(roda_tmux)
nao_contem "$q" '#[fg=#f38ba8]' 'ticker_cor=0 tira as cores'; contem "$q" '▼ 1,3%' 'e mantém o texto'
sed -i '/^ticker_cor=/d' "$XDG_CONFIG_HOME/tt/config"
passou 'transformação: casas, pt/en, milhar, escala, moeda, 4 arredondamentos, traduzir; variação (campo, base, calculada), setas, cor por sinal'
# sem dado novo: esconder, último (marcado como velho) ou erro — e uma falha de rede nunca apaga o letreiro
zerar
cria d1 url="$H/valor?v=1" caminho=v modelo='um {valor}' cache_max=60 se_faltar=ultimo
cria d2 url="$H/valor?v=2" caminho=v modelo='dois {valor}' cache_max=60 se_faltar=esconder
cria d3 url="$H/valor?v=3" caminho=v modelo='tres {valor}' cache_max=60 se_faltar=erro rotulo=Três
atual d1 d2 d3
q=$(roda_tmux); contem "$q" 'Um 1' 'dado novo aparece com a inicial capitalizada'; nao_contem "$q" '⏳' 'sem marca de velho enquanto está dentro de cache_max'
for f in d1 d2 d3; do touch -d '-3 hours' "$HOME/.cache/tt-ticker/$f"; done
q=$(roda_tmux)
contem "$q" '⏳ Um 1' 'se_faltar=ultimo: o último valor com a marca de velho'; contem "$q" '#[fg=#585b70]' 'e apagado'
nao_contem "$q" 'Dois 2' 'se_faltar=esconder: some'; contem "$q" '⚠ Três: sem dado atual' 'se_faltar=erro: mostra o problema'
py editar d1 url="$H/erro500" >/dev/null; atual d1
igual "$(meta d1 falhas)" 1 'falha registrada'; contem "$(cru d1)" 'um 1' 'a falha de rede NÃO apagou o cache'
contem "$(roda_tmux)" 'Um 1' 'nem o letreiro'
passou 'dado velho/ausente: esconder, último com marca ⏳ (apagado) ou erro; falha de rede nunca apaga o letreiro'

# ============================================================================================
# 5) Agenda e condições: TTL (e mudar o TTL), janela de dias/horas, cota por hora, espera após erro, condições
#    de exibição, escopo por perfil/máquina e modo economia
# ============================================================================================
zerar
printf 'ticker_fuso=UTC\n' >>"$XDG_CONFIG_HOME/tt/config"
epoch() { TZ=UTC date -d "$1" +%s; }
cria k1 url="$H/contador" caminho=n modelo='k1={valor}' ttl=3600
agora_real=$(date +%s)
atual k1; h0=$(hits /contador)
TT_AGORA=$((agora_real + 60)) py atualizar >/dev/null 2>&1; igual "$(hits /contador)" "$h0" 'dentro do TTL não busca de novo'
py editar k1 ttl=30 >/dev/null
TT_AGORA=$((agora_real + 60)) py atualizar >/dev/null 2>&1; igual "$(hits /contador)" "$((h0 + 1))" 'mudar o TTL vale já no ciclo seguinte'
passou 'TTL: sem nova busca dentro dele; ao diminuir o TTL o próximo ciclo atualiza'
# janela de dias e horas (pregão: seg-sex, 10h às 18h)
cria j1 url="$H/contador" caminho=n modelo='pregao={valor}' ttl=10 dias=seg-sex horas=10-18
for quando in '2026-10-10 12:00' '2026-10-12 09:59' '2026-10-12 18:00'; do
  h=$(hits /contador); TT_AGORA=$(epoch "$quando") py atualizar j1 >/dev/null 2>&1; igual "$(hits /contador)" "$h" "fora da janela ($quando) não busca"
done
h=$(hits /contador); TT_AGORA=$(epoch '2026-10-12 12:00') py atualizar j1 >/dev/null 2>&1; igual "$(hits /contador)" "$((h + 1))" 'dentro da janela (seg 12:00) busca'
h=$(hits /contador); TT_AGORA=$(epoch '2026-10-16 17:59') py atualizar j1 >/dev/null 2>&1; igual "$(hits /contador)" "$((h + 1))" 'sexta 17:59 ainda é janela'
bad=$(py editar j1 horas=25-3 2>&1 || true); contem "$bad" 'horas' 'hora inválida é recusada'
passou 'janela de dias e horas: fora dela não busca (fim exclusivo), dentro busca'
# cota por hora
cria q1 url="$H/contador" caminho=n modelo='q={valor}' ttl=10 limite_hora=2
t0=$(epoch '2026-10-12 12:00'); h=$(hits /contador)
for i in 0 1 2 3; do TT_AGORA=$((t0 + 20 * i)) py atualizar q1 >/dev/null 2>&1; done
igual "$(hits /contador)" "$((h + 2))" 'limite_hora=2: só 2 requisições na hora'
TT_AGORA=$((t0 + 3700)) py atualizar q1 >/dev/null 2>&1; igual "$(hits /contador)" "$((h + 3))" 'passada a hora, volta a buscar'
passou 'cota por hora (limite_hora) respeitada'
# espera crescente após erro e aviso quando falha demais
cria e1 url="$H/erro500" caminho=x ttl=10 alerta_falhas=3 tentativas=1
t0=$(epoch '2026-10-12 12:00'); : >"$T/tt-chamado.log"
TT_AGORA=$t0 py atualizar e1 >/dev/null 2>&1; igual "$(meta e1 falhas)" 1 '1ª falha'
igual "$(( $(meta e1 espera_ate) - t0 ))" 60 'espera de 60 s após a 1ª falha'
h=$(hits /erro500); TT_AGORA=$((t0 + 30)) py atualizar e1 >/dev/null 2>&1; igual "$(hits /erro500)" "$h" 'durante a espera não tenta'
TT_AGORA=$((t0 + 61)) py atualizar e1 >/dev/null 2>&1; igual "$(( $(meta e1 espera_ate) - t0 - 61 ))" 120 'espera dobra: 120 s'
[[ ! -s $T/tt-chamado.log ]] || falhou 'não avisa antes de falhar demais'
TT_AGORA=$((t0 + 200)) py atualizar e1 >/dev/null 2>&1; igual "$(meta e1 falhas)" 3 '3ª falha'
grep -q -- '--notificar' "$T/tt-chamado.log" && grep -q 'e1' "$T/tt-chamado.log" || falhou "aviso na central de notificações ao falhar demais: $(cat "$T/tt-chamado.log")"
TT_AGORA=$((t0 + 5000)) py atualizar e1 >/dev/null 2>&1; igual "$(grep -c -- '--notificar' "$T/tt-chamado.log")" 1 'um aviso só por sequência de falhas'
py editar e1 url="$H/valor?v=1" caminho=v >/dev/null; TT_AGORA=$((t0 + 9000)) py atualizar e1 >/dev/null 2>&1
igual "$(meta e1 falhas)" 0 'sucesso zera as falhas'; igual "$(meta e1 espera_ate)" 0 'e a espera'
passou 'espera crescente após erro (60, 120, … s), sem tentar durante ela, aviso na central após N falhas, zera ao voltar'
# condições: variação, valor, cruzamento de limite
cria c1 url="$H/valor?v=100&p=0.5" caminho=v variacao=p condicao='abs>1' modelo='mexeu {valor}'
cria c2 url="$H/valor?v=100&p=2.5" caminho=v variacao=p condicao='abs>1' modelo='mexeu {valor}'
cria c3 url="$H/valor?v=100" caminho=v condicao='valor>50' condicao='valor<150' modelo='faixa {valor}'
cria c4 url="$H/valor?v=100" caminho=v condicao='valor>500' modelo='alto {valor}'
cria c5 url="$H/valor?v=90" caminho=v condicao='cruza 100' modelo='cruzou {valor}'
atual c1 c2 c3 c4 c5
igual "$(cache c1)" '' 'variação 0,5% não passa de 1%'; igual "$(cache c2)" 'mexeu 100' 'variação 2,5% passa'
igual "$(cache c3)" 'faixa 100' 'várias condições valem juntas (E)'; igual "$(cache c4)" '' 'valor>500 esconde'
igual "$(cache c5)" '' 'cruza 100: sem valor anterior, nada'
py editar c5 url="$H/valor?v=110" >/dev/null; atual c5; igual "$(cache c5)" 'cruzou 110' 'cruzou o limite: alerta aparece'
py editar c5 url="$H/valor?v=111" >/dev/null; TT_AGORA=$(( $(date +%s) + 1800 )) py atualizar c5 --forcar >/dev/null 2>&1; igual "$(cache c5)" 'cruzou 111' 'o alerta segue visível por 1 h'
py editar c5 url="$H/valor?v=112" >/dev/null; TT_AGORA=$(( $(date +%s) + 7200 )) py atualizar c5 --forcar >/dev/null 2>&1; igual "$(cache c5)" '' 'e some depois'
passou 'condições: abs>N, valor>N / valor<N (juntas), cruza N (alerta por 1 h)'
# escopo por perfil e por máquina; modo economia; só com cliente
zerar
cria s1 url="$H/valor?v=1" caminho=v modelo='todos {valor}'
cria s2 url="$H/valor?v=2" caminho=v modelo='celular {valor}' perfil=celular
cria s3 url="$H/valor?v=3" caminho=v modelo='so-teste {valor}' maquinas=teste
cria s4 url="$H/valor?v=4" caminho=v modelo='nao-teste {valor}' maquinas='!teste'
cria s5 url="$H/valor?v=5" caminho=v modelo='outra {valor}' maquinas=outra,mais
atual
igual "$(py linha)" 'todos 1 • so-teste 3' 'perfil celular, máquinas !teste e outras não valem nesta máquina (desktop "teste")'
contem "$(py listar --tsv | awk -F'\t' '$1=="s2"{print $3}')" fora 'a tela mostra "fora" para a que não vale aqui'
igual "$(TT_PERFIL=celular py linha)" "$(TT_PERFIL=celular py linha)" 'estável'
TT_PERFIL=celular py compilar >/dev/null; contem "$(python3 -I -c 'import json,sys; print([i["nome"] for i in json.load(open(sys.argv[1]))["itens"]])' "$HOME/.cache/tt-ticker/_roda.json")" "'s2'" 'no celular a de perfil celular entra na roda'
py compilar >/dev/null
cria z1 url="$H/contador" caminho=n modelo='{valor}' ttl=10 so_com_cliente=1
h=$(hits /contador); TT_LETREIRO_CLIENTES=0 py atualizar z1 >/dev/null 2>&1; igual "$(hits /contador)" "$h" 'so_com_cliente=1 sem terminal em uso: não busca'
TT_LETREIRO_CLIENTES=1 py atualizar z1 >/dev/null 2>&1; igual "$(hits /contador)" "$((h + 1))" 'com terminal em uso: busca'
printf 'ticker_economia=1\n' >>"$XDG_CONFIG_HOME/tt/config"; py editar z1 so_com_cliente=0 ttl=10 >/dev/null
h=$(hits /contador); TT_AGORA=$(( $(date +%s) + 100 )) TT_LETREIRO_BATERIA='15 Discharging' py atualizar z1 >/dev/null 2>&1; igual "$(hits /contador)" "$h" 'economia: bateria baixa (15%) sem carregar não busca'
TT_AGORA=$(( $(date +%s) + 100 )) TT_LETREIRO_BATERIA='15 Charging' py atualizar z1 >/dev/null 2>&1; igual "$(hits /contador)" "$((h + 1))" 'economia: carregando, busca'
TT_AGORA=$(( $(date +%s) + 200 )) TT_LETREIRO_CLIENTES=0 TT_LETREIRO_BATERIA='90 Discharging' py atualizar z1 >/dev/null 2>&1; igual "$(hits /contador)" "$((h + 1))" 'economia: nenhum terminal em uso não busca'
sed -i '/^ticker_economia=/d' "$XDG_CONFIG_HOME/tt/config"
passou 'escopo por perfil/máquina e modo economia (bateria, sem terminal em uso, só com cliente)'

# modo economia no desenhista: bateria baixa sem carregar vira páginas (não anima); carregando, volta a deslizar
zerar
cria en1 url="$H/valor?v=1" caminho=v modelo='ECONOMIA-XXXXXXXXXXXXXXXXXXXX'
printf 'ticker_economia=1\nticker_rolagem=continua\n' >>"$XDG_CONFIG_HOME/tt/config"
TT_LETREIRO_BATERIA='9 Discharging' py atualizar en1 --forcar >/dev/null 2>&1
contem "$(cat "$HOME/.cache/tt-ticker/_energia")" '9 0 ' 'o módulo deixa a bateria para o desenhista'
estatica() { python3 -I - "$D" <<'PY2'
import importlib.util, sys, time
sp = importlib.util.spec_from_file_location("lt", sys.argv[1]); lt = importlib.util.module_from_spec(sp); sp.loader.exec_module(lt)
cfg = lt.ler_conf()
print(lt.economia_estatica(cfg), lt._quadro(cfg, 200, False, time.time(), 20, 6)[1])
PY2
}
igual "$(estatica)" 'True False' 'economia: bateria baixa → o letreiro não anima'
TT_LETREIRO_BATERIA='9 Charging' py atualizar en1 --forcar >/dev/null 2>&1
igual "$(estatica)" 'False True' 'carregando: volta a deslizar'
passou 'modo economia: bateria baixa sem carregar congela em páginas; o módulo avisa o desenhista'

# ============================================================================================
# 6) Segurança: só https, nada de destino local/privado (SSRF), tempo e tamanho limitados, XML sem entidades,
#    texto remoto limpo (escapes de terminal, #[ e #() do tmux, controles de direção) — com testes de ataque
# ============================================================================================
zerar
H0=$(hits /dolar)
out=$(py criar h1 url="$U/dolar" caminho=USDBRL.bid 2>&1 || true); contem "$out" 'não é criptografado' 'http:// recusado por padrão'
py criar h1 url="$U/dolar" caminho=USDBRL.bid permitir_http=1 >/dev/null 2>"$T/err"; contem "$(cat "$T/err")" 'sem criptografia' 'permitir_http=1 aceita, mas avisa'
# sem o modo de teste, o loopback também é destino privado: a mesma fonte não busca nada
out=$(TT_LETREIRO_TESTE= py testar h1 2>&1 || true); contem "$out" 'bloqueado' 'sem TT_LETREIRO_TESTE o servidor local é bloqueado'
igual "$(hits /dolar)" "$H0" 'e nenhuma requisição saiu'
for u in 'file:///etc/passwd' 'ftp://x.example/a' 'gopher://x.example/' 'javascript:alert(1)'; do
  out=$(py testar --arquivo <(printf 'url=%s\n' "$u") 2>&1 || true); contem "$out" 'http' "esquema recusado: $u"
done
bloq() { # url → deve ser bloqueada e não gerar requisição
  local out
  out=$(TT_LETREIRO_TESTE= TT_LETREIRO_HOSTS="evil.test=127.0.0.1,evil2.test=10.0.0.5,evil3.test=169.254.169.254,rebind.test=93.184.216.34|127.0.0.1,v6.test=::1,mapped.test=::ffff:127.0.0.1,tail.test=100.64.0.7" \
    py testar --arquivo <(printf 'url=%s\npermitir_http=1\n' "$1") 2>&1 || true)
  contem "$out" 'bloqueado' "SSRF: $1 deveria ser bloqueado"
}
for u in https://localhost/x https://127.0.0.1/x "https://127.0.0.1:$PH/dolar" https://10.1.2.3/x https://192.168.1.1/x https://169.254.169.254/latest/meta-data/ \
         https://172.16.0.1/x https://100.64.0.5/x 'https://[::1]/x' 'https://[::ffff:127.0.0.1]/x' https://0.0.0.0/x https://2130706433/x https://127.1/x https://0x7f.0.0.1/x \
         https://evil.test/x https://evil2.test/x https://evil3.test/x https://rebind.test/x https://v6.test/x https://mapped.test/x https://tail.test/x \
         http://intranet.local/x https://servico.internal/x https://app.localhost/x; do bloq "$u"; done
igual "$(hits /dolar)" "$H0" 'nenhum dos destinos bloqueados chegou a fazer requisição'
# redirecionamentos: cada salto é revalidado
cria rd1 url="$H/redir?para=/dolar" caminho=USDBRL.bid modelo='redir {valor}'
atual rd1; igual "$(cache rd1)" 'redir 5.1234' 'redirecionamento para o mesmo servidor funciona'
cria rd2 url="$H/redir?para=https://evil2.test/x" caminho=x; out=$(TT_LETREIRO_HOSTS="x.example=127.0.0.1,evil2.test=10.0.0.5" py testar rd2 2>&1 || true); contem "$out" 'bloqueado' 'redirect para IP privado é bloqueado'
cria rd3 url="$H/redir?para=http://127.0.0.1:$PH/dolar" caminho=x; contem "$(py testar rd3 2>&1 || true)" 'de https para http' 'redirect https→http recusado'
out=$(py testar --arquivo <(printf 'url=%s/loop\ncaminho=x\n' "$H") 2>&1 || true); contem "$out" 'demais' 'laço de redirecionamentos para'
# tempo, tentativas, tamanho e compressão
cria lim1 url="$H/grande?kb=2000" caminho=lixo; contem "$(py testar lim1 2>&1 || true)" 'maior que o limite' 'resposta acima de tamanho_max é recusada'
cria lim2 url="$H/lento?s=3" caminho=ok timeout=1 tentativas=1; t0=$SECONDS; out=$(py testar lim2 2>&1 || true); contem "$out" 'tempo esgotado' 'timeout'; ((SECONDS - t0 <= 4)) || falhou 'o timeout não limitou o tempo'
cria lim3 url="$H/flaky?ate=1" caminho=ok tentativas=2 espera=0 modelo='{valor}'; atual lim3; igual "$(cache lim3)" passou 'tentativa seguinte aproveita (500 → 200)'; igual "$(hits /flaky)" 2 'duas requisições'
cria lim4 url="$H/429" caminho=x tentativas=2 espera=0; h=$(hits /429); py testar lim4 >/dev/null 2>&1 || true; igual "$(hits /429)" "$((h + 2))" '429 também tenta de novo'
cria lim5 url="$H/erro404" caminho=x tentativas=3 espera=0; h=$(hits /erro404); py testar lim5 >/dev/null 2>&1 || true; igual "$(hits /erro404)" "$((h + 1))" '404 não tenta de novo'
cria lim6 url="$H/gzip" caminho=z modelo='{valor}'; atual lim6; igual "$(cache lim6)" comprimido 'gzip é descomprimido'
cria lim7 url="$H/bomba-gzip" caminho=z; contem "$(py testar lim7 2>&1 || true)" 'descomprimida maior que o limite' 'bomba de compressão'
cria lim8 url="$H/xml-bomba" formato=xml caminho='.//t'; contem "$(py testar lim8 2>&1 || true)" 'DOCTYPE/ENTITY recusado' 'XML com entidades (billion laughs) recusado'
out=$(env -u TT_LETREIRO_CA python3 -I "$L" testar lim6 2>&1 || true); contem "$out" 'certificado TLS' 'certificado que não confere é recusado'
py editar lim6 tls_verificar=0 >/dev/null 2>&1; out=$(env -u TT_LETREIRO_CA python3 -I "$L" testar lim6 2>&1 || true); contem "$out" 'comprimido' 'tls_verificar=0 aceita (com aviso)'; contem "$out" 'NÃO será verificado' 'e avisa'
passou 'SSRF: 25 destinos bloqueados sem requisição; redirects revalidados; timeout, tentativas, tamanho, gzip, XML e TLS limitados'
# sanitização do texto remoto
cria at1 url="$H/ataque" caminho=t modelo='{valor}'; cria at2 url="$H/ataque" caminho=t2 modelo='{valor}'; cria at3 url="$H/ataque" caminho=t3 modelo='{valor}'
atual at1 at2 at3
for f in at1 at2 at3; do
  c=$(cru $f)
  [[ $c != *$'\033'* && $c != *$'\007'* && $c != *$'\010'* && $c != *$'\r'* ]] || falhou "$f: escape/controle de terminal no cache"
  [[ $c != *'#['* && $c != *'#('* && $c != *'#{'* ]] || falhou "$f: sintaxe do tmux no cache: $c"
  [[ $c != *$'‮'* && $c != *$'⁩'* ]] || falhou "$f: controle de direção no cache"
done
igual "$(cache at1)" 'ok VERMELHO [fg=red,bold] (touch /tmp/pwn) {pane_pid} RTL fim' 'texto de ataque limpo: sem escapes nem RTL, e o # que abria #[ #( #{ foi tirado (o resto vira texto inofensivo)'
# defesa em profundidade: um cache adulterado também não passa pelo desenhista
cria evil url="$H/valor" caminho=v; atual evil
printf 'MAU \033[31mverm\033[0m \033]52;c;ZWNobyBwd25lZA==\007 #[fg=red] #(touch %s/pwn) #{pane_pid} #S ok\n' "$T" >"$HOME/.cache/tt-ticker/evil"
python3 -I - "$D" "$T/bin" <<'PY' || falhou 'o desenhista deixou passar escape ou sintaxe do tmux de um cache adulterado'
import importlib.util, re, sys, time
sp = importlib.util.spec_from_file_location("lt", sys.argv[1]); lt = importlib.util.module_from_spec(sp); sp.loader.exec_module(lt)
q = lt.janela_roda(lt.montar_roda(lt.ler_conf(), time.time()), 900, 0)
assert "\x1b" not in q and "\x07" not in q, repr(q)
semtags = re.sub(r"#\[fg=#[0-9a-f]{6}\]", "", q)       # só os estilos do próprio tt
i = 0
while i < len(semtags):
    if semtags[i] == "#":
        assert i + 1 < len(semtags) and semtags[i + 1] == "#", "# sozinho (sintaxe do tmux): %r" % semtags[max(0, i - 4):i + 8]
        i += 2
    else:
        i += 1
assert "##(touch" in q and "##[fg=red]" in q, q
PY
[[ ! -e $T/pwn ]] || falhou 'comando injetado foi executado'
passou 'texto remoto não confiável: sem escapes de terminal, sem #[ #( #{, sem controles de direção — no cache e no desenhista'
clique_malicioso=$(py criar cm url="$H/valor" caminho=v clique=url 'clique_alvo=javascript:alert(1)' 2>&1; atual cm; python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["acao"])' "$HOME/.cache/tt-ticker/cm.itens")
contem "$clique_malicioso" bloqueado 'clique=url só aceita http(s): javascript: fica bloqueado'

# ============================================================================================
# 7) Diagnóstico: última tentativa e sucesso, HTTP, latência, falhas seguidas, espera, estados, log rotativo
# ============================================================================================
zerar
cria dg1 url="$H/dolar" caminho=USDBRL.bid modelo='{valor}' ttl=60
cria dg2 url="$H/erro500" caminho=x tentativas=1
cria dg3 url="$H/dolar" caminho=USDBRL.bid ativa=0
cria dg4 url="$H/dolar" caminho=USDBRL.bid perfil=celular
cria dg5 url="$H/dolar" caminho=USDBRL.bid
atual dg1 dg2
igual "$(meta dg1 http)" 200 'HTTP do último pedido'; [[ $(meta dg1 latencia_ms) =~ ^[0-9]+$ ]] || falhou 'latência em ms'
[[ $(meta dg1 sucesso) =~ ^[0-9]+$ && $(meta dg1 tentativa) =~ ^[0-9]+$ ]] || falhou 'última tentativa e último sucesso'
igual "$(meta dg2 http)" 500 'HTTP do erro'; igual "$(meta dg2 falhas)" 1 'falhas seguidas'; contem "$(meta dg2 erro)" 'HTTP 500' 'último erro'
est=$(py listar --tsv | awk -F'\t' '{print $1":"$3}' | paste -sd' ')
for e in dg1:ok dg2:erro dg3:desligada dg4:fora dg5:aguardando; do contem "$est" "$e" "estado $e"; done
touch -d '-1 day' "$HOME/.cache/tt-ticker/dg1"; python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["sucesso"]=d["sucesso"]-86400; json.dump(d,open(p,"w"))' "$HOME/.cache/tt-ticker/dg1.meta"
contem "$(py listar --tsv | awk -F'\t' '$1=="dg1"{print $3}')" velha 'cache de ontem com TTL de 60 s = velha'
contem "$(py listar)" 'ESTADO' 'tabela legível'; contem "$(py listar)" 'HTTP 500' 'com o último erro à vista'
py log dg2 | grep -q 'ERRO http=500' || falhou 'o log tem a falha'; py log dg1 | grep -q 'ok http=200' || falhou 'o log tem o sucesso'
nao_contem "$(py log dg1)" ' dg2 ' 'log filtra por fonte'
# log rotativo em ~/.cache
head -c 300000 /dev/zero | tr '\0' 'x' >"$HOME/.cache/tt-letreiro.log"; atual dg1
[[ -s $HOME/.cache/tt-letreiro.log.1 && $(stat -c %s "$HOME/.cache/tt-letreiro.log") -lt 100000 ]] || falhou 'log não rodou ao passar de 256 KB'
passou 'diagnóstico: tentativa, sucesso, HTTP, latência, falhas seguidas, último erro, estados (ok/velha/erro/desligada/fora/aguardando) e log rotativo'

# ============================================================================================
# 8) Comandos de linha e painel: o MESMO resultado pelo arquivo, pelo comando e pelo painel (assistente)
# ============================================================================================
zerar
mkdir -p "$HOME/.config/tt/letreiro"
cat >"$HOME/.config/tt/letreiro/via-arquivo.conf" <<EOF
versao=1
url=$H/dolar
formato=json
caminho=USDBRL.bid
variacao=USDBRL.pctChange
rotulo=dólar
icone=💵
moeda=R\$
decimais=3
separador=pt
arredondar=truncar
ttl=300
EOF
tt --letreiro-add via-cli url="$H/dolar" caminho=USDBRL.bid variacao=USDBRL.pctChange rotulo=dólar icone=💵 'moeda=R$' decimais=3 separador=pt arredondar=truncar ttl=300 >/dev/null || falhou 'tt --letreiro-add'
R=$T/rascunho.conf; : >"$R"                                # o que o assistente do painel faz, passo a passo
py aplicar "$R" "url=$H/dolar" >/dev/null && py aplicar "$R" formato=json caminho=USDBRL.bid >/dev/null && py aplicar "$R" icone=💵 rotulo=dólar ttl=300 >/dev/null || falhou 'rascunho'
py aplicar "$R" variacao=USDBRL.pctChange 'moeda=R$' decimais=3 separador=pt arredondar=truncar >/dev/null
py salvar "$R" via-painel >/dev/null || falhou 'salvar o rascunho'
norm() { py ler "$1" --campos | cut -f1,2; }
igual "$(norm via-cli)" "$(norm via-arquivo)" 'comando = arquivo'
igual "$(norm via-painel)" "$(norm via-arquivo)" 'painel (rascunho) = arquivo'
for f in via-arquivo via-cli via-painel; do atual $f; done
igual "$(cache via-cli)" "$(cache via-arquivo)" 'mesma linha no letreiro (comando = arquivo)'; igual "$(cache via-painel)" "$(cache via-arquivo)" 'mesma linha no letreiro (painel = arquivo)'
igual "$(cache via-cli)" '💵 dólar R$ 5,123 ▲ 0,5%' 'e é a linha esperada'
passou 'arquivo, comando (--letreiro-add) e painel (assistente: rascunho → salvar) produzem a mesma fonte e a mesma linha'
# verbos
out=$(tt --letreiro-listar); contem "$out" 'via-cli' 'listar'; contem "$(tt --letreiro-listar --tsv)" $'via-cli\t1\tok' 'listar --tsv'
out=$(tt --letreiro-add novo url="$H/texto" formato=texto --testar 2>&1); contem "$out" 'Resultado: primeira linha do texto' 'add --testar mostra o teste'
tt --letreiro-add novo url="$H/texto" >/dev/null 2>&1 && falhou 'add de nome repetido deveria falhar'
tt --letreiro-editar novo ttl=45 modelo='[{valor}]' >/dev/null || falhou editar; contem "$(tt --letreiro-editar novo)" 'ttl=45' 'editar sem pares mostra o arquivo (fora de terminal)'
tt --letreiro-editar novo ttl=1 >/dev/null 2>&1 && falhou 'ttl fora do intervalo deveria ser recusado'
tt --letreiro-editar novo --local ativa=0 >/dev/null || falhou 'editar --local'; [[ -f $HOME/.config/tt/letreiro/local/novo.conf ]] || falhou 'sobrescrita só desta máquina fica em letreiro/local/'
contem "$(py listar --tsv | awk -F'\t' '$1=="novo"{print $3"/"$16}')" 'desligada/1' 'a sobrescrita local desliga só aqui'
tt --letreiro-ativar novo --local >/dev/null; [[ $(py listar --tsv | awk -F'\t' '$1=="novo"{print $3}') != desligada ]] || falhou 'ativar --local'
tt --letreiro-duplicar novo novo-2 >/dev/null || falhou duplicar; [[ -f $HOME/.config/tt/letreiro/novo-2.conf ]] || falhou 'duplicar cria o arquivo'
tt --letreiro-desativar novo-2 >/dev/null; contem "$(py listar --tsv | awk -F'\t' '$1=="novo-2"{print $2}')" 0 'desativar'
tt --letreiro-ativar novo-2 >/dev/null; contem "$(py listar --tsv | awk -F'\t' '$1=="novo-2"{print $2}')" 1 'ativar'
ordem() { py listar --tsv | awk -F'\t' '$2==1{print $1}' | paste -sd, | tr -d '\n'; }
tt --letreiro-mover novo-2 inicio >/dev/null; [[ $(ordem) == novo-2,* ]] || falhou "mover para o início: $(ordem)"
tt --letreiro-mover novo-2 +1 >/dev/null; [[ $(ordem) != novo-2,* ]] || falhou "mover +1: $(ordem)"
tt --letreiro-mover novo-2 fim >/dev/null; [[ $(ordem) == *,novo-2 ]] || falhou "mover para o fim: $(ordem)"
tt --letreiro-rm novo-2 >/dev/null 2>&1 && falhou 'remover sem terminal exige --sim'
tt --letreiro-rm novo-2 --sim >/dev/null || falhou 'rm --sim'; [[ ! -e $HOME/.config/tt/letreiro/novo-2.conf ]] || falhou 'rm apaga o arquivo'
tt --letreiro-testar novo | grep -q 'Estado: ok' || falhou 'testar'; tt --letreiro-log novo | grep -q . || tt --letreiro-log | grep -q . || falhou 'log'
tt --letreiro-testar novo --gravar >/dev/null; igual "$(cache novo)" '[primeira linha do texto]' 'testar --gravar também atualiza o cache'
# exportar → apagar → importar: volta igual
tt --letreiro-exportar via-cli novo >"$T/pacote.txt" || falhou exportar; antes=$(norm via-cli)
tt --letreiro-rm via-cli --sim >/dev/null; tt --letreiro-importar "$T/pacote.txt" >/dev/null || falhou importar
igual "$(norm via-cli)" "$antes" 'exportar/importar devolve a fonte igual'
out=$(tt --letreiro-importar "$T/pacote.txt"); contem "$out" 'já existe' 'importar não sobrescreve sem --sobrescrever'
# catálogo de um clique
contem "$(tt --letreiro-catalogo)" 'euro' 'catálogo lista'; contem "$(tt --letreiro-catalogo)" 'tarefas-atrasadas' 'catálogo: tarefas atrasadas'
for id in euro bitcoin selic ipca ibovespa feriados; do tt --letreiro-catalogo "$id" >/dev/null || falhou "catálogo $id"; done
tt --letreiro-catalogo clima lat=-12.97 lon=-38.5 cidade=Salvador >/dev/null || falhou 'catálogo clima'
tt --letreiro-catalogo rss feed="$H/rss" >/dev/null || falhou 'catálogo rss'
tt --letreiro-catalogo status pagina=status.exemplo.com servico=Exemplo >/dev/null || falhou 'catálogo status'
tt --letreiro-catalogo ci-github repo=dono/projeto >/dev/null || falhou 'catálogo ci'
tt --letreiro-catalogo tarefas-atrasadas >/dev/null || falhou 'catálogo tarefas'; tt --letreiro-catalogo emails-nao-lidos >/dev/null || falhou 'catálogo e-mails'
grep -q '^var.lat=-12.97' "$HOME/.config/tt/letreiro/clima.conf" && grep -q 'latitude={lat}' "$HOME/.config/tt/letreiro/clima.conf" || falhou 'clima: variáveis var.lat/var.lon na fonte'
tt --letreiro-catalogo nao-existe >/dev/null 2>&1 && falhou 'catálogo inexistente deveria falhar'
atual rss; igual "$(cache rss)" $'📰 Manchete A do g1\n📰 Manchete B\n📰 C nao entra' 'catálogo rss: manchetes do feed'
atual tarefas-atrasadas; igual "$(cache tarefas-atrasadas)" '⏰ 3 atrasadas' 'catálogo tarefas atrasadas: dado do próprio tt (--letreiro-dado)'
contem "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["acao"], json.load(open(sys.argv[1]))[0]["alvo"])' "$HOME/.cache/tt-ticker/tarefas-atrasadas.itens")" 'painel tarefas' 'e o clique abre o painel de tarefas'
atual emails-nao-lidos; igual "$(cache emails-nao-lidos)" '' 'e-mails não lidos: zero não aparece (condicao valor>0)'
igual "$(tt --letreiro-dado tarefas-atrasadas)" 0 'tt --letreiro-dado conta de verdade (tarefas atrasadas: nenhuma)'
passou 'comandos: listar, add (--testar), editar (--local), duplicar, ativar/desativar, mover, rm (--sim), testar, log, exportar/importar e o catálogo de um clique'
# ajustes globais
out=$(tt --letreiro-ajustes); contem "$out" ticker_fps 'ajustes listados'
tt --letreiro-ajuste ticker_fps 8 >/dev/null || falhou 'ajuste fps'; igual "$(grep -c '^ticker_fps=8' "$XDG_CONFIG_HOME/tt/config")" 1 'ajuste gravado no config'
tt --letreiro-ajuste ticker_fps 21 >/dev/null 2>&1 && falhou 'fps 21 deveria ser recusado'
tt --letreiro-ajuste ticker_rolagem paginas >/dev/null && tt --letreiro-ajuste ticker_rolagem nada >/dev/null 2>&1 && falhou 'valor fora da lista deveria ser recusado'
tt --letreiro-ajuste ticker_rolagem continua >/dev/null
tt --letreiro-ajuste ticker_veloc 0.05 >/dev/null 2>&1 && falhou 'rolagem abaixo de 0,1 s deveria ser recusada'
tt --letreiro-ajuste ticker_veloc 0.5 >/dev/null || falhou 'rolagem confortável aceita'
tt --letreiro-ajuste ticker_rolagem paginas >/dev/null
tt --letreiro-ajuste ticker_veloc 0.5 >/dev/null 2>&1 && falhou '0,5 s por página deveria ser recusado'
tt --letreiro-ajuste ticker_veloc 8 >/dev/null || falhou '8 s por página aceita'
tt --letreiro-ajuste ticker_veloc 61 >/dev/null 2>&1 && falhou 'mais de 60 s por página deveria ser recusado'
tt --letreiro-ajuste ticker_rolagem continua >/dev/null
[[ -z $(grep '^ticker_veloc=' "$XDG_CONFIG_HOME/tt/config") ]] || falhou 'trocar para rolagem contínua restaura o padrão quando a velocidade de página não cabe'
tt --letreiro-ajuste ticker_separador ' | ' >/dev/null; igual "$(grep '^ticker_separador=' "$XDG_CONFIG_HOME/tt/config")" 'ticker_separador= | ' 'separador com espaços'
tt --letreiro-ajuste ticker_ordem peso >/dev/null; tt --letreiro-ajuste ticker_largura 60 >/dev/null; tt --letreiro-ajuste ticker_ligado 0 >/dev/null
tt --letreiro-ajuste inexistente 1 >/dev/null 2>&1 && falhou 'ajuste desconhecido'
tt --letreiro-ajuste ticker_fps '' >/dev/null; [[ -z $(grep '^ticker_fps=' "$XDG_CONFIG_HOME/tt/config") ]] || falhou 'valor vazio volta ao padrão (apaga a chave)'
igual "$(python3 -I "$D" quadro 140)" '' 'ticker_ligado=0: o slot do letreiro some'
sed -i '/^ticker_ligado=/d' "$XDG_CONFIG_HOME/tt/config"
# separador, ordem por peso e largura máxima, vistos pelo desenhista
zerar
cria w1 url="$H/valor?v=a" caminho=v modelo='W1' peso=1 ordem=10; cria w2 url="$H/valor?v=b" caminho=v modelo='W2' peso=3 ordem=20; cria w3 url="$H/valor?v=c" caminho=v modelo='W3' peso=2 ordem=30
atual w1 w2 w3
igual "$(py linha)" 'W1 • W2 • W3' 'ordem manual (campo ordem)'
r() { python3 -I - "$D" <<'PY2'
import importlib.util, sys, time
sp = importlib.util.spec_from_file_location("lt", sys.argv[1]); lt = importlib.util.module_from_spec(sp); sp.loader.exec_module(lt)
print("".join(c for c, _e in lt.montar_roda(lt.ler_conf(), time.time()).cel))
PY2
}
igual "$(r)" 'W1 • W2 • W3 • W2 • W3 • W2' 'peso = quantas vezes aparece por volta (W2 3x, W3 2x), espalhadas'
printf 'ticker_ordem=peso\nticker_separador= | \n' >>"$XDG_CONFIG_HOME/tt/config"
igual "$(r)" 'W2 | W3 | W1 | W2 | W3 | W2' 'ordem por peso e separador próprio'
printf 'ticker_ordem=aleatoria\n' >>"$XDG_CONFIG_HOME/tt/config"; [[ $(r | tr -d ' ' | tr '|' '\n' | sort | uniq -c | tr -s ' ' | paste -sd,) == *'3 W2'* ]] || falhou 'ordem aleatória mantém os pesos'
sed -i '/^ticker_ordem=/d;/^ticker_separador=/d' "$XDG_CONFIG_HOME/tt/config"
q=$(python3 -I - "$D" <<'PY2'
import importlib.util, sys, time
sp = importlib.util.spec_from_file_location("lt", sys.argv[1]); lt = importlib.util.module_from_spec(sp); sp.loader.exec_module(lt)
cfg = dict(lt.ler_conf(), ticker_largura="20")
print(lt.quadro(cfg, 200, False, time.time(), 20, 6))
PY2
)
python3 -I -c 'import re,sys; t=re.sub(r"#\[[^\]]*\]","",sys.argv[1]); assert len(t)<=20+12+4, len(t)' "$q" || falhou "ticker_largura=20 deveria limitar o slot: [$q]"
passou 'ajustes globais: validação, gravação no config, ordem (manual/peso/aleatória), peso, separador, largura máxima e o interruptor da máquina'

# ============================================================================================
# 9) Propagação pela rede: o cadastro das fontes globais viaja como o de demandas (a mudança mais nova vence,
#    lápides não ressuscitam, sobrescrita por máquina), sem nunca copiar segredos
# ============================================================================================
zerar
B=$T/homeB; mkdir -p "$B/.config/tt" "$B/.secrets" "$B/rt"; chmod 700 "$B/.secrets"; printf 'nome=B\nindicadores=0\n' >"$B/.config/tt/config"
inB() { HOME=$B XDG_CONFIG_HOME=$B/.config TT_RT=$B/rt TT_MACHINE=B python3 -I "$L" "$@"; }
tempo() { TT_HORA_AGORA=$1 py "${@:2}"; }
SEG='ABC-token-9f3k'; printf '%s' "$SEG" >"$HOME/.secrets/api"; chmod 600 "$HOME/.secrets/api"
TT_HORA_AGORA=1000 py criar g1 url="$H/valor?v=1" caminho=v modelo='g1 A {valor}' escopo=global >/dev/null
TT_HORA_AGORA=1000 py criar g2 url="$H/eco" auth=bearer segredo=@api caminho=auth escopo=global >/dev/null
TT_HORA_AGORA=1000 py criar l1 url="$H/valor?v=9" caminho=v >/dev/null
pac=$(py pacote)
contem "$pac" '@@fonte g1 mudada=1000' 'o pacote leva a fonte global com a hora da mudança'; contem "$pac" '@@fonte g2 ' 'e a que usa segredo (só a referência)'
nao_contem "$pac" '@@fonte l1 ' 'fonte local nunca sai da máquina'; nao_contem "$pac" "$SEG" 'segredo nunca viaja'; contem "$pac" 'segredo=@api' 'só o nome do arquivo de segredo'
printf '%s\n' "$pac" | inB receber >/dev/null
[[ -f $B/.config/tt/letreiro/g1.conf && -f $B/.config/tt/letreiro/g2.conf && ! -e $B/.config/tt/letreiro/l1.conf ]] || falhou 'B deveria ter g1 e g2, e não l1'
grep -q '^mudada=1000' "$B/.config/tt/letreiro/g1.conf" || falhou 'a hora da mudança é preservada na chegada'
out=$(inB testar g2 2>&1 || true); contem "$out" 'não encontrado' 'em B o segredo não existe (nunca é copiado)'; [[ ! -e $B/.secrets/api ]] || falhou 'segredo apareceu em B'
# a mudança mais nova vence (nos dois sentidos) e uma máquina atrasada nunca desfaz a mudança nova
TT_HORA_AGORA=2000 inB editar g1 modelo='g1 B {valor}' >/dev/null
inB pacote | py receber >/dev/null; contem "$(py ler g1)" 'g1 B' 'A recebeu a mudança mais nova (feita em B)'
TT_HORA_AGORA=1500 py editar g1 ttl=77 >/dev/null; py pacote | inB receber >/dev/null
contem "$(inB ler g1)" 'g1 B' 'B ignorou a mudança mais velha de A'; nao_contem "$(inB ler g1)" 'ttl=77' 'e não a aplicou'
inB pacote | py receber >/dev/null; nao_contem "$(py ler g1)" 'ttl=77' 'A, que ficou atrás, adota a versão mais nova'
# lápide: remover em A remove em B e nada ressuscita fonte removida, a não ser uma recriação mais nova
TT_HORA_AGORA=3000 py remover g1 >/dev/null; contem "$(py pacote)" '@@fonte g1 mudada=3000 removida=1' 'a remoção vira lápide no pacote'
py pacote | inB receber >/dev/null; [[ ! -e $B/.config/tt/letreiro/g1.conf ]] || falhou 'B deveria ter removido g1'
printf '@@fonte g1 mudada=2500\n%s\n@@fim\n' "$(inB ler g1 2>/dev/null; printf 'url=%s/valor?v=1\nescopo=global\n' "$H")" | inB receber >/dev/null
[[ ! -e $B/.config/tt/letreiro/g1.conf ]] || falhou 'pacote mais velho que a lápide não pode ressuscitar a fonte'
printf '@@fonte g1 mudada=3500\nurl=%s/valor?v=1\ncaminho=v\nescopo=global\n@@fim\n' "$H" | inB receber >/dev/null
[[ -f $B/.config/tt/letreiro/g1.conf ]] || falhou 'recriação mais nova que a lápide vale'
# sobrescrita por máquina: B desliga g2 só lá; mudanças globais seguintes chegam, a escolha de B fica
TT_HORA_AGORA=4000 inB editar g2 --local ativa=0 >/dev/null; [[ -f $B/.config/tt/letreiro/local/g2.conf ]] || falhou 'sobrescrita local em letreiro/local/'
TT_HORA_AGORA=4100 py editar g2 ttl=123 >/dev/null; py pacote | inB receber >/dev/null
contem "$(inB ler g2 --campos | awk -F'\t' '$1=="ttl"||$1=="ativa"{print $1"="$2}' | paste -sd,)" 'ttl=123' 'a mudança global chegou'
contem "$(inB ler g2 --campos | awk -F'\t' '$1=="ativa"{print $2}')" 0 'e a escolha local de B (desligada) continua valendo'
nao_contem "$(inB pacote)" 'ativa=0' 'a sobrescrita local nunca é propagada'
# uma fonte local de B com o mesmo nome de uma global que chega: a local ganha
inB criar onlyb url="$H/valor?v=5" caminho=v >/dev/null
printf '@@fonte onlyb mudada=9999\nurl=%s/valor?v=1\ncaminho=v\nescopo=global\n@@fim\n' "$H" | inB receber 2>&1 | grep -q 'local com esse nome' || falhou 'fonte local com o mesmo nome deveria vencer'
# pacotes hostis são recusados
ataque() { printf '%s\n' "$1" | inB receber 2>&1; }
contem "$(ataque $'@@fonte ../../evil mudada=9\nurl=https://x.example/\nescopo=global\n@@fim')" 'nome inválido' 'nome com ../ recusado'; [[ ! -e $B/evil.conf && ! -e $T/evil.conf ]] || falhou 'escreveu fora da pasta'
contem "$(ataque $'@@fonte cred mudada=9\nurl=https://x.example/\nheader=Authorization: Bearer zzz123\nescopo=global\n@@fim')" 'recusada' 'credencial literal recusada na chegada'
contem "$(ataque $'@@fonte priv mudada=9\nurl=https://10.0.0.1/x\nescopo=global\n@@fim')" 'bloqueado' 'URL privada recusada na chegada'
contem "$(ataque $'@@fonte chave mudada=9\nurl=https://x.example/\ncomando=rm -rf\nescopo=global\n@@fim')" 'recusada' 'chave desconhecida recusada'
contem "$(ataque $'@@fonte loc mudada=9\nurl=https://x.example/\n@@fim')" 'só fontes globais' 'pacote sem escopo=global não entra'
[[ ! -e $B/.config/tt/letreiro/cred.conf && ! -e $B/.config/tt/letreiro/priv.conf && ! -e $B/.config/tt/letreiro/chave.conf ]] || falhou 'fonte hostil foi gravada'
passou 'propagação: global viaja, local não; a mais nova vence; lápide não ressuscita; sobrescrita local fica; segredo nunca copiado; pacote hostil recusado'
# pela rede de verdade (ssh de mentira que entra em B): propaga ao cadastrar e puxa o que B tem de mais novo
printf 'maquinab.test usuario B\n' >"$XDG_CONFIG_HOME/tt/maquinas"
cat >"$T/bin/ssh" <<EOF
#!/bin/bash
cmd=\${@: -1}
export HOME=$B XDG_CONFIG_HOME=$B/.config TT_RT=$B/rt TT_MACHINE=B TT_DIR=$T/pkg
case \$cmd in
  *--receber-letreiro*) exec "$T/pkg/tt" --receber-letreiro ;;
  *--letreiro-pacote*) exec "$T/pkg/tt" --letreiro-pacote ;;
esac
exit 1
EOF
chmod +x "$T/bin/ssh"
tt --letreiro-add rede1 url="$H/valor?v=1" caminho=v escopo=global >/dev/null || falhou 'add global'
for _ in $(seq 1 40); do [[ -f $B/.config/tt/letreiro/rede1.conf ]] && break; sleep 0.25; done
[[ -f $B/.config/tt/letreiro/rede1.conf ]] || falhou 'cadastrar uma fonte global deveria propagá-la (ssh)'
TT_HORA_AGORA=$(( $(date +%s) + 600 )) inB criar rede2 url="$H/valor?v=2" caminho=v escopo=global >/dev/null
tt --puxar-letreiro >/dev/null 2>&1; [[ -f $HOME/.config/tt/letreiro/rede2.conf ]] || falhou '--puxar-letreiro deveria trazer a fonte global criada em B'
tt --letreiro-rm rede1 --sim >/dev/null; for _ in $(seq 1 40); do [[ ! -f $B/.config/tt/letreiro/rede1.conf ]] && break; sleep 0.25; done
[[ ! -f $B/.config/tt/letreiro/rede1.conf ]] || falhou 'remover uma fonte global deveria propagar a remoção'
passou 'ssh: cadastrar propaga, --puxar-letreiro traz a mais nova, remover propaga a lápide'
rm -f "$T/bin/ssh" "$XDG_CONFIG_HOME/tt/maquinas"

# ============================================================================================
# 10) Com um tmux de verdade (isolado): clique no letreiro (url, copiar, painel, pausa), painel por teclado e
#     mouse, e o assistente de ponta a ponta
# ============================================================================================
rm -f "$T/bin/tmux"                                  # daqui em diante o tmux é o isolado (TMUX_TMPDIR do teste)
instalar_isolado
D=$TT_DIR/letreiro-tt.py; L=$TT_DIR/letreiro-fontes.py
printf '#!/bin/sh\ncat >"%s/clip.txt"\n' "$T" >"$T/bin/wl-copy"; printf '#!/bin/sh\necho "$1" >>"%s/aberto.txt"\n' "$T" >"$T/bin/xdg-open"; chmod +x "$T/bin/wl-copy" "$T/bin/xdg-open"
export WAYLAND_DISPLAY=wayland-teste
zerar
printf 'ticker_rolagem=paginas\nticker_veloc=3600\nticker_fps=1\nnavegador=sistema\ncopia_entre_maquinas=0\nfaixa_notif=1\n' >>"$XDG_CONFIG_HOME/tt/config"
cria cl1 url="$H/valor?v=1" caminho=v modelo='ALFA-LONGO-AAAAAA' clique=url clique_alvo=https://exemplo.com/alfa ordem=10
cria cl2 url="$H/valor?v=2" caminho=v modelo='BRAVO-LONGO-BBBBBB' clique=copiar clique_alvo=copiado-bravo ordem=20
cria cl3 url="$H/valor?v=3" caminho=v modelo='CHARLIE-LONGO-CCCC' clique=painel clique_alvo=tarefas ordem=30
cria cl4 url="$H/valor?v=4" caminho=v modelo='DELTA-LONGO-DDDDDD' ordem=40
cria cl5 url="$H/valor?v=5" caminho=v modelo='ECO-LONGO-EEEEEEEEEE' clique=url 'clique_alvo=javascript:alert(1)' ordem=50
atual
tmux -f "$HOME/.tmux.conf" new -d -s s -x 220 -y 30 'sleep 900' 2>/dev/null; sleep 2
anexar x 220 34 s; sleep 4
faixa() { fora capture-pane -p -t "$1" | tail -1; }
a=$(faixa x); contem "$a" 'ALFA-LONGO' 'o letreiro aparece na faixa'; contem "$a" 'DELTA-LONGO' 'com as quatro fontes'
coluna() { python3 -I - "$D" "$1" "$2" <<'PY2'
import importlib.util, sys
sp = importlib.util.spec_from_file_location("lt", sys.argv[1]); lt = importlib.util.module_from_spec(sp); sp.loader.exec_module(lt)
linha, alvo = sys.argv[2], sys.argv[3]
i = linha.index(alvo)
print(sum(lt.larg(c) for c in linha[:i]) + 4)   # +4: meio do trecho (as 4 primeiras letras)
PY2
}
cliente=$(tmux list-clients -F '#{client_name}' | head -1); painel=$(tmux display -p -t s '#{pane_id}')
[[ -n $cliente ]] || falhou 'sem cliente tmux para o clique'
# o desenhista grava a geometria a cada quadro (aqui 1 por segundo) e só começa depois que o tmux o inicia: espera até 15 s
tmux refresh-client -S -t "$cliente" # agenda explicitamente o #() após a sessão ser anexada
for _ in $(seq 60); do ls "$TT_RT"/tt-letreiro-*.geo >/dev/null 2>&1 && break; sleep 0.25; done
ls "$TT_RT"/tt-letreiro-*.geo >/dev/null 2>&1 || falhou 'o desenhista não deixou a geometria do slot para o clique'
clicar() { tt --clique letreiro "$cliente" "$painel" "$HOME" "$(coluna "$a" "$1")"; sleep 0.7; }
: >"$T/aberto.txt"; clicar ALFA-LONGO; contem "$(cat "$T/aberto.txt")" 'https://exemplo.com/alfa' 'clique no item com clique=url abre a URL (seletor/navegador)'
rm -f "$T/clip.txt"; clicar BRAVO-LONGO; igual "$(cat "$T/clip.txt" 2>/dev/null)" 'copiado-bravo' 'clique no item com clique=copiar copia o texto'
: >"$T/aberto.txt"; clicar ECO-LONGO; [[ ! -s $T/aberto.txt ]] || falhou 'clique_alvo=javascript: nunca é aberto'
[[ ! -e $TT_RT/tt-letreiro-pausa ]] || falhou 'sem clique ainda, sem pausa'
clicar DELTA-LONGO; [[ -e $TT_RT/tt-letreiro-pausa ]] || falhou 'clique em item sem ação pausa o letreiro'
clicar DELTA-LONGO; [[ ! -e $TT_RT/tt-letreiro-pausa ]] || falhou 'e o segundo clique continua'
printf 'ticker_pausa=nunca\n' >>"$XDG_CONFIG_HOME/tt/config"; clicar DELTA-LONGO; [[ ! -e $TT_RT/tt-letreiro-pausa ]] || falhou 'ticker_pausa=nunca desliga a pausa por clique'
sed -i '/^ticker_pausa=/d' "$XDG_CONFIG_HOME/tt/config"
tt --clique letreiro "$cliente" "$painel" "$HOME" 0; sleep 0.7; [[ ! -e $TT_RT/tt-letreiro-pausa && ! -s $T/aberto.txt ]] || falhou 'clique fora do texto (coluna 0) não faz nada'
pid=$(tmux list-clients -F '#{client_pid}' | head -1)
tmux refresh-client -S -t "$cliente" # a leitura direta do desenhista deve usar a geometria do quadro atual
igual "$(python3 -I "$D" clique "$pid" "$(coluna "$a" CHARLIE-LONGO)")" $'painel\ttarefas' 'a ação painel diz qual painel do tt abrir'
passou 'clique no letreiro: url (só http/https), copiar, painel e pausa; fora do texto nada'
# pausa de verdade: congela o quadro; o clique de novo devolve
printf 'ticker_rolagem=continua\nticker_veloc=0.2\nticker_fps=6\n' >>"$XDG_CONFIG_HOME/tt/config"; sleep 3
p1=$(faixa x); sleep 1.5; p2=$(faixa x); [[ $p1 != "$p2" ]] || falhou 'o letreiro deveria rolar'
python3 -I "$D" pausar >/dev/null; sleep 2; p1=$(faixa x); sleep 1.5; p2=$(faixa x); [[ $p1 == "$p2" ]] || falhou 'pausado, o quadro tem que ficar parado'
python3 -I "$D" pausar >/dev/null; sleep 2; p1=$(faixa x); sleep 1.5; p2=$(faixa x); [[ $p1 != "$p2" ]] || falhou 'depois de continuar, rola de novo'
passou 'pausa/continua congela e devolve o letreiro'
sed -i '/^ticker_rolagem=continua/d;/^ticker_veloc=0.2/d;/^ticker_fps=6/d' "$XDG_CONFIG_HOME/tt/config"
# pelo painel (teclado): ^a liga/desliga, ^k/^j reordenam, ^d duplica, F2 abre o formulário, esc sai
cap() { tmux capture-pane -p -t "$1" 2>/dev/null; }
espera() { local alvo=$1 padrao=$2 i; for i in $(seq 1 60); do [[ $(cap "$alvo") == *"$padrao"* ]] && return 0; sleep 0.2; done; falhou "esperava ver [$padrao] no painel $alvo: $(cap "$alvo" | tail -12)"; }
ativa() { py listar --tsv | awk -F'\t' -v n="$1" '$1==n{print $2}'; }
source "$RAIZ/tests/fzf-esperar.sh"
aguardar_ui() {
  local i
  for i in {1..60}; do eval "$1" && return 0; sleep 0.2; done
  falhou "$2: $(cap ui | head -20)"
}
cl2_selecionada() { cap ui | grep -Eq '^[[:space:]]*▌.* cl2([[:space:]]|$)'; }
tmux new -d -s ui -x 150 -y 40 "$FZF_UI_ENV $TT_DIR/tt --letreiro-ui" ; espera ui 'Nova fonte'; espera ui 'cl3'
contem "$(cap ui)" 'Catálogo' 'painel: catálogo'; contem "$(cap ui)" 'Ajustes globais' 'painel: ajustes'; contem "$(cap ui)" 'Pré-visualizar' 'painel: prévia'
contem "$(cap ui)" 'cl3' 'painel lista as fontes'; contem "$(cap ui)" 'ok' 'com o estado de cada uma'
tmux send-keys -t ui "'cl2 !cl2-" # casamento exato, excluindo a cópia que será criada abaixo
aguardar_ui 'cl2_selecionada' 'filtro não selecionou cl2'
fzf_recarregar C-a
aguardar_ui '[[ $(ativa cl2) == 0 ]] && cl2_selecionada && cap ui | grep -Eq "▌.*○.* cl2([[:space:]]|$)"' '^a não desligou a fonte e recarregou a lista'
fzf_recarregar C-a
aguardar_ui '[[ $(ativa cl2) == 1 ]] && cl2_selecionada && cap ui | grep -Eq "▌.*●.* cl2([[:space:]]|$)"' '^a não religou a fonte e recarregou a lista'
fzf_recarregar C-j
aguardar_ui '[[ $(py listar --tsv | awk -F"\t" '\''$2==1{print $1}'\'' | paste -sd,) == cl1,cl3,cl2,* ]] && cl2_selecionada' '^j não desceu a fonte na roda'
fzf_recarregar C-k
aguardar_ui '[[ $(py listar --tsv | awk -F"\t" '\''$2==1{print $1}'\'' | paste -sd,) == cl1,cl2,cl3,* ]] && cl2_selecionada' '^k não subiu a fonte na roda'
fzf_recarregar C-d
aguardar_ui '[[ -f $HOME/.config/tt/letreiro/cl2-2.conf ]] && cl2_selecionada' '^d não duplicou a fonte'
tmux send-keys -t ui F2; espera ui 'url'; contem "$(cap ui)" 'salvar' 'F2 abre o formulário de todos os campos'; contem "$(cap ui)" 'https://x.example' 'com os valores atuais'; nao_contem "$(cap ui)" '|| https' 'sem lixo na lista'
tmux send-keys -t ui Escape; sleep 1
tmux send-keys -t ui C-u; sleep 0.3; tmux send-keys -t ui Escape; sleep 1; tmux has-session -t ui 2>/dev/null && { tmux send-keys -t ui Escape; sleep 1; }
tmux has-session -t ui 2>/dev/null && falhou 'esc deveria fechar o painel'
passou 'painel por teclado: ^a liga/desliga, ^j/^k reordenam, ^d duplica, F2 abre o formulário, esc fecha'
# mouse no painel: duplo clique numa fonte abre o menu de ações (SGR, como o fzf recebe do terminal)
tmux new -d -s ui2 -x 150 -y 40 "$TT_DIR/tt --letreiro-ui"; espera ui2 'Nova fonte'; espera ui2 'cl3'
y=$(cap ui2 | grep -n ' cl3 ' | head -1 | cut -d: -f1); [[ -n $y ]] || falhou 'não achei a linha da fonte cl3 para clicar'
tmux send-keys -t ui2 -l "$(printf '\033[<0;12;%dM\033[<0;12;%dm\033[<0;12;%dM\033[<0;12;%dm' "$y" "$y" "$y" "$y")"; espera ui2 'Testar agora'
contem "$(cap ui2)" 'Testar agora' 'duplo clique numa fonte abre o menu de ações (Testar agora, Editar, Duplicar…)'
tmux kill-session -t ui2 2>/dev/null
passou 'painel por mouse: duplo clique abre o menu da fonte'
# o assistente de ponta a ponta: URL → resposta → campo no fzf → rótulo/TTL/modelo → teste ao vivo → salvar
tmux new -d -s as -x 150 -y 45 "$TT_DIR/tt --letreiro-assistente; sleep 20"; espera as 'endereço'
tmux send-keys -t as "$H/dolar" Enter; espera as 'A API pede chave'
tmux send-keys -t as Enter; espera as 'campo ›'
contem "$(cap as)" 'USDBRL' 'o assistente mostra os campos da resposta para escolher'
tmux send-keys -t as 'bid'; sleep 0.5; tmux send-keys -t as Enter; espera as 'nome da fonte'
tmux send-keys -t as 'wiz1' Enter; sleep 0.3; tmux send-keys -t as '💵' Enter; sleep 0.3; tmux send-keys -t as 'dólar' Enter; sleep 0.3
tmux send-keys -t as '300' Enter; sleep 0.3; tmux send-keys -t as Enter; espera as 'Teste ao vivo'; espera as 'Salvar a fonte wiz1'
contem "$(cap as)" '5.1234' 'o teste ao vivo mostra o valor antes de salvar'
[[ ! -e $HOME/.config/tt/letreiro/wiz1.conf ]] || falhou 'nada é salvo antes da confirmação'
tmux send-keys -t as Enter; espera as 'salva e ativa'
[[ -f $HOME/.config/tt/letreiro/wiz1.conf ]] || falhou 'o assistente deveria salvar a fonte'
c=$(py ler wiz1 --campos | cut -f1,2); contem "$c" $'caminho\tUSDBRL.bid' 'campo escolhido no fzf'; contem "$c" $'rotulo\tdólar' 'rótulo'; contem "$c" $'ttl\t300' 'ttl'; contem "$c" $'url\t'"$H/dolar" 'url'
tmux kill-session -t as 2>/dev/null
passou 'criar uma fonte só pela tela (assistente), testando ao vivo antes de salvar, sem editar arquivo'
# o formulário de edição (todos os campos): editar texto, ligar/desligar, escolher uma opção, testar e salvar
tmux new -d -s fm -x 150 -y 45 "$TT_DIR/tt --letreiro-editar wiz1; sleep 20"; espera fm 'wiz1 ›'
espera_item() {
  local i
  for i in {1..60}; do cap "$1" | grep -Eq "^[[:space:]]*[▌>][[:space:]]+$2([[:space:]]|$)" && return 0; sleep 0.2; done
  falhou "item $2 não ficou selecionado: $(cap "$1")"
}
campo_selecionado() {
  tmux send-keys -t fm C-u
  tmux send-keys -t fm "'$1"
  espera_item fm "$1"
}
campo_selecionado ttl; tmux send-keys -t fm Enter; espera fm 'ttl ='
tmux send-keys -t fm C-u; tmux send-keys -t fm 45 Enter; espera fm 'ttl             45'
campo_selecionado tls_verificar; tmux send-keys -t fm Enter; espera fm 'tls_verificar   0'
campo_selecionado metodo; tmux send-keys -t fm Enter; espera fm 'metodo ›'; tmux send-keys -t fm POST; espera_item fm POST; tmux send-keys -t fm Enter; espera fm 'metodo          POST'
contem "$(cap fm)" 'metodo          POST' 'campo com opções abre a lista e grava a escolha'
[[ $(py ler wiz1 --campos | awk -F'\t' '$1=="ttl"{print $2}') == 300 ]] || falhou 'nada vale antes de salvar (o formulário trabalha num rascunho)'
tmux send-keys -t fm C-t; espera fm 'continua'; tmux send-keys -t fm Enter; espera fm 'wiz1 ›'
tmux send-keys -t fm C-s; espera fm 'continua'; tmux send-keys -t fm Enter; sleep 1.5
c=$(py ler wiz1 --campos | cut -f1,2); contem "$c" $'ttl\t45' 'ttl salvo pelo formulário'; contem "$c" $'metodo\tPOST' 'método salvo'; contem "$c" $'tls_verificar\t0' 'tls_verificar salvo'
tmux kill-session -t fm 2>/dev/null
passou 'formulário: texto, booleano, opção, teste ao vivo e salvar (só depois do teste)'
# editar uma fonte NATIVA grava só a diferença (a definição de fábrica continua valendo); vazio explícito desfaz um padrão
py editar dolar ttl=99 >/dev/null; grep -q '^ttl=99' "$HOME/.config/tt/letreiro/dolar.conf" && [[ $(grep -c '^url=\|^caminho=\|^formato=' "$HOME/.config/tt/letreiro/dolar.conf") == 0 ]] || falhou 'personalizar a nativa deve gravar só o que mudou (nada da definição de fábrica)'
contem "$(py ler dolar --campos | cut -f1,2 | paste -sd,)" $'url\thttps://economia.awesomeapi.com.br' 'a URL de fábrica continua valendo'
py editar dolar separador= >/dev/null; igual "$(py ler dolar --campos | awk -F'\t' '$1=="separador"{print $2}')" '' 'vazio explícito desfaz o padrão pt da nativa'
grep -q '^separador=$' "$HOME/.config/tt/letreiro/dolar.conf" || falhou 'o vazio explícito precisa ficar no arquivo'
R2=$T/rasc2.conf; py rascunho dolar >"$R2"; py aplicar "$R2" ttl=77 >/dev/null; py salvar "$R2" dolar >/dev/null
[[ $(grep -c '^url=' "$HOME/.config/tt/letreiro/dolar.conf") == 0 ]] && contem "$(py ler dolar --campos | awk -F'\t' '$1=="ttl"{print $2}')" 77 || falhou 'salvar o rascunho de uma nativa grava só a diferença'
passou 'nativas: personalizar grava só a diferença para o padrão de fábrica'

fora kill-server 2>/dev/null; tmux kill-server 2>/dev/null

# ============================================================================================
# 11) Contratos estáticos: pacote, rota do clique, menu, matriz de interações e documentação
# ============================================================================================
R=$RAIZ
rg -q 'ARQUIVOS_FONTE=\(.*letreiro-fontes\.py' "$R/tt" || falhou 'letreiro-fontes.py precisa estar em ARQUIVOS_FONTE (senão a atualização instala um pacote incompleto)'
[[ -f $R/letreiro-fontes.py ]] && python3 -m py_compile "$R/letreiro-fontes.py" "$R/letreiro-tt.py" "$R/tests/servidor_falso.py" || falhou 'sintaxe Python'
rg -q 'range=user\|letreiro' "$R/letreiro-tt.py" && rg -q '^\s+letreiro\) letreiro_clique' "$R/tt" || falhou 'o range user|letreiro desenhado precisa de rota em clique()'
rg -q 'letreiro\) eval .*--letreiro-ui' "$R/tt" || falhou 'o aviso de falhas (ação letreiro) precisa abrir o painel (notif_abrir)'
rg -q $'^j\t📰 Letreiro' "$R/tt" || falhou 'item Letreiro no menu ⋯ do painel'
for k in 'enter' 'double-click' 'right-click' 'ctrl-n' 'f2' 'ctrl-t' 'ctrl-a' 'ctrl-d' 'ctrl-k' 'ctrl-j' 'ctrl-l' 'ctrl-x' 'ctrl-g' 'ctrl-b' 'ctrl-p' 'ctrl-r' 'esc'; do
  rg -q -- "--bind=\"$k:transform\(\\\$a " "$R/tt" || falhou "painel sem a tecla/mouse $k"
done
# teclado, mouse e menu chegam às mesmas ações (o despachante devolve o comando do fzf)
for ev in nova catalogo ajustes previa; do [[ -n $(tt --letreiro-acao "$ev" '') ]] || falhou "despachante sem ação para $ev"; done
for ev in editar testar log duplicar alternar cima baixo apagar enter duplo menu; do [[ -n $(tt --letreiro-acao "$ev" via-cli) ]] || falhou "despachante sem ação para $ev numa fonte"; done
[[ -z $(tt --letreiro-acao editar '+') ]] || falhou 'ação de fonte numa linha de comando do painel deveria ser vazia'
rg -q 'Letreiro \(fontes/APIs\)' "$R/tests/INTERACTIONS.md" || falhou 'matriz tests/INTERACTIONS.md sem o Letreiro'
rg -q '^## Letreiro: fontes \(APIs\)' "$R/README.md" && rg -q 'letreiro/NOME.conf' "$R/README.md" && rg -q 'tt --letreiro-listar' "$R/README.md" || falhou 'README sem a documentação do letreiro'
rg -q 'letreiro-fontes' "$R/skill-tt-terminais.md" || falhou 'skill sem o letreiro'
rg -q -- '--letreiro-listar' <(tt --help) || falhou 'tt --help sem o letreiro'
python3 -I -c '
import importlib.util, sys
sp = importlib.util.spec_from_file_location("lf", sys.argv[1]); lf = importlib.util.module_from_spec(sp); sp.loader.exec_module(lf)
chaves = [c[0] for c in lf.CAMPOS]
assert len(chaves) == len(set(chaves)), "campo repetido no esquema"
readme = open(sys.argv[2]).read()
falta = [k for k in chaves if "`%s`" % k not in readme]
assert not falta, "campos sem documentação no README: %s" % falta
' "$R/letreiro-fontes.py" "$R/README.md" || falhou 'todo campo do esquema precisa estar no README'
passou 'contratos: pacote, rota e menu do clique, teclas do painel, matriz de interações, README e skill'
echo "ok: letreiro — fontes configuráveis (módulo, formatos, auth, agenda, segurança, diagnóstico, CLI, painel, propagação, clique)"
