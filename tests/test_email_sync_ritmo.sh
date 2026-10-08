#!/usr/bin/env bash
# Ritmo e aviso do sync local de e-mail (o 📧 ficava vermelho o dia todo na empresa): o .mbsyncrc
# sem "Timeout 60" é regravado (no padrão de 20 s o login lento do Gmail estourava); rodada que acha
# a trava ocupada pela volta completa fica registrada como "pulada" e não vira "parado"; depois de
# um erro o vigia espera (2×, 4×… o intervalo, até 15 min) e à mão sincroniza na hora; "erro" só
# com 3 falhas seguidas, mais de 10 min sem INBOX bom ou senha recusada; "parado" usa o intervalo
# em uso pelo vigia e ignora rodada em andamento e a espera proposital. Isola HOME/XDG; mbsync falso.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"
cat >"$T/bin/mbsync" <<MB
#!/bin/sh
echo "\$@" >>"$T/mbsync.calls"
[ -n "\$MBSYNC_DORME" ] && sleep "\$MBSYNC_DORME"
[ -n "\$MBSYNC_ERR" ] && echo "\$MBSYNC_ERR" >&2
exit \${MBSYNC_RC:-0}
MB
chmod +x "$T/bin"/*
export PATH="$T/bin:/usr/bin:/bin"
echo 'SENHA' | "$TT" --email-adicionar nome=Local endereco=eu@gmail.com provedor=gmail auth=senha sync_local=1 --senha-stdin >/dev/null || falhou 'cadastro'
E=$HOME/.local/state/tt/email-sync; RC=$HOME/.config/tt/mbsync/local.mbsyncrc
curto() { "$TT" --email-sync-estado curto | awk -F'\t' '$1 == "local" { print $2 }'; }
linha() { printf '%s\t%s\t%s\t%s\n' "$@" >>"$E/local"; }
zera() { rm -f "$E"/local "$E"/local.*; }

# 1) rc em canais sem "Timeout" (gerado antes da v202) é regravado pela migração; com ele, fica
grep -q '^Timeout 60$' "$RC" || falhou 'rc novo deveria ter Timeout 60'
sed -i '/^Timeout /d' "$RC"
TT_EMAIL_SEM_REDE=1 "$TT" --email-mbsync-migrar >/dev/null
grep -q '^Timeout 60$' "$RC" || falhou 'migração não repôs o Timeout 60 num rc em canais'
grep -q '^Group local$' "$RC" || falhou 'migração estragou o rc'
passou 'migração repõe o "Timeout 60" que faltava em rc já em canais'

# 2) trava ocupada (volta completa em curso): a rodada do INBOX é "pulada", registrada, e não é parada
zera; : >"$T/mbsync.calls"
MBSYNC_DORME=3 "$TT" --email-sync Local --completo >/dev/null 2>&1 &
sleep 1; "$TT" --email-sync Local >/dev/null 2>&1; wait
grep -q '^pulada	' "$E/local" || falhou "rodada com a trava ocupada não ficou registrada: $(cat "$E/local")"
[[ $(grep -c . "$T/mbsync.calls") == 1 ]] || falhou "rodou o mbsync duas vezes ao mesmo tempo: $(cat "$T/mbsync.calls")"
passou 'INBOX com a trava ocupada pela volta completa fica registrado como "pulada"'

# 3) "parado": sem rodada há mais de 3 intervalos; a régua é o intervalo em uso pelo vigia
zera; agora=$(date +%s)
linha inbox $((agora - 700)) $((agora - 690)) 0
[[ $(curto) == parado ]] || falhou "sem rodada há 690 s com intervalo 120 deveria ser parado: $(curto)"
echo 300 >"$E/.intervalo"
[[ $(curto) == ok ]] || falhou "com o vigia em 300 s (ocioso), 690 s ainda não é parado: $(curto)"
linha pulada $((agora - 30)) $((agora - 30)) 0; echo 120 >"$E/.intervalo"
[[ $(curto) == ok ]] || falhou "rodada pulada há 30 s mostra que o sync está vivo: $(curto)"
zera; linha inbox $((agora - 900)) $((agora - 890)) 0; printf 'completo\t%s\n' $((agora - 200)) >"$E/local.andamento"
[[ $(curto) == ok ]] || falhou "volta completa em andamento não é parado: $(curto)"
printf 'completo\t%s\n' $((agora - 5000)) >"$E/local.andamento"
[[ $(curto) == parado ]] || falhou "andamento velho (processo que morreu) não pode esconder o parado: $(curto)"
rm -f "$E/local.andamento"; echo $((agora + 300)) >"$E/local.espera"
[[ $(curto) == ok ]] || falhou "espera proposital depois de erro não é parado: $(curto)"
rm -f "$E/.intervalo"
passou '"parado" usa o intervalo do vigia e ignora rodada pulada, em andamento e a espera proposital'

# 4) falha passageira = atrasado; 3 seguidas ou > 10 min sem INBOX bom = erro; senha recusada = erro já
zera; agora=$(date +%s)
linha inbox $((agora - 130)) $((agora - 125)) 0; linha inbox $((agora - 20)) $((agora - 2)) 1
echo 'Socket error on imap.gmail.com: timeout.' >"$E/local.erro"
[[ $(curto) == atrasado ]] || falhou "1 falha passageira deveria ser atrasado: $(curto)"
linha inbox $((agora - 1)) $((agora - 1)) 1; linha inbox $((agora - 1)) $((agora)) 1
[[ $(curto) == erro ]] || falhou "3 falhas seguidas deveriam ser erro: $(curto)"
zera; linha inbox $((agora - 700)) $((agora - 690)) 0; linha inbox $((agora - 20)) $((agora - 2)) 1
echo 'timeout' >"$E/local.erro"
[[ $(curto) == erro ]] || falhou "mais de 10 min sem INBOX bom deveria ser erro: $(curto)"
zera; linha inbox $((agora - 130)) $((agora - 125)) 0; linha completo $((agora - 60)) $((agora - 50)) 0; linha inbox $((agora - 20)) $((agora - 2)) 1
echo 'NO [AUTHENTICATIONFAILED] Invalid credentials (Failure)' >"$E/local.erro"
[[ $(curto) == erro ]] || falhou "senha recusada deveria ser erro já na 1ª: $(curto)"
zera; linha inbox $((agora - 130)) $((agora - 125)) 0; linha inbox $((agora - 60)) $((agora - 50)) 1; linha completo $((agora - 40)) $((agora - 5)) 0
echo 'timeout' >"$E/local.erro"
[[ $(curto) == ok ]] || falhou "volta completa boa depois do INBOX que falhou deveria limpar o atrasado: $(curto)"
passou 'falha passageira é "atrasado"; 3 seguidas, > 10 min ou senha recusada é "erro"'

# 5) espera depois de erro: o vigia (--vigia) respeita, à mão sincroniza já; sucesso zera
zera; : >"$T/mbsync.calls"
MBSYNC_RC=1 MBSYNC_ERR='timeout' "$TT" --email-sync Local >/dev/null 2>&1
esp=$(cat "$E/local.espera" 2>/dev/null); agora=$(date +%s)
[[ -n $esp ]] && ((esp - agora >= 200 && esp - agora <= 241)) || falhou "1ª falha deveria esperar 2× o intervalo (240 s): $((esp - agora))"
"$TT" --email-sync --vigia >/dev/null 2>&1
[[ $(grep -c . "$T/mbsync.calls") == 1 ]] || falhou "o vigia não respeitou a espera: $(cat "$T/mbsync.calls")"
for i in 2 3 4 5; do MBSYNC_RC=1 MBSYNC_ERR='timeout' "$TT" --email-sync Local >/dev/null 2>&1; done
esp=$(cat "$E/local.espera"); agora=$(date +%s)
((esp - agora <= 900 && esp - agora >= 880)) || falhou "a espera tem teto de 15 min: $((esp - agora))"
grep -q 'tenta de novo em' <<<"$("$TT" --email-sync-estado)" || falhou "estado longo deveria contar a espera: $("$TT" --email-sync-estado)"
"$TT" --email-sync Local >/dev/null 2>&1
[[ ! -e $E/local.espera && ! -e $E/local.falhas ]] || falhou 'rodada boa deveria zerar a espera'
"$TT" --email-sync --vigia >/dev/null 2>&1
[[ $(grep -c . "$T/mbsync.calls") == 7 ]] || falhou "depois do sucesso o vigia volta ao ritmo normal: $(grep -c . "$T/mbsync.calls")"
zera; MBSYNC_DORME=3 TT_EMAIL_SYNC_TETO=1 "$TT" --email-sync Local --completo >/dev/null 2>&1
[[ ! -e $E/local.espera ]] || falhou 'volta completa que só estourou o teto não deveria pôr o INBOX em espera'
grep -q 'tempo esgotado' "$E/local.erro" || falhou "o tempo esgotado da completa deveria ficar registrado: $(cat "$E/local.erro" 2>/dev/null)"
passou 'depois de erro o vigia espera (2×, 4×… até 15 min); à mão sincroniza já; sucesso zera'

# 6) ligações do vigia: completa ao iniciar só se a última for velha; intervalo ocioso; --vigia
corpo=$(sed -n '/^vigiar()/,/^}/p' "$TT_DIR/tt")
grep -q 'ultima_email_completo=$(email_ultima_completa)' <<<"$corpo" || falhou 'vigia não parte da última volta completa registrada'
grep -q 'cliente_ativo_desde' <<<"$corpo" && grep -q 'TT_EMAIL_SYNC_OCIOSO' <<<"$corpo" || falhou 'vigia sem o intervalo ocioso'
grep -q -- '--email-sync --completo --vigia' <<<"$corpo" && grep -q -- '--email-sync --vigia' <<<"$corpo" || falhou 'vigia não pede o sync como vigia (espera depois de erro)'
passou 'vigia: volta completa ao iniciar só se a última for velha, intervalo ocioso, respeita a espera'

echo "TODOS OS TESTES PASSARAM"
