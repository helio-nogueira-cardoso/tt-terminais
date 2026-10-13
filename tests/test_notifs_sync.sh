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
  *--notifs-receber)
    tmp=$(mktemp -d "$dir/.receive.XXXX")
    tar -xf - -C "$tmp" --no-same-owner --no-same-permissions
    cp -an "$tmp"/* "$dir"/ 2>/dev/null || true
    for tomb in "$dir"/*.apagada; do
      [[ -f $tomb ]] || continue
      id=${tomb##*/}; id=${id%.apagada}; rm -f "$dir/$id" "$dir/$id.lida"
    done
    rm -rf "$tmp"
    ;;
  *) exit 1 ;;
esac
SH
chmod +x "$TS/bin/ssh"; export PATH="$TS/bin:$PATH"
export RT=$TS/rt DIR_NOTIFS=$TS/local EU=tt TT_REMOTO=tt
SSH_OPC=()
maquinas() { printf 'ma\tA\nmb\tB\n'; }
atualizar_barras() { :; }
atualizar_barras_pedir() { :; }
source <(sed -n '/^notifs_nome_valido()/,/^barra_status_linhas()/p' "$ROOT/tt")
source <(sed -n '/^notifs_apagar()/,/^notifs_render()/ { /^notifs_render()/d; p; }' "$ROOT/tt")
source <(sed -n '/^barra_notifs_sino()/,/^}/p' "$ROOT/tt")
notifs_sincronizar_em_segundo_plano() { notifs_sincronizar; }

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
notifs_apagar 1000000000000000001
for dir in "$DIR_NOTIFS" "$TS/ma" "$TS/mb"; do
  [[ ! -e $dir/1000000000000000001 ]] || { echo "FALHOU: exclusão não convergiu em $dir" >&2; exit 1; }
  [[ -f $dir/1000000000000000001.apagada ]] || { echo "FALHOU: lápide não convergiu em $dir" >&2; exit 1; }
done
# Uma cópia antiga que reapareça depois deve ser removida pela lápide universal.
printf '%s\t%s\n' 9999999999 'cópia antiga' >"$TS/ma/1000000000000000001"
notifs_sincronizar
for dir in "$DIR_NOTIFS" "$TS/ma" "$TS/mb"; do
  [[ ! -e $dir/1000000000000000001 ]] || { echo "FALHOU: aviso apagado ressuscitou em $dir" >&2; exit 1; }
done
: >"$DIR_NOTIFS/1000000000000000003.lida"
notifs_apagar_lidas
for dir in "$DIR_NOTIFS" "$TS/ma" "$TS/mb"; do
  [[ ! -e $dir/1000000000000000002 && ! -e $dir/1000000000000000003 ]] || { echo "FALHOU: apagar lidas não convergiu em $dir" >&2; exit 1; }
done
echo 'ok: notificações, leituras e exclusões convergem; cópia antiga não restaura aviso apagado'
