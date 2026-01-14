function gpb() {
  git push origin $(current_branch) --force-with-lease -u
}

function connect() {
  echo "Current context: $(kubectl config current-context)"
  pod=$(kubectl get pods --no-headers -o custom-columns=":metadata.name,:status.phase" | rg $1 | rg Running | head -n 1 | awk '{print $1}')
  if [ -z "$pod" ]
  then
    echo "No running $1 pods found."
  else
    echo "Connecting to $pod..."
    kubectl exec -it $pod -- /bin/bash
  fi
}

if [[ -z "${CLAUDECODE}" ]]; then
  eval "$(zoxide init --cmd cd zsh)"
fi

# alias claude="~/.claude/local/claude"
# ~/.local/bin/claude
export PATH="$HOME/.claude/local:$PATH"
export PATH="/Users/random/.bun/bin:$PATH"
export PATH="/Users/random/.cargo/bin:$PATH"

export PATH=$PATH:/Users/random/Projects/npupko/utility/target/release
eval "$(ruby ~/.local/try.rb init ~/Projects/tries)"

eval "$(codex completion zsh)"
