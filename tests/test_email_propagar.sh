#!/usr/bin/env bash
# tt --email-propagar / --email-receber: propaga uma conta de e-mail (configuração + senha/token)
# para as outras máquinas, só por comando ou pergunta, por ssh direto e transacional. Sem rede: o
# ssh é falso e roda o comando remoto aqui mesmo, num segundo HOME ("a outra máquina"); o tt de lá
# é o mesmo pacote. Cobre: sonda antes do segredo (tt antigo não recebe nada), segredo nunca na
# linha de comando, chegada com 600 e bloco do aerc regerado, sync_local sem mbsync chega
# desligado, conta existente só com --sobrescrever, pacote estranho recusado sem resíduo,
# pergunta no fim do cadastro, propagar=1 na CLI e o seletor da tela da conta.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"
# mbsync falso (só --version) para a origem aceitar sync_local=1.
printf '#!/bin/sh\necho "isync 1.4.4"\n' >"$T/bin/mbsync"; chmod +x "$T/bin/mbsync"
export PATH=$T/bin:$PATH

# A "outra máquina": HOME separado, com o mesmo tt instalado em ~/.local/bin/tt.
D=$T/dest; mkdir -p "$D/.local/bin" "$D/.config/tt"; ln -s "$TT" "$D/.local/bin/tt"
export DEST=$D
# ssh falso: ignora opções e host; o último argumento é o comando remoto, que roda no HOME de lá
# (TT_MBSYNC inexistente por padrão: lá não há mbsync). Registra os argumentos para conferir que o
# segredo nunca vai na linha de comando. MODO_SSH=antigo imita um tt sem --email-receber;
# MODO_SSH=fora, uma máquina que não responde.
B=$HOME/.local/bin
cat >"$B/ssh" <<'EOF'
#!/usr/bin/env bash
cmd=${*: -1}
printf '%s\n' "$*" >>"$SSH_LOG"
case ${MODO_SSH:-} in
  antigo) echo "tt: opção desconhecida: --email-receber (tt --help mostra as principais)" >&2; exit 2 ;;
  fora) echo "ssh: connect to host x port 22: No route to host" >&2; exit 255 ;;
esac
[[ $cmd == *--sonda* ]] || cat >"$ENVIADO"
exec env HOME="$DEST" XDG_CONFIG_HOME="$DEST/.config" XDG_STATE_HOME="$DEST/.local/state" \
  TT_MBSYNC="${DEST_MBSYNC:-/nonexistent/mbsync}" bash -c "$cmd" <"$ENVIADO"
EOF
chmod +x "$B/ssh"
export SSH_LOG=$T/ssh.log ENVIADO=$T/enviado.tar; : >"$ENVIADO"
printf 'destino-host helio alvo1\n' >"$XDG_CONFIG_HOME/tt/maquinas"

# Conta de origem, com senha.
echo 'SENHA_FICT_P' | "$TT" --email-adicionar nome=Pessoal endereco=eu@gmail.com provedor=gmail auth=senha --senha-stdin >/dev/null || falhou 'cadastro'

