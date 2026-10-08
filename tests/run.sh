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
# Testes de comportamento: cada tests/test_*.sh roda isolado (HOME, tmux e pacote temporários).
for t in "$suite_dir"/test_*.sh; do
  if "$t"; then :; else falha "$(basename "$t")"; fi
done

for cmd in bash python3 rg tmux; do exige "$cmd"; done
[[ -x $tt ]] || { printf 'tt não executável: %s\n' "$tt" >&2; exit 2; }
[[ -f $conf ]] || { printf 'tmux.conf não encontrado: %s\n' "$conf" >&2; exit 2; }
[[ -f $tema ]] || { printf 'tema-tmux.conf não encontrado: %s\n' "$tema" >&2; exit 2; }

if bash -n "$tt"; then ok 'sintaxe Bash'; else falha 'sintaxe Bash'; fi

# tt --help mostra os verbos; uma opção desconhecida é recusada (antes abria a central em silêncio).
# (saída capturada antes do rg: com pipefail, o `rg -q` fecha o cano e o sed do --help morre com SIGPIPE)
ajuda_saida=$("$tt" --help 2>/dev/null || true)
rg -q -- 'tt --vigia' <<<"$ajuda_saida" && ok 'tt --help lista os verbos' || falha 'tt --help não lista os verbos'
rc=0; "$tt" --opcao-que-nao-existe >/dev/null 2>&1 || rc=$?
[[ $rc == 2 ]] && ok 'opção desconhecida é recusada com erro' || falha "opção desconhecida não foi recusada (rc=$rc)"

awk '/^  codigo=\$\(cat <<'\''PYEOF'\''/{captura=1; next} captura && /^PYEOF$/{exit} captura {print}' "$tt" |
  python3 -c 'import sys; compile(sys.stdin.read(), "com_mouse", "exec")'
ok 'sintaxe Python da ponte de mouse'

tem "$tt" ': >"\$arq"' &&
  tem "$tt" "pendente = b''" &&
  tem "$tt" "\\(\[Mm\]\)" &&
  tem "$tt" 'dados = pendente \+ d' &&
  tem "$tt" 'resto\.rfind' && ok 'ponte de mouse: estado e pacotes fragmentados' ||
  falha 'ponte de mouse não protege contra coordenada velha/pacote fragmentado'

tem "$tt" 't_atualizacao=\$\{TT_T_ATUALIZACAO:-1800\}' &&
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

# O perfil do celular (atalhos-padrao-mobile) é verificado por comportamento em test_atalhos.sh.
tem "$tt" 'atalhos-padrao-mobile' &&
  [[ -f $raiz/atalhos-padrao-mobile ]] && ok 'perfil mobile empacotado e usado pelo tt' ||
  falha 'perfil mobile ausente do pacote ou do tt'

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
base=$falhas
for rota in maquina sessao fixar ajustar tt painel arquivos email transferencias copias 'at[0-9]*' 'fx*' 'fxx*' fixprev fixnext tarefas relogio; do
  rg -Fq "$rota)" "$tt" || falha "rota de interação ausente: $rota"
done
((falhas == base)) && ok 'contrato: todos os controles da barra têm rota de ação' || true

