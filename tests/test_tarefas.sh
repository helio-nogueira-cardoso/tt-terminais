#!/usr/bin/env bash
# Teste de regressão do gerenciador de tarefas (tt --tarefas) e da sincronização por tarefa.
# Isola HOME/XDG e usa um stub de tmux: nenhum arquivo ou socket real do usuário é tocado.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TT="$ROOT/tt"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

[[ -x "$TT" ]]
bash -n "$TT"

# Estrutura do código esperada (contrato interno).
grep -q '^CONF_TAREFAS=' "$TT"
grep -q '^tarefa_add()' "$TT"
grep -q '^tarefa_estado()' "$TT"
grep -q '^tarefas_merge()' "$TT"
grep -q '^receber_tarefas()' "$TT"
grep -q '^abrir_tarefas()' "$TT"
grep -q '^barra_tarefas_fmt()' "$TT"
grep -q 'range=user|tarefas' "$TT"

mkdir -p "$TEST_DIR/home" "$TEST_DIR/bin"
C="$TEST_DIR/home/.config/tt"; mkdir -p "$C"
printf 'nome=A\n' >"$C/config"

# Stub de tmux: list-sessions falha (fora do servidor) para forçar o modo texto da CLI;
# display-popup registra os argumentos no log, para checar a ancoragem do slide-over.
cat >"$TEST_DIR/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
case ${1:-} in
  list-sessions) exit 1 ;;
  display-popup) printf '%s\n' "$*" >>"$TT_TMUX_LOG"; exit 0 ;;
  display-message) printf '%s\n' clienteX ;;
  show-options|list-clients|set-option|set|refresh-client) exit 0 ;;
  *) exit 0 ;;
esac
TMUX
chmod +x "$TEST_DIR/bin/tmux"

tt() { env HOME="$TEST_DIR/home" XDG_CONFIG_HOME="$TEST_DIR/home/.config" \
  XDG_STATE_HOME="$TEST_DIR/home/.local/state" TT_MACHINE=A \
  TT_TMUX_LOG="$TEST_DIR/popup.log" PATH="$TEST_DIR/bin:$PATH" "$TT" "$@"; }

fail() { echo "FALHOU: $1" >&2; exit 1; }

# --- comportamento: add, listar, concluir, remover -------------------------
tt --tarefa-add "comprar cafe" >/dev/null
tt --tarefa-add "revisar PR" >/dev/null
[[ $(awk 'END{print NR}' "$C/tarefas") == 2 ]] || fail "add deveria gravar 2 tarefas"

id_cafe=$(awk -F'\t' '$5=="comprar cafe"{print $1}' "$C/tarefas")
id_pr=$(awk -F'\t' '$5=="revisar PR"{print $1}' "$C/tarefas")
[[ $id_cafe =~ ^[0-9a-f]{12}$ ]] || fail "id da tarefa deveria ser 12 hex"

tt --tarefa-ok "$id_cafe"
grep -q "^$id_cafe	feita	" "$C/tarefas" || fail "tarefa-ok deveria marcar feita"

# barra conta só abertas (1 restante)
tt --tarefas-barra | grep -Fq '📋 1' || fail "barra deveria mostrar 1 aberta"

# remover vira lápide 'removida' (não some do arquivo imediatamente, mas some das vivas)
tt --tarefa-rm "$id_pr"
grep -q "^$id_pr	removida	" "$C/tarefas" || fail "tarefa-rm deveria virar lapide removida"
tt --tarefas 2>/dev/null | grep -Fq 'revisar PR' && fail "tarefa removida nao pode aparecer na lista"

# limpar feitas: a feita (cafe) vira removida
tt --tarefa-limpar
grep -q "^$id_cafe	removida	" "$C/tarefas" || fail "tarefa-limpar deveria remover as feitas"

echo "ok: add, concluir, remover e limpar"

