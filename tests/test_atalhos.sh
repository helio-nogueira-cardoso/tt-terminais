#!/usr/bin/env bash
# Atalhos da barra: perfil de PC, perfil de celular (Termux), e personalização local por ID.
source "$(dirname "$0")/lib.sh"; isolar
ids() { "$TT" --atalhos-lista | cut -f2 | tr '\n' ' '; }

[[ $(ids) == "ia-nova ia-aqui " ]] || falhou "padrão do PC deveria ter 2 atalhos: $(ids)"
"$TT" --atalhos-lista | grep -q $'\tia-conta abrir\t' || falhou 'ia-nova do PC não abre a melhor IA'
passou 'PC: 2 atalhos padrão (melhor IA numa sessão nova ou no painel atual)'

m=$(PREFIX=/data/data/com.termux/files/usr "$TT" --atalhos-lista)
grep -q 'proot-distro login debian' <<<"$m" || falhou 'celular: atalhos não entram no Debian (proot)'
grep -q "bash -lc '.*ia-conta abrir'" <<<"$m" || falhou 'celular: ia-nova sem ia-conta abrir no Debian'
passou 'celular: perfil mobile (ia-conta abrir no Debian via proot)'

# O atalho acha o ia-conta mesmo que o login do Debian não ponha ~/.local/bin no PATH (o ~/.bashrc
# do proot do S23 perdeu a linha e os atalhos terminavam com código 127).
deb=$T/debian-root; mkdir -p "$deb/.local/bin" "$T/fb"
printf '#!/bin/sh\necho "ia-conta $*"\n' >"$deb/.local/bin/ia-conta"; chmod +x "$deb/.local/bin/ia-conta"
# proot-distro falso: descarta tudo até o "--" e roda o resto com a casa do Debian e o PATH do sistema.
printf '#!/usr/bin/env bash\nwhile (($#)) && [[ $1 != -- ]]; do shift; done; shift\nexec env -i HOME="$DEB" PATH=/usr/bin:/bin "$@"\n' >"$T/fb/proot-distro"
chmod +x "$T/fb/proot-distro"
for id in ia-nova ia-aqui; do
  cmd=$(awk -F'\t' -v id="$id" '$2 == id { print $3 }' <<<"$m"); cmd=${cmd#@aqui }; cmd=${cmd//\{retomar\}/}
  out=$(DEB=$deb PATH=$T/fb:$PATH bash -c "$cmd" 2>&1) || falhou "celular: $id falhou sem ~/.local/bin no login do Debian: $out"
  [[ $out == 'ia-conta abrir' ]] || falhou "celular: $id rodou outra coisa: $out"
done
passou 'celular: atalhos acham o ia-conta mesmo sem ~/.local/bin no PATH do login do Debian'

c=$XDG_CONFIG_HOME/tt/atalhos
printf '🔧\tia-aqui\tcodex --yolo\t#f38ba8\n-\tia-nova\t\t\n⚡\tmeu\thtop\t#a6e3a1\n' >"$c"
[[ $(ids) == "ia-aqui meu " ]] || falhou "personalização: $(ids)"
"$TT" --atalhos-lista | grep -q $'^🔧\tia-aqui\tcodex --yolo' || falhou 'troca de um padrão pelo mesmo ID'
passou 'local: troca padrão pelo ID, "-" desativa, ID novo acrescenta no fim'

printf '🅰\tum\tls\t\n🅱\tdois\tls\t\n🅰\tum\tpwd\t\n' >"$c"
[[ $("$TT" --atalhos-lista | awk -F'\t' '$2 == "um"' | wc -l) == 1 ]] || falhou 'ID repetido aparece duas vezes'
"$TT" --atalhos-lista | grep -q $'\tum\tpwd' || falhou 'a última linha de um ID deveria valer'
passou 'ID repetido no arquivo local: vale a última, sem duplicar o botão'
