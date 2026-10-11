#!/usr/bin/env bash
# A receita "o celular como navegador" (skill celular-android, seção 14): a função login_pelo_celular que está na
# DOCUMENTAÇÃO é extraída do próprio markdown e roda contra um alvo e um celular FALSOS (um `ssh` de mentira que
# responde pelos dois), em vários cenários: o caminho feliz (login do site → conta do Google → consentimento →
# código), o botão "Autorizar" abaixo da dobra, o Termux voltando à frente entre as chamadas, conexão que cai,
# tela apagada/bloqueada, reserva ocupada, senha/2FA, outra conta, página de erro, ensaio e tempo esgotado.
# O código de login nunca pode aparecer na saída nem no registro de chamadas.
source "$(dirname "$0")/lib.sh"; isolar

# ───────────── a função, tal como está na skill ─────────────
python3 -I - "$RAIZ/skill-celular-android.md" "$T/funcao.sh" <<'PY'
import re, sys
md = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"```bash\n(# login_pelo_celular.*?)\n```", md, re.S)
if not m: sys.exit("bloco login_pelo_celular não encontrado na skill")
open(sys.argv[2], "w", encoding="utf-8").write(m.group(1) + "\n")
PY
bash -n "$T/funcao.sh" || falhou 'a função da skill tem erro de sintaxe'
source "$T/funcao.sh"
passou 'a função da skill foi extraída e a sintaxe confere'

# ───────────── o ssh falso ─────────────
mkdir -p "$T/fake/bin"
cat >"$T/fake/bin/ssh" <<'FAKE'
#!/usr/bin/env bash
# ssh de mentira: responde pelo ALVO (ia-login) e pelo CELULAR (cliente do controle rápido, "fakecel").
E=${FAKE_DIR:?}
while (($#)); do case $1 in -o) shift 2 ;; -*) shift ;; *) break ;; esac; done
host=$1; shift; cmd="$*"
log() { printf '%s\n' "$*" >>"$E/chamadas.log"; }
if [[ $host == *celular* && -s $E/falhar_conexao ]]; then # conexão que cai (255) nas primeiras N tentativas
  n=$(<"$E/falhar_conexao"); if ((n > 0)); then echo $((n - 1)) >"$E/falhar_conexao"; log 'conexao-caiu'; exit 255; fi
fi

ia-login() {
  case $1 in
    --help) if [[ -f $E/ia_antigo ]]; then echo 'uso: ia-login [máquina...]'; else echo 'ia-login --principal CONTA|E-MAIL [--plano] [máq...]'; fi ;;
    --conferir) log "conferir $2 $3"; cat "$E/entrou" 2>/dev/null; true ;;
    --iniciar) log "iniciar $2 $3 $4"
      if [[ -f $E/iniciar_erro ]]; then cat "$E/iniciar_erro"; return 1; fi
      c=$(cat "$E/iniciar_corrida" 2>/dev/null || echo 0)
      if ((c > 0)); then echo $((c - 1)) >"$E/iniciar_corrida"; printf 'server exited unexpectedly\nia-login: tmux não abriu a sessão de login\n'; return 1; fi
      n=$(cat "$E/principal_aberta" 2>/dev/null || echo 0)
      if ((n > 0)); then
        echo $((n - 1)) >"$E/principal_aberta"
        printf 'ia-conta: a principal está aberta agora (processos: 123); feche essas sessões\n\n[ia-login: fim 1]\n' >"$E/tela"
      else cp "$E/tela_link" "$E/tela"; fi
      echo login-claude-principal ;;
    --tela) cat "$E/tela" ;;
    --encerrar) log "encerrar $2" ;;
    --codigo) log 'codigo-entregue'; printf '%s' "$3" >"$E/codigo_recebido"
      printf 'Paste code here if prompted > Login successful.\n[ia-login: fim 0]\n' >"$E/tela"; cp "$E/conta_final" "$E/entrou" ;;
  esac
}