# Botão de e-mail (📧): range no tema entre arquivos e relógio, rota de clique, case de botão,
# verbo de teclado/CLI --email, cliente configurável (default aerc) e aviso quando ausente.
base=$falhas
rg -q 'range=user\|email' "$tema" || falha 'e-mail: range ausente no tema'
rg -Fq 'email) botao_email' "$tt" || falha 'e-mail: case de botão ausente'
rg -Fq -- '--email)' "$tt" || falha 'e-mail: verbo --email ausente'
rg -q '^email_comando\(\)' "$tt" && rg -q 'c=\$\{c:-aerc\}' "$tt" || falha 'e-mail: email_comando com default aerc ausente'
rg -q '^botao_email\(\)' "$tt" || falha 'e-mail: botao_email ausente'
# Abstração em subjanela: botao_email abre num display-popup (como a central), não cria sessão.
corpo_email=$(sed -n '/^botao_email()/,/^}/p' "$tt")
grep -Fq 'display-popup' <<<"$corpo_email" || falha 'e-mail: botao_email deve abrir em subjanela (display-popup)'
grep -Fq 'new-session' <<<"$corpo_email" && falha 'e-mail: botao_email não deve criar sessão tmux (é popup)'
# Dica de fechar no título do popup: display-popup não tem X clicável, o título instrui a saída.
grep -Eq -- '-T " 📧 e-mail · ' <<<"$corpo_email" || falha 'e-mail: título do popup deve mostrar como fechar'
grep -Fq 'q fecha' <<<"$corpo_email" || falha 'e-mail: dica de saída do aerc (q fecha) ausente no título'
# aerc em tela cheia e sem borda: nada da tela de baixo vaza para o quadro, e não há borda para arrastar.
grep -Fq -- "-b rounded" <<<"$corpo_email" || falha 'e-mail: subjanela deve ter borda arredondada'
rg -q '@tt_papel email' "$tt" && falha 'e-mail: não deve mais marcar papel de sessão email — é popup'
# O 📧 vem depois do ⇅ arquivos e antes do relógio %H:%M (ordem pedida na barra).
pos_arq=$(rg -n 'range=user\|arquivos' "$tema" | head -1 | cut -d: -f1)
pos_eml=$(rg -n 'range=user\|email' "$tema" | head -1 | cut -d: -f1)
pos_rel=$(rg -n '%H:%M' "$tema" | head -1 | cut -d: -f1)
[[ -n $pos_arq && -n $pos_eml && -n $pos_rel && $pos_arq -lt $pos_eml && $pos_eml -lt $pos_rel ]] ||
  falha 'e-mail: 📧 não está entre arquivos e relógio na barra'
((falhas == base)) && ok 'botão de e-mail: barra, rota, botão, verbo e posição' || true

# Botão de tarefas (📋): range na 2ª linha da barra (ao lado da versão), rota de clique (esquerdo
# abre o slide-over, direito abre o menu), verbos de CLI, atalho de teclado e sincronização.
base=$falhas
rg -q 'range=user\|tarefas' "$tt" || falha 'tarefas: range do botão ausente (barra_tarefas_fmt no tt)'
rg -q '@barra_tarefas' "$tema" || falha 'tarefas: @barra_tarefas ausente no status-format[1]'
rg -Fq 'tarefas) abrir_tarefas' "$tt" || falha 'tarefas: clique esquerdo não abre o painel'
rg -Fq 'tarefas) menu_tarefas' "$tt" || falha 'tarefas: clique direito não abre o menu'
rg -Fq -- '--tarefas)' "$tt" || falha 'tarefas: verbo --tarefas ausente'
rg -Fq -- '--tarefa-add)' "$tt" || falha 'tarefas: verbo --tarefa-add ausente'
rg -Fq -- '--tarefa-ok)' "$tt" || falha 'tarefas: verbo --tarefa-ok ausente'
rg -Fq -- '--tarefa-rm)' "$tt" || falha 'tarefas: verbo --tarefa-rm ausente'
rg -Fq -- '--receber-tarefas)' "$tt" || falha 'tarefas: verbo --receber-tarefas (sync P2P) ausente'
rg -q 'bind t run-shell.*--clique tarefas' "$conf" || falha 'tarefas: atalho de teclado (bind t) ausente ou com rota diferente do botão'
# O slide-over abre em subjanela (display-popup), ancorado à direita (-x), NÃO cria sessão.
corpo_abrir=$(sed -n '/^abrir_tarefas()/,/^}/p' "$tt")
grep -Fq 'display-popup' <<<"$corpo_abrir" || falha 'tarefas: abrir_tarefas deve usar display-popup (subjanela)'
grep -Fq -- '-x ' <<<"$corpo_abrir" || falha 'tarefas: slide-over deve ancorar com -x (lateral)'
grep -Fq 'new-session' <<<"$corpo_abrir" && falha 'tarefas: abrir_tarefas não deve criar sessão (é popup)'
# Merge por tarefa e sync configurável: o contrato que faz P2P e git interoperarem sem perder.
rg -q '^tarefas_merge\(\)' "$tt" || falha 'tarefas: tarefas_merge (merge por tarefa) ausente'
rg -q '^tarefas_sync_modo\(\)' "$tt" || falha 'tarefas: modo de sync configurável ausente'
rg -q 'tarefas_repo' "$tt" || falha 'tarefas: repositório git pessoal (tarefas_repo) ausente'
rg -Fq -- '--tarefas-puxar' "$tt" || falha 'tarefas: vigia não puxa tarefas (--tarefas-puxar ausente)'
rg -Fq -- '--tarefas-lembrete' "$tt" || falha 'tarefas: lembrete de prazo (--tarefas-lembrete) ausente'
# A versão continua no canto direito; o 📋 vem antes dela na 2ª linha.
pos_tar=$(rg -n '@barra_tarefas' "$tema" | head -1 | cut -d: -f1)
pos_ver=$(rg -n '@barra_versao' "$tema" | head -1 | cut -d: -f1)
[[ -n $pos_tar && -n $pos_ver && $pos_tar -le $pos_ver ]] || falha 'tarefas: 📋 deveria vir antes da versão na 2ª linha'
((falhas == base)) && ok 'botão de tarefas: barra, rotas, verbos, atalho, slide-over e sync' || true

