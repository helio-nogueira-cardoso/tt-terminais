#!/usr/bin/env bash
# Teto do ticker_fps: 1 a 20 (antes 10). Cada quadro além do primeiro custa um gatilho (processo bash por
# cliente), então há teto; acima dele ou lixo volta ao limite/padrão e nada quebra.
source "$(dirname "$0")/lib.sh"; isolar
python3 -I - "$RAIZ/letreiro-tt.py" <<'PY' || falhou "fps_de fora do esperado"
import importlib.util, sys
sp = importlib.util.spec_from_file_location("letreiro", sys.argv[1]); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
casos = {"": 6, "6": 6, "10": 10, "11": 11, "20": 20, "21": 20, "99": 20, "0": 1, "-3": 1, "abc": 6}
for entrada, esperado in casos.items():
    got = m.fps_de({"ticker_fps": entrada})
    assert got == esperado, (entrada, got, esperado)
PY
passou 'fps_de: 1..20, acima do teto vira 20, 0 vira 1 e lixo vira o padrão 6'
for v in 6 10 11 20; do
  printf 'ticker_fps=%s\n' "$v" >>"$XDG_CONFIG_HOME/tt/config"
  n=$(bash -c "source <(sed -n '/^conf()/,/^}/p' '$TT'); CONF=$XDG_CONFIG_HOME/tt/config; fps=\$(conf ticker_fps); [[ \$fps =~ ^([1-9]|1[0-9]|20)\$ ]] && echo \$fps || echo 6")
  [[ $n == "$v" ]] || falhou "ticker_fps=$v virou $n na barra"
  sed -i '/^ticker_fps=/d' "$XDG_CONFIG_HOME/tt/config"
done
grep -q '\^(\[1-9\]|1\[0-9\]|20)\$' "$TT" || falhou "a regex do tt não aceita até 20"
passou 'a barra aceita ticker_fps até 20'
