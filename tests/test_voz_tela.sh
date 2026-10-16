#!/usr/bin/env bash
# 🎤 nos computadores: o voz no pacote, o canal da janela (voz --turno com VOZ_TELA_FD), o cérebro padrão, a escolha do
# gravador e da voz em Linux, macOS e WSL (voz-audio.py com VOZ_SISTEMA e programas falsos), a gravação até o silêncio,
# a janela da conversa num tmux isolado (microfone, transcrição e voz falsos) e o atalho @janela do tt (Ctrl+B v).
# Nada usa microfone, alto-falante, modelo ou Claude de verdade.
source "$(dirname "$0")/lib.sh"; isolar
V=$RAIZ/voz; A=$RAIZ/voz-audio.py
bash -n "$V" || falhou "sintaxe: $V"
python3 -m py_compile "$A" || falhou "sintaxe: $A"

B=$T/fake; mkdir -p "$B"
cat >"$B/tt" <<'FIM'
#!/usr/bin/env bash
case $1 in
  --maquinas) printf 'u@h1 dell\nu@h2 book\n' ;;
  --saude) printf 'Saude das maquinas cadastradas:\n  \033[32m●\033[0m dell             ok\n  \033[31m●\033[0m book             timeout\n  ● units locais     0 em falha\n' ;;
  --listar-tudo) printf '# mestre de obras — mesa — 20260101T000000Z\n' ;;
