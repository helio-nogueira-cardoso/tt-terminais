#!/usr/bin/env python3
"""Envelopes no SSH existente: bytes, identidade do transporte e destino da tela."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import pty
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

if __name__=='__main__':
    unittest.main()
