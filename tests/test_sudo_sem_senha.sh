#!/usr/bin/env bash
# Pendência "sudo sem senha": aparece (nível recurso) enquanto o sudo pede senha; aceitar grava, pelo próprio sudo,
# uma regra NOPASSWD em sudoers.d conferida pelo visudo (modo 0440) e ela some; regra recusada pelo visudo não é
# gravada; com o sudo já sem senha, nada a fazer. sudo de mentira (TT_SUDO_BIN) e sudoers.d temporário
# (TT_SUDOERS_DIR): nunca toca o sistema.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
mkdir -p "$T/bin" "$T/sudoers"
cat >"$T/bin/fsudo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$T/sudo.log"
if [[ \$1 == -n ]]; then [[ -e "$T/liberado" ]]; exit; fi
case \$1 in
  visudo) [[ -z \${FAKE_VISUDO_FALHA:-} ]] && grep -q 'NOPASSWD: ALL' "\$3" ;;
  install) src=\${@: -2:1}; dst=\${@: -1}; cp "\$src" "\$dst" && chmod 0440 "\$dst" && touch "$T/liberado" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/bin/fsudo"
export TT_PEND_SEM_SUDO_SEM_SENHA="" TT_SUDO_BIN=$T/bin/fsudo TT_SUDOERS_DIR=$T/sudoers TT_TTY=/dev/null
f=$T/sudoers/tt-sem-senha-$(id -un | sed 's/[^A-Za-z0-9_-]/_/g')

grep -q $'^sudo-sem-senha\tfalta\trecurso\tsudo sem senha' <<<"$("$TT" --pendencias --tsv)" || falhou "pendência ausente ou errada: $("$TT" --pendencias --tsv | grep sudo)"
passou 'com o sudo pedindo senha, a pendência "sudo sem senha" aparece (recurso)'

saida=$(FAKE_VISUDO_FALHA=1 "$TT" --pedir-sudo --sim sudo-sem-senha 2>&1) || true
grep -q 'visudo recusou' <<<"$saida" && [[ ! -e $f ]] || falhou "regra recusada pelo visudo não pode ser gravada: $saida"
passou 'regra recusada pelo visudo: nada é gravado'

saida=$("$TT" --pedir-sudo --sim sudo-sem-senha 2>&1)
grep -q 'sudo sem senha ativo' <<<"$saida" || falhou "aceitar deveria ativar: $saida"
[[ -f $f && $(stat -c %a "$f") == 440 ]] || falhou "regra ausente ou com modo errado: $(ls -l "$T/sudoers")"
grep -qx "$(id -un) ALL=(ALL) NOPASSWD: ALL" "$f" || falhou "regra errada: $(cat "$f")"
grep -q '^install -m 0440 -o root -g root ' "$T/sudo.log" || falhou "a regra deveria entrar pelo sudo, com dono root e modo 0440: $(cat "$T/sudo.log")"
grep -q $'^sudo-sem-senha\tok\t' <<<"$("$TT" --pendencias --tsv)" || falhou 'depois de ativar, a pendência deveria ficar ok'
grep -q 'Configuração do sistema:.*NOPASSWD' <<<"$saida" || falhou "o modal deveria mostrar o comando exato: $saida"
! grep -q 'na sua pasta (sem administrador)' <<<"$saida" || falhou "passo de administrador listado como feito sem administrador: $saida"
passou 'aceitar grava a regra pelo sudo (visudo, 0440, dono root), o modal mostra o comando (não como passo sem administrador) e a pendência fica ok'
