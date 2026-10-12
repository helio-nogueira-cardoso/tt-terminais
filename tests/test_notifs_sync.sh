#!/usr/bin/env bash
# O sino é estado da rede: union de avisos e marcas de leitura, em ambos os sentidos.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$(dirname "$0")/lib.sh"; isolar
TS=$T/notifs-sync; mkdir -p "$TS/bin" "$TS/rt" "$TS/local" "$TS/ma" "$TS/mb"
export TT_TEST_REMOTE_ROOT=$TS
cat >"$TS/bin/ssh" <<'SH'
#!/usr/bin/env bash
dest=$1; shift; cmd=$1; dir=$TT_TEST_REMOTE_ROOT/$dest
mkdir -p "$dir"
case $cmd in
  *--notifs-exportar) tar -C "$dir" -cf - . ;;
  *--notifs-receber) tar -xf - -C "$dir" --no-same-owner --no-same-permissions ;;
  *) exit 1 ;;
esac
SH
chmod +x "$TS/bin/ssh"; export PATH="$TS/bin:$PATH"
export RT=$TS/rt DIR_NOTIFS=$TS/local EU=tt TT_REMOTO=tt
SSH_OPC=()
maquinas() { printf 'ma\tA\nmb\tB\n'; }
atualizar_barras() { :; }
source <(sed -n '/^notifs_nome_valido()/,/^notifs_sincronizar_em_segundo_plano()/p' "$ROOT/tt")
source <(sed -n '/^barra_notifs_sino()/,/^}/p' "$ROOT/tt")

printf '%s\t%s\t%s\t%s\n' 9999999999 'local não lida' - sino >"$DIR_NOTIFS/1000000000000000001"
printf '%s\t%s\t%s\t%s\n' 9999999999 'A não lida' - sino >"$TS/ma/1000000000000000002"
printf '%s\t%s\t%s\t%s\n' 9999999999 'B lida' - sino >"$TS/mb/1000000000000000003"
: >"$TS/mb/1000000000000000001.lida"
notifs_sincronizar

for dir in "$DIR_NOTIFS" "$TS/ma" "$TS/mb"; do
  for id in 1000000000000000001 1000000000000000002 1000000000000000003; do
    [[ -f $dir/$id ]] || { echo "FALHOU: $id não chegou a $dir" >&2; exit 1; }
  done
  [[ -f $dir/1000000000000000001.lida ]] || { echo "FALHOU: marca lida não convergiu em $dir" >&2; exit 1; }
done
[[ $(barra_notifs_sino) == 2 ]] || { echo "FALHOU: contador universal deveria mostrar dois avisos não lidos" >&2; exit 1; }
: >"$DIR_NOTIFS/1000000000000000002.lida"; notifs_sincronizar
for dir in "$DIR_NOTIFS" "$TS/ma" "$TS/mb"; do
  [[ -f $dir/1000000000000000002.lida ]] || { echo "FALHOU: leitura nova não chegou a $dir" >&2; exit 1; }
done
[[ $(barra_notifs_sino) == 1 ]] || { echo "FALHOU: contador universal não atualizou após leitura" >&2; exit 1; }
echo 'ok: notificações e marcas de leitura convergem entre as máquinas; leitura não é desfeita por cópia antiga'
