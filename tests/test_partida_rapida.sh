#!/usr/bin/env bash
# tt-teste: sozinho (compara tempos)
# Partida rápida: a instalação gera rapido/ (núcleo com stubs + um corpo por função, conferidos contra o tt
# inteiro) e o desvio no topo do tt lê só o núcleo. A saída é a mesma do tt inteiro, o tempo cai, e qualquer
# problema volta ao caminho de sempre: corpo faltando (carrega todos), núcleo velho (tt editado depois),
# TT_COMPLETO=1, rapido/ removido. O gerador recusa um tt cuja divisão não confere com o bash.
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado
R=$TT_DIR/rapido
[[ -r $R/nucleo.sh ]] || falhou "a instalação não gerou a partida rápida: $(TT_COMPLETO=1 "$TT" --rapido gerar 2>&1)"
grep -q 'ligada' <<<"$("$TT" --rapido)" || falhou "tt --rapido: $("$TT" --rapido)"
(( $(wc -l <"$R/nomes") > 500 )) || falhou "poucas funções sob demanda: $(wc -l <"$R/nomes")"
(( $(wc -c <"$R/nucleo.sh") * 3 < $(wc -c <"$TT_DIR/tt") )) || falhou 'o núcleo deveria ter menos de um terço do tt'
passou "instalação gera a partida rápida ($(wc -l <"$R/nomes") funções sob demanda; núcleo de $(($(wc -c <"$R/nucleo.sh") / 1024)) KB)"

# 1) a mesma saída nos dois caminhos
tmux -f "$HOME/.tmux.conf" new -d -s s -x 120 -y 30 'bash --norc'; tmux new -d -s outra 'sleep 600'
for i in 1 2 3; do "$TT" --tarefa-add "tarefa $i @amanha !alta #x" >/dev/null 2>&1; done
"$TT" --fixar outra >/dev/null 2>&1
compara() {
  local v a b
  for v in "$@"; do
    a=$(TT_COMPLETO=1 "$TT" $v 2>&1; echo "rc=$?"); b=$("$TT" $v 2>&1; echo "rc=$?")
    a=${a/ (TT_COMPLETO=1: desligada neste ambiente)/}
    # Idade relativa ("agora", "há 5 s") muda entre as duas chamadas sob a carga da suíte: não é diferença de código.
    a=$(sed -E 's/(agora|há [0-9]+ (s|min|h)) +/IDADE /g' <<<"$a"); b=$(sed -E 's/(agora|há [0-9]+ (s|min|h)) +/IDADE /g' <<<"$b")
    [[ $a == "$b" ]] || falhou "$v: saída diferente com a partida rápida
--- inteiro:
$(head -5 <<<"$a")
--- rápido:
$(head -5 <<<"$b")"
  done
}
verbos=(--versao --help --tarefas-lista --tarefas-cabecalho --tarefas --listar --listar-leve --fixadas --atalhos-lista
  --letreiro-listar --pendencias --rapido --opcao-que-nao-existe)
compara "${verbos[@]}"
passou "a mesma saída com e sem a partida rápida (${#verbos[@]} verbos)"

# 2) mais rápido: a mediana do --versao cai a menos de 70% da do tt inteiro
mediana() { local i s e; for i in 1 2 3 4 5 6 7; do s=$EPOCHREALTIME; "$@" >/dev/null 2>&1; e=$EPOCHREALTIME; echo "${e/[.,]/} - ${s/[.,]/}" | bc; done | sort -n | sed -n 4p; }
ti=$(TT_COMPLETO=1 mediana "$TT" --versao); tr=$(mediana "$TT" --versao)
((tr * 10 < ti * 7)) || falhou "partida rápida não ficou mais rápida: inteiro $((ti / 1000)) ms, rápido $((tr / 1000)) ms"
passou "tt --versao: $((ti / 1000)) ms inteiro → $((tr / 1000)) ms com a partida rápida"

# 3) robustez: corpo faltando carrega todos; nada carregável dá erro claro; tt editado roda inteiro
rm -f "$R/f/tarefas_raw.sh"
compara --tarefas-lista
mv "$R/todas.sh" "$T/todas.sh"; mv "$R/f" "$T/f"
st=0; s=$("$TT" --tarefas-lista 2>&1) || st=$?
((st != 0)) && grep -q 'partida rápida incompleta' <<<"$s" || falhou "sem os corpos deveria dar erro claro (rc=$st): $s"
[[ -n $(TT_COMPLETO=1 "$TT" --tarefas-lista) ]] || falhou 'TT_COMPLETO=1 deveria contornar'
mv "$T/todas.sh" "$R/todas.sh"; mv "$T/f" "$R/f"
passou 'corpo faltando: carrega todos; sem corpos: erro claro, e TT_COMPLETO=1 contorna'
touch -d '+1 min' "$TT_DIR/tt"
grep -q desligada <<<"$("$TT" --rapido)" || falhou 'tt mais novo que o núcleo deveria desligar a partida rápida'
compara --tarefas-lista --versao
"$TT" --rapido gerar >/dev/null && grep -q ligada <<<"$("$TT" --rapido)" || falhou 'tt --rapido gerar deveria religar'
"$TT" --rapido remover >/dev/null && [[ ! -e $R ]] && grep -q desligada <<<"$("$TT" --rapido)" || falhou 'tt --rapido remover'
compara --versao --tarefas-lista
"$TT" --rapido gerar >/dev/null || falhou 'regerar'
passou 'tt editado depois da instalação roda inteiro; --rapido gerar/remover'

# 4) processos longos carregam todos os corpos de uma vez (uma instalação no meio não mistura versões)
grep -q -- '--vigia .*source "$_TT_RAPIDO/todas.sh"' "$R/nucleo.sh" || falhou 'o núcleo deveria carregar tudo nos processos longos'

# 5) o gerador recusa uma divisão que não confere: "}" na coluna 0 dentro de um heredoc engana o corte
D=$T/pacote-esquisito; mkdir -p "$D"
awk '/^\[\[ -n \$\{TT_SO_CARREGAR:-\} \]\]/ { print "teste_heredoc() {\n  cat <<'"'"'FIM'"'"'\n}\nFIM\n}" } { print }' "$TT_DIR/tt" >"$D/tt"
grep -q '^teste_heredoc() {' "$D/tt" || falhou 'cenário do heredoc não montado'
saida=$(TT_COMPLETO=1 bash -c 'TT_SO_CARREGAR=1 source "$1"; gerar_rapido "$2"' _ "$TT_DIR/tt" "$D" 2>&1) && falhou "o gerador aceitou uma divisão errada: $saida"
[[ -e $D/rapido ]] && falhou 'divisão recusada não pode deixar rapido/'
passou "o gerador recusa uma divisão que não confere ($saida)"
