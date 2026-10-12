#!/usr/bin/env bash
# Tarefa por e-mail em TRÊS VIAS (protocolo v2): o e-mail leva o estado da tarefa, [x]/[ ] das subtarefas e as removidas
# (depois da assinatura, que um tt antigo ignora) e nunca o diário ⟡; quem recebe compara atual × recebida × base: o que só
# o e-mail mudou entra, o que só você mudou fica, o que os dois mudaram é conflito (nada grava até decidir); propostas
# repetidas ou velhas são descartadas; e a tela de revisão (vim) resolve tarefa a tarefa, campo a campo, por clique ou tecla.
# Duas máquinas isoladas (A envia, B recebe) no mesmo pacote; caixa de e-mail falsa em maildir.
source "$(dirname "$0")/lib.sh"; isolar
trap 'rc=$?; printf "ERRO interno na linha %s (rc=%s): %s\\n" "$LINENO" "$rc" "$BASH_COMMAND" >&2; exit "$rc"' ERR
tt() { "$TT" "$@"; }      # B, o receptor
mkdir -p "$T/A/home/.config/tt" "$T/A/rt" "$T/bin"
printf 'nome=A\n' >"$T/A/home/.config/tt/config"; : >"$T/A/home/.config/tt/maquinas"
A() { HOME=$T/A/home XDG_CONFIG_HOME=$T/A/home/.config TT_RT=$T/A/rt TT_MACHINE=A "$TT" "$@"; }
printf '#!/bin/sh\nexit 0\n' >"$T/bin/notify-send"; chmod +x "$T/bin/notify-send"; export PATH="$T/bin:$PATH"
CB="$XDG_CONFIG_HOME/tt/tarefas"; CA="$T/A/home/.config/tt/tarefas"
INBOX="$HOME/.cache/tt/maildir/conta/INBOX"; mkdir -p "$INBOX/new"
sem_cor() { sed 's/\x1b\[[0-9;]*m//g'; }
tt --demanda-autorizar ana@x.com - aberto >/dev/null
EPOCH=1791600000; N=0
entrega() { # saída de `A --tarefa-email` → e-mail de ana@x.com na caixa de B (data crescente, ou a pedida) → processa
  local out=$1 data=${2:-$((EPOCH + N * 60))} subj body; N=$((N + 1))
  subj=$(sed -n 's/^Assunto: //p' <<<"$out" | head -1)
  body=$(awk 'f { print } /^Assunto:/ { seen = 1 } /^$/ && seen { f = 1 }' <<<"$out" | sed '/^mailto:/,$d')
  { echo "From: Ana <ana@x.com>"; echo "Date: $(date -R -d "@$data")"; echo "Message-ID: <m$N@t>"; echo "Subject: $subj"
    echo "Content-Type: text/plain; charset=utf-8"; echo; printf '%s\n' "$body"; } >"$INBOX/new/m$N"
  tt --demandas-processar conta
}
estado_de() { awk -F'\t' -v i="$1" '$1==i{print $2}' "$2"; }
texto_de() { awk -F'\t' -v i="$1" '$1==i{print $5}' "$2"; }
meta_de() { awk -F'\t' -v i="$1" '$1==i{print $6}' "$2" | tr '|' '\n' | sed -n "s/^$3=//p"; }
props() { awk -F'\t' '$2=="pendente" && $6 ~ /(^|\|)upd=/{print $1}' "$CB"; }
nprops() { props | grep -c . || true; }
id_em() { awk -F'\t' -v t="$1" '$5==t && $2!="removida"{print $1; exit}' "$2"; }

