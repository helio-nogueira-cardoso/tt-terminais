#!/usr/bin/env bash
# telas-agentes.py + telas-agentes.conf: as telas que os agentes (Claude, Codex, Kiro, Gemini, outros) mostram antes da
# conversa ou no meio dela. Rotina e pasta autorizada: resposta sozinha; senha, credencial, destrutivo, permissão nova de
# execução, dinheiro e o desconhecido: perguntar. Também a lista de pastas e o catálogo do usuário (estender e desligar).
source "$(dirname "$0")/lib.sh"; isolar
P=$RAIZ/telas-agentes.py
D=$T/telas; mkdir -p "$D"
decidir() { python3 -I "$P" decidir --maquina dell --casa /home/helio "$@" < "$D/$TELA"; }
campo() { cut -f"$1" <<<"$R"; }
espera() { # TELA DECISÃO CLASSE [AÇÃO] [args do decidir...]
  TELA=$1; local dec=$2 cl=$3 ac=${4:-}; shift 3; (($#)) && shift
  R=$(decidir "$@")
  [[ $(campo 1) == "$dec" && $(campo 2) == "$cl" && ( -z $ac || $(campo 4) == "$ac" ) ]] ||
    falhou "$TELA: esperava $dec/$cl${ac:+/$ac}, veio: $R"
}

python3 -I "$P" validar || falhou "o catálogo do pacote tem erro"
[[ $(python3 -I "$P" catalogo | cut -f3 | sort -u | tr '\n' ' ') == "decisao pasta rotina " ]] || falhou "classes do catálogo"

# ---- Claude Code (textos do binário 2.1.x) ----
cat >"$D/claude-pasta" <<'FIM'
╭──────────────────────────────────────────────────────────────╮
│ Accessing workspace:                                         │
│                                                              │
│ /home/helio/Projetos/tt                                      │
│                                                              │
│ Quick safety check: is this a project you created or one you │
│ trust? Sessions started here can read, edit, and execute     │
│ files, and this folder's project settings (hooks, MCP        │
│ servers, permission rules, helper commands) apply to them.   │
│                                                              │
│ ❯ 1. Yes, I trust this folder                                │
│   2. No, exit                                                │
╰──────────────────────────────────────────────────────────────╯
   Enter to confirm · Esc to cancel
FIM
cat >"$D/claude-sem-permissoes" <<'FIM'
╭──────────────────────────────────────────────────────────────╮
│ WARNING: Claude Code running in Bypass Permissions mode      │
│                                                              │
│ In Bypass Permissions mode, Claude Code will not ask for     │
│ your approval before running potentially dangerous commands. │
│ This mode should only be used in a sandboxed container/VM    │
│ that has restricted internet access and can easily be        │
│ restored if damaged.                                         │
│                                                              │
│ By proceeding, you accept all responsibility for actions     │
│ taken while running in Bypass Permissions mode.              │
│                                                              │
│ ❯ No, exit                                                   │
│   Yes, I accept                                              │
╰──────────────────────────────────────────────────────────────╯
FIM
cat >"$D/claude-termos" <<'FIM'
 Updates to Consumer Terms and Policies

 An update to our Consumer Terms and Privacy Policy will take effect on October 8, 2025. You can accept the updated terms today.

 Please select how you'd like to continue
 ❯ 1. Accept terms · Help improve our AI models: ON
   2. Accept terms · Help improve our AI models: OFF
   3. Not now
FIM
cat >"$D/claude-tema" <<'FIM'
 Welcome to Claude Code v2.1.302

 Let's get started.

 Choose the text style that looks best with your terminal
 To change this later, run /theme

 ❯ 1. Dark mode ✔
   2. Light mode
   3. Dark mode (colorblind-friendly)
FIM
cat >"$D/claude-terminal" <<'FIM'
 Use Claude Code's terminal setup?

 For the optimal coding experience, enable the recommended settings for your terminal: Shift+Enter for newlines

 ❯ 1. Yes, use recommended settings
   2. No, maybe later with /terminal-setup
FIM
cat >"$D/claude-seguranca" <<'FIM'
 Security notes:

 1. Claude can make mistakes
    You're responsible for Claude's actions and should always review them, especially when running code.
 2. Due to prompt injection risks, only use it with code you trust

 Press Enter to continue…
FIM
cat >"$D/claude-login-ok" <<'FIM'
 Login successful. Press Enter to continue…
FIM
cat >"$D/claude-login" <<'FIM'
 Claude Code can be used with your Claude subscription or billed based on API usage through your Console account.

 Select login method:

 ❯ 1. Claude account with subscription · Pro, Max, Team, or Enterprise
   2. Anthropic Console account · API usage billing
   3. 3rd-party platform
FIM
cat >"$D/claude-api-key" <<'FIM'
 Detected a custom API key in your environment

 ANTHROPIC_API_KEY: sk-ant-...x9

 Do you want to use this API key?
 ❯ No (recommended)
   Yes
FIM
cat >"$D/claude-mcp" <<'FIM'
 New MCP server found in this project: github

 MCP servers may execute code or access system resources.

 ❯ 1. Use this MCP server
   2. Use this and all future MCP servers in this project
   3. Continue without using this MCP server
FIM
cat >"$D/claude-proceed" <<'FIM'
● Vou apagar a pasta de build.

╭──────────────────────────────────────────────────────────────╮
│ Bash command                                                 │
│   rm -rf build/                                              │
│ Do you want to proceed?                                      │
│ ❯ 1. Yes                                                     │
│   2. Yes, and don't ask again for rm commands in /home/x     │
│   3. No, and tell Claude what to do differently (esc)        │
╰──────────────────────────────────────────────────────────────╯
FIM
cat >"$D/claude-edicao" <<'FIM'
╭──────────────────────────────────────────────────────────────╮
│ Edit file                                                    │
│ src/app.py                                                   │
│ Do you want to make this edit to app.py?                     │
│ ❯ 1. Yes                                                     │
│   2. Yes, allow all edits during this session (shift+tab)    │
│   3. No, and tell Claude what to do differently (esc)        │
╰──────────────────────────────────────────────────────────────╯
FIM
cat >"$D/claude-limite" <<'FIM'
 You've reached your usage limit.
 ❯ 1. Wait here, then continue automatically when the limit resets
   2. Continue with usage credits
   3. Add funds to continue with usage credits
FIM
cat >"$D/claude-pasta-comandos" <<'FIM'
 Accessing workspace:

 /home/helio/Projetos/tt

 This folder runs commands to mint HTTP headers (headersHelper), declared in .claude/settings.json
 These will apply without asking. Only proceed if you trust this configuration.

 ❯ 1. Yes, I trust this folder
   2. No, continue without these permissions
FIM
espera claude-pasta perguntar pasta "opcao 1"
[[ $(campo 7) == /home/helio/Projetos/tt && $(campo 8) == "Quick safety check: is this a project you created or one you trust?" ]] ||
  falhou "pasta e pergunta da tela do Claude: $R"
espera claude-sem-permissoes auto rotina "opcao 2"      # sem número: a 2ª linha do menu de setas; a marcada é a 1ª
[[ $(campo 5) == 1 && $(campo 9) == "1=No, exit|2=Yes, I accept" ]] || falhou "menu sem números: $R"
espera claude-termos auto rotina "opcao 2"              # aceita sem ceder as conversas para treino
espera claude-tema auto rotina "opcao 1"
espera claude-terminal auto rotina "opcao 2"            # não mexe no terminal
espera claude-seguranca auto rotina "teclas Enter"      # a lista numerada sem cursor não é menu
espera claude-login-ok auto rotina "teclas Enter"
espera claude-login perguntar decisao; [[ $(campo 3) == credencial && $(campo 8) == "Select login method:" ]] || falhou "login: $R"
espera claude-api-key perguntar decisao; [[ $(campo 3) == credencial ]] || falhou "chave de API: $R"
espera claude-mcp perguntar decisao; [[ $(campo 3) == permissao-execucao ]] || falhou "MCP: $R"
espera claude-proceed perguntar decisao; [[ $(campo 3) == destrutivo ]] || falhou "rm -rf: $R"
espera claude-edicao perguntar decisao; [[ $(campo 3) == permissao-execucao ]] || falhou "edição: $R"
espera claude-limite perguntar decisao; [[ $(campo 3) == dinheiro ]] || falhou "limite de uso: $R"
printf '%s\n' '~/Projetos/**' >"$T/pastas"
espera claude-pasta-comandos perguntar decisao "" --pastas "$T/pastas"  # pasta da lista, mas com comandos próprios
passou 'telas: Claude (pasta, sem permissões, termos, tema, terminal, avisos, login feito) e as decisões (login, chave, MCP, rm, edição, créditos)'

# ---- Codex (0.162) e Kiro (2.31) ----
cat >"$D/codex-pasta" <<'FIM'
>_ OpenAI Codex (v0.162.1)

  Trust this folder?

  /home/helio/Projetos/tt

  Codex can read, edit, and run files here, subject to your permission settings. Folder settings can run code automatically, even without a model request. Continue only if you trust these files.

› 1. Trust and continue
  2. Open restricted
FIM
cat >"$D/codex-atualizacao" <<'FIM'
  ✨ Update available! 0.162.1 -> 0.163.0

  Release notes: https://github.com/openai/codex/releases/latest

› 1. Update now (runs `npm install -g @openai/codex`)
  2. Skip
  3. Skip until next version

  Press enter to continue
FIM
cat >"$D/codex-modelo" <<'FIM'
  Codex just got an upgrade. Introducing gpt-6-codex.

› 1. Try new model
  2. Use existing model
FIM
cat >"$D/codex-comando" <<'FIM'
• Running the migration

  Would you like to run the following command?

  $ psql -c 'drop table usuarios'

› 1. Yes, proceed
  2. Yes, and don't ask again for commands that start with `psql`
  3. No, and tell Codex what to do differently
FIM
cat >"$D/codex-login" <<'FIM'
  Welcome to Codex, OpenAI's command-line coding agent

  Sign in with ChatGPT to use Codex as part of your paid plan

› 1. Sign in with ChatGPT
  2. Provide your own API key
FIM
cat >"$D/kiro-ferramenta" <<'FIM'
> Vou rodar o build.

🛠️  Using tool: execute_bash
 ● I will run the following shell command: make build

Allow this action? Use 't' to trust (always allow) this tool for the session. [y/n/t]:
FIM
cat >"$D/kiro-pasta" <<'FIM'
 Kiro CLI

 Do you trust this folder? /home/helio/Projetos/tt
 ❯ 1. Yes, trust this folder
   2. Trust all folders under the parent
   3. No
FIM
cat >"$D/gemini-pasta" <<'FIM'
 Gemini CLI
 Do you trust this folder?
 ❯ 1. Trust folder (tt)
   2. Trust parent folder (Projetos)
   3. Don't trust (esc)
FIM
espera codex-pasta perguntar pasta "opcao 1"
espera codex-pasta auto pasta "opcao 1" --pastas "$T/pastas"
espera codex-atualizacao auto rotina "opcao 2"          # pula; nunca "pular até a próxima versão"
espera codex-modelo auto rotina "opcao 2"               # fica no modelo de sempre
espera codex-comando perguntar decisao; [[ $(campo 3) == destrutivo ]] || falhou "drop table: $R"
espera codex-login perguntar decisao; [[ $(campo 3) == credencial ]] || falhou "login do Codex: $R"
espera kiro-ferramenta perguntar decisao; [[ $(campo 6) == sn && $(campo 9) == "s=sim|n=não" ]] || falhou "[y/n/t] do Kiro: $R"
espera kiro-pasta auto pasta "opcao 1" --pastas "$T/pastas"   # nunca "confiar em todas sob a pasta-mãe"
espera gemini-pasta perguntar pasta "opcao 1"           # outro agente: o mesmo caminho
passou 'telas: Codex (pasta, atualização, modelo, comando, login), Kiro ([y/n/t], pasta) e Gemini'

# ---- trava do código: senha, opções perigosas, menu velho, lista do agente, nada na tela ----
printf '%s\n' 'helio@dell:~$ sudo apt install foo' '[sudo] password for helio: ' >"$D/sudo"
printf '%s\n' 'Enter passphrase for key /home/helio/.ssh/id_ed25519: ' >"$D/ssh"
printf '%s\n' '● Pronto. Fiz três coisas:' '  1. Corrigi o teste' '  2. Atualizei a doc' '' '> ' >"$D/lista"
{ cat "$D/codex-atualizacao"; for i in 1 2 3 4 5 6; do echo "● linha $i da resposta do agente"; done; } >"$D/menu-velho"
printf 'Qual cor você prefere?\n ❯ 1. Azul\n   2. Verde\n' >"$D/desconhecida"
: >"$D/vazia"
espera sudo perguntar senha; espera ssh perguntar senha
espera lista nada -; espera menu-velho nada -; espera vazia nada -
espera desconhecida perguntar desconhecida; [[ $(campo 8) == "Qual cor você prefere?" && $(campo 9) == "1=Azul|2=Verde" ]] || falhou "desconhecida: $R"
# um bloco de rotina do usuário que tentasse aprovar "não pergunte de novo" não consegue (e o desconhecido é perguntado)
cat >"$T/meu.conf" <<'FIM'
[aprova-tudo]
agente = *
classe = rotina
tela = qual cor
opcao = .

[aprova-sempre]
agente = *
classe = rotina
tela = escolha o modo
opcao = ^sempre
FIM
printf 'Escolha o modo?\n ❯ 1. Sempre usar este modo\n   2. Só agora\n' >"$D/sempre"
TT_TELAS_CATALOGO="$RAIZ/telas-agentes.conf:$T/meu.conf" espera sempre perguntar desconhecida
TT_TELAS_CATALOGO="$RAIZ/telas-agentes.conf:$T/meu.conf" espera desconhecida auto rotina "opcao 1"  # o usuário estendeu
# tecla Enter só onde a tela pede só Enter: num menu desconhecido com "press enter" no texto, pergunta
printf 'Press enter to continue with one of these\n ❯ 1. Azul\n   2. Verde\n' >"$D/enter-menu"
espera enter-menu perguntar desconhecida
passou 'telas: senha nunca, lista do agente e menu velho não são pergunta, opção "sempre" nunca sozinha, Enter só onde só cabe Enter'

# ---- o catálogo do usuário: trocar um bloco pelo mesmo id e desligar outro ----
mkdir -p "$XDG_CONFIG_HOME/tt"
printf '[claude-sem-permissoes]\nagente = claude\nclasse = decisao\ntela = bypass permissions mode\nmotivo = quero ouvir este aviso\n\n[claude-tema]\nclasse = -\n' >"$XDG_CONFIG_HOME/tt/telas-agentes.conf"
espera claude-sem-permissoes perguntar decisao; [[ $(campo 10) == "quero ouvir este aviso" ]] || falhou "bloco trocado pelo usuário: $R"
espera claude-tema perguntar desconhecida               # desligado: vira pergunta
printf '[quebrado]\nclasse = talvez\ntela = (\n' >"$XDG_CONFIG_HOME/tt/telas-agentes.conf"
python3 -I "$P" validar 2>"$T/erros" && falhou "validar aceitou um bloco quebrado"
grep -q "\[quebrado\]" "$T/erros" || falhou "validar não disse o bloco: $(cat "$T/erros")"
espera claude-tema auto rotina "opcao 1"                # o bloco quebrado fica de fora; o resto vale
rm -f "$XDG_CONFIG_HOME/tt/telas-agentes.conf"
passou 'telas: o catálogo do usuário troca um bloco (mesmo id), desliga outro (classe -) e um bloco quebrado não derruba os outros'

# ---- a lista de pastas: ~, MÁQUINA:, /** (subpastas), * e .. ----
pok() { python3 -I "$P" pasta-ok --pastas "$T/pl" --maquina "${2:-dell}" --casa /home/helio --casa /root "$1"; }
printf '%s\n' '# comentário' '~' >"$T/pl"
pok /home/helio && pok /root && pok '~' || falhou "~ autoriza a pasta pessoal (e a /root do proot)"
pok /home/helio/Projetos && falhou "~ sozinho não vale as subpastas"
printf '%s\n' 'empresa:~/Projetos/**' '/srv/app' '~/tmp/*' >"$T/pl"
pok /home/helio/Projetos empresa && pok /home/helio/Projetos/tt/x empresa || falhou "MÁQUINA:~/Projetos/** vale a pasta e as de baixo"
pok /home/helio/Projetos/tt dell && falhou "a entrada de outra máquina valeu aqui"
pok /home/helio/Projetos/../.ssh empresa && falhou ".. na pasta não pode sair da autorizada"
pok /srv/app && ! pok /srv/app/x || falhou "pasta absoluta exata"
pok /home/helio/tmp/a || falhou "* da lista"
pok /home/helio/Projetos2 empresa && falhou "~/Projetos/** não vale ~/Projetos2"
passou 'telas: a lista de pastas (~, MÁQUINA:, /** com as subpastas, * e .. barrado)'
