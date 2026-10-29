#!/bin/bash
# Releases Ogle: builds the app signed with the Developer ID, notarizes it, tags the version,
# pushes main and the tag, and publishes a GitHub release with Ogle.zip.
#
#   scripts/sign-and-release.sh            prints the latest release and the usage
#   scripts/sign-and-release.sh 0.3.2      releases v0.3.2 from main
#
# Needs the Developer ID Application certificate in the keychain, notary credentials saved
# as "ogle-notary" (xcrun notarytool store-credentials ogle-notary), and gh logged in.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "release: $*" >&2; exit 1; }

latest() { git tag --list 'v*' --sort=-v:refname | head -n 1; }

if [[ $# -eq 0 ]]; then
  git fetch --quiet --tags origin 2>/dev/null || true
  current=$(latest)
  echo "Latest release: ${current:-none}"
  if [[ -n "$current" ]]; then
    IFS=. read -r major minor patch <<<"${current#v}"
    echo "Next patch:     $major.$minor.$((patch + 1))"
  fi
  echo "Usage: scripts/sign-and-release.sh <version>, e.g. scripts/sign-and-release.sh ${current:+$major.$minor.$((patch + 1))}"
  exit 0
fi

version=${1#v}
tag="v$version"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "'$1' is not a version like 1.2.3"

# Preflight: everything that can be checked before the slow build.
[[ "$(git branch --show-current)" == main ]] || fail "not on main (on '$(git branch --show-current)')"
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || fail "uncommitted changes; commit or stash them first"
command -v gh > /dev/null || fail "the GitHub CLI is missing: brew install gh"
gh auth status > /dev/null 2>&1 || fail "gh is not logged in: gh auth login"
security find-identity -v -p codesigning | grep -q "Developer ID Application" \
  || fail "no Developer ID Application certificate in the keychain"

echo "Fetching origin…"
git fetch --quiet --tags origin
if ! git merge-base --is-ancestor origin/main main; then
  fail "main has diverged from origin/main; pull first"
fi
git rev-parse -q --verify "refs/tags/$tag" > /dev/null && fail "$tag already exists"
gh release view "$tag" > /dev/null 2>&1 && fail "a GitHub release $tag already exists"
previous=$(latest)
if [[ -n "$previous" ]] && [[ "$(printf '%s\n' "${previous#v}" "$version" | sort -V | tail -n 1)" != "$version" ]]; then
  fail "$tag is not newer than $previous"
fi

echo "Releasing $tag from $(git log -1 --format='%h %s')"
VERSION="$version" SIGN_IDENTITY="Developer ID Application" ./build.sh
scripts/notarize.sh

echo
echo "Built and notarized build/Ogle.app ($tag). Commits since ${previous:-the start}:"
git log --oneline ${previous:+"$previous"..}main | cat
echo
read -r -p "Tag, push and publish $tag? [y/N] " answer
[[ "$answer" == [yY]* ]] || { echo "Stopped before tagging; nothing was pushed."; exit 1; }

git tag -a "$tag" -m "Ogle $tag"
git push origin main "$tag"
gh release create "$tag" build/Ogle.zip --title "Ogle $tag" --generate-notes --verify-tag
echo "Released $tag: $(gh release view "$tag" --json url --jq .url)"