# Tarefas ricas: wrap do texto no painel, descrição/prazo/subtarefas e o calendário no relógio.
# O comportamento completo está em tests/test_tarefas_rico.sh; aqui o contrato estrutural.
base=$falhas
grep -Fq -- '--wrap' <<<"$(sed -n '/^tarefas_ui()/,/^}/p' "$tt")" || falha 'tarefas: fzf do painel sem --wrap (texto corta em vez de quebrar)'
rg -q '^tarefas_meta_get\(\)' "$tt" || falha 'tarefas: meta (6º campo) ausente'
rg -q '^tarefa_set_desc\(\)' "$tt" || falha 'tarefas: descrição editável ausente'
rg -q '^tarefa_add_sub\(\)' "$tt" || falha 'tarefas: subtarefas ausentes'
rg -q '^tarefa_add_natural\(\)' "$tt" || falha 'tarefas: captura por sintaxe natural ausente'
rg -q '^tarefa_sub_mover\(\)' "$tt" || falha 'tarefas: reordenação de subtarefa ausente'
rg -q '^tarefas_filtro_ciclar\(\)' "$tt" || falha 'tarefas: filtro (abertas/feitas/prazo/todas) ausente'
rg -q '^calendario_tui\(\)' "$tt" || falha 'tarefas: calendário interativo ausente'
for v in --tarefa-sub-prompt --tarefa-desc-prompt --tarefa-prazo-prompt --tarefa-sub-mover --tarefa-mover --tarefa-prio-ciclar --tarefa-rep-ciclar --tarefa-filtro-ciclar --tarefa-expandir --tarefa-preview --calendario --tarefas-cabecalho --tarefa-cabecalho-clique; do
  rg -Fq -- "$v)" "$tt" || falha "tarefas: verbo $v ausente"
