#!/usr/bin/env bash
# tt --conta-propagar / --conta-receber: propaga os arquivos próprios de uma conta do ia-conta
# (credencial e afins) para as outras máquinas, sem levar os dados compartilhados (links para
# ~/.claude), recriando os links locais e o atalho claude-<nome>. Sem rede: o ssh é falso e roda o
# comando remoto aqui mesmo, no mesmo HOME isolado.
source "$(dirname "$0")/lib.sh"; isolar
instalar_isolado
mkdir -p "$HOME/.claude"

R=$HOME/.local/share/claude-contas
cred='{"claudeAiOauth":{"accessToken":"segredo","expiresAt":0}}'

# --- conta-receber: tar válido instala a conta, cria atalho e links de dados compartilhados ------
# Dados compartilhados em ~/.claude (para os links apontarem para cá).
mkdir -p "$HOME/.claude/projects" "$HOME/.claude/sessions"
printf 'hist\n' >"$HOME/.claude/history.jsonl"
# Pacote (tar) com só os itens próprios.
pac=$T/pac; mkdir -p "$pac"
echo "$cred" >"$pac/.credentials.json"
echo 'conta@exemplo.com' >"$pac/.account-email"
echo '{}' >"$pac/.claude.json"
mkdir -p "$pac/backups"; echo 'bkp' >"$pac/backups/b1"
tar -C "$pac" -cf "$T/itau.tar" .credentials.json .account-email .claude.json backups

out=$("$TT" --conta-receber itau <"$T/itau.tar")
grep -q "instalada" <<<"$out" || falhou "conta-receber não confirmou: $out"
[[ -s $R/itau/.credentials.json ]] || falhou 'credencial não gravada'
grep -q segredo "$R/itau/.credentials.json" || falhou 'credencial com conteúdo errado'
[[ -f $R/itau/.claude.json && -d $R/itau/backups ]] || falhou 'itens próprios não gravados'
# .account-email é cache: o receber apaga para o ia-conta recriar no host.
[[ -e $R/itau/.account-email ]] && falhou '.account-email deveria ser removido no destino'
# Links de dados compartilhados apontando para o ~/.claude local.
[[ -L $R/itau/projects && $(readlink -f "$R/itau/projects") == "$(readlink -f "$HOME/.claude/projects")" ]] ||
  falhou 'projects não virou link para o ~/.claude local'
[[ -L $R/itau/history.jsonl ]] || falhou 'history.jsonl não virou link'
# Atalho claude-itau criado e funcional (aponta para claude-conta).
[[ -x $HOME/.local/bin/claude-itau ]] || falhou 'atalho claude-itau não criado'
grep -q 'claude-conta' "$HOME/.local/bin/claude-itau" || falhou 'atalho não chama claude-conta'
# A credencial fica só para o dono.
perm=$(stat -c %a "$R/itau/.credentials.json")
[[ $perm == 600 ]] || falhou "credencial deveria ser 600, é $perm"
passou 'conta-receber: instala credencial, recria links locais e cria o atalho'

# Idempotente: receber de novo não quebra nem duplica.
out=$("$TT" --conta-receber itau <"$T/itau.tar")
grep -q "instalada" <<<"$out" || falhou "segundo receber falhou: $out"
[[ $(readlink -f "$R/itau/projects") == "$(readlink -f "$HOME/.claude/projects")" ]] || falhou 'link quebrou no segundo receber'
passou 'conta-receber é idempotente'

# --- conta-receber recusa pacote sem credencial, sem gravar nada ---------------------------------
rm -rf "$R/nova"
printf 'lixo' | tar -cf "$T/vazio.tar" -T /dev/null
out=$("$TT" --conta-receber nova <"$T/vazio.tar" 2>&1)
grep -q "sem credencial" <<<"$out" || falhou "deveria recusar sem credencial: $out"
[[ -e $R/nova ]] && falhou 'criou a conta mesmo sem credencial'
passou 'conta-receber recusa pacote sem credencial e não grava nada'

# --- sem Claude Code (sem ~/.claude): pula sem erro e sem criar conta -----------------------------
rm -rf "$HOME/.claude"
out=$("$TT" --conta-receber semclaude <"$T/itau.tar" 2>&1)
grep -q "sem Claude Code" <<<"$out" || falhou "deveria avisar sem Claude: $out"
[[ -e $R/semclaude ]] && falhou 'criou conta onde não há Claude Code'
mkdir -p "$HOME/.claude"  # restaura para os próximos
passou 'conta-receber pula onde não há Claude Code (ex.: celular), sem erro'

# --- conta-propagar: valida a conta de origem ----------------------------------------------------
set +e; out=$("$TT" --conta-propagar naoexiste 2>&1); rc=$?; set -e
[[ $rc != 0 ]] || falhou 'propagar de conta inexistente deveria falhar'
grep -q "não existe aqui" <<<"$out" || falhou "mensagem de origem ausente: $out"
set +e; out=$("$TT" --conta-propagar 2>&1); rc=$?; set -e
[[ $rc != 0 ]] && grep -q "uso:" <<<"$out" || falhou "sem nome deveria mostrar uso: $out"
passou 'conta-propagar valida a conta de origem e o uso'

# --- conta-propagar empacota só os itens próprios (nunca links nem dados compartilhados) ----------
# Conta de origem com itens próprios e symlinks de dados compartilhados.
mkdir -p "$R/orig"
echo "$cred" >"$R/orig/.credentials.json"
echo '{}' >"$R/orig/.claude.json"
ln -s "$HOME/.claude/projects" "$R/orig/projects"
ln -s "$HOME/.claude/history.jsonl" "$R/orig/history.jsonl"
# ssh falso: ignora opções e host, roda "tt --conta-receber ..." aqui, lendo o tar do stdin, mas em
# vez de instalar só grava o tar recebido para inspeção.
B=$HOME/.local/bin
cat >"$B/ssh" <<EOF
#!/usr/bin/env bash
# último argumento é o comando remoto; só queremos o tar do stdin.
cat >"$T/enviado.tar"
echo "✓ conta 'orig' instalada"
EOF
chmod +x "$B/ssh"
# maquinas() falso: um destino.
printf 'teste\tdell helio book-hl\n' >/dev/null
cat >"$XDG_CONFIG_HOME/tt/maquinas" <<EOF
destino-host helio alvo1
EOF
# tailscale ausente: maquinas_agora lê o cadastro e usa o host como está.
out=$(PATH="$B:$PATH" "$TT" --conta-propagar orig 2>&1 || true)
[[ -s $T/enviado.tar ]] || falhou "propagar não enviou tar: $out"
lista=$(tar -tf "$T/enviado.tar")
grep -qx '.credentials.json' <<<"$lista" || falhou "tar sem credencial: $lista"
grep -qx '.claude.json' <<<"$lista" || falhou "tar sem .claude.json: $lista"
grep -q 'projects' <<<"$lista" && falhou "tar levou link projects (não deveria): $lista"
grep -q 'history.jsonl' <<<"$lista" && falhou "tar levou link history.jsonl (não deveria): $lista"
passou 'conta-propagar empacota só os itens próprios, nunca links de dados compartilhados'
