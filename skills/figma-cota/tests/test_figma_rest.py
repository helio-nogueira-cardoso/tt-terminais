import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/figma_rest.py'
spec = importlib.util.spec_from_file_location('figma_rest', SCRIPT)
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)

class FigmaTests(unittest.TestCase):
    def test_urls(self):
        for kind in ('design', 'file', 'proto', 'board'):
            for node in ('12-34', '12%3A34'):
                self.assertEqual(f.referencia(f'https://www.figma.com/{kind}/ABC/Test?node-id={node}&t=x'), ('ABC', '12:34'))
        self.assertEqual(f.referencia('ABC'), ('ABC', None))
        self.assertEqual(f.referencia('https://figma.com/design/MAIN/branch/BRANCH/Name?node-id=1-2'), ('BRANCH', '1:2'))

    def test_reject_urls(self):
        for url in ('https://evil.test/design/ABC/X', 'http://figma.com/design/ABC/X', 'https://figma.com.evil.test/design/ABC/X', '../ABC', 'https://figma.com/design/../X', 'https://figma.com/design/ABC/X?node-id=1-2&node-id=3-4', 'https://figma.com/design/ABC/X?node-id=oops'):
            with self.subTest(url=url), self.assertRaises(ValueError):
                f.referencia(url)

    def cache(self, root, key='ABC'):
        (root/'arquivo.json').write_text(json.dumps({'name':'Teste','version':'v1','document':{'id':'0:0','type':'DOCUMENT','children':[{'id':'0:1','type':'CANVAS','name':'Página','children':[{'id':'12:34','type':'FRAME','name':'Ação','children':[]}]}]}}))
        (root/'meta.json').write_text(json.dumps({'fileKey':key,'version':'v1'}))

    def test_offline_cli(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); self.cache(root)
            env=dict(os.environ, FIGMA_TOKEN_FILE=str(root/'missing'), FIGMA_COTA_LIVRO=str(root/'usage'))
            for cmd in (['ler','https://figma.com/design/ABC/Test?node-id=12-34'], ['no','ABC','12:34'], ['buscar','ABC','acao'], ['telas','ABC']):
                r=subprocess.run([sys.executable,str(SCRIPT),*cmd,'--cache',tmp],env=env,text=True,capture_output=True)
                self.assertEqual(r.returncode,0,r.stderr)
                self.assertIn('12:34',r.stdout)
            self.assertFalse((root/'usage').exists())

    def test_missing_and_wrong_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(SystemExit): f.no('ABC',tmp,'12:34',3)
            self.cache(Path(tmp),key='OTHER')
            with self.assertRaises(SystemExit): f.no('ABC',tmp,'12:34',3)

    def test_429_single_request(self):
        error=HTTPError('https://api.figma.com',429,'limit',{'Retry-After':'90'},None)
        with patch.object(f,'_token',return_value='fake'),patch.object(f,'registrar') as log,patch.object(f.urllib.request,'urlopen',side_effect=error) as net:
            with self.assertRaises(SystemExit) as e: f._get(f.API+'/files/ABC','test')
            self.assertIn('Retry-After 90',str(e.exception))
            self.assertNotIn('mes acabou',str(e.exception))
            net.assert_called_once(); log.assert_called_once()

    def test_download_and_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            doc={'name':'Teste','version':'v1','lastModified':'today','document':{'children':[]}}
            with patch.object(f,'_get',return_value=doc) as get,contextlib.redirect_stdout(io.StringIO()):
                f.baixar('ABC',tmp,False)
                self.assertEqual(get.call_count,1)
            self.assertEqual(json.loads((Path(tmp)/'meta.json').read_text())['fileKey'],'ABC')
            out=io.StringIO()
            with patch.object(f,'_get',return_value=doc),contextlib.redirect_stdout(out):f.versao('ABC',tmp)
            self.assertIn('IGUAL',out.getvalue())

    def test_invalid_cli(self):
        for cmd in (['no','ABC'],['ler','https://figma.com/design/ABC/X?node-id=1-2','3:4'],['no','ABC','1:2','--prof','-1'],['baixar','ABC','--cache']):
            r=subprocess.run([sys.executable,str(SCRIPT),*cmd],capture_output=True,text=True)
            self.assertEqual(r.returncode,2)
            self.assertNotIn('Traceback',r.stderr)

if __name__=='__main__': unittest.main()
