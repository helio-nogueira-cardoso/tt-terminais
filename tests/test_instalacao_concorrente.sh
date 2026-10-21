#!/usr/bin/env bash
# tt-teste: sozinho (várias instalações ao mesmo tempo)
# Duas trocas de pacote ao mesmo tempo (o vigia que se atualiza sozinho + um --atualizar/--sincronizar chamado de fora) usavam os mesmos
# nomes (tt.novo, tt.velho), apagavam a cópia um do outro e deixavam ~/.local/share/tt sem o pacote: a empresa ficou com o tt quebrado
# em 21/10/2026. A troca agora é uma por vez, e quem espera confere de novo (mesmo pacote: nada a fazer; mais novo instalado: não rebaixa).
source "$(dirname "$0")/lib.sh"; isolar
inst=$T/inst; export TT_DIR=$inst
pac() { rm -rf "$T/p$2"; cp -r "$T/pkg" "$T/p$2"; echo "$1" >"$T/p$2/VERSAO"; }
ver() { cut -d' ' -f1-2 "$inst/VERSAO" 2>/dev/null; }
completo() { local f; for f in tt voz VERSAO tema-agentes.sh memoria-agentes.sh README.md; do [[ -e $inst/$f ]] || { echo "falta $f"; return 1; }; done; [[ -x $inst/tt ]] || { echo "tt sem permissão"; return 1; }; bash -n "$inst/tt" 2>/dev/null || { echo "tt com erro de sintaxe"; return 1; }; }
sem_restos() { local r; r=$(ls -d "$inst".novo "$inst".velho "$inst".trava 2>/dev/null); [[ -z $r ]] || { echo "sobrou: $r"; return 1; }; }
pids=()
espera() { local p; for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done; pids=(); }

pac "50 aaaaaaa 2026-10-01" a; "$T/pa/tt" --instalar-aqui >/dev/null 2>&1; [[ $(ver) == "50 aaaaaaa" ]] || falhou "instalação inicial: $(ver)"

# 1) 8 instalações do MESMO pacote ao mesmo tempo
pac "60 bbbbbbb 2026-10-02" b
for i in 1 2 3 4 5 6 7 8; do "$T/pb/tt" --instalar-aqui >/dev/null 2>&1 & pids+=($!); done; espera
[[ $(ver) == "60 bbbbbbb" ]] || falhou "8 instalações simultâneas: versão ${ver:-?}: $(ver)"
r=$(completo) || falhou "pacote incompleto depois de 8 instalações simultâneas: $r"
r=$(sem_restos) || falhou "restos da troca: $r"
passou 'concorrência: 8 instalações do mesmo pacote deixam um pacote completo e sem restos'

# 2) pacotes de versões DIFERENTES ao mesmo tempo: a mais nova vence, ninguém rebaixa
pac "70 ccccccc 2026-10-03" c; pac "65 ddddddd 2026-10-02" d; pac "61 eeeeeee 2026-10-02" e
for k in e d c e d c; do "$T/p$k/tt" --instalar-aqui >/dev/null 2>&1 & pids+=($!); done; espera
[[ $(ver) == "70 ccccccc" ]] || falhou "a mais nova deveria ganhar (70): $(ver)"
r=$(completo) || falhou "pacote incompleto com versões diferentes: $r"
r=$(sem_restos) || falhou "restos da troca (versões diferentes): $r"
passou 'concorrência: com versões diferentes a mais nova vence e ninguém rebaixa'

# 3) trava de um processo que morreu é retomada (não prende a instalação)
mkdir -p "$inst.trava"; echo 999999 >"$inst.trava/pid"
pac "80 fffffff 2026-10-04" f; "$T/pf/tt" --instalar-aqui >/dev/null 2>&1; [[ $(ver) == "80 fffffff" ]] || falhou "trava de processo morto prendeu a instalação: $(ver)"
# 4) trava de um processo VIVO faz esperar e, vencido o prazo, não troca nada
mkdir -p "$inst.trava"; echo $$ >"$inst.trava/pid"
pac "90 ggggggg 2026-10-05" g; TT_INSTALAR_TRAVA_TENTATIVAS=4 "$T/pg/tt" --instalar-aqui >/dev/null 2>&1 && falhou 'com a trava de um processo vivo, a instalação deveria desistir'
[[ $(ver) == "80 fffffff" ]] || falhou "desistiu mas trocou o pacote: $(ver)"
rm -rf "$inst.trava"
passou 'trava: de processo morto é retomada; de processo vivo faz esperar e desistir sem trocar nada'
