#!/usr/bin/env bash
# Menu do botão direito dos atalhos (5ª coluna do atalho):
#  - @contas lista as contas pelo próprio comando ({conta} → --listar-contas, no ambiente do atalho) e cada item
#    roda o atalho com --conta NOME; clicado direto, {conta} some (o rotador escolhe);
#  - opção fixa "Rótulo=comando" e separador;
#  - @maquinas roda o atalho de mesmo ID noutra máquina (ssh falso), numa sessão nova de lá, e a tela vai para ela;
#  - sem a 5ª coluna, nada de menu (o botão direito só mostra o comando, como antes);
#  - ia-conta abrir --listar-contas (só caches) e --conta (sem o rotador);
#  - o editor grava e preserva a 5ª coluna.
source "$(dirname "$0")/lib.sh"; isolar
B=$T/fb; mkdir -p "$B"
# ia-conta falso: --listar-contas imprime duas contas (e uma linha de sujeira, que não vira item); abrir registra.
cat >"$B/ia-conta" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" --listar-contas "* ]]; then
  echo 'aviso qualquer do login'
  printf 'alfa\tclaude\tclaude · alfa\t5h 10%%\nbeta\tcodex\tcodex · beta\t-\n'
  echo x >>"$LISTAGENS"; exit 0
fi
printf '%s\n' "$*" >>"$IA_LOG"
EOF
chmod +x "$B/ia-conta"
export IA_LOG=$T/ia-conta.log LISTAGENS=$T/listagens
c=$XDG_CONFIG_HOME/tt/atalhos
printf '🚀\tia-nova\t%s abrir {conta}\t#a6e3a1\t@contas\n' "$B/ia-conta" >"$c"
printf '🧪\tteste\techo base >%s\t\t@contas ;; - ;; Outro jeito=echo outro >%s ;; @maquinas\n' "$T/base.out" "$T/outro.out" >>"$c"
printf '⚡\tsem-menu\thtop\t#f38ba8\n' >>"$c"
espera() { local i; for i in $(seq 40); do [[ -s $1 ]] && return 0; sleep 0.2; done; return 1; }

tmux new -d -s inicio -x 120 -y 30 -c "$T" 'sleep 600'
anexar tela 120 30 inicio; sleep 0.8
cli=$(tmux list-clients -F '#{client_name}' | head -1)
pane=$(tmux display -p -t '=inicio:' '#{pane_id}')
sessao_de() { tmux list-clients -F '#{client_name} #{session_name}' | awk -v c="$1" '$1 == c { print $2; exit }'; }

m=$("$TT" --atalho-menu-itens ia-nova "$cli" "$pane")
grep -qP '^0\t🚀 A de mais folga agora, pelo rotador \(o clique\)\t.*--atalho-rodar ia-nova ' <<<"$m" || falhou "1º item (o clique) faltando: $m"
grep -qP '^1\t🤖 claude · alfa  ·  5h 10%\t.*--atalho-rodar ia-nova .*conta=alfa' <<<"$m" || falhou "item da conta alfa: $m"
grep -qP '^2\t🤖 codex · beta  ·  -\t.*conta=beta' <<<"$m" || grep -qP '^2\t🤖 codex · beta\t.*conta=beta' <<<"$m" || falhou "item da conta beta: $m"
grep -q 'aviso qualquer' <<<"$m" && falhou 'linha que não é conta virou item'
grep -qP '^ \tℹ ' <<<"$m" || falhou "sem a linha do comando: $m"
passou '@contas: uma opção por conta, tirada do próprio comando do atalho ({conta} → --listar-contas)'

n1=$(wc -l <"$LISTAGENS")
"$TT" --atalho-menu-itens ia-nova "$cli" "$pane" >/dev/null
[[ $(wc -l <"$LISTAGENS") == "$n1" ]] || falhou 'a 2ª abertura do menu listou as contas de novo (deveria vir da lista guardada)'
passou '@contas: a segunda abertura usa a lista guardada (menu na hora)'

