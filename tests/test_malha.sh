#!/usr/bin/env bash
# Regressão (projeto tt): ILHAS na malha de máquinas. O cadastro liga só duas máquinas (A↔B); C cadastrada
# só em A deixava B e C sem se conhecer, e uma sessão de B não alcançava nenhuma de C. A malha precisa ser
# completa, coerente, inter-acessível e sem fricção. Simula 4 máquinas, cada uma com a sua configuração, e
# um ssh falso que executa o tt REAL na máquina de destino (com SSH_CONNECTION do chamador). Sem rede.
set -u
TT="$(cd "$(dirname "$0")/.." && pwd)/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
falhas=0
ok()   { echo "  ok: $1"; }
erro() { echo "  ERRO: $1"; falhas=$((falhas+1)); }

mkdir -p "$T/bin"
# host  pasta  ip
for n in 1 2 3 4; do
  d=$T/m$n; mkdir -p "$d/home/.local/bin" "$d/config/tt" "$d/rt"
  ln -s "$TT" "$d/home/.local/bin/tt"
  printf 'nome=m%s\n' "$n" >"$d/config/tt/config"
  echo "h$n $d 10.0.0.$n" >>"$T/hosts"; echo "10.0.0.$n $d 10.0.0.$n" >>"$T/hosts"
done
cat >"$T/bin/ssh" <<'SSH'
#!/usr/bin/env bash
args=("$@"); i=0; dest=""; porta=22
while ((i < ${#args[@]})); do
  a=${args[i]}
  case $a in -p) porta=${args[i+1]}; i=$((i+2)); continue ;; -o|-i|-l) i=$((i+2)); continue ;; -*) i=$((i+1)); continue ;; esac
  dest=$a; i=$((i+1)); break
