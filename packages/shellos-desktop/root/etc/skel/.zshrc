# ShellOS zsh defaults. Yours to edit.

HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt share_history hist_ignore_all_dups hist_ignore_space
setopt auto_cd extended_glob interactive_comments no_beep

autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

bindkey -e
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word

alias ls='ls --color=auto --group-directories-first'
alias ll='ls -lh'
alias la='ls -lAh'
alias grep='grep --color=auto'
alias ip='ip -color=auto'

[[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] &&
	source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
command -v starship >/dev/null && eval "$(starship init zsh)"
# Must be sourced last.
[[ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] &&
	source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
