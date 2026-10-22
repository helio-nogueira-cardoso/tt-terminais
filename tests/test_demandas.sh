#!/usr/bin/env bash
# Demandas por e-mail: remetentes autorizados (cadastro comum, mesclado por e-mail), e-mails com "[tt]" no
# assunto viram tarefas PENDENTES (estado novo, fora das listas, na aba Entrada), só se o provedor autenticou o
# remetente (ou segredo/relaxado/aberto, por remetente); idempotentes (id do Message-ID); aprovar vira aberta com as
# subtarefas, recusar deixa lápide, e nenhuma recriação tardia ressuscita nada. Isola HOME/XDG/TT_RT; usa uma
# caixa de e-mail falsa (maildir) e um notify-send de mentira.
source "$(dirname "$0")/lib.sh"; isolar
tt() { "$TT" "$@"; }
fail() { echo "FALHOU: $1" >&2; exit 1; }
sem_cor() { sed 's/\x1b\[[0-9;]*m//g'; }
mkdir -p "$T/bin"
printf '#!/bin/sh\necho "NOTIF: $*" >>"%s/notifs.log"\n' "$T" >"$T/bin/notify-send"; chmod +x "$T/bin/notify-send"
printf '#!/bin/sh\nexit 1\n' >"$T/bin/tmux"; chmod +x "$T/bin/tmux"   # sem servidor tmux: nenhum aviso vai à tela real
export PATH="$T/bin:$PATH"
C="$XDG_CONFIG_HOME/tt/tarefas"; D="$XDG_CONFIG_HOME/tt/demandas"
mkdir -p "$(dirname "$D")"; : >"$XDG_CONFIG_HOME/tt/demandas-v2.5.1-relaxado"
UI="$TT_RT/tt-tarefas-ui-$(id -u)"
INBOX="$HOME/.cache/tt/maildir/conta/INBOX"; mkdir -p "$INBOX/new" "$INBOX/cur"
n=0
eml() { # nome from auth assunto corpo [message-id]
  n=$((n + 1)); local f="$INBOX/new/$1.eml:2,"; f="$INBOX/new/$1"
  {
    [[ $3 == pass ]] && echo "Authentication-Results: mx.exemplo.net; dkim=pass header.i=@${2#*@} header.s=s; spf=pass smtp.mailfrom=$2; dmarc=pass header.from=${2#*@}"
    [[ $3 == fail ]] && echo "Authentication-Results: mx.exemplo.net; dkim=fail; spf=softfail smtp.mailfrom=spam@outro.net; dmarc=fail"
    [[ $3 == semveredito || $3 == interno ]] && { [[ $3 == interno ]] && echo "Authentication-Results: tt-graph; x-ms-exchange-authas=internal header.from=${2#*@}"
      echo "Authentication-Results: mx.microsoft.com 1; dkim=none (message not signed) header.d=none;dmarc=none action=none header.from=${2#*@};"; }
    echo "From: Fulano <$2>"; echo "Date: Fri, 09 Oct 2026 14:00:00 -0300"; echo "Message-ID: <${6:-id-$1@teste}>"
    echo "Subject: $4"; echo "Content-Type: text/plain; charset=utf-8"; echo; printf '%s\n' "$5"
  } >"$f"
}

# 1) cadastro: valida, grava com 600, mescla por e-mail (hora mais nova vence), remove, e propaga a quem pede
tt --demanda-autorizar 'invalido' >/dev/null 2>&1 && fail "e-mail inválido deveria ser recusado"
r=$(tt --demanda-autorizar chefe@empresa.com.br '#Juridico') || fail "autorizar falhou"
[[ $r == 'autorizado: chefe@empresa.com.br (etiqueta #_juridico, modo auth)' ]] || fail "confirmação do cadastro com a etiqueta repetida ou errada: [$r]"
tt --demanda-autorizar seg@empresa.com.br prod segredo abcd1234 >/dev/null || fail "autorizar com segredo falhou"
tt --demanda-autorizar seg2@empresa.com.br - segredo ab >/dev/null 2>&1 && fail "segredo curto demais deveria ser recusado"
tt --demanda-autorizar livre@empresa.com.br - aberto >/dev/null || fail "autorizar aberto falhou"
tt --demanda-autorizar relax@empresa.com.br relax relaxado >/dev/null || fail "autorizar relaxado falhou"
[[ $(stat -c %a "$D") == 600 ]] || fail "o cadastro tem segredo: precisa ser 600 (está $(stat -c %a "$D"))"
grep -q $'^chefe@empresa.com.br\t_juridico\tauth\t-\t' "$D" || fail "etiqueta deveria ser normalizada (#Juridico -> _juridico): $(cat "$D")"
printf 'chefe@empresa.com.br\tantiga\tauth\t-\t1000\nnovo@x.com\tt\tauth\t-\t5\n' | tt --receber-demandas
grep -q $'^chefe@empresa.com.br\t_juridico\t' "$D" || fail "linha mais velha não pode vencer: $(cat "$D")"
grep -q '^novo@x.com' "$D" || fail "remetente novo vindo de outra máquina deveria entrar"
printf 'novo@x.com\t-\t-\t-\t99999999999\n' | tt --receber-demandas
tt --demandas | grep -q 'novo@x.com' && fail "remetente removido (modo -) não pode aparecer na lista"
tt --demanda-remover livre@empresa.com.br >/dev/null; tt --demanda-autorizar livre@empresa.com.br - aberto >/dev/null
echo "ok: cadastro de remetentes (validação, 600, mescla por hora, remoção)"

