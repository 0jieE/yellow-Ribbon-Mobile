#!/usr/bin/env bash
# Sets the same version in all three apps and moves every build number past
# the highest one in use, so each app's update check sees a newer build.
#
#   scripts/bump-version.sh 1.0.2
#
# Then commit, tag and push (see .github/workflows/release.yml).
set -euo pipefail

version="${1:-}"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 X.Y.Z" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
apps=(customer_app rider_app admin_app)

highest=0
for app in "${apps[@]}"; do
  code=$(grep -E '^version:' "$root/$app/pubspec.yaml" | head -1 | sed -E 's/.*\+([0-9]+).*/\1/' | tr -d '\r')
  [[ "$code" =~ ^[0-9]+$ ]] || code=0
  (( code > highest )) && highest=$code
done
next=$((highest + 1))

for app in "${apps[@]}"; do
  # Only the version text is replaced, so CRLF line endings survive.
  sed -b -i -E "s/^version: [0-9A-Za-z.+-]+/version: $version+$next/" "$root/$app/pubspec.yaml"
  echo "$app: $(grep -E '^version:' "$root/$app/pubspec.yaml")"
done

echo
echo "Next: git commit -am \"Release $version\" && git tag -a v$version -m \"What changed\" && git push origin main v$version"
