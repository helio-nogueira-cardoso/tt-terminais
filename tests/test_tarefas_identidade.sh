#!/usr/bin/env bash
# Identidade das subtarefas: o CÓDIGO é a identidade (único, nunca repete, nunca é tomado por e-mail), o APELIDO
# estável (MÃE.apelido-da-sub) é a forma falável, e MÃE.N é só a posição de hoje: uma ordem única (ord, criação,
# código) em painel, cartão e linha de comando; empates normalizados ao mexer; subtarefa de subtarefa recusada;
# verbos que alteram dizem em que item agiram; e um e-mail não toma, não ressuscita nem substitui subtarefa alheia.
# Isola HOME/XDG/TT_RT; stub de tmux e notify-send.
source "$(dirname "$0")/lib.sh"; isolar
tt() { "$TT" "$@"; }
mkdir -p "$T/bin"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/notify-send"; printf '#!/bin/sh\nexit 1\n' >"$T/bin/tmux"; chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"
C="$XDG_CONFIG_HOME/tt/tarefas"; INBOX="$HOME/.cache/tt/maildir/conta/INBOX"; mkdir -p "$INBOX/new"
UI="$TT_RT/tt-tarefas-ui-$(id -u)"
sem_cor() { sed 's/\x1b\[[0-9;]*m//g'; }
estado() { awk -F'\t' -v i="$1" '$1==i{print $2; exit}' "$C"; }
pai_de() { awk -F'\t' -v i="$1" '$1==i{print $6; exit}' "$C" | tr '|' '\n' | sed -n 's/^pai=//p'; }
texto_de() { awk -F'\t' -v i="$1" '$1==i{print $5; exit}' "$C"; }
id_de() { awk -F'\t' -v t="$1" '$5==t && $2!="removida"{print $1; exit}' "$C"; }
ord_de() { awk -F'\t' -v i="$1" '$1==i{print $6; exit}' "$C" | tr '|' '\n' | sed -n 's/^ord=//p'; }

