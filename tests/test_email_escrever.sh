#!/usr/bin/env bash
# Escrever bem (compose do aerc): editor padronizado do tt (vim: largura 72 em format=flowed,
# ortografia pt/en quando há dicionário, Ctrl+S salva), avisos de assunto vazio e de anexo
# esquecido, destinatários a partir dos maildirs (+ contatos.tsv à mão; os próprios endereços e os
# automáticos ficam de fora), seletor de anexos (sem terminal lê a entrada padrão), assinatura por
# conta (cadastro CLI e assistente, tt --email-assinatura, bloco do aerc, extra do dono manda,
# remoção), e os binds a/A na revisão. aerc falso; vim real quando existe.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/aerc"; chmod +x "$T/bin/aerc"; export PATH=$T/bin:$PATH
unset VISUAL EDITOR
C=$HOME/.config/aerc/aerc.conf; B=$HOME/.config/aerc/binds.conf
roda() { bash -c "source <(sed -n '/^AERC_BINDS_INI=/,/^remover_aerc() {/p' '$TT' | sed '\$d'); DIR_TT='$TT_DIR'; conf() { :; }; aerc_tema_suportado() { return 1; }; configurar_aerc"; }
v() { awk -v S="$1" -v K="$2" '/^\[.*\]/ { s = $0; gsub(/^\[|\].*$/, "", s); next } s == S && index($0, K "=") == 1 { sub(/^[^=]*=/, ""); print }' "$C"; }

# 1) configurar_aerc: compose do aerc apontando para o tt; idempotente; escolha do dono fica
roda; roda
[[ $(v compose editor) == "$HOME/.local/bin/tt --email-editor" ]] || falhou "editor do compose: $(v compose editor)"
[[ $(v compose format-flowed) == true ]] || falhou 'format-flowed ausente'
[[ $(v compose empty-subject-warning) == true ]] || falhou 'aviso de assunto vazio ausente'
[[ $(v compose no-attachment-warning) == '^[^>]*(anex[oa]|anexei|attach)' ]] || falhou "aviso de anexo esquecido: $(v compose no-attachment-warning)"
[[ $(v compose address-book-cmd) == "$HOME/.local/bin/tt --email-contatos %s" ]] || falhou 'address-book-cmd ausente'
[[ $(v compose file-picker-cmd) == "$HOME/.local/bin/tt --email-anexos-escolher %f" ]] || falhou 'file-picker-cmd ausente'
[[ $(grep -c '^editor=' "$C") == 1 && $(grep -c '^\[compose\]' "$C") == 1 ]] || falhou 'compose duplicado (não idempotente)'
sed -n '/# >>> tt (saída rápida/,$p' "$B" | sed -n '/^\[compose::review\]/,$p' | grep -q '^a = :attach -m<Enter>' || falhou 'a na revisão deveria abrir o seletor de anexos'
sed -n '/# >>> tt (saída rápida/,$p' "$B" | grep -q '^A = :attach<space>' || falhou 'A na revisão deveria pedir o caminho'
printf '[compose]\neditor=nano\n' >"$C"; roda
[[ $(v compose editor) == nano ]] || falhou 'editor escolhido pelo dono foi sobrescrito'
passou 'compose do aerc: editor do tt, format-flowed, avisos, destinatários e anexos pelo tt; a/A na revisão; escolha do dono fica'

