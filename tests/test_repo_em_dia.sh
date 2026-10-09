#!/usr/bin/env bash
# `tt --sincronizar` só roda de um clone que contém o main publicado. Também quando o ramo local não
# tem upstream (worktree, `checkout -B`): em 08/10/2026 um clone assim instalou nas 4 máquinas, pela
# contagem de commits, uma versão divergente que não continha o main publicado (e desfez o que ele
# trazia). O "GitHub" aqui é um repositório bare local; nenhuma rede é usada.
source "$(dirname "$0")/lib.sh"; isolar
cd "$T"
g() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -C "$1" "${@:2}"; }
# O bare nasce com HEAD em main (o padrão do git ainda é master): senão o 2º clone fica sem ramo
# e o "commit publicado depois" não existe — o teste passava em falso.
git init -q --bare publicado.git && git -C publicado.git symbolic-ref HEAD refs/heads/main
git clone -q publicado.git dev 2>/dev/null
for f in tt email-tt.py links-tt.py letreiro-tt.py gatilho-tt.sh tmux.conf tema-tmux.conf tema-terminal.sh tema-agentes.sh memoria-agentes.sh \
         atalhos-padrao atalhos-padrao-mobile README.md AI-DLC.md ia-conta ia-rot ia-login contas-uso.py \
         skill-rodizio-de-contas.md nomeador-local.py skill-tt-terminais.md aidlc-tt NOVIDADES.md; do
  [[ -e $RAIZ/$f ]] && cp "$RAIZ/$f" dev/
done
g dev checkout -q -B main 2>/dev/null
g dev add -A && g dev commit -qm base && g dev push -q -u origin main
# Outro clone publica um commit a mais no "GitHub".
git clone -q publicado.git outro 2>/dev/null
echo "linha publicada depois" >>outro/README.md
g outro commit -qam "publicado depois" && g outro push -q origin HEAD:main
printf 'nome=teste\nrepo=%s\n' "$T/dev" >"$XDG_CONFIG_HOME/tt/config"

# 1) clone atrasado, ramo com upstream: recusado antes de instalar qualquer coisa
saida=$("$T/dev/tt" --sincronizar 2>&1) && falhou "sincronizar rodou de um clone atrasado (com upstream): $saida"
grep -q 'atrás' <<<"$saida" || falhou "sem o aviso de clone atrasado: $saida"
[[ -e $TT_DIR/VERSAO && $(cat "$TT_DIR/VERSAO") != 999* ]] && falhou 'instalou mesmo atrasado'
passou 'clone atrasado com upstream é recusado'

# 2) ramo SEM upstream (checkout -B), ainda atrasado: antes passava direto (regressão de 08/10)
g dev checkout -q -B trabalho
saida=$("$T/dev/tt" --sincronizar 2>&1) && falhou "sincronizar rodou de um ramo sem upstream atrasado: $saida"
grep -q 'atrás' <<<"$saida" || falhou "ramo sem upstream: sem o aviso de clone atrasado: $saida"
passou 'ramo sem upstream também é conferido contra o main publicado'

# 3) em dia (contém o publicado): a checagem passa e a instalação local acontece. TT_FORCAR porque o
# pacote isolado tem a versão fictícia 999 e instalar a 2 seria rebaixar (recusado por desenho).
g dev checkout -q main && g dev pull -q --rebase origin main
saida=$(TT_FORCAR=1 "$T/dev/tt" --sincronizar 2>&1) || falhou "sincronizar em dia falhou: $saida"
grep -q 'atrás' <<<"$saida" && falhou "em dia, mas avisou atraso: $saida"
[[ $(awk '{print $1}' "$TT_DIR/VERSAO" 2>/dev/null) == 2 ]] || falhou "não instalou a versão 2 (VERSAO: $(cat "$TT_DIR/VERSAO" 2>/dev/null))"
passou 'clone em dia sincroniza e instala'

echo 'ok: sincronizar recusa clone que não contém o main publicado, com ou sem upstream no ramo'
