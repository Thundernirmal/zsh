# Global aliases — work anywhere in the command line, but only when enabled.
# They are opt-in because unquoted tokens such as H or G expand anywhere and
# can turn an ordinary argument into shell syntax (for example, `echo H`
# behaves as `echo | head`). To keep a shared configuration predictable,
# these aliases stay undefined unless requested before startup:
#   export ZSH_GLOBAL_ALIASES=1   # in ~/.zshrc, before sourcing init.zsh
# Quote a token to keep it literal: `echo 'H'` prints H.
# Usage examples (once enabled):
#   git log G "fix" L        → git log | grep "fix" | less
#   some-command NE           → some-command 2>/dev/null
#   ps aux W                  → ps aux | wc -l
if [[ ${ZSH_GLOBAL_ALIASES:-0} == 1 ]]; then
  alias -g G='| grep'
  alias -g L='| less'
  alias -g W='| wc -l'
  alias -g H='| head'
  alias -g T='| tail'
  alias -g NE='2>/dev/null'
  alias -g NUL='>/dev/null 2>&1'
fi
