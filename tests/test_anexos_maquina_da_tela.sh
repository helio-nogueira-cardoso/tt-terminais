#!/usr/bin/env bash
# Anexos do e-mail abrem e são salvos na máquina da TELA em que se está, não na da sessão (a do aerc):
#  1) O (abrir), cliente que é ponte de outra máquina (TT_PONTE): o arquivo vai por ssh (tt --abrir-recebido),
#     com o conteúdo inteiro, e nada abre aqui;
#  2) cliente de dentro do popup do e-mail (TT_ORIGEM): idem;
#  3) a de lá não responde: abre aqui, como antes;
#  4) cliente desta máquina: abre aqui, sem ssh;
#  5) o lado de lá (tt --abrir-recebido NOME) guarda o conteúdo e abre; nome com barra não escapa da pasta;
#  6) S (salvar) pela ponte: pergunta a pasta de recebidos de lá e manda o anexo para ela (transferência);
#  7) S desta máquina: salva na pasta pedida, sem sobrescrever ("nome (2)");
#  8) E (enviar): o seletor de máquina começa pela da tela, marcada "(onde você está)";
#  9) o aerc ganha os abridores de anexo e o S novo.
source "$(dirname "$0")/lib.sh"; isolar
path_sem_termux_open_url
O() { fora "$@"; }
B=$T/bin; mkdir -p "$B"
printf '#!/bin/sh\necho "$1" >> %s\n' "$T/xdg.log" >"$B/xdg-open"; chmod +x "$B/xdg-open"
# ssh falso: registra o comando remoto e guarda a entrada; responde ao --pasta-recebidos; ssh-falha simula a de lá fora.
cat >"$B/ssh" <<EOF
#!/bin/sh
for a; do last=\$a; done
echo "\$last" >> $T/ssh.log
[ -f $T/ssh-falha ] && exit 255
case \$last in
  *--pasta-recebidos*) echo '~/Recebidos' ;;
  *--abrir-recebido*) cat > $T/ssh.stdin ;;
  *) cat >/dev/null ;;
esac
exit 0
EOF
chmod +x "$B/ssh"
export PATH="$B:$PATH"
printf 'nome=teste\n' >"$XDG_CONFIG_HOME/tt/config"
printf '192.0.2.7 ninguem book-x\n' >"$XDG_CONFIG_HOME/tt/maquinas"

tmux -f /dev/null new -d -s sessao 'sleep 600'
O new -d -s ponte -x 100 -y 20 "env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR TT_PONTE='book-x|ponte-1' tmux attach -t sessao"
O new -d -s local -x 90 -y 20 "env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR tmux attach -t sessao"
O new -d -s email -x 80 -y 20 "env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR TT_ORIGEM=book-x tmux attach -t sessao"
sleep 1
cli() { tmux list-clients -F '#{client_width} #{client_name}' | awk -v w="$1" '$1 == w { print $2 }'; }
c_ponte=$(cli 100) c_local=$(cli 90) c_email=$(cli 80)
[[ -n $c_ponte && -n $c_local && -n $c_email ]] || falhou "clientes de teste não subiram: $(tmux list-clients)"
espera() { local i; for ((i = 0; i < 30; i++)); do [[ -s $1 ]] && return 0; sleep 0.1; done; return 1; }
limpa() { rm -f "$T/xdg.log" "$T/ssh.log" "$T/ssh.stdin"; }
# Transferência lançada em segundo plano (setsid) pelo S pela ponte: o ssh dela pode chegar depois do limpa da
# etapa seguinte e cair no registro dela (sob a carga da suíte, era o "S local: não deveria usar ssh").
# Espera todas acabarem: estado ainda em andamento ou trabalhador vivo.
espera_transferencias() {
  local i f p st ativo
  for ((i = 0; i < 200; i++)); do
    ativo=0
    for f in "$TT_RT/tt-transferencias-$UID"/*.status; do
      [[ -f $f ]] || continue
      st=$(cat "$f" 2>/dev/null); p=$(cat "${f%.status}.pid" 2>/dev/null)
      case $st in 'na fila' | calculando* | transferindo*) ativo=1 ;; esac
      [[ -n $p ]] && kill -0 "$p" 2>/dev/null && ativo=1
    done
    ((ativo)) || return 0
    sleep 0.1
  done
  return 1
}

A="$T/aerc-tmp/Relatório final (v2).pdf"; mkdir -p "${A%/*}"; printf 'PDF-%s\n' "$RANDOM" >"$A"

limpa; TT_LINK_CLIENTE=$c_ponte "$TT" --abrir-anexo "$A" </dev/null
grep -q -- '--abrir-recebido' "$T/ssh.log" 2>/dev/null || falhou "O pela ponte: não foi por ssh para a máquina da tela ($(cat "$T/ssh.log" 2>/dev/null))"
[[ $(bash -c "set -- $(sed 's/.*--abrir-recebido //' "$T/ssh.log"); printf %s \"\$1\"") == "${A##*/}" ]] || falhou "nome chegou partido: $(cat "$T/ssh.log")"
cmp -s "$A" "$T/ssh.stdin" || falhou 'O pela ponte: o conteúdo do anexo não chegou inteiro'
sleep 0.3; [[ ! -s $T/xdg.log ]] || falhou "O pela ponte: abriu também aqui: $(cat "$T/xdg.log")"
passou 'O pela ponte: o anexo vai por ssh, inteiro e com o nome, para a máquina da tela'