done
# o 6º campo não quebra o merge: ainda chaveado por id, com NF>=5
rg -q 'NF >= 5' "$tt" || falha 'tarefas: merge perdeu a tolerância NF>=5 (quebraria linhas com meta)'
# clique no relógio abre o calendário num popup largo o bastante (dica nao vaza)
rg -Fq 'relogio) tmux display-popup' "$tt" || falha 'tarefas: clique no relógio não abre o calendário'
rg -q 'relogio\) tmux display-popup -c "\$2" -w (5[6-9]|[6-9][0-9])' "$tt" || falha 'calendário: popup do relógio estreito demais (<56)'
rg -q 'range=user\|relogio' "$tema" || falha 'tarefas: relógio sem range clicável no tema'
# painel mais clicável e com abas de filtro: left-click alterna, double-click expande, click-header troca filtro
corpo_ui=$(sed -n '/^tarefas_ui()/,/^}/p' "$tt")
# toda tecla, clique e botão passa pelo mesmo despachante (tarefa_acao): mesma ação por qualquer canal
for ev in left-click double-click right-click click-header enter space esc ctrl-n ctrl-x tab; do
  grep -Fq -- "$ev:transform(\$a " <<<"$corpo_ui" || falha "tarefas: $ev não passa pelo despachante tarefa_acao"
done
grep -Fq -- "--bind=\"q:" <<<"$corpo_ui" && falha 'tarefas: q não pode fechar o painel (impede digitar tarefas com q)'
grep -Fq -- '--id-nth' <<<"$corpo_ui" && falha 'tarefas: --id-nth faz o fzf perder o 2º clique durante a recarga'
rg -q '^tarefas_cabecalho\(\)' "$tt" || falha 'tarefas: cabeçalho com abas de filtro ausente'
((falhas == base)) && ok 'tarefas ricas: wrap, descrição, prazo, subtarefas, filtro e calendário' || true

# Gerência de contas de e-mail (cadastro guiado): funções, verbos e item de menu existem; o
# wizard grava a conta e a senha de app FORA do accounts.conf (só o cred-cmd fica lá).
base=$falhas
rg -q '^email_conta_nova_ui\(\)' "$tt" || falha 'e-mail/contas: email_conta_nova_ui ausente'
rg -q '^email_contas_ui\(\)' "$tt" || falha 'e-mail/contas: email_contas_ui ausente'
rg -q '^botao_email_contas\(\)' "$tt" || falha 'e-mail/contas: botao_email_contas ausente'
rg -Fq -- '--email-contas-ui)' "$tt" || falha 'e-mail/contas: verbo --email-contas-ui ausente'
rg -Fq -- '--email-conta-nova-ui)' "$tt" || falha 'e-mail/contas: verbo --email-conta-nova-ui ausente'
rg -Fq -- '--email-contas|--email-conta)' "$tt" || falha 'e-mail/contas: verbo --email-contas ausente'
rg -Fq 'Contas de e-mail' "$tt" || falha 'e-mail/contas: item de menu administrar ausente'
# Senha nunca é ecoada: a leitura usa read -s.
# (a senha é pedida em email_pedir_segredo, chamada pelo assistente e pela edição)
corpo_nova=$(sed -n '/^email_conta_nova_ui()/,/^}/p' "$tt")
corpo_seg=$(sed -n '/^email_pedir_segredo()/,/^}/p' "$tt")
grep -q 'email_pedir_segredo' <<<"$corpo_nova" || falha 'e-mail/contas: assistente não pede o segredo por email_pedir_segredo'
grep -Eq "read -r -s -p 'Senha" <<<"$corpo_seg" || falha 'e-mail/contas: senha deve ser lida com read -s (sem eco)'
# Teste funcional em HOME isolado: cadastra uma conta e confirma que a senha vai para ~/.secrets
# (600) e não para o accounts.conf. aerc é simulado via PATH; valores são fictícios.
tmphome=$(mktemp -d)
printf '#!/bin/sh\nexit 0\n' > "$tmphome/aerc"; chmod +x "$tmphome/aerc"
printf 'gmail\nx@gmail.com\nContaTeste\nsenha\nSENHA_FICTICIA_TESTE\nSENHA_FICTICIA_TESTE\n\n' |
  env HOME="$tmphome" PATH="$tmphome:$PATH" EU="$tmphome/tt" TT_EMAIL_SEM_REDE=1 bash "$tt" --email-conta-nova-ui >/dev/null 2>&1
