"""Reconcilia o fallback local do Tailscale no macOS, sem login nem prompts."""
import fcntl
import http.client
import os
from pathlib import Path
import plistlib
import pwd
import shutil
import subprocess
import sys
import tempfile
import time

SERVICES = {"com.tailscale.tt-ws-control": 18743,
            "com.tailscale.tt-ws-control80": 80, "com.tailscale.tt-ws-derp": 18744}
PROXY = {"HTTP_PROXY": "http://127.0.0.1:18744", "HTTPS_PROXY": "http://127.0.0.1:18744",
         "TS_DEBUG_USE_DERP_HTTP": "true", "TS_USE_CONTROL_DIAL_PLAN": "false"}


class Pending(RuntimeError):
    pass


def run(*args, check=True, timeout=30):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True,
                            timeout=timeout, stdin=subprocess.DEVNULL)
    if check and result.returncode:
        # Não inclui argumentos/ambiente nem saída arbitrária de programas no log.
        command = "sudo " + " ".join(str(a) for a in args[2:4]) if args[0] == "sudo" else Path(str(args[0])).name
        raise Pending(f"{command} falhou (código {result.returncode})")
    return result


def read_plist(path):
    return plistlib.loads(path.read_bytes()) if path.exists() else {}


def bridge_alive(port):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=1)
    try:
        connection.request("GET", "/tt-health")
        response = connection.getresponse()
        return response.status == 200 and response.read(64) == b"tt-tailscale-ws\n"
    except (OSError, http.client.HTTPException):
        return False
    finally:
        connection.close()


