#!/usr/bin/env bash
# Regressão (projeto tt): ILHAS na malha de máquinas. O cadastro liga só duas máquinas (A↔B); C cadastrada
# só em A deixava B e C sem se conhecer, e uma sessão de B não alcançava nenhuma de C. A malha precisa ser
# completa, coerente, inter-acessível e sem fricção. Simula 4 máquinas, cada uma com a sua configuração, e
# um ssh falso que executa o tt REAL na máquina de destino (com SSH_CONNECTION do chamador). Sem rede.
set -u; unset PREFIX
TT="$(cd "$(dirname "$0")/.." && pwd)/tt"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
source "$(dirname "$0")/tmux-isolado.sh"
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
# nome que só ESTA máquina (a que chama) não resolve: o celular sem o MagicDNS
grep -qxF "$host" "$HOME/naoresolve" 2>/dev/null && { echo "ssh: Could not resolve hostname $host: No address associated with hostname" >&2; exit 255; }
[[ -e $dir/PORTA8022 && $porta != 8022 ]] && { echo "ssh: connect to host $host port 22: Connection refused" >&2; exit 255; }
[[ -e $dir/DESLIGADA ]] && { echo "ssh: connect to host $host port 22: Connection timed out" >&2; exit 255; }
[[ -n ${SIM_LENTO:-} && $cmd == *--diagnosticar* ]] && sleep "$SIM_LENTO"   # diagnóstico lento (a máquina de destino não herda)
exec env SIM_LENTO= HOME="$dir/home" XDG_CONFIG_HOME="$dir/config" TT_RT="$dir/rt" SIM_HOSTS="$SIM_HOSTS" SSH_CONNECTION="${SIM_IP:-10.9.9.9} 50000 $ip 22" SIM_IP="$ip" bash -c "${cmd:-true}"
SSH
chmod +x "$T/bin/ssh"
# O teste simula máquinas fora da tailnet local. Não consulte o Tailscale instalado no host que roda
# a suíte, pois ele filtraria os nomes h1..h4 pelo estado real da rede.
# Uma máquina com $HOME/tailscale.json responde o status por ele (os cenários 9 e 10).
cat >"$T/bin/tailscale" <<'TAILSCALE'
#!/usr/bin/env bash
[[ ${1:-} == status && -f $HOME/tailscale.json ]] && { cat "$HOME/tailscale.json"; exit 0; }
echo indisponivel
TAILSCALE
chmod +x "$T/bin/tailscale"

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

# --- 9) o nome não resolve só nesta máquina (celular sem o MagicDNS) e as outras usam o mesmo nome: religa pelo IP
#        da tailnet que outra anuncia; uma cadastrada por IP (m4) não esconde o IP alternativo (era cortado em "10")
reg 1 2 3 4; reg 3 1 2 4; reg 4 1 2 3; rm -f "$T"/m*/config/tt/maquinas-estado "$T/m4/PORTA8022" "$T/m2/home/.ssh/config"
printf '# h\nh1 u m1\nh3 u m3\n10.0.0.4 u m4\n' >"$T/m2/config/tt/maquinas"
como 2 --registrar 10.0.0.3 u m3 >/dev/null
grep -qE '^10\.0\.0\.4 +u +m4$' "$T/m2/config/tt/maquinas" && grep -qE '^10\.0\.0\.3 +u +m3$' "$T/m2/config/tt/maquinas" &&
  ok "cadastrar uma pelo IP não apaga as outras guardadas por IP (era o corte no 1º ponto)" || erro "registrar por IP: $(grep -v '^#' "$T/m2/config/tt/maquinas" | tr '\n' ';')"
printf '# h\nh1 u m1\nh3 u m3\n10.0.0.4 u m4\n' >"$T/m2/config/tt/maquinas"
echo h3 >"$T/m2/home/naoresolve"
echo '{"Peer": {"p3": {"HostName": "h3", "DNSName": "h3.tail.ts.net.", "Online": true, "TailscaleIPs": ["10.0.0.3", "fd7a::3"]}}}' >"$T/m1/home/tailscale.json"
grep -q $'^M\t10.0.0.3\tu\tm3$' <<<"$(como 1 --malha-lista)" && ok "a malha-lista anuncia o IP da tailnet de quem está cadastrada por nome" || erro "sem o IP na malha-lista: $(como 1 --malha-lista | grep m3)"
como 2 --malha-completar >/dev/null
grep -qE '^10\.0\.0\.3 +u +m3$' "$T/m2/config/tt/maquinas" && ! grep -q '^h3 ' "$T/m2/config/tt/maquinas" && grep -q ' m4$' "$T/m2/config/tt/maquinas" &&
  ok "m3 religada pelo IP da tailnet (o nome não resolvia só em m2)" || erro "IP alternativo: $(grep -v '^#' "$T/m2/config/tt/maquinas" | tr '\n' ';')"
