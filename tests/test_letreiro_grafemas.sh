#!/usr/bin/env bash
# Letreiro recorta por grafema, não por caractere. Uma bandeira (🇧🇷 = duas letras regionais) partida na borda do
# recorte deixava uma letra regional sozinha: 1 coluna para o tmux 3.8 e 2 para o Ghostty 1.3. Na faixa, que é a
# última linha da tela, a coluna a mais quebrava a linha e a tela inteira rolava (linhas duplicadas, barras
# deslocadas até o próximo redesenho). Também ficam inteiros ZWJ, tom de pele e keycap; somem o que os dois medem
# diferente (letra regional sozinha, VS15, VS16 depois de letra comum) e a largura de cada grafema é a do tmux.
source "$(dirname "$0")/lib.sh"; isolar
python3 -I - "$TT_DIR/letreiro-tt.py" <<'PY' || falhou 'recorte do letreiro parte grafemas ou erra a largura'
import importlib.util, sys
sp = importlib.util.spec_from_file_location("lt", sys.argv[1]); lt = importlib.util.module_from_spec(sp); sp.loader.exec_module(lt)
RI = lambda c: 0x1F1E6 <= ord(c) <= 0x1F1FF
g = lt.grafemas
assert g("🇦🇷 Peso") == ["🇦🇷", " ", "P", "e", "s", "o"], g("🇦🇷 Peso")
assert g("a🇦b") == ["a", "b"], "letra regional sozinha deveria sumir"
assert g("👨‍👩‍👧x") == ["👨‍👩‍👧", "x"]
assert g("👍🏽") == ["👍🏽"] and g("1️⃣") == ["1️⃣"] and g("é") == ["é"]
assert g("🕰2022")[:2] == ["🕰️", "2"] and g("❤") == ["❤️"] and g("© ™ →") == ["©", " ", "™", " ", "→"]
assert g("❤️") == ["❤️"] and g("x️") == ["x"] and g("🌍︎") == ["🌍"] and g("✌") == ["✌️"]
larg = {"🇦🇷": 2, "👨‍👩‍👧": 2, "👍🏽": 2, "1️⃣": 2, "é": 1, "❤️": 2, "❤": 1, "✌️": 2,
        "🌍": 2, "a": 1, "🌡": 1, "—": 1}
for k, v in larg.items():
    assert lt.larg(k) == v, (k, lt.larg(k), v)
roda = lt.Roda()
roda.cel = [(c, None) for c in g("🇦🇷 Peso 🇺🇸 S&P 👨‍👩‍👧 casa ❤️ 👍🏽 1️⃣ fim")]
roda.fim_roda = [(c, None) for c in g(" • ")]
n = len(roda.cel) + len(roda.fim_roda)
for w in (5, 9, 13):
    for off in range(n):
        txt = lt.janela_roda(roda, w, off)
        cel = g(txt)
        assert not any(len(c) == 1 and RI(c) for c in cel), (w, off, txt)
        assert sum(lt.larg(c) for c in cel) == w, (w, off, txt)
t = lt.cortar("🇦🇷 Peso arg. 🇺🇸 dólar", 6)
assert t.endswith("…") and sum(lt.larg(c) for c in g(t)) <= 6 and not any(len(c) == 1 and RI(c) for c in g(t)), t
assert lt.janela("ab🇧🇷cd", 3, 2) == "🇧🇷c", lt.janela("ab🇧🇷cd", 3, 2)
# A roda é guardada entre quadros (remontar custava dezenas de ms por quadro) e se renova quando a fonte muda.
import os, time
os.makedirs(lt.DIR_TICKER, exist_ok=True)
arq = os.path.join(lt.DIR_TICKER, "_teste-memo")
cfg = {"indicadores": "_teste-memo"}
open(arq, "w", encoding="utf-8").write("primeira 🇧🇷\n")
agora = time.time()
assert lt.montar_roda(cfg, agora) is lt.montar_roda(cfg, agora + 1), "a roda deveria vir guardada no quadro seguinte"
assert "".join(c for c, _ in lt.montar_roda(cfg, agora).cel) == "Primeira 🇧🇷"
open(arq, "w", encoding="utf-8").write("segunda\n")
os.utime(arq, ns=(time.time_ns(), time.time_ns() + 10**9))
assert "".join(c for c, _ in lt.montar_roda(cfg, agora + 2).cel) == "Segunda", "fonte mudou e a roda não"
os.unlink(arq)
PY
# A medida que vale é a do tmux: cada recorte impresso num painel deixa o cursor exatamente na coluna w.
if tmux -V | awk '{v=$2+0; exit !(v >= 3.6)}'; then
  py=$(mktemp); trap 'rm -f "$py"' EXIT
  cat >"$py" <<'PY'
import importlib.util, sys
sp = importlib.util.spec_from_file_location("lt", sys.argv[1]); lt = importlib.util.module_from_spec(sp); sp.loader.exec_module(lt)
roda = lt.Roda()
roda.cel = [(c, None) for c in lt.grafemas("🇦🇷 Peso 🇺🇸 S&P 👨‍👩‍👧 casa ❤️ 👍🏽 1️⃣ fim")]
roda.fim_roda = [(c, None) for c in lt.grafemas(" • ")]
print(lt.janela_roda(roda, 9, int(sys.argv[2])).replace("##", "#"), end="")
PY
  tmux new -d -s g -x 40 -y 5 'sleep 60' 2>/dev/null || falhou 'tmux de teste não subiu'
  for off in $(seq 0 40); do
    tmux respawn-pane -k -t g "python3 -I '$py' '$TT_DIR/letreiro-tt.py' $off; sleep 30"
    x=; for _ in $(seq 1 20); do sleep 0.05; x=$(tmux display -p -t g '#{cursor_x}'); [[ $x != 0 ]] && break; done
    [[ $x == 9 ]] || falhou "recorte $off ocupa $x colunas no tmux, não 9: [$(tmux capture-pane -p -t g | head -1)]"
  done
  tmux kill-server 2>/dev/null
fi
passou 'letreiro recorta por grafema: nenhuma bandeira partida, largura igual à do tmux em todo recorte'
