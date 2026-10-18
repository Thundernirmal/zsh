emulate -L zsh
repo=$1 mode=$2 legacy=$3 matrix=${4:-full}
export LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM=xterm-256color
unset NO_COLOR COLORTERM
source "$repo/25-theme.zsh"
source "$repo/55-ui-helpers.zsh"
source "$repo/60-functions.zsh"
_zsh_functions_load upkg || exit 2
[[ $mode == frozen ]] && { source "$legacy" || exit 3; }
typeset -g _UPKG_THEME_MODE=1
local -a rows
rows=(
  $'pacman\tripgrep\t14.1.0-1\tA search tool that combines the usability of ag with the raw speed of grep'
  $'apt\tvery-long-package-name-that-exceeds-every-column-width-0123456789\t1:2.3.4+dfsg-5ubuntu0.1~22.04.1\tshort'
  $'nix\tlegacyPackages.x86_64-linux.python3Packages.something\t\t'
  $'brew\t日本語パッケージ名前テスト\t版本一二三四五六七八九十\t説明文は全角文字で書かれていて非常に長いので切り詰められるべきです'
  $'flatpak\tcafé-combininǵ́\t1.0́\tCombining marks é at cut points éééééééééé'
  $'npm\temoji-😀-pkg-😀😀😀😀😀😀😀\t👍1.0\t🚀 rocket 🚀 description with emoji 🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀'
  $'paru\tctrl\e[31mred\x01\x7f\t1.0\x01\tdesc with \e]0;title\a controls and \r\n newlines \t tabs   '
  $'superlongmanagername\tname-with-trailing-newline\n\n\t2.0\n\t  padded description  '
  $'apt\tx\t\t   '
  $'apt\t\t\t'
  $'pacman\tа-cyrillic-имя-пакета-длинное-очень\tверсия-1.2.3\tОписание на русском языке, достаточно длинное для усечения в узкой колонке'
  $'nix\tinvalid-\xff\xfe-bytes\t1.\xe9\t\xe9\x9b trailing incomplete'
)
local -a widths themes depths glyphs
if [[ $matrix == full ]]; then
  widths=(59 60 80 100 120 130); themes=( "${_ZSH_UI_THEME_NAMES[@]}" ); depths=(ansi 256 truecolor none); glyphs=(nerd unicode ascii)
else
  widths=(59 60 80 100 130); themes=(catppuccin-mocha terminal); depths=(ansi 256 truecolor none); glyphs=(nerd unicode ascii)
fi
render() {
  local label=$1
  REPLY=reply-sentinel; reply=(array-sentinel)
  print -r -- "=== $label"
  _upkg_format_search_rows "${rows[@]}"
  print -r -- "--- rc=$? REPLY=${(q+)REPLY} reply=${(q+)${(j:|:)reply}}"
}
local w t d g
for w in $widths; do for t in $themes; do for d in $depths; do for g in $glyphs; do
  unset NO_COLOR COLORTERM; TERM=xterm
  case $d in 256) TERM=xterm-256color ;; truecolor) COLORTERM=truecolor ;; none) export NO_COLOR=1 ;; esac
  ZSH_UI_THEME=$t ZSH_UI_GLYPHS=$g
  _zsh_theme_resolve_settings
  COLUMNS=$w
  render "w=$w theme=$t depth=$d glyphs=$g tier=$_ZSH_UI_GLYPH_TIER cdepth=$_ZSH_UI_COLOR_DEPTH"
done; done; done; done
unset NO_COLOR COLORTERM
ZSH_UI_THEME=catppuccin-mocha ZSH_UI_GLYPHS=nerd TERM=dumb; _zsh_theme_resolve_settings; COLUMNS=120; render dumb
TERM=xterm-256color LC_ALL=C LANG=C; _zsh_theme_resolve_settings; render c-locale
LC_ALL=C.UTF-8 LANG=C.UTF-8; _zsh_theme_resolve_settings
render restored
print -r -- "=== width-data-loaded=${_ZSH_UI_WIDTH_DATA_LOADED:-0}" >/dev/null
