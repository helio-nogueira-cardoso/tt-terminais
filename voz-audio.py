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
def candidatos_gravador():
    """Comandos que soltam PCM s16le mono 16 kHz no stdout, do mais comum ao último recurso."""
    c = os.environ.get("VOZ_GRAVADOR")
    if c:
        return [("VOZ_GRAVADOR", ["sh", "-c", c])]
    w = shutil.which
    t = str(TAXA)
    sox = ["-q", "-d", "-t", "raw", "-b", "16", "-e", "signed-integer", "-c", "1", "-r", t, "-"]
    ff = ["-loglevel", "quiet", "-nostdin"]
    out = []
    if eh_mac():
        if w("sox"):
            out.append(("sox", ["sox"] + sox))
        if w("rec"):
            out.append(("rec", ["rec"] + sox))
        if w("ffmpeg"):
            out.append(("ffmpeg", ["ffmpeg"] + ff + ["-f", "avfoundation", "-i", ":0", "-ac", "1", "-ar", t,
                                                    "-f", "s16le", "-"]))
        return out
    ambiente_audio()
    if w("parecord"):
        out.append(("parecord", ["parecord", "--raw", "--format=s16le", "--rate=" + t, "--channels=1",
                                 "--latency-msec=60"]))
    if w("pw-record"):
        out.append(("pw-record", ["pw-record", "--raw", "--rate", t, "--channels", "1", "--format", "s16", "-"]))
    if w("arecord"):
        out.append(("arecord", ["arecord", "-q", "-t", "raw", "-f", "S16_LE", "-r", t, "-c", "1"]))
        # o servidor de som pode ter perdido a placa (só "Dummy Output"): o microfone direto pelo ALSA ainda grava
        try:
            lista = subprocess.run(["arecord", "-l"], capture_output=True, text=True, timeout=5).stdout
        except (OSError, subprocess.SubprocessError):
            lista = ""
        for m in re.finditer(r"^card (\d+):.*?device (\d+): ([^\n]*)", lista, re.M):
            out.append(("arecord hw:%s,%s (%s)" % (m.group(1), m.group(2), m.group(3).split("[")[0].strip()),
                        ["arecord", "-q", "-D", "plughw:%s,%s" % (m.group(1), m.group(2)), "-t", "raw",
                         "-f", "S16_LE", "-r", t, "-c", "1"]))
    if w("sox"):
        out.append(("sox", ["sox"] + sox))
    if w("ffmpeg"):
        out.append(("ffmpeg", ["ffmpeg"] + ff + ["-f", "pulse", "-i", "default", "-ac", "1", "-ar", t,
                                                "-f", "s16le", "-"]))
    return out


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


