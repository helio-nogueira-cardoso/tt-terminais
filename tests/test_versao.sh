#!/usr/bin/env bash
# Versão hierárquica MAIOR.MENOR.PATCH: o arquivo MARCO diz a série e o PATCH conta os commits depois do que
# mudou o MARCO — subir a série zera o da direita. A ORDEM de atualização continua sendo o nº de commits
# (1º campo do VERSAO); o rótulo vai no 4º campo. Repositório local, sem rede.
source "$(dirname "$0")/lib.sh"; isolar
cd "$T"
g() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -C "$1" "${@:2}"; }
fail() { echo "FALHOU: $1" >&2; exit 1; }
git init -q dev; g dev checkout -q -B main 2>/dev/null
for f in tt email-tt.py links-tt.py letreiro-tt.py letreiro-fontes.py letreiro-catalogo.json letreiro-padrao.json gatilho-tt.sh tmux.conf tema-tmux.conf tema-terminal.sh tema-agentes.sh memoria-agentes.sh \
         atalhos-padrao atalhos-padrao-mobile README.md AI-DLC.md ia-conta ia-rot ia-login contas-uso.py \
         skill-rodizio-de-contas.md nomeador-local.py skill-tt-terminais.md skill-celular-android.md agentes-regras-tt.md aidlc-tt NOVIDADES.md pacotes-tt.sh sessoes-ia.py tarefas-merge.py tarefas-merge.vim checagens-tt.md checagem-prompt.md voz voz-audio.py voz-microfone.ps1; do
  [[ -e $RAIZ/$f ]] && cp "$RAIZ/$f" dev/
done
printf 'nome=teste\nrepo=%s\n' "$T/dev" >"$XDG_CONFIG_HOME/tt/config"
rotulo() { "$TT" --pacote | tar -xOf - VERSAO | awk '{ print $4 }'; }
ordem()  { "$TT" --pacote | tar -xOf - VERSAO | awk '{ print $1 }'; }
echo 1.6 >dev/MARCO; g dev add -A; g dev commit -qm base
[[ $(rotulo) == 1.6.0 ]] || fail "o commit que abre a série é PATCH 0 (veio $(rotulo))"
for i in 1 2 3; do echo "x$i" >>dev/README.md; g dev commit -qam "c$i"; done
[[ $(rotulo) == 1.6.3 ]] || fail "3 commits depois: 1.6.3 (veio $(rotulo))"
n=$(ordem)
echo 1.7 >dev/MARCO; g dev commit -qam "série nova"
[[ $(rotulo) == 1.7.0 ]] || fail "subir a série zera o PATCH: 1.7.0 (veio $(rotulo))"
(($(ordem) == n + 1)) || fail "a ordem de atualização continua crescendo (nº de commits)"
echo y >>dev/README.md; g dev commit -qam "depois"
[[ $(rotulo) == 1.7.1 ]] || fail "1.7.1 (veio $(rotulo))"
echo 2.0 >dev/MARCO; [[ $(rotulo) == 2.0.0 ]] || fail "MARCO ainda não gravado já mostra a série nova com PATCH 0 (veio $(rotulo))"
g dev commit -qam "maior"; echo z >>dev/README.md; g dev commit -qam "d"
[[ $(rotulo) == 2.0.1 ]] || fail "2.0.1 (veio $(rotulo))"
echo "ok: PATCH zera quando a série sobe; a ordem de atualização segue crescendo"

# Instalado: o rótulo vem do VERSAO; sem o 4º campo (instalação antiga) cai em 1.6.N.
echo "312 teste 2099-01-01 3.4.5" >"$TT_DIR/VERSAO"
[[ $("$TT" --versao) == "312 teste 2099-01-01 3.4.5" ]] || true
"$TT" --help >"$T/ajuda.txt" 2>&1   # num arquivo: `| grep -q` fecha o cano e o tt recebe SIGPIPE (pipefail) quando a ajuda é longa
grep -q 'Versão instalada: v3.4.5' "$T/ajuda.txt" || fail "ajuda deveria mostrar v3.4.5: $(tail -3 "$T/ajuda.txt")"
echo "312 teste 2099-01-01" >"$TT_DIR/VERSAO"
"$TT" --help >"$T/ajuda.txt" 2>&1
grep -q 'Versão instalada: v1.6.312' "$T/ajuda.txt" || fail "VERSAO antigo deveria cair em v1.6.N"
echo "ok: rótulo vem do VERSAO; instalação antiga cai em 1.6.N"
echo "TODOS OS TESTES PASSARAM"
