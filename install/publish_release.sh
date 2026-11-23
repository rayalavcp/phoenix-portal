#!/usr/bin/env bash
# Publishes a built APK as a GitHub Release without leaving it in git
# history (APKs in history made the repository gigabytes big).
#
#   install/publish_release.sh <apk>
#
# Run it after the branch is committed with install/releases.json for the
# new version (install/make_releases.py). It pushes the branch plus one
# temporary commit on top that adds install/upload/phoenix-portal.apk. The
# "Phoenix release" workflow (.github/workflows/phoenix-release.yml) then
# makes release v<version> with the APK attached, moves the branch back off
# the temporary commit and keeps only the newest three releases. The local
# branch never holds the APK commit.
set -euo pipefail
apk="${1:?path to the APK}"
cd "$(git rev-parse --show-toplevel)"
[ -f "$apk" ] || { echo "no such APK: $apk" >&2; exit 1; }
branch="$(git rev-parse --abbrev-ref HEAD)"
head="$(git rev-parse HEAD)"
version="$(python3 -c 'import json;print(json.load(open("install/releases.json"))[0]["tag_name"])')"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export GIT_INDEX_FILE="$tmp/index"
git read-tree "$head"
blob="$(git hash-object -w "$apk")"
git update-index --add --cacheinfo 100644,"$blob",install/upload/phoenix-portal.apk
tree="$(git write-tree)"
unset GIT_INDEX_FILE
commit="$(git commit-tree "$tree" -p "$head" -m "APK upload for $version (taken off again by the release workflow)")"
# The remote branch must be this branch's own history (the workflow moves
# it back off each upload commit); anything else is someone else's work.
git fetch -q origin "$branch"
remote="$(git rev-parse "origin/$branch")"
if ! git merge-base --is-ancestor "$remote" "$head"; then
  echo "origin/$branch has commits this branch lacks: merge them first." >&2
  exit 1
fi
git push --force-with-lease="refs/heads/$branch:$remote" origin "$commit:refs/heads/$branch"
echo "Pushed the APK for $version; the Phoenix release workflow publishes it."
echo "Releases: https://github.com/rayalavcp/phoenix-portal/releases"
