#!/usr/bin/env bash
# tt-teste: sozinho (painel/tela sob carga oscila: roda sem outros testes disputando a máquina)
# Catálogo de fábrica do letreiro: ~150 fontes validadas na rede real, que vêm DESLIGADAS no pacote
# (letreiro-catalogo.json) e que o painel liga, desliga, configura, tira da lista e traz de volta; mais os
# modelos que perguntam o que falta. A suíte NÃO usa a rede: cada fonte roda contra a resposta real guardada em
# tests/letreiro-amostras (tests/letreiro_catalogo_offline.py); a ferramenta de manutenção que fala com a rede
# de verdade é tests/letreiro_catalogo_rede.py (não faz parte da suíte).
source "$(dirname "$0")/lib.sh"; isolar
tt() { "$TT" "$@"; }
L=$T/pkg/letreiro-fontes.py
py() { python3 -I "$L" "$@"; }
igual() { [[ $1 == "$2" ]] || falhou "$3: esperava [$2], veio [$1]"; }
contem() { [[ $1 == *"$2"* ]] || falhou "$3: esperava conter [$2], veio [$1]"; }
nao_contem() { [[ $1 != *"$2"* ]] || falhou "$3: NÃO deveria conter [$2], veio [$1]"; }
ativa() { py listar --tsv --todas | awk -F'\t' -v n="$1" '$1==n{print $2}'; }
zerar() { rm -rf "$HOME/.config/tt/letreiro" "$HOME/.cache/tt-ticker" "$HOME/.cache/tt-letreiro.log"* "$HOME/.cache/tt-letreiro-vista"; printf 'nome=teste\n' >"$XDG_CONFIG_HOME/tt/config"; }

mkdir -p "$T/bin"
printf '#!/bin/sh\necho "$@" >>"%s/notif.log"\n' "$T" >"$T/bin/notify-send"; chmod +x "$T/bin/notify-send"
export PATH="$T/bin:$PATH"

# servidor https de mentira só para as três fontes que vêm ligadas (nada sai para a rede real)
free_port() { python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
PS=$(free_port)
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout "$T/chave.pem" -out "$T/cert.pem" -days 2 \
  -subj /CN=x.example -addext subjectAltName=DNS:x.example >/dev/null 2>&1 || falhou 'openssl não gerou o certificado de teste'
cp "$RAIZ/tests/servidor_falso.py" "$T/servidor_falso.py"
python3 "$T/servidor_falso.py" "$PS" "$T/cert.pem" "$T/chave.pem" >"$T/srv-https.log" 2>&1 &
for _ in $(seq 1 50); do grep -q pronto "$T/srv-https.log" && break; sleep 0.1; done
grep -q pronto "$T/srv-https.log" || falhou "servidor de mentira não subiu: $(cat "$T/srv-https.log")"
export TT_LETREIRO_TESTE=1 TT_LETREIRO_HOSTS="x.example=127.0.0.1" TT_LETREIRO_CA="$T/cert.pem" TT_LETREIRO_CLIENTES=1 TT_PERFIL=desktop TT_MACHINE=teste
H=https://x.example:$PS
export TT_LETREIRO_REMAP="https://economia.awesomeapi.com.br/json/last/USD-BRL=>$H/dolar;https://g1.globo.com/rss/g1/=>$H/rss;https://feeds.bbci.co.uk/news/world/rss.xml=>$H/rss-bbc"

# ============================================================================================
# 1) o catálogo inteiro, contra respostas reais guardadas (sem rede)
# ============================================================================================
out=$(python3 "$RAIZ/tests/letreiro_catalogo_offline.py" 2>&1) || falhou "catálogo de fábrica: $out"
contem "$out" ' 0 problema(s)' 'o catálogo confere'
n_fab=$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["fabrica"]))' "$RAIZ/letreiro-catalogo.json")
(( n_fab >= 120 )) || falhou "o pacote deveria levar bem mais fontes de fábrica (são $n_fab)"
passou "catálogo de fábrica: $n_fab fontes validadas contra respostas reais, só https, desligadas, sem segredo"

