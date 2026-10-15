#!/usr/bin/env python3
"""Gera tt-voz.prj.xml, o projeto OPCIONAL do Tasker para falar com o tt por voz (ver `termux/celular.sh voz`).

Duas peças, sem nenhuma ação sobre o aparelho além de ler/gravar arquivos em /sdcard/Tasker/voz, dizer texto e ouvir:
  Terminal         sem texto, abre a conversa (%TTVOZ_CONVERSA=1); com texto em %par1 (Assistente em inglês: "run
                   terminal with status in Tasker"), manda só aquela frase. Grava em /sdcard/Tasker/voz/in/ para o
                   `voz --daemon` do Termux.
  tt voz: falar    perfil do intent tt.VOZ_FALAR (mandado pelo `voz`): lê fala.txt, diz com o "Dizer" do Tasker e, em
                   conversa, ouve a próxima frase (getVoice) e a grava em in/. Silêncio ou "encerrar" fecham a conversa.
                   Extra ouvir=0 (avisos como "Enviado"): só fala. Zera voz/falando quando termina de dizer.
                   Não usa o microfone do celular com a tela apagada, no carro (alguma global de
                   /sdcard/Tasker/voz/carro.txt vale 1, ex. a do seu perfil de Android Auto) ou se a escuta falha
                   na hora (celular bloqueado): manda "__sem_microfone__" e o `voz` explica como seguir (pelo Telegram).
  tt voz: abrir    perfil do intent tt.VOZ_ABRIR (`voz --abrir`): abre a conversa (roda Terminal sem texto).
  tt voz: Android Auto  perfil da notificação do Android Auto ("... está conectado"): avisa o `voz`, que manda pelo bot do
                   Telegram (se ligado) a mensagem "pronto" que você responde falando na tela do carro.
Uso: python3 termux/tasker/gerar-voz.py   (grava termux/tasker/tt-voz.prj.xml)
"""
import os
from xml.sax.saxutils import escape as E

T0 = 1791030000000


def S(i, v=''):
    return f'<Str sr="arg{i}" ve="3">{E(v)}</Str>' if v != '' else f'<Str sr="arg{i}" ve="3"/>'


def I(i, v=0):
    return f'<Int sr="arg{i}" val="{v}"/>'


class Task:
    def __init__(self, id, name):
        self.id, self.name, self.acts = id, name, []

    def js(self, code, timeout=30):
        self.acts.append((129, S(0, code) + S(1) + I(2, 1) + I(3, timeout)))

    def setvar(self, nome, valor):
        self.acts.append((547, S(0, nome) + S(1, valor) + I(2) + I(3) + I(4) + I(5, 3) + I(6, 1)))

    def say(self, text):
        self.acts.append((559, '<se>false</se>' + S(0, text) + S(1, 'default:default') + I(2, 3) + I(3, 5) +
                          I(4, 5) + I(5, 1) + I(6, 0) + I(7, 0)))

    def xml(self):
        a = ''.join(f'<Action sr="act{i}" ve="7"><code>{c}</code>{b}</Action>' for i, (c, b) in enumerate(self.acts))
        return (f'<Task sr="task{self.id}"><cdate>{T0}</cdate><edate>{T0}</edate><id>{self.id}</id>'
                f'<nme>{E(self.name)}</nme><pri>100</pri>{a}</Task>')


entrada = Task(21, 'Terminal')
entrada.js(r"""var t=(typeof par1!=='undefined'&&String(par1).indexOf('%')!==0)?String(par1):'';
t=t.replace(/^\s+|\s+$/g,'');
setGlobal('TTVOZ_CONVERSA', t ? '0' : '1');
createDir('/sdcard/Tasker/voz/in', true, false);
writeFile('/sdcard/Tasker/voz/in/'+Date.now()+'.txt', t||'terminal', false);""")

