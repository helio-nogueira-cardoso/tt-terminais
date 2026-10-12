#!/usr/bin/env bash
# Código e apelido das tarefas + upsert por e-mail: o código é o id (igual em toda máquina), o apelido
# (ex.: kito47) sai dele; verbos de CLI aceitam apelido/prefixo/MÃE.N; e-mail com "~código" cria a
# tarefa com o MESMO código quando ela não existe e vira PROPOSTA DE ATUALIZAÇÃO quando existe.
source "$(dirname "$0")/lib.sh"; isolar
tt() { "$TT" "$@"; }
fail() { echo "FALHOU: $1" >&2; exit 1; }
mkdir -p "$T/bin"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/notify-send"; printf '#!/bin/sh\nexit 1\n' >"$T/bin/tmux"; chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"
C="$XDG_CONFIG_HOME/tt/tarefas"; D="$XDG_CONFIG_HOME/tt/demandas"
INBOX="$HOME/.cache/tt/maildir/conta/INBOX"; mkdir -p "$INBOX/new"

# 1) apelido: CVCV+2 dígitos, estável, igual no awk e no bash
tt --tarefa-add "Revisar contrato" ; id=$(cut -f1 "$C" | head -1)
tt --tarefa-sub-add "$id" "Ler cláusula 4"; tt --tarefa-sub-add "$id" "Enviar ao jurídico"
slug=$(tt --tarefa-codigo "$id" | cut -f1)
[[ $slug =~ ^[bdfgjklmnprstvz][aeiou][bdfgjklmnprstvz][aeiou][0-9]{2}$ ]] || fail "apelido fora do formato: $slug"
[[ $(tt --tarefa-codigo "$id" | cut -f1) == "$slug" ]] || fail "apelido não é estável"
[[ $(tt --tarefa-codigo | wc -l) == 3 ]] || fail "--tarefa-codigo sem argumento deveria listar as 3 tarefas"
echo "ok: apelido $slug"

# 2) verbos aceitam apelido, prefixo e MÃE.N
sub1=$(tt --tarefa-codigo "$slug.1" | cut -f2); [[ -n $sub1 ]] || fail "MÃE.1 deveria resolver"
tt --tarefa-ok "$slug.1" || fail "MÃE.N deveria concluir a 1ª subtarefa"
[[ $(awk -F'\t' -v i="$sub1" '$1==i{print $2}' "$C") == feita ]] || fail "subtarefa 1 deveria estar feita"
tt --tarefa-ok "${id:0:6}" 2>/dev/null && fail "mãe não conclui com subtarefa aberta"
tt --tarefa-rm "$slug.9" 2>/dev/null && fail "MÃE.N inexistente deveria falhar"
tt --tarefa-editar "$slug" "Revisar contrato @sex !alta" || fail "editar por apelido"
grep -q $'\tRevisar contrato\t.*prio=1' "$C" || fail "edição por apelido não gravou"
lista=$(tt --tarefas 2>&1); grep -q "\[$slug $id\]" <<<"$lista" || fail "listagem em texto deveria mostrar apelido e código: $lista"
echo "ok: apelido, prefixo e MÃE.N nos verbos"

# 3) e-mail de compartilhamento: assunto com ~código, subtarefas com código e [x]
out=$(tt --tarefa-email "$slug" fulano@x.com)
grep -q "^Assunto: \[tt\] Revisar contrato .*~$id$" <<<"$out" || fail "assunto sem ~código: $out"
grep -q "^- \[$sub1\] \[x\] Ler cláusula 4$" <<<"$out" || fail "subtarefa feita sem código/[x]: $out"
grep -q '^mailto:fulano%40x.com?subject=' <<<"$out" || fail "faltou o link mailto"
echo "ok: texto de compartilhamento"

# 4) recebimento: outra pessoa (código desconhecido) -> pendente com o MESMO código; depois, atualização
tt --demanda-autorizar chefe@empresa.com.br - aberto >/dev/null
eml() { # nome assunto corpo
  { echo "From: Chefe <chefe@empresa.com.br>"; echo "Date: Fri, 09 Oct 2026 14:00:00 -0300"; echo "Message-ID: <$1@t>"
    echo "Subject: $2"; echo "Content-Type: text/plain; charset=utf-8"; echo; printf '%s\n' "$3"; } >"$INBOX/new/$1"
}
NOVO=abc123def456; S1=111111aaaaaa
eml m1 "[tt] Preparar reunião @sex !alta ~$NOVO" $'Pauta no anexo\n- ['"$S1"$'] Reservar sala\n- Mandar convite'
tt --demandas-processar conta
[[ $(awk -F'\t' -v i="$NOVO" '$1==i{print $2}' "$C") == pendente ]] || fail "tarefa nova deveria nascer pendente com o código do e-mail: $(cut -f1,2,5 "$C")"
[[ $(awk -F'\t' -v i="$S1" '$1==i{print $2}' "$C") == pendente ]] || fail "subtarefa deveria manter o código do e-mail"
tt --demanda-aprovar "$(tt --tarefa-codigo "$NOVO" | cut -f1)" >/dev/null || fail "aprovar por apelido"
[[ $(awk -F'\t' -v i="$NOVO" '$1==i{print $2}' "$C") == aberta ]] || fail "aprovada deveria ficar aberta com o mesmo código"
[[ $(awk -F'\t' -v i="$S1" '$1==i{print $2}' "$C") == aberta ]] || fail "subtarefa aprovada deveria ficar aberta"
echo "ok: criação com o código do remetente"

