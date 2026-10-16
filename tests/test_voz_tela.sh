#!/usr/bin/env bash
# 🎤 nos computadores: o voz no pacote, o canal da janela (voz --turno com VOZ_TELA_FD), o cérebro padrão, a escolha do
# gravador e da voz em Linux, macOS e WSL (voz-audio.py com VOZ_SISTEMA e programas falsos), a gravação até o silêncio,
# a janela da conversa num tmux isolado (microfone, transcrição e voz falsos) e o atalho @janela do tt (Ctrl+B v).
# Nada usa microfone, alto-falante, modelo ou Claude de verdade.
source "$(dirname "$0")/lib.sh"; isolar
V=$RAIZ/voz; A=$RAIZ/voz-audio.py
bash -n "$V" || falhou "sintaxe: $V"
python3 -m py_compile "$A" || falhou "sintaxe: $A"

B=$T/fake; mkdir -p "$B"
cat >"$B/tt" <<'FIM'
#!/usr/bin/env bash
case $1 in
  --maquinas) printf 'u@h1 dell\nu@h2 book\n' ;;
  --saude) printf 'Saude das maquinas cadastradas:\n  \033[32m●\033[0m dell             ok\n  \033[31m●\033[0m book             timeout\n  ● units locais     0 em falha\n' ;;
  --listar-tudo) printf '# mestre de obras — mesa — 20260101T000000Z\n' ;;
