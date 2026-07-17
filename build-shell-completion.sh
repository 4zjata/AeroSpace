#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

./script/install-dep.sh --complgen

rm -rf .shell-completion && mkdir -p \
    .shell-completion/zsh \
    .shell-completion/fish \
    .shell-completion/bash

./.deps/cargo-root/bin/complgen aot ./grammar/commands-bnf-grammar.txt \
    --zsh-script .shell-completion/zsh/_aerospace \
    --fish-script .shell-completion/fish/aerospace.fish \
    --bash-script .shell-completion/bash/aerospace

# Check basic syntax
zsh -c 'autoload -Uz compinit; compinit; source ./.shell-completion/zsh/_aerospace'
if command -v fish &>/dev/null; then
    fish -c 'source ./.shell-completion/fish/aerospace.fish'
fi
if bash -c 'declare -A test_arr; [[ -v test_arr[key] ]]' &>/dev/null; then
    bash -c 'source ./.shell-completion/bash/aerospace'
else
    echo "Skipping bash syntax check because system bash is too old"
fi
