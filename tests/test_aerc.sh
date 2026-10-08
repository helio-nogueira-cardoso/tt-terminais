#!/usr/bin/env bash
# Provisionamento do aerc: tema Catppuccin, opções de visual só acrescentadas (escolhas do dono ficam),
# filtro de HTML que funciona sem w3m, atalhos novos na lista e na leitura, nada solto antes do 1º
# cabeçalho do bloco, idempotente, accounts.conf intocado.
source "$(dirname "$0")/lib.sh"; isolar
mkdir -p "$T/bin" "$HOME/.config/aerc"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"
C=$HOME/.config/aerc/aerc.conf; B=$HOME/.config/aerc/binds.conf
printf '[ui]\n#mouse-enabled=false\nsidebar-width=30\n\n[filters]\ntext/plain=colorize\ntext/html=! html\n' >"$C"
printf '[messages]\nj = :next<Enter>\n\n[terminal]\n<C-p> = :prev-tab<Enter>\n' >"$B"
roda() { PATH="$T/bin:/usr/bin:/bin" bash -c "source <(sed -n '/^AERC_BINDS_INI=/,/^remover_aerc() {/p' '$TT' | sed '\$d'); DIR_TT='$TT_DIR'; conf() { :; }; configurar_aerc"; }
roda; roda
v() { awk -v S="$1" -v K="$2" '/^\[.*\]/ { s = $0; gsub(/^\[|\].*$/, "", s); next } s == S && index($0, K "=") == 1 { sub(/^[^=]*=/, ""); print }' "$C"; }
[[ $(v ui styleset-name) == tt-catppuccin && -s $HOME/.config/aerc/stylesets/tt-catppuccin ]] || falhou 'tema Catppuccin não aplicado'
[[ $(v ui sidebar-width) == 30 ]] || falhou 'escolha do dono (sidebar-width=30) foi sobrescrita'
[[ $(v ui mouse-enabled) == true && $(grep -c 'mouse-enabled' "$C") == 1 ]] || falhou 'mouse não ligado uma vez só'
[[ $(v ui threading-enabled) == true && $(v ui dirlist-tree) == true ]] || falhou 'fios/árvore de pastas não ligados'
grep -q '^dirlist-right={{if .Unread}}' "$C" || falhou 'contagem de não lidas nas pastas ausente'
[[ $(v ui cache-headers) == true ]] || falhou 'cache-headers=true ausente (consulta de e-mail não é acelerada)'
[[ $(grep -c '^cache-headers' "$C") == 1 ]] || falhou 'cache-headers duplicado (não idempotente)'
[[ $(grep -c '^\[ui\]' "$C") == 1 ]] || falhou 'seção [ui] duplicada'
passou 'visual: tema Catppuccin, pastas em árvore com não lidas, fios, cache de cabeçalhos; escolhas do dono preservadas; idempotente'

h=$(v filters text/html)
if PATH="$T/bin:/usr/bin:/bin" command -v w3m >/dev/null; then [[ $h == '! html'*extbrowser* && $h != *'|'* ]] || falhou "com w3m deveria ser '! html -o extbrowser…' sem pipe, para o w3m ficar interativo (está: $h)"
elif PATH="$T/bin:/usr/bin:/bin" command -v lynx >/dev/null; then [[ $h == lynx*linkify* ]] || falhou "sem w3m deveria usar lynx + linkify (está: $h)"
else [[ $h == *email-tt.py\ html*linkify* ]] || falhou "sem w3m/lynx deveria usar o conversor do tt + linkify (está: $h)"; fi
r=$(printf '<p>Oi <a href="https://x.y/z">link</a></p>' | python3 "$TT_DIR/email-tt.py" html)
[[ $r == *"Oi link [1]"* && $r == *"[1] https://x.y/z"* ]] || falhou "conversor de HTML do tt: $r"
passou "HTML: filtro que funciona nesta máquina ($h) e conversor próprio como reserva"