limpa; TT_LINK_CLIENTE=$c_email "$TT" --abrir-anexo "$A" </dev/null
grep -q -- '--abrir-recebido' "$T/ssh.log" 2>/dev/null && cmp -s "$A" "$T/ssh.stdin" || falhou 'O no popup do e-mail (TT_ORIGEM): não foi para a máquina da tela'
passou 'O no popup do e-mail aberto de uma ponte (TT_ORIGEM): idem'

limpa; touch "$T/ssh-falha"; TT_LINK_CLIENTE=$c_ponte "$TT" --abrir-anexo "$A" </dev/null
espera "$T/xdg.log" && [[ $(cat "$T/xdg.log") == "$A" ]] || falhou "máquina da tela fora do ar: deveria abrir aqui ('$(cat "$T/xdg.log" 2>/dev/null)')"
rm -f "$T/ssh-falha"
passou 'máquina da tela fora do ar: abre aqui, como antes'

limpa; TT_LINK_CLIENTE=$c_local "$TT" --abrir-anexo "$A" </dev/null
espera "$T/xdg.log" && [[ $(cat "$T/xdg.log") == "$A" ]] || falhou 'cliente desta máquina: não abriu aqui'
[[ ! -s $T/ssh.log ]] || falhou "cliente desta máquina: não deveria usar ssh ($(cat "$T/ssh.log"))"
passou 'cliente desta máquina: abre aqui, sem ssh'

# --abrir-imagem (imagens do e-mail, tecla i) segue a mesma regra
limpa; TT_LINK_CLIENTE=$c_ponte "$TT" --abrir-imagem "$A" </dev/null
grep -q -- '--abrir-recebido' "$T/ssh.log" 2>/dev/null || falhou 'imagem pela ponte: não foi para a máquina da tela'
passou 'imagem (tecla i) pela ponte: idem'

# Lado de lá: guarda o que chega e abre; nome com barra fica dentro da pasta.
limpa; printf 'conteudo\n' | "$TT" --abrir-recebido '../../escapa/x.txt'
espera "$T/xdg.log" || falhou '--abrir-recebido não abriu o arquivo'
f=$(cat "$T/xdg.log")
[[ $f == "$HOME/.cache/tt-anexos/abertos/"* && -f $f && $(cat "$f") == conteudo ]] || falhou "--abrir-recebido guardou errado: '$f'"
[[ $f == */.._.._escapa_x.txt ]] || falhou "nome com barra não foi neutralizado: '$f'"
passou 'lado de lá: guarda em ~/.cache/tt-anexos/abertos e abre; barra no nome não escapa da pasta'

