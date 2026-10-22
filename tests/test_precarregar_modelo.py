#!/usr/bin/env python3
import importlib.util
import base64
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
spec = importlib.util.spec_from_file_location("pre", Path(__file__).resolve().parents[1] / "precarregar-tt.py")
pre = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pre)


class Heuristica(unittest.TestCase):
    def setUp(self):
        self.target = {"machine": "dell", "name": "tarefa", "id": "a" * 32}
        self.now = 1000000

    def score(self, index, history=None, intent=None):
        return pre.rank(self.target, index, history or [], "origem", intent, self.now)[0]

    def test_esquerda_e_fixada_sao_sinais(self):
        self.assertGreater(self.score(0), self.score(1))
        self.assertGreater(self.score(1), self.score(12))
        self.assertGreater(self.score(12), self.score(None))

    def test_adaptativa_pode_superar_primeira_fixada(self):
        visits = [{"to": pre.identity(self.target), "from": "origem", "time": self.now - i}
                  for i in range(10)]
        self.assertGreater(self.score(None, visits), self.score(0))
        for v in visits:
            v["time"] -= 8 * 86400
        self.assertEqual(self.score(None, visits), 0)

    def test_intencao_precisa_estabilizar_e_expira(self):
        intent = {"key": pre.identity(self.target), "time": self.now - .1}
        self.assertEqual(self.score(None, intent=intent), 0)
        intent["time"] = self.now - .5
        self.assertGreater(self.score(None, intent=intent), self.score(0))
        intent["time"] = self.now - 10
        self.assertEqual(self.score(None, intent=intent), 0)

    def test_identidade_nao_depende_do_nome(self):
        other = dict(self.target, name="renomeada")
        self.assertEqual(pre.identity(self.target), pre.identity(other))

    def test_resolver_nao_recicla_id_de_servidor_reiniciado(self):
        out = pre.SEP.join(["$1", "200", "tarefa", "a" * 32, ""]) + "\n"
        with patch.object(pre.protocol, "tmux", return_value=(0, out)):
            self.assertIsNone(pre.protocol.remote_target("tarefa", "a" * 32, {"sid": "$1", "server": "100"}))
            self.assertIsNotNone(pre.protocol.remote_target("nome-antigo", "a" * 32))
            self.assertIsNone(pre.protocol.remote_target("tarefa", "b" * 32))

    def test_limites_energia_e_modo_off(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)), \
                patch.object(pre, "read_config", return_value={"precarregar": "auto"}), \
                patch.dict(pre.os.environ, {"TT_PRECARREGAR": "auto", "PREFIX": ""}), \
                patch.object(pre, "battery", return_value=(15, False)):
            c = pre.Coordinator(Path(d))
            self.assertEqual(c.settings(), ("auto", 2, 1))
            c.energy = (5, False)
            self.assertEqual(c.settings()[1], 0)
            c.energy = (90, True)
            self.assertEqual(c.settings()[1:], (6, 3))
            with patch.dict(pre.os.environ, {"TT_PRECARREGAR": "0"}):
                self.assertEqual(c.settings()[1], 0)

    def test_backoff_e_cancelamento_nao_gravam_uso(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)):
            c = pre.Coordinator(Path(d))
            item = {"target": self.target}
            c.failure(item, "sem rede", machine=True)
            first = c.failures["dell"]["until"]
            c.failure(item, "sem rede", machine=True)
            self.assertGreater(c.failures["dell"]["until"], first)
            c.requests["tela"] = {"key": "antigo"}
            c.handle({"op": "cancel", "client": "tela"})
            self.assertFalse(c.requests)
            self.assertFalse(c.history)

    def test_runtime_privado_e_socket_curto(self):
        with patch.dict(pre.os.environ, {"TMUX": "/tmp/so-modelo,1,0"}):
            folder = pre.runtime()
            self.assertLess(len(str(folder / "socket")), 100)
            self.assertEqual(folder.stat().st_mode & 0o077, 0)
            with pre.socket.socket(pre.socket.AF_UNIX, pre.socket.SOCK_STREAM) as listener:
                listener.bind(str(folder / "socket"))
            (folder / "socket").unlink()
            folder.rmdir()

    def test_runtime_sem_tmp_global_usa_temporario_do_sistema(self):
        with tempfile.TemporaryDirectory() as d, \
                patch.dict(pre.os.environ, {"TMUX": "/socket-termux,1,0"}), \
                patch.object(pre.os, "access", return_value=False), \
                patch.object(pre.tempfile, "gettempdir", return_value=d):
            folder = pre.runtime()
            self.assertEqual(folder.parent, Path(d))
            self.assertEqual(folder.stat().st_mode & 0o077, 0)

    def test_status_sem_tmux_nao_inicia_servidor_nem_coordenador(self):
        with patch.object(pre, "runtime", side_effect=pre.TmuxUnavailable), \
                patch.dict(pre.os.environ, {"TT_PRECARREGAR": "1"}), \
                patch.object(pre, "read_config", return_value={"precarregar": "auto"}), \
                patch.object(pre.subprocess, "Popen") as spawn:
            with patch("sys.stdout", new_callable=io.StringIO) as out:
                self.assertEqual(pre.main(["status"]), 0)
                self.assertEqual(json.loads(out.getvalue())["coordenador"], "parado")
            with patch("sys.stdout", new_callable=io.StringIO) as out:
                self.assertEqual(pre.main(["status-text"]), 0)
                self.assertIn("aguardando sessão tmux", out.getvalue())
            self.assertEqual(pre.main(["stop"]), 0)
            self.assertEqual(pre.main(["evento"]), 0)
            self.assertEqual(pre.main(["navigate", "tela", "dell", "sessão"]), 1)
            spawn.assert_not_called()

    def test_reordenar_fixadas_muda_prioridade_sem_mudar_identidade(self):
        other = dict(self.target, name="outra", id="b" * 32)
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)):
            c = pre.Coordinator(Path(d))
            with patch.object(c, "fixed", return_value=[self.target, other]), \
                    patch.object(c, "machines", return_value={"dell": "u@dell"}):
                before = c.ranking("tela")
            with patch.object(c, "fixed", return_value=[other, self.target]), \
                    patch.object(c, "machines", return_value={"dell": "u@dell"}):
                after = c.ranking("tela")
            self.assertEqual(before[0]["key"], after[1]["key"])
            self.assertEqual(before[1]["key"], after[0]["key"])

    def test_clique_atrasado_nao_sobrepoe_cancelamento(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)):
            c = pre.Coordinator(Path(d))
            c.handle({"op": "cancel", "client": "tela", "order": 30})
            with patch.object(c, "navigate") as navigate:
                self.assertTrue(c.handle({"op": "navigate", "client": "tela", "order": 20})["handled"])
                navigate.assert_not_called()
            self.assertFalse(c.requests)

    def test_pedido_expirado_nao_abre_nada(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)):
            c = pre.Coordinator(Path(d))
            with patch.object(c, "navigate") as navigate:
                c.handle({"op": "navigate", "client": "tela", "expires": 0})
                navigate.assert_not_called()

    def test_sleep_cancela_pedidos_e_preserva_ponte_ativa(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)):
            c = pre.Coordinator(Path(d))
            c.last_tick, c.last_wall = 100, 1000
            c.requests["tela"] = {"key": "espera"}
            c.candidates = {"espera": {"state": "ready"}, "ativa": {"state": "active"}}
            with patch.object(c, "still_owned", return_value=False):
                c.check_wake(101, 1600)  # monotônico ficou parado durante o suspend
            self.assertFalse(c.requests)
            self.assertEqual(list(c.candidates), ["ativa"])
            self.assertEqual(c.cooldown_until, 106)

    def test_limite_global_e_concorrencia_de_preparacao(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)):
            c = pre.Coordinator(Path(d))
            c.clients = {"a": {"generation": "1"}, "b": {"generation": "2"}, "c": {"generation": "3"}}
            ranked = [{"key": str(i), "target": dict(self.target, id=str(i)), "score": 100-i, "blocked": False} for i in range(9)]
            def prepare(client, target):
                item = {"state": "ready", "target": target, "created": pre.time.monotonic(),
                        "client": client, "generation": c.clients[client]["generation"]}
                c.candidates[(client, target["id"])] = item
                return item
            with patch.object(c, "settings", return_value=("auto", 6, 3)), \
                    patch.object(c, "ranking", return_value=ranked), patch.object(c, "prepare", side_effect=prepare) as p:
                c.maintain()
                self.assertLessEqual(p.call_count, 2)
                c.maintain()
                c.maintain()
                self.assertEqual(len(c.candidates), 6)
                self.assertLessEqual(max(sum(k[0] == client for k in c.candidates) for client in c.clients), 3)

    def test_falha_de_sessao_nao_bloqueia_maquina_inteira(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)):
            c = pre.Coordinator(Path(d))
            c.failure({"target": self.target}, "sessão removida")
            self.assertNotIn("dell", c.failures)
            self.assertIn(pre.identity(self.target), c.failures)

    def test_falha_parcial_de_criacao_nao_deixa_candidato(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)):
            c = pre.Coordinator(Path(d))
            c.clients["tela"] = {"width": "100", "height": "30", "generation": "1"}
            with patch.object(c, "machines", return_value={"dell": "u@dell"}), \
                    patch.object(c, "still_owned", return_value=True), patch.object(pre, "tmux", return_value=(1, "")) as tmux:
                self.assertIsNone(c.prepare("tela", self.target))
                self.assertEqual(tmux.call_args[0][0], "kill-session")
            self.assertFalse(c.candidates)

    def test_tela_desanexada_cancela_ativacao(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)):
            c = pre.Coordinator(Path(d))
            c.requests["tela"] = {"key": "espera", "generation": "1", "source": "origem"}
            c.candidates["espera"] = {"state": "ready"}
            with patch.object(c, "still_owned", return_value=False), patch.object(c, "begin_activation") as activate:
                c.poll_requests()
                activate.assert_not_called()
            self.assertFalse(c.requests)
            self.assertFalse(c.candidates)

    def test_config_off_prevalece_sobre_opt_in_do_ambiente(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)), \
                patch.object(pre, "read_config", return_value={"precarregar": "off"}), \
                patch.dict(pre.os.environ, {"TT_PRECARREGAR": "1"}), \
                patch.object(pre, "battery", return_value=(90, True)):
            c = pre.Coordinator(Path(d))
            self.assertEqual(c.settings()[0:2], ("off", 0))

    def test_identidade_explicita_nao_e_sobreposta_por_fixada_de_mesmo_nome(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)):
            c = pre.Coordinator(Path(d))
            c.clients["tela"] = {"generation": "1", "session": "origem"}
            with patch.object(c, "scan_clients"), patch.object(c, "resolve_machine", return_value="dell"), \
                    patch.object(c, "fixed", return_value=[self.target]), \
                    patch.object(c, "settings", return_value=("auto", 6, 3)), \
                    patch.object(c, "prepare", return_value={"state": "preparing"}) as prepare:
                c.navigate({"client": "tela", "dest": "dell", "name": "tarefa", "id": "b" * 32})
                self.assertEqual(prepare.call_args[0][1]["id"], "b" * 32)

    def test_resposta_perdida_nao_dispara_caminho_legado(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "runtime", return_value=Path(d)), \
                patch.object(pre, "send_request", side_effect=pre.UncertainReply), \
                patch.object(pre.subprocess, "Popen") as spawn:
            self.assertEqual(pre.main(["navigate", "tela", "dell", "tarefa"]), 0)
            spawn.assert_not_called()
        conn = MagicMock()
        conn.__enter__.return_value = conn
        conn.recv.side_effect = pre.socket.timeout()
        with patch.object(pre.socket, "socket", return_value=conn):
            with self.assertRaises(pre.UncertainReply):
                pre.send_request(Path("/tmp"), {"op": "navigate"})

    def test_bilhete_malformado_e_token_diferente_sao_recusados(self):
        token = "a" * 32
        payload = {"sid": "$1", "server": "100", "pid": 12, "name": "sessão", "id": "b" * 32}
        output = pre.PREFIX + token + " " + base64.b64encode(json.dumps(payload).encode()).decode()
        self.assertEqual(pre.decode_ticket(output, token), payload)
        self.assertIsNone(pre.decode_ticket(output, "c" * 32))
        payload["sid"] = "sessão-por-nome"
        output = pre.PREFIX + token + " " + base64.b64encode(json.dumps(payload).encode()).decode()
        with self.assertRaises(ValueError):
            pre.decode_ticket(output, token)

    def test_orfa_so_e_removida_com_marca_propria_e_sem_cliente(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)):
            folder = Path(d)
            c = pre.Coordinator(folder)
            token = "a" * 32
            lines = [pre.SEP.join(["tt-pre-" + token[:16], owner, token, state, attached])
                     for owner, state, attached in ((folder.name, "espera", "0"),
                                                   ("outro-coordenador", "espera", "0"),
                                                   (folder.name, "ativa", "0"),
                                                   (folder.name, "espera", "1"))]
            with patch.object(pre, "tmux", side_effect=[(0, "\n".join(lines)), (0, "")]) as tmux:
                c.reap_orphans()
                self.assertEqual(tmux.call_count, 2)
                self.assertEqual(tmux.call_args[0], ("kill-session", "-t", "=tt-pre-" + token[:16]))

    def test_orfa_de_coordenador_morto_e_removida_e_de_vivo_fica(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)):
            root = Path(d)
            folder = root / "tt-pre-1-aaaaaaaaaaaaaaaa"; folder.mkdir()
            vivo, morto = root / "tt-pre-1-bbbbbbbbbbbbbbbb", root / "tt-pre-1-cccccccccccccccc"
            vivo.mkdir(); morto.mkdir(); (morto / "lock").touch()
            c = pre.Coordinator(folder)
            tokens = {"vivo": "b" * 32, "morto": "c" * 32, "sumido": "d" * 32}
            owners = {"vivo": vivo.name, "morto": morto.name, "sumido": "tt-pre-1-dddddddddddddddd"}
            lines = [pre.SEP.join(["tt-pre-" + tokens[k][:16], owners[k], tokens[k], "espera", "0"]) for k in tokens]
            with open(vivo / "lock", "a") as trava:
                pre.fcntl.flock(trava, pre.fcntl.LOCK_EX)
                with patch.object(pre, "tmux", side_effect=[(0, "\n".join(lines)), (0, ""), (0, "")]) as tmux:
                    c.reap_orphans()
            mortas = [call[0][2] for call in tmux.call_args_list[1:]]
            self.assertEqual(sorted(mortas), sorted(["=tt-pre-" + tokens["morto"][:16], "=tt-pre-" + tokens["sumido"][:16]]))

    def test_ponte_ativa_repetida_fecha_so_as_que_ninguem_ve(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)):
            c = pre.Coordinator(Path(d))
            a, b = "a" * 32, "b" * 32
            rows = [("tt-pre-1", "ativa", a, "u@pc", "0", "100"), ("tt-pre-2", "ativa", a, "u@pc", "0", "300"),
                    ("tt-pre-3", "ativa", a, "u@pc", "1", "50"), ("tt-pre-4", "ativa", b, "u@pc", "0", "10"),
                    ("tt-pre-5", "ativa", b, "u@pc", "0", "20"), ("tt-pre-6", "espera", b, "u@pc", "0", "5"),
                    ("comum", "ativa", b, "u@pc", "0", "1")]
            out = "\n".join(pre.SEP.join(r) for r in rows)
            with patch.object(c, "resolve_machine", return_value="pc"), \
                    patch.object(pre, "tmux", side_effect=[(0, out)] + [(0, "")] * 5) as tmux:
                c.dedupe_active()
            mortas = sorted(call[0][2] for call in tmux.call_args_list[1:])
            # a: fica a anexada (3), fecham 1 e 2; b: fica a mais recente (5), fecha 4; espera e não tt-pre ficam
            self.assertEqual(mortas, ["=tt-pre-1", "=tt-pre-2", "=tt-pre-4"])

    def test_um_coordenador_por_servidor_mesmo_com_tt_rt_e_atalho_de_tmp(self):
        with tempfile.TemporaryDirectory() as d:
            real = Path(d) / "real"; real.mkdir(); (Path(d) / "atalho").symlink_to(real)
            pastas = set()
            for sock, rt in ((str(real / "default"), "/tmp"), (str(Path(d) / "atalho" / "default"), "/var/folders/x/T/")):
                with patch.dict(pre.os.environ, {"TMUX": sock + ",1,0", "TT_RT": rt}):
                    pastas.add(pre.runtime())
            self.assertEqual(len(pastas), 1)
            for f in pastas:
                f.rmdir()

    def test_transporte_abre_conexao_propria_e_nao_canal_da_mestra(self):
        with patch.object(pre.subprocess, "call", return_value=0) as call:
            pre.main(["transporte", "u@pc", "t" * 32, "sessao", "", "maq|tt-pre-x", "180",
                      "--ssh-args", "-o", "ControlMaster=auto", "-o", "ControlPath=/x/%C"])
        args = call.call_args[0][0]
        self.assertLess(args.index("ControlPath=none"), args.index("ControlPath=/x/%C"))
        self.assertLess(args.index("ControlMaster=no"), args.index("ControlMaster=auto"))

    def test_expiracao_remove_espera_mas_nao_ponte_ativa(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)):
            c = pre.Coordinator(Path(d))
            c.candidates = {"velha": {"state": "ready", "created": 0, "client": "tela", "generation": "1"},
                            "ativa": {"state": "active", "bridge": "usada"}}
            with patch.object(c, "settings", return_value=("auto", 6, 3)), \
                    patch.object(c, "still_owned", return_value=False), patch.object(pre, "tmux", return_value=(0, "")):
                c.maintain()
            self.assertEqual(list(c.candidates), ["ativa"])

    def test_cadastro_antigo_e_ocultas(self):
        with tempfile.TemporaryDirectory() as d, patch.object(pre, "STATE", Path(d)), patch.object(pre, "CONF", Path(d)):
            (Path(d) / "maquinas").write_text("dell.exemplo u\noculta u secreta oculta\nsemusuario - velha\nmac u local\n")
            c = pre.Coordinator(Path(d))
            c.machine = "local"
            self.assertEqual(c.machines(), {"dell": "u@dell.exemplo"})


if __name__ == "__main__":
    unittest.main()