class Gravador:
    """Acha um gravador que entrega som de verdade e grava frases, com o fim pelo silêncio."""

    def __init__(self):
        self.nome = None
        self.cmd = None
        self.motivo = ""

    def escolher(self):
        memo = os.path.join(CACHE, "gravador")
        cands = candidatos_gravador()
        if os.environ.get("VOZ_GRAVADOR"):  # escolhido à mão: sem prova (que gastaria o começo da gravação)
            self.nome, self.cmd = cands[0]
            return True
        if not cands:
            self.motivo = "sem programa para gravar (" + ("brew install sox" if eh_mac() else
                                                           "instale pulseaudio-utils, alsa-utils ou sox") + ")"
            return False
        try:
            with open(memo) as f:
                antes = f.read().strip()
            cands.sort(key=lambda c: c[0] != antes)
        except OSError:
            pass
        # o primeiro que entrega som com sinal; uma entrada sem microfone (a analógica sem fone) só dá um chiado baixo
        erros, mudos = [], []
        sinal = float(os.environ.get("VOZ_SINAL_MIN", "20"))
        for nome, cmd in cands:
            ok, erro, nv = self._prova(cmd)
            if ok and nv >= sinal:
                return self._usar(nome, cmd, memo)
            if ok:
                mudos.append((nv, nome, cmd))
            else:
                erros.append("%s: %s" % (nome, erro))
        if mudos:
            nv, nome, cmd = max(mudos, key=lambda m: m[0])
            return self._usar(nome, cmd, memo)
        self.motivo = "nenhum gravador entregou som (" + "; ".join(erros)[:300] + ")"
        return False

    def _usar(self, nome, cmd, memo):
        self.nome, self.cmd = nome, cmd
        try:
            os.makedirs(CACHE, exist_ok=True)
            with open(memo, "w") as f:
                f.write(nome + "\n")
        except OSError:
            pass
        return True

    @staticmethod
    def _prova(cmd):
        """(entregou som?, erro, nível): lê 0,4 s (ou espera até VOZ_PROVA_S pelo primeiro áudio)."""
        try:
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL)
        except OSError as e:
            return False, str(e), 0.0
        try:
            b = ler_exato(p.stdout.fileno(), 12800, time.time() + float(os.environ.get("VOZ_PROVA_S", "1.5")))
        finally:
            parar_processo(p)
        if len(b) >= 3200:
            return True, "", rms(b[1600:])
        err = (p.stderr.read() or b"").decode("utf-8", "replace").strip().splitlines()
        return False, (err[-1] if err else "não entregou áudio"), 0.0

    def frase(self, nivel=None, parar=None, espera=None, maximo=20.0, pausa=None):
        """Grava até o silêncio depois da fala. Devolve (pcm, motivo): motivo = fala | silencio | parado | erro."""
        espera = float(os.environ.get("VOZ_ESPERA_FALA_S", espera or 8.0))
        pausa = float(os.environ.get("VOZ_PAUSA", pausa or 1.1))
        minimo = float(os.environ.get("VOZ_LIMIAR", "350"))
        try:
            p = subprocess.Popen(self.cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 stdin=subprocess.DEVNULL)
        except OSError:
            return b"", "erro"
        fd = p.stdout.fileno()
        tam = QUADRO * 2
        antes, fala = [], []
        piso = None
        acima = abaixo = 0
        falando = False
        inicio = time.time()
        comeco_fala = 0.0
        motivo = "silencio"
        try:
            while True:
                q = ler_exato(fd, tam, time.time() + 2.0)
                if len(q) < tam:
                    motivo = "erro" if not falando else "fala"
                    break
                r = rms(q)
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
        finally:
            parar_processo(p)
        if motivo == "fala":
            return b"".join(fala), motivo
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
    """faster-whisper e Piper carregados uma vez (no processo que tem os pacotes)."""

    def __init__(self):
        self.modelo = None
        self.piper = None

    def stt(self, wav, dica=""):
        if self.modelo is None:
            from faster_whisper import WhisperModel
            self.modelo = WhisperModel(os.environ.get("VOZ_MODELO", "small"),
                                       device=os.environ.get("VOZ_DISPOSITIVO", "cpu"),
                                       compute_type=os.environ.get("VOZ_PRECISAO", "int8"))
        with wave.open(io.BytesIO(wav)) as w:
            pcm = w.readframes(w.getnframes())
        import numpy
        audio = numpy.frombuffer(pcm, dtype=numpy.int16).astype(numpy.float32) / 32768.0
        segs, _ = self.modelo.transcribe(audio, language=os.environ.get("VOZ_IDIOMA", "pt"), beam_size=5,
                                         vad_filter=False, condition_on_previous_text=False,
                                         without_timestamps=True, initial_prompt=dica or None)
        return " ".join(s.text.strip() for s in segs).strip()

    def tts(self, texto, saida):
        if self.piper is None:
            from piper import PiperVoice
            self.piper = PiperVoice.load(arquivo_voz_piper())
        with wave.open(saida, "wb") as w:
            self.piper.synthesize_wav(texto, w)
        return saida


def arquivo_voz_piper():
    return os.path.join(VOZES, VOZ_PIPER + ".onnx")


