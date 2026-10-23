#!/usr/bin/env bash
# Guarda dos serviços do usuário (23/10/2026): o ollama.service do Jiraops, com Restart=on-failure e sem limite, reiniciou
# 6611 vezes em 23 h, a cada 3 s, depois que a pasta do Ollama foi apagada; nunca chegava a "failed" e ninguém via.
# Programa ausente: contido sozinho (condição), um aviso por episódio, religado e CONFERIDO quando o programa volta.
# Falha repetida: medida por taxa, nunca parada (só espera crescente). Serviço que sai 0 e o que nunca entrou em loop
# não são tocados. systemctl e journalctl falsos; nada toca o systemd real.
source "$(dirname "$0")/lib.sh"; isolar
B=$T/bin; mkdir -p "$B" "$T/show" "$T/units"
U=$XDG_CONFIG_HOME/systemd/user
PROG=$HOME/.local/bin/ollama
mkdir -p "$HOME/.local/bin"; ln -s "$HOME/.local/ollama/bin/ollama" "$PROG"   # link quebrado, como na empresa
cat >"$B/systemctl" <<'FIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$T/systemctl.log"
[[ ${1:-} == --version ]] && { echo "systemd $(cat "$T/versao" 2>/dev/null || echo 259) (teste)"; exit 0; }
[[ ${1:-} == --user ]] || exit 1
shift
prop() { # unit chave
  case $2 in
    LoadState) if [[ -e $T/sumiu-$1 ]]; then echo not-found; elif [[ -e $T/mascarado-$1 ]]; then echo masked; else echo loaded; fi ;;
    ActiveState) cat "$T/ativo-$1" 2>/dev/null || echo inactive ;;
    *) sed -n "s/^$2=//p" "$T/show/$1" ;;
  esac
}
case ${1:-} in
  show-environment) exit 0 ;;
  list-units) for f in "$T"/units/*; do [[ -f $f && ! -e $T/parado-${f##*/} ]] && cat "$f"; done; exit 0 ;;
  show)
    shift; us=() ps=(); while (($#)); do case $1 in -p) ps+=("$2"); shift 2 ;; --value) shift ;; *) us+=("$1"); shift ;; esac; done
    if [[ ${#us[@]} == 1 && ${#ps[@]} == 1 ]]; then prop "${us[0]}" "${ps[0]}"; exit 0; fi
    n=0; for u in "${us[@]}"; do ((n++)) && echo; cat "$T/show/$u" 2>/dev/null; done; exit 0 ;;
  stop) touch "$T/parado-$2"; exit 0 ;;
  start | restart)
    echo "$2" >>"$T/ligados"
    prog=$(prop "$2" ExecStart | sed -n 's/^{ path=\([^ ;]*\).*/\1/p')
    if [[ -x $prog && -e $T/oneshot-$2 ]]; then echo inactive >"$T/ativo-$2"; sed -i 's/^Result=.*/Result=success/' "$T/show/$2"
    elif [[ -x $prog && -e $T/sobe-$2 ]]; then echo active >"$T/ativo-$2"; else echo failed >"$T/ativo-$2"; fi; exit 0 ;;
  is-active) cat "$T/ativo-$2" 2>/dev/null || echo inactive; exit 0 ;;
  *) exit 0 ;;
esac
FIM
cat >"$B/journalctl" <<'FIM'
#!/usr/bin/env bash
[[ " $* " == *" --grep "* ]] && echo "2026-10-22T16:45:20-03:00 empresa (ollama)[1]: ollama.service: Unable to locate executable"
exit 0
FIM
chmod +x "$B"/*
# (sem as esperas de segurança: conferir de pé, reconferir o programa ausente e esperar o programa assentar; cada uma
# tem a sua própria verificação abaixo)
export T PATH="$B:$TT_PATH_BASE" TT_SERVICO_CONFERIR=0 TT_SERVICO_RECONFERIR=0 TT_SERVICO_ASSENTAR=0
N=$HOME/.local/state/tt/notifs
em_loop() { # unit programa partidas status descrição [estado] [resultado]
  printf '%s loaded activating %s %s\n' "$1" "${6:-auto-restart}" "$5" >"$T/units/$1"
  printf 'Id=%s\nNRestarts=%s\nSubState=%s\nResult=%s\nExecMainStatus=%s\nExecStart={ path=%s ; argv[]=%s serve ; ignore_errors=no }\nDescription=%s\n' \
    "$1" "$3" "${6:-auto-restart}" "${7:-exit-code}" "$4" "$2" "$2" "$5" >"$T/show/$1"
  rm -f "$T/parado-$1"
}
avisos() { local f n=0; for f in "$N"/*; do [[ -f $f ]] && grep -q -- "$1" "$f" && grep -q -- "$2" "$f" && n=$((n + 1)); done; echo $n; }
estado() { sed -n 's/^estado=//p' "$HOME/.local/state/tt/servicos/$1" 2>/dev/null; }
guarda() { printf '%s/%s.d/00-tt-guarda.conf' "$U" "$1"; }
vigiar() { : >"$T/systemctl.log"; "$TT" --servicos vigiar; }

# --- o loop de hoje: guarda, causa e um aviso
em_loop ollama.service "$PROG" 6611 203 "Ollama local para Jiraops"
vigiar
grep -qx "ConditionFileIsExecutable=$PROG" "$(guarda ollama.service)" || falhou "sem a guarda com a condição: $(cat "$(guarda ollama.service)" 2>/dev/null)"
grep -qx -- '--user stop ollama.service' "$T/systemctl.log" || falhou 'não parou o loop'
[[ $(grep -c daemon-reload "$T/systemctl.log") == 1 ]] || falhou 'daemon-reload fora de 1'
[[ $(avisos ollama.service 'reiniciava sem parar') == 1 ]] || falhou "esperava 1 aviso, há $(avisos ollama.service 'reiniciava sem parar')"
a=$(cat "$N"/*)
[[ $a == *6611×* && $a == *'22/10 16:45'* && $a == *'~/.local/ollama/bin/ollama'* ]] || falhou "aviso sem a causa: $a"
[[ $(estado ollama.service) == guardado ]] || falhou "estado: $(estado ollama.service)"
passou 'programa ausente: guarda com a condição, loop parado, um aviso com a causa, o destino do link e desde quando'

# --- o mesmo episódio de novo: nem aviso nem daemon-reload (a guarda não mudou); o --checar pede a decisão
em_loop ollama.service "$PROG" 6611 203 "Ollama local para Jiraops"
vigiar
[[ $(avisos ollama.service 'reiniciava sem parar') == 1 ]] || falhou 'aviso repetido no mesmo episódio'
grep -q daemon-reload "$T/systemctl.log" && falhou 'daemon-reload sem a guarda mudar'
ck=$("$TT" --checar --tsv 2>/dev/null || true)   # (o --checar sai 1 com as falhas de um ambiente isolado)
grep -q $'^servicos\taviso\t.*ollama.service' <<<"$ck" || falhou "checar sem o aviso da decisão: $(grep '^servicos' <<<"$ck")"
passou 'mesmo episódio: sem aviso repetido nem daemon-reload; o --checar pede a decisão'

# --- o programa volta (parado há mais de 30 s): o vigia tira a guarda, liga, confere que ficou de pé e avisa
mkdir -p "$HOME/.local/ollama/bin"; printf '#!/bin/sh\nexit 0\n' >"$HOME/.local/ollama/bin/ollama"; chmod +x "$HOME/.local/ollama/bin/ollama"
touch -d '-2 min' "$HOME/.local/ollama/bin/ollama"; touch "$T/sobe-ollama.service" "$T/parado-ollama.service"
vigiar
[[ ! -e $(guarda ollama.service) ]] || falhou 'a guarda ficou depois de religar'
grep -qx ollama.service "$T/ligados" || falhou 'não ligou'
[[ $(estado ollama.service) == ativo ]] || falhou "estado depois de voltar: $(estado ollama.service)"
[[ $(avisos ollama.service 'voltou') == 1 ]] || falhou 'sem o aviso de que voltou'
passou 'o programa voltou: guarda tirada, serviço ligado e conferido de pé, aviso'

# --- some de novo: outro episódio, outro aviso; volta e não fica de pé: registra e só tenta de novo se o programa mudar
rm -f "$HOME/.local/ollama/bin/ollama" "$T/sobe-ollama.service" "$T/ativo-ollama.service" "$T/ligados"
em_loop ollama.service "$PROG" 12 203 "Ollama local para Jiraops"
sleep 1; vigiar
[[ $(avisos ollama.service 'reiniciava sem parar') == 2 ]] || falhou "o episódio novo não avisou: $(avisos ollama.service 'reiniciava sem parar')"
printf '#!/bin/sh\nexit 1\n' >"$HOME/.local/ollama/bin/ollama"; chmod +x "$HOME/.local/ollama/bin/ollama"; touch -d '-2 min' "$HOME/.local/ollama/bin/ollama"
touch "$T/parado-ollama.service"
vigiar
[[ $(estado ollama.service) == religar-falhou ]] || falhou "não ficou de pé: $(estado ollama.service)"
[[ $(avisos ollama.service 'não ficou de pé') == 1 ]] || falhou 'sem o aviso de que não ficou de pé'
grep -qx -- '--user stop ollama.service' "$T/systemctl.log" || falhou 'religação que falhou deixou o serviço em loop (sem stop)'
rm -f "$T/ligados"; vigiar
[[ ! -e $T/ligados ]] || falhou 'tentou de novo com o mesmo programa'
sleep 1; touch "$HOME/.local/ollama/bin/ollama"; touch "$T/sobe-ollama.service"; vigiar   # ctime novo: outro programa
[[ $(estado ollama.service) == ativo ]] || falhou "programa novo não religou: $(estado ollama.service)"
passou 'novo episódio avisa de novo; religação que não fica de pé é registrada e só tentada de novo com outro programa'

# --- o usuário trocou o ExecStart (consertou): a guarda sai; a unit apagada: guarda e estado saem
rm -f "$HOME/.local/ollama/bin/ollama" "$T/sobe-ollama.service"
em_loop ollama.service "$PROG" 9 203 "Ollama local para Jiraops"; sleep 1; vigiar; touch "$T/parado-ollama.service"
sed -i "s|path=$PROG|path=/opt/outro/ollama|" "$T/show/ollama.service"; vigiar
[[ ! -e $(guarda ollama.service) && -z $(estado ollama.service) ]] || falhou 'ExecStart trocado: a guarda ficou'
em_loop ollama.service "$PROG" 9 203 "Ollama local para Jiraops"; vigiar; touch "$T/parado-ollama.service" "$T/sumiu-ollama.service"; vigiar
[[ ! -e $(guarda ollama.service) && -z $(estado ollama.service) ]] || falhou 'unit apagada: restos'
rm -f "$T/sumiu-ollama.service"
passou 'ExecStart trocado pelo usuário ou unit apagada: a guarda e o estado saem'

# --- desligar: não sobe mais; a guarda fica; o programa voltando não religa
em_loop ollama.service "$PROG" 9 203 "Ollama local para Jiraops"; vigiar
"$TT" --servicos desligar ollama >/dev/null
grep -q -- '--user disable --now ollama.service' "$T/systemctl.log" || falhou 'desligar não desabilitou'
[[ -e $(guarda ollama.service) && $(estado ollama.service) == desligado ]] || falhou 'desligar: guarda/estado'
printf '#!/bin/sh\nexit 0\n' >"$HOME/.local/ollama/bin/ollama"; chmod +x "$HOME/.local/ollama/bin/ollama"; touch -d '-2 min' "$HOME/.local/ollama/bin/ollama"
rm -f "$T/ligados"; touch "$T/parado-ollama.service"; vigiar
[[ ! -e $T/ligados ]] || falhou 'desligado foi religado'
passou 'desligar: desabilita, mantém a guarda e não religa quando o programa volta'

# --- soltar: tira a guarda deste episódio; vale até o serviço se normalizar; depois, o próximo sumiço é outro episódio
rm -f "$HOME/.local/ollama/bin/ollama"
n=$(avisos ollama.service 'reiniciava sem parar')
"$TT" --servicos soltar ollama >/dev/null
[[ ! -e $(guarda ollama.service) && $(estado ollama.service) == solto ]] || falhou 'soltar'
em_loop ollama.service "$PROG" 9 203 "Ollama local para Jiraops"; vigiar
[[ ! -e $(guarda ollama.service) && $(avisos ollama.service 'reiniciava sem parar') == "$n" ]] || falhou 'solto: a guarda voltou no mesmo episódio'
printf '#!/bin/sh\nexit 0\n' >"$HOME/.local/ollama/bin/ollama"; chmod +x "$HOME/.local/ollama/bin/ollama"
touch "$T/parado-ollama.service"; sed -i 's/^SubState=.*/SubState=running/' "$T/show/ollama.service"; echo active >"$T/ativo-ollama.service"
vigiar; vigiar
[[ -z $(estado ollama.service) ]] || falhou "solto: o episódio não fechou com o serviço de pé: $(estado ollama.service)"
rm -f "$HOME/.local/ollama/bin/ollama" "$T/ativo-ollama.service"
em_loop ollama.service "$PROG" 9 203 "Ollama local para Jiraops"; sleep 1; vigiar
[[ -e $(guarda ollama.service) && $(avisos ollama.service 'reiniciava sem parar') == $((n + 1)) ]] || falhou 'depois de normalizar, o novo sumiço não abriu episódio'
passou 'soltar: vale pelo episódio; normalizado, fecha; o próximo sumiço é outro episódio, com guarda e aviso'

# --- no systemd < 254 a guarda de programa ausente entra do mesmo jeito (antes ela nunca entrava)
echo 252 >"$T/versao"; rm -rf "$HOME/.local/state/tt/servicos" "$U"
em_loop velho.service "$HOME/.local/bin/sumido" 7 203 "Velho"; vigiar
grep -q ConditionFileIsExecutable "$(guarda velho.service)" || falhou 'systemd 252: sem guarda'
passou 'systemd 252: a guarda de programa ausente entra'

# --- falha repetida: por taxa, nunca parada; espera crescente só no 254+; o que sai 0 e o que nunca entrou em loop ficam
em_loop quebra.service /bin/sh 10 1 "Quebra"; vigiar                      # 1ª olhada: só observa
[[ ! -e $(guarda quebra.service) && $(avisos quebra.service 'falha e reinicia') == 0 ]] || falhou 'falha agiu sem taxa'
em_loop quebra.service /bin/sh 20 1 "Quebra"; vigiar                      # 10 partidas desde a olhada anterior
[[ ! -e $(guarda quebra.service) ]] || falhou 'systemd 252: escreveu espera crescente que ele não tem'
[[ $(avisos quebra.service 'falha e reinicia') == 1 ]] || falhou 'systemd 252: falha repetida sem aviso'
grep -q -- '--user stop quebra.service' "$T/systemctl.log" && falhou 'falha repetida foi parada'
echo 259 >"$T/versao"
em_loop quebra.service /bin/sh 30 1 "Quebra"; vigiar
grep -qx 'RestartSteps=5' "$(guarda quebra.service)" || falhou 'systemd 259: sem espera crescente'
grep -q 'StartLimit\|ConditionFile' "$(guarda quebra.service)" && falhou 'falha repetida ganhou limite/condição'
grep -q -- '--user stop quebra.service' "$T/systemctl.log" && falhou 'falha repetida foi parada'
[[ $(avisos quebra.service 'falha e reinicia') == 1 ]] || falhou 'falha repetida avisou duas vezes'
em_loop periodico.service /bin/sh 100 0 "Periódico" auto-restart success; vigiar
em_loop periodico.service /bin/sh 200 0 "Periódico" auto-restart success; vigiar
em_loop exec203.service /bin/sh 50 203 "Interpretador sumiu"; vigiar
em_loop exec203.service /bin/sh 52 203 "Interpretador sumiu"; vigiar      # programa existe: taxa baixa, nada
em_loop timer.service "$HOME/.local/bin/sumido2" 0 203 "Oneshot" failed exit-code; vigiar
[[ ! -e $(guarda periodico.service) && ! -e $(guarda exec203.service) && ! -e $(guarda timer.service) ]] ||
  falhou 'tocou em serviço periódico (sai 0), em 203 com programa presente e taxa baixa, ou em failed que nunca entrou em loop'
grep -q 'periodico\|exec203\|timer' <(cat "$N"/*) && falhou 'avisou de serviço que não está em loop'
passou 'falha repetida: por taxa, nunca parada, espera crescente só no 254+; periódico, 203 presente e failed sem loop intactos'

# --- programa ausente, segurança: arquivo recém-escrito (ctime < 30 s) não é religado; programa que reaparece na
# reconferência não abre episódio; unit mascarada não é religada
rm -rf "$HOME/.local/state/tt/servicos" "$U" "$HOME/.local/ollama"; rm -f "$T"/sobe-* "$T"/ativo-* "$T/ligados"
em_loop ollama.service "$PROG" 9 203 "Ollama local para Jiraops"; vigiar; touch "$T/parado-ollama.service"
mkdir -p "$HOME/.local/ollama/bin"; printf '#!/bin/sh\nexit 0\n' >"$HOME/.local/ollama/bin/ollama"; chmod +x "$HOME/.local/ollama/bin/ollama"
TT_SERVICO_ASSENTAR=30 vigiar
[[ ! -e $T/ligados ]] || falhou 'religou um programa ainda sendo escrito (ctime recente)'
touch "$T/mascarado-ollama.service"; vigiar
[[ ! -e $T/ligados ]] || falhou 'religou uma unit mascarada'
rm -f "$T/mascarado-ollama.service" "$HOME/.local/ollama/bin/ollama"
em_loop novo.service "$HOME/.local/bin/chegando" 4 203 "Chegando"
( sleep 0.4; printf '#!/bin/sh\n' >"$HOME/.local/bin/chegando"; chmod +x "$HOME/.local/bin/chegando" ) &
TT_SERVICO_RECONFERIR=2 vigiar; wait
[[ ! -e $(guarda novo.service) && $(avisos novo.service 'reiniciava') == 0 ]] || falhou 'troca de versão momentânea virou episódio'
passou 'programa ausente: recém-escrito não religa, mascarada não religa, troca de versão momentânea não é episódio'

# --- o ExecStart consertado pelo usuário (programa novo existe): guarda sai e o tt liga e confere; ligar sem estado;
# oneshot que termina bem conta como de pé
rm -rf "$HOME/.local/state/tt/servicos" "$U"; rm -f "$T"/sobe-* "$T"/ativo-* "$T/ligados"
em_loop conserto.service "$HOME/.local/bin/sumido-c" 9 203 "Conserto"; vigiar; touch "$T/parado-conserto.service"
sed -i "s|path=$HOME/.local/bin/sumido-c|path=/bin/sh|" "$T/show/conserto.service"; touch "$T/sobe-conserto.service"; vigiar
[[ ! -e $(guarda conserto.service) && $(estado conserto.service) == ativo ]] || falhou "ExecStart consertado: $(estado conserto.service)"
rm -rf "$HOME/.local/state/tt/servicos"; rm -f "$T/ativo-conserto.service"
"$TT" --servicos ligar conserto >/dev/null 2>&1 || falhou 'ligar sem estado gravado falhou'
em_loop tarefa.service "$HOME/.local/bin/sumido-t" 6 203 "Oneshot" failed start-limit-hit; vigiar
printf '#!/bin/sh\n' >"$HOME/.local/bin/sumido-t"; chmod +x "$HOME/.local/bin/sumido-t"; touch "$T/oneshot-tarefa.service" "$T/parado-tarefa.service"; vigiar
[[ $(estado tarefa.service) == ativo ]] || falhou "oneshot que terminou bem: $(estado tarefa.service)"
passou 'ExecStart consertado: religa e confere; ligar sem estado funciona; oneshot que termina bem conta como de pé'

# --- falha repetida: o episódio fecha com o serviço de pé (sai a espera crescente); soltar vale pelo episódio;
# linha de base retida quando o serviço não é pego em auto-restart
rm -rf "$HOME/.local/state/tt/servicos" "$U"
em_loop cai.service /bin/sh 10 1 "Cai"; vigiar; em_loop cai.service /bin/sh 20 1 "Cai"; vigiar
[[ -e $(guarda cai.service) ]] || falhou 'falha repetida sem espera crescente'
touch "$T/parado-cai.service"; sed -i 's/^SubState=.*/SubState=running/' "$T/show/cai.service"; echo active >"$T/ativo-cai.service"
vigiar; [[ -e $(guarda cai.service) ]] || falhou 'fechou o episódio com uma olhada só'
vigiar; [[ ! -e $(guarda cai.service) && -z $(estado cai.service) ]] || falhou 'episódio de falha não fechou com o serviço de pé'
rm -f "$T/ativo-cai.service"
em_loop cai.service /bin/sh 30 1 "Cai"; vigiar; em_loop cai.service /bin/sh 40 1 "Cai"; vigiar
[[ $(avisos cai.service 'falha e reinicia') == 2 ]] || falhou 'a recaída depois de normalizar não avisou'
"$TT" --servicos soltar cai >/dev/null
em_loop cai.service /bin/sh 50 1 "Cai"; vigiar; em_loop cai.service /bin/sh 60 1 "Cai"; vigiar
[[ ! -e $(guarda cai.service) && $(avisos cai.service 'falha e reinicia') == 2 && $(estado cai.service) == solto ]] || falhou 'soltar não valeu pelo episódio'
em_loop salta.service /bin/sh 10 1 "Salta"; vigiar; touch "$T/parado-salta.service"; vigiar   # de pé entre duas quedas
em_loop salta.service /bin/sh 20 1 "Salta"; vigiar
[[ $(avisos salta.service 'falha e reinicia') == 1 ]] || falhou 'a linha de base se perdeu quando o serviço não foi pego em auto-restart'
passou 'falha repetida: episódio fecha de pé (sai a espera), recaída avisa de novo, soltar vale pelo episódio, linha de base retida'

# --- instalar de novo: pasta dedicada, só bin/ e lib/ trocados (modelos ficam), sha256 conferido
if [[ $(uname -s) == Linux ]]; then
  rm -rf "$HOME/.local/state/tt/servicos" "$U" "$HOME/.local/ollama"; rm -f "$T/ligados"
  mkdir -p "$HOME/.local/ollama/models" "$T/rel/bin" "$T/rel/lib/ollama"
  echo modelo >"$HOME/.local/ollama/models/m"; echo meu >"$HOME/.local/guardar"
  printf '#!/bin/sh\necho "ollama version is 9.9.9"\n' >"$T/rel/bin/ollama"; chmod +x "$T/rel/bin/ollama"; echo lib >"$T/rel/lib/ollama/x"
  tar -czf "$T/ollama.tgz" -C "$T/rel" bin lib
  sha=$(sha256sum "$T/ollama.tgz" | cut -d' ' -f1)
  python3 - "$T" "$sha" >"$T/rel.json" <<'PY'
import json, os, sys
t, sha = sys.argv[1:]
print(json.dumps({"tag_name": "v9.9.9", "assets": [
    {"name": "ollama-linux-%s.tgz" % a, "browser_download_url": "file://%s/ollama.tgz" % t, "digest": "sha256:" + sha,
     "size": os.path.getsize(t + "/ollama.tgz")} for a in ("amd64", "arm64")]}))
PY
  em_loop ollama.service "$PROG" 6611 203 "Ollama local para Jiraops"; vigiar; touch "$T/sobe-ollama.service"
  TT_OLLAMA_API=file://$T/rel.json TT_PK_QUIETO=1 "$TT" --servicos instalar ollama >"$T/inst.out" 2>&1 || falhou "instalar: $(cat "$T/inst.out")"
  [[ $("$PROG") == *9.9.9* && -f $HOME/.local/ollama/lib/ollama/x ]] || falhou "instalação: $(ls -lR "$HOME/.local/ollama" | head)"
  [[ $(cat "$HOME/.local/ollama/models/m") == modelo && $(cat "$HOME/.local/guardar") == meu ]] || falhou 'a instalação apagou o que não era dela'
  [[ $(estado ollama.service) == ativo ]] || falhou "estado depois de instalar: $(estado ollama.service)"
  ls -d "$HOME"/.local/.tt-ollama.* >/dev/null 2>&1 && falhou 'restos do download'
  # link que levaria a ~/.local inteiro (~/bin/ollama → ../.local/bin/ollama-x): instala na pasta dedicada, ~/.local fica
  mkdir -p "$HOME/bin"; ln -s ../.local/bin/ollama-x "$HOME/bin/ollama"
  em_loop outro.service "$HOME/bin/ollama" 6 203 "Outro"; vigiar; touch "$T/sobe-outro.service"
  TT_OLLAMA_API=file://$T/rel.json TT_PK_QUIETO=1 "$TT" --servicos instalar outro >"$T/inst2.out" 2>&1 || falhou "instalar outro: $(cat "$T/inst2.out")"
  [[ $(readlink "$HOME/bin/ollama") == "$HOME/.local/ollama/bin/ollama" && $(cat "$HOME/.local/guardar") == meu && -d $HOME/.local/state ]] ||
    falhou "o link perigoso mexeu em ~/.local: $(readlink "$HOME/bin/ollama")"
  # sha256 que não confere: nada muda
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); [a.update(digest="sha256:"+"0"*64) for a in d["assets"]]; json.dump(d,open(sys.argv[1],"w"))' "$T/rel.json"
  TT_OLLAMA_API=file://$T/rel.json TT_PK_QUIETO=1 "$TT" --servicos instalar ollama >"$T/inst3.out" 2>&1 && falhou 'instalou com sha256 errado'
  [[ $("$PROG") == *9.9.9* ]] || falhou 'o sha256 errado mexeu na instalação boa'
  # programa fora da sua pasta (precisa de administrador): recusa antes de baixar
  em_loop sistema.service /usr/local/sbin/tt-teste-ollama/ollama 6 203 "Sistema"; vigiar
  TT_OLLAMA_API=file:///nao/existe "$TT" --servicos instalar sistema >"$T/inst4.out" 2>&1 && falhou 'instalou fora da pasta do usuário'
  grep -q 'administrador' "$T/inst4.out" || falhou "recusa sem explicação: $(cat "$T/inst4.out")"
  passou 'instalar: pasta dedicada, só bin/ e lib/ (modelos e ~/.local intactos), sha256 conferido, fora da sua pasta recusa antes de baixar'
fi

# --- o clique no aviso abre a decisão na máquina do serviço (por ssh, se for outra)
c=$(TT_SO_CARREGAR=1 "$BASH" -c '
  source "$1" >/dev/null 2>&1
  popup_tt() { printf "printf %%s %q" "$3"; }
  dest_ir() { echo u@dell; }
  MAQUINA=empresa; servico_abrir "dell|ollama.service" cliente; echo; servico_abrir "empresa|ollama.service" cliente' _ "$T/pkg/tt")
# (o comando de lá vai citado para o shell remoto: "--servicos\ ui\ ollama.service")
grep -Eq 'ssh -t .*u@dell .*--servicos\\? ui\\? ollama\.service' <<<"$(head -1 <<<"$c")" || falhou "outra máquina: $c"
grep -Eq -- '--servicos ui ollama\.service' <<<"$(tail -1 <<<"$c")" && ! grep -q ssh <<<"$(tail -1 <<<"$c")" || falhou "nesta máquina: $c"
grep -q 'servico:\*) servico_abrir' "$T/pkg/tt" || falhou 'aviso sem rota no 🔔'
passou 'o clique no aviso abre a decisão na máquina do serviço (ssh quando é outra)'

# --- sem systemd do usuário (macOS, Termux): não age
rm -f "$B/systemctl"
"$TT" --servicos status | grep -q 'sem systemd do usuário' || falhou 'sem systemd: status'
"$TT" --servicos vigiar || falhou 'sem systemd: vigiar falhou'
passou 'sem systemd do usuário: status explica e o vigia não age'