pagina_atual() { cat "$E/pagina" 2>/dev/null || echo -1; }
arquivo_pagina() { local a=$E/paginas/$(pagina_atual); [[ -f $E/rolou && -f $a.rolado ]] && a=$a.rolado; echo "$a"; } # rolada: o botão ganha limites reais
dump() {
  echo '== com.android.systemui'; echo '[0,0,1080,94] FrameLayout id="status_bar"'
  if [[ $(cat "$E/frente" 2>/dev/null) == chrome ]]; then
    p=$(pagina_atual); echo "== $(cat "$E/navegador" 2>/dev/null || echo com.android.chrome)"
    cat "$(arquivo_pagina)" 2>/dev/null
    # páginas que "carregam": depois de K leituras, vão para outra
    if [[ -f $E/auto ]]; then
      while read -r n k m; do
        [[ $n == "$p" ]] || continue
        c=$(cat "$E/leituras_$p" 2>/dev/null || echo 0); c=$((c + 1)); echo "$c" >"$E/leituras_$p"
        ((c >= k)) && echo "$m" >"$E/pagina"
      done <"$E/auto"
    fi
  else echo '== com.termux'; echo '[0,0,1080,2316] TextView t="$ "'; fi
}
tela_pagina() { echo '@ com.android.chrome · ? · retrato'; cat "$E/paginas/$(pagina_atual).tela" 2>/dev/null; true; }
clicar() { # click por acessibilidade: só aciona elemento NATIVO do navegador (abas); botão de página web não reage
  local q=$1 exato=0 p linha
  q=${q#btn:}; q=${q#tab:}; [[ $q == =* ]] && { exato=1; q=${q#=}; }
  p=$(pagina_atual)
  if ((exato)); then grep -qE " (t|d)=\"$q\"" "$E/paginas/$p" 2>/dev/null || grep -q "\"$q" "$E/paginas/$p.tela" 2>/dev/null || return 1
  else grep -qiF -- "$q" "$E/paginas/$p" 2>/dev/null || grep -qiF -- "$q" "$E/paginas/$p.tela" 2>/dev/null || return 1; fi
  log "click:$q"
  while IFS='|' read -r n texto m req; do
    [[ $n == "$p" && $texto == "$q" ]] || continue
    [[ $req == nativo ]] || return 0 # no aparelho real o click "dá certo" (✓) mas a página web não reage
    echo "$m" >"$E/pagina"; return 0
  done <"$E/trans"
  return 0
}
tocar_xy() { # toque de verdade (input tap): aciona o elemento visível sob o ponto, web ou nativo
  local x=$1 y=$2 p arq linha n texto m tipo t x1 y1 x2 y2
  p=$(pagina_atual); arq=$(arquivo_pagina)
  while read -r linha; do
    [[ $linha =~ ^\[([0-9]+),([0-9]+),([0-9]+),([0-9]+)\] ]] || continue
    x1=${BASH_REMATCH[1]} y1=${BASH_REMATCH[2]} x2=${BASH_REMATCH[3]} y2=${BASH_REMATCH[4]}
    ((y2 - y1 > 0 && x >= x1 && x <= x2 && y >= y1 && y <= y2)) || continue
    [[ $linha =~ \ (t|d)=\"([^\"]*)\" ]] || continue
    t=${BASH_REMATCH[2]}; log "tap:$t"
    while IFS='|' read -r n texto m tipo; do
      [[ $n == "$p" && $texto == "$t" && -z $tipo ]] && { echo "$m" >"$E/pagina"; return 0; }
    done <"$E/trans"
    return 0
  done <"$arq"
  log 'tap:nada'
}
fakecel() {
  local sub=$1; shift
  case $sub in
    sh) case $1 in
          'echo ok') echo ok ;;
          'pm list packages '*) p=${1#pm list packages }; grep -qx "$p" "$E/pacotes" && echo "package:$p"; true ;;
          'cmd package resolve-activity'*) p=${1##* }; echo 'priority=0 preferredOrder=0 match=0x0 specificIndex=-1 isDefault=false'; grep "^$p/" "$E/atividades"; true ;;
          'dumpsys window | grep -q '*'input tap '*) # toque avulso com a guarda de foco do script
            [[ $(cat "$E/frente" 2>/dev/null) == chrome ]] || { log 'guarda-de-foco-barrou'; return 1; }
            set -- ${1##*input tap }; tocar_xy "$1" "$2" ;;
          'dumpsys power'*) cat "$E/estado_tela" ;;
          'input keyevent KEYCODE_WAKEUP') log wake; sed -i 's/Asleep/Awake/' "$E/estado_tela" ;;
          'wm size') echo 'Physical size: 1080x2316' ;;
          'am start'*) l=${1#*-d \'}; l=${l%\'}; printf '%s' "$l" >"$E/link_aberto"; log "am-start ${1%% -d*}"
            cat "$E/inicio" 2>/dev/null >"$E/pagina" || echo 0 >"$E/pagina"; echo chrome >"$E/frente"; rm -f "$E/rolou" "$E"/leituras_* ;;
        esac ;;
    lock) if [[ -f $E/ocupado ]]; then echo 'OCUPADO por outro até 10:00'; return 1; fi; log lock; echo 'OK reservado' ;;
    unlock) log unlock; echo OK ;;
    termux) log termux; echo termux >"$E/frente" ;;
    ui) mapfile -t partes < <(sed 's/ ; /\n/g' <<<"$1")
      for c in "${partes[@]}"; do
        c=${c# }
        case $c in
          abrir\ *) log "abrir ${c#abrir }"; echo chrome >"$E/frente" ;;
          assenta*) ;;
          'dump all') dump ;;
          'click '*) clicar "${c#click }" || { echo "✗ $c → NAO_ACHEI"; break; } ;;
          swipe*) log swipe; : >"$E/rolou" ;;
          'sh input tap '*) log 'tap-sem-efeito' ;; # dentro de um lote o toque não aciona botão de página web
          tap\ *) log 'tap-sem-efeito' ;; # o tap do servidor de acessibilidade não aciona botão de página web
          tela) tela_pagina ;;
          back) log back ;;
        esac
      done
      if [[ -s $E/volta_ao_termux ]]; then # o Termux volta à frente entre duas chamadas (N vezes)
        n=$(<"$E/volta_ao_termux")
        if ((n > 0)); then echo termux >"$E/frente"; echo $((n - 1)) >"$E/volta_ao_termux"; fi
      fi
      true ;;
  esac
}