esac
FIM
chmod +x "$B"/*
export PATH="$B:$PATH"

# --- o voz no pacote e no PATH; no celular, o termux/bin/voz roda o da raiz
grep -qE '^ARQUIVOS_FONTE=.*' "$RAIZ/tt" && sed -n '/^ARQUIVOS_FONTE=(/,/)/p' "$RAIZ/tt" | grep -qw 'voz-audio.py' &&
  sed -n '/^ARQUIVOS_FONTE=(/,/)/p' "$RAIZ/tt" | grep -qE '(^| )voz( |$)' || falhou 'voz e voz-audio.py fora do ARQUIVOS_FONTE'
[[ $(bash "$RAIZ/termux/bin/voz" --destino dell) == u@h1 ]] || falhou 'termux/bin/voz não roda o voz da raiz'
[[ $(head -1 "$V") == '#!/usr/bin/env bash' ]] || falhou 'o voz da raiz precisa de um shebang que valha fora do Termux'
passou 'voz no pacote (raiz) e o atalho do celular apontando para ele'

# --- canal da janela: "tipo<TAB>texto" no fd VOZ_TELA_FD; fim encerra; status sem a linha "units"
ev=$(VOZ_TELA_FD=3 bash "$V" --turno maquinas 3>&1 >/dev/null)
[[ $ev == $'fala\tMáquinas: dell, book, mesa. Atual: mesa.' ]] || falhou "evento da fala: '$ev'"
ev=$(VOZ_TELA_FD=3 bash "$V" --turno status 3>&1 >/dev/null)
[[ $ev == $'fala\tmesa, esta, ok. dell ok. book fora do ar.' ]] || falhou "status (sem units, com esta máquina): '$ev'"
ev=$(VOZ_TELA_FD=3 bash "$V" --turno encerrar 3>&1 >/dev/null)
[[ $ev == $'fim\tTerminal encerrado.' ]] || falhou "evento de fim: '$ev'"
grep -q 'você: encerrar' "$HOME/.local/state/tt-voz/conversa.log" && grep -q 'tt: Terminal encerrado.' "$HOME/.local/state/tt-voz/conversa.log" ||
  falhou "conversa.log: $(cat "$HOME/.local/state/tt-voz/conversa.log")"
# o cérebro junta as falas da volta numa só (um evento), e o pedido diz que é o computador
printf '%s' '{"fala": "", "acoes": [{"acao": "status"}]}' >"$T/plano.json"
ev=$(VOZ_TELA_FD=3 VOZ_CEREBRO_CMD="cat > '$T/pedido.txt'; cat '$T/plano.json'" bash "$V" --turno "quem está ligado agora" 3>&1 >/dev/null)
[[ $ev == $'fala\tmesa, esta, ok. dell ok. book fora do ar.' ]] || falhou "cérebro na janela: '$ev'"
grep -q 'microfone do computador' "$T/pedido.txt" || falhou 'o pedido ao cérebro não diz que a conversa é no computador'
passou 'voz --turno: falas, fim e o cérebro chegam à janela pelo VOZ_TELA_FD; status só com as máquinas'

# --- cérebro padrão da janela: o Claude desta máquina (ia-rot), sem configuração; "-" desliga
printf '#!/usr/bin/env bash\ncat >/dev/null; echo %q\n' '{"fala": "Do cérebro local.", "acoes": []}' >"$B/ia-rot"; chmod +x "$B/ia-rot"
[[ $(VOZ_CEREBRO_PADRAO=local bash "$V" --turno "uma frase solta qualquer") == *'Do cérebro local.'* ]] || falhou 'VOZ_CEREBRO_PADRAO=local não usou o ia-rot'
r=$(bash "$V" --audio 2>/dev/null | tail -1); [[ $r == 'cérebro: local ' ]] || falhou "voz --audio (cérebro padrão com ia-rot): '$r'"
bash "$V" --cerebro - >/dev/null
[[ $(VOZ_CEREBRO_PADRAO=local bash "$V" --turno "uma frase solta qualquer") != *'Do cérebro local.'* ]] || falhou '--cerebro - não desligou o padrão'
r=$(bash "$V" --audio 2>/dev/null | tail -1); [[ $r == 'cérebro: ' ]] || falhou "voz --audio com o cérebro desligado: '$r'"
rm -f "$HOME/.config/tt-voz/cerebro" "$B/ia-rot"
passou 'cérebro: na janela, sem configuração, o Claude desta máquina; voz --cerebro - desliga'

# --- voz-audio.py: escolha do gravador e da voz por sistema
py() { python3 - "$A" "$@"; }
CARREGA='import importlib.util, sys
s = importlib.util.spec_from_file_location("va", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)'
F=$T/f2; mkdir -p "$F"
cat >"$F/parecord" <<'FIM'
#!/bin/sh
sleep 5
FIM
cat >"$F/pw-record" <<'FIM'
#!/bin/sh
head -c 64000 /dev/zero; sleep 5
FIM
cat >"$F/arecord" <<'FIM'
#!/bin/sh
case " $* " in
  *" -l "*) printf 'card 1: Fake [Fake], device 0: Mic (*) []\n' ;;
  *plughw:1,0*) head -c 64000 /dev/urandom; sleep 5 ;;
  *) echo 'arecord: main:850: audio open error: Host is down' >&2; exit 1 ;;
esac
FIM
chmod +x "$F"/*
r=$(PATH="$F:$PATH" VOZ_SISTEMA=Linux VOZ_PROVA_S=0.6 py <<EOF
$CARREGA
g = m.Gravador(); print(g.escolher(), g.nome)
g = m.Gravador(); print(g.escolher(), g.nome)
EOF
)
[[ $r == $'True arecord hw:1,0 (Mic (*))\nTrue arecord hw:1,0 (Mic (*))' ]] ||
  falhou "gravador: o servidor de som mudo e o sem sinal ficam de fora, o microfone direto vale: '$r'"
passou 'gravador: pula o que não entrega som e o que só dá silêncio; acha o microfone direto pelo ALSA e lembra dele'

cat >"$F/say" <<'FIM'
#!/bin/sh
if [ "$1" = -v ] && [ "$2" = '?' ]; then printf 'Alex                en_US    # Hello\nLuciana             pt_BR    # Olá, meu nome é Luciana\n'; exit 0; fi
echo "$*" >>"$SAY_LOG"
FIM
cat >"$F/sox" <<'FIM'
#!/bin/sh
sleep 5
FIM
cat >"$F/powershell.exe" <<'FIM'
#!/bin/sh
printf '%s\n' "$@" >"$PS_LOG"
FIM
chmod +x "$F"/*
r=$(PATH="$F:$PATH" VOZ_SISTEMA=Darwin SAY_LOG=$T/say.log py <<EOF
$CARREGA
print(m.candidatos_gravador()[0][1][:3])
f = m.Falador(); print(f.qual, f.det); f.falar("Olá do Mac")
EOF
)
[[ $r == $'[\'sox\', \'-q\', \'-d\']\nsay say Luciana' ]] || falhou "macOS: gravar pelo sox e falar pelo say com a Luciana: '$r'"
[[ $(<"$T/say.log") == '-v Luciana Olá do Mac' ]] || falhou "say: $(cat "$T/say.log")"
passou 'macOS: grava pelo sox (dispositivo padrão) e fala pelo say com a voz pt-BR'

: >"$T/sock"
r=$(PATH="$F:$PATH" VOZ_SISTEMA=WSL VOZ_WSLG=$T/sock PS_LOG=$T/ps.log env -u PULSE_SERVER python3 - "$A" <<EOF
$CARREGA
import os
c = m.candidatos_gravador(); print(c[0][0], os.environ.get("PULSE_SERVER"))
f = m.Falador(); print(f.qual); f.falar("Ação concluída")
EOF
)
[[ $r == "parecord unix:$T/sock"$'\nwindows' ]] || falhou "WSL: gravar pelo PulseAudio do WSLg e falar com a voz do Windows: '$r'"
b64=$(grep -o "FromBase64String('[^']*')" "$T/ps.log" | sed "s/.*('//; s/')//")
[[ $(printf '%s' "$b64" | base64 -d) == 'Ação concluída' ]] || falhou "texto para o Windows (UTF-8 em base64): $(cat "$T/ps.log")"
grep -q "pt-BR" "$T/ps.log" || falhou 'a voz do Windows deveria preferir a pt-BR'
passou 'WSL: grava pelo PulseAudio do WSLg (PULSE_SERVER) e fala com a voz pt-BR do Windows (acentos intactos)'

printf '#!/bin/sh\necho "$*" >>"$SPD_LOG"\n' >"$F/spd-say"; chmod +x "$F/spd-say"
r=$(PATH="$F:$PATH" VOZ_SISTEMA=Linux SPD_LOG=$T/spd.log py <<EOF
$CARREGA
f = m.Falador(); print(f.qual); f.falar("oi")
EOF
)
[[ $r == spd && $(<"$T/spd.log") == '-w -l pt-BR -r 15 oi' ]] || falhou "Linux sem Piper: spd-say em pt-BR: '$r' $(cat "$T/spd.log" 2>/dev/null)"
passou 'Linux sem o Piper instalado: fala pelo spd-say em pt-BR'

# --- gravar até o silêncio: fala detectada pelo nível, silêncio, e o Espaço que encerra
python3 -c 'import math, struct, sys
sys.stdout.buffer.write(b"\0\0" * 4000 + b"".join(struct.pack("<h", int(6000 * math.sin(i * 0.17))) for i in range(16000)))' >"$T/tom.raw"
GRAV="cat '$T/tom.raw'; while :; do head -c 3200 /dev/zero || exit 0; sleep 0.1; done"
r=$(VOZ_GRAVADOR="$GRAV" VOZ_PAUSA=0.6 py <<EOF
$CARREGA
g = m.Gravador(); g.escolher(); pcm, motivo = g.frase(); print(motivo, round(len(pcm) / 2 / 16000, 1))
EOF
)
read -r mot dur <<<"$r"
[[ $mot == fala ]] && awk -v d="$dur" 'BEGIN { exit !(d >= 1.0 && d <= 2.2) }' || falhou "frase com 1 s de fala: '$r'"
r=$(VOZ_GRAVADOR="while :; do head -c 3200 /dev/zero || exit 0; sleep 0.1; done" VOZ_ESPERA_FALA_S=1 py <<EOF
$CARREGA
import time
g = m.Gravador(); g.escolher(); t = time.time(); pcm, motivo = g.frase(); print(motivo, len(pcm), time.time() - t < 4)
EOF
)
[[ $r == 'silencio 0 True' ]] || falhou "silêncio: '$r'"
passou 'gravação: a fala começa pelo nível e acaba no silêncio; sem fala, "silencio" depois da espera'

# --- a janela da conversa: microfone, transcrição e voz falsos; o voz e o cérebro de regras de verdade
J=$T/janela; mkdir -p "$J"; echo 0 >"$J/n"
printf 'máquinas\n' >"$J/frases"
cat >"$J/stt" <<'FIM'
#!/bin/sh
# transcrição falsa: a próxima linha de frases (o áudio vem no stdin)
cat >/dev/null; n=$(($(cat "$J/n") + 1)); echo $n >"$J/n"; sed -n "${n}p" "$J/frases"
FIM
chmod +x "$J/stt"
export J
# o cérebro deixa um filho em segundo plano com o canal aberto: a volta acaba quando o voz acaba, sem esperar por ele
printf '%s' '{"fala": "Tudo certo por aqui.", "acoes": []}' >"$J/plano.json"
tmux new-session -d -s conversa -x 100 -y 30 -e VOZ_GRAVADOR="$GRAV" -e VOZ_STT_CMD="$J/stt" -e VOZ_PAUSA=0.5 \
  -e VOZ_CEREBRO_CMD="cat >/dev/null; (sleep 40 >/dev/null 2>&1 &); cat '$J/plano.json'" \
  -e VOZ_ESPERA_FALA_S=60 -e VOZ_TTS_CMD="cat >>'$J/falas'; echo >>'$J/falas'" -e J="$J" -e PATH="$PATH" \
  "bash '$V' --conversa; echo SAIU=\$? >'$J/saiu'; sleep 60"
espera_tela() { local i; for i in $(seq 100); do tmux capture-pane -p -J -t '=conversa:' 2>/dev/null | grep -qF "$1" && return 0; sleep 0.2; done; return 1; }
espera_tela 'Atual: mesa' || falhou "a frase falada não virou resposta: $(tmux capture-pane -p -J -t '=conversa:')"
tela=$(tmux capture-pane -p -J -t '=conversa:')
grep -q 'você: máquinas' <<<"$tela" && grep -q 'tt: Terminal. Máquina mesa, nenhuma sessão escolhida. Pode falar.' <<<"$tela" ||
  falhou "transcrição na janela: $tela"
grep -q 'Máquinas: dell, book, mesa. Atual: mesa.' "$J/falas" && grep -q 'Terminal. Máquina mesa' "$J/falas" || falhou "a voz não disse as respostas: $(cat "$J/falas")"
# ouvindo de novo: t digita uma frase
espera_tela 'Espaço: terminei' || falhou 'não voltou a ouvir'
tmux send-keys -t '=conversa:' t; sleep 0.4; tmux send-keys -t '=conversa:' -l 'onde'; tmux send-keys -t '=conversa:' Enter
espera_tela 'Máquina mesa, nenhuma sessão escolhida.' || falhou "frase digitada: $(tmux capture-pane -p -J -t '=conversa:')"
grep -q 'você: onde' <<<"$(tmux capture-pane -p -J -t '=conversa:')" || falhou 'a frase digitada não apareceu como sua'
espera_tela 'Espaço: terminei' || falhou 'depois da frase digitada, não voltou a ouvir'
tmux send-keys -t '=conversa:' t; sleep 0.4; tmux send-keys -t '=conversa:' -l 'como vai tudo por aí'; tmux send-keys -t '=conversa:' Enter
espera_tela 'tt: Tudo certo por aqui.' || falhou "frase solta ao cérebro: $(tmux capture-pane -p -J -t '=conversa:')"
t0=$(date +%s); espera_tela 'Espaço: terminei' && (($(date +%s) - t0 < 10)) ||
  falhou 'um filho do voz em segundo plano prendeu a volta (a janela não voltou a ouvir)'
tmux send-keys -t '=conversa:' Escape
for i in $(seq 50); do [[ -s $J/saiu ]] && break; sleep 0.2; done
[[ $(<"$J/saiu") == SAIU=0 ]] || falhou "Esc não fechou a janela: $(cat "$J/saiu" 2>/dev/null)"
passou 'janela: ouve, mostra e fala a resposta; t digita uma frase; volta a ouvir; Esc fecha'

# "encerrar" falado fecha sozinha
echo 0 >"$J/n"; printf 'encerrar\n' >"$J/frases"; rm -f "$J/saiu"; tmux kill-session -t '=conversa' 2>/dev/null || true
tmux new-session -d -s conversa2 -x 100 -y 30 -e VOZ_GRAVADOR="$GRAV" -e VOZ_STT_CMD="$J/stt" -e VOZ_PAUSA=0.5 \
  -e VOZ_TTS_CMD="cat >/dev/null" -e J="$J" -e PATH="$PATH" "bash '$V' --conversa; echo SAIU=\$? >'$J/saiu'; sleep 60"
for i in $(seq 100); do [[ -s $J/saiu ]] && break; sleep 0.2; done
[[ $(cat "$J/saiu" 2>/dev/null) == SAIU=0 ]] || falhou "encerrar não fechou a janela: $(tmux capture-pane -p -J -t '=conversa2:')"
tmux kill-session -t '=conversa2' 2>/dev/null || true
passou 'janela: "encerrar" diz Terminal encerrado e fecha'

# sem gravador: avisa e segue digitando
tmux new-session -d -s conversa3 -x 100 -y 30 -e VOZ_GRAVADOR= -e PATH="$T/vazio:/usr/bin:/bin" -e VOZ_TTS_CMD="cat >/dev/null" \
  "env PATH='$B:/usr/bin:/bin' VOZ_SISTEMA=Darwin bash '$V' --conversa; sleep 60"
espera_tela_em() { local i; for i in $(seq 80); do tmux capture-pane -p -J -t "=$1:" 2>/dev/null | grep -qF "$2" && return 0; sleep 0.2; done; return 1; }
espera_tela_em conversa3 'Sem microfone' && espera_tela_em conversa3 'você>' ||
  falhou "sem gravador: $(tmux capture-pane -p -J -t '=conversa3:')"
tmux kill-session -t '=conversa3' 2>/dev/null || true
passou 'sem programa para gravar: a janela diz o que instalar e segue digitando'

# --- celular com o Tasker: a janela abre a conversa nele, mostra o conversa.log e o que se digita vai ao daemon
P=$T/com.termux/usr; mkdir -p "$P" "$HOME/.config/tt-voz" "$T/sd/Tasker/voz/in"; touch "$HOME/.config/tt-voz/ativo"
echo $$ >"$HOME/.local/state/tt-voz/daemon.pid"  # daemon "de pé": o garantir não sobe outro
printf '#!/bin/sh\necho "$*" >>"%s"\n' "$T/am.log" >"$B/am"; chmod +x "$B/am"
tmux new-session -d -s celular -x 60 -y 20 -e PREFIX="$P" -e VOZ_SDCARD="$T/sd" -e PATH="$PATH" "bash '$V' --conversa; sleep 60"
espera_tela_em celular 'A conversa abre no Tasker' || falhou "celular: $(tmux capture-pane -p -J -t '=celular:')"
grep -q 'tt.VOZ_ABRIR' "$T/am.log" || falhou 'celular: a janela não abriu a conversa no Tasker'
echo "12:00:00 tt: Dito pelo Tasker." >>"$HOME/.local/state/tt-voz/conversa.log"
espera_tela_em celular 'tt: Dito pelo Tasker.' || falhou "celular: a janela não mostrou o conversa.log: $(tmux capture-pane -p -J -t '=celular:')"
tmux send-keys -t '=celular:' t; sleep 0.4; tmux send-keys -t '=celular:' -l 'status'; tmux send-keys -t '=celular:' Enter
for i in $(seq 25); do ls "$T/sd/Tasker/voz/in/"tela-*.txt >/dev/null 2>&1 && break; sleep 0.2; done
[[ $(cat "$T/sd/Tasker/voz/in/"tela-*.txt 2>/dev/null) == status ]] || falhou 'celular: o que se digita não foi ao daemon'
tmux kill-session -t '=celular' 2>/dev/null || true; rm -f "$HOME/.config/tt-voz/ativo" "$HOME/.local/state/tt-voz/daemon.pid"
passou 'celular: o 🎤 abre a conversa no Tasker, a janela mostra o que foi dito e manda ao daemon o que se digita'

# --- o atalho 🎤 do tt: @janela abre o comando numa janela flutuante (não numa sessão), também pelo Ctrl+B v
grep -qP '^🎤\tvoz\t@janela voz --conversa\t' "$RAIZ/atalhos-padrao" && grep -qP '^🎤\tvoz\t@janela voz --conversa\t' "$RAIZ/atalhos-padrao-mobile" ||
  falhou 'o 🎤 não está nos atalhos padrão'
grep -q "bind v run-shell -b \"~/.local/bin/tt --clique voz " "$RAIZ/tmux.conf" || falhou 'Ctrl+B v não chama o 🎤'
"$TT" --atalhos-lista | grep -qP '^🎤\tvoz\t@janela voz --conversa' || falhou "o 🎤 não aparece na lista de atalhos: $("$TT" --atalhos-lista)"
printf '🎤\tvoz\t@janela echo "janela $(pwd)" >%s\t#cba6f7\n' "$T/janela.out" >"$XDG_CONFIG_HOME/tt/atalhos"
tmux new -d -s inicio -x 120 -y 30 -c "$T" 'sleep 600'
anexar tela 120 30 inicio; sleep 0.8
cli=$(tmux list-clients -F '#{client_name}' | head -1); pane=$(tmux display -p -t '=inicio:' '#{pane_id}')
antes=$(tmux list-sessions -F '#{session_name}' | sort)
"$TT" --clique voz "$cli" "$pane" "$T" &
for i in $(seq 40); do [[ -s $T/janela.out ]] && break; sleep 0.2; done
[[ $(cat "$T/janela.out" 2>/dev/null) == "janela $T" ]] || falhou "Ctrl+B v / @janela não rodou o comando na pasta do painel: $(cat "$T/janela.out" 2>/dev/null)"
[[ $(tmux list-sessions -F '#{session_name}' | sort) == "$antes" ]] || falhou '@janela criou uma sessão (devia ser uma janela flutuante)'
wait
i=$("$TT" --atalhos-lista | cut -f2 | grep -n '^voz$' | cut -d: -f1); rm -f "$T/janela.out"
"$TT" --clique "at$i" "$cli" "$pane" "$T" &
for i in $(seq 40); do [[ -s $T/janela.out ]] && break; sleep 0.2; done
[[ -s $T/janela.out ]] || falhou 'o clique no 🎤 da barra não abriu a janela'
wait
passou 'atalho 🎤: @janela roda numa janela flutuante na pasta do painel, pelo clique e pelo Ctrl+B v'

# --- instalação: o voz vai para o ~/.local/bin (fora do celular)
instalar_isolado
[[ $(readlink "$HOME/.local/bin/voz") == "$HOME/.local/share/tt/voz" && -x $HOME/.local/share/tt/voz-audio.py ]] ||
  falhou "instalação: ~/.local/bin/voz -> $(readlink "$HOME/.local/bin/voz" 2>/dev/null)"
passou 'instalação: voz no PATH, voz-audio.py executável no pacote'
