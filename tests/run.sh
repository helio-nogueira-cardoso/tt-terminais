#!/usr/bin/env bash
# Testes de regressão do tt. Uso:
#   tests/run.sh                         # fonte deste clone
#   TT_DIR=~/.local/share/tt tests/run.sh # instalação ativa
set -euo pipefail

raiz=${TT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}
tt=$raiz/tt
conf=$raiz/tmux.conf
tema=$raiz/tema-tmux.conf
falhas=0

ok() { printf 'ok — %s\n' "$1"; }
falha() { printf 'FALHOU — %s\n' "$1" >&2; falhas=$((falhas + 1)); }
exige() { command -v "$1" >/dev/null || { printf 'falta dependência de teste: %s\n' "$1" >&2; exit 2; }; }
tem() { rg -q -- "$2" "$1"; }

suite_dir=$(cd "$(dirname "$0")" && pwd)
if [[ -x $suite_dir/test_fixadas.sh ]]; then
  "$suite_dir/test_fixadas.sh"
fi
if [[ -x $suite_dir/test_fixadas_tmux.sh ]]; then
  "$suite_dir/test_fixadas_tmux.sh"
fi
if [[ -x $suite_dir/test_ponte_cliente.sh ]]; then
  "$suite_dir/test_ponte_cliente.sh"
fi
if [[ -x $suite_dir/test_instalar_repo.sh ]]; then
  "$suite_dir/test_instalar_repo.sh"
fi

for cmd in bash python3 rg tmux; do exige "$cmd"; done
[[ -x $tt ]] || { printf 'tt não executável: %s\n' "$tt" >&2; exit 2; }
[[ -f $conf ]] || { printf 'tmux.conf não encontrado: %s\n' "$conf" >&2; exit 2; }
[[ -f $tema ]] || { printf 'tema-tmux.conf não encontrado: %s\n' "$tema" >&2; exit 2; }

if bash -n "$tt"; then ok 'sintaxe Bash'; else falha 'sintaxe Bash'; fi

awk '/^  codigo=\$\(cat <<'\''PYEOF'\''/{captura=1; next} captura && /^PYEOF$/{exit} captura {print}' "$tt" |
  python3 -c 'import sys; compile(sys.stdin.read(), "com_mouse", "exec")'
ok 'sintaxe Python da ponte de mouse'

tem "$tt" ': >"\$arq"' &&
  tem "$tt" "pendente = b''" &&
  tem "$tt" "\\(\[Mm\]\)" &&
  tem "$tt" 'dados = pendente \+ d' &&
  tem "$tt" 'resto\.rfind' && ok 'ponte de mouse: estado e pacotes fragmentados' ||
  falha 'ponte de mouse não protege contra coordenada velha/pacote fragmentado'

tem "$tt" 't_atualizacao=\$\{TT_T_ATUALIZACAO:-300\}' &&
  tem "$tt" -- '--garantir-atualizacao' &&
  tem "$tt" 'REPO_TT=\$DIR_FONTE' &&
  tem "$tt" '\(\(n > atual\)\)' && ok 'vigia exige a versão publicada mais nova' ||
  falha 'vigia não garante atualização publicada'

tem "$tt" '^versao_barra\(\)' &&
  tem "$tema" '@barra_versao' && ok 'versão exibida na faixa de fixadas' ||
  falha 'versão não foi ligada à faixa de fixadas'

tem "$tt" 'tmux set -g status 2' &&
  tem "$tt" 'printf.*📌' && ok 'faixa de fixadas permanece visível vazia' ||
  falha 'faixa de fixadas desaparece quando vazia'

tem "$tt" 'atalhos-padrao-s23' &&
  tem "$raiz/atalhos-padrao-s23" 'claude --dangerously-skip-permissions' &&
  tem "$raiz/atalhos-padrao-s23" 'codex --yolo' && ok 'perfil s23 abre Claude e Codex novos com permissões reforçadas' ||
  falha 'perfil s23 não reforça atalhos novos de Claude/Codex'

tem "$tt" 'c\[3:4\] == \["oculta"\]' &&
  tem "$tt" '^ocultar_maquina\(\)' &&
  tem "$tt" '^mostrar_maquina\(\)' && ok 'ocultar/mostrar preserva máquinas cadastradas' ||
  falha 'ocultar/mostrar máquinas não está completo'