"$TT" --atalho-rodar ia-nova "$cli" "$pane" conta=alfa
espera "$IA_LOG" || falhou 'o item da conta não rodou o atalho'
[[ $(tail -1 "$IA_LOG") == 'abrir --conta alfa' ]] || falhou "item da conta: $(cat "$IA_LOG")"
[[ $(sessao_de "$cli") == atalho-* ]] || falhou "a tela não foi para a sessão nova do atalho: $(sessao_de "$cli")"
"$TT" --atalho-rodar ia-nova "$cli" "$pane" 'conta=x;rm -rf /' && sleep 0.5
[[ $(wc -l <"$IA_LOG") == 1 ]] || falhou "conta com caracteres estranhos rodou: $(cat "$IA_LOG")"
: >"$IA_LOG"; i=$("$TT" --atalhos-lista | cut -f2 | grep -n '^ia-nova$' | cut -d: -f1)
"$TT" --clique "at$i" "$cli" "$pane" "$T"
espera "$IA_LOG" || falhou 'o clique direto não rodou'
[[ $(tail -1 "$IA_LOG") == 'abrir' ]] || falhou "clique direto deveria deixar o rotador escolher (sem --conta): '$(cat "$IA_LOG")'"
passou 'conta escolhida: --conta NOME; clique direto: {conta} some e o rotador escolhe'

m=$("$TT" --atalho-menu-itens teste "$cli" "$pane")
grep -qP '^\w\tOutro jeito\t.*opcao=1' <<<"$m" || falhou "opção fixa: $m"
[[ $(grep -c $'^-\t' <<<"$m") -ge 3 ]] || falhou "separadores: $m"
"$TT" --atalho-rodar teste "$cli" "$pane" opcao=1
espera "$T/outro.out" || falhou 'a opção fixa não rodou'
[[ $(cat "$T/outro.out") == outro && ! -e $T/base.out ]] || falhou 'a opção fixa rodou o comando errado'
grep -q '🤖' <<<"$m" && falhou '@contas num comando sem {conta} não deveria listar contas'
passou 'opção fixa (Rótulo=comando) roda o comando dela; @contas sem {conta} não lista nada'

[[ -z $("$TT" --atalho-menu-itens sem-menu "$cli" "$pane" | grep -v '^0	\|^-	\|^ 	\|^e	') ]] || falhou 'atalho sem menu ganhou itens'
grep -q 'atalho_info "\$c" "\$i"' "$TT" || falhou 'sem a 5ª coluna, o botão direito deveria continuar mostrando o comando'
passou 'sem a 5ª coluna: sem menu (o botão direito mostra o comando, como antes)'

# @maquinas: o atalho "teste" roda na outra máquina (ssh falso: o comando roda aqui, com a HOME de lá) e a tela vai
# para a sessão nova de lá, por ponte.
D=$T/dest; mkdir -p "$D/.local/bin" "$D/.config/tt" "$D/rt"; ln -s "$TT" "$D/.local/bin/tt"
printf 'nome=outra\n' >"$D/.config/tt/config"
printf '🧪\tteste\techo la >%s\t\t\n' "$T/la.out" >"$D/.config/tt/atalhos"
cat >"$B/ssh" <<'EOF'
#!/usr/bin/env bash
cmd=${*: -1}
printf '%s\n' "$cmd" >>"$SSH_LOG"
exec env HOME="$DEST" XDG_CONFIG_HOME="$DEST/.config" TT_RT="$DEST/rt" bash -c "$cmd"
EOF
chmod +x "$B/ssh"
export PATH=$B:$PATH SSH_LOG=$T/ssh.log DEST=$D
printf 'destino-host helio outra\n' >"$XDG_CONFIG_HOME/tt/maquinas"
m=$("$TT" --atalho-menu-itens teste "$cli" "$pane")
grep -qP '^\w\t🖥 Em outra \(sessão nova lá\)\t.*maquina=outra' <<<"$m" || falhou "@maquinas sem a outra máquina: $m"
grep -q 'Em teste' <<<"$m" && falhou '@maquinas não deveria oferecer esta mesma máquina'
tmux switch-client -c "$cli" -t =inicio
TMUX=$(tmux display -p '#{socket_path}'),1,0 "$TT" --atalho-rodar teste "$cli" "$pane" maquina=outra
espera "$T/la.out" || falhou "o atalho não rodou na outra máquina: $(cat "$SSH_LOG" 2>/dev/null)"
grep -q -- '--atalho-sessao teste' "$SSH_LOG" || falhou "não pediu a sessão à outra máquina: $(cat "$SSH_LOG")"
s=$(sessao_de "$cli"); alvo=$(tmux show -qv -t "=$s:" @ponte_alvo)
[[ $alvo == helio@destino-host\|atalho-* ]] || falhou "a tela não foi por ponte à sessão nova de lá: sessão=$s alvo=$alvo"
passou "@maquinas: o atalho de mesmo ID roda numa sessão nova da outra máquina e a tela vai até ela ($alvo)"