if [[ $host == *celular* ]]; then eval "$cmd"
elif [[ $cmd == 'bash -s' ]]; then eval "$(cat)" # o código chega pelo stdin
else eval "$cmd"; fi
FAKE
chmod +x "$T/fake/bin/ssh"
export PATH=$T/fake/bin:$PATH FAKE_DIR=$T/fake/estado
export PAUSA=0.05 CEL=fakecel LIMITE=20 # leituras rápidas; o cliente de exemplo do celular chama-se fakecel aqui

EMAIL=conta.certa@exemplo.com
ESTADO_LINK='ZI1hD_0wy5_EZUnrvvfDtg'
CODIGO="AbCdEf0123456789AbCdEf0123456789AbCdEf#$ESTADO_LINK"
CODIGO_VELHO='QqQqQq0123456789QqQqQq0123456789QqQqQq#MGCScEK0tgWEnHesh0gBXQ' # de um login anterior (outro state)

# ───────────── montagem dos cenários ─────────────
pg() { cat >"$FAKE_DIR/paginas/$1"; }
cenario() { # zera o mundo falso e monta o caminho padrão (site → Google → consentimento → código → abas)
  rm -rf "$FAKE_DIR"; mkdir -p "$FAKE_DIR/paginas"; local E=$FAKE_DIR
  printf 'com.android.chrome\n' >"$E/pacotes"
  printf 'com.android.chrome/com.google.android.apps.chrome.Main\norg.mozilla.firefox/org.mozilla.fenix.HomeActivity\n' >"$E/atividades"
  printf 'mWakefulness=Awake\nisKeyguardShowing=false\n' >"$E/estado_tela"
  printf 'Opening browser to sign in…\nhttps://claude.com/cai/oauth/authorize?code=true&client_id=abc-123&state=%s&email=conta%%40exemplo.com\nPaste code here if prompted >\n' "$ESTADO_LINK" >"$E/tela_link"
  : >"$E/entrou"; echo "$EMAIL" >"$E/conta_final"
  pg 0 <<EOF
      [90,600,990,700] Button {c} t="Continuar com o Google"
      [90,500,990,590] EditText t="$EMAIL"
EOF
  pg 1 <<EOF
      [90,200,990,300] TextView t="Fazer Login com o Google"
      [90,310,990,400] Button {c} d="$EMAIL selecionado. Alternar entre contas"
      [90,900,490,990] Button {c} t="Cancelar"
      [500,900,990,990] Button {c} t="Continuar"
EOF
  pg 2 <<EOF
      [90,94,990,167] TextView t="Claude Code gostaria de se conectar à sua Claude chat account"
      [90,2018,990,2018] Button {c} t="Autorizar"
      [90,2018,990,2018] Button {c} t="Recusar"
EOF
  cat >"$E/paginas/2.rolado" <<EOF
      [90,94,990,167] TextView t="Claude Code gostaria de se conectar à sua Claude chat account"
      [90,1581,990,1697] Button {c} t="Autorizar"
      [90,1716,990,1832] Button {c} t="Recusar"
      [154,1989,925,2048] TextView t="Conectado como $EMAIL"
EOF
  pg 3 <<EOF
      [188,687,891,769] TextView t="Código de autenticação"
      [292,799,787,859] TextView t="Cole isso em Claude Code:"
      [75,1002,1004,1168] TextView t="$CODIGO"
      [345,1241,734,1337] Button {cf} t="Copiar código"
      [810,2023,945,2181] ImageButton {cl} d="Ver 3 guias" id="tab_switcher_button"
EOF
  pg 4 </dev/null; printf '   btn   "Fechar guia Authentication code | Claude Platform"\n' >"$E/paginas/4.tela"
  pg 5 </dev/null
  printf '0|Continuar com o Google|1|\n1|Continuar|2|\n2|Autorizar|3|\n3|guias|4|nativo\n4|Fechar guia Authentication code|5|nativo\n' >"$E/trans"
}
rodar() { # roda a função da skill e guarda saída + código de saída
  set +e; login_pelo_celular "$@" >"$T/saida.txt" 2>&1; RC=$?; set -e
  return 0
}
limpo() { # o código de login não pode vazar para a saída nem para o registro
  ! grep -qF "$CODIGO" "$T/saida.txt" "$FAKE_DIR/chamadas.log" 2>/dev/null || falhou "$1: o código de login vazou para a saída ou o registro"
}
chamou() { grep -qE -- "$1" "$FAKE_DIR/chamadas.log"; }
devolveu_o_celular() { chamou '^termux$' && chamou '^unlock$' || falhou "$1: não devolveu o Termux e soltou a reserva"; }
ALVO=u@alvo CEL_HOST=u@celular

