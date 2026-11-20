set -e

picker=${0:A:h:h}/man-picker.zsh
base=${TMPDIR:-/tmp}/opencode
mkdir -p "$base"
fixture=$(mktemp -d "$base/rex-man-picker.XXXXXXXX")
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/man root/man1" "$fixture/man root/man3" "$fixture/other/man1" "$fixture/other/mann"
touch -- "$fixture/man root/man1/demo.1.gz" "$fixture/man root/man3/demo.3" \
  "$fixture/other/man1/demo.1.xz" "$fixture/other/man1/-sample name.1.bz2" \
  "$fixture/other/mann/Tcl.ntcl" "$fixture/other/man1/README"
ln -s demo.1.gz "$fixture/man root/man1/alias.1.gz"
export PATH="$fixture/bin:$PATH"
export MANPATH="$fixture/man root:$fixture/missing:$fixture/other"
export FZF_DEFAULT_OPTS=--print-query FZF_DEFAULT_OPTS_FILE="$fixture/options"
export CATALOG="$fixture/catalog"

cat > "$fixture/bin/manpath" <<'SH'
#!/bin/sh
[ "$#" -eq 1 ] && [ "$1" = -q ] || exit 2
printf '%s\n' "$MANPATH"
SH
cat > "$fixture/fake fzf" <<'SH'
#!/bin/sh
[ -z "$FZF_DEFAULT_OPTS" ] && [ -z "$FZF_DEFAULT_OPTS_FILE" ] || exit 2
cat > "$CATALOG"
[ -z "$FZF_STATUS" ] || exit "$FZF_STATUS"
[ -n "$SELECTION" ] || exit 130
printf '%s\n' "$SELECTION"
SH
cat > "$fixture/bin/man" <<'SH'
#!/bin/sh
printf '<%s>\n' "$@"
SH
chmod +x "$fixture/bin/manpath" "$fixture/fake fzf" "$fixture/bin/man"

run_picker() {
  SELECTION="$1" zsh -f "$picker" "$fixture/fake fzf"
}

[[ $(run_picker 'demo(3)') == $'<-S>\n<3>\n<-->\n<demo>' ]]
diff - "$CATALOG" <<'CATALOG'
-sample name(1)
Tcl(ntcl)
alias(1)
demo(1)
demo(3)
CATALOG
[[ $(run_picker '-sample name(1)') == $'<-S>\n<1>\n<-->\n<-sample name>' ]]
[[ $(run_picker 'Tcl(ntcl)') == $'<-S>\n<ntcl>\n<-->\n<Tcl>' ]]
result=$(run_picker '')
[[ -z $result ]]
result=$(FZF_STATUS=1 run_picker '')
[[ -z $result ]]
if FZF_STATUS=2 run_picker '' > "$fixture/unexpected"; then
  print -ru2 -- 'Ignored a picker failure.'
  exit 1
else
  [[ $? == 2 && ! -s "$fixture/unexpected" ]]
fi
if run_picker 'not a catalog entry' > "$fixture/unexpected" 2>/dev/null; then
  print -ru2 -- 'Accepted a selection outside the catalog.'
  exit 1
fi
[[ ! -s "$fixture/unexpected" ]]
print 'Manual picker: catalog, selection and cancellation passed.'