# 5) mesmo código de novo: vira PROPOSTA; aprovar atualiza a mesma tarefa (sem duplicar), recusar não toca
eml m2 "[tt] Preparar reunião de diretoria @seg !media ~$NOVO" $'Nova pauta\n- ['"$S1"$'] [x] Reservar sala (feito)\n- [222222bbbbbb] Imprimir pauta\n- Mandar convite'
tt --demandas-processar conta
n_top=$(awk -F'\t' '$2=="pendente" && $6 !~ /pai=/' "$C" | wc -l)
[[ $n_top == 1 ]] || fail "deveria haver 1 proposta pendente: $(cut -f1,2,5 "$C")"
tt --demandas-pendentes | grep -q "\[atualiza $NOVO\]" || fail "proposta deveria aparecer como atualização"
[[ $(awk -F'\t' -v i="$NOVO" '$1==i{print $5}' "$C") == "Preparar reunião" ]] || fail "a tarefa não pode mudar antes de aprovar"
prop=$(awk -F'\t' '$2=="pendente" && $6 !~ /pai=/{print $1}' "$C")
tt --demanda-aprovar "$prop" >/dev/null
[[ $(awk -F'\t' -v i="$NOVO" '$1==i{print $5}' "$C") == "Preparar reunião de diretoria" ]] || fail "aprovar deveria atualizar o texto da mesma tarefa"
[[ $(awk -F'\t' -v i="$NOVO" '$1==i{print $6}' "$C") == *prio=2* ]] || fail "prioridade deveria virar média"
[[ $(awk -F'\t' -v i="$S1" '$1==i{print $2}' "$C") == feita ]] || fail "subtarefa com [x] deveria ficar feita"
[[ $(awk -F'\t' -v i=222222bbbbbb '$1==i{print $2}' "$C") == aberta ]] || fail "subtarefa nova com código deveria ser criada"
[[ $(awk -F'\t' -v p="$NOVO" '$6 ~ "pai="p && $2!="removida"' "$C" | wc -l) == 3 ]] || fail "'Mandar convite' não pode duplicar: $(cut -f2,5 "$C")"
[[ $(awk -F'\t' '$2=="pendente"' "$C" | wc -l) == 0 ]] || fail "nada deve ficar pendente depois de aprovar"
eml m3 "[tt] Trocar tudo ~$NOVO" 'x'
tt --demandas-processar conta
prop=$(awk -F'\t' '$2=="pendente" && $6 !~ /pai=/{print $1}' "$C")
tt --demanda-recusar "$prop" >/dev/null
[[ $(awk -F'\t' -v i="$NOVO" '$1==i{print $5}' "$C") == "Preparar reunião de diretoria" ]] || fail "recusar não pode tocar a tarefa"
echo "ok: upsert por código (proposta, aprovar, recusar, sem duplicar)"

# 6) removida não ressuscita por e-mail
tt --tarefa-rm "$NOVO"
eml m4 "[tt] Volta ~$NOVO" 'x'
tt --demandas-processar conta
[[ $(awk -F'\t' '$2=="pendente"' "$C" | wc -l) == 0 ]] || fail "tarefa removida não pode voltar por e-mail"
echo "ok: removida não ressuscita"

# 7) registro de trabalho padronizado na descrição (tt --tarefa-log) e histórico com totais
tt --tarefa-add "Logar" >/dev/null; L=$(awk -F'\t' '$5=="Logar"{print $1}' "$C")
tt --tarefa-sub-add "$L" "Parte um" >/dev/null; LS=$(tt --tarefa-codigo "$(tt --tarefa-codigo | awk -F'\t' '$3=="Parte um"{print $1}')" | cut -f2)
tt --tarefa-desc "$L" $'aidlc: /tmp/x.md\nnota do dono'
tt --tarefa-log "$L" "Implementei o login" --como "editei tt e rodei os testes" --agente claude --modelo claude-sonnet-5-5 --esforco high \
   --tokens-ent 10000 --tokens-sai 2300 --usd 0,09 --brl 0,45 --sessao impl-3 --sessao-codigo 1234abcd --maquina notebook --conta trabalho --email voce@exemplo.com \
   --inicio 2026-10-10T15:10:00-03:00 --fim 2026-10-10T15:52:00-03:00 || fail "tarefa-log falhou"
