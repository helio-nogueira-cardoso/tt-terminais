#!/usr/bin/env bash
# Conversa do tt-mesh (tt --conversa-mesh): lê SÓ o tt-mesh de quem roda (TT_MESH), filtra o dia, usa a persona
# da carta e põe a própria máquina à direita. Isola HOME; o mesh é um falso.
source "$(dirname "$0")/lib.sh"; isolar
M="$T/mesh"; mkdir -p "$M/channel/arquivo"
printf '## Personas\n- **dell** · Vito — coordenador.\n- **mac** · Teo — prático.\n- **book** · Ana Lúcia — detalhista.\n- **s23** · Lua\n' >"$M/mission.md"
dia=$(date +%F)
hora=$(date -u +%Y%m%dT%H%M%SZ)
printf -- '---\nfrom: dell\nto: all\ntopic: teste de conversa\n---\nOi, Teo, o canal chegou.\n' >"$M/channel/${hora}-dell-a1.md"
printf -- '---\nfrom: mac\nto: all\ntopic: teste de conversa\n---\nRecebido, Vito.\n' >"$M/channel/${hora}-mac-b2.md"
printf -- '---\nfrom: dono\nto: all\ntopic: teste de conversa\n---\nMensagem minha do dono.\n' >"$M/channel/${hora}-dono-b3.md"
printf -- '---\nfrom: dell\nto: all\ntopic: de outro dia\n---\nisto nao entra\n' >"$M/channel/arquivo/20200101T000000Z-dell-c3.md"
out=$(TT_MESH="$M" TT_MAQUINA=mac python3 -I "$RAIZ/conversa-mesh.py" "$dia")
grep -q 'Vito' <<<"$out" && grep -q 'dell' <<<"$out" || falhou 'a persona da carta deveria dar o nome à máquina'
grep -q 'Oi, Teo' <<<"$out" || falhou 'a mensagem do dia deveria aparecer'
grep -q 'isto nao entra' <<<"$out" && falhou 'mensagem de outro dia não deveria aparecer'
linha_dono=$(grep 'Mensagem minha' <<<"$out"); [[ $linha_dono =~ ^[[:space:]]{8,} ]] || falhou 'a mensagem do dono deveria ficar à direita'
linha_mac=$(grep 'Recebido' <<<"$out"); [[ $linha_mac =~ ^[[:space:]]{8,} ]] && falhou 'mensagem de outra máquina não deve ficar à direita'
passou 'conversa do mesh: lê o tt-mesh de quem roda, filtra o dia, usa persona e põe a própria máquina à direita'

# Nome de persona com mais de uma palavra sai inteiro (até o travessão da descrição), com acento.
printf -- '---\nfrom: book\nto: all\ntopic: nome composto\n---\nOi do book.\n' >"$M/channel/${hora}-book-d4.md"
printf -- '---\nfrom: s23\nto: all\ntopic: nome composto\n---\nOi do celular.\n' >"$M/channel/${hora}-s23-d5.md"
out=$(TT_MESH="$M" TT_MAQUINA=mac python3 -I "$RAIZ/conversa-mesh.py" "$dia")
grep -q 'Ana Lúcia' <<<"$out" || falhou "nome composto da persona deveria sair inteiro: $out"
grep -q 'Lua' <<<"$out" || falhou 'persona sem descrição deveria sair'
passou 'persona com nome composto (Ana Lúcia) e sem descrição saem inteiras'

