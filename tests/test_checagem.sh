#!/usr/bin/env bash
# Checagem pós-atualização: o coletor (tt --checar) acusa vigia parado, pacote incompleto ou com arquivo do
# usuário e e-mail com erro; o agente (tt --checar-agente, por um ia-rot de mentira) recebe o pedido com o
# coletor, o trecho novo do NOVIDADES.md e os limites, roda sem pedir permissão e fecha a rodada (histórico,
# relatório, aviso no 🔔); o vigia (--checar-auto) dispara uma vez por versão nova, não incomoda máquina
# recém-instalada, respeita checagem_auto=0 e, sem conta livre, tenta 3 vezes e fecha só com o coletor; as
# rodadas antigas são podadas; o handoff empacota tudo sem segredo nem e-mail legível.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
ES=$HOME/.local/state/tt CK=$HOME/.local/state/tt/checagens
mkdir -p "$T/bin"

# ia-rot de mentira: --melhor diz se há conta livre ($T/sem-conta existe = não há); -p grava o que recebeu e
# escreve o relatório na pasta da rodada que o pedido indica, como o agente de verdade faria.
cat >"$T/bin/ia-rot" <<'FIM'
#!/usr/bin/env bash
T=${0%/bin/ia-rot}
if [[ ${1:-} == --melhor ]]; then [[ -e $T/sem-conta ]] && exit 2; printf 'principal\t10\t-\n'; exit 0; fi
printf '%s\n' "$@" >"$T/args"
[[ $1 == -p ]] && printf '%s' "$2" >"$T/pedido"
rod=$(grep -o 'Pasta desta rodada: `[^`]*`' <<<"$2" | sed 's/.*`\(.*\)`/\1/')
printf '# Checagem\n\nRESUMO: ok=8 aviso=1 falha=0 corrigido=2\n' >"$rod/relatorio.md"
echo "agente rodou"
FIM
chmod +x "$T/bin/ia-rot"
export TT_IA_ROT=$T/bin/ia-rot

esperar_hist() { # n linhas no histórico
  local i; for i in $(seq 1 50); do (($( { wc -l <"$CK/historico.log"; } 2>/dev/null || echo 0) >= $1)) && return 0; sleep 0.2; done; return 1
}

# --- Coletor -------------------------------------------------------------------------------------------
saida=$("$TT" --checar --tsv) || true
for id in vigia atualizacao partida-rapida separacao email tarefas malha agentes pendencias hora; do
  grep -q "^$id"$'\t' <<<"$saida" || falhou "coletor sem a checagem $id: $saida"
done
grep -q $'^vigia\tfalha\t' <<<"$saida" || falhou "vigia parado deveria ser falha: $(grep ^vigia <<<"$saida")"
grep -q $'^separacao\tok\t' <<<"$saida" || falhou "pacote recém-instalado deveria estar ok: $(grep ^separacao <<<"$saida")"
"$TT" --checar >/dev/null && falhou '--checar deveria sair 1 com falha'
passou 'coletor: todas as checagens, vigia parado é falha e o --checar sai 1'

# Logo depois de instalar, o publicado guardado é o da sonda anterior: não pode acusar a máquina de atrasada.
inst=$(stat -c %Y "$TT_DIR/VERSAO")
printf 'sonda_em=%s\npublicado=%s\n' $((inst - 60)) 0123456789abcdef0123456789abcdef01234567 >"$ES/atualizacao"
l=$(grep '^atualizacao' <<<"$("$TT" --checar --tsv)")
[[ $l == atualizacao$'\t'ok$'\t'* ]] || falhou "sonda anterior à instalação acusou atraso: $l"
printf 'sonda_em=%s\npublicado=%s\n' $((inst + 60)) 0123456789abcdef0123456789abcdef01234567 >"$ES/atualizacao"
l=$(grep '^atualizacao' <<<"$("$TT" --checar --tsv)")
[[ $l == atualizacao$'\t'aviso$'\t'* ]] || falhou "sonda posterior com outro publicado deveria ser aviso: $l"
rm -f "$ES/atualizacao"
passou 'atualização: publicado de antes da instalação não acusa atraso; o de depois, sim'

