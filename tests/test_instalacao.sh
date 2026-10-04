#!/usr/bin/env bash
# Instalação: nunca rebaixa, nunca aceita pacote incompleto ou quebrado, nunca troca um repositório.
source "$(dirname "$0")/lib.sh"; isolar
inst=$T/inst; export TT_DIR=$inst
pac() { rm -rf "$T/p"; cp -r "$T/pkg" "$T/p"; echo "$1" >"$T/p/VERSAO"; }
instala() { "$T/p/tt" --instalar-aqui >/dev/null 2>&1; }
ver() { cut -d' ' -f1-2 "$inst/VERSAO" 2>/dev/null; }

pac "50 aaaaaaa 2026-10-01"; instala; [[ $(ver) == "50 aaaaaaa" ]] || falhou "instalação do zero: $(ver)"
pac "40 bbbbbbb 2026-09-01"; instala && falhou 'aceitou versão mais velha'; [[ $(ver) == "50 aaaaaaa" ]] || falhou 'rebaixou'
pac "50 ccccccc 2026-10-01"; instala && falhou 'aceitou mesmo número de outro commit'
pac "60 ddddddd 2026-10-02"; rm "$T/p/tema-agentes.sh"; instala && falhou 'aceitou pacote incompleto'
pac "60 ddddddd 2026-10-02"; echo 'if then' >>"$T/p/tema-terminal.sh"; instala && falhou 'aceitou script com erro de sintaxe'
[[ $(ver) == "50 aaaaaaa" ]] || falhou "algum pacote ruim foi instalado: $(ver)"
pac "60 ddddddd 2026-10-02"; instala; [[ $(ver) == "60 ddddddd" ]] || falhou 'não instalou a mais nova'
pac "30 eeeeeee 2026-08-01"; TT_FORCAR=1 "$T/p/tt" --instalar-aqui >/dev/null 2>&1; [[ $(ver) == "30 eeeeeee" ]] || falhou 'TT_FORCAR não voltou de versão'
passou 'instalação: não rebaixa, recusa pacote incompleto/quebrado, TT_FORCAR força'

mkdir -p "$T/clone/.git"; echo marca >"$T/clone/do-clone"
pac "99 fffffff 2026-12-01"; TT_DIR=$T/clone "$T/p/tt" --instalar-aqui >/dev/null 2>&1 || true
[[ -d $T/clone/.git && -f $T/clone/do-clone ]] || falhou 'a instalação substituiu um repositório git'
passou 'instalação recusa substituir um repositório git'