# S pela ponte: o anexo salvo pelo aerc em ~/.cache/tt-anexos/salvar vai para a pasta de recebidos de lá.
limpa; mkdir -p "$HOME/.cache/tt-anexos/salvar"; cp "$A" "$HOME/.cache/tt-anexos/salvar/"
TT_LINK_CLIENTE=$c_ponte "$TT" --anexo-salvar </dev/null >"$T/salvar.out" 2>&1
grep -q -- '--pasta-recebidos' "$T/ssh.log" || falhou "S pela ponte: não perguntou a pasta de recebidos da máquina da tela ($(cat "$T/ssh.log"))"
info=$(cat "$TT_RT/tt-transferencias-$UID"/*.info 2>/dev/null)
grep -q $'book-x\t~/Recebidos' <<<"$info" || falhou "S pela ponte: não iniciou a transferência para book-x:~/Recebidos (info: '$info'; saída: $(cat "$T/salvar.out"))"
[[ -z $(ls -A "$HOME/.cache/tt-anexos/salvar" 2>/dev/null) ]] || falhou 'S pela ponte: o anexo ficou na pasta de salvar'
espera_transferencias || falhou 'S pela ponte: a transferência não terminou em 20 s'
passou 'S pela ponte: o anexo vai para a pasta de recebidos da máquina da tela'

# S desta máquina: pede a pasta (aqui pela entrada) e não sobrescreve.
limpa; D=$T/destino; mkdir -p "$D"; echo antigo >"$D/${A##*/}"
mkdir -p "$HOME/.cache/tt-anexos/salvar"; cp "$A" "$HOME/.cache/tt-anexos/salvar/"
echo "$D" | TT_LINK_CLIENTE=$c_local "$TT" --anexo-salvar >"$T/salvar.out" 2>&1
[[ $(cat "$D/${A##*/}") == antigo ]] || falhou 'S local: sobrescreveu o arquivo que já existia'
n=${A##*/}; [[ -f "$D/${n%.*} (2).${n##*.}" ]] && cmp -s "$A" "$D/${n%.*} (2).${n##*.}" || falhou "S local: não salvou como 'nome (2)': $(ls "$D")"
[[ ! -s $T/ssh.log ]] || falhou "S local: não deveria usar ssh ($(cat "$T/ssh.log"))"
passou 'S desta máquina: salva na pasta pedida, sem sobrescrever (nome (2))'

# A descoberta da pasta padrão (cmd.exe no WSL) não pode consumir a pasta recebida pelo stdin.
mkdir -p "$HOME/.cache/tt-anexos/salvar"; cp "$A" "$HOME/.cache/tt-anexos/salvar/"
(
  TT_SO_CARREGAR=1 source "$TT"
  dest_da_tela() { :; }
  pasta_recebidos() { cat >"$T/entrada-consumida"; echo "$T/padrao"; }
  printf '%s\n' "$T/destino-explicito" | anexo_salvar
) >"$T/salvar-explicito.out" 2>&1 || falhou "salvar com destino explícito: $(cat "$T/salvar-explicito.out")"
cmp -s "$A" "$T/destino-explicito/${A##*/}" && [[ ! -e $T/entrada-consumida ]] || falhou 'descoberta do destino consumiu a entrada explícita'
passou 'pasta explícita pelo stdin dispensa a descoberta do padrão'

# E: o seletor de máquina começa pela da tela.
src=$(sed -n '/^escolher_maquina() {/,/^}/p' "$TT")
lista=$(MAQUINA=aqui bash -c 'maquinas() { printf "outra-x\tOutra\n192.0.2.7\tbook-x\n"; }
fzf() { cat >'"$T"'/fzf.in; head -1 '"$T"'/fzf.in; }
'"$src"'
escolher_maquina titulo "" 192.0.2.7')
[[ $lista == 192.0.2.7 ]] || falhou "E: a primeira opção deveria ser a máquina da tela, veio '$lista'"
grep -q 'onde você está' "$T/fzf.in" && [[ $(grep -c . "$T/fzf.in") == 3 ]] || falhou "E: lista errada: $(cat -v "$T/fzf.in")"
passou 'E: o seletor de máquina começa pela da tela, "(onde você está)", sem repetir'

# aerc: abridores de anexo e o S novo (o que o tt grava na configuração)
grep -q "openers \"\$tp\" \"\$HOME/.local/bin/tt --abrir-anexo {}\"" "$TT" && grep -q "for tp in 'application/\*' 'text/\*' 'audio/\*' 'video/\*'" "$TT" || falhou 'aerc: faltam os abridores de anexo'
grep -q 'S = :save -f -p $HOME/.cache/tt-anexos/salvar/<Enter>:term $HOME/.local/bin/tt --anexo-salvar<Enter>' "$TT" || falhou 'aerc: falta o S que salva na máquina da tela'
passou 'aerc: abridores de anexo (application, text, audio, video) e o S novo'