# --- propagar: sonda, pacote mínimo, chegada com 600 e bloco do aerc ------------------------------
out=$("$TT" --email-propagar Pessoal 2>&1) || falhou "propagar falhou: $out"
grep -q "alvo1 .*✓ conta 'Pessoal' instalada" <<<"$out" || falhou "sem confirmação da chegada: $out"
grep -q -- '--email-receber pessoal *--sonda' "$SSH_LOG" || falhou "não sondou o tt de lá antes de mandar: $(cat "$SSH_LOG")"
grep -q 'SENHA_FICT_P' "$SSH_LOG" && falhou 'a senha foi na linha de comando do ssh'
lista=$(tar -tf "$ENVIADO")
[[ $lista == $'pessoal.conf\naerc-pessoal.txt' ]] || falhou "pacote deveria ter só conf + senha: $lista"
[[ $(cat "$D/.secrets/aerc-pessoal.txt") == SENHA_FICT_P ]] || falhou 'senha não chegou'
[[ $(stat -c %a "$D/.secrets/aerc-pessoal.txt") == 600 ]] || falhou 'senha lá não está 600'
grep -q '^endereco=eu@gmail.com$' "$D/.config/tt/email/pessoal.conf" || falhou 'conf não chegou'
grep -q '^# >>> tt e-mail: pessoal >>>$' "$D/.config/aerc/accounts.conf" || falhou 'bloco do aerc não foi regerado lá'
grep -q '^source *= imaps://eu%40gmail.com@imap.gmail.com:993$' "$D/.config/aerc/accounts.conf" || falhou 'URL IMAP errada lá'
grep -q 'SENHA_FICT_P' "$D/.config/aerc/accounts.conf" && falhou 'segredo vazou para o accounts.conf de lá'
passou 'propagar: sonda o tt de lá, manda só conf + segredo pelo stdin do ssh; chega com 600 e bloco do aerc regerado'

# --- já existe lá: sem --sobrescrever nada muda; com ele, substitui --------------------------------
: >"$SSH_LOG"; : >"$ENVIADO"
set +e; out=$("$TT" --email-propagar Pessoal 2>&1 </dev/null); rc=$?; set -e
((rc != 0)) || falhou 'já existente deveria devolver erro sem --sobrescrever'
grep -q 'já existe lá' <<<"$out" || falhou "deveria avisar que já existe: $out"
[[ -s $ENVIADO ]] && falhou 'mandou o pacote mesmo com a conta já existente'
echo 'SENHA_NOVA_P' >"$HOME/.secrets/aerc-pessoal.txt"
out=$("$TT" --email-propagar Pessoal --sobrescrever 2>&1) || falhou "sobrescrever falhou: $out"
grep -q "✓ conta 'Pessoal' substituída" <<<"$out" || falhou "sem confirmação da substituição: $out"
[[ $(cat "$D/.secrets/aerc-pessoal.txt") == SENHA_NOVA_P ]] || falhou 'senha nova não chegou'
[[ $(grep -c '^# >>> tt e-mail: pessoal >>>$' "$D/.config/aerc/accounts.conf") == 1 ]] || falhou 'substituir duplicou o bloco'
passou 'conta já existente lá: fica como está sem --sobrescrever; com ele é substituída (bloco único)'

# --- tt antigo lá: nada é enviado; máquina fora: sem resposta ------------------------------------
: >"$SSH_LOG"; : >"$ENVIADO"
set +e; out=$(MODO_SSH=antigo "$TT" --email-propagar Pessoal --sobrescrever 2>&1); set -e
grep -q 'não sabe receber' <<<"$out" || falhou "tt antigo deveria pedir atualização: $out"
[[ -s $ENVIADO ]] && falhou 'mandou o segredo para um tt que não sabe receber'
set +e; out=$(MODO_SSH=fora "$TT" --email-propagar Pessoal --sobrescrever 2>&1); set -e
grep -q 'sem resposta' <<<"$out" || falhou "máquina fora deveria dar sem resposta: $out"
set +e; out=$("$TT" --email-propagar Pessoal naoexiste 2>&1); rc=$?; set -e
((rc != 0)) && grep -q 'naoexiste .*não está cadastrada' <<<"$out" || falhou "máquina desconhecida: $out"
set +e; out=$("$TT" --email-propagar NaoCadastrada 2>&1); rc=$?; set -e
((rc != 0)) && grep -q 'Conta não encontrada' <<<"$out" || falhou "conta inexistente: $out"
passou 'tt antigo lá não recebe o segredo (pede atualizar); máquina fora, rótulo e conta desconhecidos dão erro legível'

