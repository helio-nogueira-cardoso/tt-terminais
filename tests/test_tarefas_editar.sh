#!/usr/bin/env bash
# ✎ Editar uma tarefa (F2, botão da barra, ⋯ menu, CLI --tarefa-editar): a frase da tarefa volta
# preenchida com os marcadores que ela tem (tarefas_frase_de) e é relida como na criação
# (tarefas_frase_ler): texto, @prazo (com hora), !prioridade, *repetição e #etiquetas vêm da frase;
# marcador que saiu tira o atributo; a descrição só muda por linhas extras ou pelo editor (Ctrl+E);
# subtarefa só troca o texto; arquivada avisa; --tarefa-renomear segue só no texto.
# Isola HOME/XDG e usa stub de tmux; nenhum arquivo real é tocado.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[[ -x "$TT" ]]; bash -n "$TT"

for fn in tarefas_frase_ler tarefas_frase_de tarefa_editar tarefa_editar_prompt; do
  grep -q "^$fn()" "$TT" || { echo "FALHOU: função $fn ausente"; exit 1; }
done
for v in --tarefa-editar --tarefa-editar-prompt --tarefa-frase; do
  grep -Fq -- "$v" "$TT" || { echo "FALHOU: verbo $v ausente"; exit 1; }
done
corpo_ui=$(sed -n '/^tarefas_ui()/,/^}/p' "$TT")
grep -Fq -- 'f2:transform($a editar {1})' <<<"$corpo_ui" || { echo "FALHOU: F2 não vai para o evento editar"; exit 1; }
grep -q -- "acoes=(nova sub editar .*rotulos=(.*'✎ Editar'" "$TT" || { echo "FALHOU: barra sem o botão ✎ Editar"; exit 1; }
echo "ok: funções, verbos, F2 → editar e o botão ✎ Editar existem"