rm -f "$T/m2/home/naoresolve" "$T/m1/home/tailscale.json"

# --- 11) a máquina que esta perdeu do cadastro (o s23 sem o MagicDNS perdeu a book-hl pelo corte no 1º ponto) é
#         aprendida de novo pelo IP da tailnet que outra anuncia, já que o nome não resolve daqui
reg 1 2 3 4; reg 3 1 2 4; reg 4 1 2 3; rm -f "$T"/m*/config/tt/maquinas-estado
printf '# h\nh1 u m1\n10.0.0.4 u m4\n' >"$T/m2/config/tt/maquinas"
echo h3 >"$T/m2/home/naoresolve"
echo '{"Peer": {"p3": {"HostName": "h3", "DNSName": "h3.tail.ts.net.", "Online": true, "TailscaleIPs": ["10.0.0.3"]}}}' >"$T/m1/home/tailscale.json"
como 2 --malha-completar >/dev/null
grep -qE '^10\.0\.0\.3 +u +m3$' "$T/m2/config/tt/maquinas" && ! grep -q '^h3 ' "$T/m2/config/tt/maquinas" && grep -q ' m4$' "$T/m2/config/tt/maquinas" &&
  ok "m3 que m2 não conhecia é aprendida pelo IP da tailnet (o nome não resolve em m2)" || erro "aprender pelo IP: $(grep -v '^#' "$T/m2/config/tt/maquinas" | tr '\n' ';')"
rm -f "$T/m2/home/naoresolve" "$T/m1/home/tailscale.json"

# --- 10) desligada no Tailscale de quem pergunta não é ilha, nem vista de uma que não sabe (o Termux não tem o tailscale)
reg 1 2 3 4; reg 2 1 3 4; reg 3 1 2 4; reg 4 1 2 3; rm -f "$T"/m*/config/tt/maquinas-estado; touch "$T/m4/DESLIGADA"
echo '{"Peer": {"p4": {"HostName": "h4", "DNSName": "h4.tail.ts.net.", "Online": false, "TailscaleIPs": ["10.0.0.4"]}}}' >"$T/m1/home/tailscale.json"
saida=$(como 1 --malha); rc=$?
[[ $rc == 0 && $saida == *"m4:○"* && $saida != *"m4:✗"* ]] && ok "tt --malha: m4 desligada aparece ○ nas outras linhas e não conta como ilha" || erro "desligada vista como ilha (rc=$rc): $saida"
rm -f "$T/m4/DESLIGADA" "$T/m1/home/tailscale.json"

# --- 12) duas rodadas ao mesmo tempo (a volta do vigia e um tt --malha à mão): a pasta das respostas era fixa por
# usuário, a segunda apagava a da primeira, e as duas acusavam ilha falsa ("não respondeu ao diagnóstico")
( SIM_LENTO=2 como 1 --malha >"$T/malha-a" ) & a=$!
sleep 0.7; SIM_LENTO=2 como 1 --malha >"$T/malha-b"; rb=$?; wait "$a"; ra=$?
[[ $ra == 0 && $rb == 0 ]] && ! grep -q "sem resposta" "$T/malha-a" "$T/malha-b" && grep -q "Malha completa" "$T/malha-a" &&
  grep -q "Malha completa" "$T/malha-b" && grep -q "^m3 " "$T/malha-a" && grep -q "^m3 " "$T/malha-b" && ok "duas rodadas do tt --malha ao mesmo tempo não se atrapalham" ||
  erro "rodadas simultâneas viram ilha (rc $ra/$rb): $(cat "$T/malha-a" "$T/malha-b")"

echo
if ((falhas == 0)); then echo "TODOS OS TESTES PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit $falhas
