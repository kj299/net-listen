#!/bin/sh
# Extract one release's section from CHANGELOG.md, for use as the body of the
# GitHub Release.
#
#   tools/release-notes.sh v0.2.0 [output-file]
#
# The release workflow runs this before building, so a tag whose section was
# never promoted out of [Unreleased] fails the release immediately rather than
# publishing binaries with empty notes — the same principle as gating the
# packaging step on the smoke test.
set -eu

tag=${1:?usage: release-notes.sh <tag> [output-file]}
out=${2:-RELEASE_NOTES.md}
changelog=CHANGELOG.md

if ! grep -q "^## \[$tag\]" "$changelog"; then
    echo "error: $changelog has no '## [$tag]' section." >&2
    echo "Promote the [Unreleased] section to [$tag] before pushing the tag." >&2
    exit 1
fi

# Everything between this section's heading and the next one. The heading
# itself is dropped: GitHub already titles the release with the tag, and
# '[$tag]' would render as a broken reference link, since the link definitions
# live at the foot of the changelog and are not carried across.
awk -v heading="## [$tag]" '
    !inside && substr($0, 1, length(heading)) == heading {
        # Accept the heading bare or followed by a date, not a longer tag.
        rest = substr($0, length(heading) + 1)
        if (rest == "" || substr(rest, 1, 1) == " ") { inside = 1; next }
    }
    # The next section ends this one — as does the block of link definitions
    # at the foot of the file, which follows the oldest section directly.
    inside && (substr($0, 1, 3) == "## " || $0 ~ /^\[[^]]+\]: /) { exit }
    inside {
        # Hold blank lines back so the section does not open or close on one.
        if ($0 ~ /^[ \t]*$/) { if (started) blanks++; next }
        for (; blanks > 0; blanks--) print ""
        started = 1
        print
    }
' "$changelog" > "$out"

if ! grep -q '[^[:space:]]' "$out"; then
    echo "error: the [$tag] section in $changelog is empty." >&2
    exit 1
fi

# Only available under Actions; a local run just omits the link.
if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    printf '\nFull changelog: https://github.com/%s/blob/%s/CHANGELOG.md\n' \
        "$GITHUB_REPOSITORY" "$tag" >> "$out"
fi

echo "wrote $out ($(wc -l < "$out") lines) for $tag"