class Manager:
    def __init__(self, source):
        self.source = Path(source)
        self.plists = Path("/Library/LaunchDaemons")
        # A compatibilidade na porta 80 roda como root: código instalado pertence ao root.
        self.data = Path("/Library/Application Support/tt-tailscale-ws")
        self.state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "tt/tailscale-ws"
        self.user = pwd.getpwuid(os.getuid()).pw_name
        self.changed = []
        self.before = {}
        self.loaded_before = set()
        self.work = None

    def launch(self, *args, check=True):
        return run("sudo", "-n", "launchctl", *args, check=check)

    def loaded(self, label):
        return run("launchctl", "print", "system/" + label, check=False).returncode == 0

    def running(self, label):
        result = run("launchctl", "print", "system/" + label, check=False)
        return result.returncode == 0 and "state = running" in result.stdout

    def daemon_path(self):
        for name in ("com.tailscale.tailscaled", "homebrew.mxcl.tailscale"):
            path = self.plists / (name + ".plist")
            if path.exists():
                return path
        return self.plists / "com.tailscale.tailscaled.plist"

    def dependencies(self):
        node, daemon = shutil.which("node"), shutil.which("tailscaled")
        node_ok = node and run(node, "-e", "process.exit(typeof WebSocket === 'function' ? 0 : 1)", check=False).returncode == 0
        if node_ok and daemon:
            return node, daemon
        brew = shutil.which("brew")
        if not brew:
            raise Pending("faltam Node.js com WebSocket nativo/tailscaled; instale Homebrew para o tt completar")
        packages = ([] if node_ok else ["node"]) + ([] if daemon else ["tailscale"])
        run(brew, "install", *packages, timeout=180)
        prefix = run(brew, "--prefix").stdout.strip()
        if not node_ok:
            node = str(Path(prefix) / "bin/node")
        daemon = daemon or str(Path(prefix) / "bin/tailscaled")
        if run(node, "-e", "process.exit(typeof WebSocket === 'function' ? 0 : 1)", check=False).returncode:
            raise Pending("Node.js instalado não oferece WebSocket nativo")
        if not Path(daemon).is_file():
            raise Pending("tailscaled não encontrado após instalar Homebrew tailscale")
        return node, daemon

    def write(self, path, content, mode="644"):
        """Troca atômica; guarda o primeiro conteúdo para reversão desta rodada."""
        previous = path.read_bytes() if path.exists() else None
        if previous == content:
            return False
        if path not in self.before:
            self.before[path] = previous
        stage = self.work / "arquivo"
        stage.write_bytes(content)
        run("sudo", "-n", "install", "-o", "root", "-g", "wheel", "-m", mode, stage, str(path) + ".tt-novo")
        run("sudo", "-n", "mv", str(path) + ".tt-novo", path)
        return True

    def reload(self, label, path):
        if label not in self.changed:
            if self.loaded(label):
                self.loaded_before.add(label)
            self.changed.append(label)
        if self.loaded(label):
            self.unload(label)
        self.launch("enable", "system/" + label)
        self.launch("bootstrap", "system", path)

    def unload(self, label):
        self.launch("bootout", "system/" + label)
        # bootout pode voltar com o processo ainda em SIGTERMed. Enquanto existir no
        # domínio, bootstrap falha com código 5, mesmo com um plist válido.
        for _ in range(120):
            if not self.loaded(label):
                return
            time.sleep(0.25)
        raise Pending(f"{label} ainda está encerrando; a próxima garantia tentará novamente")

    def rollback(self):
        for label in reversed(self.changed):
            if self.loaded(label):
                self.unload(label)
        for path, content in self.before.items():
            if content is None:
                run("sudo", "-n", "rm", "-f", path, check=False)
            else:
                self.write(path, content)
        for label in self.loaded_before:
            self.launch("bootstrap", "system", self.plists / (label + ".plist"), check=False)

    def bridge_plist(self, label, port, node):
        data = {"Label": label, "ProgramArguments": [node, str(self.data / "bridge.cjs")],
                "EnvironmentVariables": {"BRIDGE_PORT": str(port), "NODE_EXTRA_CA_CERTS": str(self.data / "system-ca.pem")},
                "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 10,
                "StandardOutPath": str(self.state / (label + ".log")),
                "StandardErrorPath": str(self.state / (label + ".err.log"))}
        if port != 80:
            data["UserName"] = self.user
        return data

    def activate(self):
        run("sudo", "-n", "true")
        node, daemon = self.dependencies()
        path = self.daemon_path()
        current = read_plist(path)
        # Preserva argumentos (--state, --socket…), logs e escolhas do serviço existente.
        desired = dict(current) if current else {
            "Label": path.stem, "ProgramArguments": [daemon], "RunAtLoad": True}
        args = desired.get("ProgramArguments", [daemon])
        if not Path(args[0]).is_file():
            desired["ProgramArguments"] = [daemon, *args[1:]]
        desired["EnvironmentVariables"] = {**current.get("EnvironmentVariables", {}), **PROXY}
        certs = run("security", "find-certificate", "-a", "-p", "/Library/Keychains/System.keychain").stdout
        run("sudo", "-n", "install", "-d", "-o", "root", "-g", "wheel", "-m", "755", self.data)
        backup = self.data / "tailscaled.antes-ws.plist"
        if current and not any(current.get("EnvironmentVariables", {}).get(k) == v for k, v in PROXY.items()) and not backup.exists():
            self.write(backup, plistlib.dumps(current))
        runtime_changed = self.write(self.data / "bridge.cjs", (self.source / "tailscale-ws-bridge.cjs").read_bytes())
        ca_changed = self.write(self.data / "system-ca.pem", certs.encode())
        for label, port in SERVICES.items():
            bridge_path = self.plists / (label + ".plist")
            changed = self.write(bridge_path, plistlib.dumps(self.bridge_plist(label, port, node)))
            if changed or runtime_changed or ca_changed or not self.loaded(label) or not bridge_alive(port):
                self.reload(label, bridge_path)
        # Só aponta o daemon ao proxy depois que TODOS os listeners responderem como bridge.
        for _ in range(20):
            if all(bridge_alive(port) for port in SERVICES.values()):
                break
            time.sleep(0.25)
        else:
            raise Pending("bridge não respondeu nas portas 80/18743/18744; configuração anterior restaurada")
        daemon_changed = current != desired and self.write(path, plistlib.dumps(desired))
        # Bridge/CA novos exigem uma conexão nova: o daemon pode ter memorizado a
        # falha anterior e estar tentando só o transporte bloqueado pela rede.
        if daemon_changed or runtime_changed or ca_changed or not self.running(desired["Label"]):
            self.reload(desired["Label"], path)
        for _ in range(20):
            if self.running(desired["Label"]):
                break
            time.sleep(0.25)
        else:
            raise Pending("tailscaled não carregou; configuração anterior restaurada")
        return "ativo; serviços e listeners conferidos" if self.changed else "ativo; nenhuma alteração necessária"

    def deactivate(self):
        run("sudo", "-n", "true")
        path = self.daemon_path()
        current = read_plist(path)
        if current:
            env = current.get("EnvironmentVariables", {})
            previous = read_plist(self.data / "tailscaled.antes-ws.plist").get("EnvironmentVariables", {})
            # Backups antigos podem conter o próprio proxy: remove somente os valores do tt.
            for key, value in PROXY.items():
                if env.get(key) == value:
                    if key in previous and previous[key] != value:
                        env[key] = previous[key]
                    else:
                        env.pop(key)
            if env:
                current["EnvironmentVariables"] = env
            else:
                current.pop("EnvironmentVariables", None)
            if self.write(path, plistlib.dumps(current)):
                self.reload(current["Label"], path)
        for label in SERVICES:
            if self.loaded(label):
                self.unload(label)
            self.launch("disable", "system/" + label)
        return "desativado até a próxima garantia automática no Mac (TT_TAILSCALE_WS_AUTO=0 suspende o reforço)"

    def status(self):
        failures = []
        for label, port in SERVICES.items():
            if not self.loaded(label) or not bridge_alive(port):
                failures.append(f"{label}:{port}")
        data = read_plist(self.daemon_path())
        if not self.running(data.get("Label", "com.tailscale.tailscaled")) or any(
                data.get("EnvironmentVariables", {}).get(k) != v for k, v in PROXY.items()):
            failures.append("configuração/serviço tailscaled")
        return (False, "pendente: " + ", ".join(failures)) if failures else (True, "ativo; serviços e listeners conferidos")

    def reconcile(self, action):
        self.changed, self.before, self.loaded_before = [], {}, set()
        self.state.mkdir(parents=True, exist_ok=True)
        with (self.state / "garantir.lock").open("a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return "outra verificação em andamento"
            with tempfile.TemporaryDirectory(prefix="tt-ws-") as temporary:
                self.work = Path(temporary)
                try:
                    return self.deactivate() if action in ("desativar", "off", "disable") else self.activate()
                except Exception:
                    self.rollback()
                    raise


def main():
    source, action = sys.argv[1:3]
    if sys.platform != "darwin":
        print("não se aplica: fallback WebSocket automático é exclusivo do macOS")
        return 0
    if action not in ("garantir", "ativar", "on", "enable", "desativar", "off", "disable", "status", "testar", "test"):
        print("uso: tt --tailscale-ws garantir|ativar|desativar|status|testar", file=sys.stderr)
        return 2
    # Dupla barreira: suites com HOME/TT_RT isolado jamais administram LaunchDaemons do hospedeiro.
    actual_home = Path(pwd.getpwuid(os.getuid()).pw_dir)
    if os.environ.get("TT_RT") or Path.home().resolve() != actual_home.resolve():
        print("ignorado: ambiente isolado")
        return 0
    manager = Manager(source)
    try:
        if action in ("status", "testar", "test"):
            ok, message = manager.status()
            print(message)
            return 0 if ok else 1
        message = manager.reconcile(action)
        manager.state.joinpath("estado").write_text(message + "\n")
        print(message)
        return 0
    except (OSError, ValueError, Pending, subprocess.TimeoutExpired) as error:
        message = f"pendente: {error}"
        manager.state.mkdir(parents=True, exist_ok=True)
        manager.state.joinpath("estado").write_text(message + "\n")
        print(message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
