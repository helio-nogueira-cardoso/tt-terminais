#!/usr/bin/env python3
"""Recuperação de transporte do tt; só stdlib, PTY próprio, nenhuma sessão tmux encerrada.

esperar: 0 tenta novamente; 10 abre central; 11 nova sessão; 130 terminal fechado.
conectar: prazo somente até marcador + primeira saída do destino; sessão ociosa não expira.
O processo filho é uma sessão Unix própria: cancelamento mata apenas esta tentativa.
"""
import argparse
import errno
import fcntl
import os
import pty
import re
import select
import signal
import sys
import termios
import time
import tty

RESET = (b"\x1b[?2026l\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l"
         b"\x1b[?1004l\x1b[?2004l\x1b[?1049l\x1b[?7h\x1b[0m\x1b[r\x1b[?25h")
output_check = lambda: None


class Finish(Exception):
    def __init__(self, code):
        self.code = code


def write(data, fd=1):
    if isinstance(data, str):
        data = data.encode()
    while data:
        output_check()
        try:
            data = data[os.write(fd, data):]
        except BlockingIOError:
            select.select([], [fd], [], .1)


def read_input():
    try:
        return os.read(0, 65536)
    except BlockingIOError:
        return None


class Terminal:
    def __init__(self, check):
        self.check = check

    def __enter__(self):
        global output_check
        self.old = termios.tcgetattr(0)
        self.flags = fcntl.fcntl(1, fcntl.F_GETFL)
        self.previous_check = output_check
        output_check = self.check
        fcntl.fcntl(1, fcntl.F_SETFL, self.flags | os.O_NONBLOCK)
        tty.setraw(0, termios.TCSANOW)
        termios.tcflush(0, termios.TCIFLUSH)
        try:
            write(RESET + b"\x1b[2J\x1b[H")
        except BaseException:
            self.__exit__()
            raise
        return self

    def __exit__(self, *args):
        global output_check
        until = time.monotonic() + .2
        def cleanup_check():
            if time.monotonic() >= until:
                raise Finish(130)
        output_check = cleanup_check
        try:
            write(RESET)
        except (OSError, Finish):
            pass
        finally:
            # TCSAFLUSH também espera a saída escoar: PTY sem leitor não pode prender a saída.
            try:
                termios.tcflush(0, termios.TCIFLUSH)
                termios.tcsetattr(0, termios.TCSANOW, self.old)
            finally:
                fcntl.fcntl(1, fcntl.F_SETFL, self.flags)
                output_check = self.previous_check


class Keys:
    """Consome teclas especiais inteiras e colagem, inclusive fragmentadas; nunca ecoa."""
    def __init__(self):
        self.buf = b""
        self.paste = False
        self.since = 0

    def feed(self, data=b"", now=None):
        now = time.monotonic() if now is None else now
        if data and not self.buf:
            self.since = now
        self.buf += data
        actions = []
        while self.buf:
            if self.paste:
                end = self.buf.find(b"\x1b[201~")
                if end < 0:
                    self.buf = self.buf[-5:]
                    break
                self.buf = self.buf[end + 6:]
                self.paste = False
                continue
            if self.buf.startswith(b"\x1b[200~"):
                self.buf = self.buf[6:]
                self.paste = True
                continue
            if self.buf.startswith(b"\x1b"):
                if self.buf == b"\x1b":
                    if now - self.since < .3:
                        break
                    self.buf = b""
                    actions.append("central")
                    continue
                if self.buf.startswith((b"\x1b[", b"\x1bO")):
                    match = re.match(rb"\x1b(?:\[[0-?]*[ -/]*[@-~]|O.)", self.buf)
                    if not match:
                        if now - self.since > .5 or len(self.buf) > 4096:
                            self.buf = b""  # sequência incompleta não vira letra/Enter
                        break
                    seq = match.group()
                    mouse = re.fullmatch(rb"\x1b\[<0;(\d+);(\d+)M", seq)
                    if mouse:
                        x, y = map(int, mouse.groups())
                        if y == 4 and 1 <= x <= 24:
                            actions.append("retry")
                        elif y == 5 and 1 <= x <= 24:
                            actions.append("central")
                        elif y == 6 and 1 <= x <= 24:
                            actions.append("new")
                    self.buf = self.buf[len(seq):]
                    continue
                self.buf = self.buf[2:]  # Alt+tecla não executa a tecla solta
                continue
            key, self.buf = self.buf[:1], self.buf[1:]
            if key in (b"r", b"R", b"\r", b"\n"):
                actions.append("retry")
            elif key in (b"v", b"V", b"q", b"Q", b"\x03"):
                actions.append("central")
            elif key in (b"n", b"N"):
                actions.append("new")
        return actions