for evento in Status StatusLeft StatusRight; do
  if rg -q "MouseDown1$evento run-shell.*--clique" "$conf" &&
     rg -q "MouseUp1$evento" "$conf"; then
    ok "fixadas em MouseDown/MouseUp$evento"
  else
    falha "fixadas sem proteção completa em $evento"
  fi
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/tt-test.XXXXXX")
sock=$tmp/tmux.sock
limpar() { tmux -S "$sock" kill-server >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap limpar EXIT

# Fluxo de administração de máquinas em isolamento completo. TT_RT existe para que nenhum cache
# da sessão do usuário seja lido ou removido; o teste exercita os mesmos comandos CLI dos popups.
caso=$tmp/maquinas
mkdir -p "$caso/home" "$caso/config/tt" "$caso/runtime"
printf 'node.example  alice  remoto\n' >"$caso/config/tt/maquinas"
tt_isolado() {
  HOME="$caso/home" XDG_CONFIG_HOME="$caso/config" TT_RT="$caso/runtime" TMPDIR="$caso" "$tt" "$@"
}
saida=$(tt_isolado --maquinas) || { falha 'listar máquina isolada'; saida=''; }
[[ $saida == 'alice@node.example remoto' ]] && ok 'CLI: máquina cadastrada aparece no seletor' ||
  falha 'CLI: máquina cadastrada não apareceu como esperado'
tt_isolado --ocultar-maquina remoto >/dev/null || falha 'CLI: ocultar máquina'
grep -qx 'node.example  alice  remoto  oculta' "$caso/config/tt/maquinas" && ok 'CLI: ocultar preserva host, usuário e rótulo' ||
  falha 'CLI: ocultar perdeu configuração'
saida=$(tt_isolado --maquinas) || { falha 'listar após ocultar'; saida=''; }
[[ -z $saida ]] && ok 'CLI: máquina ocultada sai dos canais de listagem' ||
  falha 'CLI: máquina ocultada ainda aparece'
tt_isolado --mostrar-maquina remoto >/dev/null || falha 'CLI: mostrar máquina'
grep -qx 'node.example  alice  remoto' "$caso/config/tt/maquinas" && ok 'CLI: mostrar restaura a configuração original' ||
  falha 'CLI: mostrar não restaurou configuração'
saida=$(tt_isolado --maquinas) || { falha 'listar após mostrar'; saida=''; }
[[ $saida == 'alice@node.example remoto' ]] && ok 'CLI: máquina mostrada volta ao seletor' ||
  falha 'CLI: máquina mostrada não voltou ao seletor'

# O formato antigo "host -" não tinha usuário. Ao restaurá-lo, o tt pede somente essa informação
# ausente e passa a gravar o formato moderno, preservando o rótulo.
printf 'legacy.example  -  legado\n' >"$caso/config/tt/maquinas"
printf 'carol\n' | tt_isolado --mostrar-maquina legado >/dev/null || falha 'CLI: mostrar formato antigo'
grep -qx 'legacy.example  carol  legado' "$caso/config/tt/maquinas" && ok 'CLI: formato antigo é recuperável' ||
  falha 'CLI: formato antigo não foi recuperado'

# Cada range desenhado pela barra deve chegar a uma rota explícita em clique(). Isto é o contrato
# comum para mouse, toque e os ranges que o tmux classifica de forma diferente por terminal.
for rota in maquina sessao fixar ajustar tt painel arquivos transferencias copias 'at[0-9]*' 'fx*' 'fxx*'; do
  rg -Fq "$rota)" "$tt" || falha "rota de interação ausente: $rota"
done
((falhas == 0)) && ok 'contrato: todos os controles da barra têm rota de ação' || true

# Especificação executável da captura SGR: o pressionar esquerdo é registrado, soltura/arrasto não,
# e a mesma sequência continua correta quando chega em pedaços pelo pty.
python3 - <<'PY'
import re
padrao = re.compile(rb'\x1b\[<(\d+);(\d+);(\d+)([Mm])')
pendente = b''; coordenada = None
for bloco in (b'abc\x1b[<0;12;', b'7M\x1b[<0;12;7m', b'\x1b[<32;13;7M'):
    dados = pendente + bloco; fim = 0
    for m in padrao.finditer(dados):
        fim = m.end(); botao = int(m.group(1))
        if m.group(4) == b'M' and botao & 3 == 0 and not botao & 32:
            coordenada = (int(m.group(2)), int(m.group(3)))
    resto = dados[fim:]; inicio = resto.rfind(b'\x1b[<')
    pendente = resto[inicio:] if inicio >= 0 else b''
assert coordenada == (12, 7), coordenada
PY
ok 'mouse SGR: pressão, soltura, arrasto e pacote fragmentado'

tmux -S "$sock" -f "$conf" new-session -d -s tt-test 'sleep 5'
tmux -S "$sock" list-keys -T root >"$tmp/keys"
tmux -S "$sock" list-keys -T prefix >"$tmp/prefix-keys"
for evento in MouseDown1Status MouseDown1StatusLeft MouseDown1StatusRight MouseUp1Status MouseUp1StatusLeft MouseUp1StatusRight; do
  rg -q " $evento " "$tmp/keys" || falha "binding tmux ausente: $evento"
done
for evento in MouseDrag1Pane DoubleClick1Pane TripleClick1Pane MouseDown2Pane MouseUp2Pane MouseUp3Pane MouseDown3Pane MouseUp3Status MouseDown3Status MouseDown3Border; do
  rg -q " $evento " "$tmp/keys" || falha "gesto de painel/status ausente: $evento"
done
for tecla in F1 F2 F3 F4 F5 F6 F7 F8 F9 F10; do
  rg -q " $tecla " "$tmp/prefix-keys" || falha "atalho de teclado ausente: $tecla"
done
for esperado in 'F1 cl' 'F2 clc' 'F3 clr' 'F4 dbn' 'F5 tela' 'F6 sair' 'F7 ant' 'F8 dv' 'F9 zm' 'F10 jn'; do
  read -r tecla botao <<<"$esperado"
  rg -q -- " $tecla .*--botao $botao " "$tmp/prefix-keys" ||
    falha "atalho $tecla não alcança o botão esperado: $botao"
done
((falhas == 0)) && ok 'teclas F1–F10 alcançam todos os botões do tt' || true
rg -q 'MouseUp3Status.*--clique-direito' "$conf" && rg -q 'MouseUp3Pane.*--menu-painel' "$conf" && ok 'botão direito alcança menus de status e painel' ||
  falha 'botão direito não tem rota completa'
rg -q 'align=right.*@barra_versao' "$tema" && rg -q 'range=user\|fixar' "$tema" && ok 'tema expõe pino e versão nos dois cantos da barra' ||
  falha 'tema não expõe controles esperados da barra'
((falhas == 0)) && ok 'configuração tmux isolada' || true

((falhas == 0)) || exit 1
printf 'Todos os testes passaram (%s).\n' "$raiz"
