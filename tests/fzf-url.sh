#!/bin/bash
set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
vendor="$repo/vendor/rex-fzf-url"
tmp_root=/tmp/opencode
mkdir -p "$tmp_root"
tmp=$(mktemp -d "$tmp_root/rex-fzf-url.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT

punctuation='https://example.test/wiki/Page_(topic)?q[]=x+y&raw=$a!%2F,*;v@x#result(2)'
ipv6='HTTP://[::1]:8080/log?q=foo%2Fbar#tail'
apostrophe="https://example.test/O'Reilly#anchor"
bare='https://example.test/path?q=value#ends-with-period.'
actual=$(
  printf '%s\n' "See ($punctuation)." "<$ipv6>" "'$apostrophe'" "$punctuation" "$bare" |
    /usr/bin/perl "$vendor/bin/extract-urls.pl"
)
[[ "$actual" == "$punctuation"$'\n'"$ipv6"$'\n'"$apostrophe"$'\n'"$bare" ]]

export TEST_LOG="$tmp/opened"
export FZF_URL_FZF="$tmp/test fzf"
export FZF_URL_OPEN_CMD="$tmp/open-stub"
export FZF_URL_ROWS=24
export FZF_DEFAULT_OPTS='--select-1'
export FZF_DEFAULT_OPTS_FILE="$tmp/opts"
cat >"$FZF_URL_FZF" <<'EOF'
#!/bin/bash
[[ -z "$FZF_DEFAULT_OPTS" && -z "$FZF_DEFAULT_OPTS_FILE" ]] || exit 2
cat >/dev/null
[[ "$TEST_CANCEL" != yes ]] || exit 130
printf '\n%s\n' 'file:///etc/hosts' 'ftp://example.test' 'mailto:example@example.test' "$TEST_URL"
EOF
cat >"$FZF_URL_OPEN_CMD" <<'EOF'
#!/bin/bash
[[ "$#" == 1 ]] || exit 2
printf '%s\n' "$1" >>"$TEST_LOG"
EOF
chmod +x "$FZF_URL_FZF" "$FZF_URL_OPEN_CMD"

# Even when fzf returns shell metacharacters, the opener receives one literal argument.
export TEST_URL='https://example.test/$(touch${IFS}marker)?x=$HOME&y=a*b#tail'
export TEST_CANCEL=yes
printf '%s\n' "$TEST_URL" >"$tmp/urls"
(cd "$tmp" && PATH=/usr/bin:/bin /bin/bash "$vendor/bin/picker.sh" "$tmp/urls")
[[ ! -e "$TEST_LOG" && ! -e "$tmp/urls" ]]

export TEST_CANCEL=no
printf '%s\n' "$TEST_URL" >"$tmp/urls"
(cd "$tmp" && PATH=/usr/bin:/bin /bin/bash "$vendor/bin/picker.sh" "$tmp/urls")
[[ "$(<"$TEST_LOG")" == "$TEST_URL" ]]
[[ ! -e "$tmp/marker" && ! -e "$tmp/urls" ]]

echo "fzf URL checks passed"