# 2) o analisador de e-mail (autenticação do provedor: só vale o cabeçalho de cima; alinhado ao domínio do From)
eml a1 chefe@empresa.com.br pass '=?UTF-8?Q?[tt]_Revisar_contrato_@sex_14h_!alta_#urgente?=' $'Preciso até sexta.\n- Ler cláusula 4\n- Enviar ao jurídico\n> citação\n-- \nChefe' 'abc@empresa'
v=$(python3 -I "$T/pkg/email-tt.py" demanda "$INBOX/new/a1" | cut -f1,2,4); [[ $v == $'chefe@empresa.com.br\tabc@empresa\tpass' ]] || fail "analisador: $v"
{ echo "Authentication-Results: mx; dkim=pass header.i=@outro.net; spf=softfail"; echo "From: x@empresa.com.br"; echo "Subject: [tt] a"; echo; echo b; } >"$T/dom.eml"
[[ $(python3 -I "$T/pkg/email-tt.py" demanda "$T/dom.eml" | cut -f4) == fail ]] || fail "dkim=pass de OUTRO domínio não pode autenticar o From"
{ echo "Authentication-Results: mx; spf=pass smtp.mailfrom=bounce@mail.empresa.com.br"; echo "From: x@empresa.com.br"; echo "Subject: [tt] a"; echo; echo b; } >"$T/dom.eml"
[[ $(python3 -I "$T/pkg/email-tt.py" demanda "$T/dom.eml" | cut -f4) == pass ]] || fail "spf=pass com domínio alinhado (subdomínio) deveria valer"
{ echo "Authentication-Results: mx; dmarc=fail"; echo "Authentication-Results: falso; dmarc=pass"; echo "From: x@y.com"; echo "Subject: [tt] a"; echo; echo b; } >"$T/dom.eml"
[[ $(python3 -I "$T/pkg/email-tt.py" demanda "$T/dom.eml" | cut -f4) == fail ]] || fail "só o Authentication-Results de cima vale (o de baixo pode ser forjado)"
# tt-graph (o graph_sync traduz o AuthAs=Internal do Exchange: colega do mesmo tenant, sem DKIM/DMARC): só no topo e alinhado
{ echo "Authentication-Results: tt-graph; x-ms-exchange-authas=internal header.from=empresa.com.br"; echo "Authentication-Results: mx.microsoft.com 1; dkim=none (message not signed) header.d=none;dmarc=none action=none header.from=empresa.com.br;"; echo "From: x@empresa.com.br"; echo "Subject: [tt] a"; echo; echo b; } >"$T/dom.eml"
[[ $(python3 -I "$T/pkg/email-tt.py" demanda "$T/dom.eml" | cut -f4) == fail ]] || fail "cabeçalho tt-graph não pode autenticar um e-mail por si só"
{ echo "Authentication-Results: tt-graph; x-ms-exchange-authas=internal header.from=outro.net"; echo "From: x@empresa.com.br"; echo "Subject: [tt] a"; echo; echo b; } >"$T/dom.eml"
[[ $(python3 -I "$T/pkg/email-tt.py" demanda "$T/dom.eml" | cut -f4) == fail ]] || fail "tt-graph de OUTRO domínio não pode autenticar o From"
{ echo "Authentication-Results: mx; dkim=none; dmarc=none"; echo "Authentication-Results: tt-graph; x-ms-exchange-authas=internal header.from=empresa.com.br"; echo "From: x@empresa.com.br"; echo "Subject: [tt] a"; echo; echo b; } >"$T/dom.eml"
[[ $(python3 -I "$T/pkg/email-tt.py" demanda "$T/dom.eml" | cut -f4) == fail ]] || fail "tt-graph fora do topo (forjável por quem manda) não pode valer"
echo "ok: analisador (dmarc/dkim/spf alinhados, tt-graph, só o cabeçalho de cima, citação e assinatura ignoradas)"

