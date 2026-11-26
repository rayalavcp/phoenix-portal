#!/usr/bin/env bash
# Publishes docs/wiki/*.md to the repository's GitHub wiki.
# Run from the repository root on a machine with push access.
set -euo pipefail
src="$(git rev-parse --show-toplevel)/docs/wiki"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone -q https://github.com/rayalavcp/phoenix-portal.wiki.git "$tmp/wiki"
for f in "$src"/*.md; do
  name="$(basename "$f")"
  [ "$name" = "README.md" ] && continue
  # Wiki links are page names without ".md".
  sed -E 's/\]\(([A-Za-z0-9_-]+)\.md(#[^)]*)?\)/](\1\2)/g' "$f" > "$tmp/wiki/$name"
done
cd "$tmp/wiki"
git add -A
if git diff --cached --quiet; then echo "Wiki already up to date."; exit 0; fi
git commit -qm "Update the wiki from docs/wiki"
git push -q
echo "Wiki updated: https://github.com/rayalavcp/phoenix-portal/wiki"
