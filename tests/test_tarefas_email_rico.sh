#!/usr/bin/env bash
# Contrato de dados compartilhados: muitos filhos, metadados, Unicode e Graph completo.
source "$(dirname "$0")/lib.sh"; isolar
python3 - "$T" "$TT" <<'PY'
import base64, contextlib, email, email.policy, importlib.util, io, json, os, pathlib, subprocess, sys

root, tt = pathlib.Path(sys.argv[1]), sys.argv[2]
def carregar(nome, arq):
    spec = importlib.util.spec_from_file_location(nome, root / 'pkg' / arq)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod
merge = carregar('merge', 'tarefas-merge.py')
mail = carregar('mailtt', 'email-tt.py')
tid = 'abcdef123456'
desc = ('Descrição longa, acentuação e listas.\n- item de contexto\n' * 2000).strip()
meta = {'desc': merge.b64e(desc + '\n\n⟡ registro privado\nconta=privada\n'),
        'prazo': '1900000123', 'hora': '1', 'prio': '1', 'rep': 'm', 'tags': 'entrega'}
linhas = [[tid, 'aberta', '1792000000', '1792000000', 'Entrega completa', merge.meta_fmt(meta)]]
for i in range(40):
    cod = f'{i + 1:012x}'
    m = {'pai': tid, 'ord': str(i + 1), 'desc': merge.b64e(f'Detalhes da etapa {i}.\n- critério de aceite'),
         'prazo': '1900000000', 'hora': '1', 'prio': '2', 'rep': 'w', 'tags': 'equipe,ação'}
    linhas.append([cod, 'feita' if i == 0 else 'aberta', '1792000000', '1792000000', f'Etapa {i}', merge.meta_fmt(m)])
arq = root / 'home' / '.config' / 'tt' / 'tarefas'
arq.write_text('\n'.join('\t'.join(l) for l in linhas) + '\n')
saida = io.StringIO()
with contextlib.redirect_stdout(saida):
    assert merge.cmd_email(str(arq), tid, 'Entrega completa !alta #entrega') == 0
assunto, corpo, enviada = [base64.b64decode(s).decode() for s in saida.getvalue().strip().split('\t')]
assert 'registro privado' not in corpo and 'conta=privada' not in corpo
rica = mail.demanda_rica(corpo, assunto)
assert rica and rica[0] == desc and len(rica[1]) == 40
assert 'desc=' in rica[1][0] and 'prazo=1900000000' in rica[1][0] and 'tags=equipe,ação' in rica[1][0]
assert 'prazo=1900000123' in rica[4] and 'hora=1' in rica[4] and 'rep=m' in rica[4]
assert 'titulo=' + merge.b64e('Entrega completa') in rica[4]
assert mail.demanda_rica(corpo.replace('Etapa 1', 'Etapa editada', 1), assunto) is None, 'edição manual foi ignorada'
assert mail.demanda_rica(corpo, assunto.replace(tid, 'abcdef999999')) is None, 'pacote tomou outra identidade'
pacote = json.loads(base64.b64decode(corpo.split('tt:3 ')[1]))
pacote['subs']['000000000001']['prazo'] = '1|pai=outro'
ruim = corpo.split('tt:3 ')[0] + 'tt:3 ' + base64.b64encode(json.dumps(pacote).encode()).decode() + '\n'
assert mail.demanda_rica(ruim, assunto) is None, 'metadado não validado'

# O mesmo corpo completo sai da API do Graph e chega ao Maildir sem perder Unicode nem a identidade.
consultas = []
def graph(c, caminho):
    consultas.append(caminho)
    return {'value': [{'id': 'identidade/Graph', 'internetMessageId': '<mesma-mensagem@exemplo.com>',
        'subject': assunto, 'from': {'emailAddress': {'name': 'Remetente', 'address': 'origem@exemplo.com'}},
        'receivedDateTime': '2026-10-21T12:00:00Z', 'isRead': False,
        'bodyPreview': 'somente os primeiros caracteres', 'body': {'contentType': 'text', 'content': corpo},
        'internetMessageHeaders': [{'name': 'Authentication-Results', 'value': 'mx; dmarc=pass header.from=exemplo.com'}]}]}
