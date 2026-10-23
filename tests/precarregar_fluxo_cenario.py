#!/usr/bin/env python3
"""Empresa (origem) → Mac (remota) → clique Mac → fluxo SSH → origem → quadro."""
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time

command, client, outer, root, remote_socket, bridge_a, machine = sys.argv[1:]
root = Path(root)
env = os.environ.copy()
for key in ('TMUX_PANE','TT_CLIENTE','_TT_PATH_ORIGEM','TT_PRE_FAST_FALLBACK'):
    env.pop(key,None)
env.update(HOME=str(root/'home'),XDG_CONFIG_HOME=str(root/'home/.config'),
           XDG_STATE_HOME=str(root/'home/.local/state'),TT_DIR=str(root/'home/.local/share/tt'),
           TMUX_TMPDIR=str(root/'tmux'),TMUX=remote_socket+',1,0',TT_RT=str(root/'rt'),
           TT_PRECARREGAR='1',TT_PRE_MACHINE='remota',TT_PRE_TT=command,TT_SEM_VIGIA_AUTO='1')
share=root/'home/.local/share/tt'; share.symlink_to(Path(command).parent)
remote_tt=root/'home/.local/bin/tt';remote_tt.symlink_to(command)
conf=root/'home/.config/tt'
(conf/'config').write_text('nome=remota\nprecarregar=auto\n')
(conf/'maquinas').write_text('origem usuario '+machine+'\n')
(conf/'fixadas').write_text('remota\tprimeira\t'+'a'*32+'\nremota\tsegunda\t'+'b'*32+'\n')
(root/'origin.json').write_text(json.dumps({key:os.environ[key] for key in
    ('HOME','XDG_CONFIG_HOME','TMUX_TMPDIR','TT_RT','TT_DIR') if key in os.environ}))

def call(args, **kw):
    return subprocess.check_output(args,text=True,**kw)
def screen():
    return call(['tmux','-L',outer,'capture-pane','-p','-t','=pc:'])
def current():
    rows=call(['tmux','list-clients','-F','#{client_name}\t#{session_name}']).splitlines()
    return next(r.split('\t')[1] for r in rows if r.startswith(client+'\t'))
def remote_client(name):
    rows=call(['tmux','-S',remote_socket,'list-clients','-F','#{session_name}\t#{client_name}']).splitlines()
    return next(r.split('\t')[1] for r in rows if r.startswith(name+'\t'))
def wait_frame(marker):
    until=time.monotonic()+10
    while time.monotonic()<until:
        frame=screen()
        if marker in frame:
            assert 'tt-nav;' not in frame
            return
        time.sleep(.005)
    raise AssertionError('quadro não chegou: '+marker+'\n'+screen())
def click(source_name, target, index=0):
    tty=remote_client(source_name)
    key='fx'+hashlib.sha256(('remota\t'+target*32).encode()).hexdigest()[:12]
    args=['--ir-fixada',tty,key] if index%2 else ['--clique','user|'+key,tty,'%0','','0','d']
    began=time.monotonic()
    subprocess.run([command,*args],env=env,check=True)
    wait_frame('TT_TELA_PRIMEIRA' if target=='a' else 'TT_TELA_SEGUNDA')
    return round((time.monotonic()-began)*1000)
try:
    subprocess.run([command,'--precarregar-evento','evento'],env=env,check=True)
    click('renomeada','b')
    bridge_b=current();assert bridge_b!=bridge_a
    # Ambos os transportes já têm quadro e identidade. Daqui em diante não há SSH novo.
    before=(root/'ssh.log').read_text().splitlines()
    samples=[]
    name_a='renomeada'
    for index in range(7):
        if index==3:
            subprocess.run(['tmux','-S',remote_socket,'rename-session','-t','=renomeada','outro-nome-mesmo-id'],check=True)
            name_a='outro-nome-mesmo-id'
        source,target=('segunda','a') if index%2==0 else (name_a,'b')
        samples.append(click(source,target,index))
    after=(root/'ssh.log').read_text().splitlines()
    assert before==after,('clique dentro da ponte abriu SSH adicional',after[len(before):])
    assert current()==bridge_a
    status=json.loads(call([command,'--precarregar','json'],env=env))
    assert status['metricas'].get('encaminhadas_fluxo',0)>=8,status
    print('empresa→Mac→clique remoto→quadro (7): mediana=%d ms máximo=%d ms; SSH adicional=0' %
          (statistics.median(samples),max(samples)))
    subprocess.run(['tmux','-S',remote_socket,'rename-session','-t','=outro-nome-mesmo-id','renomeada'],check=True)
    # Teclado e janela atravessam os dois PTYs, com stdout do SSH passando pelo filtro.
    subprocess.run(['tmux','-S',remote_socket,'new-session','-d','-s','teclado',
                    "printf 'TT_TELA_TECLADO\\n'; exec bash --noprofile --norc"],check=True)
    subprocess.run(['tmux','-S',remote_socket,'set-option','-t','=teclado:','@tt_session_id','c'*32],check=True)
    with (conf/'fixadas').open('a') as f: f.write('remota\tteclado\t'+'c'*32+'\n')
    key='fx'+hashlib.sha256(('remota\t'+'c'*32).encode()).hexdigest()[:12]
    subprocess.run([command,'--ir-fixada',remote_client('renomeada'),key],env=env,check=True)
    wait_frame('TT_TELA_TECLADO');bridge_keys=current()
    subprocess.run(['tmux','-L',outer,'send-keys','-t','=pc:','-l',"printf '%s%s\\n' TT_ENTRADA_ CONFERE"],check=True)
    subprocess.run(['tmux','-L',outer,'send-keys','-t','=pc:','Enter'],check=True)
    wait_frame('TT_ENTRADA_CONFERE')
    subprocess.run(['tmux','-L',outer,'resize-window','-t','=pc','-x','105','-y','31'],check=True)
    until=time.monotonic()+5
    while time.monotonic()<until:
        sizes=call(['tmux','-S',remote_socket,'list-clients','-F','#{session_name} #{client_width}']).splitlines()
        if 'teclado 105' in sizes: break
        time.sleep(.02)
    else: raise AssertionError('redimensionamento não chegou ao cliente remoto: '+str(sizes))
    subprocess.run(['tmux','-L',outer,'resize-window','-t','=pc','-x','120','-y','35'],check=True)
    click('teclado','a')
    subprocess.run(['tmux','kill-session','-t','='+bridge_keys],check=True)
    subprocess.run(['tmux','-S',remote_socket,'kill-session','-t','=teclado'],check=True)
    print('fluxo: renomeação com ID constante, teclado e redimensionamento preservados')
    subprocess.run(['tmux','kill-session','-t','='+bridge_b],check=True)
    until=time.monotonic()+5
    while time.monotonic()<until:
        if len(call(['tmux','-S',remote_socket,'list-clients','-F','#{session_name}']).splitlines())==1:
            break
        time.sleep(.02)
    else:
        raise AssertionError('fechar ponte deixou cliente remoto fantasma')
finally:
    subprocess.run([command,'--precarregar','off'],env=env,check=False,stdout=subprocess.DEVNULL)
    remote_tt.unlink(missing_ok=True);share.unlink(missing_ok=True)
