#!/usr/bin/env bash
# AVALIAÇÃO MANUAL (não roda na suíte): manda frases soltas, com o pedido completo da voz (regras + contexto reais), ao MODELO de verdade
# e imprime o plano (JSON) que ele devolve — sem executar nenhuma ação. Serve para conferir a política de autonomia (decidir o que o
# usuário não disse, sem perguntar), os planos compostos e as ações novas depois de mudar as regras em `voz`.
#   EVAL_MODELO=sonnet tests/avaliar_cerebro.sh            (usa o `claude -p` desta máquina; custa uma chamada por frase)
REAL_HOME=$HOME   # o modelo precisa do login de verdade; o tmux e o tt ficam isolados
source "$(dirname "$0")/lib.sh"; isolar
command -v claude >/dev/null || { echo "sem o claude nesta máquina"; exit 0; }
V=$RAIZ/voz; B=$T/fake; mkdir -p "$B"
cat >"$B/tt" <<FIM
#!/usr/bin/env bash
exec "$TT" "\$@"
FIM
chmod +x "$B/tt"; export PATH="$B:$PATH" VOZ_MUDO=1
for s in site backend deploy-a deploy-b deploy-c relatorios; do tmux new-session -d -s "$s" 'sleep 600'; done
sleep 1
FRASES=(
  "quero trabalhar na conciliação bancária do bimo"
  "resume por tema as sessões que estão abertas"
  "fecha as do deploy que estão paradas e junta o resto numa sessão só"
  "peça para a sessão backend validar o que a site fez"
  "abre uma sessão nova para investigar uma lentidão"
  "aquela conversa que eu tinha com o codex sobre pool de conexões"
  "apaga a tarefa de revisar o contrato e fecha a sessão relatórios"
  "qual é a capital da França"
)
(($#)) && FRASES=("$@")   # frases dadas na linha de comando substituem as de exemplo
for f in "${FRASES[@]}"; do
  VOZ_CEREBRO_CMD="cat > '$T/prompt.txt'; echo '{\"fala\":\"\",\"acoes\":[]}'" bash "$V" "$f" >/dev/null 2>&1
  printf '\n\033[1m› %s\033[0m\n' "$f"
  HOME=$REAL_HOME timeout 120 claude -p --model "${EVAL_MODELO:-sonnet}" --no-session-persistence <"$T/prompt.txt" 2>&1 | python3 -I -c '
import json, sys
t = sys.stdin.read(); i, j = t.find("{"), t.rfind("}")
try:
    d = json.loads(t[i:j + 1])
except Exception:
    print("   (sem JSON) " + t[:300]); sys.exit()
print("   fala:", d.get("fala") or "(vazia)")
for a in d.get("acoes") or []:
    print("   ação:", json.dumps(a, ensure_ascii=False))' || true
done
