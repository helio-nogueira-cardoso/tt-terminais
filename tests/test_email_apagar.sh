#!/usr/bin/env bash
# Apagar e arquivar certos no Gmail: contas Gmail do tt ganham, no binds.conf (bloco do tt) e nos
# binds da sessão oculta (botões ✕/▤), seções por conta — d/D movem para a lixeira da conta, a tira
# do INBOX (= arquivar no Gmail) — e por pasta — na lixeira/spam d/D apagam de vez, e lá e em
# "Todos os e-mails" arquivar fica sem efeito. Contas de outros provedores não ganham nada; o
# cadastro/remoção regera o bloco; nomes com caracteres de regex são escapados. aerc falso.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
# aerc falso que fica vivo: ignora os argumentos (-C conf -B binds) e dorme com argv[0] = "aerc" —
# é o que o tmux mostra em pane_current_command, e o botão 📧 confere que o aerc continua aberto.
mkdir -p "$T/bin"
printf '#!/usr/bin/env bash\nexec -a aerc python3 -c "import time; time.sleep(600)"\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"; export PATH=$T/bin:$PATH
B=$HOME/.config/aerc/binds.conf
G=(provedor=gmail auth=senha 'pasta_naoabre=[Gmail]' 'pasta_lixeira=[Gmail]/Lixeira' 'pasta_spam=[Gmail]/Spam' 'pasta_todos=[Gmail]/Todos os e-mails')
sec() { sed -n "/^\[$1\]\$/,/^\[/p" "$B" | sed '1d;$d'; } # linhas de uma seção (o nome é regex literal aqui)

# 1) conta Gmail: seções por conta e por pasta no binds.conf
echo 'S' | "$TT" --email-adicionar nome=Pessoal endereco=eu@gmail.com "${G[@]}" --senha-stdin >/dev/null || falhou 'cadastro gmail'
[[ -f $B ]] || falhou 'binds.conf não foi criado pelo cadastro'
s=$(sec 'messages:account=^Pessoal$')
grep -q "^d = :choose -o y 'Apagar (vai para a lixeira)' 'move Lixeira'<Enter>$" <<<"$s" || falhou "d na lista deveria mover para a Lixeira: $s"
grep -q '^D = :move Lixeira<Enter>$' <<<"$s" || falhou 'D na lista deveria mover direto'
grep -q '^a = :delete<Enter>$' <<<"$s" || falhou 'a na lista deveria tirar do INBOX (arquivar no Gmail)'
s=$(sec 'view:account=^Pessoal$')
grep -q "^d = :choose -o y 'Apagar (vai para a lixeira)' 'move Lixeira'<Enter>$" <<<"$s" && grep -q '^a = :delete<Enter>$' <<<"$s" || falhou "na leitura também: $s"
s=$(sec 'messages:folder=^Lixeira$')
grep -q "^d = :choose -o y 'Apagar de vez (não volta)' delete-message<Enter>$" <<<"$s" || falhou "na Lixeira d apaga de vez: $s"
grep -q '^D = :delete<Enter>$' <<<"$s" && grep -q '^a =$' <<<"$s" || falhou 'na Lixeira D apaga de vez e a fica sem efeito'
s=$(sec 'messages:folder=^Spam$'); grep -q 'delete-message' <<<"$s" || falhou 'no Spam d apaga de vez'
s=$(sec 'view:folder=^Todos os e-mails$'); grep -q '^a =$' <<<"$s" || falhou 'em Todos os e-mails arquivar fica sem efeito'
sec 'messages:folder=^Todos os e-mails$' | grep -q 'delete' && falhou 'em Todos os e-mails d/D não são sobrescritos (lá d = lixeira pela conta)'
awk '/# >>> tt \(saída rápida/{b=1} b' "$B" | grep -q '^\[messages:account=' || falhou 'as seções por conta devem estar dentro do bloco do tt'
passou 'conta Gmail: d/D → Lixeira, a → tira do INBOX; na Lixeira/Spam apaga de vez; em Todos os e-mails arquivar sem efeito'

# 2) conta de outro provedor: nada por conta; nome com caracteres de regex escapado; remoção limpa
echo 'S' | "$TT" --email-adicionar nome=Trabalho endereco=eu@fastmail.com provedor=fastmail auth=senha --senha-stdin >/dev/null || falhou 'cadastro fastmail'
grep -q 'account=^Trabalho\$' "$B" && falhou 'conta não-Gmail não deveria ganhar seção por conta'
echo 'S' | "$TT" --email-adicionar 'nome=G+Mail (2.0)' endereco=dois@gmail.com "${G[@]}" --senha-stdin >/dev/null || falhou 'cadastro com regex no nome'
grep -q '^\[messages:account=^G\\+Mail \\(2\\.0\\)\$\]$' "$B" || falhou "nome com +, ( ) e . deveria vir escapado: $(grep 'account=' "$B")"
"$TT" --email-remover Pessoal >/dev/null || falhou 'remover'
grep -q 'account=^Pessoal\$' "$B" && falhou 'remover deveria tirar as seções da conta'
grep -q 'account=^G\\+Mail' "$B" || falhou 'remover uma conta não deveria tirar as da outra'
[[ $(grep -c '^\[messages:folder=^Lixeira\$\]$' "$B") == 1 ]] || falhou 'seção da pasta Lixeira deveria aparecer uma vez só'
[[ $(grep -c '# >>> tt (saída rápida' "$B") == 1 ]] || falhou 'bloco do tt duplicado'
passou 'outros provedores sem seção; nome escapado; remover limpa só a conta; pastas sem repetição'

# 3) sessão oculta: os botões ✕ (F9) e ▤ (F8) seguem a mesma regra
tmux -f /dev/null new -d -s base -x 150 -y 40 'sleep 600'
# o botão 📧 cria a sessão oculta (o popup em si falha: "base" não é um cliente — não importa aqui)
"$TT" --botao email base '%0' "$HOME" >/dev/null 2>&1 || true
tmux has-session -t =_tt-email 2>/dev/null || falhou 'sessão oculta não foi criada pelo botão 📧'
bo=~/.cache/tt-aerc-binds-oculto.conf
[[ -f $bo ]] || falhou 'binds da sessão oculta não foram gerados'
sed -n '/^\[messages:account=^G\\+Mail \\(2\\.0\\)\$\]$/,/^\[/p' "$bo" | grep -q "^<F9> = :choose -o y 'Apagar (vai para a lixeira)' 'move Lixeira'<Enter>$" || falhou "botão ✕ na conta Gmail deveria mover para a Lixeira: $(grep -n 'F9\|account=' "$bo" | head)"
sed -n '/^\[messages:account=^G\\+Mail \\(2\\.0\\)\$\]$/,/^\[/p' "$bo" | grep -q '^<F8> = :delete<Enter>$' || falhou 'botão ▤ na conta Gmail deveria tirar do INBOX'
sed -n '/^\[messages:folder=^Lixeira\$\]$/,/^\[/p' "$bo" | grep -q "^<F9> = :choose -o y 'Apagar de vez (não volta)' delete-message<Enter>$" || falhou 'botão ✕ na Lixeira apaga de vez'
sed -n '/^\[messages:folder=^Lixeira\$\]$/,/^\[/p' "$bo" | grep -q '^<F8> =$' || falhou 'botão ▤ na Lixeira sem efeito'
passou 'sessão oculta: ✕ e ▤ seguem a regra do Gmail por conta e por pasta'

echo 'ok: apagar e arquivar certos no Gmail (binds por conta e por pasta, lista, leitura e botões)'
