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
source <(sed -n '/^notifs_nome_valido()/,/^barra_status_linhas()/ { /^barra_status_linhas()/d; p; }' "$ROOT/tt")
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

# Código de evento (5º campo): o mesmo evento criado em várias máquinas (ex.: "📰 tt atualizado para a vX", um
# por máquina que se atualiza) vira UM aviso na rede inteira: fica o de menor id, as cópias ganham lápide e a
# marca de lido passa para o que fica. Aviso sem código com o mesmo texto e código de outro evento passam.
rm -f "$DIR_NOTIFS"/* "$TS"/ma/* "$TS"/mb/*
NV='📰 tt atualizado para a v9.9.9 — veja o que há de novo (clique)'
conta_evento() { # pasta: avisos (só ids, sem marcas) do evento novidades-v9.9.9
  local x n=0; for x in "$1"/*; do [[ ${x##*/} =~ ^[0-9]{18,20}$ ]] && grep -q $'\tnovidades-v9.9.9$' "$x" && n=$((n + 1)); done; echo "$n"
}
printf '%s\t%s\t%s\t%s\t%s\n' 9999999999 "$NV" novidades - novidades-v9.9.9 >"$DIR_NOTIFS/2000000000000000002"
printf '%s\t%s\t%s\t%s\t%s\n' 9999999999 "$NV" novidades - novidades-v9.9.9 >"$TS/ma/2000000000000000001"
printf '%s\t%s\t%s\t%s\t%s\n' 9999999999 "$NV" novidades - novidades-v9.9.9 >"$TS/mb/2000000000000000003"
: >"$TS/mb/2000000000000000003.lida"
printf '%s\t%s\t%s\n' 9999999999 "$NV" novidades >"$TS/mb/2000000000000000004"
printf '%s\t%s\t%s\t%s\t%s\n' 9999999999 'v9.9.8' novidades - novidades-v9.9.8 >"$TS/mb/2000000000000000005"
notifs_sincronizar; notifs_sincronizar
for dir in "$DIR_NOTIFS" "$TS/ma" "$TS/mb"; do
  n=$(conta_evento "$dir")
  ((n == 1)) || { echo "FALHOU: esperava 1 aviso do evento novidades-v9.9.9 em $dir, vi $n" >&2; exit 1; }
  [[ -f $dir/2000000000000000001 ]] || { echo "FALHOU: deveria ficar o de menor id em $dir" >&2; exit 1; }
  [[ -f $dir/2000000000000000001.lida ]] || { echo "FALHOU: a leitura da cópia não passou ao que ficou em $dir" >&2; exit 1; }
  [[ -f $dir/2000000000000000004 && -f $dir/2000000000000000005 ]] || { echo "FALHOU: aviso sem código ou de outro evento sumiu em $dir" >&2; exit 1; }
done
# canal "-" + código não podem virar canal "sino" nem atrapalhar o contador
[[ $(barra_notifs_sino) =~ ^[0-9]+$ ]] || { echo "FALHOU: contador quebrou com o 5º campo" >&2; exit 1; }
# Apagado pelo usuário: a lápide guarda o código, e uma cópia que chegue depois (máquina que se atualizou tarde)
# não traz o aviso de volta; o notificar local também não o recria.
notifs_apagar 2000000000000000001
grep -qx 'codigo=novidades-v9.9.9' "$DIR_NOTIFS/2000000000000000001.apagada" || { echo "FALHOU: lápide sem o código" >&2; exit 1; }
printf '%s\t%s\t%s\t%s\t%s\n' 9999999999 "$NV" novidades - novidades-v9.9.9 >"$TS/ma/2000000000000000009"
notifs_sincronizar
n=$(conta_evento "$DIR_NOTIFS")
((n == 0)) || { echo "FALHOU: evento apagado voltou pela sincronização ($n)" >&2; exit 1; }
notificar() { source <(sed -n '/^notificar()/,/^}/p' "$ROOT/tt"); notificar "$@"; }
notifs_podar() { :; }
notificar "$NV" 3600 novidades "" novidades-v9.9.9
n=$(conta_evento "$DIR_NOTIFS")
((n == 0)) || { echo "FALHOU: notificar recriou evento apagado ($n)" >&2; exit 1; }

