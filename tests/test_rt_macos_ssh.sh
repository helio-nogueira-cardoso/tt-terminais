#!/usr/bin/env bash
# Runtime (RT) estável no macOS: o servidor do tmux e o vigia nascem com TMPDIR=/var/folders/…/T/, mas o ssh não
# interativo não define TMPDIR e o RT caía em /tmp. O pidfile do vigia ficava num lugar para o tmux e noutro para o ssh:
# `tt --checar` por ssh dizia "vigia parado" com ele vivo, e o vigia_garantir de uma sessão ssh podia subir um 2º vigia.
# `rt_sem_run_user` usa o getconf DARWIN_USER_TEMP_DIR quando o TMPDIR falta (só no macOS) e não abre processo nenhum
# quando o TMPDIR existe. uname e getconf são falsos: roda em qualquer sistema, sem tocar no runtime de verdade.
source "$(dirname "$0")/lib.sh"; isolar
fail() { echo "FALHOU: $1" >&2; exit 1; }

mkdir -p "$T/falso" "$T/usuario-tmp" "$T/gui-tmp"
# uname: o sistema vem de $FALSO_SO. getconf: devolve $FALSO_TMP (com a barra final, como o de verdade) e deixa um rastro.
cat >"$T/falso/uname" <<'SH'
#!/bin/sh
echo "${FALSO_SO:-Linux}"
SH
cat >"$T/falso/getconf" <<'SH'
#!/bin/sh
echo "$1" >>"$FALSO_RASTRO"
[ "$1" = DARWIN_USER_TEMP_DIR ] && echo "$FALSO_TMP"
SH
chmod +x "$T/falso/uname" "$T/falso/getconf"

# Roda rt_sem_run_user no tt instalado (o pacote copiado por isolar) e imprime o RT que ele escolheu.
# $1 = sistema falso; $2 = TMPDIR ("" = não definido); $3 = o que o getconf diz.
rt_de() {
  : >"$T/rastro"
  (cd / && env -u TMPDIR ${2:+TMPDIR="$2"} FALSO_SO="$1" FALSO_TMP="$3" FALSO_RASTRO="$T/rastro" PATH="$T/falso:$PATH" \
    TT_COMPLETO=1 TT_SO_CARREGAR=1 bash -c 'source "$1/tt"; rt_sem_run_user; printf "%s" "$RT"' _ "$TT_DIR")
}
chamou_getconf() { [[ -s $T/rastro ]]; }

# 1) macOS, sessão ssh (sem TMPDIR): o mesmo diretório do tmux/vigia, sem a barra final
r=$(rt_de Darwin "" "$T/usuario-tmp/")
[[ $r == "$T/usuario-tmp" ]] || fail "macOS sem TMPDIR deveria usar o DARWIN_USER_TEMP_DIR; veio '$r'"
chamou_getconf || fail "o getconf deveria ter sido consultado"
echo "ok: macOS sem TMPDIR (ssh) usa o diretório temporário do usuário"

# 2) macOS, tmux/GUI (com TMPDIR): fica como sempre foi e nenhum processo extra roda
r=$(rt_de Darwin "$T/gui-tmp/" "$T/usuario-tmp/")
[[ $r == "$T/gui-tmp/" ]] || fail "com TMPDIR o RT deveria ser o TMPDIR de sempre; veio '$r'"
chamou_getconf && fail "com TMPDIR não pode chamar o getconf (custo em toda partida)"
echo "ok: macOS com TMPDIR mantém o TMPDIR e não chama o getconf"

# 3) o ssh e o tmux enxergam o MESMO pidfile do vigia (o bug original)
ssh_rt=$(rt_de Darwin "" "$T/usuario-tmp/")
tmux_rt=$(rt_de Darwin "$T/usuario-tmp/" "$T/usuario-tmp/")
[[ ${ssh_rt%/}/tt-vigia-1.pid == ${tmux_rt%/}/tt-vigia-1.pid ]] || fail "ssh ($ssh_rt) e tmux ($tmux_rt) apontam pastas diferentes"
echo "ok: ssh e tmux compartilham o pidfile do vigia"

# 4) Linux/Termux sem /run/user e sem TMPDIR: /tmp como antes, sem getconf
r=$(rt_de Linux "" "$T/usuario-tmp/")
[[ $r == /tmp ]] || fail "fora do macOS o RT sem TMPDIR deveria ser /tmp; veio '$r'"
chamou_getconf && fail "fora do macOS não pode consultar o getconf"
echo "ok: fora do macOS nada muda"

# 5) macOS com getconf inútil (diretório que não existe ou vazio): cai em /tmp, nunca num caminho inexistente
r=$(rt_de Darwin "" "$T/nao-existe/")
[[ $r == /tmp ]] || fail "getconf com diretório inexistente deveria cair em /tmp; veio '$r'"
r=$(rt_de Darwin "" "")
[[ $r == /tmp ]] || fail "getconf vazio deveria cair em /tmp; veio '$r'"
echo "ok: getconf inútil cai em /tmp"

# 6) a chamada fica só no caminho sem /run/user e o TT_RT explícito continua mandando
grep -q '|| rt_sem_run_user$' "$TT" || fail "o tt deveria chamar rt_sem_run_user só quando /run/user falta"
r=$(cd / && TT_COMPLETO=1 TT_SO_CARREGAR=1 TT_RT="$T/rt" bash -c 'source "$1/tt"; printf "%s" "$RT"' _ "$TT_DIR")
[[ $r == "$T/rt" ]] || fail "TT_RT explícito deveria vencer; veio '$r'"
echo "ok: TT_RT explícito continua mandando"
echo "TODOS OS TESTES PASSARAM"
