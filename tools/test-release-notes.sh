#!/bin/sh
# Self-test for tools/release-notes.sh.
#
# The release workflow only runs on tag pushes, so without this the extractor
# would first execute during an actual release — on a Windows runner, against
# whatever the changelog happens to look like that day. CI runs this on both
# platforms on every push instead.
set -eu

script=$(pwd)/tools/release-notes.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; failures=$((failures + 1)); }

tags=$(sed -n 's/^## \[\(v[^]]*\)\].*/\1/p' CHANGELOG.md)
if [ -z "$tags" ]; then
    echo "[FAIL] CHANGELOG.md has no version headings to extract"
    exit 1
fi

# Every released section has to produce a body worth publishing.
for tag in $tags; do
    out=$work/$tag.md
    if ! sh "$script" "$tag" "$out" >/dev/null 2>&1; then
        fail "$tag extracts"
    elif ! grep -q '[^[:space:]]' "$out"; then
        fail "$tag is non-empty"
    elif grep -q '^\[[^]]*\]: ' "$out"; then
        fail "$tag excludes the changelog's link definitions"
    elif grep -q "^## \[$tag\]" "$out"; then
        fail "$tag drops its own heading"
    elif [ -z "$(head -n 1 "$out")" ] || [ -z "$(tail -n 1 "$out")" ]; then
        fail "$tag neither opens nor closes on a blank line"
    else
        pass "$tag"
    fi
done

# A tag with no section of its own must fail the release rather than publish
# empty notes — this is the guard against tagging before promoting.
if sh "$script" v9999.0.0 "$work/missing.md" >/dev/null 2>&1; then
    fail "a missing section is rejected"
else
    pass "a missing section is rejected"
fi

# So must a heading that exists but says nothing under it.
mkdir -p "$work/empty"
printf '# Changelog\n\n## [v1.0.0]\n\n## [v0.9.0]\n\n- something\n' \
    > "$work/empty/CHANGELOG.md"
if (cd "$work/empty" && sh "$script" v1.0.0 out.md) >/dev/null 2>&1; then
    fail "an empty section is rejected"
else
    pass "an empty section is rejected"
fi

echo
if [ "$failures" -eq 0 ]; then
    echo "release-notes.sh: all checks passed"
else
    echo "release-notes.sh: $failures check(s) failed"
    exit 1
fi
