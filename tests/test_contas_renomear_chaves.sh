#!/usr/bin/env bash
# macOS: o login de um perfil fica no Chaves, num item com o hash da pasta no nome. O ia-conta renomear move o item
# junto com a pasta (antes o perfil renomeado ficava sem login e o item velho, órfão); o segredo nunca vai para a
# linha de comando; com o Chaves trancado (ssh) recusa sem mexer em nada. uname e security são falsos.
source "$(dirname "$0")/lib.sh"
isolar
B=$HOME/.local/bin R=$HOME/.local/share/claude-contas
mkdir -p "$B" "$HOME/.claude" "$R" "$HOME/.cache"
printf '#!/usr/bin/env bash\nexit 1\n' >"$B/claude"
chmod +x "$B/claude"
export PATH=$B:$PATH
instalar_isolado

# Chaves falso: um arquivo por item em $HOME/chaves (o segredo e, em .acct, a conta). Registra os argumentos de
# cada chamada; $HOME/trancado faz a leitura do segredo falhar, como por ssh.
F=$T/falsos; C=$HOME/chaves K=$HOME/Library/Keychains/login.keychain-db
mkdir -p "$F" "$C" "${K%/*}"; : >"$K"
printf '#!/bin/sh\necho Darwin\n' >"$F/uname"
cat >"$F/security" <<'EOF'
#!/usr/bin/env bash
C=$HOME/chaves K=$HOME/Library/Keychains/login.keychain-db
printf '%s\n' "$*" >>"$HOME/security.argv"
case $1 in
  find-generic-password)
    [[ $2 == -s && -s $C/$3 ]] || exit 44
    if [[ $4 == -w ]]; then
      [[ $5 == "$K" && ! -e $HOME/trancado ]] || exit 36
      cat "$C/$3"; echo
    else
      [[ $4 == "$K" ]] || exit 44
      printf 'keychain: "%s"\nattributes:\n    "acct"<blob>="%s"\n    "svce"<blob>="%s"\n' "$K" "$(cat "$C/$3.acct")" "$3"
    fi ;;
  delete-generic-password) [[ $2 == -s && $4 == "$K" && -e $C/$3 ]] || exit 44; rm -f "$C/$3" "$C/$3.acct" ;;
  -i)
    while IFS= read -r linha; do
      eval "set -- $linha"
      [[ $1 == add-generic-password ]] || exit 1; shift
      a='' s='' x='' k=''
      while (($#)); do
        case $1 in -U) shift ;; -a) a=$2; shift 2 ;; -s) s=$2; shift 2 ;; -X) x=$2; shift 2 ;; *) k=$1; shift ;; esac
      done
      [[ $k == "$K" ]] || exit 1
      python3 -c 'import sys; sys.stdout.buffer.write(bytes.fromhex(sys.argv[1]))' "$x" >"$C/$s"
      printf '%s' "$a" >"$C/$s.acct"
    done ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$F/uname" "$F/security"
export PATH=$F:$PATH
h() { python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:8])' "$1"; }
segredo='{"claudeAiOauth":{"accessToken":"segredo-do-teste x\"y","expiresAt":4102444800000}}'
mkdir -p "$R/velho"; echo 'velho@x.com' >"$R/velho/.account-email"
printf '%s' "$segredo" >"$C/Claude Code-credentials-$(h "$R/velho")"; printf 'eu' >"$C/Claude Code-credentials-$(h "$R/velho").acct"

# Chaves trancado: recusa e não move nada.
touch "$HOME/trancado"
ia-conta renomear velho novo >/dev/null 2>&1 && falhou 'renomeou sem conseguir mover o login do Chaves'
[[ -d $R/velho && ! -e $R/novo ]] || falhou 'Chaves trancado: a pasta foi movida mesmo assim'
[[ -s "$C/Claude Code-credentials-$(h "$R/velho")" ]] || falhou 'Chaves trancado: o item velho sumiu'
[[ -e "$C/Claude Code-credentials-$(h "$R/novo")" ]] && falhou 'Chaves trancado: sobrou item com o nome novo'
passou 'Chaves trancado (ssh): recusa sem mover a pasta nem o login'

rm -f "$HOME/trancado" "$HOME/security.argv"
out=$(ia-conta renomear velho novo 2>&1) || falhou "renomear falhou: $out"
[[ -d $R/novo && ! -e $R/velho ]] || falhou 'a pasta não foi renomeada'
[[ $(cat "$C/Claude Code-credentials-$(h "$R/novo")" 2>/dev/null) == "$segredo" ]] || falhou 'o login não foi para o item da pasta nova'
[[ $(cat "$C/Claude Code-credentials-$(h "$R/novo").acct" 2>/dev/null) == eu ]] || falhou 'o item novo perdeu a conta (acct)'
[[ -e "$C/Claude Code-credentials-$(h "$R/velho")" ]] && falhou 'o item velho ficou órfão no Chaves'
grep -Eq '^novo .*velho@x\.com' <<<"$(ia-conta listar --rapido)" || falhou 'o perfil renomeado não aparece conectado'
passou 'macOS: renomear leva o login do Chaves para o nome da pasta nova e apaga o velho'

hex=$(printf '%s' "$segredo" | python3 -c 'import sys; print(sys.stdin.buffer.read().hex())')
grep -qF -e 'segredo-do-teste' -e "$hex" "$HOME/security.argv" && falhou 'o segredo passou pela linha de comando do security'
passou 'o segredo vai de um security a outro sem passar pela linha de comando'
