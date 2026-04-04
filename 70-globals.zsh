# Global aliases — work anywhere in the command line.
# Usage examples:
#   git log G "fix" L        → git log | grep "fix" | less
#   some-command NE           → some-command 2>/dev/null
#   ps aux W                  → ps aux | wc -l
alias -g G='| grep'
alias -g L='| less'
alias -g W='| wc -l'
alias -g H='| head'
alias -g T='| tail'
alias -g NE='2>/dev/null'
alias -g NUL='>/dev/null 2>&1'
