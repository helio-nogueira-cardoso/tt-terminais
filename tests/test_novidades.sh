#!/usr/bin/env bash
# Novidades do tt: mostra só o que saiu depois da última versão vista, --todas mostra tudo, o vigia
# avisa uma vez por versão nova (sem avisar máquina recém-instalada), e o clique no aviso do agente
# vai ao painel mesmo com a sessão renomeada.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado; TT=$HOME/.local/bin/tt
ES=$HOME/.local/state/tt
cat >"$TT_DIR/NOVIDADES.md" <<'N'
# Novidades
## v1.7.2 · 01/01/2099
- coisa nova C — atualização com ação
## v1.7.1 · 01/01/2099
- coisa nova B
## v1.7.0 · 01/01/2099
- coisa velha A
## v1.5.3 · 01/01/2099
- coisa legada Z
N
echo "312 teste 2099-01-01 1.7.2" >"$TT_DIR/VERSAO"
echo 1.7.0 >"$(mkdir -p "$ES"; echo "$ES/novidades-visto")"
saida=$("$TT" --novidades)
grep -q 'coisa nova C' <<<"$saida" && grep -q 'coisa nova B' <<<"$saida" || falhou "faltou novidade: $saida"
grep -q 'coisa velha A' <<<"$saida" && falhou 'mostrou o que já foi visto'
[[ $(cat "$ES/novidades-visto") == 1.7.2 ]] || falhou 'não marcou como visto'
passou 'mostra só o que saiu depois da última versão vista, e marca como visto'
saida=$("$TT" --novidades --todas); grep -q 'coisa velha A' <<<"$saida" || falhou '--todas deveria mostrar tudo'
passou '--todas mostra tudo'