# 3) a caixa: o que vira demanda e o que é ignorado
rm -f "$INBOX/new/a1"
eml ok chefe@empresa.com.br pass '[tt] Revisar contrato @sex 14h !alta #urgente' $'Preciso até sexta.\n- Ler cláusula 4\n- Enviar ao jurídico\n> citação\n-- \nChefe'
eml forjado chefe@empresa.com.br fail '[tt] Pagar boleto' '- mandar dinheiro'
eml estranho desconhecido@spam.net pass '[tt] Comprar bitcoin' 'agora'
eml semtt chefe@empresa.com.br pass 'Reunião amanhã' 'sem o marcador'
eml segok seg@empresa.com.br pass '[tt:abcd1234] Subir versão' ''
eml segruim seg@empresa.com.br pass '[tt:errado999] Apagar tudo' ''
eml segsem seg@empresa.com.br pass '[tt] Sem segredo' ''
eml livre livre@empresa.com.br none '[tt] Tarefa sem autenticação mas modo aberto #x' ''
eml velho chefe@empresa.com.br pass '[tt] Mensagem antiga' ''; touch -d '3 days ago' "$INBOX/new/velho"
tt --demandas-processar conta
pend() { awk -F'\t' '$2=="pendente"' "$C"; }
topo() { pend | awk -F'\t' '$6 !~ /(^|\|)pai=/'; }
[[ $(topo | wc -l) == 3 ]] || fail "deveriam existir 3 demandas pendentes (ok, segok, livre): $(topo | cut -f5)"
topo | grep -q $'\tRevisar contrato\t' || fail "título deveria perder o [tt] e os marcadores: $(topo | cut -f5)"
topo | grep -q $'\tSubir versão\t' || fail "segredo certo deveria valer"
topo | grep -q 'Tarefa sem autenticação' || fail "modo aberto deveria valer sem autenticação"
topo | grep -qE 'Pagar boleto|bitcoin|Reunião|Apagar tudo|Sem segredo|antiga' && fail "e-mail forjado/desconhecido/sem [tt]/segredo errado/antigo não pode virar demanda"
m=$(topo | grep $'\tRevisar contrato\t' | cut -f6)
[[ $m == *prio=1* && $m == *tags=*juridico* && $m == *urgente* && $m == *prazo=* && $m == *hora=1* && $m == *de=chefe@empresa.com.br* && $m == *desc=* ]] || fail "meta da demanda incompleta: $m"
[[ $(pend | grep -c 'pai=') == 2 ]] || fail "as 2 linhas '- texto' deveriam virar 2 subtarefas pendentes: $(pend | cut -f5)"
id=$(topo | grep $'\tRevisar contrato\t' | cut -f1)
t1=$(topo | grep $'\tRevisar contrato\t' | cut -f4); [[ $t1 == 1791565200 ]] || fail "o horário da demanda deveria ser o da mensagem (veio $t1)"
grep -q 'ignorada de=chefe@empresa.com.br motivo=autenticacao(fail)' "$HOME/.local/state/tt/email-sync/conta.demandas.log" || fail "a recusa por autenticação deveria ficar no log"
grep -q 'NOTIF:.*demanda' "$T/notifs.log" || fail "deveria avisar da nova demanda"
# toda máquina que espelha a caixa lê o mesmo e-mail: o aviso do 🔔 é de lote (uma chave por mensagem), um só na rede
grep -rqE $'\tdemandas-conta#[0-9a-f]{12}(,[0-9a-f]{12}){2}$' "$HOME/.local/state/tt/notifs" || fail "o aviso das 3 demandas no 🔔 deveria levar o código de lote: $(cat "$HOME"/.local/state/tt/notifs/[0-9]* 2>/dev/null)"
grep -rqE $'\tdemandas-ignoradas-conta#[0-9a-f]{12}' "$HOME/.local/state/tt/notifs" || fail "o aviso das ignoradas no 🔔 deveria levar o código de lote"
echo "ok: só vira demanda o que é de remetente autorizado, com [tt], autenticado (ou segredo/aberto); e-mail antigo não"

# 4) idempotente: de novo (mesmo com a lista de vistos apagada) não duplica nem ressuscita
antes=$(md5sum <"$C"); tt --demandas-processar conta; [[ $(md5sum <"$C") == "$antes" ]] || fail "reprocessar mudou as tarefas"
rm -f "$HOME/.local/state/tt/email-sync/conta.demandas"; tt --demandas-processar conta
[[ $(topo | wc -l) == 3 ]] || fail "sem a lista de vistos, reprocessar não pode duplicar (id do Message-ID): $(topo | wc -l)"
echo "ok: idempotente — o id sai do Message-ID"

# 5) fora das listas normais; na aba Entrada com ✓ aprovar / ✕ recusar; aba só aparece com pendentes
printf 'filtro=todas\nmodo=lista\n' >"$UI"
l=$(tt --tarefas-lista | sem_cor); grep -q 'Revisar contrato' <<<"$l" && fail "demanda pendente não pode aparecer nas listas normais: $l"
cab=$(FZF_COLUMNS=100 tt --tarefas-cabecalho | sem_cor); grep -q 'Entrada 3' <<<"$cab" || fail "a aba Entrada deveria mostrar 3 pendentes: $cab"
printf 'filtro=entrada\nmodo=lista\n' >"$UI"
l=$(tt --tarefas-lista | sem_cor)
grep -q 'Revisar contrato' <<<"$l" && grep -q "^apv:$id" <<<"$l" && grep -q "^rec:$id" <<<"$l" && grep -q 'Ler cláusula 4' <<<"$l" || fail "a Entrada deveria mostrar título, subtarefas e as linhas ✓/✕: $l"
grep -q 'de chefe@empresa.com.br' <<<"$l" || fail "a Entrada deveria dizer de quem veio"
grep -q '📥 3' <<<"$(tt --tarefas-barra)" || fail "a barra deveria mostrar o chip 📥 3 das demandas pendentes: $(tt --tarefas-barra)"
printf 'filtro=arquivo\nmodo=lista\n' >"$UI"; tt --tarefa-filtro-ciclar
[[ $(sed -n 's/^filtro=//p' "$UI" | tail -1) == entrada ]] || fail "com pendentes, a aba depois de Arquivo deveria ser a Entrada"
echo "ok: pendentes só na aba Entrada (✓ aprovar / ✕ recusar), contador na aba e chip 📥 na barra"