# 1) primeira entrega: protocolo v2, sem o diário ⟡, [x] chega feita, base gravada dos dois lados
A --tarefa-add "Fechar balanço" >/dev/null; ID=$(id_em "Fechar balanço" "$CA")
A --tarefa-editar "$ID" "Fechar balanço @sex !alta #fin" >/dev/null
A --tarefa-desc "$ID" $'Contexto do balanço.\n- ponto da descrição' >/dev/null
A --tarefa-sub-add "$ID" "Conciliar bancos" >/dev/null 2>&1; A --tarefa-sub-add "$ID" "Revisar impostos" >/dev/null 2>&1
S1=$(id_em "Conciliar bancos" "$CA"); S2=$(id_em "Revisar impostos" "$CA")
A --tarefa-ok "$S1" >/dev/null 2>&1
INI=$(date -d '1 second ago' '+%Y-%m-%dT%H:%M:%S%:z'); FIM=$(date '+%Y-%m-%dT%H:%M:%S%:z')
A --tarefa-log "$ID" "rodei a conciliação" --como "script" --agente claude --modelo m --tokens-ent 10 --tokens-sai 5 --inicio "$INI" --fim "$FIM" --conta trabalho --email dono@secreto.com >/dev/null 2>&1
out=$(A --tarefa-email "$ID" ana@x.com 2>&1)
grep -q '⟡' <<<"$out" && falhou "o diário de trabalho (⟡) vazou no e-mail: $out"
grep -q 'dono@secreto.com' <<<"$out" && falhou 'o e-mail da conta vazou no corpo do e-mail'
grep -q "^- \[$S1\] \[x\] Conciliar bancos$" <<<"$out" && grep -q "^- \[$S2\] \[ \] Revisar impostos$" <<<"$out" || falhou "subtarefas com [x]/[ ] explícitos: $out"
grep -q '^-- $' <<<"$out" && grep -q '^tt:2 estado=aberta$' <<<"$out" || falhou "faltou o rodapé do protocolo v2 depois da assinatura: $out"
[[ -n $(meta_de "$ID" "$CA" base) ]] || falhou 'enviar deveria gravar a base (a versão enviada) em quem enviou'
entrega "$out"
[[ $(estado_de "$ID" "$CB") == pendente && $(estado_de "$S1" "$CB") == pendente ]] || falhou "a tarefa nova deveria nascer pendente com os códigos do remetente"
[[ $(meta_de "$S1" "$CB" sest) == f && $(meta_de "$S2" "$CB" sest) == a ]] || falhou "[x]/[ ] da primeira entrega: S1=$(meta_de "$S1" "$CB" sest) S2=$(meta_de "$S2" "$CB" sest)"
tt --demanda-aprovar "$ID" >/dev/null
[[ $(estado_de "$ID" "$CB") == aberta && $(estado_de "$S1" "$CB") == feita && $(estado_de "$S2" "$CB") == aberta ]] || falhou "aprovada: mãe aberta, S1 feita (veio [x]), S2 aberta: $(estado_de "$ID" "$CB") $(estado_de "$S1" "$CB") $(estado_de "$S2" "$CB")"
[[ -n $(meta_de "$ID" "$CB" base) && -z $(meta_de "$S1" "$CB" sest) && -z $(meta_de "$ID" "$CB" v2) ]] || falhou 'aprovada: base gravada e o meta transitório (sest/v2) limpo'
pr=$(tt --tarefa-ia-prompt "$ID"); grep -q 'rodei a conciliação' <<<"$pr" && falhou 'o diário da A não pode ter chegado na descrição da B'
passou 'primeira entrega: v2, sem diário nem e-mail de conta, [x] chega feita, base nos dois lados'

