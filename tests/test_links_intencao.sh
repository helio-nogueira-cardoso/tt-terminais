#!/usr/bin/env bash
# Cancelar/trocar o clique durante a captura do painel nunca permite abrir o link antigo.
source "$(dirname "$0")/lib.sh"; isolar
python3 -I - "$TT_DIR/links-tt.py" <<'PY'
import importlib.util, sys
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('links',sys.argv[1]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for explicit, following in [(False,''),(True,''),(True,'server:2')]:
    state=['server:1']
    def tmux(*args):
        if args[0]=='set': state[0]=args[-1]
        return state[0]
    def lookup(*args):
        state[0]=following
        return 'https://example.com/antigo'
    with patch.object(m,'tmux',side_effect=tmux),patch.object(m,'url_no_painel',side_effect=lookup),patch.object(m,'soltar') as launch:
        m.clique('cliente','%1',2,3,80,24,False,'',*(['server:1'] if explicit else []))
        launch.assert_not_called()
        assert state[0]==following
with patch.object(m,'tmux',return_value='server:2'),patch.object(m,'url_no_painel') as lookup,patch.object(m,'soltar') as launch:
    m.clique('cliente','%1',2,3,80,24,False,'','server:1')
    lookup.assert_not_called(); launch.assert_not_called()
with patch.object(m,'tmux',return_value='server:1'),patch.object(m,'url_no_painel',return_value='https://example.com/atual'),patch.object(m,'soltar') as launch:
    m.clique('cliente','%1',2,3,80,24,False,'','server:1')
    launch.assert_called_once_with('--link-abrir','server:1','cliente','%1','https://example.com/atual')
print('ok: cancelamento antes/durante a captura, clique mais novo e clique vigente')
PY
