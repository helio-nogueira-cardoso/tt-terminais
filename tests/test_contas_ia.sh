#!/usr/bin/env bash
# ia-conta / ia-rot: instalação (apelidos claude-*, versão antiga guardada, skill nos agentes), renomear
# e remover contas, coluna de uso, rotação pulando conta cheia pelo uso e passagem de tarefa no tmux.
# Sem rede: o Claude é falso, os tokens estão vencidos e o uso vem do cache do contas-uso.py.
source "$(dirname "$0")/lib.sh"
isolar
mkdir -p "$HOME/.local/bin" "$HOME/.claude/skills" "$HOME/.codex" "$HOME/.cache"
B=$HOME/.local/bin
# Versão antiga de um claude-rot do usuário (cabeçalho do original) e um claude-conta escrito à mão.
printf '#!/usr/bin/env bash\n# claude-rot — roda um agente headless (antigo)\n' >"$B/claude-rot"
# Claude falso: registra conta e argumentos; "-p" responde a última palavra do prompt.
cat >"$B/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\n' "${CLAUDE_CONFIG_DIR:-principal}" "$*" >>"$HOME/claude.log"
c=${CLAUDE_CONFIG_DIR:-/principal}; c=${c##*/}
[[ $1 == auth ]] && { printf '{\n  "email": "%s@exemplo.com"\n}\n' "$c"; exit 0; }
# Sem prompt (renovação de token pelo ia-conta) o Claude de verdade sai com erro.
[[ $* == *--no-session-persistence ]] && { echo 'Error: Input must be provided' >&2; exit 1; }
for a; do :; done; echo "resposta de ${CLAUDE_CONFIG_DIR##*/}: $a"
EOF
chmod +x "$B/claude"
export PATH=$B:$PATH
instalar_isolado

for n in ia-conta claude-conta ia-rot claude-rot; do
  [[ -L $B/$n ]] || falhou "$n não virou link do pacote"
done
grep -q 'antigo' "$B/claude-rot.antes-tt" || falhou 'claude-rot antigo não foi guardado em .antes-tt'
for c in "$HOME/.claude" "$HOME/.codex"; do
  grep -q '^name: rodizio-de-contas' "$c/skills/rodizio-de-contas/SKILL.md" || falhou "skill ausente em $c"
done
[[ -e $HOME/.kiro ]] && falhou 'criou ~/.kiro sem Kiro instalado'
passou 'instalação: ia-conta/ia-rot + apelidos, versão antiga guardada, skill no Claude e no Codex'

# Contas: credenciais vencidas (a consulta de uso nunca vai à rede).
R=$HOME/.local/share/claude-contas
cred='{"claudeAiOauth":{"accessToken":"t","expiresAt":0}}'
echo "$cred" >"$HOME/.claude/.credentials.json"
for c in alfa beta; do mkdir -p "$R/$c"; echo "$cred" >"$R/$c/.credentials.json"; done
agora=$(date +%s)
cat >"$HOME/.cache/claude-rot.uso.json" <<EOF
{"principal": {"alvo": "$HOME/.claude", "quando": $agora, "janelas": [["5h", 100, $((agora + 3600))], ["7d", 40, $((agora + 86400))]], "email": ""},
 "alfa": {"alvo": "$R/alfa", "quando": $agora, "janelas": [["5h", 20, $((agora + 3600))], ["7d", 50, $((agora + 86400))]], "email": ""}}
EOF

out=$(ia-conta listar --rapido)
grep -qE '^principal +principal@exemplo.com +esgotada +~5h 100%' <<<"$out" || falhou "listar: principal esgotada com uso do cache: $out"
grep -qE '^alfa .*~5h 20% · 7d 50%' <<<"$out" || falhou "listar: uso da alfa: $out"
grep -qE '^beta .* \?$' <<<"$out" || falhou "listar: beta sem dado deveria mostrar ?: $out"
# Sem --rapido renova os tokens vencidos (o Claude sem prompt sai com erro) e lista do mesmo jeito.
: >"$HOME/claude.log"
out2=$(ia-conta listar) || falhou 'listar com renovação de token saiu com erro'
[[ $out2 == "$out" ]] || falhou "listar com renovação difere do --rapido: $out2"
grep -q -- '-p --no-session-persistence' "$HOME/claude.log" || falhou 'listar não renovou os tokens vencidos'
passou 'listar mostra a coluna USO (cache marcado com ~, desconhecido = ?), renovando tokens vencidos'

set +e
IA_CONTA=principal ia-conta uso --eu >"$T/uso"; rc=$?
set -e
[[ $rc == 4 ]] && grep -q $'^principal\t100\tpassar' "$T/uso" || falhou "uso --eu: rc=$rc $(cat "$T/uso")"
passou 'uso --eu: conta da sessão no limite → situação passar, saída 4'

ia-conta renomear alfa gama >/dev/null
[[ -d $R/gama && ! -e $R/alfa ]] || falhou 'renomear não moveu a pasta'
[[ -x $B/claude-gama && ! -e $B/claude-alfa ]] || falhou 'renomear não trocou o atalho claude-<conta>'
grep -q '"gama"' "$HOME/.cache/claude-rot.uso.json" || falhou 'renomear não levou o uso em cache'
ia-conta renomear gama beta 2>/dev/null && falhou 'renomear por cima de conta existente'
ia-conta renomear gama codex 2>/dev/null && falhou 'renomear para nome reservado'
# Conta aberta (processo com CLAUDE_CONFIG_DIR dela) não muda de nome.
CLAUDE_CONFIG_DIR=$R/beta sleep 30 &
aberta=$!
sleep 0.2
ia-conta renomear beta delta 2>"$T/err" && falhou 'renomeou conta aberta'
grep -q 'está aberta' "$T/err" || falhou "mensagem de conta aberta: $(cat "$T/err")"
kill $aberta; wait $aberta 2>/dev/null || true
passou 'renomear: pasta, atalho e cache; recusa existente, reservado e conta aberta'

# Rotação: principal está cheia pelo uso → o ia-rot nem tenta e vai para a próxima.
: >"$HOME/claude.log"
resp=$(cd /tmp && ia-rot --claude-only -p "diga oi" </dev/null 2>"$T/err")
[[ $resp == 'resposta de beta: diga oi' ]] || falhou "rotação não pulou para beta pelo uso: '$resp' $(cat "$T/err")"
grep -q 'principal' "$HOME/claude.log" && falhou 'ia-rot tentou a principal cheia'
passou 'ia-rot pula conta com uso ≥ limite antes de tentar'

ia-conta remover gama --sim >/dev/null
[[ ! -e $R/gama && ! -e $B/claude-gama ]] || falhou 'remover não tirou pasta/atalho'
ls "$R.removidas"/gama-* >/dev/null 2>&1 || falhou 'remover não guardou a pasta'
passou 'remover guarda a pasta em claude-contas.removidas'

# Passagem de tarefa dentro do tmux: abre janela nova na mesma sessão com a próxima conta.
mkdir -p "$T/proj"
printf '# Passagem: teste\n## Próximo passo\nnada\n' >"$T/passagem.md"
tmux -f /dev/null new-session -d -s trabalho -c "$T/proj" -x 120 -y 30
tmux send-keys -t trabalho "cd $(printf '%q' "$T/proj") && IA_CONTA=principal $(printf "%q" "$B/ia-rot") --passar $(printf '%q' "$T/passagem.md") > $(printf '%q' "$T/passar.out") 2>&1; echo fim-passar" Enter
for _ in $(seq 50); do grep -q 'passada' "$T/passar.out" 2>/dev/null && break; sleep 0.1; done
grep -q "tarefa passada para 'beta'" "$T/passar.out" || falhou "passagem: $(cat "$T/passar.out" 2>/dev/null)"
[[ $(tmux list-windows -t trabalho | wc -l) == 2 ]] || falhou 'passagem não abriu janela nova na sessão'
for _ in $(seq 50); do grep -q 'passagem.md' "$HOME/claude.log" && break; sleep 0.1; done
linha=$(grep 'passagem.md' "$HOME/claude.log") || falhou 'próxima conta não recebeu o arquivo de passagem'
[[ $linha == "$R/beta"* && $linha == *"$T/proj"* ]] || falhou "passagem: conta/pasta erradas: $linha"
passou 'ia-rot --passar abre a próxima conta numa janela da mesma aba, lendo a passagem'

# Cadastro comum (e-mail → nome, igual em todas as máquinas). O listar acima já registrou as daqui.
C=$XDG_CONFIG_HOME/tt/contas-ia
# (alfa foi renomeada para gama, e o cadastro acompanhou; "principal" é reservado: vira principal-ia.)
[[ $(awk -F'\t' '{print $1 "=" $2}' "$C" | sort | tr '\n' ' ') == 'alfa@exemplo.com=gama beta@exemplo.com=beta principal@exemplo.com=principal-ia ' ]] ||
  falhou "registro automático: $(cat "$C")"
# Mesclar: por e-mail, a mudança mais nova vence, a ordem de chegada não importa, lixo é ignorado.
printf 'a@x.com\tum\t100\nb@x.com\tdois\t100\nlixo\nc@x.com\tnome com espaço\t1\n' | "$TT" --receber-contas-ia
printf 'a@x.com\tnovo\t200\nb@x.com\tvelho\t50\n' | "$TT" --receber-contas-ia
printf 'a@x.com\tum\t100\n' | "$TT" --receber-contas-ia
[[ $(grep -c . "$C") == 5 ]] && grep -qx $'a@x.com\tnovo\t200' "$C" && grep -qx $'b@x.com\tdois\t100' "$C" ||
  falhou "mesclagem do cadastro: $(cat "$C")"
passou 'cadastro: registro automático; mescla por e-mail, a mais nova vence, lixo fora'

# Conta local com nome já tomado por outro e-mail no cadastro: entra com outro nome; o listar avisa.
mkdir -p "$R/novo"; echo "$cred" >"$R/novo/.credentials.json"
out=$(ia-conta listar --rapido)
grep -q $'^novo@exemplo.com\tnovo-2\t' "$C" || falhou "nome em conflito: $(cat "$C")"
grep -q 'faltam aqui' <<<"$out" && grep -q 'dois  b@x.com  → ia-conta adicionar dois' <<<"$out" || falhou "faltam aqui: $out"
grep -q 'novo  é "novo-2" no cadastro  → ia-conta renomear novo novo-2' <<<"$out" || falhou "nome diferente: $out"
# Falta aqui uma conta cujo nome é de outra conta local: a dica manda renomear antes de adicionar.
t=$(($(date +%s) + 100)) # mais nova que o registro automático
printf 'outro@x.com\tbeta\t%s\nbeta@exemplo.com\tsigma\t%s\n' $t $t | "$TT" --receber-contas-ia
out=$(ia-conta listar --rapido)
grep -q 'beta  outro@x.com  → antes, ia-conta renomear beta sigma; depois ia-conta adicionar beta' <<<"$out" ||
  falhou "dica de nome ocupado: $out"
printf 'outro@x.com\t-\t%s\nbeta@exemplo.com\tbeta\t%s\n' $((t + 1)) $((t + 1)) | "$TT" --receber-contas-ia
passou 'listar: registra com nome livre, mostra o que falta aqui (sem atropelar nome local) e nome diferente'

ia-conta cadastro nomear b@x.com tres >/dev/null
grep -q $'^b@x.com\ttres\t' "$C" || falhou 'cadastro nomear'
ia-conta cadastro nomear tres beta 2>/dev/null && falhou 'nomear com nome de outro e-mail'
ia-conta cadastro esquecer novo >/dev/null
grep -q $'^a@x.com\t-\t' "$C" || falhou 'cadastro esquecer'
out=$(ia-conta cadastro)
grep -q 'a@x.com' <<<"$out" && falhou "esquecida ainda listada: $out"
grep -qE '^beta +beta@exemplo.com +beta$' <<<"$out" && grep -qE '^tres +b@x.com +falta$' <<<"$out" || falhou "cadastro: $out"
ia-conta renomear beta zeta >/dev/null
grep -q $'^beta@exemplo.com\tzeta\t' "$C" || falhou "renomear local não levou o nome do cadastro: $(cat "$C")"
passou 'cadastro: nomear, esquecer, lista com onde está; renomear local acompanha o cadastro'
