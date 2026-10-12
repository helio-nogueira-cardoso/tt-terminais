#!/usr/bin/env bash
# Bloco do tt no ~/.bashrc: a instalação troca só o miolo do bloco e nunca apaga o resto do arquivo,
# nem quando falta o marcador de fim (foi assim que o Debian do S23 perdeu a linha do PATH e os
# atalhos de IA passaram a terminar com código 127).
source "$(dirname "$0")/lib.sh"; isolar
rc=$HOME/.bashrc
INI='# >>> tt (terminais em tmux) >>>' FIM='# <<< tt (terminais em tmux) <<<'
modo() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
# A mesma versão de novo não instala nada ("já instalada"): cada reinstalação sobe o número.
n=1000
reinstalar() {
  n=$((n + 1)); echo "$n outro 2099-01-02" >"$T/pkg/VERSAO"
  TT_DIR=$HOME/.local/share/tt "$T/pkg/tt" --instalar-aqui >/dev/null 2>&1 || falhou 'reinstalação'
  grep -q "^$n " "$HOME/.local/share/tt/VERSAO" || falhou 'reinstalação não aconteceu'
}

# Bloco sem marcador de fim, com coisas do usuário antes e depois dele.
{ echo 'antes=1'; echo "$INI"; echo '# miolo velho'
  echo 'if [[ $- == *i* ]]; then'; echo '  exec "$HOME/.local/bin/tt" --janela'; echo 'fi'
  echo 'export PATH="$HOME/.local/bin:$PATH"'; } >"$rc"
chmod 644 "$rc"
instalar_isolado
grep -qx 'antes=1' "$rc" || falhou 'sumiu o que vinha antes do bloco'
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$rc" || falhou "sumiu o que vinha depois do bloco sem marcador de fim: $(cat "$rc")"
[[ $(grep -cxF "$INI" "$rc") == 1 && $(grep -cxF "$FIM" "$rc") == 1 && $(grep -c -- '--janela$' "$rc") == 1 ]] ||
  falhou "bloco com marcadores errados ou duplicado: $(cat "$rc")"
grep -q 'miolo velho' "$rc" && falhou 'o miolo velho do bloco ficou'
awk -v f="$FIM" '$0 == f { m = NR } /^export PATH=/ { p = NR } END { exit !(m && p > m) }' "$rc" ||
  falhou 'o que vinha depois não ficou depois do bloco'
[[ $(modo "$rc") == 644 ]] || falhou "permissões do ~/.bashrc mudaram: $(modo "$rc")"
passou 'bashrc: bloco sem marcador de fim é fechado sem apagar o resto; permissões mantidas'

# Sem marcador de fim e sem o "fi" do tt --janela não dá para saber onde o bloco acaba: não mexe.
printf '%s\n' 'antes=1' "$INI" '# só o começo' 'depois=1' >"$rc"
antes=$(cksum <"$rc")
reinstalar
[[ $(cksum <"$rc") == "$antes" ]] || falhou "mexeu num ~/.bashrc cujo bloco não tem fim reconhecível: $(cat "$rc")"
passou 'bashrc: bloco sem fim reconhecível fica intocado'

# ~/.bashrc que é link (dotfiles) continua link, e o bloco vai para o arquivo apontado.
mkdir -p "$HOME/dotfiles"; printf '%s\n' 'meu=1' "$INI" "$FIM" 'fim=1' >"$HOME/dotfiles/bashrc"
rm -f "$rc"; ln -s "$HOME/dotfiles/bashrc" "$rc"
reinstalar
[[ -L $rc ]] || falhou '~/.bashrc deixou de ser link'
grep -q -- '--janela$' "$HOME/dotfiles/bashrc" && grep -qx 'meu=1' "$HOME/dotfiles/bashrc" && grep -qx 'fim=1' "$HOME/dotfiles/bashrc" ||
  falhou "bloco não foi para o arquivo apontado: $(cat "$HOME/dotfiles/bashrc")"
passou 'bashrc: link de dotfiles preservado'
