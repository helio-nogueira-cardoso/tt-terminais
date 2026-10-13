#!/usr/bin/env bash
# Atualização pelo vigia: a sonda leve (git ls-remote) só busca e instala quando o publicado mudou; a decisão
# é por ancestralidade (publicado que contém o instalado instala; instalado à frente ou divergente com número
# maior não rebaixa); falhas seguidas ficam no estado e, na 3ª, viram um aviso; tt --atualizacao-estado
# explica a situação.
source "$(dirname "$0")/lib.sh"; isolar
export TT_DIR=$HOME/.local/share/tt PATH=$HOME/.local/bin:$PATH TT_SEM_BASHRC=1
G=(git -c user.name=t -c user.email=t@t -c commit.gpgsign=false)
GH=$T/gh; ES=$HOME/.local/state/tt
mkdir -p "$GH"; "${G[@]}" -C "$GH" init -q -b main
for f in "$T"/pkg/*; do [[ ${f##*/} == VERSAO ]] || cp -r "$f" "$GH/"; done
"${G[@]}" -C "$GH" add -A; "${G[@]}" -C "$GH" commit -qm a
echo "fonte=$GH" >>"$XDG_CONFIG_HOME/tt/config"
inst() { awk '{ print $2 }' "$TT_DIR/VERSAO" 2>/dev/null; }
pub() { git -C "$GH" rev-parse --short=7 HEAD; }
estado() { "$HOME/.local/bin/tt" --atualizacao-estado 2>&1; }

# 1) Primeira instalação pela fonte; a sonda com o mesmo SHA não busca nem reinstala.
"$T/pkg/tt" --garantir-atualizacao >/dev/null 2>&1
[[ $(inst) == "$(pub)" ]] || falhou "não instalou a versão publicada: [$(inst)] x [$(pub)]"
touch -d '2000-01-01' "$TT_DIR/tt"
tt --sondar-atualizacao >/dev/null 2>&1
[[ $(stat -c %Y "$TT_DIR/tt") == $(date -d 2000-01-01 +%s) ]] || falhou 'a sonda com o mesmo SHA reinstalou'
grep -q 'em dia' <<<"$(estado)" || falhou "o estado deveria dizer em dia: $(estado)"
grep -qx "  publicada:     $(pub)" <<<"$(estado)" || falhou "a linha da publicada deveria ter o SHA curto uma vez: $(estado)"
passou 'sonda com o SHA igual ao instalado: nada a buscar; estado "em dia"'

# 2) Publicado novo (contém o instalado): a sonda instala.
echo "# novo" >>"$GH/README.md"; "${G[@]}" -C "$GH" commit -qam b
tt --sondar-atualizacao >/dev/null 2>&1
[[ $(inst) == "$(pub)" ]] || falhou "a sonda não instalou o publicado novo: [$(inst)] x [$(pub)]"
passou 'publicado novo que contém o instalado: a sonda instala'

# 3) Instalado à frente do publicado (máquina de desenvolvimento): não mexe, e a sonda seguinte não busca de novo.
"${G[@]}" -C "$GH" checkout -q -b dev; echo "# dev" >>"$GH/README.md"; "${G[@]}" -C "$GH" commit -qam c
C=$(git -C "$GH" rev-parse --short=7 HEAD); "${G[@]}" -C "$GH" checkout -q main
git -C "$HOME/.local/share/tt-fonte" fetch -q origin 2>/dev/null
read -r n _ resto <"$TT_DIR/VERSAO"; echo "$((n + 1)) $C $resto" >"$TT_DIR/VERSAO"
tt --sondar-atualizacao >/dev/null 2>&1
[[ $(inst) == "$C" ]] || falhou "rebaixou uma máquina à frente do publicado: [$(inst)]"
grep -q 'à frente do publicado' <<<"$(estado)" || falhou "o estado deveria dizer à frente: $(estado)"
passou 'instalado à frente do publicado: não rebaixa, e o estado explica'

# 4) Divergente com número maior: não rebaixa (decidido); com número menor, instala o publicado.
"${G[@]}" -C "$GH" checkout -q -b outra HEAD~1; echo "# outra" >>"$GH/tema-tmux.conf"; "${G[@]}" -C "$GH" commit -qam d
D=$(git -C "$GH" rev-parse --short=7 HEAD); "${G[@]}" -C "$GH" checkout -q main
git -C "$HOME/.local/share/tt-fonte" fetch -q origin 2>/dev/null
echo "999 $D $resto" >"$TT_DIR/VERSAO"
tt --garantir-atualizacao >/dev/null 2>&1
[[ $(inst) == "$D" ]] || falhou 'divergente com número maior foi rebaixado'
echo "1 $D $resto" >"$TT_DIR/VERSAO"
tt --garantir-atualizacao >/dev/null 2>&1
[[ $(inst) == "$(pub)" ]] || falhou "divergente com número menor deveria instalar o publicado: [$(inst)]"
passou 'divergente: número maior não rebaixa; número menor converge para o publicado'

# 5) Fonte inalcançável: 3 falhas seguidas viram UM aviso com o motivo; o estado mostra "falhando".
sed -i '/^fonte=/d' "$XDG_CONFIG_HOME/tt/config"; echo "fonte=$T/nao-existe" >>"$XDG_CONFIG_HOME/tt/config"
for i in 1 2 3 4; do tt --sondar-atualizacao >/dev/null 2>&1 || true; done
[[ $(awk -F= '$1 == "falhas" { print $2 }' "$ES/atualizacao") == 4 ]] || falhou "falhas seguidas não contadas: $(cat "$ES/atualizacao")"
n=$(grep -l 'não consegue se atualizar' "$ES"/notifs/* 2>/dev/null | wc -l)
((n == 1)) || falhou "esperava 1 aviso de falha, vi $n"
grep -q 'falhando' <<<"$(estado)" || falhou "o estado deveria mostrar a falha: $(estado)"
grep -q 'fonte= do config' <<<"$(estado)" || falhou 'o estado deveria apontar a fonte fora do oficial'
sed -i '/^fonte=/d' "$XDG_CONFIG_HOME/tt/config"; echo "fonte=$GH" >>"$XDG_CONFIG_HOME/tt/config"
tt --sondar-atualizacao >/dev/null 2>&1
[[ $(awk -F= '$1 == "falhas" { print $2 }' "$ES/atualizacao") == 0 ]] || falhou 'o sucesso deveria zerar as falhas'
passou 'falhas seguidas: contadas, um aviso na 3ª, estado com o motivo; o sucesso zera'

# 6) O vigia usa a sonda leve (git ls-remote) e a busca completa só de 6 em 6 h.
grep -q 'TT_T_SONDA:-300' "$TT_DIR/tt" && grep -q 'TT_T_ATUALIZACAO:-21600' "$TT_DIR/tt" && grep -q -- '--sondar-atualizacao >>' "$TT_DIR/tt" ||
  falhou 'o vigia deveria sondar a cada 5 min e buscar tudo a cada 6 h'
passou 'vigia: sonda a cada 5 min, busca completa a cada 6 h'