mail.graph_get = graph
base = root / 'maildir'
mail.graph_sync({}, str(base), 50)
assert 'body,' in consultas[0] and 'internetMessageId' in consultas[0]
eml = next((base / 'INBOX' / 'new').iterdir())
mensagem = email.message_from_bytes(eml.read_bytes(), policy=email.policy.default)
assert mensagem['Message-ID'] == '<mesma-mensagem@exemplo.com>'
assert mensagem.get_body(('plain',)).get_content().replace('\r', '').rstrip() == corpo.rstrip()
saida = io.StringIO()
with contextlib.redirect_stdout(saida):
    assert mail.demanda(str(eml)) == 0
campos = saida.getvalue().strip().split('\t')
assert campos[1] == 'mesma-mensagem@exemplo.com' and campos[3] == 'pass'
assert base64.b64decode(campos[5]).decode() == desc
assert len(base64.b64decode(campos[6]).decode().splitlines()) == 40
assert 'v3=1' in base64.b64decode(campos[7]).decode()

# Paginação e fallback de corpo completo: nunca troca uma tarefa por bodyPreview truncado.
def pagina(c, caminho):
    if 'messages/pagina2' in caminho:
        return {'value': [dict(graph(c, caminho)['value'][0], id='segunda/Graph')]}
    if '/me/messages/' in caminho:
        return {'body': {'contentType': 'text', 'content': corpo}}
    msg = dict(graph(c, caminho)['value'][0], id='primeira/Graph')
    msg.pop('body')
    return {'value': [msg], '@odata.nextLink': 'https://graph.microsoft.com/v1.0/messages/pagina2'}
mail.graph_get = pagina
mail.graph_sync({}, str(base), 2)
assert len(list((base / 'INBOX' / 'new').iterdir())) == 2
anteriores = {p.name: p.read_bytes() for p in (base / 'INBOX' / 'new').iterdir()}
def corpo_ausente(c, caminho):
    if '/me/messages/' in caminho:
        return {}
    msg = dict(graph(c, caminho)['value'][0]); msg.pop('body')
    return {'value': [msg]}
mail.graph_get = corpo_ausente
try:
    mail.graph_sync({}, str(base), 2)
    raise AssertionError('corpo truncado substituiu o espelho anterior')
except RuntimeError as exc:
    assert 'corpo completo' in str(exc)
assert {p.name: p.read_bytes() for p in (base / 'INBOX' / 'new').iterdir()} == anteriores

# Corpo maior que o limite usual de um argumento do sistema vai pelo stdin.
contas = root / 'home' / '.config' / 'tt' / 'email'
contas.mkdir(exist_ok=True)
(contas / 'teste.conf').write_text('nome=Teste\nendereco=origem@exemplo.com\nprovedor=outro\nsmtp_host=127.0.0.1\n')
antes = arq.read_bytes()
ensaio = subprocess.run([tt, '--email-enviar', '--conta', 'teste', '--para', 'destino@exemplo.com',
                        '--tarefa', tid, '--ensaio'], capture_output=True, text=True)
assert ensaio.returncode == 0, ensaio.stderr
assert 'Etapa 39' in ensaio.stdout and 'tt:3 ' not in ensaio.stdout
assert arq.read_bytes() == antes, 'ensaio mudou a base'

# Menus públicos alcançam envio, recebimento e configuração de remetentes.
src = (root / 'pkg' / 'tt').read_text()
assert '--email-enviar --tarefas-ui --tarefa $id' in src
assert '📥 Tarefas recebidas / Entrada' in src and '--clique entrada' in src
print('ok: 40 subtarefas completas, descrição longa exata, privacidade, edição manual, validação e ida/volta Graph')
PY