# Código de LOTE (BASE#item,…): o aviso de e-mail novo. Cada máquina que espelha a conta vê os mesmos e-mails,
# mas não na mesma hora nem no mesmo número. Na rede some o aviso que não traz item novo (todos num mais velho
# que ficou, ou num apagado), na ordem dos ids: toda máquina chega ao mesmo resultado.
rm -f "$DIR_NOTIFS"/* "$TS"/ma/* "$TS"/mb/*
lote() { printf '%s\t%s\t%s\t%s\t%s\n' 9999999999 "$2" email:gm - "email-gm#$3" >"$1"; }
existe_em_todas() { local d; for d in "$DIR_NOTIFS" "$TS/ma" "$TS/mb"; do [[ -f $d/$1 ]] || return 1; done; }
sumiu_de_todas() { local d; for d in "$DIR_NOTIFS" "$TS/ma" "$TS/mb"; do [[ ! -e $d/$1 && -f $d/$1.apagada ]] || return 1; done; }
# A avisou X e depois Y; B estava fora e, ao voltar, avisou X e Y juntos; o local avisou X de novo (corrida).
lote "$TS/ma/3000000000000000001" 'X' aaa
lote "$TS/ma/3000000000000000002" 'Y' bbb
lote "$TS/mb/3000000000000000005" 'X e Y' aaa,bbb
: >"$TS/mb/3000000000000000005.lida"
lote "$DIR_NOTIFS/3000000000000000003" 'X de novo' aaa
lote "$TS/mb/3000000000000000004" 'Z e X' ccc,aaa   # traz Z: fica, mesmo repetindo X
lote "$TS/ma/3000000000000000006" 'conta outra' aaa; sed -i 's/email-gm#/email-outra#/' "$TS/ma/3000000000000000006"
notifs_sincronizar; notifs_sincronizar
for id in 3000000000000000001 3000000000000000002 3000000000000000004 3000000000000000006; do
  existe_em_todas "$id" || { echo "FALHOU: aviso de lote com item novo ($id) deveria ficar em todas" >&2; exit 1; }
done
for id in 3000000000000000003 3000000000000000005; do
  sumiu_de_todas "$id" || { echo "FALHOU: aviso de lote sem item novo ($id) deveria sumir de todas" >&2; exit 1; }
done
# o que sumiu (X e Y) já tinha sido lido: os mais velhos que ele cobria por inteiro (X, Y) ficam lidos
for d in "$DIR_NOTIFS" "$TS/ma" "$TS/mb"; do
  [[ -f $d/3000000000000000001.lida && -f $d/3000000000000000002.lida ]] || { echo "FALHOU: a leitura do lote que sumiu não passou aos que ficaram em $d" >&2; exit 1; }
  [[ ! -f $d/3000000000000000004.lida ]] || { echo "FALHOU: Z e X não estava coberto pelo lido e não deveria ficar lido em $d" >&2; exit 1; }
done
[[ $(notifs_itens_conhecidos email-gm | sort -u | paste -sd,) == aaa,bbb,ccc ]] || { echo "FALHOU: itens conhecidos de email-gm: $(notifs_itens_conhecidos email-gm | paste -sd,)" >&2; exit 1; }
# Apagado pelo usuário: a lápide guarda o código, e o lote que volta com os mesmos itens não reaparece.
notifs_apagar 3000000000000000004
grep -qx 'codigo=email-gm#ccc,aaa' "$DIR_NOTIFS/3000000000000000004.apagada" || { echo "FALHOU: lápide do lote sem o código" >&2; exit 1; }
lote "$TS/mb/3000000000000000009" 'Z de novo' ccc
notifs_sincronizar
sumiu_de_todas 3000000000000000009 || { echo "FALHOU: lote apagado pelo usuário voltou por outra máquina" >&2; exit 1; }
# A poda (só os 30 mais novos ficam) também guarda o código na lápide: quem volta de um tempo fora não reavisa.
rm -f "$DIR_NOTIFS"/* "$TS"/ma/* "$TS"/mb/*
source <(sed -n '/^notifs_podar()/,/^}/p' "$ROOT/tt")
lote "$DIR_NOTIFS/4000000000000000000" 'velho' ddd
for i in $(seq 10 40); do printf '%s\t%s\n' 9999999999 "aviso $i" >"$DIR_NOTIFS/40000000000000000$i"; done
notifs_podar
grep -qx 'codigo=email-gm#ddd' "$DIR_NOTIFS/4000000000000000000.apagada" || { echo "FALHOU: a poda não guardou o código do lote" >&2; exit 1; }
[[ $(notifs_itens_conhecidos email-gm) == ddd ]] || { echo "FALHOU: item do lote podado deveria continuar conhecido" >&2; exit 1; }
echo 'ok: notificações, leituras e exclusões convergem; cópia antiga não restaura aviso apagado; o mesmo código vira um aviso na rede, e o lote só fica com item novo'