def esperar(title, reason, allow_new=False):
    def render():
        width = os.get_terminal_size(1).columns or 80
        def line(text):
            return "".join(c for c in text if c.isprintable())[:max(1, width - 1)] + "\r\n"
        # Sem quebra automática: caracteres largos não deslocam as linhas clicáveis.
        write(b"\x1b[2J\x1b[H\x1b[?7l\x1b[?1000h\x1b[?1006h\x1b[?2004h")
        write(line(title) + line(reason) + "\r\n" + line("[R / Enter] Reconectar") +
              line("[V / Esc]   Central") + (line("[N]         Nova sessão") if allow_new else "") +
              "\r\n" + line("Saída local: Ctrl+B Esc"))
    resize = [True]
    stopped = [False]
    handlers = {signal.SIGWINCH: signal.signal(signal.SIGWINCH, lambda *_: resize.__setitem__(0, True))}
    for sig in (signal.SIGTERM, signal.SIGHUP):
        handlers[sig] = signal.signal(sig, lambda *_: stopped.__setitem__(0, True))
    keys = Keys()
    def check():
        if stopped[0]:
            raise Finish(130)
    try:
        with Terminal(check):
            while True:
                if stopped[0]:
                    return 130
                if resize[0]:
                    render(); resize[0] = False
                ready, _, _ = select.select([0], [], [], .1 if keys.buf else 1)
                data = read_input() if ready else b""
                if data is None:
                    continue
                if ready and not data:
                    return 130
                actions = [action for action in keys.feed(data) if allow_new or action != "new"]
                if actions:
                    return {"retry": 0, "central": 10, "new": 11}[actions[0]]
    except Finish as exc:
        return exc.code
    finally:
        for sig, handler in handlers.items():
            signal.signal(sig, handler)


def stop_child(pid):
    # Não esperar pipes herdados por netos. O grupo é exclusivo da tentativa (pty.fork).
    for sig, delay in ((signal.SIGTERM, .5), (signal.SIGKILL, .5)):
        try:
            os.killpg(pid, sig)
        except (ProcessLookupError, PermissionError):
            # Darwin também pode devolver EPERM para um grupo já desfeito após waitpid.
            break
        end = time.monotonic() + delay
        while time.monotonic() < end:
            try:
                done, _ = os.waitpid(pid, os.WNOHANG)
            except ChildProcessError:
                done = pid
            if done:
                # Mesmo com o líder encerrado pode haver neto segurando terminal/SSH.
                break
            time.sleep(.02)
        if sig == signal.SIGTERM:
            continue
    try:
        os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        pass