# Vigia: versão nova → um aviso (ação novidades); repetido na mesma versão → nada.
rm -rf "$ES/notifs" "$ES/novidades-avisada"; echo 1.7.0 >"$ES/novidades-visto"
"$TT" --novidades-avisar; "$TT" --novidades-avisar
n=$(grep -lE $'\tnovidades(\t|$)' "$ES"/notifs/* 2>/dev/null | wc -l || true); ((n == 1)) || falhou "esperava 1 aviso, vi $n"
# Máquina recém-instalada (sem registro do que foi visto): não avisa.
rm -rf "$ES/notifs" "$ES/novidades-avisada" "$ES/novidades-visto"; "$TT" --novidades-avisar
[[ -z $(ls "$ES/notifs" 2>/dev/null) ]] || falhou 'avisou numa máquina recém-instalada'
[[ $(cat "$ES/novidades-visto") == 1.7.2 ]] || falhou 'recém-instalada deveria marcar a versão atual'
passou 'vigia avisa uma vez por versão nova; instalação nova não é incomodada'

# O aviso leva o código da versão; se outra máquina já anunciou a versão (chegou pela sincronização) ou o
# usuário já o apagou, esta máquina não cria um segundo.
rm -rf "$ES/notifs" "$ES/novidades-avisada"; echo 1.7.0 >"$ES/novidades-visto"
"$TT" --novidades-avisar
grep -q $'\tnovidades\t-\tnovidades-v1.7.2$' "$ES"/notifs/* || falhou 'o aviso deveria levar o código novidades-v1.7.2'
rm -rf "$ES/notifs" "$ES/novidades-avisada"; echo 1.7.0 >"$ES/novidades-visto"; mkdir -p "$ES/notifs"
printf '%s\t%s\t%s\t%s\t%s\n' 9999999999 'anunciado pela empresa' novidades - novidades-v1.7.2 >"$ES/notifs/1000000000000000007"
"$TT" --novidades-avisar
n=$(ls "$ES"/notifs | grep -cE '^[0-9]{18,20}$'); ((n == 1)) || falhou "com o aviso de outra máquina, esperava 1, vi $n"
rm -rf "$ES/notifs" "$ES/novidades-avisada"; echo 1.7.0 >"$ES/novidades-visto"; mkdir -p "$ES/notifs"
echo 'codigo=novidades-v1.7.2' >"$ES/notifs/1000000000000000007.apagada"
"$TT" --novidades-avisar
n=$(ls "$ES"/notifs | grep -cE '^[0-9]{18,20}$' || true); ((n == 0)) || falhou "aviso apagado pelo usuário voltou ($n)"
passou 'código por versão: um aviso só na rede; apagado não volta'

# O rótulo instalado sai da contagem de commits e anda com commits sem entrada no NOVIDADES.md (e com quem publica ao mesmo tempo): os
# títulos ficam ABAIXO do rótulo (aqui 1.7.9 instalado, títulos até 1.7.2). O que vale é a ordem do arquivo: novo = o que está acima do
# último título visto. Antes, nada contava como novo e o aviso nunca saía.
echo "320 teste 2099-01-01 1.7.9" >"$TT_DIR/VERSAO"
rm -rf "$ES/notifs" "$ES/novidades-avisada"; echo 1.7.0 >"$ES/novidades-visto"
saida=$("$TT" --novidades)
grep -q 'coisa nova C' <<<"$saida" && grep -q 'coisa nova B' <<<"$saida" && ! grep -q 'coisa velha A' <<<"$saida" || falhou "título abaixo do rótulo: $saida"
[[ $(cat "$ES/novidades-visto") == 1.7.2 ]] || falhou "deveria marcar o título mais novo (1.7.2), marcou $(cat "$ES/novidades-visto")"
saida=$("$TT" --novidades); grep -q 'coisa nova C' <<<"$saida" || true   # nada novo: cai nas 3 mais recentes, sem marcar nada além do topo
[[ $(cat "$ES/novidades-visto") == 1.7.2 ]] || falhou 'rever sem novidade mexeu no marcador'
# aviso: sai com texto novo, mesmo com rótulo maior que os títulos; e só um, mesmo com o rótulo andando (commits sem novidade)
rm -rf "$ES/notifs" "$ES/novidades-avisada"; echo 1.7.0 >"$ES/novidades-visto"
"$TT" --novidades-avisar
echo "321 teste 2099-01-01 1.7.10" >"$TT_DIR/VERSAO"; "$TT" --novidades-avisar
echo "322 teste 2099-01-01 1.7.11" >"$TT_DIR/VERSAO"; "$TT" --novidades-avisar
n=$(grep -lE $'\tnovidades(\t|$)' "$ES"/notifs/* 2>/dev/null | wc -l || true); ((n == 1)) || falhou "rótulo andando sem novidade nova: esperava 1 aviso, vi $n"
grep -q $'\tnovidades\t-\tnovidades-v1.7.2$' "$ES"/notifs/* || falhou 'o código do aviso deveria ser o do título mais novo (novidades-v1.7.2)'
# visto o texto, o rótulo andar não avisa de novo
rm -rf "$ES/notifs" "$ES/novidades-avisada"; "$TT" --novidades >/dev/null; "$TT" --novidades-avisar
[[ -z $(ls "$ES/notifs" 2>/dev/null) ]] || falhou 'avisou de novo o que já foi visto'
# título novo entra ACIMA mesmo com número menor que o rótulo e até menor que um título abaixo (quem publica ao mesmo tempo escolhe números diferentes)
{ printf '# Novidades\n## v1.7.1 · 01/01/2099\n- coisa nova D, com título fora de ordem\n'; sed '1d' "$TT_DIR/NOVIDADES.md"; } >"$TT_DIR/NOVIDADES.novo" && mv "$TT_DIR/NOVIDADES.novo" "$TT_DIR/NOVIDADES.md"
echo 1.7.2 >"$ES/novidades-visto"
# (o marcador 1.7.2 é o 2º título agora: o que está acima dele é novo)
saida=$("$TT" --novidades); grep -q 'coisa nova D' <<<"$saida" || falhou "título fora de ordem não apareceu: $saida"
passou 'novidades: vale a ordem do arquivo (títulos abaixo do rótulo e fora de ordem aparecem; um aviso só)'
# volta o arquivo do teste ao que os testes seguintes esperam
sed -i.bak '2,3d' "$TT_DIR/NOVIDADES.md" && rm -f "$TT_DIR/NOVIDADES.md.bak"
echo "312 teste 2099-01-01 1.7.2" >"$TT_DIR/VERSAO"

# Estado antigo (só o nº de commits) vale como 1.6.N: não reabre o que já passou, mas mostra a série nova.
echo 999 >"$ES/novidades-visto"; saida=$("$TT" --novidades)
grep -q 'coisa nova C' <<<"$saida" && ! grep -q 'coisa legada Z' <<<"$saida" || falhou "estado numérico antigo: $saida"
passou 'estado antigo (nº de commits) é lido como 1.6.N'

# Clique do agente: vale o nome ATUAL da sessão do painel.
tmux -f /dev/null new -d -s antigo -x 120 -y 30 'sleep 300'; tmux new -d -s outra 'sleep 300'
anexar cli 120 30 outra; sleep 1.2
c=$(tmux list-clients -F "#{client_name}" | head -1); p=$(tmux list-panes -t antigo -F '#{pane_id}')
tmux rename-session -t antigo novo
TMUX="$(tmux display -p "#{socket_path}"),1,0" "$TT" --notif-abrir "sessao:antigo|$p" "$c"; sleep 0.7
[[ $(tmux list-clients -F '#{client_session}' | head -1) == novo ]] || falhou "não foi à sessão renomeada: $(tmux list-clients -F '#{client_session}')"
passou 'o clique do aviso do agente acha a sessão renomeada pelo id do painel'
# Num terminal a tela SEGURA o texto (antes o less saía sozinho com pouco texto e o popup piscava).
res=$(python3 - "$TT" <<'PY'
import os, pty, sys, time, select
tt = sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"; os.environ["LINES"] = "40"; os.environ["COLUMNS"] = "100"
    # Reproduz Debian sem locale configurado (POSIX/ASCII), como no proot do S23.
    os.environ["LANG"] = "C"; os.environ["LC_ALL"] = "C"
    os.environ.pop("LC_CTYPE", None); os.environ.pop("LESSCHARSET", None)
    os.execvp(tt, [tt, "--novidades", "--todas"])
out = b""; t0 = time.time()
while time.time() - t0 < 2.5:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try: out += os.read(fd, 4096)
        except OSError: break
done, _ = os.waitpid(pid, os.WNOHANG)
vivo = done == 0
if vivo:
    os.write(fd, b"q")
    # drena a saída enquanto espera: no macOS o processo só termina depois que alguém lê o fim do pty
    fim = time.time() + 1.5
    while time.time() < fim:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try: os.read(fd, 4096)
            except OSError: pass
        done, _ = os.waitpid(pid, os.WNOHANG)
        if done: break
utf8 = "atualização com ação".encode() in out
print("SEGUROU_UTF8" if vivo and done and utf8 else "PISCOU" if not vivo else "NAO-FECHOU-NO-Q" if not done else "UTF8-ESCAPOU")
PY
)
[[ $res == SEGUROU_UTF8 ]] || falhou "tela de novidades em locale ASCII: $res"
passou 'tela de novidades fica aberta e mostra UTF-8 mesmo sem locale UTF-8'
# Formatador: **negrito** e `código` viram estilo do terminal (nada de asterisco ou crase crua), subitem
# ganha ◦ e recuo, e nenhuma linha passa da largura pedida (a continuação alinha com o texto do item).
fmt=$(printf '%s\n' '## v9.9.9 · 01/01/2099' \
  '- **Negrito longo aqui.** Texto com `codigo` e mais palavras para quebrar a linha sem passar da largura.' \
  '  - subitem **forte**' | "$TT" --novidades-fmt 40)
limpo=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$fmt")
grep -q '[*`]' <<<"$limpo" && falhou "sobrou marcação crua: $limpo"
grep -qF $'\e[1mNegrito longo aqui.' <<<"$fmt" && grep -qF $'\e[36mcodigo' <<<"$fmt" || falhou "negrito/código sem estilo: $(cat -v <<<"$fmt")"
grep -q '^    ◦ subitem forte$' <<<"$limpo" && grep -q '^  • Negrito' <<<"$limpo" && grep -q '^    [a-z]' <<<"$limpo" || falhou "marcadores/recuo: $limpo"
python3 -I -c 'import sys, unicodedata as u; sys.exit(max(sum(2 if u.east_asian_width(c) in "WF" else 1 for c in l) for l in sys.stdin.read().splitlines()) > 40)' <<<"$limpo" ||
  falhou "linha mais larga que 40 colunas: $limpo"
passou 'novidades: negrito e código formatados, subitens com recuo, linhas na largura da tela'
# Item escrito em várias linhas no NOVIDADES.md (continuação com recuo): vira um parágrafo só, com o recuo do item.
fmt=$(printf '%s\n' '- primeira linha do item que' '  continua na segunda linha e' '  termina na terceira.' '- outro item' | "$TT" --novidades-fmt 60)
limpo=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$fmt")
grep -q '^  • primeira linha do item que continua na segunda' <<<"$limpo" && grep -q '^    termina na terceira\.$' <<<"$limpo" &&
  grep -q '^  • outro item$' <<<"$limpo" && ! grep -q '^  [a-z]' <<<"$limpo" || falhou "continuação do item não foi juntada: $limpo"
passou 'novidades: linhas de continuação do item entram no mesmo parágrafo, com o recuo dele'
echo "TODOS OS TESTES PASSARAM"
