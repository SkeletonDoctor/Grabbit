#!/bin/zsh
# Publishes the version in ./VERSION as a GitHub release. Installed copies of Grabbit pick it up
# automatically (see Sources/Grabbit/Updater.swift).
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
ASSETS=(build/Grabbit.zip build/Grabbit.zip.sig build/YTDown.zip build/YTDown.zip.sig)
rm -rf "${ASSETS[@]}" build/legacy
ditto -c -k --keepParent build/Grabbit.app build/Grabbit.zip
swift Scripts/sign_update.swift sign build/Grabbit.zip > build/Grabbit.zip.sig

# Copies from before the rename (YTDown 1.1.x) look for YTDown.zip containing YTDown.app.
# Shipping the same app under that name lets them update; it renames itself on first launch.
mkdir -p build/legacy
ditto build/Grabbit.app build/legacy/YTDown.app
ditto -c -k --keepParent build/legacy/YTDown.app build/YTDown.zip
swift Scripts/sign_update.swift sign build/YTDown.zip > build/YTDown.zip.sig
rm -rf build/legacy

echo "→ Publishing $TAG…"
git push
if [[ $# -gt 0 ]]; then
  gh release create "$TAG" "${ASSETS[@]}" --title "Grabbit $VERSION" --notes "$1"
else
  gh release create "$TAG" "${ASSETS[@]}" --title "Grabbit $VERSION" --generate-notes
fi
echo "✓ Released $TAG"