# --- sync_local=1 numa máquina sem mbsync chega desligado; com mbsync, chega ligado ---------------
echo 'SENHA_S' | "$TT" --email-adicionar nome=Espelho endereco=esp@gmail.com provedor=gmail auth=senha sync_local=1 --senha-stdin >/dev/null || falhou 'cadastro com sync'
out=$("$TT" --email-propagar Espelho 2>&1) || falhou "propagar espelho: $out"
grep -q 'sync local desligado: sem mbsync' <<<"$out" || falhou "deveria avisar sem mbsync lá: $out"
grep -q '^sync_local=1$' "$D/.config/tt/email/espelho.conf" && falhou 'sync_local=1 ficou ligado onde não há mbsync'
[[ -e $D/.config/tt/mbsync/espelho.mbsyncrc ]] && falhou 'gerou .mbsyncrc onde não há mbsync'
grep -q '^source *= imaps://' "$D/.config/aerc/accounts.conf" || falhou 'lá a conta deveria ler direto do IMAP'
out=$(DEST_MBSYNC=$T/bin/mbsync "$TT" --email-propagar Espelho --sobrescrever 2>&1) || falhou "propagar espelho com mbsync: $out"
grep -q 'sem mbsync' <<<"$out" && falhou "com mbsync lá não deveria avisar: $out"
grep -q '^sync_local=1$' "$D/.config/tt/email/espelho.conf" || falhou 'sync_local não chegou ligado onde há mbsync'
[[ -s $D/.config/tt/mbsync/espelho.mbsyncrc ]] || falhou '.mbsyncrc não foi gerado lá'
grep -q 'SENHA_S' "$D/.config/tt/mbsync/espelho.mbsyncrc" && falhou 'segredo no .mbsyncrc de lá'
passou 'sync_local=1 chega desligado (com aviso) onde não há mbsync, e ligado, com .mbsyncrc sem segredo, onde há'

# --- receber: pacote estranho recusado sem resíduo; conta existente intacta ----------------------
rc_em_dest() { HOME=$D XDG_CONFIG_HOME=$D/.config XDG_STATE_HOME=$D/.local/state TT_MBSYNC=/nonexistent/mbsync "$TT" "$@"; }
sonda=$(rc_em_dest --email-receber pessoal --sonda </dev/null)
[[ $sonda == 'pronto existe=1 mbsync=0' ]] || falhou "sonda: $sonda"
sonda=$(rc_em_dest --email-receber outra --sonda </dev/null)
[[ $sonda == 'pronto existe=0 mbsync=0' ]] || falhou "sonda de conta nova: $sonda"
# Membro fora da raiz (../) ou com nome inesperado.
mkdir -p "$T/mal/sub"; printf 'nome=Mal\n' >"$T/mal/sub/mal.conf"; printf 'x' >"$T/mal/sub/evil"
tar -C "$T/mal" -cf "$T/mal.tar" sub/mal.conf sub/evil
set +e; out=$(rc_em_dest --email-receber mal <"$T/mal.tar" 2>&1); rc=$?; set -e
((rc != 0)) && grep -q 'conteúdo inesperado' <<<"$out" || falhou "pacote estranho: $out"
[[ -e $D/.config/tt/email/mal.conf ]] && falhou 'pacote estranho deixou conf'
# Sem senha para auth=senha: recusa antes de tocar em qualquer arquivo.
mkdir -p "$T/semsenha"; cp "$HOME/.config/tt/email/pessoal.conf" "$T/semsenha/pessoal.conf"
tar -C "$T/semsenha" -cf "$T/semsenha.tar" pessoal.conf
antes=$(cat "$D/.secrets/aerc-pessoal.txt")
set +e; out=$(rc_em_dest --email-receber pessoal --sobrescrever <"$T/semsenha.tar" 2>&1); rc=$?; set -e
((rc != 0)) && grep -q 'sem a senha/token' <<<"$out" || falhou "pacote sem senha: $out"
[[ $(cat "$D/.secrets/aerc-pessoal.txt") == "$antes" ]] || falhou 'pacote recusado alterou a conta existente'
# Lixo em vez de tar.
set +e; out=$(printf 'lixo' | rc_em_dest --email-receber lixo 2>&1); rc=$?; set -e
((rc != 0)) && grep -q 'pacote inválido' <<<"$out" || falhou "lixo: $out"
[[ -e $D/.config/tt/email/lixo.conf ]] && falhou 'lixo deixou conf'
# Nome que colide com um bloco escrito à mão no accounts.conf de lá.
printf '\n[Manual]\nsource = imaps://m@x.com@mail.x.com:993\n' >>"$D/.config/aerc/accounts.conf"
echo 'S' | "$TT" --email-adicionar nome=Manual endereco=m@gmail.com provedor=gmail auth=senha --senha-stdin >/dev/null || falhou 'cadastro Manual'
set +e; out=$("$TT" --email-propagar Manual 2>&1); rc=$?; set -e
((rc != 0)) && grep -q 'Já existe uma conta "Manual"' <<<"$out" || falhou "colisão com bloco manual: $out"
[[ -e $D/.config/tt/email/manual.conf ]] && falhou 'colisão gravou a conta'
passou 'receber: sonda responde existe/mbsync; pacote estranho, sem senha, lixo ou nome colidente são recusados sem resíduo'

