#!/bin/bash
# Hooks aliases.zsh into zsh by symlinking it into oh-my-zsh's custom folder.
# oh-my-zsh sources every *.zsh in $ZSH_CUSTOM, so no need to touch .zshrc

here=$(dirname "$(realpath "$0")")

# make sure zsh is actually set up with a custom folder (oh-my-zsh)
if ! grep -q 'oh-my-zsh.sh' ~/.zshrc 2>/dev/null; then
    echo "~/.zshrc doesn't load oh-my-zsh, so there's no custom folder to drop aliases in"
    exit 1
fi

custom=$(zsh -ic 'print -r -- $ZSH_CUSTOM' 2>/dev/null | tail -1)
if [ -z "$custom" ] || [ ! -d "$custom" ]; then
    echo "Couldn't find \$ZSH_CUSTOM (got '$custom')"
    exit 1
fi
echo "Custom folder: $custom"

link="$custom/bernardscripts.zsh"
if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "$link already exists and isn't a symlink, leaving it alone"
    exit 1
fi

ln -sfn "$here/aliases.zsh" "$link"
echo "Linked $link -> $here/aliases.zsh"
echo "Open a new terminal or run: source ~/.zshrc"