# 6) ações do painel: duplo clique/⏎ nas outras linhas não marcam feita; ✓ aprova; ✕ recusa
acao() { FZF_QUERY= tt --tarefa-acao "$@"; }
acao clique "$id" >/dev/null; acao clique "$id" >/dev/null   # 2 cliques rápidos = duplo: não pode concluir uma pendente
[[ $(awk -F'\t' -v i="$id" '$1==i{print $2}' "$C") == pendente ]] || fail "duplo clique numa demanda pendente não pode aprová-la nem concluí-la"
acao clique "apv:$id" >/dev/null
[[ $(awk -F'\t' -v i="$id" '$1==i{print $2}' "$C") == aberta ]] || fail "clicar em ✓ aprovar deveria abrir a tarefa"
[[ $(awk -F'\t' -v i="$id" '$1!=i && $6 ~ ("pai=" i) {print $2}' "$C" | sort -u) == aberta ]] || fail "as subtarefas deveriam abrir junto"
t2=$(awk -F'\t' -v i="$id" '$1==i{print $4}' "$C"); ((t2 > t1)) || fail "aprovar deveria subir a hora da mudança (para vencer recriações tardias)"
sid=$(topo | grep $'\tSubir versão\t' | cut -f1)
acao clique "rec:$sid" >/dev/null
[[ $(awk -F'\t' -v i="$sid" '$1==i{print $2}' "$C") == removida ]] || fail "clicar em ✕ recusar deveria deixar a lápide"
tt --demanda-aprovar "$(topo | grep $'\tTarefa sem' | cut -f1)" | grep -q '1 aprovada' || fail "--demanda-aprovar deveria aprovar 1"
[[ $(topo | wc -l) == 0 ]] || fail "não deveria sobrar pendente: $(topo | cut -f5)"
grep -q '📥' <<<"$(tt --tarefas-barra)" && fail "sem pendentes, o chip 📥 não pode aparecer"
printf 'filtro=arquivo\nmodo=lista\n' >"$UI"; tt --tarefa-filtro-ciclar
[[ $(sed -n 's/^filtro=//p' "$UI" | tail -1) == hoje ]] || fail "sem pendentes, a aba depois de Arquivo volta para Hoje"
echo "ok: ✓ aprova (com as subtarefas), ✕ recusa (lápide), duplo clique não conclui pendente"

# 7) recriação tardia (outra máquina, caixa que reaparece) não ressuscita nem desfaz aprovação/recusa
rm -f "$HOME/.local/state/tt/email-sync/conta.demandas"; tt --demandas-processar conta
[[ $(topo | wc -l) == 0 ]] || fail "reprocessar depois de aprovar/recusar não pode recriar pendentes"
[[ $(awk -F'\t' -v i="$id" '$1==i{print $2}' "$C") == aberta ]] || fail "a aprovação não pode ser desfeita por uma recriação"
# e o merge entre máquinas: o registro da mensagem (hora velha, pendente) perde para a aprovação (hora nova)
printf '%s\tpendente\t%s\t%s\tRevisar contrato\t\n' "$id" "$t1" "$t1" | tt --receber-tarefas
[[ $(awk -F'\t' -v i="$id" '$1==i{print $2}' "$C") == aberta ]] || fail "um registro pendente velho de outra máquina não pode vencer a aprovação"
echo "ok: sem ressuscitar nem desfazer, nem pelo merge entre máquinas"

# 8) sem remetente cadastrado o processamento não faz nada; remetente removido deixa de valer
tt --demanda-remover chefe@empresa.com.br seg@empresa.com.br livre@empresa.com.br >/dev/null 2>&1
tt --demanda-remover chefe@empresa.com.br >/dev/null; tt --demanda-remover seg@empresa.com.br >/dev/null; tt --demanda-remover livre@empresa.com.br >/dev/null
eml novo chefe@empresa.com.br pass '[tt] Depois de remover' '' 'novo-id'
antes=$(md5sum <"$C"); tt --demandas-processar conta; [[ $(md5sum <"$C") == "$antes" ]] || fail "remetente removido não pode criar demanda"
echo "ok: remetente removido deixa de valer"

# 9) conta nova, de pouco volume: sem e-mail com mais de 1 dia o arquivo de "já vistos" nasce VAZIO; o processamento
#    não pode ficar mudo por causa disso (o awk NR == FNR tratava a lista de mensagens como se fosse o arquivo vazio)
tt --demanda-autorizar chefe@empresa.com.br juridico >/dev/null || fail "autorizar de novo falhou"
INBOX="$HOME/.cache/tt/maildir/vazia/INBOX"; mkdir -p "$INBOX/new" "$INBOX/cur"
eml vz chefe@empresa.com.br pass '[tt] Conta nova sem histórico' '' 'vz-id'
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/tt/email-sync"; : >"${XDG_STATE_HOME:-$HOME/.local/state}/tt/email-sync/vazia.demandas"
tt --demandas-processar vazia >/dev/null
grep -q $'\tpendente\t.*Conta nova sem histórico' "$C" || fail "caixa com arquivo de vistos vazio deveria criar a demanda: $(cut -f2,5 "$C")"
echo "ok: conta nova (arquivo de vistos vazio) também processa as demandas"

