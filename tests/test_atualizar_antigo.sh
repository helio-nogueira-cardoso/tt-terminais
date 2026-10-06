#!/usr/bin/env bash
# Um tt antigo (instalado de um clone, como manda o README) precisa conseguir se atualizar sozinho
# para a versão publicada, mesmo quando ela tem arquivos que ele não conhece. O pacote é montado com
# a lista de arquivos da versão velha; a v124 trouxe o email-tt.py e, sem completar o pacote, o tt
# novo o recusava como incompleto: toda máquina de fora parou de se atualizar.
source "$(dirname "$0")/lib.sh"; isolar
REPO=$(cd "$(dirname "$0")/.." && pwd)
VELHO=52e8574^ # última versão sem email-tt.py
git -C "$REPO" rev-parse -q --verify "$VELHO^{commit}" >/dev/null 2>&1 || { echo "(histórico sem $VELHO: teste pulado)"; exit 0; }
export TT_DIR=$HOME/.local/share/tt PATH=$HOME/.local/bin:$PATH
G=(git -c user.name=t -c user.email=t@t)

# Clone do amigo: versão velha, instalada com ./tt --instalar (grava repo= no config).
mkdir -p "$T/clone"; git -C "$REPO" archive "$VELHO" | tar -x -C "$T/clone"
(cd "$T/clone" && "${G[@]}" init -q && "${G[@]}" add -A && "${G[@]}" commit -qm v1 && TT_SEM_BASHRC=1 ./tt --instalar V1) >/dev/null 2>&1
[[ $(awk '{print $1}' "$TT_DIR/VERSAO" 2>/dev/null) == 1 ]] || falhou 'instalação da versão velha'

# "GitHub": a versão atual (arquivos do pacote em teste), dois commits → versão 2.
mkdir -p "$T/gh"; "${G[@]}" -C "$T/gh" init -q; "${G[@]}" -C "$T/gh" commit -q --allow-empty -m a
(cd "$T/pkg" && cp tt email-tt.py tmux.conf tema-tmux.conf tema-terminal.sh tema-agentes.sh memoria-agentes.sh \
  atalhos-padrao atalhos-padrao-mobile README.md AI-DLC.md "$T/gh/")
"${G[@]}" -C "$T/gh" add -A; "${G[@]}" -C "$T/gh" commit -qm b
echo "fonte=$T/gh" >>"$XDG_CONFIG_HOME/tt/config"

saida=$("$HOME/.local/bin/tt" --garantir-atualizacao 2>&1)
[[ $(awk '{print $1}' "$TT_DIR/VERSAO") == 2 ]] || falhou "tt velho não se atualizou: $saida"
[[ -s $TT_DIR/email-tt.py ]] || falhou 'arquivo novo (email-tt.py) não veio na atualização'
cmp -s "$TT_DIR/tt" "$T/gh/tt" || falhou 'tt instalado difere do publicado'
passou 'tt antigo se atualiza sozinho mesmo com arquivos novos no pacote'
