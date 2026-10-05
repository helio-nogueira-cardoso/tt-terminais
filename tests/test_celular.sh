#!/usr/bin/env bash
# Instalador do celular (termux/celular.sh) em simulação: percorre todos os passos sem tocar em nada,
# nunca sobrescreve config do usuário e a verificação roda sem Termux.
source "$(dirname "$0")/lib.sh"; isolar
C=$RAIZ/termux/celular.sh
for f in "$C" "$RAIZ/termux/atalhos.sh"; do bash -n "$f" || falhou "sintaxe: $f"; done
for f in "$RAIZ/termux/boot-tt" "$RAIZ/termux/android-ajustes.sh"; do sh -n "$f" || falhou "sintaxe: $f"; done

printf 'nome=meu\nclaude_flags=--minhas\n' >"$XDG_CONFIG_HOME/tt/config"
cp "$XDG_CONFIG_HOME/tt/config" "$T/antes"
saida=$(CELULAR_SIMULAR=1 PREFIX=/data/data/com.termux/files/usr bash "$C" instalar --nome cel 2>&1) ||
  falhou "simulação falhou: $saida"
for passo in 'Pacotes do Termux' 'Barra de teclas' 'SSH' 'Termux:Boot' 'tt (central' 'Debian' 'Falta fazer'; do
  grep -q "$passo" <<<"$saida" || falhou "passo ausente na simulação: $passo"
done
grep -q 'instalar.sh cel' <<<"$saida" || falhou 'nome não chegou ao instalar.sh'
grep -q 'claude_env=IS_SANDBOX=1' <<<"$saida" || falhou 'claude_env padrão não proposto'
grep -q 'claude_flags=' <<<"$saida" && falhou 'proporia sobrescrever claude_flags do usuário'
cmp -s "$T/antes" "$XDG_CONFIG_HOME/tt/config" || falhou 'simulação alterou o config'
[[ -e $HOME/.termux || -e $HOME/.bashrc ]] && falhou 'simulação criou arquivos na home'
passou 'celular: simulação percorre os passos sem alterar nada e respeita o config'

saida=$(bash "$C" verificar 2>&1) || falhou "verificar falhou: $saida"
grep -q 'não é Termux' <<<"$saida" && grep -q 'perfil nunca aplicado' <<<"$saida" || falhou "verificar: $saida"
bash "$C" xyz >/dev/null 2>&1 && falhou 'aceitou comando desconhecido'
passou 'celular: verificar só lê e comando inválido é recusado'