clicar() { rm -f "$TT_RT/tt-clique-$(id -u)"; tt --clique "$@" >/dev/null 2>&1; }   # (clique repetido em < 0,5 s é descartado de propósito)

# 10) chip 📥: range próprio, rota no clique e no clique direito, e o clique abre o painel direto na Entrada
grep -q 'range=user|entrada]' "$TT" || fail "o chip 📥 deveria ter o range próprio entrada"
grep -q '📥 3' <<<"$(tt --tarefas-barra)" && fail "só há 1 pendente agora"
grep -q 'range=user|entrada' <<<"$(tt --tarefas-barra)" || fail "a barra deveria desenhar o chip 📥 com o range entrada: $(tt --tarefas-barra)"
printf 'filtro=hoje\nmodo=lista\n' >"$UI"; clicar entrada cli '%0' ''
[[ $(sed -n 's/^filtro=//p' "$UI" | tail -1) == entrada ]] || fail "o clique no chip 📥 deveria abrir na aba Entrada"
printf 'filtro=hoje\nmodo=lista\n' >"$UI"; clicar tarefas cli '%0' ''
[[ $(sed -n 's/^filtro=//p' "$UI" | tail -1) == hoje ]] || fail "o 📋 não deve forçar a Entrada"
echo "ok: o chip 📥 abre direto na Entrada; o 📋 continua abrindo no filtro de sempre"

# 11) parado na Entrada sem nada pendente: abrir o painel volta para Hoje (não mostra aba vazia)
tt --demanda-aprovar $(tt --demandas-pendentes | awk 'NF{print $1; exit}') >/dev/null 2>&1
for i in $(awk -F'\t' '$2=="pendente" && $6 !~ /pai=/{print $1}' "$C"); do tt --demanda-recusar "$i" >/dev/null 2>&1; done
printf 'filtro=entrada\nmodo=lista\n' >"$UI"; clicar tarefas cli '%0' ''
[[ $(sed -n 's/^filtro=//p' "$UI" | tail -1) == hoje ]] || fail "sem pendentes, abrir o painel na Entrada deveria voltar para Hoje"
echo "ok: sem pendentes o painel não abre numa Entrada vazia"
# 12) e-mail [tt] que chega ANTES de o remetente ser autorizado: fica à espera (log diz "aguardando autorização")
#     e vira demanda quando o remetente passa a valer, mesmo já marcado como visto; e-mail sem [tt] de quem não está
#     autorizado não entra na espera.
INBOX="$HOME/.cache/tt/maildir/conta/INBOX"
eml antes1 depois@empresa.com.br pass '[tt] Chegou antes da autorização' 'linha 1'
eml antes2 depois@empresa.com.br pass 'Conversa comum' 'sem tt'
tt --demandas-processar conta
grep -q "aguardando autorização de=depois@empresa.com.br" "$HOME/.local/state/tt/email-sync/conta.demandas.log" || fail "o log deveria dizer que espera a autorização"
grep -q 'Chegou antes' "$C" && fail "não autorizado ainda não pode virar demanda"
[[ $(grep -c depois@empresa.com.br "$HOME/.local/state/tt/email-sync/conta.demandas.espera") == 1 ]] || fail "só o e-mail [tt] entra na espera: $(cat "$HOME/.local/state/tt/email-sync/conta.demandas.espera")"
tt --demandas-processar conta; grep -q 'Chegou antes' "$C" && fail "continua sem autorização: não pode virar demanda"
tt --demanda-autorizar depois@empresa.com.br >/dev/null
tt --demandas-processar conta
grep -q 'Chegou antes da autorização' "$C" || fail "autorizado depois, o e-mail que já tinha chegado deveria virar demanda"
[[ -s "$HOME/.local/state/tt/email-sync/conta.demandas.espera" ]] && grep -q antes1 "$HOME/.local/state/tt/email-sync/conta.demandas.espera" && fail "liberado deveria sair da espera"
echo "ok: e-mail que chega antes da autorização vira demanda quando o remetente é autorizado"

# 13) descrição longa (handoff de 10 mil+ caracteres) chega inteira
longa=$(for i in $(seq 1 300); do echo "linha $i do handoff com texto suficiente para passar de oito mil caracteres"; done)
eml longo chefe@empresa.com.br pass '[tt] Handoff longo' "$longa
FIM-DO-HANDOFF"
tt --demandas-processar conta
id=$(awk -F'\t' '$5 ~ /Handoff longo/ {print $1}' "$C" | head -1)
[[ -n $id ]] || fail "o handoff longo não virou demanda"
awk -F'\t' -v i="$id" '$1 == i {print $6}' "$C" | tr '|' '\n' | sed -n 's/^desc=//p' | base64 -d | grep -q FIM-DO-HANDOFF || fail "a descrição longa foi cortada"
echo "ok: descrição longa chega inteira"

