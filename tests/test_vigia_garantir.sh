#!/usr/bin/env bash
# tt-teste: sozinho (mede tempo: roda sem outros testes disputando a máquina)
# Vigia morto é religado por quem usa a barra, e a malha espera a rede subir depois de um sleep.
#  - tt --vigia-garantir liga o vigia que não existe, no máximo a cada 30 s, e deixa em paz o que está vivo;
#  - TT_SEM_VIGIA_AUTO=1 desliga (é o que a suíte usa);
#  - salto do relógio entre duas voltas do vigia (a máquina dormiu): a malha só é conferida TT_POS_WAKE s depois.
source "$(dirname "$0")/lib.sh"; isolar; instalar_isolado # antes do tmux: instalar com servidor de pé religaria o vigia
# S23: Debian instalado não substitui o perfil nativo que tem máquinas ou e-mail.
(
  TT_SO_CARREGAR=1 source "$TT_DIR/tt"
  PREFIX=/data/data/com.termux/files/usr
  distro_proot() { return 0; }
  email_slugs() { :; }
  CONF_MAQ=$T/maquinas-vigia
  vigia_no_debian || falhou 'perfil nativo vazio deveria delegar ao Debian'
  echo 'host usuario maquina' >"$CONF_MAQ"
  vigia_no_debian && falhou 'perfil com máquinas não pode ficar sem vigia'
  : >"$CONF_MAQ"
  email_slugs() { echo gmail; }
  vigia_no_debian && falhou 'perfil com e-mail não pode ficar sem vigia'
  passou 'vigia nativo preservado quando Debian não atende o perfil'
)
unset TT_SEM_VIGIA_AUTO
tmux -f /dev/null new -d -s s 'sleep 600'
pidf="$TT_RT/tt-vigia-$(id -u).pid"
vivo() { local p; p=$(cat "$pidf" 2>/dev/null); [[ -n $p ]] && kill -0 "$p" 2>/dev/null; }
esperar() { local i; for ((i = 0; i < $2 * 2; i++)); do eval "$1" && return 0; sleep 0.5; done; return 1; }

vivo && falhou 'havia vigia antes de o teste começar'
TT_SEM_VIGIA_AUTO=1 "$TT" --vigia-garantir; sleep 2
vivo && falhou 'TT_SEM_VIGIA_AUTO=1 não desligou o religamento'
rm -f "$TT_RT"/tt-vigia-garantir-*

TT_PAUSA=2 "$TT" --vigia-garantir
esperar vivo 10 || falhou 'tt --vigia-garantir não religou o vigia parado'
p1=$(cat "$pidf")
passou 'vigia parado é religado por tt --vigia-garantir'

rm -f "$TT_RT"/tt-vigia-garantir-*
"$TT" --vigia-garantir; sleep 2
[[ $(cat "$pidf") == "$p1" ]] || falhou 'vigia vivo foi trocado por outro'
passou 'vigia vivo não é tocado'

# Morto de novo: dentro dos 30 s da última conferência não religa (a marca vale); passados, religa.
kill -9 "$p1"; sleep 1
"$TT" --vigia-garantir; sleep 2
vivo && falhou 'religou antes de passar a janela de 30 s da marca'
rm -f "$TT_RT"/tt-vigia-garantir-*
TT_PAUSA=2 "$TT" --vigia-garantir
esperar vivo 10 || falhou 'não religou depois da janela da marca'
passou 'a conferência respeita a janela de 30 s e religa depois dela'
kill -9 "$(cat "$pidf")" 2>/dev/null; sleep 1

# Instalar com TT_RT isolado (testes) nunca mexe no vigia de OUTRO tt. No macOS o pidfile do vigia de verdade mora no
# $TMPDIR (não há /run/user); o instalador procurava pidfiles antigos ali e em /tmp, matava o vigia e apagava o arquivo, e
# toda suíte de testes derrubava o vigia de quem a rodava.
mkdir -p "$T/fora"
bash -c 'sleep 300; : "$0"' --vigia & decoy=$!      # "vigia de fora": a linha de comando traz --vigia
echo "$decoy" >"$T/fora/tt-vigia-$(id -u).pid"
echo "1000 teste 2099-01-01" >"$T/pkg/VERSAO" # versão nova: reinstalar a mesma sai cedo, sem chegar à troca do vigia
TMPDIR=$T/fora TT_DIR=$HOME/.local/share/tt "$T/pkg/tt" --instalar-aqui >/dev/null 2>&1
kill -0 "$decoy" 2>/dev/null || falhou 'instalar com TT_RT isolado matou o vigia de fora (pidfile no TMPDIR)'
[[ -f $T/fora/tt-vigia-$(id -u).pid ]] || falhou 'instalar com TT_RT isolado apagou o pidfile de fora'
kill "$decoy" 2>/dev/null
passou 'instalar com TT_RT isolado não toca no vigia nem no pidfile de fora'

# Depois de um sleep: o vigia fica parado (SIGSTOP) por mais que 3 voltas + folga, e o relógio anda; a volta seguinte vê o
# salto e a malha espera TT_POS_WAKE s. (Com a folga de 10 s e voltas de ~5 s, o salto é > 13 s.)
export TT_SEM_VIGIA_AUTO=1                       # daqui em diante só o vigia que o teste liga
for p in $(pgrep -f "$TT --vigia"); do kill -9 "$p" 2>/dev/null; done; sleep 1   # (o caminho de $TT é só deste teste)
marcas=$T/malha
conta() { [[ -f $marcas ]] && wc -l <"$marcas" | tr -d ' ' || echo 0; }
rm -f "$pidf" "$TT_RT"/tt-vigia-garantir-*
TT_PAUSA=1 TT_T_MALHA=1 TT_FOLGA_WAKE=10 TT_POS_WAKE=12 TT_TESTE_MALHA_MARCA=$marcas "$TT" --vigia >/dev/null 2>&1 &
esperar vivo 15 || falhou 'o vigia do teste não subiu'
vp=$(cat "$pidf")
esperar '[[ $(conta) -ge 1 ]]' 20 || falhou 'a malha nunca foi conferida (teste sem efeito)'
passou 'sem sleep, a malha é conferida'
kill -STOP "$vp"; sleep 1; n1=$(conta)        # parado: nenhuma volta nova (e a que estava em curso já gravou)
sleep 16; kill -CONT "$vp"                    # a máquina "dormiu" 17 s
sleep 9                                       # pelo menos uma volta depois de acordar, dentro dos 12 s de tolerância
[[ $(conta) -eq $n1 ]] || falhou "a malha foi conferida logo depois do sleep ($(conta) marcas; eram $n1 antes de dormir)"
n2=$(conta)
esperar "[[ \$(conta) -gt $n2 ]]" 25 || falhou 'a malha não voltou a ser conferida depois da tolerância'
passou 'depois de um sleep a malha espera a rede subir e volta a ser conferida'
kill -9 "$vp" 2>/dev/null
exit 0
