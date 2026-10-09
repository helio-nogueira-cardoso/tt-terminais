#!/usr/bin/env bash
# aidlc-tt: publica a bateria de perguntas do AI-DLC na descrição de uma subtarefa, colhe as
# respostas escritas no tt para o .md, traz de volta ao tt a que já estava no .md, preserva a
# descrição anterior como anotação, avisa letra inexistente e "Other" sem texto, não sobrescreve
# conflito e conclui a subtarefa quando tudo estiver respondido. Isola HOME/XDG.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/.config/tt" "$T/bin" "$T/rt"
printf 'nome=A\ntarefas_sync=off\n' >"$T/home/.config/tt/config"
printf '#!/usr/bin/env bash\ncase ${1:-} in list-sessions) exit 1;; display-message) echo cx;; *) exit 0;; esac\n' >"$T/bin/tmux"
chmod +x "$T/bin/tmux"
C="$T/home/.config/tt/tarefas"
ENVS=(HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/state" TT_RT="$T/rt"
  TT_MACHINE=A LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH="$T/bin:$PATH" TT="$ROOT/tt")
run(){ env "${ENVS[@]}" "$ROOT/tt" "$@"; }
aidlc(){ env "${ENVS[@]}" python3 "$ROOT/aidlc-tt" "$@"; }
id_de(){ awk -F'\t' -v t="$1" '$5==t{print $1; exit}' "$C"; }
est(){ awk -F'\t' -v t="$1" '$5==t{print $2; exit}' "$C"; }
desc(){ awk -F'\t' -v t="$1" '$5==t{print $6; exit}' "$C" | tr '|' '\n' | sed -n 's/^desc=//p' | base64 -d; }
fail(){ echo "FALHOU: $1" >&2; exit 1; }

MD="$T/perguntas.md"
cat >"$MD" <<'E'
# Perguntas

## Question 1
Qual cor?

A) ⭐ Azul

B) Verde

C) Other (please describe after [Answer]: tag below)

Por quê: azul combina.

[Answer]:

## Question 2
Qual tamanho?

A) Pequeno

B) Grande

[Answer]: B

## Question 3
Qual prazo?

A) Hoje

B) Amanhã

[Answer]:
E

run --tarefa-add "Projeto" >/dev/null; m=$(id_de Projeto)
run --tarefa-sub-prompt "$m" <<<"Responder perguntas" >/dev/null 2>&1
s=$(id_de "Responder perguntas")
run --tarefa-sub-prompt "$m" <<<"Outra coisa" >/dev/null 2>&1
printf 'nota antiga\n' >"$T/nota"; env "${ENVS[@]}" VISUAL="cp $T/nota" "$ROOT/tt" --tarefa-desc-prompt "$s" </dev/null

# 1) publicar põe as perguntas na descrição, preserva a nota e traz a resposta que já estava no .md
out=$(aidlc publicar "$MD" "$s")
d=$(desc "Responder perguntas")
[[ $(head -1 <<<"$d") == "aidlc: $MD" ]] || fail "marca na primeira linha: $d"
grep -q '^== Q1 · Qual cor?' <<<"$d" && grep -q '^A) ⭐ Azul' <<<"$d" && grep -q '^Por quê: azul combina.' <<<"$d" || fail "pergunta 1 na descrição: $d"
grep -q '^nota antiga$' <<<"$d" || fail "descrição anterior deveria virar anotação"
[[ $(grep -c '^\[Answer\]:' <<<"$d") == 3 ]] || fail "uma linha [Answer]: por pergunta"
grep -q '^\[Answer\]: B$' <<<"$d" || fail "resposta do .md (Q2) deveria voltar ao tt"
grep -q 'respondidas: 1/3' <<<"$out" || fail "resumo do publicar: $out"
[[ $(est "Responder perguntas") == aberta ]] || fail "subtarefa segue aberta com perguntas pendentes"
echo "ok: publicar monta a bateria, preserva a nota e traz a resposta do .md"

# 2) resposta inválida (letra inexistente, Other sem texto) não vai para o .md
responder(){ desc "Responder perguntas" | python3 -c '
import sys,re
d=sys.stdin.read().split("\n"); q=None; r=dict(a.split("=",1) for a in sys.argv[1:])
for i,l in enumerate(d):
    m=re.match(r"^== Q(\d+)",l)
    if m: q=m.group(1)
    elif l.startswith("[Answer]:") and q in r: d[i]="[Answer]: "+r[q]
print("\n".join(d),end="")' "$@" >"$T/nova"; env "${ENVS[@]}" VISUAL="cp $T/nova" "$ROOT/tt" --tarefa-desc-prompt "$s" </dev/null; }
responder 1=C 3=Z
out=$(aidlc colher "$MD")
grep -q "Q1: C é 'Other'" <<<"$out" && grep -q 'Q3: letra Z não existe' <<<"$out" || fail "avisos de resposta inválida: $out"
[[ $(grep -c '^\[Answer\]: *$' "$MD") == 2 ]] || fail ".md não pode receber resposta inválida"
echo "ok: letra inexistente e Other sem texto não são gravados"

# 3) conflito: .md e tt diferentes não se sobrescrevem
responder 2=A
out=$(aidlc colher "$MD")
grep -q "Q2: conflito" <<<"$out" || fail "conflito deveria aparecer: $out"
grep -q '^\[Answer\]: B$' "$MD" || fail ".md não pode ser sobrescrito no conflito"
echo "ok: conflito é reportado e nada é sobrescrito"

# 4) respostas válidas vão para o .md e a subtarefa conclui (a mãe não)
responder 1="C Amarelo, com texto" 2=B 3="B. amanhã cedo"
out=$(aidlc colher "$MD")
grep -q 'respondidas: 3/3' <<<"$out" || fail "resumo final: $out"
grep -q '^\[Answer\]: C Amarelo, com texto$' "$MD" && grep -q '^\[Answer\]: B. amanhã cedo$' "$MD" || fail "respostas no .md: $(grep Answer "$MD")"
[[ $(est "Responder perguntas") == feita ]] || fail "subtarefa deveria concluir"
[[ $(est Projeto) == aberta ]] || fail "a mãe não conclui sozinha"
grep -q '^nota antiga$' <<<"$(desc "Responder perguntas")" || fail "nota some depois do colher"
echo "ok: colher grava no .md e conclui a subtarefa"

# 4b) complemento escrito no tt (começa com a resposta do .md) atualiza o .md em vez de conflitar
responder 3="B. amanhã cedo, depois das 9h"
out=$(aidlc colher "$MD")
! grep -q conflito <<<"$out" || fail "complemento não é conflito: $out"
grep -q '^\[Answer\]: B. amanhã cedo, depois das 9h$' "$MD" || fail "complemento deveria ir ao .md"
echo "ok: complemento no tt atualiza o .md"

# 5) estado não grava; publicar de novo é idempotente e não liga o .md a outra tarefa
antes=$(md5sum <"$MD")
aidlc estado "$MD" | grep -q 'respondidas: 3/3' || fail "estado"
[[ $(md5sum <"$MD") == "$antes" ]] || fail "estado não pode gravar"
aidlc publicar "$MD" "$s" >/dev/null
[[ $(desc "Responder perguntas" | grep -c '^== Q') == 3 ]] || fail "publicar de novo duplicou perguntas"
if aidlc publicar "$MD" "$(id_de "Outra coisa")" >/dev/null 2>&1; then fail "um .md não pode ligar a duas tarefas"; fi
echo "ok: estado só lê; publicar é idempotente e recusa segunda tarefa"
