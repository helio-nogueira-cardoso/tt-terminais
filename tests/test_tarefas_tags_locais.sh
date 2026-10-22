#!/usr/bin/env bash
# Etiquetas locais: migração conservadora, edição e ida/volta por e-mail.
source "$(dirname "$0")/lib.sh"; isolar
python3 - "$T" "$TT" <<'PY'
import base64, contextlib, importlib.util, io, json, pathlib, subprocess, sys
root, tt = pathlib.Path(sys.argv[1]), sys.argv[2]
spec = importlib.util.spec_from_file_location('merge', root/'pkg/tarefas-merge.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
spec = importlib.util.spec_from_file_location('mail', root/'pkg/email-tt.py')
mail = importlib.util.module_from_spec(spec); spec.loader.exec_module(mail)
arq = root/'home/.config/tt/tarefas'; cad = arq.with_name('demandas')
cad.write_text('felipe@example.com\tnetto\trelaxado\t-\t100\n')
tid, sid, manual, arc = 'abcdef123456', 'abcdef123457', 'abcdef123458', 'abcdef123459'
def linha(i, meta, estado='aberta'):
    return '\t'.join([i, estado, '100', '100', 'Entrega', m.meta_fmt(meta)])+'\n'
arq.write_text(linha(tid, {'de':'felipe@example.com','tags':'netto,cliente'})+
               linha(sid, {'pai':tid,'ord':'1','tags':'equipe,_local'})+
               linha(manual, {'tags':'netto'})+
               linha(arc, {'de':'felipe@example.com','tags':'netto,arquivo'}, 'arquivada'))
buf = io.StringIO()
with contextlib.redirect_stdout(buf): m.cmd_tags_migrar(str(arq), str(cad), 200)
arq.write_text(buf.getvalue())
linhas = m.ler(str(arq))
assert m.meta_ler(linhas[tid][5])['tags'] == '_netto,cliente'
assert m.meta_ler(linhas[manual][5])['tags'] == 'netto'
assert m.meta_ler(linhas[arc][5])['tags'] == '_netto,arquivo'
buf = io.StringIO()
with contextlib.redirect_stdout(buf): m.cmd_tags_migrar(str(arq), str(cad), 201)
assert buf.getvalue() == arq.read_text(), 'migração não idempotente'
# A instalação usa a mesma migração sob trava, com backup privado antes de gravar.
arq.write_text(linha(tid, {'de':'felipe@example.com','tags':'netto,cliente'})+
               linha(sid, {'pai':tid,'ord':'1','tags':'equipe,_local'})+
               linha(manual, {'tags':'netto'})+
               linha(arc, {'de':'felipe@example.com','tags':'netto,arquivo'}, 'arquivada'))
original = arq.read_bytes()
comando = ['bash','-c','TT_COMPLETO=1 TT_SO_CARREGAR=1 source "$1"; demandas_tags_migrar','_',tt]
r = subprocess.run(comando, capture_output=True, text=True)
assert r.returncode == 0, (r.stdout,r.stderr)
backups = list((root/'home/.local/state/tt/migracoes').glob('tarefas-tags-locais.*'))
assert len(backups) == 1 and backups[0].read_bytes() == original, backups
assert backups[0].stat().st_mode & 0o777 == 0o600
migrada = arq.read_bytes()
r = subprocess.run(comando, capture_output=True, text=True)
assert r.returncode == 0 and arq.read_bytes() == migrada
assert list(backups[0].parent.glob('tarefas-tags-locais.*')) == backups
antes = arq.read_bytes()
r = subprocess.run([tt, '--tarefa-editar', tid, 'Entrega #_forjada'], capture_output=True, text=True)
assert r.returncode != 0 and arq.read_bytes() == antes, (r.stdout,r.stderr)
r = subprocess.run([tt, '--tarefa-editar', tid, 'Entrega #nova'], capture_output=True, text=True)
assert r.returncode == 0, r.stderr
linhas = m.ler(str(arq)); tags = m.meta_ler(linhas[tid][5])['tags'].split(',')
assert tags == ['nova','_netto'], tags
buf = io.StringIO()
with contextlib.redirect_stdout(buf): m.cmd_email(str(arq), tid, 'Entrega #nova #_netto')
assunto, corpo, enviada = [base64.b64decode(s).decode() for s in buf.getvalue().strip().split('\t')]
pacote = json.loads(base64.b64decode(corpo.split('tt:3 ')[1]))
assert '_netto' not in assunto+corpo+enviada+json.dumps(pacote)
assert '_local' not in json.dumps(pacote)
assert pacote['tarefa']['tags'] == 'nova' and pacote['subs'][sid]['tags'] == 'equipe'
# Dados externos nunca atribuem etiquetas locais à máquina que recebe.
pacote['tarefa']['tags'] += ',_forjada'
pacote['subs'][sid]['tags'] += ',_forjada'
forjado = corpo.split('tt:3 ')[0]+'tt:3 '+base64.b64encode(json.dumps(pacote).encode()).decode()+'\n'
rica = mail.demanda_rica(forjado, assunto)
assert rica and '_forjada' not in str(rica)
# Etiquetas locais não são divergência no merge e não desaparecem ao aplicar.
pid='abcdef123460'
with arq.open('a') as f:
    f.write(linha(pid, {'upd':tid,'de':'outro@example.com','tags':'nova,_outro','v3':'1'}, 'pendente'))
buf=io.StringIO()
with contextlib.redirect_stdout(buf): assert m.cmd_aplicar(str(arq),pid,300,'','inc') == 0
for l in buf.getvalue().splitlines():
    if l.startswith(tid+'\t'):
        tags=m.meta_ler(l.split('\t')[5])['tags'].split(',')
        assert tags == ['nova','_netto','_outro'], tags
print('ok: tags locais reservadas, migração idempotente, edição sem perda e e-mail sem etiquetas de origem')
PY
