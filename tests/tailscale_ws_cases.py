"""Contrato de instalação com launchctl/sudo simulados; nunca alcança o sistema."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("ws", ROOT / "tailscale-ws.py")
ws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ws)


class Installation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.manager = ws.Manager(ROOT)
        self.manager.plists = self.base / "plists"
        self.manager.data = self.base / "data"
        self.manager.state = self.base / "state"
        self.manager.plists.mkdir()
        self.live = set()
        self.stopping = {}
        self.stop_delay = 0
        self.calls = []
        self.fail = None
        self.healthy = True
        for p in (patch.object(ws, "run", self.fake_run), patch.object(ws, "bridge_alive", lambda port: self.healthy and self.label(port) in self.live),
                  patch.object(ws.time, "sleep"), patch.object(self.manager, "dependencies", return_value=(sys.executable, sys.executable))):
            p.start()
            self.addCleanup(p.stop)

    def label(self, port):
        return next(k for k, v in ws.SERVICES.items() if v == port)

    def fake_run(self, *args, check=True, timeout=30):
        args = [str(a) for a in args]
        self.calls.append(args)
        if args[0] == "sudo":
            self.assertEqual(args[1], "-n")
            args = args[2:]
        rc, output = 0, ""
        if args[0] == "launchctl":
            verb = args[1]
            if verb == "print":
                label = args[2].split("/", 1)[1]
                if self.stopping.get(label):
                    self.stopping[label] -= 1
                    if not self.stopping[label]:
                        self.live.discard(label)
                rc = int(label not in self.live)
                output = "state = running\n" if not rc else ""
            elif verb == "bootstrap":
                path = Path(args[3])
                self.assertTrue(path.is_file(), f"bootstrap recebeu arquivo inexistente: {path}")
                data = ws.read_plist(path)
                self.assertNotIn(data["Label"], self.live, "bootstrap antes do fim do bootout")
                if data["Label"] == self.fail:
                    self.fail = None
                    rc = 5
                else:
                    self.assertEqual(path.name, data["Label"] + ".plist")
                    self.live.add(data["Label"])
            elif verb == "bootout":
                label = args[2].split("/", 1)[1]
                if self.stop_delay:
                    self.stopping[label] = self.stop_delay
                else:
                    self.live.discard(label)
        elif args[0] == "install":
            if "-d" in args:
                Path(args[-1]).mkdir(parents=True, exist_ok=True)
            else:
                shutil.copyfile(args[-2], args[-1])
        elif args[0] == "mv":
            os.replace(args[1], args[2])
        elif args[0] == "rm":
            Path(args[-1]).unlink(missing_ok=True)
        elif args[0] == "security":
            output = "certificate\n"
        elif args[0] != "true":
            self.failTest(f"comando inesperado {args[0]}")
        if check and rc:
            raise ws.Pending("falha simulada")
        return subprocess.CompletedProcess(args, rc, output, "")

    def bootstraps(self):
        return [c[-1] for c in self.calls if "bootstrap" in c]

    def existing(self, name="com.tailscale.tailscaled"):
        self.original = {"Label": name, "ProgramArguments": [sys.executable, "--state=/custom/state"],
                         "RunAtLoad": True, "EnvironmentVariables": {"CUSTOM": "preservado"}}
        path = self.manager.plists / (name + ".plist")
        path.write_bytes(plistlib.dumps(self.original))
        self.live.add(name)
        return path

    def test_install_and_repeat(self):
        path = self.existing()
        self.manager.reconcile("garantir")
        self.assertEqual(len(self.bootstraps()), 4)
        self.assertEqual(ws.read_plist(path)["ProgramArguments"], self.original["ProgramArguments"])
        self.assertEqual(ws.read_plist(path)["EnvironmentVariables"]["CUSTOM"], "preservado")
        before = list(self.bootstraps())
        self.manager.changed.clear()
        self.manager.before.clear()
        self.manager.reconcile("garantir")
        self.assertEqual(self.bootstraps(), before)
        self.assertTrue(self.manager.status()[0])

    def test_fallen_bridge_only(self):
        self.manager.reconcile("garantir")
        self.live.remove(self.label(18744))
        self.calls.clear()
        self.manager.reconcile("garantir")
        self.assertEqual(self.bootstraps(), [str(self.manager.plists / (self.label(18744) + ".plist"))])

    def test_waits_for_service_exit(self):
        self.manager.reconcile("garantir")
        self.stop_delay = 3
        (self.manager.data / "bridge.cjs").unlink()
        self.manager.reconcile("garantir")
        self.assertTrue(self.manager.status()[0])

    def test_bridge_update_reconnects_daemon_once(self):
        self.manager.reconcile("garantir")
        self.calls.clear()
        (self.manager.data / "bridge.cjs").write_text("old bridge")
        self.manager.reconcile("garantir")
        self.assertEqual(len(self.bootstraps()), 4)
        self.calls.clear()
        self.manager.reconcile("garantir")
        self.assertEqual(self.bootstraps(), [])

    def test_bootstrap_failure_rolls_back(self):
        path = self.existing()
        self.fail = self.label(18744)
        with self.assertRaises(ws.Pending):
            self.manager.reconcile("garantir")
        self.assertEqual(ws.read_plist(path), self.original)
        self.assertEqual(self.live, {self.original["Label"]})

    def test_dead_listener_does_not_switch_daemon(self):
        path = self.existing()
        self.healthy = False
        with self.assertRaises(ws.Pending):
            self.manager.reconcile("garantir")
        self.assertEqual(ws.read_plist(path), self.original)
        self.assertFalse(any("tailscaled.plist" in p for p in self.bootstraps()))

    def test_daemon_failure_rolls_back(self):
        path = self.existing()
        self.fail = self.original["Label"]
        with self.assertRaises(ws.Pending):
            self.manager.reconcile("garantir")
        self.assertEqual(ws.read_plist(path), self.original)
        self.assertIn(self.original["Label"], self.live)

    def test_homebrew_daemon_preserved(self):
        path = self.existing("homebrew.mxcl.tailscale")
        self.manager.reconcile("garantir")
        self.assertEqual(self.manager.daemon_path(), path)
        self.assertFalse((self.manager.plists / "com.tailscale.tailscaled.plist").exists())

    def test_disable_strips_contaminated_backup(self):
        path = self.existing()
        self.manager.reconcile("garantir")
        Path(str(path) + ".antes-ws").write_bytes(path.read_bytes())
        self.manager.reconcile("desativar")
        self.assertEqual(ws.read_plist(path), self.original)
        self.assertFalse(set(ws.SERVICES) & self.live)

    def test_sudo_denied_no_writes(self):
        with patch.object(ws, "run", side_effect=ws.Pending("sudo indisponível")):
            with self.assertRaises(ws.Pending):
                self.manager.reconcile("garantir")
        self.assertEqual(list(self.manager.plists.iterdir()), [])

    def test_disable_restores_previous_proxy(self):
        path = self.existing()
        self.original["EnvironmentVariables"]["HTTPS_PROXY"] = "http://proxy.example:8080"
        path.write_bytes(plistlib.dumps(self.original))
        self.manager.reconcile("garantir")
        self.manager.reconcile("desativar")
        self.assertEqual(ws.read_plist(path), self.original)

    def test_linux_and_isolated_mac_never_touch_launchd(self):
        for system in ("linux", "darwin"):
            self.calls.clear()
            with patch.object(ws.sys, "platform", system), patch.object(ws.sys, "argv", ["ws", str(ROOT), "garantir"]), \
                    patch.dict(os.environ, {"TT_RT": str(self.base)}), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(ws.main(), 0)
            self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