# ============================================================================================
# 2) lista: o padrão mostra só o que está na roda; --todas e os filtros mostram as de fábrica
# ============================================================================================
zerar
igual "$(py listar --tsv | cut -f1 | paste -sd,)" 'dolar,frases,noticias' 'lista padrão: só as três que vêm ligadas'
igual "$(py listar --tsv --todas | wc -l)" "$((n_fab + 3))" '--todas: as de fábrica mais as três'
igual "$(py listar --tsv --ativas | cut -f1 | paste -sd,)" 'dolar,frases,noticias' '--ativas'
igual "$(py listar --tsv --inativas | wc -l)" "$n_fab" '--inativas: todas as de fábrica'
st=$(py listar --tsv --inativas --categoria status | cut -f1 | paste -sd,)
contem "$st" 'status-github' 'filtro por categoria'; nao_contem "$st" 'selic' 'a categoria filtra'
igual "$(py listar --tsv --todas | awk -F'\t' '$1=="euro"{print $19}')" 'moeda' 'a categoria sai no TSV'
cats=$(py categorias | cut -f1 | paste -sd,)
contem "$cats" 'moeda,cripto,economia,bolsa,clima' 'categorias na ordem do catálogo'
info=$(py info euro)
contem "$info" $'origem\tde fábrica' 'info: de fábrica'; contem "$info" $'exemplo\t💶 euro R$' 'info: exemplo validado'; contem "$info" $'validada\t20' 'info: data da validação'
contem "$(tt --letreiro-listar --todas --categoria cripto)" 'ethereum' 'o comando aceita os filtros'
passou 'lista: padrão enxuto; --todas/--ativas/--inativas/--categoria; categorias e info com o exemplo'

# ============================================================================================
# 3) ligar, desligar e configurar uma fonte de fábrica
# ============================================================================================
igual "$(ativa euro)" 0 'euro vem desligada'
[[ ! -e $HOME/.config/tt/letreiro/euro.conf ]] || falhou 'uma fonte de fábrica desligada não tem arquivo seu'
tt --letreiro-ativar euro >/dev/null; igual "$(ativa euro)" 1 'ativar liga'
igual "$(py listar --tsv | cut -f1 | paste -sd,)" 'dolar,frases,noticias,euro' 'e ela entra na lista padrão'
contem "$(cat "$HOME/.cache/tt-ticker/_roda.json")" '"nome": "euro"' 'a roda compilada leva a ligada'
nao_contem "$(cat "$HOME/.cache/tt-ticker/_roda.json")" 'libra' 'e não leva as desligadas'
c=$(grep -v '^#' "$HOME/.config/tt/letreiro/euro.conf" | grep -v '^versao=' | grep . | paste -sd'|')
igual "$c" 'ativa=1' 'ligar grava só a diferença (ativa=1)'
py editar euro ttl=120 'rotulo=€' >/dev/null
c=$(grep -v '^#' "$HOME/.config/tt/letreiro/euro.conf" | sort | paste -sd'|')
contem "$c" 'ttl=120' 'configurar grava o que mudou'; contem "$c" 'rotulo=€' 'o rótulo novo'; nao_contem "$c" 'url=' 'sem congelar a definição de fábrica'
igual "$(py ler euro --campos | awk -F'\t' '$1=="ttl"{print $2}')" 120 'a efetiva usa o que você mudou'
tt --letreiro-desativar euro >/dev/null; igual "$(ativa euro)" 0 'desativar desliga'
igual "$(py listar --tsv | cut -f1 | paste -sd,)" 'dolar,frases,noticias,euro' 'e a que você mexeu continua visível (desligada)'
py ativar libra --local >/dev/null; igual "$(py listar --tsv | awk -F'\t' '$1=="libra"{print $2$16}')" '11' '--local: ligada só nesta máquina (✎)'
passou 'ligar/desligar/configurar uma fonte de fábrica: só a diferença vai para o arquivo; a roda compilada acompanha'

# ============================================================================================
# 4) tirar da lista, trazer de volta pelo catálogo e voltar ao padrão
# ============================================================================================
zerar
out=$(tt --letreiro-rm xkcd --sim 2>&1); contem "$out" 'de fábrica' 'tirar da lista explica que é de fábrica'
py listar --tsv --todas | cut -f1 | grep -qx xkcd && falhou 'xkcd deveria ter saído da lista'
igual "$(py listar --ocultas --tsv | cut -f1)" xkcd 'ficou na lista de tiradas'
contem "$(py catalogo listar --adicionaveis --tsv)" $'xkcd\t' 'o catálogo oferece a que você tirou'
nao_contem "$(py catalogo listar --adicionaveis --tsv | cut -f1 | paste -sd,)" 'libra' 'e só as que você tirou (mais os modelos)'
out=$(tt --letreiro-catalogo xkcd 2>&1); contem "$out" 'instalada e ativa' 'o catálogo traz de volta e liga'
igual "$(ativa xkcd)" 1 'volta ligada'; igual "$(py listar --ocultas --tsv | grep -c .)" 0 'e sai da lista de tiradas'
py editar xkcd ttl=777 >/dev/null; tt --letreiro-restaurar xkcd >/dev/null
igual "$(ativa xkcd)" 0 'voltar ao padrão desliga de novo'; [[ ! -e $HOME/.config/tt/letreiro/xkcd.conf ]] || falhou 'e apaga o arquivo seu'
py listar --tsv --todas | cut -f1 | grep -qx xkcd || falhou 'voltar ao padrão mantém na lista'
tt --letreiro-rm dolar --sim >/dev/null 2>&1; py listar --tsv --todas | cut -f1 | grep -qx dolar || falhou 'as três de sempre nunca saem da lista (voltam ao padrão)'
passou 'tirar da lista, trazer de volta pelo catálogo e voltar ao padrão de fábrica'