# 2) o editor: vim com o trecho de e-mail (largura 72 flowed, ortografia pt quando há dicionário)
cmd=$(TT_EMAIL_EDITOR_MOSTRAR=1 "$TT" --email-editor "$T/msg.eml")
if command -v vim >/dev/null; then
  [[ $cmd == *"vim -u $TT_DIR/vimrc-tt "*"-S $TT_DIR/vimrc-tt-email "*"$T/msg.eml"* ]] || falhou "editor deveria ser o vim do tt + trecho de e-mail: $cmd"
  [[ $cmd == *"tt_spelllang=\\'en\\'"* ]] || falhou "sem dicionário de português deveria corrigir só em inglês: $cmd"
  grep -q '^setlocal textwidth=72 formatoptions+=w' "$TT_DIR/vimrc-tt-email" || falhou 'trecho de e-mail sem largura 72 / format=flowed'
  grep -q '^setlocal spell$' "$TT_DIR/vimrc-tt-email" && grep -q 'spelllang' "$TT_DIR/vimrc-tt-email" || falhou 'trecho de e-mail sem ortografia'
  grep -q 'Ctrl+S salva e volta à revisão' "$TT_DIR/vimrc-tt-email" || falhou 'trecho de e-mail sem a dica de Ctrl+S'
  mkdir -p ~/.vim/spell; printf 'dic' >~/.vim/spell/pt.utf-8.spl
  cmd=$(TT_EMAIL_EDITOR_MOSTRAR=1 "$TT" --email-editor "$T/msg.eml")
  [[ $cmd == *"tt_spelllang=\\'pt_br"*"en\\'"* ]] || falhou "com dicionário deveria corrigir em português e inglês: $cmd"
  # o vim de verdade carrega o trecho sem erro e com as opções certas
  printf 'Oi\n' >"$T/msg.eml"
  timeout 20 vim -u "$TT_DIR/vimrc-tt" --cmd "let g:tt_spelllang='en'" -S "$TT_DIR/vimrc-tt-email" -es \
    -c "redir! > $T/vim.out" -c 'setlocal textwidth? formatoptions? spelllang? filetype? number?' -c 'redir END' -c 'qa!' "$T/msg.eml" </dev/null >/dev/null 2>&1 || true
  o=$(tr -d '\n' <"$T/vim.out" 2>/dev/null)
  [[ $o == *textwidth=72* && $o == *formatoptions=*w* && $o == *spelllang=en* && $o == *filetype=mail* && $o == *nonumber* ]] || falhou "vim não aplicou o trecho de e-mail: $o"
  passou 'editor: vim do tt + e-mail (largura 72 em format=flowed, ortografia pt/en conforme o dicionário, sem números de linha), carregado pelo vim real'
else
  echo "(sem vim aqui: parte do editor pulada)"
fi
cmd=$(EDITOR=nano TT_EMAIL_EDITOR_MOSTRAR=1 "$TT" --email-editor "$T/msg.eml")
[[ $cmd == "nano -r 72 $T/msg.eml "* ]] || falhou "com EDITOR=nano deveria ser nano -r 72: $cmd"
cmd=$(EDITOR=emacs TT_EMAIL_EDITOR_MOSTRAR=1 "$TT" --email-editor "$T/msg.eml")
[[ $cmd == "emacs $T/msg.eml "* ]] || falhou "outro editor do dono deveria ficar como está: $cmd"
passou 'editor: EDITOR do dono manda (nano ganha a largura 72; outros ficam como estão)'

# 3) destinatários: índice dos maildirs, os próprios e os automáticos fora; busca; manuais primeiro
echo 'S' | "$TT" --email-adicionar nome=Pessoal endereco=eu@gmail.com provedor=gmail auth=senha --senha-stdin >/dev/null || falhou 'cadastro'
md=$HOME/.cache/tt/maildir/pessoal; mkdir -p "$md/INBOX/cur" "$md/INBOX/new" "$md/Enviados/cur"
m() { printf 'From: %s\nTo: %s\nSubject: x\nDate: Wed, 08 Oct 2026 10:00:00 +0000\n\ncorpo com joao@x.com no corpo nao conta\n' "$1" "$2" >"$3"; }
m 'João Silva <joao@x.com>' 'eu@gmail.com' "$md/INBOX/cur/1:2,S"
m 'Maria <maria@y.org>' 'eu@gmail.com' "$md/INBOX/cur/2:2,S"
m '=?utf-8?q?Maria_Jos=C3=A9?= <maria@y.org>' 'Eu <eu@gmail.com>' "$md/INBOX/new/3"
m 'eu@gmail.com' 'Pedro <pedro@z.net>, "noreply@loja.com" <noreply@loja.com>' "$md/Enviados/cur/4:2,S"
m 'Maria <maria@y.org>' 'eu@gmail.com' "$md/INBOX/cur/5:2,S"
"$TT" --email-contatos-indexar || falhou 'indexar'
idx=$HOME/.cache/tt/email-contatos.tsv
[[ $(head -1 "$idx") == $'maria@y.org\tMaria\t3' ]] || falhou "o mais frequente deveria vir primeiro, com o nome mais usado: $(cat "$idx")"
grep -q $'^joao@x.com\tJoão Silva\t1$' "$idx" || falhou "joao ausente/errado: $(cat "$idx")"
grep -q $'^pedro@z.net\tPedro\t1$' "$idx" || falhou "destinatário de e-mail enviado ausente: $(cat "$idx")"
grep -q 'eu@gmail.com' "$idx" && falhou 'o próprio endereço não deveria entrar'
grep -q 'noreply' "$idx" && falhou 'endereço automático não deveria entrar'
[[ $("$TT" --email-contatos mar) == $'maria@y.org\tMaria' ]] || falhou "busca por 'mar': $("$TT" --email-contatos mar)"
[[ $("$TT" --email-contatos SILVA) == $'joao@x.com\tJoão Silva' ]] || falhou 'busca pelo nome, sem distinguir maiúsculas'
[[ $("$TT" --email-contatos '' | head -1) == $'maria@y.org\tMaria' ]] || falhou 'sem texto: todos, os mais frequentes primeiro'
printf '# meus\nana@w.com\tAna Maria\n' >"$HOME/.config/tt/email/contatos.tsv"
[[ $("$TT" --email-contatos maria | head -1) == $'ana@w.com\tAna Maria' ]] || falhou "contato manual deveria vir primeiro: $("$TT" --email-contatos maria)"
[[ $("$TT" --email-contatos maria | wc -l) == 2 ]] || falhou 'manual + índice, sem repetir'
passou 'destinatários: índice dos maildirs (nome mais usado, frequência), próprios e automáticos fora, busca sem maiúsculas, manuais primeiro'

