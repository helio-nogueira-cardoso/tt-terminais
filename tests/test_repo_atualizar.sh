#!/usr/bin/env bash
# Máquina de desenvolvimento (repo= de um clone git): repo_atualizar traz o publicado sem perder commit local
# (avança; rebase quando divergiu; conflito guarda os commits num ramo local/<data> e segue o publicado), recusa
# com arquivo versionado mudado e não gravado, e move acréscimos locais do .gitignore para .git/info/exclude.
# tt --repo-checar explica o que trava. Nunca usa stash.
source "$(dirname "$0")/lib.sh"; isolar
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
G=(git -c commit.gpgsign=false)
PUB=$T/pub DEV=$T/dev
mkdir -p "$PUB"; "${G[@]}" -C "$PUB" init -q -b main
printf 'a\nb\nc\n' >"$PUB/arq.txt"; printf 'tmp/\n' >"$PUB/.gitignore"; cp "$T/pkg/tt" "$PUB/tt"
"${G[@]}" -C "$PUB" add -A; "${G[@]}" -C "$PUB" commit -qm base
git clone -q "$PUB" "$DEV"
ra() { TT_COMPLETO=1 bash -c 'TT_SO_CARREGAR=1 source "$1"; repo_atualizar "$2"' _ "$TT" "$DEV" 2>&1; }
pubc() { echo "$1" >>"$PUB/$2"; "${G[@]}" -C "$PUB" commit -qam "pub $1"; }
devc() { echo "$1" >>"$DEV/$2"; "${G[@]}" -C "$DEV" commit -qam "dev $1"; }
stash_antes=$(git -C "$DEV" stash list | wc -l)

# 1) Só atrás: avança.
pubc p1 arq.txt; saida=$(ra)
[[ $(git -C "$DEV" rev-parse HEAD) == $(git -C "$PUB" rev-parse HEAD) ]] || falhou "não avançou: $saida"
passou 'clone só atrás: avança para o publicado'

# 2) Divergiu sem conflito: os commits locais são reaplicados sobre o publicado; nenhum ramo de sobra.
pubc p2 arq.txt; echo d1 >"$DEV/outro.txt"; "${G[@]}" -C "$DEV" add outro.txt; "${G[@]}" -C "$DEV" commit -qm "dev d1"
saida=$(ra)
git -C "$DEV" merge-base --is-ancestor "$(git -C "$PUB" rev-parse HEAD)" HEAD || falhou "o publicado não entrou: $saida"
grep -q d1 "$DEV/outro.txt" || falhou "o commit local se perdeu: $saida"
[[ -z $(git -C "$DEV" branch --list 'local/*') ]] || falhou 'rebase limpo não deveria deixar ramo local/'
passou 'divergiu sem conflito: commit local reaplicado sobre o publicado'

# 3) Divergiu com conflito: os commits locais ficam num ramo local/<data> e o clone segue o publicado.
printf 'X\n' >"$PUB/arq.txt"; "${G[@]}" -C "$PUB" commit -qam "pub conflito"
printf 'Y\n' >"$DEV/arq.txt"; "${G[@]}" -C "$DEV" commit -qam "dev conflito"
local_antes=$(git -C "$DEV" rev-parse HEAD)
saida=$(ra)
[[ $(git -C "$DEV" rev-parse HEAD) == $(git -C "$PUB" rev-parse HEAD) ]] || falhou "com conflito o clone deveria seguir o publicado: $saida"
ramo=$(git -C "$DEV" branch --list 'local/*' --format='%(refname:short)' | head -1)
[[ -n $ramo && $(git -C "$DEV" rev-parse "$ramo") == "$local_antes" ]] || falhou "os commits locais deveriam estar no ramo local/: $saida"
grep -q "ficaram no ramo $ramo" <<<"$saida" || falhou "a mensagem deveria dizer o ramo: $saida"
[[ -z $(git -C "$DEV" status --porcelain --untracked-files=no) ]] || falhou 'o clone ficou sujo depois do conflito'
passou 'conflito: commits locais guardados em local/<data>, clone no publicado, nada perdido'

# 4) Arquivo versionado mudado e não gravado: recusa, lista e não mexe em nada.
echo sujo >>"$DEV/arq.txt"; pubc p3 tt; antes=$(git -C "$DEV" rev-parse HEAD)
saida=$(ra) && falhou 'deveria recusar com mudança não gravada'
grep -q 'arq.txt' <<<"$saida" || falhou "a recusa deveria listar o arquivo: $saida"
[[ $(git -C "$DEV" rev-parse HEAD) == "$antes" ]] && grep -q sujo "$DEV/arq.txt" || falhou 'mexeu no clone com mudança pendente'
"${G[@]}" -C "$DEV" checkout -q -- arq.txt
passou 'mudança não gravada em arquivo versionado: recusa com a lista e não mexe'

# 5) Acréscimos locais no .gitignore vão para .git/info/exclude; o .gitignore volta ao publicado e a atualização segue.
printf 'aidlc/\n.claude/\n' >>"$DEV/.gitignore"; saida=$(ra)
[[ -z $(git -C "$DEV" status --porcelain -- .gitignore) ]] || falhou "o .gitignore deveria voltar ao publicado: $saida"
grep -qx 'aidlc/' "$DEV/.git/info/exclude" && grep -qx '.claude/' "$DEV/.git/info/exclude" || falhou "as linhas locais não foram para o exclude: $(cat "$DEV/.git/info/exclude")"
[[ $(git -C "$DEV" rev-parse HEAD) == $(git -C "$PUB" rev-parse HEAD) ]] || falhou "depois de separar o local, deveria atualizar: $saida"
mkdir -p "$DEV/aidlc"; : >"$DEV/aidlc/x"; [[ -z $(git -C "$DEV" status --porcelain) ]] || falhou 'o que foi para o exclude deveria continuar ignorado'
passou '.gitignore com acréscimos locais: vão para .git/info/exclude e a atualização segue'

# 6) tt --repo-checar explica o que trava; nenhuma etapa usou stash.
echo "repo=$DEV" >>"$XDG_CONFIG_HOME/tt/config"
echo sujo >>"$DEV/arq.txt"; printf 'local\n' >>"$DEV/.gitignore"
saida=$("$TT" --repo-checar 2>&1)
grep -q 'arq.txt — trava o rebase' <<<"$saida" && grep -q '.gitignore — só acréscimos locais' <<<"$saida" || falhou "repo-checar não explicou: $saida"
"$TT" --repo-checar --corrigir >/dev/null 2>&1
[[ -z $(git -C "$DEV" status --porcelain -- .gitignore) ]] || falhou '--corrigir deveria mover o .gitignore local'
[[ $(git -C "$DEV" stash list | wc -l) == "$stash_antes" ]] || falhou 'usou stash'
passou 'tt --repo-checar explica o que trava; --corrigir separa o local; nada de stash'