done
cmd="${args[*]:i}"; host=${dest#*@}
read -r dir ip < <(awk -v h="$host" '$1 == h { print $2, $3 }' "$SIM_HOSTS")
[[ -n ${dir:-} ]] || { echo "ssh: Could not resolve hostname $host" >&2; exit 255; }
[[ -e $dir/PORTA8022 && $porta != 8022 ]] && { echo "ssh: connect to host $host port 22: Connection refused" >&2; exit 255; }
[[ -e $dir/DESLIGADA ]] && { echo "ssh: connect to host $host port 22: Connection timed out" >&2; exit 255; }
exec env HOME="$dir/home" XDG_CONFIG_HOME="$dir/config" TT_RT="$dir/rt" SSH_CONNECTION="${SIM_IP:-10.9.9.9} 50000 $ip 22" SIM_IP="$ip" bash -c "${cmd:-true}"
SSH
chmod +x "$T/bin/ssh"

# roda um verbo do tt COMO a máquina N
como() { local n=$1; shift; env HOME="$T/m$n/home" XDG_CONFIG_HOME="$T/m$n/config" TT_RT="$T/m$n/rt" SIM_HOSTS="$T/hosts" SIM_IP="10.0.0.$n" \
  PATH="$T/bin:$PATH" TMUX= TERM=xterm bash "$TT" "$@" 2>&1; }
reg() { local n=$1; shift; printf '# host usuario rotulo\n' >"$T/m$n/config/tt/maquinas"; local x; for x in "$@"; do echo "h$x u m$x" >>"$T/m$n/config/tt/maquinas"; done; }
rotulos() { awk '!/^#/ && NF { print $3 }' "$T/m$1/config/tt/maquinas" | sort | tr '\n' ' '; }
tem() { [[ " $(rotulos "$1")" == *" m$2 "* ]]; }

# --- 1) ilhas: m1 conhece todas; m2 só m1; m3 só m1; m4 só m1 (m2, m3 e m4 não se conhecem) -----------------
reg 1 2 3 4; reg 2 1; reg 3 1; reg 4 1
como 2 --malha-completar >/dev/null; como 3 --malha-completar >/dev/null; como 4 --malha-completar >/dev/null
como 2 --malha-completar >/dev/null    # 2ª volta: m2 aprende quem se apresentou depois
for a in 1 2 3 4; do for b in 1 2 3 4; do [[ $a != $b ]] && { tem $a $b && : || erro "m$a não conhece m$b (ilha): '$(rotulos $a)'"; }; done; done
[[ $falhas == 0 ]] && ok "malha completa: as 4 máquinas se conhecem entre si (nenhuma ilha)"
# o endereço com que uma se apresenta é o que a outra enxerga (IP de origem), não um nome
grep -q '^10.0.0.2 ' "$T/m3/config/tt/maquinas" && ok "m3 guardou m2 pelo IP de origem que ela viu (10.0.0.2)" || erro "m3 guardou m2 como: $(grep ' m2$' "$T/m3/config/tt/maquinas")"

# --- 2) coerência: m2 guardou m3 com rótulo errado; a máquina anuncia m3 ---------------------------------------
printf 'h1 u m1\nh3 u errado3\n' >>"$T/m2/config/tt/maquinas"; sed -i '/ m3$/d' "$T/m2/config/tt/maquinas"
como 2 --malha-completar >/dev/null
tem 2 3 && ! grep -q errado3 "$T/m2/config/tt/maquinas" && ok "rótulo incoerente corrigido para o que a máquina anuncia" || erro "rótulo: $(cat "$T/m2/config/tt/maquinas" | tr '\n' ';')"

# --- 3) remoção vale em todas e não ressuscita pela troca de listas -------------------------------------------
reg 1 2 3 4; reg 2 1 3 4; reg 3 1 2 4; reg 4 1 2 3; rm -f "$T"/m*/config/tt/maquinas-estado
como 1 --estado-maquina m4 removida "$(date +%s)" >/dev/null
sed -i '/ m4$/d' "$T/m1/config/tt/maquinas"
touch "$T/m4/DESLIGADA"
como 2 --malha-completar >/dev/null; como 3 --malha-completar >/dev/null; como 1 --malha-completar >/dev/null
for n in 1 2 3; do tem $n 4 && erro "m$n ainda lista m4 removida"; done
tem 1 4 || tem 2 4 || tem 3 4 || ok "m4 removida some de m1, m2 e m3 e a troca de listas não a ressuscita"
rm -f "$T/m4/DESLIGADA"

# --- 4) quem se cadastra de novo volta a valer em todas -----------------------------------------------------------
sleep 1; como 1 --registrar h4 u m4 >/dev/null; como 1 --estado-maquina m4 ativa "$(date +%s)" >/dev/null
como 2 --malha-completar >/dev/null; como 3 --malha-completar >/dev/null
tem 1 4 && tem 2 4 && tem 3 4 && ok "m4 recadastrada volta a valer em todas" || erro "m4 não voltou: m1='$(rotulos 1)' m2='$(rotulos 2)' m3='$(rotulos 3)'"

# --- 5) endereço que não vale daqui: m2 guarda m3 por um nome que não resolve; as outras usam um que conecta --
reg 1 2 3 4; reg 3 1 2 4; reg 4 1 2 3; printf '# h\nh1 u m1\nbad3 u m3\nh4 u m4\n' >"$T/m2/config/tt/maquinas"; rm -f "$T"/m*/config/tt/maquinas-estado
como 2 --malha-completar >/dev/null
grep -q '^h3 ' "$T/m2/config/tt/maquinas" && ! grep -q bad3 "$T/m2/config/tt/maquinas" && ok "m3 religada por outro endereço (o cadastrado não resolvia)" || erro "endereço: $(grep m3 "$T/m2/config/tt/maquinas")"

# --- 6) o diagnóstico mostra quem alcança quem e acusa ilha entre duas ligadas ---------------------------------------
reg 1 2 3 4; reg 2 1 3 4; reg 3 1 2 4; reg 4 1 2 3
saida=$(como 1 --malha); rc=$?
[[ $rc == 0 && $saida == *"Malha completa"* ]] && ok "tt --malha: malha completa, sai 0" || erro "malha completa não reconhecida (rc=$rc): $saida"
printf '# h\nh1 u m1\nbad3 u m3\nh4 u m4\n' >"$T/m2/config/tt/maquinas"   # m2 não alcança m3 (sem como consertar: ninguém usa outro)
reg 1 2 4; reg 4 1 2
saida=$(como 1 --malha); rc=$?
[[ $rc != 0 && $saida == *"m3:✗"* ]] && ok "tt --malha acusa a ilha (m2 não alcança m3) e sai com erro" || erro "ilha não acusada (rc=$rc): $saida"

# --- 7) sem nome= explícito a máquina NÃO é renomeada pelas outras (o rótulo escolhido pelo usuário vale) -----------
reg 1 2 3 4; reg 2 1 3 4; reg 3 1 2 4; reg 4 1 2 3
sed -i '/^nome=/d' "$T/m3/config/tt/config"; sed -i 's/^h3 u m3$/h3 u meu-apelido/' "$T/m2/config/tt/maquinas"
como 2 --malha-completar >/dev/null
grep -q 'meu-apelido' "$T/m2/config/tt/maquinas" && ok "rótulo escolhido pelo usuário preservado quando a outra não tem nome= explícito" || erro "rótulo trocado: $(grep h3 "$T/m2/config/tt/maquinas")"
printf 'nome=m3\n' >"$T/m3/config/tt/config"

# --- 8) o sshd do Termux escuta na 8022: a máquina nova é aprendida por fofoca e a porta entra no ssh config ---------
reg 1 2 3 4; reg 2 1; reg 3 1; reg 4 1; touch "$T/m4/PORTA8022"; rm -f "$T/m2/home/.ssh/config"
como 2 --malha-completar >/dev/null
tem 2 4 && grep -q 'Port 8022' "$T/m2/home/.ssh/config" 2>/dev/null && ok "m4 (sshd na 8022) aprendida e a porta registrada no ssh config" || erro "porta: rotulos='$(rotulos 2)' cfg='$(cat "$T/m2/home/.ssh/config" 2>&1)'"

echo
if ((falhas == 0)); then echo "TODOS OS TESTES PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit $falhas
