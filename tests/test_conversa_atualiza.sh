#!/usr/bin/env bash
# O painel traz as mensagens novas do tt-mesh (git pull) antes de mostrar a conversa; sem rede, segue sem erro.
source "$(dirname "$0")/lib.sh"; isolar
B="$T/remoto.git"; A="$T/mesh"; P="$T/publicador"
git init -q --bare -b main "$B"
git init -q -b main "$A"; git -C "$A" remote add origin "$B"
git -C "$A" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git -C "$A" push -q -u origin main 2>/dev/null
git clone -q "$B" "$P" 2>/dev/null
mkdir -p "$P/channel"; printf -- '---\nfrom: dono\nto: all\ntopic: recado\n---\nteste de atualizacao\n' >"$P/channel/20990101T000000Z-dono-x1.md"
git -C "$P" add -A && git -C "$P" -c user.email=t@t -c user.name=t commit -q -m "recado" && git -C "$P" push -q origin main 2>/dev/null
TT_MESH="$A" python3 -I -c "import importlib.util,sys; sp=importlib.util.spec_from_file_location('cm','$RAIZ/conversa-mesh.py'); cm=importlib.util.module_from_spec(sp); sp.loader.exec_module(cm); assert cm.atualizar_mesh(), 'a atualização deveria funcionar'" || falhou 'o painel não trouxe a mensagem nova do mesh'
[[ -e "$A/channel/20990101T000000Z-dono-x1.md" ]] || falhou 'a mensagem do dono deveria chegar ao mesh local'
TT_MESH="$T/sem-git" python3 -I -c "import importlib.util,sys; sp=importlib.util.spec_from_file_location('cm','$RAIZ/conversa-mesh.py'); cm=importlib.util.module_from_spec(sp); sp.loader.exec_module(cm); assert cm.atualizar_mesh() is False" || falhou 'sem git, a atualização deveria só dizer que não atualizou'
passou 'painel traz as mensagens novas do mesh e segue sem erro quando não há git'