# ============================================================================================
# 5) adicionar: modelos perguntam o que falta; nome de fábrica é protegido; "dono/nome" mantém a barra
# ============================================================================================
out=$(tt --letreiro-catalogo cotacao par=EUR-USD --nome meu-par 2>&1); contem "$out" 'meu-par: instalada e ativa' 'modelo cria uma fonte sua'
igual "$(py listar --tsv | awk -F'\t' '$1=="meu-par"{print $19}')" minhas 'e ela fica em "minhas fontes"'
contem "$(py ler meu-par)" 'EUR-USD' 'com a resposta dada'
out=$(py criar euro url=https://x.example/a 2>&1) && falhou 'criar com nome de fábrica deveria recusar'; contem "$out" 'fonte de fábrica' 'a mensagem diz o que fazer'
out=$(py catalogo instalar euro --nome outro 2>&1) && falhou '--nome numa de fábrica deveria recusar'; contem "$out" 'duplicar' 'e aponta o duplicar'
py duplicar euro euro-meu >/dev/null; igual "$(py listar --tsv | awk -F'\t' '$1=="euro-meu"{print $19}')" minhas 'duplicar uma de fábrica cria uma sua'
out=$(python3 -I - "$L" <<'PY2'
import importlib.util, sys
sp = importlib.util.spec_from_file_location("lf", sys.argv[1]); lf = importlib.util.module_from_spec(sp); sp.loader.exec_module(lf)
print(lf.aplicar_vars_url("https://api.github.com/repos/{repo}/releases/latest", {"repo": "tmux/tmux"}))
print(lf.aplicar_vars_url("https://x.example/a/{v}", {"v": "a&b=c?d#e"}))
PY2
)
contem "$out" 'repos/tmux/tmux/releases' 'dono/nome fica com a barra (o GitHub dá 404 com %2F)'
contem "$out" 'a%26b%3Dc%3Fd%23e' 'mas & = ? # continuam codificados'
passou 'modelos, proteção dos nomes de fábrica, duplicar e a barra de dono/nome nas variáveis da URL'

# ============================================================================================
# 6) desligada não busca nada; a migração do indicadores= antigo não cria um arquivo por fonte de fábrica
# ============================================================================================
zerar
printf 'nome=teste\nindicadores=dolar,euro\n' >"$XDG_CONFIG_HOME/tt/config"
py migrar >/dev/null
arqs=$(ls "$HOME/.config/tt/letreiro" | grep '\.conf$' | paste -sd' ')
igual "$arqs" 'dolar.conf euro.conf frases.conf noticias.conf' 'a migração só grava as três de sempre e as que estão na lista (nunca um arquivo por fonte de fábrica)'
igual "$(py listar --tsv | cut -f1 | paste -sd,)" 'dolar,euro,frases,noticias' 'a lista antiga vale: dolar e euro ligadas (frases e noticias aparecem desligadas)'
igual "$(ativa dolar)$(ativa euro)$(ativa frases)$(ativa noticias)$(ativa libra)" '11000' 'indicadores= liga só as listadas'
zerar
out=$(TT_LETREIRO_VERBOSO=1 py atualizar --forcar 2>&1)
for f in dolar frases noticias; do contem "$out" "$f:" "as ligadas atualizam ($f)"; done
for f in euro libra selic bitcoin status-github xkcd; do nao_contem "$out" "$f:" "uma fonte de fábrica desligada não busca nada ($f)"; done
passou 'desligada não busca nada; migrar o indicadores= antigo só mexe nas que já tinham arquivo ou estão na lista'

# ============================================================================================
# 7) painel: seções por categoria, vista com Tab, prévia com o exemplo, ligar com ^a, tirar com ^x e voltar pelo catálogo
# ============================================================================================
zerar
export TT_DIR=$T/pkg
cap() { tmux capture-pane -p -t "$1" 2>/dev/null; }
source "$RAIZ/tests/fzf-esperar.sh"
espera() { local alvo=$1 padrao=$2 i; for i in $(seq 1 60); do [[ $(cap "$alvo") == *"$padrao"* ]] && return 0; sleep 0.2; done; falhou "esperava ver [$padrao] no painel $alvo: $(cap "$alvo" | tail -14)"; }
tmux new -d -s ui -x 160 -y 48 "$FZF_UI_ENV $TT_DIR/tt --letreiro-ui"; espera ui 'Nova fonte'; espera ui 'Na roda (3)'
tela=$(cap ui)
contem "$tela" 'Na roda (3)' 'seção das ligadas'; contem "$tela" 'Disponíveis e desligadas' 'seção das disponíveis'; contem "$tela" 'Moedas (' 'categoria com a contagem'
contem "$tela" 'Vista: todas' 'a vista atual'
fzf_recarregar Tab; espera ui 'Vista: só as que estão na roda'; tela=$(cap ui)
contem "$tela" 'Vista: só as que estão na roda' 'Tab alterna para "na roda"'; nao_contem "$tela" 'Disponíveis e desligadas' 'e esconde as disponíveis'
fzf_recarregar Tab; espera ui 'Vista: só as disponíveis'; tela=$(cap ui)
contem "$tela" 'Vista: só as disponíveis' 'Tab de novo: só as disponíveis'; nao_contem "$tela" 'Na roda (' 'sem a seção das ligadas'
fzf_recarregar Tab; espera ui 'Vista: todas'
tmux send-keys -t ui "'xkcd"; espera ui 'Como aparece'; espera ui '🎨 xkcd:'
tela=$(cap ui); contem "$tela" 'Como aparece' 'a prévia mostra como a fonte aparece'; contem "$tela" '🎨 xkcd:' 'com o exemplo validado'
fzf_recarregar C-a; igual "$(ativa xkcd)" 1 '^a liga uma fonte de fábrica pelo painel'
tmux send-keys -t ui C-u; espera ui 'Na roda (4)'
tmux send-keys -t ui "'xkcd"; espera ui '🎨 xkcd:'
fzf_recarregar C-a; igual "$(ativa xkcd)" 0 '^a de novo desliga'
tmux send-keys -t ui C-x; espera ui 'tirar da lista'; fzf_recarregar s Enter
py listar --tsv --todas | cut -f1 | grep -qx xkcd && falhou '^x numa fonte de fábrica a tira da lista'
tmux send-keys -t ui C-u; sleep 0.3
tmux send-keys -t ui C-b; espera ui 'catálogo ›'; espera ui '↩ xkcd'   # o catálogo oferece a que foi tirada
tmux send-keys -t ui "xkcd"; sleep 0.5; tmux send-keys -t ui Enter
for _ in {1..60}; do [[ $(ativa xkcd) == 1 ]] && break; sleep 0.2; done
igual "$(ativa xkcd)" 1 'e traz de volta (ligada) pelo painel'
tmux kill-session -t ui 2>/dev/null
passou 'painel: seções e categorias, Tab alterna a vista, prévia com o exemplo, ^a liga/desliga, ^x tira da lista, catálogo traz de volta'

# ============================================================================================
# 8) documentação: todas as fontes de fábrica estão no README e no pacote
# ============================================================================================
faltam=$(python3 -I - "$RAIZ" <<'PY2'
import json, sys
raiz = sys.argv[1]
nomes = list(json.load(open(raiz + "/letreiro-catalogo.json"))["fabrica"])
txt = open(raiz + "/README.md", encoding="utf-8").read()
print(" ".join(n for n in nomes if "`%s`" % n not in txt))
PY2
)
[[ -z $faltam ]] || falhou "o README não lista estas fontes de fábrica: $faltam"
grep -q 'letreiro-catalogo.json' "$RAIZ/tt" && grep -q 'letreiro-catalogo.json' "$RAIZ/skill-tt-terminais.md" || falhou 'pacote e skill precisam citar o letreiro-catalogo.json'
passou 'README lista todas as fontes de fábrica; pacote e skill citam o catálogo'
echo "TODOS OS TESTES PASSARAM"
