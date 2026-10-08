#!/usr/bin/env bash
# v138: aerc_reparar_se_preciso regrava SO o filtro text/html quando ele renderiza HTML vazio.
# Nao chama configurar_aerc (nao toca binds/tema). Hermetico: shim de command -v decide ferramentas.
set -u
raiz=$(cd "$(dirname "$0")/.." && pwd)
falhas=0
ok()   { echo "  ok: $1"; }
erro() { echo "  ERRO: $1"; falhas=$((falhas+1)); }

TH=$(mktemp -d); trap 'rm -rf "$TH"' EXIT
export HOME="$TH"
mkdir -p "$HOME/.config/aerc" "$TH/bin"
BIN="$TH/bin"
DIR_TT="$TH/dirtt"; mkdir -p "$DIR_TT"

command() {
  if [[ ${1:-} == -v ]]; then
    case ${2:-} in
      w3m|lynx|aerc) [[ -x "$BIN/${2}" ]] && { echo "$BIN/${2}"; return 0; } || return 1 ;;
    esac
  fi
  builtin command "$@"
}

aerc_filtro_html() {
  if command -v w3m >/dev/null; then echo '! html'
  elif command -v lynx >/dev/null; then echo 'lynx -assume_charset=utf-8 -display_charset=utf-8 -dump -force_html -stdin -width=100 | colorize'
  else echo "python3 $DIR_TT/email-tt.py html | colorize"; fi
}

aerc_definir() {
  local f=$1 sec=$2 k=$3 v=$4 forcar=${5:-} tmp
  [[ -f $f ]] || : >"$f"
  tmp=$(mktemp) || return 1
  awk -v S="$sec" -v K="$k" -v V="$v" -v F="$forcar" '
    function poe() { if (!feito) { print K "=" V; feito = 1 } }
    /^\[.*\]/ { if (sec == S) poe(); sec = $0; gsub(/^\[|\].*$/, "", sec); print; next }
    sec == S && $0 ~ "^[[:space:]]*" K "[[:space:]]*=" { if (F != "") { poe() } else { print; feito = 1 } next }
    { print }
    END { if (sec == S) poe(); if (!feito) { print ""; print "[" S "]"; print K "=" V } }' "$f" >"$tmp"
  cmp -s "$tmp" "$f" || cat "$tmp" >"$f"; rm -f "$tmp"
}

aerc_reparar_se_preciso() {
  command -v aerc >/dev/null || return 0
  local conf="$HOME/.config/aerc/aerc.conf"
  [[ -f $conf ]] || return 0
  local linha_html
  linha_html=$(grep -E '^[[:space:]]*text/html[[:space:]]*=' "$conf" 2>/dev/null | tail -1)
  if [[ -z $linha_html ]] ||
     { [[ $linha_html =~ ^[[:space:]]*text/html[[:space:]]*=[[:space:]]*!*[[:space:]]*html[[:space:]]*$ ]] && ! command -v w3m >/dev/null; } ||
     { [[ $linha_html == *lynx* ]] && ! command -v lynx >/dev/null; } ||
     { [[ $linha_html == *w3m* ]] && ! command -v w3m >/dev/null; }; then
    aerc_definir "$conf" filters text/html "$(aerc_filtro_html)" forcar
  fi
  return 0
}

mk()  { printf '#!/bin/sh\nexit 0\n' > "$BIN/$1"; chmod +x "$BIN/$1"; }
rmk() { rm -f "$BIN/$1"; }
filtro_atual() { grep -E '^[[:space:]]*text/html[[:space:]]*=' "$HOME/.config/aerc/aerc.conf" | tail -1 | sed 's/^text\/html=//'; }

mk aerc; rmk w3m; rmk lynx
conf="$HOME/.config/aerc/aerc.conf"

rm -f "$conf"; aerc_reparar_se_preciso
[[ ! -f $conf ]] && ok "sem aerc.conf: nao cria nada (deixa p/ cadastro)" || erro "criou aerc.conf indevido"

printf '[filters]\ntext/html=! html\n[messages]\nq = :quit<Enter>\n' > "$conf"
aerc_reparar_se_preciso
f=$(filtro_atual)
[[ $f == *email-tt.py* ]] && ok "'! html' sem w3m: filtro regravado p/ fallback ($f)" || erro "filtro nao reparado: $f"
grep -q '^q = :quit<Enter>$' "$conf" && ok "binds/outras secoes intactas (q preservado)" || erro "reparo mexeu em binds"

mk lynx
printf '[filters]\ntext/html=! html\n' > "$conf"; aerc_reparar_se_preciso
[[ $(filtro_atual) == lynx* ]] && ok "com lynx: filtro usa lynx" || erro "nao usou lynx"
rmk lynx

mk w3m
printf '[filters]\ntext/html=! html\n' > "$conf"; before=$(cat "$conf"); aerc_reparar_se_preciso
[[ $(cat "$conf") == "$before" ]] && ok "'! html' com w3m: nao mexe" || erro "reescreveu a toa com w3m"

# Funções REAIS do tt (as cópias acima são antigas): filtro w3m sem extbrowser (Enter num link dava
# "Can't load" com a URL cortada) migra para abrir o link no navegador; idempotente depois.
eval "$(sed -n '/^aerc_filtro_html() {/,/^}/p;/^aerc_reparar_se_preciso() {/,/^}/p' "$raiz/tt")"
mk w3m
printf '[filters]\ntext/html=! html | colorize | python3 /x/email-tt.py linkify\n' > "$conf"; aerc_reparar_se_preciso
f=$(filtro_atual)
[[ $f == *"extbrowser='"*"--abrir-url %s'"* && $f == *keymap_file=* ]] && ok "filtro w3m antigo migrado p/ abrir link no navegador" || erro "filtro nao migrou: $f"
grep -q 'C-m EXTERN_LINK' "$DIR_TT/w3m-keymap" 2>/dev/null && ok "keymap do w3m: Enter abre o link no navegador" || erro "keymap do w3m ausente"
before=$(cat "$conf"); aerc_reparar_se_preciso
[[ $(cat "$conf") == "$before" ]] && ok "filtro w3m novo: idempotente" || erro "reescreveu filtro w3m novo"

corpo_botao=$(sed -n '/^botao_email()/,/^}/p' "$raiz/tt")
grep -q 'aerc_reparar_se_preciso' <<<"$corpo_botao" &&
  grep -q 'kill-session.*EMAIL_SESSAO' <<<"$corpo_botao" &&
  ok "reparo reinicia a sessão oculta para carregar o filtro" ||
  erro "botao_email não reinicia a sessão após reparar"

echo
if ((falhas==0)); then echo "TODOS OS TESTES PASSARAM"; else echo "$falhas FALHA(S)"; fi
exit $falhas