# 2) o que só o e-mail mudou entra; o que só EU mudei fica (três vias)
tt --tarefa-editar "$ID" "Fechar balanço @seg !media #fin #meu" >/dev/null     # B mexe no prazo, prioridade e etiquetas
tt --tarefa-desc "$ID" $'Contexto do balanço.\n- ponto da descrição\nNota privada da B' >/dev/null
A --tarefa-editar "$ID" "Fechar balanço 2026 @sex !alta #fin" >/dev/null       # A só renomeia
entrega "$(A --tarefa-email "$ID" ana@x.com)"
p=$(props); [[ -n $p && $(nprops) == 1 ]] || falhou "deveria haver 1 proposta (há $(nprops))"
d=$(tt --demanda-diff "$p" | sem_cor)
grep -q 'Título' <<<"$d" && grep -q 'Fechar balanço 2026' <<<"$d" || falhou "o diff deveria mostrar a mudança de título: $d"
grep -q 'suas mudanças mantidas' <<<"$d" && grep -q 'Prazo' <<<"$d" && grep -q 'Etiquetas' <<<"$d" || falhou "o diff deveria dizer o que da B foi mantido: $d"
grep -q '⚡' <<<"$d" && falhou "não há conflito aqui (cada lado mexeu em campos diferentes): $d"
tt --demanda-aprovar "$p" >/dev/null || falhou "aprovar sem conflito deveria dar certo"
[[ $(texto_de "$ID" "$CB") == "Fechar balanço 2026" ]] || falhou "o título da A deveria entrar: «$(texto_de "$ID" "$CB")»"
[[ $(meta_de "$ID" "$CB" prio) == 2 && $(meta_de "$ID" "$CB" tags) == fin,meu ]] || falhou "prioridade/etiquetas da B deviam ser mantidas: prio=$(meta_de "$ID" "$CB" prio) tags=$(meta_de "$ID" "$CB" tags)"
[[ -n $(meta_de "$ID" "$CB" prazo) && $(meta_de "$ID" "$CB" prazo) != "$(meta_de "$ID" "$CA" prazo)" ]] || falhou 'o prazo da B (@seg) devia ser mantido'
pr=$(tt --tarefa-ia-prompt "$ID"); grep -q 'Nota privada da B' <<<"$pr" || falhou 'a nota privada da B na descrição devia ser mantida'
[[ $(nprops) == 0 ]] || falhou 'a proposta aprovada deveria ser descartada'
passou 'três vias: o título da A entra, o prazo, a prioridade, as etiquetas e a nota privada da B ficam'

# 3) estado da mãe, concluir/reabrir/remover/acrescentar subtarefa viajam
A --tarefa-ok "$S2" >/dev/null 2>&1; A --tarefa-ok "$ID" >/dev/null 2>&1
[[ $(estado_de "$ID" "$CA") == feita ]] || falhou 'A deveria ter concluído a mãe'
out=$(A --tarefa-email "$ID" ana@x.com); grep -q '^tt:2 estado=feita$' <<<"$out" || falhou "rodapé com estado=feita: $out"
entrega "$out"; p=$(props)
tt --demanda-aprovar "$p" >/dev/null
[[ $(estado_de "$ID" "$CB") == feita && $(estado_de "$S2" "$CB") == feita ]] || falhou "concluir a mãe e a subtarefa na A deveria concluir na B: $(estado_de "$ID" "$CB") $(estado_de "$S2" "$CB")"
A --tarefa-abrir "$ID" >/dev/null 2>&1; A --tarefa-abrir "$S2" >/dev/null 2>&1       # A reabre a mãe e a subtarefa 2
A --tarefa-rm "$S1" >/dev/null 2>&1; A --tarefa-sub-add "$ID" "Assinar balanço" >/dev/null 2>&1
S3=$(id_em "Assinar balanço" "$CA")
out=$(A --tarefa-email "$ID" ana@x.com); grep -q "removidas=$S1" <<<"$out" || falhou "o rodapé deveria listar a subtarefa removida: $out"
entrega "$out"; p=$(props); tt --demanda-aprovar "$p" >/dev/null
[[ $(estado_de "$ID" "$CB") == aberta && $(estado_de "$S2" "$CB") == aberta ]] || falhou "reabrir viaja: mãe=$(estado_de "$ID" "$CB") S2=$(estado_de "$S2" "$CB")"
[[ $(estado_de "$S1" "$CB") == removida ]] || falhou "remover subtarefa viaja: S1=$(estado_de "$S1" "$CB")"
[[ $(estado_de "$S3" "$CB") == aberta ]] || falhou "subtarefa nova da A deveria entrar: $(estado_de "$S3" "$CB")"
passou 'concluir, reabrir, remover e acrescentar subtarefa, e o estado da mãe, viajam como mudanças'

