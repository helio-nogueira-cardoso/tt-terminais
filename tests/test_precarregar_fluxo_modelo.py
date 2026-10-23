#!/usr/bin/env python3
"""Envelopes no SSH existente: bytes, identidade do transporte e destino da tela."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import tempfile
import time
import unittest
from unittest.mock import MagicMock, patch

root = Path(__file__).resolve().parents[1]
import sys
sys.path.insert(0, str(root))
spec = importlib.util.spec_from_file_location('pre', root / 'precarregar-tt.py')
pre = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pre)
TOKEN = 'a' * 32

def packet(seq=1, **changes):
    result = dict(v=1, dest='macbook-pro', name='sessão com espaço', id='b'*32,
                  seq=seq, deadline=time.time()+5)
    result.update(changes)
    return result

def frame(value, token=TOKEN):
    return pre.NAV_PREFIX + token.encode() + b';' + base64.b64encode(json.dumps(value).encode()) + b'\x07'

class Fluxo(unittest.TestCase):
    def test_bytes_normais_e_outro_transporte_sao_transparentes(self):
        raw = b'texto\r\n\x1b[31mcor\x1b[0m' + frame(packet(), 'c'*32)
        calls=[]; stream=pre.NavigationStream(TOKEN, calls.append)
        self.assertEqual(stream.feed(raw, final=True), raw)
        self.assertEqual(calls, [])

    def test_todas_as_fragmentacoes_preservam_bytes_e_executam_uma_vez(self):
        p=packet(); raw=b'antes'+frame(p)+b'depois'
        for split in range(len(raw)+1):
            calls=[]; stream=pre.NavigationStream(TOKEN, calls.append)
            out=stream.feed(raw[:split])+stream.feed(raw[split:], final=True)
            self.assertEqual(out,b'antesdepois',split)
            self.assertEqual(calls,[p],split)

    def test_byte_a_byte_sequencia_duplicada_e_pedido_mais_antigo(self):
        calls=[]; stream=pre.NavigationStream(TOKEN,calls.append)
        raw=b'A'+frame(packet(2))+frame(packet(2))+frame(packet(1))+frame(packet(3))+b'B'
        out=b''.join(stream.feed(bytes([c])) for c in raw)+stream.feed(b'',final=True)
        self.assertEqual(out,b'AB'); self.assertEqual([c['seq'] for c in calls],[2,3])

    def test_invalido_expirado_e_truncado_nao_executam(self):
        bad=[packet(v=9),packet(dest='m\ncomando'),packet(id=[]),packet(deadline=1),
             packet(deadline=float('nan')),packet(deadline=10**1000),packet(deadline=1e100),packet(name=''),packet(seq=-1),packet(seq=2**64)]
        calls=[]; stream=pre.NavigationStream(TOKEN,calls.append)
        raw=b'X'+b''.join(frame(p) for p in bad)+pre.NAV_PREFIX+TOKEN.encode()+b';%%%\x07Y'
        self.assertEqual(stream.feed(raw,final=True),b'XY'); self.assertEqual(calls,[])
        self.assertEqual(stream.feed(frame(packet())[:-3],final=True),b'')
        self.assertEqual(calls,[])
        self.assertEqual(stream.feed(pre.NAV_PREFIX+TOKEN[:12].encode(),final=True),b'')

    def test_envelope_interrompido_e_limite_nao_engolem_pedido_seguinte(self):
        calls=[]; stream=pre.NavigationStream(TOKEN,calls.append)
        self.assertEqual(stream.feed(frame(packet())[:-5]+frame(packet(2)),final=True),b'')
        self.assertEqual([c['seq'] for c in calls],[2])
        stream.feed(pre.NAV_PREFIX+TOKEN.encode()+b';'+b'A'*9000)
        self.assertLess(len(stream.buffer),8192)
        stream.feed(frame(packet(3)),final=True)
        self.assertEqual([c['seq'] for c in calls],[2,3])

    def test_cliente_aninhado_emite_no_tty_sem_criar_ssh(self):
        master,slave=pty.openpty()
        try:
            client=os.ttyname(slave); generation=str(os.getpid())+':1'
            with tempfile.TemporaryDirectory() as d, patch.object(pre,'STATE',Path(d)):
                c=pre.Coordinator(Path(d)); c.nested_clients[client]=dict(generation=generation,session='origem')
                c.nested_env[generation]=TOKEN
                row=pre.SEP.join([client,str(os.getpid()),'1','origem'])
                with patch.object(pre,'tmux',return_value=(0,row)), patch.object(pre.subprocess,'Popen') as ssh:
                    self.assertTrue(c.relay_nested(client,dict(dest='mac',name='renomeada',id='b'*32,order=12)))
                    calls=[]; parser=pre.NavigationStream(TOKEN,calls.append)
                    self.assertEqual(parser.feed(os.read(master,4096),final=True),b'')
                    self.assertEqual(calls[0]['id'],'b'*32)
                    self.assertEqual(calls[0]['name'],'renomeada')
                    ssh.assert_not_called()
                with patch.object(pre,'tmux',return_value=(0,'')), patch.object(pre.os,'open') as opened:
                    self.assertTrue(c.relay_nested(client,dict(dest='mac',name='nova')))
                    opened.assert_not_called()  # tty reutilizado não recebe evento velho
                c.nested_env[generation]=''
                with patch.object(pre.os,'open') as opened:
                    self.assertFalse(c.relay_nested(client,dict(dest='mac',name='nova')))
                    opened.assert_not_called()  # conexão antiga conserva fallback
        finally:
            os.close(master); os.close(slave)

    def test_receptor_escolhe_ponte_autenticada_e_nao_duplica_resposta_perdida(self):
        for uncertain in (False,True):
            read_fd,write_fd=os.pipe(); value=packet()
            os.write(write_fd,b'antes'+frame(value)+b'depois');os.close(write_fd)
            proc=MagicMock(); proc.stdout=os.fdopen(read_fd,'rb');proc.wait.return_value=0
            output=[]
            def write(fd,data):
                self.assertEqual(fd,1);output.append(data);return len(data)
            try:
                with patch.object(pre,'runtime',return_value=Path('/nao-usar')), \
                     patch.object(pre,'send_request',return_value={'handled':True},
                                  side_effect=pre.UncertainReply if uncertain else None) as rpc, \
                     patch.object(pre.os,'write',side_effect=write), patch.object(pre,'execute') as legacy:
                    self.assertEqual(pre.relay_output(proc,TOKEN,'empresa|tt-pre-autenticada'),0)
                    data=rpc.call_args[0][1]
                    self.assertEqual(data['bridge'],'tt-pre-autenticada')
                    self.assertEqual(data['id'],value['id'])
                    self.assertEqual(b''.join(output),b'antesdepois')
                    legacy.assert_not_called()
            finally:
                proc.stdout.close()

class SemTravar(unittest.TestCase):
    """23/10/2026: a mestra do ssh segurou o pipe do coordenador, ele congelou e todo clique de dentro de uma
    ponte sumiu; e o pty do Tailscale SSH (dono root) impedia o envelope de voltar pelo terminal."""

    def test_execute_e_finish_nao_esperam_o_neto_que_segura_o_pipe(self):
        t = time.monotonic()
        self.assertEqual(pre.execute(['sh', '-c', 'sleep 3 & echo pronto'], timeout=3), (0, 'pronto\n'))
        self.assertLess(time.monotonic() - t, 1.5)
        t = time.monotonic()
        self.assertEqual(pre.execute(['sh', '-c', 'sleep 3 & sleep 3'], timeout=.3)[0], 124)
        self.assertLess(time.monotonic() - t, 1.5)
        proc = subprocess.Popen(['sh', '-c', 'echo confirmado; sleep 3 &'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        proc.wait()
        t = time.monotonic()
        self.assertEqual(pre.finish(proc, kill=False), b'confirmado\n')
        self.assertLess(time.monotonic() - t, 1)
        self.assertEqual(pre.execute(['/nao/existe']), (124, ''))

    def test_coordenador_que_parou_de_girar_e_encerrado(self):
        with tempfile.TemporaryDirectory() as d:
            folder = Path(d)
            alive = folder / pre.ALIVE
            old = time.time() - 60
            code = 'import sys,time; print("ok",flush=True); time.sleep(30)'
            # o "coordenador": a linha de comando dele tem precarregar-tt.py daemon, como a de verdade
            holder = subprocess.Popen([sys.executable, '-c', code, 'precarregar-tt.py', 'daemon'], stdout=subprocess.PIPE)
            outro = subprocess.Popen([sys.executable, '-c', code, 'outro-programa'], stdout=subprocess.PIPE)
            try:
                holder.stdout.readline(); outro.stdout.readline()
                alive.write_text(str(holder.pid))
                self.assertFalse(pre.coordinator_stuck(folder))  # girou agora há pouco: só lento
                os.utime(alive, (old, old))
                self.assertTrue(pre.coordinator_stuck(folder))   # parado: encerrado
                self.assertEqual(holder.wait(timeout=3), -9)
                self.assertTrue(pre.coordinator_stuck(folder))   # já morto: a fila dele também segue
                alive.write_text(str(outro.pid)); os.utime(alive, (old, old))
                self.assertTrue(pre.coordinator_stuck(folder))   # pid reciclado: morto, e o outro programa fica
                self.assertIsNone(outro.poll())
                alive.unlink()
                self.assertFalse(pre.coordinator_stuck(folder))  # sem vivo (versão antiga ou saída limpa): entregue
                self.assertFalse(pre.coordinator_stuck(None))
            finally:
                for proc in (holder, outro):
                    if proc.poll() is None:
                        proc.kill()
                        proc.wait()
                    proc.stdout.close()

    def test_porteiro_devolve_o_clique_quando_o_terminal_nao_aceita_escrita(self):
        master, slave = pty.openpty()
        name = os.ttyname(slave)
        procs = []
        try:
            with tempfile.TemporaryDirectory() as d, patch.dict(os.environ, {'TT_PRE_RELAY_DIR': d}), \
                    patch.object(pre, 'STATE', Path(d)):
                sock = Path(d) / ('tt-pre-relay-%d' % os.getuid()) / TOKEN[:16]
                code = ('import sys,time; sys.path.insert(0,%r); import precarregar_remoto as p; '
                        'p.start_doorman(%r); print("pronto", flush=True); time.sleep(30)') % (str(root), TOKEN)
                def cliente():  # o "cliente tmux": o processo do bilhete, que chama o porteiro e faz exec
                    proc = subprocess.Popen([sys.executable, '-c', code], stdin=slave, stdout=slave,
                                            stderr=subprocess.DEVNULL, env=dict(os.environ))
                    procs.append(proc)
                    return proc
                def ler(ate=b'pronto', prazo=5):
                    data, fim = b'', time.monotonic() + prazo
                    while ate not in data and time.monotonic() < fim:
                        if select.select([master], [], [], .1)[0]:
                            data += os.read(master, 4096)
                    return data

                # terminal que aceita a nossa escrita: sem porteiro (nenhum processo a mais)
                cliente(); self.assertIn(b'pronto', ler())
                time.sleep(.3)
                self.assertFalse(sock.exists())
                procs[-1].kill(); procs[-1].wait()

                os.chmod(name, 0o400)  # como o pty do Tailscale SSH: dono root, 620, grupo tty
                proc = cliente(); self.assertIn(b'pronto', ler())
                fim = time.monotonic() + 3
                while not sock.exists() and time.monotonic() < fim:
                    time.sleep(.05)
                self.assertTrue(sock.exists(), 'porteiro não abriu o socket')

                self.assertTrue(pre.protocol.doorman_send(TOKEN, frame(packet())))
                calls = []
                parser = pre.NavigationStream(TOKEN, calls.append)
                parser.feed(ler(b'\x07'), final=True)
                self.assertEqual(calls[0]['name'], 'sessão com espaço')

                # só envelope desta ponte: outro token e escape arbitrário não chegam ao terminal
                self.assertFalse(pre.protocol.doorman_send(TOKEN, frame(packet(), 'c' * 32)))
                self.assertFalse(pre.protocol.doorman_send(TOKEN, b'\x1b]52;c;ZXZpbA==\x07'))
                self.assertEqual(ler(b'\x07', prazo=.5), b'')

                # o coordenador: open() recusado, entrega pelo porteiro e conta à parte
                generation = '%d:1' % proc.pid
                c = pre.Coordinator(Path(d))
                c.nested_clients[name] = dict(generation=generation, session='origem')
                c.nested_env[generation] = TOKEN
                row = pre.SEP.join([name, str(proc.pid), '1', 'origem'])
                with patch.object(pre, 'tmux', return_value=(0, row)):
                    self.assertTrue(c.relay_nested(name, dict(dest='mac', name='nova', id='b' * 32, order=99)))
                self.assertEqual(c.metrics['encaminhadas_porteiro'], 1)
                self.assertEqual(c.metrics['falhas_encaminhamento'], 0)
                calls = []
                pre.NavigationStream(TOKEN, calls.append).feed(ler(b'\x07'), final=True)
                self.assertEqual(calls[0]['name'], 'nova')

                # o cliente tmux saiu: o porteiro sai junto e leva o socket
                proc.kill(); proc.wait()
                fim = time.monotonic() + 3
                while sock.exists() and time.monotonic() < fim:
                    time.sleep(.05)
                self.assertFalse(sock.exists(), 'porteiro sobreviveu ao cliente')
                self.assertFalse(pre.protocol.doorman_send(TOKEN, frame(packet(5))))
        finally:
            for proc in procs:
                if proc.poll() is None:
                    proc.kill()
                    proc.wait()
            os.close(master); os.close(slave)

if __name__=='__main__':
    unittest.main()