# 1) caminho feliz: site → Google → consentimento → código; entrega, confere e limpa
cenario
rodar $ALVO $CEL_HOST $EMAIL
((RC == 0)) || falhou "caminho feliz: saída $RC: $(cat "$T/saida.txt")"
[[ $(cat "$FAKE_DIR/codigo_recebido") == "$CODIGO" ]] || falhou 'caminho feliz: o alvo não recebeu o código certo'
[[ $(cat "$FAKE_DIR/link_aberto") == *"state=$ESTADO_LINK&email=conta%40exemplo.com" ]] || falhou "caminho feliz: link aberto incompleto: $(cat "$FAKE_DIR/link_aberto")"
chamou 'tap:Autorizar' && chamou 'tap:Continuar com o Google' && chamou 'tap:Continuar$' || falhou 'caminho feliz: não andou pelas três telas'
! chamou 'tap:Recusar|tap:Cancelar|tap-sem-efeito' || falhou 'caminho feliz: tocou em Recusar/Cancelar (ou usou o tap do servidor, que não aciona página web)'
chamou 'click:Fechar guia Authentication code' || falhou 'caminho feliz: não fechou a aba do código'
chamou 'encerrar login-claude-principal' || falhou 'caminho feliz: não encerrou a sessão de login'
devolveu_o_celular 'caminho feliz'; limpo 'caminho feliz'
passou 'login completo: andou site → Google → consentimento → código, entregou, conferiu e limpou'

# 2) o botão "Autorizar" nasce com altura zero (abaixo da dobra): rola a página ANTES de tocar, e o toque é de verdade
cenario
rodar $ALVO $CEL_HOST $EMAIL
n_rolou=$(grep -n '^swipe$' "$FAKE_DIR/chamadas.log" | head -n 1 | cut -d: -f1); n_tocou=$(grep -n '^tap:Autorizar$' "$FAKE_DIR/chamadas.log" | head -n 1 | cut -d: -f1)
((RC == 0)) && [[ -n $n_rolou && -n $n_tocou ]] && ((n_rolou < n_tocou)) || falhou "autorizar abaixo da dobra: saída $RC: $(cat "$T/saida.txt")"
limpo 'dobra'; passou 'consentimento com o botão abaixo da dobra: rola a página, depois toca no centro do botão'

