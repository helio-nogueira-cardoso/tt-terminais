#!/usr/bin/env bash
# Instalador do celular (termux/celular.sh) em simulação: percorre todos os passos sem tocar em nada,
# nunca sobrescreve config do usuário e a verificação roda sem Termux.
source "$(dirname "$0")/lib.sh"; isolar
C=$RAIZ/termux/celular.sh
for f in "$C" "$RAIZ/termux/atalhos.sh"; do bash -n "$f" || falhou "sintaxe: $f"; done
for f in "$RAIZ/termux/boot-tt" "$RAIZ/termux/android-ajustes.sh"; do sh -n "$f" || falhou "sintaxe: $f"; done

printf 'nome=meu\nclaude_flags=--minhas\n' >"$XDG_CONFIG_HOME/tt/config"
cp "$XDG_CONFIG_HOME/tt/config" "$T/antes"
saida=$(CELULAR_SIMULAR=1 PREFIX=/data/data/com.termux/files/usr bash "$C" instalar --nome cel 2>&1) ||
  falhou "simulação falhou: $saida"
for passo in 'Pacotes do Termux' 'Barra de teclas' 'SSH' 'Termux:Boot' 'tt (central' 'Debian' 'Falta fazer'; do
  grep -q "$passo" <<<"$saida" || falhou "passo ausente na simulação: $passo"
done
grep -q 'instalar.sh cel' <<<"$saida" || falhou 'nome não chegou ao instalar.sh'
grep -q 'claude_env=IS_SANDBOX=1' <<<"$saida" || falhou 'claude_env padrão não proposto'
grep -q 'claude_flags=' <<<"$saida" && falhou 'proporia sobrescrever claude_flags do usuário'
cmp -s "$T/antes" "$XDG_CONFIG_HOME/tt/config" || falhou 'simulação alterou o config'
[[ -e $HOME/.termux || -e $HOME/.bashrc ]] && falhou 'simulação criou arquivos na home'
passou 'celular: simulação percorre os passos sem alterar nada e respeita o config'

saida=$(bash "$C" verificar 2>&1) || falhou "verificar falhou: $saida"
grep -q 'não é Termux' <<<"$saida" && grep -q 'perfil nunca aplicado' <<<"$saida" || falhou "verificar: $saida"
bash "$C" xyz >/dev/null 2>&1 && falhou 'aceitou comando desconhecido'
passou 'celular: verificar só lê e comando inválido é recusado'

# adb + Shizuku + Tasker: simulação percorre os 6 passos; utilitários e projeto do Tasker válidos.
for f in "$RAIZ"/termux/bin/*; do bash -n "$f" || falhou "sintaxe: $f"; done
python3 -c 'import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
n = [e.findtext("nme") for e in r if e.tag in ("Profile", "Task")]
assert {"tt: ligar modo dev", "tt: desligar modo dev", "tt: abrir no boot", "tt: estado do Wi-Fi"} <= set(n), n
ids = {e.findtext("id") for e in r.iter("Task")}
for p in r.iter("Profile"):
    for m in ("mid0", "mid1"):
        assert p.findtext(m) in ids | {None}, (p.findtext("nme"), m)' "$RAIZ/termux/tasker/tt-celular.prj.xml" ||
  falhou 'projeto do Tasker inválido'
grep -q 'tt.MODO_DEV_ON' "$RAIZ/termux/bin/shizuku-ligar" && grep -q 'tt.MODO_DEV_ON' "$RAIZ/termux/tasker/tt-celular.prj.xml" ||
  falhou 'intent do shizuku-ligar não bate com o perfil do Tasker'
saida=$(CELULAR_SIMULAR=1 PREFIX=/data/data/com.termux/files/usr bash "$C" adb 2>&1 </dev/null) || falhou "adb simulado: $saida"
for passo in '1/6' '2/6' '3/6' '4/6' '5/6' '6/6' 'Depois de um reboot'; do
  grep -q "$passo" <<<"$saida" || falhou "passo ausente no adb: $passo"
done
[[ -e $HOME/.local/bin/adb-local ]] && falhou 'simulação criou links'
passou 'celular: adb/Shizuku/Tasker em simulação, projeto do Tasker coerente com os utilitários'

# voz (opcional): projeto do Tasker válido e gerado pelo script do repositório; ativar/desativar só em simulação.
python3 -c 'import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
n = {e.findtext("nme") for e in r if e.tag in ("Profile", "Task")}
assert {"Terminal", "tt voz: falar", "tt voz: abrir", "tt voz: Android Auto"} <= n, n
ids = {e.findtext("id") for e in r.iter("Task")}
assert all(p.findtext("mid0") in ids for p in r.iter("Profile"))' "$RAIZ/termux/tasker/tt-voz.prj.xml" || falhou 'projeto tt-voz do Tasker inválido'
cp "$RAIZ/termux/tasker/tt-voz.prj.xml" "$T/voz-antes.xml"; python3 -I "$RAIZ/termux/tasker/gerar-voz.py" >/dev/null
cmp -s "$T/voz-antes.xml" "$RAIZ/termux/tasker/tt-voz.prj.xml" || falhou 'tt-voz.prj.xml não bate com gerar-voz.py (rode o gerador)'
grep -q 'tt.VOZ_FALAR' "$RAIZ/voz" && grep -q 'tt.VOZ_FALAR' "$RAIZ/termux/tasker/tt-voz.prj.xml" || falhou 'intent do voz não bate com o perfil do Tasker'
# a 1ª notificação do Android Auto é "Conectando ao Android Auto…": o perfil precisa aceitá-la (as seguintes chegam com ele ocupado)
python3 -c 'import re, sys, html
x = html.unescape(open(sys.argv[1]).read()); m = re.search(r"if \(/([^/]+)/i\.test\(t\)\)", x)
assert m and all(re.search(m.group(1), t, re.I) for t in ("Conectando ao Android Auto", "O Android Auto está conectado")), m' \
  "$RAIZ/termux/tasker/tt-voz.prj.xml" || falhou 'perfil do Android Auto não aceita "Conectando ao Android Auto"'
mkdir -p "$T/semcron"; printf '#!/usr/bin/env bash\nexit 0\n' >"$T/semcron/crontab"; chmod +x "$T/semcron/crontab"  # crontab vazio
saida=$(PATH="$T/semcron:$PATH" CELULAR_SIMULAR=1 PREFIX=/data/data/com.termux/files/usr bash "$C" voz 2>&1 </dev/null) || falhou "voz simulado: $saida"
grep -q 'voz --garantir' <<<"$saida" && grep -q 'tt-voz.prj.xml' <<<"$saida" && grep -q 'seção 15' <<<"$saida" || falhou "voz simulado incompleto: $saida"
[[ -e $HOME/.config/tt-voz/ativo || -e $HOME/.local/bin/voz ]] && falhou 'simulação do voz criou arquivos'
passou 'celular: voz é opcional (projeto válido e em dia, simulação não altera nada)'