# nota: EU aponta para um tt inexistente de propósito; a função nova_ui não reinvoca o tt.
conta="$tmphome/.config/aerc/accounts.conf"; cred="$tmphome/.secrets/aerc-contateste.txt"
rg -Fq '[ContaTeste]' "$conta" 2>/dev/null || falha 'e-mail/contas: bloco [ContaTeste] não foi gravado'
rg -Fq 'x%40gmail.com' "$conta" 2>/dev/null || falha 'e-mail/contas: userinfo deveria ter @ como %40'
rg -Fq 'SENHA_FICTICIA_TESTE' "$conta" 2>/dev/null && falha 'e-mail/contas: SENHA VAZOU para accounts.conf'
[[ -f $cred && $(cat "$cred") == SENHA_FICTICIA_TESTE ]] || falha 'e-mail/contas: senha não foi gravada no arquivo de credencial'
perm=$(stat -c '%a' "$cred" 2>/dev/null || stat -f '%Lp' "$cred" 2>/dev/null)
[[ $perm == 600 ]] || falha "e-mail/contas: credencial deveria ser 600 (é $perm)"
rm -rf "$tmphome"
((falhas == base)) && ok 'contas de e-mail: cadastro guiado grava conta sem vazar senha' || true

# Regressão (bug do slug): dois nomes distintos que geram o MESMO slug não podem compartilhar
# o arquivo de credencial. "Pessoal" e "pessoal!" => slug "pessoal". A 2ª deve ser RECUSADA e a
# senha da 1ª NÃO pode ser sobrescrita. Também cobre a recusa de [ ] no nome.
base=$falhas
tmphome=$(mktemp -d)
printf '#!/bin/sh\nexit 0\n' > "$tmphome/aerc"; chmod +x "$tmphome/aerc"
printf 'gmail\np1@gmail.com\nPessoal\nsenha\nSENHA_UM\nSENHA_UM\n\n' |
  env HOME="$tmphome" PATH="$tmphome:$PATH" EU="$tmphome/tt" TT_EMAIL_SEM_REDE=1 bash "$tt" --email-conta-nova-ui >/dev/null 2>&1
printf 'gmail\np2@gmail.com\npessoal!\nsenha\nSENHA_DOIS\nSENHA_DOIS\n\n' |
  env HOME="$tmphome" PATH="$tmphome:$PATH" EU="$tmphome/tt" TT_EMAIL_SEM_REDE=1 bash "$tt" --email-conta-nova-ui >/dev/null 2>&1
conta="$tmphome/.config/aerc/accounts.conf"; cred="$tmphome/.secrets/aerc-pessoal.txt"
[[ -f $cred && $(cat "$cred") == SENHA_UM ]] || falha 'e-mail/contas: colisão de slug sobrescreveu a senha da 1ª conta'
[[ $(grep -c '^\[pessoal!\]$' "$conta" 2>/dev/null) == 0 ]] || falha 'e-mail/contas: 2ª conta com slug colidente foi cadastrada mesmo assim'
# nome com colchete deve ser recusado (cabeçalho [Nome] quebraria)
printf 'gmail\nt@gmail.com\nTra[balho]\nsenha\nSENHA_T\nSENHA_T\n\n' |
  env HOME="$tmphome" PATH="$tmphome:$PATH" EU="$tmphome/tt" TT_EMAIL_SEM_REDE=1 bash "$tt" --email-conta-nova-ui >/dev/null 2>&1
[[ $(grep -c '^\[Tra\[balho\]\]$' "$conta" 2>/dev/null) == 0 ]] || falha 'e-mail/contas: nome com [ ] não foi recusado'
rm -rf "$tmphome"
((falhas == base)) && ok 'contas de e-mail: slug colidente e nome com [ ] são recusados (sem sobrescrever credencial)' || true