# 2b) o site está conectado em OUTRA conta ("Conectado como …"): não autoriza
cenario; sed -i 's/Conectado como [^"]*"/Conectado como outra.pessoa@exemplo.com"/' "$FAKE_DIR/paginas/2.rolado"
rodar $ALVO $CEL_HOST $EMAIL
((RC == 2)) && grep -q 'conectado como outra.pessoa@exemplo.com' "$T/saida.txt" && ! chamou 'tap:Autorizar' || falhou "site em outra conta: saída $RC: $(cat "$T/saida.txt")"
passou 'site conectado em outra conta: para antes de autorizar'

# 3) o Termux volta à frente entre uma chamada e outra: cada leitura traz o navegador no mesmo lote
cenario; echo 6 >"$FAKE_DIR/volta_ao_termux"; echo 6 >"$FAKE_DIR/inicio"; : >"$FAKE_DIR/paginas/6"; printf '6 2 0\n' >"$FAKE_DIR/auto" # a 1ª página ainda "carrega"
rodar $ALVO $CEL_HOST $EMAIL
((RC == 0)) || falhou "Termux voltando: saída $RC: $(cat "$T/saida.txt")"
chamou 'guarda-de-foco-barrou' || falhou 'Termux voltando: a guarda de foco deveria ter barrado um toque'
! chamou 'tap:nada' || falhou 'Termux voltando: um toque caiu fora do navegador'
limpo 'termux volta'; passou 'Termux voltando à frente: a leitura traz o navegador no mesmo lote e a guarda de foco barra o toque que cairia no Termux'

# 3b) uma aba velha, com o código de OUTRA sessão, está na frente na 1ª leitura: o código velho é ignorado
cenario; echo 7 >"$FAKE_DIR/inicio"; printf '7 2 0\n' >"$FAKE_DIR/auto"
pg 7 <<EOF
      [188,687,891,769] TextView t="Código de autenticação"
      [75,1002,1004,1168] TextView t="$CODIGO_VELHO"
EOF
rodar $ALVO $CEL_HOST $EMAIL
((RC == 0)) && [[ $(cat "$FAKE_DIR/codigo_recebido") == "$CODIGO" ]] || falhou "código de aba velha: saída $RC; o alvo recebeu o código errado? $(cat "$T/saida.txt")"
! grep -qF "$CODIGO_VELHO" "$FAKE_DIR/chamadas.log" "$T/saida.txt" || falhou 'o código velho vazou'
passou 'código de uma aba velha (outro state) é ignorado: só vale o #ESTADO do link desta sessão'

# 4) a conexão com o celular cai nas primeiras tentativas (celular de tela apagada): repete e segue
cenario; echo 2 >"$FAKE_DIR/falhar_conexao"
rodar $ALVO $CEL_HOST $EMAIL
((RC == 0)) && chamou 'conexao-caiu' || falhou "conexão caindo: saída $RC: $(cat "$T/saida.txt")"
limpo 'conexão'; passou 'conexão ssh que cai (255) é repetida'

# 5) já está na conta certa (mesmo com outra caixa): não faz nada; FORCAR=1 refaz
cenario; echo "$(tr a-z A-Z <<<"$EMAIL")" >"$FAKE_DIR/entrou"
rodar $ALVO $CEL_HOST $EMAIL
((RC == 0)) && ! chamou '^iniciar' || falhou "já logado: saída $RC: $(cat "$T/saida.txt")"
FORCAR=1 rodar $ALVO $CEL_HOST $EMAIL
((RC == 0)) && chamou '^iniciar' || falhou "FORCAR=1: saída $RC: $(cat "$T/saida.txt")"
passou 'alvo já na conta pedida: nada a fazer (FORCAR=1 refaz)'

# 6) celular bloqueado: para antes de gastar o link; apagado: acorda e segue
cenario; printf 'mWakefulness=Awake\nisKeyguardShowing=true\n' >"$FAKE_DIR/estado_tela"
rodar $ALVO $CEL_HOST $EMAIL
((RC == 3)) && ! chamou '^iniciar' || falhou "bloqueado: saída $RC: $(cat "$T/saida.txt")"
cenario; printf 'mWakefulness=Asleep\nisKeyguardShowing=false\n' >"$FAKE_DIR/estado_tela"
rodar $ALVO $CEL_HOST $EMAIL
((RC == 0)) && chamou '^wake$' || falhou "apagado: saída $RC: $(cat "$T/saida.txt")"
passou 'celular bloqueado: sai com 3 sem iniciar login; tela apagada: acorda e segue'