# --- fim do cadastro: a pergunta só aparece com máquinas; "s" propaga, "n" não ------------------
: >"$ENVIADO"
# (a linha vazia antes do "s" é a assinatura, pulada)
printf 'gmail\nnova@gmail.com\nNova\nsenha\nSENHA_N\nSENHA_N\n\ns\n' | "$TT" --email-conta-nova-ui >"$T/ui.out" 2>&1
grep -q 'Propagar esta conta para as máquinas da rede (alvo1)? (S/n)' "$T/ui.out" || falhou "pergunta de propagação ausente: $(cat "$T/ui.out")"
[[ $(cat "$D/.secrets/aerc-nova.txt" 2>/dev/null) == SENHA_N ]] || falhou 'cadastro com "s" não propagou'
: >"$ENVIADO"
printf 'gmail\noutra@gmail.com\nOutra\nsenha\nSENHA_O\nSENHA_O\n\nn\n' | "$TT" --email-conta-nova-ui >"$T/ui.out" 2>&1
[[ -e $D/.secrets/aerc-outra.txt ]] && falhou 'cadastro com "n" propagou'
[[ -s $ENVIADO ]] && falhou 'cadastro com "n" mandou pacote'
# Sem máquinas cadastradas: nem pergunta.
mv "$XDG_CONFIG_HOME/tt/maquinas" "$T/maquinas.bak"; : >"$XDG_CONFIG_HOME/tt/maquinas"; rm -f "$TT_RT/tt-maquinas-"*
printf 'gmail\nso@gmail.com\nSo\nsenha\nS\nS\n' | "$TT" --email-conta-nova-ui >"$T/ui.out" 2>&1
grep -q 'Propagar esta conta' "$T/ui.out" && falhou 'perguntou sem máquinas cadastradas'
mv "$T/maquinas.bak" "$XDG_CONFIG_HOME/tt/maquinas"; rm -f "$TT_RT/tt-maquinas-"*
passou 'cadastro guiado: pergunta "Propagar para as máquinas (…)? (S/n)" só com máquinas; s propaga, n não'