# Provisionamento do aerc (incremento mouse + saída rápida), garantido pelo tt em toda máquina.
base=$falhas
rg -q '^configurar_aerc\(\)' "$tt" || falha 'aerc: configurar_aerc ausente'
rg -q '^remover_aerc\(\)' "$tt" || falha 'aerc: remover_aerc ausente'
rg -Fq $'  configurar_aerc' "$tt" || falha 'aerc: configurar_aerc não é chamado na instalação'
rg -Fq $'  remover_aerc' "$tt" || falha 'aerc: remover_aerc não é chamado na desinstalação'
# NUNCA toca accounts.conf: a função não deve referenciar accounts.conf.
corpo_aerc=$(sed -n '/^configurar_aerc()/,/^}/p' "$tt")
grep -Fq 'accounts.conf' <<<"$corpo_aerc" && falha 'aerc: configurar_aerc não pode tocar accounts.conf'
# Teste funcional em HOME isolado: aplica sobre um aerc.conf com mouse comentado e confirma mouse
# ligado (1x, sem duplicar), bind de saída rápida (Q) e que accounts.conf não é criado. Idempotente.
th=$(mktemp -d); printf '#!/bin/sh\nexit 0\n' > "$th/aerc"; chmod +x "$th/aerc"
mkdir -p "$th/.config/aerc"
printf '[ui]\n#mouse-enabled=false\nindex-columns=date\n' > "$th/.config/aerc/aerc.conf"
cat > "$th/drv.sh" <<DRV
HOME="$th"; PATH="$th:\$PATH"; conf(){ echo ""; }
DIR_TT="$th"
$(sed -n '/^AERC_BINDS_INI=/,/^remover_aerc() {/p' "$tt" | sed '$d')
$(sed -n '/^remover_aerc() {/,/^}/p' "$tt")
configurar_aerc; configurar_aerc
DRV
bash "$th/drv.sh" >/dev/null 2>&1
[[ $(grep -c '^mouse-enabled=true' "$th/.config/aerc/aerc.conf") == 1 ]] || falha 'aerc: mouse-enabled=true deveria aparecer 1x em [ui]'
sed -n '/^\[messages\]/,$p' "$th/.config/aerc/binds.conf" | grep -Fq 'q = :quit<Enter>' || falha 'aerc: binds.conf deveria ter saída rápida q na lista (casa com o título "q fecha")'
grep -Fq 'Q = :quit<Enter>' "$th/.config/aerc/binds.conf" || falha 'aerc: binds.conf deveria ter saída rápida Q'
[[ $(grep -c 'saída rápida' "$th/.config/aerc/binds.conf") == 2 ]] || falha 'aerc: bloco de bind não é idempotente (marcadores duplicados)'
[[ -f $th/.config/aerc/accounts.conf ]] && falha 'aerc: accounts.conf não deveria ser criado pelo provisionamento'
rm -rf "$th"
((falhas == base)) && ok 'aerc: tt garante mouse e saída rápida sem tocar contas (idempotente)' || true