# 7) reserva da tela com outro dono: encerra o login que abriu e diz por quê
cenario; : >"$FAKE_DIR/ocupado"
rodar $ALVO $CEL_HOST $EMAIL
((RC == 1)) && grep -q 'reservada por outro' "$T/saida.txt" && chamou 'encerrar login-claude-principal' || falhou "reserva ocupada: saída $RC: $(cat "$T/saida.txt")"
passou 'reserva ocupada: não toca na tela e encerra o login aberto'

# 8) página que pede senha / verificação: para com 2, deixa o login aberto para o dono, devolve o celular
cenario; pg 1 <<EOF
      [90,200,990,300] TextView t="Digite sua senha"
      [90,310,990,400] EditText d="Senha"
EOF
rodar $ALVO $CEL_HOST $EMAIL
((RC == 2)) || falhou "senha: saída $RC: $(cat "$T/saida.txt")"
! chamou 'encerrar' && grep -q 'tmux -L tt-login attach' "$T/saida.txt" || falhou 'senha: deveria deixar o login aberto e dizer como terminar à mão'
devolveu_o_celular 'senha'; limpo 'senha'
passou 'senha/2FA: chama o dono (saída 2), deixa o login aberto e devolve o celular'

# 9) o Google mostra OUTRA conta: não toca em Continuar
cenario; pg 1 <<'EOF'
      [90,200,990,300] TextView t="Fazer Login com o Google"
      [90,310,990,400] Button {c} d="outra.pessoa@exemplo.com selecionado. Alternar entre contas"
      [500,900,990,990] Button {c} t="Continuar"
EOF
rodar $ALVO $CEL_HOST $EMAIL
((RC == 2)) && ! chamou 'tap:Continuar$' || falhou "outra conta: saída $RC: $(cat "$T/saida.txt")"
passou 'Google com outra conta: para sem tocar em Continuar'

# 10) consentimento: ENSAIO e AUTORIZAR=0 não autorizam
cenario; ENSAIO=1 rodar $ALVO $CEL_HOST $EMAIL
((RC == 0)) && ! chamou 'tap:Autorizar' && ! chamou 'codigo-entregue' || falhou "ensaio: saída $RC: $(cat "$T/saida.txt")"
cenario; AUTORIZAR=0 rodar $ALVO $CEL_HOST $EMAIL
((RC == 2)) && ! chamou 'tap:Autorizar' || falhou "AUTORIZAR=0: saída $RC: $(cat "$T/saida.txt")"
passou 'ENSAIO=1 e AUTORIZAR=0 nunca tocam em Autorizar'

# 11) ensaio quando o consentimento já foi dado antes (a página vai direto ao código): lê, não entrega
cenario; printf '0|Continuar com o Google|3|\n3|guias|4|nativo\n4|Fechar guia Authentication code|5|nativo\n' >"$FAKE_DIR/trans"
ENSAIO=1 rodar $ALVO $CEL_HOST $EMAIL
((RC == 0)) && ! chamou 'codigo-entregue' && grep -q 'li o código' "$T/saida.txt" || falhou "ensaio até o código: saída $RC: $(cat "$T/saida.txt")"
limpo 'ensaio'; passou 'ensaio até o código: lê, fecha a aba, devolve o celular e não entrega'

# 12) entrou OUTRA conta: sai com 4
cenario; echo outra.pessoa@exemplo.com >"$FAKE_DIR/conta_final"
rodar $ALVO $CEL_HOST $EMAIL
((RC == 4)) && grep -q 'OUTRA conta' "$T/saida.txt" || falhou "conta errada ao final: saída $RC: $(cat "$T/saida.txt")"
passou 'entrou outra conta: sai com 4 e avisa'

# 13) página de erro; tempo esgotado numa página que nunca anda
cenario; pg 1 <<'EOF'
      [90,200,990,300] TextView t="Something went wrong"
EOF
rodar $ALVO $CEL_HOST $EMAIL
((RC == 1)) && grep -q 'erro' "$T/saida.txt" || falhou "página de erro: saída $RC: $(cat "$T/saida.txt")"
cenario; pg 0 </dev/null
LIMITE=1 rodar $ALVO $CEL_HOST $EMAIL
((RC == 5)) && grep -q 'tempo esgotado' "$T/saida.txt" || falhou "tempo esgotado: saída $RC: $(cat "$T/saida.txt")"
devolveu_o_celular 'tempo'; passou 'página de erro (1) e tempo esgotado (5) saem limpos'

