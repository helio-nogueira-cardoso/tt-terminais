#!/usr/bin/env bash
# Conversa do tt-mesh (tt --conversa-mesh): lê SÓ o tt-mesh de quem roda (TT_MESH), filtra o dia, usa a persona
# da carta e põe a própria máquina à direita. Isola HOME; o mesh é um falso.
source "$(dirname "$0")/lib.sh"; isolar
M="$T/mesh"; mkdir -p "$M/channel/arquivo"
printf '## Personas\n- **dell** · Vito — coordenador.\n- **mac** · Teo — prático.\n' >"$M/mission.md"
dia=$(date +%F)
hora=$(date -u +%Y%m%dT%H%M%SZ)
printf -- '---\nfrom: dell\nto: all\ntopic: teste de conversa\n---\nOi, Teo, o canal chegou.\n' >"$M/channel/${hora}-dell-a1.md"
printf -- '---\nfrom: mac\nto: all\ntopic: teste de conversa\n---\nRecebido, Vito.\n' >"$M/channel/${hora}-mac-b2.md"
printf -- '---\nfrom: dell\nto: all\ntopic: de outro dia\n---\nisto nao entra\n' >"$M/channel/arquivo/20200101T000000Z-dell-c3.md"
out=$(TT_MESH="$M" TT_MAQUINA=mac python3 -I "$RAIZ/conversa-mesh.py" "$dia")
grep -q 'Vito' <<<"$out" && grep -q 'dell' <<<"$out" || falhou 'a persona da carta deveria dar o nome à máquina'
grep -q 'Oi, Teo' <<<"$out" || falhou 'a mensagem do dia deveria aparecer'
grep -q 'isto nao entra' <<<"$out" && falhou 'mensagem de outro dia não deveria aparecer'
linha_mac=$(grep 'Recebido' <<<"$out"); [[ $linha_mac =~ ^[[:space:]]{14,} ]] || falhou 'a própria máquina deveria ficar à direita'
passou 'conversa do mesh: lê o tt-mesh de quem roda, filtra o dia, usa persona e põe a própria máquina à direita'

# Recado do dono: grava no canal como from: dono, commita no mesh (sem remoto aqui, o push fica pendente).
G="$T/mesh-git"; mkdir -p "$G/channel"; git -C "$G" init -q && git -C "$G" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
out=$(TT_MESH="$G" python3 -I "$RAIZ/conversa-mesh.py" --enviar "reunião amanhã às 9h" 2>&1)
arq=$(ls "$G"/channel/*-dono-*.md 2>/dev/null | head -1)
[[ -n $arq ]] || falhou "o recado deveria virar arquivo no canal: $out"
grep -q '^from: dono$' "$arq" && grep -q 'reunião amanhã' "$arq" || falhou 'recado sem from: dono ou sem o texto'
git -C "$G" log --oneline | grep -q 'recado do dono' || falhou 'o recado deveria ficar commitado no mesh'
passou 'recado do dono: vira mensagem do canal (from: dono) e fica commitado'
