#!/usr/bin/env bash
# Enviar tarefa por e-mail pelo tt: o botão ✉ do menu ⋯ (só tarefa de topo), o menu do 📋, tt --tarefa-email ID [destino] --abrir e
# tt --tarefas-email DESTINO ID… abrem UM e-mail por tarefa já preenchido (Para, Assunto "[tt] … ~código", corpo com as subtarefas e o
# rodapé v2) no compositor escolhido (TT_EMAIL_MAILTO_CMD ou o aerc do tt); o texto aberto é exatamente o que um tt do outro lado
# entende (ida e volta). Isola HOME/XDG/TT_RT; o "compositor" do teste só anota a URL mailto:.
source "$(dirname "$0")/lib.sh"; isolar
tt() { "$TT" "$@"; }
mkdir -p "$T/A/home/.config/tt" "$T/A/rt" "$T/bin"
printf 'nome=A\n' >"$T/A/home/.config/tt/config"; : >"$T/A/home/.config/tt/maquinas"
A() { HOME=$T/A/home XDG_CONFIG_HOME=$T/A/home/.config TT_RT=$T/A/rt TT_MACHINE=A "$TT" "$@"; }
printf '#!/bin/sh\nexit 0\n' >"$T/bin/notify-send"; printf '#!/bin/sh\nexit 1\n' >"$T/bin/tmux"; chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"
printf '#!/bin/sh\nprintf "%%s\\n" "$1" >>"%s/urls.txt"\n' "$T" >"$T/bin/compositor"; chmod +x "$T/bin/compositor"
export TT_EMAIL_MAILTO_CMD="$T/bin/compositor"
CA="$T/A/home/.config/tt/tarefas"; CB="$XDG_CONFIG_HOME/tt/tarefas"; URLS="$T/urls.txt"; : >"$URLS"
INBOX="$HOME/.cache/tt/maildir/conta/INBOX"; mkdir -p "$INBOX/new"
id_em() { awk -F'\t' -v t="$1" '$5==t && $2!="removida"{print $1; exit}' "$CA"; }
decod() { python3 -I -c 'import sys, urllib.parse as u
url = sys.argv[1]; p = u.urlsplit(url); q = u.parse_qs(p.query, keep_blank_values=True)
print("TO=" + u.unquote(p.path)); print("SUBJECT=" + q["subject"][0]); print("BODY=" + q["body"][0])' "$1"; }

A --tarefa-add "Planejar viagem" >/dev/null; P=$(id_em "Planejar viagem"); A --tarefa-sub-add "$P" "Comprar passagem" >/dev/null 2>&1
A --tarefa-add "Pagar condomínio" >/dev/null; Q=$(id_em "Pagar condomínio")
S1=$(id_em "Comprar passagem")

# 1) --abrir: um e-mail preenchido, no compositor escolhido
A --tarefa-email "$P" ana@x.com --abrir
[[ $(wc -l <"$URLS") == 1 ]] || falhou "deveria abrir 1 e-mail: $(cat "$URLS")"
d=$(decod "$(tail -n1 "$URLS")")
grep -q '^TO=ana@x.com$' <<<"$d" && grep -q "^SUBJECT=\[tt\] Planejar viagem ~$P$" <<<"$d" || falhou "Para/Assunto: $d"
grep -q "\[$S1\] \[ \] Comprar passagem" <<<"$d" && grep -q 'tt:2 estado=aberta' <<<"$d" || falhou "corpo com as subtarefas e o rodapé v2: $d"
passou '--abrir: um e-mail com Para, assunto [tt] … ~código e corpo com subtarefas e rodapé v2'

# 2) vários destinatários e várias tarefas: um e-mail por tarefa
: >"$URLS"
A --tarefas-email "ana@x.com,bia@x.com" "$P" "$Q"
[[ $(wc -l <"$URLS") == 2 ]] || falhou "2 tarefas = 2 e-mails: $(cat "$URLS")"
grep -q 'ana%40x.com%2Cbia%40x.com' "$URLS" || grep -q 'ana@x.com,bia@x.com' <(decod "$(head -n1 "$URLS")") || falhou "os dois destinatários deviam estar no Para"
d2=$(decod "$(tail -n1 "$URLS")"); grep -q "~$Q" <<<"$d2" || falhou "o 2º e-mail é da outra tarefa: $d2"
A --tarefas-email ana@x.com 2>/dev/null && falhou 'sem tarefas deveria dar erro de uso'
passou 'lote: um e-mail por tarefa, vários destinatários no Para'

# 3) a tela de envio sem perguntar (TT_EMAIL_PARA) e subtarefa vira a mãe
: >"$URLS"
TT_EMAIL_PARA=ana@x.com A --tarefa-email-ui "$P" "$Q"
[[ $(wc -l <"$URLS") == 2 ]] || falhou "tela de envio: 2 e-mails (há $(wc -l <"$URLS"))"
passou 'tela de envio com o destinatário dado: um e-mail por tarefa'

# 4) ida e volta: o que o compositor recebeu é exatamente o que o outro tt entende
d=$(decod "$(sed -n 1p "$URLS")")
assunto=$(sed -n 's/^SUBJECT=//p' <<<"$d"); corpo=$(python3 -I -c 'import sys; t = sys.stdin.read(); print(t.split("BODY=", 1)[1], end="")' <<<"$d")
{ echo "From: Ana <ana@x.com>"; echo "Date: $(date -R)"; echo "Message-ID: <ida@t>"; echo "Subject: $assunto"
  echo "Content-Type: text/plain; charset=utf-8"; echo; printf '%s\n' "$corpo"; } >"$INBOX/new/ida"
tt --demanda-autorizar ana@x.com - aberto >/dev/null; tt --demandas-processar conta
[[ $(awk -F'\t' -v i="$P" '$1==i{print $2}' "$CB") == pendente && $(awk -F'\t' -v i="$S1" '$1==i{print $2}' "$CB") == pendente ]] || falhou "o e-mail aberto pelo compositor deveria chegar como demanda com os mesmos códigos"
passou 'ida e volta: o e-mail pronto do compositor vira a demanda certa do outro lado'

# 5) o botão ✉ no menu ⋯ da tarefa de topo; não na subtarefa nem na arquivada; e no menu do 📋
UI="$TT_RT/tt-tarefas-ui-$(id -u)"
tt --tarefa-add "Planejar viagem" >/dev/null 2>&1; tt --tarefa-add "Comprar passagem" >/dev/null 2>&1   # (o menu é da B: precisa das tarefas)
BP=$(awk -F'\t' '$5=="Planejar viagem"{print $1; exit}' "$CB"); BS=$(awk -F'\t' '$5=="Comprar passagem"{print $1; exit}' "$CB"); tt --tarefa-sub-add "$BP" "Passo" >/dev/null 2>&1; BS=$(awk -F'\t' '$5=="Passo"{print $1; exit}' "$CB")
printf 'modo=menu:%s\n' "$BP" >"$UI"; m=$(tt --tarefas-lista | sed 's/\x1b\[[0-9;]*m//g')
grep -q "^act:email:$BP" <<<"$m" || falhou "o menu ⋯ da tarefa de topo deveria ter ✉ Enviar por e-mail: $m"
printf 'modo=menu:%s\n' "$BS" >"$UI"; m=$(tt --tarefas-lista | sed 's/\x1b\[[0-9;]*m//g')
grep -q "^act:email:" <<<"$m" && falhou "subtarefa não tem ✉ (compartilha-se a mãe)"
a=$(FZF_QUERY= tt --tarefa-acao email "act:email:$BP"); grep -q "execute(.*--tarefa-email-ui $BP)" <<<"$a" || falhou "a ação email deveria abrir a tela de envio: $a"
grep -q '✉ Enviar tarefas por e-mail…' "$RAIZ/tt" || falhou 'o menu do 📋 deveria ter ✉ Enviar tarefas por e-mail…'
passou 'botão ✉ só na tarefa de topo (menu ⋯) e no menu do 📋'

# 6) sem compositor configurado e sem aerc/desktop: imprime o texto (não perde o trabalho)
unset TT_EMAIL_MAILTO_CMD
out=$(unset DISPLAY WAYLAND_DISPLAY; A --tarefa-email "$P" ana@x.com --abrir 2>&1)
grep -q "^Assunto: \[tt\] Planejar viagem ~$P" <<<"$out" && grep -q '^mailto:' <<<"$out" || falhou "sem onde abrir, deveria imprimir o texto e a URL: $out"
passou 'sem compositor disponível: imprime o texto e o link mailto: (nada se perde)'
echo "TODOS OS TESTES PASSARAM"
