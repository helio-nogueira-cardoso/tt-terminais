"""Transporte falso em PTYs reais: nenhuma rede ou sessão do usuário é acessada."""
import importlib.util
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import struct
import sys
import tempfile
import termios
import time
import unittest

HELPER = sys.argv.pop(1)
spec = importlib.util.spec_from_file_location("tela_recuperar", HELPER)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Tela(unittest.TestCase):
    def setUp(self):
        self.master, self.slave = pty.openpty()
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
        self.before = termios.tcgetattr(self.slave)
        self.proc = None

    def tearDown(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            self.proc.wait(timeout=3)
        os.close(self.master); os.close(self.slave)

    def launch(self, *args):
        self.proc = subprocess.Popen([sys.executable, HELPER, *args], stdin=self.slave,
                                     stdout=self.slave, stderr=self.slave, start_new_session=True)

    def read_until(self, marker, seconds=4):
        out = b""; end = time.monotonic() + seconds
        while time.monotonic() < end:
            ready, _, _ = select.select([self.master], [], [], .05)
            if ready:
                out += os.read(self.master, 65536)
                if marker in out:
                    return out
        self.fail(f"não chegou {marker!r}: {out[-300:]!r}")

    def result(self, expected):
        self.assertEqual(self.proc.wait(timeout=4), expected)
        after = termios.tcgetattr(self.slave)
        before = self.before[:]
        # PENDIN é estado de reprocessamento da fila imposto pelo kernel BSD, não preferência.
        after[3] &= ~getattr(termios, "PENDIN", 0)
        before[3] &= ~getattr(termios, "PENDIN", 0)
        self.assertEqual(after, before)

    def test_tela_limpa_sem_eco_setas_mouse_e_enter(self):
        self.launch("esperar", "--motivo", "Falha simulada")
        first = self.read_until(b"Central")
        self.assertIn(b"\x1b[?1049l", first)
        self.assertFalse(termios.tcgetattr(self.slave)[3] & termios.ECHO)
        os.write(self.master, b"abc\x1b[A\x1b[<0;99;99M")
        ready, _, _ = select.select([self.master], [], [], .15)
        if ready:
            output = os.read(self.master, 65536)
            self.assertNotIn(b"abc", output)
            self.assertNotIn(b"^[[", output)
        self.assertIsNone(self.proc.poll())
        os.write(self.master, b"\r")
        self.result(0)

    def test_colagem_nao_reconecta_nem_sai(self):
        keys = module.Keys()
        self.assertEqual(keys.feed(b"\x1b[200~r\nqn\x1b[20"), [])
        self.assertEqual(keys.feed(b"1~"), [])
        self.assertEqual(keys.feed(b"\x1b[A"), [])
        self.assertEqual(keys.feed(b"\x1b[<0;5;5M"), ["central"])
        self.assertEqual(keys.feed(b"\x1b[<0;5;6M"), ["new"])
        self.assertEqual(keys.feed(b"\x1b[I\x1b[O"), [])

    def test_nova_sessao_exige_opcao_e_escolha(self):
        self.launch("esperar")
        self.read_until(b"Central")
        os.write(self.master, b"n")
        time.sleep(.1)
        self.assertIsNone(self.proc.poll())
        os.write(self.master, b"v")
        self.result(10)
        self.launch("esperar", "--nova")
        self.read_until(b"[N]")
        os.write(self.master, b"\x1b[I\x1b[On")
        self.result(11)

    def test_escape_fragmentado_e_mouse(self):
        keys = module.Keys()
        self.assertEqual(keys.feed(b"\x1b", now=1), [])
        self.assertEqual(keys.feed(b"[<0;10;", now=1.1), [])
        self.assertEqual(keys.feed(b"4M", now=1.2), ["retry"])
        self.assertEqual(keys.feed(b"\x1b", now=2), [])
        self.assertEqual(keys.feed(now=2.4), ["central"])

    def connect(self, script, timeout=".5"):
        self.launch("conectar", "--token", "teste", "--prazo", timeout, "--", sys.executable, "-c", script)
        self.read_until(b"Conectando")

    def test_prazo_sem_primeiro_quadro_inclui_banner(self):
        self.connect("import os,time; os.write(1,b'banner SSH\\n'); time.sleep(10)")
        self.result(124)

    def test_marcador_fragmentado_descarta_teclas_anteriores(self):
        script = ("import os,time,tty; tty.setraw(0); "
                  "os.write(1,b'BANNER'+b'.'*100); time.sleep(.3); "
                  "os.write(1,b'\\x1b]777;tt-conectado;'); time.sleep(.3); "
                  "os.write(1,b'teste\\x07QUADRO'); "
                  "assert os.read(0,1)==b'x'; os.write(1,b'RECEBIDO')")
        self.launch("conectar", "--token", "teste", "--prazo", "3", "--", sys.executable, "-c", script)
        self.read_until(b"BANNER")
        os.write(self.master, b"y")
        self.read_until(b"QUADRO")
        os.write(self.master, b"x")
        self.read_until(b"RECEBIDO")
        self.result(0)

    def test_escape_cancela_handshake_e_restaura_terminal(self):
        self.connect("import time; time.sleep(10)", "5")
        os.write(self.master, b"\x1b")
        self.result(130)

    def test_saida_sem_leitor_nao_bloqueia_prazo(self):
        self.connect("import os,time; os.write(1,b'x'*1000000); time.sleep(10)")
        self.result(124)  # não drena o PTY: até a escrita de restauração precisa de prazo

    def test_cancelamento_durante_escrita_bloqueada(self):
        self.connect("import os,time; os.write(1,b'\\x1b]777;tt-conectado;teste\\x07QUADRO'); "
                     "time.sleep(.1); os.write(1,b'x'*1000000); time.sleep(10)")
        self.read_until(b"QUADRO")
        time.sleep(.2)
        self.proc.terminate()
        self.result(130)

    def test_sinal_na_espera_restaura_terminal(self):
        self.launch("esperar")
        self.read_until(b"Central")
        self.proc.terminate()
        self.result(130)

    def test_sessao_conectada_ociosa_nao_expira_teclas_chegam(self):
        script = ("import os,time,tty; tty.setraw(0); "
                  "os.write(1,b'\\x1b]777;tt-conectado;teste\\x07QUADRO'); "
                  "time.sleep(1); os.write(1,b'PRONTO'); "
                  "assert os.read(0,1)==b'x'; os.write(1,b'RECEBIDO')")
        self.connect(script)
        self.read_until(b"PRONTO")
        self.assertIsNone(self.proc.poll())
        os.write(self.master, b"x")
        self.read_until(b"RECEBIDO")
        self.result(0)

    def test_sigterm_encerra_so_grupo_da_tentativa(self):
        with tempfile.TemporaryDirectory() as directory:
            pidfile = Path(directory) / "filho"
            script = ("import os,time; from pathlib import Path; "
                      f"Path({str(pidfile)!r}).write_text(str(os.getpid())); "
                      "time.sleep(30)")
            self.connect(script, "5")
            end = time.monotonic() + 3
            while not pidfile.exists() and time.monotonic() < end:
                time.sleep(.02)
            self.assertTrue(pidfile.exists())
            pid = int(pidfile.read_text())
            self.proc.terminate()
            self.result(130)
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)


if __name__ == "__main__":
    unittest.main()
