# Run with the environment of the pane's login shell.
roots=$(manpath -q) || exit $?
typeset -A pages
for root in ${(s/:/)roots}; do
  for file in "$root"/man*/*(N-.); do
    page=${file:t}
    [[ $page == *.(gz|bz2|xz|lzma|zst|Z) ]] && page=${page:r}
    [[ $page == *.* ]] || continue
    name=${page:r}
    section=${page:e}
    [[ -n $name && $name != *[[:cntrl:]]* && -n $section && $section != *[^[:alnum:]]* ]] || continue
    label="$name($section)"
    pages[$label]=$section
  done
done
if (( ${#pages} == 0 )); then
  print -ru2 -- 'No manual pages found.'
  exit 1
fi

# User fzf defaults can change the input/output format or run other actions.
selection=$(print -rl -- "${(@ok)pages}" |
  FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= "${1:-fzf}" --prompt='Manual> ')
case $? in
  0) ;;
  1|130) exit 0 ;;
  *) exit $? ;;
esac
if [[ -z $selection || -z ${pages[$selection]} ]]; then
  print -ru2 -- 'No valid manual page selected.'
  exit 1
fi
section=${pages[$selection]}
# Use an explicit section for suffixes man may not recognize as positional sections.
exec man -S "$section" -- "${selection%"($section)"}"