# 14) alvo antigo, login que não inicia, principal ainda aberta (tenta de novo) e sem link
cenario; : >"$FAKE_DIR/ia_antigo"; rodar $ALVO $CEL_HOST $EMAIL
((RC == 1)) && grep -q 'antigo' "$T/saida.txt" || falhou "ia-login antigo: saída $RC: $(cat "$T/saida.txt")"
cenario; echo 'ia-conta: não achei o Claude Code' >"$FAKE_DIR/iniciar_erro"; rodar $ALVO $CEL_HOST $EMAIL
((RC == 1)) && grep -q 'não iniciou' "$T/saida.txt" || falhou "iniciar com erro: saída $RC: $(cat "$T/saida.txt")"
cenario; echo 2 >"$FAKE_DIR/principal_aberta"; rodar $ALVO $CEL_HOST $EMAIL
((RC == 0)) || falhou "principal ainda saindo: saída $RC: $(cat "$T/saida.txt")"
(($(grep -c '^iniciar' "$FAKE_DIR/chamadas.log") == 3)) || falhou 'deveria tentar iniciar 3 vezes enquanto o login velho sai'
cenario; echo 9 >"$FAKE_DIR/principal_aberta"; rodar $ALVO $CEL_HOST $EMAIL
((RC == 1)) && grep -q 'não mostrou link' "$T/saida.txt" || falhou "principal sempre aberta: saída $RC: $(cat "$T/saida.txt")"
passou 'alvo antigo, login que não inicia e principal ainda aberta (repete 3 vezes e desiste com mensagem)'

# 14b) corrida do tmux 3.6 no alvo (ia-login antigo): repete o --iniciar; se nunca passa, desiste com a mensagem
cenario; echo 2 >"$FAKE_DIR/iniciar_corrida"; rodar $ALVO $CEL_HOST $EMAIL
(($(grep -c '^iniciar' "$FAKE_DIR/chamadas.log") == 3)) && ((RC == 0)) || falhou "corrida do tmux: saída $RC: $(cat "$T/saida.txt")"
cenario; echo 9 >"$FAKE_DIR/iniciar_corrida"; rodar $ALVO $CEL_HOST $EMAIL
((RC == 1)) && grep -q 'não iniciou o login' "$T/saida.txt" || falhou "corrida permanente: saída $RC: $(cat "$T/saida.txt")"
passou 'tmux do alvo ainda derrubando o servidor: repete o --iniciar (e desiste com mensagem se nunca passa)'

# 15) navegador: sem nenhum conhecido, e só o Firefox instalado (a atividade vem do próprio sistema)
cenario; : >"$FAKE_DIR/pacotes"; rodar $ALVO $CEL_HOST $EMAIL
((RC == 1)) && grep -q 'nenhum navegador' "$T/saida.txt" || falhou "sem navegador: saída $RC: $(cat "$T/saida.txt")"
cenario; echo org.mozilla.firefox >"$FAKE_DIR/pacotes"; echo org.mozilla.firefox >"$FAKE_DIR/navegador"
rodar $ALVO $CEL_HOST $EMAIL
((RC == 0)) || falhou "firefox: saída $RC: $(cat "$T/saida.txt")"
chamou 'abrir org.mozilla.firefox/org.mozilla.fenix.HomeActivity' || falhou "firefox: não abriu pela atividade resolvida: $(cat "$FAKE_DIR/chamadas.log" | head -5)"
passou 'sem navegador conhecido: para; só o Firefox: resolve a atividade principal e o usa'

# 16) a documentação e o ia-login concordam: todo verbo interno do ia-login está descrito na skill
for v in $(grep -m1 -- '--faltas | --principal-faltas' "$RAIZ/ia-login" | grep -oE -- '--[a-z-]+'); do
  grep -q -- "$v" "$RAIZ/skill-celular-android.md" || falhou "o verbo $v do ia-login não está descrito na skill celular-android"
done
passou 'todo verbo interno do ia-login (--iniciar, --tela, --codigo, ...) está descrito na skill'
echo "TODOS OS TESTES PASSARAM"