bl=$(sed -n '/# >>> tt (saída rápida/,/# <<< tt (saída rápida/p' "$B")
[[ $(sed -n 2p <<<"$bl") == \#* || $(sed -n 2p <<<"$bl") == '[messages]' ]] || true
awk '/# >>> tt \(saída rápida/ { b = 1; next } b && /^\[/ { exit } b && /=/ { print "solta: " $0; e = 1 } END { exit e }' "$B" || falhou 'linha de atalho solta antes do 1º cabeçalho do bloco (cairia em [terminal])'
for k in 'u = :read -t' '\* = :flag -t' 'f = :forward' 'M = :move' 'Y = :copy' 'F = :filter -X Seen'; do
  sed -n '/# >>> tt (saída rápida/,$p' "$B" | sed -n '/^\[messages\]/,/^\[view\]/p' | grep -q "^$k" || falhou "atalho na lista: $k"
  sed -n '/# >>> tt (saída rápida/,$p' "$B" | sed -n '/^\[view\]/,$p' | grep -q "^${k%% = *} = " || [[ $k == F* ]] || falhou "atalho na leitura: $k"
done
[[ $(grep -c '# >>> tt (saída rápida' "$B") == 1 ]] || falhou 'bloco de atalhos duplicado'
grep -q '^<C-p> = :prev-tab' "$B" || falhou 'atalhos do dono sumiram'
[[ -e $HOME/.config/aerc/accounts.conf ]] && falhou 'accounts.conf foi criado'
passou 'atalhos: lido/não lido, estrela, encaminhar, mover, copiar, filtrar não lidos; nada solto antes do bloco'

# O aerc de verdade precisa abrir com essa configuração (um atributo de tema inválido, como
# strikethrough no 0.20, impede o aerc de iniciar). HOME real só para o aerc achar os próprios
# modelos; a configuração é a do teste (XDG_CONFIG_HOME).
if PATH="$HOME_REAL/.local/bin:$PATH" command -v aerc >/dev/null; then
  mkdir -p "$T/maildir/INBOX"/{cur,new,tmp}
  printf '[Teste]\nsource = maildir://%s/maildir\nfrom = t@exemplo.com\noutgoing = /bin/true\n' "$T" >"$HOME/.config/aerc/accounts.conf"; chmod 600 "$HOME/.config/aerc/accounts.conf"
  tmux -f /dev/null new -d -s aerc -x 110 -y 20 "env HOME='$HOME_REAL' XDG_CONFIG_HOME='$XDG_CONFIG_HOME' PATH='$HOME_REAL/.local/bin:$PATH' aerc; echo SAIU; sleep 30"
  sleep 3; tela=$(tmux capture-pane -p -t =aerc:)
  grep -q 'SAIU\|error:' <<<"$tela" && falhou "o aerc não abriu com a configuração do tt: $(grep -m1 'error' <<<"$tela")"
  grep -q 'INBOX' <<<"$tela" || falhou "aerc abriu sem a lista de pastas: $(head -3 <<<"$tela")"
  passou 'o aerc real abre com o tema e os atalhos do tt'
else
  echo "(aerc não instalado aqui: partida real pulada)"
fi

# email= com caminho completo para o aerc (como no Dell) também recebe a configuração.
rm -rf "$HOME/.config/aerc"; mkdir -p "$HOME/.config/aerc"
PATH="$T/bin:/usr/bin:/bin" bash -c "source <(sed -n '/^AERC_BINDS_INI=/,/^remover_aerc() {/p' '$TT' | sed '\$d'); DIR_TT='$TT_DIR'; conf() { [[ \$1 == email ]] && echo /opt/x/bin/aerc; }; configurar_aerc"
grep -q '^styleset-name=tt-catppuccin' "$HOME/.config/aerc/aerc.conf" || falhou 'email=/caminho/aerc não recebeu a configuração'
PATH="$T/bin:/usr/bin:/bin" bash -c "source <(sed -n '/^AERC_BINDS_INI=/,/^remover_aerc() {/p' '$TT' | sed '\$d'); DIR_TT='$TT_DIR'; conf() { [[ \$1 == email ]] && echo neomutt; }; rm -f '$HOME/.config/aerc/aerc.conf'; configurar_aerc"
[[ -e $HOME/.config/aerc/aerc.conf ]] && falhou 'configurou o aerc com outro cliente escolhido (neomutt)'
passou 'email= com caminho do aerc configura; outro cliente escolhido não é tocado'

# Máquina nova sem binds.conf: começa pelos atalhos padrão do aerc (senão nem o Enter abriria).
# HTML é a versão preferida quando o e-mail tem as duas.
rm -rf "$HOME/.config/aerc"; mkdir -p "$HOME/.config/aerc" "$T/aercpad"
printf '[messages]\n<Enter> = :view<Enter>\nj = :next<Enter>\n' >"$T/aercpad/binds.conf"
PATH="$T/bin:/usr/bin:/bin" PREFIX="$T/aercpad/.." bash -c "mkdir -p '$T/share/aerc'; cp '$T/aercpad/binds.conf' '$T/share/aerc/'; PREFIX='$T'; source <(sed -n '/^AERC_BINDS_INI=/,/^remover_aerc() {/p' '$TT' | sed '\$d'); DIR_TT='$TT_DIR'; conf() { :; }; configurar_aerc"
grep -q '^<Enter> = :view' "$HOME/.config/aerc/binds.conf" || falhou 'binds.conf novo sem os atalhos padrão do aerc'
grep -q '^u = :read -t' "$HOME/.config/aerc/binds.conf" || falhou 'binds.conf novo sem os atalhos do tt'
grep -q '^alternatives=text/html,text/plain$' "$HOME/.config/aerc/aerc.conf" || falhou 'HTML não é o preferido'
grep -q '^E = :save -a -f -p .*tt --anexos-enviar' "$HOME/.config/aerc/binds.conf" || falhou 'tecla E (anexos para máquina) ausente'
passou 'máquina nova: atalhos padrão do aerc + os do tt; HTML preferido; E envia anexos'
