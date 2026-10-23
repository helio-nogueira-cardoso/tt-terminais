#!/usr/bin/env bash
# tt-teste: sozinho (confere desenho da barra e notificações do próprio servidor isolado)
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
printf '\nfaixa_notif=1\n' >>"$HOME/.config/tt/config"
tmux -f "$HOME/.tmux.conf" new-session -d -s exemplo 'sleep 600'
"$TT" --fixar exemplo >/dev/null
"$TT" --barras
[[ $(tmux show -gqv status) == 4 ]] || falhou 'layout inicial'
antes=$("$TT" --fixadas)
"$TT" --fixadas-faixa off | grep -q oculta || falhou 'ocultar fixadas'
[[ $(tmux show -gqv status) == 3 && $("$TT" --fixadas) == "$antes" ]] || falhou 'ocultar alterou cadastro ou altura'
linha=$(tmux display-message -p '#{E:status-format[2]}')
[[ $linha == *'fill=#232838'* && $linha != *'fill=#181825'* ]] || falhou "notificações não ocuparam a linha liberada: $linha"
"$TT" --fixadas-faixa on >/dev/null
[[ $(tmux show -gqv status) == 4 ]] || falhou 'restaurar altura'
linha=$(tmux display-message -p '#{E:status-format[2]}')
[[ $linha == *'fill=#181825'* ]] || falhou 'linha das fixadas não voltou'
sed -i 's/faixa_notif=1/faixa_notif=0/' "$HOME/.config/tt/config"
"$TT" --fixadas-faixa off >/dev/null
[[ $(tmux show -gqv status) == 2 ]] || falhou 'sem fixadas nem notificações'
fim0=$(tmux show -gqv @barra_fim0)
[[ $fim0 == *'#{E:@barra_tarefas}#{E:@barra_versao}'* ]] || falhou 'ocultar ambas as faixas escondeu tarefas e versão'
"$TT" --fixadas-faixa alternar >/dev/null
[[ $(tmux show -gqv status) == 3 ]] || falhou 'alternar fixadas sem notificações'
sed -i 's/faixa_notif=0/faixa_notif=1/' "$HOME/.config/tt/config"
"$TT" --barras
passou 'barra das fixadas: oculta sem apagar cadastros e recupera a linha nos dois layouts'

# O menu gera as mesmas ações da CLI; nenhuma consulta externa participa da montagem de teste.
menu=$(TT_COMPLETO=1 TT_SO_CARREGAR=1 bash -c '
  source "$0"
  maquinas() { :; }; versao_github() { echo 0; }; tam_popup_fixar() { :; }
  menu_popup() { cat; }
  menu_admin terminal-teste
' "$TT")
IFS=$'\t' read -r tecla rotulo acao <<<"$(awk -F'\t' '$1 == "F"' <<<"$menu")"
[[ $rotulo == *visível* && ${acao% --*} -ef $TT_DIR/tt && $acao == *' --fixadas-faixa alternar' ]] || falhou "menu da barra: $rotulo / $acao"
bash -c "$acao" >/dev/null
"$TT" --fixadas-faixa status | grep -q oculta || falhou 'rota do menu não ocultou a barra'
IFS=$'\t' read -r tecla rotulo acao <<<"$(awk -F'\t' '$1 == "D"' <<<"$menu")"
[[ $rotulo == *desligado* && ${acao% --*} -ef $TT_DIR/tt && $acao == *' --nao-perturbe alternar' ]] || falhou "menu não perturbe: $rotulo / $acao"
bash -c "$acao" >/dev/null
"$TT" --nao-perturbe status | grep -q ligado || falhou 'rota do menu não ligou o não perturbe'
"$TT" --nao-perturbe off >/dev/null; "$TT" --fixadas-faixa on >/dev/null
passou 'menu Administrar: rótulos e ações usam os mesmos controles da CLI'

mkdir -p "$T/bin"; export AVISOS_TESTE=$T/avisos
for cmd in notify-send termux-notification; do
  printf '#!/usr/bin/env bash\nprintf "aviso\\n" >>"$AVISOS_TESTE"\n' >"$T/bin/$cmd"; chmod +x "$T/bin/$cmd"
done
export PATH="$T/bin:$PATH"
avisar() { TT_COMPLETO=1 TT_SO_CARREGAR=1 bash -c 'source "$0"; notificar_aparelho titulo corpo' "$TT"; }
"$TT" --nao-perturbe on | grep -q ligado || falhou 'ligar não perturbe'
avisar
[[ ! -e $AVISOS_TESTE ]] || falhou 'não perturbe deixou passar aviso do aparelho'
"$TT" --notificar 'aviso preservado' 300 >/dev/null
"$TT" --notifs-listar | grep -q 'aviso preservado' || falhou 'não perturbe apagou o histórico'
"$TT" --nao-perturbe off >/dev/null; avisar
[[ -s $AVISOS_TESTE ]] || falhou 'desligar não restaurou os avisos'
"$TT" --nao-perturbe 60 >/dev/null
f=$HOME/.local/state/tt/nao-perturbe; fim=$(cat "$f")
[[ $fim =~ ^[0-9]+$ ]] || falhou 'prazo não foi persistido'
for n in 0 -1 100000 '2;touch ruim'; do
  "$TT" --nao-perturbe "$n" >/dev/null 2>&1 && falhou "aceitou prazo inválido: $n"
  [[ $(cat "$f") == "$fim" ]] || falhou 'prazo inválido alterou o estado'
done
printf '1\n' >"$f"
"$TT" --nao-perturbe status | grep -q desligado || falhou 'prazo vencido ficou ativo'
passou 'não perturbe: silencia o aparelho, preserva histórico, expira e rejeita prazos inválidos'

"$TT" --letreiro-add outra origem=lista item=Original escopo=local >/dev/null
python3 -I "$TT_DIR/letreiro-fontes.py" atualizar outra --forcar >/dev/null
mensagem='Reunião às 14h; $(touch '"$T"'/invadiu)'
"$TT" --letreiro-mensagem "$mensagem" >/dev/null
[[ ! -e $T/invadiu ]] || falhou 'mensagem executou comando'
linha=$("$TT" --letreiro-ler)
grep -qF 'Reunião às 14h' <<<"$linha" || falhou "mensagem não apareceu no letreiro: $linha"
"$TT" --letreiro-mensagem 'Novo aviso: café' >/dev/null
s=$("$TT" --letreiro-ler)
[[ $s == *'Novo aviso: café'* && $s != *'Reunião às 14h'* && $s == *Original* ]] || falhou "mensagem não substituiu só sua fonte: $s"
"$TT" --letreiro-mensagem $'duas\nlinhas' >/dev/null 2>&1 && falhou 'aceitou quebra de linha no cadastro'
passou 'mensagem do letreiro é literal, substituível e preserva as outras fontes'

nome=$("$TT" --renomear exemplo 'Novo nome')
tmux has-session -t "=$nome" || falhou 'renomeação sem prompt não ocorreu'
"$TT" --fixadas | grep -qF "$nome" || falhou 'a fixada não acompanhou o nome'
[[ $(tmux show -t "=$nome:" -qv @nome_auto) == 0 ]] || falhou 'nome manual ficou automático'
"$TT" --interface-abrir email /terminal-inexistente >/dev/null 2>&1 && falhou 'abriu interface em terminal inválido'
passou 'renomear pela CLI preserva fixadas; interface recusa terminal desconectado'
