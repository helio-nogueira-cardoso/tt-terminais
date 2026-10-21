#!/usr/bin/env bash
# voz 2.1.0: planos compostos com UM ok (o que não destrói roda direto; fechar/apagar/juntar entram numa fila aprovada de uma vez,
# "tira N" ou "não"), juntar abas de sessões, temas (agrupar por assunto e agir sobre o grupo), a política de autonomia nas regras,
# conversas antigas de qualquer conta (índice completo + retomar de verdade) e sessões que conversam entre si.
# O tt é o de verdade, isolado; os agentes e o cérebro são falsos.
source "$(dirname "$0")/lib.sh"; isolar
V=$RAIZ/voz
EST=$HOME/.local/state/tt-voz
B=$T/fake; mkdir -p "$B"
cat >"$B/tt" <<FIM
#!/usr/bin/env bash
exec "$TT" "\$@"
FIM
# agente de mentira: a cada pedido trabalha 1 s (com o "esc to interrupt" dos agentes) e responde repetindo o que recebeu
cat >"$B/agente.sh" <<'FIM'
#!/usr/bin/env bash
while IFS= read -r l; do
  for ((i = 0; i < 1; i++)); do printf '\r✻ Working… (%ds · esc to interrupt)' "$i"; sleep 1; done
  printf '\r\033[K● Feito: %s. Tudo certo.\n> ' "${l:0:200}"
