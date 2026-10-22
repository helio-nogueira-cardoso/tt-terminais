# Carregar depois de lib.sh/isolar. Nos painéis sem bind load próprio, confirma a
# recarga antes da próxima tecla: estado gravado não significa lista já pronta.
printf -v FZF_UI_ENV 'env FZF_DEFAULT_OPTS=%q' "--bind='load:execute-silent(touch $T/fzf-recarregou)'"
fzf_recarregar() {
  local i
  rm -f "$T/fzf-recarregou"
  tmux send-keys -t ui "$@"
  for ((i=0; i<120; i++)); do
    [[ -e $T/fzf-recarregou ]] && return 0
    sleep 0.25
  done
  falhou "fzf não confirmou a recarga: $(tmux capture-pane -p -t ui)"
}