echo minha-config >"$TT_DIR/meu-arquivo"
grep -q $'^separacao\taviso\t.*meu-arquivo' <<<"$("$TT" --checar --tsv)" || falhou 'arquivo do usuário no pacote não foi acusado'
rm -f "$TT_DIR/meu-arquivo"; mv "$TT_DIR/sessoes-ia.py" "$T/guardado"
grep -q $'^separacao\tfalha\t.*sessoes-ia.py' <<<"$("$TT" --checar --tsv)" || falhou 'pacote incompleto não foi acusado'
mv "$T/guardado" "$TT_DIR/sessoes-ia.py"
cp "$TT_DIR/email-tt.py" "$XDG_CONFIG_HOME/tt/velho.py"
grep -q $'^separacao\taviso\t.*velho.py' <<<"$("$TT" --checar --tsv)" || falhou 'código no perfil não foi acusado'
rm -f "$XDG_CONFIG_HOME/tt/velho.py"
passou 'separação: arquivo do usuário no pacote, pacote incompleto e código no perfil'

mkdir -p "$XDG_CONFIG_HOME/tt/email" "$ES/email-sync"
printf 'nome=Trabalho\nendereco=x@exemplo.com\nsync_local=1\n' >"$XDG_CONFIG_HOME/tt/email/trab.conf"
agora=$(date +%s)
printf 'inbox\t%s\t%s\t1\ninbox\t%s\t%s\t1\ninbox\t%s\t%s\t1\n' $((agora-900)) $((agora-890)) $((agora-600)) $((agora-590)) $((agora-300)) $((agora-290)) >"$ES/email-sync/trab"
echo 'IMAP error: AUTHENTICATIONFAILED' >"$ES/email-sync/trab.erro"
l=$(grep '^email:trab' <<<"$("$TT" --checar --tsv)")
[[ $l == *$'\tfalha\t'*AUTHENTICATIONFAILED* || $l == *$'\taviso\t'* ]] || falhou "e-mail com erro não foi acusado: $l"
rm -rf "$XDG_CONFIG_HOME/tt/email" "$ES/email-sync"
passou 'e-mail: conta com espelho falhando aparece com a causa'

# INBOX em dia e a volta completa falhando sempre (pasta que sumiu do servidor e ficou no espelho): aviso com a causa
mkdir -p "$XDG_CONFIG_HOME/tt/email" "$ES/email-sync"
printf 'nome=Trabalho\nendereco=x@exemplo.com\nsync_local=1\n' >"$XDG_CONFIG_HOME/tt/email/trab.conf"
agora=$(date +%s)
printf 'completo\t%s\t%s\t1\ninbox\t%s\t%s\t0\ncompleto\t%s\t%s\t1\ninbox\t%s\t%s\t0\n' $((agora-1900)) $((agora-1880)) $((agora-1000)) $((agora-995)) \
  $((agora-100)) $((agora-80)) $((agora-20)) $((agora-15)) >"$ES/email-sync/trab"
echo 'Error: channel trab-pastas: far side box Velha cannot be opened anymore.' >"$ES/email-sync/trab.erro-completo"
l=$(grep '^email:trab' <<<"$("$TT" --checar --tsv)")
[[ $l == *$'\taviso\t'*'2 vezes'*'Velha cannot be opened'* ]] || falhou "volta completa falhando não foi acusada: $l"
printf 'completo\t%s\t%s\t0\n' $((agora-10)) $((agora-5)) >>"$ES/email-sync/trab"
l=$(grep '^email:trab' <<<"$("$TT" --checar --tsv)")
[[ $l == *$'\tok\t'* ]] || falhou "volta completa boa deveria voltar a ok: $l"
rm -rf "$XDG_CONFIG_HOME/tt/email" "$ES/email-sync"
passou 'e-mail: INBOX em dia com a volta completa falhando é aviso, com a causa'