# Recado do dono: grava no canal como from: dono, commita no mesh (sem remoto aqui, o push fica pendente).
G="$T/mesh-git"; mkdir -p "$G/channel"; git -C "$G" init -q && git -C "$G" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
out=$(TT_MESH="$G" python3 -I "$RAIZ/conversa-mesh.py" --enviar "reunião amanhã às 9h" 2>&1)
arq=$(ls "$G"/channel/*-dono-*.md 2>/dev/null | head -1)
[[ -n $arq ]] || falhou "o recado deveria virar arquivo no canal: $out"
grep -q '^from: dono$' "$arq" && grep -q 'reunião amanhã' "$arq" || falhou 'recado sem from: dono ou sem o texto'
git -C "$G" log --oneline | grep -q 'recado do dono' || falhou 'o recado deveria ficar commitado no mesh'
passou 'recado do dono: vira mensagem do canal (from: dono) e fica commitado'

# Rolagem (painel): a janela visível anda para trás e não passa do começo nem do fim.
python3 -I - "$RAIZ/conversa-mesh.py" <<'PY' || falhou 'janela de rolagem errada'
import importlib.util, sys
sp = importlib.util.spec_from_file_location("cm", sys.argv[1]); cm = importlib.util.module_from_spec(sp); sp.loader.exec_module(cm)
linhas = [str(i) for i in range(10)]
v, d = cm.janela(linhas, 4, 0); assert v == ["6", "7", "8", "9"] and d == 0, (v, d)
v, d = cm.janela(linhas, 4, 3); assert v == ["3", "4", "5", "6"] and d == 3, (v, d)
v, d = cm.janela(linhas, 4, 99); assert v == ["0", "1", "2", "3"] and d == 6, (v, d)
PY
passou 'rolagem do painel: a janela anda para trás e para nas pontas'

# Largura visual: caracteres largos, emoji e marcas combinantes não podem quebrar balões ou cliques.
python3 -I - "$RAIZ/conversa-mesh.py" <<'PY' || falhou 'medição de colunas Unicode errada'
import importlib.util, sys
sp = importlib.util.spec_from_file_location("cm", sys.argv[1]); cm = importlib.util.module_from_spec(sp); sp.loader.exec_module(cm)
assert cm.largura_visual("é 界 🙂") == 7
assert cm.largura_visual("e\u0301") == 1
assert cm.largura_visual("👩🏽‍💻 🇧🇷") == 5
assert cm.largura_visual("\x1b[31m界\x1b[0m") == 2
for texto in ("texto com palavras", "漢字とemoji 🙂🙂", "e\u0301" * 20, "x" * 40):
    for linha in cm.quebrar_visual(texto, 8):
        assert cm.largura_visual(linha) <= 8, repr(linha)
for eu in (True, False):
    for linha in cm._balao(cm.quebrar_visual("漢字とemoji 🙂🙂", 8), eu, 16):
        assert cm.largura_visual(linha) <= 16, repr(linha)
PY
passou 'conversa do mesh: largura de balões e quebra contam colunas Unicode'

# O clique no botão Tick usa as dimensões reais do PTY e chama o tt local.
python3 -I - "$RAIZ/conversa-mesh.py" "$T" <<'PY' || falhou 'clique no botão Tick não abriu o menu'
import fcntl, os, pty, select, struct, subprocess, sys, termios, time
script, raiz = sys.argv[1:]
marcador = os.path.join(raiz, "tick-abriu")
fake = os.path.join(raiz, "tt-falso-painel")
with open(fake, "w", encoding="utf-8") as f:
    f.write("#!/bin/sh\nprintf '%s\\n' \"$*\" >>\"" + marcador + "\"\n")
os.chmod(fake, 0o755)
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 60, 0, 0))
env = dict(os.environ, TT_MESH=os.path.join(raiz, "mesh"), TT_BIN=fake, TT_CORES="0")
os.makedirs(os.path.join(env["TT_MESH"], "channel"), exist_ok=True)
p = subprocess.Popen([sys.executable, "-I", script, "--painel"], stdin=slave, stdout=slave, stderr=slave, env=env, close_fds=True)
os.close(slave)
saida = bytearray()
deadline = time.monotonic() + 3
while time.monotonic() < deadline and b"tick" not in saida:
    if select.select([master], [], [], 0.1)[0]:
        try: saida.extend(os.read(master, 4096))
        except OSError: break
assert b"tick" in saida, "painel não desenhou o botão"
inicio = len(saida)
os.write(master, b"a")
deadline = time.monotonic() + 3
while time.monotonic() < deadline and b"\xe2\x9e\xa4 a\x1b[K" not in saida[inicio:]:
    if select.select([master], [], [], 0.1)[0]:
        try: saida.extend(os.read(master, 4096))
        except OSError: break
delta = bytes(saida[inicio:])
assert b"\xe2\x9e\xa4 a\x1b[K" in delta, "tecla não apareceu no campo de mensagem"
assert b"\x1b[1;1H" not in delta, "digitar repintou a tela inteira"
os.write(master, b"\x1b[<0;20;21M\x1b[<0;20;21m")
deadline = time.monotonic() + 3
while time.monotonic() < deadline and not os.path.exists(marcador):
    if select.select([master], [], [], 0.1)[0]:
        try: saida.extend(os.read(master, 4096))
        except OSError: break
assert os.path.exists(marcador), f"clique não chamou TT_BIN --mesh-tick-menu; rc={p.poll()}, saída={bytes(saida[-1000:])!r}"
time.sleep(0.1)
os.write(master, b"\x1b")
try: p.wait(timeout=5)
except subprocess.TimeoutExpired: p.kill(); raise
os.close(master)
PY
passou 'conversa do mesh: botão Tick abre o menu pelo clique SGR'

# Recado publicado dispara o puxar nas outras máquinas (tt --mesh-puxar), para ficar disponível na hora.
fake="$T/tt-falso"; printf '#!/bin/sh\necho "$@" >>"%s/puxou"\n' "$T" >"$fake"; chmod +x "$fake"
R="$T/remoto-tick.git"; L="$T/local-tick"
git init -q --bare -b main "$R"; git init -q -b main "$L"; git -C "$L" remote add origin "$R"
git -C "$L" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base; git -C "$L" push -q -u origin main 2>/dev/null
mkdir -p "$L/channel"
TT_MESH="$L" TT_BIN="$fake" python3 -I "$RAIZ/conversa-mesh.py" --enviar "oi do dono" >/dev/null
for _ in $(seq 1 40); do [[ -s $T/puxou ]] && break; sleep 0.1; done
grep -q -- '--mesh-puxar' "$T/puxou" 2>/dev/null || falhou 'publicar o recado deveria pedir o puxar nas outras máquinas'
passou 'recado publicado: pede às outras máquinas que puxem o mesh na hora'

# Horário no nome do arquivo no futuro (estimado por quem escreveu): o painel mostra a hora real da gravação.
F=$(date -u -d "+3 hours" +%Y%m%dT%H%M%SZ)
printf -- '---\nfrom: mac\nto: all\ntopic: horario\n---\nmensagem com horario futuro\n' >"$M/channel/${F}-mac-f9.md"
out=$(TT_MESH="$M" TT_MAQUINA=mac python3 -I "$RAIZ/conversa-mesh.py" "$dia")
hora_real=$(date +%H:%M); grep -q "$hora_real" <<<"$out" || falhou 'horário no futuro: o painel deveria mostrar a hora real'
passou 'horário no futuro no nome: o painel mostra a hora real da gravação'
