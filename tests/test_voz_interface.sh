#!/usr/bin/env bash
# tt-teste: sozinho (usa clientes reais no tmux isolado, sem controlar a tela do usuário)
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
V=$T/pkg/voz; EST=$HOME/.local/state/tt-voz
export TT_REAL=$TT_DIR/tt TEST_UI_LOG=$T/ui.log TEST_CONTA_LOG=$T/conta.log TEST_UI_REAL=$T/calendario-real
export VOZ_SDCARD=$T/sd VOZ_DESTRAVAR_PAUSA=0.05 VOZ_DESTRAVAR=4
mkdir -p "$HOME/.local/bin" "$T/sd"
rm -f "$HOME/.local/bin/tt" "$HOME/.local/bin/ia-conta"
cat >"$HOME/.local/bin/tt" <<'FIM'
#!/usr/bin/env bash
case $1 in
  --interface-abrir)
    printf '%s\n' "$*" >>"$TEST_UI_LOG"
    [[ $2 == calendario && -e $TEST_UI_REAL ]] || exit 0 ;;
  --atalho-rodar) printf '%s\n' "$*" >>"$TEST_CONTA_LOG"; exit 0 ;;
esac
exec "$TT_REAL" "$@"
FIM
cat >"$HOME/.local/bin/ia-conta" <<'FIM'
#!/usr/bin/env bash
[[ $* == 'abrir --listar-contas' ]] || exit 2
printf 'principal\tclaude\tPrincipal\t5h 10%%\ncareer\tclaude\tCareer\t5h 20%%\n'
FIM
chmod +x "$HOME/.local/bin/tt" "$HOME/.local/bin/ia-conta"
export PATH="$HOME/.local/bin:$PATH"
v() { VOZ_MUDO=1 VOZ_CEREBRO_CMD='exit 1' bash "$V" "$@"; }
c() { printf '%s' "$1" >"$T/plano.json"; VOZ_MUDO=1 VOZ_CEREBRO_CMD="cat '$T/plano.json'" bash "$V" 'faça o ajuste combinado'; }
esperar() { local i; for ((i=0; i<150; i++)); do grep -qF -- "$2" "$1" 2>/dev/null && return 0; sleep 0.1; done; falhou "não apareceu $2: $(cat "$1" 2>/dev/null)"; }
tmux -f "$HOME/.tmux.conf" new-session -d -s trabalho 'sleep 600'
tmux new-session -d -s outra 'sleep 600'
anexar visao 130 40 trabalho
for i in {1..100}; do cli=$(tmux list-clients -t '=trabalho' -F '#{client_name}' | head -1); [[ -n $cli ]] && break; sleep 0.1; done
[[ -n $cli ]] || falhou 'cliente de teste não anexou'
v 'aba trabalho' >/dev/null
EU=$(tt --listar-tudo --para-ia | sed -n '1s/.*— \([^ ]*\) —.*/\1/p')

saida=$(v 'esconda a barra das fixadas'); [[ $saida == *oculta* ]] || falhou "esconder: $saida"
saida=$(v 'mostre a barra das fixadas'); [[ $saida == *visível* ]] || falhou "mostrar: $saida"
saida=$(v 'ative o não perturbe por dez minutos'); [[ $saida == *'ligado até'* ]] || falhou "não perturbe: $saida"
saida=$(v 'desligue o não perturbe'); [[ $saida == *desligado* ]] || falhou "retomar avisos: $saida"
saida=$(v 'mude a mensagem do letreiro para Café às 15h'); [[ $saida == *atualizada* ]] || falhou "mensagem: $saida"
linha=$(tt --letreiro-ler); [[ $linha == *'Café às 15h'* ]] || falhou "mensagem perdeu acento ou caixa: $linha"
passou 'voz: barra, não perturbe e mensagem literal do letreiro'

tt --fixar trabalho >/dev/null
printf '%s\ttrabalho\t20\t0\t1\t1\t0\tfoto\tpedido\n' "$EU" >"$EST/chamadas"
printf '9999999999\tler\t%s\ttrabalho\t1\t\n' "$EU" >"$EST/agenda"
printf 'terminou\t%s\ttrabalho\t-\n' "$EU" >"$EST/retorno.fila"
printf '%s:trabalho' "$EU" >"$EST/pendente"
saida=$(v 'renomeie esta sessão para Revisão da Sprint')
nome=$(cat "$EST/alvo_s")
[[ $saida == *renomeada* && $nome == revisao-da-sprint ]] || falhou "renomear: $saida / $nome"
tmux has-session -t "=$nome" || falhou 'sessão nova não existe'
tt --fixadas | grep -qF "$nome" || falhou 'fixada não acompanhou'
grep -qxF "$EU:$nome" "$HOME/.config/tt-voz/permitidas" || falhou 'permissão da voz não acompanhou'
[[ $(cut -f2 "$EST/chamadas") == "$nome" && $(cat "$EST/pendente") == "$EU:$nome" ]] || falhou 'acompanhamento do retorno perdeu a sessão'
[[ $(cut -f4 "$EST/agenda") == "$nome" && $(cut -f3 "$EST/retorno.fila") == "$nome" ]] || falhou 'agenda ou retorno já enfileirado perdeu a sessão'
rm -f "$EST/pendente" "$EST/chamadas" "$EST/agenda" "$EST/retorno.fila"
passou 'voz: renomear preserva alvo, liberação, fixada e retorno em andamento'