# 4) conflito: nada grava sem decidir; --minha e --recebida resolvem; reenvio igual não vira proposta
tt --tarefa-editar "$ID" "Balanço do B" >/dev/null
A --tarefa-editar "$ID" "Balanço da A" >/dev/null
entrega "$(A --tarefa-email "$ID" ana@x.com)"; p=$(props)
d=$(tt --demanda-diff "$p" | sem_cor); grep -q '⚡ conflito' <<<"$d" || falhou "o diff deveria apontar o conflito: $d"
rc=0; msg=$(tt --demanda-aprovar "$p" 2>&1) || rc=$?
((rc == 4)) && grep -q 'tem conflitos' <<<"$msg" || falhou "aprovar com conflito deveria sair 4 e explicar (rc=$rc): $msg"
[[ $(texto_de "$ID" "$CB") == "Balanço do B" && $(nprops) == 1 ]] || falhou "nada deveria ter mudado nem a proposta sumido"
tt --demanda-aprovar --minha "$p" >/dev/null || falhou "--minha deveria resolver"
[[ $(texto_de "$ID" "$CB") == "Balanço do B" && $(nprops) == 0 ]] || falhou "--minha mantém o título da B e descarta a proposta"
entrega "$(A --tarefa-email "$ID" ana@x.com)"
[[ $(nprops) == 0 ]] || falhou "reenviar o mesmo conteúdo, que já foi decidido, não deveria virar proposta nova (há $(nprops))"
A --tarefa-editar "$ID" "Balanço da A v2" >/dev/null; entrega "$(A --tarefa-email "$ID" ana@x.com)"; p=$(props)
tt --demanda-aprovar --recebida "$p" >/dev/null
[[ $(texto_de "$ID" "$CB") == "Balanço da A v2" ]] || falhou "--recebida deveria aceitar o título da A: «$(texto_de "$ID" "$CB")»"
passou 'conflito: nada grava sem decidir (sai 4); --minha mantém, --recebida aceita; reenvio decidido não vira proposta'

# 5) ordem e repetição: a velha chegando depois da nova é descartada; a nova substitui as velhas
A --tarefa-editar "$ID" "Versão um" >/dev/null; v1=$(A --tarefa-email "$ID" ana@x.com)
A --tarefa-editar "$ID" "Versão dois" >/dev/null; v2=$(A --tarefa-email "$ID" ana@x.com)
base_t=$((EPOCH + 5000))
entrega "$v2" $((base_t + 100)); entrega "$v1" "$base_t"      # a v2 chega antes, depois a v1 (mais velha)
[[ $(nprops) == 1 && $(texto_de "$(props)" "$CB") == "Versão dois" ]] || falhou "a velha que chega depois deveria ser descartada: $(nprops) proposta(s), «$(texto_de "$(props)" "$CB")»"
tt --demanda-recusar "$(props)" >/dev/null
entrega "$v1" $((base_t + 200)); entrega "$v2" $((base_t + 300))    # agora em ordem: a v2 substitui a v1 pendente
[[ $(nprops) == 1 && $(texto_de "$(props)" "$CB") == "Versão dois" ]] || falhou "a mais nova deveria substituir a pendente mais velha: $(nprops) proposta(s)"
tt --demanda-recusar "$(props)" >/dev/null
passou 'propostas fora de ordem ou repetidas: fica só a mais nova do mesmo remetente'

# 6) compatível com quem não usa o v2 (e-mail à mão / tt antigo): [x] conclui, falta de [x] não reabre
tt --tarefa-add "Tarefa de planilha" >/dev/null; P=$(id_em "Tarefa de planilha" "$CB")
tt --tarefa-sub-add "$P" "linha um" >/dev/null 2>&1; L1=$(id_em "linha um" "$CB")
{ echo "From: Ana <ana@x.com>"; echo "Date: $(date -R -d "@$((EPOCH + 9000))")"; echo "Message-ID: <leg1@t>"; echo "Subject: [tt] Tarefa de planilha ~$P"
  echo "Content-Type: text/plain; charset=utf-8"; echo; printf -- '- [%s] [x] linha um\n' "$L1"; } >"$INBOX/new/leg1"
tt --demandas-processar conta; p=$(props); [[ -n $p ]] || falhou 'e-mail sem rodapé v2 deveria virar proposta'
tt --demanda-aprovar "$p" >/dev/null
[[ $(estado_de "$L1" "$CB") == feita ]] || falhou "[x] de um e-mail legado deveria concluir a subtarefa: $(estado_de "$L1" "$CB")"
{ echo "From: Ana <ana@x.com>"; echo "Date: $(date -R -d "@$((EPOCH + 9100))")"; echo "Message-ID: <leg2@t>"; echo "Subject: [tt] Tarefa de planilha ~$P"
  echo "Content-Type: text/plain; charset=utf-8"; echo; printf -- '- [%s] linha um\n' "$L1"; } >"$INBOX/new/leg2"