printf 'modelo-x\t3\t15\n' >"$XDG_CONFIG_HOME/tt/precos"; echo 'cotacao_brl=5' >>"$XDG_CONFIG_HOME/tt/config"
tt --tarefa-log "$LS" "Fechei a parte um" --modelo modelo-x --tokens-ent 1000000 --tokens-sai 0 --agente codex --inicio 2026-10-10T15:10:00Z --fim 2026-10-10T15:52:00Z || fail "tarefa-log da subtarefa falhou"
raw=$(awk -F'\t' -v i="$L" '$1==i{print $6}' "$C" | tr '|' '\n' | sed -n 's/^desc=//p' | base64 -d)
grep -q '^aidlc: /tmp/x.md' <<<"$raw" && grep -q '^nota do dono' <<<"$raw" || fail "o log não pode apagar a descrição que já existia: $raw"
grep -q "^⟡ .* · $(tt --tarefa-codigo "$L" | cut -f1)$" <<<"$raw" || fail "cabeçalho do registro (quando · apelido): $raw"
grep -q '^  fez: Implementei o login$' <<<"$raw" && grep -q '^  como: editei tt' <<<"$raw" || fail "fez/como: $raw"
grep -q '^  por: claude · claude-sonnet-5-5 · esforço high · sessão impl-3 \[código 1234abcd\] · máquina notebook$' <<<"$raw" || fail "linha 'por': $raw"
grep -q '^  conta: trabalho <voce@exemplo.com>$' <<<"$raw" || fail "linha 'conta': $raw"
grep -q '^  período: 2026-10-10T15:10:00-03:00 → 2026-10-10T15:52:00-03:00$' <<<"$raw" || fail "período com fuso: $raw"
grep -q '^  uso: 12300 tokens (10000 ent · 2300 sai) · ≈ US\$ 0,0900 · ≈ R\$ 0,45$' <<<"$raw" || fail "linha 'uso': $raw"
rawsub=$(awk -F'\t' -v i="$LS" '$1==i{print $6}' "$C" | tr '|' '\n' | sed -n 's/^desc=//p' | base64 -d)
grep -q '≈ R\$ 15,00$' <<<"$rawsub" || fail "custo por tabela de preços (1M ent × US\$3 × 5): $rawsub"
tt --tarefa-log "$L" "sem nada" --agente claude --inicio 2026-10-10T15:52:00Z --fim 2026-10-10T15:53:00Z >/dev/null && true
h=$(tt --tarefa-historico "$L")
grep -q '^Total: 3 registros · 1012300 tokens · ≈ US\$ 3,0900 · ≈ R\$ 15,45$' <<<"$h" || fail "total do histórico: $h"
tt --tarefa-log "$L" 2>/dev/null && fail "sem texto deveria falhar"
tt --tarefa-log "$L" "x" --foo 1 2>/dev/null && fail "opção desconhecida deveria falhar"
tt --tarefa-log "$L" "x" --inicio 2026-10-10T15:00:00 --fim 2026-10-10T15:01:00 2>/dev/null && fail "timestamp sem fuso deveria falhar"
tt --tarefa-log "$L" "x" --inicio 2026-10-10T15:00Z --fim 2026-10-10T15:01Z 2>/dev/null && fail "RFC3339 sem segundos deveria falhar"
echo "ok: registro de trabalho (identidade de sessão, intervalo RFC3339, tokens e custos USD/BRL)"

# 8) o tt injeta a skill em TODAS as IAs (vigia/instalação via reforcar_agentes); as regras: test_agentes_md.sh
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.kiro"
tt --reforcar-agentes
for ag in .claude .codex .kiro; do cmp -s "$T/pkg/skill-tt-terminais.md" "$HOME/$ag/skills/tt-terminais/SKILL.md" || fail "skill tt-terminais ausente/desatualizada em $ag"; done
grep -q 'tt --tarefa-log' "$HOME/.claude/CLAUDE.md" || fail "regras do tt ausentes no Claude"
rm -rf "$HOME/.kiro"; tt --reforcar-agentes; [[ -e $HOME/.kiro ]] && fail "IA que não existe não pode ser criada"
echo "ok: skill e regras em todas as IAs que existem"