# Sync local opcional de e-mail (mbsync/isync + maildir): contrato estrutural. O comportamento
# completo (opt-in, maildir sem cred-cmd, .mbsyncrc sem segredo, remoção limpa) está em
# tests/test_email_sync.sh; aqui só garantimos que as peças existem e são chamadas nos lugares certos.
base=$falhas
rg -q '^email_mbsyncrc_gerar\(\)' "$tt" || falha 'sync: email_mbsyncrc_gerar ausente'
rg -q '^email_sync\(\)' "$tt" || falha 'sync: email_sync ausente'
rg -q '^email_sync_todas\(\)' "$tt" || falha 'sync: email_sync_todas ausente'
rg -q 'sync_local' "$tt" || falha 'sync: chave sync_local ausente de EMAIL_CHAVES'
rg -Fq -- '--email-sync)' "$tt" || falha 'sync: verbo --email-sync ausente no dispatch'
rg -q 'maildir://' "$tt" || falha 'sync: email_url não gera source maildir://'
# O .mbsyncrc entra no snapshot (rollback) e o vigia dispara o sync periódico (TT_EMAIL_SYNC).
rg -q 'mbsyncrc\|' "$tt" || falha 'sync: .mbsyncrc fora do snapshot de rollback'
rg -q 'TT_EMAIL_SYNC' "$tt" || falha 'sync: vigia não agenda --email-sync (TT_EMAIL_SYNC)'
# O --email-sync é silencioso (chamado pelo vigia em segundo plano).
rg -q -- '--email-sync \| |\| --email-sync' "$tt" || falha 'sync: --email-sync fora da lista de verbos silenciosos'
# A credencial nunca é gravada em claro no .mbsyncrc: PassCmd sempre deriva de arquivo/comando.
rg -q 'email_mbsync_passcmd\(\)' "$tt" || falha 'sync: email_mbsync_passcmd (PassCmd sem segredo) ausente'
((falhas == base)) && ok 'sync local de e-mail: peças, verbo, snapshot, vigia e PassCmd sem segredo' || true

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

# Limpeza do estado do menu: sair_menu e o trap do --seletor removem todos os sidecars de
# Limpeza do estado do menu centralizada em limpar_estado(): remove todos os sidecars de
# $TT_ESTADO (lista, pos, fresca, mouse). sair_menu e o trap do --seletor usam essa fonte única,
# para não repetir a lista (foi assim que o .mouse escapou antes e vazou 1 arquivo por abertura).
base=$falhas
corpo_limpar=$(sed -n '/^limpar_estado()/,/^}/p' "$tt")
for side in lista pos fresca mouse; do
  grep -Fq "\$TT_ESTADO\".$side" <<<"$corpo_limpar" || falha "menu: limpar_estado não remove sidecar .$side (vazamento)"
done
sed -n '/^sair_menu()/,/^}/p' "$tt" | grep -Fq 'limpar_estado' || falha 'menu: sair_menu deve delegar para limpar_estado'
rg -q 'trap limpar_estado EXIT' "$tt" || falha 'menu: trap do --seletor deve usar limpar_estado'
# Nenhum trap EXIT de $TT_ESTADO pode remover só o arquivo base (rm -f cru): todos delegam a
# limpar_estado para não vazar sidecar futuro (foi assim que o .mouse escapou nos traps duplicados).
grep -nE "trap +'?rm -f +\"?\\\$TT_ESTADO\"?'? +EXIT" "$tt" >/dev/null 2>&1 \
  && falha 'menu: trap EXIT de $TT_ESTADO com rm -f cru (deve usar limpar_estado)'
((falhas == base)) && ok 'menu: limpar_estado centraliza limpeza dos sidecars (sem vazar arquivo)' || true

tmux -S "$sock" -f "$conf" new-session -d -s tt-test 'sleep 5'
tmux -S "$sock" list-keys -T root >"$tmp/keys"
base=$falhas
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
((falhas == base)) && ok 'teclas F1–F10 alcançam todos os botões do tt' || true
rg -q 'MouseUp3Status.*--clique-direito' "$conf" && rg -q 'MouseUp3Pane.*--menu-painel' "$conf" && ok 'botão direito alcança menus de status e painel' ||
  falha 'botão direito não tem rota completa'
rg -q 'align=right.*@barra_versao' "$tema" && rg -q 'range=user\|fixar' "$tema" && ok 'tema expõe pino e versão nos dois cantos da barra' ||
  falha 'tema não expõe controles esperados da barra'
((falhas == 0)) && ok 'configuração tmux isolada' || true

((falhas == 0)) || exit 1
printf 'Todos os testes passaram (%s).\n' "$raiz"