def conectar(command, token, deadline):
    marker = ("\x1b]777;tt-conectado;" + token + "\x07").encode()
    pid, master = pty.fork()
    if pid == 0:
        try:
            os.execvp(command[0], command)
        except OSError:
            os._exit(127)
    os.set_blocking(master, False)
    stopped = [False]
    handlers = {}
    def resize(*_):
        try:
            fcntl.ioctl(master, termios.TIOCSWINSZ, fcntl.ioctl(0, termios.TIOCGWINSZ, b"\0" * 8))
        except OSError:
            pass
    for sig in (signal.SIGTERM, signal.SIGHUP):
        handlers[sig] = signal.signal(sig, lambda *_: stopped.__setitem__(0, True))
    handlers[signal.SIGWINCH] = signal.signal(signal.SIGWINCH, resize)
    ready, saw_marker, buffer = False, False, b""
    start = time.monotonic()
    keys = Keys()
    def check():
        if stopped[0]:
            raise Finish(130)
        if not ready and time.monotonic() - start >= deadline:
            raise Finish(124)
    try:
        with Terminal(check):
            resize()
            write("Conectando… Esc cancela; Ctrl+B Esc abre a central.\r\n")
            while True:
                if stopped[0]:
                    return 130
                if not ready and time.monotonic() - start >= deadline:
                    return 124
                fds, _, _ = select.select([0, master], [], [], .1 if not ready else 1)
                if master in fds:
                    try:
                        block = os.read(master, 65536)
                    except BlockingIOError:
                        continue
                    except OSError as exc:
                        if exc.errno != errno.EIO:
                            raise
                        block = b""
                    if not block:
                        # No BSD o EOF do PTY pode chegar antes do estado de saída do filho.
                        # Espera limitada: um neto com descritor herdado nunca prende a tela.
                        end = time.monotonic() + .5
                        done, status = os.waitpid(pid, os.WNOHANG)
                        while not done and time.monotonic() < end:
                            time.sleep(.01)
                            done, status = os.waitpid(pid, os.WNOHANG)
                        return os.WEXITSTATUS(status) if done and os.WIFEXITED(status) else 125
                    if not saw_marker:
                        buffer += block
                        at = buffer.find(marker)
                        if at >= 0:
                            write(buffer[:at]); block = buffer[at + len(marker):]
                            buffer = b""; saw_marker = True
                        else:
                            # Guarda apenas o sufixo que pode conter um marcador fragmentado.
                            keep = min(len(buffer), len(marker) - 1)
                            write(buffer[:-keep] if keep else buffer)
                            buffer = buffer[-keep:] if keep else b""
                            block = b""
                    if saw_marker and block:
                        if not ready:
                            termios.tcflush(0, termios.TCIFLUSH)
                            if 0 in fds:
                                fds.remove(0)
                        ready = True
                        write(block)
                if 0 in fds:
                    data = read_input()
                    if data is None:
                        continue
                    if not data:
                        return 130
                    if ready:
                        write(data, master)
                    elif "central" in keys.feed(data):
                        return 130
                elif not ready and "central" in keys.feed():
                    return 130
                done, status = os.waitpid(pid, os.WNOHANG)
                if done:
                    return os.WEXITSTATUS(status) if os.WIFEXITED(status) else 130
    except Finish as exc:
        return exc.code
    finally:
        stop_child(pid)
        os.close(master)
        for sig, handler in handlers.items():
            signal.signal(sig, handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("esperar", "conectar"))
    parser.add_argument("--titulo", default="Conexão interrompida")
    parser.add_argument("--motivo", default="A sessão foi preservada.")
    parser.add_argument("--token", default="")
    parser.add_argument("--prazo", type=float, default=20)
    parser.add_argument("--nova", action="store_true")
    args, cmd = parser.parse_known_args()
    if not os.isatty(0) or not os.isatty(1):
        print("tt: recuperação interativa precisa de um terminal", file=sys.stderr)
        return 130
    if args.mode == "esperar":
        return esperar(args.titulo, args.motivo, args.nova)
    if cmd[:1] == ["--"]:
        cmd.pop(0)
    if not cmd or not re.fullmatch(r"[a-zA-Z0-9-]{1,96}", args.token) or not 0 < args.prazo <= 120:
        parser.error("comando, token ou prazo inválido")
    return conectar(cmd, args.token, args.prazo)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, KeyboardInterrupt):
        sys.exit(130)
