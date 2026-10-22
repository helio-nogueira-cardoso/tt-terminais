#!/usr/bin/env bash
# Quadros do letreiro que mudam de fato: com velocidade mais lenta que 1 coluna por quadro, o tt reduz os quadros
# (e os gatilhos por cliente) a fps/R sem mudar a tela: o deslocamento do letreiro-tt.py dá o MESMO valor em
# qualquer instante com fps e com fps/R. Páginas, velocidade vazia e casos não divisíveis ficam como estão.
source "$(dirname "$0")/lib.sh"; isolar
source <(sed -n '/^letreiro_fps_efetivo() {/,/^}/p' "$TT")
casos=("20 0.5" "20 0.25" "20 0.125" "8 0.125" "20 0.3" "20 1" "6 0.5" "12 0.2" "20 2" "6 0.1" "10 0.15" "16 0.0625")
for c in "${casos[@]}"; do
  set -- $c
  e=$(letreiro_fps_efetivo "$1" "$2" continua)
  python3 -I - "$TT_DIR/letreiro-tt.py" "$1" "$e" "$2" <<'PY' || falhou "fps $1 → $e com veloc $2 muda a tela"
import importlib.util, sys
sp = importlib.util.spec_from_file_location("lt", sys.argv[1]); lt = importlib.util.module_from_spec(sp); sp.loader.exec_module(lt)
f, e, v = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
cfg = {"ticker_veloc": v, "ticker_rolagem": "continua"}
t0 = 1792666000.0
for i in range(20000):
    t = t0 + i * 0.0137
    if lt.deslocamento(cfg, 80, t, False, f) != lt.deslocamento(cfg, 80, t, False, e):
        sys.exit(1)
PY
done
[[ $(letreiro_fps_efetivo 20 0.5 continua) == 2 && $(letreiro_fps_efetivo 20 0.125 continua) == 10 ]] || falhou 'redução esperada não aconteceu (20 quadros a 2 e a 8 colunas/s)'
[[ $(letreiro_fps_efetivo 20 0.5 paginas) == 20 && $(letreiro_fps_efetivo 6 '' continua) == 6 && $(letreiro_fps_efetivo 20 0.3 continua) == 20 ]] || falhou 'páginas, velocidade vazia ou caso não divisível mudaram'
passou "letreiro: quadros reduzidos ao que muda, mesma tela em ${#casos[@]} combinações de velocidade e quadros"