falar = Task(22, 'tt voz: falar')
falar.js(r"""var fala=''; try{ fala=String(readFile('/sdcard/Tasker/voz/fala.txt')||''); }catch(e){}
fala=fala.replace(/\s+/g,' ').replace(/^\s+|\s+$/g,'');
if(!fala) fala='Sem resposta.';""")
falar.say('%fala')
falar.js(r"""writeFile('/sdcard/Tasker/voz/falando', '0', false);
if (global('TTVOZ_CONVERSA') == '1' && !(typeof ouvir !== 'undefined' && String(ouvir) == '0')) {
  var carro = false;
  try { String(readFile('/sdcard/Tasker/voz/carro.txt') || '').split(/[\s,]+/).forEach(function (v) {
    v = v.replace(/^%/, ''); if (/^[A-Z][A-Za-z0-9_]+$/.test(v) && global(v) == '1') carro = true; }); } catch (e) {}
  var r, t = '', ini = Date.now();
  if (carro || global('SCREEN') == 'off') t = '__sem_microfone__';
  else {
    try { r = getVoice('Terminal', 'free', 15); } catch (e) {}
    if (r !== undefined && r !== null) t = (typeof r === 'object' && r.length) ? String(r[0]) : String(r).split(',')[0];
    t = t.replace(/^\s+|\s+$/g, '');
    if (!t && Date.now() - ini < 4000) t = '__sem_microfone__';
  }
  if (t == '__sem_microfone__' || !t || /^(encerrar|sair|tchau|fim|terminar|desligar)[.!]?$/i.test(t)) {
    setGlobal('TTVOZ_CONVERSA', '0'); if (t != '__sem_microfone__') t = 'encerrar';
  }
  writeFile('/sdcard/Tasker/voz/in/' + Date.now() + '.txt', t, false);
}""", timeout=45)

aa = Task(24, 'tt voz: Android Auto')
aa.setvar('%ntitle', '%evtprm2')
aa.js(r"""var t = (typeof ntitle !== 'undefined' && String(ntitle).indexOf('%') !== 0) ? String(ntitle) : '';
if (/conect|connect/i.test(t)) {  // "Conectando ao Android Auto" e "O Android Auto está conectado"; o voz evita repetir
  createDir('/sdcard/Tasker/voz/in', true, false);
  writeFile('/sdcard/Tasker/voz/in/' + Date.now() + '.txt', '__android_auto__', false);
}""")
GEARHEAD = ('<App sr="arg0"><appClass/><appPkg>com.google.android.projection.gearhead</appPkg>'
            '<label>Android Auto</label></App>')


def perfil(id, nome, tarefa, evento):
    return (f'<Profile sr="prof{id}" ve="2"><cdate>{T0}</cdate><edate>{T0}</edate><flags>8</flags><id>{id}</id>'
            f'<mid0>{tarefa.id}</mid0><nme>{E(nome)}</nme><Event sr="con0" ve="2">{evento}</Event></Profile>')


def intent(acao):
    return f'<code>599</code><pri>0</pri>{S(0, acao)}{S(1)}{S(2)}{S(3)}{S(4)}'


perfis = [perfil(31, 'tt voz: falar', falar, intent('tt.VOZ_FALAR')),
          perfil(32, 'tt voz: abrir', entrada, intent('tt.VOZ_ABRIR')),
          # 461 = Notificação (do app Android Auto); %evtprm2 = título
          perfil(34, 'tt voz: Android Auto', aa,
                 f'<code>461</code><pri>0</pri>{GEARHEAD}{S(1)}{S(2)}{S(3)}{S(4)}{S(5)}{S(6)}{I(7)}')]
xml = ('<TaskerData sr="" dvi="1" tv="6.6.20">' + ''.join(perfis) +
       f'<Project sr="proj0" ve="2"><cdate>{T0}</cdate><name>tt-voz</name><pids>31,32,34</pids>'
       f'<tids>{entrada.id},{falar.id},{aa.id}</tids></Project>' + entrada.xml() + falar.xml() + aa.xml() +
       '</TaskerData>')
destino = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tt-voz.prj.xml')
open(destino, 'w', encoding='utf-8').write(xml)
print(destino, len(xml), 'bytes')