# 1) o gerador de código nunca devolve um que já existe (tenta de novo)
r=$(bash -c '
  MAQUINA=m; CNT=$(mktemp); echo 0 >"$CNT"
  date() { echo 1; }
  tarefas_estado_de() { local c; c=$(cat "$CNT"); echo $((c + 1)) >"$CNT"; ((c < 2)) && echo aberta; return 0; }
  source <(sed -n "/^tarefas_novo_id() {/,/^}/p" "$1")
  id=$(tarefas_novo_id x); echo "$id $(cat "$CNT")"' _ "$TT")
[[ $r =~ ^[0-9a-f]{12}\ 3$ ]] || falhou "o código deveria ser sorteado de novo até achar um livre (3 consultas): '$r'"
passou 'código novo nunca repete um que existe (tenta de novo)'

# 2) apelido estável da subtarefa dentro da mãe; MÃE.N continua sendo posição
tt --tarefa-add "Mae" >/dev/null; M=$(id_de Mae); ms=$(tt --tarefa-codigo "$M" | cut -f1)
for t in Alfa Beta Gama; do tt --tarefa-sub-add "$M" "$t" >/dev/null 2>&1; done
A=$(id_de Alfa); B=$(id_de Beta); G=$(id_de Gama)
refB=$(tt --tarefa-codigo "$B" | cut -f4)
[[ $refB == "$ms".* && ${refB#*.} =~ ^[bdfgjklmnprstvz][aeiou][bdfgjklmnprstvz][aeiou][0-9]{2}$ ]] || falhou "referência estável da subtarefa (mãe.apelido): '$refB'"
[[ $(tt --tarefa-codigo "$refB" | cut -f2) == "$B" ]] || falhou "mãe.apelido deveria resolver para a subtarefa"
[[ $(tt --tarefa-codigo "$ms.${B:0:6}" | cut -f2) == "$B" ]] || falhou "mãe.prefixo-do-código deveria resolver"
[[ $(tt --tarefa-codigo "$ms.2" | cut -f2) == "$B" ]] || falhou "mãe.N continua sendo a posição"
tt --tarefa-add "Outra" >/dev/null; O=$(id_de Outra); os=$(tt --tarefa-codigo "$O" | cut -f1)
tt --tarefa-codigo "$os.${refB#*.}" >/dev/null 2>&1 && falhou "o apelido de uma subtarefa não vale dentro de OUTRA mãe"
# a referência não muda quando as irmãs entram, saem ou trocam de lugar
tt --tarefa-rm "$A" >/dev/null 2>&1; tt --tarefa-sub-add "$M" "Delta" >/dev/null 2>&1; tt --tarefa-sub-mover "$G" cima
[[ $(tt --tarefa-codigo "$refB" | cut -f2) == "$B" ]] || falhou "o apelido estável tem de continuar apontando para a mesma subtarefa"
[[ $(tt --tarefa-codigo "$ms.1" | cut -f2) == "$G" && $(tt --tarefa-codigo "$ms.3" | cut -f2) != "$G" ]] || falhou "(a posição de Gama tinha de ter mudado: era .3 e agora é .1; .3 é outra subtarefa)"
# dois irmãos com o mesmo apelido: ambíguo, pede o código (nunca escolhe um)
printf 'aaaaaaaa0001\taberta\t5\t5\tDupla 1\tpai=%s|ord=90\naaaaaaaa0002\taberta\t6\t6\tDupla 2\tpai=%s|ord=91\n' "$M" "$M" >>"$C"
dup=$(tt --tarefa-codigo aaaaaaaa0001 | cut -f4)
msg=$(tt --tarefa-codigo "$dup" 2>&1) && falhou "apelido repetido entre irmãs deveria falhar"
grep -q 'ambíguo' <<<"$msg" && grep -q 'aaaaaaaa0001' <<<"$msg" && grep -q 'aaaaaaaa0002' <<<"$msg" || falhou "a ambiguidade deveria listar as candidatas: $msg"
sed -i '/^aaaaaaaa000[12]\t/d' "$C"
passou 'mãe.apelido e mãe.prefixo são estáveis; mãe.N é posição; apelido repetido entre irmãs pede o código'

# 3) uma ordem só: ord, criação, código (painel = linha de comando = texto), com 3 filhas de MESMO ord
rm -f "$C"; now=1791686100; M=aaaaaaaaaaaa
printf '%s\taberta\t%s\t%s\tMae T\t\n' "$M" $now $now >"$C"
printf 'ccccccc00001\taberta\t%s\t%s\tFilha criada 1o\tpai=%s|ord=1\n' $((now + 1)) $((now + 1)) "$M" >>"$C"
printf 'bbbbbbb00002\taberta\t%s\t%s\tFilha criada 2o\tpai=%s|ord=1\n' $((now + 2)) $((now + 2)) "$M" >>"$C"
printf 'aaaaaaa00003\taberta\t%s\t%s\tFilha criada 3o\tpai=%s|ord=1\n' $((now + 2)) $((now + 2)) "$M" >>"$C"
ms=$(tt --tarefa-codigo "$M" | cut -f1); printf 'exp=%s\n' "$M" >"$UI"
painel=$(tt --tarefas-lista 2>&1 | sem_cor | grep -E ' \.[0-9] ' | sed -E 's/^.* \.[0-9] [bdfgjklmnprstvz][aeiou][bdfgjklmnprstvz][aeiou][0-9]{2} //; s/ +[0-9a-f]{12}$//' | tr '\n' '|')
cli=""; for n in 1 2 3; do cli+="$(tt --tarefa-codigo "$ms.$n" | cut -f3)|"; done
texto=$(tt --tarefas | sem_cor | grep 'Filha' | sed -E 's/^ +. +//; s/ +\[.*$//' | tr '\n' '|')
[[ $cli == "Filha criada 1o|Filha criada 3o|Filha criada 2o|" ]] || falhou "ordem da linha de comando (ord, criação, código): $cli"
[[ $painel == "$cli" ]] || falhou "o painel deveria ordenar como a linha de comando: painel='$painel' cli='$cli'"
[[ $texto == "$cli" ]] || falhou "a listagem em texto deveria ordenar igual: texto='$texto' cli='$cli'"
passou 'painel, linha de comando e texto ordenam as filhas do mesmo jeito (ord, criação, código), inclusive em empate'

# 4) empate de ord: subir/descer funciona e acrescentar normaliza
c3=aaaaaaa00003
tt --tarefa-sub-mover "$c3" baixo
cli=""; for n in 1 2 3; do cli+="$(tt --tarefa-codigo "$ms.$n" | cut -f3)|"; done
[[ $cli == "Filha criada 1o|Filha criada 2o|Filha criada 3o|" ]] || falhou "descer a 2ª (empatada) deveria trocá-la com a 3ª: $cli"
[[ $(ord_de ccccccc00001) == 1 && $(ord_de bbbbbbb00002) == 2 && $(ord_de aaaaaaa00003) == 3 ]] || falhou "o empate deveria ter virado 1,2,3: $(ord_de ccccccc00001) $(ord_de bbbbbbb00002) $(ord_de aaaaaaa00003)"
sed -i -E 's/\|ord=[0-9]+$/|ord=1/' "$C"
tt --tarefa-sub-add "$M" "Quarta" >/dev/null 2>&1
q=$(id_de Quarta); [[ $(ord_de "$q") == 4 ]] || falhou "acrescentar a uma família empatada normaliza antes: Quarta ficou com ord $(ord_de "$q")"
[[ $(cut -f6 "$C" | tr '|' '\n' | sed -n 's/^ord=//p' | sort -n | uniq -d | wc -l) == 0 ]] || falhou "depois de acrescentar, ninguém deveria ter ord repetido"
[[ $(tt --tarefa-codigo "$ms.1" | cut -f3) == "Filha criada 1o" && $(tt --tarefa-codigo "$ms.4" | cut -f3) == Quarta ]] || falhou 'a ordem das antigas deveria ser preservada e a nova vir por último'
passou 'empate de ord: mover funciona, acrescentar normaliza 1..n sem mudar a ordem'

# 5) subtarefa de subtarefa e mãe inválida são recusadas, sem deixar linha órfã
antes=$(wc -l <"$C")
msg=$(tt --tarefa-sub-add "$q" "neto" 2>&1) && falhou "subtarefa de subtarefa deveria ser recusada"
grep -q 'subtarefa não tem subtarefa' <<<"$msg" && grep -q "$ms" <<<"$msg" || falhou "a mensagem deveria mandar acrescentar à mãe ($ms): $msg"
tt --tarefa-sub-add zzzzzz "x" >/dev/null 2>&1 && falhou "mãe inexistente deveria falhar"
[[ $(wc -l <"$C") == "$antes" ]] || falhou 'a recusa não pode deixar linha nova no arquivo'
tt --tarefa-add "Apagada" >/dev/null; D=$(id_de Apagada); tt --tarefa-rm "$D" >/dev/null 2>&1
tt --tarefa-sub-add "$D" "y" >/dev/null 2>&1 && falhou "não dá para acrescentar subtarefa a tarefa removida"
passou 'subtarefa de subtarefa, mãe inexistente e mãe removida: recusadas sem deixar lixo'

# 6) o verbo que altera diz em qual item agiu (stderr); pelo código inteiro fica quieto
tt --tarefa-abrir "$q" >/dev/null 2>&1
e=$(tt --tarefa-ok "$ms.4" 2>&1 >/dev/null)
grep -q "^→ $ms\.[a-z0-9]* «Quarta» (subtarefa de «Mae T»)" <<<"$e" || falhou "eco do alvo por posição: $e"
grep -q '.4 é posição e muda' <<<"$e" && grep -q "fixo: $ms\." <<<"$e" || falhou "por posição deveria avisar e dar a forma estável: $e"
tt --tarefa-abrir "$q" >/dev/null 2>&1
e=$(tt --tarefa-ok "$(tt --tarefa-codigo "$q" | cut -f1)" 2>&1 >/dev/null)
grep -q '^→ ' <<<"$e" && ! grep -q 'posição' <<<"$e" || falhou "pela referência estável: mostra o alvo, sem aviso de posição: $e"
tt --tarefa-abrir "$q" >/dev/null 2>&1
e=$(tt --tarefa-ok "$q" 2>&1 >/dev/null); [[ -z $e ]] || falhou "pelo código inteiro não há o que conferir: $e"
e=$(tt --tarefa-codigo "$ms.4" 2>&1 >/dev/null); [[ -z $e ]] || falhou "verbo que só lê não deveria ecoar: $e"
passou 'verbos que alteram dizem o alvo; por posição avisam; pelo código inteiro e os de leitura ficam quietos'

# 7) listagens mostram a referência estável
lista=$(tt --tarefas | sem_cor)
grep -qE "Quarta +\[$ms\.[a-z0-9]+ $q\]" <<<"$lista" || falhou "a listagem em texto deveria mostrar mãe.apelido e o código da subtarefa: $lista"
pr=$(tt --tarefa-ia-prompt "$M" | sem_cor)
grep -qE "\[$q\] (aberta|feita) · Quarta · $ms\.[a-z0-9]+$" <<<"$pr" && grep -q 'nunca pela posição' <<<"$pr" || falhou "o prompt da IA deveria listar o apelido estável e proibir a posição: $pr"
passou 'tt --tarefas e o prompt da IA mostram mãe.apelido (estável) ao lado do código'

# ---------- e-mail ----------
tt --demanda-autorizar chefe@empresa.com.br - aberto >/dev/null
eml() { # nome assunto corpo — a data é a de AGORA: mais nova que as linhas daqui (a precondição do sequestro)
  { echo "From: Chefe <chefe@empresa.com.br>"; echo "Date: $(date -R)"; echo "Message-ID: <$1@t>"
    echo "Subject: $2"; echo "Content-Type: text/plain; charset=utf-8"; echo; printf '%s\n' "$3"; } >"$INBOX/new/$1"
  tt --demandas-processar conta
}
rm -f "$C"; tt --tarefa-add "Tarefa Y" >/dev/null; Y=$(id_de "Tarefa Y")
tt --tarefa-sub-add "$Y" "sub vivo" >/dev/null 2>&1; tt --tarefa-sub-add "$Y" "sub apagado" >/dev/null 2>&1; tt --tarefa-sub-add "$Y" "outro sub" >/dev/null 2>&1
V=$(id_de "sub vivo"); R=$(id_de "sub apagado"); W=$(id_de "outro sub"); tt --tarefa-rm "$R" >/dev/null 2>&1
sleep 2

# 8) tarefa NOVA cujo e-mail traz códigos de subtarefas que já existem: nasce com códigos novos, nada é tomado
eml h1 "[tt] Tarefa inocente ~c0ffee000001" $'- ['"$V"$'] pega o código do vivo\n- ['"$R"$'] pega o código do apagado\n- [c0ffee0000aa] código livre'
[[ $(estado "$V") == aberta && $(pai_de "$V") == "$Y" && $(texto_de "$V") == "sub vivo" ]] || falhou "o sub vivo foi tomado: $(estado "$V") pai=$(pai_de "$V") «$(texto_de "$V")»"
[[ $(estado "$R") == removida && $(pai_de "$R") == "$Y" ]] || falhou "o sub apagado foi ressuscitado/movido: $(estado "$R")"
[[ $(estado c0ffee0000aa) == pendente && $(pai_de c0ffee0000aa) == c0ffee000001 ]] || falhou 'o código livre deveria ser mantido'
n1=$(id_de "pega o código do vivo"); n2=$(id_de "pega o código do apagado")
[[ -n $n1 && $n1 != "$V" && $(pai_de "$n1") == c0ffee000001 && $(estado "$n1") == pendente ]] || falhou "o sub que colidiu deveria nascer com código novo sob a tarefa nova: n1=$n1"
[[ -n $n2 && $n2 != "$R" && $(pai_de "$n2") == c0ffee000001 ]] || falhou "o sub que colidiu com o apagado deveria nascer com código novo: n2=$n2"
grep -q "colide=$V" <(awk -F'\t' -v i="$n1" '$1==i{print $6}' "$C") || falhou 'a colisão deveria ficar registrada (colide=) para a tela de diff'
tt --demanda-recusar c0ffee000001 >/dev/null
[[ $(estado "$V") == aberta && $(pai_de "$V") == "$Y" && $(estado "$W") == aberta ]] || falhou 'recusar a tarefa nova não pode levar subtarefas alheias'
[[ $(estado "$n1") == removida ]] || falhou 'recusar deveria descartar a subtarefa que veio no e-mail'
passou 'e-mail de tarefa nova com códigos de subtarefa já usados: códigos novos, nada é tomado nem ressuscitado, recusar não leva nada alheio'

# 9) "~código" que na verdade é o de uma SUBTAREFA: não vira proposta sobre ela, é demanda nova
eml h2 "[tt] Tarefa que cita um sub ~$W" 'corpo'
[[ $(texto_de "$W") == "outro sub" && $(estado "$W") == aberta ]] || falhou "a subtarefa foi alterada por um ~código: «$(texto_de "$W")»"
awk -F'\t' '$6 ~ /upd=/' "$C" | grep -q . && falhou "não deveria haver proposta de atualização sobre subtarefa"
m=$(id_de "Tarefa que cita um sub"); [[ -n $m && $(estado "$m") == pendente && -z $(pai_de "$m") ]] || falhou "deveria virar uma demanda nova comum: m=$m"
tt --demanda-recusar "$m" >/dev/null
passou '~código que aponta para uma subtarefa daqui é ignorado: vira demanda nova'

# 10) proposta de ATUALIZAÇÃO com código de subtarefa alheio / apagada: não mexe nelas, entra como nova (sem duplicar)
tt --tarefa-add "Tarefa Z" >/dev/null; Z=$(id_de "Tarefa Z"); tt --tarefa-sub-add "$Z" "já tenho" >/dev/null 2>&1; ZR=$(id_de "já tenho")
tt --tarefa-sub-add "$Z" "apaguei de Z" >/dev/null 2>&1; ZA=$(id_de "apaguei de Z"); tt --tarefa-rm "$ZA" >/dev/null 2>&1
sleep 2
eml h3 "[tt] Tarefa Z nova ~$Z" $'- ['"$V"$'] texto do sub alheio\n- ['"$ZA"$'] volta o apagado?\n- [already0000] já tenho\n- ['"$ZR"$'] já tenho'
p=$(awk -F'\t' '$2=="pendente" && $6 ~ /upd=/{print $1; exit}' "$C"); [[ -n $p ]] || falhou 'deveria haver uma proposta de atualização da Tarefa Z'
# (a Tarefa Z nunca foi compartilhada: sem base, o título diferente é conflito de verdade; aqui aceitamos a recebida)
tt --demanda-aprovar --recebida "$p" >/dev/null
[[ $(texto_de "$V") == "sub vivo" && $(pai_de "$V") == "$Y" ]] || falhou "a atualização mexeu em subtarefa de OUTRA tarefa: «$(texto_de "$V")» pai=$(pai_de "$V")"
[[ $(estado "$ZA") == removida ]] || falhou "a subtarefa apagada de Z não pode voltar com o código antigo: $(estado "$ZA")"
novo=$(id_de "texto do sub alheio"); [[ -n $novo && $novo != "$V" && $(pai_de "$novo") == "$Z" && $(estado "$novo") == aberta ]] || falhou "o texto do sub alheio deveria entrar como subtarefa NOVA de Z (código novo): novo=$novo"
[[ $(awk -F'\t' -v z="$Z" 'index($6,"pai=" z) && $2!="removida" && $5=="já tenho"' "$C" | wc -l) == 1 ]] || falhou 'subtarefa de mesmo texto não pode duplicar'
[[ -z $(id_de "volta o apagado?") ]] || falhou 'a apagada de Z não pode voltar nem como texto novo quando o código era dela'
passou 'atualização com código alheio: não mexe na subtarefa dos outros, entra como nova sem duplicar, a apagada daqui não volta'

# 11) legítimo: e-mail mais novo sobre a mesma PENDENTE mantém os códigos do remetente e substitui
eml h4 "[tt] Plano ~f00dfeed0001" $'- [f00dfeed0011] passo um\n- [f00dfeed0012] passo dois'
sleep 1
eml h5 "[tt] Plano v2 ~f00dfeed0001" $'- [f00dfeed0011] passo um (revisto)\n- [f00dfeed0012] passo dois'
[[ $(texto_de f00dfeed0001) == "Plano v2" && $(texto_de f00dfeed0011) == "passo um (revisto)" && $(pai_de f00dfeed0011) == f00dfeed0001 ]] || falhou "o e-mail mais novo deveria substituir a pendente mantendo os códigos: «$(texto_de f00dfeed0001)» «$(texto_de f00dfeed0011)»"
awk -F'\t' '$6 ~ /colide=/' "$C" | grep -q 'f00dfeed' && falhou 'o mesmo remetente reusando os próprios códigos pendentes não é colisão'
passou 'pendente substituída por e-mail mais novo mantém os códigos do remetente (sem falsa colisão)'
echo "TODOS OS TESTES PASSARAM"
