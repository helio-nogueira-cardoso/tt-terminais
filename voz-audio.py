#!/usr/bin/env python3
"""voz-audio — o áudio do 🎤 do tt em qualquer máquina (Linux, macOS, WSL; o celular usa o Tasker).

Grava uma frase (o fim é o silêncio), transcreve (faster-whisper, aqui ou noutra máquina por ssh), fala (Piper, say do
macOS, a voz do Windows no WSL, spd-say/espeak) e desenha a janela da conversa do 🎤. Só a biblioteca padrão; o
faster-whisper e o Piper vêm de um Python que os tenha (o venv do `voz --instalar-audio`, ou VOZ_PYTHON).

  voz-audio.py conversa [--digitar]   a janela do 🎤: ouve, mostra, manda ao `voz --turno` e fala as respostas
  voz-audio.py espelho                no celular: mostra a conversa do Tasker (conversa.log) e deixa digitar
  voz-audio.py diagnostico            o que esta máquina usa para gravar, transcrever e falar
  voz-audio.py teste                  grava uma frase, mostra o nível, transcreve e repete o que ouviu
  voz-audio.py gravar ARQ.wav         grava uma frase (até o silêncio)
  voz-audio.py transcrever ARQ.wav    o texto da fala (faster-whisper deste Python)
  voz-audio.py servidor               motor sem recarregar modelos: linha JSON {"op": "stt", "n": N} + N bytes de WAV,
                                      ou {"op": "tts", "texto": T, "saida": ARQ}; responde uma linha JSON
  voz-audio.py falar TEXTO            diz o texto com o melhor motor desta máquina
  voz-audio.py instalar               venv com faster-whisper e Piper, a voz pt-BR e o modelo (para o voz --instalar-audio)

Variáveis (o `voz` as preenche com a configuração de ~/.config/tt-voz): VOZ (o script voz), VOZ_TRANSCREVER (lugares:
local e/ou rótulos de máquina do tt), VOZ_FALA (auto|piper|say|windows|spd|espeak|termux|nenhum), VOZ_MODELO (small),
VOZ_GRAVADOR (comando que solta PCM s16le mono 16 kHz no stdout), VOZ_STT_CMD e VOZ_TTS_CMD (testes: comandos que
recebem o WAV / o texto no stdin), VOZ_LIMIAR, VOZ_PAUSA, VOZ_ESPERA_FALA_S, VOZ_PYTHON.
"""
import array
import base64
import glob
import io
import json
import math
import os
import platform
import queue
import re
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
import unicodedata
import wave

TAXA = 16000
QUADRO = 480  # 30 ms
CASA = os.path.expanduser("~")
DADOS = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(CASA, ".local", "share"), "tt-voz")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(CASA, ".cache"), "tt-voz")
VENV = os.path.join(DADOS, "venv")
VOZES = os.path.join(DADOS, "piper")
VOZ_PIPER = os.environ.get("VOZ_PIPER_VOZ", "pt_BR-faber-medium")
EU = os.path.abspath(__file__)
# frases que o Whisper inventa com o microfone quase em silêncio
ALUCINACOES = re.compile(r"^(legendas? (pela|por) .*|obrigad[oa] por assistir|.*amara\.org.*|inscreva-se.*|"
                         r"\.+|sous-titr.*|subt[ií]tulos.*|♪+)$", re.I)


SISTEMA = os.environ.get("VOZ_SISTEMA", "")  # testes: Darwin, WSL ou Linux no lugar do sistema de verdade


def eh_mac():
    return (SISTEMA or platform.system()) == "Darwin"


def eh_wsl():
    if SISTEMA:
        return SISTEMA == "WSL"
    try:
        with open("/proc/version") as f:
            return "microsoft" in f.read().lower()
    except OSError:
        return False


def eh_termux():
    return "com.termux" in os.environ.get("PREFIX", "")


def ambiente_audio():
    """O tmux e o ssh nem sempre trazem o endereço do servidor de som: o PulseAudio do WSLg e o do usuário."""
    if not os.environ.get("XDG_RUNTIME_DIR") and os.path.isdir("/run/user/%d" % os.getuid()):
        os.environ["XDG_RUNTIME_DIR"] = "/run/user/%d" % os.getuid()
    sock = os.environ.get("VOZ_WSLG", "/mnt/wslg/PulseServer")
    if eh_wsl() and not os.environ.get("PULSE_SERVER") and os.path.exists(sock):
        os.environ["PULSE_SERVER"] = "unix:" + sock


def powershell():
    p = shutil.which("powershell.exe")
    if p:
        return p
    p = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    return p if eh_wsl() and not SISTEMA and os.path.exists(p) else None


# ---------------------------------------------------------------- gravar
# ---------------------------------------------------------------- microfones
# A escolha pelo tipo: headset (e microfone dedicado) > USB/Bluetooth > webcam > o embutido; "monitor" e "stereo mix"
# não são microfone. VOZ_MICROFONE (voz --microfone "nome, outro") e o escolhido com a tecla n vêm antes de tudo.
HEADSET = ("headset", "headphone", "fone", "blackshark", "razer", "hyperx", "steelseries", "arctis", "corsair", "jabra",
           "plantronics", "airpods", "buds", "bose", "logitech g", "astro", "sennheiser", "epos", "rode", "shure", "yeti",
           "fifine", "maono", "audio-technica")
EXTERNO = ("usb", "bluetooth", "bluez", "wireless", "sem fio")
WEBCAM = ("webcam", "c920", "c922", "c930", "brio", "camera", "câmera")
EMBUTIDO = ("array", "digital microphone", "dmic", "built-in", "interno", "internal", "macbook", "jack", "analog",
            "line in", "entrada de linha", "realtek")
NAO_MIC = ("monitor", "stereo mix", "mixagem", "loopback", "what u hear", "o que voce ouve")
MEMO_MIC = os.path.join(CACHE, "microfone")


def preferencias():
    """O microfone escolhido com a tecla n (lembrado) e os de VOZ_MICROFONE, nessa ordem."""
    out = []
    try:
        with open(MEMO_MIC, encoding="utf-8") as f:
            out.append(f.read().strip().lower())
    except OSError:
        pass
    out += [x.strip().lower() for x in re.split(r"[,;]", os.environ.get("VOZ_MICROFONE", "")) if x.strip()]
    return [x for x in out if x]


def nota_microfone(nome):
    """Quanto o microfone parece bom para conversar (None: não é microfone)."""
    n = nome.lower()
    if any(x in n for x in NAO_MIC):
        return None
    nota = 0
    for i, p in enumerate(preferencias()):
        if p in n:
            nota = max(nota, 1000 - 10 * i)
    if any(x in n for x in HEADSET):
        nota += 300
    elif any(x in n for x in EXTERNO) and not any(x in n for x in WEBCAM):
        nota += 120
    if any(x in n for x in WEBCAM):
        nota += 60
    if any(x in n for x in EMBUTIDO):
        nota -= 100
    return nota


class Mic:
    """Um jeito de gravar: nome para mostrar, comando (PCM s16le mono 16 kHz no stdout), nota e se é o padrão."""

    def __init__(self, nome, cmd, nota=0, padrao=False, generico=False, partida=1.5):
        self.nome, self.cmd, self.nota, self.padrao, self.generico, self.partida = nome, cmd, nota, padrao, generico, partida


def ps1_windows():
    p = os.environ.get("VOZ_MIC_PS1") or os.path.join(os.path.dirname(EU), "voz-windows.ps1")
    return p if os.path.exists(p) else None


def caminho_windows(p):
    try:
        return subprocess.run(["wslpath", "-w", p], capture_output=True, text=True, timeout=5).stdout.strip() or p
    except (OSError, subprocess.SubprocessError):
        return p