mkdir -p "$T/home/.config/tt" "$T/bin" "$T/rt"
printf 'nome=A\ntarefas_sync=off\n' >"$T/home/.config/tt/config"
printf '#!/usr/bin/env bash\ncase ${1:-} in list-sessions) exit 1;; display-message) echo cx;; *) exit 0;; esac\n' >"$T/bin/tmux"
chmod +x "$T/bin/tmux"
C="$T/home/.config/tt/tarefas"
UI="$T/rt/tt-tarefas-ui-$(id -u)"
run(){ env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" \
  TT_RT="$T/rt" TT_MACHINE=A LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH="$T/bin:$PATH" "$TT" "$@"; }
acao(){ FZF_QUERY=${Q:-} run --tarefa-acao "$@"; }
sem_cor(){ sed 's/\x1b\[[0-9;]*m//g'; }
id_de(){ awk -F'\t' -v t="$1" '$5==t{print $1; exit}' "$C"; }
txt_de(){ awk -F'\t' -v id="$1" '$1==id{print $5; exit}' "$C"; }
meta_de(){ awk -F'\t' -v id="$1" '$1==id{print $6; exit}' "$C"; }
campo(){ awk -F'\t' -v id="$1" -v n="$2" '$1==id{print $n; exit}' "$C"; }
mv_(){ tr '|' '\n' <<<"$(meta_de "$1")" | sed -n "s/^$2=//p"; }
fail(){ echo "FALHOU: $1" >&2; exit 1; }
printf 'filtro=todas\nmodo=lista\n' >"$UI"

# 1) a frase de uma tarefa traz tudo o que ela tem, do jeito que se escreve
run --tarefa-add-natural "Reunião com a Ana @sex 14h !alta *semanal #casa #trab" >/dev/null
id=$(id_de "Reunião com a Ana"); [[ -n $id ]] || fail "tarefa não criada: $(cat "$C")"
sex=$(date -d "next friday" +%d/%m)
f=$(run --tarefa-frase "$id")
[[ $f == "Reunião com a Ana @$sex 14h !alta *semanal #casa #trab" ]] || fail "frase da tarefa: '$f' (esperava @$sex 14h !alta *semanal #casa #trab)"
criada=$(campo "$id" 3)
echo "ok: --tarefa-frase devolve texto + @DD/MM hora !prio *rep #tags"

# 2) editar relê a frase: texto, prazo com horário (dia com ano), prioridade; *rep saiu → não repete;
#    uma tag saiu → só a outra fica; id e "criada" não mudam
sleep 1
run --tarefa-editar "$id" "Reunião com o Bob @08/09/2026 9h30 !media #casa"
[[ $(txt_de "$id") == "Reunião com o Bob" ]] || fail "texto não mudou: $(txt_de "$id")"
[[ $(mv_ "$id" prazo) == "$(date -d '2026-09-08 09:30' +%s)" ]] || fail "prazo deveria ser 08/09/2026 09:30: $(meta_de "$id")"
[[ $(mv_ "$id" hora) == 1 ]] || fail "prazo com horário deveria marcar hora=1: $(meta_de "$id")"
[[ $(mv_ "$id" prio) == 2 ]] || fail "!media deveria dar prio=2: $(meta_de "$id")"
[[ -z $(mv_ "$id" rep) ]] || fail "sem * a repetição deveria sair: $(meta_de "$id")"
[[ $(mv_ "$id" tags) == casa ]] || fail "só #casa deveria ficar: $(meta_de "$id")"
[[ $(campo "$id" 3) == "$criada" ]] || fail "editar não pode mudar 'criada'"
(( $(campo "$id" 4) > criada )) || fail "editar deveria atualizar 'mudada'"
[[ $(run --tarefa-frase "$id") == "Reunião com o Bob @08/09/2026 9h30 !media #casa" ]] || fail "frase de prazo passado deveria vir com o ano: $(run --tarefa-frase "$id")"
echo "ok: editar muda texto/prazo/hora/prio/tags; marcador que saiu tira o atributo; dia passado volta com o ano"

# 3) frase sem marcador nenhum: a tarefa fica só com o texto
run --tarefa-editar "$id" "Reunião com o Bob"
[[ $(txt_de "$id") == "Reunião com o Bob" && -z $(meta_de "$id") ]] || fail "sem marcadores deveria limpar prazo/hora/prio/rep/tags: '$(meta_de "$id")'"
echo "ok: tirar todos os marcadores deixa a tarefa só com o texto"

# 4) descrição não é marcador: fica numa edição de uma linha; linhas extras a substituem
run --tarefa-editar "$id" $'Bob @amanha\n\nPreparar a pauta\ne levar o contrato'
[[ $(run --tarefa-preview "$id" | sem_cor) == *"Preparar a pauta"*"levar o contrato"* ]] || fail "linhas extras deveriam virar a descrição"
d64=$(mv_ "$id" desc)
run --tarefa-editar "$id" "Bob @hoje !alta"
[[ $(mv_ "$id" desc) == "$d64" ]] || fail "edição de uma linha não pode mexer na descrição"
[[ $(mv_ "$id" prio) == 1 ]] || fail "!alta na edição de uma linha deveria valer"
run --tarefa-editar-prompt "$id" <<<"Bob de novo @10/10 !alta" >/dev/null 2>&1
[[ $(txt_de "$id") == "Bob de novo" && $(mv_ "$id" desc) == "$d64" ]] || fail "prompt (⏎) deveria editar o título e manter a descrição: $(cat "$C")"
run --tarefa-editar-prompt "$id" <<<"   " >/dev/null 2>&1
[[ $(txt_de "$id") == "Bob de novo" ]] || fail "⏎ vazio no prompt deveria cancelar"
run --tarefa-editar "$id" "   " >/dev/null 2>&1 && fail "editar sem texto deveria falhar"
[[ $(txt_de "$id") == "Bob de novo" ]] || fail "editar sem texto não pode apagar o título"
echo "ok: descrição fica na edição de uma linha; linhas extras a substituem; vazio cancela"

# 5) Ctrl+E no prompt: o editor recebe a frase em cima e a descrição embaixo, e o que volta vale —
#    descrição apagada no editor some (pseudo-terminal pelo python; sem python, pula)
if command -v python3 >/dev/null; then
  printf '#!/usr/bin/env bash\ncp "$1" "%s/recebido"; printf "Titulo do editor @amanha !alta\\n" >"$1"\n' "$T" >"$T/bin/ed-falso"
  chmod +x "$T/bin/ed-falso"
  cat >"$T/tty-falso.py" <<'EOF'
import os, pty, sys, time, select
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
time.sleep(1.0)
os.write(fd, b'\x05')          # Ctrl+E abre o editor; na volta o prompt confirma
fim = time.time() + 20
while time.time() < fim:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            if not os.read(fd, 4096): break
        except OSError: break
    if os.waitpid(pid, os.WNOHANG)[0]: break
EOF
  env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" TT_RT="$T/rt" TT_MACHINE=A \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH="$T/bin:$PATH" VISUAL="$T/bin/ed-falso" TERM=xterm \
    timeout 40 python3 -I "$T/tty-falso.py" "$TT" --tarefa-editar-prompt "$id" >/dev/null 2>&1 || fail "prompt pelo pseudo-terminal falhou"
  [[ -f $T/recebido ]] || fail "Ctrl+E não abriu o editor (VISUAL)"
  [[ $(sed -n 1p "$T/recebido") == "Bob de novo @10/10 !alta" ]] || fail "o editor deveria receber a frase na 1ª linha: $(cat "$T/recebido")"
  grep -q 'Preparar a pauta' "$T/recebido" || fail "o editor deveria receber a descrição embaixo: $(cat "$T/recebido")"
  [[ $(txt_de "$id") == "Titulo do editor" ]] || fail "o título do editor deveria valer: $(txt_de "$id")"
  [[ $(mv_ "$id" prio) == 1 && -z $(mv_ "$id" desc) ]] || fail "o que voltou do editor vale: !alta e sem descrição: $(meta_de "$id")"
  echo "ok: Ctrl+E edita no editor com a descrição embaixo, e o que volta vale (descrição apagada some)"
else
  echo "pulado: sem python3 para o pseudo-terminal do Ctrl+E"
fi

# 6) subtarefa: a frase é só o texto e editar não lê marcadores (como na criação dela)
run --tarefa-sub-prompt "$id" <<<"ligar @amanha" >/dev/null 2>&1
s=$(id_de "ligar @amanha"); [[ -n $s ]] || fail "subtarefa não criada"
[[ $(run --tarefa-frase "$s") == "ligar @amanha" ]] || fail "frase da subtarefa deveria ser só o texto"
run --tarefa-editar "$s" "ligar @hoje !alta"
[[ $(txt_de "$s") == "ligar @hoje !alta" ]] || fail "subtarefa: o texto vale literal: $(txt_de "$s")"
[[ $(mv_ "$s" pai) == "$id" && -z $(mv_ "$s" prio) ]] || fail "subtarefa: mãe fica e marcador não vira atributo: $(meta_de "$s")"
run --tarefa-editar-prompt "$s" <<<"ligar depois" >/dev/null 2>&1
[[ $(txt_de "$s") == "ligar depois" && $(mv_ "$s" pai) == "$id" ]] || fail "prompt da subtarefa deveria renomear e manter a mãe"
echo "ok: subtarefa edita só o texto e mantém a mãe"

# 7) os quatro caminhos do painel levam ao mesmo prompt: F2/evento, botão da barra, menu ⋯, clique no item
esperado="execute($TT --tarefa-editar-prompt $id)+reload-sync($TT --tarefas-lista {q})+transform-header($TT --tarefas-cabecalho)"
[[ $(acao editar "$id") == "$esperado" ]] || fail "evento editar (F2): $(acao editar "$id")"
[[ $(acao renomear "$id") == "$esperado" ]] || fail "evento renomear (nome antigo) deveria editar"
FZF_COLUMNS=72 run --tarefas-cabecalho >/dev/null
read -r ln c1 c2 _ < <(awk '$4=="editar"' "$T/rt/tt-tarefas-mapa-$(id -u)")
[[ -n ${ln:-} ]] || fail "mapa do cabeçalho sem o botão editar"
cab=$(FZF_COLUMNS=72 run --tarefas-cabecalho | sem_cor); l=$(sed -n "${ln}p" <<<"$cab")
[[ ${l:$((c1 - 1)):$((c2 - c1 + 1))} == *"✎ Editar"* ]] || fail "botão ✎ Editar desalinhado no mapa: '${l:$((c1 - 1)):$((c2 - c1 + 1))}'"
[[ $(FZF_CLICK_HEADER_LINE=$ln FZF_CLICK_HEADER_COLUMN=$((c1 + 1)) acao cabecalho "$id") == "$esperado" ]] || fail "clique no botão ✎ Editar"
acao menu "$id" >/dev/null
mn=$(run --tarefas-lista | sem_cor)
grep -q "^act:editar:$id	.*✎ Editar…  F2 · texto e @prazo" <<<"$mn" || fail "menu da tarefa sem ✎ Editar… (com a dica dos marcadores): $mn"
[[ $(acao clique "act:editar:$id") == "$esperado" ]] || fail "item ✎ Editar do menu"
[[ $(sed -n 's/^modo=//p' "$UI" | tail -1) == lista ]] || fail "o item do menu deveria voltar à lista"
acao menu "$s" >/dev/null
grep -q "^act:editar:$s	.*✎ Editar…  F2 · o texto" <<<"$(run --tarefas-lista | sem_cor)" || fail "menu da subtarefa deveria oferecer ✎ Editar… (só o texto)"
printf 'filtro=todas\nmodo=lista\n' >"$UI"
echo "ok: F2, botão ✎ Editar, menu ⋯ e clique no item chamam o mesmo prompt"

# 8) arquivada não edita (avisa para restaurar); --tarefa-renomear segue trocando só o texto
run --tarefa-add-natural "Velha @hoje #x" >/dev/null; v=$(id_de Velha)
run --tarefa-arquivar "$v" >/dev/null
r=$(acao editar "$v"); [[ $r != *--tarefa-editar-prompt* ]] || fail "arquivada não deveria abrir o prompt"
grep -q '⚠ Tarefa arquivada' <<<"$(FZF_COLUMNS=90 run --tarefas-cabecalho | sem_cor)" || fail "arquivada deveria avisar para restaurar"
run --tarefa-restaurar "$v" >/dev/null
run --tarefa-renomear "$v" "Velha renomeada @amanha"
[[ $(txt_de "$v") == "Velha renomeada @amanha" && $(mv_ "$v" tags) == x ]] || fail "--tarefa-renomear deveria trocar só o texto, sem ler marcadores: $(grep "$v" "$C")"
echo "ok: arquivada avisa; --tarefa-renomear continua só no texto"

# 9) ida e volta: a frase que o tt mostra, gravada de novo sem mexer, dá a mesma tarefa
run --tarefa-add-natural "Ida e volta @amanha às 18h !alta *mensal #a #b" >/dev/null; iv=$(id_de "Ida e volta")
antes=$(meta_de "$iv"); run --tarefa-editar "$iv" "$(run --tarefa-frase "$iv")"
[[ $(meta_de "$iv") == "$antes" ]] || fail "reler a própria frase mudou a tarefa: '$antes' → '$(meta_de "$iv")'"
echo "ok: a frase relida sem mudança não altera nada"

# 10) ajuda do painel explica o editar
h=$(run --tarefas-ajuda)
grep -q '✎ Editar' <<<"$h" && grep -q 'F2 editar' <<<"$h" || fail "ajuda sem ✎ Editar / F2 editar"
echo "ok: ajuda do painel explica ✎ Editar (F2)"

echo "ok: ✎ Editar — frase preenchida, relida como na criação; marcador que saiu tira o atributo"