def servidor():
    """Laço do motor: lê pedidos no stdin (binário) e responde uma linha JSON por pedido."""
    m = Motor()
    ent, sai = sys.stdin.buffer, sys.stdout
    sai.write(json.dumps({"pronto": True}) + "\n")
    sai.flush()
    while True:
        linha = ent.readline()
        if not linha:
            return 0
        try:
            p = json.loads(linha)
            t0 = time.time()
            if p.get("op") == "stt":
                wav = ent.read(int(p["n"]))
                r = {"texto": m.stt(wav, p.get("dica", "")), "s": round(time.time() - t0, 2)}
            elif p.get("op") == "tts":
                r = {"saida": m.tts(p["texto"], p["saida"]), "s": round(time.time() - t0, 2)}
            elif p.get("op") == "carregar":
                if p.get("stt"):
                    m.stt(wav_de(b"\0\0" * (TAXA // 2)))
                if p.get("tts") and os.path.exists(arquivo_voz_piper()):
                    m.tts("ok", os.path.join(tempfile.gettempdir(), "tt-voz-carregar-%d.wav" % os.getpid()))
                r = {"ok": True, "s": round(time.time() - t0, 2)}
            else:
                r = {"erro": "pedido desconhecido"}
        except Exception as e:  # o cliente decide o que fazer; o laço segue
            r = {"erro": "%s: %s" % (type(e).__name__, e)}
        sai.write(json.dumps(r, ensure_ascii=False) + "\n")
        sai.flush()


def pythons():
    """Pythons candidatos ao motor, na ordem: VOZ_PYTHON, o venv do tt-voz, um venv do whisper que já exista, este."""
    out = []
    for p in (os.environ.get("VOZ_PYTHON"), os.path.join(VENV, "bin", "python"),
              os.path.join(CASA, ".local", "share", "whisper-venv", "bin", "python"), sys.executable):
        if p and os.path.exists(p) and p not in out:
            out.append(p)
    return out


def python_com(modulo):
    for p in pythons():
        try:
            if subprocess.run([p, "-c", "import " + modulo], capture_output=True, timeout=30).returncode == 0:
                return p
        except (OSError, subprocess.SubprocessError):
            pass
    return None


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

    def pedir(self, pedido, dados=b"", tempo=60):
        with self.trava:
            if self.p.poll() is not None:
                raise RuntimeError("o motor em %s parou" % self.nome)
            self.p.stdin.write((json.dumps(pedido, ensure_ascii=False) + "\n").encode() + dados)
            self.p.stdin.flush()
            linha = self._linha(tempo)
        if not linha:
            raise RuntimeError("o motor em %s não respondeu a tempo" % self.nome)
        r = json.loads(linha)
        if r.get("erro"):
            raise RuntimeError(r["erro"])
        return r

    def fechar(self):
        try:
            self.p.stdin.close()
        except OSError:
            pass
        parar_processo(self.p)


class Transcritor:
    """Transcreve onde der: os lugares de VOZ_TRANSCREVER (local = este computador; rótulo = outra máquina do tt)."""

    def __init__(self, avisar=None):
        self.canal = None
        self.onde = ""
        self.motivo = ""
        self.avisar = avisar or (lambda t: None)

    def lugares(self):
        v = os.environ.get("VOZ_TRANSCREVER", "").split()
        return v or ["local"]

    def preparar(self):
        if os.environ.get("VOZ_STT_CMD"):
            self.onde = "comando de teste"
            return True
        erros = []
        for lugar in self.lugares():
            try:
                if lugar == "local":
                    py = python_com("faster_whisper")
                    if not py:
                        erros.append("local: sem faster-whisper (voz --instalar-audio)")
                        continue
                    self.canal = Canal([py, EU, "servidor"], "local")
                else:
                    dest = destino(lugar)
                    if not dest or dest == "local":
                        erros.append("%s: máquina desconhecida" % lugar)
                        continue
                    self.canal = Canal(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
                                        "-o", "ServerAliveInterval=10", dest,
                                        'PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"; '
                                        'exec voz --motor'], lugar)
                self.onde = lugar
                modelo = os.environ.get("VOZ_MODELO", "small")
                self.avisar("carregando o reconhecimento (%s, modelo %s)…" % (lugar, modelo))
                self.canal.pedir({"op": "carregar", "stt": True}, tempo=300)
                if lugar != "local":  # o voz tenta esta primeiro da próxima vez (depois da local)
                    try:
                        os.makedirs(CACHE, exist_ok=True)
                        with open(os.path.join(CACHE, "transcrever-ok"), "w") as f:
                            f.write(lugar + "\n")
                    except OSError:
                        pass
                return True
            except (OSError, RuntimeError, ValueError) as e:
                erros.append("%s: %s" % (lugar, e))
                if self.canal:
                    self.canal.fechar()
                    self.canal = None
        self.motivo = "; ".join(erros) or "nenhum lugar para transcrever"
        return False

    def texto(self, pcm, dica=""):
        wav = wav_de(pcm)
        c = os.environ.get("VOZ_STT_CMD")
        if c:
            return subprocess.run(["sh", "-c", c], input=wav, capture_output=True, timeout=60).stdout.decode(
                "utf-8", "replace").strip()
        if self.canal and self.canal.p.poll() is not None:  # o motor caiu (a rede, o ssh): abre de novo
            self.canal.fechar()
            self.canal = None
            self.preparar()
        if not self.canal:
            raise RuntimeError(self.motivo or "sem reconhecimento")
        return self.canal.pedir({"op": "stt", "n": len(wav), "dica": dica[:600]}, wav)["texto"]

    def fechar(self):
        if self.canal:
            self.canal.fechar()


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
def tocador():
    w = shutil.which
    if eh_mac() and w("afplay"):
        return ["afplay"]
    ambiente_audio()
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


PS_FALAR = ("Add-Type -AssemblyName System.Speech; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
            "$v = $s.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -eq 'pt-BR' } | "
            "Select-Object -First 1; if ($v) { $s.SelectVoice($v.VoiceInfo.Name) }; $s.Rate = 1; "
            "$s.Speak([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s')))")


class Falador:
    """Diz o texto com o melhor motor daqui; `parar()` corta a fala no meio."""

    def __init__(self, motor_canal=None):
        self.proc = None
        self.motor = motor_canal
        self.trava = threading.Lock()
        self.qual, self.det = self._escolher()

    def aquecer(self):
        """Carrega a voz do Piper em segundo plano (a primeira fala sai sem esperar o modelo)."""
        if self.qual == "piper":
            threading.Thread(target=lambda: self._piper_canal().pedir({"op": "carregar", "tts": True}, tempo=120),
                             daemon=True).start()

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
            if q == "piper" and os.path.exists(arquivo_voz_piper()) and tocador():
                py = python_com("piper")
                if py:
                    return q, "Piper %s (%s)" % (VOZ_PIPER, py)
            if q == "say" and eh_mac() and w("say"):
                v = voz_say()
                return q, "say %s" % (v or "(voz padrão)")
            if q == "windows" and eh_wsl() and powershell():
                return q, "voz do Windows (pt-BR, se instalada)"
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
        if q == "cmd":
            return subprocess.Popen(["sh", "-c", os.environ["VOZ_TTS_CMD"]], stdin=subprocess.PIPE), texto
        if q == "piper":
            saida = os.path.join(tempfile.gettempdir(), "tt-voz-fala-%d.wav" % os.getpid())
            self._piper_canal().pedir({"op": "tts", "texto": texto, "saida": saida}, tempo=60)
            return subprocess.Popen(tocador() + [saida], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL), None
        if q == "say":
            v = voz_say()
            return subprocess.Popen(["say"] + (["-v", v] if v else []) + [texto]), None
        if q == "windows":
            b64 = base64.b64encode(texto.encode("utf-8")).decode()
            return subprocess.Popen([powershell(), "-NoProfile", "-NonInteractive", "-Command", PS_FALAR % b64],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL), None
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
        p = self.proc
        if p is not None:
            parar_processo(p)
            if self.qual == "spd" and shutil.which("spd-say"):
                subprocess.run(["spd-say", "-C"], capture_output=True)


# ---------------------------------------------------------------- a janela da conversa
COR = {"voce": "\033[1;36m", "tt": "\033[1;32m", "nota": "\033[2;37m", "erro": "\033[1;31m", "fim": "\033[0m"}
NIVEL = "▁▂▃▄▅▆▇█"


class Tela:
    """Conversa rolando para cima e uma linha de estado embaixo (redesenhada no lugar)."""

    def __init__(self):
        self.trava = threading.Lock()
        self.estado = ""
        self.largura = 70

    def medir(self):
        try:
            self.largura = max(30, os.get_terminal_size(sys.stdout.fileno()).columns)
        except OSError:
            self.largura = 70

    def linha(self, quem, texto):
        self.medir()
        rot = {"voce": "você: ", "tt": "tt: ", "nota": "", "erro": "⚠ "}.get(quem, "")
        corpo = textwrap.wrap(texto, self.largura - 1 - len(rot)) or [""]
        with self.trava:
            sys.stdout.write("\r\033[2K")
            for i, l in enumerate(corpo):
                pre = rot if i == 0 else " " * len(rot)
                sys.stdout.write("%s%s%s%s\n" % (COR.get(quem, ""), pre, l, COR["fim"]))
            sys.stdout.write(self.estado)
            sys.stdout.flush()

    def status(self, texto):
        with self.trava:
            self.estado = texto[: max(10, self.largura - 1)]
            sys.stdout.write("\r\033[2K" + self.estado)
            sys.stdout.flush()


class Teclado:
    """Lê teclas sem esperar Enter (modo cbreak) numa thread; Esc sozinho vira 'esc'."""

    def __init__(self):
        self.fila = queue.Queue()
        self.fd = sys.stdin.fileno()
        self.antes = None
        self.vivo = True

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

    def _ler(self):
        while self.vivo:
            r, _, _ = select.select([self.fd], [], [], 0.2)
            if not r:
                continue
            b = os.read(self.fd, 64)
            if not b:
                self.fila.put("esc")
                return
            if b == b"\x1b":
                self.fila.put("esc")
            elif b.startswith(b"\x1b"):
                continue  # setas e outras sequências: nada
            else:
                for ch in b.decode("utf-8", "replace"):
                    self.fila.put(ch)

    def tecla(self, espera=0.0):
        try:
            return self.fila.get(timeout=espera) if espera else self.fila.get_nowait()
        except queue.Empty:
            return None


class Conversa:
    def __init__(self, digitar=False):
        self.tela = Tela()
        self.voz = os.environ.get("VOZ") or shutil.which("voz") or os.path.join(os.path.dirname(EU), "voz")
        self.digitar_sempre = digitar
        self.mudo = os.environ.get("VOZ_FALA") == "nenhum"
        self.sair = False
        self.parar_gravacao = threading.Event()
        self.gravador = Gravador()
        self.transcritor = Transcritor(avisar=lambda t: self.tela.status("… " + t))
        self.falador = None
        self.dica = ""

    # -- as respostas do voz chegam pelo fd VOZ_TELA_FD: "tipo<TAB>texto" (fala, aviso, fim)
    def turno(self, frase, teclado):
        r, w = os.pipe()
        env = dict(os.environ, VOZ_TELA_FD=str(w))
        try:
            p = subprocess.Popen(["bash", self.voz, "--turno", frase], pass_fds=(w,), env=env,
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
        while True:
            self.tela.status("você> " + txt + "▏  (Enter manda · Esc " + ("sai" if self.digitar_sempre else "volta a ouvir") + ")")
            k = teclado.tecla(0.2)
            if k is None:
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
        self.parar_gravacao.clear()
        res = {}
        estado = {"n": 0.0, "f": False}

        def nivel(v, falando):
            estado["n"], estado["f"] = v, falando

        def gravar():
            res["pcm"], res["motivo"] = self.gravador.frase(nivel=nivel, parar=self.parar_gravacao)

        t = threading.Thread(target=gravar, daemon=True)
        t.start()
        while t.is_alive():
            barra = "".join(NIVEL[max(0, min(7, int((estado["n"] * 6 - i) * 8)))] for i in range(6))
            self.tela.status("%s %s  Espaço: terminei · t: digitar · m: %s · Esc: sair"
                             % ("● ouvindo" if estado["f"] else "○ fale", barra, "som" if self.mudo else "mudo"))
            k = teclado.tecla(0.1)
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

    def atualizar_dica(self):
        try:
            self.dica = subprocess.run(["bash", self.voz, "--dica"], capture_output=True, text=True,
                                       timeout=20).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            pass

    def rodar(self):
        self.tela.medir()
        som = not self.digitar_sempre
        if som and not self.gravador.escolher():
            self.tela.linha("nota", "Sem microfone: %s. Digite (t)." % self.gravador.motivo)
            som = False
        self.falador = Falador()
        self.falador.aquecer()
        partes = []
        if som:
            partes.append("ouvir: " + self.gravador.nome)
        with Teclado() as teclado:
            if som:
                if self.transcritor.preparar():
                    partes.append("transcrever: %s (%s)" % (self.transcritor.onde, os.environ.get("VOZ_MODELO", "small")))
                else:
                    self.tela.linha("nota", "Sem reconhecimento de voz: %s. Digite (t), ou rode voz --instalar-audio."
                                    % self.transcritor.motivo)
                    som = False
            partes.append("falar: " + self.falador.det)
            self.tela.linha("nota", " · ".join(partes))
            self.atualizar_dica()
            fim = self.turno("terminal", teclado)
            while not self.sair and not fim:
                if som and not self.digitar_sempre:
                    frase = self.ouvir(teclado)
                    if frase is None:
                        break
                    if frase == "\0t":  # t: digitar esta vez (Esc volta a ouvir)
                        frase = self.digitar(teclado)
                        if not frase:
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
                    if not frase:
                        continue
                    self.tela.linha("voce", frase)
                fim = self.turno(frase, teclado)
                self.atualizar_dica()
            if fim and not self.sair:
                time.sleep(0.6)
        self.transcritor.fechar()
        if self.falador and self.falador.motor:
            self.falador.motor.fechar()
        return 0


def espelho():
    """Celular: a conversa é do Tasker (ele ouve e fala); a janela mostra o conversa.log e deixa digitar."""
    tela = Tela()
    estado = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(CASA, ".local", "state"), "tt-voz")
    log = os.path.join(estado, "conversa.log")
    entrada = os.path.join(os.environ.get("VOZ_SDCARD", "/sdcard"), "Tasker", "voz", "in")
    pos = os.path.getsize(log) if os.path.exists(log) else 0
    tela.linha("nota", "A conversa abre no Tasker (ele ouve e fala). Aqui aparece o que foi dito.")
    with Teclado() as teclado:
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
        linhas.append("gravar: %s" % (g.nome if ok else "✗ " + g.motivo))
    else:
        linhas.append("gravar: candidatos " + ", ".join(n for n, _ in candidatos_gravador()))
    py = python_com("faster_whisper")
    linhas.append("transcrever aqui: %s" % ("faster-whisper em %s (modelo %s)" % (py, os.environ.get("VOZ_MODELO", "small"))
                                            if py else "✗ sem faster-whisper (voz --instalar-audio, ou transcrever noutra máquina)"))
    linhas.append("transcrever em: %s" % " ".join(Transcritor().lugares()))
    f = Falador()
    linhas.append("falar: %s" % f.det)
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
    tela.status("")
    print("\rgravado: %s, %.1f s, pico %d%%" % (motivo, len(pcm) / 2 / TAXA, pico[0] * 100))
    if motivo != "fala":
        print("✗ não ouvi fala (fale mais perto, ou ajuste VOZ_LIMIAR)")
        return 1
    if not t.preparar():
        print("✗ transcrever: " + t.motivo)
        return 1
    txt = t.texto(pcm)
    t.fechar()
    print("ouvi: %s" % (txt or "(nada)"))
    f = Falador()
    if txt and f.qual != "nenhum":
        f.falar("Ouvi: " + txt)
    return 0


def instalar():
    """venv com faster-whisper e Piper, a voz pt-BR do Piper e o modelo do Whisper (em cache)."""
    py = sys.executable
    print("venv em %s" % VENV)
    if not os.path.exists(os.path.join(VENV, "bin", "python")):
        if subprocess.run([py, "-m", "venv", VENV]).returncode != 0:
            print("✗ não consegui criar o venv (no Debian/Ubuntu: sudo apt install python3-venv)")
            return 1
    pip = [os.path.join(VENV, "bin", "python"), "-m", "pip", "install", "-q", "--upgrade"]
    if subprocess.run(pip + ["pip"]).returncode != 0 or subprocess.run(pip + ["faster-whisper", "piper-tts"]).returncode != 0:
        print("✗ pip falhou")
        return 1
    vpy = os.path.join(VENV, "bin", "python")
    os.makedirs(VOZES, exist_ok=True)
    if not os.path.exists(arquivo_voz_piper()):
        print("voz do Piper: %s" % VOZ_PIPER)
        if subprocess.run([vpy, "-m", "piper.download_voices", VOZ_PIPER, "--data-dir", VOZES]).returncode != 0:
            print("✗ não consegui baixar a voz do Piper")
            return 1
    modelo = os.environ.get("VOZ_MODELO", "small")
    print("modelo do Whisper: %s (baixa uma vez para o cache do Hugging Face)" % modelo)
    r = subprocess.run([vpy, "-c", "from faster_whisper import WhisperModel as W; W(%r, device='cpu', "
                        "compute_type='int8')" % modelo])
    if r.returncode != 0:
        print("✗ não consegui carregar o modelo %s" % modelo)
        return 1
    print("✓ pronto: o 🎤 desta máquina transcreve e fala sozinho")
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
