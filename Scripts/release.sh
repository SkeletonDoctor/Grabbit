#!/bin/zsh
# Publishes the version in ./VERSION as a GitHub release. Installed copies of YTDown pick it up
# automatically (see Sources/YTDown/Updater.swift).
#
#   1. Bump VERSION, commit and push.
#   2. ./Scripts/release.sh ["Release notes"]
#
# Needs the GitHub CLI (gh) and the update signing key (swift Scripts/sign_update.swift keygen).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "✗ Commit your changes first, so the release matches the repository." >&2; exit 1
fi
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "✗ $TAG is already released. Bump VERSION first." >&2; exit 1
fi

./Scripts/build_app.sh

echo "→ Packaging…"
rm -f build/YTDown.zip build/YTDown.zip.sig
ditto -c -k --keepParent build/YTDown.app build/YTDown.zip
swift Scripts/sign_update.swift sign build/YTDown.zip > build/YTDown.zip.sig

echo "→ Publishing $TAG…"
git push
if [[ $# -gt 0 ]]; then
  gh release create "$TAG" build/YTDown.zip build/YTDown.zip.sig --title "YTDown $VERSION" --notes "$1"
else
  gh release create "$TAG" build/YTDown.zip build/YTDown.zip.sig --title "YTDown $VERSION" --generate-notes
fi
echo "✓ Released $TAG"