# --- CLI: propagar=1 (todas) e propagar=rótulo; a chave não fica no .conf -----------------------
echo 'SENHA_C' | "$TT" --email-adicionar nome=Cli endereco=cli@gmail.com provedor=gmail auth=senha propagar=1 --senha-stdin >"$T/cli.out" 2>&1 || falhou "cadastro propagar=1: $(cat "$T/cli.out")"
grep -q "✓ conta 'Cli' instalada" "$T/cli.out" || falhou "propagar=1 não propagou: $(cat "$T/cli.out")"
[[ $(cat "$D/.secrets/aerc-cli.txt") == SENHA_C ]] || falhou 'propagar=1: senha não chegou'
grep -q '^propagar=' "$HOME/.config/tt/email/cli.conf" && falhou 'propagar= ficou gravado no .conf'
grep -q '^propagar=' "$D/.config/tt/email/cli.conf" && falhou 'propagar= viajou no .conf'
echo 'SENHA_C2' | "$TT" --email-adicionar nome=Cli2 endereco=cli2@gmail.com provedor=gmail auth=senha propagar=alvo1 --senha-stdin >"$T/cli.out" 2>&1 || falhou "cadastro propagar=alvo1: $(cat "$T/cli.out")"
[[ $(cat "$D/.secrets/aerc-cli2.txt") == SENHA_C2 ]] || falhou 'propagar=alvo1: senha não chegou'
echo 'SENHA_C3' | "$TT" --email-adicionar nome=Cli3 endereco=cli3@gmail.com provedor=gmail auth=senha propagar=0 --senha-stdin >/dev/null 2>&1 || falhou 'cadastro propagar=0'
[[ -e $D/.secrets/aerc-cli3.txt ]] && falhou 'propagar=0 propagou'
passou 'CLI: propagar=1 manda a todas, propagar=rótulo só àquela, propagar=0 não manda; a chave não fica no .conf'

# --- tela da conta: o seletor (sem terminal lê os rótulos) chama a propagação --------------------
out=$(printf 'alvo1\n' | "$TT" --email-propagar-ui Cli 2>&1 </dev/stdin) || true
grep -q 'já existe lá' <<<"$out" || falhou "seletor da tela da conta não propagou para alvo1: $out"
out=$(printf '\n' | "$TT" --email-propagar-ui Cli 2>&1) || true
grep -q 'Propagando' <<<"$out" && falhou 'seletor vazio propagou'
passou 'tela da conta (F2 → conta → ⇪ Propagar…): o seletor de máquinas chama a propagação; vazio não manda'

# --- a assinatura acompanha a conta (e some lá quando some aqui) ---------------------------------
printf 'Abraços,\nHélio\n' | "$TT" --email-assinatura Cli >/dev/null || falhou 'assinatura'
out=$("$TT" --email-propagar Cli --sobrescrever 2>&1) || falhou "propagar com assinatura: $out"
grep -qx 'cli.assinatura' <<<"$(tar -tf "$ENVIADO")" || falhou "pacote deveria levar a assinatura: $(tar -tf "$ENVIADO")"
[[ $(cat "$D/.config/tt/email/cli.assinatura") == $'Abraços,\nHélio' ]] || falhou 'assinatura não chegou'
grep -q "^signature-file *= $D/.config/tt/email/cli.assinatura$" "$D/.config/aerc/accounts.conf" || falhou 'bloco de lá sem signature-file'
printf '' | "$TT" --email-assinatura Cli >/dev/null
out=$("$TT" --email-propagar Cli --sobrescrever 2>&1) || falhou "propagar sem assinatura: $out"
[[ -e $D/.config/tt/email/cli.assinatura ]] && falhou 'assinatura tirada aqui deveria sumir lá'
grep -q 'signature-file' "$D/.config/aerc/accounts.conf" && falhou 'signature-file ficou no bloco de lá'
passou 'assinatura da conta viaja junto; tirada aqui, some lá na próxima propagação'

# --- origem sem segredo (OAuth ainda não autorizado) não propaga -----------------------------------
"$TT" --email-adicionar nome=Oauth endereco=o@empresa.com provedor=microsoft auth=oauth oauth_client_id=id-ficticio >/dev/null || falhou 'cadastro oauth'
set +e; out=$("$TT" --email-propagar Oauth 2>&1); rc=$?; set -e
((rc != 0)) && grep -q 'ainda não tem senha/token aqui' <<<"$out" || falhou "oauth sem token: $out"
[[ -e $D/.config/tt/email/oauth.conf ]] && falhou 'propagou conta sem token'
passou 'conta OAuth ainda sem token não é propagada (autorize antes)'