# 14) NENHUM remetente autorizado (quem acabou de instalar): o e-mail [tt] de um colega é lido mesmo assim, fica à
#     espera e a pessoa é avisada; ao autorizar, vira demanda (antes nada era lido e a tarefa se perdia calada)
cp "$D" "$T/demandas.antes"; : >"$D"
eml colega1 colega@empresa.com.br pass '[tt] Tarefa do colega' 'faça isto'
tt --demandas-processar conta
grep -q 'aguardando autorização de=colega@empresa.com.br' "$HOME/.local/state/tt/email-sync/conta.demandas.log" || fail "sem nenhum autorizado, o e-mail [tt] deveria ficar à espera"
grep -q 'Tarefa do colega' "$C" && fail "sem autorização não pode virar demanda"
grep -rqs 'aguardando sua autorização' "$HOME/.local/state/tt/notifs" "$T/notifs.log" || fail "a pessoa deveria ser avisada de que há tarefa esperando autorização"
grep -rqE $'\tdemandas-espera-conta#[0-9a-f]{12}$' "$HOME/.local/state/tt/notifs" || fail "o aviso da espera no 🔔 deveria levar o código de lote"
grep -q $'^demandas\taviso\t.*colega@empresa.com.br' <<<"$(tt --checar --tsv)" || fail "o tt --checar deveria mostrar o e-mail [tt] à espera"
tt --demanda-autorizar colega@empresa.com.br >/dev/null; tt --demandas-processar conta
grep -q 'Tarefa do colega' "$C" || fail "autorizado, o e-mail que esperava deveria virar demanda"
cp "$T/demandas.antes" "$D"
echo "ok: sem nenhum remetente autorizado, o e-mail [tt] fica à espera, avisa, e entra quando autorizado"

# 15) mensagens Graph sem Authentication-Results aguardam prova e são reavaliadas depois do próximo sync
eml authwait chefe@empresa.com.br none '[tt] Chegou sem cabeçalho e foi recuperada' 'teste' 'authwait-id'
tt --demandas-processar conta
grep -Fq $'authwait\tchefe@empresa.com.br' "$HOME/.local/state/tt/email-sync/conta.demandas.auth-espera" || fail "a mensagem sem cabeçalho deveria ficar aguardando revalidação"
grep -q 'Chegou sem cabeçalho e foi recuperada' "$C" && fail "sem Authentication-Results ainda não pode virar tarefa"
awk 'NR == 1 { print "Authentication-Results: mx; dkim=pass header.i=@empresa.com.br; dmarc=pass" } { print }' "$INBOX/new/authwait" >"$INBOX/new/authwait.tmp"
mv "$INBOX/new/authwait.tmp" "$INBOX/new/authwait"
tt --demandas-processar conta
grep -q $'\tpendente\t.*Chegou sem cabeçalho e foi recuperada' "$C" || fail "após o Graph trazer os cabeçalhos, a mensagem deveria entrar na Entrada"
[[ ! -s "$HOME/.local/state/tt/email-sync/conta.demandas.auth-espera" ]] || fail "mensagem revalidada deveria sair da espera de autenticação"
echo "ok: auth=none aguarda e é reprocessado quando Graph traz os cabeçalhos reais"

# 16) modo relaxado: aceita sem cabeçalho e com falha explícita para remetente previamente autorizado
eml relax_none relax@empresa.com.br none '[tt] Remetente relaxado sem cabeçalho' 'teste' 'relax-none-id'
eml relax_fail relax@empresa.com.br fail '[tt] Remetente relaxado com falha' 'teste' 'relax-fail-id'
tt --demandas-processar conta
grep -q 'Remetente relaxado sem cabeçalho' "$C" || fail "modo relaxado deveria aceitar auth=none"
grep -q 'Remetente relaxado com falha' "$C" || fail "modo relaxado deve aceitar auth=fail para remetente autorizado"
echo "ok: relaxado aceita auth=none e auth=fail somente de remetente autorizado"


# 17) atualização v2.5.1 migra uma vez todos os auth existentes em cada máquina
mv "$D" "$T/demandas.salvas"
printf 'antigo@empresa.com.br\told\tauth\t-\t100\nprotegido@empresa.com.br\tp\tsegredo\tpass1234\t101\n' >"$D"
rm -f "$XDG_CONFIG_HOME/tt/demandas-v2.5.1-relaxado"
printf 'remoto@empresa.com.br\tr\tauth\t-\t99\n' | TT_DEMANDAS_RECEBENDO_REMOTO=1 tt --receber-demandas
grep -q $'^antigo@empresa.com.br\told\trelaxado\t-\t' "$D" || fail "migração automática deveria converter auth existente"
grep -q $'^remoto@empresa.com.br\tr\trelaxado\t-\t' "$D" || fail "migração deveria converter também auth recebido de outra máquina"
grep -q $'^protegido@empresa.com.br\tp\tsegredo\tpass1234\t101$' "$D" || fail "migração não pode mudar outros modos"
tt --demanda-autorizar futuro@empresa.com.br - auth >/dev/null
grep -q $'^futuro@empresa.com.br\t-\tauth\t-\t' "$D" || fail "migração única não pode converter novos cadastros auth"
mv "$T/demandas.salvas" "$D"