def mics_windows():
    """No WSL: os microfones do Windows (voz-windows.ps1), gravados direto, sem mudar o padrão (o das chamadas)."""
    ps, ps1 = os.environ.get("VOZ_POWERSHELL") or powershell(), ps1_windows()
    if not ps or not ps1:
        return []
    base = [ps, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", caminho_windows(ps1)]
    try:
        r = subprocess.run(base + ["listar"], capture_output=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return []
    out = []
    for l in r.stdout.decode("utf-8", "replace").splitlines():
        partes = l.rstrip("\r").split("\t")
        if len(partes) < 3 or not partes[0].isdigit():
            continue
        nome = partes[3] if len(partes) > 3 and partes[3] else partes[2]
        nome = re.sub(r"^(Microphone|Microfone|Mic) \((.+)\)$", r"\2", nome)  # "Microphone (BlackShark…)" → "BlackShark…"
        nota = nota_microfone(nome)
        if nota is not None:
            out.append(Mic(nome + " (Windows)", base + ["gravar", partes[0]], nota, "padrao" in partes[1], partida=6.0))
    return out


def fontes_pulse():
    """(nome, descrição, padrão?, virtual?) das fontes do PulseAudio/PipeWire: sem os monitores de saída e sem as de
    porta "not available" (o microfone do fone que não está plugado). Virtual = filtro (um equalizador do EasyEffects),
    que só vale se tiver sinal."""
    if not shutil.which("pactl"):
        return []
    env = dict(os.environ, LC_ALL="C")
    try:
        txt = subprocess.run(["pactl", "list", "sources"], capture_output=True, text=True, timeout=5, env=env).stdout
        padrao = subprocess.run(["pactl", "get-default-source"], capture_output=True, text=True, timeout=5,
                                env=env).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return []
    out = []
    for bloco in re.split(r"\n(?=Source #)", txt):
        nome = re.search(r"^\s*Name: (.+)$", bloco, re.M)
        desc = re.search(r"^\s*Description: (.+)$", bloco, re.M)
        if not nome or nome.group(1).endswith(".monitor") or re.search(r"^\s*Monitor of Sink: (?!n/a)", bloco, re.M):
            continue
        porta = re.search(r"^\s*Active Port: (.+)$", bloco, re.M)
        if porta:
            linha = next((l for l in bloco.splitlines() if l.strip().startswith(porta.group(1).strip() + ":")), "")
            if re.search(r"not available\)\s*$", linha):
                continue
        virtual = bool(re.search(r'node\.virtual = "true"', bloco))
        out.append((nome.group(1).strip(), (desc.group(1) if desc else nome.group(1)).strip(), nome.group(1) == padrao, virtual))
    return out


def mics_mac():
    """macOS: as entradas do Core Audio (system_profiler), gravadas pelo sox ou pelo ffmpeg pelo nome."""
    try:
        d = json.loads(subprocess.run(["system_profiler", "SPAudioDataType", "-json"], capture_output=True, text=True,
                                      timeout=20).stdout or "{}")
    except (OSError, ValueError, subprocess.SubprocessError):
        return []
    out = []
    t = str(TAXA)
    for grupo in d.get("SPAudioDataType", []):
        for it in grupo.get("_items", []):
            if not it.get("coreaudio_device_input"):
                continue
            nome = it.get("_name", "")
            nota = nota_microfone(nome)
            if nota is None:
                continue
            if shutil.which("sox"):
                cmd = ["sox", "-q", "-t", "coreaudio", nome, "-t", "raw", "-b", "16", "-e", "signed-integer", "-c", "1", "-r", t, "-"]
            elif shutil.which("ffmpeg"):
                cmd = ["ffmpeg", "-loglevel", "quiet", "-nostdin", "-f", "avfoundation", "-i", ":" + nome, "-ac", "1",
                       "-ar", t, "-f", "s16le", "-"]
            else:
                continue
            out.append(Mic(nome, cmd, nota, it.get("coreaudio_default_audio_input_device") == "spaudio_yes"))
    return out


def candidatos_gravador():
    """Os jeitos de gravar desta máquina, do melhor microfone ao último recurso."""
    c = os.environ.get("VOZ_GRAVADOR")
    if c:
        return [Mic("VOZ_GRAVADOR", ["sh", "-c", c], 1000)]
    w = shutil.which
    t = str(TAXA)
    sox = ["-q", "-d", "-t", "raw", "-b", "16", "-e", "signed-integer", "-c", "1", "-r", t, "-"]
    ff = ["-loglevel", "quiet", "-nostdin"]
    out = []
    if eh_mac():
        out += mics_mac()
        if w("sox"):
            out.append(Mic("sox (entrada padrão)", ["sox"] + sox, -150, generico=True))
        if w("rec"):
            out.append(Mic("rec (entrada padrão)", ["rec"] + sox, -150, generico=True))
        if w("ffmpeg"):
            out.append(Mic("ffmpeg (entrada padrão)", ["ffmpeg"] + ff + ["-f", "avfoundation", "-i", ":0", "-ac", "1",
                                                                          "-ar", t, "-f", "s16le", "-"], -150, generico=True))
        return ordenar_mics(out)
    ambiente_audio()
    pa = ["--raw", "--format=s16le", "--rate=" + t, "--channels=1", "--latency-msec=60"]
    if eh_wsl():
        win = mics_windows()
        out += win
        if w("parecord"):  # o WSLg grava o padrão do Windows: o mesmo microfone, sem esperar o PowerShell
            p = next((m for m in win if m.padrao), None)
            out.append(Mic("parecord (o padrão do Windows%s)" % (": " + p.nome.replace(" (Windows)", "") if p else ""),
                           ["parecord"] + pa, (p.nota + 5) if p else -150, generico=not p))
    elif w("parecord"):
        for nome, desc, padrao, virtual in fontes_pulse():
            nota = nota_microfone(desc + " " + nome)
            if nota is not None:
                out.append(Mic(desc + (" (filtro)" if virtual else ""), ["parecord", "--device=" + nome] + pa,
                               nota - 400 if virtual else nota, padrao, generico=virtual))
    if w("parecord") and not eh_wsl():
        out.append(Mic("parecord (fonte padrão)", ["parecord"] + pa, -150, generico=True))
    if w("pw-record"):
        out.append(Mic("pw-record (fonte padrão)", ["pw-record", "--raw", "--rate", t, "--channels", "1", "--format", "s16", "-"],
                       -150, generico=True))
    if w("arecord"):
        out.append(Mic("arecord", ["arecord", "-q", "-t", "raw", "-f", "S16_LE", "-r", t, "-c", "1"], -160, generico=True))
        # o servidor de som pode ter perdido a placa (só "Dummy Output"): o microfone direto pelo ALSA ainda grava
        try:
            lista = subprocess.run(["arecord", "-l"], capture_output=True, text=True, timeout=5).stdout
        except (OSError, subprocess.SubprocessError):
            lista = ""
        for m in re.finditer(r"^card (\d+):.*?device (\d+): ([^\n]*)", lista, re.M):
            nome = m.group(3).split("[")[0].strip()
            nota = nota_microfone(nome)
            if nota is not None:
                out.append(Mic("arecord hw:%s,%s (%s)" % (m.group(1), m.group(2), nome),
                               ["arecord", "-q", "-D", "plughw:%s,%s" % (m.group(1), m.group(2)), "-t", "raw",
                                "-f", "S16_LE", "-r", t, "-c", "1"], min(nota, 0) - 170, generico=True))
    if w("sox"):
        out.append(Mic("sox (entrada padrão)", ["sox"] + sox, -180, generico=True))
    if w("ffmpeg"):
        out.append(Mic("ffmpeg (pulse)", ["ffmpeg"] + ff + ["-f", "pulse", "-i", "default", "-ac", "1", "-ar", t,
                                                           "-f", "s16le", "-"], -190, generico=True))
    return ordenar_mics(out)


def ordenar_mics(ms):
    """Pela nota; no empate, o padrão do sistema; depois a ordem de chegada."""
    return [m for _, m in sorted(enumerate(ms), key=lambda im: (-im[1].nota, not im[1].padrao, im[0]))]


def ler_exato(fd, n, ate):
    """Lê n bytes do fd até o instante `ate`; devolve o que veio (pode ser menos)."""
    buf = b""
    while len(buf) < n:
        resta = ate - time.time()
        if resta <= 0:
            break
        r, _, _ = select.select([fd], [], [], min(resta, 0.2))
        if not r:
            continue
        b = os.read(fd, n - len(buf))
        if not b:
            break
        buf += b
    return buf


def rms(pcm):
    a = array.array("h")
    a.frombytes(pcm[: len(pcm) // 2 * 2])
    if sys.byteorder == "big":
        a.byteswap()
    if not a:
        return 0.0
    return math.sqrt(sum(x * x for x in a) / len(a))


class Fluxo:
    """Um gravador aberto durante a conversa: uma thread lê o áudio e guarda os últimos 10 s; frase() consome do
    momento em que começa (o que tocou enquanto o tt falava fica para trás). O microfone do Windows leva ~1,5 s para
    abrir; assim isso acontece uma vez só."""

    def __init__(self, mic):
        import collections
        self.mic = mic
        self.err = tempfile.TemporaryFile()
        self.p = subprocess.Popen(mic.cmd, stdout=subprocess.PIPE, stderr=self.err, stdin=subprocess.DEVNULL)
        self.fila = collections.deque(maxlen=int(10 * TAXA / QUADRO))
        self.cond = threading.Condition()
        self.vivo = True
        threading.Thread(target=self._ler, daemon=True).start()

    def _ler(self):
        fd, tam, resto = self.p.stdout.fileno(), QUADRO * 2, b""
        while True:
            try:
                b = os.read(fd, 8192)
            except OSError:
                b = b""
            if not b:
                break
            resto += b
            with self.cond:
                while len(resto) >= tam:
                    self.fila.append(resto[:tam])
                    resto = resto[tam:]
                self.cond.notify_all()
        with self.cond:
            self.vivo = False
            self.cond.notify_all()

    def limpar(self):
        with self.cond:
            self.fila.clear()

    def quadro(self, espera=2.0):
        """O próximo quadro de 30 ms, ou None (o gravador parou ou não mandou nada a tempo)."""
        fim = time.time() + espera
        with self.cond:
            while not self.fila and self.vivo:
                resta = fim - time.time()
                if resta <= 0:
                    return None
                self.cond.wait(resta)
            return self.fila.popleft() if self.fila else None

    def erro(self):
        try:
            self.err.seek(0)
            linhas = self.err.read().decode("utf-8", "replace").strip().splitlines()
            return linhas[-1][:150] if linhas else "não entregou áudio"
        except (OSError, ValueError):
            return "não entregou áudio"

    def fechar(self):
        parar_processo(self.p)
        try:
            self.err.close()
        except OSError:
            pass


# A fala conta a partir deste nível (RMS de um quadro de 30 ms) ou de 2,6 × o ruído da sala, o que for maior. Um headset
# com filtro de ruído próprio (o BlackShark) entrega a voz baixa (picos de 400 a 700): a alta ou a máxima o ouvem.
SENSIBILIDADES = [("normal", 350), ("alta", 180), ("máxima", 100), ("baixa", 600)]


def limiar_minimo():
    """O nível mínimo da fala: VOZ_LIMIAR (voz --limiar, a tecla g das opções) é o nome de uma sensibilidade ou um número."""
    v = os.environ.get("VOZ_LIMIAR", "").strip().lower()
    for nome, valor in SENSIBILIDADES:
        if v.replace("á", "a") == nome.replace("á", "a"):
            return float(valor)
    try:
        return max(10.0, float(v.replace(",", ".")))
    except ValueError:
        return float(SENSIBILIDADES[0][1])


def rotulo_limiar(valor):
    return next((n for n, x in SENSIBILIDADES if x == valor), "%d" % valor)


class Gravador:
    """Escolhe o microfone (o de melhor nota que entrega áudio; os genéricos precisam de sinal) e grava frases, com
    o fim pelo silêncio. proximo() passa ao microfone seguinte (a tecla n da janela) e lembra a escolha."""

    def __init__(self):
        self.nome = None
        self.motivo = ""
        self.pulados = []
        self.cands = []
        self.atual = -1
        self.fluxo = None
        # da última frase: o maior nível que durou 3 quadros sem chegar a ser fala, e o limiar daquele momento
        self.quase, self.limiar_quase = 0.0, float(SENSIBILIDADES[0][1])

    @property
    def cmd(self):
        return self.fluxo.mic.cmd if self.fluxo else None

    def escolher(self, de=0):
        if not self.cands:
            self.cands = candidatos_gravador()
        if not self.cands:
            self.motivo = "sem programa para gravar (" + ("brew install sox" if eh_mac() else
                                                           "instale pulseaudio-utils, alsa-utils ou sox") + ")"
            return False
        if self.cands[0].nome == "VOZ_GRAVADOR":  # escolhido à mão: sem prova
            return self._usar(0, Fluxo(self.cands[0]), lembrar=False)
        erros, mudos = [], []
        self.pulados = []  # os que estavam no mudo (silêncio absoluto): a janela avisa
        sinal = float(os.environ.get("VOZ_SINAL_MIN", "20"))
        ordem = list(range(de, len(self.cands))) + list(range(0, de))
        for i in ordem:
            m = self.cands[i]
            f = Fluxo(m)
            ok, nv = self._prova(f, m)
            if ok and self.mudo(nv) and not m.generico:
                self.pulados.append(m.nome)
            if ok and not self.mudo(nv) and (nv >= sinal or not m.generico):
                return self._usar(i, f, lembrar=False)
            if ok:
                mudos.append((nv, i, f))
                continue
            erros.append("%s: %s" % (m.nome, f.erro()))
            f.fechar()
        if mudos:
            nv, i, f = max(mudos, key=lambda x: x[0])
            for _, _, outro in mudos:
                if outro is not f:
                    outro.fechar()
            return self._usar(i, f, lembrar=False)
        self.motivo = "nenhum microfone entregou som (" + "; ".join(erros)[:300] + ")"
        return False

    def _usar(self, i, fluxo, lembrar):
        if self.fluxo and self.fluxo is not fluxo:
            self.fluxo.fechar()
        self.atual, self.fluxo, self.nome = i, fluxo, self.cands[i].nome
        if lembrar:  # a escolha da tecla n vale enquanto esse microfone existir
            try:
                os.makedirs(CACHE, exist_ok=True)
                with open(MEMO_MIC, "w", encoding="utf-8") as f:
                    f.write(re.sub(r" \((Windows|o padrão.*)\)$", "", self.nome).lower() + "\n")
            except OSError:
                pass
        return True

    @staticmethod
    def _prova(f, m):
        """(entregou áudio?, nível): espera o primeiro áudio (o do Windows demora) e mede ~0,4 s. Nível 0 exato é
        silêncio digital: o microfone no mudo (o botão do headset), não uma sala quieta (que sempre tem ruído)."""
        partida = float(os.environ.get("VOZ_PROVA_S", m.partida))
        q = f.quadro(partida)
        if q is None:
            return False, 0.0
        b = [q]
        for _ in range(13):
            q = f.quadro(1.0)
            if q is None:
                break
            b.append(q)
        return len(b) >= 4, rms(b"".join(b[2:]))

    @staticmethod
    def mudo(nivel):
        return nivel == 0.0

    def proximo(self):
        """O microfone seguinte que entrega áudio (a tecla n); lembra a escolha. None se não há outro."""
        if len(self.cands) < 2:
            return None
        for k in range(1, len(self.cands)):
            i = (self.atual + k) % len(self.cands)
            f = Fluxo(self.cands[i])
            ok, nv = self._prova(f, self.cands[i])
            if ok and not self.mudo(nv):
                self._usar(i, f, lembrar=True)
                return self.nome
            f.fechar()
        return None

    def fechar(self):
        if self.fluxo:
            self.fluxo.fechar()
            self.fluxo = None

    def pausar(self):
        """O modo retorno: fecha o microfone (o sistema para de mostrá-lo em uso); retomar() reabre o mesmo, sem a prova."""
        self.fechar()

    def retomar(self):
        if self.fluxo and self.fluxo.vivo:
            return True
        if not (0 <= self.atual < len(self.cands)):
            return self.escolher()
        try:
            self.fluxo = Fluxo(self.cands[self.atual])
        except OSError:
            return self.escolher(self.atual)
        return True

    def frase(self, nivel=None, parar=None, espera=None, maximo=20.0, pausa=None):
        """Grava até o silêncio depois da fala. Devolve (pcm, motivo): motivo = fala | silencio | parado | erro."""
        espera = float(os.environ.get("VOZ_ESPERA_FALA_S", espera or 8.0))
        pausa = float(os.environ.get("VOZ_PAUSA", pausa or 1.1))
        minimo = limiar_minimo()
        self.quase, self.limiar_quase = 0.0, minimo
        ultimos = []
        if not self.fluxo or not self.fluxo.vivo:
            if self.fluxo:
                self.fluxo.fechar()
            if self.atual < 0 or not self.escolher(self.atual):
                return b"", "erro"
        self.fluxo.limpar()
        antes, fala = [], []
        piso = None
        acima = abaixo = 0
        falando = False
        inicio = time.time()
        comeco_fala = 0.0
        motivo = "silencio"
        algum_som = False
        while True:
            q = self.fluxo.quadro(2.0)
            if q is None:
                motivo = "erro" if not falando else "fala"
                break
            r = rms(q)
            algum_som = algum_som or r > 0
            piso = r if piso is None else (min(piso * 1.03, r) if not falando else piso)
            limiar = max(piso * 2.6, minimo)
            if nivel:
                nivel(min(1.0, r / (limiar * 2.0)), falando)
            if parar is not None and parar.is_set():
                motivo = "fala" if falando else "parado"
                break
            if not falando:
                antes.append(q)
                antes = antes[-12:]
                ultimos = (ultimos + [r])[-3:]
                if len(ultimos) == 3 and min(ultimos) > self.quase:
                    self.quase, self.limiar_quase = min(ultimos), limiar
                acima = acima + 1 if r > limiar else 0
                if acima >= 3:
                    falando, comeco_fala = True, time.time()
                    fala = list(antes)
                elif time.time() - inicio > espera:
                    break
            else:
                fala.append(q)
                abaixo = abaixo + 1 if r < limiar * 0.8 else 0
                if abaixo * QUADRO / TAXA >= pausa:
                    motivo = "fala"
                    break
                if time.time() - comeco_fala > maximo:
                    motivo = "fala"
                    break
        if motivo == "fala":
            return b"".join(fala), motivo
        if motivo == "silencio" and not algum_som:
            return b"", "mudo"
        return b"", motivo


def parar_processo(p):
    if p is None or p.poll() is not None:
        return
    try:
        p.terminate()
        p.wait(timeout=1.5)
    except (OSError, subprocess.SubprocessError):
        try:
            p.kill()
        except OSError:
            pass


def wav_de(pcm):
    b = io.BytesIO()
    with wave.open(b, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(TAXA)
        w.writeframes(pcm)
    return b.getvalue()


# ---------------------------------------------------------------- motor (faster-whisper e Piper deste Python)
class Motor:
    """faster-whisper e Piper carregados uma vez (no processo que tem os pacotes). O modelo e o dispositivo são a
    escolha desta máquina (escolha_local: o que ela mediu, ou a estimativa pelo hardware); a GPU que falhar cai na CPU."""

    def __init__(self):
        self.modelo = None
        self.piper = None
        self.escolha = None
        self.falso = os.environ.get("VOZ_MOTOR_FALSO")  # testes: transcrição fixa, sem modelo

    def _novo_modelo(self, nome, dispositivo, precisao):
        from faster_whisper import WhisperModel
        return WhisperModel(nome, device=dispositivo, compute_type=precisao)

    def _transcrever(self, audio, dica=""):
        segs, _ = self.modelo.transcribe(audio, language=os.environ.get("VOZ_IDIOMA", "pt"), beam_size=5,
                                         vad_filter=False, condition_on_previous_text=False,
                                         without_timestamps=True, initial_prompt=dica or None)
        return " ".join(s.text.strip() for s in segs).strip()

    def _aquecer(self):  # a primeira transcrição: carrega de vez e faz a GPU sem biblioteca falhar já
        self._transcrever(silencio(0.5))

    def carregar_stt(self):
        if self.modelo is not None or self.falso is not None:
            if self.escolha is None:
                self.escolha = {"modelo": "falso", "dispositivo": "cpu", "precisao": "-", "fonte": "teste"}
            return self.escolha
        e = escolha_local(sys.executable)
        tentativas = [e]
        if e["dispositivo"] != "cpu":  # a GPU só falha no primeiro uso (biblioteca CUDA, memória): aí vale a CPU
            tentativas.append(dict(e, dispositivo="cpu", precisao="int8", tempo=None, fonte="a GPU falhou"))
        erro = None
        for t in tentativas:
            try:
                self.modelo = self._novo_modelo(t["modelo"], t["dispositivo"], t["precisao"])
                self._aquecer()
                self.escolha = t
                if t is not e:
                    gpu_falhou(sys.executable, str(erro))
                return t
            except Exception as ex:  # o próximo jeito, ou o erro para o cliente
                self.modelo, erro = None, ex
        raise erro

    def stt(self, wav, dica=""):
        if self.falso is not None:
            return self.falso
        self.carregar_stt()
        with wave.open(io.BytesIO(wav)) as w:
            pcm = w.readframes(w.getnframes())
        import numpy
        audio = numpy.frombuffer(pcm, dtype=numpy.int16).astype(numpy.float32) / 32768.0
        return self._transcrever(audio, dica)

    def tts(self, texto, saida):
        if self.piper is None:
            from piper import PiperVoice
            self.piper = PiperVoice.load(arquivo_voz_piper())
        with wave.open(saida, "wb") as w:
            self.piper.synthesize_wav(texto, w)
        return saida

    def tts_wav(self, texto, voz):
        """O WAV (16 bits, mono) do texto na voz "piper:NOME" (offline) ou "edge:NOME" (a neural da Microsoft, online)."""
        if self.falso is not None:
            return wav_de(b"\0\0" * 1600)
        motor, _, nome = voz.partition(":")
        if motor == "piper":
            if not hasattr(self, "pipers"):
                self.pipers = {}
            if nome not in self.pipers:
                from piper import PiperVoice
                self.pipers[nome] = PiperVoice.load(os.path.join(VOZES, nome + ".onnx"))
            b = io.BytesIO()
            with wave.open(b, "wb") as w:
                self.pipers[nome].synthesize_wav(texto, w)
            return b.getvalue()
        if motor == "edge":
            import asyncio
            import edge_tts

            async def juntar():
                out = b""
                async for ch in edge_tts.Communicate(texto, nome, rate=os.environ.get("VOZ_RITMO", "+8%")).stream():
                    if ch["type"] == "audio":
                        out += ch["data"]
                return out
            return mp3_para_wav(asyncio.run(juntar()))
        raise RuntimeError("voz desconhecida: " + voz)


# As vozes: a do sistema (Windows, macOS, spd-say) e as neurais, geradas no motor (aqui ou na máquina que transcreve)
# e tocadas no aparelho do microfone. As da Microsoft (as do Edge) são online: o texto falado vai ao serviço dela.
VOZES_NEURAIS = [("piper:pt_BR-faber-medium", "Piper Faber", False),
                 ("edge:pt-BR-FranciscaNeural", "Francisca", True),
                 ("edge:pt-BR-AntonioNeural", "Antônio", True),
                 ("edge:pt-BR-ThalitaMultilingualNeural", "Thalita", True)]
VOZ_PADRAO = "piper:pt_BR-faber-medium"


def rotulo_voz(v):
    if v == "sistema":
        return "a do sistema"
    r = next((x for x in VOZES_NEURAIS if x[0] == v), None)
    return ("%s (online, Microsoft)" % r[1] if r[2] else "%s (offline)" % r[1]) if r else v


def vozes_de(py):
    """As vozes neurais que o Python py (um venv) sabe gerar: Piper com a voz baixada; as da Microsoft com o edge-tts."""
    if not py:
        return []
    sps = site_packages(py)
    tem = lambda mod: any(os.path.isdir(os.path.join(sp, mod)) for sp in sps)
    out = []
    if tem("piper"):
        out += ["piper:" + os.path.basename(f)[:-5] for f in sorted(glob.glob(os.path.join(VOZES, "*.onnx")))]
    if tem("edge_tts") and tem("av"):
        out += [v for v, _, online in VOZES_NEURAIS if v.startswith("edge:")]
    return out


def arquivo_voz_piper():
    return os.path.join(VOZES, VOZ_PIPER + ".onnx")


def mp3_para_wav(mp3, taxa=24000):
    """MP3 → WAV 16 bits mono, pelo PyAV (que o faster-whisper já traz): sem ffmpeg na máquina."""
    import av
    pcm = bytearray()
    with av.open(io.BytesIO(mp3)) as c:
        rs = av.AudioResampler(format="s16", layout="mono", rate=taxa)
        for fr in c.decode(audio=0):
            for o in rs.resample(fr):
                pcm += o.to_ndarray().tobytes()
        for o in rs.resample(None):
            pcm += o.to_ndarray().tobytes()
    b = io.BytesIO()
    with wave.open(b, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(taxa)
        w.writeframes(bytes(pcm))
    return b.getvalue()


def silencio(segundos):
    import numpy
    return numpy.zeros(int(TAXA * segundos), dtype=numpy.float32)


def servidor():
    """Laço do motor: lê pedidos no stdin (binário) e responde uma linha JSON por pedido."""
    com_libs_cuda()
    m = Motor()
    ent, sai = sys.stdin.buffer, sys.stdout.buffer
    sai.write(b'{"pronto": true}\n')
    sai.flush()
    while True:
        linha = ent.readline()
        if not linha:
            return 0
        dados = b""
        try:
            p = json.loads(linha)
            t0 = time.time()
            if p.get("op") == "tts_wav":
                dados = m.tts_wav(p["texto"], p["voz"])
                r = {"n": len(dados), "s": round(time.time() - t0, 2)}
            elif p.get("op") == "stt":
                wav = ent.read(int(p["n"]))
                r = {"texto": m.stt(wav, p.get("dica", "")), "s": round(time.time() - t0, 2)}
            elif p.get("op") == "tts":
                r = {"saida": m.tts(p["texto"], p["saida"]), "s": round(time.time() - t0, 2)}
            elif p.get("op") == "carregar":
                r = {"ok": True}
                if p.get("stt"):
                    r["escolha"] = m.carregar_stt()
                if p.get("tts") and os.path.exists(arquivo_voz_piper()):
                    m.tts("ok", os.path.join(tempfile.gettempdir(), "tt-voz-carregar-%d.wav" % os.getpid()))
                r["s"] = round(time.time() - t0, 2)
            else:
                r = {"erro": "pedido desconhecido"}
        except Exception as e:  # o cliente decide o que fazer; o laço segue
            r, dados = {"erro": "%s: %s" % (type(e).__name__, e)}, b""
        sai.write((json.dumps(r, ensure_ascii=False) + "\n").encode("utf-8") + dados)
        sai.flush()


def pythons():
    """Pythons candidatos ao motor, na ordem: VOZ_PYTHON, o venv do tt-voz, um venv do whisper que já exista, este."""
    out = []
    for p in (os.environ.get("VOZ_PYTHON"), os.path.join(VENV, "bin", "python"),
              os.path.join(CASA, ".local", "share", "whisper-venv", "bin", "python"), sys.executable):
        if p and os.path.exists(p) and p not in out:
            out.append(p)
    return out


def site_packages(py):
    """As site-packages de um Python de venv (<venv>/bin/python → <venv>/lib/python3.X/site-packages)."""
    return sorted(glob.glob(os.path.join(os.path.dirname(os.path.dirname(py)), "lib", "python3*", "site-packages")))


def python_com(modulo):
    """O primeiro Python que tem o módulo. Num venv basta olhar a pasta (rápido: a janela pergunta a cada abertura)."""
    for p in pythons():
        sps = site_packages(p)
        if sps and os.path.exists(os.path.join(os.path.dirname(os.path.dirname(p)), "pyvenv.cfg")):
            if any(os.path.isdir(os.path.join(sp, modulo)) for sp in sps):
                return p
            continue
        if p == sys.executable:
            import importlib.util
            if importlib.util.find_spec(modulo):
                return p
            continue
        try:
            if subprocess.run([p, "-c", "import " + modulo], capture_output=True, timeout=30).returncode == 0:
                return p
        except (OSError, subprocess.SubprocessError):
            pass
    return None


# ---------------------------------------------------------------- escolha do motor: modelo, dispositivo e máquina
# Cada máquina mede as combinações que tem (voz-audio.py medir: frases de referência ditas pelo Piper, transcritas por
# cada modelo na CPU e na GPU) e guarda o tempo e o erro. A janela pergunta a todas as máquinas ao mesmo tempo
# (capacidade), soma a carga de agora e a rede, e fica com o menor custo = tempo + PESO_ERRO × erro; o tempo de verdade
# de cada frase (desempenho.json) corrige a estimativa da próxima vez, e uma troca no meio da conversa se piorar.
MEDICOES = os.path.join(DADOS, "medicoes.json")
DESEMPENHO = os.path.join(CACHE, "desempenho.json")
SONDAS = os.path.join(CACHE, "sondas.json")
REPOS = {"tiny": "Systran/faster-whisper-tiny", "base": "Systran/faster-whisper-base",
         "small": "Systran/faster-whisper-small", "medium": "Systran/faster-whisper-medium",
         "large-v3-turbo": "mobiuslabsgmbh/faster-whisper-large-v3-turbo"}
# por modelo: tempo relativo ao small na CPU, MB em disco (float16; em int8 ocupa a metade) e erro típico em pt-BR
PERFIL = {"tiny": (0.3, 75, 0.45), "base": (0.45, 145, 0.35), "small": (1.0, 484, 0.2),
          "medium": (2.6, 1528, 0.15), "large-v3-turbo": (2.0, 1618, 0.12)}
PESO_ERRO = float(os.environ.get("VOZ_PESO_ERRO", "4"))  # errar 1 palavra em 4 custa como esperar 1 s a mais
FRASES_TESTE = ["Troca essa sessão para o Codex e me avisa quando estiver pronto.",
                "Quais tarefas eu tenho para hoje?",
                "Libera a sessão dois e pergunta ao Claude que horas são lá.",
                "Abre uma sessão nova no notebook com o Kiro."]
DICA_TESTE = "tt, Terminal, Claude, Codex, Kiro, sessão, sessões, máquinas, liberar, encerrar, tarefas, contas, notebook"
NUMEROS = {"0": "zero", "1": "um", "2": "dois", "3": "tres", "4": "quatro", "5": "cinco", "6": "seis", "7": "sete",
           "8": "oito", "9": "nove", "10": "dez"}


def ler_json(arq, padrao=None):
    try:
        with open(arq, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return padrao


def gravar_json(arq, dados):
    try:
        os.makedirs(os.path.dirname(arq), exist_ok=True)
        tmp = "%s.%d" % (arq, os.getpid())
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(dados, f, ensure_ascii=False, indent=1)
        os.replace(tmp, arq)
    except OSError:
        pass


def hf_hub():
    return os.environ.get("HF_HUB_CACHE") or os.path.join(
        os.environ.get("HF_HOME") or os.path.join(CASA, ".cache", "huggingface"), "hub")


def modelos_em_cache():
    """Os modelos do Whisper já baixados (o model.bin inteiro no cache do Hugging Face)."""
    out = []
    for nome, repo in REPOS.items():
        snaps = os.path.join(hf_hub(), "models--" + repo.replace("/", "--"), "snapshots")
        try:
            if any(os.path.exists(os.path.join(snaps, s, "model.bin")) for s in os.listdir(snaps)):
                out.append(nome)
        except OSError:
            pass
    return out


def gpus_nvidia():
    """GPUs NVIDIA com driver ("nome, MB"). O macOS não tem CUDA (o ctranslate2 usa só a CPU lá)."""
    teste = os.environ.get("VOZ_GPUS")
    if teste is not None:
        return [g.strip() for g in teste.split(";") if g.strip()]
    if eh_mac() or os.environ.get("VOZ_SEM_GPU"):
        return []
    smi = shutil.which("nvidia-smi") or next((p for p in ("/usr/lib/wsl/lib/nvidia-smi",) if os.path.exists(p)), None)
    if not smi:
        return []
    try:
        r = subprocess.run([smi, "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return []
    return [l.strip() for l in r.stdout.splitlines() if l.strip()] if r.returncode == 0 else []


def vram_mb(gpus):
    try:
        return max(int(g.rsplit(",", 1)[1]) for g in gpus)
    except (ValueError, IndexError):
        return 0


def pacotes(py):
    """Versões dos pacotes do motor no venv (pelas pastas dist-info, sem importar nada)."""
    out = {}
    for sp in site_packages(py) if py else []:
        for d in glob.glob(os.path.join(sp, "*.dist-info")):
            nome, _, ver = os.path.basename(d)[:-10].rpartition("-")
            nome = nome.lower().replace("_", "-")
            if nome in ("faster-whisper", "ctranslate2", "nvidia-cublas-cu12", "nvidia-cudnn-cu12"):
                out[nome] = ver
    return out


def assinatura(py):
    """O que, se mudar, invalida as medições: pacotes, modelos baixados e GPUs."""
    return json.dumps({"pacotes": pacotes(py), "modelos": modelos_em_cache(), "gpus": gpus_nvidia()}, sort_keys=True)


def libs_cuda_dirs():
    out = []
    for sp in [p for p in sys.path if p.endswith("site-packages")]:
        for sub in ("nvidia/cublas/lib", "nvidia/cudnn/lib", "nvidia/cuda_nvrtc/lib"):
            d = os.path.join(sp, sub)
            if os.path.isdir(d):
                out.append(d)
    return out


def com_libs_cuda():
    """As bibliotecas CUDA do pip (nvidia-cublas-cu12, nvidia-cudnn-cu12) só valem no LD_LIBRARY_PATH de partida:
    se faltam lá, o processo recomeça com elas (os fds, inclusive o canal do motor, continuam)."""
    atual = [d for d in os.environ.get("LD_LIBRARY_PATH", "").split(":") if d]
    falta = [d for d in libs_cuda_dirs() if d not in atual]
    if falta and not os.environ.get("_VOZ_CUDA"):
        os.environ["LD_LIBRARY_PATH"] = ":".join(falta + atual)
        os.environ["_VOZ_CUDA"] = "1"
        os.execv(sys.executable, [sys.executable] + sys.argv)


def gpu_falhou(py, motivo):
    """A GPU falhou de verdade: as medições desta assinatura passam a valer só para a CPU."""
    med = ler_json(MEDICOES) or {}
    if med.get("assinatura") == assinatura(py):
        med["gpu_falhou"] = motivo[:200]
        gravar_json(MEDICOES, med)


def ram_livre_mb():
    try:
        with open("/proc/meminfo") as f:
            for l in f:
                if l.startswith("MemAvailable:"):
                    return int(l.split()[1]) // 1024
    except OSError:
        pass
    try:  # macOS: metade da memória física, como aproximação
        r = subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True, timeout=5)
        return int(r.stdout.strip()) // 2 // 1048576
    except (OSError, ValueError, subprocess.SubprocessError):
        return 0


def carga():
    try:
        return os.getloadavg()[0]
    except OSError:
        return 0.0


def palavras(t):
    t = unicodedata.normalize("NFKD", t.lower())
    t = "".join(c for c in t if not unicodedata.combining(c))
    return [NUMEROS.get(w, w) for w in re.findall(r"[a-z0-9]+", t)]


def erro_palavras(ref, hip):
    """Taxa de erro por palavra (distância de edição / palavras da referência), sem acento nem pontuação."""
    a, b = palavras(ref), palavras(hip)
    d = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        ant, d[0] = d[0], i
        for j, y in enumerate(b, 1):
            ant, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, ant + (x != y))
    return d[len(b)] / max(1, len(a))


def erro_efetivo(r):
    """As frases de referência são voz sintética, mais fácil que a de um microfone de verdade (os modelos pequenos
    parecem tão bons quanto os grandes): o erro medido vale metade; a outra metade é o erro típico do modelo."""
    tipico = PERFIL.get(r.get("modelo"), PERFIL["small"])[2]
    return 0.5 * r["erro"] + 0.5 * tipico if r.get("fonte", "medido") == "medido" and "erro" in r else r.get("erro", tipico)


def custo(r):
    return (r.get("tempo") or 99) + PESO_ERRO * erro_efetivo(r)


def estimativa(modelo, nucleos):
    """Sem medição: o tempo de uma frase na CPU pelo número de núcleos (o small leva ~2,2 s em 8)."""
    return round(2.2 * PERFIL.get(modelo, PERFIL["small"])[0] * (8.0 / max(1, nucleos or 1)) ** 0.7, 2)


def escolha_local(py):
    """O jeito desta máquina transcrever: {modelo, dispositivo, precisao, tempo, erro, fonte}. Vem das medições (se a
    assinatura bate) ou da estimativa pelo hardware; VOZ_MODELO e VOZ_DISPOSITIVO restringem."""
    pedido, disp = os.environ.get("VOZ_MODELO"), os.environ.get("VOZ_DISPOSITIVO")
    med = ler_json(MEDICOES) or {}
    if med.get("assinatura") == assinatura(py):
        rs = [r for r in med.get("resultados", []) if r.get("tempo")
              and (not pedido or r["modelo"] == pedido) and (not disp or r["dispositivo"] == disp)
              and not (med.get("gpu_falhou") and r["dispositivo"] != "cpu")]
        if rs:
            r = min(rs, key=custo)
            return dict(r, fonte="medido", carga_medida=med.get("carga", 0.0), nucleos=med.get("nucleos"))
    cache = modelos_em_cache()
    n = os.cpu_count() or 1
    if pedido:
        m = pedido
    elif ram_livre_mb() and ram_livre_mb() < 1500 or n < 4:
        m = "base"
    else:
        m = "small"
    if not pedido and m not in cache and cache:  # um baixado de tamanho parecido, em vez de baixar outro
        m = min(cache, key=lambda c: abs(PERFIL[c][0] - PERFIL[m][0]))
    return {"modelo": m, "dispositivo": disp or "cpu", "precisao": "int8", "tempo": estimativa(m, n),
            "erro": PERFIL.get(m, PERFIL["small"])[2], "fonte": "estimado", "carga_medida": 0.0, "nucleos": n}


def capacidade():
    """O que esta máquina oferece para transcrever (a resposta do voz --motor-info, por ssh, à janela de outra)."""
    t0 = time.time()
    py = python_com("faster_whisper")
    info = {"sistema": "macOS" if eh_mac() else ("WSL" if eh_wsl() else platform.system()), "nucleos": os.cpu_count(),
            "carga": round(carga(), 2), "ram_livre_mb": ram_livre_mb(), "whisper": bool(py), "gpus": gpus_nvidia()}
    if py:
        info["escolha"] = escolha_local(py)
    info["vozes"] = vozes_de(python_com("piper") or python_com("edge_tts") or py)
    info["s"] = round(time.time() - t0, 3)
    return info


def fator_carga(info, e):
    """Quanto a carga de agora atrasa em relação à da medição (na GPU, bem menos)."""
    n = max(1, info.get("nucleos") or 1)
    agora = max(1.0, (info.get("carga", 0.0) + 1) / n)
    antes = max(1.0, ((e.get("carga_medida") or 0.0) + 1) / n)
    f = agora / antes
    return f ** 0.3 if e.get("dispositivo") != "cpu" else f


def chave(lugar, e):
    return "%s|%s|%s" % (lugar, e.get("modelo"), e.get("dispositivo"))


def avaliar(lugar, info, hist):
    """(custo, tempo previsto por frase, de onde veio) de transcrever em `lugar`; None se ele não transcreve."""
    e = info.get("escolha")
    if not info.get("whisper") or not e:
        return None
    h = hist.get(chave(lugar, e)) or {}
    if h.get("n", 0) >= 2:
        tempo, fonte = h["s"] * fator_carga(info, e) / max(0.2, fator_carga(dict(info, carga=h.get("carga", 0)), e)), "uso"
    else:
        tempo = (e.get("tempo") or estimativa(e.get("modelo", "small"), info.get("nucleos"))) * fator_carga(info, e)
        tempo += 0 if lugar == "local" else 0.15  # a ida e a volta do áudio pela rede
        fonte = e.get("fonte", "estimado")
    return tempo + PESO_ERRO * erro_efetivo(e), round(tempo, 2), fonte


def ssh_cmd(dest, comando, espera=3):
    m = os.environ.get("VOZ_MODELO", "")
    if re.match(r"^[a-z0-9.-]+$", m):  # o modelo escolhido aqui vale na máquina que transcreve
        comando = "VOZ_MODELO=%s %s" % (m, comando)
    return ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=%d" % espera, "-o", "ServerAliveInterval=10",
            "-o", "ControlPath=%s/.cache/tt-ssh-%%r@%%h" % CASA, dest,
            'PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"; ' + comando]


class ForaDoAr(RuntimeError):
    """O ssh não chegou à máquina (desligada, sem rede): ela fica de fora por 10 min."""


def sondar(lugar, prazo=6.0):
    """capacidade() de `lugar` (local aqui; outra máquina pelo voz --motor-info, por ssh)."""
    if lugar == "local":
        return capacidade()
    dest = destino(lugar)
    if not dest or dest == "local":
        raise RuntimeError("máquina desconhecida")
    try:
        r = subprocess.run(ssh_cmd(dest, "voz --motor-info"), capture_output=True, text=True, timeout=prazo)
    except subprocess.TimeoutExpired:
        raise ForaDoAr("o ssh não respondeu em %d s" % prazo)
    if r.returncode == 255:  # o código do próprio ssh: não conectou
        raise ForaDoAr((r.stderr.strip().splitlines() or ["ssh falhou"])[-1][:120])
    linhas = [l for l in r.stdout.splitlines() if l.startswith("{")]
    if r.returncode != 0 or not linhas:
        raise RuntimeError("sem o motor de voz (tt antigo ou sem python3)")
    return json.loads(linhas[-1])


def escolher(lugares, avisar=None):
    """Os lugares que transcrevem, do menor custo ao maior: [(custo, lugar, tempo, fonte, info)], e os erros.
    Pergunta a todos ao mesmo tempo; a máquina que não respondeu há menos de 10 min fica de fora (sem esperar o
    ssh dela de novo); depois da primeira resposta útil, espera as outras no máximo mais 1,5 s."""
    sondas = ler_json(SONDAS, {}) or {}
    agora = time.time()
    resultado, erros, fila = {}, [], []
    for l in dict.fromkeys(lugares):
        f = sondas.get(l) or {}
        if l != "local" and f.get("falhou") and agora - f["falhou"] < 600:
            erros.append("%s: fora do ar (há %d min)" % (l, (agora - f["falhou"]) // 60))
            continue
        fila.append(l)

    def um(l):
        try:
            resultado[l] = sondar(l)
        except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as ex:
            resultado[l] = ex

    ts = {l: threading.Thread(target=um, args=(l,), daemon=True) for l in fila}
    for t in ts.values():
        t.start()
    fim, primeira = agora + 7.0, None
    while time.time() < fim and any(t.is_alive() for t in ts.values()):
        if primeira is None and any(isinstance(v, dict) and v.get("whisper") for v in list(resultado.values())):
            primeira = time.time()
            fim = min(fim, primeira + 1.5)
        time.sleep(0.05)
    hist = ler_json(DESEMPENHO, {}) or {}
    ranking = []
    for l in fila:
        v = resultado.get(l)
        if isinstance(v, dict):
            sondas[l] = {"ok": time.time()}
            a = avaliar(l, v, hist)
            if a:
                ranking.append((a[0], l, a[1], a[2], v))
            else:
                erros.append("%s: sem faster-whisper" % l)
        else:
            if isinstance(v, ForaDoAr):
                sondas[l] = {"falhou": time.time()}
            erros.append("%s: %s" % (l, v if v is not None else "demorou para responder (fica de fora desta vez)"))
    gravar_json(SONDAS, sondas)
    ranking.sort(key=lambda x: x[0])
    return ranking, erros


def registrar_tempo(lugar, e, segundos, info=None):
    """O tempo de verdade de uma frase (com a rede), média móvel por lugar, modelo e dispositivo."""
    hist = ler_json(DESEMPENHO, {}) or {}
    k = chave(lugar, e)
    h = hist.get(k) or {"s": segundos, "n": 0}
    h["s"] = round(segundos if h["n"] == 0 else 0.7 * h["s"] + 0.3 * segundos, 3)
    h["n"] = min(h["n"] + 1, 50)
    h["carga"] = (info or {}).get("carga", 0.0)
    h["quando"] = int(time.time())
    hist[k] = h
    gravar_json(DESEMPENHO, hist)
    return h


def descrever(lugar, e, tempo=None):
    disp = {"cpu": "CPU"}.get(e.get("dispositivo"), "GPU")
    t = (" · ~%.1f s" % tempo).replace(".", ",") if tempo else ""
    return "%s · %s na %s%s" % ("esta máquina" if lugar == "local" else lugar, e.get("modelo"), disp, t)


def combinacoes(gpus, cache, nucleos, ram):
    """(modelo, dispositivo) a medir: na CPU os leves (o medium e o turbo só em CPU forte); na GPU, os que cabem nela."""
    out = []
    leves = [m for m in ("tiny", "base", "small") if m in cache] or ["small"]
    pesados = [m for m in ("medium", "large-v3-turbo") if m in cache]
    for m in leves + ([p for p in pesados if nucleos >= 16 and ram > 4000] if pesados else []):
        out.append((m, "cpu"))
    if gpus:
        vram = vram_mb(gpus)
        for m in [m for m in ("small", "medium", "large-v3-turbo") if m in cache] or ["small"]:
            if PERFIL[m][1] / 2 < vram * 0.7:
                out.append((m, "cuda"))
    return out


def medir(fabrica=None, sintetizar=None, saida=print):
    """Mede cada combinação desta máquina com as frases de referência (ditas pelo Piper) e grava MEDICOES."""
    com_libs_cuda()
    if sintetizar is None:
        import numpy
        from piper import PiperVoice
        voz = PiperVoice.load(arquivo_voz_piper())

        def sintetizar(frase):
            b = io.BytesIO()
            with wave.open(b, "wb") as w:
                voz.synthesize_wav(frase, w)
            with wave.open(io.BytesIO(b.getvalue())) as w:
                taxa, pcm = w.getframerate(), w.readframes(w.getnframes())
            a = numpy.frombuffer(pcm, dtype=numpy.int16).astype(numpy.float32) / 32768.0
            x = numpy.arange(0, len(a), taxa / float(TAXA))
            a = numpy.interp(x, numpy.arange(len(a)), a).astype(numpy.float32)
            # ruído de microfone de notebook (~15 dB abaixo da fala), sempre o mesmo: a voz sintética limpa é fácil demais
            ruido = numpy.random.default_rng(7).normal(0, 1, len(a)).astype(numpy.float32)
            return a + ruido * float(numpy.sqrt(numpy.mean(a ** 2))) * 10 ** (-15 / 20.0)
    audios = [(f, sintetizar(f)) for f in FRASES_TESTE]
    gpus, cache, n, ram = gpus_nvidia(), modelos_em_cache(), os.cpu_count() or 1, ram_livre_mb()
    resultados = []
    for modelo, disp in combinacoes(gpus, cache, n, ram):
        for prec in (["int8"] if disp == "cpu" else ["int8", "int8_float16", "float32"]):
            m = Motor()
            if fabrica:
                m._novo_modelo = fabrica
            try:
                t0 = time.time()
                m.modelo = m._novo_modelo(modelo, disp, prec)
                carga_s = time.time() - t0
                m._transcrever(audios[0][1], DICA_TESTE)  # aquecimento
                tempos, erros = [], []
                for ref, a in audios:
                    t0 = time.time()
                    hip = m._transcrever(a, DICA_TESTE)
                    tempos.append(time.time() - t0)
                    erros.append(erro_palavras(ref, hip))
                r = {"modelo": modelo, "dispositivo": disp, "precisao": prec, "tempo": round(sum(tempos) / len(tempos), 3),
                     "erro": round(sum(erros) / len(erros), 3), "carregar": round(carga_s, 2)}
                resultados.append(r)
                saida("  %-15s %-4s %-12s %5.2f s por frase · erro %3.0f%% · carregar %.1f s"
                      % (modelo, disp, prec, r["tempo"], r["erro"] * 100, carga_s))
                break
            except Exception as ex:  # a próxima precisão, ou a próxima combinação
                saida("  %-15s %-4s %-12s ✗ %s" % (modelo, disp, prec, str(ex)[:90]))
            finally:
                m.modelo = None
    med = {"assinatura": assinatura(sys.executable), "quando": int(time.time()), "carga": round(carga(), 2),
           "nucleos": n, "resultados": resultados}
    gravar_json(MEDICOES, med)
    if resultados:
        e = escolha_local(sys.executable)
        saida("escolha: %s %s (%s)" % (e["modelo"], {"cpu": "na CPU"}.get(e["dispositivo"], "na GPU"),
                                       ("%.2f s por frase, erro %.0f%%" % (e["tempo"], e["erro"] * 100)).replace(".", ",")))
    return med


def medicao_velha(py):
    med = ler_json(MEDICOES) or {}
    return med.get("assinatura") != assinatura(py)


class Canal:
    """Um motor rodando (aqui ou por ssh), com o protocolo do `servidor`."""

    def __init__(self, cmd, nome):
        self.nome = nome
        self.p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.trava = threading.Lock()
        linha = self._linha(float(os.environ.get("VOZ_MOTOR_PARTIDA_S", "40")))
        if not linha or not json.loads(linha).get("pronto"):
            parar_processo(self.p)
            raise RuntimeError("o motor em %s não respondeu" % nome)

    def _linha(self, tempo):
        fd = self.p.stdout.fileno()
        buf = b""
        fim = time.time() + tempo
        while not buf.endswith(b"\n"):
            resta = fim - time.time()
            if resta <= 0:
                return None
            r, _, _ = select.select([fd], [], [], min(resta, 0.5))
            if r:
                b = os.read(fd, 1)
                if not b:
                    return None
                buf += b
        return buf.decode("utf-8", "replace")

    def pedir(self, pedido, dados=b"", tempo=60, binario=False):
        """A resposta (JSON) do motor; com binario=True, (resposta, os "n" bytes que vêm depois dela)."""
        corpo = b""
        with self.trava:
            if self.p.poll() is not None:
                raise RuntimeError("o motor em %s parou" % self.nome)
            self.p.stdin.write((json.dumps(pedido, ensure_ascii=False) + "\n").encode() + dados)
            self.p.stdin.flush()
            linha = self._linha(tempo)
            r = json.loads(linha) if linha else None
            if binario and r and r.get("n"):
                corpo = self._bytes(int(r["n"]), tempo)
        if not linha:
            raise RuntimeError("o motor em %s não respondeu a tempo" % self.nome)
        if r.get("erro"):
            raise RuntimeError(r["erro"])
        return (r, corpo) if binario else r

    def _bytes(self, n, tempo):
        fd, buf, fim = self.p.stdout.fileno(), b"", time.time() + tempo
        while len(buf) < n:
            resta = fim - time.time()
            if resta <= 0:
                raise RuntimeError("o motor em %s não mandou o áudio a tempo" % self.nome)
            r, _, _ = select.select([fd], [], [], min(resta, 0.5))
            if r:
                b = os.read(fd, min(65536, n - len(buf)))
                if not b:
                    raise RuntimeError("o motor em %s parou no meio" % self.nome)
                buf += b
        return buf

    def fechar(self):
        try:
            self.p.stdin.close()
        except OSError:
            pass
        parar_processo(self.p)


class Transcritor:
    """Transcreve no melhor lugar (escolher: esta máquina ou outra do tt, pelo custo), com o motor aberto uma vez por
    conversa. Mede cada frase; se o escolhido ficar bem mais lento que o seguinte, abre o seguinte em segundo plano e
    troca. Motor que cai é aberto de novo, no melhor lugar que sobrar."""

    def __init__(self, avisar=None):
        self.canal = None
        self.onde = ""
        self.desc = ""
        self.motivo = ""
        self.escolha = {}
        self.info = {}
        self.ranking = []
        self.proximo = None  # (canal, lugar, escolha, info) já carregado, esperando a troca
        self.trocando = False
        self.fechado = False
        self.trava = threading.Lock()
        self.avisar = avisar or (lambda t: None)

    def lugares(self):
        v = os.environ.get("VOZ_TRANSCREVER", "").split()
        return v or ["local"]

    @staticmethod
    def _canal(lugar):
        if lugar == "local":
            py = python_com("faster_whisper")
            if not py:
                raise RuntimeError("sem faster-whisper (voz --instalar-audio)")
            return Canal([py, EU, "servidor"], "local")
        dest = destino(lugar)
        if not dest or dest == "local":
            raise RuntimeError("máquina desconhecida")
        return Canal(ssh_cmd(dest, "exec voz --motor", espera=8), lugar)

    def _abrir(self, lugar, info):
        c = self._canal(lugar)
        try:
            r = c.pedir({"op": "carregar", "stt": True}, tempo=300)
        except (OSError, RuntimeError, ValueError):
            c.fechar()
            raise
        return c, r.get("escolha") or info.get("escolha") or {}

    def preparar(self, pular=()):
        if os.environ.get("VOZ_STT_CMD"):
            self.onde = self.desc = "comando de teste"
            return True
        self.avisar("escolhendo onde transcrever…")
        self.ranking, erros = escolher([l for l in self.lugares() if l not in pular])
        for custo_, lugar, tempo, fonte, info in self.ranking:
            try:
                self.avisar("carregando o reconhecimento: %s…" % descrever(lugar, info.get("escolha", {})))
                self.canal, self.escolha = self._abrir(lugar, info)
                self.onde, self.info = lugar, info
                if self.escolha.get("modelo") != info.get("escolha", {}).get("modelo") or \
                        self.escolha.get("dispositivo") != info.get("escolha", {}).get("dispositivo"):
                    tempo = None  # carregou outro jeito (a GPU falhou): a estimativa não vale
                self.desc = descrever(lugar, self.escolha, tempo)
                if len(self.ranking) > 1:
                    self.desc += " (de %d)" % len(self.ranking)
                return True
            except (OSError, RuntimeError, ValueError) as ex:
                erros.append("%s: %s" % (lugar, ex))
        self.motivo = "; ".join(erros) or "nenhum lugar para transcrever"
        return False

    def _alternativa(self):
        """O melhor lugar do ranking que não é o de agora: (lugar, tempo previsto, info)."""
        for custo_, lugar, tempo, fonte, info in self.ranking:
            if lugar != self.onde:
                return lugar, tempo, info
        return None

    def _talvez_trocar(self, h):
        """Depois de duas frases, se o atual leva 1,6 vez o previsto para o seguinte, carrega o seguinte em paralelo."""
        alt = self._alternativa()
        if self.trocando or self.proximo or not alt or h["n"] < 2 or h["s"] < 1.6 * alt[1]:
            return
        self.trocando = True

        def abrir():
            try:
                c, e = self._abrir(alt[0], alt[2])
                with self.trava:
                    if self.fechado:
                        c.fechar()
                    else:
                        self.proximo = (c, alt[0], e, alt[2])
            except (OSError, RuntimeError, ValueError):
                pass
            finally:
                self.trocando = False

        threading.Thread(target=abrir, daemon=True).start()

    def texto(self, pcm, dica=""):
        wav = wav_de(pcm)
        c = os.environ.get("VOZ_STT_CMD")
        if c:
            return subprocess.run(["sh", "-c", c], input=wav, capture_output=True, timeout=60).stdout.decode(
                "utf-8", "replace").strip()
        with self.trava:
            if self.proximo:  # o seguinte já carregou: troca
                velho = self.canal
                self.canal, self.onde, self.escolha, self.info = self.proximo
                self.proximo = None
                self.desc = descrever(self.onde, self.escolha) + " (trocou: o anterior ficou lento)"
                self.avisar("transcrever: " + self.desc)
                if velho:
                    velho.fechar()
        if self.canal and self.canal.p.poll() is not None:  # o motor caiu (a rede, o ssh): o melhor que sobrar
            caiu = self.onde
            self.canal.fechar()
            self.canal = None
            self.preparar(pular=(caiu,))
        if not self.canal:
            raise RuntimeError(self.motivo or "sem reconhecimento")
        t0 = time.time()
        txt = self.canal.pedir({"op": "stt", "n": len(wav), "dica": dica[:600]}, wav)["texto"]
        h = registrar_tempo(self.onde, self.escolha, time.time() - t0, self.info)
        self._talvez_trocar(h)
        return txt

    def fechar(self):
        with self.trava:
            self.fechado = True
            for c in (self.canal, (self.proximo or (None,))[0]):
                if c:
                    c.fechar()
            self.canal, self.proximo = None, None


def destino(rotulo):
    voz = os.environ.get("VOZ") or shutil.which("voz")
    if not voz:
        return None
    try:
        return subprocess.run(["bash", voz, "--destino", rotulo], capture_output=True, text=True,
                              timeout=30).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None


# ---------------------------------------------------------------- falar
# ---------------------------------------------------------------- saídas de som
# A fala sai no mesmo aparelho do microfone escolhido (o headset ouve e fala); sem par, a saída de melhor nota (a de
# comunicação do Windows conta como headset), e só por último a padrão. VOZ_SAIDA (voz --saida) e a escolhida com a
# tecla s das opções vêm antes. No Windows, a padrão costuma ser o alto-falante ou a saída P2 (o headset é a de
# comunicação): a voz do Windows e o WSLg tocam lá; por isso o tt toca direto no aparelho escolhido.
MEMO_SAIDA = os.path.join(CACHE, "saida")


TIPOS = (r"(microphone array|microphone|microfone|mic|headphones|headset|speakers?|alto-falantes?|fones? de ouvido|"
         r"earphones?|auriculares|output|input|saída|entrada|array)")


def nucleo(nome):
    """O aparelho de um nome de entrada ou saída, sem o tipo: "Headphones (BlackShark V2 Pro PS 2.4)" →
    "blackshark v2 pro ps 2.4"; "MacBook Pro Microphone" e "MacBook Pro Speakers" → "macbook pro"."""
    n = re.sub(r" \((Windows|filtro|padrão.*)\)$", "", nome.strip())
    m = re.match(r"^([^(]*)\((.+)\)$", n)
    if m and re.fullmatch(TIPOS + r"( \d+)?", m.group(1).strip(), re.I):
        n = m.group(2)
    n = re.sub(r"\b" + TIPOS + r"\b", " ", n, flags=re.I)
    return " ".join(n.lower().split())


def escolher_saida(saidas, mic=""):
    """saidas: [(id, nome, padrao, comunicacao)] → o índice na lista da saída a usar (None: nenhuma)."""
    if not saidas:
        return None
    prefs = []
    try:
        with open(MEMO_SAIDA, encoding="utf-8") as f:
            prefs.append(f.read().strip().lower())
    except OSError:
        pass
    prefs += [x.strip().lower() for x in re.split(r"[,;]", os.environ.get("VOZ_SAIDA", "")) if x.strip()]
    for p in [x for x in prefs if x]:
        for i, s in enumerate(saidas):
            if p in s[1].lower():
                return i
    alvo = nucleo(mic) if mic else ""
    if len(alvo) >= 4:  # o mesmo aparelho (o nome de um começa pelo do outro: "comet lake pch-lp" e "comet lake")
        for i, s in enumerate(saidas):
            n = nucleo(s[1])
            if len(n) >= 4 and (n == alvo or n.startswith(alvo) or alvo.startswith(n)):
                return i

    def nota(i):
        s = saidas[i]
        v = nota_microfone(s[1].replace("Speakers", "alto-falante embutido"))
        v = -999 if v is None else v
        return (v + (150 if s[3] else 0), s[2], -i)
    return max(range(len(saidas)), key=nota)


def saidas_pulse():
    """[(nome, descrição, padrão, False)] das saídas do PulseAudio/PipeWire (sem as de porta "not available")."""
    if not shutil.which("pactl"):
        return []
    env = dict(os.environ, LC_ALL="C")
    try:
        txt = subprocess.run(["pactl", "list", "sinks"], capture_output=True, text=True, timeout=5, env=env).stdout
        padrao = subprocess.run(["pactl", "get-default-sink"], capture_output=True, text=True, timeout=5,
                                env=env).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return []
    out = []
    for bloco in re.split(r"\n(?=Sink #)", txt):
        nome = re.search(r"^\s*Name: (.+)$", bloco, re.M)
        desc = re.search(r"^\s*Description: (.+)$", bloco, re.M)
        if not nome or nome.group(1).strip() == "auto_null":
            continue
        porta = re.search(r"^\s*Active Port: (.+)$", bloco, re.M)
        if porta:
            linha = next((l for l in bloco.splitlines() if l.strip().startswith(porta.group(1).strip() + ":")), "")
            if re.search(r"not available\)\s*$", linha):
                continue
        out.append((nome.group(1).strip(), (desc.group(1) if desc else nome.group(1)).strip(), nome.group(1) == padrao, False))
    return out


def saidas_say():
    """macOS: [(id, nome, False, False)] dos aparelhos do `say -a ?`."""
    try:
        txt = subprocess.run(["say", "-a", "?"], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    out = []
    for l in txt.splitlines():
        m = re.match(r"^\s*(\d+)\s+(.+)$", l)
        if m:
            out.append((m.group(1), m.group(2).strip(), False, False))
    return out


def som_plim():
    """O aviso antes do que a voz fala sozinha (o retorno de uma sessão): dois tons curtos, um WAV em memória."""
    import struct
    import wave
    taxa, partes = 22050, []
    for freq, dur in ((880.0, 0.09), (1320.0, 0.14)):
        n = int(taxa * dur)
        for i in range(n):
            env = min(1.0, i / (taxa * 0.01), (n - i) / (taxa * 0.03))
            partes.append(struct.pack("<h", int(9000 * env * math.sin(2 * math.pi * freq * i / taxa))))
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(taxa)
        w.writeframes(b"".join(partes))
    return buf.getvalue()


def tocador(saida=None):
    w = shutil.which
    if eh_mac() and w("afplay"):
        return ["afplay"]
    ambiente_audio()
    if saida and w("paplay"):
        return ["paplay", "--device=" + saida]
    if saida and w("pw-play"):
        return ["pw-play", "--target", saida]
    for c in (["paplay"], ["pw-play"], ["aplay", "-q"], ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet"]):
        if w(c[0]):
            return c
    return None


def voz_say():
    """A voz pt-BR do say (macOS): Luciana, ou a primeira pt_BR da lista."""
    try:
        lista = subprocess.run(["say", "-v", "?"], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    nomes = [l.split("  ")[0].strip() for l in lista.splitlines() if "pt_BR" in l or "pt-BR" in l]
    for n in nomes:
        if n.startswith("Luciana"):
            return n
    return nomes[0] if nomes else None


class FalaWindows:
    """A voz do Windows num processo só (voz-windows.ps1 falar): ele lista as saídas, recebe "D n" (a saída), "F
    base64" (fala) e "P" (para) e responde "fim" a cada fala; abre uma vez (~1,5 s) e toca no aparelho escolhido."""

    def __init__(self, mic=""):
        ps, ps1 = os.environ.get("VOZ_POWERSHELL") or powershell(), ps1_windows()
        if not ps or not ps1:
            raise RuntimeError("sem o PowerShell do Windows")
        self.p = subprocess.Popen([ps, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                                   caminho_windows(ps1), "falar"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL)
        self.trava = threading.Lock()
        self.saidas = []
        fim = time.time() + 30
        while time.time() < fim:
            l = self._linha(fim - time.time())
            if l is None or l == "--":
                break
            partes = l.split("\t")
            if len(partes) >= 3 and partes[0].isdigit():
                nome = partes[3] if len(partes) > 3 and partes[3] else partes[2]
                self.saidas.append((partes[0], nome, "padrao" in partes[1], "comunicacao" in partes[1]))
        if self.p.poll() is not None:
            raise RuntimeError("a voz do Windows não abriu")
        self.atual = None
        i = escolher_saida(self.saidas, mic)
        self.usar(i)

    def _linha(self, espera):
        fd, buf, fim = self.p.stdout.fileno(), b"", time.time() + max(0.1, espera)
        while not buf.endswith(b"\n"):
            resta = fim - time.time()
            if resta <= 0:
                return None
            r, _, _ = select.select([fd], [], [], min(resta, 0.3))
            if r:
                b = os.read(fd, 1)
                if not b:
                    return None
                buf += b
        return buf.decode("utf-8", "replace").rstrip("\r\n")

    def usar(self, i):
        self.atual = i
        self._mandar("D %s" % (self.saidas[i][0] if i is not None else "-1"))

    @property
    def nome(self):
        return self.saidas[self.atual][1] if self.atual is not None else "a saída padrão do Windows"

    def _mandar(self, l):
        with self.trava:
            self.p.stdin.write((l + "\n").encode())
            self.p.stdin.flush()

    def falar(self, texto):
        return self._esperar("F " + base64.b64encode(texto.encode("utf-8")).decode())

    def tocar(self, wav):
        return self._esperar("T " + base64.b64encode(wav).decode())

    def _esperar(self, cmd):
        self._mandar(cmd)
        while True:
            l = self._linha(120)
            if l is None or l == "fim" or l.startswith("erro"):
                return l == "fim"

    def parar(self):
        try:
            self._mandar("P")
        except (OSError, ValueError):
            pass

    def fechar(self):
        try:
            self.p.stdin.close()
        except OSError:
            pass
        parar_processo(self.p)


def pedacos(texto, limite=220):
    """O texto em frases: a primeira sozinha (começa a tocar mais cedo), as outras juntas até `limite` letras."""
    frases = [f for f in re.split(r"(?<=[.!?])\s+", texto.strip()) if f]
    out, atual = [], ""
    for f in frases:
        if atual and (len(out) == 0 or len(atual) + 1 + len(f) > limite):
            out.append(atual)
            atual = f
        else:
            atual = (atual + " " + f).strip()
    if atual:
        out.append(atual)
    return out or [texto]


class Falador:
    """Diz o texto com o melhor motor daqui, no aparelho do microfone (`mic`); `parar()` corta a fala no meio."""

    def __init__(self, motor_canal=None, mic="", fornecedor=None):
        self.proc = None
        self.motor = motor_canal
        self.mic = mic
        self.win = None
        self.fornecedor = fornecedor  # () -> (canal, vozes) da máquina que transcreve, para gerar a voz neural lá
        self.local = None  # o motor deste computador para a voz neural (quando ele mesmo a gera)
        self.cancelar = threading.Event()
        self.voz = os.environ.get("VOZ_VOZ") or VOZ_PADRAO
        self.saidas, self.saida = [], None  # Linux (pactl) e macOS (say -a): a lista e o índice escolhido
        self.trava = threading.Lock()
        self.qual, self.det = self._escolher()
        if not eh_wsl() and self.qual not in ("nenhum", "cmd", "termux"):
            self.saidas = saidas_say() if eh_mac() else saidas_pulse()
            self.saida = escolher_saida(self.saidas, mic)

    @property
    def onde(self):
        if self.win:
            return self.win.nome
        if self.saida is not None and self.saidas:
            return self.saidas[self.saida][1]
        return "a saída padrão"

    def proxima_saida(self):
        """A saída seguinte (a tecla s das opções); lembra a escolha. O nome, ou None."""
        lista = self.win.saidas if self.win else self.saidas
        if not lista:
            return None
        atual = self.win.atual if self.win else self.saida
        i = 0 if atual is None else (atual + 1) % len(lista)
        if self.win:
            self.win.usar(i)
        else:
            self.saida = i
        try:
            os.makedirs(CACHE, exist_ok=True)
            with open(MEMO_SAIDA, "w", encoding="utf-8") as f:
                f.write(lista[i][1].lower() + "\n")
        except OSError:
            pass
        return lista[i][1]

    def aquecer(self):
        """Carrega a voz em segundo plano (o Piper, ou o processo da voz do Windows): a primeira fala não espera."""
        if self.qual == "piper":
            threading.Thread(target=lambda: self._piper_canal().pedir({"op": "carregar", "tts": True}, tempo=120),
                             daemon=True).start()
        elif self.qual == "windows":
            threading.Thread(target=self._abrir_win, daemon=True).start()

    def _abrir_win(self):
        with self.trava:
            if self.win is None or self.win.p.poll() is not None:
                try:
                    self.win = FalaWindows(self.mic)
                except (OSError, RuntimeError, ValueError):
                    self.win = None
            return self.win

    # -- a voz neural: onde gerar (aqui, se este computador tem o motor dela; senão a máquina que transcreve)
    def _fonte(self, voz):
        py = python_com("piper") or python_com("edge_tts")
        if voz in vozes_de(py):
            with self.trava:
                if self.local is None or self.local.p.poll() is not None:
                    self.local = Canal([py, EU, "servidor"], "voz")
                return self.local
        if self.fornecedor:
            canal, vozes = self.fornecedor()
            if canal is not None and voz in (vozes or []):
                return canal
        return None

    def vozes(self):
        """As vozes que dá para usar agora: a do sistema e as neurais que aqui ou a máquina que transcreve geram."""
        tem = set(vozes_de(python_com("piper") or python_com("edge_tts")))
        if self.fornecedor:
            tem |= set(self.fornecedor()[1] or [])
        return ["sistema"] + [v for v, _, _ in VOZES_NEURAIS if v in tem]

    def neural(self):
        return self.voz != "sistema" and self.qual not in ("nenhum", "cmd", "termux") and self._tocador_wav()

    def _tocador_wav(self):
        return eh_wsl() and self.qual == "windows" or bool(tocador())

    def _sintetizar(self, texto):
        c = self._fonte(self.voz)
        if c is None:
            raise RuntimeError("nenhuma máquina gera a voz " + rotulo_voz(self.voz))
        return c.pedir({"op": "tts_wav", "texto": texto, "voz": self.voz}, tempo=60, binario=True)[1]

    def _tocar_wav(self, wav):
        if eh_wsl() and self.qual == "windows":
            win = self._abrir_win()
            return bool(win) and win.tocar(wav)
        arq = os.path.join(tempfile.gettempdir(), "tt-voz-fala-%d.wav" % os.getpid())
        with open(arq, "wb") as f:
            f.write(wav)
        alvo = self.saidas[self.saida][0] if self.saida is not None and self.saidas and not eh_mac() else None
        self.proc = subprocess.Popen(tocador(alvo) + [arq], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.proc.wait()
        self.proc = None
        return True

    def plim(self):
        """O som curto antes do retorno de uma sessão (VOZ_PLIM=0 desliga). Sem tocador, nada."""
        if self.qual == "nenhum" or os.environ.get("VOZ_PLIM") == "0":
            return
        try:
            if not (eh_wsl() and self.qual == "windows") and tocador() is None:
                return
            self._tocar_wav(som_plim())
        except (OSError, RuntimeError, ValueError, TypeError):
            pass

    def _falar_neural(self, texto):
        """Frase a frase: a seguinte é gerada enquanto a atual toca. False se a primeira não saiu (vale a do sistema)."""
        self.cancelar.clear()
        fila = queue.Queue(maxsize=2)

        def gerar():
            for p in pedacos(texto):
                if self.cancelar.is_set():
                    break
                try:
                    fila.put(self._sintetizar(p))
                except (OSError, RuntimeError, ValueError) as ex:
                    fila.put(ex)
                    break
            fila.put(None)
        threading.Thread(target=gerar, daemon=True).start()
        primeira = True
        while True:
            w = fila.get()
            if w is None:
                return True
            if isinstance(w, Exception):
                return not primeira
            primeira = False
            if not self.cancelar.is_set():
                self._tocar_wav(w)

    def _escolher(self):
        pedido = os.environ.get("VOZ_FALA", "auto") or "auto"
        if os.environ.get("VOZ_TTS_CMD"):
            return "cmd", "comando de teste"
        w = shutil.which
        ordem = [pedido] if pedido != "auto" else ["termux", "piper", "say", "windows", "spd", "espeak"]
        for q in ordem:
            if q == "nenhum":
                return "nenhum", "sem voz (só texto)"
            if q == "termux" and eh_termux() and w("termux-tts-speak"):
                return q, "termux-tts-speak"
            if q == "piper" and self.voz != "sistema" and os.path.exists(arquivo_voz_piper()) and tocador():
                py = python_com("piper")
                if py:
                    return q, "Piper %s" % VOZ_PIPER
            if q == "say" and eh_mac() and w("say"):
                v = voz_say()
                return q, "say %s" % (v or "(voz padrão)")
            if q == "windows" and eh_wsl() and (os.environ.get("VOZ_POWERSHELL") or powershell()) and ps1_windows():
                return q, "a voz do Windows"
            if q == "spd" and w("spd-say"):
                return q, "spd-say pt-BR"
            if q == "espeak" and (w("espeak-ng") or w("espeak")):
                return q, "espeak pt-br"
        return "nenhum", "sem motor de voz (só texto)"

    def _piper_canal(self):
        with self.trava:
            if self.motor is None or self.motor.p.poll() is not None:
                self.motor = Canal([python_com("piper"), EU, "servidor"], "piper")
            return self.motor

    def comando(self, texto):
        """O processo que diz o texto (ou None: já foi dito, ou não há voz)."""
        q = self.qual
        w = shutil.which
        alvo = self.saidas[self.saida][0] if self.saida is not None and self.saidas else None
        if q == "cmd":
            return subprocess.Popen(["sh", "-c", os.environ["VOZ_TTS_CMD"]], stdin=subprocess.PIPE), texto
        if q == "piper":
            saida = os.path.join(tempfile.gettempdir(), "tt-voz-fala-%d.wav" % os.getpid())
            self._piper_canal().pedir({"op": "tts", "texto": texto, "saida": saida}, tempo=60)
            return subprocess.Popen(tocador(alvo) + [saida], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL), None
        if q == "say":
            v = voz_say()
            return subprocess.Popen(["say"] + (["-v", v] if v else []) + (["-a", alvo] if alvo else []) + [texto]), None
        if q == "spd":
            return subprocess.Popen(["spd-say", "-w", "-l", "pt-BR", "-r", "15", texto],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL), None
        if q == "espeak":
            return subprocess.Popen([w("espeak-ng") or w("espeak"), "-v", "pt-br", "-s", "175", texto],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL), None
        if q == "termux":
            return subprocess.Popen(["termux-tts-speak", "-l", "pt-BR", texto]), None
        return None, None

    def falar(self, texto):
        if self.neural():
            try:
                if self._falar_neural(texto):
                    return True
            except (OSError, RuntimeError, ValueError):
                pass
            if self.cancelar.is_set():
                return True
        if self.qual == "windows":
            win = self._abrir_win()
            if win is None:
                return False
            try:
                return win.falar(texto)
            except (OSError, ValueError):
                return False
        try:
            p, entrada = self.comando(texto)
        except (OSError, RuntimeError, ValueError):
            return False
        if p is None:
            return False
        self.proc = p
        try:
            if entrada is not None:
                p.stdin.write(entrada.encode())
                p.stdin.close()
            p.wait()
        except (OSError, ValueError):
            pass
        self.proc = None
        return True

    def parar(self):
        self.cancelar.set()
        if self.win:
            self.win.parar()
        p = self.proc
        if p is not None:
            parar_processo(p)
            if self.qual == "spd" and shutil.which("spd-say"):
                subprocess.run(["spd-say", "-C"], capture_output=True)

    def fechar(self):
        if self.win:
            self.win.fechar()
        if self.motor:
            self.motor.fechar()
        if self.local:
            self.local.fechar()


# ---------------------------------------------------------------- a janela da conversa
COR = {"voce": "\033[1;36m", "tt": "\033[1;32m", "nota": "\033[2;37m", "erro": "\033[1;31m", "fim": "\033[0m"}
NIVEL = "▁▂▃▄▅▆▇█"


class Tela:
    """A conversa e uma linha de estado embaixo. Aberta (abrir()), desenha numa tela própria (a alternativa do terminal)
    com o histórico guardado: a roda do mouse, as setas, PgUp/PgDn e Home/End rolam (o Teclado chama rolar()); rolada
    para cima, a vista não pula quando chega texto (o estado diz quantas linhas novas há embaixo). Sem abrir() (o teste
    do microfone), escreve rolando, como um terminal."""

    def __init__(self):
        self.trava = threading.RLock()  # o redesenho do SIGWINCH roda na mesma thread de quem escreve
        self.estado = ""
        self.largura, self.altura = 70, 24
        self.itens = []  # (quem, texto) de tudo o que foi dito
        self.linhas = []  # os itens quebrados na largura de agora, com as cores
        self.desloc = 0  # linhas roladas para cima (0 = acompanhando o fim)
        self.novas = 0
        self.cheia = False

    def medir(self):
        try:
            t = os.get_terminal_size(sys.stdout.fileno())
            self.largura, self.altura = max(30, t.columns), max(5, t.lines)
        except OSError:
            self.largura, self.altura = 70, 24

    def _quebrar(self, quem, texto):
        rot = {"voce": "você: ", "tt": "tt: ", "nota": "", "erro": "⚠ "}.get(quem, "")
        corpo = textwrap.wrap(texto, max(10, self.largura - 1 - len(rot))) or [""]
        return ["%s%s%s%s" % (COR.get(quem, ""), rot if i == 0 else " " * len(rot), l, COR["fim"])
                for i, l in enumerate(corpo)]

    def abrir(self):
        """Tela própria com histórico e a roda do mouse (SGR)."""
        with self.trava:
            self.medir()
            self.cheia = True
            sys.stdout.write("\033[?1049h\033[?1000h\033[?1006h\033[?25l\033[2J")
            self._desenhar()
        try:
            signal.signal(signal.SIGWINCH, lambda *a: self._redimensionar())
        except (ValueError, OSError, AttributeError):
            pass  # fora da thread principal ou sem SIGWINCH

    def fechar(self):
        with self.trava:
            if self.cheia:
                self.cheia = False
                sys.stdout.write("\033[?1006l\033[?1000l\033[?25h\033[?1049l")
                sys.stdout.flush()

    def _redimensionar(self):
        with self.trava:
            self.medir()
            self.linhas = [l for q, t in self.itens for l in self._quebrar(q, t)]
            self.desloc = min(self.desloc, self._max_desloc())
            self._desenhar()

    def _max_desloc(self):
        return max(0, len(self.linhas) - (self.altura - 1))

    def _desenhar(self):
        if not self.cheia:
            return
        h = self.altura - 1
        fim = len(self.linhas) - self.desloc
        vis = self.linhas[max(0, fim - h):fim]
        out = ["\033[?2026h"]
        for i in range(h):
            out.append("\033[%d;1H\033[2K%s" % (i + 1, vis[i] if i < len(vis) else ""))
        out.append("\033[%d;1H\033[2K%s\033[?2026l" % (self.altura, self._linha_estado()))
        sys.stdout.write("".join(out))
        sys.stdout.flush()

    def _linha_estado(self):
        if not self.desloc:
            return self.estado[: max(10, self.largura - 1)]
        marca = " ↓ %d nova%s · End volta" % (self.novas, "" if self.novas == 1 else "s") if self.novas else " ↑ rolada · End volta"
        return "%s\033[7m%s\033[0m" % (self.estado[: max(0, self.largura - 1 - len(marca))], marca)

    def rolar(self, n):
        """n linhas para cima (negativo: para baixo); "inicio"/"fim" vão às pontas."""
        with self.trava:
            if n == "inicio":
                self.desloc = self._max_desloc()
            elif n == "fim":
                self.desloc = 0
            else:
                self.desloc = min(self._max_desloc(), max(0, self.desloc + n))
            if not self.desloc:
                self.novas = 0
            self._desenhar()

    def pagina(self):
        return max(1, self.altura - 2)

    def linha(self, quem, texto):
        with self.trava:
            if not self.cheia:
                self.medir()
            novas = self._quebrar(quem, texto)
            self.itens.append((quem, texto))
            self.linhas.extend(novas)
            if len(self.itens) > 2000:  # a conversa de um dia inteiro cabe; o resto vai embora
                self.itens = self.itens[-1500:]
                self.linhas = [l for q, t in self.itens for l in self._quebrar(q, t)]
            if self.cheia:
                if self.desloc:
                    self.desloc = min(self._max_desloc(), self.desloc + len(novas))  # a vista fica onde estava
                    self.novas += len(novas)
                self._desenhar()
                return
            sys.stdout.write("\r\033[2K")
            for l in novas:
                sys.stdout.write(l + "\n")
            sys.stdout.write(self.estado)
            sys.stdout.flush()

    def status(self, texto):
        with self.trava:
            self.estado = texto[: max(10, self.largura - 1)]
            if self.cheia:
                sys.stdout.write("\033[%d;1H\033[2K%s" % (self.altura, self._linha_estado()))
            else:
                sys.stdout.write("\r\033[2K" + self.estado)
            sys.stdout.flush()


# as sequências que o Teclado entende: a roda do mouse (SGR), setas, PgUp/PgDn, Home/End; o resto de um CSI é descartado
SEQ_MOUSE = re.compile(rb"\x1b\[<(\d+);\d+;\d+[Mm]")
SEQ_TECLA = re.compile(rb"\x1b(?:\[(\d+)~|\[([ABCDHF])|O([ABCDHF]))")
SEQ_CSI = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]")
SEQ_INCOMPLETA = re.compile(rb"\x1b(\[[0-?<]*[ -/]*|O)?$")


class Teclado:
    """Lê teclas sem esperar Enter (modo cbreak) numa thread; Esc sozinho vira 'esc'. A rolagem (roda do mouse, setas,
    PgUp/PgDn, Home/End) vai direto à tela (tela.rolar), em qualquer momento da conversa."""

    def __init__(self, tela=None):
        self.fila = queue.Queue()
        self.fd = sys.stdin.fileno()
        self.antes = None
        self.vivo = True
        self.tela = tela

    def __enter__(self):
        import termios
        import tty
        try:
            self.antes = termios.tcgetattr(self.fd)
            tty.setcbreak(self.fd)
        except termios.error:
            self.antes = None
        sys.stdout.write("\033[?25l")
        threading.Thread(target=self._ler, daemon=True).start()
        return self

    def __exit__(self, *a):
        import termios
        self.vivo = False
        sys.stdout.write("\033[?25h\n")
        sys.stdout.flush()
        if self.antes is not None:
            termios.tcsetattr(self.fd, termios.TCSADRAIN, self.antes)

    def _rolar(self, n):
        if self.tela is not None:
            self.tela.rolar(n)

    def _ler(self):
        import codecs
        dec = codecs.getincrementaldecoder("utf-8")("replace")
        buf = b""
        espera = float(os.environ.get("TT_ESC_SEQ", "0.3"))
        while self.vivo:
            r, _, _ = select.select([self.fd], [], [], 0.2 if not buf else espera)
            if r:
                b = os.read(self.fd, 256)
                if not b:
                    self.fila.put("esc")
                    return
                buf += b
            elif buf:  # nada mais chegou: um Esc sozinho (ou o pedaço de uma sequência que não veio inteira)
                if buf == b"\x1b":
                    self.fila.put("esc")
                buf = b""
                continue
            else:
                continue
            buf = self._consumir(buf, dec)

    def _consumir(self, buf, dec):
        """Tira de buf o que já dá para entender; devolve o resto (uma sequência que ainda não chegou inteira)."""
        while buf:
            i = buf.find(b"\x1b")
            if i != 0:
                texto = buf if i < 0 else buf[:i]
                for ch in dec.decode(texto):
                    self.fila.put(ch)
                buf = b"" if i < 0 else buf[i:]
                continue
            m = SEQ_MOUSE.match(buf)
            if m:
                bt = int(m.group(1))
                if bt in (64, 65):
                    self._rolar(3 if bt == 64 else -3)
                buf = buf[m.end():]
                continue
            m = SEQ_TECLA.match(buf)
            if m:
                cod = m.group(1)
                letra = (m.group(2) or m.group(3) or b"").decode()
                if cod in (b"5", b"6"):
                    self._rolar((1 if cod == b"5" else -1) * (self.tela.pagina() if self.tela else 10))
                elif cod in (b"1", b"7") or letra == "H":
                    self._rolar("inicio")
                elif cod in (b"4", b"8") or letra == "F":
                    self._rolar("fim")
                elif letra in ("A", "B"):
                    self._rolar(1 if letra == "A" else -1)
                buf = buf[m.end():]
                continue
            m = SEQ_CSI.match(buf)
            if m:
                buf = buf[m.end():]
                continue
            if SEQ_INCOMPLETA.match(buf):
                return buf  # espera o resto
            # Esc seguido de outra coisa (Alt+tecla): o Esc, e a tecla segue
            self.fila.put("esc")
            buf = buf[1:]
        return buf

    def tecla(self, espera=0.0):
        try:
            return self.fila.get(timeout=espera) if espera else self.fila.get_nowait()
        except queue.Empty:
            return None


# ---------------------------------------------------------------- opções (tecla c da janela e voz --opcoes)
CF_VOZ = os.path.join(CASA, ".config", "tt-voz")
ESTADO = os.path.join(CASA, ".local", "state", "tt-voz")
CEREBROS = [("1", "haiku", "Haiku", "o mais rápido; erra mais nas frases ambíguas"),
            ("2", "sonnet", "Sonnet", "entende melhor o ambíguo, ~1 s a mais (o padrão)"),
            ("3", "opus", "Opus", "o mais capaz; mais lento e gasta mais cota")]
MODELOS_STT = [("a", "", "automático", "o de menor custo em cada máquina (o padrão)"),
               ("b", "tiny", "tiny", ""), ("c", "base", "base", ""), ("d", "small", "small", ""),
               ("e", "medium", "medium", ""), ("f", "large-v3-turbo", "turbo", "")]


def conf(nome):
    try:
        with open(os.path.join(CF_VOZ, nome), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def gravar_conf(nome, valor):
    arq = os.path.join(CF_VOZ, nome)
    try:
        if valor:
            os.makedirs(CF_VOZ, exist_ok=True)
            with open(arq, "w", encoding="utf-8") as f:
                f.write(valor + "\n")
        elif os.path.exists(arq):
            os.remove(arq)
    except OSError:
        pass


def cerebro_atual():
    return os.environ.get("VOZ_CEREBRO_MODELO") or conf("cerebro-modelo") or "sonnet"


def medidas_texto():
    """As medições desta máquina, numa linha ("small GPU 0,9 s 18% · base CPU 0,8 s 15%")."""
    med = ler_json(MEDICOES) or {}
    rs = sorted(med.get("resultados", []), key=custo)
    return " · ".join(("%s %s %.1f s %d%%" % (r["modelo"].replace("large-v3-", ""), "CPU" if r["dispositivo"] == "cpu" else "GPU",
                                              r["tempo"], round(r["erro"] * 100))).replace(".", ",") for r in rs)


def escolher_maquina(tela, teclado):
    """Submenu numérico: automático ou uma máquina fixa; Esc preserva a escolha."""
    maquinas = list(dict.fromkeys(["local"] + os.environ.get("VOZ_MAQUINAS", "").split()
                                 + os.environ.get("VOZ_TRANSCREVER", "").split()))
    tela.linha("nota", "máquina de transcrição: 0 automática")
    for i, lugar in enumerate(maquinas, 1):
        tela.linha("nota", "%d %s" % (i, "esta máquina (local)" if lugar == "local" else lugar))
    numero = ""
    while True:
        tela.status("máquina: %s · número e Enter escolhe · Esc cancela" % numero)
        k = teclado.tecla(0.3)
        if k in ("esc", "q"):
            return False
        if k in ("\r", "\n"):
            if not numero or int(numero) > len(maquinas):
                tela.linha("erro", "Escolha um número da lista.")
                numero = ""
                continue
            lugar = maquinas[int(numero) - 1] if int(numero) else ""
            gravar_conf("transcrever", lugar)
            os.environ["VOZ_TRANSCREVER"] = lugar or " ".join(maquinas)
            # Uma escolha explícita deve tentar novamente mesmo após uma falha recente de rede.
            sondas = ler_json(SONDAS, {}) or {}
            sondas.pop(lugar, None)
            gravar_json(SONDAS, sondas)
            tela.linha("nota", "✓ máquina de transcrição: %s (aplicada ao voltar à conversa)" % (lugar or "automática"))
            return True
        if k in ("\x7f", "\b", "backspace"):
            numero = numero[:-1]
        elif k and k.isascii() and k.isdigit() and len(numero) < 4:
            numero += k


def painel_opcoes(tela, teclado, gravador=None, falador=None, transcritor=None):
    """O painel: 1-3 o cérebro, a-f o modelo da transcrição, n o microfone, s a saída de som; Enter ou Esc volta.
    Grava a escolha em ~/.config/tt-voz (como voz --cerebro-modelo e voz --modelo). Devolve True se a transcrição mudou."""
    cer, mod = cerebro_atual(), os.environ.get("VOZ_MODELO", "")
    tela.linha("nota", "── opções do 🎤 (ficam guardadas) ──")
    tela.linha("nota", "cérebro, que entende a frase:  " + "   ".join(
        "%s %s%s" % (k, rot, " ✓" if m == cer else "") for k, m, rot, _ in CEREBROS))
    tela.linha("nota", "transcrição, da voz ao texto:  " + "   ".join(
        "%s %s%s" % (k, rot, " ✓" if m == mod else "") for k, m, rot, _ in MODELOS_STT))
    tela.linha("nota", "máquina de transcrição: %s   (l: escolher máquina ou automática)" % (conf("transcrever") or "automática"))
    med = medidas_texto()
    if med:
        tela.linha("nota", "   medido nesta máquina: " + med)
    if transcritor is not None and transcritor.desc:
        tela.linha("nota", "   agora: " + transcritor.desc)
    if gravador is not None and gravador.nome:
        tela.linha("nota", "microfone: %s   (n: o seguinte)" % gravador.nome)
    lim = limiar_minimo()
    tela.linha("nota", "sensibilidade do microfone: %s (a fala conta a partir do nível %d)   (g: a seguinte)"
               % (rotulo_limiar(lim), lim))
    if falador is not None and falador.qual not in ("nenhum", "cmd"):
        tela.linha("nota", "saída de som: %s   (s: a seguinte)" % falador.onde)
    if falador is not None:
        tela.linha("nota", "voz: %s   (v: a seguinte, com um exemplo; disponíveis: %s)" % (
            rotulo_voz(falador.voz), ", ".join(rotulo_voz(v) for v in falador.vozes())))
    mudou = False
    while True:
        tela.status("opções: 1-3 cérebro · a-f modelo · l máquina · n microfone · g sensibilidade · s saída · v voz · Enter")
        k = teclado.tecla(0.3)
        if k is None:
            continue
        if k in ("esc", "\r", "\n", "q", "c"):
            return mudou
        if k == "l":
            mudou = escolher_maquina(tela, teclado) or mudou
            continue
        esc = next((x for x in CEREBROS if x[0] == k), None)
        if esc:
            gravar_conf("cerebro-modelo", "" if esc[1] == "sonnet" else esc[1])
            os.environ.pop("VOZ_CEREBRO_MODELO", None)
            tela.linha("nota", "✓ cérebro: %s (%s)" % (esc[2], esc[3]))
            continue
        esc = next((x for x in MODELOS_STT if x[0] == k), None)
        if esc:
            gravar_conf("modelo", esc[1])
            if esc[1]:
                os.environ["VOZ_MODELO"] = esc[1]
            else:
                os.environ.pop("VOZ_MODELO", None)
            baixado = not esc[1] or esc[1] in modelos_em_cache()
            tela.linha("nota", "✓ transcrição: %s%s" % (esc[2], "" if baixado else
                                                        " (não está baixado aqui: a 1ª vez baixa %d MB)" % PERFIL[esc[1]][1]))
            mudou = mudou or esc[1] != mod
            continue
        if k == "n" and gravador is not None:
            tela.status("… abrindo o próximo microfone")
            novo = gravador.proximo()
            tela.linha("nota", "✓ microfone: %s" % novo if novo else "não há outro microfone que funcione")
            if novo and falador is not None:
                falador.mic = novo
        elif k == "v" and falador is not None:
            lista = falador.vozes()
            if len(lista) < 2:
                tela.linha("nota", "nenhuma voz neural disponível agora (a máquina que transcreve ainda não respondeu, ou "
                                   "nenhuma tem o Piper ou o edge-tts): a voz fica %s" % rotulo_voz(falador.voz))
                continue
            nova = lista[(lista.index(falador.voz) + 1) % len(lista)] if falador.voz in lista else lista[0]
            falador.voz = nova
            gravar_conf("voz", "" if nova == VOZ_PADRAO else nova)
            os.environ["VOZ_VOZ"] = nova
            tela.linha("nota", "✓ voz: %s%s" % (rotulo_voz(nova), "  (o texto falado vai ao serviço da Microsoft)"
                                                if nova.startswith("edge:") else ""))
            tela.status("🔊 exemplo da voz…")
            falador.falar("Esta é a voz %s do tt. Diga o que precisa." % rotulo_voz(nova).split(" (")[0])
        elif k == "g":
            nomes = [n for n, _ in SENSIBILIDADES]
            atual = rotulo_limiar(limiar_minimo())
            nome, valor = SENSIBILIDADES[(nomes.index(atual) + 1) % len(nomes) if atual in nomes else 0]
            gravar_conf("limiar", "" if nome == SENSIBILIDADES[0][0] else nome)
            os.environ["VOZ_LIMIAR"] = nome
            tela.linha("nota", "✓ sensibilidade: %s (a fala conta a partir do nível %d)" % (nome, valor))
        elif k == "s" and falador is not None:
            novo = falador.proxima_saida()
            tela.linha("nota", "✓ saída de som: %s" % novo if novo else "não há outra saída de som")


class CerebroVivo:
    """O Claude do cérebro aberto a conversa toda (`voz --cerebro-vivo`: stream-json, regras no system prompt), servido
    aos `voz --turno` por um socket Unix (VOZ_CEREBRO_SOCK): cada volta ~1,5 s, contra ~7 s de um `claude -p` que parte do
    zero. Enquanto abre (a escolha da conta pode levar dezenas de segundos), se cair ou errar, o socket responde vazio e o
    voz usa o caminho de sempre (ia-rot -p). Depois de VOLTAS voltas recomeça (o contexto não cresce sem fim)."""
    VOLTAS = 20

    def __init__(self, voz):
        self.voz = voz
        self.proc = None
        self.fila = None
        self.voltas = 0
        self.trava = threading.Lock()
        self.pronto = threading.Event()
        self.abrindo = False
        self.fechado = False
        self.pasta = tempfile.mkdtemp(prefix="tt-voz-")
        self.sock = os.path.join(self.pasta, "cerebro.sock")
        self.srv = None

    def iniciar(self):
        import socket
        try:
            self.srv = socket.socket(socket.AF_UNIX)
            self.srv.bind(self.sock)
            self.srv.listen(4)
        except OSError:
            return
        os.environ["VOZ_CEREBRO_SOCK"] = self.sock
        threading.Thread(target=self._servir, daemon=True).start()
        self._abrir_fundo()

    def _abrir_fundo(self):
        if self.abrindo or self.fechado:
            return
        self.abrindo = True
        threading.Thread(target=self._abrir, daemon=True).start()

    def _abrir(self):
        try:
            p = subprocess.Popen(["bash", self.voz, "--cerebro-vivo"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, start_new_session=True)
            if self.fechado:
                parar_processo(p)
                return
            fila = queue.Queue()
            threading.Thread(target=self._ler, args=(p, fila), daemon=True).start()
            with self.trava:
                self.proc, self.fila, self.voltas = p, fila, 0
                ok = self._pedir('Início da conversa. Responda só: {"fala": "", "acoes": []}',
                                 float(os.environ.get("VOZ_CEREBRO_ABRIR", "120"))) is not None
            if ok:
                self.pronto.set()
        except OSError:
            pass
        finally:
            self.abrindo = False

    @staticmethod
    def _ler(p, fila):
        for linha in p.stdout:
            try:
                d = json.loads(linha)
            except ValueError:
                continue
            if d.get("type") == "result":
                fila.put(d)
        fila.put(None)

    def _parar(self):
        self.pronto.clear()
        p, self.proc = self.proc, None
        if p:
            try:
                p.stdin.close()
            except OSError:
                pass
            try:
                os.killpg(p.pid, signal.SIGTERM)  # o grupo todo: o ia-rot que ainda escolhe a conta, ou o Claude
            except OSError:
                pass
            parar_processo(p)

    def _pedir(self, texto, tempo):
        """Uma volta (com a trava): o texto da resposta, ou None (e o processo é descartado)."""
        p = self.proc
        if p is None or p.poll() is not None:
            return None
        try:
            while not self.fila.empty():
                self.fila.get_nowait()
            msg = {"type": "user", "message": {"role": "user", "content": texto}}
            p.stdin.write((json.dumps(msg, ensure_ascii=False) + "\n").encode("utf-8"))
            p.stdin.flush()
            d = self.fila.get(timeout=tempo)
        except (OSError, ValueError, queue.Empty):
            d = None
        if not d or d.get("is_error") or not isinstance(d.get("result"), str):
            self._parar()
            return None
        self.voltas += 1
        return d["result"]

    def pedir(self, texto, tempo=45.0):
        if not self.pronto.is_set():
            return None
        with self.trava:
            r = self._pedir(texto, tempo)
            if r is None or self.voltas >= self.VOLTAS:
                self._parar()
        if not self.pronto.is_set():
            self._abrir_fundo()  # a próxima volta já pega um novo (até lá, o caminho de sempre)
        return r

    def _servir(self):
        while not self.fechado:
            try:
                c, _ = self.srv.accept()
            except OSError:
                return
            threading.Thread(target=self._atender, args=(c,), daemon=True).start()

    def _atender(self, c):
        try:
            c.settimeout(60)
            dados = b""
            while True:
                b = c.recv(65536)
                if not b:
                    break
                dados += b
            r = self.pedir(dados.decode("utf-8", "replace"), float(os.environ.get("VOZ_CEREBRO_TEMPO", "45")))
            if r:
                c.sendall(r.encode("utf-8"))
        except OSError:
            pass
        finally:
            c.close()

    def fechar(self):
        self.fechado = True
        os.environ.pop("VOZ_CEREBRO_SOCK", None)
        try:
            self.srv and self.srv.close()
        except OSError:
            pass
        self._parar()  # sem a trava: ela pode estar presa na abertura (a escolha da conta leva até 2 min)
        shutil.rmtree(self.pasta, ignore_errors=True)


class Conversa:
    def __init__(self, digitar=False):
        self.tela = Tela()
        self.voz = os.environ.get("VOZ") or shutil.which("voz") or os.path.join(os.path.dirname(EU), "voz")
        self.digitar_sempre = digitar
        self.mudo = os.environ.get("VOZ_FALA") == "nenhum"
        self.sair = False
        self.parar_gravacao = threading.Event()
        self.gravador = Gravador()
        self.transcritor = Transcritor(avisar=self._aviso_transcritor)
        self.falador = None
        self.dica = ""
        self.pendente_pronto = threading.Event()
        self.som_pronto = threading.Event()
        self.cerebro = None
        self.conferindo = False
        self.avisou_fraco = False
        self.retorno_estado = ""
        self.retomando = None

    def _aviso_transcritor(self, t):
        if t.startswith("transcrever: "):  # troca no meio da conversa: fica na conversa
            self.tela.linha("nota", t)
        else:
            self.tela.status("… " + t)

    # -- as respostas do voz chegam pelo fd VOZ_TELA_FD: "tipo<TAB>texto" (fala, aviso, fim)
    def turno(self, frase, teclado, args=None):
        r, w = os.pipe()
        env = dict(os.environ, VOZ_TELA_FD=str(w))
        try:
            p = subprocess.Popen(["bash", self.voz] + (args or ["--turno", frase]), pass_fds=(w,), env=env,
                                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError as e:
            os.close(r)
            os.close(w)
            self.tela.linha("erro", "não consegui rodar o voz: %s" % e)
            return False
        os.close(w)
        self.tela.status("… pensando  ·  Esc: sair")
        fim = False
        buf = b""
        aberto = True
        while aberto:
            k = teclado.tecla()
            if k == "esc" or k == "q":
                parar_processo(p)
                self.sair = True
                break
            pr, _, _ = select.select([r], [], [], 0.1)
            if not pr:
                if p.poll() is not None:  # acabou (um filho em segundo plano pode manter o pipe aberto)
                    break
                continue
            b = os.read(r, 4096)
            if not b:
                aberto = False
            buf += b
            while b"\n" in buf:
                l, buf = buf.split(b"\n", 1)
                tipo, _, texto = l.decode("utf-8", "replace").partition("\t")
                if not texto.strip():
                    continue
                self.tela.linha("tt", texto)
                if tipo == "fim":
                    fim = True
                if not self.dizer(texto, teclado):
                    parar_processo(p)
                    aberto = False
                    break
                self.tela.status("… pensando  ·  Esc: sair")
        os.close(r)
        try:
            p.wait(timeout=5)
        except subprocess.SubprocessError:
            parar_processo(p)
        return fim

    def dizer(self, texto, teclado):
        """Fala o texto; Espaço pula a fala, Esc sai. False = sair."""
        if self.mudo or self.falador is None or self.falador.qual == "nenhum":
            return not self.sair
        t = threading.Thread(target=self.falador.falar, args=(texto,), daemon=True)
        t.start()
        self.tela.status("🔊 falando  ·  Espaço: pular  ·  m: mudo  ·  Esc: sair")
        while t.is_alive():
            k = teclado.tecla(0.1)
            if k == " ":
                self.falador.parar()
            elif k == "m":
                self.mudo = True
                self.falador.parar()
            elif k in ("esc", "q"):
                self.falador.parar()
                self.sair = True
                return False
        return True

    def digitar(self, teclado):
        """Linha digitada (Enter manda, Esc volta a ouvir)."""
        txt = ""
        ultima = time.time()
        while True:
            self.tela.status("você> " + txt + "▏  (Enter manda · Esc " + ("sai" if self.digitar_sempre else "volta a ouvir") + ")")
            k = teclado.tecla(0.2)
            if k is None:
                if not txt and self.som_pronto.is_set():
                    return "\0n"  # o reconhecimento acabou de ser instalado: volta ao laço, que passa a ouvir
                if not txt and self.pendente_pronto.is_set():
                    return "\0p"  # a voz tem algo a falar sozinha (e você não está digitando)
                if time.time() - ultima > 6:
                    ultima = time.time()
                    self._talvez_conferir()
                continue
            if k == "esc":
                return None
            if k in ("\r", "\n"):
                return txt.strip()
            if k in ("\x7f", "\b"):
                txt = txt[:-1]
            elif k == "\x15":
                txt = ""
            elif k.isprintable():
                txt += k

    def ouvir(self, teclado):
        """Uma frase falada → texto. None = sair; '' = silêncio; '\0t' = quer digitar."""
        if self.retomando is not None:  # o microfone ainda reabrindo (depois do modo retorno)
            self.retomando.join(10)
            self.retomando = None
        self.parar_gravacao.clear()
        res = {}
        estado = {"n": 0.0, "f": False}

        def nivel(v, falando):
            estado["n"], estado["f"] = v, falando

        def gravar():
            res["pcm"], res["motivo"] = self.gravador.frase(nivel=nivel, parar=self.parar_gravacao)

        t = threading.Thread(target=gravar, daemon=True)
        t.start()
        ultima = time.time()
        while t.is_alive():
            # o que a voz fala sozinha (o agente que terminou, a espera que venceu, a sessão acompanhada): confere em
            # segundo plano; com algo pronto e você sem falar, ela fala
            if self.pendente_pronto.is_set() and not estado["f"]:
                self.parar_gravacao.set()
                t.join()
                return "\0p"
            if time.time() - ultima > 6 and not estado["f"]:
                ultima = time.time()
                self._talvez_conferir()
            barra = "".join(NIVEL[max(0, min(7, int((estado["n"] * 6 - i) * 8)))] for i in range(6))
            self.tela.status("%s %s  Espaço: terminei · t: digitar · c: opções · m: %s · Esc: sair"
                             % ("● ouvindo" if estado["f"] else "○ fale", barra, "som" if self.mudo else "mudo"))
            k = teclado.tecla(0.1)
            if k == "c":
                self.parar_gravacao.set()
                t.join()
                if painel_opcoes(self.tela, teclado, self.gravador, self.falador, self.transcritor):
                    self.recarregar_transcricao()
                return "\0n"
            if k == "n":
                self.parar_gravacao.set()
                t.join()
                self.tela.status("… abrindo o próximo microfone")
                novo = self.gravador.proximo()
                self.tela.linha("nota", "ouvir: %s" % novo if novo else "não há outro microfone que funcione")
                return "\0n"
            if k == " ":
                self.parar_gravacao.set()
            elif k == "t":
                self.parar_gravacao.set()
                t.join()
                return "\0t"
            elif k == "m":
                self.mudo = not self.mudo
            elif k in ("esc", "q"):
                self.parar_gravacao.set()
                t.join()
                return None
        if res.get("motivo") == "erro":
            self.tela.linha("erro", "o gravador parou (%s)" % self.gravador.nome)
            return None
        if res.get("motivo") == "mudo":
            self.tela.linha("erro", "%s não manda som nenhum: está no mudo? (o botão do headset). c e depois n troca o "
                                    "microfone." % self.gravador.nome)
            return ""
        if res.get("motivo") in ("silencio", "parado"):
            self._aviso_fraco()
        if res.get("motivo") != "fala":
            return ""
        self.tela.status("… entendendo")
        try:
            txt = self.transcritor.texto(res["pcm"], self.dica)
        except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as e:
            self.tela.linha("erro", "não consegui transcrever: %s" % e)
            return ""
        txt = " ".join(txt.split())
        return "" if ALUCINACOES.match(txt.strip(" .!?,")) else txt

    def recarregar_transcricao(self):
        self.tela.status("… carregando a transcrição")
        novo = Transcritor(avisar=self._aviso_transcritor)
        if novo.preparar():
            antigo, self.transcritor = self.transcritor, novo
            antigo.fechar()
            self.tela.linha("nota", "transcrever: " + self.transcritor.desc)
        else:
            novo.fechar()
            self.tela.linha("erro", "não consegui trocar: %s. Continua em %s; l nas opções permite escolher outra máquina."
                            % (novo.motivo, self.transcritor.desc or "sem reconhecimento"))

    def _aviso_fraco(self):
        """Um som que durou mas não chegou ao limiar (o headset que entrega a voz baixa): diz uma vez por conversa como
        aumentar a sensibilidade, em vez de só "não ouvi"."""
        g = self.gravador
        if self.avisou_fraco or not g.quase or g.quase < 0.3 * g.limiar_quase or g.quase >= g.limiar_quase:
            return
        self.avisou_fraco = True
        self.tela.linha("nota", "ouvi um som fraco (nível %d; a fala conta a partir de %d). Se era você, fale mais perto do "
                                "microfone ou aumente a sensibilidade: c e depois g." % (g.quase, g.limiar_quase))

    def _ha_fundo(self):
        """Há algo que a voz possa ter de falar sozinha? (o agente pendente, uma espera agendada, uma sessão acompanhada)"""
        return any(os.path.exists(os.path.join(ESTADO, n)) for n in ("pendente", "agenda", "acompanhar", "retorno"))

    def _nota_fundo(self):
        """A nota antes do que a voz fala sozinha: de onde vem (o agente pendente, a hora combinada, a sessão acompanhada)."""
        for n, t in (("retorno.fila", "retorno:"), ("pendente", "o agente terminou:"), ("agenda", "deu a hora:"),
                     ("acompanhar", "a sessão acompanhada:")):
            if os.path.exists(os.path.join(ESTADO, n)):
                self.tela.linha("nota", t)
                return

    def _talvez_conferir(self):
        if not self.conferindo and self._ha_fundo():
            self.conferindo = True
            threading.Thread(target=self._conferir_pendente, daemon=True).start()

    def _conferir_pendente(self):
        try:
            if subprocess.run(["bash", self.voz, "--fundo-pronto"], capture_output=True, timeout=90).returncode == 0:
                self.pendente_pronto.set()
        except (OSError, subprocess.SubprocessError):
            pass
        finally:
            self.conferindo = False

    # -- o modo retorno: o microfone fecha e a janela espera as sessões chamarem
    def _em_retorno(self):
        return os.path.exists(os.path.join(ESTADO, "retorno"))

    def _conferir_retorno(self):
        """voz --retorno-pronto: a 1ª linha é o estado (quem está em aberto, o prazo); saída 0 = há o que falar."""
        try:
            r = subprocess.run(["bash", self.voz, "--retorno-pronto"], capture_output=True, text=True, timeout=90,
                               stdin=subprocess.DEVNULL)
            linhas = (r.stdout or "").strip().splitlines()
            if linhas:
                self.retorno_estado = linhas[0][:120]
            if r.returncode == 0:
                self.pendente_pronto.set()
        except (OSError, subprocess.SubprocessError):
            pass
        finally:
            self.conferindo = False

    def aguardar_retorno(self, teclado):
        """Espera no modo retorno, com o microfone fechado, conferindo a cada VOZ_T_RETORNO s. '\0p' = há retorno a
        falar; '\0f' = Espaço (falar agora); '\0t' = digitar; '\0r' = sair do modo; '\0n' = o modo acabou por fora;
        None = fechar a janela."""
        self.gravador.pausar()
        intervalo = float(os.environ.get("VOZ_T_RETORNO", "3"))
        ultima = 0.0
        while not self.sair:
            if self.pendente_pronto.is_set():
                self.pendente_pronto.clear()
                return "\0p"
            if not self._em_retorno():
                return "\0n"
            if time.time() - ultima > intervalo and not self.conferindo:
                ultima = time.time()
                self.conferindo = True
                threading.Thread(target=self._conferir_retorno, daemon=True).start()
            self.tela.status("⏸ retorno: %s  ·  Espaço: falar · t: digitar · r: sair do modo · Esc: sair"
                             % (self.retorno_estado or "…"))
            k = teclado.tecla(0.2)
            if k == " ":
                return "\0f"
            if k == "t":
                return "\0t"
            if k == "r":
                return "\0r"
            if k in ("esc", "q"):
                return None
        return None

    def _retomar_mic(self, som):
        """Reabre o microfone em segundo plano (enquanto a voz fala o retorno); ouvir() espera por ele."""
        if som and not self.digitar_sempre and self.gravador.cands:
            self.retomando = threading.Thread(target=self.gravador.retomar, daemon=True)
            self.retomando.start()

    def sua_vez(self, teclado, som, digitar=False):
        """Uma frase sua depois de um retorno (ou do Espaço): o texto, '' (silêncio ou nada: volta a esperar) ou None."""
        if self.retomando is not None:
            self.retomando.join(10)
            self.retomando = None
        if digitar or not som or self.digitar_sempre:
            frase = self.digitar(teclado)
            return "" if frase in ("\0p", "\0n") else frase
        frase = self.ouvir(teclado)
        if frase == "\0t":
            frase = self.digitar(teclado)
        return "" if frase in ("\0p", "\0n") else frase

    def atualizar_dica(self):
        try:
            self.dica = subprocess.run(["bash", self.voz, "--dica"], capture_output=True, text=True,
                                       timeout=20).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            pass

    def _erro_thread(self, a):
        """Erro numa tarefa de segundo plano: vai ao log (~/.cache/tt-voz/erros.log), nunca à tela da conversa."""
        try:
            import traceback
            os.makedirs(CACHE, exist_ok=True)
            with open(os.path.join(CACHE, "erros.log"), "a", encoding="utf-8") as f:
                f.write("%s %s\n" % (time.strftime("%F %T"), "".join(
                    traceback.format_exception(a.exc_type, a.exc_value, a.exc_traceback)).rstrip()))
        except OSError:
            pass

    def _aquecer_piper(self):
        try:
            self.falador._sintetizar("ok")
        except (OSError, RuntimeError, ValueError):
            pass  # sem o Piper em lugar nenhum: fala a voz do sistema

    def _oferecer_instalar(self, teclado):
        """Sem reconhecimento em lugar nenhum e sem ele aqui: oferece instalar agora (em 2º plano; a conversa segue
        digitando e passa a ouvir quando terminar). "n" fica lembrado por 7 dias."""
        if python_com("faster_whisper") or os.environ.get("VOZ_STT_CMD"):
            return
        marca = os.path.join(CACHE, "instalar-recusado")
        try:
            if time.time() - os.path.getmtime(marca) < 7 * 86400:
                return
        except OSError:
            pass
        self.tela.linha("nota", "Para ouvir você, esta máquina precisa do reconhecimento de voz (Whisper e a voz Piper, "
                                "~1 GB, uns minutos). Instalo agora, em segundo plano? Enquanto isso, você digita.")
        self.tela.status("instalar o reconhecimento de voz? s: sim · n: agora não")
        fim = time.time() + 120
        while time.time() < fim:
            k = teclado.tecla(0.3)
            if k in ("s", "S", "\r", "\n"):
                threading.Thread(target=self._instalar_fundo, daemon=True).start()
                return
            if k in ("n", "N", "esc", "q"):
                try:
                    os.makedirs(CACHE, exist_ok=True)
                    open(marca, "w").close()
                except OSError:
                    pass
                self.tela.linha("nota", "Tudo bem: siga digitando. Para instalar depois: botão direito no 🎤 → Instalar a voz neural.")
                return

    def _instalar_fundo(self):
        log = os.path.join(CACHE, "instalar.log")
        self.tela.linha("nota", "instalando o reconhecimento de voz (o passo a passo fica em %s)…" % log)
        try:
            os.makedirs(CACHE, exist_ok=True)
            with open(log, "w", encoding="utf-8") as f:
                cmd = ["bash", "-c", os.environ["VOZ_INSTALAR_CMD"]] if os.environ.get("VOZ_INSTALAR_CMD") else \
                    [sys.executable, EU, "instalar"]  # (VOZ_INSTALAR_CMD: testes)
                p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=f, text=True, stdin=subprocess.DEVNULL)
                for linha in p.stdout:
                    f.write(linha)
                    f.flush()
                    if linha.strip():
                        self.tela.linha("nota", "  " + linha.strip()[:160])
                rc = p.wait()
        except OSError as e:
            rc = 1
            self.tela.linha("erro", "não consegui instalar: %s" % e)
        if rc != 0:
            self.tela.linha("erro", "a instalação não terminou (veja %s). Siga digitando." % log)
            return
        novo = Transcritor(avisar=self._aviso_transcritor)
        if novo.preparar():
            antigo, self.transcritor = self.transcritor, novo
            antigo.fechar()
            self.tela.linha("nota", "✓ reconhecimento instalado: transcrever: %s. Pode falar." % novo.desc)
            self.som_pronto.set()
        else:
            novo.fechar()
            self.tela.linha("erro", "instalou, mas não abriu: %s" % novo.motivo)

    def _indice_fundo(self):
        """O índice das sessões de todas as máquinas (o cérebro escolhe por ele) renovado a cada ~30 s."""
        while not self.sair:
            try:
                subprocess.run(["bash", self.voz, "--indice-atualizar"], timeout=40, stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except (OSError, subprocess.SubprocessError):
                pass
            for _ in range(int(float(os.environ.get("VOZ_T_INDICE_JANELA", "30")) * 2)):
                if self.sair:
                    return
                time.sleep(0.5)

    def rodar(self):
        self.tela.abrir()
        try:
            return self._rodar()
        finally:
            self.tela.fechar()

    def _rodar(self):
        threading.excepthook = self._erro_thread
        if os.environ.get("VOZ_CEREBRO_VIVO", "1") != "0":
            self.cerebro = CerebroVivo(self.voz)
            self.cerebro.iniciar()  # a conta e o Claude abrem enquanto o microfone e a transcrição abrem
        threading.Thread(target=self._indice_fundo, daemon=True).start()
        self.tela.medir()
        som = not self.digitar_sempre
        if som:
            self.tela.status("… abrindo o microfone")
        if som and not self.gravador.escolher():
            self.tela.linha("nota", "Sem microfone: %s. Digite (t)." % self.gravador.motivo)
            som = False
        for nome in self.gravador.pulados:
            self.tela.linha("erro", "%s não manda som nenhum: está no mudo? (o botão do headset, ou o microfone "
                                    "desligado). Ouvindo pelo seguinte; c e depois n troca." % nome)
        self.falador = Falador(mic=self.gravador.nome if som else "",
                               fornecedor=lambda: (self.transcritor.canal, (self.transcritor.info or {}).get("vozes")))
        self.falador.aquecer()
        partes = []
        if som:
            partes.append("ouvir: %s" % self.gravador.nome)
        with Teclado(self.tela) as teclado:
            sem_reconhecimento = False
            if som:
                if self.transcritor.preparar():
                    partes.append("transcrever: " + self.transcritor.desc)
                else:
                    sem_reconhecimento = True
                    self.tela.linha("nota", "Sem reconhecimento de voz: %s. Por enquanto, digite."
                                    % self.transcritor.motivo)
                    som = False
            if self.falador.qual == "windows":
                self.falador._abrir_win()  # já vinha abrindo junto com a transcrição: aqui sabe-se onde toca
            if self.falador.neural() and self.falador.voz.startswith("piper:"):  # carrega a voz enquanto a conversa abre
                threading.Thread(target=self._aquecer_piper, daemon=True).start()
            if self.falador.neural() and self.falador.voz in self.falador.vozes():
                partes.append("falar: %s em %s" % (rotulo_voz(self.falador.voz), self.falador.onde))
            else:
                partes.append("falar: %s%s" % (self.falador.det, "" if self.falador.qual in ("nenhum", "cmd", "spd", "espeak", "termux")
                                               else " em " + self.falador.onde))
            self.tela.linha("nota", " · ".join(partes) + "   (c: opções)")
            if sem_reconhecimento and not self.digitar_sempre:
                self._oferecer_instalar(teclado)
            self.atualizar_dica()
            fim = self.turno("terminal", teclado)
            while not self.sair and not fim:
                if self.som_pronto.is_set():  # a instalação terminou: passa a ouvir
                    self.som_pronto.clear()
                    som = self.gravador.fluxo is not None or self.gravador.escolher()
                if self._em_retorno():
                    r = self.aguardar_retorno(teclado)
                    if r is None:
                        break
                    if r == "\0r":
                        self._retomar_mic(som)
                        fim = self.turno("sair do modo retorno", teclado)
                        continue
                    if r == "\0n":  # o modo acabou (outra conversa, o celular): volta a ouvir sempre
                        self._retomar_mic(som)
                        continue
                    if r != "\0t":
                        self._retomar_mic(som)
                    if r == "\0p":  # uma sessão chamou (respondeu, pediu uma decisão, fechou) ou o prazo venceu
                        self._nota_fundo()
                        if not self.mudo and self.falador:
                            self.falador.plim()
                        fim = self.turno("", teclado, ["--turno-fundo"])
                        if fim or self.sair:
                            continue
                    frase = self.sua_vez(teclado, som, digitar=(r == "\0t"))
                    if frase is None:
                        break
                    if not frase:  # em silêncio: volta a esperar (ou, se o modo acabou, a ouvir sempre)
                        continue
                    self.tela.linha("voce", frase)
                    fim = self.turno(frase, teclado)
                    self.atualizar_dica()
                    continue
                if som and not self.digitar_sempre:
                    frase = self.ouvir(teclado)
                    if frase is None:
                        break
                    if frase == "\0n":  # trocou o microfone ou as opções: volta a ouvir
                        continue
                    if frase == "\0p":  # o agente terminou, a espera venceu ou a sessão acompanhada mudou: a voz fala
                        self.pendente_pronto.clear()
                        self._nota_fundo()
                        fim = self.turno("", teclado, ["--turno-fundo"])
                        continue
                    if frase == "\0t":  # t: digitar esta vez (Esc volta a ouvir)
                        frase = self.digitar(teclado)
                        if frase == "\0p":
                            self.pendente_pronto.clear()
                            self._nota_fundo()
                            fim = self.turno("", teclado, ["--turno-fundo"])
                            continue
                        if not frase or frase == "\0n":
                            continue
                        self.tela.linha("voce", frase)
                    elif frase == "":
                        frase = "silencio"  # o voz pede de novo; na 2ª vez seguida, encerra
                    else:
                        self.tela.linha("voce", frase)
                else:
                    frase = self.digitar(teclado)
                    if frase is None:
                        break
                    if frase == "\0p":
                        self.pendente_pronto.clear()
                        self._nota_fundo()
                        fim = self.turno("", teclado, ["--turno-fundo"])
                        continue
                    if not frase or frase == "\0n":
                        continue
                    self.tela.linha("voce", frase)
                fim = self.turno(frase, teclado)
                self.atualizar_dica()
            if fim and not self.sair:
                time.sleep(0.6)
        self.sair = True
        if self.cerebro:
            self.cerebro.fechar()
        self.transcritor.fechar()
        self.gravador.fechar()
        if self.falador:
            self.falador.fechar()
        medir_depois()
        return 0


def medir_depois():
    """Ao fechar a janela: se esta máquina transcreve e as medições não valem mais (pacote, modelo ou GPU mudou),
    mede de novo em segundo plano, com prioridade baixa (as frases de referência precisam da voz do Piper)."""
    py = python_com("faster_whisper")
    if not py or os.environ.get("VOZ_STT_CMD") or not os.path.exists(arquivo_voz_piper()) or not medicao_velha(py):
        return
    log = os.path.join(CACHE, "medir.log")
    try:
        os.makedirs(CACHE, exist_ok=True)
        with open(log, "a") as f:
            subprocess.Popen(["nice", "-n", "19", py, EU, "medir"], stdout=f, stderr=f, stdin=subprocess.DEVNULL,
                             start_new_session=True)
    except OSError:
        pass


def espelho():
    """Celular: a conversa é do Tasker (ele ouve e fala); a janela mostra o conversa.log e deixa digitar."""
    tela = Tela()
    try:
        return _espelho(tela)
    finally:
        tela.fechar()


def _espelho(tela):
    estado = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(CASA, ".local", "state"), "tt-voz")
    log = os.path.join(estado, "conversa.log")
    entrada = os.path.join(os.environ.get("VOZ_SDCARD", "/sdcard"), "Tasker", "voz", "in")
    pos = os.path.getsize(log) if os.path.exists(log) else 0
    tela.abrir()
    tela.linha("nota", "A conversa abre no Tasker (ele ouve e fala). Aqui aparece o que foi dito.")
    with Teclado(tela) as teclado:
        while True:
            tela.status("t: digitar · Esc: fechar a janela (diga encerrar para fechar a conversa)")
            k = teclado.tecla(0.3)
            if k in ("esc", "q"):
                return 0
            if k == "t":
                txt = ""
                while True:
                    tela.status("você> " + txt + "▏  (Enter manda · Esc cancela)")
                    k = teclado.tecla(0.2)
                    if k == "esc":
                        txt = ""
                        break
                    if k in ("\r", "\n"):
                        break
                    if k in ("\x7f", "\b"):
                        txt = txt[:-1]
                    elif k and k.isprintable():
                        txt += k
                if txt.strip():
                    os.makedirs(entrada, exist_ok=True)
                    with open(os.path.join(entrada, "tela-%d.txt" % int(time.time() * 1000)), "w") as f:
                        f.write(txt.strip())
            try:
                with open(log, encoding="utf-8", errors="replace") as f:
                    f.seek(pos)
                    novo = f.read()
                    pos = f.tell()
            except OSError:
                novo = ""
            for l in novo.splitlines():
                hora, _, resto = l.partition(" ")
                quem, _, texto = resto.partition(": ")
                tela.linha("voce" if quem == "você" else "tt", texto)


# ---------------------------------------------------------------- diagnóstico, teste e instalação
def diagnostico(provar=True):
    linhas = []
    sistema = "macOS" if eh_mac() else ("WSL" if eh_wsl() else ("Termux" if eh_termux() else platform.system()))
    linhas.append("sistema: %s" % sistema)
    g = Gravador()
    if provar:
        ok = g.escolher()
        linhas.append("ouvir: %s" % (g.nome if ok else "✗ " + g.motivo))
        g.fechar()
    linhas.append("microfones (o 1º que entrega áudio vale; na janela, n passa ao seguinte):")
    for m in g.cands or candidatos_gravador():
        linhas.append("    %s%s%s" % ("● " if m.nome == g.nome else "  ", m.nome, " (padrão do sistema)" if m.padrao else ""))
    py = python_com("faster_whisper")
    if py:
        e = escolha_local(py)
        med = ler_json(MEDICOES) or {}
        linhas.append("transcrever aqui: %s (%s)" % (descrever("local", e, e.get("tempo")),
                                                     "medido em %s" % time.strftime("%d/%m %H:%M", time.localtime(med["quando"]))
                                                     if e.get("fonte") == "medido" else "estimado; voz --medir mede"))
        if e.get("fonte") == "medido":
            for r in sorted(med.get("resultados", []), key=custo):
                linhas.append("    %-15s %-4s %5.2f s · erro %3.0f%%" % (r["modelo"], r["dispositivo"], r["tempo"], r["erro"] * 100))
    else:
        linhas.append("transcrever aqui: ✗ sem faster-whisper (voz --instalar-audio, ou transcreve noutra máquina)")
    gp = gpus_nvidia()
    linhas.append("GPU: %s" % (", ".join(g.replace(",", " ·") + " MB" for g in gp) if gp else "nenhuma NVIDIA (só a CPU)"))
    if provar:
        ranking, erros = escolher(Transcritor().lugares())
        linhas.append("onde transcrever (o 1º é o escolhido; custo = tempo + %g × erro):" % PESO_ERRO)
        for custo_, lugar, tempo, fonte, info in ranking:
            e = info.get("escolha", {})
            linhas.append("    %s  (custo %.2f, erro %.0f%%, %s)" % (descrever(lugar, e, tempo), custo_, e.get("erro", 0) * 100, fonte))
        for er in erros:
            linhas.append("    ✗ " + er)
    f = Falador(mic=g.nome or "")
    if f.qual == "windows":
        f._abrir_win()
    linhas.append("falar: %s%s" % (f.det, "" if f.qual in ("nenhum", "cmd", "spd", "espeak", "termux") else " em " + f.onde))
    f.fechar()
    print("\n".join(linhas))
    return 0


def teste():
    """Grava uma frase, mostra o nível e o texto, e repete o que ouviu (o teste do botão direito do 🎤)."""
    tela = Tela()
    diagnostico()
    g = Gravador()
    if not g.escolher():
        print("✗ " + g.motivo)
        return 1
    t = Transcritor(avisar=lambda x: tela.status("… " + x))
    print("Fale uma frase curta (o fim é o silêncio)…")
    pico = [0.0]

    def nivel(v, falando):
        pico[0] = max(pico[0], v)
        tela.status("%s nível %s" % ("●" if falando else "○", "█" * int(v * 20)))

    pcm, motivo = g.frase(nivel=nivel)
    g.fechar()
    tela.status("")
    print("\rgravado: %s, %.1f s, pico %d%%" % (motivo, len(pcm) / 2 / TAXA, pico[0] * 100))
    if motivo != "fala":
        print("✗ não ouvi fala%s: fale mais perto, ou aumente a sensibilidade (voz --limiar alta, ou c e g na janela)"
              % (" (ouvi um som fraco, nível %d; a fala conta a partir de %d)" % (g.quase, g.limiar_quase)
                 if g.quase >= 0.3 * g.limiar_quase else ""))
        return 1
    if not t.preparar():
        print("✗ transcrever: " + t.motivo)
        return 1
    txt = t.texto(pcm)
    t.fechar()
    print("ouvi: %s" % (txt or "(nada)"))
    f = Falador(mic=g.nome or "")
    if txt and f.qual != "nenhum":
        print("falando em: %s" % f.onde if f.qual not in ("spd", "espeak", "termux", "cmd") else "falando")
        f.falar("Ouvi: " + txt)
    f.fechar()
    return 0


def instalar():
    """venv com faster-whisper e Piper, a voz pt-BR do Piper e o modelo do Whisper (em cache).
    Tudo o que cada passo imprime vai também para ~/.local/state/tt-voz/instalar.log (acrescenta, com data); um passo
    que falha não derruba os que não dependem dele, e no fim diz quantos erros deram."""
    py = sys.executable
    estado = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(CASA, ".local", "state"), "tt-voz")
    os.makedirs(estado, exist_ok=True)
    log = os.path.join(estado, "instalar.log")
    erros = []

    def escrever(txt):
        with open(log, "a", encoding="utf-8") as f:
            f.write(txt)

    def dizer(txt):
        print(txt, flush=True)
        escrever(txt + "\n")

    def passo(nome, cmd):
        """roda o comando mostrando a saída e gravando no log; devolve o código de saída."""
        escrever("\n== %s  $ %s\n" % (time.strftime("%F %T"), " ".join(cmd)))
        saida = []
        try:
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True,
                                 errors="replace")
            for linha in p.stdout:
                sys.stdout.write(linha)
                escrever(linha)
                saida.append(linha)
            rc = p.wait()
        except OSError as e:
            rc = 127
            dizer("  %s" % e)
        escrever("== %s: código %d\n" % (nome, rc))
        if rc != 0:
            erros.append(nome)
            junto = "".join(saida)
            if re.search(r"HTTP Error 40[13]|\b40[13] (Client Error|Forbidden)|ns-template", junto):
                dizer("  ↳ o endereço respondeu 403: um filtro de rede/proxy bloqueia o site. Libere o domínio (o Hugging Face "
                      "é huggingface.co) ou rode numa rede sem o filtro; a instalação continua de onde parou.")
        return rc

    dizer("venv em %s (log em %s)" % (VENV, log))
    vpy = os.path.join(VENV, "bin", "python")
    if not os.path.exists(vpy) or subprocess.run([vpy, "-m", "pip", "--version"], capture_output=True).returncode != 0:
        if subprocess.run([py, "-m", "venv", VENV], capture_output=True).returncode != 0:
            # Debian/Ubuntu sem o python3-venv (o ensurepip vem nele): o venv sem pip e o pip pelo get-pip.py, sem sudo
            dizer("venv sem o ensurepip (falta o python3-venv): pip pelo get-pip.py")
            gp = os.path.join(tempfile.gettempdir(), "tt-voz-get-pip.py")
            if passo("venv", [py, "-m", "venv", "--clear", "--without-pip", VENV]) != 0 or \
                    passo("get-pip", ["curl", "-fsSL", "-m", "120", "-o", gp, os.environ.get(
                        "VOZ_GET_PIP", "https://bootstrap.pypa.io/get-pip.py")]) != 0 or \
                    passo("get-pip.py", [vpy, gp, "-q"]) != 0:
                dizer("✗ não consegui criar o venv (no Debian/Ubuntu: sudo apt install python3-venv)")
                return 1
    pip = [vpy, "-m", "pip", "install", "--upgrade", "--disable-pip-version-check"]
    if passo("pip", pip + ["pip"]) != 0 or passo("pip pacotes", pip + ["faster-whisper", "piper-tts", "edge-tts"]) != 0:
        dizer("✗ pip falhou (nada mais é instalado sem os pacotes)")
        return 1
    os.makedirs(VOZES, exist_ok=True)
    if not os.path.exists(arquivo_voz_piper()):
        dizer("voz do Piper: %s" % VOZ_PIPER)
        if passo("voz do Piper", [vpy, "-m", "piper.download_voices", VOZ_PIPER, "--data-dir", VOZES]) != 0:
            dizer("✗ não consegui baixar a voz do Piper (a fala cai no edge-tts/voz do sistema)")
    gpus = gpus_nvidia()
    if gpus and not os.environ.get("VOZ_SEM_GPU"):
        dizer("GPU NVIDIA (%s): bibliotecas CUDA para o Whisper (cuBLAS e cuDNN, ~2 GB; VOZ_SEM_GPU=1 pula)" % gpus[0])
        if passo("CUDA", pip + ["nvidia-cublas-cu12", "nvidia-cudnn-cu12==9.*"]) != 0:
            dizer("  ✗ não instalou; fica a CPU")
    modelos = [os.environ["VOZ_MODELO"]] if os.environ.get("VOZ_MODELO") else ["small", "base"]
    carregou = 0
    for modelo in modelos:
        dizer("modelo do Whisper: %s (baixa uma vez para o cache do Hugging Face)" % modelo)
        if passo("modelo %s" % modelo, [vpy, "-c", "from faster_whisper import WhisperModel as W; W(%r, device='cpu', "
                                                  "compute_type='int8')" % modelo]) == 0:
            carregou += 1
        else:
            dizer("✗ não consegui carregar o modelo %s" % modelo)
    if carregou and os.path.exists(arquivo_voz_piper()):
        dizer("medindo cada jeito de transcrever nesta máquina (modelo × CPU/GPU, frases de referência):")
        if passo("medição", [vpy, EU, "medir"]) != 0:
            dizer("✗ a medição falhou; vale a estimativa pelo hardware (voz --medir tenta de novo)")
    if erros:
        dizer("✗ terminou com %d erro(s): %s. Detalhes em %s; rode voz --instalar-audio de novo depois de resolver."
              % (len(erros), ", ".join(erros), log))
        return 1
    dizer("✓ pronto: o 🎤 desta máquina transcreve e fala sozinho")
    return 0


def main(a):
    signal.signal(signal.SIGTERM, lambda *x: sys.exit(0))
    cmd = a[0] if a else ""
    if cmd == "conversa":
        return Conversa(digitar="--digitar" in a).rodar()
    if cmd == "espelho":
        return espelho()
    if cmd == "diagnostico":
        return diagnostico(provar="--sem-provar" not in a)
    if cmd == "teste":
        return teste()
    if cmd == "servidor":
        return servidor()
    if cmd == "opcoes":
        tela = Tela()
        tela.abrir()
        try:
            g = Gravador()
            tela.status("… abrindo o microfone e a voz")
            tem_mic = g.escolher()
            f = Falador(mic=g.nome if tem_mic else "")
            if f.qual == "windows":
                f._abrir_win()
            with Teclado(tela) as teclado:
                painel_opcoes(tela, teclado, g if tem_mic else None, f)
            g.fechar()
            f.fechar()
        finally:
            tela.fechar()
        return 0
    if cmd == "capacidade":
        print(json.dumps(capacidade(), ensure_ascii=False))
        return 0
    if cmd == "medir":  # no Python com o faster-whisper (e o Piper, que diz as frases de referência)
        py = python_com("faster_whisper")
        if py and py != sys.executable:
            os.execv(py, [py, EU, "medir"])
        if not py or not os.path.exists(arquivo_voz_piper()):
            print("sem faster-whisper ou sem a voz do Piper (voz --instalar-audio)")
            return 1
        return 0 if medir().get("resultados") else 1
    if cmd == "escolher":
        ranking, erros = escolher(os.environ.get("VOZ_TRANSCREVER", "local").split())
        for custo_, lugar, tempo, fonte, info in ranking:
            print("%.2f\t%s\t%s\t%s" % (custo_, lugar, tempo, descrever(lugar, info.get("escolha", {}))))
        for er in erros:
            print("✗ " + er)
        return 0 if ranking else 1
    if cmd == "motor":  # o servidor no Python que tem o faster-whisper (pedido por outra máquina, por ssh)
        py = python_com("faster_whisper")
        if not py:
            print(json.dumps({"pronto": False, "erro": "sem faster-whisper nesta máquina"}), flush=True)
            return 1
        os.execv(py, [py, EU, "servidor"])
    if cmd == "instalar":
        return instalar()
    if cmd == "gravar" and len(a) > 1:
        g = Gravador()
        if not g.escolher():
            print(g.motivo, file=sys.stderr)
            return 1
        pcm, motivo = g.frase()
        with open(a[1], "wb") as f:
            f.write(wav_de(pcm))
        print(motivo)
        return 0 if motivo == "fala" else 1
    if cmd == "transcrever" and len(a) > 1:
        dados = sys.stdin.buffer.read() if a[1] == "-" else open(a[1], "rb").read()
        print(Motor().stt(dados))
        return 0
    if cmd == "falar":
        return 0 if Falador().falar(" ".join(a[1:])) else 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