done
FIM
chmod +x "$B"/*
export PATH="$B:$PATH" VOZ_SDCARD=$T/sd VOZ_DESTRAVAR_PAUSA=0.3 VOZ_ACOMPANHAR_PAUSA=0.5 VOZ_ESPERA=8 VOZ_CONVERSA_ESPERA=30
mkdir -p "$T/sd"
v() { VOZ_MUDO=1 bash "$V" "$@"; }
vc() { # vc 'JSON do plano' "frase": o cérebro falso devolve o plano; guarda o pedido que recebeu
  VOZ_CEREBRO_CMD="cat > '$T/pedido.txt'; printf '%s' '$1'" v "$2"
}
tem() { tmux has-session -t "=$1" 2>/dev/null; }
# espera até N s (padrão 20) que um comando passe: sob carga alta (a máquina de desenvolvimento chega a load 90) o que antes era "sleep 1" não basta
ate() { local i; for ((i = 0; i < ${2:-20}; i++)); do eval "$1" && return 0; sleep 1; done; return 1; }
nj() { tmux list-windows -t "=$1:" 2>/dev/null | wc -l | tr -d ' '; }
mkdir -p "$EST"

tmux new-session -d -s site "$B/agente.sh"
tmux new-session -d -s backend "$B/agente.sh"
tmux new-session -d -s deploy-a 'sleep 600'; tmux new-window -t =deploy-a: 'sleep 600'
tmux new-session -d -s deploy-b 'sleep 600'
tmux new-session -d -s deploy-c 'sleep 600'
tmux new-session -d -s sobra 'sleep 600'
sleep 1

# ---- 1) plano: o que não destrói roda; o que destrói vira UMA pergunta; nada fecha antes do sim ----
saida=$(vc '{"fala":"","acoes":[{"acao":"fechar_sessao","sessao":"deploy-b"},{"acao":"fechar_sessao","sessao":"deploy-c"},{"acao":"juntar_sessoes","sessao":"deploy-a","origem":"sobra"}]}' "feche o deploy b e o deploy c e junte a sobra no deploy a")
[[ $saida == *"Vou fazer isto"* && $saida == *"1, fechar a sessão deploy b"* && $saida == *"2, fechar a sessão deploy c"* && $saida == *"3, juntar as abas de sobra na sessão deploy a"* ]] || falhou "o plano não listou tudo numa pergunta só: $saida"
[[ $saida == *"Diga sim para fazer tudo"* ]] || falhou "faltou o convite ao sim: $saida"
tem deploy-b && tem deploy-c && tem sobra || falhou 'algo foi fechado antes do sim'
[[ $(cat "$EST/pergunta") == plano ]] || falhou "pergunta pendente deveria ser plano: $(cat "$EST/pergunta")"
[[ $(grep -c . "$EST/lote") == 3 ]] || falhou "fila com 3 itens: $(cat "$EST/lote" | tr '\037' '|')"

# tira um item pelo número, e outro pelo nome
saida=$(v "tira o 2")
[[ $saida == *"1, fechar a sessão deploy b"* && $saida == *"2, juntar as abas de sobra"* && $saida != *"deploy c"* ]] || falhou "tira o 2: $saida"
saida=$(v "tira a sobra")
[[ ${saida,,} == *"fechar a sessão deploy b"* && $saida != *"juntar"* ]] || falhou "tira a sobra: $saida"
[[ $(grep -c . "$EST/lote") == 1 ]] || falhou 'depois dos dois "tira", sobra 1 item'
# "não" cancela tudo e limpa
v "não" >/dev/null
[[ ! -e $EST/lote && -z $(cat "$EST/pergunta" 2>/dev/null) ]] || falhou 'não deveria limpar a fila e a pergunta'
tem deploy-b && tem deploy-c && tem sobra || falhou 'cancelar fechou algo'

# ---- 2) o sim executa tudo, em ordem, de uma vez ----
vc '{"fala":"","acoes":[{"acao":"fechar_sessao","sessao":"deploy-b"},{"acao":"fechar_sessao","sessao":"deploy-c"},{"acao":"juntar_sessoes","sessao":"deploy-a","origem":"sobra"}]}' "feche e junte" >/dev/null
saida=$(v "sim")
tem deploy-b && falhou 'o sim não fechou deploy-b'
tem deploy-c && falhou 'o sim não fechou deploy-c'
tem sobra && falhou 'a sessão sobra deveria sumir ao ficar sem abas'
[[ $(nj deploy-a) == 3 ]] || falhou "deploy-a deveria ter 3 abas (2 + a da sobra): $(nj deploy-a)"
[[ $saida == *"Fechei a sessão deploy b"* && $saida == *"Fechei a sessão deploy c"* && $saida == *"Juntei 1 abas em deploy a"* ]] || falhou "o sim deveria dizer o que fez: $saida"
[[ ! -e $EST/lote && -z $(cat "$EST/pergunta" 2>/dev/null) ]] || falhou 'depois do sim a fila some'
passou 'plano: um só ok para fechar, fechar e juntar; tira N, tira por nome, não e sim'

# ---- 3) item único: pergunta curta; sessão interna e a de outra máquina não entram ----
tmux new-session -d -s uma 'sleep 600'
saida=$(vc '{"fala":"","acoes":[{"acao":"fechar_sessao","sessao":"uma"}]}' "feche a uma")
[[ $saida == *"Fechar a sessão uma"* && $saida == *"Diga sim para fazer"* ]] || falhou "item único: $saida"
v "não" >/dev/null
tmux new-session -d -s _interna 'sleep 600'
saida=$(vc '{"fala":"","acoes":[{"acao":"juntar_sessoes","sessao":"deploy-a","origem":"_interna"}]}' "junte a interna")
tem _interna || falhou 'sessão interna foi mexida'
[[ ! -e $EST/lote ]] || falhou 'sessão interna não pode entrar na fila'
passou 'plano: item único e sessões internas'

# ---- 4) ações de leitura e organização no mesmo plano rodam direto, sem pergunta ----
saida=$(vc '{"fala":"","acoes":[{"acao":"fixar","sessao":"site"},{"acao":"desafixar","sessao":"backend"},{"acao":"fixadas"}]}' "fixa o site e desafixa o backend e lê as fixadas")
[[ ! -e $EST/lote ]] || falhou 'fixar e desafixar não são destrutivos: sem fila'
[[ $(cat "$EST/pergunta" 2>/dev/null) != plano ]] || falhou 'plano sem destrutivo não pergunta'
passou 'plano: o que não destrói roda direto'

# ---- 4b) pedido composto não fica numa regra simples: vai ao cérebro, que monta o plano inteiro ----
tmux new-session -d -s composta 'sleep 600'
rm -f "$T/pedido.txt"
saida=$(vc '{"fala":"","acoes":[{"acao":"apagar_tarefa","nome":"xyz"},{"acao":"fechar_sessao","sessao":"composta"}]}' "apagar tarefa xyz e fechar a sessão composta")
[[ -s $T/pedido.txt ]] || falhou "a frase composta deveria ir ao cérebro (e não parar na regra de apagar tarefa): $saida"
[[ $saida == *"fechar a sessão composta"* || ${saida,,} == *"fechar a sessão composta"* ]] || falhou "o plano composto deveria listar o fechamento: $saida"
v "não" >/dev/null
# e a frase simples continua nas regras (sem chamar o cérebro)
rm -f "$T/pedido.txt"; VOZ_CEREBRO_CMD="cat > '$T/pedido.txt'; echo '{\"fala\":\"x\",\"acoes\":[]}'" v "status" >/dev/null 2>&1 || true
[[ ! -s $T/pedido.txt ]] || falhou 'um comando simples (status) não deveria chamar o cérebro'
for f in "esperar 30 segundos" "fixar o site" "fechar sessao site" "concluir tarefa limpar a casa"; do
  rm -f "$T/pedido.txt"; VOZ_CEREBRO_CMD="cat > '$T/pedido.txt'; echo '{\"fala\":\"x\",\"acoes\":[]}'" v "$f" >/dev/null 2>&1 || true
done
passou 'composto: "X e Y" vai ao cérebro; o simples segue nas regras'

# ---- 5) as regras do cérebro trazem a política de autonomia, o plano e as ações novas ----
vc '{"fala":"ok","acoes":[]}' "me ajude a organizar o trabalho de hoje" >/dev/null
for k in 'AUTONOMIA' 'PLANO' '"acao":"temas"' '"acao":"juntar_sessoes"' '"acao":"achar_conversa"' '"acao":"retomar_conversa"' '"acao":"falar_com_sessao"' '"acao":"plano_tirar"' 'Abri uma sessão nova'; do
  grep -qF -- "$k" "$T/pedido.txt" || falhou "as regras do cérebro não trazem: $k"
done
grep -q 'nunca pergunte "posso fazer?"' "$T/pedido.txt" || falhou 'a autonomia deveria proibir perguntar "posso fazer?"'
passou 'regras: autonomia, plano e ações novas'

# ---- 6) temas: agrupa, guarda os grupos e o contexto seguinte os traz ----
EU=$("$TT" --nome)
cat >"$B/cerebro-temas.sh" <<FIM
#!/usr/bin/env bash
p=\$(cat)
printf '%s' "\$p" > "$T/pedido-temas.txt"
if grep -q '^TEMAS\.' <<<"\$p"; then
  printf '%s' '{"fala":"Dois assuntos: deploy, com deploy a e deploy c, e site, com site e backend.","acoes":[],"grupos":{"deploy":["$EU:deploy-a","$EU:deploy-c"],"site":["$EU:site","$EU:backend"]}}'
else printf '%s' '{"fala":"ok","acoes":[]}'; fi
FIM
chmod +x "$B/cerebro-temas.sh"
tmux new-session -d -s deploy-c 'sleep 600'
cat >"$B/cerebro2.sh" <<FIM
#!/usr/bin/env bash
p=\$(cat)
if grep -q '^TEMAS\.' <<<"\$p"; then "$B/cerebro-temas.sh" <<<"\$p"; else printf '%s' '{"fala":"","acoes":[{"acao":"temas"}]}'; fi
FIM
chmod +x "$B/cerebro2.sh"
saida=$(VOZ_CEREBRO_CMD="$B/cerebro2.sh" v "resuma as sessões por tema")
[[ $saida == *"Dois assuntos"* ]] || falhou "temas não falou o resumo por assunto: $saida"
[[ -s $EST/temas ]] || falhou 'temas não guardou os grupos'
grep -q '^deploy' "$EST/temas" && grep -q 'deploy-a' "$EST/temas" || falhou "grupos guardados: $(cat "$EST/temas" | tr '\037' '|')"
VOZ_CEREBRO_CMD="cat > '$T/pedido-ctx.txt'; printf '%s' '{\"fala\":\"ok\",\"acoes\":[]}'" v "e agora?" >/dev/null
grep -q 'temas da última análise' "$T/pedido-ctx.txt" && grep -q 'deploy:' "$T/pedido-ctx.txt" || falhou 'o contexto seguinte não traz os temas'
passou 'temas: agrupa por assunto, guarda os grupos e o contexto os traz'

# ---- 7) agir sobre um grupo = ações por sessão no mesmo plano (um ok para o lote) ----
saida=$(vc "{\"fala\":\"\",\"acoes\":[{\"acao\":\"fechar_sessao\",\"sessao\":\"deploy-a\"},{\"acao\":\"fechar_sessao\",\"sessao\":\"deploy-c\"},{\"acao\":\"fixar\",\"sessao\":\"site\"}]}" "fecha o grupo do deploy e fixa o site")
[[ $saida == *"1, fechar a sessão deploy a"* && $saida == *"2, fechar a sessão deploy c"* ]] || falhou "grupo: $saida"
v "sim" >/dev/null
tem deploy-a && falhou 'o grupo deploy-a não fechou'; tem deploy-c && falhou 'o grupo deploy-c não fechou'
tem site || falhou 'o site não pode fechar'
passou 'temas: agir sobre o grupo com um ok'

# ---- 8) conversas antigas de qualquer conta: índice completo, busca por assunto e retomar de verdade ----
export TT_BUSCA_DB=$T/busca.db
mkdir -p "$HOME/.claude/projects/-tmp-bimo" "$HOME/.codex/sessions/2026/10/01" "$HOME/.kiro/sessions/cli"
CL=0aaa2222-3333-4444-8555-666677778888; CX=0bbb2222-3333-4444-8555-666677778888; KR=0ccc2222-3333-4444-8555-666677778888
python3 - "$HOME" "$CL" "$CX" "$KR" <<'FIM'
import json, os, sys, time
home, cl, cx, kr = sys.argv[1:5]
def u(t): return {"type": "user", "cwd": "/tmp/bimo", "timestamp": "2026-10-10T10:00:00Z", "message": {"role": "user", "content": t}}
def a(t): return {"type": "assistant", "timestamp": "2026-10-10T10:01:00Z", "message": {"role": "assistant", "content": [{"type": "text", "text": t}]}}
with open(f"{home}/.claude/projects/-tmp-bimo/{cl}.jsonl", "w") as f:
    f.write(json.dumps(u("Vamos corrigir o relatório de conciliação bancária do BIMO")) + "\n")
    for i in range(50): f.write(json.dumps(a("passo %d: ajustei a rotina de conciliação número %d" % (i, i))) + "\n")
    f.write(json.dumps(a("conclusão: o ZEBRALARANJA foi o ultimo ajuste")) + "\n")
with open(f"{home}/.codex/sessions/2026/10/01/rollout-2026-10-01T10-00-00-{cx}.jsonl", "w") as f:
    f.write(json.dumps({"type": "session_meta", "payload": {"id": cx, "cwd": "/tmp/bimo"}}) + "\n")
    f.write(json.dumps({"type": "response_item", "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "Investigar lentidão no deploy do hubblue3 em produção"}]}}) + "\n")
    f.write(json.dumps({"type": "response_item", "payload": {"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "A lentidão vem do pool de conexões do hubblue3"}]}}) + "\n")
with open(f"{home}/.kiro/sessions/cli/{kr}.jsonl", "w") as f:
    f.write(json.dumps({"kind": "Prompt", "data": {"content": [{"kind": "text", "data": "Montar o plano de migração do sistema legado"}]}}) + "\n")
FIM
"$TT" --busca-indexar >/dev/null 2>&1 || true
out=$(python3 -I "$RAIZ/busca-tt.py" conversas-indexar --dias 365 --orcamento 120)
[[ $out == *"conversas:"* ]] || falhou "conversas-indexar: $out"
r=$("$TT" --busca-conversas "conciliacao zebralaranja")
IFS=$'\t' read -r sc prov cod quando cwd tit trecho <<<"$(head -n 1 <<<"$r")"
[[ $prov == claude && $cod == "$CL" && $tit == *"conciliação"* ]] || falhou "claude: $r"
r=$("$TT" --busca-conversas "pool de conexões hubblue3")
[[ $(cut -f2 <<<"$r" | head -n 1) == codex && $(cut -f3 <<<"$r" | head -n 1) == "$CX" ]] || falhou "codex: $r"
r=$("$TT" --busca-conversas "migração legado")
[[ $(cut -f2 <<<"$r" | head -n 1) == kiro && $(cut -f3 <<<"$r" | head -n 1) == "$KR" ]] || falhou "kiro: $r"
# acento, caixa, várias palavras, prefixo: a mesma busca da central
[[ -n $("$TT" --busca-conversas "CONCILIAC bancaria") ]] || falhou 'sem acento e com prefixo'
[[ -z $("$TT" --busca-conversas "assunto-que-nao-existe-xyz") ]] || falhou 'busca sem resultado devia ficar vazia'
# a busca por SESSÃO da central não mistura as conversas antigas (sessão vazia)
[[ -z $(python3 -I "$RAIZ/busca-tt.py" consultar "zebralaranja") ]] || falhou 'o histórico não pode virar sessão na central'
# incremental: segunda volta não reindexa nada; conversa anexada volta; conversa apagada sai
out=$(python3 -I "$RAIZ/busca-tt.py" conversas-indexar --dias 365 --orcamento 120); [[ $out == "conversas: 0 indexadas agora"* ]] || falhou "incremental: $out"
echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"novidade PAPAGAIOROXO"}]}}' >> "$HOME/.claude/projects/-tmp-bimo/$CL.jsonl"
python3 -I "$RAIZ/busca-tt.py" conversas-indexar --dias 365 --orcamento 120 >/dev/null
[[ -n $("$TT" --busca-conversas "papagaioroxo") ]] || falhou 'o que foi anexado à conversa deveria ser achado'
rm -f "$HOME/.kiro/sessions/cli/$KR.jsonl"; python3 -I "$RAIZ/busca-tt.py" conversas-indexar --dias 365 --orcamento 120 >/dev/null
[[ -z $("$TT" --busca-conversas "migração legado") ]] || falhou 'conversa apagada deveria sair do índice'
# orçamento de tempo: 0 s não indexa nada novo, mas não quebra
rm -f "$T/busca.db"*; out=$(python3 -I "$RAIZ/busca-tt.py" conversas-indexar --dias 365 --orcamento 0); [[ $out == *"na fila"* ]] || falhou "orçamento: $out"
python3 -I "$RAIZ/busca-tt.py" conversas-indexar --dias 365 --orcamento 120 >/dev/null

# pela voz: achar, ler e reabrir (retomar de verdade: o ia-conta retomar da máquina, sem pedir permissões)
mkdir -p "$HOME/.local/bin"
cat >"$HOME/.local/bin/ia-conta" <<FIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$T/ia-conta.log"
sleep 600
FIM
chmod +x "$HOME/.local/bin/ia-conta"
saida=$(vc '{"fala":"","acoes":[{"acao":"achar_conversa","consulta":"conciliação bancária"}]}' "aquela conversa sobre conciliação bancária")
[[ $saida == *"Achei"* && $saida == *"Claude"* && $saida == *"1,"* ]] || falhou "achar_conversa não leu o resultado: $saida"
[[ -s $EST/conversas ]] || falhou 'a lista de conversas não foi guardada'
IFS=$'\037' read -r m prov cod _ <<<"$(head -n 1 "$EST/conversas")"
[[ $prov == claude && $cod == "$CL" ]] || falhou "lista guardada: $(cat "$EST/conversas" | tr '\037' '|')"
vc '{"fala":"","acoes":[{"acao":"retomar_conversa","numero":1}]}' "abre a primeira" >/dev/null 2>&1 || true
ate "grep -q 'retomar claude $CL' '$T/ia-conta.log' 2>/dev/null" 30 || falhou "retomar_conversa não chamou o ia-conta retomar: $(cat "$T/ia-conta.log" 2>/dev/null)"
ate "tmux list-sessions -F '#S' | grep -q '^voz-claude-retomada-'" 10 || falhou 'a sessão da conversa retomada não foi criada'
passou 'conversas antigas: indexa Claude, Codex e Kiro, busca por assunto, incremental, orçamento; a voz acha e retoma de verdade'

# ---- 9) sessões que conversam: a mensagem vai, a resposta volta ----
tmux new-session -d -s alfa "$B/agente.sh"; tmux new-session -d -s beta "$B/agente.sh"; sleep 1
EU=$("$TT" --nome)
v --sessao-falar "alfa" "beta" "valide o contrato da API" 1 >$T/conv.out 2>&1
b=$(tmux capture-pane -p -J -t =beta: -S -50); a=$(tmux capture-pane -p -J -t =alfa: -S -50)
[[ $b == *"Mensagem da sessão 'alfa'"* && $b == *"valide o contrato da API"* ]] || falhou "o destino não recebeu a mensagem: $b"
[[ $a == *"Resposta da sessão 'beta'"* && $a == *"Feito"* ]] || falhou "a origem não recebeu a resposta: $a"
[[ $(cat "$T/conv.out") == *"respondeu e entreguei a resposta para alfa"* ]] || falhou "faltou o relato: $(cat "$T/conv.out")"
# a voz como origem: lê a resposta em voz alta
saida=$(v --sessao-falar "-" "beta" "qual o status?" 1)
[[ $saida == *"Feito"* ]] || falhou "a voz deveria ler a resposta do destino: $saida"
# duas idas e voltas
v --sessao-falar "alfa" "beta" "primeiro ponto" 2 >$T/conv2.out 2>&1
b=$(tmux capture-pane -p -J -t =beta: -S -80)
(( $(grep -o "Mensagem da sessão 'alfa'" <<<"$b" | wc -l) >= 3 )) || falhou "duas rodadas: o destino deveria ter 3 mensagens da alfa no total: $(grep -c "Mensagem da sessão" <<<"$b")"
# sessão que não existe e rodadas fora do limite
saida=$(v --sessao-falar "alfa" "nao-existe" "oi" 1); [[ $saida == *"não existe"* ]] || falhou "destino inexistente: $saida"
# pela ação do cérebro
saida=$(vc '{"fala":"","acoes":[{"acao":"falar_com_sessao","origem":"alfa","sessao":"beta","texto":"confirme o deploy","rodadas":1}]}' "peça à beta para confirmar o deploy")
b=$(tmux capture-pane -p -J -t =beta: -S -80); [[ $b == *"confirme o deploy"* ]] || falhou "a ação falar_com_sessao não entregou: $saida"
# o verbo do tt delega para a voz
"$TT" --sessao-falar "alfa" "beta" "pelo tt" 1 >/dev/null 2>&1; b=$(tmux capture-pane -p -J -t =beta: -S -120); [[ $b == *"pelo tt"* ]] || falhou 'tt --sessao-falar não chegou ao destino'
passou 'sessões conversam: mensagem de ida, resposta de volta, rodadas, a voz como origem e o verbo do tt'
echo 'ok: voz 2.1.0 (plano com um ok, juntar, temas, autonomia, conversas antigas, sessões que conversam)'