tt --demandas-processar conta
[[ $(nprops) == 0 && $(estado_de "$L1" "$CB") == feita ]] || falhou "sem [x] num e-mail legado não é 'reabrir': nada a fazer (props=$(nprops), estado=$(estado_de "$L1" "$CB"))"
passou 'e-mail legado (sem rodapé v2): [x] conclui; sem [x] não reabre nem vira proposta'

# 7) a tela de revisão (vim): decisões por tecla e por clique, tudo recebido / tudo meu, só aplica sem conflito pendente
if ! command -v vim >/dev/null; then echo "pulado: sem vim a tela de revisão não roda aqui"; echo "TODOS OS TESTES PASSARAM"; exit 0; fi
tt --tarefa-editar "$ID" "Título do B" >/dev/null; tt --tarefa-sub-add "$ID" "Sub da B" >/dev/null 2>&1
A --tarefa-editar "$ID" "Título da A" >/dev/null; A --tarefa-sub-add "$ID" "Sub da A" >/dev/null 2>&1
entrega "$(A --tarefa-email "$ID" ana@x.com)"; p=$(props)
plano="$T/plano.tsv"; python3 -I "$T/pkg/tarefas-merge.py" plano "$CB" "$p" >"$plano" || falhou 'o plano deveria sair'
grep -qP '^campo:texto\tcampo\tTítulo\tconflito\t' "$plano" && grep -qP '^sub:[^\t]*:novo\tsub\t[^\t]*\tentrada\t' "$plano" || falhou "o plano deveria ter o conflito do título e a subtarefa nova: $(cut -f1,4 "$plano")"
sess=merge; { tmux kill-session -t $sess 2>/dev/null || true; }
saida="$T/dec.tsv"; : >"$saida"
roda_vim() { # [largura] → sessão tmux com a tela
  { tmux kill-session -t $sess 2>/dev/null || true; }; rm -f "$saida"
  tmux new -d -s $sess -x ${1:-110} -y 34 "TT_MERGE_PLANO=$plano TT_MERGE_SAIDA=$saida vim -u $T/pkg/vimrc-tt -S $T/pkg/tarefas-merge.vim; echo FIM:\$? >$T/vim.fim; sleep 30"
  sleep 1.2
}
bash -c 'DIR_TT=$1; source <(sed -n "/^vimrc_tt_garantir() {/,/^}/p" "$2"); vimrc_tt_garantir' _ "$T/pkg" "$TT"
[[ -s $T/pkg/vimrc-tt ]] || falhou 'não gerou o vimrc do tt'
grep -q '^set encoding=utf-8 fileencoding=utf-8 fileencodings=utf-8$' "$T/pkg/vimrc-tt" || falhou 'o vimrc do tt deve preservar UTF-8 mesmo com locale ASCII'
rm -f "$T/vim.fim"; roda_vim
tela=$(tmux capture-pane -p -t $sess); grep -q '⇄  Atualização de ana@x.com' <<<"$tela" && grep -q 'Aceitar tudo recebido' <<<"$tela" || falhou "a tela de revisão não abriu direito: $tela"
grep -q '⚡ Título' <<<"$tela" && grep -q 'minha     │ Título do B' <<<"$tela" && grep -q 'recebida  │ Título da A' <<<"$tela" || falhou "o bloco do conflito (minha × recebida) não apareceu: $tela"
# no celular (63 colunas) nada passa da largura: os botões e o resumo quebram de linha
roda_vim 63; maior=0
while IFS= read -r l; do ((${#l} > maior)) && maior=${#l}; done < <(tmux capture-pane -p -t $sess)
((maior <= 63)) || falhou "em 63 colunas a tela não pode passar da largura (maior linha: $maior)"
grep -q 'Aceitar tudo recebido' <<<"$(tmux capture-pane -p -t $sess)" || falhou 'em 63 colunas os botões do topo têm de aparecer'
roda_vim
# com conflito sem decisão, Ctrl+S não aplica
tmux send-keys -t $sess C-s; sleep 0.6
[[ ! -e $T/vim.fim && ! -s $saida ]] || falhou 'não pode aplicar com conflito sem decisão'
# clique no botão "Aceitar recebida" do bloco do título (posição lida da tela)
linha=$(tmux capture-pane -p -t $sess | grep -n '\[ Aceitar recebida \]' | head -1 | cut -d: -f1)
texto_l=$(tmux capture-pane -p -t $sess | sed -n "${linha}p"); pre=${texto_l%%\[ Aceitar recebida \]*}; col=$((${#pre} + 4))
tmux send-keys -t $sess -l "$(printf '\033[<0;%s;%sM\033[<0;%s;%sm' "$col" "$linha" "$col" "$linha")"; sleep 0.8
tela=$(tmux capture-pane -p -t $sess); grep -q '✔ Título' <<<"$tela" && grep -q '● recebida  │ Título da A' <<<"$tela" || falhou "o clique deveria escolher a recebida e marcar o conflito como resolvido: $tela"
tmux send-keys -t $sess C-s; sleep 1.2
for _ in $(seq 1 20); do [[ -f $T/vim.fim ]] && break; sleep 0.3; done
[[ $(cat "$T/vim.fim" 2>/dev/null) == FIM:0 ]] || falhou "aplicar deveria sair com 0: $(cat "$T/vim.fim" 2>/dev/null)"
grep -q $'^campo:texto\tinc\t' "$saida" && grep -q $'^sub:.*:novo\tinc\t' "$saida" || falhou "decisões gravadas: $(cat "$saida")"
rc=0; tt --demanda-aprovar "$p" >/dev/null 2>&1 || rc=$?; ((rc == 4)) || falhou "sem aplicar as decisões, a proposta continua em conflito (rc=$rc)"
# teclas: "Manter tudo meu" (M) rejeita também o que entraria sozinho
rm -f "$T/vim.fim"; roda_vim
tmux send-keys -t $sess M; sleep 0.4; tmux send-keys -t $sess C-s; sleep 1.2
for _ in $(seq 1 20); do [[ -f $T/vim.fim ]] && break; sleep 0.3; done
grep -q $'^campo:texto\tcur\t' "$saida" && grep -q $'^sub:.*:novo\tcur\t' "$saida" || falhou "M deveria manter tudo meu: $(cat "$saida")"
# cancelar não grava
rm -f "$T/vim.fim"; roda_vim; tmux send-keys -t $sess Q; sleep 1
for _ in $(seq 1 20); do [[ -f $T/vim.fim ]] && break; sleep 0.3; done
[[ $(cat "$T/vim.fim" 2>/dev/null) != FIM:0 && ! -s $saida ]] || falhou "cancelar não pode gravar decisão: $(cat "$T/vim.fim" 2>/dev/null) / $(cat "$saida" 2>/dev/null)"
{ tmux kill-session -t $sess 2>/dev/null || true; }
passou 'tela de revisão: conflito bloqueia aplicar, clique escolhe, A/M valem para tudo, cancelar não grava'

# 8) as decisões voltam para o tt: --decisoes aplica; manual e "as duas" funcionam
printf 'campo:texto\tmanual\tTítulo combinado\nsub:%s:novo\tinc\t\n' "$(awk -F'\t' '$1=="sub"||1{print $1}' "$plano" | sed -n 's/^sub:\(.*\):novo$/\1/p' | head -1)" >"$T/dec2.tsv"
tarefa_ok=0
python3 -I "$T/pkg/tarefas-merge.py" aplicar "$CB" "$p" --agora 4000000000 --decisoes "$T/dec2.tsv" >"$T/linhas.tsv" || falhou 'aplicar com decisões manuais'
grep -q $'\tTítulo combinado\t' "$T/linhas.tsv" || falhou "o texto manual deveria ir para a tarefa: $(cut -f1,5 "$T/linhas.tsv")"
python3 -I "$T/pkg/tarefas-merge.py" aplicar "$CB" "$p" --agora 4000000000 >/dev/null 2>&1 && falhou 'sem decisão sobre o conflito, aplicar deveria falhar'
python3 -I "$T/pkg/tarefas-merge.py" aplicar "$CB" "$p" --agora 4000000000 --padrao cur | grep -q $'\tTítulo do B\t' || falhou '--padrao cur mantém o título da B'
passou 'decisões voltam para o tt: manual, padrão, e recusa de aplicar com conflito sem decisão'

# 9) aba Entrada: linhas de revisão e de lote; aprovar com conflito abre a revisão; --demanda-merge resolve; lotes
UI="$TT_RT/tt-tarefas-ui-$(id -u)"; acao() { FZF_QUERY= tt --tarefa-acao "$@"; }
A --tarefa-add "Outra tarefa da A" >/dev/null; O=$(id_em "Outra tarefa da A" "$CA")
entrega "$(A --tarefa-email "$O" ana@x.com)"
[[ $(estado_de "$O" "$CB") == pendente ]] || falhou 'a demanda nova (sem conflito) deveria estar pendente'
printf 'filtro=entrada\n' >"$UI"
lista=$(tt --tarefas-lista | sem_cor)
grep -q "^apvt:todas" <<<"$lista" && grep -q "^rect:todas" <<<"$lista" || falhou "com 2 pendentes deveria haver aprovar/recusar todas: $lista"
grep -q "^rev:$p" <<<"$lista" && grep -q "^apv:$p" <<<"$lista" || falhou "a atualização deveria ter ⇄ revisar e ✓ aprovar: $lista"
grep -q '1 ⚡' <<<"$lista" && grep -qE '[0-9]+ mudanças?' <<<"$lista" || falhou "o resumo (mudanças e conflitos) deveria aparecer: $lista"
grep -q 'há conflitos: abre a revisão' <<<"$lista" || falhou "o ✓ aprovar da atualização com conflito deveria avisar que abre a revisão: $lista"
a=$(acao clique "apv:$p"); grep -q "execute(.*--demanda-merge $p)" <<<"$a" || falhou "✓ aprovar com conflito deveria abrir a revisão: $a"
[[ $(estado_de "$p" "$CB") == pendente ]] || falhou 'abrir a revisão não pode aplicar nada'
a=$(acao clique "rev:$p"); grep -q "execute(.*--demanda-merge $p)" <<<"$a" || falhou "⇄ revisar deveria abrir a revisão: $a"
a=$(acao clique "apv:$O"); grep -q 'execute' <<<"$a" && falhou "demanda nova sem conflito aprova na hora (sem abrir tela): $a"
[[ $(estado_de "$O" "$CB") == aberta ]] || falhou 'clicar ✓ aprovar na demanda nova deveria aprová-la'
r=$(TT_MERGE_AUTO=inc tt --demanda-merge "$p" 2>&1) || falhou "--demanda-merge (modo automático: tudo recebido) deveria aplicar: $r"
[[ $(texto_de "$ID" "$CB") == "Título da A" && $(nprops) == 0 ]] || falhou "tudo recebido: o título da A entra e a proposta some: «$(texto_de "$ID" "$CB")» props=$(nprops)"
[[ -n $(id_em "Sub da A" "$CB") && -n $(id_em "Sub da B" "$CB") ]] || falhou 'as duas subtarefas (a da B que já existia e a da A) deveriam estar na tarefa'
# lote: uma atualização com conflito e uma demanda limpa → só a limpa passa; recusar todas limpa o resto
tt --tarefa-editar "$ID" "Título 3 do B" >/dev/null; A --tarefa-editar "$ID" "Título 3 da A" >/dev/null
entrega "$(A --tarefa-email "$ID" ana@x.com)"
A --tarefa-add "Mais uma da A" >/dev/null; O2=$(id_em "Mais uma da A" "$CA"); entrega "$(A --tarefa-email "$O2" ana@x.com)"
r=$(tt --demandas-aprovar-limpas); grep -q '1 aprovada' <<<"$r" || falhou "o lote deveria aprovar só 1 (a sem conflito): $r"
[[ $(estado_de "$O2" "$CB") == aberta && $(nprops) == 1 ]] || falhou "a atualização com conflito deveria ficar pendente: O2=$(estado_de "$O2" "$CB") props=$(nprops)"
r=$(tt --demandas-recusar-todas); grep -q '1 recusada' <<<"$r" || falhou "recusar todas: $r"
[[ $(nprops) == 0 ]] || falhou 'recusar todas deveria limpar a Entrada'
passou 'Entrada: linhas de revisão e de lote, aprovar com conflito abre a revisão, modo automático, aprovar/recusar em lote'
echo "TODOS OS TESTES PASSARAM"