# --- Agente ----------------------------------------------------------------------------------------------
cat >"$TT_DIR/NOVIDADES.md" <<'N'
# Novidades
## v1.14.0 · 01/01/2099
- coisa nova da checagem — com & no texto
## v1.13.1 · 01/01/2099
- coisa velha
N
echo "400 teste 2099-01-01 1.14.0" >"$TT_DIR/VERSAO"
"$TT" --checar-agente --de 1.13.1 >/dev/null || falhou 'checar-agente não lançou'
esperar_hist 1 || falhou 'a rodada do agente não fechou'
grep -q 'coisa nova da checagem — com & no texto' "$T/pedido" || falhou 'pedido sem o trecho novo do NOVIDADES.md (ou o & estragou)'
grep -q 'coisa velha' "$T/pedido" && falhou 'pedido trouxe novidade antiga'
grep -q 'Limites' "$T/pedido" && grep -q '✗ \*\*vigia\*\*' "$T/pedido" && grep -q 'Separação' "$T/pedido" || falhou 'pedido sem limites, coletor ou checagens'
grep -q '{{' "$T/pedido" && falhou "marcador sem substituir no pedido: $(grep -o '{{[A-Z]*}}' "$T/pedido" | sort -u)"
grep -qx -- '--dangerously-skip-permissions' "$T/args" || falhou 'agente não rodou com --dangerously-skip-permissions'
l=$(tail -1 "$CK/historico.log")
[[ $l == *$'\t1.13.1→1.14.0\tagente\tok=8 aviso=1 falha=0 corrigido=2\t'* ]] || falhou "linha do histórico: $l"
rod=$CK/$(cut -f6 <<<"$l")
[[ -s $rod/relatorio.md && -s $rod/coletor.tsv && -s $rod/prompt.md && -d $rod/backup ]] || falhou "pasta da rodada incompleta: $(ls "$rod")"
grep -l "checagem:${rod##*/}" "$ES"/notifs/* >/dev/null 2>&1 || falhou 'sem aviso no 🔔 com o relatório'
grep -q 'RESUMO' <<<"$("$TT" --checar-ver)" || falhou '--checar-ver não mostrou o último relatório'
passou 'agente: pedido completo, sem pedir permissão, rodada fechada com histórico, relatório e aviso'

touch "$T/sem-conta"; n=$(ls -d "$CK"/*/ | wc -l)
rc=0; "$TT" --checar-agente >/dev/null || rc=$?
((rc == 2)) && (($(ls -d "$CK"/*/ | wc -l) == n)) || falhou "sem conta livre: rc=$rc e não deveria criar rodada"
rm -f "$T/sem-conta"
rc=0; TT_IA_ROT=- "$TT" --checar-agente >/dev/null || rc=$?
((rc == 3)) || falhou "sem agente: rc=$rc"
grep -q 'Sem agente de IA' "$(ls -dt "$CK"/*/ | head -1)relatorio.md" || falhou 'sem agente: relatório do coletor não diz por quê'
passou 'sem conta livre não cria rodada; sem agente fecha só com o coletor'

# --- Gatilho do vigia --------------------------------------------------------------------------------------
rm -rf "$CK"; : >"$T/args"
"$TT" --checar-auto
[[ $(cat "$CK/versao-checada") == 1.14.0 ]] || falhou 'máquina recém-instalada deveria só marcar a versão'
[[ -s $T/args ]] && falhou 'máquina recém-instalada não deveria lançar o agente'
echo 1.13.1 >"$CK/versao-checada"
"$TT" --checar-auto; esperar_hist 1 || falhou 'versão nova não lançou a checagem'
[[ $(cat "$CK/versao-checada") == 1.14.0 ]] || falhou 'a marca não avançou'
"$TT" --checar-auto; sleep 0.5
(($(wc -l <"$CK/historico.log") == 1)) || falhou 'a mesma versão disparou de novo'
passou 'vigia: uma rodada por versão nova; instalação nova só marca'

echo 1.13.1 >"$CK/versao-checada"; echo checagem_auto=0 >>"$XDG_CONFIG_HOME/tt/config"
"$TT" --checar-auto
[[ $(cat "$CK/versao-checada") == 1.13.1 ]] || falhou 'checagem_auto=0 deveria desligar'
sed -i '/^checagem_auto=/d' "$XDG_CONFIG_HOME/tt/config"
touch "$T/sem-conta"
TT_CHECAGEM_REPETIR=0 "$TT" --checar-auto; TT_CHECAGEM_REPETIR=0 "$TT" --checar-auto
[[ $(cat "$CK/tentativas") == 2 && $(cat "$CK/versao-checada") == 1.13.1 ]] || falhou "sem conta: deveria contar tentativas ($(cat "$CK/tentativas" 2>/dev/null))"
TT_CHECAGEM_REPETIR=0 "$TT" --checar-auto
[[ $(cat "$CK/versao-checada") == 1.14.0 && ! -e $CK/tentativas ]] || falhou 'na 3ª tentativa sem conta deveria fechar a versão'
grep -q 'Nenhuma conta de IA ficou livre' "$(ls -dt "$CK"/*/ | head -1)relatorio.md" || falhou 'relatório sem conta não diz por quê'
rm -f "$T/sem-conta"
passou 'vigia: checagem_auto=0 desliga; sem conta tenta 3 vezes e fecha só com o coletor'

TT_CHECAGEM_MANTER=2 "$TT" --checar-agente --so-coletor >/dev/null
sleep 1; TT_CHECAGEM_MANTER=2 "$TT" --checar-agente --so-coletor >/dev/null
(($(ls -d "$CK"/*/ | wc -l) == 2)) || falhou "retenção: $(ls -d "$CK"/*/ | wc -l) rodadas"
passou 'retenção: só as últimas rodadas ficam'

# --- Handoff -------------------------------------------------------------------------------------------------
mkdir -p "$HOME/.secrets" "$HOME/.cache"
echo SEGREDO-DO-ARQUIVO >"$HOME/.secrets/aerc-trab.txt"
printf 'conta fulano@exemplo.com refresh_token=abc123SEGREDO\nsenha: hunter2xyz\nAuthorization: Bearer ey.SEGREDOJWT123\n' >>"$HOME/.cache/tt-vigia.log"
echo 'token ghp_ABCDEFGHIJKLMNOPQRST' >>"$(ls -dt "$CK"/*/ | head -1)relatorio.md"
"$TT" --checar-handoff "$T/h.tar.gz" >"$T/handoff.out" || falhou "handoff falhou: $(cat "$T/handoff.out")"
mkdir "$T/h"; tar -xzf "$T/h.tar.gz" -C "$T/h"
for s in SEGREDO-DO-ARQUIVO abc123SEGREDO hunter2xyz SEGREDOJWT123 ghp_ABCDEFGHIJKLMNOPQRST fulano@exemplo.com; do
  grep -rq -- "$s" "$T/h" && falhou "handoff vazou: $s"
done
grep -rq 'f\*\*\*@exemplo.com' "$T/h" || falhou 'e-mail deveria aparecer mascarado'
ls "$T"/h/*/LEIA-ME.md "$T"/h/*/checagens/historico.log "$T"/h/*/estado/checar.tsv "$T"/h/*/logs/tt-vigia.log >/dev/null || falhou "handoff incompleto: $(cd "$T/h" && find . -type f)"
find "$T/h" -path '*/backup*' | grep -q . && falhou 'handoff levou backup do perfil'
(($(wc -l <"$(ls "$T"/h/*/estado/plataforma.txt)") >= 2)) || falhou 'plataforma.txt: a plataforma e o kernel deveriam ficar em linhas separadas'
grep -q 'LEIA-ME.md' "$T/handoff.out" || falhou 'handoff não mostrou o conteúdo'
passou 'handoff: relatórios, estado e logs, sem segredo e com e-mail mascarado'

# --- Canais ------------------------------------------------------------------------------------------------
fn=$(TT_COMPLETO=1 bash -c 'TT_SO_CARREGAR=1 source "$1" >/dev/null 2>&1; declare -f menu_admin notif_abrir' _ "$TT_DIR/tt")
grep -q -- '--checar-agente' <<<"$fn" && grep -q -- '--checar-handoff' <<<"$fn" || falhou 'menu administrar sem os itens 🩺'
grep -q 'checagem:' <<<"$fn" || falhou 'aviso da checagem sem destino'
passou 'menu administrar → 🩺 e o clique no aviso abrem a checagem'
