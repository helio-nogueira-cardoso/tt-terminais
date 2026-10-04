#!/usr/bin/env bash
# Vigia numa aba do Claude: o primeiro nome vem do título da conversa; depois, mesmo com o título
# parado (o aiTitle não muda ao longo da conversa), o nome acompanha os pedidos mais recentes.
source "$(dirname "$0")/lib.sh"; isolar

# Um "claude" falso em duas partes. A tela: um link chamado claude para o bash (o vigia acha o
# Claude pelo nome do processo; sob proot, um script com shebang apareceria como "bash")
# que registra a sessão como o Claude Code e escreve a cada segundo (cada volta do vigia vê uso).
# O Haiku: ~/.local/bin/claude, chamado com -p, nomeia pelo último pedido que recebeu.
mkdir -p "$HOME/.local/bin" "$HOME/.claude/sessions" "$HOME/.claude/projects/p" "$T/bin"
conversa=$HOME/.claude/projects/p/conversa-1.jsonl
ln -s "$(command -v bash)" "$T/bin/claude"
cat >"$T/tela-claude.sh" <<EOF
echo '{"pid":'\$\$',"sessionId":"conversa-1","status":"busy","name":"x"}' >"$HOME/.claude/sessions/\$\$.json"
while :; do date +%s%N; sleep 1; done
EOF
cat >"$HOME/.local/bin/claude" <<'EOF'
#!/usr/bin/env bash
case $(grep '^- ' | tail -1) in
  *PEDIDO-B*) echo tarefa-beta ;;
  *PEDIDO-A*) echo tarefa-alfa ;;
  *) echo vazio ;;
esac
EOF
chmod +x "$HOME/.local/bin/claude"
dizer() { printf '{"type":"user","message":{"role":"user","content":"%s"}}\n' "$1" >>"$conversa"; }
titulo() { printf '{"type":"ai-title","aiTitle":"%s","sessionId":"conversa-1"}\n' "$1" >>"$conversa"; }
dizer 'PEDIDO-A primeiro assunto'
printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"PEDIDO-B não é pedido"}]}}\n' >>"$conversa"
titulo 'Página do primeiro assunto'

tmux -f /dev/null new -d -s atalho-1 "exec $T/bin/claude $T/tela-claude.sh"
nome() { tmux list-sessions -F '#{session_name}' | grep -v '^guarda$' | head -1; }
esperar() { # nome-esperado segundos
  local i
  for ((i = 0; i < $2; i++)); do [[ $(nome) == "$1" ]] && return 0; sleep 1; done
  return 1
}
tmux -f /dev/null new -d -s guarda 'sleep 600' # o vigia só roda enquanto houver tmux

TT_PAUSA=1 TT_T_PRIMEIRO=1 TT_T_RENOMEAR=2 TT_INTERACOES_RENOMEAR=2 TT_T_REVISAO=999999 \
  "$TT" --vigia >/dev/null 2>&1 &

esperar pagina-primeiro-assunto 20 || falhou "primeiro nome não veio do título (ficou $(nome))"
for ((i = 0; i < 5; i++)); do # o vigia grava o título logo depois do rename
  t=$(tmux show-options -qv -t '=pagina-primeiro-assunto:' @nome_titulo); [[ -n $t ]] && break; sleep 1
done
[[ $t == 'Página do primeiro assunto' ]] || falhou "título guardado errado: $t"
passou 'aba do Claude: primeiro nome é o título da conversa'

# O título fica parado; a revisão lê os pedidos (resultados de ferramenta não contam).
esperar tarefa-alfa 30 || falhou "com o título parado a aba não foi revisada (ficou $(nome))"
passou 'título parado: o vigia revisa a aba do Claude pelos pedidos'

dizer 'PEDIDO-B mudei de assunto'
esperar tarefa-beta 30 || falhou "o nome não acompanhou o pedido mais recente (ficou $(nome))"
passou 'o nome acompanha a tarefa atual da conversa'

# Um título novo continua valendo na hora.
titulo 'Outro título'
esperar outro-titulo 20 || falhou "título novo não foi seguido (ficou $(nome))"
passou 'título novo da conversa é seguido'