# 18) a espera tem prazo: sem o cabeçalho até TT_DEMANDAS_AUTH_ESPERA, é ignorada com o aviso (antes esperava calada para sempre)
AW="$HOME/.local/state/tt/email-sync/conta.demandas.auth-espera"
eml semcab chefe@empresa.com.br none '[tt] Nunca traz o cabeçalho' 'teste' 'semcab-id'
TT_DEMANDAS_AUTH_ESPERA=0 tt --demandas-processar conta
awk -F'\t' '$1 == "semcab" && $3 ~ /^[0-9]+$/' "$AW" | grep -q . || fail "a 1ª vez sem cabeçalho espera e guarda a hora: $(cat "$AW")"
grep -q 'Nunca traz o cabeçalho' "$C" && fail "sem Authentication-Results não pode virar tarefa"
: >"$T/notifs.log"
TT_DEMANDAS_AUTH_ESPERA=0 tt --demandas-processar conta
grep -q 'ignorada de=chefe@empresa.com.br motivo=autenticacao(none)' "$HOME/.local/state/tt/email-sync/conta.demandas.log" || fail "vencido o prazo, deveria ser ignorada pela autenticação"
grep -q '^semcab' "$AW" && fail "ignorada, deveria sair da espera: $(cat "$AW")"
grep -q 'ignorado' "$T/notifs.log" || fail "ignorada, deveria avisar: $(cat "$T/notifs.log")"
grep -q 'Nunca traz o cabeçalho' "$C" && fail "vencido o prazo, continua sem virar tarefa"
eml semcab2 chefe@empresa.com.br none '[tt] Espera da v2.4.5' 'teste' 'semcab2-id'
tt --demandas-processar conta
awk -F'\t' '$1 != "semcab2" { print; next } { print $1 "\t" $2 }' "$AW" >"$AW.t" && mv "$AW.t" "$AW"   # como a v2.4.5 gravava
TT_DEMANDAS_AUTH_ESPERA=0 tt --demandas-processar conta
awk -F'\t' '$1 == "semcab2" && $3 ~ /^[0-9]+$/' "$AW" | grep -q . || fail "espera sem hora (v2.4.5) passa a contar dali, sem ignorar na hora: $(cat "$AW")"
rm -f "$INBOX/new/semcab" "$INBOX/new/semcab2"
echo "ok: a espera pelo cabeçalho tem prazo e, vencido, ignora com o aviso"

# 19) no auth (o padrão dos cadastros novos), o e-mail interno do Exchange (o do Felipe: só dkim=none e dmarc=none) passa pelo
# tt-graph do topo; o mesmo cabeçalho sem o tt-graph (de fora, ou o domínio sem DKIM/SPF/DMARC) continua fail
eml sv1 chefe@empresa.com.br semveredito '[tt] De fora sem veredito' 'teste' 'sv1-id'
eml sv2 chefe@empresa.com.br interno '[tt] Interno pelo tt-graph' 'teste' 'sv2-id'
tt --demandas-processar conta
grep -q 'De fora sem veredito' "$C" && fail "no auth, o cabeçalho sem veredito não entra"
grep -q $'\tpendente\t.*Interno pelo tt-graph' "$C" && fail "no auth, cabeçalho tt-graph sem prova do provedor não entra"
echo "ok: no auth, cabeçalho sintético não substitui o veredito do provedor"