# 4) seletor de anexos sem terminal: lê a entrada padrão, uma linha por arquivo, e grava onde o aerc pediu
printf '/tmp/a.pdf\n\n/tmp/b c.png\n' | "$TT" --email-anexos-escolher "$T/sel" || falhou 'seletor'
[[ $(cat "$T/sel") == $'/tmp/a.pdf\n/tmp/b c.png' ]] || falhou "seleção gravada errada: $(cat "$T/sel")"
passou 'seletor de anexos grava os escolhidos no arquivo do aerc (%f)'

# 5) assinatura por conta: CLI, tt --email-assinatura (várias linhas), vazio tira, extra do dono manda, assistente, remoção
A=$HOME/.config/aerc/accounts.conf
echo 'S' | "$TT" --email-adicionar nome=Sig endereco=sig@gmail.com provedor=gmail auth=senha 'assinatura=— Hélio' --senha-stdin >/dev/null || falhou 'cadastro com assinatura'
f=$HOME/.config/tt/email/sig.assinatura
[[ $(cat "$f") == '— Hélio' ]] || falhou 'assinatura do cadastro CLI não gravada'
grep -q "^signature-file *= $f$" "$A" || falhou "bloco do aerc sem signature-file: $(grep -A12 'tt e-mail: sig >>>' "$A")"
grep -q '^assinatura=' "$HOME/.config/tt/email/sig.conf" && falhou 'assinatura= não deveria ir para o .conf'
printf 'Atenciosamente,\nHélio Cardoso\n' | "$TT" --email-assinatura Sig | grep -q '2 linhas' || falhou 'tt --email-assinatura (2 linhas)'
[[ $(cat "$f") == $'Atenciosamente,\nHélio Cardoso' ]] || falhou 'assinatura de várias linhas não gravada'
printf '' | "$TT" --email-assinatura Sig | grep -q 'sem assinatura' || falhou 'vazio deveria tirar a assinatura'
[[ -e $f ]] && falhou 'arquivo de assinatura vazio deveria ser removido'
grep -q 'signature-file' "$A" && falhou 'signature-file ficou no bloco sem assinatura'
echo 'S' | "$TT" --email-adicionar nome=Extra endereco=ex@gmail.com provedor=gmail auth=senha 'extra_1=signature-cmd = echo x' assinatura=y --senha-stdin >/dev/null || falhou 'cadastro extra'
grep -q '^signature-cmd = echo x$' "$A" || falhou 'extra do dono (signature-cmd) sumiu'
sed -n '/tt e-mail: extra >>>/,/tt e-mail: extra <<</p' "$A" | grep -q 'signature-file' && falhou 'com signature-cmd do dono o tt não deveria pôr signature-file'
printf 'gmail\nnovo@gmail.com\nNovo\nsenha\nS\nS\nAbraços, Hélio\n' | "$TT" --email-conta-nova-ui >/dev/null 2>&1
[[ $(cat "$HOME/.config/tt/email/novo.assinatura" 2>/dev/null) == 'Abraços, Hélio' ]] || falhou 'assistente: assinatura não gravada'
grep -q "^signature-file *= $HOME/.config/tt/email/novo.assinatura$" "$A" || falhou 'assistente: bloco sem signature-file'
"$TT" --email-remover Novo >/dev/null || falhou 'remover'
[[ -e $HOME/.config/tt/email/novo.assinatura ]] && falhou 'remover deveria apagar a assinatura'
passou 'assinatura por conta: cadastro CLI e assistente, várias linhas por tt --email-assinatura, vazio tira, signature-cmd do dono manda, remoção limpa'

echo 'ok: escrever bem — editor padronizado, avisos, destinatários, anexos e assinatura'