v 'abrir e-mail' >/dev/null; esperar "$TEST_UI_LOG" "--interface-abrir email $cli"
v 'abrir transferências' >/dev/null; esperar "$TEST_UI_LOG" "--interface-abrir transferencias $cli"
v 'abrir calendário' >/dev/null; esperar "$TEST_UI_LOG" "--interface-abrir calendario $cli"
v 'aba outra' >/dev/null
saida=$(v 'abrir e-mail'); [[ $saida == *'Não há terminal conectado'* ]] || falhou "sem cliente abriu em outra tela: $saida"
v "aba $nome" >/dev/null
saida=$(v 'contas de e-mail'); [[ $saida == *'Nenhuma conta de e-mail cadastrada'* ]] || falhou "contas de email: $saida"
saida=$(v 'ver transferências'); [[ $saida == *'Nenhuma transferência registrada'* ]] || falhou "transferências: $saida"
tt --tarefa-add-natural 'Compromisso @amanha' >/dev/null
saida=$(v 'ler calendário'); [[ $saida == *Compromisso* ]] || falhou "agenda não foi lida: $saida"
touch "$TEST_UI_REAL"
v 'abrir calendário' >/dev/null
for i in {1..150}; do tela=$(fora capture-pane -p -J -t '=visao:'); [[ $tela == *'as tarefas com prazo, dia a dia'* ]] && break; sleep 0.1; done
[[ $tela == *'as tarefas com prazo, dia a dia'* ]] || falhou "calendário real não abriu no cliente escolhido: $tela"
fora send-keys -t '=visao:' Escape
rm -f "$TEST_UI_REAL"
passou 'voz: interfaces seguem o cliente da sessão escolhida; calendário real abre e consultas são lidas'

saida=$(v 'trocar conta'); [[ $saida == *principal* && $saida == *career* ]] || falhou "lista de contas: $saida"
saida=$(v 'troque a conta para career'); [[ $saida == *'Diga sim para trocar'* && ! -e $TEST_CONTA_LOG ]] || falhou "não confirmou antes de trocar: $saida"
v não >/dev/null; [[ ! -e $TEST_CONTA_LOG ]] || falhou 'trocou apesar do não'
v 'troque a conta para career' >/dev/null
saida=$(v sim); [[ $saida == *'Pronto: career'* ]] || falhou "troca confirmada: $saida"
[[ $(cat "$TEST_CONTA_LOG") == *'--atalho-rodar ia-aqui '*'conta=career'* ]] || falhou 'não reutilizou o atalho da conta'
rm -f "$TEST_CONTA_LOG"
v 'troque a conta para career' >/dev/null
tmux kill-session -t "=$nome"; tmux new-session -d -s "$nome" 'sleep 600'
saida=$(v sim); [[ $saida == *'sessão mudou'* && ! -e $TEST_CONTA_LOG ]] || falhou "a confirmação atingiu uma sessão substituída: $saida"
saida=$(v 'troque a conta para inexistente'); [[ $saida == *'Não conheço a conta'* && ! -e $TEST_CONTA_LOG ]] || falhou "conta inexistente: $saida"
passou 'voz: troca de conta confirma, respeita o não e recusa conta inválida ou sessão substituída'

saida=$(c '{"fala":"","acoes":[{"acao":"barra_fixadas","tecla":"esconder"},{"acao":"nao_perturbe","tecla":"ligar","segundos":120},{"acao":"mensagem_letreiro","texto":"Atenção: Café"}]}' )
[[ $saida == *oculta* && $saida == *'ligado até'* && $saida == *atualizada* ]] || falhou "ações do cérebro: $saida"
linha=$(tt --letreiro-ler); [[ $linha == *'Atenção: Café'* ]] || falhou 'texto do cérebro não foi literal'
printf '%s' '{"fala":"","acoes":[{"acao":"mensagem_letreiro","texto":"Pronto"},{"acao":"barra_fixadas","tecla":"mostrar"}]}' >"$T/plano.json"
saida=$(VOZ_MUDO=1 VOZ_CEREBRO_CMD="cat '$T/plano.json'" bash "$V" 'mude a mensagem do letreiro para Pronto e mostre a barra das fixadas')
[[ $saida == *atualizada* && $saida == *visível* ]] || falhou "segundo controle foi engolido pela mensagem: $saida"
linha=$(tt --letreiro-ler); [[ $linha == *Pronto* && $linha != *'mostre a barra'* ]] || falhou 'pedido composto virou texto do letreiro'
saida=$(c '{"fala":"","acoes":[{"acao":"trocar_conta","ia":"career"}]}' )
[[ $saida == *'Diga sim'* && ! -e $TEST_CONTA_LOG ]] || falhou "cérebro trocou sem aprovação do plano: $saida"
v não >/dev/null
regras=$(bash -c "source <(sed -n '/^cerebro_regras()/,/^}/p' '$V'); cerebro_regras")
for acao in barra_fixadas nao_perturbe mensagem_letreiro renomear_sessao email transferencias calendario trocar_conta; do
  grep -q "\"acao\":\"$acao\"" <<<"$regras" || falhou "ação ausente no prompt: $acao"
done
passou 'cérebro: novas ações preservam texto literal e a troca participa da confirmação do plano'
