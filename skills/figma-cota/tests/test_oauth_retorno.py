import contextlib
import http.server
import importlib.util
from pathlib import Path
import threading
import unittest
import urllib.parse
from unittest.mock import patch

SCRIPT=Path(__file__).resolve().parents[1]/'scripts/figma_oauth_retorno.py'
spec=importlib.util.spec_from_file_location('retorno',SCRIPT)
f=importlib.util.module_from_spec(spec);spec.loader.exec_module(f)


def auth(port=12345,host='127.0.0.1',path='/oauth/callback'):
    return 'https://www.figma.com/oauth/mcp?'+urllib.parse.urlencode({'redirect_uri':f'http://{host}:{port}{path}','state':'tentativa'})


def callback(port=12345,host='127.0.0.1',path='/oauth/callback',query='code=sintetico&state=tentativa&iss=https%3A%2F%2Fapi.figma.com'):
    return f'http://{host}:{port}{path}?{query}'


class RetornoTests(unittest.TestCase):
    def test_valid(self):
        p,path=f.destino(auth(),callback())
        self.assertEqual(p,12345);self.assertIn('code=sintetico',path);self.assertIn('iss=',path)

    def test_reject_other_attempt(self):
        for q in ('code=x&state=outro','code=x&state=tentativa&state=tentativa','state=tentativa','code=x&code=y&state=tentativa','code=x&state=tentativa&error=denied'):
            with self.subTest(query=q),self.assertRaises(ValueError):f.destino(auth(),callback(query=q))

    def test_reject_other_destination(self):
        for args in ({'host':'example.com'},{'host':'localhost'},{'port':12346},{'path':'/admin'}):
            with self.subTest(args=args),self.assertRaises(ValueError):f.destino(auth(),callback(**args))
        with self.assertRaises(ValueError):f.destino(auth().replace('www.figma.com','evil.test'),callback())
        with self.assertRaises(ValueError):f.destino(auth(),callback()+'#fragment')

    def test_invalid_does_not_connect(self):
        with patch.object(f.http.client,'HTTPConnection') as net:
            with self.assertRaises(ValueError):f.entregar(auth(),callback(query='code=x&state=errado'))
            net.assert_not_called()

    def test_tt_authorization_link(self):
        import subprocess
        from unittest.mock import Mock
        result=Mock(stdout='aviso\n'+auth()+'\n')
        with patch.object(f.subprocess,'run',return_value=result) as run:
            self.assertEqual(f.autorizacao_tt('figma-retorno-wsl'),auth())
            run.assert_called_once()
        with self.assertRaises(ValueError):f.autorizacao_tt('../outra')

    def test_delivery_on_cli_host(self):
        seen=[]
        class Receiver(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                seen.append(self.path);self.send_response(200);self.end_headers()
            def log_message(self,*args):pass
        with http.server.HTTPServer(('127.0.0.1',0),Receiver) as server:
            t=threading.Thread(target=server.handle_request);t.start()
            try:f.entregar(auth(server.server_port),callback(server.server_port))
            finally:t.join(timeout=3)
        self.assertEqual(len(seen),1);self.assertIn('code=sintetico',seen[0])

    def test_no_redirect_following(self):
        seen=[]
        class Receiver(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                seen.append(self.path);self.send_response(302);self.send_header('Location','http://example.com/');self.end_headers()
            def log_message(self,*args):pass
        with http.server.HTTPServer(('127.0.0.1',0),Receiver) as server:
            t=threading.Thread(target=server.handle_request);t.start()
            try:
                with self.assertRaises(ValueError):f.entregar(auth(server.server_port),callback(server.server_port))
            finally:t.join(timeout=3)
        self.assertEqual(len(seen),1)

if __name__=='__main__':unittest.main()