esac
FIM
chmod +x "$B"/*
export PATH="$B:$PATH"

# --- o voz no pacote e no PATH; no celular, o termux/bin/voz roda o da raiz
grep -qE '^ARQUIVOS_FONTE=.*' "$RAIZ/tt" && sed -n '/^ARQUIVOS_FONTE=(/,/)/p' "$RAIZ/tt" | grep -qw 'voz-audio.py' &&
  sed -n '/^ARQUIVOS_FONTE=(/,/)/p' "$RAIZ/tt" | grep -qE '(^| )voz( |$)' || falhou 'voz e voz-audio.py fora do ARQUIVOS_FONTE'
[[ $(TT_DIR=/nada bash "$RAIZ/termux/bin/voz" --destino dell) == u@h1 ]] || falhou 'termux/bin/voz não roda o voz da raiz'
mkdir -p "$T/pacote"; printf 'echo "do pacote: $*"\n' >"$T/pacote/voz"
[[ $(TT_DIR=$T/pacote bash "$RAIZ/termux/bin/voz" status) == 'do pacote: status' ]] || falhou 'termux/bin/voz deveria preferir o voz do tt instalado'
[[ $(head -1 "$V") == '#!/usr/bin/env bash' ]] || falhou 'o voz da raiz precisa de um shebang que valha fora do Termux'
passou 'voz no pacote (raiz); o atalho do celular roda o do tt instalado (atualizado sozinho) ou o da raiz'

# --- canal da janela: "tipo<TAB>texto" no fd VOZ_TELA_FD; fim encerra; status sem a linha "units"
ev=$(VOZ_TELA_FD=3 bash "$V" --turno maquinas 3>&1 >/dev/null)
[[ $ev == $'fala\tMáquinas: dell, book, mesa. Atual: mesa.' ]] || falhou "evento da fala: '$ev'"
ev=$(VOZ_TELA_FD=3 bash "$V" --turno status 3>&1 >/dev/null)
[[ $ev == $'fala\tmesa, esta, ok. dell ok. book fora do ar.' ]] || falhou "status (sem units, com esta máquina): '$ev'"
ev=$(VOZ_TELA_FD=3 bash "$V" --turno encerrar 3>&1 >/dev/null)
[[ $ev == $'fim\tTerminal encerrado.' ]] || falhou "evento de fim: '$ev'"
grep -q 'você: encerrar' "$HOME/.local/state/tt-voz/conversa.log" && grep -q 'tt: Terminal encerrado.' "$HOME/.local/state/tt-voz/conversa.log" ||
  falhou "conversa.log: $(cat "$HOME/.local/state/tt-voz/conversa.log")"
# o cérebro junta as falas da volta numa só (um evento), e o pedido diz que é o computador
printf '%s' '{"fala": "", "acoes": [{"acao": "status"}]}' >"$T/plano.json"
ev=$(VOZ_TELA_FD=3 VOZ_CEREBRO_CMD="cat > '$T/pedido.txt'; cat '$T/plano.json'" bash "$V" --turno "quem está ligado agora" 3>&1 >/dev/null)
[[ $ev == $'fala\tmesa, esta, ok. dell ok. book fora do ar.' ]] || falhou "cérebro na janela: '$ev'"
grep -q 'microfone do computador' "$T/pedido.txt" || falhou 'o pedido ao cérebro não diz que a conversa é no computador'
passou 'voz --turno: falas, fim e o cérebro chegam à janela pelo VOZ_TELA_FD; status só com as máquinas'

# --- cérebro padrão da janela: o Claude desta máquina (ia-rot), sem configuração; "-" desliga
printf '#!/usr/bin/env bash\necho "$*" >>%q; cat >/dev/null; echo %q\n' "$T/ia-rot.log" '{"fala": "Do cérebro local.", "acoes": []}' >"$B/ia-rot"; chmod +x "$B/ia-rot"
[[ $(VOZ_CEREBRO_PADRAO=local bash "$V" --turno "uma frase solta qualquer") == *'Do cérebro local.'* ]] || falhou 'VOZ_CEREBRO_PADRAO=local não usou o ia-rot'
r=$(bash "$V" --audio 2>/dev/null | tail -1); [[ $r == 'cérebro: local (sonnet)' ]] || falhou "voz --audio (cérebro padrão com ia-rot): '$r'"
[[ $(tail -1 "$T/ia-rot.log") == '-p --model sonnet' ]] || falhou "o cérebro deveria ser o Sonnet: $(cat "$T/ia-rot.log")"
bash "$V" --cerebro-modelo haiku >/dev/null; VOZ_CEREBRO_PADRAO=local bash "$V" --turno "outra frase solta" >/dev/null
[[ $(tail -1 "$T/ia-rot.log") == '-p --model haiku' ]] || falhou "voz --cerebro-modelo haiku não trocou: $(tail -1 "$T/ia-rot.log")"
bash "$V" --cerebro-modelo 'x;y' >/dev/null 2>&1 && falhou 'modelo com caracteres estranhos aceito'
bash "$V" --cerebro-modelo padrao >/dev/null
bash "$V" --cerebro - >/dev/null
[[ $(VOZ_CEREBRO_PADRAO=local bash "$V" --turno "uma frase solta qualquer") != *'Do cérebro local.'* ]] || falhou '--cerebro - não desligou o padrão'
r=$(bash "$V" --audio 2>/dev/null | tail -1); [[ $r == 'cérebro: (sonnet)' ]] || falhou "voz --audio com o cérebro desligado: '$r'"
rm -f "$HOME/.config/tt-voz/cerebro" "$B/ia-rot"
passou 'cérebro: na janela, sem configuração, o Sonnet desta máquina; voz --cerebro-modelo troca; voz --cerebro - desliga'

# --- voz-audio.py: escolha do gravador e da voz por sistema
py() { python3 - "$A" "$@"; }
CARREGA='import importlib.util, sys
s = importlib.util.spec_from_file_location("va", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)'
F=$T/f2; mkdir -p "$F"
cat >"$F/parecord" <<'FIM'
#!/bin/sh
sleep 5
FIM
cat >"$F/pw-record" <<'FIM'
#!/bin/sh
head -c 64000 /dev/zero; sleep 5
FIM
cat >"$F/arecord" <<'FIM'
#!/bin/sh
case " $* " in
  *" -l "*) printf 'card 1: Fake [Fake], device 0: Mic (*) []\n' ;;
  *plughw:1,0*) head -c 64000 /dev/urandom; sleep 5 ;;
  *) echo 'arecord: main:850: audio open error: Host is down' >&2; exit 1 ;;
esac
FIM
printf '#!/bin/sh\nexit 0\n' >"$F/pactl"  # sem fontes do PulseAudio
chmod +x "$F"/*
r=$(PATH="$F:$PATH" VOZ_SISTEMA=Linux VOZ_PROVA_S=0.6 py <<EOF
$CARREGA
g = m.Gravador(); print(g.escolher(), g.nome); g.fechar()
EOF
)
[[ $r == 'True arecord hw:1,0 (Mic (*))' ]] ||
  falhou "gravador: o servidor de som mudo e o sem sinal ficam de fora, o microfone direto vale: '$r'"
# fontes do PulseAudio: o conector de fone vazio ("not available") e os monitores saem; o filtro virtual só com sinal
cat >"$F/pactl" <<'FIM'
#!/bin/sh
case "$*" in
  get-default-source) echo alsa_input.dmic ;;
  "list sources") cat <<'L'
Source #1
	Name: effect_output.eq
	Description: Headset EQ Mic
	Monitor of Sink: n/a
	Properties:
		node.virtual = "true"
Source #2
	Name: alsa_output.hdmi.monitor
	Description: Monitor of HDMI
	Monitor of Sink: alsa_output.hdmi
Source #3
	Name: alsa_input.headset
	Description: Headset Mono Microphone
	Monitor of Sink: n/a
	Ports:
		[In] Headset: Headset Mono Microphone (type: Headset, priority: 300, not available)
	Active Port: [In] Headset
Source #4
	Name: alsa_input.dmic
	Description: Digital Microphone
	Monitor of Sink: n/a
	Ports:
		[In] Mic1: Digital Microphone (type: Mic, priority: 100, availability unknown)
	Active Port: [In] Mic1
Source #5
	Name: bluez_input.fone
	Description: Fone JBL Bluetooth
	Monitor of Sink: n/a
L
  ;;
esac
FIM
chmod +x "$F/pactl"
r=$(PATH="$F:$PATH" VOZ_SISTEMA=Linux py <<EOF
$CARREGA
for c in m.candidatos_gravador()[:4]: print(c.nome, c.nota, c.padrao, c.cmd[1] if c.cmd[0] == "parecord" else "")
EOF
)
[[ $r == "Fone JBL Bluetooth 300 False --device=bluez_input.fone
Digital Microphone -100 True --device=alsa_input.dmic
Headset EQ Mic (filtro) -100 False --device=effect_output.eq
parecord (fonte padrão) -150 False --raw" ]] || falhou "fontes do PulseAudio: '$r'"
printf '#!/bin/sh\nexit 0\n' >"$F/pactl"
passou 'microfones: o fone primeiro, o embutido depois, o genérico por último; conector vazio, monitor e filtro sem sinal ficam de fora'

cat >"$F/say" <<'FIM'
#!/bin/sh
if [ "$1" = -v ] && [ "$2" = '?' ]; then printf 'Alex                en_US    # Hello\nLuciana             pt_BR    # Olá, meu nome é Luciana\n'; exit 0; fi
if [ "$1" = -a ] && [ "$2" = '?' ]; then printf '   41 MacBook Pro Speakers\n   73 AirPods Pro\n'; exit 0; fi
echo "$*" >>"$SAY_LOG"
FIM
cat >"$F/sox" <<'FIM'
#!/bin/sh
sleep 5
FIM
cat >"$F/powershell.exe" <<'FIM'
#!/bin/sh
printf '%s\n' "$@" >"$PS_LOG"
FIM
chmod +x "$F"/*
r=$(PATH="$F:$PATH" VOZ_SISTEMA=Darwin SAY_LOG=$T/say.log py <<EOF
$CARREGA
print(m.candidatos_gravador()[0].cmd[:3])
f = m.Falador(); print(f.qual, f.det, "|", f.onde); f.falar("Olá do Mac")
f = m.Falador(mic="MacBook Pro Microphone"); f.falar("pelo alto-falante")
EOF
)
[[ $r == $'[\'sox\', \'-q\', \'-d\']\nsay say Luciana | AirPods Pro' ]] || falhou "macOS: gravar pelo sox e falar pelo say com a Luciana: '$r'"
[[ $(<"$T/say.log") == $'-v Luciana -a 73 Olá do Mac\n-v Luciana -a 41 pelo alto-falante' ]] ||
  falhou "say: os AirPods sem microfone escolhido; com o microfone do MacBook, o alto-falante dele: $(cat "$T/say.log")"
passou 'macOS: grava pelo sox e fala pelo say com a voz pt-BR, no aparelho do microfone (sem ele, o fone)'

: >"$T/sock"
r=$(PATH="$F:$PATH" VOZ_SISTEMA=WSL VOZ_WSLG=$T/sock PS_LOG=$T/ps.log env -u PULSE_SERVER python3 - "$A" <<EOF
$CARREGA
import os
c = m.candidatos_gravador(); print(c[0].cmd[0], os.environ.get("PULSE_SERVER"))
EOF
)
[[ $r == "parecord unix:$T/sock" ]] || falhou "WSL: gravar pelo PulseAudio do WSLg: '$r'"
# a voz do Windows num processo só, no aparelho do microfone (o padrão do Windows aí é a saída P2, não o headset)
cat >"$F/ps-fala" <<'FIM'
#!/bin/sh
case "$*" in *" falar") ;; *) exit 1 ;; esac
printf '0\tpadrao\tHeadphones (Realtek(R) Audio)\tHeadphones (Realtek(R) Audio)\r\n1\t\tSpeakers (Realtek(R) Audio)\tSpeakers (Realtek(R) Audio)\r\n2\tcomunicacao\tHeadphones (BlackShark V2 Pro P\tHeadphones (BlackShark V2 Pro PS 2.4)\r\n--\r\n'
while IFS= read -r l; do echo "$l" >>"$PS_LOG"; case $l in F*|T*) echo fim ;; esac; done
FIM
chmod +x "$F/ps-fala"
: >"$T/ps.log"
r=$(PATH="$F:$PATH" VOZ_SISTEMA=WSL VOZ_POWERSHELL="$F/ps-fala" PS_LOG=$T/ps.log py <<EOF
$CARREGA
f = m.Falador(mic="BlackShark V2 Pro PS 2.4 (Windows)"); print(f.qual, "|", f._abrir_win() and f.onde)
print(f.falar("Ação concluída")); print(f.proxima_saida()); f.fechar()
f = m.Falador(mic="Microphone Array (Intel Digital Microphones) (Windows)"); f._abrir_win(); print(f.onde); f.fechar()
EOF
)
[[ $r == "windows | Headphones (BlackShark V2 Pro PS 2.4)
True
Headphones (Realtek(R) Audio)
Headphones (Realtek(R) Audio)" ]] || falhou "WSL: a voz do Windows: '$r'"
[[ $(sed -n 1p "$T/ps.log") == 'D 2' ]] || falhou "WSL: a fala deveria sair no BlackShark (saída 2): $(cat "$T/ps.log")"
b64=$(grep '^F ' "$T/ps.log" | head -1 | cut -c3-)
[[ $(printf '%s' "$b64" | base64 -d) == 'Ação concluída' ]] || falhou "texto para o Windows (UTF-8 em base64): $(cat "$T/ps.log")"
rm -f "$HOME/.cache/tt-voz/saida"
# Linux: as saídas do PulseAudio; a do mesmo aparelho do microfone, sem a de porta vazia
cat >"$F/pactl" <<'FIM'
#!/bin/sh
case "$*" in
  get-default-sink) echo alsa_output.speaker ;;
  "list sinks") cat <<'L'
Sink #1
	Name: alsa_output.speaker
	Description: Comet Lake Speaker
	Active Port: [Out] Speaker
Sink #2
	Name: alsa_output.fone-p2
	Description: Comet Lake Headphones
	Ports:
		[Out] Headphones: Headphones (type: Headphones, priority: 200, not available)
	Active Port: [Out] Headphones
Sink #3
	Name: bluez_output.fone
	Description: Fone JBL Bluetooth
L
  ;;
esac
FIM
chmod +x "$F/pactl"
r=$(PATH="$F:$PATH" VOZ_SISTEMA=Linux py <<EOF
$CARREGA
s = m.saidas_pulse(); print([x[1] for x in s])
print(s[m.escolher_saida(s, "Fone JBL Bluetooth")][0], s[m.escolher_saida(s, "Comet Lake Digital Microphone")][0])
print(m.tocador("bluez_output.fone"))
EOF
)
[[ $r == "['Comet Lake Speaker', 'Fone JBL Bluetooth']
bluez_output.fone alsa_output.speaker
['paplay', '--device=bluez_output.fone']" ]] || falhou "Linux: saídas do PulseAudio: '$r'"
printf '#!/bin/sh\nexit 0\n' >"$F/pactl"
passou 'Linux: a fala sai no aparelho do microfone (o fone com o do fone, o alto-falante com o embutido); a de porta vazia fica de fora'

# WSL com o PowerShell: os microfones do Windows, gravados direto (o headset, mesmo não sendo o padrão); n troca e lembra
cat >"$F/ps-falso" <<'FIM'
#!/bin/sh
case "$*" in
  *" listar") printf '0\tpadrao,comunicacao\tMicrophone (HD Pro Webcam C920)\tMicrophone (Intel USB Audio)\r\n1\t\tMicrophone (BlackShark V2 Pro P\tMicrophone (BlackShark V2 Pro PS 2.4)\r\n2\t\tStereo Mix (Realtek)\tStereo Mix (Realtek(R) Audio)\r\n' ;;
  *" gravar "*) echo "${*##* }" >>"$MIC_LOG"; head -c 64000 /dev/urandom; sleep 5 ;;
esac
FIM
chmod +x "$F/ps-falso"
r=$(PATH="$F:$PATH" VOZ_SISTEMA=WSL VOZ_WSLG=$T/sock VOZ_POWERSHELL="$F/ps-falso" MIC_LOG=$T/mic.log VOZ_PROVA_S=0.6 py <<EOF
$CARREGA
print([c.nome for c in m.candidatos_gravador()][:3])
g = m.Gravador(); print(g.escolher(), g.nome)
print(g.proximo()); g.fechar()
g = m.Gravador(); print(g.escolher(), g.nome); g.fechar()
EOF
)
[[ $r == "['BlackShark V2 Pro PS 2.4 (Windows)', 'parecord (o padrão do Windows: Intel USB Audio)', 'Intel USB Audio (Windows)']
True BlackShark V2 Pro PS 2.4 (Windows)
Intel USB Audio (Windows)
True Intel USB Audio (Windows)" ]] || falhou "WSL: microfones do Windows: '$r'"
[[ $(head -1 "$T/mic.log") == 1 ]] || falhou "WSL: gravou do microfone errado: $(cat "$T/mic.log")"
rm -f "$HOME/.cache/tt-voz/microfone"
passou 'WSL: grava direto do headset do Windows (sem mudar o padrão); stereo mix fica de fora; n passa ao seguinte e lembra'
passou 'WSL: a voz do Windows fala no aparelho do microfone (não na saída padrão), acentos intactos; s troca a saída e lembra'

printf '#!/bin/sh\necho "$*" >>"$SPD_LOG"\n' >"$F/spd-say"; chmod +x "$F/spd-say"
r=$(PATH="$F:$PATH" VOZ_SISTEMA=Linux SPD_LOG=$T/spd.log py <<EOF
$CARREGA
f = m.Falador(); print(f.qual); f.falar("oi")
EOF
)
[[ $r == spd && $(<"$T/spd.log") == '-w -l pt-BR -r 15 oi' ]] || falhou "Linux sem Piper: spd-say em pt-BR: '$r' $(cat "$T/spd.log" 2>/dev/null)"
passou 'Linux sem o Piper instalado: fala pelo spd-say em pt-BR'

# --- escolha do motor: cada máquina mede (modelo × CPU/GPU), a janela fica com o menor custo entre todas
export VOZ_GPUS="" HF_HUB_CACHE=$T/hf
mkdir -p "$HF_HUB_CACHE"
modelo_em_cache() { local d=$HF_HUB_CACHE/models--$1/snapshots/x; mkdir -p "$d"; : >"$d/model.bin"; }
modelo_em_cache Systran--faster-whisper-small; modelo_em_cache Systran--faster-whisper-base
modelo_em_cache mobiuslabsgmbh--faster-whisper-large-v3-turbo
# um venv com o "faster-whisper" (só a pasta: python_com olha a pasta num venv)
VE=$T/venv; python3 -m venv --without-pip "$VE" 2>/dev/null || { mkdir -p "$VE/bin"; ln -sf "$(command -v python3)" "$VE/bin/python"; printf 'home = %s\n' "$(dirname "$(command -v python3)")" >"$VE/pyvenv.cfg"; }
SPV=$("$VE/bin/python" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])'); mkdir -p "$SPV/faster_whisper" "$SPV/ctranslate2-4.8.3.dist-info"
export VOZ_PYTHON=$VE/bin/python
r=$(VOZ_GPUS="NVIDIA Teste, 2048" py <<EOF
$CARREGA
print(round(m.erro_palavras("Libera a sessão dois e pergunta que horas são lá.", "libera sessão 2 e pergunta que horas sao la"), 3))
print(m.combinacoes(m.gpus_nvidia(), m.modelos_em_cache(), 8, 8000))
print(m.combinacoes([], ["small"], 16, 8000), m.combinacoes(["Fraca, 512"], ["small", "large-v3-turbo"], 4, 2000))
py = m.python_com("faster_whisper"); print(py == "$VE/bin/python")
m.gravar_json(m.MEDICOES, {"assinatura": m.assinatura(py), "carga": 0.5, "nucleos": 8, "resultados": [
  {"modelo": "base", "dispositivo": "cpu", "precisao": "int8", "tempo": 0.8, "erro": 0.15},
  {"modelo": "small", "dispositivo": "cpu", "precisao": "int8", "tempo": 2.6, "erro": 0.11},
  {"modelo": "small", "dispositivo": "cuda", "precisao": "int8", "tempo": 0.9, "erro": 0.18},
  {"modelo": "large-v3-turbo", "dispositivo": "cuda", "precisao": "int8", "tempo": 3.3, "erro": 0.08}]})
e = m.escolha_local(py); print(e["modelo"], e["dispositivo"], e["fonte"])
import os
os.environ["VOZ_MODELO"] = "large-v3-turbo"; e = m.escolha_local(py); print(e["modelo"], e["dispositivo"]); del os.environ["VOZ_MODELO"]
m.gpu_falhou(py, "libcublas.so.12 não encontrada"); e = m.escolha_local(py); print(e["modelo"], e["dispositivo"])
EOF
)
[[ $r == "0.1
[('base', 'cpu'), ('small', 'cpu'), ('small', 'cuda'), ('large-v3-turbo', 'cuda')]
[('small', 'cpu')] [('small', 'cpu'), ('small', 'cuda')]
True
small cuda medido
large-v3-turbo cuda
base cpu" ]] || falhou "medições: erro por palavra, combinações por hardware, escolha pelo custo, modelo pedido e GPU que falhou: '$r'"
r=$(VOZ_GPUS="NVIDIA Outra, 4096" py <<EOF
$CARREGA
e = m.escolha_local(m.python_com("faster_whisper")); print(e["modelo"], e["dispositivo"], e["fonte"])
EOF
)
[[ $r == 'small cpu estimado' ]] || falhou "outra GPU (assinatura mudou): as medições velhas não valem: '$r'"
passou 'escolha da máquina: erro por palavra, o que medir por hardware, menor custo (tempo e erro), GPU que falhou fica de fora'

# GPU que falha no primeiro uso cai na CPU e marca a medição
r=$(VOZ_GPUS="NVIDIA Teste, 2048" py <<EOF
$CARREGA
py = m.python_com("faster_whisper")
med = m.ler_json(m.MEDICOES); med.pop("gpu_falhou", None); med["assinatura"] = m.assinatura(py); m.gravar_json(m.MEDICOES, med)
class M(m.Motor):
    def _novo_modelo(self, nome, disp, prec):
        self.disp = disp; return object()
    def _aquecer(self):
        if self.disp == "cuda": raise RuntimeError("Library libcublas.so.12 is not found")
import sys; sys.executable = py
x = M(); e = x.carregar_stt(); print(e["modelo"], e["dispositivo"], e["fonte"])
print(m.ler_json(m.MEDICOES).get("gpu_falhou", "")[:30])
EOF
)
[[ $r == $'small cpu a GPU falhou\nLibrary libcublas.so.12 is not' ]] || falhou "motor: GPU sem biblioteca deveria cair na CPU e marcar: '$r'"
passou 'motor: a GPU que falha no primeiro uso cai na CPU, e a escolha da máquina deixa a GPU de fora'

# medir: injeta o modelo e a voz; grava tempo e erro de cada combinação e a assinatura
r=$(VOZ_GPUS="" py <<EOF
$CARREGA
import itertools, time
class Falso:
    def __init__(self, nome): self.nome = nome
def fabrica(nome, disp, prec):
    if nome == "base": raise RuntimeError("sem memória")
    return Falso(nome)
orig = m.Motor._transcrever
def transcrever(self, audio, dica=""):
    return audio if self.modelo.nome == "small" else "texto errado"
m.Motor._transcrever = transcrever
import sys; sys.executable = m.python_com("faster_whisper")  # o medir roda no Python do venv
med = m.medir(fabrica=fabrica, sintetizar=lambda f: f, saida=lambda *a: None)
print([(r["modelo"], r["dispositivo"], r["erro"]) for r in med["resultados"]], med["assinatura"] == m.assinatura(m.python_com("faster_whisper")))
EOF
)
[[ $r == "[('small', 'cpu', 0.0)] True" ]] || falhou "medir: '$r'"
passou 'medir: cada combinação com tempo e erro (a que falha fica de fora); a assinatura invalida quando o hardware muda'

# vozes neurais: o que um venv gera (Piper com a voz baixada; as da Microsoft com o edge-tts e o PyAV); frases
r=$(py <<EOF
$CARREGA
import os
sp = m.site_packages(m.python_com("faster_whisper"))[0]
print(m.vozes_de(m.python_com("faster_whisper")))
for d in ("piper", "edge_tts", "av"): os.makedirs(os.path.join(sp, d), exist_ok=True)
os.makedirs(m.VOZES, exist_ok=True); open(os.path.join(m.VOZES, "pt_BR-faber-medium.onnx"), "w").close()
print(m.vozes_de(m.python_com("faster_whisper")))
print(m.pedacos("Tarefas para hoje: 1, a primeira. 2, a segunda. Pode falar."))
print(m.rotulo_voz("edge:pt-BR-FranciscaNeural"), "|", m.rotulo_voz("piper:pt_BR-faber-medium"), "|", m.rotulo_voz("sistema"))
import shutil
for d in ("piper", "edge_tts", "av"): shutil.rmtree(os.path.join(sp, d))
os.remove(os.path.join(m.VOZES, "pt_BR-faber-medium.onnx"))
EOF
)
[[ $r == "[]
['piper:pt_BR-faber-medium', 'edge:pt-BR-FranciscaNeural', 'edge:pt-BR-AntonioNeural', 'edge:pt-BR-ThalitaMultilingualNeural']
['Tarefas para hoje: 1, a primeira.', '2, a segunda. Pode falar.']
Francisca (online, Microsoft) | Piper Faber (offline) | a do sistema" ]] || falhou "vozes neurais: '$r'"
passou 'vozes: o que cada máquina gera (Piper offline, as da Microsoft online); a fala vai em frases, a primeira sozinha'

# escolher entre máquinas: ssh falso responde a capacidade de cada uma; fora do ar fica de fora (e é lembrada)
ln -sf "$V" "$B/voz"
cat >"$B/tt" <<'FIM'
#!/usr/bin/env bash
case $1 in
  --maquinas) printf 'u@h1 dell\nu@h2 book\nu@h3 velha\nu@h4 desligada\n' ;;
  --listar-tudo) printf '# mestre de obras — mesa — 20260101T000000Z\n' ;;
esac
FIM
cat >"$B/ssh" <<'FIM'
#!/usr/bin/env bash
# ssh falso: o destino escolhe a resposta; o comando roda aqui (o motor com a transcrição fixa "frase do DESTINO")
while [[ $1 == -* ]]; do [[ $1 == -o ]] && shift; shift; done; d=$1; shift
echo "$d $*" >>"$SSH_LOG"
case $d in u@h4) echo 'ssh: connect to host h4: No route to host' >&2; exit 255 ;; u@h3) exit 127 ;; esac
if [[ $* == *--motor-info* ]]; then cat "$CAPS/$d.json"; exit 0; fi
VOZ_MOTOR_FALSO="frase do $d" VOZ_PYTHON=${VOZ_PYTHON_LA:-$VOZ_PYTHON} exec bash -c "$*"
FIM
chmod +x "$B/tt" "$B/ssh"
export CAPS=$T/caps SSH_LOG=$T/ssh.log; mkdir -p "$CAPS"
printf '%s' '{"whisper": true, "nucleos": 8, "carga": 0.5, "escolha": {"modelo": "small", "dispositivo": "cuda", "precisao": "int8", "tempo": 0.9, "erro": 0.18, "fonte": "medido", "carga_medida": 0.5}, "s": 0.02}' >"$CAPS/u@h1.json"
printf '%s' '{"whisper": true, "nucleos": 8, "carga": 0.5, "escolha": {"modelo": "small", "dispositivo": "cpu", "precisao": "int8", "tempo": 2.5, "erro": 0.11, "fonte": "medido", "carga_medida": 0.5}, "s": 0.02}' >"$CAPS/u@h2.json"
rm -f "$HOME/.cache/tt-voz/sondas.json" "$HOME/.cache/tt-voz/desempenho.json"
mv "$VOZ_PYTHON" "$VOZ_PYTHON.x"; export VOZ_PYTHON_LA=$VOZ_PYTHON.x  # esta máquina sem faster-whisper; as outras com
ESC() { VOZ="$V" VOZ_TRANSCREVER="local dell book velha desligada" python3 "$A" escolher; }
r=$(ESC 2>&1 || true)
[[ $(head -2 <<<"$r" | cut -f2 | tr '\n' ' ') == 'dell book ' ]] || falhou "ranking: a GPU do dell antes da CPU do book: $r"
grep -q '✗ local: sem faster-whisper' <<<"$r" && grep -q '✗ velha: sem o motor de voz' <<<"$r" && grep -q '✗ desligada: ' <<<"$r" ||
  falhou "ranking: os que não transcrevem: $r"
: >"$SSH_LOG"; r=$(ESC 2>&1 || true)
grep -q 'u@h4' "$SSH_LOG" && falhou 'a máquina fora do ar foi sondada de novo antes de 10 min'
grep -q 'u@h3' "$SSH_LOG" || falhou 'a máquina sem o motor (mas ligada) ficou de fora como se estivesse desligada'
grep -q '✗ desligada: fora do ar' <<<"$r" || falhou "a fora do ar deveria aparecer como fora do ar: $r"
r=$(VOZ_MODELO=tiny py <<<"$CARREGA
print(m.ssh_cmd('u@h1', 'voz --motor-info')[-1].split('; ')[-1])")
[[ $r == 'VOZ_MODELO=tiny voz --motor-info' ]] || falhou "o modelo escolhido aqui não vai à máquina que transcreve: '$r'"
passou 'escolher: pergunta a todas, a de menor custo primeiro; a desligada fica de fora por 10 min, a sem motor não'

# Máquina fixa: o submenu deixa escolher inclusive a mais lenta, voltar ao automático e cancelar.
r=$(VOZ="$V" VOZ_MAQUINAS="local dell book velha desligada" VOZ_TRANSCREVER="local dell book" python3 - "$A" <<EOF
$CARREGA
import os
class Tela:
    def linha(self, *args): pass
    def status(self, *args): pass
class Teclas:
    def __init__(self, ks): self.ks = iter(ks)
    def tecla(self, *args): return next(self.ks)
assert m.escolher_maquina(Tela(), Teclas(['3', '\\r']))
assert m.conf('transcrever') == 'book'
t = m.Transcritor(); assert t.preparar() and t.onde == 'book'
assert len(t.ranking) == 1 and t._alternativa() is None
assert t.texto(b'\\0\\0' * 8000) == 'frase do u@h2'
t.fechar()
assert not m.escolher_maquina(Tela(), Teclas(['2', 'esc']))
assert m.conf('transcrever') == 'book'
assert m.escolher_maquina(Tela(), Teclas(['9', '\\r', '0', '\\r']))
assert not m.conf('transcrever') and 'dell' in m.Transcritor().lugares()
assert m.escolher_maquina(Tela(), Teclas(['2', '\\r']))
t = m.Transcritor(); assert t.preparar() and t.onde == 'dell'
# A troca durante uma conversa não destrói o motor atual se a máquina escolhida falhar.
c = m.Conversa(digitar=True); c.tela = Tela(); c.transcritor = t
assert m.escolher_maquina(Tela(), Teclas(['5', '\\r']))
c.recarregar_transcricao()
assert c.transcritor is t and t.texto(b'\\0\\0' * 8000) == 'frase do u@h1'
assert m.escolher_maquina(Tela(), Teclas(['3', '\\r']))
c.recarregar_transcricao()
assert c.transcritor.onde == 'book' and t.fechado
assert c.transcritor.texto(b'\\0\\0' * 8000) == 'frase do u@h2'
c.transcritor.fechar()
m.escolher_maquina(Tela(), Teclas(['0', '\\r']))
print('ok')
EOF
)
[[ $r == ok ]] || falhou "seleção manual de máquina: '$r'"
rm -f "$HOME/.cache/tt-voz/desempenho.json"
passou 'máquina: fixa a escolhida, cancela, volta ao automático, troca na conversa e preserva o motor se falhar'

# a janela transcreve no escolhido (o motor de lá, pelo ssh), mede, e troca quando ele fica lento
r=$(VOZ="$V" VOZ_TRANSCREVER="dell book" python3 - "$A" <<EOF
$CARREGA
t = m.Transcritor(); print(t.preparar(), t.onde, "|", t.desc)
pcm = b"\0\0" * 8000
print(t.texto(pcm))
h = m.ler_json(m.DESEMPENHO); print(sorted(h), h["dell|falso|cpu"]["n"])
h["dell|falso|cpu"] = {"s": 9.0, "n": 5}; m.gravar_json(m.DESEMPENHO, h)
t.texto(pcm)          # o dell ficou lento: o book carrega em paralelo
import time
for i in range(100):
    if t.proximo: break
    time.sleep(0.1)
print(t.texto(pcm), "|", t.desc)
t.fechar()
EOF
)
[[ $r == "True dell | dell · falso na CPU (de 2)
frase do u@h1
['dell|falso|cpu'] 1
frase do u@h2 | book · falso na CPU (trocou: o anterior ficou lento)" ]] || falhou "transcrever no escolhido e trocar: '$r'"
r=$(VOZ="$V" VOZ_TRANSCREVER="dell" VOZ_SISTEMA=WSL VOZ_POWERSHELL="$F/ps-fala" PS_LOG=$T/ps2.log python3 - "$A" <<EOF
$CARREGA
t = m.Transcritor(); t.preparar(); t.info["vozes"] = ["edge:pt-BR-FranciscaNeural"]
f = m.Falador(mic="BlackShark V2 Pro PS 2.4 (Windows)", fornecedor=lambda: (t.canal, t.info.get("vozes")))
f.voz = "edge:pt-BR-FranciscaNeural"
print(f.vozes(), bool(f.neural()), f.falar("Primeira frase. Segunda frase."))
f.fechar(); t.fechar()
EOF
)
[[ $r == "['sistema', 'edge:pt-BR-FranciscaNeural'] True True" ]] || falhou "voz neural gerada noutra máquina: '$r'"
[[ $(grep -c '^T ' "$T/ps2.log") == 2 ]] || falhou "WSL: deveria tocar 2 WAVs (uma frase cada): $(cut -c1-20 "$T/ps2.log")"
[[ $(grep -m1 '^T ' "$T/ps2.log" | cut -c3- | base64 -d | head -c 4) == RIFF ]] || falhou 'WSL: o que vai ao PowerShell não é um WAV'
mv "$VOZ_PYTHON.x" "$VOZ_PYTHON"; unset VOZ_PYTHON_LA
passou 'janela: transcreve no motor da máquina escolhida, mede cada frase e troca para a seguinte quando ela fica lenta'
unset VOZ_GPUS VOZ_PYTHON
cat >"$B/tt" <<'FIM'
#!/usr/bin/env bash
case $1 in
  --maquinas) printf 'u@h1 dell\nu@h2 book\n' ;;
  --saude) printf 'Saude das maquinas cadastradas:\n  \033[32m●\033[0m dell             ok\n  \033[31m●\033[0m book             timeout\n  ● units locais     0 em falha\n' ;;
  --listar-tudo) printf '# mestre de obras — mesa — 20260101T000000Z\n' ;;
esac
FIM
rm -f "$B/ssh" "$B/voz"

# --- gravar até o silêncio: fala detectada pelo nível, silêncio, e o Espaço que encerra
python3 -c 'import math, struct, sys
sys.stdout.buffer.write(b"\0\0" * 4000 + b"".join(struct.pack("<h", int(6000 * math.sin(i * 0.17))) for i in range(16000)))' >"$T/tom.raw"
# 0,1 s de ruído baixo de sala (um microfone de verdade nunca dá zero exato: zero exato é microfone no mudo)
python3 -c 'import random, struct, sys
random.seed(3); sys.stdout.buffer.write(b"".join(struct.pack("<h", random.randint(-6, 6)) for i in range(1600)))' >"$T/ruido.raw"
# o microfone falso fica aberto (como o de verdade) e "fala" a frase quando aparece o arquivo $T/falar
GRAV="while :; do if [ -e '$T/falar' ]; then rm -f '$T/falar'; cat '$T/tom.raw'; fi; cat '$T/ruido.raw' || exit 0; sleep 0.1; done"
falar_quando_ouvir() { # SESSÃO: espera a janela ouvir ("○ fale") e "fala" no microfone falso
  local i; for i in $(seq 100); do tmux capture-pane -p -J -t "=$1:" 2>/dev/null | grep -qF '○ fale' && break; sleep 0.2; done
  touch "$T/falar"
}
r=$(VOZ_GRAVADOR="$GRAV" VOZ_PAUSA=0.6 py <<EOF
$CARREGA
import threading, time
g = m.Gravador(); g.escolher(); time.sleep(0.5)
threading.Timer(0.3, lambda: open("$T/falar", "w").close()).start()
pcm, motivo = g.frase(); print(motivo, round(len(pcm) / 2 / 16000, 1)); g.fechar()
EOF
)
read -r mot dur <<<"$r"
[[ $mot == fala ]] && awk -v d="$dur" 'BEGIN { exit !(d >= 1.0 && d <= 2.2) }' || falhou "frase com 1 s de fala: '$r'"
r=$(VOZ_GRAVADOR="while :; do cat '$T/ruido.raw' || exit 0; sleep 0.1; done" VOZ_ESPERA_FALA_S=1 py <<EOF
$CARREGA
import time
g = m.Gravador(); g.escolher(); t = time.time(); pcm, motivo = g.frase(); print(motivo, len(pcm), time.time() - t < 4)
EOF
)
[[ $r == 'silencio 0 True' ]] || falhou "silêncio: '$r'"
# microfone no mudo (zero exato): na frase, "mudo"; na escolha, pula para o seguinte e conta qual pulou
r=$(VOZ_GRAVADOR="while :; do head -c 3200 /dev/zero || exit 0; sleep 0.1; done" VOZ_ESPERA_FALA_S=1 py <<EOF
$CARREGA
g = m.Gravador(); g.escolher(); print(g.frase()[1]); g.fechar()
EOF
)
[[ $r == mudo ]] || falhou "frase com o microfone no mudo: '$r'"
cat >"$F/ps-mudo" <<'FIM'
#!/bin/sh
case "$*" in
  *" listar") printf '0\tpadrao\tMicrophone (HD Pro Webcam C920)\tMicrophone (Intel USB Audio)\r\n1\t\tMicrophone (BlackShark V2 Pro P\tMicrophone (BlackShark V2 Pro PS 2.4)\r\n' ;;
  *" gravar 1") head -c 64000 /dev/zero; sleep 5 ;;
  *" gravar 0") head -c 64000 /dev/urandom; sleep 5 ;;
esac
FIM
chmod +x "$F/ps-mudo"
r=$(PATH="$F:$PATH" VOZ_SISTEMA=WSL VOZ_WSLG=/nada VOZ_POWERSHELL="$F/ps-mudo" VOZ_PROVA_S=0.6 py <<EOF
$CARREGA
g = m.Gravador(); print(g.escolher(), g.nome, "|", g.pulados); g.fechar()
EOF
)
[[ $r == "True Intel USB Audio (Windows) | ['BlackShark V2 Pro PS 2.4 (Windows)']" ]] ||
  falhou "headset no mudo: deveria ouvir pelo seguinte e avisar: '$r'"
passou 'gravação: fala pelo nível, fim no silêncio; microfone no mudo (zero exato) é pulado e avisado'

# --- a janela da conversa: microfone, transcrição e voz falsos; o voz e o cérebro de regras de verdade
tmux new-session -d -s _base 'sleep 3600'  # o servidor do tmux não morre entre uma janela e a seguinte
J=$T/janela; mkdir -p "$J"; echo 0 >"$J/n"
printf 'máquinas\n' >"$J/frases"
cat >"$J/stt" <<'FIM'
#!/bin/sh
# transcrição falsa: a próxima linha de frases (o áudio vem no stdin)
cat >/dev/null; n=$(($(cat "$J/n") + 1)); echo $n >"$J/n"; sed -n "${n}p" "$J/frases"
FIM
chmod +x "$J/stt"
export J
# um Piper (falso) neste computador: a tecla v tem para onde ir
VV=$HOME/.local/share/tt-voz/venv; python3 -m venv --without-pip "$VV" 2>/dev/null || { mkdir -p "$VV/bin"; ln -sf "$(command -v python3)" "$VV/bin/python"; : >"$VV/pyvenv.cfg"; }
mkdir -p "$("$VV/bin/python" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')/piper" "$HOME/.local/share/tt-voz/piper"
: >"$HOME/.local/share/tt-voz/piper/pt_BR-faber-medium.onnx"
# o cérebro deixa um filho em segundo plano com o canal aberto: a volta acaba quando o voz acaba, sem esperar por ele
printf '%s' '{"fala": "Tudo certo por aqui.", "acoes": []}' >"$J/plano.json"
tmux new-session -d -s conversa -x 100 -y 30 -e VOZ_GRAVADOR="$GRAV" -e VOZ_STT_CMD="$J/stt" -e VOZ_PAUSA=0.5 \
  -e VOZ_CEREBRO_CMD="cat >/dev/null; (sleep 40 >/dev/null 2>&1 &); cat '$J/plano.json'" \
  -e VOZ_ESPERA_FALA_S=60 -e VOZ_TTS_CMD="cat >>'$J/falas'; echo >>'$J/falas'" -e J="$J" -e PATH="$PATH" \
  "bash '$V' --conversa; echo SAIU=\$? >'$J/saiu'; sleep 60"
espera_tela() { local i; for i in $(seq 100); do tmux capture-pane -p -J -t '=conversa:' 2>/dev/null | grep -qF "$1" && return 0; sleep 0.2; done; return 1; }
falar_quando_ouvir conversa
espera_tela 'Atual: mesa' || falhou "a frase falada não virou resposta: $(tmux capture-pane -p -J -t '=conversa:')"
tela=$(tmux capture-pane -p -J -t '=conversa:')
grep -q 'você: máquinas' <<<"$tela" && grep -q 'tt: Terminal. Máquina mesa, nenhuma sessão escolhida. Pode falar.' <<<"$tela" ||
  falhou "transcrição na janela: $tela"
grep -q 'Máquinas: dell, book, mesa. Atual: mesa.' "$J/falas" && grep -q 'Terminal. Máquina mesa' "$J/falas" || falhou "a voz não disse as respostas: $(cat "$J/falas")"
# ouvindo de novo: t digita uma frase
espera_tela 'Espaço: terminei' || falhou 'não voltou a ouvir'
tmux send-keys -t '=conversa:' t; sleep 0.4; tmux send-keys -t '=conversa:' -l 'onde'; tmux send-keys -t '=conversa:' Enter
espera_tela 'Máquina mesa, nenhuma sessão escolhida.' || falhou "frase digitada: $(tmux capture-pane -p -J -t '=conversa:')"
grep -q 'você: onde' <<<"$(tmux capture-pane -p -J -t '=conversa:')" || falhou 'a frase digitada não apareceu como sua'
espera_tela 'Espaço: terminei' || falhou 'depois da frase digitada, não voltou a ouvir'
tmux send-keys -t '=conversa:' t; sleep 0.4; tmux send-keys -t '=conversa:' -l 'como vai tudo por aí'; tmux send-keys -t '=conversa:' Enter
espera_tela 'tt: Tudo certo por aqui.' || falhou "frase solta ao cérebro: $(tmux capture-pane -p -J -t '=conversa:')"
t0=$(date +%s); espera_tela 'Espaço: terminei' && (($(date +%s) - t0 < 10)) ||
  falhou 'um filho do voz em segundo plano prendeu a volta (a janela não voltou a ouvir)'
# c: as opções; 1 = cérebro Haiku, b = transcrição tiny (gravados como voz --cerebro-modelo e voz --modelo); Enter volta
tmux send-keys -t '=conversa:' c; espera_tela 'cérebro, que entende a frase' || falhou "c não abriu as opções: $(tmux capture-pane -p -J -t '=conversa:')"
tmux send-keys -t '=conversa:' 1; espera_tela '✓ cérebro: Haiku' || falhou 'opções: 1 não escolheu o Haiku'
tmux send-keys -t '=conversa:' b; espera_tela '✓ transcrição: tiny' || falhou 'opções: b não escolheu o tiny'
tmux send-keys -t '=conversa:' v; espera_tela '✓ voz: a do sistema' || falhou "opções: v não trocou a voz: $(tmux capture-pane -p -J -t '=conversa:')"
for i in $(seq 25); do grep -q 'Esta é a voz a do sistema' "$J/falas" && break; sleep 0.2; done
grep -q 'Esta é a voz a do sistema' "$J/falas" || falhou 'opções: v não falou o exemplo da voz'
tmux send-keys -t '=conversa:' Enter; espera_tela 'transcrever: comando de teste' || falhou 'opções: a transcrição não recarregou'
[[ $(cat "$HOME/.config/tt-voz/cerebro-modelo") == haiku && $(cat "$HOME/.config/tt-voz/modelo") == tiny ]] ||
  falhou "opções: não gravou a escolha: $(cat "$HOME/.config/tt-voz/cerebro-modelo" "$HOME/.config/tt-voz/modelo" 2>&1)"
[[ $(bash "$V" --cerebro-modelo) == 'cérebro: haiku' ]] || falhou 'o voz não lê o cérebro escolhido nas opções'
[[ $(cat "$HOME/.config/tt-voz/voz") == sistema ]] || falhou "opções: a voz não ficou guardada: $(cat "$HOME/.config/tt-voz/voz" 2>&1)"
rm -f "$HOME/.config/tt-voz/voz"; rm -rf "$VV" "$HOME/.local/share/tt-voz/piper"
espera_tela 'c: opções' || falhou 'depois das opções, não voltou a ouvir'
# um agente que ficou trabalhando (pendente) terminou: enquanto ouve, a janela confere e fala a resposta sozinha
tmux new-session -d -s agente-x "printf '● Pronto: terminei a revisão.\n'; sleep 600"; sleep 0.5
printf 'mesa:agente-x\n' >"$HOME/.local/state/tt-voz/pendente"
espera_tela 'o agente terminou:' && espera_tela 'tt: Pronto: terminei a revisão.' ||
  falhou "a janela não avisou que o agente pendente terminou: $(tmux capture-pane -p -J -t '=conversa:')"
[[ -e $HOME/.local/state/tt-voz/pendente ]] && falhou 'o pendente ficou depois do aviso'
tmux kill-session -t '=agente-x'
espera_tela 'c: opções' || falhou 'depois do aviso, não voltou a ouvir'
tmux send-keys -t '=conversa:' Escape
for i in $(seq 50); do [[ -s $J/saiu ]] && break; sleep 0.2; done
[[ $(<"$J/saiu") == SAIU=0 ]] || falhou "Esc não fechou a janela: $(cat "$J/saiu" 2>/dev/null)"
passou 'janela: ouve, mostra e fala; t digita; c abre as opções (guardadas); avisa sozinha quando o agente pendente termina; Esc fecha'

# voz --opcoes (o item do botão direito do 🎤): 2 volta ao Sonnet (o padrão: sem arquivo), a volta ao automático
tmux new-session -d -s opcoes -x 100 -y 20 -e VOZ_GRAVADOR="$GRAV" -e VOZ_TTS_CMD="cat >/dev/null" -e PATH="$PATH" \
  "bash '$V' --opcoes; echo SAIU >'$J/saiu-op'; sleep 60"
espera_tela_op() { local i; for i in $(seq 80); do tmux capture-pane -p -J -t '=opcoes:' 2>/dev/null | grep -qF "$1" && return 0; sleep 0.2; done; return 1; }
espera_tela_op 'Sonnet' || falhou "voz --opcoes: $(tmux capture-pane -p -J -t '=opcoes:')"
tmux send-keys -t '=opcoes:' 2; espera_tela_op '✓ cérebro: Sonnet' || falhou 'voz --opcoes: 2'
tmux send-keys -t '=opcoes:' a; espera_tela_op '✓ transcrição: automático' || falhou 'voz --opcoes: a'
tmux send-keys -t '=opcoes:' l; espera_tela_op '0 automática' || falhou 'voz --opcoes: lista de máquinas'
tmux send-keys -t '=opcoes:' 2 Enter; espera_tela_op '✓ máquina de transcrição: dell' || falhou 'voz --opcoes: escolher máquina'
[[ $(cat "$HOME/.config/tt-voz/transcrever") == dell ]] || falhou 'máquina escolhida não ficou guardada'
tmux send-keys -t '=opcoes:' l 0 Enter; espera_tela_op '✓ máquina de transcrição: automática' || falhou 'voz --opcoes: automático'
[[ ! -e $HOME/.config/tt-voz/transcrever ]] || falhou 'automático não apagou preferência de máquina'
tmux send-keys -t '=opcoes:' Escape
for i in $(seq 30); do [[ -s $J/saiu-op ]] && break; sleep 0.2; done
[[ ! -e $HOME/.config/tt-voz/cerebro-modelo && ! -e $HOME/.config/tt-voz/modelo ]] || falhou 'voz --opcoes: Sonnet e automático deveriam apagar a escolha'
tmux kill-session -t '=opcoes' 2>/dev/null || true
passou 'voz --opcoes: o mesmo painel fora da conversa; o padrão (Sonnet, automático) apaga a escolha guardada'

# "encerrar" falado fecha sozinha
echo 0 >"$J/n"; printf 'encerrar\n' >"$J/frases"; rm -f "$J/saiu"; tmux kill-session -t '=conversa' 2>/dev/null || true
tmux new-session -d -s conversa2 -x 100 -y 30 -e VOZ_GRAVADOR="$GRAV" -e VOZ_STT_CMD="$J/stt" -e VOZ_PAUSA=0.5 \
  -e VOZ_TTS_CMD="cat >/dev/null" -e J="$J" -e PATH="$PATH" "bash '$V' --conversa; echo SAIU=\$? >'$J/saiu'; sleep 60"
falar_quando_ouvir conversa2
for i in $(seq 100); do [[ -s $J/saiu ]] && break; sleep 0.2; done
[[ $(cat "$J/saiu" 2>/dev/null) == SAIU=0 ]] || falhou "encerrar não fechou a janela: $(tmux capture-pane -p -J -t '=conversa2:')"
tmux kill-session -t '=conversa2' 2>/dev/null || true
passou 'janela: "encerrar" diz Terminal encerrado e fecha'

# sem gravador: avisa e segue digitando
tmux new-session -d -s conversa3 -x 100 -y 30 -e VOZ_GRAVADOR= -e PATH="$T/vazio:/usr/bin:/bin" -e VOZ_TTS_CMD="cat >/dev/null" \
  "env PATH='$B:/usr/bin:/bin' VOZ_SISTEMA=Darwin bash '$V' --conversa; sleep 60"
espera_tela_em() { local i; for i in $(seq 80); do tmux capture-pane -p -J -t "=$1:" 2>/dev/null | grep -qF "$2" && return 0; sleep 0.2; done; return 1; }
espera_tela_em conversa3 'Sem microfone' && espera_tela_em conversa3 'você>' ||
  falhou "sem gravador: $(tmux capture-pane -p -J -t '=conversa3:')"
tmux kill-session -t '=conversa3' 2>/dev/null || true
passou 'sem programa para gravar: a janela diz o que instalar e segue digitando'

# --- celular com o Tasker: a janela abre a conversa nele, mostra o conversa.log e o que se digita vai ao daemon
P=$T/com.termux/usr; mkdir -p "$P" "$HOME/.config/tt-voz" "$T/sd/Tasker/voz/in"; touch "$HOME/.config/tt-voz/ativo"
echo $$ >"$HOME/.local/state/tt-voz/daemon.pid"  # daemon "de pé": o garantir não sobe outro
printf '#!/bin/sh\necho "$*" >>"%s"\n' "$T/am.log" >"$B/am"; chmod +x "$B/am"
tmux new-session -d -s celular -x 60 -y 20 -e PREFIX="$P" -e VOZ_SDCARD="$T/sd" -e PATH="$PATH" "bash '$V' --conversa; sleep 60"
espera_tela_em celular 'A conversa abre no Tasker' || falhou "celular: $(tmux capture-pane -p -J -t '=celular:')"
grep -q 'tt.VOZ_ABRIR' "$T/am.log" || falhou 'celular: a janela não abriu a conversa no Tasker'
echo "12:00:00 tt: Dito pelo Tasker." >>"$HOME/.local/state/tt-voz/conversa.log"
espera_tela_em celular 'tt: Dito pelo Tasker.' || falhou "celular: a janela não mostrou o conversa.log: $(tmux capture-pane -p -J -t '=celular:')"
tmux send-keys -t '=celular:' t; sleep 0.4; tmux send-keys -t '=celular:' -l 'status'; tmux send-keys -t '=celular:' Enter
for i in $(seq 25); do ls "$T/sd/Tasker/voz/in/"tela-*.txt >/dev/null 2>&1 && break; sleep 0.2; done
[[ $(cat "$T/sd/Tasker/voz/in/"tela-*.txt 2>/dev/null) == status ]] || falhou 'celular: o que se digita não foi ao daemon'
tmux kill-session -t '=celular' 2>/dev/null || true; rm -f "$HOME/.config/tt-voz/ativo" "$HOME/.local/state/tt-voz/daemon.pid"
passou 'celular: o 🎤 abre a conversa no Tasker, a janela mostra o que foi dito e manda ao daemon o que se digita'

# --- o atalho 🎤 do tt: @janela abre o comando numa janela flutuante (não numa sessão), também pelo Ctrl+B v
grep -qP '^🎤\tvoz\t@janela voz --conversa\t' "$RAIZ/atalhos-padrao" && grep -qP '^🎤\tvoz\t@janela voz --conversa\t' "$RAIZ/atalhos-padrao-mobile" ||
  falhou 'o 🎤 não está nos atalhos padrão'
grep -q "bind v run-shell -b \"~/.local/bin/tt --clique voz " "$RAIZ/tmux.conf" || falhou 'Ctrl+B v não chama o 🎤'
"$TT" --atalhos-lista | grep -qP '^🎤\tvoz\t@janela voz --conversa' || falhou "o 🎤 não aparece na lista de atalhos: $("$TT" --atalhos-lista)"
printf '🎤\tvoz\t@janela echo "janela $(pwd)" >%s\t#cba6f7\n' "$T/janela.out" >"$XDG_CONFIG_HOME/tt/atalhos"
tmux new -d -s inicio -x 120 -y 30 -c "$T" 'sleep 600'
anexar tela 120 30 inicio; sleep 0.8
cli=$(tmux list-clients -F '#{client_name}' | head -1); pane=$(tmux display -p -t '=inicio:' '#{pane_id}')
antes=$(tmux list-sessions -F '#{session_name}' | sort)
"$TT" --clique voz "$cli" "$pane" "$T" &
for i in $(seq 40); do [[ -s $T/janela.out ]] && break; sleep 0.2; done
[[ $(cat "$T/janela.out" 2>/dev/null) == "janela $T" ]] || falhou "Ctrl+B v / @janela não rodou o comando na pasta do painel: $(cat "$T/janela.out" 2>/dev/null)"
[[ $(tmux list-sessions -F '#{session_name}' | sort) == "$antes" ]] || falhou '@janela criou uma sessão (devia ser uma janela flutuante)'
wait
i=$("$TT" --atalhos-lista | cut -f2 | grep -n '^voz$' | cut -d: -f1); rm -f "$T/janela.out"
"$TT" --clique "at$i" "$cli" "$pane" "$T" &
for i in $(seq 40); do [[ -s $T/janela.out ]] && break; sleep 0.2; done
[[ -s $T/janela.out ]] || falhou 'o clique no 🎤 da barra não abriu a janela'
wait
passou 'atalho 🎤: @janela roda numa janela flutuante na pasta do painel, pelo clique e pelo Ctrl+B v'

# 🎤 clicado numa ponte (você vê esta máquina de outra): a janela abre na máquina de origem, a do aparelho onde você
# está (o microfone e o som dela), com a sessão daqui como alvo da conversa
cat >"$B/ssh" <<FIM
#!/bin/sh
for a; do ultimo=\$a; done
echo "\$ultimo" >>"$T/ssh-ponte.log"
exit 0
FIM
chmod +x "$B/ssh"
printf '192.0.2.9 ninguem origem\n' >"$XDG_CONFIG_HOME/tt/maquinas"
rm -f "$XDG_CONFIG_HOME/tt/atalhos"  # o 🎤 de fábrica: @janela voz --conversa
fora new -d -s viaponte -x 110 -y 30 "env -u TMUX TMUX_TMPDIR=$TMUX_TMPDIR TT_PONTE='origem|ponte-y' tmux attach -t inicio"
for i in $(seq 25); do cli_p=$(tmux list-clients -F '#{client_width} #{client_name}' | awk '$1 == 110 { print $2 }'); [[ -n $cli_p ]] && break; sleep 0.2; done
"$TT" --clique voz "$cli_p" "$pane" "$T"
l=$(cat "$T/ssh-ponte.log" 2>/dev/null)
[[ $l == *--janela-ponte* && $l == *ponte-y* && $l == *conversa* && $l == *teste* && $l == *inicio* ]] ||
  falhou "🎤 pela ponte: deveria pedir à máquina de origem: '$l'"
fora kill-session -t viaponte
# a máquina de origem: abre no cliente que olha a ponte e põe a sessão de lá como alvo da conversa
mkdir -p "$HOME/.local/bin"; ln -sf "$V" "$HOME/.local/bin/voz"
"$TT" --janela-ponte inicio "voz --dica >$T/dica.out # --conversa" dell sessao-de-la
for i in $(seq 40); do [[ -s $T/dica.out ]] && break; sleep 0.2; done
[[ -s $T/dica.out ]] || falhou '--janela-ponte: a janela não abriu no cliente da ponte'
[[ $(cat "$HOME/.local/state/tt-voz/alvo_m") == dell && $(cat "$HOME/.local/state/tt-voz/alvo_s") == sessao-de-la ]] ||
  falhou "--janela-ponte: a conversa deveria começar na sessão de lá"
"$TT" --janela-ponte inicio "rm -rf /tmp/nada" dell x && falhou '--janela-ponte aceitou um comando que não é do voz'
rm -f "$HOME/.local/bin/voz" "$B/ssh"; : >"$XDG_CONFIG_HOME/tt/maquinas"
passou '🎤 numa ponte: abre na máquina de origem (o microfone e o som de onde você está), já na sessão que estava na tela'

# --- instalação: o voz vai para o ~/.local/bin (fora do celular)
instalar_isolado
[[ $(readlink "$HOME/.local/bin/voz") == "$HOME/.local/share/tt/voz" && -x $HOME/.local/share/tt/voz-audio.py ]] ||
  falhou "instalação: ~/.local/bin/voz -> $(readlink "$HOME/.local/bin/voz" 2>/dev/null)"
passou 'instalação: voz no PATH, voz-audio.py executável no pacote'
