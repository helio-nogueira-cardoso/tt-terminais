#!/usr/bin/env bash
# Pendência email-espelho: conta IMAP sem sync local vira pendência (recurso, com o mbsync como pré-requisito);
# aceitar liga o sync_local; "não instalar" não vale para ela (vira "mais tarde" e volta em 1 dia); sem conta
# ou com todas espelhadas, não aparece; o vigia avisa.
source "$(dirname "$0")/lib.sh"; isolar
B=$T/bin; mkdir -p "$B" "$HOME/.config/tt/email"
cat >"$B/apt-get" <<'EOF'
#!/bin/sh
case "$*" in *install*) echo "$*" >> "$SUDOLOG";; esac
exit 0
EOF
printf '#!/bin/sh\nexec "$@"\n' >"$B/sudo"
printf '#!/bin/sh\necho "  Candidate: 1.0"\n' >"$B/apt-cache"
for f in aerc vim w3m mbsync; do printf '#!/bin/sh\n:\n' >"$B/$f"; done
chmod +x "$B"/*
export SUDOLOG=$T/sudo.log TT_GERENCIADOR=apt-get TT_PRIV=sudo TT_SO=linux TT_AMBIENTE=nativo TT_EMAIL_SEM_REDE=1
ES=$HOME/.local/state/tt
conta() { printf 'nome=%s\nendereco=%s@y.z\nauth=senha\nimap_host=imap.y.z\nimap_porta=993\nsmtp_host=smtp.y.z\nsmtp_porta=465\n%s' "$1" "$1" "${2:-}" >"$HOME/.config/tt/email/$1.conf"; }
roda() { PATH="$B:$PATH" TT_TTY="$T/resposta" "$TT" --pedir-sudo "$@" 2>&1; }
estado() { PATH="$B:$PATH" "$TT" --pendencias --tsv 2>/dev/null | awk -F'\t' '$1 == "email-espelho" { print $2 }'; }
limpar() { rm -f "$ES"/sudo-recusado-* "$ES"/pendencias-avisadas; rm -rf "$ES/pendencias.trava" "$ES/notifs"; }

# 1) Sem conta: não se aplica. Conta já espelhada: ok.
[[ $(estado) == na ]] || falhou "sem conta a pendência deveria ser na, foi [$(estado)]"
conta a $'sync_local=1\n'
[[ $(estado) == na ]] || falhou "com todas as contas espelhadas deveria ser na, foi [$(estado)]"
passou 'sem conta, ou com todas espelhadas, a pendência não aparece'

# 2) Conta sem espelho: falta, com o nome da conta no rótulo; sem mbsync, o mbsync entra no comando.
conta b
[[ $(estado) == falta ]] || falhou "conta sem espelho deveria gerar a pendência, veio [$(estado)]"
printf m >"$T/resposta"; saida=$(PATH="$B:$PATH" TT_TTY="$T/resposta" TT_FINGE_FALTA="mbsync" "$TT" --pedir-sudo 2>&1) || true
grep -q 'espelho local do e-mail (b)' <<<"$saida" || falhou "rótulo sem a conta: $saida"
grep -q 'isync' <<<"$saida" || falhou "sem mbsync, o comando deveria instalar o isync: $saida"
grep -q 'não pode ser recusado de vez' <<<"$saida" || falhou "o modal deveria avisar que não aceita nunca: $saida"
passou 'conta IMAP sem espelho vira pendência, com o mbsync como pré-requisito e o aviso de obrigatória'

# 3) "Não instalar" vale como "mais tarde": não grava nunca, some hoje e volta depois de 1 dia.
limpar; printf n >"$T/resposta"; roda >/dev/null || true
v=$(cat "$ES/sudo-recusado-email-espelho" 2>/dev/null)
[[ $v =~ ^[0-9]+$ ]] || falhou "\"não\" deveria gravar uma hora (mais tarde), gravou [$v]"
grep -q 'espelho local' <<<"$(printf m >"$T/resposta"; roda)" && falhou 'adiado voltou na hora'
echo $(( v - 90000 )) >"$ES/sudo-recusado-email-espelho"
grep -q 'espelho local' <<<"$(printf m >"$T/resposta"; roda)" || falhou 'depois de 1 dia deveria perguntar de novo'
echo nunca >"$ES/sudo-recusado-email-espelho"   # recusa antiga ou gravada à mão também não cala a pergunta
grep -q 'espelho local' <<<"$(printf m >"$T/resposta"; roda)" || falhou '"nunca" gravado não pode calar a pendência obrigatória'
passou '"não instalar" vira "mais tarde": volta em 1 dia, e um "nunca" antigo não cala'

# 4) O vigia avisa (é recurso).
limpar
PATH="$B:$PATH" "$TT" --pendencias-avisar
grep -qs 'espelho local' "$ES"/notifs/* || falhou "o vigia não avisou: $(cat "$ES"/notifs/* 2>/dev/null)"
passou 'o vigia avisa da pendência'

# 5) Aceitar liga o sync local da conta (e só das que faltavam); a pendência some.
limpar; printf i >"$T/resposta"; saida=$(roda) || true
grep -qx 'sync_local=1' "$HOME/.config/tt/email/b.conf" || falhou "aceitar não ligou o espelho: $saida"
grep -qx 'sync_local=1' "$HOME/.config/tt/email/a.conf" || falhou 'mexeu na conta que já estava espelhada'
[[ $(estado) == na ]] || falhou "depois de ligar a pendência deveria sumir, veio [$(estado)]"
passou 'aceitar liga o espelho das contas que faltavam e a pendência some'

# 5b) Conta OAuth ainda sem token (o login não terminou) não vira pendência: ligar o espelho dela só daria erro de login.
conta c $'auth=oauth\n'
[[ $(estado) == na ]] || falhou "conta OAuth sem token não deveria ser pendência, veio [$(estado)]"
rm -f "$HOME/.config/tt/email/c.conf"
passou 'conta OAuth sem token não vira pendência do espelho'

# 6) Conta espelhada (maildir) tem check-mail-cmd no aerc: sem ele o :check-mail (F11, ⟳, abrir pelo aviso)
#    respondia "no command specified". Conta antiga sem a linha é regravada pela migração da instalação.
A=$HOME/.config/aerc/accounts.conf
bloco() { awk -v a="# >>> tt e-mail: $1 >>>" -v z="# <<< tt e-mail: $1 <<<" '$0 == a { d = 1 } d; $0 == z { d = 0 }' "$A"; }
grep -qx "check-mail-cmd    = $HOME/.local/bin/tt --email-sync b" <<<"$(bloco b)" || falhou "conta espelhada sem check-mail-cmd: $(bloco b)"
grep -qx 'check-mail        = 2m' <<<"$(bloco b)" || falhou "conta espelhada sem intervalo de atualização: $(bloco b)"
grep -q '^check-mail-timeout' <<<"$(bloco b)" || falhou 'sem check-mail-timeout (o mbsync passa dos 10 s padrão)'
sed -i '/^check-mail[[:space:]]*=/d' "$A"
PATH="$B:$PATH" TT_COMPLETO=1 bash -c 'TT_SO_CARREGAR=1 source "$1"; email_checkmail_migrar' _ "$TT"
grep -qx "check-mail-cmd    = $HOME/.local/bin/tt --email-sync b" <<<"$(bloco b)" || falhou "a migração não regravou a conta antiga: $(bloco b)"
grep -qx 'check-mail        = 2m' <<<"$(bloco b)" || falhou "a migração não ativou a atualização automática: $(bloco b)"
passou 'conta espelhada ganha check-mail automático no aerc, e a migração conserta as antigas'