# ia-conta de verdade: --listar-contas só com caches (uma linha por conta, a principal fora quando é o perfil), e
# --conta abre a escolhida sem o rotador.
R=$HOME/.local/share/claude-contas; mkdir -p "$R/alfa" "$R/semcred" "$HOME/.claude" "$HOME/.cache"
cred='{"claudeAiOauth":{"accessToken":"t","expiresAt":9999999999999}}'
echo "$cred" >"$R/alfa/.credentials.json"; echo "$cred" >"$HOME/.claude/.credentials.json"
echo a@x.com >"$R/alfa/.account-email"; echo a@x.com >"$HOME/.claude/.account-email"
printf '{"alfa": {"alvo": "%s", "quando": %s, "janelas": [["5h", 12, %s]], "email": ""}}\n' "$R/alfa" "$(date +%s)" "$(($(date +%s) + 3600))" \
  >"$HOME/.cache/claude-rot.uso.json"
printf 'claude\ta@x.com\tpessoal\t1\n' >"$XDG_CONFIG_HOME/tt/contas-ia"
cat >"$B/claude" <<'EOF'
#!/usr/bin/env bash
printf 'claude\t%s\t%s\n' "${CLAUDE_CONFIG_DIR:-principal}" "$*" >>"$IA_LOG"
EOF
chmod +x "$B/claude"
l=$(CLAUDE_ROT_USO=0 "$T/pkg/ia-conta" abrir --listar-contas)
[[ $(grep -cP '^[^\t]+\tclaude\t' <<<"$l") == 1 ]] || falhou "listar-contas: a principal com o e-mail do perfil (mesma conta) e o perfil sem credencial deveriam ficar fora: $l"
grep -qP '^alfa\tclaude\tclaude · pessoal \(alfa\)\t5h 12%$' <<<"$l" || falhou "listar-contas: $l"
: >"$IA_LOG"
"$T/pkg/ia-conta" abrir --conta alfa >/dev/null </dev/null
grep -qP "^claude\t$R/alfa\t--dangerously-skip-permissions\$" "$IA_LOG" || falhou "abrir --conta alfa: $(cat "$IA_LOG")"
"$T/pkg/ia-conta" abrir --conta nao-existe >/dev/null 2>&1 </dev/null && falhou 'abrir --conta com conta inexistente deveria falhar'
passou 'ia-conta: --listar-contas (só caches, uma por conta) e abrir --conta (sem o rotador)'

# Editor: gravar_atalho com menu põe a 5ª coluna; sem menu, a linha fica com 4.
bash -c "TT_SO_CARREGAR=1 source '$TT'; gravar_atalho novo '🧩' 'ls' '#cba6f7' '@contas ;; X=pwd'; gravar_atalho velho '🧱' 'ls' '#cba6f7'"
grep -qP '^🧩\tnovo\tls\t#cba6f7\t@contas ;; X=pwd$' "$c" || falhou "editor não gravou o menu: $(cat "$c")"
grep -qP '^🧱\tvelho\tls\t#cba6f7$' "$c" || falhou "editor pôs coluna vazia num atalho sem menu: $(cat "$c")"
"$TT" --atalhos-barra | grep -q 'range=user|at' || falhou 'barra sem atalhos'
"$TT" --atalhos-barra | grep -q '@contas' && falhou 'a 5ª coluna vazou para a barra (cor errada)'
passou 'editor: grava a 5ª coluna só quando há menu; a barra não a confunde com a cor'