# 20) mudou o cadastro do remetente, o e-mail que tinha sido ignorado é lido de novo com a regra nova (na v2.5.1 a migração
# para o relaxado não liberava nada: o e-mail ignorado ficava visto para sempre)
IGN="$HOME/.local/state/tt/email-sync/conta.demandas.ignoradas"
printf 'muda@empresa.com.br\tm\tauth\t-\t1000\n' | tt --receber-demandas
eml muda1 muda@empresa.com.br none '[tt] Ignorada e depois liberada' 'teste' 'muda1-id'
TT_DEMANDAS_AUTH_ESPERA=0 tt --demandas-processar conta   # 1ª vez: espera o cabeçalho
TT_DEMANDAS_AUTH_ESPERA=0 tt --demandas-processar conta   # prazo vencido: ignorada, como a do Felipe às 15:22
grep -q 'ignorada de=muda@empresa.com.br motivo=autenticacao(none)' "$HOME/.local/state/tt/email-sync/conta.demandas.log" || fail "no auth, sem o cabeçalho e com o prazo vencido, é ignorada"
grep -q 'Ignorada e depois liberada' "$C" && fail "no auth, sem o cabeçalho ainda não entra"
grep -Fq $'muda1\tmuda@empresa.com.br\t' "$IGN" || fail "o e-mail ignorado deveria ficar guardado para ser lido de novo: $(cat "$IGN" 2>/dev/null)"
n1=$(grep -c 'de=muda@empresa.com.br' "$HOME/.local/state/tt/email-sync/conta.demandas.log")
tt --demandas-processar conta
[[ $(grep -c 'de=muda@empresa.com.br' "$HOME/.local/state/tt/email-sync/conta.demandas.log") == "$n1" ]] || fail "sem mudar o cadastro, o ignorado não é lido de novo a cada volta"
printf 'muda@empresa.com.br\tm\trelaxado\t-\t1000\n' | tt --receber-demandas   # mesma hora: o relaxado vence o auth no empate
tt --demandas-processar conta
grep -q $'\tpendente\t.*Ignorada e depois liberada' "$C" || fail "com o remetente no relaxado, o e-mail ignorado deveria virar demanda: $(tail -3 "$HOME/.local/state/tt/email-sync/conta.demandas.log")"
grep -q 'reavaliada de=muda@empresa.com.br' "$HOME/.local/state/tt/email-sync/conta.demandas.log" || fail "a releitura deveria ficar no log"
grep -Fq $'muda1\t' "$IGN" && fail "lido de novo, sai dos ignorados"
# remetente removido: o ignorado dele não vai para a espera de autorização
printf 'muda@empresa.com.br\tm\tauth\t-\t1500\n' | tt --receber-demandas
eml muda2 muda@empresa.com.br fail '[tt] Ignorada de quem saiu' 'teste' 'muda2-id'
tt --demandas-processar conta
grep -Fq $'muda2\t' "$IGN" || fail "o fail no auth fica guardado: $(cat "$IGN" 2>/dev/null)"
printf 'muda@empresa.com.br\tm\t-\t-\t2000\n' | tt --receber-demandas
tt --demandas-processar conta
grep -q 'muda@empresa.com.br' "$HOME/.local/state/tt/email-sync/conta.demandas.espera" 2>/dev/null && fail "remetente removido: o ignorado dele não vai para a espera"
grep -Fq $'muda2\t' "$IGN" || fail "remetente removido: o ignorado continua guardado (se ele voltar, é lido de novo)"
# o tt --checar não fica 7 dias avisando do ignorado que depois virou demanda
L="$HOME/.local/state/tt/email-sync/conta.demandas.log"; cp "$L" "$T/log.antes"
ESP="$HOME/.local/state/tt/email-sync/conta.demandas.espera"; [[ -f $ESP ]] && mv "$ESP" "$T/espera.antes"   # a espera vem antes no --checar
grep -v 'ignorada' "$T/log.antes" >"$L"
printf '%s ignorada de=muda@empresa.com.br motivo=autenticacao(none)\n%s reavaliada de=muda@empresa.com.br (o cadastro do remetente mudou)\n%s criada id=abc de=muda@empresa.com.br\n' "$(date '+%F %T')" "$(date '+%F %T')" "$(date '+%F %T')" >>"$L"
grep -q $'^demandas\taviso\t.*muda@empresa.com.br' <<<"$(tt --checar --tsv)" && fail "o ignorado que virou demanda depois não é mais aviso do --checar"
printf '%s ignorada de=muda@empresa.com.br motivo=autenticacao(fail,modo=relaxado)\n' "$(date '+%F %T')" >>"$L"
grep -q $'^demandas\taviso\t.*muda@empresa.com.br' <<<"$(tt --checar --tsv)" || fail "ignorado de novo, volta a ser aviso do --checar"
cp "$T/log.antes" "$L"; [[ -f $T/espera.antes ]] && mv "$T/espera.antes" "$ESP"
echo "ok: o ignorado é lido de novo quando o cadastro do remetente muda; o --checar não avisa do que já foi resolvido"

# 21) a migração da v2.5.1 só converte o cadastro de antes dela, e com a hora dele: uma remoção feita em outra máquina depois
# do cadastro continua valendo e o auth escolhido depois da v2.5.1 fica (a linha migrada ganhava a hora da instalação, e a
# máquina que instalasse depois, como a que estava desligada, ressuscitava o remetente removido)
mv "$D" "$T/demandas.salvas2"
printf 'velho@empresa.com.br\tv\tauth\t-\t100\nsaiu@empresa.com.br\ts\tauth\t-\t100\ndepois@empresa.com.br\td\tauth\t-\t1792620700\n' >"$D"
rm -f "$XDG_CONFIG_HOME/tt/demandas-v2.5.1-relaxado"
printf 'saiu@empresa.com.br\ts\t-\t-\t150\n' | tt --receber-demandas
grep -q $'^velho@empresa.com.br\tv\trelaxado\t-\t100$' "$D" || fail "a migração muda o modo e mantém a hora do cadastro: $(cat "$D")"
grep -q $'^saiu@empresa.com.br\ts\t-\t-\t150$' "$D" || fail "a remoção feita depois do cadastro não pode ser desfeita pela migração: $(cat "$D")"
grep -q $'^depois@empresa.com.br\td\tauth\t-\t1792620700$' "$D" || fail "o auth escolhido depois da v2.5.1 não é migrado: $(cat "$D")"
printf 'velho@empresa.com.br\tv\tauth\t-\t100\n' | tt --receber-demandas   # a máquina ainda na v2.5.0 manda o auth da mesma hora
grep -q $'^velho@empresa.com.br\tv\trelaxado\t-\t100$' "$D" || fail "no empate da mescla, o relaxado migrado vence o auth antigo: $(cat "$D")"
mv "$T/demandas.salvas2" "$D"
echo "ok: a migração mantém a hora do cadastro e não desfaz o que foi decidido depois"

echo "TODOS OS TESTES PASSARAM"