# --- merge por tarefa: mais nova vence, removida vence, nova entra ---------
printf 'aaaaaaaaaaaa\taberta\t50\t100\tum\nbbbbbbbbbbbb\tfeita\t50\t100\tdois\n' >"$C/tarefas"
printf 'aaaaaaaaaaaa\tfeita\t50\t200\tum\nbbbbbbbbbbbb\tremovida\t50\t300\tdois\ncccccccccccc\taberta\t60\t150\ttres\n' | tt --receber-tarefas
grep -q '^aaaaaaaaaaaa	feita	50	200	' "$C/tarefas" || fail "merge: mudanca mais nova (feita) deveria vencer"
grep -q '^bbbbbbbbbbbb	removida	50	300	' "$C/tarefas" || fail "merge: remocao mais nova deveria vencer"
grep -q '^cccccccccccc	aberta	60	150	' "$C/tarefas" || fail "merge: tarefa nova deveria entrar"
tt --tarefas-barra | grep -Fq '📋 1' || fail "merge: deveria restar 1 aberta (tres)"

# empate de 'mudada': removida ganha de feita (nao ressuscita)
printf 'dddddddddddd\tfeita\t50\t500\tx\n' >"$C/tarefas"
printf 'dddddddddddd\tremovida\t50\t500\tx\n' | tt --receber-tarefas
grep -q '^dddddddddddd	removida	' "$C/tarefas" || fail "merge: empate deve favorecer removida"

echo "ok: merge por tarefa (recencia e precedencia de remocao)"

# --- slide-over ancorado a direita (display-popup -x = largura - w) --------
# Stub com client_width conhecido para checar o calculo de x. do_cliente usa list-clients -F.
cat >"$TEST_DIR/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
case ${1:-} in
  display-popup) printf '%s\n' "$*" >>"$TT_TMUX_LOG"; exit 0 ;;
  list-sessions) exit 0 ;;
  list-clients)
    # -F "#{client_name}\t<formato>"; abrir_tarefas pede client_width/height
    printf 'clienteX\t120 40\n' ;;
  display-message) printf '%s\n' clienteX ;;
  *) exit 0 ;;
esac
TMUX
chmod +x "$TEST_DIR/bin/tmux"
: >"$TEST_DIR/popup.log"
tt --tarefas clienteX
# largura 64, cliente 120 => x = 56; altura 100%; borda arredondada
grep -Fq -- '-x 56' "$TEST_DIR/popup.log" || fail "slide-over deveria ancorar a direita (x = largura - 64)"
grep -Fq -- '-h 100%' "$TEST_DIR/popup.log" || fail "slide-over deveria ocupar a altura toda"
grep -Fq -- '-b rounded' "$TEST_DIR/popup.log" || fail "slide-over deveria ter borda arredondada"
grep -Fq -- '--tarefas-ui' "$TEST_DIR/popup.log" || fail "slide-over deveria rodar a UI de tarefas"
grep -Fq '📋 tarefas' "$TEST_DIR/popup.log" || fail "slide-over deveria mostrar o titulo com como fechar"

# tela estreita (celular): ocupa a largura toda, ancorada em x=0
cat >"$TEST_DIR/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
case ${1:-} in
  display-popup) printf '%s\n' "$*" >>"$TT_TMUX_LOG"; exit 0 ;;
  list-sessions) exit 0 ;;
  list-clients) printf 'c\t60 30\n' ;;
  display-message) printf '%s\n' c ;;
  *) exit 0 ;;
esac
TMUX
chmod +x "$TEST_DIR/bin/tmux"
: >"$TEST_DIR/popup.log"
tt --tarefas c
grep -Fq -- '-x 0' "$TEST_DIR/popup.log" || fail "em tela estreita o painel deveria ancorar em x=0"
grep -Fq -- '-w 60' "$TEST_DIR/popup.log" || fail "em tela estreita o painel deveria ocupar a largura toda"

echo "ok: slide-over ancorado a direita (e largura total no celular)"

# --- sincronizacao configuravel --------------------------------------------
grep -q '^tarefas_sync_modo()' "$TT"
grep -q '^propagar_tarefas()' "$TT"
grep -q '^empurrar_tarefas_git()' "$TT"
grep -q '^puxar_tarefas_git()' "$TT"
grep -q 'tarefas_repo' "$TT"
# modo off nao propaga (sem efeito externo quando desligado)
printf 'nome=A\ntarefas_sync=off\n' >"$C/config"
tt --tarefas-espelhar  # nao deve falhar nem tentar ssh
echo "ok: sincronizacao configuravel (p2p/git/ambos/off) presente"

echo "TODOS OS TESTES DE TAREFAS PASSARAM"
